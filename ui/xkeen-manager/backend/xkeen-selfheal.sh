#!/bin/sh

LOG_PATH="/opt/var/log/xkeen-selfheal.log"
XRAY_BIN="/opt/sbin/xray"
XRAY_ASSET_DIR="/opt/etc/xray/dat"
XRAY_CONF_DIR="/opt/etc/xray/configs"
LOCK_DIR="/tmp/xkeen-selfheal.lock"

needs_repair=0
force_mode=0

if [ "$1" = "--force" ]; then
  force_mode=1
fi

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_PATH"
}

has_rule() {
  "$@" >/dev/null 2>&1
}

xray_ready() {
  netstat -lnptu 2>/dev/null | grep -q '61219' && \
  netstat -lnptu 2>/dev/null | grep -q '61220'
}

check_runtime() {
  has_rule iptables -t nat -S xkeen || needs_repair=1
  has_rule iptables -t nat -C PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen || needs_repair=1
  has_rule iptables -t nat -C PREROUTING -m connmark --mark 0xffffaac -m conntrack ! --ctstate INVALID -j xkeen || needs_repair=1
  has_rule iptables -t mangle -S xkeen_udp || needs_repair=1
  has_rule iptables -t mangle -C PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp || needs_repair=1
  has_rule iptables -t mangle -C PREROUTING -m connmark --mark 0xffffaac -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp || needs_repair=1
  ip rule show | grep -q 'fwmark 0x111 lookup 111' || needs_repair=1
  xray_ready || needs_repair=1
}

repair_hooks() {
  iptables -t nat -N xkeen 2>/dev/null || true
  iptables -t nat -F xkeen 2>/dev/null || true
  iptables -t nat -A xkeen -d 192.168.1.102/32 -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -p tcp -j REDIRECT --to-ports 61219 2>/dev/null || true
  iptables -t nat -C PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen
  iptables -t nat -C PREROUTING -m connmark --mark 0xffffaac -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -m connmark --mark 0xffffaac -m conntrack ! --ctstate INVALID -j xkeen

  ip rule add fwmark 0x111 lookup 111 2>/dev/null || true
  ip route add local default dev lo table 111 2>/dev/null || true

  iptables -t mangle -N xkeen_udp 2>/dev/null || true
  iptables -t mangle -F xkeen_udp 2>/dev/null || true
  iptables -t mangle -A xkeen_udp -d 192.168.1.102/32 -j RETURN 2>/dev/null || true
  iptables -t mangle -A xkeen_udp -p udp -m socket --transparent -j MARK --set-mark 0x111 2>/dev/null || true
  iptables -t mangle -A xkeen_udp -p udp -j TPROXY --on-ip 0.0.0.0 --on-port 61220 --tproxy-mark 0x111 2>/dev/null || true
  iptables -t mangle -C PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp 2>/dev/null || \
    iptables -t mangle -I PREROUTING 1 -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp
  iptables -t mangle -C PREROUTING -m connmark --mark 0xffffaac -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp 2>/dev/null || \
    iptables -t mangle -I PREROUTING 1 -m connmark --mark 0xffffaac -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp
}

restart_xray() {
  killall xray 2>/dev/null || true
  sleep 1
  XRAY_LOCATION_ASSET="$XRAY_ASSET_DIR" XRAY_LOCATION_CONFDIR="$XRAY_CONF_DIR" \
    /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/xray-ui.pid -x "$XRAY_BIN" -- run >>"$LOG_PATH" 2>&1
  sleep 3
}

repair_runtime() {
  log "repair start"

  repair_hooks

  if ! xray_ready; then
    log "xray restart needed"
    restart_xray
  fi

  if xray_ready; then
    log "repair done"
    return 0
  fi

  log "repair failed"
  return 1
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi

trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM

check_runtime

if [ "$force_mode" -eq 1 ] || [ "$needs_repair" -eq 1 ]; then
  repair_runtime
  exit $?
fi

exit 0
