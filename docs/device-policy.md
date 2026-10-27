# Default VPN group

The **VPN-группа по умолчанию / Default VPN group** checkbox controls the
primary home segment's Keenetic connection policy. It is router-wide and
independent of the currently selected AntiGoblin traffic profile. Routes inside
that profile still determine which destinations use VPN or direct access.

Installation and application updates create a missing `no_vpn` connection
policy using the router's global internet interfaces. An existing policy with
that description, including its custom WAN configuration, is retained. This
step does not enroll devices or change the segment binding. Fresh installs
therefore remain opt-in; an existing home-to-xkeen binding is displayed as on.

Enabling requires a saved active key and no pending profile edits. The operation
assigns the primary segment to the discovered xkeen policy. New devices inherit
it, whether registered or not. For existing clients identified in that segment,
other explicit policy assignments are changed to segment inheritance. Explicit
`no_vpn` assignments, internet-denied clients and other segments are retained.
Offline clients whose segment cannot be established are not guessed or moved.

Before migration, prior assignments are recorded in
`/opt/etc/antigoblin-device-policy.json`. Disabling restores the prior segment
binding and migrated client assignments, while retaining any newer explicit
manual overrides (especially `no_vpn`). Without an AntiGoblin migration record,
disabling an existing manual home-to-xkeen binding returns the segment to
`permit`; individual assignments remain. Changes apply immediately and survive
reboots. Reconnect applications or Wi-Fi to replace existing connections.

The controller discovers the primary Bridge0 alias and policy identifiers;
Policy42 and a particular router IP are not assumed. Duplicate descriptions,
missing internet interfaces, policy limits, invalid payloads and failed native
configuration saves produce errors. Partial policy/device changes are rolled
back. The endpoint uses the normal Keenetic session and runtime apply lock.

Implementation: `scripts/xkeen/antigoblin-device-policy.sh`,
`ui/xkeen-manager/backend/device-policy-config.awk` and the authenticated
`routing.cgi?kind=device-policy` endpoint. Recovery state is included in the
application updater's file snapshot. The native Keenetic policy is not a
domain/CIDR traffic group.

Validation: `python3 tests/device-policy.py`, `node tests/device-policy-ui.js`,
and real CGI/browser checks in the isolated server contour. The simulation does
not establish compatibility with every Keenetic firmware or replace checks on
the actual target router.
