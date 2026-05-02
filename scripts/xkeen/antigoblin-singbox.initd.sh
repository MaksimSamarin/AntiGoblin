#!/bin/sh

ENABLED=yes
PROCS=sing-box
ARGS="run -c /opt/etc/sing-box/xkeen.json"
PREARGS=""
DESC="AntiGoblin sing-box UDP relay"
PATH="/opt/bin:/opt/sbin:/sbin:/usr/sbin:/bin:/usr/bin"

. /opt/etc/init.d/rc.func
