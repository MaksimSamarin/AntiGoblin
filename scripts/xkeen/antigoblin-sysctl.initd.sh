#!/bin/sh
# AntiGoblin TCP/conntrack timing tweaks.
#
# Why these values:
# Default Linux TCP timeouts assume long-lived sessions on stable links.
# A home VPN router proxies many short HTTPS / RTC flows to a remote
# VLESS server. Default keepalive (2 hours) and FIN_WAIT (60s) cause
# closed flows to occupy file descriptors and conntrack slots much
# longer than necessary. Over hours, xray accumulates FDs in FIN_WAIT
# state and starts misbehaving well below the actual FD limit.
#
# These tweaks let dead and closed sockets be reaped within seconds,
# keeping the FD budget healthy without changing user-visible behavior.
# Conservative values, safe for typical home traffic.
#
# Apply on every boot via Entware init order. Idempotent: re-running
# is harmless.

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

LOG_PATH="/opt/var/log/xkeen-sysctl.log"

apply_sysctl() {
  KEY="$1"
  VAL="$2"
  PROCFS="/proc/sys/$(printf '%s' "$KEY" | tr '.' '/')"
  [ -w "$PROCFS" ] || return 0
  CURRENT="$(cat "$PROCFS" 2>/dev/null)"
  [ "$CURRENT" = "$VAL" ] && return 0
  if printf '%s' "$VAL" > "$PROCFS" 2>/dev/null; then
    printf '%s set %s %s -> %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$KEY" "${CURRENT:-?}" "$VAL" >> "$LOG_PATH"
  else
    printf '%s FAIL %s = %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$KEY" "$VAL" >> "$LOG_PATH"
  fi
}

# Lower a sysctl only if the current value is greater than the target.
# Used for limits where Keenetic ships a sane (low) value on some
# models but Linux defaults are very high on others.
lower_sysctl() {
  KEY="$1"
  CEIL="$2"
  PROCFS="/proc/sys/$(printf '%s' "$KEY" | tr '.' '/')"
  [ -r "$PROCFS" ] || return 0
  CURRENT="$(cat "$PROCFS" 2>/dev/null)"
  case "$CURRENT" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ "$CURRENT" -gt "$CEIL" ] || return 0
  apply_sysctl "$KEY" "$CEIL"
}

apply_all() {
  mkdir -p /opt/var/log 2>/dev/null || true

  # Detect dead TCP peers faster. Some Keenetic models ship 120s
  # already (good); generic Linux is 7200s (bad for a router with
  # many short-lived flows). Cap at 300s either way — far enough to
  # avoid spurious churn on healthy idle TCP, soon enough to free
  # FDs from disappeared VPN servers within a few minutes.
  lower_sysctl net.ipv4.tcp_keepalive_time 300
  lower_sysctl net.ipv4.tcp_keepalive_intvl 30
  lower_sysctl net.ipv4.tcp_keepalive_probes 3

  # Drop FIN_WAIT2 sockets faster. VPN tunnel connections that the peer
  # never properly closes (orphan FIN) should be reaped in ~10s rather
  # than 30s to prevent pileup when many short-lived flows close at once.
  lower_sysctl net.ipv4.tcp_fin_timeout 10

  # Orphan sockets retry up to 2 times instead of the kernel default
  # (typically 7-15). Speeds up cleanup after xray restart.
  apply_sysctl net.ipv4.tcp_orphan_retries 2

  # Conntrack timeouts for closed connections. Tighten FIN_WAIT and
  # TIME_WAIT so slots are freed quickly after VPN tunnel teardown.
  lower_sysctl net.netfilter.nf_conntrack_tcp_timeout_fin_wait 15
  lower_sysctl net.netfilter.nf_conntrack_tcp_timeout_time_wait 15
  lower_sysctl net.netfilter.nf_conntrack_tcp_timeout_close_wait 10
  lower_sysctl net.netfilter.nf_conntrack_tcp_timeout_last_ack 15
}

case "$1" in
  start|reload|"")
    apply_all
    ;;
  stop)
    : # nothing — defaults stay until reboot or manual sysctl reset
    ;;
  status)
    for k in \
      net.ipv4.tcp_keepalive_time \
      net.ipv4.tcp_keepalive_intvl \
      net.ipv4.tcp_keepalive_probes \
      net.ipv4.tcp_fin_timeout \
      net.ipv4.tcp_orphan_retries \
      net.netfilter.nf_conntrack_tcp_timeout_fin_wait \
      net.netfilter.nf_conntrack_tcp_timeout_time_wait \
      net.netfilter.nf_conntrack_tcp_timeout_close_wait \
      net.netfilter.nf_conntrack_tcp_timeout_last_ack
    do
      pf="/proc/sys/$(printf '%s' "$k" | tr '.' '/')"
      v="$(cat "$pf" 2>/dev/null || printf '?')"
      printf '%s = %s\n' "$k" "$v"
    done
    ;;
  *)
    echo "Usage: $0 {start|stop|reload|status}"
    exit 1
    ;;
esac
