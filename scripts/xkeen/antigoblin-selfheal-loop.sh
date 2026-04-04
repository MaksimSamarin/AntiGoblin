#!/bin/sh

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

SELFHEAL="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"

while true; do
  [ -x "$SELFHEAL" ] && "$SELFHEAL" >/dev/null 2>&1 || true
  sleep 15
done
