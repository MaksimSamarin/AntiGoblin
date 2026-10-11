#!/bin/sh
PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin

MODE="${1:-status}"
ASSET_DIR=/opt/etc/xray/dat
CONFIG_DIR=/opt/etc/xray/configs
STATE=/opt/share/xkeen-manager/xkeen-ui-state.json
META="$ASSET_DIR/antigoblin-geodata.json"
LOG=/opt/var/log/xkeen-geodata.log
RUNTIME=/opt/share/xkeen-manager/api/xkeen-runtime.sh
GEODATA_WORKER=/opt/share/xkeen-manager/api/geodata.js
RUNTIME_DIR=/opt/share/xkeen-manager/runtime
VPN_IP_CACHE="$RUNTIME_DIR/geoip-vpn.cidrs"
BYPASS_IP_CACHE="$RUNTIME_DIR/geoip-bypass.cidrs"
CACHE_STATE_SHA="$RUNTIME_DIR/geodata-state.sha256"
BASE_URL="${XKEEN_GEODATA_BASE_URL:-https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download}"
MAX_SIZE=67108864
UPDATE_INTERVAL=604800
RETRY_INTERVAL=21600
ATTEMPT_STAMP=/tmp/xkeen-geodata-update-last-attempt

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }
file_size() { [ -f "$1" ] && wc -c < "$1" 2>/dev/null || echo 0; }

status() {
  GEOIP_SIZE="$(file_size "$ASSET_DIR/geoip.dat")"
  GEOSITE_SIZE="$(file_size "$ASSET_DIR/geosite.dat")"
  UPDATED_AT="$(jq -r '.updatedAt // 0' "$META" 2>/dev/null || echo 0)"
  case "$UPDATED_AT" in ''|*[!0-9]*) UPDATED_AT=0 ;; esac
  jq -cn \
    --argjson installed "$([ "$GEOIP_SIZE" -gt 0 ] && [ "$GEOSITE_SIZE" -gt 0 ] && echo true || echo false)" \
    --argjson geoipSize "$GEOIP_SIZE" --argjson geositeSize "$GEOSITE_SIZE" \
    --argjson updatedAt "$UPDATED_AT" --arg source "$BASE_URL" \
    '{ok:true,installed:$installed,geoipSize:$geoipSize,geositeSize:$geositeSize,updatedAt:$updatedAt,source:$source,autoUpdateDays:7}'
}

profile_uses_geodata() {
  [ -f "$STATE" ] || return 1
  jq -e '
    any(.profiles[]?.groups[]?;
      any(.domains[]?; ascii_downcase | startswith("geosite:"))
      or any(.cidrs[]?; ascii_downcase | startswith("geoip:")))
  ' "$STATE" >/dev/null 2>&1
}

download_one() {
  NAME="$1"
  DEST="$2"
  curl -fsSL --retry 1 --retry-max-time 100 --connect-timeout 10 --max-time 90 --max-filesize "$MAX_SIZE" \
    -A 'AntiGoblin-geodata/1.0' -o "$DEST/$NAME" "$BASE_URL/$NAME" || return 1
  curl -fsSL --retry 1 --retry-max-time 40 --connect-timeout 10 --max-time 30 --max-filesize 4096 \
    -A 'AntiGoblin-geodata/1.0' -o "$DEST/$NAME.sha256sum" "$BASE_URL/$NAME.sha256sum" || return 1
  EXPECTED="$(awk 'NR==1 {print tolower($1)}' "$DEST/$NAME.sha256sum")"
  ACTUAL="$(sha256sum "$DEST/$NAME" | awk '{print tolower($1)}')"
  case "$EXPECTED" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
    *) return 1 ;;
  esac
  [ "${#EXPECTED}" -eq 64 ] && [ "$ACTUAL" = "$EXPECTED" ]
}

rollback_assets() {
  for NAME in geoip.dat geosite.dat; do
    rm -f "$ASSET_DIR/$NAME.new-$$" "$ASSET_DIR/$NAME.rollback-$$"
    BACKUP="$ASSET_DIR/$NAME.bak-antigoblin-update"
    if [ -f "$BACKUP" ]; then
      rm -f "$ASSET_DIR/$NAME"
      mv "$BACKUP" "$ASSET_DIR/$NAME"
    else
      rm -f "$ASSET_DIR/$NAME"
    fi
  done
}

update_assets() {
  [ -x /opt/bin/curl ] || { log 'update failed: curl missing'; return 1; }
  [ -x /opt/bin/jq ] || { log 'update failed: jq missing'; return 1; }
  [ -x /opt/sbin/xray ] || { log 'update failed: xray missing'; return 1; }
  [ -f "$RUNTIME" ] || { log 'update failed: runtime missing'; return 1; }
  mkdir -p "$ASSET_DIR" || return 1
  AVAILABLE_KB="$(df -Pk "$ASSET_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
  case "$AVAILABLE_KB" in ''|*[!0-9]*) AVAILABLE_KB=0 ;; esac
  [ "$AVAILABLE_KB" -ge 131072 ] || { log "update failed: less than 128 MiB free"; return 1; }

  WORK="/tmp/xkeen-geodata-update-$$"
  LOCK_HELD=0
  mkdir -p "$WORK/download" || return 1
  trap 'rm -rf "$WORK"; [ "${LOCK_HELD:-0}" = "1" ] && xkeen_lock_release || true' EXIT INT TERM
  download_one geoip.dat "$WORK/download" & PID_IP=$!
  download_one geosite.dat "$WORK/download" & PID_SITE=$!
  RC=0
  wait "$PID_IP" || RC=1
  wait "$PID_SITE" || RC=1
  [ "$RC" -eq 0 ] || { log 'update failed: download or checksum'; return 1; }
  XRAY_LOCATION_ASSET="$WORK/download" /opt/sbin/xray run -test -confdir "$CONFIG_DIR" >/dev/null 2>&1 \
    || { log 'update failed: candidate assets reject current xray config'; return 1; }

  . "$RUNTIME"
  xkeen_lock_acquire || { log 'update skipped: apply lock busy'; return 1; }
  LOCK_HELD=1
  cp "$WORK/download/geoip.dat" "$ASSET_DIR/geoip.dat.new-$$" \
    && cp "$WORK/download/geosite.dat" "$ASSET_DIR/geosite.dat.new-$$" \
    || { rm -f "$ASSET_DIR/geoip.dat.new-$$" "$ASSET_DIR/geosite.dat.new-$$"; log 'update failed: staging'; return 1; }
  for NAME in geoip.dat geosite.dat; do
    BACKUP="$ASSET_DIR/$NAME.bak-antigoblin-update"
    rm -f "$BACKUP"
    [ -f "$ASSET_DIR/$NAME" ] && mv "$ASSET_DIR/$NAME" "$BACKUP"
    if ! mv "$ASSET_DIR/$NAME.new-$$" "$ASSET_DIR/$NAME"; then
      rollback_assets
      log 'update failed: atomic install'
      return 1
    fi
  done
  chmod 644 "$ASSET_DIR/geoip.dat" "$ASSET_DIR/geosite.dat" 2>/dev/null || true
  if ! XRAY_LOCATION_ASSET="$ASSET_DIR" /opt/sbin/xray run -test -confdir "$CONFIG_DIR" >/dev/null 2>&1; then
    rollback_assets
    log 'update failed: installed assets reject current xray config; rolled back'
    return 1
  fi

  NOW_MS=$(( $(date +%s) * 1000 ))
  GEOIP_HASH="$(sha256sum "$ASSET_DIR/geoip.dat" | awk '{print $1}')"
  GEOSITE_HASH="$(sha256sum "$ASSET_DIR/geosite.dat" | awk '{print $1}')"
  if ! jq -cn --argjson updatedAt "$NOW_MS" --arg source "$BASE_URL" \
      --arg geoipSha256 "$GEOIP_HASH" --arg geositeSha256 "$GEOSITE_HASH" \
      --argjson geoipSize "$(file_size "$ASSET_DIR/geoip.dat")" \
      --argjson geositeSize "$(file_size "$ASSET_DIR/geosite.dat")" \
      '{updatedAt:$updatedAt,source:$source,geoipSha256:$geoipSha256,geositeSha256:$geositeSha256,geoipSize:$geoipSize,geositeSize:$geositeSize}' \
      > "$ASSET_DIR/antigoblin-geodata.json.new-$$" \
      || ! chmod 644 "$ASSET_DIR/antigoblin-geodata.json.new-$$" \
      || ! mv "$ASSET_DIR/antigoblin-geodata.json.new-$$" "$META"; then
    rollback_assets
    log 'update failed: metadata write; rolled back'
    return 1
  fi
  if profile_uses_geodata; then
    render_ipsets "$STATE" || {
      rm -f "$CACHE_STATE_SHA"
      log 'update warning: failed to refresh GeoIP ipset cache'
    }
  fi
  touch /tmp/xkeen-needs-xray-restart
  rm -rf /tmp/xkeen-geodata-cache-* 2>/dev/null || true
  log "update complete geoip=$(file_size "$ASSET_DIR/geoip.dat") geosite=$(file_size "$ASSET_DIR/geosite.dat")"
  printf '%s\n' 'geoip.dat and geosite.dat updated; xray restart scheduled'
}

render_singbox() {
  RENDER_STATE="$1"
  RENDER_INPUT="$2"
  RENDER_OUTPUT="$3"
  [ -f "$RENDER_STATE" ] && [ -f "$RENDER_INPUT" ] || return 1
  if ! jq -e '
    (.activeProfileId // "") as $id
    | .profiles[]? | select(.id == $id)
    | any(.groups[]?;
        (.enabled != false)
        and (any(.domains[]?; ascii_downcase | startswith("geosite:"))
          or any(.cidrs[]?; ascii_downcase | startswith("geoip:"))))
  ' "$RENDER_STATE" >/dev/null 2>&1; then
    cp "$RENDER_INPUT" "$RENDER_OUTPUT" || return 1
    EMPTY_RULES="/tmp/xkeen-geodata-empty-$$.json"
    printf '%s\n' '{"vpnCidrs":[],"bypassCidrs":[]}' > "$EMPTY_RULES"
    write_ipset_caches "$RENDER_STATE" "$EMPTY_RULES" || { rm -f "$EMPTY_RULES"; return 1; }
    rm -f "$EMPTY_RULES"
    return 0
  fi
  [ -x /opt/bin/qjs ] && [ -f "$GEODATA_WORKER" ] \
    && [ -s "$ASSET_DIR/geoip.dat" ] && [ -s "$ASSET_DIR/geosite.dat" ] || return 1
  RULES="/tmp/xkeen-geodata-render-$$.json"
  /opt/bin/qjs --std "$GEODATA_WORKER" singbox "$RENDER_STATE" \
    "$ASSET_DIR/geoip.dat" "$ASSET_DIR/geosite.dat" "$RULES" >/dev/null 2>&1 || return 1
  write_ipset_caches "$RENDER_STATE" "$RULES" || { rm -f "$RULES"; return 1; }
  jq --slurpfile geo "$RULES" \
    '.route.rules = $geo[0].rules | .route.final = $geo[0].final' \
    "$RENDER_INPUT" > "$RENDER_OUTPUT" || return 1
  /opt/sbin/sing-box check -c "$RENDER_OUTPUT" >/dev/null 2>&1 || return 1
  rm -f "$RULES"
}

write_ipset_caches() {
  CACHE_STATE="$1"
  CACHE_RULES="$2"
  mkdir -p "$RUNTIME_DIR" || return 1
  VPN_NEW="$VPN_IP_CACHE.new-$$"
  BYPASS_NEW="$BYPASS_IP_CACHE.new-$$"
  SHA_NEW="$CACHE_STATE_SHA.new-$$"
  jq -r '.vpnCidrs[]?' "$CACHE_RULES" | sed '/^[[:space:]]*$/d' | sort -u > "$VPN_NEW" \
    && jq -r '.bypassCidrs[]?' "$CACHE_RULES" | sed '/^[[:space:]]*$/d' | sort -u > "$BYPASS_NEW" \
    && sha256sum "$CACHE_STATE" | awk '{print $1}' > "$SHA_NEW" \
    && mv "$VPN_NEW" "$VPN_IP_CACHE" \
    && mv "$BYPASS_NEW" "$BYPASS_IP_CACHE" \
    && mv "$SHA_NEW" "$CACHE_STATE_SHA" \
    || { rm -f "$VPN_NEW" "$BYPASS_NEW" "$SHA_NEW"; return 1; }
  chmod 644 "$VPN_IP_CACHE" "$BYPASS_IP_CACHE" "$CACHE_STATE_SHA" 2>/dev/null || true
}

render_ipsets() {
  RENDER_STATE="$1"
  [ -f "$RENDER_STATE" ] || return 1
  [ -x /opt/bin/qjs ] && [ -f "$GEODATA_WORKER" ] \
    && [ -s "$ASSET_DIR/geoip.dat" ] && [ -s "$ASSET_DIR/geosite.dat" ] || return 1
  RULES="/tmp/xkeen-geodata-ipsets-$$.json"
  /opt/bin/qjs --std "$GEODATA_WORKER" singbox "$RENDER_STATE" \
    "$ASSET_DIR/geoip.dat" "$ASSET_DIR/geosite.dat" "$RULES" >/dev/null 2>&1 || return 1
  write_ipset_caches "$RENDER_STATE" "$RULES"
  RC=$?
  rm -f "$RULES"
  return "$RC"
}

case "$MODE" in
  status) status ;;
  update) date +%s > "$ATTEMPT_STAMP"; update_assets ;;
  render-singbox)
    [ "$#" -eq 4 ] || { echo "usage: $0 render-singbox STATE INPUT OUTPUT" >&2; exit 2; }
    render_singbox "$2" "$3" "$4"
    ;;
  render-ipsets)
    [ "$#" -eq 2 ] || { echo "usage: $0 render-ipsets STATE" >&2; exit 2; }
    render_ipsets "$2"
    ;;
  cron)
    profile_uses_geodata || exit 0
    NOW="$(date +%s)"
    LAST="$(jq -r '(.updatedAt // 0) / 1000 | floor' "$META" 2>/dev/null || echo 0)"
    ATTEMPT="$(cat "$ATTEMPT_STAMP" 2>/dev/null || echo 0)"
    case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
    case "$ATTEMPT" in ''|*[!0-9]*) ATTEMPT=0 ;; esac
    [ $((NOW - LAST)) -ge "$UPDATE_INTERVAL" ] || exit 0
    [ $((NOW - ATTEMPT)) -ge "$RETRY_INTERVAL" ] || exit 0
    printf '%s\n' "$NOW" > "$ATTEMPT_STAMP"
    update_assets >/dev/null 2>&1 || true
    ;;
  *) echo "usage: $0 {status|update|cron|render-singbox|render-ipsets}" >&2; exit 2 ;;
esac
