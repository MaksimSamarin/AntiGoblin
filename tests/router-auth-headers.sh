#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_file="$repo_root/ui/xkeen-manager/backend/routing.cgi"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

extract_function() {
  awk -v name="$2" '$0 == name "() {" { emit=1 } emit { print } emit && $0 == "}" { exit }' "$1"
}
extract_function "$source_file" auth_header_value > "$tmpdir/functions.sh"
extract_function "$source_file" auth_param_value >> "$tmpdir/functions.sh"
extract_function "$source_file" auth_set_cookie_pair >> "$tmpdir/functions.sh"
# Router scripts use Entware gawk at this path; use host awk in the unit test.
sed -i 's#/opt/bin/awk#awk#g' "$tmpdir/functions.sh"
# shellcheck source=/dev/null
. "$tmpdir/functions.sh"

standard='  HTTP/1.1 401 Unauthorized
  X-NDM-Realm: Keenetic Peak
  X-NDM-Challenge: abcdef0123456789
  Set-Cookie: language=ru; Path=/
  Set-Cookie: ndm_session=SID-123_abc; Path=/; SameSite=Strict
  WWW-Authenticate: x-ndw2-interactive realm="Keenetic Peak" challenge="abcdef0123456789" session_cookie="ndm_session"'
test "$(auth_header_value X-NDM-Realm "$standard")" = 'Keenetic Peak'
test "$(auth_header_value x-ndm-challenge "$standard")" = 'abcdef0123456789'
test "$(auth_set_cookie_pair ndm_session "$standard")" = 'ndm_session=SID-123_abc'

fallback='  WWW-Authenticate: x-ndw2-interactive realm=Keenetic-Viva challenge=feedface session_cookie=session_name session_id=session_value'
test "$(auth_param_value realm "$fallback")" = 'Keenetic-Viva'
test "$(auth_param_value challenge "$fallback")" = 'feedface'
test "$(auth_param_value session_cookie "$fallback")" = 'session_name'
test "$(auth_param_value session_id "$fallback")" = 'session_value'

json_body='{"realm":"must-not-be-trusted","challenge":"body-value"}'
test -z "$(auth_header_value X-NDM-Realm "$json_body")"
echo 'PASS: Keenetic auth parses X-NDM/Set-Cookie and legacy WWW-Authenticate formats'
