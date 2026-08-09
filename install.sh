#!/bin/sh
# AntiGoblin one-command on-router installer.
#
# Usage on the router (after Entware/OPKG is enabled in Keenetic and
# the USB stick is mounted at /opt):
#
#   curl -fsSL https://raw.githubusercontent.com/MaksimSamarin/AntiGoblin/main/install.sh | sh
#
# Or (if curl is not yet installed):
#
#   opkg install curl
#   curl -fsSL -o install.sh https://raw.githubusercontent.com/MaksimSamarin/AntiGoblin/main/install.sh
#   sh install.sh
#
# Note: Entware ships wget-nossl by default (no HTTPS support), so
# `wget https://...` will not work. The installer itself pulls curl via
# opkg if it isn't there yet.
#
# The script is idempotent: re-running it upgrades sources without
# touching existing UI state or xray configs unless ANTIGOBLIN_FORCE=1.

set -eu

REPO_OWNER="${ANTIGOBLIN_REPO_OWNER:-MaksimSamarin}"
REPO_NAME="${ANTIGOBLIN_REPO_NAME:-AntiGoblin}"
REPO_BRANCH="${ANTIGOBLIN_REPO_BRANCH:-main}"
REPO_TARBALL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_BRANCH}.tar.gz"

SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.8}"

WORK_DIR="${ANTIGOBLIN_WORK_DIR:-/tmp/antigoblin-install}"
SRC_DIR=""
FORCE_SEED="${ANTIGOBLIN_FORCE:-0}"

UI_PORT="${ANTIGOBLIN_UI_PORT:-8899}"

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# Resolve an HTTPS-capable downloader. Default Entware ships wget-nossl
# (compiled without HTTPS), so prefer curl, then wget if it links a TLS
# library. As a last resort install curl via opkg (the package index is
# fetched over HTTP, so that works even without HTTPS).
FETCHER_BIN=""
FETCHER_TYPE=""

_fetcher_try_wget() {
  cand="$1"
  [ -x "$cand" ] || return 1
  "$cand" --version 2>&1 | grep -qiE '\+https|gnutls|openssl|ssl/tls' || return 1
  FETCHER_BIN="$cand"
  FETCHER_TYPE="wget"
  return 0
}

ensure_https_fetcher() {
  [ -n "$FETCHER_BIN" ] && return 0

  if [ -x /opt/bin/curl ]; then
    FETCHER_BIN="/opt/bin/curl"; FETCHER_TYPE="curl"; return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    FETCHER_BIN="$(command -v curl)"; FETCHER_TYPE="curl"; return 0
  fi
  _fetcher_try_wget /opt/bin/wget     && return 0
  _fetcher_try_wget /opt/usr/bin/wget && return 0
  if command -v wget >/dev/null 2>&1; then
    _fetcher_try_wget "$(command -v wget)" && return 0
  fi

  # Nothing HTTPS-capable yet. Try to install curl via opkg.
  if [ -x /opt/bin/opkg ]; then
    log "No HTTPS-capable downloader found, trying: opkg install curl"
    /opt/bin/opkg update >/dev/null 2>&1 || true
    /opt/bin/opkg install curl >/dev/null 2>&1 || true
    if [ -x /opt/bin/curl ]; then
      FETCHER_BIN="/opt/bin/curl"; FETCHER_TYPE="curl"; return 0
    fi
  fi

  die "No HTTPS-capable downloader (curl or wget-ssl) and could not install one. Run: opkg install curl"
}

fetch_to() {
  ensure_https_fetcher
  url="$1"; dest="$2"
  case "$FETCHER_TYPE" in
    curl) "$FETCHER_BIN" -fsSL -o "$dest" "$url" ;;
    wget) "$FETCHER_BIN" -q -O "$dest" "$url" ;;
    *)    die "fetcher not resolved" ;;
  esac
}

fetch_stdout() {
  ensure_https_fetcher
  url="$1"
  case "$FETCHER_TYPE" in
    curl) "$FETCHER_BIN" -fsSL "$url" ;;
    wget) "$FETCHER_BIN" -q -O - "$url" ;;
    *)    die "fetcher not resolved" ;;
  esac
}

require_entware() {
  [ -d /opt ] || die "/opt is not mounted. Enable Entware (Поддержка открытых пакетов) in Keenetic and mount the USB stick first."
  [ -x /opt/bin/opkg ] || die "/opt/bin/opkg not found. Entware is not initialized on this router."
  mkdir -p /opt/sbin
  # opkg keeps its lock at /opt/tmp/opkg.lock and does NOT create the
  # directory itself — without it every single call dies with
  # "opkg_conf_load: Could not create lock file /opt/tmp/opkg.lock".
  # Entware's own installer creates /opt/tmp eventually, but the USB
  # firstboot path can reach us before that, so make sure it exists.
  mkdir -p /opt/tmp
}

# Entware's opkg can wait indefinitely for an unreachable repository. That is
# particularly harmful during USB firstboot: the user sees neither a UI nor an
# actionable error. Run each call as a child, cap it, and let the caller retry.
# opkg performs downloads in-process on the supported Entware build, so killing
# the child also stops the stalled transfer.
OPKG_TIMEOUT="${ANTIGOBLIN_OPKG_TIMEOUT:-120}"
opkg_run() {
  /opt/bin/opkg "$@" &
  _opkg_pid=$!
  _opkg_waited=0
  while kill -0 "$_opkg_pid" 2>/dev/null; do
    if [ "$_opkg_waited" -ge "$OPKG_TIMEOUT" ]; then
      log "WARN: opkg $* exceeded ${OPKG_TIMEOUT}s; terminating it"
      kill "$_opkg_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$_opkg_pid" 2>/dev/null || true
      wait "$_opkg_pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
    _opkg_waited=$((_opkg_waited + 1))
  done
  wait "$_opkg_pid"
}

opkg_install_retry() {
  _opkg_pkg="$1"
  _opkg_try=1
  while [ "$_opkg_try" -le 3 ]; do
    if opkg_run install "$_opkg_pkg"; then
      return 0
    fi
    log "WARN: opkg install $_opkg_pkg failed (attempt $_opkg_try/3)"
    _opkg_try=$((_opkg_try + 1))
    [ "$_opkg_try" -le 3 ] && sleep 5
  done
  return 1
}

install_packages() {
  log "Updating Entware package index"
  opkg_run update || log "WARN: opkg update failed; trying package installs with the current index"

  # Essentials — the stack literally can't run without them; fail hard.
  # Optionals — nice-to-have (rich netstat, coreutils base64, standalone
  # curl/wget for user shell); warn and continue.
  ESSENTIAL_PKGS="xray uhttpd_kn iptables ipset conntrack jq gawk ca-bundle"
  OPTIONAL_PKGS="cron curl wget tar gzip coreutils-base64 coreutils-timeout net-tools-netstat"

  MISSING_ESSENTIAL=""
  for pkg in $ESSENTIAL_PKGS; do
    if ! /opt/bin/opkg list-installed | grep -q "^${pkg} "; then
      log "Installing (essential) $pkg"
      if ! opkg_install_retry "$pkg"; then
        MISSING_ESSENTIAL="$MISSING_ESSENTIAL $pkg"
      fi
    fi
  done
  if [ -n "$MISSING_ESSENTIAL" ]; then
    die "Failed to install essential packages:$MISSING_ESSENTIAL. Fix opkg/network and re-run install.sh."
  fi

  for pkg in $OPTIONAL_PKGS; do
    if ! /opt/bin/opkg list-installed | grep -q "^${pkg} "; then
      log "Installing (optional) $pkg"
      opkg_install_retry "$pkg" || log "WARN: failed to install optional $pkg (continuing)"
    fi
  done
}

fetch_sources() {
  # Offline / staged mode: firstboot script (S99antigoblin-firstboot.sh) sets
  # ANTIGOBLIN_SRC_DIR to a pre-unpacked source tree bundled into the USB
  # installer tarball. Skip the GitHub download entirely — /opt is a fresh
  # Entware with no ca-bundle guaranteed and possibly no WAN.
  if [ -n "${ANTIGOBLIN_SRC_DIR:-}" ] && [ -d "$ANTIGOBLIN_SRC_DIR/ui/xkeen-manager" ]; then
    log "Using pre-staged sources from ANTIGOBLIN_SRC_DIR=$ANTIGOBLIN_SRC_DIR"
    SRC_DIR="$ANTIGOBLIN_SRC_DIR"
    return 0
  fi

  ensure_https_fetcher
  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"

  log "Fetching repository tarball: $REPO_TARBALL (via $FETCHER_TYPE)"
  if ! fetch_to "$REPO_TARBALL" "$WORK_DIR/src.tar.gz"; then
    die "Failed to download repository tarball. Check internet access and ca-bundle."
  fi

  log "Extracting sources"
  /opt/bin/tar -xzf "$WORK_DIR/src.tar.gz" -C "$WORK_DIR"
  SRC_DIR="$(find "$WORK_DIR" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n 1)"
  [ -n "$SRC_DIR" ] || die "Cannot locate extracted source directory under $WORK_DIR"
  [ -d "$SRC_DIR/ui/xkeen-manager" ] || die "Source tree looks broken: $SRC_DIR/ui/xkeen-manager missing"
}

ensure_xkeen_policy() {
  # Accept any of the NDMC description formats seen in the wild:
  #   `description = xkeen:Home`  (Format A one-liner)
  #   `description: xkeen`        (Format B multiline, no space before `:`)
  #   `description xkeen`         (Format C bare)
  # This regex is the SAME one xkeen-runtime.sh exports as
  # XKEEN_POLICY_DESC_RE — keep them in sync (an earlier install.sh copy
  # required a mandatory space and silently missed Format B).
  DESC_MATCH='description(([[:space:]]*[=:])|([[:space:]]+))[[:space:]]*"?xkeen($|[":,[:space:]])'
  if ndmc -c 'show ip policy' 2>/dev/null | grep -Eq "$DESC_MATCH"; then
    log "Keenetic policy 'xkeen' already exists"
    return 0
  fi

  log "Creating Keenetic policy 'xkeen'"

  WAN_IFACE="$(ndmc -c 'show interface' | /opt/bin/awk '
    /^Interface, name = / {
      iface=$4
      gsub(/"/, "", iface)
      next
    }
    /defaultgw:[[:space:]]+yes/ {
      print iface
      exit
    }
  ')"

  [ -n "$WAN_IFACE" ] || die "Failed to detect active WAN interface. Add the policy manually."

  NEXT_POLICY_NUM="$(
    ndmc -c 'show running-config' | /opt/bin/awk '
      /^ip policy Policy[0-9]+$/ {
        name=$3
        sub(/^Policy/, "", name)
        if (name >= 42) {
          print name
        }
      }
    ' | sort -n | /opt/bin/awk '
      BEGIN { n = 42 }
      {
        if ($1 == n) {
          n++
        }
      }
      END { print n }
    '
  )"

  [ -n "$NEXT_POLICY_NUM" ] || NEXT_POLICY_NUM=42
  POLICY_NAME="Policy$NEXT_POLICY_NUM"

  ndmc -c "ip policy $POLICY_NAME"
  ndmc -c "ip policy $POLICY_NAME description xkeen"
  ndmc -c "ip policy $POLICY_NAME permit global $WAN_IFACE"
  # Persist to startup-config. Retry a few times: if another process is
  # writing config, first save can fail transiently and we'd silently lose
  # the policy after reboot.
  saved=0
  for _try in 1 2 3; do
    if ndmc -c "system configuration save" >/dev/null 2>&1; then
      saved=1
      break
    fi
    sleep 1
  done
  [ "$saved" = "1" ] || log "WARN: 'system configuration save' failed after 3 tries; policy may not survive reboot."
  log "Created policy $POLICY_NAME with description 'xkeen' over $WAN_IFACE"
}

mkdirs() {
  mkdir -p \
    /opt/etc/xray/configs \
    /opt/etc/xray/dat \
    /opt/etc/sing-box \
    /opt/share/xkeen-manager \
    /opt/share/xkeen-manager/api \
    /opt/share/xkeen-manager/runtime \
    /opt/var/log \
    /opt/var/log/xray \
    /opt/var/run \
    /opt/etc/cron.1min \
    /opt/etc/ndm/usb.d \
    /opt/etc/ndm/netfilter.d
  # touch, not `:>`. A reinstall over an existing box (typical when the
  # user re-fetches install.sh after a bug) must not truncate xray logs
  # — the error.log entry that reproduces their crash is often the whole
  # reason they're re-running install.sh.
  touch /opt/var/log/xray/access.log /opt/var/log/xray/error.log \
        /opt/var/log/xkeen-selfheal.log /opt/var/log/xkeen-health.log
}

seed_file() {
  SRC="$1"
  DST="$2"
  MODE="${3:-644}"

  [ -f "$SRC" ] || die "Source seed missing: $SRC"

  if [ -f "$DST" ] && [ "$FORCE_SEED" != "1" ]; then
    log "Keep existing $DST"
    return 0
  fi

  cp "$SRC" "$DST"
  chmod "$MODE" "$DST"
  log "Seeded $DST"
}

deploy_file() {
  SRC="$1"
  DST="$2"
  MODE="${3:-755}"

  [ -f "$SRC" ] || die "Source missing: $SRC"
  cp "$SRC" "$DST"
  chmod "$MODE" "$DST"
}

deploy_sources() {
  CONFIGS="$SRC_DIR/configs/xkeen"
  UI="$SRC_DIR/ui/xkeen-manager"
  BACKEND="$UI/backend"
  SCRIPTS="$SRC_DIR/scripts/xkeen"

  log "Seeding xray and sing-box configs (existing files kept; set ANTIGOBLIN_FORCE=1 to overwrite)"
  seed_file "$CONFIGS/01_log.sample.json"        /opt/etc/xray/configs/01_log.json
  seed_file "$CONFIGS/02_relay.sample.json"      /opt/etc/xray/configs/02_relay.json
  seed_file "$CONFIGS/03_inbounds.sample.json"   /opt/etc/xray/configs/03_inbounds.json
  # 04_outbounds and 05_routing are runtime-generated by backend on every
  # apply. Force-reseed replaces them with samples that don't declare a
  # vless-reality outbound, breaking xray until user saves from UI. Keep
  # them out of FORCE_SEED path.
  if [ ! -f /opt/etc/xray/configs/04_outbounds.json ]; then
    seed_file "$CONFIGS/04_outbounds.sample.json" /opt/etc/xray/configs/04_outbounds.json
  fi
  if [ ! -f /opt/etc/xray/configs/05_routing.json ]; then
    seed_file "$CONFIGS/05_routing.sample.json" /opt/etc/xray/configs/05_routing.json
  fi
  seed_file "$CONFIGS/sing-box-xkeen.sample.json" /opt/etc/sing-box/xkeen.json
  seed_file "$CONFIGS/xkeen-ui-state.sample.json" /opt/share/xkeen-manager/xkeen-ui-state.json

  # Upgrade path: existing 03_inbounds.json from a pre-SOCKS5-inbound
  # install lacks the `socks-in` block. seed_file above keeps the file as
  # is; here we merge in the socks-in inbound from the sample so the
  # feature works without requiring ANTIGOBLIN_FORCE=1 (which would blow
  # away every user-tuned inbound).
  if command -v jq >/dev/null 2>&1 && [ -f /opt/etc/xray/configs/03_inbounds.json ] \
      && [ -f "$CONFIGS/03_inbounds.sample.json" ]; then
    # Merge only if neither the tag nor the port 61080 is already claimed
    # by an existing inbound — otherwise xray fails to start on
    # "address in use" after upgrade, and the user has no obvious diagnosis.
    if ! jq -e '.inbounds[]? | select(.tag == "socks-in" or .port == 61080)' \
        /opt/etc/xray/configs/03_inbounds.json >/dev/null 2>&1; then
      TMP_INB="/opt/etc/xray/configs/03_inbounds.json.tmp-socks-merge"
      if jq --slurpfile sample "$CONFIGS/03_inbounds.sample.json" \
          '.inbounds += ($sample[0].inbounds | map(select(.tag == "socks-in")))' \
          /opt/etc/xray/configs/03_inbounds.json > "$TMP_INB" 2>/dev/null \
          && jq -e '.' "$TMP_INB" >/dev/null 2>&1; then
        mv "$TMP_INB" /opt/etc/xray/configs/03_inbounds.json
        chmod 644 /opt/etc/xray/configs/03_inbounds.json
        log "Merged socks-in inbound into existing 03_inbounds.json"
      else
        rm -f "$TMP_INB"
      fi
    else
      log "Skipped socks-in merge: 03_inbounds.json already declares tag=socks-in or port=61080"
    fi
  fi

  # Persist UI port for the init script (source of truth for :$UI_PORT).
  printf 'PORT=%s\n' "$UI_PORT" > /opt/etc/antigoblin.conf
  chmod 644 /opt/etc/antigoblin.conf

  log "Deploying UI"
  cp "$UI/index.html"   /opt/share/xkeen-manager/index.html
  cp "$UI/styles.css"   /opt/share/xkeen-manager/styles.css
  cp "$UI/app.js"       /opt/share/xkeen-manager/app.js
  if [ -f "$UI/antigoblin-logo.png" ]; then
    cp "$UI/antigoblin-logo.png" /opt/share/xkeen-manager/antigoblin-logo.png
  fi
  chmod 644 /opt/share/xkeen-manager/index.html /opt/share/xkeen-manager/styles.css /opt/share/xkeen-manager/app.js 2>/dev/null || true

  log "Deploying backend"
  deploy_file "$BACKEND/routing.cgi"      /opt/share/xkeen-manager/api/routing.cgi
  deploy_file "$BACKEND/xkeen-selfheal.sh" /opt/share/xkeen-manager/api/xkeen-selfheal.sh
  deploy_file "$BACKEND/xkeen-runtime.sh"  /opt/share/xkeen-manager/api/xkeen-runtime.sh

  log "Deploying init and watchdog scripts"
  deploy_file "$SCRIPTS/antigoblin-selfheal-loop.sh" /opt/share/xkeen-manager/api/xkeen-selfheal-loop.sh
  deploy_file "$SCRIPTS/antigoblin-sysctl.initd.sh"  /opt/etc/init.d/S20antigoblin-sysctl
  deploy_file "$SCRIPTS/antigoblin-singbox.initd.sh" /opt/etc/init.d/S24antigoblin-singbox
  deploy_file "$SCRIPTS/antigoblin-selfheal.initd.sh" /opt/etc/init.d/S25antigoblin-selfheal
  deploy_file "$SCRIPTS/antigoblin.initd.sh"          /opt/etc/init.d/S26antigoblin
  deploy_file "$SCRIPTS/antigoblin-selfheal.cron.sh"  /opt/etc/cron.1min/50-antigoblin-selfheal
  # remount-hook: install into usb.d only. Historically also in fs.d,
  # which double-fired the hook on USB Entware mounts. Remove legacy copy
  # from fs.d on upgrade.
  deploy_file "$SCRIPTS/antigoblin-remount-hook.sh"   /opt/etc/ndm/usb.d/50-antigoblin.sh
  rm -f /opt/etc/ndm/fs.d/50-antigoblin.sh 2>/dev/null || true
  deploy_file "$SCRIPTS/antigoblin-netfilter-hook.sh" /opt/etc/ndm/netfilter.d/50-antigoblin.sh
}

install_singbox() {
  if command -v sing-box >/dev/null 2>&1; then
    log "sing-box already installed: $(sing-box version | head -n 1 2>/dev/null || true)"
    return 0
  fi

  # sing-box release asset naming has changed across versions. Rather than
  # bet on one string, list candidates in order of preference for the CPU
  # arch and try them until one downloads. Fallback covers older naming
  # ("-musl" suffix), newer naming (unsuffixed), and the softfloat MIPS
  # variant.
  case "$(uname -m)" in
    aarch64|arm64)   ARCH_CANDIDATES="arm64-musl arm64" ;;
    armv7l|armv7*)   ARCH_CANDIDATES="armv7-musl armv7" ;;
    # Old sing-box builds ship no armv6 asset. Try armv7 — some armv6 chips
    # run armv7 binaries; if not, the user gets a clear warn and lives without
    # hy2 (VLESS TCP still works).
    armv6l|armv6*)   ARCH_CANDIDATES="armv7-musl armv7" ;;
    mipsel*)         ARCH_CANDIDATES="mipsle-softfloat mipsle" ;;
    mips*)           ARCH_CANDIDATES="mips-softfloat mips" ;;
    x86_64|amd64)    ARCH_CANDIDATES="amd64-musl amd64" ;;
    *)               ARCH_CANDIDATES="$(uname -m)" ;;
  esac

  rm -rf /tmp/antigoblin-sing-box /tmp/antigoblin-sing-box.tar.gz
  mkdir -p /tmp/antigoblin-sing-box

  DOWNLOADED=0
  for arch_try in $ARCH_CANDIDATES; do
    URL="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${arch_try}.tar.gz"
    log "Downloading sing-box ${SING_BOX_VERSION} (${arch_try})"
    if fetch_to "$URL" /tmp/antigoblin-sing-box.tar.gz 2>/dev/null; then
      DOWNLOADED=1
      break
    fi
    log "  ...asset not found for arch=${arch_try}, trying next"
  done

  if [ "$DOWNLOADED" != "1" ]; then
    log "WARN: failed to download sing-box for any of the archs ($ARCH_CANDIDATES)."
    log "      UDP-VPN groups will not work until you install /opt/sbin/sing-box manually."
    log "      Check https://github.com/SagerNet/sing-box/releases/tag/v${SING_BOX_VERSION} for the correct asset name."
    return 0
  fi

  /opt/bin/tar -xzf /tmp/antigoblin-sing-box.tar.gz -C /tmp/antigoblin-sing-box
  SBIN="$(find /tmp/antigoblin-sing-box -type f -name sing-box | head -n 1)"
  if [ -n "$SBIN" ]; then
    cp "$SBIN" /opt/sbin/sing-box
    chmod 755 /opt/sbin/sing-box
    log "Installed /opt/sbin/sing-box"
  else
    log "WARN: sing-box binary not found inside tarball"
  fi

  rm -rf /tmp/antigoblin-sing-box /tmp/antigoblin-sing-box.tar.gz
}

start_services() {
  log "Starting cron"
  for candidate in /opt/etc/init.d/S10cron /opt/etc/init.d/S05crond; do
    [ -x "$candidate" ] && "$candidate" restart >/dev/null 2>&1 || true
  done

  log "Applying sysctl tweaks"
  /opt/etc/init.d/S20antigoblin-sysctl start >/dev/null 2>&1 || true

  log "Starting sing-box"
  /opt/etc/init.d/S24antigoblin-singbox restart >/dev/null 2>&1 || true

  log "Starting self-heal watchdog"
  /opt/etc/init.d/S25antigoblin-selfheal restart >/dev/null 2>&1 || true

  log "Forcing one self-heal pass"
  /opt/share/xkeen-manager/api/xkeen-selfheal.sh --force >/dev/null 2>&1 || true

  log "Starting AntiGoblin UI on :$UI_PORT"
  /opt/etc/init.d/S26antigoblin restart >/dev/null 2>&1 || true
  # Wait for uhttpd to bind. Fixed 2s races on slower flash; poll for the
  # port and only report success once it's actually listening.
  UI_UP=0
  for _try in 1 2 3 4 5 6; do
    if netstat -lnpt 2>/dev/null | grep -q ":$UI_PORT "; then
      UI_UP=1
      break
    fi
    sleep 1
  done
  if [ "$UI_UP" != "1" ]; then
    log "WARN: UI did not bind :$UI_PORT within 6s. Check tail /opt/var/log/xkeen-manager-uhttpd.log"
  fi
}

print_summary() {
  ROUTER_IP="$(ndmc -c 'show interface' 2>/dev/null | /opt/bin/awk '
    /^Interface, name = / { iface=$4; gsub(/"/, "", iface); next }
    iface == "Bridge0" && /address:[[:space:]]+/ { print $2; exit }
  ')"
  [ -n "$ROUTER_IP" ] || ROUTER_IP="<router-ip>"

  printf '\n'
  printf '====================================================\n'
  printf 'AntiGoblin install complete.\n'
  printf '\n'
  printf 'Open the UI:\n'
  printf '  http://%s:%s/\n' "$ROUTER_IP" "$UI_PORT"
  printf '\n'
  printf 'UI auth uses your Keenetic web UI login and password.\n'
  printf '\n'
  printf 'Next steps in the UI:\n'
  printf '  1. Add a proxy key: paste vless:// / vmess:// / hysteria2://\n'
  printf '     URI, or add a subscription URL.\n'
  printf '  2. Select the active key (radio in the keys panel).\n'
  printf '  3. Configure routing groups (each with outbound:\n'
  printf '     vless-reality [via active key] / bypass).\n'
  printf '  4. Click "Save and apply".\n'
  printf '\n'
  printf 'Then in the Keenetic web UI assign devices to policy "xkeen"\n'
  printf 'in "Приоритеты подключений".\n'
  printf '====================================================\n'
}

cleanup() {
  rm -rf "$WORK_DIR"
}

main() {
  require_entware
  install_packages
  fetch_sources
  mkdirs
  ensure_xkeen_policy
  deploy_sources
  install_singbox
  start_services
  cleanup
  print_summary
}

main "$@"
