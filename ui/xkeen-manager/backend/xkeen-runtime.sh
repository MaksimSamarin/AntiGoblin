#!/bin/sh

# Shared AntiGoblin runtime builder.
# This file is sourced by CGI apply and self-heal so both paths rebuild the
# exact same iptables/ipset runtime.

PATH="/opt/bin:/opt/sbin:/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

: "${STATE_PATH:=/opt/share/xkeen-manager/xkeen-ui-state.json}"
: "${RUNTIME_DIR:=/opt/share/xkeen-manager/runtime}"
: "${XKEEN_BYPASS_SET:=xkeen_bypass}"
: "${XKEEN_UDP_ROUTE_SET:=xkeen_udp_route}"
: "${XKEEN_UDP_MARK:=0x111}"
: "${XKEEN_UDP_TABLE:=111}"
: "${XKEEN_TPROXY_PORT:=61221}"
: "${XKEEN_REDIRECT_PORT:=61219}"

XKEEN_MARK="${XKEEN_MARK:-}"

xkeen_runtime_log() {
  [ -n "${XKEEN_RUNTIME_LOG:-}" ] || return 0
  printf '%s runtime %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$XKEEN_RUNTIME_LOG"
}

xkeen_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

xkeen_has_rule() {
  "$@" >/dev/null 2>&1
}

xkeen_delete_jumps() {
  TABLE_NAME="$1"
  BASE_CHAIN="$2"
  TARGET_CHAIN="$3"
  iptables -t "$TABLE_NAME" -S "$BASE_CHAIN" 2>/dev/null | grep -E " -j ${TARGET_CHAIN}($| )" | while IFS= read -r rule; do
    delete_rule="$(printf '%s\n' "$rule" | sed 's/^-A /-D /')"
    set -- $delete_rule
    iptables -t "$TABLE_NAME" "$@" 2>/dev/null || true
  done
}

xkeen_get_mark() {
  ndmc -c 'show ip policy' 2>/dev/null | /opt/bin/awk '
    /description = xkeen:/ {
      want_mark=1
      next
    }
    want_mark && /mark:/ {
      print $2
      exit
    }
  '
}

xkeen_default_wan_iface() {
  ndmc -c 'show interface' 2>/dev/null | /opt/bin/awk '
    /^Interface, name = / {
      iface=$4
      gsub(/"/, "", iface)
      next
    }
    /defaultgw:[[:space:]]+yes/ {
      print iface
      exit
    }
  '
}

xkeen_next_policy_name() {
  ndmc -c 'show running-config' 2>/dev/null | /opt/bin/awk '
    /^ip policy Policy[0-9]+$/ {
      name=$3
      sub(/^Policy/, "", name)
      if (name >= 42) print name
    }
  ' | sort -n | /opt/bin/awk '
    BEGIN { n = 42 }
    { if ($1 == n) n++ }
    END { print "Policy" n }
  '
}

xkeen_ensure_policy() {
  if ndmc -c 'show ip policy' 2>/dev/null | grep -q 'description = xkeen:'; then
    return 0
  fi

  WAN_IFACE="$(xkeen_default_wan_iface)"
  [ -n "$WAN_IFACE" ] || return 1

  POLICY_NAME="$(xkeen_next_policy_name)"
  [ -n "$POLICY_NAME" ] || POLICY_NAME="Policy42"

  xkeen_runtime_log "policy_missing create=$POLICY_NAME wan=$WAN_IFACE"
  ndmc -c "ip policy $POLICY_NAME" >/dev/null 2>&1 || return 1
  ndmc -c "ip policy $POLICY_NAME description xkeen" >/dev/null 2>&1 || return 1
  ndmc -c "ip policy $POLICY_NAME permit global $WAN_IFACE" >/dev/null 2>&1 || return 1
  ndmc -c "system configuration save" >/dev/null 2>&1 || true
  sleep 1
  ndmc -c 'show ip policy' 2>/dev/null | grep -q 'description = xkeen:'
}

xkeen_ensure_mark() {
  xkeen_ensure_policy || return 1
  XKEEN_MARK="$(xkeen_get_mark)"
  [ -n "$XKEEN_MARK" ]
}

xkeen_resolve_ipv4() {
  nslookup "$1" 2>/dev/null | /opt/bin/awk '
    /^Name:/ { seen_name=1; next }
    seen_name && /^Address [0-9]+: / { print $3; next }
    seen_name && /^Address: / { print $2; next }
  ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -Ev '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'
}

xkeen_ipset_has_members() {
  ipset list "$1" 2>/dev/null | /opt/bin/awk '
    /^Members:/ { seen=1; next }
    seen && NF { found=1 }
    END { exit found ? 0 : 1 }
  '
}

xkeen_add_domains_to_set() {
  SET_NAME="$1"
  while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    xkeen_resolve_ipv4 "$domain" | while IFS= read -r ip; do
      [ -n "$ip" ] || continue
      ipset add "$SET_NAME" "$ip"/32 -exist 2>/dev/null || true
    done
  done
}

xkeen_add_cidrs_to_set() {
  SET_NAME="$1"
  while IFS= read -r cidr; do
    [ -n "$cidr" ] || continue
    ipset add "$SET_NAME" "$cidr" -exist 2>/dev/null || true
  done
}

xkeen_swap_set() {
  TARGET="$1"
  TMP="$2"
  ipset create "$TARGET" hash:net family inet -exist
  ipset swap "$TMP" "$TARGET" 2>/dev/null || return 1
  ipset destroy "$TMP" 2>/dev/null || true
}

xkeen_build_bypass_ipset() {
  mkdir -p "$RUNTIME_DIR" 2>/dev/null || true

  TMP_SET="${XKEEN_BYPASS_SET}_next"
  ipset destroy "$TMP_SET" 2>/dev/null || true
  ipset create "$TMP_SET" hash:net family inet -exist

  if xkeen_has_cmd jq && [ -f "$STATE_PATH" ]; then
    jq -r '
      (.activeProfileId // "") as $id
      | .profiles[]?
      | select(.id == $id)
      | .groups[]?
      | select((.enabled != false) and (.outboundTag == "bypass" or .outboundTag == "direct"))
      | .domains[]?
    ' "$STATE_PATH" 2>/dev/null | sed '/^[[:space:]]*$/d' | xkeen_add_domains_to_set "$TMP_SET"

    jq -r '
      (.activeProfileId // "") as $id
      | .profiles[]?
      | select(.id == $id)
      | .groups[]?
      | select((.enabled != false) and (.outboundTag == "bypass" or .outboundTag == "direct"))
      | .cidrs[]?
    ' "$STATE_PATH" 2>/dev/null | sed '/^[[:space:]]*$/d' | xkeen_add_cidrs_to_set "$TMP_SET"
  fi

  xkeen_swap_set "$XKEEN_BYPASS_SET" "$TMP_SET"
}

xkeen_udp_config_enabled() {
  xkeen_has_cmd jq || return 1
  [ -f "$STATE_PATH" ] || return 1
  jq -e '
    (.activeProfileId // "") as $id
    | any(.profiles[]? | select(.id == $id) | .groups[]?;
        (.enabled != false)
        and (.outboundTag != "direct")
        and (.outboundTag != "bypass"))
  ' "$STATE_PATH" >/dev/null 2>&1
}

xkeen_build_udp_route_ipset() {
  TMP_SET="${XKEEN_UDP_ROUTE_SET}_next"
  ipset destroy "$TMP_SET" 2>/dev/null || true
  ipset create "$TMP_SET" hash:net family inet -exist

  if xkeen_has_cmd jq && [ -f "$STATE_PATH" ]; then
    jq -r '
      (.activeProfileId // "") as $id
      | .profiles[]?
      | select(.id == $id)
      | .groups[]?
      | select((.enabled != false) and (.outboundTag != "direct") and (.outboundTag != "bypass"))
      | .domains[]?
    ' "$STATE_PATH" 2>/dev/null | sed '/^[[:space:]]*$/d' | xkeen_add_domains_to_set "$TMP_SET"

    jq -r '
      (.activeProfileId // "") as $id
      | .profiles[]?
      | select(.id == $id)
      | .groups[]?
      | select((.enabled != false) and (.outboundTag != "direct") and (.outboundTag != "bypass"))
      | .cidrs[]?
    ' "$STATE_PATH" 2>/dev/null | sed '/^[[:space:]]*$/d' | xkeen_add_cidrs_to_set "$TMP_SET"
  fi

  xkeen_swap_set "$XKEEN_UDP_ROUTE_SET" "$TMP_SET"
}

xkeen_cleanup_udp443_block() {
  xkeen_delete_jumps filter FORWARD xkeen_udp443_block
  iptables -t filter -F xkeen_udp443_block 2>/dev/null || true
  iptables -t filter -X xkeen_udp443_block 2>/dev/null || true
}

xkeen_cleanup_retired_udp() {
  xkeen_delete_jumps mangle PREROUTING xkeen_udp
  iptables -t mangle -F xkeen_udp 2>/dev/null || true
  iptables -t mangle -X xkeen_udp 2>/dev/null || true

  xkeen_delete_jumps mangle PREROUTING xkeen_quic
  iptables -t mangle -F xkeen_quic 2>/dev/null || true
  iptables -t mangle -X xkeen_quic 2>/dev/null || true

  ipset destroy xkeen_redirect 2>/dev/null || true
  ipset destroy xkeen_vpn 2>/dev/null || true
  ipset destroy xkeen_quic_bypass 2>/dev/null || true
  xkeen_cleanup_udp443_block
}

xkeen_cleanup_udp_route() {
  xkeen_delete_jumps mangle PREROUTING xkeen_udp_route
  iptables -t mangle -F xkeen_udp_route 2>/dev/null || true
  iptables -t mangle -X xkeen_udp_route 2>/dev/null || true
  ipset destroy "$XKEEN_UDP_ROUTE_SET" 2>/dev/null || true
  while ip rule show | grep -qE "fwmark $XKEEN_UDP_MARK(/$XKEEN_UDP_MARK)? (lookup|table) $XKEEN_UDP_TABLE"; do
    ip rule del fwmark "$XKEEN_UDP_MARK/$XKEEN_UDP_MARK" table "$XKEEN_UDP_TABLE" 2>/dev/null \
      || ip rule del fwmark "$XKEEN_UDP_MARK/$XKEEN_UDP_MARK" lookup "$XKEEN_UDP_TABLE" 2>/dev/null \
      || ip rule del fwmark "$XKEEN_UDP_MARK" table "$XKEEN_UDP_TABLE" 2>/dev/null \
      || ip rule del fwmark "$XKEEN_UDP_MARK" lookup "$XKEEN_UDP_TABLE" 2>/dev/null \
      || break
  done
  ip route flush table "$XKEEN_UDP_TABLE" 2>/dev/null || true
}

xkeen_ensure_tproxy_module() {
  iptables -t mangle -N xkeen_tproxy_probe 2>/dev/null || true
  if iptables -t mangle -A xkeen_tproxy_probe -p udp -j TPROXY --on-port "$XKEEN_TPROXY_PORT" --tproxy-mark "$XKEEN_UDP_MARK/$XKEEN_UDP_MARK" 2>/dev/null; then
    iptables -t mangle -F xkeen_tproxy_probe 2>/dev/null || true
    iptables -t mangle -X xkeen_tproxy_probe 2>/dev/null || true
    return 0
  fi
  iptables -t mangle -F xkeen_tproxy_probe 2>/dev/null || true
  iptables -t mangle -X xkeen_tproxy_probe 2>/dev/null || true

  insmod "/lib/modules/$(uname -r)/xt_TPROXY.ko" 2>/dev/null || true
  iptables -t mangle -N xkeen_tproxy_probe 2>/dev/null || true
  iptables -t mangle -A xkeen_tproxy_probe -p udp -j TPROXY --on-port "$XKEEN_TPROXY_PORT" --tproxy-mark "$XKEEN_UDP_MARK/$XKEEN_UDP_MARK" 2>/dev/null || return 1
  iptables -t mangle -F xkeen_tproxy_probe 2>/dev/null || true
  iptables -t mangle -X xkeen_tproxy_probe 2>/dev/null || true
}

xkeen_apply_udp_route() {
  if ! xkeen_udp_config_enabled; then
    xkeen_cleanup_udp_route
    return 0
  fi

  xkeen_build_udp_route_ipset || return 1
  if ! xkeen_ipset_has_members "$XKEEN_UDP_ROUTE_SET"; then
    xkeen_cleanup_udp_route
    return 0
  fi

  xkeen_ensure_tproxy_module || return 1
  iptables -t mangle -N xkeen_udp_route 2>/dev/null || true
  iptables -t mangle -F xkeen_udp_route 2>/dev/null || true
  iptables -t mangle -A xkeen_udp_route -p udp -j TPROXY --on-port "$XKEEN_TPROXY_PORT" --tproxy-mark "$XKEEN_UDP_MARK/$XKEEN_UDP_MARK" 2>/dev/null || return 1

  while ip rule show | grep -qE "fwmark $XKEEN_UDP_MARK(/$XKEEN_UDP_MARK)? (lookup|table) $XKEEN_UDP_TABLE"; do
    ip rule del fwmark "$XKEEN_UDP_MARK/$XKEEN_UDP_MARK" table "$XKEEN_UDP_TABLE" 2>/dev/null \
      || ip rule del fwmark "$XKEEN_UDP_MARK/$XKEEN_UDP_MARK" lookup "$XKEEN_UDP_TABLE" 2>/dev/null \
      || ip rule del fwmark "$XKEEN_UDP_MARK" table "$XKEEN_UDP_TABLE" 2>/dev/null \
      || ip rule del fwmark "$XKEEN_UDP_MARK" lookup "$XKEEN_UDP_TABLE" 2>/dev/null \
      || break
  done
  ip rule add fwmark "$XKEEN_UDP_MARK/$XKEEN_UDP_MARK" table "$XKEEN_UDP_TABLE" 2>/dev/null || true
  ip route replace local 0.0.0.0/0 dev lo table "$XKEEN_UDP_TABLE" 2>/dev/null || true

  xkeen_delete_jumps mangle PREROUTING xkeen_udp_route
  iptables -t mangle -A PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -p udp -m set --match-set "$XKEEN_UDP_ROUTE_SET" dst -j xkeen_udp_route
}

xkeen_append_local_returns() {
  iptables -t nat -A xkeen -d 224.0.0.0/4 -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -d 255.255.255.255/32 -j RETURN 2>/dev/null || true

  ip route show | /opt/bin/awk '
    $1 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ && $2 == "dev" { print $1 }
  ' | sort -u | while IFS= read -r subnet; do
    [ -n "$subnet" ] || continue
    iptables -t nat -A xkeen -d "$subnet" -j RETURN 2>/dev/null || true
  done
}

xkeen_repair_hooks() {
  xkeen_ensure_mark || return 1
  mkdir -p "$RUNTIME_DIR" 2>/dev/null || true

  xkeen_build_bypass_ipset || return 1

  iptables -t nat -N xkeen 2>/dev/null || true
  iptables -t nat -F xkeen 2>/dev/null || true
  xkeen_append_local_returns
  iptables -t nat -A xkeen -p tcp -m set --match-set "$XKEEN_BYPASS_SET" dst -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -p tcp -j REDIRECT --to-ports "$XKEEN_REDIRECT_PORT" 2>/dev/null || true
  iptables -t nat -A xkeen -j RETURN 2>/dev/null || true

  xkeen_delete_jumps nat PREROUTING xkeen
  iptables -t nat -C PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -j xkeen

  xkeen_cleanup_retired_udp
  xkeen_apply_udp_route
}

xkeen_tproxy_ready() {
  netstat -lnpu 2>/dev/null | grep -q ":$XKEEN_TPROXY_PORT "
}
