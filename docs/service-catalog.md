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

The Discord voice-and-stream option includes `66.22.192.0/18` and these exact
media destinations confirmed on 2026-10-12:

- `104.29.149.49/32`
- `104.29.155.176/32`
- `104.29.155.181/32`
- `104.29.155.185/32`
- `104.29.155.187/32`
- `104.29.155.196/32`
- `104.29.155.201/32`
- `104.29.155.204/32`
- `104.29.158.3/32` (screen-share destination)

Additional local destinations are imported from the active profile's
`discord-voice-observed` group and retained as profile-owned CIDRs. They are
deduplicated against the preset; arbitrary profile observations do not modify
the shared catalog. These endpoints do not constitute universal Discord
coverage; reconnecting or changing region may require additional addresses.
Broader Cloudflare ranges are not included. Disabling the media option removes
its preset-owned routes while retaining Discord GeoSite, custom rules and
other groups.

Store/launcher presets do not imply routing every game server. Website presets
for calling applications do not imply complete voice/media coverage. Scope is
shown in the picker and in the group's generated rule details. Broad ecosystem
presets are labeled separately.

Validation: `node tests/service-catalog.js`, the existing UI/subscription/Geo
tests, and a server-hosted isolated router preview. Lab configuration and local
observed destination fixtures are kept outside the shared repository.
