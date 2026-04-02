# Карта проекта

## Главное

Проект сейчас держится на трех частях:

- `AntiGoblin` UI
- `Keenetic policy xkeen`
- `XKeen/xray`

## Ключевые каталоги

- `ui/xkeen-manager/`
  Фронт, стили, логика UI и router backend.

- `ui/xkeen-manager/backend/`
  Живой runtime backend:
  - `routing.cgi`
  - `xkeen-selfheal.sh`

- `scripts/xkeen/`
  Раскатка UI/backend на роутер и служебные скрипты проекта.

- `configs/xkeen/`
  Локальные шаблоны, снапшоты и sample state.

- `docs/`
  Актуальная документация.

- `docs/troubleshooting.md`
  Короткая памятка по уже найденным проблемам и решениям.
  Там же зафиксирован временный инструмент отладки через `xray access log`.

## Что живет на роутере

- UI:
  - `/opt/share/xkeen-manager/`
- state:
  - `/opt/share/xkeen-manager/xkeen-ui-state.json`
- API:
  - `/opt/share/xkeen-manager/api/routing.cgi`
  - `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`
- xray:
  - `/opt/etc/xray/configs/04_outbounds.json`
  - `/opt/etc/xray/configs/05_routing.json`

## Как думать про схему

`AntiGoblin`:

- хранит профили и группы;
- генерирует `outbounds` и `routing`.

`Keenetic policy xkeen`:

- выбирает устройства;
- ставит mark `0xffffaaa`.

`iptables/xkeen`:

- пропускает локалку и discovery в `RETURN`;
- отправляет весь остальной `TCP` в `xray`.

`xray`:

- получает весь `TCP` устройств из `xkeen`;
- внутри себя уже решает `vless-reality` или `direct`.

`UDP`:

- сейчас идет напрямую;
- `xkeen_udp` и `xkeen_quic` отключены.
