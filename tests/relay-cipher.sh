#!/usr/bin/env bash
# Verify the in-place migration of the loopback SS relay cipher (install.sh):
# Xray 25.x+ rejects "none", so old configs must be rewritten on both sides.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
installer="${INSTALL_UNDER_TEST:-$repo_root/install.sh}"
if ! command -v jq >/dev/null 2>&1; then
  echo 'SKIP: jq is not installed'
  exit 0
fi
extract_function() {
  awk -v name="$2" '$0 == name "() {" { emit=1 } emit { print } emit && $0 == "}" { exit }' "$1"
}
eval "$(extract_function "$installer" migrate_relay_cipher)"
log() { :; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export XRAY_RELAY_CONF="$work/02_relay.json"
export SINGBOX_LIVE_CONF="$work/xkeen.json"

# 1. Legacy configs are rewritten on both sides; everything else is preserved.
cat > "$XRAY_RELAY_CONF" <<'EOF'
{"inbounds":[{"tag":"proxy-relay-ss","listen":"127.0.0.1","port":62640,"protocol":"shadowsocks","settings":{"network":"tcp,udp","method":"none","password":"none"}}]}
EOF
cat > "$SINGBOX_LIVE_CONF" <<'EOF'
{"inbounds":[{"type":"tproxy","tag":"xkeen-udp-tproxy","listen_port":61221}],"outbounds":[{"type":"shadowsocks","tag":"proxy","server":"127.0.0.1","server_port":62640,"method":"none","password":"none"},{"type":"direct","tag":"direct"}]}
EOF
migrate_relay_cipher
[ "$(jq -r '.inbounds[0].settings.method' "$XRAY_RELAY_CONF")" = aes-128-gcm ]
[ "$(jq -r '.inbounds[0].settings.password' "$XRAY_RELAY_CONF")" = antigoblin-relay ]
[ "$(jq -r '.inbounds[0].settings.network' "$XRAY_RELAY_CONF")" = tcp,udp ]
[ "$(jq -r '.inbounds[0].port' "$XRAY_RELAY_CONF")" = 62640 ]
[ "$(jq -r '.outbounds[0].method' "$SINGBOX_LIVE_CONF")" = aes-128-gcm ]
[ "$(jq -r '.outbounds[0].password' "$SINGBOX_LIVE_CONF")" = antigoblin-relay ]
[ "$(jq -r '.outbounds[0].server_port' "$SINGBOX_LIVE_CONF")" = 62640 ]
[ "$(jq -r '.outbounds[1].type' "$SINGBOX_LIVE_CONF")" = direct ]
[ "$(jq -r '.inbounds[0].listen_port' "$SINGBOX_LIVE_CONF")" = 61221 ]
echo 'PASS: legacy cipher none is rewritten on both relay sides'

# 2. Already migrated configs stay byte-identical.
before_relay="$(cat "$XRAY_RELAY_CONF")"
before_sb="$(cat "$SINGBOX_LIVE_CONF")"
migrate_relay_cipher
[ "$before_relay" = "$(cat "$XRAY_RELAY_CONF")" ]
[ "$before_sb" = "$(cat "$SINGBOX_LIVE_CONF")" ]
echo 'PASS: migrated configs are left untouched'

# 3. A hysteria2 sing-box config and an unrelated shadowsocks inbound are not touched.
cat > "$SINGBOX_LIVE_CONF" <<'EOF'
{"outbounds":[{"type":"hysteria2","tag":"proxy","server":"hy2.example","server_port":443,"password":"secret"},{"type":"direct","tag":"direct"}]}
EOF
cat > "$XRAY_RELAY_CONF" <<'EOF'
{"inbounds":[{"tag":"other-ss","protocol":"shadowsocks","settings":{"method":"none","password":"none"}}]}
EOF
before_relay="$(cat "$XRAY_RELAY_CONF")"
before_sb="$(cat "$SINGBOX_LIVE_CONF")"
migrate_relay_cipher
[ "$before_relay" = "$(cat "$XRAY_RELAY_CONF")" ]
[ "$before_sb" = "$(cat "$SINGBOX_LIVE_CONF")" ]
echo 'PASS: hysteria2 outbound and unrelated inbounds are not rewritten'

# 4. Missing files and broken JSON are skipped without leftovers.
rm -f "$XRAY_RELAY_CONF"
printf '{broken' > "$SINGBOX_LIVE_CONF"
migrate_relay_cipher
[ ! -e "$XRAY_RELAY_CONF" ]
[ "$(cat "$SINGBOX_LIVE_CONF")" = '{broken' ]
if ls "$work" | grep -q 'tmp-cipher'; then
  echo 'FAIL: temporary file left behind' >&2
  exit 1
fi
echo 'PASS: missing or broken configs are skipped without leftovers'
