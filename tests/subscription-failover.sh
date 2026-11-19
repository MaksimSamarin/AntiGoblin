#!/bin/sh
# Exercise the real cron script using an isolated filesystem and fake services.
set -eu
REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FIX="$(mktemp -d)"
trap 'code=$?; if [ "$code" -ne 0 ]; then cat "$FIX/opt/var/log/xkeen-subscription-refresh.log" "$FIX/isolated-checks" "$FIX/restarts" >&2; fi; rm -rf "$FIX"' EXIT
REAL_SLEEP="$(command -v sleep)"
REAL_JQ="$(command -v jq)"
export FIX REAL_SLEEP REAL_JQ
APP="$FIX/opt/share/xkeen-manager"
XRAY="$FIX/opt/etc/xray/configs"
SB="$FIX/opt/etc/sing-box/xkeen.json"
STATE="$APP/xkeen-ui-state.json"
LOG="$FIX/opt/var/log/xkeen-subscription-refresh.log"
mkdir -p "$APP/api" "$XRAY" "$(dirname "$SB")" "$FIX/opt/etc/init.d" \
  "$FIX/opt/bin" "$FIX/opt/sbin" "$FIX/opt/var/log" "$FIX/opt/var/run" "$FIX/tmp"
tr -d '\r' < "$REPO/scripts/xkeen/antigoblin-subscription-refresh.sh" |
  sed "s@/opt/@$FIX/opt/@g; s@/tmp/xkeen-@$FIX/tmp/xkeen-@g" > "$FIX/antigoblin-subscription-refresh.sh"
touch "$APP/app.js" "$APP/api/subscription-refresh.js" "$APP/api/subscription-candidate.js"
cat > "$FIX/opt/bin/jq" <<'JQ'
#!/bin/sh
case "$(uname -s)" in MINGW*|MSYS*) exec "$REAL_JQ" -b "$@" ;; esac
exec "$REAL_JQ" "$@"
JQ

cat > "$APP/api/xkeen-runtime.sh" <<'RUNTIME'
XKEEN_LOCK_DIR="$FIX/runtime.lock"
XKEEN_REDIRECT_PORT=61219
xkeen_lock_acquire() { mkdir "$XKEEN_LOCK_DIR"; }
xkeen_lock_release() { rmdir "$XKEEN_LOCK_DIR"; }
xkeen_tproxy_ready() { [ -f "$FIX/udp" ]; }
RUNTIME
cat > "$FIX/opt/bin/date" <<'DATE'
#!/bin/sh
case "$1" in +%s) echo "$NOW" ;; +%s000) echo "$NOW"000 ;; *) echo time ;; esac
DATE
cat > "$FIX/opt/bin/sleep" <<'SLEEP'
#!/bin/sh
"$REAL_SLEEP" 0.10
SLEEP
cat > "$FIX/opt/bin/netstat" <<'NETSTAT'
#!/bin/sh
if [ -s "$FIX/redirect-pid" ]; then
  printf 'tcp 0 0 0.0.0.0:61219 0.0.0.0:* LISTEN %s/xray\n' "$(cat "$FIX/redirect-pid")"
fi
if [ -s "$FIX/test-pid" ]; then
  printf 'tcp 0 0 127.0.0.1:62080 0.0.0.0:* LISTEN %s/xray\n' "$(cat "$FIX/test-pid")"
fi
NETSTAT
cat > "$FIX/opt/bin/qjs" <<'QJS'
#!/bin/sh
test ! -d "$FIX/runtime.lock" || exit 51
test "$5" = "$FIX/opt/share/xkeen-manager/app.js" || test "$6" = "$FIX/opt/share/xkeen-manager/app.js" || exit 52
test -d "$5" || exit 53
printf '%s\n' "$4" >> "$FIX/isolated-checks"
for file in outbounds routing singbox; do printf '%s\n' "$4" > "$5/$file.json"; done
echo '{"protocol":"vless"}' > "$5/candidate.json"
QJS
cat > "$FIX/opt/sbin/xray" <<'XRAY_BIN'
#!/bin/sh
if [ "$2" = '-test' ]; then
  case "$4" in */switch-config) [ "$INVALID_CONFIG" != yes ] || exit 23 ;; esac
  exit 0
fi
printf '%s\n' "$$" > "$FIX/test-pid"
exec "$REAL_SLEEP" 120
XRAY_BIN
cat > "$FIX/opt/sbin/sing-box" <<'SINGBOX'
#!/bin/sh
test "$1" = check
SINGBOX
cat > "$FIX/opt/bin/curl" <<'CURL'
#!/bin/sh
printf '%s\n' "$*" >> "$FIX/probes"
case "$*" in
  *:62080*)
    test ! -d "$FIX/runtime.lock" || exit 54
    if [ "$STATE_CHANGE" = yes ]; then echo ' ' >> "$FIX/opt/share/xkeen-manager/xkeen-ui-state.json"; fi
    test "$CANDIDATES_REACHABLE" = yes ;;
  *:61080*)
    if test -d "$FIX/runtime.lock"; then
      test "$LIVE_PROBE" = ok
    else
      test "$ACTIVE_PROBE" = ok
    fi ;;
  *) exit 55 ;;
esac
CURL
# The stock init starts Xray without Geo assets; failover must not use it.
cat > "$FIX/opt/etc/init.d/S24xray" <<'INIT'
#!/bin/sh
touch "$FIX/s24xray-used"
exit 1
INIT
cat > "$FIX/opt/bin/killall" <<'KILLALL'
#!/bin/sh
exit 0
KILLALL
cat > "$FIX/opt/sbin/start-stop-daemon" <<'SSD'
#!/bin/sh
test -d "$FIX/runtime.lock" || exit 56
# Geo rules need the asset directory used by self-heal and Save & Apply.
test "$XRAY_LOCATION_ASSET" = "$FIX/opt/etc/xray/dat" || exit 57
test "$XRAY_LOCATION_CONFDIR" = "$FIX/opt/etc/xray/configs" || exit 58
selected="$(cat "$FIX/opt/etc/xray/configs/04_outbounds.json")"
printf '%s\n' "$selected" >> "$FIX/restarts"
case "$selected" in
  old) mode="$ROLLBACK_MODE" ;;
  *) mode="$PROMOTION_MODE" ;;
esac
case "$mode" in
  no-bind) rm -f "$FIX/redirect-pid"; exit 0 ;;
  old-process) exit 0 ;;
esac
wc -l < "$FIX/restarts" | awk '{print $1+100}' > "$FIX/redirect-pid"
SSD
cat > "$FIX/opt/etc/init.d/S24antigoblin-singbox" <<'SB_INIT'
#!/bin/sh
touch "$FIX/udp"
SB_INIT
chmod +x "$FIX/opt/bin/"* "$FIX/opt/sbin/"* "$FIX/opt/etc/init.d/"*

reset_fixture() {
  cat > "$STATE" <<'JSON'
{"activeProfileId":"p","profiles":[{"id":"p","activeProxyId":"old","subscriptions":[{"id":"s","url":"https://example.test/","autoRefresh":true,"autoFailover":true,"lastFetched":10000000}],"proxies":[{"id":"old","source":"s"},{"id":"a","source":"s"},{"id":"b","source":"s"}]}]}
JSON
  cp "$STATE" "$FIX/original"
  for f in "$XRAY/04_outbounds.json" "$XRAY/05_routing.json" "$SB"; do echo old > "$f"; done
  echo 99 > "$FIX/redirect-pid"
  touch "$FIX/udp"
  : > "$FIX/isolated-checks"; : > "$FIX/probes"; : > "$FIX/restarts"; : > "$LOG"
  rm -f "$FIX"/tmp/xkeen-subscription-probe.state "$FIX"/tmp/xkeen-subscription-failover-cursor \
    "$FIX"/tmp/xkeen-xray-failover-recovery "$FIX/test-pid"
  export ACTIVE_PROBE=bad LIVE_PROBE=ok CANDIDATES_REACHABLE=yes STATE_CHANGE=no \
    INVALID_CONFIG=no PROMOTION_MODE=ok ROLLBACK_MODE=ok
}
tick() {
  export NOW="$1"
  if ! sh "$FIX/antigoblin-subscription-refresh.sh"; then
    cat "$LOG" >&2
    return 1
  fi
  test ! -d "$FIX/runtime.lock"
  test ! -d "$FIX/tmp/xkeen-subscription-refresh.lock"
}
no_restart() { test ! -s "$FIX/restarts"; }
three_failures() { tick 10000; tick 10060; tick 10120; }

# VPN probe cadence is independent from the six-hour subscription refresh.
reset_fixture
export ACTIVE_PROBE=ok
tick 10000
tick 10899
test "$(wc -l < "$FIX/probes")" -eq 1
tick 10900
test "$(wc -l < "$FIX/probes")" -eq 2
no_restart

# A transient probe failure recovers without a switch. Three failed ticks
# at minute intervals allow a promotion.
reset_fixture
tick 10000; tick 10059; no_restart
export ACTIVE_PROBE=ok
tick 10060; no_restart
test "$(cat "$FIX/tmp/xkeen-subscription-probe.state")" = 'p:old 10060 0'
export ACTIVE_PROBE=bad
tick 10960; tick 11020; no_restart
tick 11080
test "$(cat "$FIX/restarts")" = a
jq -e '.profiles[0].activeProxyId == "a"' "$STATE" >/dev/null

# If no VPN candidate is reachable, the ordinary TCP listener is untouched.
reset_fixture
export CANDIDATES_REACHABLE=no
three_failures
no_restart
test "$(cat "$FIX/redirect-pid")" = 99
cmp "$FIX/original" "$STATE"
grep -q 'no_reachable_candidate' "$LOG"

# A failed live promotion is rolled back once, and the next eligible
# round rotates to another candidate. No second live restart in this tick.
reset_fixture
export PROMOTION_MODE=no-bind
three_failures
test "$(cat "$FIX/restarts")" = "$(printf 'a\nold')"
cmp "$FIX/original" "$STATE"
test "$(cat "$XRAY/05_routing.json")" = old
test "$(cat "$SB")" = old
grep -q 'candidate listeners_not_ready' "$LOG"
grep -q 'rollback_restored' "$LOG"
tick 10180
test "$(wc -l < "$FIX/restarts")" -eq 2
export PROMOTION_MODE=ok
tick 11020; tick 11080; tick 11140
test "$(tail -n 1 "$FIX/restarts")" = b

# Two failed starts hand off to self-heal and leave the old config on disk.
reset_fixture
export PROMOTION_MODE=no-bind ROLLBACK_MODE=no-bind
three_failures
grep -q 'rollback_unhealthy' "$LOG"
test -f "$FIX/tmp/xkeen-xray-failover-recovery"
cmp "$FIX/original" "$STATE"
test "$(cat "$XRAY/04_outbounds.json")" = old
test "$(wc -l < "$FIX/restarts")" -eq 2
tick 10180
test "$(wc -l < "$FIX/restarts")" -eq 2

reset_fixture
export PROMOTION_MODE=old-process
three_failures
test "$(cat "$FIX/restarts")" = "$(printf 'a\nold')"
cmp "$FIX/original" "$STATE"

# Bad config and simultaneous UI edits are rejected before touching live.
reset_fixture
export INVALID_CONFIG=yes
three_failures
no_restart
grep -q 'config_invalid' "$LOG"
reset_fixture
export STATE_CHANGE=yes
three_failures
no_restart
grep -q 'configuration changed during checks' "$LOG"

# A removed key can be replaced without waiting for probe failures, yet
# a failed promotion cannot repeatedly restart the runtime on cron ticks.
reset_fixture
jq '.profiles[0].proxies[0].stale = true' "$STATE" > "$FIX/stale.json"
cp "$FIX/stale.json" "$STATE"
export LIVE_PROBE=bad
tick 10000; tick 10060
test "$(wc -l < "$FIX/restarts")" -eq 2
cmp "$FIX/stale.json" "$STATE"

# No scenario may restart Xray through the asset-less stock init script.
test ! -e "$FIX/s24xray-used"
echo 'PASS: failover cadence, independent probes, verified rollback, Geo-safe Xray start, and safe concurrent edits'
