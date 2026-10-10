#!/bin/sh
PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

STATE=/opt/share/xkeen-manager/xkeen-ui-state.json
APP=/opt/share/xkeen-manager/app.js
WORKER=/opt/share/xkeen-manager/api/subscription-refresh.js
CANDIDATE_WORKER=/opt/share/xkeen-manager/api/subscription-candidate.js
GEODATA_SCRIPT=/opt/share/xkeen-manager/api/antigoblin-geodata.sh
LOG=/opt/var/log/xkeen-subscription-refresh.log
RUNTIME=/opt/share/xkeen-manager/api/xkeen-runtime.sh
PROBE_URL="${XKEEN_SUBSCRIPTION_PROBE_URL:-https://www.youtube.com/generate_204}"
FAILOVER_STAMP=/tmp/xkeen-subscription-failover-last.ts

[ -f "$STATE" ] && [ -f "$APP" ] && [ -f "$WORKER" ] && [ -f "$CANDIDATE_WORKER" ] || exit 0
ENABLED="$(jq '[.profiles[]?.subscriptions[]? | select(.autoRefresh == true)] | length' "$STATE" 2>/dev/null || echo 0)"
case "$ENABLED" in ''|*[!0-9]*) ENABLED=0 ;; esac
[ "$ENABLED" -gt 0 ] || exit 0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }
[ -x /opt/bin/qjs ] || { log "subscription_refresh skipped: quickjs missing"; exit 1; }
[ -f "$RUNTIME" ] || { log "subscription_refresh skipped: runtime missing"; exit 1; }
. "$RUNTIME"
if ! xkeen_lock_acquire; then
  exit 0
fi

WORK_DIR="/tmp/xkeen-subscription-refresh-$$"
RESULTS="$WORK_DIR/results.ndjson"
NEW_STATE="$WORK_DIR/state.json"
STATE_CHANGED=0
mkdir -p "$WORK_DIR" || { xkeen_lock_release; exit 1; }
trap 'rm -rf "$WORK_DIR"; xkeen_lock_release' EXIT INT TERM
: > "$RESULTS"

probe_socks() {
  PROBE_PORT="$1"
  HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= http_proxy= https_proxy= all_proxy= \
    NO_PROXY= no_proxy= /opt/bin/curl --noproxy '' -fsS -o /dev/null \
    --socks5-hostname "127.0.0.1:${PROBE_PORT}" \
    --connect-timeout 5 --max-time 10 "$PROBE_URL" >/dev/null 2>&1
}

stop_test_process() {
  TEST_PID="$1"
  [ -n "$TEST_PID" ] || return 0
  kill "$TEST_PID" 2>/dev/null || true
  i=0
  while [ "$i" -lt 3 ] && kill -0 "$TEST_PID" 2>/dev/null; do sleep 1; i=$((i+1)); done
  kill -9 "$TEST_PID" 2>/dev/null || true
  wait "$TEST_PID" 2>/dev/null || true
}

build_candidate() {
  CANDIDATE_ID="$1"
  CANDIDATE_DIR="$2"
  mkdir -p "$CANDIDATE_DIR" || return 1
  /opt/bin/qjs --std "$CANDIDATE_WORKER" "$NEW_STATE" "$CANDIDATE_ID" "$CANDIDATE_DIR" "$APP" >/dev/null 2>&1 \
    || return 1
  if [ -x "$GEODATA_SCRIPT" ]; then
    "$GEODATA_SCRIPT" render-singbox "$NEW_STATE" "$CANDIDATE_DIR/singbox.json" \
      "$CANDIDATE_DIR/singbox-geo.json" >/dev/null 2>&1 || return 1
    mv "$CANDIDATE_DIR/singbox-geo.json" "$CANDIDATE_DIR/singbox.json"
  fi
}

test_candidate() {
  CANDIDATE_ID="$1"
  CANDIDATE_DIR="$WORK_DIR/candidate-$CANDIDATE_ID"
  build_candidate "$CANDIDATE_ID" "$CANDIDATE_DIR" || return 1
  PROTOCOL="$(jq -r '.protocol // "vless"' "$CANDIDATE_DIR/candidate.json" 2>/dev/null)"
  if [ "$PROTOCOL" = "hysteria2" ]; then
    jq '.inbounds = [.inbounds[] | select(.type == "mixed") | .listen = "127.0.0.1" | .listen_port = 62081]' \
      "$CANDIDATE_DIR/singbox.json" > "$CANDIDATE_DIR/singbox-test.json" || return 1
    /opt/sbin/sing-box check -c "$CANDIDATE_DIR/singbox-test.json" >/dev/null 2>&1 || return 1
    /opt/sbin/sing-box run -c "$CANDIDATE_DIR/singbox-test.json" >"$CANDIDATE_DIR/test.log" 2>&1 &
    TEST_PID=$!
    TEST_PORT=62081
  else
    mkdir -p "$CANDIDATE_DIR/xray"
    printf '%s\n' '{"log":{"loglevel":"warning"}}' > "$CANDIDATE_DIR/xray/01_log.json"
    printf '%s\n' '{"inbounds":[{"tag":"socks-in","listen":"127.0.0.1","port":62080,"protocol":"socks","settings":{"auth":"noauth","udp":true}}]}' > "$CANDIDATE_DIR/xray/03_inbounds.json"
    cp "$CANDIDATE_DIR/outbounds.json" "$CANDIDATE_DIR/xray/04_outbounds.json"
    cp "$CANDIDATE_DIR/routing.json" "$CANDIDATE_DIR/xray/05_routing.json"
    XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -test -confdir "$CANDIDATE_DIR/xray" >/dev/null 2>&1 || return 1
    XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -confdir "$CANDIDATE_DIR/xray" >"$CANDIDATE_DIR/test.log" 2>&1 &
    TEST_PID=$!
    TEST_PORT=62080
  fi
  i=0
  while [ "$i" -lt 8 ]; do
    netstat -lnpt 2>/dev/null | grep -q ":${TEST_PORT} " && break
    kill -0 "$TEST_PID" 2>/dev/null || { stop_test_process "$TEST_PID"; return 1; }
    sleep 1; i=$((i+1))
  done
  if probe_socks "$TEST_PORT"; then
    stop_test_process "$TEST_PID"
    printf '%s\n' "$CANDIDATE_DIR"
    return 0
  fi
  stop_test_process "$TEST_PID"
  return 1
}

apply_candidate() {
  PROFILE_ID="$1"
  SUBSCRIPTION_ID="$2"
  OLD_PROXY_ID="$3"
  REMOVE_OLD="$4"
  CANDIDATE_ID="$5"
  CANDIDATE_DIR="$6"
  LIVE_DIR=/opt/etc/xray/configs
  LIVE_SB=/opt/etc/sing-box/xkeen.json
  SWITCH_BACKUP="$WORK_DIR/switch-backup"
  mkdir -p "$SWITCH_BACKUP"
  cp "$NEW_STATE" "$SWITCH_BACKUP/state.json"
  cp "$LIVE_DIR/04_outbounds.json" "$SWITCH_BACKUP/04_outbounds.json"
  cp "$LIVE_DIR/05_routing.json" "$SWITCH_BACKUP/05_routing.json"
  cp "$LIVE_SB" "$SWITCH_BACKUP/singbox.json"

  jq --arg profile "$PROFILE_ID" --arg sub "$SUBSCRIPTION_ID" \
    --arg old "$OLD_PROXY_ID" --arg proxy "$CANDIDATE_ID" \
    --argjson removeOld "$REMOVE_OLD" --argjson now "$(date +%s000)" '
    (.profiles[] | select(.id == $profile)) |= (
      .activeProxyId = $proxy
      | if $removeOld then .proxies = [.proxies[] | select(.id != $old)] else . end
      | (.subscriptions[] | select(.id == $sub)) |= (
          .lastError = null
          | .lastFailoverAt = $now
          | .lastFailoverFrom = $old
          | .lastFailoverTo = $proxy
        )
    )' \
    "$NEW_STATE" > "$WORK_DIR/switched-state.json" || return 1
  cp "$CANDIDATE_DIR/outbounds.json" "$LIVE_DIR/04_outbounds.json.new"
  cp "$CANDIDATE_DIR/routing.json" "$LIVE_DIR/05_routing.json.new"
  cp "$CANDIDATE_DIR/singbox.json" "$LIVE_SB.new"
  mv "$LIVE_DIR/04_outbounds.json.new" "$LIVE_DIR/04_outbounds.json"
  mv "$LIVE_DIR/05_routing.json.new" "$LIVE_DIR/05_routing.json"
  mv "$LIVE_SB.new" "$LIVE_SB"
  cp "$WORK_DIR/switched-state.json" "$NEW_STATE"

  if ! XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -test -confdir "$LIVE_DIR" >/dev/null 2>&1 \
      || ! /opt/sbin/sing-box check -c "$LIVE_SB" >/dev/null 2>&1 \
      || ! /opt/etc/init.d/S24antigoblin-singbox restart >/dev/null 2>&1 \
      || ! /opt/etc/init.d/S24xray restart >/dev/null 2>&1; then
    SWITCH_OK=0
  else
    i=0
    while [ "$i" -lt 12 ]; do
      netstat -lnpt 2>/dev/null | grep -q ':61080 ' && break
      sleep 1; i=$((i+1))
    done
    probe_socks 61080 && SWITCH_OK=1 || SWITCH_OK=0
  fi
  if [ "$SWITCH_OK" = "1" ]; then
    STATE_CHANGED=1
    log "subscription_failover switched profile=$PROFILE_ID proxy_id=$CANDIDATE_ID"
    return 0
  fi
  cp "$SWITCH_BACKUP/04_outbounds.json" "$LIVE_DIR/04_outbounds.json"
  cp "$SWITCH_BACKUP/05_routing.json" "$LIVE_DIR/05_routing.json"
  cp "$SWITCH_BACKUP/singbox.json" "$LIVE_SB"
  cp "$SWITCH_BACKUP/state.json" "$NEW_STATE"
  /opt/etc/init.d/S24antigoblin-singbox restart >/dev/null 2>&1 || true
  /opt/etc/init.d/S24xray restart >/dev/null 2>&1 || true
  log "subscription_failover rollback profile=$PROFILE_ID"
  return 1
}

NOW_MS=$(( $(date +%s) * 1000 ))
JOBS="$(jq -r --argjson now "$NOW_MS" '
  .profiles[]? as $profile
  | $profile.subscriptions[]?
  | select(.autoRefresh == true)
  | (.autoRefreshIntervalHours // 6) as $hours
  | select(((.lastFetched // 0) + ($hours * 3600000)) <= $now)
  | [$profile.id, .id, .url] | @tsv
' "$STATE" 2>/dev/null | head -n 4)"

if [ -n "$JOBS" ]; then printf '%s\n' "$JOBS"; fi | while IFS="$(printf '\t')" read -r PROFILE_ID SUB_ID URL; do
  [ -n "$PROFILE_ID" ] && [ -n "$SUB_ID" ] && [ -n "$URL" ] || continue
  case "$URL" in https://*) ;; *)
    jq -cn --arg profileId "$PROFILE_ID" --arg subId "$SUB_ID" --argjson now "$NOW_MS" \
      '{profileId:$profileId,subId:$subId,now:$now,ok:false,error:"scheduled refresh requires https"}' >> "$RESULTS"
    continue ;;
  esac
  URL_LEN="${#URL}"
  if [ "$URL_LEN" -gt 2048 ]; then
    jq -cn --arg profileId "$PROFILE_ID" --arg subId "$SUB_ID" --argjson now "$NOW_MS" \
      '{profileId:$profileId,subId:$subId,now:$now,ok:false,error:"subscription URL too long"}' >> "$RESULTS"
    continue
  fi
  HOST_PART="${URL#https://}"; HOST_PART="${HOST_PART%%/*}"; HOST_PART="${HOST_PART##*@}"
  if ! printf '%s' "$HOST_PART" | grep -Eq '^([A-Za-z0-9._-]+)(:[0-9]+)?$|^\[[0-9A-Fa-f:]+\](:[0-9]+)?$'; then
    jq -cn --arg profileId "$PROFILE_ID" --arg subId "$SUB_ID" --argjson now "$NOW_MS" \
      '{profileId:$profileId,subId:$subId,now:$now,ok:false,error:"subscription URL has invalid host"}' >> "$RESULTS"
    continue
  fi
  HOST_ONLY="${HOST_PART%:*}"
  case "$HOST_ONLY" in
    127.*|10.*|192.168.*|169.254.*|0.0.0.0|::1|'[::1]'|localhost|localhost.*|*.localhost|'[fc'*|'[fd'*|'[fe8'*|'[fe9'*|'[fea'*|'[feb'*)
      jq -cn --arg profileId "$PROFILE_ID" --arg subId "$SUB_ID" --argjson now "$NOW_MS" \
        '{profileId:$profileId,subId:$subId,now:$now,ok:false,error:"subscription URL points to private address"}' >> "$RESULTS"
      continue ;;
    172.*)
      SECOND="${HOST_ONLY#172.}"; SECOND="${SECOND%%.*}"
      case "$SECOND" in 16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31)
        jq -cn --arg profileId "$PROFILE_ID" --arg subId "$SUB_ID" --argjson now "$NOW_MS" \
          '{profileId:$profileId,subId:$subId,now:$now,ok:false,error:"subscription URL points to private address"}' >> "$RESULTS"
        continue ;;
      esac ;;
  esac

  BODY="$WORK_DIR/body-$SUB_ID"
  ERR="$WORK_DIR/error-$SUB_ID"
  /opt/bin/curl -fsSL --max-time 10 --max-filesize 262144 \
    -A 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/131 Mobile Safari/537.36 AntiGoblin/1.0' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Accept-Language: ru-RU,ru;q=0.9,en;q=0.8' \
    -H "Origin: https://${HOST_PART}" -H "Referer: https://${HOST_PART}/" \
    -o "$BODY" "$URL" 2>"$ERR"
  RC=$?
  if [ "$RC" -ne 0 ] || [ ! -s "$BODY" ]; then
    jq -cn --arg profileId "$PROFILE_ID" --arg subId "$SUB_ID" --argjson now "$NOW_MS" --arg rc "$RC" \
      '{profileId:$profileId,subId:$subId,now:$now,ok:false,error:("scheduled fetch failed rc="+$rc)}' >> "$RESULTS"
    continue
  fi
  BODY_B64="$(/opt/bin/base64 -w 0 < "$BODY" 2>/dev/null || /opt/bin/base64 < "$BODY" | tr -d '\r\n ')"
  jq -cn --arg profileId "$PROFILE_ID" --arg subId "$SUB_ID" --argjson now "$NOW_MS" --arg body "$BODY_B64" \
    '{profileId:$profileId,subId:$subId,now:$now,ok:true,bodyBase64:$body}' >> "$RESULTS"
done

if [ -s "$RESULTS" ]; then
  SUMMARY="$(/opt/bin/qjs --std "$WORKER" "$STATE" "$RESULTS" "$NEW_STATE" "$APP" 2>&1)"
  RC=$?
  if [ "$RC" -ne 0 ] || ! jq -e 'type=="object" and (.profiles|type=="array")' "$NEW_STATE" >/dev/null 2>&1; then
    log "subscription_refresh failed: worker rc=$RC"
    exit 1
  fi
  log "$SUMMARY"
  STATE_CHANGED=1
else
  cp "$STATE" "$NEW_STATE"
fi

# Auto-failover only concerns the currently active profile and subscription.
# A key removed upstream is replaced even while its old tunnel still works;
# otherwise probe the active tunnel at most every five minutes.
FAILOVER_ROW="$(jq -r '
  .activeProfileId as $profileId
  | .profiles[]? | select(.id == $profileId) as $profile
  | $profile.subscriptions[]? | select(.autoRefresh == true and .autoFailover == true) as $sub
  | $profile.proxies[]? | select(.id == $profile.activeProxyId and .source == $sub.id)
  | [$profile.id, $sub.id, .id, (.stale // false)] | @tsv
' "$NEW_STATE" 2>/dev/null | head -n 1)"
if [ -n "$FAILOVER_ROW" ]; then
  IFS="$(printf '\t')" read -r ACTIVE_PROFILE FAILOVER_SUB ACTIVE_PROXY ACTIVE_STALE <<EOF
$FAILOVER_ROW
EOF
  NOW_SEC="$(date +%s)"
  LAST_CHECK="$(cat "$FAILOVER_STAMP" 2>/dev/null || echo 0)"
  case "$LAST_CHECK" in ''|*[!0-9]*) LAST_CHECK=0 ;; esac
  if [ "$ACTIVE_STALE" = "true" ] || [ $((NOW_SEC - LAST_CHECK)) -ge 300 ]; then
    printf '%s\n' "$NOW_SEC" > "$FAILOVER_STAMP"
    if [ "$ACTIVE_STALE" = "true" ] || ! probe_socks 61080; then
      CANDIDATES="$(jq -r --arg profile "$ACTIVE_PROFILE" --arg sub "$FAILOVER_SUB" --arg active "$ACTIVE_PROXY" '
        .profiles[]? | select(.id == $profile) | .proxies[]?
        | select(.source == $sub and .id != $active and (.stale // false) == false)
        | .id
      ' "$NEW_STATE" 2>/dev/null | head -n 4)"
      SWITCHED=0
      for CANDIDATE_ID in $CANDIDATES; do
        CANDIDATE_DIR="$(test_candidate "$CANDIDATE_ID" 2>/dev/null || true)"
        [ -n "$CANDIDATE_DIR" ] || continue
        if apply_candidate "$ACTIVE_PROFILE" "$FAILOVER_SUB" "$ACTIVE_PROXY" "$ACTIVE_STALE" "$CANDIDATE_ID" "$CANDIDATE_DIR"; then
          SWITCHED=1
          break
        fi
      done
      [ "$SWITCHED" = "1" ] || log "subscription_failover no_working_candidate profile=$ACTIVE_PROFILE"
    fi
  fi
fi

if [ "$STATE_CHANGED" = "1" ]; then
  BACKUP="${STATE}.bak-sub-auto-$(date +%Y%m%d-%H%M%S)"
  cp "$STATE" "$BACKUP" && chmod 600 "$BACKUP" 2>/dev/null || true
  chmod 600 "$NEW_STATE" 2>/dev/null || true
  mv "$NEW_STATE" "$STATE"
fi
