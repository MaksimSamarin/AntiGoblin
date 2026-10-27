# Read canonical Keenetic configuration without evaluating any of its contents.
function safe(s) { return s ~ /^[A-Za-z0-9_.\/-]+$/ }
function finish_interface() {
  if (iface == "Bridge0") print "segment\t" (alias != "" ? alias : iface)
  if (global && up && safe(iface)) print "wan\t" iface
}
function finish_policy() {
  if (description ~ /^xkeen($|:)/) print "vpn\t" policy
  if (description == "no_vpn") print "no_vpn\t" policy
}
{
  gsub(/\r/, "")
  if ($0 !~ /^[ \t]/) {
    finish_interface(); finish_policy()
    iface=""; alias=""; global=0; up=0; policy=""; description=""
  }
  if ($1 == "interface" && safe($2)) iface=$2
  if (iface && $1 == "rename" && safe($2)) alias=$2
  if (iface && $1 == "ip" && $2 == "global") global=1
  if (iface && $1 == "up") up=1
  if ($1 == "ip" && $2 == "policy" && safe($3)) {
    policy=$3; print "policy\t" policy
    if ($4 == "description") { description=$5; gsub(/^"|"$/, "", description) }
  }
  if (policy && $1 == "description") { description=$2; gsub(/^"|"$/, "", description) }
  if ($1 == "policy" && safe($2) && safe($3)) print "binding\t" $2 "\t" $3
  if ($1 == "host" && $2 ~ /^[0-9a-fA-F:]+$/ && length($2)==17 && $3 == "policy" && safe($4))
    print "host\t" tolower($2) "\t" $4
}
END { finish_interface(); finish_policy() }
