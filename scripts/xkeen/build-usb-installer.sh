#!/usr/bin/env bash
# Build a Keenetic USB installer tarball that ships Entware + AntiGoblin
# pre-staged, so the end-user just needs to drop it into `install/` on an
# ext4-formatted USB stick, plug it into the router, and enable OPKG in the
# Keenetic Web UI. First-boot picks it up automatically — no SSH, no curl,
# no manual install.sh run.
#
# Outputs two files in dist/ per build:
#
#   1. antigoblin-usb-<arch>.zip
#      A ready-to-flash bundle. User downloads, double-clicks "Extract to..."
#      in Windows Explorer (or `unzip` on *nix), points at the USB stick
#      ROOT. Zip already contains the `install/` folder with the correctly
#      named tarball inside, so nothing to rename, no folder to hand-create.
#
#   2. <arch>-installer.tar.gz
#      The raw tarball (same thing that's inside the zip). Kept as a
#      Release asset for people who prefer to drop it into `install/`
#      manually, or want to see the payload before flashing.
#
# The AntiGoblin version is embedded as /opt/share/antigoblin-staged/VERSION
# inside the tarball so the user can verify what's on their router with
# `cat /opt/share/antigoblin-staged/VERSION`.
#
# The tarball filename is deliberately `<arch>-installer.tar.gz` — the
# exact name Keenetic's `npkg` looks for. No renaming needed either way.
#
# Usage:
#   scripts/xkeen/build-usb-installer.sh --arch aarch64 [--version <ver>]
#
# Supported --arch values: aarch64, armv7
#   (mipsel/mips can be added the same way once sing-box publishes a
#   suitable asset — for MVP we skip them; long-tail users can use the
#   classic `curl … install.sh | sh` flow.)
#
# Requires on the build host: bash, curl, tar, gzip, awk, zip. No cross-
# compile, no chroot, no root — just downloads pre-built binaries and
# repacks.
#
# Must run on Linux (or WSL). Plain Windows Git-Bash cannot create the
# symlinks Entware installer ships (hundreds of BusyBox aliases) and tar
# extraction bails halfway. The GitHub Actions workflow
# `.github/workflows/release-usb-installer.yml` runs on ubuntu-latest.

set -euo pipefail

ARCH=""
VERSION=""
SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.8}"
ENTWARE_MIRROR="${ENTWARE_MIRROR:-https://bin.entware.net}"

while [ $# -gt 0 ]; do
  case "$1" in
    --arch)    ARCH="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$ARCH" ] || { echo "--arch is required (aarch64 or armv7)" >&2; exit 2; }

# Match sing-box release asset naming to CPU arch. install.sh's runtime
# lookup tries `-musl` first, then the bare variant. We mirror that here
# so the bundled binary matches what a network-install would fetch.
case "$ARCH" in
  aarch64)
    ENTWARE_ARCH="aarch64-k3.10"
    SB_CANDIDATES="arm64-musl arm64"
    ;;
  armv7)
    ENTWARE_ARCH="armv7sf-k3.2"
    SB_CANDIDATES="armv7-musl armv7"
    ;;
  *)
    echo "Unsupported --arch=$ARCH. Supported: aarch64, armv7" >&2
    exit 2
    ;;
esac

# Version tag defaults to the current git describe (or `dev` if outside a
# repo). The output filename encodes this so users can tell tarballs apart
# across releases without opening them.
if [ -z "$VERSION" ]; then
  if command -v git >/dev/null 2>&1 && VERSION="$(git -C "$(dirname "$0")/../.." describe --tags --always --dirty 2>/dev/null)"; then
    :
  else
    VERSION="dev-$(date +%Y%m%d)"
  fi
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
WORK_DIR="$(mktemp -d -t antigoblin-usb-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

mkdir -p "$DIST_DIR"

log() { printf '[build-usb-installer] %s\n' "$*"; }

log "arch=$ARCH  entware=$ENTWARE_ARCH  sing-box=$SING_BOX_VERSION  version=$VERSION"
log "work-dir=$WORK_DIR"

# ---- 1. Download and unpack upstream Entware installer ----
ENTWARE_URL="$ENTWARE_MIRROR/$ENTWARE_ARCH/installer/${ARCH}-installer.tar.gz"
log "Fetching Entware installer: $ENTWARE_URL"
curl -fsSL --retry 3 -o "$WORK_DIR/entware.tar.gz" "$ENTWARE_URL"

STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE"
log "Unpacking Entware into staging root"
tar -xzf "$WORK_DIR/entware.tar.gz" -C "$STAGE"

# Entware's <arch>-installer.tar.gz ships with paths relative to /opt
# (bin/, etc/, lib/, sbin/, usr/) — the router-side `npkg` extracts them
# into /opt directly. Our overlay files must be placed alongside these
# (bin/, etc/, sbin/, share/) — NOT under an added `opt/` layer, which
# would extract to /opt/opt/… on the router.
[ -d "$STAGE/bin" ] && [ -d "$STAGE/etc" ] \
  || { echo "Entware tarball layout unexpected (no bin/ or etc/ at root) — mirror layout changed?" >&2; exit 1; }

# ---- 2. Fetch and stage sing-box binary ----
log "Fetching sing-box $SING_BOX_VERSION for candidates: $SB_CANDIDATES"
SB_TARBALL="$WORK_DIR/sing-box.tar.gz"
SB_INSTALLED=""
for sb_arch in $SB_CANDIDATES; do
  URL="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${sb_arch}.tar.gz"
  log "  trying $sb_arch"
  if curl -fsSL --retry 2 -o "$SB_TARBALL" "$URL" 2>/dev/null; then
    SB_INSTALLED="$sb_arch"
    break
  fi
done
[ -n "$SB_INSTALLED" ] || { echo "Failed to download sing-box for any of: $SB_CANDIDATES" >&2; exit 1; }
log "  got sing-box for $SB_INSTALLED"

SB_EXTRACT="$WORK_DIR/sing-box-extract"
mkdir -p "$SB_EXTRACT"
tar -xzf "$SB_TARBALL" -C "$SB_EXTRACT"
SB_BIN="$(find "$SB_EXTRACT" -type f -name sing-box | head -n 1)"
[ -n "$SB_BIN" ] || { echo "sing-box binary not found inside downloaded tarball" >&2; exit 1; }

mkdir -p "$STAGE/sbin"
cp "$SB_BIN" "$STAGE/sbin/sing-box"
chmod 755 "$STAGE/sbin/sing-box"

# ---- 3. Stage AntiGoblin sources ----
# Copy the whole repository (minus dev/local noise) into
# /opt/share/antigoblin-staged. firstboot points install.sh at this via
# ANTIGOBLIN_SRC_DIR, so the layout is exactly what install.sh expects.
STAGED_REPO="$STAGE/share/antigoblin-staged"
mkdir -p "$STAGED_REPO"
log "Staging AntiGoblin sources into $STAGED_REPO"

# Deliberately picking directories, not `cp -a $REPO_ROOT/*` — the working
# tree carries build artifacts (dist/, node_modules/, .git/, .env, memory)
# that must never end up on end-user routers.
for item in install.sh README.md LICENSE ui configs scripts docs; do
  if [ -e "$REPO_ROOT/$item" ]; then
    cp -R "$REPO_ROOT/$item" "$STAGED_REPO/"
  fi
done
chmod 755 "$STAGED_REPO/install.sh"

# Stamp version into the staged tree so users can identify which build is
# on a given router (`cat /opt/share/antigoblin-staged/VERSION`). Same
# string that would have gone into the tarball filename previously.
printf '%s\n' "$VERSION" > "$STAGED_REPO/VERSION"

# ---- 4. Install firstboot init script ----
FIRSTBOOT_SRC="$REPO_ROOT/scripts/xkeen/antigoblin-firstboot.sh"
[ -f "$FIRSTBOOT_SRC" ] || { echo "Missing $FIRSTBOOT_SRC — cannot build USB installer" >&2; exit 1; }

mkdir -p "$STAGE/etc/init.d"
cp "$FIRSTBOOT_SRC" "$STAGE/etc/init.d/S99antigoblin-firstboot"
chmod 755 "$STAGE/etc/init.d/S99antigoblin-firstboot"

# ---- 5. Optional: bundle .ipk cache for offline install ----
# We ship an empty cache for MVP. firstboot's install.sh call will `opkg
# install` online — if the router boots WAN-up (the default), this is
# unnoticeable. Populating the cache is a future-work item, tracked by
# `docs/architecture.md` under "USB installer notes".
mkdir -p "$STAGE/var/opkg-cache"

# ---- 6. Repack the whole stage back into a single installer tarball ----
# Filename is deliberately identical to a vanilla Entware installer
# (`<arch>-installer.tar.gz`) so the user drops it into USB `install/`
# without renaming. Version stamped inside via VERSION file (step 3).
TAR_OUT="$DIST_DIR/${ARCH}-installer.tar.gz"
log "Packing final tarball: $TAR_OUT"
# Change into $STAGE so paths inside the archive start at `bin/…`,
# `etc/…`, `share/…` — matching Entware's own installer tarball layout.
# npkg extracts these directly into /opt on the router. Using
# `--owner=root --group=root` so extraction doesn't preserve build-host
# UIDs (would show ugly numeric owners).
tar --owner=0 --group=0 -czf "$TAR_OUT" -C "$STAGE" .

# ---- 7. Wrap the tarball into a ready-to-flash zip ----
# The zip contains `install/<arch>-installer.tar.gz` at its top level.
# User downloads the zip, opens it, "Extract to..." → USB stick root, and
# the correct folder structure appears automatically. No mkdir, no rename,
# no possibility of misspelling `install/` as `Install/` etc.
ZIP_OUT="$DIST_DIR/antigoblin-usb-${ARCH}.zip"
ZIP_STAGE="$WORK_DIR/zip-stage"
mkdir -p "$ZIP_STAGE/install"
cp "$TAR_OUT" "$ZIP_STAGE/install/${ARCH}-installer.tar.gz"
log "Packing user-facing zip: $ZIP_OUT"
rm -f "$ZIP_OUT"
# -j would strip paths; we want `install/…` preserved. -q silences the
# per-file listing but keeps errors visible.
( cd "$ZIP_STAGE" && zip -qr "$ZIP_OUT" install/ )

TAR_SIZE_MB="$(du -m "$TAR_OUT" | awk '{print $1}')"
ZIP_SIZE_MB="$(du -m "$ZIP_OUT" | awk '{print $1}')"
log "Done. tarball=${TAR_SIZE_MB} MB, zip=${ZIP_SIZE_MB} MB (version stamp: $VERSION)"

cat <<EOF

Build complete.

Recommended for end-users:
  $ZIP_OUT
  → download, "Extract to..." into USB stick ROOT
  → the correct install/${ARCH}-installer.tar.gz appears in place

Alternative (for people who prefer to drop the tarball manually):
  $TAR_OUT
  → put in <USB root>/install/${ARCH}-installer.tar.gz

Then in Keenetic Web UI: "Приложения → Менеджер пакетов OPKG" → point at
this USB. Router will unpack, reboot, and on next boot S99antigoblin-firstboot
runs install.sh with ANTIGOBLIN_SRC_DIR=/opt/share/antigoblin-staged.

Verify version on the router later:
  cat /opt/share/antigoblin-staged/VERSION
EOF
