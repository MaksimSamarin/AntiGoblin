#!/bin/sh

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

XRAY_INIT="/opt/etc/init.d/S24xray"
SELFHEAL_INIT="/opt/etc/init.d/S25antigoblin-selfheal"
UI_INIT="/opt/etc/init.d/S26antigoblin"
SELFHEAL="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"
ROOT_DIR="/opt/share/xkeen-manager"

find_cron_init() {
  for candidate in /opt/etc/init.d/S10cron /opt/etc/init.d/S05crond; do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

cron_running() {
  ps | grep -E '[[:space:]](cron|crond)([[:space:]]|$)' | grep -v grep >/dev/null 2>&1
}

[ -d /opt ] || exit 0
[ -d "$ROOT_DIR" ] || exit 0

[ -x "$SELFHEAL_INIT" ] && "$SELFHEAL_INIT" restart >/dev/null 2>&1 || true

if ! cron_running; then
  CRON_INIT="$(find_cron_init 2>/dev/null || true)"
  [ -x "$CRON_INIT" ] && "$CRON_INIT" restart >/dev/null 2>&1 || true
fi

if ! netstat -lnpt 2>/dev/null | grep -q ':61219 '; then
  [ -x "$XRAY_INIT" ] && "$XRAY_INIT" restart >/dev/null 2>&1 || true
fi

if ! netstat -lnpt 2>/dev/null | grep -q ':8899 '; then
  [ -x "$UI_INIT" ] && "$UI_INIT" restart >/dev/null 2>&1 || true
fi

[ -x "$SELFHEAL" ] && "$SELFHEAL" --force >/dev/null 2>&1 || true
