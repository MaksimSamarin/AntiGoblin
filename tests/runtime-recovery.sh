#!/usr/bin/env bash
# Exercise recovery helpers against disposable init scripts, without a router.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

extract_function() {
  awk -v name="$2" '$0 == name "() {" { emit=1 } emit { print } emit && $0 == "}" { exit }' "$1"
}

init="$tmpdir/S24xray"
target='ARGS="run -confdir /opt/etc/xray/configs"'
for helper in selfheal remount deploy; do
  case "$helper" in
    selfheal)
      extract_function "$repo_root/ui/xkeen-manager/backend/xkeen-selfheal.sh" ensure_xray_init_confdir |
        sed "s|/opt/etc/init.d/S24xray|$init|g" > "$tmpdir/helper.sh"
      printf '\nensure_xray_init_confdir\n' >> "$tmpdir/helper.sh"
      ;;
    remount)
      extract_function "$repo_root/scripts/xkeen/antigoblin-remount-hook.sh" ensure_xray_init_confdir > "$tmpdir/helper.sh"
      printf '\nensure_xray_init_confdir\n' >> "$tmpdir/helper.sh"
      ;;
    deploy)
      # Read only the shell here-string, never execute the deployment script.
      sed -n '/^\$patchXrayInit = /,/^Invoke-RouterCommand/p' \
        "$repo_root/scripts/xkeen/deploy_xkeen_manager_backend_to_router.ps1" |
        sed '1d;$d;/^\x27@$/d' |
        sed "s|/opt/etc/init.d/S24xray|$init|g" > "$tmpdir/helper.sh"
      ;;
  esac
  for path in '/opt/etc/xray' '/opt/etc/$PROCS' '/opt/etc/xray/configs' '/custom/configs'; do
    printf '#!/bin/sh\nPROCS=xray\nARGS="run -confdir %s"\n' "$path" > "$init"
    cp "$init" "$tmpdir/before"
    XRAY_INIT="$init" sh -c 'health_log() { :; }; . "$1"' sh "$tmpdir/helper.sh"
    if [ "$path" = '/custom/configs' ]; then
      cmp "$init" "$tmpdir/before"
    else
      grep -Fxq "$target" "$init"
    fi
    cp "$init" "$tmpdir/after"
    XRAY_INIT="$init" sh -c 'health_log() { :; }; . "$1"' sh "$tmpdir/helper.sh"
    cmp "$init" "$tmpdir/after"
  done
  echo "PASS: $helper handles literal/variable paths, preserves custom paths, is idempotent"
done

extract_function "$repo_root/ui/xkeen-manager/backend/xkeen-runtime.sh" xkeen_ndmc > "$tmpdir/ndmc-test.sh"
cat >> "$tmpdir/ndmc-test.sh" <<'EOF'
ndmc() {
  [ -z "$LD_LIBRARY_PATH" ] || return 91
  [ "$#" -eq 2 ] && [ "$1" = '-c' ] && [ "$2" = 'show ip policy' ] || return 92
  return 7
}
LD_LIBRARY_PATH=/opt/lib:/opt/usr/lib
export LD_LIBRARY_PATH
rc=0
xkeen_ndmc -c 'show ip policy' || rc=$?
[ "$rc" -eq 7 ] && [ "$LD_LIBRARY_PATH" = '/opt/lib:/opt/usr/lib' ]
EOF
sh "$tmpdir/ndmc-test.sh"
echo 'PASS: ndmc receives isolated environment and intact arguments; exit status is preserved'
