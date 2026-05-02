#!/bin/sh

PATH="/opt/bin:/opt/sbin:/sbin:/usr/sbin:/bin:/usr/bin:$PATH"

ROUTING_PATH="/opt/etc/xray/configs/05_routing.json"
OUTBOUNDS_PATH="/opt/etc/xray/configs/04_outbounds.json"
STATE_PATH="/opt/share/xkeen-manager/xkeen-ui-state.json"
TMP_BODY="/tmp/xkeen-routing-body.json"
TMP_NEW="/tmp/xkeen-routing-new.json"
TMP_STATE="/tmp/xkeen-state-new.json"
TMP_AUTH_HEADERS="/tmp/xkeen-auth-headers.txt"
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
  cat > "$TMP_BODY"
}

restart_xray() {
  killall xray 2>/dev/null || true
  rm -f /opt/var/run/xray-ui.pid /opt/var/run/xray.pid 2>/dev/null || true
  sleep 2
  XRAY_LOCATION_ASSET=/opt/etc/xray/dat XRAY_LOCATION_CONFDIR=/opt/etc/xray/configs \
    /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/xray-ui.pid -x "$XRAY_BIN" -- run >>"$LOG_PATH" 2>&1
  sleep 3
  netstat -lnptu 2>/dev/null | grep -q '61219'
}

validate_confdir() {
  /opt/sbin/xray run -test -confdir /opt/etc/xray/configs >/dev/null 2>&1
}

repair_runtime() {
  if [ -x "$SELFHEAL_PATH" ]; then
    "$SELFHEAL_PATH" --force >/dev/null 2>&1
    return $?
  fi

  if type xkeen_repair_hooks >/dev/null 2>&1; then
    xkeen_repair_hooks || return 1
    restart_xray || return 1
    return 0
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
  XRAY_PID="$(pidof xray 2>/dev/null | /opt/bin/awk '{ print $1 }')"
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
    '{
      ok: true,
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
      ipsetSize: { udpRoute: $udp_ipset_size, bypass: $bypass_ipset_size }
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
    VPN_IP="$(nslookup "$VPN_HOST" 2>/dev/null | /opt/bin/awk '
      /^Name:/ { seen=1; next }
      seen && /^Address [0-9]+: / { print $3; exit }
      seen && /^Address: / { print $2; exit }
    ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
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
  POLICY_LINE="$(printf '%s\n' "$POLICY_BLOCK" | grep 'description.*xkeen' | head -n 1)"
  POLICY_NAME="$(printf '%s' "$POLICY_LINE" | sed -n 's/.*name *= *\([^,]*\).*/\1/p' | sed 's/[[:space:]]*$//')"
  POLICY_DESC="$(printf '%s' "$POLICY_LINE" | sed -n 's/.*description *= *\([^,]*\).*/\1/p' | sed 's/[[:space:]]*$//' | sed 's/:[[:space:]]*$//' | sed 's/^xkeen:[[:space:]]*//' | sed 's/^xkeen$//')"
  if [ -z "$POLICY_NAME" ]; then
    POLICY_NAME="$(printf '%s\n' "$POLICY_BLOCK" | /opt/bin/awk '/^[[:space:]]*name:/{n=$2} /description.*xkeen/{print n; exit}')"
  fi
  if [ -z "$POLICY_DESC" ]; then
    POLICY_DESC="$(printf '%s\n' "$POLICY_BLOCK" | /opt/bin/awk -F ': ' '/description.*xkeen/{gsub(/^[[:space:]]+/,"",$2); print $2; exit}')"
  fi
  XKEEN_MARK_VAL="$(printf '%s\n' "$POLICY_BLOCK" | /opt/bin/awk '
    /description.*xkeen/ { want=1; next }
    want && /mark/ { gsub(/[[:space:]]/,"",$0); split($0,a,":"); print a[2]; exit }
  ')"

  MEM_AVAIL_KB="$(grep '^MemAvailable:' /proc/meminfo 2>/dev/null | /opt/bin/awk '{print $2}')"
  MEM_TOTAL_KB="$(grep '^MemTotal:' /proc/meminfo 2>/dev/null | /opt/bin/awk '{print $2}')"
  DISK_LINE="$(df -k /opt 2>/dev/null | tail -n 1)"
  DISK_TOTAL_KB="$(printf '%s' "$DISK_LINE" | /opt/bin/awk '{print $2}')"
  DISK_USED_KB="$(printf '%s' "$DISK_LINE" | /opt/bin/awk '{print $3}')"
  DISK_AVAIL_KB="$(printf '%s' "$DISK_LINE" | /opt/bin/awk '{print $4}')"
  DISK_MOUNT="$(printf '%s' "$DISK_LINE" | /opt/bin/awk '{print $NF}')"
  CT_COUNT="$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)"
  CT_MAX="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)"
  XRAY_PID_S="$(pidof xray 2>/dev/null | /opt/bin/awk '{print $1}')"
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
        sleep 1
        if pidof sing-box >/dev/null 2>&1; then
          json_ok "{\"ok\":true,\"service\":\"singbox\"}"
        else
          json_err "singbox not running after restart"
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

router_auth_login() {
  REQUEST_HOST="$(printf '%s' "${HTTP_HOST:-192.168.1.1}" | sed 's/:.*$//')"
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

  AUTH_GET_HEADERS="$(wget -S -O - \
    --header="Host: $REQUEST_HOST" \
    --header="User-Agent: $REQUEST_UA" \
    "http://$REQUEST_HOST/auth" 2>&1)"

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
  AUTH_PAYLOAD="$(printf '{"login":"%s","password":"%s"}' "$LOGIN" "$LOGIN_SHA256")"

  AUTH_POST_HEADERS="$(wget -S -O - \
    --header="Host: $REQUEST_HOST" \
    --header="Cookie: ${SESSION_COOKIE}=${SESSION_ID}" \
    --header="User-Agent: $REQUEST_UA" \
    --header="Content-Type: application/json; charset=utf-8" \
    --post-data="$AUTH_PAYLOAD" \
    "http://$REQUEST_HOST/auth" 2>&1)"

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
  printf '{"ok":true,"login":"%s"}\n' "$LOGIN"
  rm -f "$TMP_BODY" "$TMP_AUTH_HEADERS"
  exit 0
}

router_auth_logout() {
  REQUEST_HOST="$(printf '%s' "${HTTP_HOST:-192.168.1.1}" | sed 's/:.*$//')"
  REQUEST_COOKIE="${HTTP_COOKIE:-}"
  SESSION_COOKIE_NAME="$(printf '%s' "$REQUEST_COOKIE" | sed -n 's/^\([^=;[:space:]]*\)=.*/\1/p' | head -n 1)"

  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  if [ -n "$SESSION_COOKIE_NAME" ]; then
    printf 'Set-Cookie: %s=; Path=/; SameSite=Strict; Max-Age=0\r\n' "$SESSION_COOKIE_NAME"
  fi
  printf '\r\n'
  printf '{"ok":true,"host":"%s"}\n' "$REQUEST_HOST"
  rm -f "$TMP_BODY" "$TMP_AUTH_HEADERS"
  exit 0
}

require_router_session() {
  REQUEST_HOST="$(printf '%s' "${HTTP_HOST:-192.168.1.1}" | sed 's/:.*$//')"
  REQUEST_COOKIE="${HTTP_COOKIE:-}"
  REQUEST_UA="${HTTP_USER_AGENT:-xkeen-manager}"

  if [ -z "$REQUEST_COOKIE" ]; then
    json_unauthorized
    exit 0
  fi

  AUTH_RESPONSE="$(wget -S -O - \
    --header="Host: $REQUEST_HOST" \
    --header="Cookie: $REQUEST_COOKIE" \
    --header="User-Agent: $REQUEST_UA" \
    "http://$REQUEST_HOST/auth" 2>&1)"

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
    read_body
    BODY_SIZE="$(wc -c < "$TMP_BODY" 2>/dev/null)"

    if [ "$KIND" = "login" ]; then
      router_auth_login
    fi

    if [ "$KIND" = "logout" ]; then
      router_auth_logout
    fi

    require_router_session

    if [ "$KIND" = "state" ]; then
      if ! grep -q '"profiles"' "$TMP_BODY"; then
        cp "$TMP_BODY" /tmp/xkeen-routing-invalid.json 2>/dev/null || true
        json_err "invalid state payload (size=${BODY_SIZE:-0}, content_length=${CONTENT_LENGTH:-unset})"
        rm -f "$TMP_BODY"
        exit 0
      fi

      STATE_BAK="${STATE_PATH}.bak-ui-$(date +%Y%m%d-%H%M%S)"
      cp "$STATE_PATH" "$STATE_BAK" 2>/dev/null || true
      cp "$TMP_BODY" "$STATE_PATH" || {
        json_err "failed to write state"
        rm -f "$TMP_BODY"
        exit 0
      }

      json_ok "{\"ok\":true,\"state\":\"$STATE_PATH\"}"
      rm -f "$TMP_BODY"
      exit 0
    fi

    if [ "$KIND" = "outbounds" ]; then
      if ! grep -q '"outbounds"' "$TMP_BODY" || ! grep -q '"vless-reality"' "$TMP_BODY"; then
        cp "$TMP_BODY" /tmp/xkeen-outbounds-invalid.json 2>/dev/null || true
        json_err "invalid outbounds payload (size=${BODY_SIZE:-0}, content_length=${CONTENT_LENGTH:-unset})"
        rm -f "$TMP_BODY"
        exit 0
      fi

      OUT_BAK="${OUTBOUNDS_PATH}.bak-ui-$(date +%Y%m%d-%H%M%S)"
      cp "$OUTBOUNDS_PATH" "$OUT_BAK" 2>/dev/null || true
      cp "$TMP_BODY" "$OUTBOUNDS_PATH" || {
        json_err "failed to write outbounds"
        rm -f "$TMP_BODY"
        exit 0
      }

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

    if [ "$KIND" = "restart-svc" ]; then
      restart_service
    fi

    if ! grep -q '"routing"' "$TMP_BODY" || ! grep -q '"rules"' "$TMP_BODY"; then
      cp "$TMP_BODY" /tmp/xkeen-routing-invalid.json 2>/dev/null || true
      json_err "invalid routing json (size=${BODY_SIZE:-0}, content_length=${CONTENT_LENGTH:-unset})"
      rm -f "$TMP_BODY"
      exit 0
    fi

    cp "$TMP_BODY" "$TMP_NEW" || {
      json_err "failed to stage new routing"
      rm -f "$TMP_BODY" "$TMP_NEW"
      exit 0
    }

    TS="$(date +%Y%m%d-%H%M%S)"
    BACKUP="${ROUTING_PATH}.bak-ui-${TS}"
    cp "$ROUTING_PATH" "$BACKUP" 2>/dev/null || true
    cp "$TMP_NEW" "$ROUTING_PATH" || {
      json_err "failed to write routing"
      rm -f "$TMP_BODY" "$TMP_NEW"
      exit 0
    }
    if validate_confdir; then
      if restart_xray; then
        repair_runtime >/dev/null 2>&1 || true
        json_ok "{\"ok\":true,\"backup\":\"$BACKUP\",\"restarted\":true}"
      else
        if [ -f "$BACKUP" ]; then
          cp "$BACKUP" "$ROUTING_PATH"
        fi
        json_err "xray restart failed, rollback applied"
      fi
    else
      if [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$ROUTING_PATH"
      fi
      json_err "xray config validation failed, rollback applied"
    fi

    rm -f "$TMP_BODY" "$TMP_NEW" "$TMP_STATE" "$TMP_NEW.body"
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
