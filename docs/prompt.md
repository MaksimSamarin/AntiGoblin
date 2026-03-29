# Промпт по VPN-схеме: Keenetic + HydraRoute + XKeen/xray

Используй этот документ как короткий handoff для новой сессии.
Канонический источник истины: `docs/architecture.md`.

## Текущее рабочее состояние

- роутер: Keenetic;
- ОС: KeeneticOS / NDM;
- Entware смонтирован в `/opt`;
- CPU: `aarch64`;
- SSH: `root@192.168.2.1:22`;
- SSH-пароль: `<ROUTER_SSH_PASSWORD>`.

## Финальный рабочий результат от 2026-03-29

`OpenAI Codex compact` теперь работает.

Рабочее решение гибридное:

- `HydraRoute` остается слоем выбора и UI;
- `XKeen` стал фактическим транспортным путем для помеченного трафика.

Это значит, что старый проблемный путь:

```text
HydraRoute -> Proxy0 -> hev-socks5-tunnel -> xray SOCKS :1300 -> VLESS
```

для выбранного трафика был заменен на:

```text
HydraRoute -> connmark 0xffffaab -> XKeen REDIRECT :61219 -> xray -> VLESS
```

## Что было доказано

- тот же VLESS-сервер работает на ПК через `v2rayN`;
- старый путь на роутере ломался именно на `compact`;
- обычный долгий HTTPS не был основной проблемой;
- сильнейшим подозреваемым по старому пути был `hev-socks5-tunnel` и его runtime-поведение;
- после перевода трафика в `XKeen` `compact` начал работать.

Практический вывод: корневая проблема была в старом proxy-client пути Keenetic, а не в удаленном сервере.

## Текущие роли

`HydraRoute` оставлен, потому что он удобен:

- управление списком доменов;
- UI;
- сопоставление DNS/ipset;
- выбор и маркировка трафика.

`XKeen` теперь делает следующее:

- локальную обработку redirect;
- runtime `xray` на порту `61219`;
- маршрутизацию в `VLESS Reality` или `direct`.

## Текущие важные файлы

Старые ручные файлы:

- `/opt/etc/xray/<SOCKS_USERNAME>_config.json`;
- `/opt/etc/xray/routing_config.json`.

Текущие файлы XKeen:

- `/opt/etc/xray/configs/01_log.json`;
- `/opt/etc/xray/configs/02_transport.json`;
- `/opt/etc/xray/configs/03_inbounds.json`;
- `/opt/etc/xray/configs/04_outbounds.json`;
- `/opt/etc/xray/configs/05_routing.json`;
- `/opt/etc/xray/configs/06_policy.json`;
- `/opt/etc/init.d/S24xray`.

Файлы HydraRoute:

- `/opt/etc/HydraRoute/domain.conf`;
- `/opt/etc/HydraRoute/hrneo.conf`;
- `/opt/var/log/LOGhrneo.log`.

## Важные локальные фиксы

Это не необязательные детали, а часть рабочего состояния.

### 1. Исправление init-скрипта, сгенерированного XKeen

Сгенерированный `/opt/etc/init.d/S24xray` на этом роутере был сломан.

Примененные локальные правки:

- добавлен `name_client="xray"`;
- `busybox ps` заменен на обычный `ps`.

Без этого сервис искал конфиги в `/opt/etc//configs` и падал.

### 2. Исправление совместимости transport-шаблона XKeen

Стоковый `02_transport.json` использовал устаревший глобальный `transport`, который `Xray 26.2.6` отвергает.

Текущий фикс:

```json
{}
```

в файле:

- `/opt/etc/xray/configs/02_transport.json`.

### 3. Установщик XKeen интерактивный

Во время установки использовались минимальные ответы:

- GeoIP: `0`;
- GeoSite: `0`;
- automatic updates / cron: `0`.

## Текущий outbound

Текущий outbound `XKeen` основан на том же рабочем сервере и профиле:

- сервер: `<VLESS_SERVER_HOST>`;
- порт: `<VLESS_SERVER_PORT>`;
- протокол: `VLESS`;
- транспорт: `TCP`;
- защита: `Reality`;
- flow: `xtls-rprx-vision`;
- fingerprint: `random`;
- SNI/serverName: `<REALITY_SERVER_NAME>`.

## Текущие эксплуатационные рекомендации

Не убирать `HydraRoute`, если нет сильной причины.

Текущий рекомендуемый production-подход:

- оставить `HydraRoute` для UI и выбора политики;
- оставить `XKeen` для фактического data path помеченного трафика.

Если после изменения списка `HydraRoute` маршрутизация выглядит устаревшей:

- проверить `domain.conf`;
- проверить `ipset HydraRoute`;
- учитывать кэш браузера и старые живые соединения, прежде чем считать политику сломанной.
