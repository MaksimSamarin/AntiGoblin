#!/bin/sh

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

SELFHEAL="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"

[ -x "$SELFHEAL" ] || exit 0

"$SELFHEAL" >/dev/null 2>&1 || true
