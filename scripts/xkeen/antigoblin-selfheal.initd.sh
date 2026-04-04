#!/bin/sh

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

DAEMON="/opt/share/xkeen-manager/api/xkeen-selfheal-loop.sh"
PIDFILE="/opt/var/run/antigoblin-selfheal-loop.pid"

is_running() {
  [ -f "$PIDFILE" ] || return 1
  PID="$(cat "$PIDFILE" 2>/dev/null)"
  [ -n "$PID" ] || return 1
  kill -0 "$PID" 2>/dev/null
}

start_loop() {
  mkdir -p /opt/var/run /opt/var/log 2>/dev/null || true
  [ -x "$DAEMON" ] || return 1

  if is_running; then
    return 0
  fi

  /opt/sbin/start-stop-daemon -S -b -m -p "$PIDFILE" -x "$DAEMON"
  sleep 1
  is_running
}

stop_loop() {
  if [ -f "$PIDFILE" ]; then
    /opt/sbin/start-stop-daemon -K -p "$PIDFILE" 2>/dev/null || true
    rm -f "$PIDFILE" 2>/dev/null || true
  fi
}

case "$1" in
  start)
    start_loop
    ;;
  stop)
    stop_loop
    ;;
  restart)
    stop_loop
    sleep 1
    start_loop
    ;;
  status)
    if is_running; then
      echo "antigoblin-selfheal running"
      exit 0
    fi
    echo "antigoblin-selfheal not running"
    exit 1
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
