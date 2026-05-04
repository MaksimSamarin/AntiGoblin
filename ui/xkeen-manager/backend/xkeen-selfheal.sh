#!/bin/sh

PATH="/opt/bin:/opt/sbin:/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

LOG_PATH="/opt/var/log/xkeen-selfheal.log"
HEALTH_LOG_PATH="/opt/var/log/xkeen-health.log"
XRAY_BIN="/opt/sbin/xray"
SING_BOX_BIN="/opt/sbin/sing-box"
SING_BOX_INIT="/opt/etc/init.d/S24antigoblin-singbox"
XRAY_ASSET_DIR="/opt/etc/xray/dat"
XRAY_CONF_DIR="/opt/etc/xray/configs"
SING_BOX_CONF="/opt/etc/sing-box/xkeen.json"
STATE_PATH="/opt/share/xkeen-manager/xkeen-ui-state.json"
LOCK_DIR="/tmp/xkeen-selfheal.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
HEALTH_STAMP_FILE="/tmp/xkeen-health-last.ts"
XRAY_RESTART_STAMP_FILE="/tmp/xkeen-xray-restart-last.ts"
RUNTIME_REFRESH_STAMP_FILE="/tmp/xkeen-runtime-refresh-last.ts"
RUNTIME_REFRESH_INTERVAL_SEC=300
LOG_ROTATE_INTERVAL_SEC=86400
LOG_ROTATE_STAMP_FILE="/tmp/xkeen-log-rotate-last.ts"
RUNTIME_DIR="/opt/share/xkeen-manager/runtime"
UDP_ROUTE_SET="xkeen_udp_route"
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
XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT=0
XRAY_REMOTE_FIN_WAIT_WARN_THRESHOLD=20
XRAY_REMOTE_FIN_WAIT_CRITICAL_THRESHOLD=50
XRAY_REMOTE_FIN_WAIT_STREAK_REQUIRED=3
XRAY_REMOTE_ORPHAN_FIN_CRITICAL_THRESHOLD=30
MEM_AVAILABLE_KB=0
MEM_TOTAL_KB=0
CONNTRACK_COUNT=0
CONNTRACK_MAX=0
HEALTH_PROBE_OK=0
HEALTH_STATUS="ok"
XRAY_FD_CRITICAL_STREAK_FILE="/tmp/xkeen-xray-fd-critical-streak"
XRAY_REMOTE_FIN_WAIT_STREAK_FILE="/tmp/xkeen-xray-remote-fin-wait-streak"

XKEEN_RUNTIME_LOG="$LOG_PATH"
if [ -f "/opt/share/xkeen-manager/api/xkeen-runtime.sh" ]; then
  . "/opt/share/xkeen-manager/api/xkeen-runtime.sh"
elif [ -f "$(dirname "$0")/xkeen-runtime.sh" ]; then
  . "$(dirname "$0")/xkeen-runtime.sh"
fi

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
runtime_refresh_due=0

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
  type xkeen_get_mark >/dev/null 2>&1 && xkeen_get_mark
}

get_default_wan_iface() {
  type xkeen_default_wan_iface >/dev/null 2>&1 && xkeen_default_wan_iface
}

next_xkeen_policy_name() {
  type xkeen_next_policy_name >/dev/null 2>&1 && xkeen_next_policy_name
}

ensure_xkeen_policy() {
  type xkeen_ensure_policy >/dev/null 2>&1 && xkeen_ensure_policy
}

ensure_xkeen_mark() {
  type xkeen_ensure_mark >/dev/null 2>&1 || return 1
  xkeen_ensure_mark
}

xray_ready() {
  netstat -lnpt 2>/dev/null | grep -q ':61219 '
}

xray_relay_ready() {
  netstat -lnpt 2>/dev/null | grep -q ':62640 '
}

singbox_ready() {
  [ -x "$SING_BOX_BIN" ] || return 1
  [ -f "$SING_BOX_CONF" ] || return 1
  if type xkeen_tproxy_ready >/dev/null 2>&1; then
    xkeen_tproxy_ready
    return $?
  fi
  netstat -lnpu 2>/dev/null | grep -q ':61221 '
}

tproxy_ready() {
  singbox_ready
}

ensure_tproxy_module() {
  type xkeen_ensure_tproxy_module >/dev/null 2>&1 && xkeen_ensure_tproxy_module
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
  XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT=0

  [ -n "$XRAY_PID" ] || return 0
  [ "${XRAY_REMOTE_PORT:-0}" -gt 0 ] || return 0

  if [ -n "$XRAY_REMOTE_IP" ]; then
    XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT="$(netstat -anp 2>/dev/null | grep "${XRAY_REMOTE_IP}:${XRAY_REMOTE_PORT}" | grep -E 'FIN_WAIT1|FIN_WAIT2' | grep -c '[[:space:]]-[[:space:]]*$' || true)"
  fi

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
  XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT=0
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

  if [ "${XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT:-0}" -ge "$XRAY_REMOTE_ORPHAN_FIN_CRITICAL_THRESHOLD" ]; then
    HEALTH_STATUS="vpn_orphan_fin_critical"
    return 0
  fi
  if [ "${XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT:-0}" -ge "$XRAY_REMOTE_FIN_WAIT_WARN_THRESHOLD" ] && [ "$HEALTH_STATUS" = "ok" ]; then
    HEALTH_STATUS="vpn_orphan_fin_warn"
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
    health_log "status=$HEALTH_STATUS pid=${XRAY_PID:-0} probe=$HEALTH_PROBE_OK fd=${XRAY_FD_COUNT:-0}/${XRAY_FD_LIMIT:-0} mem_kb=${MEM_AVAILABLE_KB:-0}/${MEM_TOTAL_KB:-0} conntrack=${CONNTRACK_COUNT:-0}/${CONNTRACK_MAX:-0} vpn_remote=${XRAY_REMOTE_HOST:-unknown}:${XRAY_REMOTE_PORT:-0} vpn_ip=${XRAY_REMOTE_IP:-unknown} vpn_sock=${XRAY_REMOTE_ESTABLISHED_COUNT:-0}/${XRAY_REMOTE_FIN_WAIT_COUNT:-0}/${XRAY_REMOTE_TOTAL_COUNT:-0} vpn_orphan_fin=${XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT:-0}"
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

check_runtime_refresh_due() {
  NOW_TS="$(date +%s)"
  LAST_TS="$(cat "$RUNTIME_REFRESH_STAMP_FILE" 2>/dev/null || echo 0)"
  if [ $(( NOW_TS - LAST_TS )) -ge "$RUNTIME_REFRESH_INTERVAL_SEC" ]; then
    runtime_refresh_due=1
    needs_repair=1
  fi
}

mark_runtime_refreshed() {
  date +%s > "$RUNTIME_REFRESH_STAMP_FILE"
}

rotate_log_if_large() {
  FILE="$1"
  MAX_BYTES="$2"
  [ -f "$FILE" ] || return 0
  SIZE="$(wc -c < "$FILE" 2>/dev/null)"
  case "$SIZE" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ "$SIZE" -gt "$MAX_BYTES" ] || return 0
  KEEP_BYTES=$((MAX_BYTES / 2))
  TMP="${FILE}.rotate.tmp"
  if tail -c "$KEEP_BYTES" "$FILE" > "$TMP" 2>/dev/null && mv "$TMP" "$FILE" 2>/dev/null; then
    health_log "action=log_rotate file=$FILE old_size=$SIZE new_size=$KEEP_BYTES"
  else
    rm -f "$TMP" 2>/dev/null || true
  fi
}

maybe_rotate_logs() {
  NOW_TS="$(date +%s)"
  LAST_TS="$(cat "$LOG_ROTATE_STAMP_FILE" 2>/dev/null || echo 0)"
  case "$LAST_TS" in
    ''|*[!0-9]*) LAST_TS=0 ;;
  esac
  [ $((NOW_TS - LAST_TS)) -ge "$LOG_ROTATE_INTERVAL_SEC" ] || return 0

  rotate_log_if_large "/opt/var/log/xray-manual.log"     20971520
  rotate_log_if_large "/opt/var/log/sing-box-xkeen.log"   5242880
  rotate_log_if_large "/opt/var/log/xkeen-selfheal.log"   5242880
  rotate_log_if_large "/opt/var/log/xkeen-health.log"    10485760
  rotate_log_if_large "/opt/var/log/xkeen-sysctl.log"     1048576

  trim_backups "/opt/etc/xray/configs"            "*.bak-ui-*" 5
  trim_backups "/opt/share/xkeen-manager"         "xkeen-ui-state.json.bak-ui-*" 5

  printf '%s\n' "$NOW_TS" > "$LOG_ROTATE_STAMP_FILE"
}

# Keep only the N most recent backup files matching <pattern> in <dir>.
# Older ones get removed. Used to stop *.bak-ui-* from accumulating
# unbounded after every UI save.
trim_backups() {
  DIR="$1"
  PATTERN="$2"
  KEEP="$3"
  [ -d "$DIR" ] || return 0
  case "$KEEP" in
    ''|*[!0-9]*) return 0 ;;
  esac
  # shellcheck disable=SC2012
  REMOVED=0
  ls -t "$DIR"/$PATTERN 2>/dev/null | tail -n +"$((KEEP + 1))" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    rm -f "$f" 2>/dev/null && REMOVED=$((REMOVED + 1))
  done
  COUNT="$(ls "$DIR"/$PATTERN 2>/dev/null | wc -l | tr -d ' ')"
  health_log "action=trim_backups dir=$DIR pattern=$PATTERN keep=$KEEP remaining=$COUNT"
}

flush_vpn_conntrack() {
  get_xray_remote_endpoint
  [ -n "$XRAY_REMOTE_IP" ] || return 0
  [ "${XRAY_REMOTE_PORT:-0}" -gt 0 ] || return 0

  if ! command -v conntrack >/dev/null 2>&1; then
    health_log "action=conntrack_flush_skipped reason=missing_conntrack_tools vpn_ip=$XRAY_REMOTE_IP vpn_port=$XRAY_REMOTE_PORT"
    return 0
  fi

  conntrack -D -p tcp -d "$XRAY_REMOTE_IP" --dport "$XRAY_REMOTE_PORT" >/dev/null 2>&1 || true
  conntrack -D -p tcp -s "$XRAY_REMOTE_IP" --sport "$XRAY_REMOTE_PORT" >/dev/null 2>&1 || true
  health_log "action=conntrack_flush vpn_ip=$XRAY_REMOTE_IP vpn_port=$XRAY_REMOTE_PORT"
}

udp_route_config_enabled() {
  type xkeen_udp_config_enabled >/dev/null 2>&1 && xkeen_udp_config_enabled
}

udp_route_has_entries() {
  type xkeen_ipset_has_members >/dev/null 2>&1 && xkeen_ipset_has_members "$UDP_ROUTE_SET"
}

apply_udp_route() {
  type xkeen_apply_udp_route >/dev/null 2>&1 && xkeen_apply_udp_route
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
  if has_rule iptables -t filter -S xkeen_udp443_block; then
    needs_repair=1
  fi
  if udp_route_config_enabled && ! has_rule ipset list "$UDP_ROUTE_SET"; then
    needs_repair=1
  fi
  if has_rule ipset list "$UDP_ROUTE_SET" && udp_route_has_entries; then
    [ -n "$XKEEN_MARK" ] && has_rule iptables -t mangle -C PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -p udp -m set --match-set "$UDP_ROUTE_SET" dst -j xkeen_udp_route || needs_repair=1
    iptables -t mangle -S PREROUTING 2>/dev/null | tail -n 1 | grep -q 'xkeen_udp_route' || needs_repair=1
    ip rule show | grep -qE 'fwmark 0x111/0x111 (lookup|table) 111' || needs_repair=1
    xray_relay_ready || needs_repair=1
    tproxy_ready || needs_repair=1
  fi
  xray_ready || needs_repair=1
  capture_health_metrics
  maybe_log_health
  update_fd_critical_streak
  update_remote_fin_wait_streak
  check_runtime_refresh_due
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
  if [ "$HEALTH_STATUS" = "vpn_orphan_fin_critical" ]; then
    needs_repair=1
  fi
}

repair_hooks() {
  if type xkeen_repair_hooks >/dev/null 2>&1; then
    xkeen_repair_hooks
    XKEEN_MARK="$(xkeen_get_mark 2>/dev/null || printf '%s' "$XKEEN_MARK")"
    return $?
  fi

  log "repair failed: xkeen-runtime.sh is not loaded"
  return 1
}

dump_xray_diagnostics() {
  [ -n "$XRAY_PID" ] || return 0
  TS="$(date '+%Y%m%d-%H%M%S')"
  DUMP_FILE="/opt/var/log/xray-fd-dump-${TS}.txt"
  {
    printf '=== xray fd diagnostic snapshot %s ===\n' "$TS"
    printf 'trigger: %s\n' "${HEALTH_STATUS:-unknown}"
    printf 'pid: %s\n' "${XRAY_PID:-0}"
    printf 'fd: %s/%s (warn=%s critical=%s)\n' "${XRAY_FD_COUNT:-0}" "${XRAY_FD_LIMIT:-0}" "$XRAY_FD_WARN_THRESHOLD" "$XRAY_FD_CRITICAL_THRESHOLD"
    printf 'mem_kb: %s/%s\n' "${MEM_AVAILABLE_KB:-0}" "${MEM_TOTAL_KB:-0}"
    printf 'conntrack: %s/%s\n' "${CONNTRACK_COUNT:-0}" "${CONNTRACK_MAX:-0}"
    printf 'vpn_remote: %s:%s (%s)\n' "${XRAY_REMOTE_HOST:-unknown}" "${XRAY_REMOTE_PORT:-0}" "${XRAY_REMOTE_IP:-unknown}"
    printf 'vpn_sock: established=%s fin_wait=%s orphan_fin=%s total=%s\n' \
      "${XRAY_REMOTE_ESTABLISHED_COUNT:-0}" \
      "${XRAY_REMOTE_FIN_WAIT_COUNT:-0}" \
      "${XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT:-0}" \
      "${XRAY_REMOTE_TOTAL_COUNT:-0}"
    printf '\n=== TCP socket states for xray (per state count) ===\n'
    netstat -anp 2>/dev/null | grep "${XRAY_PID}/xray" | /opt/bin/awk '$1 == "tcp" || $1 == "tcp6" { print $6 }' | sort | uniq -c | sort -rn
    printf '\n=== TCP sockets to VPN remote (full) ===\n'
    if [ -n "$XRAY_REMOTE_IP" ]; then
      netstat -anp 2>/dev/null | grep "${XRAY_PID}/xray" | grep "${XRAY_REMOTE_IP}:${XRAY_REMOTE_PORT}" | head -200
    else
      printf '(vpn remote ip unknown)\n'
    fi
    printf '\n=== All xray TCP sockets (top 200 by recency) ===\n'
    netstat -anp 2>/dev/null | grep "${XRAY_PID}/xray" | head -200
    printf '\n=== Last 40 xray-manual.log lines ===\n'
    tail -n 40 "$LOG_PATH" 2>/dev/null
  } > "$DUMP_FILE" 2>&1

  ls -t /opt/var/log/xray-fd-dump-*.txt 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
  health_log "action=fd_dump file=$DUMP_FILE trigger=$HEALTH_STATUS fd=${XRAY_FD_COUNT:-0}/${XRAY_FD_LIMIT:-0} vpn_sock=${XRAY_REMOTE_ESTABLISHED_COUNT:-0}/${XRAY_REMOTE_FIN_WAIT_COUNT:-0}/${XRAY_REMOTE_TOTAL_COUNT:-0}"
}

restart_xray() {
  health_log "action=xray_restart reason=$HEALTH_STATUS pid=${XRAY_PID:-0} fd=${XRAY_FD_COUNT:-0}/${XRAY_FD_LIMIT:-0} mem_kb=${MEM_AVAILABLE_KB:-0}/${MEM_TOTAL_KB:-0} conntrack=${CONNTRACK_COUNT:-0}/${CONNTRACK_MAX:-0} vpn_remote=${XRAY_REMOTE_HOST:-unknown}:${XRAY_REMOTE_PORT:-0} vpn_ip=${XRAY_REMOTE_IP:-unknown} vpn_sock=${XRAY_REMOTE_ESTABLISHED_COUNT:-0}/${XRAY_REMOTE_FIN_WAIT_COUNT:-0}/${XRAY_REMOTE_TOTAL_COUNT:-0} vpn_orphan_fin=${XRAY_REMOTE_ORPHAN_FIN_WAIT_COUNT:-0}"

  case "$HEALTH_STATUS" in
    fd_critical|fd_warn|vpn_fin_critical|vpn_fin_warn|vpn_orphan_fin_warn|vpn_orphan_fin_critical)
      dump_xray_diagnostics
      ;;
  esac

  killall xray 2>/dev/null || true
  rm -f /opt/var/run/xray-ui.pid /opt/var/run/xray.pid 2>/dev/null || true
  sleep 2
  flush_vpn_conntrack
  XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" XRAY_LOCATION_CONFDIR="$XRAY_CONF_DIR" \
    /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/xray-ui.pid -x "$XRAY_BIN" -- run >>"$LOG_PATH" 2>&1
  mark_xray_restarted
  sleep 3
}

restart_singbox() {
  health_log "action=singbox_restart reason=$HEALTH_STATUS"
  if [ -x "$SING_BOX_INIT" ]; then
    "$SING_BOX_INIT" restart >>"$LOG_PATH" 2>&1 || true
  else
    killall sing-box 2>/dev/null || true
    rm -f /opt/var/run/sing-box.pid 2>/dev/null || true
    sleep 1
    [ -x "$SING_BOX_BIN" ] && [ -f "$SING_BOX_CONF" ] && \
      /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/sing-box.pid -x "$SING_BOX_BIN" -- run -c "$SING_BOX_CONF" >>"$LOG_PATH" 2>&1 || true
  fi
  sleep 2
}

repair_runtime() {
  log "repair start"
  [ "$runtime_refresh_due" -eq 1 ] && log "runtime refresh scheduled"

  if ! cron_running; then
    CRON_INIT="$(find_cron_init 2>/dev/null || true)"
    [ -n "$CRON_INIT" ] && "$CRON_INIT" restart >/dev/null 2>&1 || true
  fi

  if ! repair_hooks; then
    log "repair failed: runtime hooks"
    return 1
  fi
  mark_runtime_refreshed

  capture_health_metrics
  maybe_log_health

  if ! xray_ready || (has_rule ipset list "$UDP_ROUTE_SET" && udp_route_has_entries && ! xray_relay_ready); then
    log "xray restart needed"
    restart_xray
  elif has_rule ipset list "$UDP_ROUTE_SET" && udp_route_has_entries && ! tproxy_ready; then
    log "sing-box tproxy restart needed"
    restart_singbox
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

maybe_rotate_logs

check_runtime

if [ "$force_mode" -eq 1 ] || [ "$needs_repair" -eq 1 ]; then
  repair_runtime
  exit $?
fi

exit 0
