#!/bin/sh
# Authenticated CGI calls this worker; all remote sources are fixed to this repo.
PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin
ROOT=/opt/share/xkeen-manager
DIR=/opt/var/run/antigoblin-app-update
LOCK=/opt/var/run/antigoblin-app-update.lock
API=https://api.github.com/repos/MaksimSamarin/AntiGoblin/releases/latest
MODE="${1:-status}"
SHELL_BIN=/opt/bin/sh
[ -x "$SHELL_BIN" ] || SHELL_BIN=/bin/sh
mkdir -p "$DIR"
chmod 700 "$DIR"

valid_version() { printf '%s\n' "$1" | awk 'BEGIN{ok=0} /^[0-9]+\.[0-9]+\.[0-9]+$/{ok=1} END{exit !ok}'; }
current_version() {
  value="$(head -n 1 "$ROOT/VERSION" 2>/dev/null || true)"
  if valid_version "$value"; then printf '%s' "$value"; else printf unknown; fi
}
is_newer() {
  [ "$2" = unknown ] && return 0
  awk -v candidate="$1" -v current="$2" 'BEGIN {
    split(candidate,a,"."); split(current,b,".");
    for(i=1;i<=3;i++){if(a[i]+0>b[i]+0)exit 0;if(a[i]+0<b[i]+0)exit 1} exit 1
  }'
}
running() {
  [ -d "$LOCK" ] || return 1
  pid="$(cat "$LOCK/pid" 2>/dev/null || true)"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  command="$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  case "$command" in *antigoblin-app-update*|*worker.sh*worker*) return 0 ;; *) return 1 ;; esac
}
write_status() {
  jq -cn --arg phase "$1" --arg message "${2:-}" --argjson updatedAt "$(date +%s)" \
    '{phase:$phase,message:$message,updatedAt:$updatedAt}' > "$DIR/status.new-$$" && mv "$DIR/status.new-$$" "$DIR/status.json"
}
status() {
  current="$(current_version)"
  latest="$(jq -r '.version // empty' "$DIR/latest.json" 2>/dev/null || true)"
  valid_version "$latest" || latest=""
  available=false
  [ -n "$latest" ] && is_newer "$latest" "$current" && available=true
  active=false
  running && active=true
  phase="$(jq -r '.phase // "idle"' "$DIR/status.json" 2>/dev/null || echo idle)"
  message="$(jq -r '.message // empty' "$DIR/status.json" 2>/dev/null || true)"
  case "$phase" in starting|downloading|installing)
    if [ "$active" = false ]; then phase=failed; message='Update worker stopped; check the application and retry'; fi ;;
  esac
  jq -cn --arg currentVersion "$current" --arg latestVersion "$latest" \
    --argjson updateAvailable "$available" --argjson running "$active" --arg phase "$phase" --arg message "$message" \
    '{ok:true,currentVersion:$currentVersion,latestVersion:$latestVersion,updateAvailable:$updateAvailable,running:$running,phase:$phase,message:$message}'
}
check() {
  curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 25 --max-filesize 262144 \
    -H 'Accept: application/vnd.github+json' -A 'AntiGoblin-updater/1.0' -o "$DIR/release.new-$$" "$API" || {
      rm -f "$DIR/release.new-$$"; return 1;
    }
  tag="$(jq -r 'if .draft == false and .prerelease == false then .tag_name else empty end' "$DIR/release.new-$$" 2>/dev/null || true)"
  rm -f "$DIR/release.new-$$"
  case "$tag" in v*) version="${tag#v}" ;; *) return 1 ;; esac
  valid_version "$version" || return 1
  jq -cn --arg version "$version" --argjson checkedAt "$(date +%s)" \
    '{version:$version,checkedAt:$checkedAt}' > "$DIR/latest.new-$$" || return 1
  mv "$DIR/latest.new-$$" "$DIR/latest.json" || return 1
  status
}
unlock() { rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null || true; }
start() {
  if running; then status; return 0; fi
  # Never discard another start while it is creating its child.
  if ! mkdir "$LOCK" 2>/dev/null; then
    pid="$(cat "$LOCK/pid" 2>/dev/null || true)"
    case "$pid" in ''|*[!0-9]*)
      created="$(stat -c %Y "$LOCK" 2>/dev/null || date +%s)"
      [ $(( $(date +%s) - created )) -ge 30 ] || return 1 ;;
    esac
    unlock
    mkdir "$LOCK" 2>/dev/null || return 1
  fi
  echo $$ > "$LOCK/pid"
  if ! check >/dev/null; then unlock; return 1; fi
  target="$(jq -r '.version' "$DIR/latest.json")"
  if ! is_newer "$target" "$(current_version)"; then unlock; status; return 0; fi
  for old in "$DIR"/job-*; do
    [ ! -d "$old" ] || rm -rf "$old"
  done
  work="$DIR/job-$(date +%s)-$$"
  mkdir -p "$work" || { unlock; return 1; }
  chmod 700 "$work"
  cp "$0" "$work/worker.sh" || { unlock; return 1; }
  printf '%s\n' "$target" > "$work/target"
  write_status starting
  # Execute an immutable copy: installation replaces the live updater script.
  nohup "$SHELL_BIN" "$work/worker.sh" worker "$work" > "$DIR/update.log" 2>&1 </dev/null &
  echo $! > "$LOCK/pid"
  status
}
restart_owned_services() {
  for name in S24antigoblin-singbox S25antigoblin-selfheal S26antigoblin; do
    [ ! -x "/opt/etc/init.d/$name" ] || "/opt/etc/init.d/$name" restart >/dev/null 2>&1 || true
  done
  [ ! -x /opt/etc/init.d/S24xray ] || /opt/etc/init.d/S24xray restart >/dev/null 2>&1 || true
}
worker_cleanup() {
  if [ "$success" != 1 ]; then
    if [ "$install_started" = 1 ]; then
      if tar -xzf "$work/backup.tar.gz" -C /opt; then
        restart_owned_services
        reason='Installation failed; previous application and configuration restored'
      else
        reason='Installation failed; restoration needs manual attention'
      fi
    fi
    write_status failed "$reason"
  fi
  unlock
  # Retain one private recovery archive and bounded log for troubleshooting.
}
worker() {
  work="$2"
  target="$(cat "$work/target")"
  valid_version "$target" || return 1
  echo $$ > "$LOCK/pid"
  success=0; install_started=0; reason='Source download or validation failed'
  trap worker_cleanup EXIT
  trap 'exit 1' INT TERM
  available="$(df -Pk "$DIR" | awk 'NR==2{print $4}')"
  case "$available" in ''|*[!0-9]*) return 1 ;; esac
  [ "$available" -ge 262144 ] || { reason='At least 256 MiB free space is required'; return 1; }
  write_status downloading
  curl -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 180 --max-filesize 67108864 \
    -A 'AntiGoblin-updater/1.0' -o "$work/source.tar.gz" \
    "https://codeload.github.com/MaksimSamarin/AntiGoblin/tar.gz/refs/tags/v$target" || return 1
  tar -tzf "$work/source.tar.gz" > "$work/files" || return 1
  awk '/^\// || /(^|\/)\.\.(\/|$)/ {bad=1} END{exit bad}' "$work/files" || return 1
  mkdir "$work/source" || return 1
  tar -xzf "$work/source.tar.gz" -C "$work/source" || return 1
  src="$work/source/AntiGoblin-$target"
  [ -f "$src/install.sh" ] && [ -f "$src/ui/xkeen-manager/VERSION" ] || return 1
  [ "$(cat "$src/ui/xkeen-manager/VERSION")" = "$target" ] || return 1
  # Snapshot only application-owned files; never touch unrelated server/router data.
  : > "$work/backup-files"
  for path in share/xkeen-manager etc/xray/configs etc/sing-box/xkeen.json etc/antigoblin.conf \
    etc/init.d/S20antigoblin-sysctl etc/init.d/S24antigoblin-singbox etc/init.d/S24xray \
    etc/init.d/S25antigoblin-selfheal etc/init.d/S26antigoblin etc/cron.1min/50-antigoblin-selfheal \
    etc/ndm/netfilter.d/50-antigoblin.sh etc/ndm/usb.d/50-antigoblin.sh; do
    [ ! -e "/opt/$path" ] || printf '%s\n' "$path" >> "$work/backup-files"
  done
  tar -czf "$work/backup.tar.gz" -C /opt -T "$work/backup-files" || return 1
  port="$(sed -n 's/^PORT=//p' /opt/etc/antigoblin.conf 2>/dev/null | head -n 1)"
  case "$port" in ''|*[!0-9]*) port=8899 ;; esac
  write_status installing
  install_started=1
  [ ! -x /opt/etc/init.d/S25antigoblin-selfheal ] || /opt/etc/init.d/S25antigoblin-selfheal stop >/dev/null 2>&1 || true
  # Offline staged mode pins the complete source tree to the checked release.
  ANTIGOBLIN_SRC_DIR="$src" ANTIGOBLIN_FORCE=0 ANTIGOBLIN_UI_PORT="$port" \
    ANTIGOBLIN_WORK_DIR="$work/install-work" "$SHELL_BIN" "$src/install.sh" || return 1
  [ "$(current_version)" = "$target" ] || return 1
  curl --noproxy '*' -fsS --connect-timeout 3 --max-time 10 "http://127.0.0.1:$port/" >/dev/null || return 1
  success=1
  write_status succeeded
  rm -f "$work/source.tar.gz"
  printf '%s\n' 'Application update completed'
}

case "$MODE" in
  status) status ;;
  check) check ;;
  start) start ;;
  worker) worker "$@" ;;
  *) exit 2 ;;
esac
