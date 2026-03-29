# Сопоставление профиля для XKeen

Эта заметка показывает, как текущий рабочий ручной профиль роутера переносится в файлы, которые ожидает `XKeen`.

## Исходный профиль

Текущий источник ручного профиля:

- [prompt.md](/e:/Домашние проекты/VPN на роутере/docs/prompt.md)
- текущий файл на роутере: `/opt/etc/xray/<SOCKS_USERNAME>_config.json`

## Значения, которые нужно сохранить

- сервер: `<VLESS_SERVER_HOST>`;
- порт: `<VLESS_SERVER_PORT>`;
- протокол: `VLESS`;
- транспорт: `TCP`;
- защита: `Reality`;
- UUID: `<VLESS_UUID>`;
- flow: `xtls-rprx-vision`;
- public key: `<REALITY_PUBLIC_KEY>`;
- SNI/serverName: `<REALITY_SERVER_NAME>`;
- shortId: `<REALITY_SHORT_ID>`;
- fingerprint: `random`.

## Черновые файлы XKeen

- черновик outbound:
  - [04_outbounds.vdpsina-reality-draft.json](/e:/Домашние проекты/VPN на роутере/configs/xkeen/04_outbounds.vdpsina-reality-draft.json)
- черновик routing:
  - [05_routing.hydraroute-draft.json](/e:/Домашние проекты/VPN на роутере/configs/xkeen/05_routing.hydraroute-draft.json)

## Ключевые замечания

- Стоковый шаблон `XKeen` использует `fingerprint: chrome`; в этом draft он заменен на `random`, чтобы быть ближе к реально рабочему outbound-профилю ПК и роутера.
- Стоковый outbound-шаблон `XKeen` по умолчанию использует порт `443`; в этом draft подставлен настоящий порт сервера `<VLESS_SERVER_PORT>`.
- Direct-исключения для:
  - `stalcraft.net`;
  - `exbo.net`;
  - `cdn77.org`
  сохранены в routing draft.

## Замысел миграции

Когда начнется окно миграции, соответствующие шаблонные файлы `XKeen` нужно заменить draft-версиями из этого репозитория, прежде чем `xkeen -i` начнет использоваться как активный путь.
