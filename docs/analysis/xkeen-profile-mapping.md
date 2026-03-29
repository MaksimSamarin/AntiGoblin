# XKeen Profile Mapping

This note maps the current working manual router profile to the files XKeen expects.

## Source Profile

Current manual profile source:

- [prompt.md](/e:/Домашние проекты/VPN на роутере/docs/prompt.md)
- current router file: `/opt/etc/xray/<SOCKS_USERNAME>_config.json`

## Values To Preserve

- server: `<VLESS_SERVER_HOST>`
- port: `<VLESS_SERVER_PORT>`
- protocol: `VLESS`
- transport: `TCP`
- security: `Reality`
- UUID: `<VLESS_UUID>`
- flow: `xtls-rprx-vision`
- public key: `<REALITY_PUBLIC_KEY>`
- SNI/serverName: `<REALITY_SERVER_NAME>`
- shortId: `<REALITY_SHORT_ID>`
- fingerprint: `random`

## XKeen Draft Files

- outbound draft:
  - [04_outbounds.vdpsina-reality-draft.json](/e:/Домашние проекты/VPN на роутере/configs/xkeen/04_outbounds.vdpsina-reality-draft.json)
- routing draft:
  - [05_routing.hydraroute-draft.json](/e:/Домашние проекты/VPN на роутере/configs/xkeen/05_routing.hydraroute-draft.json)

## Key Notes

- XKeen stock template uses `fingerprint: chrome`; this draft changes it to `random`
  to match the currently working PC/router outbound profile more closely.
- XKeen stock outbound template defaults to port `443`; this draft uses the real server
  port `<VLESS_SERVER_PORT>`.
- direct exceptions for:
  - `stalcraft.net`
  - `exbo.net`
  - `cdn77.org`
  are preserved in the routing draft.

## Migration Intent

When the migration window starts, the relevant XKeen template files should be replaced
with the draft versions from this repository before `xkeen -i` is used as the active path.
