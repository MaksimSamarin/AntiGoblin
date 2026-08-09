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
# Shared mkdir-based lock: selfheal, netfilter-hook, remount-hook and CGI
# apply all serialise on the same LOCK_DIR to avoid clobbering each other's
# iptables/ipset rebuilds. Every caller sources this file and uses
# xkeen_lock_acquire / xkeen_lock_release below — do NOT reinvent the lock
# per script (previous attempts race-clobbered each other on WiFi flaps).
: "${XKEEN_LOCK_DIR:=/tmp/xkeen-selfheal.lock}"
: "${XKEEN_LOCK_PID_FILE:=${XKEEN_LOCK_DIR}/pid}"

XKEEN_MARK="${XKEEN_MARK:-}"

xkeen_runtime_log() {
  [ -n "${XKEEN_RUNTIME_LOG:-}" ] || return 0
  printf '%s runtime %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$XKEEN_RUNTIME_LOG"
}

xkeen_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# --- Shared cross-process lock -----------------------------------------
#
# mkdir is atomic, so a plain `mkdir "$LOCK_DIR"` gives us mutual exclusion.
# Two things that used to be race-prone and are handled here:
#
#   1. **Race window** between `mkdir` success and pidfile write. The old
#      code, on mkdir-fail, immediately looked at pidfile — if it wasn't
#      there yet, it force-cleaned the directory. That could steal the
#      lock from a legitimate owner mid-init. Now the owner writes the
#      pidfile before releasing execution; other callers poll for it up
#      to ~500ms before considering the lock stale.
#
#   2. **PID recycling**: `kill -0 $OLD_PID` returns 0 for ANY process
#      owning that PID, not just our killed one. Under process churn a
#      recycled PID belonging to a completely unrelated process would
#      fake liveness and keep the lock held forever. We now check that
#      /proc/$PID/comm looks like a shell (`sh`/`ash`) — the interpreter
#      running one of our scripts — to reject collisions. This isn't
#      bullet-proof (another shell could own it), but it's much better
#      than raw kill -0.
#
# Returns 0 on lock acquired (caller must arrange xkeen_lock_release in a
# trap), 1 on failure (caller should exit / retry).

_xkeen_lock_holder_looks_alive() {
  _pid="$1"
  [ -n "$_pid" ] || return 1
  kill -0 "$_pid" 2>/dev/null || return 1
  # Check cmdline (not comm) — comm is just "sh" for every /bin/sh
  # process, including unrelated user SSH sessions. cmdline contains
  # the actual arguments so we can look for AntiGoblin script names.
  # If cmdline isn't readable, fall back to comm with a narrower rule.
  if [ -r "/proc/$_pid/cmdline" ]; then
    _cmdline="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)"
    case "$_cmdline" in
      *xkeen-selfheal*|*antigoblin*|*routing.cgi*|*xkeen-runtime*)
        return 0
        ;;
      *)
        # Not one of ours — stale (or recycled by an unrelated process).
        return 1
        ;;
    esac
  fi
  if [ -r "/proc/$_pid/comm" ]; then
    _comm="$(cat "/proc/$_pid/comm" 2>/dev/null)"
    case "$_comm" in
      xkeen-selfhea*|antigoblin*|routing.cgi*)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi
  # No /proc access at all — assume alive (fail-safe: don't steal).
  return 0
}

xkeen_lock_acquire() {
  _attempts=0
  while [ $_attempts -lt 3 ]; do
    if mkdir "$XKEEN_LOCK_DIR" 2>/dev/null; then
      printf '%s\n' "$$" > "$XKEEN_LOCK_PID_FILE" 2>/dev/null || true
      return 0
    fi
    # mkdir failed. Wait briefly for the owner to write its pidfile —
    # bridging the race window in case they only just took the lock.
    _wait=0
    while [ $_wait -lt 5 ] && [ ! -f "$XKEEN_LOCK_PID_FILE" ]; do
      sleep 1
      _wait=$((_wait + 1))
      # sh has no sub-second sleep everywhere. This is worst-case
      # 5s of pause but only when a truly racy contender exists.
    done
    if [ -f "$XKEEN_LOCK_PID_FILE" ]; then
      _old_pid="$(cat "$XKEEN_LOCK_PID_FILE" 2>/dev/null)"
      if _xkeen_lock_holder_looks_alive "$_old_pid"; then
        return 1
      fi
      # Stale lock: pidfile points at a dead or unrelated PID.
      xkeen_runtime_log "lock_stale_cleanup old_pid=${_old_pid:-empty}"
      rm -rf "$XKEEN_LOCK_DIR" 2>/dev/null || true
      _attempts=$((_attempts + 1))
      continue
    fi
    # Directory exists, pidfile still absent after wait: treat as
    # abandoned partial-init and clean up.
    xkeen_runtime_log "lock_abandoned_cleanup"
    rm -rf "$XKEEN_LOCK_DIR" 2>/dev/null || true
    _attempts=$((_attempts + 1))
  done
  return 1
}

xkeen_lock_release() {
  rm -f "$XKEEN_LOCK_PID_FILE" 2>/dev/null || true
  rmdir "$XKEEN_LOCK_DIR" 2>/dev/null || true
}

xkeen_has_rule() {
  "$@" >/dev/null 2>&1
}

# Canonical regex for matching the AntiGoblin policy description across all
# NDMC output formats seen in the wild:
#   - `description = xkeen:Home`  (format A, newer one-liner, one policy per row)
#   - `description: xkeen`        (format B, older multiline, no space before `:`)
#   - `description xkeen`         (format C, bare, what our own
#                                  `ndmc -c "ip policy X description xkeen"`
#                                  produces on some builds)
# Bare `descriptionxkeen` MUST NOT match, so between the word and `xkeen` we
# require EITHER at least one whitespace OR a `=`/`:` separator.
: "${XKEEN_POLICY_DESC_RE:=description(([[:space:]]*[=:])|([[:space:]]+))[[:space:]]*\"?xkeen($|[\":,[:space:]])}"

# DNS cache: nslookup is synchronous and holds apply_lock while iterating
# large group lists (100+ domains → minutes). Cache resolved IPs for 15 min
# in /tmp so repeated selfheal cycles reuse them. Negative results are also
# cached (empty file) with a shorter TTL so a permanently-dead domain
# doesn't cost a 3-second timeout every 15-second selfheal tick, but a
# domain that starts resolving again isn't blackholed for 15 minutes.
: "${XKEEN_DNS_CACHE_DIR:=/tmp/xkeen-dns-cache}"
: "${XKEEN_DNS_CACHE_TTL:=900}"
: "${XKEEN_DNS_CACHE_NEG_TTL:=120}"
# Per-lookup nslookup wall-time cap (BusyBox nslookup has no --timeout,
# and coreutils-timeout isn't installed by default).
: "${XKEEN_NSLOOKUP_TIMEOUT:=3}"

_xkeen_parse_nslookup_ipv4() {
  /opt/bin/awk '
    /^Name:/ { seen_name=1; next }
    seen_name && /^Address [0-9]+: / { print $3; next }
    seen_name && /^Address: / { print $2; next }
  ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | grep -Ev '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'
}

xkeen_nslookup_ipv4_uncached() {
  # If Entware coreutils-timeout is around, use it — it sends SIGTERM to
  # its direct child (plus SIGKILL after -s TERM if the child ignores it),
  # no orphan-killer risk.
  if [ -x /opt/bin/timeout ]; then
    /opt/bin/timeout -k 1 "$XKEEN_NSLOOKUP_TIMEOUT" nslookup "$1" 2>/dev/null \
      | _xkeen_parse_nslookup_ipv4
    return
  fi
  # Fallback: background nslookup + poll for its exit. Uses SIGKILL after
  # SIGTERM because BusyBox nslookup can ignore SIGTERM while waiting on
  # UDP DNS retries — a plain `wait "$nspid"` after `kill $nspid` would
  # hang forever. `wait` at the end is bounded, so hung nslookups can't
  # deadlock selfheal.
  mkdir -p "$XKEEN_DNS_CACHE_DIR" 2>/dev/null || true
  tmp="$XKEEN_DNS_CACHE_DIR/.nslookup-$$-$(date +%s).tmp"
  nslookup "$1" >"$tmp" 2>/dev/null &
  nspid=$!
  i=0
  while [ $i -lt "$XKEEN_NSLOOKUP_TIMEOUT" ] && kill -0 "$nspid" 2>/dev/null; do
    # `kill -0` returns 0 for a zombie whose exit hasn't been reaped yet.
    # Two fast-paths so we don't wait the full timeout after the answer
    # (or failure) already landed:
    #   - Answer already written: an `Address:` line means nslookup got a
    #     valid response and is finishing up.
    #   - Process is a zombie: /proc/<pid>/status shows `State: Z ...`.
    grep -q '^Address' "$tmp" 2>/dev/null && break
    if [ -r "/proc/$nspid/status" ]; then
      case "$(/opt/bin/awk '/^State:/{print $2; exit}' /proc/$nspid/status 2>/dev/null)" in
        Z) break ;;
      esac
    fi
    sleep 1
    i=$((i + 1))
  done
  if kill -0 "$nspid" 2>/dev/null; then
    kill "$nspid" 2>/dev/null
    sleep 1
    kill -9 "$nspid" 2>/dev/null
  fi
  # Reap the zombie. `wait` blocks until the child truly disappears, but
  # after SIGKILL that's essentially immediate.
  wait "$nspid" 2>/dev/null
  _xkeen_parse_nslookup_ipv4 <"$tmp"
  rm -f "$tmp" 2>/dev/null || true
}

_xkeen_dns_cache_key() {
  printf '%s' "$1" | /opt/bin/awk '{gsub(/[^A-Za-z0-9._-]/, "_"); print}'
}

# Returns 0 if cache entry exists AND is within its TTL (positive TTL for
# non-empty entries, negative TTL for empty entries). No output.
xkeen_dns_cache_fresh() {
  cache_file="$XKEEN_DNS_CACHE_DIR/$(_xkeen_dns_cache_key "$1")"
  [ -f "$cache_file" ] || return 1
  now="$(date +%s)"
  mtime="$(stat -c %Y "$cache_file" 2>/dev/null)"
  case "$mtime" in ''|*[!0-9]*) return 1 ;; esac
  if [ -s "$cache_file" ]; then
    ttl="$XKEEN_DNS_CACHE_TTL"
  else
    ttl="$XKEEN_DNS_CACHE_NEG_TTL"
  fi
  [ $((now - mtime)) -lt "$ttl" ]
}

xkeen_dns_cache_get() {
  cache_file="$XKEEN_DNS_CACHE_DIR/$(_xkeen_dns_cache_key "$1")"
  [ -f "$cache_file" ] || return 1
  cat "$cache_file"
}

xkeen_dns_cache_set() {
  key="$(_xkeen_dns_cache_key "$1")"
  mkdir -p "$XKEEN_DNS_CACHE_DIR" 2>/dev/null || return 0
  cat > "$XKEEN_DNS_CACHE_DIR/$key" 2>/dev/null || true
}

# GC: delete entries older than max(pos-TTL, neg-TTL) * 2. Called from
# selfheal's daily rotate, so it won't run on every tick. Uses `find` with
# -mmin fallback path if -mmin isn't available (BusyBox find is fine here).
xkeen_dns_cache_gc() {
  [ -d "$XKEEN_DNS_CACHE_DIR" ] || return 0
  # 2 * 900s = 30min. `-mmin +30` = older than 30 minutes.
  find "$XKEEN_DNS_CACHE_DIR" -type f -mmin +30 -delete 2>/dev/null || true
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
  # NDMC prints marks in two shapes:
  #   Format A (one-liner):  "policy, name = PolicyN, description = xkeen:X, mark = 0xNNN, ..."
  #                          — description and mark on the SAME line.
  #   Format B (multiline):  "name: PolicyN\n  description: xkeen\n  mark: 0xNNN\n"
  #                          — mark on a subsequent line.
  # Previous version did `next` on the description match, which skipped the
  # Format-A line entirely and then read `mark` from an unrelated later
  # policy. Now we first try to extract mark from the SAME line as
  # description; if not found, we fall through to Format-B lookahead.
  ndmc -c 'show ip policy' 2>/dev/null | /opt/bin/awk -v pat="$XKEEN_POLICY_DESC_RE" '
    function extract_mark(line) {
      if (match(line, /mark[[:space:]]*[=:][[:space:]]*(0x)?[0-9a-fA-F]+/)) {
        val = substr(line, RSTART, RLENGTH)
        sub(/^mark[[:space:]]*[=:][[:space:]]*/, "", val)
        sub(/^0x/, "", val)
        return val
      }
      return ""
    }
    # New policy starts — reset the "looking for mark" flag so we do not
    # accidentally read a NEXT policys mark line after our xkeen
    # description block ended without finding one.
    /^[[:space:]]*policy,/ {
      want_mark = 0
    }
    $0 ~ pat {
      m = extract_mark($0)
      if (m != "") { print m; exit }
      want_mark = 1
      next
    }
    want_mark {
      m = extract_mark($0)
      if (m != "") { print m; exit }
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
  if ndmc -c 'show ip policy' 2>/dev/null | grep -Eq "$XKEEN_POLICY_DESC_RE"; then
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
  ndmc -c 'show ip policy' 2>/dev/null | grep -Eq "$XKEEN_POLICY_DESC_RE"
}

xkeen_ensure_mark() {
  xkeen_ensure_policy || return 1
  XKEEN_MARK="$(xkeen_get_mark)"
  if [ -n "$XKEEN_MARK" ]; then
    # Cache the successful ndmc lookup so netfilter.d hooks (which fire
    # DURING an NDM netfilter reload) don't have to dial ndmc themselves
    # — that call can stall while NDMS is busy reconfiguring, delaying
    # the very jump-restore that made the hook run in the first place.
    printf '%s' "$XKEEN_MARK" > /tmp/xkeen-mark 2>/dev/null || true
    return 0
  fi
  return 1
}

xkeen_resolve_ipv4() {
  domain="$1"
  # Cache hit path (positive OR negative — negative = empty file, still
  # counts as a hit within its short TTL so we don't re-nslookup every
  # 15-second selfheal tick on a dead domain).
  if xkeen_dns_cache_fresh "$domain"; then
    xkeen_dns_cache_get "$domain"
    return 0
  fi
  fresh="$(xkeen_nslookup_ipv4_uncached "$domain")"
  if [ -z "$fresh" ]; then
    xkeen_runtime_log "resolve_ipv4_none domain=$domain (neg-cached ${XKEEN_DNS_CACHE_NEG_TTL}s)"
    : | xkeen_dns_cache_set "$domain"
    return 0
  fi
  printf '%s\n' "$fresh" | xkeen_dns_cache_set "$domain"
  printf '%s\n' "$fresh"
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
    # hash:net в BusyBox ipset не принимает 0.0.0.0/0. Пользователь ожидает
    # что этот CIDR = "весь IPv4", а не сталкивался с молчаливым падением.
    # Разбиваем на две половины, оба валидны для hash:net.
    if [ "$cidr" = "0.0.0.0/0" ]; then
      ipset add "$SET_NAME" "0.0.0.0/1" -exist 2>/dev/null \
        || xkeen_runtime_log "ipset_add_fail set=$SET_NAME cidr=0.0.0.0/1"
      ipset add "$SET_NAME" "128.0.0.0/1" -exist 2>/dev/null \
        || xkeen_runtime_log "ipset_add_fail set=$SET_NAME cidr=128.0.0.0/1"
    else
      ipset add "$SET_NAME" "$cidr" -exist 2>/dev/null \
        || xkeen_runtime_log "ipset_add_fail set=$SET_NAME cidr=$cidr"
    fi
  done
}

xkeen_swap_set() {
  TARGET="$1"
  TMP="$2"
  ipset create "$TARGET" hash:net family inet -exist
  if ! ipset swap "$TMP" "$TARGET" 2>/dev/null; then
    xkeen_runtime_log "ipset_swap_fail target=$TARGET tmp=$TMP"
    return 1
  fi
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

    # Warn (but don't block) when the user adds an RFC1918 CIDR to a
    # routed group. Consequence: entire LAN traffic goes through TPROXY →
    # sing-box → VPN, including traffic to the router itself, which can
    # take the admin UI offline. UI-side validation is the real fix; this
    # is a diagnostic breadcrumb.
    jq -r '
      (.activeProfileId // "") as $id
      | .profiles[]?
      | select(.id == $id)
      | .groups[]?
      | select((.enabled != false) and (.outboundTag != "direct") and (.outboundTag != "bypass"))
      | .cidrs[]?
    ' "$STATE_PATH" 2>/dev/null | sed '/^[[:space:]]*$/d' | while IFS= read -r cidr; do
      case "$cidr" in
        192.168.*|10.*|172.16.*|172.17.*|172.18.*|172.19.*|172.20.*|172.21.*|172.22.*|172.23.*|172.24.*|172.25.*|172.26.*|172.27.*|172.28.*|172.29.*|172.30.*|172.31.*)
          xkeen_runtime_log "warn routed cidr is rfc1918 cidr=$cidr (may blackhole LAN)"
          ;;
      esac
      printf '%s\n' "$cidr"
    done | xkeen_add_cidrs_to_set "$TMP_SET"
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

  # Guard against empty mark. A stale caller can slip through even after
  # xkeen_ensure_mark. Without this, the mangle rule reads `--mark 0x` and
  # iptables rejects it — but we've already deleted the previous working
  # rule right after (xkeen_delete_jumps). Result: healthy rule gone, new
  # rule not added, UDP route silently broken.
  if [ -z "$XKEEN_MARK" ]; then
    xkeen_runtime_log "abort xkeen_apply_udp_route: empty XKEEN_MARK"
    return 1
  fi

  xkeen_build_udp_route_ipset || return 1
  if ! xkeen_ipset_has_members "$XKEEN_UDP_ROUTE_SET"; then
    xkeen_cleanup_udp_route
    return 0
  fi

  xkeen_ensure_tproxy_module || return 1
  iptables -t mangle -N xkeen_udp_route 2>/dev/null || true
  iptables -t mangle -F xkeen_udp_route 2>/dev/null || true
  # Bypass UDP for hosts in the bypass ipset before TPROXY. Mirrors the TCP
  # bypass-RETURN that lives in the nat `xkeen` chain. Without this, a host
  # added to bypass via UI only escapes REDIRECT (TCP); its UDP still goes
  # to sing-box -> xray -> VPN, which adds full VPN RTT to realtime traffic
  # (e.g. game servers, voice). Same set is used so UI bypass groups cover
  # both protocols with one toggle, matching the project's intent.
  iptables -t mangle -A xkeen_udp_route -m set --match-set "$XKEEN_BYPASS_SET" dst -j RETURN 2>/dev/null || true
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
  if ! iptables -t mangle -A PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -p udp -m set --match-set "$XKEEN_UDP_ROUTE_SET" dst -j xkeen_udp_route 2>/dev/null; then
    xkeen_runtime_log "iptables_fail: mangle PREROUTING -> xkeen_udp_route (mark=0x$XKEEN_MARK)"
    return 1
  fi
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

xkeen_block_ipv6_forward() {
  # Prevent IPv6 leaks for xkeen-policy devices: AAAA-resolved domains
  # (claude.ai, anthropic.com, etc) bypass our IPv4-only iptables and
  # leak the real ISP IPv6 to the destination. Reject IPv6 forward for
  # the xkeen connmark so clients fall back to IPv4 (which goes via VPN).
  command -v ip6tables >/dev/null 2>&1 || return 0
  [ -n "$XKEEN_MARK" ] || return 0
  ip6tables -C FORWARD -m connmark --mark "0x$XKEEN_MARK" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null && return 0
  ip6tables -I FORWARD -m connmark --mark "0x$XKEEN_MARK" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null || true
}

# Detects the router's LAN IPv4 address dynamically.
# Excludes:
#   - lo (loopback)
#   - the WAN interface itself (the one holding the default route). This is
#     critical in double-NAT setups: if the Keenetic sits behind another
#     router (WAN IP is RFC1918 like 192.168.1.102), that address is on the
#     wrong side of the router and would be unreachable from LAN clients.
#   - VPN / tunnel interfaces (wg*/tun*/ppp*/tap*/ovpn*/nwg*)
# Returns the first surviving RFC1918 address. Bridge-preferring (br*) is
# not enforced: some Keenetic builds surface the LAN as a non-bridge iface.
xkeen_lan_ip() {
  WAN_IF="$(ip -4 route show default 2>/dev/null | /opt/bin/awk '/^default/{
    for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit }
  }')"

  ip -4 addr show 2>/dev/null | /opt/bin/awk -v wan="$WAN_IF" '
    /^[0-9]+:[[:space:]]/ {
      iface=$2
      sub(/:$/, "", iface)
      sub(/@.*/, "", iface)
      next
    }
    /^[[:space:]]*inet / {
      if (iface == "lo") next
      if (wan != "" && iface == wan) next
      if (iface ~ /^(wg|tun|ppp|tap|ovpn|nwg)/) next
      split($2, a, "/")
      addr = a[1]
      if (addr ~ /^192\.168\./ || addr ~ /^10\./ \
          || addr ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) {
        print addr
        exit
      }
    }
  '
}

# Sets `settings.ip` in xray socks-in inbound to the router's LAN IPv4.
# xray sends this value to SOCKS5 clients in the UDP-ASSOCIATE reply as
# the endpoint they must open UDP sockets to. Hardcoding it in the shipped
# config would break setups where the router LAN is not 192.168.2.1.
# Idempotent: writes only when the value actually differs; safe to call
# from selfheal every cycle and from routing.cgi on apply/restart.
xkeen_ensure_socks_inbound_ip() {
  xkeen_has_cmd jq || return 0
  INBOUNDS_PATH=/opt/etc/xray/configs/03_inbounds.json
  [ -f "$INBOUNDS_PATH" ] || return 0
  jq -e '.inbounds[]? | select(.tag == "socks-in")' "$INBOUNDS_PATH" >/dev/null 2>&1 || return 0

  LAN_IP="$(xkeen_lan_ip)"
  if [ -z "$LAN_IP" ]; then
    xkeen_runtime_log "socks-in settings.ip skip: no RFC1918 LAN interface found"
    return 0
  fi

  CURRENT_IP="$(jq -r '(.inbounds[]?|select(.tag=="socks-in").settings.ip) // ""' "$INBOUNDS_PATH" 2>/dev/null)"
  [ "$CURRENT_IP" = "$LAN_IP" ] && return 0

  TMP="${INBOUNDS_PATH}.tmp-socks-ip"
  jq --arg ip "$LAN_IP" '(.inbounds[] | select(.tag == "socks-in") | .settings.ip) = $ip' "$INBOUNDS_PATH" > "$TMP" 2>/dev/null || { rm -f "$TMP"; return 1; }
  jq -e '.' "$TMP" >/dev/null 2>&1 || { rm -f "$TMP"; return 1; }
  # 644, not 755 — this is a JSON config, not an executable. xray reads it
  # as its own uid, no need for +x anywhere.
  mv "$TMP" "$INBOUNDS_PATH" && chmod 644 "$INBOUNDS_PATH"
  xkeen_runtime_log "socks-in settings.ip -> $LAN_IP"
  # xray only reads inbounds at startup. Drop a sentinel so selfheal picks
  # up the change on its next tick and restarts xray. Without this, a
  # freshly-installed router (or LAN-IP change on a live one) leaves the
  # SOCKS5-inbound advertising the wrong IP until something else forces
  # an xray restart.
  touch /tmp/xkeen-needs-xray-restart 2>/dev/null || true
  return 0
}

xkeen_repair_hooks() {
  xkeen_ensure_mark || return 1
  mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
  xkeen_ensure_socks_inbound_ip

  xkeen_build_bypass_ipset || return 1

  iptables -t nat -N xkeen 2>/dev/null || true
  iptables -t nat -F xkeen 2>/dev/null || true
  xkeen_append_local_returns
  iptables -t nat -A xkeen -p tcp -m set --match-set "$XKEEN_BYPASS_SET" dst -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -p tcp -j REDIRECT --to-ports "$XKEEN_REDIRECT_PORT" 2>/dev/null || true
  # REDIRECT is terminating, so nothing after it in this chain is reachable.
  # We keep the trailing RETURN as a defensive marker: if someone later
  # inserts a non-terminating rule between REDIRECT and here, packets not
  # matched by REDIRECT (e.g. UDP if the -p tcp guard is edited) will
  # explicitly leave the chain instead of falling through implicitly.
  iptables -t nat -A xkeen -j RETURN 2>/dev/null || true

  xkeen_delete_jumps nat PREROUTING xkeen
  if ! iptables -t nat -C PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null; then
    if ! iptables -t nat -I PREROUTING 1 -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null; then
      xkeen_runtime_log "iptables_fail: nat PREROUTING -> xkeen (mark=0x$XKEEN_MARK)"
    fi
  fi

  xkeen_block_ipv6_forward
  xkeen_cleanup_retired_udp
  xkeen_apply_udp_route
}

xkeen_tproxy_ready() {
  netstat -lnpu 2>/dev/null | grep -q ":$XKEEN_TPROXY_PORT "
}
