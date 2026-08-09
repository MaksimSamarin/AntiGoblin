#!/bin/sh
# NDM fs.d / usb.d hook. Runs when /opt (Entware) is (re-)mounted.
# Purpose: bring the AntiGoblin stack back up after a USB remount or the
# initial filesystem availability signal.
#
# Historically installed to BOTH /opt/etc/ndm/fs.d/ AND /opt/etc/ndm/usb.d/,
# which caused two near-simultaneous invocations racing against each other.
# install.sh + deploy_backend.ps1 now only place this hook in usb.d/
# (fs.d/ was removed).
#
# We deliberately DO NOT take the shared xkeen selfheal lock here. All the
# work below is init.d restart (idempotent) + confdir sed (guarded by a
# grep for the target string, safe to re-run). None of it touches iptables
# or ipset. Grabbing the lock only made selfheal / netfilter-hook ticks
# starve us on a mount event — with `... || exit 0` we'd silently skip the
# restart cascade and leave xray/UI down until the next cron tick. The
# final `selfheal --force` at the end takes its own lock the normal way.

PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

XRAY_INIT="/opt/etc/init.d/S24xray"
SELFHEAL_INIT="/opt/etc/init.d/S25antigoblin-selfheal"
UI_INIT="/opt/etc/init.d/S26antigoblin"
SELFHEAL="/opt/share/xkeen-manager/api/xkeen-selfheal.sh"
ROOT_DIR="/opt/share/xkeen-manager"

find_cron_init() {
  for candidate in /opt/etc/init.d/S10cron /opt/etc/init.d/S05crond; do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

cron_running() {
  ps | grep -E '[[:space:]](cron|crond)([[:space:]]|$)' | grep -v grep >/dev/null 2>&1
}

ensure_xray_init_confdir() {
  [ -f "$XRAY_INIT" ] || return 0
  grep -q 'ARGS="run -confdir /opt/etc/xray/configs"' "$XRAY_INIT" 2>/dev/null && return 0
  grep -q 'ARGS="run -confdir /opt/etc/xray"' "$XRAY_INIT" 2>/dev/null || return 0
  cp "$XRAY_INIT" "$XRAY_INIT.bak-antigoblin-confdir" 2>/dev/null || true
  # Atomic swap: sed → tmp → mv. `cat > INIT` truncates then writes in
  # two steps; a kill between them leaves the init script empty.
  if sed 's#ARGS="run -confdir /opt/etc/xray"#ARGS="run -confdir /opt/etc/xray/configs"#' "$XRAY_INIT" > "$XRAY_INIT.tmp" \
      && chmod 755 "$XRAY_INIT.tmp" 2>/dev/null \
      && mv "$XRAY_INIT.tmp" "$XRAY_INIT"; then
    :
  else
    rm -f "$XRAY_INIT.tmp" 2>/dev/null || true
  fi
}

[ -d /opt ] || exit 0
[ -d "$ROOT_DIR" ] || exit 0

ensure_xray_init_confdir

[ -x "$SELFHEAL_INIT" ] && "$SELFHEAL_INIT" restart >/dev/null 2>&1 || true

if ! cron_running; then
  CRON_INIT="$(find_cron_init 2>/dev/null || true)"
  [ -x "$CRON_INIT" ] && "$CRON_INIT" restart >/dev/null 2>&1 || true
fi

if ! netstat -lnpt 2>/dev/null | grep -q ':61219 '; then
  [ -x "$XRAY_INIT" ] && "$XRAY_INIT" restart >/dev/null 2>&1 || true
fi

UI_PORT=8899
if [ -r /opt/etc/antigoblin.conf ]; then
  # Parse instead of source — don't execute arbitrary shell from a config
  # file, and reject anything that isn't a number 1..65535.
  _cfg_port="$(awk -F= '$1=="PORT" && $2 ~ /^[0-9]+$/ { gsub(/[^0-9]/,"",$2); print $2; exit }' /opt/etc/antigoblin.conf 2>/dev/null)"
  case "$_cfg_port" in
    ''|*[!0-9]*) ;;
    *)
      if [ "$_cfg_port" -ge 1 ] && [ "$_cfg_port" -le 65535 ]; then
        UI_PORT="$_cfg_port"
      fi
      ;;
  esac
fi
if ! netstat -lnpt 2>/dev/null | grep -q ":$UI_PORT "; then
  [ -x "$UI_INIT" ] && "$UI_INIT" restart >/dev/null 2>&1 || true
fi

[ -x "$SELFHEAL" ] && "$SELFHEAL" --force >/dev/null 2>&1 || true
