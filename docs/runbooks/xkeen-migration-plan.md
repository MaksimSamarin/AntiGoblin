# XKeen Migration Plan

## Goal

Replace the current `HydraRoute + Proxy0 + manual xray` selective path with an `Xkeen`-managed path, but do it in a controlled way with rollback ready.

## Preconditions

- `xkeen` utility is installed at `/opt/sbin/xkeen`
- current manual router path is still active
- no `xkeen -i` migration has been run yet

## Stage 1: Backup

Run:

- [xkeen_backup_state.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_backup_state.ps1)

Expected output:

- backup tarball saved under `snapshots/xkeen-migration/<timestamp>/`

## Stage 2: Inspect current XKeen layout

Run:

- [xkeen_probe_layout.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_probe_layout.ps1)
- [xkeen_preflight.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_preflight.ps1)

Purpose:

- confirm current xray layout
- confirm no `xkeen` policy is already active
- review what `xkeen` expects to manage
- confirm required kernel and `iptables` features before cutover

## Stage 3: Controlled migration window

Only during a planned test window:

1. stop the manual xray path
2. temporarily disable HydraRoute influence on routing
3. run [xkeen_stage_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_stage_drafts.ps1)
4. run `xkeen -i`
5. inspect generated:
   - `/opt/etc/xray/configs`
   - `/opt/etc/init.d/S24xray`
   - `rci/show/ip/policy`
6. run [xkeen_apply_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_apply_drafts.ps1)
7. start XKeen-managed xray
8. attach only one test client/device to `xkeen` policy

## Stage 4: First validation

Validate in this order:

1. ordinary HTTPS browsing
2. long-lived HTTPS test
3. `Codex compact`

Do not add complex selective domain routing until full-device routing for one client is stable.

## Stage 5: Rollback

If migration fails:

- use [xkeen-cutover-checklist.md](/e:/Домашние проекты/VPN на роутере/docs/runbooks/xkeen-cutover-checklist.md) as the migration-window sequence
- use [xkeen_rollback_notes.md](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_rollback_notes.md)
- restore `/opt/etc/xray`
- restore original service/start method
- return device to old routing path
