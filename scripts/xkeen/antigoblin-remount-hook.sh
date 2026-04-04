#!/bin/sh

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

XRAY_INIT="/opt/etc/init.d/S24xray"
UI_INIT="/opt/etc/init.d/S26antigoblin"
SELFHEAL="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"
ROOT_DIR="/opt/share/xkeen-manager"

[ -d /opt ] || exit 0
[ -d "$ROOT_DIR" ] || exit 0

if ! netstat -lnpt 2>/dev/null | grep -q ':61219 '; then
  [ -x "$XRAY_INIT" ] && "$XRAY_INIT" restart >/dev/null 2>&1 || true
fi

if ! netstat -lnpt 2>/dev/null | grep -q ':8899 '; then
  [ -x "$UI_INIT" ] && "$UI_INIT" restart >/dev/null 2>&1 || true
fi

[ -x "$SELFHEAL" ] && "$SELFHEAL" --force >/dev/null 2>&1 || true
