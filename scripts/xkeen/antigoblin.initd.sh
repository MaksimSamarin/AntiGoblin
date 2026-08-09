#!/bin/sh

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

# Port defaults to 8899 but can be overridden via /opt/etc/antigoblin.conf
# (written by install.sh from $ANTIGOBLIN_UI_PORT). Keeps install.sh's summary
# URL and the actual bound port in sync.
PORT="8899"
if [ -r /opt/etc/antigoblin.conf ]; then
  # Parse PORT=NNN safely (no `source` — that would execute arbitrary shell
  # if the file were tampered with, and would also silently propagate a
  # non-numeric or empty PORT into `is_running` where `grep -q ": "` would
  # match any listener).
  _cfg_port="$(awk -F= '$1=="PORT" && $2 ~ /^[0-9]+$/ { gsub(/[^0-9]/,"",$2); print $2; exit }' /opt/etc/antigoblin.conf 2>/dev/null)"
  case "$_cfg_port" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$_cfg_port" -ge 1 ] && [ "$_cfg_port" -le 65535 ]; then
        PORT="$_cfg_port"
      fi
      ;;
  esac
fi
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
  # -t 120 (CGI), -T 120 (network): default 60/30 was too short for full
  # Save+Apply (rebuilds ~700 ipset CIDRs + xray reload), users hit Bad
  # Gateway mid-save when crossing the 60s CGI window.
  /opt/sbin/uhttpd -f -p 0.0.0.0:$PORT -h "$ROOT_DIR" -I index.html -x /api -i .cgi=/bin/sh -r 'AntiGoblin' -t 120 -T 120 >>"$LOG_FILE" 2>&1 &
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
