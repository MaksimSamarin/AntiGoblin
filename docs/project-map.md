# Карта проекта

Где что лежит в репозитории и что куда раскатывается на роутер.

## Корень

| Файл | Что это |
|------|---------|
| `install.sh` | On-router установщик одной командой. Скачивается через `wget` на роутере, разворачивает весь стек. |
| `README.md` | Главная страница проекта, quickstart. |
| `LICENSE` | MIT. |
| `.gitignore` | Игнор для `.env`, `snapshots/`, `archive/`, `tmp/`, `.claude/` и т.д. |

## `ui/xkeen-manager/`

Фронтенд router-hosted UI. Раскатывается в `/opt/share/xkeen-manager/`.

- `index.html`, `app.js`, `styles.css` — vanilla SPA, без сборки.
- `antigoblin-logo.png` — логотип.

### `ui/xkeen-manager/backend/`

Backend и runtime-сборка. Раскатывается в `/opt/share/xkeen-manager/api/`.

- `routing.cgi` — REST-API для UI: state, apply, health, logs, restart, stack-info.
- `xkeen-runtime.sh` — единая сборка `iptables`/`ipset`. Используется и apply, и self-heal — гарантия отсутствия дрейфа между ними.
- `xkeen-selfheal.sh` — авто-восстановление и health-проверки (`fd`, conntrack, mem, состояния сокетов к VPN).

## `scripts/xkeen/`

Серверные shell-скрипты (раскатываются на роутер) и dev-скрипты (запускаются с Windows для разработки).

### Раскатываются на роутер `install.sh`-ом

| Скрипт в репе | Куда едет на роутер | Что делает |
|---------------|---------------------|------------|
| `antigoblin.initd.sh` | `/opt/etc/init.d/S26antigoblin` | Поднимает UI на :8899 после reboot. |
| `antigoblin-singbox.initd.sh` | `/opt/etc/init.d/S24antigoblin-singbox` | Запускает `sing-box` для UDP TPROXY. |
| `antigoblin-selfheal.initd.sh` | `/opt/etc/init.d/S25antigoblin-selfheal` | Watchdog для self-heal-loop. |
| `antigoblin-sysctl.initd.sh` | `/opt/etc/init.d/S20antigoblin-sysctl` | Занижает TCP/conntrack таймауты для роутера. |
| `antigoblin-selfheal-loop.sh` | `/opt/share/xkeen-manager/api/xkeen-selfheal-loop.sh` | Daemon, гоняет `xkeen-selfheal.sh` каждые 15 секунд. |
| `antigoblin-selfheal.cron.sh` | `/opt/etc/cron.1min/50-antigoblin-selfheal` | Страховочный слой self-heal раз в минуту. |
| `antigoblin-remount-hook.sh` | `/opt/etc/ndm/fs.d/50-antigoblin.sh` и `/opt/etc/ndm/usb.d/50-antigoblin.sh` | Восстановление после возврата `/opt` и USB-событий. |

### Dev-скрипты (только локально на Windows)

Эти скрипты конечному пользователю не нужны — он ставит проект через `install.sh`. Их использует только разработчик для пуша изменений с локальной машины на тестовый роутер.

- `_load-env.ps1` — общий хелпер: подгружает `.env` из корня репозитория в process env.
- `bootstrap_antigoblin_router.ps1` — Windows-аналог `install.sh` для разработки.
- `deploy_xkeen_manager_stack_to_router.ps1` — UI + backend.
- `deploy_xkeen_manager_ui_to_router.ps1` — только UI.
- `deploy_xkeen_manager_backend_to_router.ps1` — только backend.
- `start_xkeen_manager_ui_router.ps1` / `stop_xkeen_manager_ui_router.ps1` — управление uhttpd_kn на роутере по SSH.
- `xkeen_backup_state.ps1` — снимок `/opt/etc/xray`, `iptables`, `ip rule` в `snapshots/` (gitignored).
- `router_ssh.py` — paramiko-обертка для SSH/SCP, используется PowerShell-скриптами.
- `xkeen_rollback_notes.md` — fast rollback path при аварии.

## `configs/xkeen/`

Generic sample-конфиги. `install.sh` копирует их в `/opt/etc/xray/configs/` и `/opt/etc/sing-box/`, **не перезаписывая** существующие (при чистой установке кладёт, при апгрейде сохраняет пользовательскую правку). Чтобы пересеять — `ANTIGOBLIN_FORCE=1 sh install.sh`.

| Файл | Куда едет |
|------|-----------|
| `01_log.sample.json` | `/opt/etc/xray/configs/01_log.json` |
| `02_relay.sample.json` | `/opt/etc/xray/configs/02_relay.json` (xray SS-relay для UDP) |
| `03_inbounds.sample.json` | `/opt/etc/xray/configs/03_inbounds.json` (TCP dokodemo-door) |
| `04_outbounds.sample.json` | `/opt/etc/xray/configs/04_outbounds.json` |
| `05_routing.sample.json` | `/opt/etc/xray/configs/05_routing.json` |
| `xkeen-ui-state.sample.json` | `/opt/share/xkeen-manager/xkeen-ui-state.json` (источник истины UI) |
| `sing-box-xkeen.sample.json` | `/opt/etc/sing-box/xkeen.json` (UDP TPROXY → SS-relay) |

В этой папке не должно быть live-снапшотов роутера и личных черновиков.

## `docs/`

- [architecture.md](architecture.md) — текущая архитектура.
- [project-map.md](project-map.md) — этот файл.
- [troubleshooting.md](troubleshooting.md) — типовые проблемы пользователя.
- [xkeen-manager-ui.md](xkeen-manager-ui.md) — как пользоваться UI.
- [screenshots/](screenshots/) — скриншоты UI для README.

Полная инструкция по установке — в [README.md](../README.md), там же подготовка Keenetic, флешки и Entware.

## Раскладка на роутере

UI и state:

- `/opt/share/xkeen-manager/` — UI-файлы и backend.
- `/opt/share/xkeen-manager/xkeen-ui-state.json` — единственный источник истины.
- `/opt/share/xkeen-manager/api/` — `routing.cgi`, `xkeen-runtime.sh`, `xkeen-selfheal.sh`, `xkeen-selfheal-loop.sh`.

Конфиги `xray`:

- `/opt/etc/xray/configs/01_log.json`
- `/opt/etc/xray/configs/02_relay.json`
- `/opt/etc/xray/configs/03_inbounds.json`
- `/opt/etc/xray/configs/04_outbounds.json` (генерируется backend-ом из state.json)
- `/opt/etc/xray/configs/05_routing.json` (генерируется backend-ом из state.json)

Конфиг `sing-box`:

- `/opt/etc/sing-box/xkeen.json`

Логи:

- `/opt/var/log/xkeen-selfheal.log`
- `/opt/var/log/xkeen-health.log`
- `/opt/var/log/xray/access.log` и `error.log`
- `/opt/var/log/sing-box-xkeen.log` (если включен debug)
- `/opt/var/log/xkeen-manager-uhttpd.log`

## Правила на будущее

- В `configs/xkeen/` — только generic sample-файлы, без личных хостов/паролей/UUID.
- Live-дампы роутера держим вне продуктовой части репозитория.
- После каждого подтверждённого бага и решения — обновлять [troubleshooting.md](troubleshooting.md).
- После изменения архитектуры — обновлять [README.md](../README.md), [architecture.md](architecture.md), этот файл.
