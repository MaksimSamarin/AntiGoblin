# Проект VPN на роутере

Репозиторий хранит текущую рабочую схему `Keenetic + Entware + XKeen/xray + AntiGoblin`.

Текущее состояние:

- `HydraRoute` удален с роутера полностью.
- `AntiGoblin` хранит профили, группы, `VLESS/Reality` и генерирует `04_outbounds.json` и `05_routing.json`.
- Нативная политика Keenetic `xkeen` помечает устройства mark `0xffffaaa`.
- Цепочка `xkeen` на роутере:
  - пропускает локалку и discovery через `RETURN`;
  - отправляет весь остальной `TCP` в `xray` через `REDIRECT 61219`.
- `UDP` сейчас идет напрямую мимо `xray`.

Источник истины:

- `/opt/share/xkeen-manager/xkeen-ui-state.json`

Главные каталоги:

- `ui/xkeen-manager/`
- `configs/xkeen/`
- `scripts/xkeen/`
- `docs/`

Точки входа:

- [project-map.md](/e:/Домашние проекты/VPN на роутере/docs/project-map.md)
- [architecture.md](/e:/Домашние проекты/VPN на роутере/docs/architecture.md)
- [prompt.md](/e:/Домашние проекты/VPN на роутере/docs/prompt.md)
