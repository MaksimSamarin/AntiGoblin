#!/bin/sh
# S99antigoblin-firstboot — one-shot AntiGoblin bring-up over a freshly
# unpacked Entware. Installed by the USB installer tarball at
# /opt/etc/init.d/S99antigoblin-firstboot. Runs once, then removes itself.
#
# What it does (offline-friendly, works with no WAN):
#   1. Waits for NDM (ndmc) to answer — cold boot needs a few seconds.
#   2. Installs bundled .ipk files from /opt/var/opkg-cache/ (if any).
#   3. Runs the staged install.sh with ANTIGOBLIN_SRC_DIR pointing at
#      /opt/share/antigoblin-staged, so no GitHub download is needed.
#   4. Touches /opt/etc/antigoblin.done and deletes itself from init.d.
#
# Every step is logged to /opt/var/log/antigoblin-firstboot.log. If the box
# boots without internet and the cache is complete, the whole path is
# online-free.

DONE_FLAG=/opt/etc/antigoblin.done
LOG=/opt/var/log/antigoblin-firstboot.log
STAGED=/opt/share/antigoblin-staged
OPKG_CACHE=/opt/var/opkg-cache
SELF=/opt/etc/init.d/S99antigoblin-firstboot

# Idempotency guard — a manual second run (or reboot into `restart`) is a
# no-op. The final `rm -f $SELF` below is the real disarm.
[ -f "$DONE_FLAG" ] && exit 0

# Standard Entware init.d contract: only act on `start` (which is what NDM
# invokes at boot). Ignore `stop`/`restart`/`status` — there's nothing to
# stop, and a restart during firstboot would re-run install.sh, which is
# expensive and pointless.
case "${1:-start}" in
  start) ;;
  *) exit 0 ;;
esac

mkdir -p /opt/var/log
touch "$LOG"
log() { printf '%s firstboot: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
die() { log "FATAL: $*"; exit 1; }

log "=== AntiGoblin first-boot begin ==="

# Wait for NDM socket to answer. On cold boot ndmc returns non-zero for a
# few seconds while NDMS boots. Capped at ~40s — beyond that something is
# seriously wrong and we should bail rather than hang init forever.
i=0
while [ $i -lt 20 ]; do
  if ndmc -c 'show version' >/dev/null 2>&1; then
    log "NDM ready after $((i * 2))s"
    break
  fi
  sleep 2
  i=$((i + 1))
done
[ $i -lt 20 ] || die "NDM did not respond within 40s"

# Offline opkg install from the bundled cache. --nodeps because we shipped
# the exact set of .ipk we depend on; asking opkg to resolve deps would
# make it try to reach downloads.openwrt.org and stall on a boot with no
# WAN. Anything we missed is picked up by the online top-up below (or by
# install.sh's own opkg calls).
if [ -d "$OPKG_CACHE" ] && ls "$OPKG_CACHE"/*.ipk >/dev/null 2>&1; then
  log "Offline-installing $(ls "$OPKG_CACHE"/*.ipk | wc -l) bundled .ipk files"
  /opt/bin/opkg install --nodeps "$OPKG_CACHE"/*.ipk >>"$LOG" 2>&1 || \
    log "WARN: some bundled .ipk failed to install (will retry via online install.sh)"
fi

# sing-box ships pre-installed at /opt/sbin/sing-box in the USB tarball.
# install.sh's install_singbox() early-returns when the binary is already
# present, so this check is really diagnostics: if the tarball was built
# wrong, we want a clear line in the log rather than silent missing UDP.
if [ -x /opt/sbin/sing-box ]; then
  log "sing-box binary present: $(/opt/sbin/sing-box version 2>/dev/null | head -n 1)"
else
  log "WARN: /opt/sbin/sing-box missing — install.sh will try to download online"
fi

# Verify the staged source tree looks intact before handing off. Corrupt
# tarballs otherwise produce cryptic install.sh errors deep in the run.
[ -d "$STAGED/ui/xkeen-manager" ] || die "staged tree missing: $STAGED/ui/xkeen-manager (corrupt USB installer?)"
[ -x "$STAGED/install.sh" ] || die "staged install.sh missing or not executable: $STAGED/install.sh"

log "Running staged install.sh from $STAGED"
# ANTIGOBLIN_SRC_DIR tells install.sh's fetch_sources to skip the GitHub
# download and use our local staged tree. install.sh handles everything
# from here: opkg install (top-up), mkdirs, ensure_xkeen_policy, deploy,
# start_services.
ANTIGOBLIN_SRC_DIR="$STAGED" sh "$STAGED/install.sh" >>"$LOG" 2>&1 || \
  die "staged install.sh failed — see $LOG for details"

# Success — arm the done-flag BEFORE self-removal so that a race (init
# re-invocation, unlikely but possible) sees the flag and exits early.
touch "$DONE_FLAG"
log "=== AntiGoblin first-boot done, removing self from init.d ==="
rm -f "$SELF"

exit 0
