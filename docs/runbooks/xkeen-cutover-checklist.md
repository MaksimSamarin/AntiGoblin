# XKeen Cutover Checklist

Use this only during a planned migration window.

## Goal

Switch from the current `HydraRoute + Proxy0 + manual xray` path to an `Xkeen`-managed path in a controlled and reversible way.

## Prepared Assets

- backup: [xkeen_backup_state.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_backup_state.ps1)
- preflight: [xkeen_preflight.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_preflight.ps1)
- stage drafts: [xkeen_stage_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_stage_drafts.ps1)
- apply drafts: [xkeen_apply_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_apply_drafts.ps1)
- rollback notes: [xkeen_rollback_notes.md](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_rollback_notes.md)

## Sequence

1. Run [xkeen_backup_state.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_backup_state.ps1).
2. Run [xkeen_preflight.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_preflight.ps1).
3. Run [xkeen_stage_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_stage_drafts.ps1).
4. Stop the current manual `xray` path and pause HydraRoute influence.
5. Run `xkeen -i` on the router.
6. Confirm `/opt/etc/xray/configs` now exists and `xkeen` policy was created.
7. Run [xkeen_apply_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_apply_drafts.ps1).
8. Start the `Xkeen`-managed service.
9. Attach only the test client `192.168.2.106` to `xkeen` policy.
10. Validate:
    - ordinary HTTPS
    - long-lived HTTPS
    - `Codex compact`

## Success Criteria

- the test client has working internet through `Xkeen`
- `Codex compact` no longer disconnects
- the rest of the router remains unaffected

## Rollback Trigger

Rollback immediately if:

- the test client loses general internet access
- `xray/Xkeen` service does not stay up
- router policy routing behaves unexpectedly
- `Codex compact` still fails and the new path is not otherwise cleaner

## Actual Notes From Successful Migration

The 2026-03-29 migration did eventually succeed, but with important platform-specific fixes:

- `xkeen -i` is interactive and must be answered
  - GeoIP: `0`
  - GeoSite: `0`
  - automatic updates: `0`
- `XKeen` expected the router UI policy `xkeen` to exist; it did not create that policy automatically
- generated `/opt/etc/init.d/S24xray` needed manual repair:
  - add `name_client="xray"`
  - replace `busybox ps` with plain `ps`
- stock `/opt/etc/xray/configs/02_transport.json` was incompatible with current `Xray 26.2.6`
  - current working fix is `{}` in that file

## Current Result

After those fixes:

- `XKeen` xray runs on `61219`
- `HydraRoute` continues to supply selection/marking
- marked traffic is redirected by chain `xkeen`
- `Codex compact` works on the new path
