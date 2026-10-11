#!/bin/sh
# Run only in a disposable AntiGoblin lab router container.
set -eu
[ "${ANTIGOBLIN_LAB_TEST:-}" = 1 ] && [ -f /usr/local/lib/antigoblin-lab/mock-process ] || exit 2
repo="${1:-/src}"
updater="$repo/scripts/xkeen/antigoblin-app-update.sh"
root=/opt/share/xkeen-manager
dir=/opt/var/run/antigoblin-app-update
testdir=/tmp/antigoblin-update-test
mkdir -p "$testdir" "$root" /opt/var/run /opt/bin
real_curl="$(command -v curl)"
cp /opt/bin/curl "$testdir/original-curl" 2>/dev/null || true
trap 'cp "$testdir/original-curl" /opt/bin/curl 2>/dev/null || true' EXIT
cat > /opt/bin/curl <<'CURL'
#!/bin/sh
dest=''; url=''
while [ "$#" -gt 0 ]; do
  case "$1" in -o) dest="$2"; shift ;; http*) url="$1" ;; esac
  shift
done
testdir=/tmp/antigoblin-update-test
case "$url" in
  https://api.github.com/repos/MaksimSamarin/AntiGoblin/releases/latest)
    [ ! -f "$testdir/network-fail" ] || exit 22
    cp "$testdir/release.json" "$dest" ;;
  https://codeload.github.com/MaksimSamarin/AntiGoblin/tar.gz/refs/tags/v1.5.0)
    cp "$testdir/source.tar.gz" "$dest" ;;
  http://127.0.0.1:8899/) printf '<html>ready</html>' ;;
  *) exit 22 ;;
esac
CURL
chmod 755 /opt/bin/curl
printf '1.4.0\n' > "$root/VERSION"
printf '{"activeProfileId":"keep","profiles":[{"id":"keep","subscriptions":[{"id":"sub","url":"https://example.test/private-token"}]}]}' > "$root/xkeen-ui-state.json"
cp "$root/xkeen-ui-state.json" "$testdir/state-before"
rm -rf "$dir" /opt/var/run/antigoblin-app-update.lock

release() { jq -cn --arg tag "$1" '{tag_name:$tag,draft:false,prerelease:false}' > "$testdir/release.json"; }
release v1.3.1
"$updater" check | jq -e '.currentVersion=="1.4.0" and .updateAvailable==false' >/dev/null
"$updater" start | jq -e '.running==false' >/dev/null
test ! -d /opt/var/run/antigoblin-app-update.lock
release 'v1.5.0;touch /tmp/antigoblin-injected'
if "$updater" check >/dev/null 2>&1; then echo 'malicious tag accepted'; exit 1; fi
test ! -f /tmp/antigoblin-injected
touch "$testdir/network-fail"
if "$updater" check >/dev/null 2>&1; then echo 'failed fetch reported success'; exit 1; fi
rm "$testdir/network-fail"
release v1.5.0
mkdir -p "$testdir/source/AntiGoblin-1.5.0/ui/xkeen-manager"
printf '1.5.0\n' > "$testdir/source/AntiGoblin-1.5.0/ui/xkeen-manager/VERSION"
cat > "$testdir/source/AntiGoblin-1.5.0/install.sh" <<'INSTALL'
#!/bin/sh
test "$ANTIGOBLIN_FORCE" = 0
sleep 2
if [ -f /tmp/antigoblin-update-test/install-fail ]; then
  printf '{"corrupt":true}' > /opt/share/xkeen-manager/xkeen-ui-state.json
  printf 'broken' > /opt/share/xkeen-manager/VERSION
  exit 1
fi
printf '1.5.0\n' > /opt/share/xkeen-manager/VERSION
INSTALL
tar -czf "$testdir/source.tar.gz" -C "$testdir/source" AntiGoblin-1.5.0
"$updater" start | jq -e '.running==true' >/dev/null
"$updater" start | jq -e '.running==true' >/dev/null
test "$(find "$dir" -maxdepth 1 -type d -name 'job-*' | wc -l)" = 1
for n in $(seq 1 25); do
  info="$("$updater" status)"
  printf '%s' "$info" | jq -e '.running==true' >/dev/null || break
  sleep 1
done
printf '%s' "$info" | jq -e '.phase=="succeeded" and .currentVersion=="1.5.0"' >/dev/null
cmp "$testdir/state-before" "$root/xkeen-ui-state.json"
printf '1.4.0\n' > "$root/VERSION"
touch "$testdir/install-fail"
"$updater" start >/dev/null
for n in $(seq 1 30); do
  info="$("$updater" status)"
  printf '%s' "$info" | jq -e '.running==true' >/dev/null || break
  sleep 1
done
printf '%s' "$info" | jq -e '.phase=="failed" and .currentVersion=="1.4.0"' >/dev/null
cmp "$testdir/state-before" "$root/xkeen-ui-state.json"
test ! -d /opt/var/run/antigoblin-app-update.lock
result="$(printf '{"confirm":true}' | REQUEST_METHOD=POST QUERY_STRING=kind=app-update-start \
  CONTENT_LENGTH=16 CONTENT_TYPE=application/json HTTP_COOKIE='' /bin/sh "$repo/ui/xkeen-manager/backend/routing.cgi")"
printf '%s' "$result" | grep -q 'Status: 401'
echo 'PASS: stable release pinning, no downgrade, hostile tag, fetch failure, duplicate start, preserved state, rollback and auth'
