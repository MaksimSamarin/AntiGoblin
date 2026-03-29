# v2rayN vs Router xray

## Purpose

This note compares the known working PC path with the router path that fails on `Codex compact`.

## Working PC Client

Path:
- `C:\Users\Home-PC\Desktop\v2rayN-windows-64`

Detected components:
- GUI: `v2rayN V7.18.0 X64`
- Core: `Xray 26.2.4 (go1.25.6 windows/amd64)`

Relevant `guiNConfig.json` observations:

- `TunModeItem.EnableTun = true`
- `TunModeItem.AutoRoute = true`
- `TunModeItem.StrictRoute = true`
- `TunModeItem.Stack = "gvisor"`
- `TunModeItem.Mtu = 9000`
- inbound SOCKS local port: `10808`
- inbound sniffing enabled
- `RouteOnly = false`
- `MuxEnabled = false`
- `Loglevel = "warning"`
- `DomainStrategy = "AsIs"`
- `EnableIPv6Address = false`

Active selected profile from `guiNDB.db` (`IndexId = 5076900947224219232`):

- Remarks: `vdpsina-samara_pc`
- Address: `<VLESS_SERVER_HOST>`
- Port: `<VLESS_SERVER_PORT>`
- Protocol family: `VLESS`
- Network: `tcp`
- Stream security: `reality`
- Flow: `xtls-rprx-vision`
- Security: `none`
- Fingerprint: `random`
- SNI: `<REALITY_SERVER_NAME>`
- Public key: same as router profile
- ShortId: same as router profile
- User ID: same as router profile

## Router Client

Observed router environment:

- Router xray: `26.2.6 (go1.25.7 linux/arm64)`
- Inbound: SOCKS on `1300`
- Sniffing enabled
- `routeOnly = true`
- Traffic delivery path:
  - LAN client
  - HydraRoute/ipset
  - Keenetic fwmark / proxy client
  - `t2s0`
  - SOCKS inbound on router xray
  - VLESS outbound

## Key Differences

### 1. Delivery model

PC:
- `v2rayN` uses TUN mode with `gvisor` stack and strict routing

Router:
- traffic is injected by Keenetic proxy routing into a SOCKS inbound
- xray is not handling a local TUN stack

This is currently the strongest architectural difference.

### 2. Inbound sniffing mode

PC:
- sniffing enabled
- `RouteOnly = false`

Router:
- sniffing enabled
- `routeOnly = true`

This may affect how destination metadata is applied internally.

Update after live test on 2026-03-29:

- router was temporarily switched from `routeOnly = true` to `routeOnly = false`
- `Codex compact` still failed with the same disconnect error
- therefore this difference is currently considered less likely to be the root cause

### 3. Domain strategy

PC:
- `DomainStrategy = "AsIs"`

Router:
- routing config uses `IPOnDemand`

This is a smaller but still meaningful difference for domain/IP handling.

### 4. IPv6 behavior

PC:
- `EnableIPv6Address = false`

Router:
- HydraRoute logs and system state show mixed IPv4 and IPv6 DNS handling in general
- actual observed `chatgpt.com` compact path was mainly IPv4 Fastly IPs

### 5. Runtime and platform

PC:
- Windows + v2rayN + Xray 26.2.4

Router:
- Keenetic/Entware + Xray 26.2.6

Version delta is small. Architecture and traffic injection model are much more important.

### 6. Outbound profile parity

The active PC profile and router outbound are effectively the same server/profile:

- same host
- same port
- same UUID
- same `flow`
- same `Reality` parameters
- same fingerprint policy

This makes the outbound server/profile itself much less likely to be the root cause.

## Current Interpretation

The remote VLESS server is unlikely to be the root cause, because it works through `v2rayN` on PC.

The most likely root cause is now one of:

- Keenetic delivery path into SOCKS inbound
- difference between TUN-mode client behavior and router SOCKS-inbound behavior
- `Codex compact` being sensitive to this exact connection model even though generic long-lived HTTPS works

## New Strong Evidence From Live Socket Monitoring

Router monitoring showed that the local process feeding xray SOCKS is:

- `hev-socks5-tu`

Observed socket relationship:

- `hev-socks5-tu -> 192.168.2.1:1300`
- `xray <- :1300`

Observed close behavior:

- xray side entered `CLOSE_WAIT`
- peer side entered `FIN_WAIT2`

Current interpretation:

- the inbound SOCKS side appears to be closed by the local proxy-delivery layer before xray itself initiates closure
- this makes `hev-socks5-tu` / Keenetic proxy delivery much more suspicious than the outbound VLESS profile

## Most Useful Next Checks

1. compare whether `RouteOnly = false` on router changes behavior
2. compare router routing `domainStrategy` with PC `AsIs`
3. verify whether Codex compact depends on a specific HTTP/2 or reconnect pattern that survives TUN but not SOCKS-injected routing
