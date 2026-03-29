# System Architecture: Keenetic + Entware + HydraRoute + XKeen/xray

## Hardware

- Router: Keenetic Giga
- CPU: `aarch64`
- OS: KeeneticOS / NDM
- SSH: `root@192.168.2.1:22`
- SSH password: `<ROUTER_SSH_PASSWORD>`

## Current Production State

Current working production path is now a hybrid:

- `HydraRoute` is kept as the selector/UI layer
- `XKeen` provides the working transparent redirect path
- old `Proxy0 -> hev-socks5-tunnel -> xray:1300` path is no longer the path used for the problematic traffic

This is the key outcome of the 2026-03-29 migration/debug session.

## Current Traffic Flow

### Selector layer

`HydraRoute` still does:

- watches DNS replies through NFLOG
- matches domains from its list/UI
- adds resolved IPs into `ipset HydraRoute`
- marks matching traffic through existing `connmark 0xffffaab`

### Transport layer

Marked traffic is now redirected into `XKeen`:

```text
LAN client
  -> DNS answer observed by HydraRoute
  -> destination IP added to ipset HydraRoute
  -> iptables mangle marks matching traffic with connmark 0xffffaab
  -> iptables nat PREROUTING sends marked TCP traffic into chain xkeen
  -> xkeen REDIRECT to local xray on port 61219
  -> xray inbound "redirect"
  -> routing rules
  -> VLESS Reality outbound or direct
```

### Important consequence

The system is currently hybrid:

- `HydraRoute` chooses what should enter the special path
- `XKeen/xray` handles how that traffic is actually proxied

## Router Objects And Paths

### Legacy path still present in system

- `Proxy0`
- `hev-socks5-tunnel`
- old manual `xray` config directory `/opt/etc/xray`
- old manual SOCKS listener on port `1300`

These were the original path and the source of the `compact` problem.

### Current XKeen path

- `XKeen` policy exists in router UI as policy description `xkeen`
- current `XKeen` xray listens on port `61219`
- active NAT rule:
  - `PREROUTING ... connmark 0xffffaab -> xkeen`
  - `xkeen -> REDIRECT --to-ports 61219`

### Current config locations

- legacy manual configs:
  - `/opt/etc/xray/<SOCKS_USERNAME>_config.json`
  - `/opt/etc/xray/routing_config.json`
- current XKeen configs:
  - `/opt/etc/xray/configs/01_log.json`
  - `/opt/etc/xray/configs/02_transport.json`
  - `/opt/etc/xray/configs/03_inbounds.json`
  - `/opt/etc/xray/configs/04_outbounds.json`
  - `/opt/etc/xray/configs/05_routing.json`
  - `/opt/etc/xray/configs/06_policy.json`
- staged user drafts:
  - `/opt/var/xkeen-drafts/04_outbounds.json`
  - `/opt/var/xkeen-drafts/05_routing.json`

## Confirmed Root Cause Of Codex Compact Failure

The original failing path was:

```text
HydraRoute -> Proxy0 -> hev-socks5-tunnel -> xray SOCKS :1300 -> VLESS
```

Strong evidence collected during live debugging:

- `xray` itself did not crash
- generic long-lived HTTPS through VPN worked
- the same VLESS server worked through `v2rayN` on PC
- the local process feeding `xray:1300` was `hev-socks5-tunnel`
- socket states showed that this side often initiated closure
- runtime config contained:

```yaml
misc:
  connect-timeout: 7000
  read-write-timeout: 20000
```

This made `hev-socks5-tunnel` / built-in Keenetic proxy delivery the main suspect.

## Confirmed Fix For Codex Compact

`Codex compact` started working only after moving the marked traffic away from the built-in proxy-client delivery path and into `XKeen`.

Working path now:

```text
HydraRoute -> connmark 0xffffaab -> XKeen REDIRECT 61219 -> xray -> VLESS
```

This confirms:

- the server was not the root cause
- generic xray/VLESS config was not the root cause
- the problematic layer was the old Keenetic proxy-client path, not the destination service itself

## Important Local Fixes Applied During XKeen Bring-Up

### 1. Interactive installer handling

`xkeen -i` is interactive by default.

For minimal install during this migration the following answers were used:

- `GeoIP`: `0`
- `GeoSite`: `0`
- `Auto updates / cron`: `0`

### 2. Transport template compatibility fix

Stock `XKeen` `02_transport.json` used deprecated global `transport` config that `Xray 26.2.6` rejects.

Observed startup error:

- `The feature Global transport config has been removed ...`

Current local compatibility fix:

- `/opt/etc/xray/configs/02_transport.json` replaced with:

```json
{}
```

### 3. Generated init script fix

Generated `/opt/etc/init.d/S24xray` on this router was broken:

- missing `name_client="xray"`
- used `busybox ps`, but this router exposes `ps` separately and not as a busybox applet

Local fix applied:

- inserted `name_client="xray"`
- replaced `busybox ps` with plain `ps`

Without this, `XKeen` looked for configs under `/opt/etc//configs` and could not start correctly.

## Current XKeen Runtime Behavior

Observed after successful start:

- `xray run` active without `-confdir /opt/etc/xray`
- listener on `61219`
- active NAT counters on chain `xkeen`
- connections from `192.168.2.106` observed toward local `61219`

This confirmed that the test PC was actually traversing the new path.

## HydraRoute Current Role

HydraRoute is intentionally still kept because:

- it provides the convenient UI for domain selection
- it continues to manage the domain list and ipset feed
- removing it right now would reduce convenience without immediate benefit

So current design intent is:

- keep `HydraRoute` for domain/UI management
- keep `XKeen` for the actual working data path

## Notes About Policy Changes

If a domain is removed from HydraRoute UI/list:

- it may still appear to route through the special path briefly if a client/browser keeps old connections alive
- but fresh checks showed:
  - the domain disappears from `domain.conf`
  - corresponding entries are absent from `ipset HydraRoute`
  - after cache/connection refresh, routing follows the updated policy

## Current Status Summary

What is now true:

- `Codex compact` works
- `Stalcraft` direct-routing fix remains intact
- `HydraRoute` UI remains usable
- `XKeen` is the effective transport for marked traffic

What should be remembered:

- this success currently depends on local fixes to `XKeen` runtime files
- future `xkeen -i` or template regeneration may overwrite:
  - `/opt/etc/init.d/S24xray`
  - `/opt/etc/xray/configs/02_transport.json`

## Useful Checks

```bash
# active xkeen redirect counters
iptables -t nat -L xkeen -n -v

# confirm local xray listener
netstat -tlnp | grep 61219

# confirm policy objects
curl -kfsS localhost:79/rci/show/ip/policy

# check HydraRoute log
tail -f /opt/var/log/LOGhrneo.log

# inspect current XKeen configs
ls -la /opt/etc/xray/configs
```
