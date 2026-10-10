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

## 3. Claude Code / VS Code не авторизуется: `platform.claude.com` видит RU

### Симптом

- В Claude Code / VS Code слетает авторизация или повторяется login flow.
- В логе расширения есть `platform.claude.com/v1/oauth/token`, `403` и `Request not allowed`.
- `https://claude.ai/cdn-cgi/trace` показывает VPN-IP, а `https://platform.claude.com/cdn-cgi/trace` показывает direct/RU-IP.

### Причина

Claude Code использует не только `claude.ai` и `api.anthropic.com`, но и OAuth endpoint `platform.claude.com`. Если в группе Claude есть только `claude.ai`/`anthropic.com`, часть авторизации может уйти в fallback `direct`.

### Решение

В UI-группу Claude с outbound `vless-reality` добавить домены:

- `claude.ai`
- `claude.com`
- `platform.claude.com`
- `anthropic.com`
- `claudeusercontent.com`

После этого нажать `Сохранить и применить` и проверить:

```powershell
curl.exe --noproxy "*" -4 -s https://platform.claude.com/cdn-cgi/trace
```

Ожидаемо: `ip=` равен VPN exit IP, а `loc=` не RU.

## 4. Chrome / Claude / Discord обходят VPN через QUIC

### Симптом

- Сайт в браузере явно идет direct, хотя домен сидит в `vless-reality` группе.
- `google-chrome --disable-quic` сразу чинит ситуацию.
- В `conntrack` или `tcpdump` видно `UDP/443` соединения от устройства.

### Причина

Современные клиенты переходят с HTTPS на QUIC (UDP/443), как только сервер его поддерживает. По умолчанию AntiGoblin не загоняет весь UDP политики в VPN — это ломает игры, RTC и IoT.

### Решение

Положить домены/CIDR сервиса в группу с outbound `vless-reality`. Self-heal сам добавит их в `xkeen_udp_route`, и QUIC-трафик начнет проходить через VPN. Отдельного флага «UDP через VPN» нет — UDP идет в VPN автоматически за outbound группы.

Для Cloudflare, Discord и подобных лучше добавлять не только домены, но и CIDR-диапазоны: у QUIC-пакетов не всегда есть SNI, по которому правило по домену сматчится.

## 5. Discord voice плавает по задержке или вообще не подключается

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

## 6. Игра не подключается к серверу или висит на логине после установки

### Симптом

- `HANDSHAKE_DEADLINK`, бесконечная авторизация, постоянные таймауты.
- На неVPN-устройстве та же игра работает.

### Причина

Игровой UDP (особенно anti-cheat и трафик к game-server orchestration) не любит проксирование через любой VPN — увеличивается RTT, ломаются sequence-checks, рвутся сессии.

### Решение

- Положить устройство с игрой не в `xkeen`, а в политику Keenetic типа `no_vpn` (если она у тебя есть), либо
- Создать в UI группу с outbound `bypass`, добавить туда домены/CIDR игрового сервера, и держать игровое устройство в `xkeen`. Игровой трафик уйдет до `xray` через `RETURN`, остальной TCP пойдет через VPN.

## 7. Что-то ведет себя «как раньше» после Сохранить и применить

Симптом: вроде применил новую группу, но устройство продолжает идти старым путем.

Возможные причины:

- Браузер держит долгоживущие HTTP/2 сессии — закрыть вкладки сервиса и открыть заново.
- Conntrack еще держит старые TCP-записи. Self-heal сам сбрасывает conntrack к VPN-апстриму при controlled-restart `xray`, но конкретные клиентские сессии могут остаться. Подождать 1–2 минуты или выключить-включить Wi-Fi на устройстве.
- Keenetic не успел перепривязать устройство к политике после смены — проверить в `Приоритеты подключений`.

## 8. Включить отладочный лог `xray` (по необходимости)

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

## 9. Где смотреть логи

| Лог | Что там |
|-----|--------|
| `/opt/var/log/xkeen-selfheal.log` | Что чинил self-heal в последние циклы. |
| `/opt/var/log/xkeen-health.log` | Health-snapshots `xray` каждые 5 мин: `fd`, `conntrack`, mem, состояния сокетов к VPN-серверу. |
| `/opt/var/log/xray/access.log` | Подробный access лог `xray` (только когда `loglevel: info`). |
| `/opt/var/log/xray/error.log` | Ошибки `xray` (рестарт, отвал TLS, проблемы с outbound). |
| `/opt/var/log/sing-box-xkeen.log` | sing-box, если включен debug в `/opt/etc/sing-box/xkeen.json`. |
| `/opt/var/log/xkeen-manager-uhttpd.log` | UI-сервер `uhttpd_kn` на :8899. |

То же самое доступно прямо в UI в блоке «Здоровье и логи» — селектор и кнопка «Загрузить».

## 10. Диагностика внутренностей self-heal (advanced)

### DNS cache
`xkeen-runtime.sh` кэширует результаты `nslookup` в `/tmp/xkeen-dns-cache/` чтобы apply/selfheal не блокировался на медленных DNS-ответах.

- Положительный TTL — 15 мин, отрицательный — 2 мин (пустой файл = «нет A-записей»).
- Проверить содержимое:

```sh
ls -la /tmp/xkeen-dns-cache/ | head
```

- Заставить пересобрать (если поменялся upstream DNS и IP-ки устарели):

```sh
rm -rf /tmp/xkeen-dns-cache/*
/opt/share/xkeen-manager/api/xkeen-selfheal.sh --force
```

### Shared apply-lock

`selfheal / apply / netfilter-hook` синхронизируются через один mkdir-lock — `/tmp/xkeen-selfheal.lock/`. Remount-hook перезапускает службы без этого lock; заключительный вызов selfheal получает lock самостоятельно.

- Кто держит и жив ли:

```sh
[ -f /tmp/xkeen-selfheal.lock/pid ] && cat /tmp/xkeen-selfheal.lock/pid
PID=$(cat /tmp/xkeen-selfheal.lock/pid 2>/dev/null)
[ -n "$PID" ] && tr '\0' ' ' </proc/$PID/cmdline
```

- Симптомы застрявшего lock: `apply` из UI отвечает `503 apply lock busy`, health checks сериализуются. Селфхил сам ловит stale (умершего или подменённого владельца) и пишет `lock_stale_cleanup` в `xray-manual.log` — эти сообщения полезны:

```sh
grep -E "lock_stale|lock_abandoned" /opt/var/log/xray-manual.log | tail -20
```

- Ручная зачистка (только если фрилок реально сдох и не self-cleanup'ится):

```sh
rm -rf /tmp/xkeen-selfheal.lock
```

### NDM netfilter-hook

`/opt/etc/ndm/netfilter.d/50-antigoblin.sh` восстанавливает TPROXY-jump в конце `mangle PREROUTING` за миллисекунды после каждого NDM reload netfilter (WAN reconnect, WiFi client join, firewall changes).

- Проверить что хук стоит и исполняем:

```sh
ls -la /opt/etc/ndm/netfilter.d/50-antigoblin.sh
```

- Симптом: `Discord` теряет голос на 1-3 секунды при WiFi-событиях. Без хука восстановление занимает до 15 сек (следующий selfheal-tick).

- Тест руками (удалить правило, вызвать хук, проверить восстановление). Mark политики xkeen у каждого роутера свой — берём из `/tmp/xkeen-mark` (кэш, пишется selfheal/apply при успешном ndmc-запросе):

```sh
MARK="0x$(cat /tmp/xkeen-mark 2>/dev/null)"
iptables -t mangle -D PREROUTING -p udp -m connmark --mark "$MARK" -m conntrack ! --ctstate INVALID -m set --match-set xkeen_udp_route dst -j xkeen_udp_route
env table=mangle /opt/etc/ndm/netfilter.d/50-antigoblin.sh
iptables -t mangle -S PREROUTING | tail -2
```

### xray restart backoff

После N подряд неудачных стартов selfheal вводит экспоненциальный backoff (60 → 300 → 900 → 1800 сек), чтобы кривой конфиг не превращал selfheal в watchdog storm.

- Проверить активен ли backoff:

```sh
[ -f /tmp/xkeen-xray-start-backoff.ts ] && \
  echo "backoff active until $(date -d @$(cat /tmp/xkeen-xray-start-backoff.ts) 2>/dev/null || cat /tmp/xkeen-xray-start-backoff.ts)"
cat /tmp/xkeen-xray-start-fail-streak 2>/dev/null
```

- Сбросить (например после ручной починки конфига):

```sh
rm -f /tmp/xkeen-xray-start-backoff.ts /tmp/xkeen-xray-start-fail-streak
/opt/share/xkeen-manager/api/xkeen-selfheal.sh --force
```

Успешный старт xray (из UI-`Рестарт` или selfheal-цикла) обе эти отметки сбрасывает автоматически.

### `repair failed: runtime hooks` каждые 15 сек — `ndmc` падает под Entware `LD_LIBRARY_PATH`

Симптомы (все сразу, ровно с какого-то момента):

- `/opt/var/log/xkeen-selfheal.log` — `repair start` / `repair failed: runtime hooks` каждые 15 сек, ни одного `repair done`;
- `/tmp/xkeen-mark` не обновляется (дата = последний успешный repair);
- в UI Health `tproxyRuleAtEnd: fail`, а `iptables -t nat -S PREROUTING | grep xkeen` пуст — после любого NDM netfilter-reload цепочки `xkeen` / `xkeen_udp_route` пропадают и не возвращаются;
- «VPN подключён, сайты не грузятся»: xray жив, но трафик устройств идёт мимо него;
- упавший xray сам не поднимается (`restart_xray` в selfheal идёт после hooks);
- при этом панель показывает `policyName` и `mark` — CGI ndmc работает, что маскирует проблему.

Причина: `/bin/ndmc` — системный бинарь, слинкованный с библиотеками прошивки. Entware-стартер `rc.unslung` экспортирует `LD_LIBRARY_PATH=/opt/lib:/opt/usr/lib:/lib:/usr/lib` во все `/opt/etc/init.d/S*`, включая selfheal-демон и SSH-сессии с Entware-профилем. Как только в `/opt/lib` появляется библиотека, конфликтующая с системной (обычно после `opkg upgrade`), ndmc под этим окружением падает:

```
ndm: ndmc: system failed [0xcffd0062].
ndm: Cli::Main: failed to initialize.
```

`xkeen_ensure_mark` возвращает ошибку без записи в лог, `xkeen_repair_hooks` прерывается на первом шаге. uhttpd (CGI) переменную не наследует — панель продолжает видеть mark.

Проверка одной парой команд из SSH роутера:

```sh
LD_LIBRARY_PATH= ndmc -c 'show version'            # должно ответить
LD_LIBRARY_PATH=/opt/lib:/opt/usr/lib:/lib:/usr/lib ndmc -c 'show version'   # если падает — это оно
```

Фикс — в коде: все вызовы идут через `xkeen_ndmc()` (`LD_LIBRARY_PATH= ndmc "$@"`) в `xkeen-runtime.sh`; в `routing.cgi`, `install.sh`, `antigoblin-firstboot.sh` и PS1-помощниках ndmc вызывается как `LD_LIBRARY_PATH= ndmc -c …`. Глобально чистить `LD_LIBRARY_PATH` нельзя — `jq`, `awk`, `curl` из `/opt/bin` без `/opt/lib` не запустятся.

Убедиться, что помогло: `/opt/share/xkeen-manager/api/xkeen-selfheal.sh --force` → в логе `repair done`, `/tmp/xkeen-mark` со свежей датой, в UI Health все чеки `ok`.

### xray не стартует через `S24xray` / не переживает ребут

Стоковый Entware-init `/opt/etc/init.d/S24xray` содержит `ARGS="run -confdir /opt/etc/$PROCS"` — путь задан через переменную. Он раскрывается в `/opt/etc/xray`, где лежит только `config.json.example`; рабочие конфиги — в `/opt/etc/xray/configs/`. Такой xray стартует с пустым конфигом и сразу выходит: `/opt/etc/init.d/S24xray restart` **гасит** рабочий xray и не поднимает новый.

Selfheal и remount-hook чинят это автоматически (`ensure_xray_init_confdir`); backend deploy также исправляет init-скрипт. Старые версии искали в файле литерал `/opt/etc/xray` и молча пропускали форму с `$PROCS`. Проверить и починить руками:

```sh
grep -n 'ARGS=' /opt/etc/init.d/S24xray          # должно быть: run -confdir /opt/etc/xray/configs
sed -i -E 's#ARGS="run -confdir /opt/etc/(xray|\$PROCS)"#ARGS="run -confdir /opt/etc/xray/configs"#' /opt/etc/init.d/S24xray
```

Поднять xray без init-скрипта, так же как это делает selfheal:

```sh
XRAY_LOCATION_ASSET=/opt/etc/xray/dat XRAY_LOCATION_CONFDIR=/opt/etc/xray/configs \
  /opt/sbin/start-stop-daemon -S -b -m -p /opt/var/run/xray-ui.pid -x /opt/sbin/xray -- run
```
