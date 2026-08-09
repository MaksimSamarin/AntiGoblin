#!/bin/sh
# S99antigoblin-firstboot.sh — one-shot AntiGoblin bring-up over a freshly
# unpacked Entware. Installed by the USB installer tarball at
# /opt/etc/init.d/S99antigoblin-firstboot.sh. Runs once, then removes itself.
#
# What it does (offline-friendly, works with no WAN):
#   1. Starts a background worker that waits until Entware is ready — see
#      "boot ordering" below. The init chain is never blocked.
#   2. Waits for NDM (ndmc) to answer — cold boot needs a few seconds.
#   3. Installs bundled .ipk files from /opt/var/opkg-cache/ (if any).
#   4. Runs the staged install.sh with ANTIGOBLIN_SRC_DIR pointing at
#      /opt/share/antigoblin-staged, so no GitHub download is needed.
#   5. Touches /opt/etc/antigoblin.done and deletes itself from init.d.
#
# Every step is logged to /opt/var/log/antigoblin-firstboot.log. If the box
# boots without internet and the cache is complete, the whole path is
# online-free.
#
# --- Why the `.sh` suffix and the subshell wrapper ---
#
# Entware's rc.unslung iterates /opt/etc/init.d/S* like this:
#
#     case "$i" in
#       *.sh) . $i ;;              # sourced — no execute bit needed
#       *)    [ -x $i ] && $i start ;;
#     esac
#
# On a FAT/NTFS-formatted USB stick the execute bit does not survive npkg's
# extraction, so a plain `S99antigoblin-firstboot` is silently skipped by the
# `[ -x ]` branch — no error, no log line, nothing. Naming the file `*.sh`
# routes us into the `.` (source) branch, which does not care about the mode
# bits. The price is that we run inside rc.unslung's own shell, where a bare
# `exit` would abort the whole init sequence — hence everything below lives
# in a subshell.
#
# --- Boot ordering ---
#
# On the very first boot npkg extracts our tarball and immediately runs the
# init.d scripts, BEFORE Entware's own installer has fetched libc/busybox/opkg.
# There is nothing useful we can install that early, but simply exiting would
# require a second reboot: rc.unslung only invokes S* scripts at startup.
# Instead the tiny launcher below starts one background worker. It polls for
# Entware for up to 30 minutes, then continues in the same router session.
# This removes both the second reboot and the need for a manual SSH command.

DONE_FLAG=/opt/etc/antigoblin.done
LOG=/opt/var/log/antigoblin-firstboot.log
PID_FILE=/opt/var/run/antigoblin-firstboot.pid

# rc.unslung can source this file more than once (and npkg may invoke it while
# changing initrc). One worker is enough. A stale PID from a power loss is
# discarded on the next invocation.
mkdir -p /opt/var/run 2>/dev/null || true
if [ ! -f "$DONE_FLAG" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    true
  else
    rm -f "$PID_FILE"

(
  DONE_FLAG=/opt/etc/antigoblin.done
  LOG=/opt/var/log/antigoblin-firstboot.log
  PID_FILE=/opt/var/run/antigoblin-firstboot.pid
  STAGED=/opt/share/antigoblin-staged
  OPKG_CACHE=/opt/var/opkg-cache

  trap 'rm -f "$PID_FILE"' 0 1 2 15

  # Idempotency guard — a manual second run (or reboot into `restart`) is a
  # no-op. The final `rm -f` below is the real disarm.
  [ -f "$DONE_FLAG" ] && exit 0

  # Standard Entware init.d contract: only act on `start` (which is what NDM
  # invokes at boot). Ignore `stop`/`restart`/`status` — there's nothing to
  # stop, and a restart during firstboot would re-run install.sh, which is
  # expensive and pointless. Note: when sourced by rc.unslung there may be no
  # argument at all, which the default below treats as `start`.
  case "${1:-start}" in
    start) ;;
    *) exit 0 ;;
  esac

  # Locate ourselves for the self-removal at the end. Both the historical
  # extension-less name and the current `.sh` one are handled so an upgrade
  # over an old installer still disarms correctly.
  SELF=""
  for cand in /opt/etc/init.d/S99antigoblin-firstboot.sh \
              /opt/etc/init.d/S99antigoblin-firstboot; do
    [ -f "$cand" ] && { SELF="$cand"; break; }
  done

  # --- Entware readiness wait ---
  #
  # First boot runs us straight after npkg unpacked the tarball, while
  # Entware's installer is still downloading libc. Without opkg and busybox
  mkdir -p /opt/var/log
  touch "$LOG"
  log() { printf '%s firstboot: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }
  die() { log "FATAL: $*"; exit 1; }

  # Npkg extracts this file before its own Entware bootstrap has installed
  # opkg/busybox. Poll in the background rather than relying on a later boot.
  # Five-second ticks keep the common case fast while avoiding a busy loop on
  # the tiny router CPU. The finite cap makes a genuinely broken Entware setup
  # visible in the log instead of leaving an immortal process behind.
  i=0
  while [ "$i" -lt 360 ]; do
    if [ -x /opt/bin/opkg ] && [ -x /opt/bin/busybox ]; then
      break
    fi
    if [ "$i" -eq 0 ]; then
      log "Entware not ready yet; waiting in background (up to 30 minutes)"
    fi
    sleep 5
    i=$((i + 1))
  done
  [ "$i" -lt 360 ] || die "Entware did not become ready within 30 minutes"

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

  # opkg stores its lock at /opt/tmp/opkg.lock and will not create the
  # directory on its own: without it EVERY opkg call fails with
  # "opkg_conf_load: Could not create lock file /opt/tmp/opkg.lock". Entware's
  # installer does create /opt/tmp, but on the USB path we can run before it
  # gets there — opkg and busybox already exist, so the readiness gate above
  # lets us through while /opt/tmp is still missing.
  mkdir -p /opt/tmp

  # Restore execute bits that a non-POSIX filesystem may have dropped. On
  # ext this is a no-op; on NTFS/FAT it is what makes the staged tree usable.
  # Failures are ignored on purpose — every consumer below is invoked in a
  # bit-independent way, this is belt-and-braces for anything we hand off to.
  chmod 755 "$STAGED/install.sh" 2>/dev/null || true
  chmod 755 /opt/sbin/sing-box 2>/dev/null || true

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
  if [ -f /opt/sbin/sing-box ]; then
    # Do not execute the bundled binary here. During the Entware bootstrap its
    # dynamic loader may not be available yet, which can make this harmless
    # diagnostic block firstboot for minutes.
    log "sing-box binary present"
  else
    log "WARN: /opt/sbin/sing-box missing — install.sh will try to download online"
  fi

  # Verify the staged source tree looks intact before handing off. Corrupt
  # tarballs otherwise produce cryptic install.sh errors deep in the run.
  # Deliberately `-f`, not `-x`: we invoke it as `sh install.sh`, so the mode
  # bits are irrelevant, and testing for them broke every NTFS/FAT stick.
  [ -d "$STAGED/ui/xkeen-manager" ] || die "staged tree missing: $STAGED/ui/xkeen-manager (corrupt USB installer?)"
  [ -f "$STAGED/install.sh" ] || die "staged install.sh missing: $STAGED/install.sh"

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
  [ -n "$SELF" ] && rm -f "$SELF"

  exit 0
) &
    worker_pid=$!
    printf '%s\n' "$worker_pid" > "$PID_FILE"
  fi
fi

# Swallow the subshell's status: when rc.unslung sources us, a non-zero here
# would leak into its loop. Real failures are recorded in the log and, more
# visibly, by the absence of /opt/etc/antigoblin.done.
true
