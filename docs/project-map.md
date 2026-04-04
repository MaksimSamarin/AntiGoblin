# Карта проекта

## Главные части

Проект сейчас состоит из трех практических частей:

- UI `AntiGoblin`
- router backend и self-heal
- deploy и обслуживающие скрипты для `Keenetic + Entware`

## Карта каталогов

### `ui/xkeen-manager/`

Фронтенд router-hosted UI:

- `index.html`
- `app.js`
- `styles.css`
- logo assets

### `ui/xkeen-manager/backend/`

Router backend и поддержка runtime:

- `routing.cgi`  
  API для UI, сохранение state, apply, probe, restart
- `xkeen-selfheal.sh`  
  Восстановление runtime и очистка старых хвостов

### `scripts/xkeen/`

Deploy и операционные скрипты:

- `deploy_xkeen_manager_stack_to_router.ps1`
- `bootstrap_antigoblin_router.ps1`
- `deploy_xkeen_manager_ui_to_router.ps1`
- `deploy_xkeen_manager_backend_to_router.ps1`
- `antigoblin.initd.sh`
- `antigoblin-remount-hook.sh`
- `start_xkeen_manager_ui_router.ps1`
- `stop_xkeen_manager_ui_router.ps1`
- `xkeen_backup_state.ps1`
- `xkeen_rollback_notes.md`

### `configs/xkeen/`

Только generic sample-конфиги:

- `xkeen-ui-state.sample.json`
- `01_log.sample.json`
- `03_inbounds.sample.json`
- `04_outbounds.sample.json`
- `05_routing.sample.json`

В этой папке не должно быть live-снапшотов роутера и личных черновиков.

### `docs/`

Актуальная документация:

- [architecture.md](architecture.md)
- [project-map.md](project-map.md)
- [PROMPT.md](PROMPT.md)
- [troubleshooting.md](troubleshooting.md)
- [runbooks/xkeen-manager-ui.md](runbooks/xkeen-manager-ui.md)
- [runbooks/deploy-from-zero.md](runbooks/deploy-from-zero.md)

## Runtime-файлы на роутере

UI и state:

- `/opt/share/xkeen-manager/`
- `/opt/share/xkeen-manager/xkeen-ui-state.json`

Backend:

- `/opt/share/xkeen-manager/api/routing.cgi`
- `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`

Runtime bypass больше не хранится отдельными текстовыми файлами.
`xkeen_bypass` собирается из активных групп UI с типом `Bypass`.

Конфиги `xray`:

- `/opt/etc/xray/configs/01_log.json`
- `/opt/etc/xray/configs/03_inbounds.json`
- `/opt/etc/xray/configs/04_outbounds.json`
- `/opt/etc/xray/configs/05_routing.json`

## Правила на будущее

- В `configs/xkeen/` должны лежать только generic sample-файлы.
- Live-дампы роутера нужно держать вне продуктовой части.
- После каждого подтвержденного бага и решения нужно обновлять `docs/troubleshooting.md`.
- После изменения архитектуры нужно обновлять `README.md`, `docs/architecture.md` и `docs/PROMPT.md`.
