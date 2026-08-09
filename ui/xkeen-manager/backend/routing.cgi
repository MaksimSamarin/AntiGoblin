#!/bin/sh

PATH="/opt/bin:/opt/sbin:/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

ROUTING_PATH="/opt/etc/xray/configs/05_routing.json"
OUTBOUNDS_PATH="/opt/etc/xray/configs/04_outbounds.json"
STATE_PATH="/opt/share/xkeen-manager/xkeen-ui-state.json"
# Per-PID scratch paths. Two concurrent CGI processes MUST NOT share
# these — read_body writes to TMP_BODY BEFORE acquire_apply_lock, so if
# both used a fixed path client B would overwrite client A's body, and
# A (after taking the lock) would then `cp $TMP_BODY $STATE_PATH` and
# persist B's data under A's response. Same class of race exists for
# TMP_NEW/TMP_STATE. The $$ suffix makes each process self-contained.
TMP_BODY="/tmp/xkeen-routing-body-$$.json"
TMP_NEW="/tmp/xkeen-routing-new-$$.json"
TMP_STATE="/tmp/xkeen-state-new-$$.json"
TMP_AUTH_HEADERS="/tmp/xkeen-auth-headers-$$.txt"
LOG_PATH="/opt/var/log/xray-manual.log"
XRAY_BIN="/opt/sbin/xray"
SELFHEAL_PATH="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"
TMP_RESTART_SCRIPT="/tmp/xkeen-apply-restart.sh"
RUNTIME_DIR="/opt/share/xkeen-manager/runtime"
XKEEN_MARK=""

XKEEN_RUNTIME_LOG="$LOG_PATH"
if [ -f "/opt/share/xkeen-manager/api/xkeen-runtime.sh" ]; then
  . "/opt/share/xkeen-manager/api/xkeen-runtime.sh"
elif [ -f "$(dirname "$0")/xkeen-runtime.sh" ]; then
  . "$(dirname "$0")/xkeen-runtime.sh"
fi

json_ok() {
  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  printf '%s\n' "$1"
}

json_err() {
  printf 'Status: 500 Internal Server Error\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  printf '{"ok":false,"error":"%s"}\n' "$1"
}

json_unauthorized() {
  printf 'Status: 401 Unauthorized\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  printf '{"ok":false,"error":"router ui authorization required"}\n'
}

json_invalid_credentials() {
  printf 'Status: 401 Unauthorized\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  printf '{"ok":false,"error":"invalid router credentials"}\n'
}

read_body() {
  # Cap request bodies. uhttpd forwards CONTENT_LENGTH bytes into stdin,
  # so an authenticated attacker sending CONTENT_LENGTH=500MB would fill
  # /tmp (tmpfs) and OOM the router. Reject early on the declared header,
  # and use `head -c` as a belt-and-suspenders limit if the header lied.
  MAX_BODY=524288
  DECLARED="${CONTENT_LENGTH:-0}"
  case "$DECLARED" in ''|*[!0-9]*) DECLARED=0 ;; esac
  if [ "$DECLARED" -gt "$MAX_BODY" ]; then
    printf 'Status: 413 Payload Too Large\r\n'
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf '\r\n'
    printf '{"ok":false,"error":"body too large (%s > %s bytes)"}\n' "$DECLARED" "$MAX_BODY"
    exit 0
  fi
  head -c "$MAX_BODY" > "$TMP_BODY"
}

# Parse HTTP Host header, stripping the port. Handles both plain hosts
# (`192.168.1.1:8899`) and bracketed IPv6 literals (`[fdxx::1]:8899` →
# `[fdxx::1]`). Plain `sed 's/:.*$//'` on the IPv6 form would leave `[`.
strip_host_port() {
  case "$1" in
    '')           printf '%s' "192.168.1.1" ;;
    '['*']:'*)    printf '%s' "${1%%]:*}]" ;;
    '['*']')      printf '%s' "$1" ;;
    *:*)          printf '%s' "${1%:*}" ;;
    *)            printf '%s' "$1" ;;
  esac
}

# Router auth endpoint (host used for wget http://…/auth calls).
# NEVER derived from HTTP_HOST — the client controls that header, so an
# attacker on LAN could set `Host: attacker.tld` and steer the session
# check to a server they own that replies "HTTP/1.1 200 OK" to any
# request, bypassing router auth entirely. Same channel also carries the
# challenge/password-hash exchange during login → offline brute-force.
# Resolution order:
#   1. ROUTER_AUTH_HOST in /opt/etc/antigoblin.conf (operator override,
#      hostname or bracketed IPv6; awk-validated, no `source`).
#   2. xkeen_lan_ip — LAN-side address of this Keenetic (already excludes
#      the WAN interface in double-NAT setups).
#   3. Hard fallback 192.168.1.1 (Keenetic factory default).
router_auth_endpoint() {
  if [ -f /opt/etc/antigoblin.conf ]; then
    OVERRIDE="$(/opt/bin/awk -F= '
      $1 == "ROUTER_AUTH_HOST" && $2 ~ /^[A-Za-z0-9._:\[\]-]+$/ {
        print $2; exit
      }
    ' /opt/etc/antigoblin.conf 2>/dev/null)"
    if [ -n "$OVERRIDE" ]; then
      printf '%s' "$OVERRIDE"
      return 0
    fi
  fi
  LAN="$(xkeen_lan_ip 2>/dev/null)"
  if [ -n "$LAN" ]; then
    printf '%s' "$LAN"
    return 0
  fi
  printf '%s' "192.168.1.1"
}

# Cross-process apply lock shared with selfheal. Uses xkeen_lock_acquire
# from xkeen-runtime.sh (PID-recycle-safe + race-window-safe). Wall-clock
# capped at 60s — well below uhttpd's `-t 120` CGI timeout, so the client
# gets a clean 503 instead of a 502 Bad Gateway from uhttpd cutting the
# CGI process mid-flight.
acquire_apply_lock() {
  deadline=$(( $(date +%s) + 60 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if xkeen_lock_acquire; then
      trap 'xkeen_lock_release' EXIT INT TERM
      return 0
    fi
    sleep 1
  done
  return 1
}

require_apply_lock() {
  if ! acquire_apply_lock; then
    printf 'Status: 503 Service Unavailable\r\n'
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf '\r\n'
    printf '{"ok":false,"error":"apply lock busy; another apply or selfheal cycle in progress"}\n'
    rm -f "$TMP_BODY" 2>/dev/null || true
    exit 0
  fi
}

restart_xray() {
  type xkeen_ensure_socks_inbound_ip >/dev/null 2>&1 && xkeen_ensure_socks_inbound_ip
  # Graceful stop first: wait for the old xray to actually exit before
  # starting a new one. Old code did `killall xray; sleep 2` which can
  # leave the previous process still holding :61219 when a new one tries
  # to bind, especially at high fd count (the very scenario UI-restart is
  # meant to recover from).
  OLD_XRAY_PID="$(get_xray_pid 2>/dev/null)"
  killall xray 2>/dev/null || true
  if [ -n "$OLD_XRAY_PID" ]; then
    j=0
    while [ $j -lt 8 ] && kill -0 "$OLD_XRAY_PID" 2>/dev/null; do
      sleep 1
      j=$((j + 1))
    done
    # PID may have been recycled during the poll window (BusyBox has a
    # small PID space and short-lived sh scripts churn PIDs fast). Only
    # SIGKILL if the process still identifies as xray.
    if kill -0 "$OLD_XRAY_PID" 2>/dev/null; then
      CMDLINE="$(tr '\0' ' ' < "/proc/$OLD_XRAY_PID/cmdline" 2>/dev/null || true)"
      case "$CMDLINE" in
        *xray*) kill -9 "$OLD_XRAY_PID" 2>/dev/null || true ;;
      esac
    fi
  else
    sleep 2
  fi
  rm -f /opt/var/run/xray-ui.pid /opt/var/run/xray.pid 2>/dev/null || true
  XRAY_LOCATION_ASSET=/opt/etc/xray/dat XRAY_LOCATION_CONFDIR=/opt/etc/xray/configs \
    /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/xray-ui.pid -x "$XRAY_BIN" -- run >>"$LOG_PATH" 2>&1
  # Poll for :61219 instead of a fixed sleep. Capped at ~12s for slow flash.
  i=0
  while [ $i -lt 12 ]; do
    if netstat -lnpt 2>/dev/null | grep -q ':61219 '; then
      # A UI-driven restart also counts as a real restart from selfheal's
      # perspective: publish the stamp AND clear any streak/backoff state
      # that selfheal was tracking for auto-restarts. Also clear the
      # "please restart xray" sentinel so selfheal doesn't do a redundant
      # second restart on its next tick.
      date +%s > /tmp/xkeen-xray-restart-last.ts 2>/dev/null || true
      rm -f /tmp/xkeen-xray-start-fail-streak /tmp/xkeen-xray-start-backoff.ts /tmp/xkeen-needs-xray-restart 2>/dev/null || true
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  return 1
}

validate_confdir() {
  /opt/sbin/xray run -test -confdir /opt/etc/xray/configs >/dev/null 2>&1
}

get_xray_pid() {
  PID="$(netstat -lnpt 2>/dev/null | /opt/bin/awk '/:61219 / && /\/xray/ { split($NF, p, "/"); print p[1]; exit }')"
  [ -n "$PID" ] && { printf '%s\n' "$PID"; return 0; }

  for PID in $(pidof xray 2>/dev/null); do
    CMDLINE="$(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null || true)"
    case "$CMDLINE" in
      *" -test "*) continue ;;
    esac
    printf '%s\n' "$PID"
    return 0
  done
}

repair_runtime() {
  # We are called with acquire_apply_lock already held (POST branch).
  # DO NOT fork selfheal --force here — it will try to grab the same
  # shared lock, see our PID owning it (comm=`sh`), consider us alive,
  # and quietly exit 0 without doing any repair. The UI would then get
  # {"ok":true} while the runtime is untouched. Run the repair inline
  # under our own lock instead.
  if type xkeen_repair_hooks >/dev/null 2>&1; then
    xkeen_repair_hooks || return 1
    restart_xray || return 1
    return 0
  fi

  # Fallback if xkeen-runtime.sh could not be sourced. This path is only
  # reachable when the CGI itself isn't holding a lock (i.e. never today),
  # so it's safe to fork the selfheal here.
  if [ -x "$SELFHEAL_PATH" ]; then
    "$SELFHEAL_PATH" --force >/dev/null 2>&1
    return $?
  fi

  return 1
}

get_kind() {
  case "$QUERY_STRING" in
    kind=state|*'&kind=state'|kind=state'&'*)
      printf 'state'
      ;;
    kind=repair-runtime|*'&kind=repair-runtime'|kind=repair-runtime'&'*)
      printf 'repair-runtime'
      ;;
    kind=login|*'&kind=login'|kind=login'&'*)
      printf 'login'
      ;;
    kind=logout|*'&kind=logout'|kind=logout'&'*)
      printf 'logout'
      ;;
    kind=outbounds|*'&kind=outbounds'|kind=outbounds'&'*)
      printf 'outbounds'
      ;;
    kind=probe|*'&kind=probe'|kind=probe'&'*)
      printf 'probe'
      ;;
    kind=health|*'&kind=health'|kind=health'&'*)
      printf 'health'
      ;;
    kind=logs|*'&kind=logs'|kind=logs'&'*)
      printf 'logs'
      ;;
    kind=restart-svc|*'&kind=restart-svc'|kind=restart-svc'&'*)
      printf 'restart-svc'
      ;;
    kind=stack-info|*'&kind=stack-info'|kind=stack-info'&'*)
      printf 'stack-info'
      ;;
    kind=subscription-fetch|*'&kind=subscription-fetch'|kind=subscription-fetch'&'*)
      printf 'subscription-fetch'
      ;;
    kind=singbox|*'&kind=singbox'|kind=singbox'&'*)
      printf 'singbox'
      ;;
    *)
      printf 'routing'
      ;;
  esac
}

parse_qs_param() {
  PARAM_NAME="$1"
  printf '%s' "${QUERY_STRING:-}" | /opt/bin/awk -v want="$PARAM_NAME" '
    {
      count=split($0, parts, "&")
      for (i=1; i<=count; i++) {
        eqpos=index(parts[i], "=")
        if (eqpos == 0) continue
        key=substr(parts[i], 1, eqpos-1)
        val=substr(parts[i], eqpos+1)
        if (key == want) { print val; exit }
      }
    }
  '
}

emit_health() {
  XRAY_PID="$(get_xray_pid)"
  SB_PID="$(pidof sing-box 2>/dev/null | /opt/bin/awk '{ print $1 }')"
  SELFHEAL_PID="$(cat /opt/var/run/antigoblin-selfheal-loop.pid 2>/dev/null | /opt/bin/awk 'NR==1 && $0 ~ /^[0-9]+$/ { print }')"
  if [ -n "$SELFHEAL_PID" ] && ! kill -0 "$SELFHEAL_PID" 2>/dev/null; then
    SELFHEAL_PID=""
  fi

  XRAY_TCP_OK=0
  netstat -lnpt 2>/dev/null | grep -q ':61219 ' && XRAY_TCP_OK=1
  XRAY_RELAY_OK=0
  netstat -lnpu 2>/dev/null | grep -q '127.0.0.1:62640 ' && XRAY_RELAY_OK=1
  SB_LISTEN_OK=0
  netstat -lnpu 2>/dev/null | grep -q ':61221 ' && SB_LISTEN_OK=1

  TPROXY_AT_END=0
  iptables -t mangle -S PREROUTING 2>/dev/null | tail -1 | grep -q 'xkeen_udp_route' && TPROXY_AT_END=1
  IP_RULE_MASKED=0
  ip rule show 2>/dev/null | grep -qE 'fwmark 0x111/0x111 (lookup|table) 111' && IP_RULE_MASKED=1
  UDP_IPSET_OK=0
  ipset list xkeen_udp_route -terse >/dev/null 2>&1 && UDP_IPSET_OK=1
  BYPASS_IPSET_OK=0
  ipset list xkeen_bypass -terse >/dev/null 2>&1 && BYPASS_IPSET_OK=1

  UDP_IPSET_SIZE=0
  if [ "$UDP_IPSET_OK" = "1" ]; then
    UDP_IPSET_SIZE="$(ipset list xkeen_udp_route 2>/dev/null | /opt/bin/awk '/^Members:/ { m=1; next } m && NF { c++ } END { print c+0 }')"
  fi
  BYPASS_IPSET_SIZE=0
  if [ "$BYPASS_IPSET_OK" = "1" ]; then
    BYPASS_IPSET_SIZE="$(ipset list xkeen_bypass 2>/dev/null | /opt/bin/awk '/^Members:/ { m=1; next } m && NF { c++ } END { print c+0 }')"
  fi

  # FD count
  XRAY_FD=0
  XRAY_FD_LIMIT=0
  if [ -n "$XRAY_PID" ] && [ -d "/proc/$XRAY_PID/fd" ]; then
    XRAY_FD="$(ls "/proc/$XRAY_PID/fd" 2>/dev/null | wc -l | tr -d ' ')"
    XRAY_FD_LIMIT="$(grep 'Max open files' "/proc/$XRAY_PID/limits" 2>/dev/null | /opt/bin/awk '{ print $4; exit }')"
    case "$XRAY_FD_LIMIT" in ''|unlimited) XRAY_FD_LIMIT=0 ;; esac
  fi
  case "$XRAY_FD"       in ''|*[!0-9]*) XRAY_FD=0 ;; esac
  case "$XRAY_FD_LIMIT" in ''|*[!0-9]*) XRAY_FD_LIMIT=0 ;; esac

  # Conntrack
  CT_COUNT="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"
  CT_MAX="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)"
  case "$CT_COUNT" in ''|*[!0-9]*) CT_COUNT=0 ;; esac
  case "$CT_MAX"   in ''|*[!0-9]*) CT_MAX=0 ;; esac

  # VPN socket metrics
  VPN_HOST=""
  VPN_PORT=0
  VPN_IP=""
  VPN_ESTABLISHED=0
  VPN_FIN_WAIT=0
  VPN_ORPHAN_FIN=0
  VPN_TOTAL=0
  if [ -f /opt/etc/xray/configs/04_outbounds.json ] && command -v /opt/bin/jq >/dev/null 2>&1; then
    VPN_HOST="$(/opt/bin/jq -r '.outbounds[]?|select(.tag=="vless-reality")|.settings.vnext[0].address // ""' /opt/etc/xray/configs/04_outbounds.json 2>/dev/null | head -1)"
    VPN_PORT="$(/opt/bin/jq -r '.outbounds[]?|select(.tag=="vless-reality")|.settings.vnext[0].port // 0' /opt/etc/xray/configs/04_outbounds.json 2>/dev/null | head -1)"
  fi
  case "$VPN_PORT" in ''|*[!0-9]*) VPN_PORT=0 ;; esac
  if [ -n "$VPN_HOST" ] && [ "$VPN_PORT" -gt 0 ]; then
    if type xkeen_resolve_ipv4 >/dev/null 2>&1; then
      VPN_IP="$(xkeen_resolve_ipv4 "$VPN_HOST" | head -1)"
    else
      VPN_IP="$(nslookup "$VPN_HOST" 2>/dev/null | /opt/bin/awk '/^Name:/{seen=1;next} seen&&/^Address [0-9]+:/{print $3;exit} seen&&/^Address:/{print $2;exit}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
    fi
  fi
  if [ -n "$XRAY_PID" ] && [ -n "$VPN_IP" ] && [ "$VPN_PORT" -gt 0 ]; then
    # Match PID/xray exactly on the last netstat field — grep "$PID/xray"
    # would substring-match e.g. 4567/xray inside 14567/xray-something,
    # inflating counts once a similar PID appears on another socket.
    SOCK_LINES="$(netstat -anp 2>/dev/null | /opt/bin/awk -v pid="$XRAY_PID" -v ep="${VPN_IP}:${VPN_PORT}" '
      $NF == pid "/xray" && ($4 == ep || $5 == ep) { print }
    ')"
    VPN_TOTAL="$(printf '%s\n' "$SOCK_LINES" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
    VPN_ESTABLISHED="$(printf '%s\n' "$SOCK_LINES" | grep -c 'ESTABLISHED' || true)"
    VPN_FIN_WAIT="$(printf '%s\n' "$SOCK_LINES" | grep -cE 'FIN_WAIT1|FIN_WAIT2' || true)"
    VPN_ORPHAN_FIN="$(netstat -anp 2>/dev/null | /opt/bin/awk -v ep="${VPN_IP}:${VPN_PORT}" '
      ($4 == ep || $5 == ep) && ($6 == "FIN_WAIT1" || $6 == "FIN_WAIT2") && $NF == "-" { c++ }
      END { print c+0 }
    ')"
  fi
  case "$VPN_ESTABLISHED" in ''|*[!0-9]*) VPN_ESTABLISHED=0 ;; esac
  case "$VPN_FIN_WAIT"    in ''|*[!0-9]*) VPN_FIN_WAIT=0 ;; esac
  case "$VPN_ORPHAN_FIN"  in ''|*[!0-9]*) VPN_ORPHAN_FIN=0 ;; esac
  case "$VPN_TOTAL"       in ''|*[!0-9]*) VPN_TOTAL=0 ;; esac

  # Compute health status (mirrors selfheal thresholds)
  HEALTH_STATUS="ok"
  if [ -z "$XRAY_PID" ]; then
    HEALTH_STATUS="xray_down"
  elif [ "$XRAY_FD" -ge 600 ]; then
    HEALTH_STATUS="fd_critical"
  elif [ "$VPN_ORPHAN_FIN" -ge 30 ]; then
    HEALTH_STATUS="vpn_orphan_fin_critical"
  elif [ "$VPN_FIN_WAIT" -ge 50 ]; then
    HEALTH_STATUS="vpn_fin_critical"
  elif [ "$XRAY_FD" -ge 400 ]; then
    HEALTH_STATUS="fd_warn"
  elif [ "$VPN_ORPHAN_FIN" -ge 20 ]; then
    HEALTH_STATUS="vpn_orphan_fin_warn"
  elif [ "$VPN_FIN_WAIT" -ge 20 ]; then
    HEALTH_STATUS="vpn_fin_warn"
  fi
  if [ "$CT_MAX" -gt 0 ]; then
    CT_PCT=$(( CT_COUNT * 100 / CT_MAX ))
    if [ "$CT_PCT" -ge 95 ] && [ "$HEALTH_STATUS" = "ok" ]; then HEALTH_STATUS="conntrack_critical"; fi
    if [ "$CT_PCT" -ge 85 ] && [ "$HEALTH_STATUS" = "ok" ]; then HEALTH_STATUS="conntrack_warn"; fi
  fi

  XRAY_RUN=$([ -n "$XRAY_PID" ] && printf 'true' || printf 'false')
  SB_RUN=$([ -n "$SB_PID" ] && printf 'true' || printf 'false')
  SH_RUN=$([ -n "$SELFHEAL_PID" ] && printf 'true' || printf 'false')

  PAYLOAD="$(/opt/bin/jq -n \
    --argjson xray_run "$XRAY_RUN" \
    --arg xray_pid "${XRAY_PID:-}" \
    --argjson xray_tcp "$XRAY_TCP_OK" \
    --argjson xray_relay "$XRAY_RELAY_OK" \
    --argjson sb_run "$SB_RUN" \
    --arg sb_pid "${SB_PID:-}" \
    --argjson sb_listen "$SB_LISTEN_OK" \
    --argjson sh_run "$SH_RUN" \
    --arg sh_pid "${SELFHEAL_PID:-}" \
    --argjson tproxy_end "$TPROXY_AT_END" \
    --argjson ip_rule_masked "$IP_RULE_MASKED" \
    --argjson udp_ipset_ok "$UDP_IPSET_OK" \
    --argjson bypass_ipset_ok "$BYPASS_IPSET_OK" \
    --argjson udp_ipset_size "$UDP_IPSET_SIZE" \
    --argjson bypass_ipset_size "$BYPASS_IPSET_SIZE" \
    --argjson xray_fd "$XRAY_FD" \
    --argjson xray_fd_limit "$XRAY_FD_LIMIT" \
    --argjson ct_count "$CT_COUNT" \
    --argjson ct_max "$CT_MAX" \
    --argjson vpn_established "$VPN_ESTABLISHED" \
    --argjson vpn_fin_wait "$VPN_FIN_WAIT" \
    --argjson vpn_orphan_fin "$VPN_ORPHAN_FIN" \
    --argjson vpn_total "$VPN_TOTAL" \
    --arg vpn_host "${VPN_HOST:-}" \
    --arg health_status "$HEALTH_STATUS" \
    '{
      ok: true,
      healthStatus: $health_status,
      services: {
        xray:    { running: $xray_run, pid: $xray_pid, listenTcp: ($xray_tcp == 1), listenRelayUdp: ($xray_relay == 1) },
        singbox: { running: $sb_run, pid: $sb_pid, listenUdp: ($sb_listen == 1) },
        selfheal:{ running: $sh_run, pid: $sh_pid }
      },
      checks: {
        tproxyRuleAtEnd: ($tproxy_end == 1),
        ipRuleMasked:    ($ip_rule_masked == 1),
        udpIpsetExists:  ($udp_ipset_ok == 1),
        bypassIpsetExists: ($bypass_ipset_ok == 1)
      },
      ipsetSize: { udpRoute: $udp_ipset_size, bypass: $bypass_ipset_size },
      xrayFd: { count: $xray_fd, limit: $xray_fd_limit },
      conntrack: { count: $ct_count, max: $ct_max },
      vpnTunnel: {
        host: $vpn_host,
        established: $vpn_established,
        finWait: $vpn_fin_wait,
        orphanFin: $vpn_orphan_fin,
        total: $vpn_total
      }
    }')"

  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  printf '%s\n' "$PAYLOAD"
  exit 0
}

emit_logs() {
  SVC="$(parse_qs_param svc)"
  N="$(parse_qs_param n)"
  case "$N" in
    ''|*[!0-9]*) N=100 ;;
  esac
  if [ "$N" -gt 1000 ]; then N=1000; fi

  case "$SVC" in
    xray)     LOG_FILE="$LOG_PATH" ;;
    singbox)  LOG_FILE="/opt/var/log/sing-box-xkeen.log" ;;
    selfheal) LOG_FILE="/opt/var/log/xkeen-selfheal.log" ;;
    health)   LOG_FILE="/opt/var/log/xkeen-health.log" ;;
    sysctl)   LOG_FILE="/opt/var/log/xkeen-sysctl.log" ;;
    fd-dump)
      LOG_FILE="$(ls -t /opt/var/log/xray-fd-dump-*.txt 2>/dev/null | head -n 1)"
      ;;
    *)
      json_err "unknown svc"
      exit 0
      ;;
  esac

  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: text/plain; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  if [ -z "$LOG_FILE" ]; then
    printf '(no fd-dump file present yet — none has been triggered since boot)\n'
  elif [ -f "$LOG_FILE" ]; then
    if [ "$SVC" = "fd-dump" ]; then
      printf '# %s\n\n' "$LOG_FILE"
      cat "$LOG_FILE" 2>/dev/null
    else
      tail -n "$N" "$LOG_FILE" 2>/dev/null
    fi
  else
    printf '(log file %s does not exist)\n' "$LOG_FILE"
  fi
  exit 0
}

emit_stack_info() {
  XRAY_VER="$(/opt/sbin/xray version 2>/dev/null | head -n 1 | /opt/bin/awk '{print $2}')"
  SB_VER="$(/opt/sbin/sing-box version 2>/dev/null | head -n 1 | /opt/bin/awk '{print $3}')"
  KERNEL="$(uname -r 2>/dev/null)"
  HOSTNAME_S="$(uname -n 2>/dev/null)"
  UPTIME_SEC="$(/opt/bin/awk '{ printf "%d", int($1) }' /proc/uptime 2>/dev/null)"
  case "$UPTIME_SEC" in ''|*[!0-9]*) UPTIME_SEC=0 ;; esac

  OUTBOUNDS_FILE=/opt/etc/xray/configs/04_outbounds.json
  VPN_HOST=""
  VPN_PORT=0
  VPN_SNI=""
  if [ -f "$OUTBOUNDS_FILE" ] && command -v /opt/bin/jq >/dev/null 2>&1; then
    VPN_HOST="$(/opt/bin/jq -r '.outbounds[]?|select(.tag=="vless-reality")|.settings.vnext[0].address // ""' "$OUTBOUNDS_FILE" 2>/dev/null)"
    VPN_PORT="$(/opt/bin/jq -r '.outbounds[]?|select(.tag=="vless-reality")|.settings.vnext[0].port // 0' "$OUTBOUNDS_FILE" 2>/dev/null)"
    VPN_SNI="$(/opt/bin/jq -r '.outbounds[]?|select(.tag=="vless-reality")|.streamSettings.realitySettings.serverName // ""' "$OUTBOUNDS_FILE" 2>/dev/null)"
  fi
  case "$VPN_PORT" in ''|*[!0-9]*) VPN_PORT=0 ;; esac
  VPN_IP=""
  if [ -n "$VPN_HOST" ]; then
    if type xkeen_resolve_ipv4 >/dev/null 2>&1; then
      VPN_IP="$(xkeen_resolve_ipv4 "$VPN_HOST" | head -1)"
    else
      VPN_IP="$(nslookup "$VPN_HOST" 2>/dev/null | /opt/bin/awk '
        /^Name:/ { seen=1; next }
        seen && /^Address [0-9]+: / { print $3; exit }
        seen && /^Address: / { print $2; exit }
      ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
    fi
  fi

  WAN_IFACE="$(ip route show default 2>/dev/null | /opt/bin/awk '/^default/{print $5; exit}')"
  WAN_IP=""
  if [ -n "$WAN_IFACE" ]; then
    WAN_IP="$(ip addr show "$WAN_IFACE" 2>/dev/null | /opt/bin/awk '/inet /{print $2; exit}' | cut -d/ -f1)"
  fi
  GW="$(ip route show default 2>/dev/null | /opt/bin/awk '/^default/{print $3; exit}')"
  LAN_NET="$(ip route show 2>/dev/null | /opt/bin/awk '/scope link/ && /^(192\.168\.|10\.|172\.)/ {print $1; exit}')"

  POLICY_BLOCK="$(ndmc -c 'show ip policy' 2>/dev/null)"
  # Format A (newer): one-line "policy, name = Policy42, description = xkeen:Home"
  # Format B (older): multi-line with separate "name: Policy42" / "description: xkeen:Home"
  # Use the single source of truth from xkeen-runtime.sh to guarantee that
  # CGI (this) and runtime (xkeen_get_mark/xkeen_ensure_policy) agree on
  # which policy the health UI shows vs which one selfheal actually manages.
  DESC_MATCH="${XKEEN_POLICY_DESC_RE:-description[[:space:]]*[=:][[:space:]]*\"?xkeen(\$|[\":,[:space:]])}"
  POLICY_LINE="$(printf '%s\n' "$POLICY_BLOCK" | grep -E "$DESC_MATCH" | head -n 1)"
  POLICY_NAME="$(printf '%s' "$POLICY_LINE" | sed -n 's/.*name *= *\([^,]*\).*/\1/p' | sed 's/[[:space:]]*$//')"
  POLICY_DESC="$(printf '%s' "$POLICY_LINE" | sed -n 's/.*description *= *\([^,]*\).*/\1/p' | sed 's/[[:space:]]*$//' | sed 's/:[[:space:]]*$//' | sed 's/^xkeen:[[:space:]]*//' | sed 's/^xkeen$//')"
  if [ -z "$POLICY_NAME" ]; then
    POLICY_NAME="$(printf '%s\n' "$POLICY_BLOCK" | /opt/bin/awk -v pat="$DESC_MATCH" '/^[[:space:]]*name:/{n=$2} $0 ~ pat {print n; exit}')"
  fi
  if [ -z "$POLICY_DESC" ]; then
    POLICY_DESC="$(printf '%s\n' "$POLICY_BLOCK" | /opt/bin/awk -F ': ' -v pat="$DESC_MATCH" '$0 ~ pat {gsub(/^[[:space:]]+/,"",$2); print $2; exit}')"
  fi
  # Use the runtime helper — it already handles Format A (mark on the same
  # line as description) and Format B (mark on a later line), and reset on
  # new `policy,`. Local awk here had the same `next` bug that iter 2
  # fixed in xkeen_get_mark, so keeping a private copy re-introduced the
  # UI-vs-runtime split-brain.
  if type xkeen_get_mark >/dev/null 2>&1; then
    XKEEN_MARK_VAL="$(xkeen_get_mark 2>/dev/null)"
  else
    XKEEN_MARK_VAL=""
  fi

  MEM_AVAIL_KB="$(grep '^MemAvailable:' /proc/meminfo 2>/dev/null | /opt/bin/awk '{print $2}')"
  MEM_TOTAL_KB="$(grep '^MemTotal:' /proc/meminfo 2>/dev/null | /opt/bin/awk '{print $2}')"
  DISK_LINE="$(df -k /opt 2>/dev/null | tail -n 1)"
  DISK_TOTAL_KB="$(printf '%s' "$DISK_LINE" | /opt/bin/awk '{print $2}')"
  DISK_USED_KB="$(printf '%s' "$DISK_LINE" | /opt/bin/awk '{print $3}')"
  DISK_AVAIL_KB="$(printf '%s' "$DISK_LINE" | /opt/bin/awk '{print $4}')"
  DISK_MOUNT="$(printf '%s' "$DISK_LINE" | /opt/bin/awk '{print $NF}')"
  CT_COUNT="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"
  CT_MAX="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)"
  XRAY_PID_S="$(get_xray_pid)"
  XRAY_FD_COUNT_S=0
  XRAY_FD_LIMIT_S=0
  if [ -n "$XRAY_PID_S" ] && [ -d "/proc/$XRAY_PID_S/fd" ]; then
    XRAY_FD_COUNT_S="$(ls "/proc/$XRAY_PID_S/fd" 2>/dev/null | wc -l | tr -d ' ')"
    XRAY_FD_LIMIT_S="$(grep 'Max open files' "/proc/$XRAY_PID_S/limits" 2>/dev/null | /opt/bin/awk '{print $4}')"
  fi
  case "$MEM_AVAIL_KB"  in ''|*[!0-9]*) MEM_AVAIL_KB=0 ;; esac
  case "$MEM_TOTAL_KB"  in ''|*[!0-9]*) MEM_TOTAL_KB=0 ;; esac
  case "$CT_COUNT"      in ''|*[!0-9]*) CT_COUNT=0 ;; esac
  case "$CT_MAX"        in ''|*[!0-9]*) CT_MAX=0 ;; esac
  case "$XRAY_FD_COUNT_S" in ''|*[!0-9]*) XRAY_FD_COUNT_S=0 ;; esac
  case "$XRAY_FD_LIMIT_S" in ''|*[!0-9]*) XRAY_FD_LIMIT_S=0 ;; esac
  case "$DISK_TOTAL_KB" in ''|*[!0-9]*) DISK_TOTAL_KB=0 ;; esac
  case "$DISK_USED_KB"  in ''|*[!0-9]*) DISK_USED_KB=0 ;; esac
  case "$DISK_AVAIL_KB" in ''|*[!0-9]*) DISK_AVAIL_KB=0 ;; esac

  PAYLOAD="$(/opt/bin/jq -n \
    --arg xray_ver "$XRAY_VER" \
    --arg sb_ver "$SB_VER" \
    --arg kernel "$KERNEL" \
    --arg hostname "$HOSTNAME_S" \
    --argjson uptime_sec "$UPTIME_SEC" \
    --arg vpn_host "$VPN_HOST" \
    --argjson vpn_port "$VPN_PORT" \
    --arg vpn_sni "$VPN_SNI" \
    --arg vpn_ip "$VPN_IP" \
    --arg wan_iface "$WAN_IFACE" \
    --arg wan_ip "$WAN_IP" \
    --arg lan_net "$LAN_NET" \
    --arg gw "$GW" \
    --arg policy_name "$POLICY_NAME" \
    --arg policy_desc "$POLICY_DESC" \
    --arg xkeen_mark "$XKEEN_MARK_VAL" \
    --argjson mem_avail_kb "$MEM_AVAIL_KB" \
    --argjson mem_total_kb "$MEM_TOTAL_KB" \
    --argjson ct_count "$CT_COUNT" \
    --argjson ct_max "$CT_MAX" \
    --argjson xray_fd "$XRAY_FD_COUNT_S" \
    --argjson xray_fd_limit "$XRAY_FD_LIMIT_S" \
    --argjson disk_total_kb "$DISK_TOTAL_KB" \
    --argjson disk_used_kb "$DISK_USED_KB" \
    --argjson disk_avail_kb "$DISK_AVAIL_KB" \
    --arg disk_mount "$DISK_MOUNT" \
    '{
      ok: true,
      versions: { xray: $xray_ver, singbox: $sb_ver, kernel: $kernel, hostname: $hostname, uptimeSec: $uptime_sec },
      vpn:      { host: $vpn_host, port: $vpn_port, sni: $vpn_sni, exitIp: $vpn_ip },
      network:  { wanIface: $wan_iface, wanIp: $wan_ip, gateway: $gw, lanNet: $lan_net },
      xkeen:    { policyName: $policy_name, policyDescription: $policy_desc, mark: $xkeen_mark, tproxyUdp: 61221, redirectTcp: 61219, ssRelay: "127.0.0.1:62640" },
      runtime:  { selfhealIntervalSec: 15, logRotateInterval: "daily", backupRetention: 5, fdWarn: 400, fdCritical: 600 },
      resources:{ memAvailKb: $mem_avail_kb, memTotalKb: $mem_total_kb, conntrackCount: $ct_count, conntrackMax: $ct_max, xrayFd: $xray_fd, xrayFdLimit: $xray_fd_limit, diskTotalKb: $disk_total_kb, diskUsedKb: $disk_used_kb, diskAvailKb: $disk_avail_kb, diskMount: $disk_mount }
    }')"

  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  printf '%s\n' "$PAYLOAD"
  exit 0
}

restart_service() {
  SVC="$(json_field 'svc')"
  case "$SVC" in
    xray)
      if restart_xray; then
        json_ok "{\"ok\":true,\"service\":\"xray\"}"
      else
        json_err "xray restart failed"
      fi
      ;;
    singbox)
      if [ -x /opt/etc/init.d/S24antigoblin-singbox ]; then
        /opt/etc/init.d/S24antigoblin-singbox restart >/dev/null 2>&1
        # Poll for :61221 (TPROXY UDP) — pidof alone reports running
        # before the socket is actually bound.
        i=0
        SB_BOUND=0
        while [ $i -lt 8 ]; do
          if pidof sing-box >/dev/null 2>&1 && netstat -lnpu 2>/dev/null | grep -q ':61221 '; then
            SB_BOUND=1
            break
          fi
          sleep 1
          i=$((i + 1))
        done
        if [ "$SB_BOUND" = "1" ]; then
          json_ok "{\"ok\":true,\"service\":\"singbox\"}"
        else
          json_err "singbox not listening on :61221 after restart"
        fi
      else
        json_err "singbox init script missing"
      fi
      ;;
    selfheal)
      if [ -x /opt/etc/init.d/S25antigoblin-selfheal ]; then
        /opt/etc/init.d/S25antigoblin-selfheal restart >/dev/null 2>&1
        sleep 1
        json_ok "{\"ok\":true,\"service\":\"selfheal\"}"
      else
        json_err "selfheal init script missing"
      fi
      ;;
    *)
      json_err "unknown service"
      ;;
  esac
  rm -f "$TMP_BODY"
  exit 0
}

emit_file() {
  FILE_PATH="$1"
  if [ ! -f "$FILE_PATH" ]; then
    printf 'Status: 404 Not Found\r\n'
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf '\r\n'
    printf '{"ok":false,"error":"file not found"}\n'
    exit 0
  fi
  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf '\r\n'
  cat "$FILE_PATH"
  exit 0
}

json_field() {
  FIELD_NAME="$1"
  sed -n "s/.*\"${FIELD_NAME}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$TMP_BODY" | head -n 1
}

valid_probe_address() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9.-]+$'
}

valid_probe_port() {
  printf '%s' "$1" | grep -Eq '^[0-9]+$' || return 1
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# Fetch a subscription URL and return its body base64-encoded for JSON-safe
# transport. The endpoint is intentionally dumb: it does NOT decode or parse
# the subscription content; the client decodes base64 and parses URIs.
# This keeps the server simple and avoids assumptions about format.
#
# Constraints:
#   - URL must use https:// (no plain http to prevent token leaks)
#   - URL length capped to avoid pathological inputs
#   - Response capped at 256KB and 10s wall time (DoS mitigation)
#   - Prefers curl; falls back to wget only if it has HTTPS support
fetch_subscription() {
  URL="$(json_field url)"

  if [ -z "$URL" ]; then
    json_err "missing url field"
    rm -f "$TMP_BODY"
    exit 0
  fi

  case "$URL" in
    https://*) ;;
    *)
      json_err "url must use https://"
      rm -f "$TMP_BODY"
      exit 0
      ;;
  esac

  URL_LEN="${#URL}"
  if [ "$URL_LEN" -gt 2048 ]; then
    json_err "url too long ($URL_LEN > 2048)"
    rm -f "$TMP_BODY"
    exit 0
  fi

  # SSRF guard: refuse hosts on private / loopback / link-local space.
  # An authenticated UI operator otherwise gets a fetch-through-router
  # primitive to probe internal services (`https://192.168.1.1/rci/…`,
  # `https://127.0.0.1/…`). Uses a substring match on the URL host part —
  # skips resolve-and-recheck (an extra DNS round-trip we'd have to
  # timeout-cap for a marginal gain against active DNS-rebinding attacks
  # which are already limited to a single 10s fetch here).
  HOST_PART="${URL#https://}"
  HOST_PART="${HOST_PART%%/*}"
  HOST_PART="${HOST_PART%%\?*}"
  HOST_PART="${HOST_PART%%\#*}"
  HOST_PART="${HOST_PART##*@}"
  case "$HOST_PART" in
    '['*']:'*) HOST_ONLY="${HOST_PART%%]:*}]" ;;
    '['*']')   HOST_ONLY="$HOST_PART" ;;
    *:*)       HOST_ONLY="${HOST_PART%:*}" ;;
    *)         HOST_ONLY="$HOST_PART" ;;
  esac
  case "$HOST_ONLY" in
    127.*|10.*|192.168.*|169.254.*|0.0.0.0|::1|'[::1]'|localhost|localhost.*|*.localhost|'[fc'*|'[fd'*|'[fe8'*|'[fe9'*|'[fea'*|'[feb'*)
      json_err "subscription url points to a private / loopback address"
      rm -f "$TMP_BODY"
      exit 0
      ;;
    172.*)
      SECOND="${HOST_ONLY#172.}"
      SECOND="${SECOND%%.*}"
      case "$SECOND" in
        16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31)
          json_err "subscription url points to a private address"
          rm -f "$TMP_BODY"
          exit 0
          ;;
      esac
      ;;
  esac

  FETCHER=""
  if [ -x /opt/bin/curl ]; then
    FETCHER="curl"
  elif [ -x /opt/bin/wget ] && /opt/bin/wget --version 2>&1 | grep -qiE '\+https|gnutls|openssl|ssl/tls'; then
    FETCHER="wget"
  else
    json_err "no https-capable fetcher (install curl: opkg install curl)"
    rm -f "$TMP_BODY"
    exit 0
  fi

  # Per-PID scratch — subscription-fetch runs WITHOUT the apply lock, so
  # two concurrent refreshes on a fixed path would swap their bodies:
  # process A's `base64 -w 0 < TMP_FETCH` could encode B's contents and
  # return VLESS-UUIDs / vmess-passwords from subscription B in the
  # response to A.
  TMP_FETCH="/tmp/xkeen-sub-fetch-$$.raw"
  TMP_FETCH_ERR="/tmp/xkeen-sub-fetch-$$.err"
  rm -f "$TMP_FETCH" "$TMP_FETCH_ERR"

  if [ "$FETCHER" = "curl" ]; then
    /opt/bin/curl -fsSL \
      --max-time 10 \
      --max-filesize 262144 \
      -A 'AntiGoblin/1.0' \
      -o "$TMP_FETCH" \
      "$URL" 2>"$TMP_FETCH_ERR"
    RC=$?
  else
    /opt/bin/wget -q \
      --timeout=10 \
      --tries=1 \
      -O "$TMP_FETCH" \
      "$URL" 2>"$TMP_FETCH_ERR"
    RC=$?
  fi

  if [ "$RC" -ne 0 ] || [ ! -s "$TMP_FETCH" ]; then
    ERR="$(tr -d '\r' < "$TMP_FETCH_ERR" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' | cut -c1-200)"
    json_err "fetch failed (rc=$RC, fetcher=$FETCHER): $ERR"
    rm -f "$TMP_BODY" "$TMP_FETCH" "$TMP_FETCH_ERR"
    exit 0
  fi

  SIZE="$(wc -c < "$TMP_FETCH" 2>/dev/null || echo 0)"

  # wget has no --max-filesize equivalent; enforce the cap after the fact
  # so a hostile / compromised subscription endpoint can't stream tens of
  # MB into /tmp within the 10s timeout window and OOM tmpfs. curl was
  # already capped via --max-filesize 262144.
  if [ "$FETCHER" = "wget" ] && [ "$SIZE" -gt 262144 ]; then
    json_err "subscription response too large ($SIZE > 262144 bytes)"
    rm -f "$TMP_BODY" "$TMP_FETCH" "$TMP_FETCH_ERR"
    exit 0
  fi

  ENCODED="$(/opt/bin/base64 -w 0 < "$TMP_FETCH" 2>/dev/null || /opt/bin/base64 < "$TMP_FETCH" | tr -d '\n\r ')"

  if [ -z "$ENCODED" ]; then
    json_err "base64 encoding produced empty output (size=$SIZE)"
    rm -f "$TMP_BODY" "$TMP_FETCH" "$TMP_FETCH_ERR"
    exit 0
  fi

  json_ok "{\"ok\":true,\"size\":${SIZE},\"fetcher\":\"${FETCHER}\",\"raw\":\"${ENCODED}\"}"
  rm -f "$TMP_BODY" "$TMP_FETCH" "$TMP_FETCH_ERR"
  exit 0
}

router_auth_login() {
  REQUEST_HOST="$(router_auth_endpoint)"
  REQUEST_UA="${HTTP_USER_AGENT:-xkeen-manager}"

  LOGIN_B64="$(json_field 'loginB64')"
  PASSWORD_B64="$(json_field 'passwordB64')"

  if [ -z "$LOGIN_B64" ] || [ -z "$PASSWORD_B64" ]; then
    json_err "invalid login payload"
    rm -f "$TMP_BODY" "$TMP_AUTH_HEADERS"
    exit 0
  fi

  LOGIN="$(printf '%s' "$LOGIN_B64" | /opt/bin/base64 -d 2>/dev/null)"
  PASSWORD="$(printf '%s' "$PASSWORD_B64" | /opt/bin/base64 -d 2>/dev/null)"

  if [ -z "$LOGIN" ] || [ -z "$PASSWORD" ]; then
    json_err "failed to decode credentials"
    rm -f "$TMP_BODY" "$TMP_AUTH_HEADERS"
    exit 0
  fi

  AUTH_GET_HEADERS="$(wget -S -O - --timeout=5 --tries=1 \
    --header="Host: $REQUEST_HOST" \
    --header="User-Agent: $REQUEST_UA" \
    "http://$REQUEST_HOST/auth" 2>&1 | head -c 8192)"

  REALM="$(printf '%s' "$AUTH_GET_HEADERS" | sed -n 's/.*realm="\([^"]*\)".*/\1/p' | head -n 1)"
  CHALLENGE="$(printf '%s' "$AUTH_GET_HEADERS" | sed -n 's/.*challenge="\([^"]*\)".*/\1/p' | head -n 1)"
  SESSION_ID="$(printf '%s' "$AUTH_GET_HEADERS" | sed -n 's/.*session_id="\([^"]*\)".*/\1/p' | head -n 1)"
  SESSION_COOKIE="$(printf '%s' "$AUTH_GET_HEADERS" | sed -n 's/.*session_cookie="\([^"]*\)".*/\1/p' | head -n 1)"

  if [ -z "$REALM" ] || [ -z "$CHALLENGE" ] || [ -z "$SESSION_ID" ] || [ -z "$SESSION_COOKIE" ]; then
    json_err "failed to read router auth challenge"
    rm -f "$TMP_BODY" "$TMP_AUTH_HEADERS"
    exit 0
  fi

  LOGIN_MD5="$(printf '%s' "${LOGIN}:${REALM}:${PASSWORD}" | /opt/bin/md5sum | /opt/bin/awk '{print $1}')"
  LOGIN_SHA256="$(printf '%s' "${CHALLENGE}${LOGIN_MD5}" | /opt/bin/sha256sum | /opt/bin/awk '{print $1}')"
  AUTH_PAYLOAD="$(/opt/bin/jq -cn --arg login "$LOGIN" --arg password "$LOGIN_SHA256" '{login:$login, password:$password}')"

  AUTH_POST_HEADERS="$(wget -S -O - --timeout=5 --tries=1 \
    --header="Host: $REQUEST_HOST" \
    --header="Cookie: ${SESSION_COOKIE}=${SESSION_ID}" \
    --header="User-Agent: $REQUEST_UA" \
    --header="Content-Type: application/json; charset=utf-8" \
    --post-data="$AUTH_PAYLOAD" \
    "http://$REQUEST_HOST/auth" 2>&1 | head -c 8192)"

  printf '%s' "$AUTH_POST_HEADERS" | grep -q 'HTTP/1\.[01] 200' || {
    json_invalid_credentials
    rm -f "$TMP_BODY" "$TMP_AUTH_HEADERS"
    exit 0
  }

  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf 'Set-Cookie: %s=%s; Path=/; SameSite=Strict; Max-Age=300\r\n' "$SESSION_COOKIE" "$SESSION_ID"
  printf '\r\n'
  /opt/bin/jq -cn --arg login "$LOGIN" '{ok:true, login:$login}'
  rm -f "$TMP_BODY" "$TMP_AUTH_HEADERS"
  exit 0
}

router_auth_logout() {
  REQUEST_HOST="$(router_auth_endpoint)"
  REQUEST_COOKIE="${HTTP_COOKIE:-}"
  SESSION_COOKIE_NAME="$(printf '%s' "$REQUEST_COOKIE" | sed -n 's/^\([^=;[:space:]]*\)=.*/\1/p' | head -n 1)"

  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  if [ -n "$SESSION_COOKIE_NAME" ]; then
    printf 'Set-Cookie: %s=; Path=/; SameSite=Strict; Max-Age=0\r\n' "$SESSION_COOKIE_NAME"
  fi
  printf '\r\n'
  /opt/bin/jq -cn --arg host "$REQUEST_HOST" '{ok:true, host:$host}'
  rm -f "$TMP_BODY" "$TMP_AUTH_HEADERS"
  exit 0
}

require_router_session() {
  REQUEST_HOST="$(router_auth_endpoint)"
  REQUEST_COOKIE="${HTTP_COOKIE:-}"
  REQUEST_UA="${HTTP_USER_AGENT:-xkeen-manager}"

  if [ -z "$REQUEST_COOKIE" ]; then
    json_unauthorized
    exit 0
  fi

  AUTH_RESPONSE="$(wget -S -O - --timeout=5 --tries=1 \
    --header="Host: $REQUEST_HOST" \
    --header="Cookie: $REQUEST_COOKIE" \
    --header="User-Agent: $REQUEST_UA" \
    "http://$REQUEST_HOST/auth" 2>&1 | head -c 8192)"

  printf '%s' "$AUTH_RESPONSE" | grep -q 'HTTP/1\.[01] 200' || {
    json_unauthorized
    exit 0
  }
}

case "$REQUEST_METHOD" in
  GET)
    require_router_session
    KIND="$(get_kind)"
    if [ "$KIND" = "state" ]; then
      emit_file "$STATE_PATH"
    fi
    if [ "$KIND" = "outbounds" ]; then
      emit_file "$OUTBOUNDS_PATH"
    fi
    if [ "$KIND" = "health" ]; then
      emit_health
    fi
    if [ "$KIND" = "logs" ]; then
      emit_logs
    fi
    if [ "$KIND" = "stack-info" ]; then
      emit_stack_info
    fi
    emit_file "$ROUTING_PATH"
    ;;
  POST)
    KIND="$(get_kind)"
    # Auth before body for anything that isn't login/logout — otherwise an
    # unauthenticated client can waste CGI processes uploading a 512KB body
    # only to fail the session check afterward. Login/logout themselves
    # legitimately need the body before their own auth logic.
    case "$KIND" in
      login|logout)
        read_body
        ;;
      *)
        require_router_session
        read_body
        ;;
    esac
    BODY_SIZE="$(wc -c < "$TMP_BODY" 2>/dev/null)"

    if [ "$KIND" = "login" ]; then
      router_auth_login
    fi

    if [ "$KIND" = "logout" ]; then
      router_auth_logout
    fi

    case "$KIND" in
      probe|subscription-fetch)
        ;;
      *)
        require_apply_lock
        ;;
    esac

    if [ "$KIND" = "state" ]; then
      if ! /opt/bin/jq -e 'type == "object" and has("profiles")' "$TMP_BODY" >/dev/null 2>&1; then
        cp "$TMP_BODY" /tmp/xkeen-routing-invalid.json 2>/dev/null || true
        json_err "invalid state payload (size=${BODY_SIZE:-0}, content_length=${CONTENT_LENGTH:-unset})"
        rm -f "$TMP_BODY"
        exit 0
      fi

      STATE_BAK="${STATE_PATH}.bak-ui-$(date +%Y%m%d-%H%M%S)"
      cp "$STATE_PATH" "$STATE_BAK" 2>/dev/null || true
      # Atomic write: stage on the SAME filesystem as the destination so the
      # final mv is a rename(2) — no chance of a truncated JSON if uhttpd
      # kills us at -t 120 mid-write or the box loses power. A direct
      # `cp $TMPFS $OPT` copies chunk-by-chunk across the FS boundary,
      # leaves a half-written file, and the next selfheal `jq` read fails
      # silently → xkeen_bypass empties → every bypass group breaks until
      # the user restores a .bak-ui-*.
      STATE_STAGE="${STATE_PATH}.new-$$"
      if ! cp "$TMP_BODY" "$STATE_STAGE" || ! mv "$STATE_STAGE" "$STATE_PATH"; then
        rm -f "$STATE_STAGE"
        json_err "failed to write state"
        rm -f "$TMP_BODY"
        exit 0
      fi

      json_ok "{\"ok\":true,\"state\":\"$STATE_PATH\"}"
      rm -f "$TMP_BODY"
      exit 0
    fi

    if [ "$KIND" = "outbounds" ]; then
      if ! /opt/bin/jq -e '.outbounds | type == "array" and (map(.tag) | index("vless-reality") != null)' "$TMP_BODY" >/dev/null 2>&1; then
        cp "$TMP_BODY" /tmp/xkeen-outbounds-invalid.json 2>/dev/null || true
        json_err "invalid outbounds payload (size=${BODY_SIZE:-0}, content_length=${CONTENT_LENGTH:-unset})"
        rm -f "$TMP_BODY"
        exit 0
      fi

      OUT_BAK="${OUTBOUNDS_PATH}.bak-ui-$(date +%Y%m%d-%H%M%S)"
      cp "$OUTBOUNDS_PATH" "$OUT_BAK" 2>/dev/null || true
      # Atomic same-FS stage + rename (see state branch above for rationale).
      OUT_STAGE="${OUTBOUNDS_PATH}.new-$$"
      if ! cp "$TMP_BODY" "$OUT_STAGE" || ! mv "$OUT_STAGE" "$OUTBOUNDS_PATH"; then
        rm -f "$OUT_STAGE"
        json_err "failed to write outbounds"
        rm -f "$TMP_BODY"
        exit 0
      fi

      json_ok "{\"ok\":true,\"outbounds\":\"$OUTBOUNDS_PATH\"}"
      rm -f "$TMP_BODY"
      exit 0
    fi

    if [ "$KIND" = "probe" ]; then
      ADDRESS="$(sed -n 's/.*"address"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP_BODY" | head -n 1)"
      PORT="$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$TMP_BODY" | head -n 1)"
      if [ -z "$ADDRESS" ] || [ -z "$PORT" ] || ! valid_probe_address "$ADDRESS" || ! valid_probe_port "$PORT"; then
        json_err "invalid probe payload"
        rm -f "$TMP_BODY"
        exit 0
      fi

      RESOLVED_IP="$(nslookup "$ADDRESS" 2>/dev/null | awk '/^Address [0-9]*: /{print $3} /^Address: /{print $2}' | tail -n 1)"
      if printf '' | /opt/bin/nc "$ADDRESS" "$PORT" >/dev/null 2>&1; then
        json_ok "{\"ok\":true,\"address\":\"$ADDRESS\",\"port\":$PORT,\"resolvedIp\":\"$RESOLVED_IP\"}"
      else
        json_err "tcp connect failed"
      fi
      rm -f "$TMP_BODY"
      exit 0
    fi

    if [ "$KIND" = "repair-runtime" ]; then
      if repair_runtime; then
        json_ok '{"ok":true,"message":"runtime restored"}'
      else
        json_err "failed to restore xkeen/xray runtime"
      fi
      rm -f "$TMP_BODY"
      exit 0
    fi

    if [ "$KIND" = "subscription-fetch" ]; then
      fetch_subscription
    fi

    if [ "$KIND" = "singbox" ]; then
      if ! /opt/bin/jq -e '.outbounds | type == "array"' "$TMP_BODY" >/dev/null 2>&1 \
         || ! /opt/bin/jq -e '.inbounds  | type == "array"' "$TMP_BODY" >/dev/null 2>&1; then
        cp "$TMP_BODY" /tmp/xkeen-singbox-invalid.json 2>/dev/null || true
        json_err "invalid singbox payload (size=${BODY_SIZE:-0})"
        rm -f "$TMP_BODY"
        exit 0
      fi

      SINGBOX_PATH="/opt/etc/sing-box/xkeen.json"
      SB_BAK="${SINGBOX_PATH}.bak-ui-$(date +%Y%m%d-%H%M%S)"
      cp "$SINGBOX_PATH" "$SB_BAK" 2>/dev/null || true
      # Atomic same-FS stage + rename (see state branch above).
      SB_STAGE="${SINGBOX_PATH}.new-$$"
      if ! cp "$TMP_BODY" "$SB_STAGE" || ! mv "$SB_STAGE" "$SINGBOX_PATH"; then
        rm -f "$SB_STAGE"
        json_err "failed to write sing-box config"
        rm -f "$TMP_BODY"
        exit 0
      fi

      # sing-box validates its own config at start; failure leaves the
      # service down and the next selfheal cycle will notice. We accept the
      # write either way — UI is the source of truth on this path.
      /opt/etc/init.d/S24antigoblin-singbox restart >/dev/null 2>&1 || true

      json_ok "{\"ok\":true,\"singbox\":\"$SINGBOX_PATH\"}"
      rm -f "$TMP_BODY"
      exit 0
    fi

    if [ "$KIND" = "restart-svc" ]; then
      restart_service
    fi

    if ! grep -q '"routing"' "$TMP_BODY" || ! grep -q '"rules"' "$TMP_BODY"; then
      cp "$TMP_BODY" /tmp/xkeen-routing-invalid.json 2>/dev/null || true
      json_err "invalid routing json (size=${BODY_SIZE:-0}, content_length=${CONTENT_LENGTH:-unset})"
      rm -f "$TMP_BODY"
      exit 0
    fi

    TS="$(date +%Y%m%d-%H%M%S)"
    BACKUP="${ROUTING_PATH}.bak-ui-${TS}"
    cp "$ROUTING_PATH" "$BACKUP" 2>/dev/null || true
    # Atomic same-FS stage + rename. TMP_BODY lives on tmpfs (/tmp); a direct
    # `cp` to /opt would leave a truncated file if uhttpd kills us at -t 120
    # mid-copy — xray then boots on the next restart with a corrupt routing
    # config, selfheal watches it fail, and backoff kicks in for 1800s. The
    # same rationale for state / outbounds / singbox writes above.
    ROUTING_STAGE="${ROUTING_PATH}.new-$$"
    if ! cp "$TMP_BODY" "$ROUTING_STAGE" || ! mv "$ROUTING_STAGE" "$ROUTING_PATH"; then
      rm -f "$ROUTING_STAGE"
      json_err "failed to write routing"
      rm -f "$TMP_BODY"
      exit 0
    fi
    # rollback_routing: restore from $BACKUP atomically. Same-FS mv again.
    rollback_routing() {
      [ -f "$BACKUP" ] || return 0
      ROLLBACK_STAGE="${ROUTING_PATH}.rollback-$$"
      if cp "$BACKUP" "$ROLLBACK_STAGE" && mv "$ROLLBACK_STAGE" "$ROUTING_PATH"; then
        return 0
      fi
      rm -f "$ROLLBACK_STAGE"
      return 1
    }
    if validate_confdir; then
      if restart_xray; then
        # Deliberately NOT calling repair_runtime here. It runs xkeen_repair_hooks
        # (which rebuilds xkeen_bypass ipset by resolving every domain in state
        # — 60+ nslookups when the DNS cache is cold) AND a second restart_xray
        # right after we already restarted. Both together push the apply call
        # past 60s and the browser's 20s fetch timeout aborts the request while
        # xray IS getting restarted. The selfheal tick (every 15s) refreshes
        # the ipset on its own; the small window where bypass-set has yesterday's
        # domains until the next tick is acceptable.
        json_ok "{\"ok\":true,\"backup\":\"$BACKUP\",\"restarted\":true}"
      else
        rollback_routing
        json_err "xray restart failed, rollback applied"
      fi
    else
      rollback_routing
      json_err "xray config validation failed, rollback applied"
    fi

    rm -f "$TMP_BODY"
    exit 0
    ;;
  *)
    printf 'Status: 405 Method Not Allowed\r\n'
    printf 'Content-Type: application/json; charset=utf-8\r\n'
    printf '\r\n'
    printf '{"ok":false,"error":"method not allowed"}\n'
    exit 0
    ;;
esac
