# VPN Setup Prompt: Keenetic + HydraRoute + XKeen/xray

Use this document as the compact handoff prompt for another session.
Canonical source of truth is `docs/architecture.md`.

## Current Working State

- Router: Keenetic
- OS: KeeneticOS / NDM
- Entware mounted at `/opt`
- CPU: `aarch64`
- SSH: `root@192.168.2.1:22`
- SSH password: `<ROUTER_SSH_PASSWORD>`

## Final Working Outcome From 2026-03-29

`OpenAI Codex compact` now works.

The working solution is a hybrid:

- `HydraRoute` remains the selector/UI layer
- `XKeen` became the actual transport path for marked traffic

This means the old problematic path:

```text
HydraRoute -> Proxy0 -> hev-socks5-tunnel -> xray SOCKS :1300 -> VLESS
```

was replaced for selected traffic by:

```text
HydraRoute -> connmark 0xffffaab -> XKeen REDIRECT :61219 -> xray -> VLESS
```

## What Was Proven

- same VLESS server works on PC through `v2rayN`
- old router path failed specifically on `compact`
- generic long-lived HTTPS was not the core issue
- strongest old suspect was `hev-socks5-tunnel` and its runtime behavior
- after moving traffic into `XKeen`, `compact` succeeded

So the practical root cause was the old Keenetic proxy-client delivery path, not the remote server.

## Current Roles

`HydraRoute` is kept because it is convenient:

- domain list management
- UI
- DNS/ipset matching
- mark selection

`XKeen` now does:

- local redirect handling
- xray runtime on port `61219`
- routing to `VLESS Reality` or `direct`

## Current Relevant Files

Legacy manual files:

- `/opt/etc/xray/<SOCKS_USERNAME>_config.json`
- `/opt/etc/xray/routing_config.json`

Current XKeen files:

- `/opt/etc/xray/configs/01_log.json`
- `/opt/etc/xray/configs/02_transport.json`
- `/opt/etc/xray/configs/03_inbounds.json`
- `/opt/etc/xray/configs/04_outbounds.json`
- `/opt/etc/xray/configs/05_routing.json`
- `/opt/etc/xray/configs/06_policy.json`
- `/opt/etc/init.d/S24xray`

HydraRoute files:

- `/opt/etc/HydraRoute/domain.conf`
- `/opt/etc/HydraRoute/hrneo.conf`
- `/opt/var/log/LOGhrneo.log`

## Important Local Fixes

These are not optional details; they are part of the working state.

### 1. XKeen generated init script fix

Generated `/opt/etc/init.d/S24xray` was broken on this router.

Local fixes applied:

- inserted `name_client="xray"`
- replaced `busybox ps` with plain `ps`

Without this the service looked for configs under `/opt/etc//configs` and failed.

### 2. XKeen transport template compatibility fix

Stock `02_transport.json` used deprecated global `transport` config rejected by `Xray 26.2.6`.

Current fix:

```json
{}
```

at:

- `/opt/etc/xray/configs/02_transport.json`

### 3. XKeen installer is interactive

During install the minimal choices used were:

- GeoIP: `0`
- GeoSite: `0`
- automatic updates / cron: `0`

## Current Outbound

Current `XKeen` outbound is based on the same working server/profile:

- server: `<VLESS_SERVER_HOST>`
- port: `<VLESS_SERVER_PORT>`
- protocol: `VLESS`
- transport: `TCP`
- security: `Reality`
- flow: `xtls-rprx-vision`
- fingerprint: `random`
- SNI/serverName: `<REALITY_SERVER_NAME>`

## Current Operational Guidance

Do not remove `HydraRoute` unless there is a strong reason.

Current recommended production approach:

- keep `HydraRoute` for UI and policy selection
- keep `XKeen` for the actual marked-traffic data path

If routing seems stale after changing HydraRoute list:

- verify `domain.conf`
- verify `ipset HydraRoute`
- consider browser cache / old live connections before assuming policy failure
