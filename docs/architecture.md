# Архитектура

## Что это

`AntiGoblin` — управляющий слой над `Keenetic + Entware + xray + sing-box`. Это router-hosted панель управления: и UI, и backend, и self-heal живут на самом роутере в `/opt/share/xkeen-manager/`.

## Три уровня стека

```text
┌────────────────────────────────────────────────────────────┐
│ KeeneticOS                                                  │
│ - политика "xkeen" -> mark на устройства                    │
│ - web-сессия и авторизация                                  │
│ - базовый сетевой стек                                      │
└──────────────────────────┬─────────────────────────────────┘
                           │ mark = mark(xkeen policy)
┌──────────────────────────▼─────────────────────────────────┐
│ iptables                                                    │
│ - PREROUTING -> chain xkeen на mark политики                │
│ - локалка/discovery/multicast -> RETURN                     │
│ - адреса из ipset xkeen_bypass -> RETURN                    │
│ - остальной TCP -> REDIRECT 61219 (xray)                    │
│ - UDP к адресам из ipset xkeen_udp_route -> TPROXY 61221    │
└─────┬───────────────────────────────────┬──────────────────┘
      │ TCP                               │ UDP
┌─────▼──────────────────────┐  ┌─────────▼─────────────┐
│ xray (61219, 62640)         │  │ sing-box (61221)      │
│ - dokodemo-door TCP 61219   │  │ - tproxy UDP 61221    │
│ - shadowsocks relay 62640   │  │ - SS outbound to      │
│ - vless-reality outbound    │  │   127.0.0.1:62640     │
│ - direct outbound           │  │   (xray relay)        │
│                             │  └───────────┬───────────┘
│  routing.json решает         │              │
│   group → vless / direct    │◄─────────────┘
└──────────────┬──────────────┘
               │
        VLESS Reality сервер
```

## Что делает Keenetic, что делает Entware

**KeeneticOS** отвечает за политики доступа в интернет, привязку устройств к политике `xkeen`, веб-сессию роутера, базовый сетевой стек.

**Entware (`/opt`)** отвечает за всё остальное: `xray`, `sing-box`, `uhttpd_kn` (UI-сервер), backend на shell, init-скрипты, self-heal, runtime-файлы. Если флешка с Entware упала или `/opt` пропал — VPN-стек выглядит полностью мёртвым, даже если KeeneticOS жив.

## Как идёт трафик

### Mark и выбор устройств

Устройства, которым в Keenetic UI назначена политика с описанием `xkeen`, получают её mark. Mark **не хардкодится**: на разных роутерах он может быть разным (`0xffffaaa`, `0xffffaab`, ...). AntiGoblin при каждой сборке runtime ищет mark динамически по описанию политики `xkeen`.

Инвариант безопасности: `AntiGoblin` цепляется только к mark политики `xkeen`. Любые другие политики Keenetic (например, личная `no_vpn`) проектом не трогаются.

### TCP

```text
RETURN  локальные RFC1918 сети
RETURN  multicast (224.0.0.0/4) и broadcast
RETURN  адреса из ipset xkeen_bypass
REDIRECT всё остальное TCP -> 61219 (xray)
RETURN  fallback
```

`xray` на :61219 — `dokodemo-door` inbound. Дальше `05_routing.json` отправляет поток в outbound `vless-reality` или `direct`.

### UDP

```text
PREROUTING  UDP, dst ∈ xkeen_udp_route -> TPROXY :61221 (sing-box)
            всё остальное UDP -> direct (никаких хуков нет)
```

`sing-box` на :61221 принимает TPROXY-UDP и проксирует его в локальный xray Shadowsocks-relay (`127.0.0.1:62640`). Уже оттуда xray по тегу inbound отправляет UDP в outbound `vless-reality`.

Эта схема воспроизводит локальный путь `v2rayN` (TUN → SS-relay → xray VLESS) и стабильно работает для realtime-UDP, в т.ч. Discord voice. Прямой путь `xray TPROXY → vless-reality` retired как нерабочий: для realtime-UDP он давал стабильный 5000 мс ping.

### Что задаёт UI-группа

У каждой группы один параметр — `outbound`:

| Outbound       | TCP                       | UDP                       |
|----------------|---------------------------|---------------------------|
| `vless-reality`| через `xray` → VPN        | через `sing-box` → VPN    |
| `direct`       | через `xray` → без VPN    | direct (не перехватывается) |
| `bypass`       | `RETURN` до `xray`        | `RETURN` до `xray`        |

Отдельного флага «UDP через VPN» у группы нет: UDP идёт в VPN автоматически за outbound группы.

`bypass` и `direct` — **не одно и то же**. `bypass` — это `RETURN` ещё в `iptables`, поток вообще не доходит до `xray`. `direct` — поток вошёл в `xray`, но был выпущен наружу без VPN. Для локалки, discovery и части IoT cloud-сценариев нужен именно `bypass`, а не `direct`.

## Источник истины

`/opt/share/xkeen-manager/xkeen-ui-state.json` — единственный источник истины для UI и runtime.

Из него backend генерирует:

- `/opt/etc/xray/configs/04_outbounds.json`
- `/opt/etc/xray/configs/05_routing.json`

И собирает runtime-наборы `xkeen_bypass` и `xkeen_udp_route`. И apply из UI, и self-heal используют один и тот же код в `/opt/share/xkeen-manager/api/xkeen-runtime.sh` — расхождения между ними невозможны.

## Self-heal

`xkeen-selfheal.sh` запускается каждые 15 секунд через watchdog `S25antigoblin-selfheal` и:

- проверяет, что политика `xkeen` существует — если её удалили в Keenetic UI, создаёт заново как `Policy42+`;
- проверяет, что `xray` жив, слушает `61219`, имеет приемлемый `fd`/`conntrack`/память;
- проверяет, что `PREROUTING -> xkeen` на месте, и при необходимости пересобирает цепочку;
- проверяет, что `sing-box` слушает `61221`, если в UI есть хотя бы одна группа с outbound `vless-reality`;
- раз в ~5 минут пересобирает `xkeen_bypass` и `xkeen_udp_route` (DNS-имена могут резолвиться в новые IP) через `ipset swap` — без рестарта `xray`;
- пишет health-snapshot в `/opt/var/log/xkeen-health.log`;
- пишет действия в `/opt/var/log/xkeen-selfheal.log`.

Дополнительно стоит:

- cron-хук `cron.1min/50-antigoblin-selfheal` как страховочный слой;
- `ndm/fs.d/50-antigoblin.sh` и `ndm/usb.d/50-antigoblin.sh` — поднимают всё после возврата `/opt` или USB-событий;
- `S20antigoblin-sysctl` — точечно занижает TCP/conntrack-таймауты, чтобы fd на роутере не накапливались.

## Что больше не часть live-архитектуры

- `xkeen_udp` (общий UDP-перехват всей политики) — ломал игры и IoT.
- `xkeen_quic` (отдельный блокатор UDP/443) — перешел в общий `xkeen_udp_route` за outbound группы.
- Прямой xray TPROXY UDP на 61220 → vless-reality — заменен на `sing-box → SS-relay → xray VLESS`.
- Seed-файлы `bypass-domains.txt` / `bypass-cidrs.txt` — единственным источником истины является `xkeen-ui-state.json`.
- Live-снапшоты роутера в продуктовой части репозитория.
