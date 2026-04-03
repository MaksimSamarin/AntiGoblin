# Архитектура

## Общее устройство

`AntiGoblin` — это управляющий слой над `Keenetic + Entware + XKeen/xray`.

Стек делится на три уровня:

1. `KeeneticOS`  
   Выбирает устройства через штатную политику доступа в интернет `xkeen`.
2. `iptables`  
   Перехватывает `TCP` трафик этой политики и отправляет его в `xray`.
3. `xray`  
   Применяет routing-правила и отправляет поток либо в `vless-reality`, либо в `direct`.

## Keenetic и Entware

### Что делает KeeneticOS

Сама Keenetic отвечает за:

- политики доступа в интернет
- назначение устройств в политику `xkeen`
- веб-сессию и авторизацию в веб-интерфейсе
- базовый сетевой стек роутера

### Что делает Entware

Весь проект живет в `/opt`, то есть в среде `Entware`.

Там находятся:

- `xray`
- `uhttpd`
- файлы UI
- backend-скрипты
- self-heal
- runtime-файлы и сгенерированные конфиги

Если ломается `/opt`, носитель или сама среда `Entware`, то VPN-стек может выглядеть полностью упавшим, даже если KeeneticOS жива.

## Что живет на роутере

UI и state:

- `/opt/share/xkeen-manager/`
- `/opt/share/xkeen-manager/xkeen-ui-state.json`

Backend:

- `/opt/share/xkeen-manager/api/routing.cgi`
- `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`

Runtime bypass-файлы:

- `/opt/share/xkeen-manager/runtime/bypass-domains.txt`
- `/opt/share/xkeen-manager/runtime/bypass-cidrs.txt`

Конфиги `xray`:

- `/opt/etc/xray/configs/01_log.json`
- `/opt/etc/xray/configs/03_inbounds.json`
- `/opt/etc/xray/configs/04_outbounds.json`
- `/opt/etc/xray/configs/05_routing.json`

## Источник истины

Единственный источник истины для UI:

- `/opt/share/xkeen-manager/xkeen-ui-state.json`

Из этого файла backend собирает:

- `04_outbounds.json`
- `05_routing.json`

Старые routing-снапшоты и разовые дампы роутера не считаются источником истины.

## Как идет трафик

### Выбор устройств

Устройства, назначенные в политику Keenetic `xkeen`, получают mark:

- `0xffffaaa`

### Уровень `iptables`

Трафик с этим mark попадает в цепочку `xkeen`.

Текущая живая модель:

```text
RETURN локальные RFC1918 сети
RETURN multicast
RETURN broadcast
RETURN runtime bypass destinations
REDIRECT tcp -> 61219
RETURN
```

Смысл:

- локалка и discovery не трогаются
- явные bypass-адреса обходят `xray`
- весь остальной `TCP` устройств из `xkeen` идет в `xray`
- `UDP` не перехватывается и остается direct

## Как используется `xray`

`xray` работает как:

- прозрачный `TCP` ingress на `61219`
- routing engine
- outbound `vless-reality`
- outbound `direct`

После попадания потока в `xray` уже `05_routing.json` решает:

- отправить его в `vless-reality`
- или отправить его в `direct`

## Важное различие

`RETURN` и `direct` — это не одно и то же.

- `RETURN`
  Полностью обходит `xray`.
- `direct`
  Значит, что трафик уже вошел в `xray`, а потом был выпущен наружу без VPN.

Для локалки, discovery и части мобильных/IoT-облачных сценариев часто нужен именно `RETURN`, а не `direct`.

## Self-heal

`xkeen-selfheal.sh` отвечает за:

- проверку, что `xray` жив
- проверку, что `PREROUTING -> xkeen` на месте
- пересборку цепочки `xkeen`
- пересборку runtime bypass ipset
- очистку retired runtime-хвостов, например:
  - `xkeen_udp`
  - `xkeen_quic`

Cron запускает self-heal несколько раз в минуту.

## Что больше не является частью архитектуры

Эти вещи больше не входят в live-дизайн:

- `xkeen_udp`
- `xkeen_quic`
- live routing snapshots внутри продуктовой части репозитория
