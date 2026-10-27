#!/bin/sh
set -eu
repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$tmp/job with spaces" "$tmp/lock" "$tmp/status"
awk '/^launch_worker\(\) \{/ { emit=1 } emit { print } emit && /^\}/ { exit }' \
  "$repo/scripts/xkeen/antigoblin-app-update.sh" > "$tmp/launch.sh"
test -s "$tmp/launch.sh"
cat > "$tmp/job with spaces/worker.sh" <<'WORKER'
#!/bin/sh
test "$1" = worker
test "$2" = "$work"
printf '%s\n' launched > "$2/result"
WORKER
export work="$tmp/job with spaces" DIR="$tmp/status" LOCK="$tmp/lock"
SHELL_BIN="$(command -v sh)"; export SHELL_BIN
# An empty utility path reproduces Entware without nohup. The parent exits
# immediately; the detached real launcher must still run the immutable job.
"$SHELL_BIN" -c '. "$1"; PATH=/no-external-utilities; launch_worker' sh "$tmp/launch.sh"
for attempt in 1 2 3 4 5; do
  [ ! -f "$work/result" ] || break
  sleep 1
done
test "$(cat "$work/result")" = launched
case "$(cat "$LOCK/pid")" in ''|*[!0-9]*) exit 1 ;; esac
echo 'PASS: detached updater starts without nohup and preserves spaced job arguments'
