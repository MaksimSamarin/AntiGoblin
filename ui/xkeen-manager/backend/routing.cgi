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
BYPASS_DOMAINS_PATH="$RUNTIME_DIR/bypass-domains.txt"
BYPASS_CIDRS_PATH="$RUNTIME_DIR/bypass-cidrs.txt"
XKEEN_MARK=""

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

ensure_xkeen_mark() {
  XKEEN_MARK="$(get_xkeen_mark)"
  [ -n "$XKEEN_MARK" ]
}

build_bypass_ipset_inline() {
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

append_local_returns_inline() {
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

validate_confdir() {
  /opt/sbin/xray run -test -confdir /opt/etc/xray/configs >/dev/null 2>&1
}

repair_runtime() {
  if [ -x "$SELFHEAL_PATH" ]; then
    "$SELFHEAL_PATH" --force >/dev/null 2>&1
    return $?
  fi

  ensure_xkeen_mark || return 1
  mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
  build_bypass_ipset_inline
  iptables -t nat -N xkeen 2>/dev/null || true
  iptables -t nat -F xkeen 2>/dev/null || true
  append_local_returns_inline
  iptables -t nat -A xkeen -p tcp -m set --match-set xkeen_bypass dst -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -p tcp -j REDIRECT --to-ports 61219 2>/dev/null || true
  iptables -t nat -A xkeen -j RETURN 2>/dev/null || true
  iptables -t nat -D PREROUTING -m connmark --mark "0x$XKEEN_MARK" -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || true
  iptables -t nat -D PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || true
  iptables -t nat -D PREROUTING -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || true
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

  restart_xray || return 1
  return 0
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
    *)
      printf 'routing'
      ;;
  esac
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
