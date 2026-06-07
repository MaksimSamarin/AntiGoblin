#!/bin/sh
# AntiGoblin one-command on-router installer.
#
# Usage on the router (after Entware/OPKG is enabled in Keenetic and
# the USB stick is mounted at /opt):
#
#   wget -O - https://raw.githubusercontent.com/MaksimSamarin/AntiGoblin/main/install.sh | sh
#
# Or:
#
#   wget -O install.sh https://raw.githubusercontent.com/MaksimSamarin/AntiGoblin/main/install.sh
#   sh install.sh
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
}

install_packages() {
  log "Updating Entware package index"
  /opt/bin/opkg update >/dev/null 2>&1 || true

  PKGS="ca-bundle curl wget tar gzip jq gawk coreutils-base64 net-tools-netstat cron uhttpd_kn xray iptables ipset conntrack"
  for pkg in $PKGS; do
    if ! /opt/bin/opkg list-installed | grep -q "^${pkg} "; then
      log "Installing $pkg"
      /opt/bin/opkg install "$pkg" >/dev/null 2>&1 || log "WARN: failed to install $pkg (continuing)"
    fi
  done
}

fetch_sources() {
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
  if ndmc -c 'show ip policy' 2>/dev/null | grep -q 'description = xkeen:'; then
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
  ndmc -c "system configuration save" >/dev/null 2>&1 || true
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
    /opt/etc/ndm/fs.d \
    /opt/etc/ndm/usb.d
  : > /opt/var/log/xray/access.log
  : > /opt/var/log/xray/error.log
  touch /opt/var/log/xkeen-selfheal.log /opt/var/log/xkeen-health.log
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
  seed_file "$CONFIGS/04_outbounds.sample.json"  /opt/etc/xray/configs/04_outbounds.json
  seed_file "$CONFIGS/05_routing.sample.json"    /opt/etc/xray/configs/05_routing.json
  seed_file "$CONFIGS/sing-box-xkeen.sample.json" /opt/etc/sing-box/xkeen.json
  seed_file "$CONFIGS/xkeen-ui-state.sample.json" /opt/share/xkeen-manager/xkeen-ui-state.json

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
  deploy_file "$SCRIPTS/antigoblin-remount-hook.sh"   /opt/etc/ndm/fs.d/50-antigoblin.sh
  deploy_file "$SCRIPTS/antigoblin-remount-hook.sh"   /opt/etc/ndm/usb.d/50-antigoblin.sh
}

install_singbox() {
  if command -v sing-box >/dev/null 2>&1; then
    log "sing-box already installed: $(sing-box version | head -n 1 2>/dev/null || true)"
    return 0
  fi

  case "$(uname -m)" in
    aarch64|arm64) ARCH=arm64-musl ;;
    armv7l|armv7*) ARCH=armv7 ;;
    mipsel*)       ARCH=mipsle ;;
    mips*)         ARCH=mips ;;
    *)             ARCH="$(uname -m)" ;;
  esac

  URL="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${ARCH}.tar.gz"
  log "Downloading sing-box ${SING_BOX_VERSION} (${ARCH})"

  rm -rf /tmp/antigoblin-sing-box /tmp/antigoblin-sing-box.tar.gz
  mkdir -p /tmp/antigoblin-sing-box

  if ! fetch_to "$URL" /tmp/antigoblin-sing-box.tar.gz; then
    log "WARN: failed to download sing-box. UDP-VPN groups will not work until you install /opt/sbin/sing-box manually."
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
  sleep 2
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
  printf '  1. Fill in VLESS Reality credentials.\n'
  printf '  2. Configure routing groups (each with outbound: vless-reality / direct / bypass).\n'
  printf '  3. Click "Save and apply".\n'
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
