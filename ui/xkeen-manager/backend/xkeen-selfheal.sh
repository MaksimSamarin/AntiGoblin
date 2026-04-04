#!/bin/sh

PATH="/opt/bin:/opt/sbin:/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

LOG_PATH="/opt/var/log/xkeen-selfheal.log"
XRAY_BIN="/opt/sbin/xray"
XRAY_ASSET_DIR="/opt/etc/xray/dat"
XRAY_CONF_DIR="/opt/etc/xray/configs"
STATE_PATH="/opt/share/xkeen-manager/xkeen-ui-state.json"
LOCK_DIR="/tmp/xkeen-selfheal.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
RUNTIME_DIR="/opt/share/xkeen-manager/runtime"
BYPASS_DOMAINS_PATH="$RUNTIME_DIR/bypass-domains.txt"
BYPASS_CIDRS_PATH="$RUNTIME_DIR/bypass-cidrs.txt"
XKEEN_MARK=""
find_cron_init() {
  for candidate in /opt/etc/init.d/S10cron /opt/etc/init.d/S05crond; do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

cron_running() {
  ps | grep -E '[[:space:]](cron|crond)([[:space:]]|$)' | grep -v grep >/dev/null 2>&1
}

needs_repair=0
force_mode=0

if [ "$1" = "--force" ]; then
  force_mode=1
fi

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_PATH"
}

has_rule() {
  "$@" >/dev/null 2>&1
}

get_xkeen_mark() {
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

get_default_wan_iface() {
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

next_xkeen_policy_name() {
  ndmc -c 'show running-config' 2>/dev/null | /opt/bin/awk '
    /^ip policy Policy[0-9]+$/ {
      name=$3
      sub(/^Policy/, "", name)
      if (name >= 42) {
        print name
      }
    }
  ' | sort -n | /opt/bin/awk '
    BEGIN { n = 42 }
    {
      if ($1 == n) {
        n++
      }
    }
    END { print "Policy" n }
  '
}

ensure_xkeen_policy() {
  if ndmc -c 'show ip policy' 2>/dev/null | grep -q 'description = xkeen:'; then
    return 0
  fi

  WAN_IFACE="$(get_default_wan_iface)"
  [ -n "$WAN_IFACE" ] || return 1

  POLICY_NAME="$(next_xkeen_policy_name)"
  [ -n "$POLICY_NAME" ] || POLICY_NAME="Policy42"

  log "xkeen policy missing, creating $POLICY_NAME on $WAN_IFACE"
  ndmc -c "ip policy $POLICY_NAME" >/dev/null 2>&1 || return 1
  ndmc -c "ip policy $POLICY_NAME description xkeen" >/dev/null 2>&1 || return 1
  ndmc -c "ip policy $POLICY_NAME permit global $WAN_IFACE" >/dev/null 2>&1 || return 1
  ndmc -c "system configuration save" >/dev/null 2>&1 || true
  sleep 1
  ndmc -c 'show ip policy' 2>/dev/null | grep -q 'description = xkeen:'
}

ensure_xkeen_mark() {
  ensure_xkeen_policy || return 1
  XKEEN_MARK="$(get_xkeen_mark)"
  [ -n "$XKEEN_MARK" ]
}

xray_ready() {
  netstat -lnpt 2>/dev/null | grep -q ':61219 '
}

build_bypass_ipset() {
  ipset create xkeen_bypass hash:net family inet -exist
  ipset flush xkeen_bypass 2>/dev/null || true

  [ -f "$BYPASS_DOMAINS_PATH" ] || : > "$BYPASS_DOMAINS_PATH"
  [ -f "$BYPASS_CIDRS_PATH" ] || : > "$BYPASS_CIDRS_PATH"

  sed 's/#.*$//' "$BYPASS_DOMAINS_PATH" | sed '/^[[:space:]]*$/d' | while IFS= read -r domain; do
    [ -n "$domain" ] || continue
    nslookup "$domain" 2>/dev/null | /opt/bin/awk '
      /^Name:/ { seen_name=1; next }
      seen_name && /^Address [0-9]+: / { print $3; next }
      seen_name && /^Address: / { print $2; next }
    ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -Ev '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' | while IFS= read -r ip; do
      [ -n "$ip" ] || continue
      ipset add xkeen_bypass "$ip"/32 -exist 2>/dev/null || true
    done
  done

  sed 's/#.*$//' "$BYPASS_CIDRS_PATH" | sed '/^[[:space:]]*$/d' | while IFS= read -r cidr; do
    [ -n "$cidr" ] || continue
    ipset add xkeen_bypass "$cidr" -exist 2>/dev/null || true
  done

  if command -v jq >/dev/null 2>&1 && [ -f "$STATE_PATH" ]; then
    jq -r '.profiles[]? | .groups[]? | select((.enabled != false) and (.outboundTag == "bypass")) | .domains[]?' "$STATE_PATH" 2>/dev/null | \
      sed '/^[[:space:]]*$/d' | while IFS= read -r domain; do
        [ -n "$domain" ] || continue
        nslookup "$domain" 2>/dev/null | /opt/bin/awk '
          /^Name:/ { seen_name=1; next }
          seen_name && /^Address [0-9]+: / { print $3; next }
          seen_name && /^Address: / { print $2; next }
        ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -Ev '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' | while IFS= read -r ip; do
          [ -n "$ip" ] || continue
          ipset add xkeen_bypass "$ip"/32 -exist 2>/dev/null || true
        done
      done

    jq -r '.profiles[]? | .groups[]? | select((.enabled != false) and (.outboundTag == "bypass")) | .cidrs[]?' "$STATE_PATH" 2>/dev/null | \
      sed '/^[[:space:]]*$/d' | while IFS= read -r cidr; do
        [ -n "$cidr" ] || continue
        ipset add xkeen_bypass "$cidr" -exist 2>/dev/null || true
      done
  fi
}

append_local_returns() {
  iptables -t nat -A xkeen -d 224.0.0.0/4 -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -d 255.255.255.255/32 -j RETURN 2>/dev/null || true

  ip route show | /opt/bin/awk '
    $1 ~ /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/ && $2 == "dev" {
      print $1
    }
  ' | sort -u | while IFS= read -r subnet; do
    [ -n "$subnet" ] || continue
    iptables -t nat -A xkeen -d "$subnet" -j RETURN 2>/dev/null || true
  done
}

check_runtime() {
  ensure_xkeen_mark || needs_repair=1
  has_rule iptables -t nat -S xkeen || needs_repair=1
  [ -n "$XKEEN_MARK" ] && has_rule iptables -t nat -C PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -j xkeen || needs_repair=1
  has_rule iptables -t nat -C xkeen -d 224.0.0.0/4 -j RETURN || needs_repair=1
  has_rule iptables -t nat -C xkeen -d 255.255.255.255/32 -j RETURN || needs_repair=1
  has_rule iptables -t nat -C xkeen -p tcp -m set --match-set xkeen_bypass dst -j RETURN || needs_repair=1
  has_rule iptables -t nat -C xkeen -p tcp -j REDIRECT --to-ports 61219 || needs_repair=1
  has_rule iptables -t nat -C xkeen -j RETURN || needs_repair=1
  has_rule ipset list xkeen_bypass || needs_repair=1
  xray_ready || needs_repair=1
}

repair_hooks() {
  ensure_xkeen_mark || return 1
  mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
  build_bypass_ipset
  iptables -t nat -N xkeen 2>/dev/null || true
  iptables -t nat -F xkeen 2>/dev/null || true
  append_local_returns
  iptables -t nat -A xkeen -p tcp -m set --match-set xkeen_bypass dst -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -p tcp -j REDIRECT --to-ports 61219 2>/dev/null || true
  iptables -t nat -A xkeen -j RETURN 2>/dev/null || true
  iptables -t nat -D PREROUTING -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || true
  iptables -t nat -D PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || true
  iptables -t nat -C PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -j xkeen

  while ip rule show | grep -q 'fwmark 0x111 lookup 111'; do
    ip rule del fwmark 0x111 lookup 111 2>/dev/null || break
  done

  iptables -t mangle -D PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp 2>/dev/null || true
  iptables -t mangle -D PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp 2>/dev/null || true
  iptables -t mangle -D PREROUTING -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp 2>/dev/null || true
  iptables -t mangle -F xkeen_udp 2>/dev/null || true
  iptables -t mangle -X xkeen_udp 2>/dev/null || true

  iptables -t mangle -D PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -p udp -j xkeen_quic 2>/dev/null || true
  iptables -t mangle -D PREROUTING -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -p udp -j xkeen_quic 2>/dev/null || true
  iptables -t mangle -F xkeen_quic 2>/dev/null || true
  iptables -t mangle -X xkeen_quic 2>/dev/null || true

  ipset destroy xkeen_redirect 2>/dev/null || true
  ipset destroy xkeen_vpn 2>/dev/null || true
  ipset destroy xkeen_quic_bypass 2>/dev/null || true
}

restart_xray() {
  killall xray 2>/dev/null || true
  rm -f /opt/var/run/xray-ui.pid /opt/var/run/xray.pid 2>/dev/null || true
  sleep 2
  XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" XRAY_LOCATION_CONFDIR="$XRAY_CONF_DIR" \
    /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/xray-ui.pid -x "$XRAY_BIN" -- run >>"$LOG_PATH" 2>&1
  sleep 3
}

repair_runtime() {
  log "repair start"

  if ! cron_running; then
    CRON_INIT="$(find_cron_init 2>/dev/null || true)"
    [ -n "$CRON_INIT" ] && "$CRON_INIT" restart >/dev/null 2>&1 || true
  fi

  repair_hooks

  if ! xray_ready; then
    log "xray restart needed"
    restart_xray
  fi

  if xray_ready; then
    log "repair done"
    return 0
  fi

  log "repair failed"
  return 1
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_PID_FILE"
    return 0
  fi

  if [ -f "$LOCK_PID_FILE" ]; then
    OLD_PID="$(cat "$LOCK_PID_FILE" 2>/dev/null)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      exit 0
    fi
  fi

  rm -rf "$LOCK_DIR" 2>/dev/null || true
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_PID_FILE"
    return 0
  fi

  exit 0
}

acquire_lock

trap 'rm -f "$LOCK_PID_FILE" 2>/dev/null || true; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

check_runtime

if [ "$force_mode" -eq 1 ] || [ "$needs_repair" -eq 1 ]; then
  repair_runtime
  exit $?
fi

exit 0
