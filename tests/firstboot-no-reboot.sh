#!/usr/bin/env bash
# Regression test for the USB firstboot race: npkg can source our script
# before Entware supplies opkg. The worker must survive that gap and finish
# without a second boot or a manual SSH command.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

opt="$tmpdir/opt"
mkdir -p "$opt/etc/init.d" "$opt/share/antigoblin-staged/ui/xkeen-manager" "$tmpdir/bin"

# Convert the router's fixed /opt paths into our disposable test root.
sed "s|/opt|$opt|g" "$repo_root/scripts/xkeen/antigoblin-firstboot.sh" > "$tmpdir/firstboot.sh"
cp "$repo_root/scripts/xkeen/antigoblin-firstboot.sh" "$opt/etc/init.d/S99antigoblin-firstboot.sh"

cat > "$opt/share/antigoblin-staged/install.sh" <<'EOF'
#!/bin/sh
printf 'ran\n' > "${FIRSTBOOT_TEST_MARKER:?}"
EOF
chmod 755 "$opt/share/antigoblin-staged/install.sh"

cat > "$tmpdir/bin/ndmc" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$tmpdir/bin/ndmc"

marker="$tmpdir/install-ran"
PATH="$tmpdir/bin:$PATH" FIRSTBOOT_TEST_MARKER="$marker" sh -c ". '$tmpdir/firstboot.sh'"

# Entware appears after firstboot was already invoked. The old implementation
# exits here and never reaches the staged installer until a reboot.
sleep 1
mkdir -p "$opt/bin"
for command in opkg busybox; do
  printf '#!/bin/sh\nexit 0\n' > "$opt/bin/$command"
  chmod 755 "$opt/bin/$command"
done

for _ in $(seq 1 8); do
  [ -f "$marker" ] && break
  sleep 1
done

test -f "$marker"
test -f "$opt/etc/antigoblin.done"
for _ in $(seq 1 3); do
  [ ! -e "$opt/etc/init.d/S99antigoblin-firstboot.sh" ] && break
  sleep 1
done
test ! -e "$opt/etc/init.d/S99antigoblin-firstboot.sh"
echo "PASS: firstboot waits for Entware and completes without reboot"
