#!/bin/sh

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

SELFHEAL="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"
GEODATA="/opt/share/xkeen-manager/api/antigoblin-geodata.sh"
SUBSCRIPTION_REFRESH="/opt/share/xkeen-manager/api/antigoblin-subscription-refresh.sh"

[ -x "$SELFHEAL" ] || exit 0

"$SELFHEAL" >/dev/null 2>&1 || true
[ -x "$GEODATA" ] && "$GEODATA" cron >/dev/null 2>&1 || true
[ -x "$SUBSCRIPTION_REFRESH" ] && "$SUBSCRIPTION_REFRESH" >/dev/null 2>&1 || true
