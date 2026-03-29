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

### Важное следствие

Система сейчас гибридная:

- `HydraRoute` решает, что должно попасть в специальный путь;
- `XKeen/xray` решает, как именно этот трафик реально проксировать.

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
HydraRoute -> connmark 0xffffaab -> XKeen REDIRECT 61219 -> xray -> VLESS
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
