# Service catalog

The traffic rules panel offers a searchable catalog of 32 service presets with
12 shortcuts. Most presets use the installed GeoSite/GeoIP databases. The catalog
requires installed databases; update them before adding services when absent.
The router-side Geo compiler validates category presence during apply.

## NAD / BluOS

`NAD / BluOS` is in **Video and music** and can be found by searching for
`NAD` or `BluOS`. It uses explicit vendor domains rather than a nonexistent
GeoSite category. It covers BluOS online services, firmware checks/downloads,
the BluOS website and NAD/Bluesound support. Spotify remains a separate preset;
other music providers and arbitrary radio streams are outside this preset.
Local player discovery and control keep using the router's existing LAN bypass.

Vendor domains: `bluos.net`, `bluos.io`, `bluesound.com`, `nadelectronics.com`.
On 2026-10-27, the actual C700 V2 updater used `ca2.upgrade.bluos.net`
(confirmed by the destination's TLS certificate), covered by `bluos.net`.
Its diagnostic log also confirmed `upgrade.nadelectronics.com`,
`main.news.bluos.net`, `1.ntp.bluos.net` and the firmware data host
`d27y2nb09d21cl.cloudfront.net`. That exact CloudFront distribution is included
alongside the vendor domains. A future CDN change may require a catalog update.
Do not add all of `cloudfront.net`, `amazonaws.com`, AWS networks or a catch-all
route: shared CDN infrastructure also hosts unrelated applications.

Sources: [BluOS downloads](https://bluos.io/downloads/),
[BluOS update instructions](https://support.bluos.net/hc/en-us/articles/360000205287-How-to-identify-and-update-the-current-BluOS-firmware-version-on-my-BluOS-Player).

## Preset ownership and coverage

Selecting services creates an ordinary routing group. Existing groups can also
receive presets. `domains` and `cidrs` remain the materialized routing fields
consumed by Xray, sing-box and the kernel ipsets; no runtime protocol changes
are introduced by the catalog.

Preset ownership is recorded in `serviceIds`, `serviceManualDomains`,
`serviceManualCidrs`, `serviceVoiceEnabled` and `serviceVoiceCidrs`. Additional
manual rules are merged with preset rules. Removing a preset retains manual
rules, including overlapping Geo tokens. JSON export, profile duplication and
reload preserve the metadata. Unknown future preset IDs retain their compiled
rules. Removing the last preset from an otherwise empty group disables the
group so it cannot accidentally enable the runtime's full-tunnel semantics.

The Discord voice-and-stream option includes these media ranges, restored
from a working legacy router profile on 2026-10-23:

- `66.22.192.0/18`
- `104.29.0.0/16`

Discord supplies the UDP destination during connection setup; clients must
not assume the next voice or stream connection will reuse an observed IP.
See [Discord's voice connection documentation](https://github.com/discord/discord-api-docs/blob/main/developers/topics/voice-connections.mdx).
The previous per-host list repeatedly missed new destinations inside
`104.29.0.0/16`, so it was replaced by the range rather than another `/32`.
All media destinations observed during the October incidents and the newly
encountered stream destination fit inside these ranges.

This is practical network coverage, not an official exclusive Discord IP
allocation or a guarantee that future regions will stay inside these ranges.
Shared addresses can route other services through the selected outbound.
The legacy profile's much broader Google and Cloudflare CIDRs are not part of
the preset. Routing still preserves explicit bypass groups.

Additional local destinations are imported from the active profile's
`discord-voice-observed` group and retained as profile-owned CIDRs. They are
deduplicated against the preset by exact value; arbitrary profile observations
do not modify the shared catalog. Existing host observations and manually
entered rules remain profile-owned, including ones now covered by a range.
Disabling the media option removes
its preset-owned routes while retaining Discord GeoSite, custom rules and
other groups.

Existing groups selected from the catalog adopt the current preset when the UI
loads their service metadata. Save and apply to activate the updated rules.
Plain manually created groups are unchanged; add Discord to an existing group
with the service picker if it should receive catalog-managed coverage.

Store/launcher presets do not imply routing every game server. Website presets
for calling applications do not imply complete voice/media coverage. Scope is
shown in the picker and in the group's generated rule details. Broad ecosystem
presets are labeled separately.

Validation: `node tests/service-catalog.js`, the existing UI/subscription/Geo
tests, and a server-hosted isolated router preview. Lab configuration and local
observed destination fixtures are kept outside the shared repository.
