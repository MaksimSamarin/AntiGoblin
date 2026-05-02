# Discord UDP investigation handoff

Дата: 2026-05-02

Цель: понять, почему Discord voice на ПК `192.168.2.106` плохо работает через роутерный AntiGoblin/xkeen, хотя локальный v2rayN TUN на этом же ПК работает штатно.

## Короткий вывод

Проблема не похожа на ошибку списков IP, UI-групп, Keenetic policy или iptables mark. Мы доказали, что Discord UDP попадает в `xkeen`, проходит через TPROXY и доходит до userspace.

Основной вывод на момент остановки: Discord voice плохо работает через роутерный путь `TPROXY -> VLESS Reality over TCP/XUDP`. Даже после добавления `sing-box` на роутер проблема не ушла. Нужен либо UDP-native транспорт для voice-групп, либо другой router-side дизайн, не завязанный на VLESS Reality TCP для UDP media.

## Инварианты проекта

- AntiGoblin должен трогать только Keenetic policy/group `xkeen`.
- Остальные политики Keenetic, например `no_vpn`, нельзя перехватывать.
- TCP selective-маршрутизация работает через `iptables nat REDIRECT -> xray 61219`.
- UDP selective-маршрутизация включается только для UI-групп с флагом `routeUdp`.
- UDP отбирается через ipset `xkeen_udp_route`.

## Устройства и политики

Проверенные соответствия:

- `192.168.2.106` = `MAIN PC` = MAC `34:5a:60:be:93:31`.
- Для тестов Discord ПК был возвращен в `Policy42/xkeen`.
- Mark `xkeen`: `0xffffaab`.

Команда проверки:

```sh
ndmc -c 'show running-config' | grep -E 'ip policy|description xkeen|host .*policy|policy Home'
ip neigh show | grep '192.168.2.106'
```

Ожидаемый смысл:

- `host 34:5a:60:be:93:31 policy Policy42`.
- `Policy42` имеет `description xkeen`.

## Рабочий локальный v2rayN TUN

Когда пользователь включает локальный v2rayN TUN на Windows, Discord voice начинает работать штатно.

Найденная локальная схема v2rayN:

```text
Discord -> sing-box TUN(gvisor) -> local Shadowsocks relay -> xray -> VLESS Reality
```

Файлы v2rayN:

- `C:\Users\Home-PC\Desktop\v2rayN-windows-64\binConfigs\configPre.json`
- `C:\Users\Home-PC\Desktop\v2rayN-windows-64\binConfigs\config.json`

Ключевые параметры `configPre.json`:

```json
{
  "type": "tun",
  "tag": "tun-in",
  "interface_name": "singbox_tun",
  "address": ["172.18.0.1/30"],
  "mtu": 9000,
  "auto_route": true,
  "strict_route": true,
  "stack": "gvisor"
}
```

Ключевой relay:

```json
{
  "server": "127.0.0.1",
  "server_port": 62640,
  "method": "none",
  "password": "none",
  "type": "shadowsocks",
  "tag": "proxy"
}
```

Ключевые параметры `config.json` у xray:

```json
{
  "listen": "127.0.0.1",
  "port": 62640,
  "protocol": "shadowsocks",
  "settings": {
    "network": "tcp,udp",
    "method": "none",
    "password": "none"
  },
  "tag": "proxy-relay-ss"
}
```

VLESS outbound локального xray:

```json
{
  "tag": "proxy",
  "protocol": "vless",
  "streamSettings": {
    "network": "tcp",
    "security": "reality"
  },
  "mux": {
    "enabled": false
  }
}
```

Важное отличие: локальный v2rayN использует `sing-box` как TUN/gvisor сетевой слой. Это не то же самое, что роутерный `iptables TPROXY -> xray dokodemo-door`.

## Что было проверено на роутере

### 1. IP-списки Discord

Discord voice ходил на адреса вида:

```text
104.29.153.248:19316
104.29.153.181:19332
104.29.153.111:19329
104.29.153.234:19331
104.29.156.6:19339
```

Эти IP попадали в `xkeen_udp_route`.

Команды:

```sh
ipset test xkeen_udp_route 104.29.153.248
ipset test xkeen_udp_route 104.29.156.6
```

Вывод был вида:

```text
Warning: 104.29.153.248 is in set xkeen_udp_route.
```

Вывод: проблема не в том, что Discord IP не добавлены.

### 2. Mark и policy

Conntrack для Discord UDP показывал mark `268434091`, это `0xffffaab`, то есть `xkeen`.

Пример:

```text
udp src=192.168.2.106 dst=104.29.153.248 sport=57034 dport=19316 ... mark=268434091
```

Вывод: трафик тестового ПК действительно был в `xkeen`.

### 3. TPROXY ловит UDP

Изначально UDP шел в xray `61220`, потом был переведен на sing-box `61221`.

Актуальный hook после доработки:

```sh
iptables -t mangle -S PREROUTING | grep xkeen
```

Ожидаемо:

```text
-A PREROUTING -p udp -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -m set --match-set xkeen_udp_route dst -j xkeen_udp_route
```

Цепочка:

```sh
iptables -t mangle -L xkeen_udp_route -v -n
```

Ожидаемо:

```text
TPROXY redirect 0.0.0.0:61221 mark 0x111/0x111
```

Счетчик рос во время Discord voice. Пример:

```text
pkts bytes target
71   14186 TPROXY udp ...
```

Вывод: UDP реально ловится.

### 4. Тест "весь UDP через VPN"

Временно ставился hook без ipset-фильтра:

```sh
-A PREROUTING -p udp -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen_udp_route
```

То есть весь UDP из `xkeen` шел в TPROXY.

Результат: Discord voice не починился.

Вывод: проблема не в неполном наборе Discord IP.

## Попытка 1: UDP через xray TPROXY

Схема:

```text
Discord UDP -> iptables TPROXY 61220 -> xray dokodemo-door/tproxy -> VLESS Reality
```

Файл:

- `/opt/etc/xray/configs/03_inbounds.json`

Inbound:

```json
{
  "tag": "tproxy",
  "port": 61220,
  "protocol": "dokodemo-door",
  "settings": {
    "network": "udp",
    "followRedirect": true
  },
  "streamSettings": {
    "sockopt": {
      "tproxy": "tproxy"
    }
  }
}
```

Routing:

```json
{
  "type": "field",
  "inboundTag": ["tproxy"],
  "network": "udp",
  "outboundTag": "vless-reality"
}
```

Пробовали варианты VLESS mux:

- `mux.enabled = true`, `concurrency = -1`, `xudpConcurrency = 16`, `xudpProxyUDP443 = "reject"`.
- `mux.enabled = false`.

Результат: Discord voice не починился.

## Попытка 2: sing-box relay как у v2rayN

Добавлены файлы:

- `/opt/etc/sing-box/xkeen.json`
- `/opt/etc/xray/configs/02_relay.json`

Установлен musl-бинарь:

```text
/opt/sbin/sing-box
sing-box version 1.13.8
Tags: with_gvisor, with_quic, with_wireguard, with_utls, ... with_musl
```

Важно: обычный `linux-arm64` binary не запускается на Keenetic/Entware и дает:

```text
sh: /opt/sbin/sing-box: not found
```

Нужен `linux-arm64-musl`.

Схема:

```text
Discord UDP -> TPROXY 61221 -> sing-box -> local SS 127.0.0.1:62640 -> xray -> VLESS Reality
```

`sing-box` слушал:

```text
udp 0.0.0.0:61221  19466/sing-box
```

xray relay слушал:

```text
tcp 127.0.0.1:62640  xray
udp 127.0.0.1:62640  xray
```

Факт прохождения до relay:

```text
udp 127.0.0.1:<port> -> 127.0.0.1:62640 ESTABLISHED  sing-box
```

Результат: Discord voice не починился.

## Попытка 3: sing-box напрямую в VLESS Reality

Схема:

```text
Discord UDP -> TPROXY 61221 -> sing-box VLESS Reality -> server
```

Первый конфиг содержал:

```json
"flow": "xtls-rprx-vision",
"network": "tcp",
"packet_encoding": "xudp"
```

Лог `sing-box` показал точную ошибку:

```text
router: UDP is not supported by outbound: vless-reality
```

После удаления `flow` ошибка осталась.

После удаления `"network": "tcp"` ошибка исчезла. Лог стал:

```text
inbound/tproxy[xkeen-udp-tproxy]: inbound packet connection to 104.29.153.248:19316
outbound/vless[vless-reality]: outbound packet connection to 104.29.153.248:19316
```

То есть `sing-box` начал считать VLESS outbound UDP-capable.

Результат: Discord voice стало стабильно 5000 ms, то есть не починилось.

Вывод: даже когда sing-box технически отправляет UDP в VLESS outbound, качество/совместимость для Discord voice плохие.

## Актуальное состояние на роутере после последнего теста

Debug лог выключен и очищен:

```text
/opt/var/log/sing-box-xkeen.log size 0
```

`sing-box` запущен:

```text
sing-box run -c /opt/etc/sing-box/xkeen.json
udp 0.0.0.0:61221
```

xray запущен:

```text
/opt/sbin/xray run
tcp6 :::61219
tcp 127.0.0.1:62640
udp 127.0.0.1:62640
```

UDP hook:

```text
TPROXY redirect 0.0.0.0:61221 mark 0x111/0x111
```

Внимание: `sing-box` конфиг сейчас оставлен в варианте direct VLESS без debug, без `network: tcp`, без `flow`, с `packet_encoding: xudp`.

## Главная гипотеза на конец расследования

VLESS Reality over TCP/XUDP не подходит для Discord voice в роутерном TPROXY-сценарии. Это не просто "не поймали IP". Это транспортная проблема realtime UDP через TCP-based proxy stack.

Локальный v2rayN TUN работает, но это не доказывает, что роутерный TPROXY + VLESS должен работать так же. Локальная схема использует Windows TUN/gvisor и связку процессов, а не router TPROXY.

## Что НЕ надо делать дальше

- Не добавлять бесконечно новые Discord IP, пока не появится новый факт. Тест "весь UDP через VPN" уже не помог.
- Не искать проблему в Bypass/Direct UI-группах. Для Discord UDP мы видели correct mark и TPROXY hit.
- Не возвращать `xkeen_quic` или старый UDP-хардкод.
- Не трогать другие Keenetic policies. Только `xkeen`.

## Что стоит проверить дальше

### Вариант A: UDP-native outbound

Добавить второй outbound специально для UDP voice-групп:

- WireGuard
- Hysteria2
- TUIC

Идея:

```text
TCP selected groups -> xray VLESS Reality
UDP selected groups -> UDP-native transport
```

Это наиболее перспективный путь.

### Вариант B: проверить серверную поддержку XUDP/UDP

Если есть доступ к серверу, проверить server-side xray:

- версия xray;
- VLESS inbound;
- поддержка UDP/XUDP;
- нет ли ограничений firewall на UDP-like flows;
- не ломается ли Reality/Vision при UDP encapsulation.

Но даже если сервер поддерживает, Discord voice через VLESS over TCP может быть плохим по задержкам.

### Вариант C: полноценный sing-box stack вместо xray для UDP

Не relay в xray, а отдельный sing-box outbound с UDP-native протоколом.

Прямой sing-box VLESS был проверен и не помог, поэтому просто "переписать на sing-box VLESS" не выглядит достаточным.

### Вариант D: Discord direct/bypass

Если Discord voice доступен напрямую без VPN у конкретного провайдера, можно оставить Discord UDP direct, а TCP/домены Discord при необходимости гонять через VPN.

Это практично, но не универсально.

## Полезные команды диагностики

Проверить процессы и порты:

```sh
ps | grep -E '[x]ray|[s]ing-box'
netstat -lnptu 2>/dev/null | grep -E '61219|61220|61221|62640|xray|sing-box'
```

Проверить hooks:

```sh
iptables -t nat -S PREROUTING | grep xkeen
iptables -t mangle -S PREROUTING | grep xkeen
iptables -t mangle -L xkeen_udp_route -v -n
```

Проверить Discord conntrack:

```sh
conntrack -L -p udp 2>/dev/null \
  | grep 'src=192.168.2.106' \
  | grep -E '104\.29\.|66\.22\.|162\.159\.|172\.64\.|172\.65\.|172\.66\.|172\.67\.|1932|1933'
```

Проверить, что Discord IP в UDP ipset:

```sh
ipset test xkeen_udp_route 104.29.153.248
```

Включить временный sing-box debug:

```sh
cp /opt/etc/sing-box/xkeen.json /opt/etc/sing-box/xkeen.json.bak-debug
# руками добавить:
# "log": {"level":"info","timestamp":true,"output":"/opt/var/log/sing-box-xkeen.log"}
/opt/sbin/sing-box check -c /opt/etc/sing-box/xkeen.json
/opt/etc/init.d/S24antigoblin-singbox restart
tail -f /opt/var/log/sing-box-xkeen.log
```

Выключить debug:

```sh
# вернуть log.level warn и убрать log.output
/opt/etc/init.d/S24antigoblin-singbox restart
: > /opt/var/log/sing-box-xkeen.log
```

Проверить xray config:

```sh
/opt/sbin/xray run -test -confdir /opt/etc/xray/configs
```

## Файлы, которые были добавлены/изменены в ходе попытки

Добавлены:

- `configs/xkeen/02_relay.sample.json`
- `configs/xkeen/sing-box-xkeen.sample.json`
- `scripts/xkeen/antigoblin-singbox.initd.sh`

Изменены:

- `ui/xkeen-manager/backend/xkeen-runtime.sh`
- `ui/xkeen-manager/backend/xkeen-selfheal.sh`
- `ui/xkeen-manager/app.js`
- `configs/xkeen/05_routing.sample.json`
- `scripts/xkeen/bootstrap_antigoblin_router.ps1`
- `scripts/xkeen/deploy_xkeen_manager_backend_to_router.ps1`

## Мой честный итог

Я не смог добиться рабочего Discord voice через текущий VLESS Reality router-path. Но расследование сузило проблему:

- policy/mark верные;
- ipset верный;
- TPROXY работает;
- xray relay работает;
- sing-box запускается;
- ошибка `UDP is not supported by outbound` была найдена и устранена;
- после устранения UDP начал уходить в VLESS outbound, но Discord voice стал стабильно плохим.

Следующему разработчику стоит не продолжать лечить списки, а менять транспортную стратегию для UDP voice.
