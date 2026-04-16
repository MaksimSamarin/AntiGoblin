#!/bin/sh

PATH="/opt/bin:/opt/sbin:/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

LOG_PATH="/opt/var/log/xkeen-selfheal.log"
HEALTH_LOG_PATH="/opt/var/log/xkeen-health.log"
XRAY_BIN="/opt/sbin/xray"
XRAY_ASSET_DIR="/opt/etc/xray/dat"
XRAY_CONF_DIR="/opt/etc/xray/configs"
STATE_PATH="/opt/share/xkeen-manager/xkeen-ui-state.json"
LOCK_DIR="/tmp/xkeen-selfheal.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
HEALTH_STAMP_FILE="/tmp/xkeen-health-last.ts"
XRAY_RESTART_STAMP_FILE="/tmp/xkeen-xray-restart-last.ts"
RUNTIME_DIR="/opt/share/xkeen-manager/runtime"
BYPASS_DOMAINS_PATH="$RUNTIME_DIR/bypass-domains.txt"
BYPASS_CIDRS_PATH="$RUNTIME_DIR/bypass-cidrs.txt"
XKEEN_MARK=""
XRAY_PID=""
XRAY_FD_COUNT=0
XRAY_FD_LIMIT=0
XRAY_FD_WARN_THRESHOLD=400
XRAY_FD_CRITICAL_THRESHOLD=600
XRAY_FD_CRITICAL_STREAK_REQUIRED=3
XRAY_REMOTE_HOST=""
XRAY_REMOTE_PORT=0
XRAY_REMOTE_IP=""
XRAY_REMOTE_TOTAL_COUNT=0
XRAY_REMOTE_ESTABLISHED_COUNT=0
XRAY_REMOTE_FIN_WAIT_COUNT=0
XRAY_REMOTE_FIN_WAIT_WARN_THRESHOLD=20
XRAY_REMOTE_FIN_WAIT_CRITICAL_THRESHOLD=50
XRAY_REMOTE_FIN_WAIT_STREAK_REQUIRED=3
MEM_AVAILABLE_KB=0
MEM_TOTAL_KB=0
CONNTRACK_COUNT=0
CONNTRACK_MAX=0
HEALTH_PROBE_OK=0
HEALTH_STATUS="ok"
XRAY_FD_CRITICAL_STREAK_FILE="/tmp/xkeen-xray-fd-critical-streak"
XRAY_REMOTE_FIN_WAIT_STREAK_FILE="/tmp/xkeen-xray-remote-fin-wait-streak"
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

health_log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$HEALTH_LOG_PATH"
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

get_xray_pid() {
  pidof xray 2>/dev/null | /opt/bin/awk '{ print $1; exit }'
}

get_xray_remote_endpoint() {
  XRAY_REMOTE_HOST=""
  XRAY_REMOTE_PORT=0
  XRAY_REMOTE_IP=""

  if command -v jq >/dev/null 2>&1 && [ -f "$XRAY_CONF_DIR/04_outbounds.json" ]; then
    XRAY_REMOTE_HOST="$(jq -r '.outbounds[]? | select(.tag == "vless-reality") | .settings.vnext[0].address // empty' "$XRAY_CONF_DIR/04_outbounds.json" 2>/dev/null | head -n 1)"
    XRAY_REMOTE_PORT="$(jq -r '.outbounds[]? | select(.tag == "vless-reality") | .settings.vnext[0].port // 0' "$XRAY_CONF_DIR/04_outbounds.json" 2>/dev/null | head -n 1)"
  fi

  case "$XRAY_REMOTE_PORT" in
    ''|*[!0-9]*) XRAY_REMOTE_PORT=0 ;;
  esac

  if [ -n "$XRAY_REMOTE_HOST" ]; then
    XRAY_REMOTE_IP="$(nslookup "$XRAY_REMOTE_HOST" 2>/dev/null | /opt/bin/awk '
      /^Name:/ { seen_name=1; next }
      seen_name && /^Address [0-9]+: / { print $3; exit }
      seen_name && /^Address: / { print $2; exit }
    ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)"
  fi
}

capture_xray_remote_socket_metrics() {
  XRAY_REMOTE_TOTAL_COUNT=0
  XRAY_REMOTE_ESTABLISHED_COUNT=0
  XRAY_REMOTE_FIN_WAIT_COUNT=0

  [ -n "$XRAY_PID" ] || return 0
  [ "${XRAY_REMOTE_PORT:-0}" -gt 0 ] || return 0

  SOCKET_LINES="$(netstat -anp 2>/dev/null | grep "${XRAY_PID}/xray" | grep ":${XRAY_REMOTE_PORT} " || true)"
  [ -n "$SOCKET_LINES" ] || return 0

  XRAY_REMOTE_TOTAL_COUNT="$(printf '%s\n' "$SOCKET_LINES" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  XRAY_REMOTE_ESTABLISHED_COUNT="$(printf '%s\n' "$SOCKET_LINES" | grep -c 'ESTABLISHED' || true)"
  XRAY_REMOTE_FIN_WAIT_COUNT="$(printf '%s\n' "$SOCKET_LINES" | grep -E -c 'FIN_WAIT1|FIN_WAIT2' || true)"
}

capture_health_metrics() {
  XRAY_PID="$(get_xray_pid)"
  XRAY_FD_COUNT=0
  XRAY_FD_LIMIT=0
  XRAY_REMOTE_TOTAL_COUNT=0
  XRAY_REMOTE_ESTABLISHED_COUNT=0
  XRAY_REMOTE_FIN_WAIT_COUNT=0
  MEM_AVAILABLE_KB=0
  MEM_TOTAL_KB=0
  CONNTRACK_COUNT=0
  CONNTRACK_MAX=0
  HEALTH_PROBE_OK=0
  HEALTH_STATUS="ok"

  get_xray_remote_endpoint

  if [ -n "$XRAY_PID" ] && [ -d "/proc/$XRAY_PID/fd" ]; then
    XRAY_FD_COUNT="$(ls "/proc/$XRAY_PID/fd" 2>/dev/null | wc -l | tr -d ' ')"
    XRAY_FD_LIMIT="$(grep 'Max open files' "/proc/$XRAY_PID/limits" 2>/dev/null | /opt/bin/awk '{ print $4; exit }')"
    case "$XRAY_FD_LIMIT" in
      ''|unlimited) XRAY_FD_LIMIT=0 ;;
    esac
  fi

  MEM_AVAILABLE_KB="$(grep '^MemAvailable:' /proc/meminfo 2>/dev/null | /opt/bin/awk '{ print $2; exit }')"
  MEM_TOTAL_KB="$(grep '^MemTotal:' /proc/meminfo 2>/dev/null | /opt/bin/awk '{ print $2; exit }')"
  CONNTRACK_COUNT="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"
  CONNTRACK_MAX="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)"

  if [ -n "$XRAY_PID" ] && xray_ready; then
    HEALTH_PROBE_OK=1
  else
    HEALTH_PROBE_OK=0
  fi

  capture_xray_remote_socket_metrics

  if [ "${XRAY_FD_COUNT:-0}" -ge "$XRAY_FD_CRITICAL_THRESHOLD" ]; then
    HEALTH_STATUS="fd_critical"
    return 0
  fi
  if [ "${XRAY_FD_COUNT:-0}" -ge "$XRAY_FD_WARN_THRESHOLD" ]; then
    HEALTH_STATUS="fd_warn"
  fi

  if [ "${XRAY_REMOTE_FIN_WAIT_COUNT:-0}" -ge "$XRAY_REMOTE_FIN_WAIT_CRITICAL_THRESHOLD" ]; then
    HEALTH_STATUS="vpn_fin_critical"
    return 0
  fi
  if [ "${XRAY_REMOTE_FIN_WAIT_COUNT:-0}" -ge "$XRAY_REMOTE_FIN_WAIT_WARN_THRESHOLD" ] && [ "$HEALTH_STATUS" = "ok" ]; then
    HEALTH_STATUS="vpn_fin_warn"
  fi

  if [ "${CONNTRACK_MAX:-0}" -gt 0 ]; then
    CT_PCT=$(( CONNTRACK_COUNT * 100 / CONNTRACK_MAX ))
    if [ "$CT_PCT" -ge 95 ]; then
      HEALTH_STATUS="conntrack_critical"
      return 0
    fi
    if [ "$CT_PCT" -ge 85 ] && [ "$HEALTH_STATUS" = "ok" ]; then
      HEALTH_STATUS="conntrack_warn"
    fi
  fi

  if [ "${MEM_TOTAL_KB:-0}" -gt 0 ]; then
    MEM_AVAIL_PCT=$(( MEM_AVAILABLE_KB * 100 / MEM_TOTAL_KB ))
    if [ "$MEM_AVAIL_PCT" -le 5 ]; then
      HEALTH_STATUS="mem_critical"
      return 0
    fi
    if [ "$MEM_AVAIL_PCT" -le 10 ] && [ "$HEALTH_STATUS" = "ok" ]; then
      HEALTH_STATUS="mem_warn"
    fi
  fi
}

maybe_log_health() {
  NOW_TS="$(date +%s)"
  LAST_TS="$(cat "$HEALTH_STAMP_FILE" 2>/dev/null || echo 0)"

  if [ "$HEALTH_STATUS" != "ok" ] || [ $(( NOW_TS - LAST_TS )) -ge 300 ]; then
    health_log "status=$HEALTH_STATUS pid=${XRAY_PID:-0} probe=$HEALTH_PROBE_OK fd=${XRAY_FD_COUNT:-0}/${XRAY_FD_LIMIT:-0} mem_kb=${MEM_AVAILABLE_KB:-0}/${MEM_TOTAL_KB:-0} conntrack=${CONNTRACK_COUNT:-0}/${CONNTRACK_MAX:-0} vpn_remote=${XRAY_REMOTE_HOST:-unknown}:${XRAY_REMOTE_PORT:-0} vpn_sock=${XRAY_REMOTE_ESTABLISHED_COUNT:-0}/${XRAY_REMOTE_FIN_WAIT_COUNT:-0}/${XRAY_REMOTE_TOTAL_COUNT:-0}"
    printf '%s\n' "$NOW_TS" > "$HEALTH_STAMP_FILE"
  fi
}

update_fd_critical_streak() {
  STREAK=0
  if [ -f "$XRAY_FD_CRITICAL_STREAK_FILE" ]; then
    STREAK="$(cat "$XRAY_FD_CRITICAL_STREAK_FILE" 2>/dev/null || echo 0)"
  fi
  case "$STREAK" in
    ''|*[!0-9]*) STREAK=0 ;;
  esac

  if [ "$HEALTH_STATUS" = "fd_critical" ]; then
    STREAK=$((STREAK + 1))
    printf '%s\n' "$STREAK" > "$XRAY_FD_CRITICAL_STREAK_FILE"
  else
    rm -f "$XRAY_FD_CRITICAL_STREAK_FILE" 2>/dev/null || true
    STREAK=0
  fi

  XRAY_FD_CRITICAL_STREAK="$STREAK"
}

update_remote_fin_wait_streak() {
  STREAK=0
  if [ -f "$XRAY_REMOTE_FIN_WAIT_STREAK_FILE" ]; then
    STREAK="$(cat "$XRAY_REMOTE_FIN_WAIT_STREAK_FILE" 2>/dev/null || echo 0)"
  fi
  case "$STREAK" in
    ''|*[!0-9]*) STREAK=0 ;;
  esac

  if [ "$HEALTH_STATUS" = "vpn_fin_critical" ]; then
    STREAK=$((STREAK + 1))
    printf '%s\n' "$STREAK" > "$XRAY_REMOTE_FIN_WAIT_STREAK_FILE"
  else
    rm -f "$XRAY_REMOTE_FIN_WAIT_STREAK_FILE" 2>/dev/null || true
    STREAK=0
  fi

  XRAY_REMOTE_FIN_WAIT_STREAK="$STREAK"
}

restart_xray_allowed() {
  NOW_TS="$(date +%s)"
  LAST_TS="$(cat "$XRAY_RESTART_STAMP_FILE" 2>/dev/null || echo 0)"
  [ $(( NOW_TS - LAST_TS )) -ge 300 ]
}

mark_xray_restarted() {
  date +%s > "$XRAY_RESTART_STAMP_FILE"
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
  capture_health_metrics
  maybe_log_health
  update_fd_critical_streak
  update_remote_fin_wait_streak
  [ "$HEALTH_PROBE_OK" -eq 1 ] || needs_repair=1
  case "$HEALTH_STATUS" in
    mem_critical|conntrack_critical)
      needs_repair=1
      ;;
  esac
  if [ "$HEALTH_STATUS" = "fd_critical" ] && [ "${XRAY_FD_CRITICAL_STREAK:-0}" -ge "$XRAY_FD_CRITICAL_STREAK_REQUIRED" ]; then
    needs_repair=1
  fi
  if [ "$HEALTH_STATUS" = "vpn_fin_critical" ] && [ "${XRAY_REMOTE_FIN_WAIT_STREAK:-0}" -ge "$XRAY_REMOTE_FIN_WAIT_STREAK_REQUIRED" ]; then
    needs_repair=1
  fi
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
  health_log "action=xray_restart reason=$HEALTH_STATUS pid=${XRAY_PID:-0} fd=${XRAY_FD_COUNT:-0}/${XRAY_FD_LIMIT:-0} mem_kb=${MEM_AVAILABLE_KB:-0}/${MEM_TOTAL_KB:-0} conntrack=${CONNTRACK_COUNT:-0}/${CONNTRACK_MAX:-0}"
  killall xray 2>/dev/null || true
  rm -f /opt/var/run/xray-ui.pid /opt/var/run/xray.pid 2>/dev/null || true
  sleep 2
  XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" XRAY_LOCATION_CONFDIR="$XRAY_CONF_DIR" \
    /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/xray-ui.pid -x "$XRAY_BIN" -- run >>"$LOG_PATH" 2>&1
  mark_xray_restarted
  sleep 3
}

repair_runtime() {
  log "repair start"

  if ! cron_running; then
    CRON_INIT="$(find_cron_init 2>/dev/null || true)"
    [ -n "$CRON_INIT" ] && "$CRON_INIT" restart >/dev/null 2>&1 || true
  fi

  repair_hooks

  capture_health_metrics
  maybe_log_health

  if ! xray_ready; then
    log "xray restart needed"
    restart_xray
  elif [ "$HEALTH_STATUS" = "fd_critical" ] || [ "$HEALTH_STATUS" = "vpn_fin_critical" ]; then
    if restart_xray_allowed; then
      log "xray deep health restart needed: $HEALTH_STATUS"
      restart_xray
    else
      health_log "action=xray_restart_skipped reason=$HEALTH_STATUS cooldown=active"
    fi
  fi

  capture_health_metrics
  maybe_log_health

  if xray_ready && [ "$HEALTH_PROBE_OK" -eq 1 ]; then
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
