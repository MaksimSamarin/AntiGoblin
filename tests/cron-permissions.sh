#!/bin/sh
set -eu

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM

# Source only the permission helper; running the installer would alter services.
awk '/^prepare_cron_permissions\(\) \{/ { emit=1 } emit { print } emit && /^\}/ { exit }' \
  "$REPO/install.sh" > "$TEST_DIR/helper.sh"
[ -s "$TEST_DIR/helper.sh" ]
. "$TEST_DIR/helper.sh"

TABLE="$TEST_DIR/cron table"
printf '%s\n' '*/1 * * * * root /opt/bin/run-parts /opt/etc/cron.1min' > "$TABLE"
cp "$TABLE" "$TEST_DIR/expected"
chmod 775 "$TABLE"
prepare_cron_permissions "$TABLE"
[ "$(ls -l "$TABLE" | awk '{print $1}')" = '-rw-------' ]
cmp "$TABLE" "$TEST_DIR/expected"

# Repeated installation preserves both permissions and every existing job.
prepare_cron_permissions "$TABLE"
[ "$(ls -l "$TABLE" | awk '{print $1}')" = '-rw-------' ]
cmp "$TABLE" "$TEST_DIR/expected"
prepare_cron_permissions "$TEST_DIR/absent"
[ ! -e "$TEST_DIR/absent" ]

# A filesystem that cannot change permissions must report failure to the caller.
if (chmod() { return 1; }; prepare_cron_permissions "$TABLE"); then
  echo 'FAIL: chmod failure was hidden' >&2
  exit 1
fi
chmod 775 "$TABLE"
if (chmod() { return 0; }; prepare_cron_permissions "$TABLE"); then
  echo 'FAIL: ineffective chmod was reported as success' >&2
  exit 1
fi
echo 'PASS: cron mode repaired, jobs preserved, repeated/missing-table cases and chmod failures handled'
