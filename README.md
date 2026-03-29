# VPN Router Project

This repository is now organized into a few clear areas:

- [docs/project-map.md](/e:/Домашние проекты/VPN на роутере/docs/project-map.md): project index and current status
- [docs/architecture.md](/e:/Домашние проекты/VPN на роутере/docs/architecture.md): canonical technical source of truth
- [docs/prompt.md](/e:/Домашние проекты/VPN на роутере/docs/prompt.md): compact handoff for new sessions

## Structure

- `docs/`
- `docs/analysis/`
- `docs/runbooks/`
- `configs/sing-box/`
- `configs/xkeen/`
- `scripts/router/`
- `scripts/xkeen/`
- `snapshots/router-configs/`

## Current focus

- root cause investigation of `Codex compact` failures through Keenetic proxy routing
- evaluation of alternatives to `Proxy0 -> hev-socks5-tunnel`
- staged migration research toward `Xkeen`

## Useful entry points

- [docs/runbooks/codex-compact-debug-checklist.md](/e:/Домашние проекты/VPN на роутере/docs/runbooks/codex-compact-debug-checklist.md)
- [docs/runbooks/xkeen-migration-plan.md](/e:/Домашние проекты/VPN на роутере/docs/runbooks/xkeen-migration-plan.md)
- [docs/runbooks/xkeen-cutover-checklist.md](/e:/Домашние проекты/VPN на роутере/docs/runbooks/xkeen-cutover-checklist.md)
- [docs/analysis/v2rayn-vs-router-xray.md](/e:/Домашние проекты/VPN на роутере/docs/analysis/v2rayn-vs-router-xray.md)
- [docs/analysis/xkeen-profile-mapping.md](/e:/Домашние проекты/VPN на роутере/docs/analysis/xkeen-profile-mapping.md)
- [scripts/xkeen/xkeen_backup_state.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_backup_state.ps1)
- [scripts/xkeen/xkeen_probe_layout.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_probe_layout.ps1)
- [scripts/xkeen/xkeen_preflight.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_preflight.ps1)
- [scripts/xkeen/xkeen_stage_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_stage_drafts.ps1)
- [scripts/xkeen/xkeen_apply_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_apply_drafts.ps1)

## Script prerequisites

- Export `ROUTER_SSH_PASSWORD` before running PowerShell automation scripts.
- `snapshots/`, `.claude/`, and backup archives are intentionally excluded from git.
