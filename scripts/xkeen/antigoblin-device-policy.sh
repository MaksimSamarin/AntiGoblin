#!/bin/sh
# Device policy is router-wide, independent of the selected traffic profile.
set -eu
PATH="/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin:$PATH"
BASE="${ANTIGOBLIN_POLICY_ROOT:-/opt}"
NDMC="${ANTIGOBLIN_POLICY_NDMC:-ndmc}"
PARSER="${ANTIGOBLIN_POLICY_PARSER:-$BASE/share/xkeen-manager/api/device-policy-config.awk}"
STATE="$BASE/etc/antigoblin-device-policy.json"
UI_STATE="$BASE/share/xkeen-manager/xkeen-ui-state.json"
RUNTIME="$BASE/share/xkeen-manager/api/xkeen-runtime.sh"
TMP="$(mktemp -d)"
OWN_LOCK=0
TRANSACTION=0
CREATED=""
run() { LD_LIBRARY_PATH= "$NDMC" -c "$1"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }
valid_id() { case "$1" in ''|*[!A-Za-z0-9_./-]*) return 1 ;; esac; }
snapshot() {
  run 'show running-config' > "$TMP/config"
  # ndmc can emit terminal clear-line sequences even without a PTY.
  sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$TMP/config" | awk -f "$PARSER" > "$TMP/parsed"
  for kind in vpn no_vpn; do
    count="$(awk -F '\t' -v k="$kind" '$1==k{print $2}' "$TMP/parsed" | sort -u | wc -l)"
    [ "$count" -le 1 ] || fail 'Ambiguous policy descriptions; select a unique xkeen and no_vpn policy'
  done
  SEGMENT="$(awk -F '\t' '$1=="segment"{print $2;exit}' "$TMP/parsed")"
  VPN="$(awk -F '\t' '$1=="vpn"{print $2;exit}' "$TMP/parsed")"
  NOVPN="$(awk -F '\t' '$1=="no_vpn"{print $2;exit}' "$TMP/parsed")"
  valid_id "$SEGMENT" && valid_id "$VPN" || fail 'Cannot identify the primary segment and xkeen policy'
  CURRENT="$(awk -F '\t' -v s="$SEGMENT" '$1=="binding"&&$2==s{print $3;exit}' "$TMP/parsed")"
  [ -n "$CURRENT" ] || CURRENT=permit
}
save_config() {
  for attempt in 1 2 3; do run 'system configuration save' >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}
restore_policy() {
  mac="$1"; old="$2"
  if [ "$old" = '-' ]; then run "no ip hotspot host $mac policy" >/dev/null
  else run "ip hotspot host $mac policy $old" >/dev/null; fi
}
cleanup() {
  code=$?
  trap - EXIT INT TERM
  if [ "$TRANSACTION" = 1 ]; then
    run "ip hotspot policy $SEGMENT $ORIGINAL" >/dev/null 2>&1 || true
    if [ -f "$TMP/changed" ]; then
      while read -r mac old; do restore_policy "$mac" "$old" >/dev/null 2>&1 || true; done < "$TMP/changed"
    fi
    save_config || true
  fi
  if [ -n "$CREATED" ]; then run "no ip policy $CREATED" >/dev/null 2>&1 || true; save_config || true; fi
  [ "$OWN_LOCK" = 0 ] || xkeen_lock_release
  rm -f "$STATE.new-$$"
  rm -rf "$TMP"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
umask 077

ensure_no_vpn() {
  [ -z "$NOVPN" ] || return 0
  wans="$(awk -F '\t' '$1=="wan"{print $2}' "$TMP/parsed")"
  [ -n "$wans" ] || fail 'Cannot identify global internet connections for no_vpn'
  count="$(awk -F '\t' '$1=="policy"{print $2}' "$TMP/parsed" | sort -u | wc -l)"
  [ "$count" -lt 16 ] || fail 'Keenetic policy limit reached'
  number=42
  while awk -F '\t' -v p="Policy$number" '$1=="policy"&&$2==p{found=1} END{exit !found}' "$TMP/parsed"; do number=$((number+1)); done
  CREATED="Policy$number"
  run "ip policy $CREATED" >/dev/null
  run "ip policy $CREATED description no_vpn" >/dev/null
  for wan in $wans; do valid_id "$wan" || fail 'Invalid internet interface'; run "ip policy $CREATED permit global $wan" >/dev/null; done
  save_config || fail 'Cannot save no_vpn policy'
  expected="$CREATED"
  snapshot
  [ "$NOVPN" = "$expected" ] || fail 'no_vpn policy verification failed'
  CREATED=""
}
ready() {
  jq -e '.activeProfileId as $p | .profiles[] | select(.id==$p) | .activeProxyId as $key |
    any(.proxies[]?; .id==$key and (.config.address|type=="string" and length>0))' "$UI_STATE" >/dev/null 2>&1
}
status() {
  enabled=false; [ "$CURRENT" != "$VPN" ] || enabled=true
  usable=false; ready && usable=true
  managed=false; [ ! -f "$STATE" ] || managed=true
  jq -cn --argjson enabled "$enabled" --argjson ready "$usable" --argjson managed "$managed" \
    --arg segment "$SEGMENT" --arg vpnPolicy "$VPN" --arg noVpnPolicy "$NOVPN" \
    '{ok:true,enabled:$enabled,ready:$ready,managed:$managed,segment:$segment,vpnPolicy:$vpnPolicy,noVpnPolicy:$noVpnPolicy}'
}
home_hosts() {
  run 'show ip hotspot' > "$TMP/hotspot"
  awk -v segment="$SEGMENT" '
    function emit(){if(mac!="" && (iface=="Bridge0" || iface==segment) && access!="deny")print mac}
    /^[ \t]*host:/ {emit();mac="";iface="";access=""}
    $1=="mac:"{mac=tolower($2)} $1=="id:"{iface=$2} $1=="access:"{access=$2}
    END{emit()}' "$TMP/hotspot" | sort -u > "$TMP/home-hosts"
}
enable() {
  ready || fail 'Save and apply a working proxy key first'
  ensure_no_vpn
  ORIGINAL="$CURRENT"
  # Preserve the first snapshot across repeated enables and application updates.
  if [ -f "$STATE" ] && [ "$CURRENT" = "$VPN" ]; then
    jq -e '.version==1 and (.clients|type=="array")' "$STATE" >/dev/null || fail 'Invalid device policy recovery state'
    cp "$STATE" "$TMP/state"
  else
    previous="$CURRENT"; [ "$previous" != "$VPN" ] || previous=permit
    jq -cn --arg segment "$SEGMENT" --arg previous "$previous" '{version:1,segment:$segment,previousSegmentPolicy:$previous,clients:[]}' > "$TMP/state"
  fi
  [ "$(jq -r '.segment' "$TMP/state")" = "$SEGMENT" ] || fail 'Primary segment changed; restore its previous device policy first'
  home_hosts
  : > "$TMP/changed"
  while read -r mac; do
    old="$(awk -F '\t' -v m="$mac" '$1=="host"&&$2==m{print $3;exit}' "$TMP/parsed")"
    [ -n "$old" ] || continue
    [ "$old" != "$NOVPN" ] && [ "$old" != "$VPN" ] || continue
    case "$mac" in *[!0-9a-f:]*|'') fail 'Invalid client address' ;; esac
    printf '%s %s\n' "$mac" "$old" >> "$TMP/changed"
    jq --arg mac "$mac" --arg policy "$old" 'if any(.clients[]; .mac==$mac) then . else .clients += [{mac:$mac,policy:$policy}] end' "$TMP/state" > "$TMP/next"
    mv "$TMP/next" "$TMP/state"
  done < "$TMP/home-hosts"
  TRANSACTION=1
  while read -r mac old; do run "no ip hotspot host $mac policy" >/dev/null; done < "$TMP/changed"
  run "ip hotspot policy $SEGMENT $VPN" >/dev/null
  save_config || fail 'Cannot save default VPN policy'
  snapshot
  [ "$CURRENT" = "$VPN" ] || fail 'Default VPN policy was not applied'
  mkdir -p "$BASE/etc"
  cp "$TMP/state" "$STATE.new-$$"; chmod 600 "$STATE.new-$$"; mv "$STATE.new-$$" "$STATE"
  TRANSACTION=0
  status
}
disable() {
  # Respect a later manual segment change rather than overwriting it on disable.
  if [ "$CURRENT" != "$VPN" ]; then status; return; fi
  ORIGINAL="$CURRENT"
  previous=permit
  : > "$TMP/changed"
  : > "$TMP/restore"
  if [ -f "$STATE" ]; then
    [ "$(jq -r '.segment' "$STATE")" = "$SEGMENT" ] || fail 'Primary segment changed'
    previous="$(jq -r '.previousSegmentPolicy' "$STATE")"
    valid_id "$previous" || fail 'Invalid saved segment policy'
    jq -r '.clients[] | [.mac,.policy] | @tsv' "$STATE" > "$TMP/clients"
    while read -r mac old; do
      case "$mac" in *[!0-9a-f:]*|'') fail 'Invalid saved client address' ;; esac
      [ "${#mac}" = 17 ] && valid_id "$old" || fail 'Invalid saved client policy'
      current="$(awk -F '\t' -v m="$mac" '$1=="host"&&$2==m{print $3;exit}' "$TMP/parsed")"
      # A user choosing no_vpn (or any explicit override) owns that newer choice.
      [ -z "$current" ] || continue
      printf '%s %s\n' "$mac" "$old" >> "$TMP/restore"
      printf '%s -\n' "$mac" >> "$TMP/changed"
    done < "$TMP/clients"
  fi
  TRANSACTION=1
  while read -r mac old; do restore_policy "$mac" "$old"; done < "$TMP/restore"
  run "ip hotspot policy $SEGMENT $previous" >/dev/null
  save_config || fail 'Cannot save previous device policy'
  snapshot
  [ "$CURRENT" = "$previous" ] || fail 'Previous segment policy was not restored'
  rm -f "$STATE"
  TRANSACTION=0
  status
}

action="${1:-status}"
case "$action" in status|ensure|enable|disable) ;; *) fail 'Unknown device policy action' ;; esac
if [ "$action" != status ] && [ "${ANTIGOBLIN_POLICY_LOCK_HELD:-0}" != 1 ] && [ -f "$RUNTIME" ]; then
  . "$RUNTIME"
  xkeen_lock_acquire || fail 'Another runtime operation is active'
  OWN_LOCK=1
fi
snapshot
case "$action" in status) status ;; ensure) ensure_no_vpn; status ;; enable) enable ;; disable) disable ;; esac
