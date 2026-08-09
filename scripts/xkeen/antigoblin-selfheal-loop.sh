#!/bin/sh
# antigoblin-selfheal-loop — 15s-cadence driver for xkeen-selfheal.sh.
# Runs as an S25 init.d service, one instance per boot.

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

SELFHEAL="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"
LOG=/opt/var/log/xkeen-selfheal.log

# Hard timeout per tick. xkeen-selfheal.sh in a healthy cycle finishes in
# <2 seconds; anything past a couple of minutes means it hung on nslookup,
# a stuck subprocess, or lock acquisition. Without a wall-clock cap the
# whole loop stalls (we observed a ~9h freeze in the wild — the bypass
# ipset stopped refreshing, and new bypass domains never took effect).
# `timeout -k 5 180` sends SIGTERM at 180s, SIGKILL 5s later if the tick
# still hasn't exited. Both /opt/bin/timeout (coreutils) and BusyBox's
# built-in `timeout` accept these flags.
SELFHEAL_TICK_TIMEOUT="${SELFHEAL_TICK_TIMEOUT:-180}"

# Try to prefer /opt/bin/timeout (coreutils-timeout) — it's the one
# xkeen-runtime.sh relies on for DNS. Fall back to plain `timeout` (or
# nothing) if it's absent.
TIMEOUT_BIN=""
if [ -x /opt/bin/timeout ]; then
  TIMEOUT_BIN="/opt/bin/timeout"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
fi

log_watchdog() {
  # Best-effort append to the same log the selfheal script writes to, so
  # anyone tail-ing it sees the watchdog event in-line with normal repair
  # markers. If /opt is unmounted, this silently no-ops.
  printf '%s selfheal-loop: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null || true
}

while true; do
  if [ -x "$SELFHEAL" ]; then
    if [ -n "$TIMEOUT_BIN" ]; then
      "$TIMEOUT_BIN" -k 5 "$SELFHEAL_TICK_TIMEOUT" "$SELFHEAL" >/dev/null 2>&1
      RC=$?
      # coreutils-timeout returns 124 on SIGTERM, 137 on SIGKILL.
      case "$RC" in
        0) ;;
        124|137) log_watchdog "watchdog killed selfheal tick (rc=$RC, limit=${SELFHEAL_TICK_TIMEOUT}s)" ;;
        *) : ;;  # non-zero from selfheal itself — its own log tells the story
      esac
    else
      "$SELFHEAL" >/dev/null 2>&1 || true
    fi
  fi
  sleep 15
done
