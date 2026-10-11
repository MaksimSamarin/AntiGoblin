# Service catalog

The traffic rules panel offers a searchable catalog of 31 service presets with
12 shortcuts. Presets use the installed GeoSite/GeoIP databases. The catalog
requires installed databases; update them before adding services when absent.
The router-side Geo compiler validates category presence during apply.

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

Discord includes the existing `66.22.192.0/18` range when voice CIDRs are enabled.
Locally observed destinations are imported from the active profile's
`discord-voice-observed` group and retained as profile-owned CIDRs. These
observations are not embedded in the shared catalog. Current observed endpoints
do not constitute universal Discord coverage; reconnecting or changing region
may require additional addresses. Custom rules and other groups are not
removed when the preset voice option is disabled.

Store/launcher presets do not imply routing every game server. Website presets
for calling applications do not imply complete voice/media coverage. Scope is
shown in the picker and in the group's generated rule details. Broad ecosystem
presets are labeled separately.

Validation: `node tests/service-catalog.js`, the existing UI/subscription/Geo
tests, and a server-hosted isolated router preview. Lab configuration and local
observed destination fixtures are kept outside the shared repository.
