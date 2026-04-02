# Handoff Prompt

Используй этот файл как короткий handoff для следующей сессии.

## Текущее состояние

- роутер: Keenetic
- Entware смонтирован в `/opt`
- UI: `AntiGoblin` на `http://192.168.2.1:8899/`
- source of truth:
  - `/opt/share/xkeen-manager/xkeen-ui-state.json`
- xray:
  - `/opt/etc/xray/configs/04_outbounds.json`
  - `/opt/etc/xray/configs/05_routing.json`

## Важные факты

- `HydraRoute` удален с роутера полностью
- нативная политика Keenetic `xkeen` использует mark:
  - `0xffffaaa`
- `xkeen` сейчас работает как:
  - локалка/discovery -> `RETURN`
  - весь остальной `TCP` -> `REDIRECT 61219`
- `UDP` сейчас идет напрямую
- `xkeen_udp` отключен
- `xkeen_quic` отключен

## Что не ломать

- не восстанавливать `HydraRoute` и `0xffffaab`
- не включать обратно `xkeen_quic`
- не включать обратно `xkeen_udp` без явного теста и причины

## Где смотреть runtime

- `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`
- `/opt/share/xkeen-manager/api/routing.cgi`
- `iptables -t nat -S xkeen`
- `iptables -t nat -S PREROUTING | grep xkeen`
- `iptables -t mangle -S PREROUTING | grep xkeen`

## Ментальная модель

- UI управляет профилями и группами
- Keenetic policy выбирает устройства
- `iptables` отправляет весь `TCP` группы `xkeen` в `xray`
- `xray` уже внутри решает `vless-reality` или `direct`
