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
FAILOVER_STAMP=/tmp/xkeen-subscription-probe.state
FAILOVER_CURSOR=/tmp/xkeen-subscription-failover-cursor
REFRESH_LOCK=/tmp/xkeen-subscription-refresh.lock
UPDATE_LOCK=/opt/var/run/antigoblin-app-update.lock
XRAY_RECOVERY_REQUEST=/tmp/xkeen-xray-failover-recovery
LIVE_DIR=/opt/etc/xray/configs
LIVE_SB=/opt/etc/sing-box/xkeen.json

[ -f "$STATE" ] && [ -f "$APP" ] && [ -f "$WORKER" ] && [ -f "$CANDIDATE_WORKER" ] || exit 0
ENABLED="$(jq '[.profiles[]?.subscriptions[]? | select(.autoRefresh == true)] | length' "$STATE" 2>/dev/null || echo 0)"
case "$ENABLED" in ''|*[!0-9]*) ENABLED=0 ;; esac
[ "$ENABLED" -gt 0 ] || exit 0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }
[ -x /opt/bin/qjs ] || { log "subscription_refresh skipped: quickjs missing"; exit 1; }
[ -f "$RUNTIME" ] || { log "subscription_refresh skipped: runtime missing"; exit 1; }
. "$RUNTIME"

xray_redirect_pid() {
  netstat -lnpt 2>/dev/null | awk -v suffix=":$XKEEN_REDIRECT_PORT" '
    $4 ~ (suffix "$") && $NF ~ /^[0-9]+\/xray$/ {split($NF, p, "/"); print p[1]; exit}'
}
xray_redirect_ready() { [ -n "$(xray_redirect_pid)" ]; }

refresh_lock() (
  XKEEN_LOCK_DIR="$REFRESH_LOCK"
  XKEEN_LOCK_PID_FILE="$REFRESH_LOCK/pid"
  "$@"
)

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

test_candidate() (
  TEST_PID=
  trap '[ -z "$TEST_PID" ] || stop_test_process "$TEST_PID"' EXIT
  trap 'exit 1' INT TERM
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

  for attempt in 1 2 3 4 5 6 7 8; do
    if netstat -lnpt 2>/dev/null | awk -v port=":$TEST_PORT" -v pid="$TEST_PID/" '
        $4 ~ (port "$") && index($NF, pid) == 1 {found=1} END {exit !found}'; then
      probe_socks "$TEST_PORT" || return 1
      return 0
    fi
    kill -0 "$TEST_PID" 2>/dev/null || return 1
    sleep 1
  done
  return 1
)

acquire_current_runtime() {
  [ ! -d "$UPDATE_LOCK" ] && xkeen_lock_acquire || return 1
  RUNTIME_LOCK_HELD=1
  if [ -d "$UPDATE_LOCK" ] || ! cmp -s "$BASE_STATE" "$STATE"; then
    log "subscription_refresh deferred: configuration changed during checks"
    return 1
  fi
}

install_switch_configs() {
  cp "$1/04_outbounds.json" "$LIVE_DIR/04_outbounds.json.new-$$" &&
    cp "$1/05_routing.json" "$LIVE_DIR/05_routing.json.new-$$" &&
    cp "$2" "$LIVE_SB.new-$$" &&
    mv "$LIVE_DIR/04_outbounds.json.new-$$" "$LIVE_DIR/04_outbounds.json" &&
    mv "$LIVE_DIR/05_routing.json.new-$$" "$LIVE_DIR/05_routing.json" &&
    mv "$LIVE_SB.new-$$" "$LIVE_SB"
}

wait_switch_listeners() {
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    current_pid="$(xray_redirect_pid)"
    [ -n "$current_pid" ] && [ "$current_pid" != "$1" ] && xkeen_tproxy_ready && return 0
    sleep 1
  done
  return 1
}

# Start Xray the same way self-heal and Save & Apply do. The stock S24xray
# init omits XRAY_LOCATION_ASSET: with geosite:/geoip: rules it stops the
# working core and the new one exits on "failed to load geosite".
restart_switch_xray() {
  old_pid="$(xray_redirect_pid)"
  killall xray 2>/dev/null || true
  if [ -n "$old_pid" ]; then
    for attempt in 1 2 3 4 5 6 7 8; do
      kill -0 "$old_pid" 2>/dev/null || break
      sleep 1
    done
    # The PID space is small: SIGKILL only a process that is still Xray.
    if kill -0 "$old_pid" 2>/dev/null; then
      case "$(tr '\0' ' ' < "/proc/$old_pid/cmdline" 2>/dev/null)" in
        *xray*) kill -9 "$old_pid" 2>/dev/null || true ;;
      esac
    fi
  fi
  rm -f /opt/var/run/xray-ui.pid /opt/var/run/xray.pid
  XRAY_LOCATION_ASSET=/opt/etc/xray/dat XRAY_LOCATION_CONFDIR="$LIVE_DIR" \
    /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/xray-ui.pid \
    -x /opt/sbin/xray -- run >/dev/null 2>&1
}

restart_switch_stack() {
  # Starting Xray first restores ordinary TCP even if sing-box fails.
  prior_pid="$(xray_redirect_pid)"
  restart_ok=1
  restart_switch_xray ||
    { log "subscription_failover $1 xray_restart_failed"; restart_ok=0; }
  /opt/etc/init.d/S24antigoblin-singbox restart >/dev/null 2>&1 ||
    { log "subscription_failover $1 singbox_restart_failed"; restart_ok=0; }
  if ! wait_switch_listeners "$prior_pid"; then
    log "subscription_failover $1 listeners_not_ready"
    xkeen_tproxy_ready || log "subscription_failover $1 singbox_listener_missing"
    return 1
  fi
  [ "$restart_ok" = 1 ]
}

rollback_switch() {
  if ! install_switch_configs "$SWITCH_BACKUP" "$SWITCH_BACKUP/singbox.json"; then
    KEEP_BACKUP=1
    log "subscription_failover rollback_files_failed backup=$SWITCH_BACKUP"
    return 1
  fi
  if restart_switch_stack rollback; then
    log "subscription_failover rollback_restored profile=$PROFILE_ID"
    return 0
  fi
  : > "$XRAY_RECOVERY_REQUEST"
  log "subscription_failover rollback_unhealthy profile=$PROFILE_ID"
  return 1
}

cleanup_refresh() {
  if [ "$SWITCH_PENDING" = 1 ] &&
     ! cmp -s "$STATE" "$WORK_DIR/switched-state.json"; then
    # Also restore on INT/TERM between replacing configs and persisting state.
    rollback_switch || true
  fi
  rm -f "$LIVE_DIR/04_outbounds.json.new-$$" "$LIVE_DIR/05_routing.json.new-$$" "$LIVE_SB.new-$$" "$STATE.new-$$"
  [ "$KEEP_BACKUP" = 1 ] || rm -rf "$WORK_DIR"
  if [ "$RUNTIME_LOCK_HELD" = 1 ]; then xkeen_lock_release; fi
  refresh_lock xkeen_lock_release
}

persist_state() {
  cp "$1" "$STATE.new-$$" && chmod 600 "$STATE.new-$$" && mv "$STATE.new-$$" "$STATE"
}

apply_candidate() {
  PROFILE_ID="$1"
  SUBSCRIPTION_ID="$2"
  OLD_PROXY_ID="$3"
  REMOVE_OLD="$4"
  CANDIDATE_ID="$5"
  CANDIDATE_DIR="$6"
  SWITCH_BACKUP="$WORK_DIR/switch-backup"
  SWITCH_CONFIG="$WORK_DIR/switch-config"
  if ! mkdir -p "$SWITCH_BACKUP" "$SWITCH_CONFIG" ||
     ! cp "$LIVE_DIR/04_outbounds.json" "$LIVE_DIR/05_routing.json" "$SWITCH_BACKUP/" ||
     ! cp "$LIVE_SB" "$SWITCH_BACKUP/singbox.json" ||
     ! cp "$LIVE_DIR/"*.json "$SWITCH_CONFIG/" ||
     ! cp "$CANDIDATE_DIR/outbounds.json" "$SWITCH_CONFIG/04_outbounds.json" ||
     ! cp "$CANDIDATE_DIR/routing.json" "$SWITCH_CONFIG/05_routing.json"; then
    log "subscription_failover prepare_failed profile=$PROFILE_ID"
    return 1
  fi
  if ! XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -test -confdir "$SWITCH_CONFIG" >/dev/null 2>&1 ||
     ! /opt/sbin/sing-box check -c "$CANDIDATE_DIR/singbox.json" >/dev/null 2>&1; then
    log "subscription_failover config_invalid profile=$PROFILE_ID"
    return 1
  fi

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

  xray_redirect_ready || return 1
  SWITCH_PENDING=1
  if install_switch_configs "$SWITCH_CONFIG" "$CANDIDATE_DIR/singbox.json" &&
     restart_switch_stack candidate &&
     probe_socks 61080 &&
     persist_state "$WORK_DIR/switched-state.json"; then
    SWITCH_PENDING=0
    STATE_CHANGED=0
    log "subscription_failover switched profile=$PROFILE_ID proxy_id=$CANDIDATE_ID"
    return 0
  fi
  log "subscription_failover promotion_failed profile=$PROFILE_ID"
  rollback_switch || true
  SWITCH_PENDING=0
  return 1
}

# The scheduler ticks once a minute. Persist the confirmation count so
# retries do not sleep while holding a lock or overlap the next tick.
probe_due() {
  LAST_PROXY=
  LAST_CHECK=0
  FAILURES=0
  if [ -r "$FAILOVER_STAMP" ]; then
    read -r LAST_PROXY LAST_CHECK FAILURES < "$FAILOVER_STAMP" || true
  fi
  case "$LAST_CHECK" in ''|*[!0-9]*) LAST_CHECK=0 ;; esac
  case "$FAILURES" in 1|2) ;; *) FAILURES=0 ;; esac
  if [ "$LAST_PROXY" != "$PROBE_KEY" ]; then
    LAST_CHECK=0
    FAILURES=0
  fi
  interval=900
  [ "$FAILURES" -eq 0 ] || interval=60
  elapsed=$((PROBE_NOW - LAST_CHECK))
  [ "$elapsed" -ge "$interval" ] || [ "$elapsed" -lt 0 ]
}

save_probe_state() {
  printf '%s %s %s\n' "$1" "$2" "$3" > "$FAILOVER_STAMP"
}

# Serialize scheduler jobs separately. Network checks must not exclude
# self-heal or Save & Apply from the runtime lock.
[ ! -d "$UPDATE_LOCK" ] && xray_redirect_ready || exit 0
refresh_lock xkeen_lock_acquire || exit 0
umask 077
WORK_DIR="$(mktemp -d /tmp/xkeen-subscription-refresh-XXXXXX)" ||
  { refresh_lock xkeen_lock_release; exit 1; }
RESULTS="$WORK_DIR/results.ndjson"
BASE_STATE="$WORK_DIR/base.json"
NEW_STATE="$WORK_DIR/state.json"
STATE_CHANGED=0
SWITCH_PENDING=0
KEEP_BACKUP=0
PROBE_NOW="$(date +%s)"
RUNTIME_LOCK_HELD=0
trap 'cleanup_refresh' EXIT
trap 'exit 1' INT TERM
cp "$STATE" "$BASE_STATE" || exit 1
: > "$RESULTS"

NOW_MS=$(( $(date +%s) * 1000 ))
JOBS="$(jq -r --argjson now "$NOW_MS" '
  .profiles[]? as $profile
  | $profile.subscriptions[]?
  | select(.autoRefresh == true)
  | (.autoRefreshIntervalHours // 6) as $hours
  | select(((.lastFetched // 0) + ($hours * 3600000)) <= $now)
  | [$profile.id, .id, .url] | @tsv
' "$BASE_STATE" 2>/dev/null | head -n 4)"

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
  SUMMARY="$(/opt/bin/qjs --std "$WORKER" "$BASE_STATE" "$RESULTS" "$NEW_STATE" "$APP" 2>&1)"
  RC=$?
  if [ "$RC" -ne 0 ] || ! jq -e 'type=="object" and (.profiles|type=="array")' "$NEW_STATE" >/dev/null 2>&1; then
    log "subscription_refresh failed: worker rc=$RC"
    exit 1
  fi
  log "$SUMMARY"
  STATE_CHANGED=1
else
  cp "$BASE_STATE" "$NEW_STATE" || exit 1
fi

# Refreshing the list and checking the active tunnel have separate schedules.
FAILOVER_ROW="$(jq -r '
  .activeProfileId as $profileId
  | .profiles[]? | select(.id == $profileId) as $profile
  | $profile.subscriptions[]? | select(.autoRefresh == true and .autoFailover == true) as $sub
  | $profile.proxies[]? | select(.id == $profile.activeProxyId and .source == $sub.id)
  | [$profile.id, $sub.id, .id, (.stale // false)] | @tsv
' "$NEW_STATE" 2>/dev/null | head -n 1)"

run_failover() {
  [ -n "$FAILOVER_ROW" ] || return 0
  IFS="$(printf '\t')" read -r ACTIVE_PROFILE FAILOVER_SUB ACTIVE_PROXY ACTIVE_STALE <<EOF
$FAILOVER_ROW
EOF
  PROBE_KEY="$ACTIVE_PROFILE:$ACTIVE_PROXY"
  initial_pid="$(xray_redirect_pid)"
  [ -n "$initial_pid" ] && cmp -s "$BASE_STATE" "$STATE" && probe_due || return 0
  if [ "$ACTIVE_STALE" != "true" ]; then
    if probe_socks 61080; then
      save_probe_state "$PROBE_KEY" "$PROBE_NOW" 0
      return 0
    fi
    # A local outage is not evidence of an upstream failure.
    [ "$(xray_redirect_pid)" = "$initial_pid" ] || return 0
    FAILURES=$((FAILURES + 1))
    log "subscription_failover active_probe_failed profile=$ACTIVE_PROFILE count=$FAILURES"
    if [ "$FAILURES" -lt 3 ]; then
      save_probe_state "$PROBE_KEY" "$PROBE_NOW" "$FAILURES"
      return 0
    fi
  fi

  LAST_CANDIDATE="$(cat "$FAILOVER_CURSOR" 2>/dev/null || true)"
  CANDIDATES="$(jq -r --arg profile "$ACTIVE_PROFILE" --arg sub "$FAILOVER_SUB" \
    --arg active "$ACTIVE_PROXY" --arg last "$LAST_CANDIDATE" '
    [.profiles[]? | select(.id == $profile) | .proxies[]?
    | select(.source == $sub and .id != $active and (.stale // false) == false) | .id][:4]
    | ((index($last) // -1) + 1) as $start
    | (.[$start:] + .[:$start])[]
  ' "$NEW_STATE" 2>/dev/null)"

  for candidate in $CANDIDATES; do
    case "$candidate" in ''|*[!a-zA-Z0-9_-]*) continue ;; esac
    if ! test_candidate "$candidate" 2>/dev/null; then
      log "subscription_failover isolated_probe_failed profile=$ACTIVE_PROFILE"
      continue
    fi
    dir="$WORK_DIR/candidate-$candidate"
    if ! acquire_current_runtime || [ "$(xray_redirect_pid)" != "$initial_pid" ]; then return 1; fi
    printf '%s\n' "$candidate" > "$FAILOVER_CURSOR"
    # One live attempt per round. A rollback must not trigger another restart.
    if apply_candidate "$ACTIVE_PROFILE" "$FAILOVER_SUB" "$ACTIVE_PROXY" "$ACTIVE_STALE" "$candidate" "$dir"; then
      save_probe_state "$ACTIVE_PROFILE:$candidate" "$(date +%s)" 0
    else
      save_probe_state "$PROBE_KEY" "$(date +%s)" 0
    fi
    return 0
  done
  log "subscription_failover no_reachable_candidate profile=$ACTIVE_PROFILE"
  save_probe_state "$PROBE_KEY" "$(date +%s)" 0
}

run_failover || exit 0
if [ "$STATE_CHANGED" = 1 ]; then
  if [ "$RUNTIME_LOCK_HELD" = 0 ]; then acquire_current_runtime || exit 0; fi
  BACKUP="$STATE.bak-sub-auto-$(date +%Y%m%d-%H%M%S)"
  cp "$STATE" "$BACKUP" && chmod 600 "$BACKUP" 2>/dev/null || true
  persist_state "$NEW_STATE" || { log "subscription_refresh state_write_failed"; exit 1; }
fi
