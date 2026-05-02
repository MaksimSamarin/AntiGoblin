# Troubleshooting

Здесь только проблемы, на которые пользователь реально может наткнуться и которые он сам может починить через UI или несколько команд по SSH.

Большая часть исторических багов (stale `xray` после apply, lock self-heal, переключение Keenetic-политик, удаление `xkeen` в web UI, дрейф `fd`/`conntrack`, устаревшие CDN-IP в `ipset`) уже зашита в self-heal и при чистой установке через `install.sh` ловится автоматически. Если показалось, что что-то из этого снова сломалось — смотри:

- `/opt/var/log/xkeen-selfheal.log` — что чинил self-heal в последние циклы;
- `/opt/var/log/xkeen-health.log` — снапшоты здоровья `xray` каждые 5 минут (`fd`, conntrack, память, состояние сокетов на VPN-апстрим);
- блок «Здоровье и логи» прямо в UI — там же видно, какие проверки сейчас красные.

## 1. Сайт показывает не VPN-IP, хотя должен

### Симптом

- Группа сервиса в UI выставлена в `vless-reality`, в applied `05_routing.json` правило для домена есть.
- `https://2ip.ru` или `https://chatgpt.com/cdn-cgi/trace` показывает direct IP провайдера.

### Что проверить по слоям

1. UI state: домен реально лежит в правильной группе и группа `enabled: true`.
2. Apply: после правки нажат `Сохранить и применить`, не просто `Сохранить`.
3. На роутере: `cat /opt/etc/xray/configs/05_routing.json | grep <домен>` — правило есть.
4. На роутере: `iptables -t nat -S PREROUTING | grep xkeen` — hook на mark `xkeen` живой.
5. На устройстве: устройство привязано к политике `xkeen` в Keenetic web UI (`Приоритеты подключений`).
6. На устройстве: нет локального VPN-клиента / TUN, который перехватывает трафик до роутера.
7. Браузер: жесткий refresh `Ctrl+Shift+R`. У Chrome/Firefox долгоживущие HTTP/2-сессии могут тащить старый путь после смены группы — закрыть вкладку и открыть заново.

Если `cdn-cgi/trace` показал VPN-IP, а сайт всё равно видит direct — значит, поверх роутерного path есть что-то ещё на ПК. Если `cdn-cgi/trace` показал direct — проблема в пути роутер → VPN.

## 2. Mi Home, Xiaomi-камеры или умные розетки тупят / подключаются 3-5 минут

### Причина

Часть Xiaomi cloud-сценариев плохо переносит сам факт прозрачного `TCP REDIRECT -> xray`, даже если внутри `xray` поток уйдет в `direct`. `RETURN` до `xray` и `direct` внутри `xray` — это не одно и то же.

### Решение

- Создать UI-группу с outbound `bypass` и положить в нее домены/CIDR Xiaomi cloud.
- `bypass` означает `RETURN` ещё до попадания в `xray`. `direct` означает «вошел в xray и вышел без VPN» — этого недостаточно для IoT.
- Локальный multicast/broadcast уже выносится автоматически — руками этого делать не надо.

## 3. Chrome / Claude / Discord обходят VPN через QUIC

### Симптом

- Сайт в браузере явно идет direct, хотя домен сидит в `vless-reality` группе.
- `google-chrome --disable-quic` сразу чинит ситуацию.
- В `conntrack` или `tcpdump` видно `UDP/443` соединения от устройства.

### Причина

Современные клиенты переходят с HTTPS на QUIC (UDP/443), как только сервер его поддерживает. По умолчанию AntiGoblin не загоняет весь UDP политики в VPN — это ломает игры, RTC и IoT.

### Решение

Положить домены/CIDR сервиса в группу с outbound `vless-reality`. Self-heal сам добавит их в `xkeen_udp_route`, и QUIC-трафик начнет проходить через VPN. Отдельного флага «UDP через VPN» нет — UDP идет в VPN автоматически за outbound группы.

Для Cloudflare, Discord и подобных лучше добавлять не только домены, но и CIDR-диапазоны: у QUIC-пакетов не всегда есть SNI, по которому правило по домену сматчится.

## 4. Discord voice плавает по задержке или вообще не подключается

### Симптом

- Текстовый Discord работает.
- Голос подключился, но ping 1000+ мс или собеседник режется.

### Причина

Discord voice идет по UDP RTC к Cloudflare-CDN (`104.29.x.x:19300-19400` и т.п.). Если эти IP не в `xkeen_udp_route`, голос остается на direct — у провайдера это часто упирается в плохие маршруты или фильтры.

### Решение

В UI создать (или включить) группу для Discord с outbound `vless-reality`. В нее добавить:

- домены `discord.com`, `discord.gg`, `discordapp.com`, `discordapp.net`;
- CIDR Discord/Cloudflare RTC. Готовые свежие списки можно взять в [iplist.opencck.org](https://iplist.opencck.org/) (раздел `discord`).

Транспортный путь под капотом:

```text
Device UDP -> iptables TPROXY :61221 -> sing-box -> 127.0.0.1:62640 (xray SS-relay) -> xray vless-reality
```

Если voice по-прежнему висит, проверить:

```sh
ipset list xkeen_udp_route                     # IP Discord должны быть в наборе
iptables -t mangle -L xkeen_udp_route -v -n    # счетчик пакетов растет?
netstat -lnpu  | grep 61221                    # sing-box слушает
netstat -lnptu | grep 62640                    # xray relay слушает
ip rule show | grep 'fwmark 0x111'             # masked rule lookup 111
```

## 5. Игра не подключается к серверу или висит на логине после установки

### Симптом

- `HANDSHAKE_DEADLINK`, бесконечная авторизация, постоянные таймауты.
- На неVPN-устройстве та же игра работает.

### Причина

Игровой UDP (особенно anti-cheat и трафик к game-server orchestration) не любит проксирование через любой VPN — увеличивается RTT, ломаются sequence-checks, рвутся сессии.

### Решение

- Положить устройство с игрой не в `xkeen`, а в политику Keenetic типа `no_vpn` (если она у тебя есть), либо
- Создать в UI группу с outbound `bypass`, добавить туда домены/CIDR игрового сервера, и держать игровое устройство в `xkeen`. Игровой трафик уйдет до `xray` через `RETURN`, остальной TCP пойдет через VPN.

## 6. Что-то ведет себя «как раньше» после Сохранить и применить

Симптом: вроде применил новую группу, но устройство продолжает идти старым путем.

Возможные причины:

- Браузер держит долгоживущие HTTP/2 сессии — закрыть вкладки сервиса и открыть заново.
- Conntrack еще держит старые TCP-записи. Self-heal сам сбрасывает conntrack к VPN-апстриму при controlled-restart `xray`, но конкретные клиентские сессии могут остаться. Подождать 1–2 минуты или выключить-включить Wi-Fi на устройстве.
- Keenetic не успел перепривязать устройство к политике после смены — проверить в `Приоритеты подключений`.

## 7. Включить отладочный лог `xray` (по необходимости)

Когда нужно понять, какой именно `IP:port` входит в `xray` и в какой outbound он уходит:

```sh
# /opt/etc/xray/configs/01_log.json
{
  "log": { "loglevel": "info" }
}
```

```sh
: > /opt/var/log/xray/access.log
xkeen restart      # или /opt/etc/init.d/S24xray restart
tail -f /opt/var/log/xray/access.log
```

Что показывает: `from <client>:<port> accepted tcp:IP:PORT [redirect -> outbound-tag]`.

Чего не показывает: трафик, который ушел `RETURN`-ом еще до `xray` (локалка, `xkeen_bypass`). Для этого смотри счетчики `iptables -t nat -L xkeen -v -n`.

После отладки **обязательно**:

```json
{
  "log": { "loglevel": "none" }
}
```

И снова рестарт `xray`. Иначе access.log быстро забьет флешку.

## 8. Где смотреть логи

| Лог | Что там |
|-----|--------|
| `/opt/var/log/xkeen-selfheal.log` | Что чинил self-heal в последние циклы. |
| `/opt/var/log/xkeen-health.log` | Health-snapshots `xray` каждые 5 мин: `fd`, `conntrack`, mem, состояния сокетов к VPN-серверу. |
| `/opt/var/log/xray/access.log` | Подробный access лог `xray` (только когда `loglevel: info`). |
| `/opt/var/log/xray/error.log` | Ошибки `xray` (рестарт, отвал TLS, проблемы с outbound). |
| `/opt/var/log/sing-box-xkeen.log` | sing-box, если включен debug в `/opt/etc/sing-box/xkeen.json`. |
| `/opt/var/log/xkeen-manager-uhttpd.log` | UI-сервер `uhttpd_kn` на :8899. |

То же самое доступно прямо в UI в блоке «Здоровье и логи» — селектор и кнопка «Загрузить».
