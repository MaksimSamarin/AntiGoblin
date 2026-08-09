#!/bin/sh
# NDM netfilter.d hook. Runs whenever KeeneticOS reloads netfilter (WAN
# reconnect, WiFi client join/leave, firewall changes in UI, etc). NDM
# often rebuilds mangle PREROUTING and our TPROXY-tail rule for UDP-route
# gets bumped out of the last position — pushing the first UDP packet of
# a Discord voice call through WAN direct, which the server sees as a
# NAT flap and drops the call for 1-3 seconds.
#
# This hook makes the recovery instant (~5-10ms) instead of waiting up to
# 15s for the next self-heal cycle. It only re-adds the PREROUTING jump;
# it does NOT rebuild ipsets (self-heal owns that).
#
# NDM invokes: /opt/etc/ndm/netfilter.d/<name>.sh with env vars including
# `$table` and `$hook`. We only care about mangle-table changes.

[ -f /opt/share/xkeen-manager/api/xkeen-runtime.sh ] || exit 0

case "${table:-mangle}" in
  mangle|"") ;;
  *) exit 0 ;;
esac

# shellcheck disable=SC1091
. /opt/share/xkeen-manager/api/xkeen-runtime.sh || exit 0

# Take the shared lock. If selfheal / apply / another hook holds it, they
# will restore the tail rule as part of their run.
xkeen_lock_acquire || exit 0
trap 'xkeen_lock_release' EXIT INT TERM

# Prefer the cache written by selfheal / apply on every successful ndmc
# lookup. Circular dependency: this hook runs when NDMS reloads netfilter;
# ndmc talks to NDMS; dialing ndmc from inside the reload can stall for
# seconds, defeating the whole point of the hook (fast tail-rule restore).
# Only fall back to ndmc if we've never seen a mark yet.
MARK="$(cat /tmp/xkeen-mark 2>/dev/null)"
if [ -z "$MARK" ]; then
  MARK="$(xkeen_get_mark 2>/dev/null)"
fi
[ -n "$MARK" ] || exit 0

ipset list "$XKEEN_UDP_ROUTE_SET" -terse >/dev/null 2>&1 || exit 0

LAST_RULE="$(iptables -t mangle -S PREROUTING 2>/dev/null | tail -n 1)"
case "$LAST_RULE" in
  *xkeen_udp_route*) exit 0 ;;
esac

xkeen_delete_jumps mangle PREROUTING xkeen_udp_route
if ! iptables -t mangle -A PREROUTING \
  -m connmark --mark "0x$MARK" \
  -m conntrack ! --ctstate INVALID \
  -p udp \
  -m set --match-set "$XKEEN_UDP_ROUTE_SET" dst \
  -j xkeen_udp_route 2>/dev/null; then
  xkeen_runtime_log "netfilter_hook: iptables_fail PREROUTING xkeen_udp_route (mark=0x$MARK)"
fi

exit 0
