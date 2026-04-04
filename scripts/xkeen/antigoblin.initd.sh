#!/bin/sh

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

PORT="8899"
ROOT_DIR="/opt/share/xkeen-manager"
LOG_FILE="/opt/var/log/xkeen-manager-uhttpd.log"
SELFHEAL="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"

is_running() {
  netstat -lnpt 2>/dev/null | grep -q ":$PORT "
}

start_ui() {
  mkdir -p /opt/var/log /opt/var/run "$ROOT_DIR" 2>/dev/null || true

  if is_running; then
    echo "antigoblin already listening on $PORT"
    [ -x "$SELFHEAL" ] && "$SELFHEAL" --force >/dev/null 2>&1 || true
    return 0
  fi

  rm -f "$ROOT_DIR/httpd-auth.conf" 2>/dev/null || true
  : > "$LOG_FILE"

  cd "$ROOT_DIR" || return 1
  /opt/sbin/uhttpd -f -p 0.0.0.0:$PORT -h "$ROOT_DIR" -I index.html -x /api -i .cgi=/bin/sh -r 'AntiGoblin' >>"$LOG_FILE" 2>&1 &
  sleep 2

  if is_running; then
    [ -x "$SELFHEAL" ] && "$SELFHEAL" --force >/dev/null 2>&1 || true
    return 0
  fi

  tail -n 20 "$LOG_FILE" 2>/dev/null || true
  return 1
}

stop_ui() {
  pkill -f "/opt/sbin/uhttpd -f -p 0.0.0.0:$PORT" 2>/dev/null || true
}

case "$1" in
  start)
    start_ui
    ;;
  stop)
    stop_ui
    ;;
  restart)
    stop_ui
    sleep 1
    start_ui
    ;;
  status)
    if is_running; then
      echo "antigoblin running on $PORT"
      exit 0
    fi
    echo "antigoblin not running"
    exit 1
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
