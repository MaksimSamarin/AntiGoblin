# Проект VPN на роутере

Этот репозиторий собран как база знаний и набор рабочих артефактов по схеме `Keenetic + Entware + HydraRoute + XKeen/xray`.

Основные точки входа:

- [project-map.md](/e:/Домашние проекты/VPN на роутере/docs/project-map.md) — карта проекта и текущее состояние.
- [architecture.md](/e:/Домашние проекты/VPN на роутере/docs/architecture.md) — основной технический документ.
- [prompt.md](/e:/Домашние проекты/VPN на роутере/docs/prompt.md) — короткий handoff для новой сессии.

## Структура

- `docs/`
- `docs/analysis/`
- `docs/runbooks/`
- `configs/sing-box/`
- `configs/xkeen/`
- `scripts/router/`
- `scripts/xkeen/`
- `snapshots/router-configs/`

## Текущий фокус

- расследование причин сбоев `Codex compact` в схеме маршрутизации Keenetic;
- фиксация рабочего гибридного решения `HydraRoute + XKeen`;
- сохранение runbook-ов, конфигов и утилит для повторного развертывания и отката.

## Полезные точки входа

- [codex-compact-debug-checklist.md](/e:/Домашние проекты/VPN на роутере/docs/runbooks/codex-compact-debug-checklist.md)
- [xkeen-migration-plan.md](/e:/Домашние проекты/VPN на роутере/docs/runbooks/xkeen-migration-plan.md)
- [xkeen-cutover-checklist.md](/e:/Домашние проекты/VPN на роутере/docs/runbooks/xkeen-cutover-checklist.md)
- [v2rayn-vs-router-xray.md](/e:/Домашние проекты/VPN на роутере/docs/analysis/v2rayn-vs-router-xray.md)
- [xkeen-profile-mapping.md](/e:/Домашние проекты/VPN на роутере/docs/analysis/xkeen-profile-mapping.md)
- [xkeen_backup_state.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_backup_state.ps1)
- [xkeen_probe_layout.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_probe_layout.ps1)
- [xkeen_preflight.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_preflight.ps1)
- [xkeen_stage_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_stage_drafts.ps1)
- [xkeen_apply_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_apply_drafts.ps1)

## Требования к скриптам

- Перед запуском PowerShell-скриптов нужно экспортировать `ROUTER_SSH_PASSWORD`.
- `snapshots/`, `.claude/` и backup-архивы специально исключены из git.
