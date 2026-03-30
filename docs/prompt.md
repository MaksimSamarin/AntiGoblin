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

Важное уточнение:

- `HydraRoute` отвечает за селекцию трафика через `domain.conf`, `ip.list`, `ipset HydraRoute` и `connmark 0xffffaab`;
- `XKeen/xray` отвечает уже за финальное routing-решение внутри `xray`;
- поэтому для IP-only сервисов одного добавления домена или CIDR в `HydraRoute` может быть недостаточно: соответствующие сети иногда нужно дублировать еще и в `xray routing`.

Это значит, что старый проблемный путь:

```text
HydraRoute -> Proxy0 -> hev-socks5-tunnel -> xray SOCKS :1300 -> VLESS
```

для выбранного трафика был заменен на:

```text
HydraRoute -> connmark 0xffffaab -> XKeen/xray -> VLESS
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
- при включенном UDP-расширении еще и `tproxy` на `61220`;
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

Отдельный важный вывод по Telegram:

- Telegram корректно матчился в `HydraRoute` по доменам и CIDR;
- но в гибридной схеме ломался уже после попадания в `xray`;
- причина оказалась в том, что часть Telegram-трафика приходила в `xray` как IP-only и не совпадала с domain-rules;
- из-за этого такой трафик внутри `xray` падал в финальный `direct`;
- исправление: добавить Telegram CIDR в `05_routing.json` как отдельное `ip`-правило на `vless-reality`.

Отдельный важный вывод по GitHub Copilot:

- `HydraRoute` корректно матчила основные GitHub/Copilot/Microsoft-домены;
- `_ping`-диагностика Copilot отвечала успешно по `api.github.com`, `api.githubcopilot.com` и `copilot-proxy.githubusercontent.com`;
- но selective-режим все равно падал с `403 NotAuthorized / not available in your location`;
- причина оказалась той же природы, что и у Telegram: без отдельного Copilot/GitHub/Microsoft/Azure блока в `xray routing` часть service-chain внутри `xray` уходила в финальный `direct`.

Исправление:

- добавить Copilot/GitHub/Microsoft/Azure домены и накопленные CIDR в `05_routing.json` на `vless-reality`.

После этого `GitHub Copilot` начал работать в selective-сценарии.

Если после изменения списка `HydraRoute` маршрутизация выглядит устаревшей:

- проверить `domain.conf`;
- проверить `ipset HydraRoute`;
- учитывать кэш браузера и старые живые соединения, прежде чем считать политику сломанной.
# Новый Общий Вывод По CIDR

- точечное дублирование только Telegram/Copilot-сетей в `xray routing` оказалось рабочим, но плохо масштабируемым;
- текущее состояние схемы: весь список CIDR из `HydraRoute ip.list` зеркалируется в `xray` как общий `ip`-блок на `vless-reality`;
- это нужно помнить при следующей диагностике: если домен или сеть уже выбраны `HydraRoute`, но сервис внутри `xray` все равно ведет себя как direct, надо сначала проверить, попал ли его CIDR в общий `ip`-блок `05_routing.json`.
