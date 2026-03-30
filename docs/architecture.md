# Архитектура системы: Keenetic + Entware + HydraRoute + XKeen/xray

## Аппаратная база

- роутер: Keenetic Giga;
- CPU: `aarch64`;
- ОС: KeeneticOS / NDM;
- SSH: `root@192.168.2.1:22`;
- SSH-пароль: `<ROUTER_SSH_PASSWORD>`.

## Текущее боевое состояние

Рабочая боевая схема сейчас гибридная:

- `HydraRoute` сохранен как слой выбора и удобный UI;
- `XKeen` дает рабочий прозрачный redirect-путь;
- старый путь `Proxy0 -> hev-socks5-tunnel -> xray:1300` больше не используется для проблемного трафика.

Это главный итог отладочной и миграционной сессии от `2026-03-29`.

## Текущий поток трафика

### Слой выбора

`HydraRoute` по-прежнему делает следующее:

- наблюдает DNS-ответы через `NFLOG`;
- сопоставляет домены со своим списком;
- добавляет разрешенные IP в `ipset HydraRoute`;
- маркирует подходящий трафик через существующий `connmark 0xffffaab`.

### Транспортный слой

Помеченный трафик теперь перенаправляется в `XKeen`:

```text
LAN-клиент
  -> HydraRoute видит DNS-ответ
  -> IP назначения попадает в ipset HydraRoute
  -> iptables mangle помечает совпавший трафик connmark 0xffffaab
  -> iptables nat PREROUTING отправляет помеченный TCP-трафик в цепочку xkeen
  -> xkeen делает REDIRECT в локальный xray на порт 61219
  -> xray inbound "redirect"
  -> routing rules
  -> VLESS Reality outbound или direct
```

Для сервисов, которым нужен не только TCP, но и UDP-путь, гибрид позже был расширен:

```text
HydraRoute -> connmark 0xffffaab
  -> TCP: nat xkeen -> REDIRECT 61219 -> xray inbound "redirect"
  -> UDP: mangle xkeen_udp -> TPROXY 61220 -> xray inbound "tproxy"
  -> xray routing -> VLESS Reality или direct
```

### Важное следствие

Система сейчас гибридная:

- `HydraRoute` решает, что должно попасть в специальный путь;
- `XKeen/xray` решает, как именно этот трафик реально проксировать.

Это значит, что логика сейчас двухслойная:

- `HydraRoute` отвечает за селекцию трафика через `domain.conf`, `ip.list`, `ipset HydraRoute` и `connmark 0xffffaab`;
- `XKeen/xray` отвечает за финальное routing-решение уже внутри `xray`.

Из этого следует важное практическое правило:

- добавить домен или CIDR только в `HydraRoute` иногда недостаточно;
- если сервис приходит в `xray` как IP-only трафик без sniffable домена, соответствующий CIDR нужно продублировать еще и в `xray routing`.

## Объекты и пути на роутере

### Старый путь все еще присутствует в системе

- `Proxy0`;
- `hev-socks5-tunnel`;
- старый каталог ручных `xray`-конфигов `/opt/etc/xray`;
- старый ручной SOCKS-listener на порту `1300`.

Именно этот путь был исходной схемой и источником проблемы с `compact`.

### Текущий путь через XKeen

- в UI роутера существует policy `xkeen`;
- текущий `XKeen`-`xray` слушает порт `61219`;
- активны NAT-правила:
  - `PREROUTING ... connmark 0xffffaab -> xkeen`;
  - `xkeen -> REDIRECT --to-ports 61219`.

### Текущие пути к конфигам

- старые ручные конфиги:
  - `/opt/etc/xray/<SOCKS_USERNAME>_config.json`;
  - `/opt/etc/xray/routing_config.json`.
- текущие конфиги XKeen:
  - `/opt/etc/xray/configs/01_log.json`;
  - `/opt/etc/xray/configs/02_transport.json`;
  - `/opt/etc/xray/configs/03_inbounds.json`;
  - `/opt/etc/xray/configs/04_outbounds.json`;
  - `/opt/etc/xray/configs/05_routing.json`;
  - `/opt/etc/xray/configs/06_policy.json`.
- подготовленные пользовательские drafts:
  - `/opt/var/xkeen-drafts/04_outbounds.json`;
  - `/opt/var/xkeen-drafts/05_routing.json`.

## Подтвержденная причина падения Codex Compact

Изначально ломавшийся путь был таким:

```text
HydraRoute -> Proxy0 -> hev-socks5-tunnel -> xray SOCKS :1300 -> VLESS
```

Сильные подтверждения, собранные во время live-диагностики:

- `xray` сам по себе не падал;
- обычный долгоживущий HTTPS через VPN работал;
- тот же VLESS-сервер работал через `v2rayN` на ПК;
- локальный процесс, который кормил `xray:1300`, был `hev-socks5-tunnel`;
- состояния сокетов показывали, что именно эта сторона часто начинала закрытие;
- в runtime-конфиге были параметры:

```yaml
misc:
  connect-timeout: 7000
  read-write-timeout: 20000
```

Из этого следовало, что главным подозреваемым был именно `hev-socks5-tunnel` и встроенный proxy-delivery слой Keenetic.

## Подтвержденный фикс для Codex Compact

`Codex compact` заработал только после того, как помеченный трафик был выведен из встроенного proxy-client пути и направлен в `XKeen`.

Новая рабочая схема:

```text
HydraRoute -> connmark 0xffffaab -> XKeen/xray -> VLESS
```

Это подтверждает:

- сервер не был корневой причиной;
- общая конфигурация `xray/VLESS` не была корневой причиной;
- проблемным слоем был старый proxy-client путь Keenetic, а не целевой сервис.

## Важные локальные фиксы, примененные при запуске XKeen

### 1. Обработка интерактивного установщика

`xkeen -i` по умолчанию интерактивный.

Для минимальной установки в этой миграции использовались ответы:

- `GeoIP`: `0`;
- `GeoSite`: `0`;
- `Auto updates / cron`: `0`.

### 2. Исправление совместимости transport-шаблона

Стоковый `XKeen`-файл `02_transport.json` использовал устаревший глобальный `transport`, который `Xray 26.2.6` больше не принимает.

Наблюдавшаяся ошибка запуска:

- `The feature Global transport config has been removed ...`

Текущий локальный фикс:

- файл `/opt/etc/xray/configs/02_transport.json` заменен на:

```json
{}
```

### 3. Исправление сгенерированного init-скрипта

Сгенерированный `/opt/etc/init.d/S24xray` на этом роутере оказался сломан:

- отсутствовал `name_client="xray"`;
- использовался `busybox ps`, хотя на этом роутере нужен обычный `ps`.

Примененный локальный фикс:

- добавлен `name_client="xray"`;
- `busybox ps` заменен на обычный `ps`.

Без этого `XKeen` искал конфиги в `/opt/etc//configs` и не мог стартовать корректно.

## Текущее поведение runtime XKeen

После успешного запуска наблюдалось:

- активный `xray run` без `-confdir /opt/etc/xray`;
- listener на `61219`;
- растущие NAT-счетчики в цепочке `xkeen`;
- соединения от `192.168.2.106` к локальному `61219`.

Это подтвердило, что тестовый ПК действительно пошел по новому пути.

## Текущая роль HydraRoute

`HydraRoute` специально оставлен, потому что:

- дает удобный UI для выбора доменов;
- по-прежнему управляет списком доменов и подачей IP в `ipset`;
- его удаление сейчас снизило бы удобство без немедленной выгоды.

Поэтому текущий дизайн такой:

- оставить `HydraRoute` для управления доменами и UI;
- оставить `XKeen` для фактического data path.

## Telegram: отдельный вывод по гибридной схеме

После перехода на гибридный `HydraRoute + XKeen` выяснилось:

- Telegram работал через старый встроенный путь Keenetic;
- через текущий TCP-only `XKeen`-хук начал ломаться;
- при этом домены Telegram и его CIDR в `HydraRoute` применялись корректно.

Проверка показала:

- `HydraRoute` успешно матчила `t.me` и `telegram.org`;
- Telegram-сети присутствовали в `ipset HydraRoute`;
- трафик клиента реально попадал в `xkeen` и доходил до `xray`;
- но часть Telegram-трафика была IP-only и приходила в `xray` без sniffable домена;
- из-за финального правила `outboundTag: direct` такой трафик внутри `xray` уходил напрямую, а не в `vless-reality`.

Фикс:

- в `05_routing.json` добавлено отдельное IP-правило для Telegram CIDR:
  - `149.154.160.0/20`
  - `91.105.192.0/23`
  - `91.108.4.0/22`
  - `91.108.8.0/22`
  - `91.108.12.0/22`
  - `91.108.16.0/22`
  - `91.108.20.0/22`
  - `91.108.56.0/22`
  - `95.161.64.0/20`

Вывод:

- проблема Telegram была не в `HydraRoute`;
- проблема была не в отсутствии Telegram CIDR на входе;
- проблема была в том, что `xray routing` не знал, что делать с Telegram IP-only трафиком после попадания в `XKeen`.

## GitHub Copilot: отдельный вывод по гибридной схеме

После починки `Codex compact` выяснилось, что `GitHub Copilot` в selective-режиме все еще не работает, хотя при полном туннеле для всего устройства токен выдавался корректно.

Диагностика показала:

- `_ping`-проверки `api.github.com`, `api.githubcopilot.com` и `copilot-proxy.githubusercontent.com` отвечали `HTTP 200`;
- `HydraRoute` корректно матчила основные GitHub/Copilot/Microsoft-домены;
- наблюдаемые Copilot IP действительно присутствовали в `ipset HydraRoute`;
- такие TCP-сессии реально получали `connmark 0xffffaab` и уходили в `xkeen -> 61219`;
- при этом сервер Copilot все равно отвечал `403 NotAuthorized / not available in your location`.

Практический вывод:

- проблема была не только в селекции на уровне `HydraRoute`;
- проблема была в том, что `xray routing` не содержал отдельного блока правил для Copilot/GitHub/Microsoft/Azure service-chain;
- часть трафика после попадания в `xray` могла уходить в финальный `direct`, несмотря на то, что `HydraRoute` уже выбрала этот поток как VPN-трафик.

Фикс:

- в `05_routing.json` добавлены Copilot/GitHub/Microsoft/Azure домены:
  - `github.com`
  - `github.dev`
  - `githubapp.com`
  - `githubassets.com`
  - `githubcopilot.com`
  - `githubstatus.com`
  - `githubusercontent.com`
  - `appcenter.ms`
  - `azure.com`
  - `azureedge.net`
  - `azurefd.net`
  - `azurewebsites.net`
  - `bing.com`
  - `services.bingapis.com`
  - `dual-a-0001.a-msedge.net`
  - `exp-tas.com`
  - `live.com`
  - `microsoft.com`
  - `microsoftapp.net`
  - `trafficmanager.net`
  - `visualstudio.com`
  - `vscode.dev`
  - `windows.net`
- в `05_routing.json` добавлены связанные CIDR:
  - `4.225.11.0/24`
  - `8.6.112.0/21`
  - `8.47.69.0/24`
  - `13.69.239.0/24`
  - `13.89.179.0/24`
  - `13.107.5.0/24`
  - `13.107.253.0/24`
  - `20.42.72.0/24`
  - `20.50.88.0/24`
  - `20.199.39.0/24`
  - `20.250.119.0/24`
  - `34.160.81.0/24`
  - `104.208.16.0/24`
  - `140.82.112.0/20`
  - `172.64.155.0/24`

Итог:

- `GitHub Copilot` начал работать в selective-сценарии;
- корневая причина оказалась той же природы, что и у Telegram:
  `HydraRoute` выбирала трафик правильно, но без отдельного Copilot-блока в `xray routing` этого было недостаточно.

## Замечания по изменению политики

Если домен удален из UI/списка `HydraRoute`:

- короткое время может казаться, что он все еще идет по специальному пути, если клиент или браузер держит старые соединения;
- но свежие проверки показали:
  - домен исчезает из `domain.conf`;
  - соответствующие записи отсутствуют в `ipset HydraRoute`;
  - после обновления кэша и соединений трафик следует уже новой политике.

## Сводка текущего состояния

Что сейчас уже верно:

- `Codex compact` работает;
- direct-фикс для `Stalcraft` остается в силе;
- UI `HydraRoute` остается доступным;
- `XKeen` является фактическим транспортом для помеченного трафика.

Что важно помнить:

- текущий успех зависит от локальных фиксов runtime-файлов `XKeen`;
- будущий `xkeen -i` или регенерация шаблонов могут перезаписать:
  - `/opt/etc/init.d/S24xray`;
  - `/opt/etc/xray/configs/02_transport.json`.

## Полезные проверки

```bash
# счетчики активного xkeen redirect
iptables -t nat -L xkeen -n -v

# подтверждение локального xray listener
netstat -tlnp | grep 61219

# подтверждение policy-объектов
curl -kfsS localhost:79/rci/show/ip/policy

# логи HydraRoute
tail -f /opt/var/log/LOGhrneo.log

# текущие конфиги XKeen
ls -la /opt/etc/xray/configs
```
