#!/usr/bin/env bash
# Exercise generated packet routing and upgrade preparation without a router.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
runtime="${RUNTIME_UNDER_TEST:-$repo_root/ui/xkeen-manager/backend/xkeen-runtime.sh}"
extract_function() {
  awk -v name="$2" '$0 == name "() {" { emit=1 } emit { print } emit && $0 == "}" { exit }' "$1"
}
eval "$(extract_function "$runtime" xkeen_apply_udp_route)"
eval "$(extract_function "$repo_root/install.sh" prepare_udp_dns_bypass)"

mock_udp_rules=()
mock_chain_exists=0
mock_fail_dns=0
mock_targeted=1
mock_quic=0
mock_quic_proxy=0
XKEEN_MARK=ffffaab
XKEEN_UDP_ROUTE_SET=xkeen_udp_route
XKEEN_BYPASS_SET=xkeen_bypass
XKEEN_TPROXY_PORT=61221
XKEEN_QUIC_TPROXY_PORT=61222
XKEEN_UDP_MARK=0x111
XKEEN_UDP_TABLE=111

xkeen_udp_config_enabled() { return 0; }
xkeen_build_udp_route_ipset() { return 0; }
xkeen_ipset_has_members() { [ "$mock_targeted" = 1 ]; }
xkeen_quic_config_enabled() { [ "$mock_quic" = 1 ]; }
xkeen_ensure_tproxy_module() { return 0; }
xkeen_delete_jumps() { return 0; }
xkeen_cleanup_udp_route() { mock_udp_rules=(); mock_chain_exists=0; }
xkeen_runtime_log() { :; }
ip() { :; }

# Model the chain operations used by the actual runtime and installer helpers.
iptables() {
  [ "$1" = -t ] && [ "$2" = mangle ] || return 2
  shift 2
  local operation="$1" chain="$2"
  shift 2
  [ "$chain" != PREROUTING ] || return 0
  if [ "$chain" = xkeen_quic_route ]; then
    if [[ "$operation $*" == '-A '*'-j TPROXY '* ]]; then mock_quic_proxy=1; fi
    return 0
  fi
  [ "$chain" = xkeen_udp_route ] || return 2
  case "$operation" in
    -N) mock_chain_exists=1 ;;
    -F) mock_udp_rules=() ;;
    -X) mock_chain_exists=0 ;;
    -S) [ "$mock_chain_exists" = 1 ] ;;
    -C)
      [ "$mock_chain_exists" = 1 ] || return 1
      local rule
      for rule in "${mock_udp_rules[@]}"; do [ "$rule" != "$*" ] || return 0; done
      return 1
      ;;
    -A|-I)
      [ "$mock_chain_exists" = 1 ] || return 1
      if [ "$operation" = -I ]; then [ "$1" = 1 ] || return 2; shift; fi
      if [ "$mock_fail_dns" = 1 ] && [[ " $* " == *' --dport 53 '* ]]; then return 1; fi
      if [ "$operation" = -I ]; then mock_udp_rules=("$*" "${mock_udp_rules[@]}")
      else mock_udp_rules+=("$*"); fi
      ;;
    *) return 2 ;;
  esac
}

# Evaluate first-match protocol/port/bypass rules for a UDP packet.
udp_action() {
  local destination="$1" port="$2" rule match action i
  local words=()
  for rule in "${mock_udp_rules[@]}"; do
    read -r -a words <<< "$rule"
    match=1; action=''
    for ((i=0; i<${#words[@]}; i++)); do
      case "${words[i]}" in
        -p) [ "${words[i+1]}" = udp ] || match=0 ;;
        --dport) [ "${words[i+1]}" = "$port" ] || match=0 ;;
        --match-set) [ "$destination" = 203.0.113.7 ] || match=0 ;;
        -j) action="${words[i+1]}" ;;
      esac
    done
    if [ "$match" = 1 ]; then printf '%s\n' "$action"; return; fi
  done
  printf 'UNMATCHED\n'
}
expect_action() {
  local actual
  actual="$(udp_action "$1" "$2")"
  [ "$actual" = "$3" ] || { printf 'FAIL: UDP %s:%s expected %s, got %s\n' "$1" "$2" "$3" "$actual" >&2; exit 1; }
}

xkeen_apply_udp_route
expect_action 8.8.8.8 53 RETURN
expect_action 192.168.2.1 53 RETURN
expect_action 198.51.100.4 443 TPROXY
expect_action 198.51.100.4 19323 TPROXY
expect_action 198.51.100.4 5300 TPROXY
expect_action 198.51.100.4 853 TPROXY
expect_action 203.0.113.7 19323 RETURN
xkeen_apply_udp_route
expect_action 8.8.8.8 53 RETURN
[ "${#mock_udp_rules[@]}" = 3 ]
echo 'PASS: DNS bypass survives rebuild; QUIC, voice, other ports and host bypass retain routing'

mock_targeted=0; mock_quic=1
xkeen_apply_udp_route
[ "$mock_chain_exists" = 0 ] && [ "$mock_quic_proxy" = 1 ]
echo 'PASS: QUIC-only configuration does not require the targeted UDP chain'

mock_chain_exists=0; mock_udp_rules=()
prepare_udp_dns_bypass
[ "$mock_chain_exists" = 0 ]
mock_chain_exists=1
mock_udp_rules=('-p udp -j TPROXY --on-port 61221')
prepare_udp_dns_bypass
expect_action 8.8.8.8 53 RETURN
expect_action 198.51.100.4 19323 TPROXY
prepare_udp_dns_bypass
[ "${#mock_udp_rules[@]}" = 2 ]
echo 'PASS: upgrade preparation fixes an existing chain once; fresh install needs no chain'

mock_udp_rules=('-p udp -j TPROXY --on-port 61221')
mock_fail_dns=1
if prepare_udp_dns_bypass; then echo 'FAIL: upgrade ignored a rejected DNS exception' >&2; exit 1; fi
mock_targeted=1; mock_quic=0
if xkeen_apply_udp_route; then echo 'FAIL: runtime ignored a rejected DNS exception' >&2; exit 1; fi
expect_action 8.8.8.8 53 UNMATCHED
echo 'PASS: rule installation failures propagate before unsafe proxying'
