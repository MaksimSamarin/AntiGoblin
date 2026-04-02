#!/bin/sh

LOG_PATH="/opt/var/log/xkeen-selfheal.log"
XRAY_BIN="/opt/sbin/xray"
XRAY_ASSET_DIR="/opt/etc/xray/dat"
XRAY_CONF_DIR="/opt/etc/xray/configs"
STATE_PATH="/opt/share/xkeen-manager/xkeen-ui-state.json"
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

build_bypass_ipset() {
  ipset create xkeen_bypass hash:net family inet -exist
  ipset flush xkeen_bypass 2>/dev/null || true

  cat <<'EOF' | while IFS= read -r domain; do
api.io.mi.com
api.home.mi.com
home.mi.com
ot.io.mi.com
app.chat.global.xiaomi.net
resolver.msg.global.xiaomi.net
data.mistat.xiaomi.com
EOF
    [ -n "$domain" ] || continue
    nslookup "$domain" 2>/dev/null | /opt/bin/awk '
      /^Name:/ { seen_name=1; next }
      seen_name && /^Address [0-9]+: / { print $3; next }
      seen_name && /^Address: / { print $2; next }
    ' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -Ev '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' | while IFS= read -r ip; do
      [ -n "$ip" ] || continue
      ipset add xkeen_bypass "$ip"/32 -exist 2>/dev/null || true
    done
  done

  cat <<'EOF' | while IFS= read -r ip; do
5.28.195.2
47.241.213.210
EOF
    [ -n "$ip" ] || continue
    ipset add xkeen_bypass "$ip"/32 -exist 2>/dev/null || true
  done
}

check_runtime() {
  has_rule iptables -t nat -S xkeen || needs_repair=1
  has_rule iptables -t nat -C PREROUTING -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -j xkeen || needs_repair=1
  has_rule iptables -t nat -C xkeen -d 192.168.2.0/24 -j RETURN || needs_repair=1
  has_rule iptables -t nat -C xkeen -d 224.0.0.0/4 -j RETURN || needs_repair=1
  has_rule iptables -t nat -C xkeen -d 255.255.255.255/32 -j RETURN || needs_repair=1
  has_rule iptables -t nat -C xkeen -p tcp -m set --match-set xkeen_bypass dst -j RETURN || needs_repair=1
  has_rule iptables -t nat -C xkeen -p tcp -j REDIRECT --to-ports 61219 || needs_repair=1
  has_rule iptables -t nat -C xkeen -j RETURN || needs_repair=1
  has_rule ipset list xkeen_bypass || needs_repair=1
  xray_ready || needs_repair=1
}

repair_hooks() {
  build_bypass_ipset
  iptables -t nat -N xkeen 2>/dev/null || true
  iptables -t nat -F xkeen 2>/dev/null || true
  iptables -t nat -A xkeen -d 192.168.2.0/24 -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -d 224.0.0.0/4 -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -d 255.255.255.255/32 -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -d 192.168.1.102/32 -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -p tcp -m set --match-set xkeen_bypass dst -j RETURN 2>/dev/null || true
  iptables -t nat -A xkeen -p tcp -j REDIRECT --to-ports 61219 2>/dev/null || true
  iptables -t nat -A xkeen -j RETURN 2>/dev/null || true
  iptables -t nat -D PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || true
  iptables -t nat -C PREROUTING -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -j xkeen 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -j xkeen

  while ip rule show | grep -q 'fwmark 0x111 lookup 111'; do
    ip rule del fwmark 0x111 lookup 111 2>/dev/null || break
  done

  iptables -t mangle -D PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp 2>/dev/null || true
  iptables -t mangle -D PREROUTING -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp 2>/dev/null || true
  iptables -t mangle -F xkeen_udp 2>/dev/null || true
  iptables -t mangle -X xkeen_udp 2>/dev/null || true

  iptables -t mangle -D PREROUTING -m connmark --mark 0xffffaaa -m conntrack ! --ctstate INVALID -p udp -j xkeen_quic 2>/dev/null || true
  iptables -t mangle -F xkeen_quic 2>/dev/null || true
  iptables -t mangle -X xkeen_quic 2>/dev/null || true

  ipset destroy xkeen_vpn 2>/dev/null || true
  ipset destroy xkeen_quic_bypass 2>/dev/null || true
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
