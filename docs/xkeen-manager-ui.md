# Runbook: AntiGoblin UI

## Что это

`AntiGoblin` — router-hosted UI для управления:

- профилями (несколько независимых наборов настроек)
- активным ключом (radio-selector в панели «Активный ключ»)
- ручными ключами (vless:// / vmess:// / hysteria2:// URI)
- подписками (HTTPS URL → backend стягивает и парсит)
- routing-группами (`vless-reality` через VPN / `bypass` мимо)
- Mux/XUDP
- сгенерированными файлами `xray` и `sing-box` на роутере

## Файлы на роутере

UI state:

- `/opt/share/xkeen-manager/xkeen-ui-state.json` — источник истины (`profiles[]`, `proxies[]`, `subscriptions[]`, `groups[]`, `activeProxyId`, `muxConfig`)

Сгенерированные файлы `xray`:

- `/opt/etc/xray/configs/04_outbounds.json` — активный outbound (vless / vmess / hy2-мост)
- `/opt/etc/xray/configs/05_routing.json` — правила из UI-групп

Также с UI-стороны редактируется:

- `/opt/etc/xray/configs/03_inbounds.json` — содержит SOCKS5-inbound `socks-in` (порт `61080`, LAN-IP роутера подставляется автоматически)
- `/opt/etc/sing-box/xkeen.json` — bridge для hy2 (mixed :61225) и TPROXY UDP (:61221)

Backend:

- `/opt/share/xkeen-manager/api/routing.cgi` — HTTP API (`kind=state|outbounds|singbox|repair-runtime|restart-svc|probe|subscription-fetch|health|stack-info|logs|login|logout`)
- `/opt/share/xkeen-manager/api/xkeen-selfheal.sh` — watchdog (15 сек tick + cron.1min страховка)
- `/opt/share/xkeen-manager/api/xkeen-runtime.sh` — shared runtime builder (iptables/ipset/DNS-cache/lock)

Конфиги:

- `/opt/etc/antigoblin.conf` — `PORT=<UI-порт>` (задаётся установщиком через `ANTIGOBLIN_UI_PORT`)

## Действия в UI

### Добавить ключ

**Ручной ключ** — вставить `vless://` / `vmess://` / `hysteria2://` URI, backend распарсит на поля. Или заполнить поля вручную.

**Подписка** — HTTPS URL. Backend стягивает через `curl` (fallback `wget-ssl`), парсит base64 → набор URI → создаёт по одному `proxies[]`-элементу с `source=<subId>`.

### Выбрать активный ключ

Radio-кнопка в панели «Активный ключ». Активный ключ → генерируется `outbound` в `04_outbounds.json`. Все routing-группы с `outbound=vless-reality` используют этот ключ (сам тег `vless-reality` — просто «через VPN», реальный протокол зависит от активного ключа).

### `Сохранить`

Только UI state на роутере, без пересборки xray/sing-box.

### `Сохранить и применить`

Pipeline из 4 шагов:

1. **state** — POST `xkeen-ui-state.json`
2. **outbounds** — генерирует `04_outbounds.json` из активного ключа
3. **sing-box** — генерирует `sing-box/xkeen.json` (bridge для hy2 или пустой)
4. **routing** — генерирует `05_routing.json`, validate xray-config, backup всех троих, перезапускает xray + sing-box (если нужно)

При провале UI показывает **на каком шаге** упало (`Save/apply failed на шаге <state|outbounds|sing-box|routing>: ...`).

### `Рестарт`

Чинит только runtime (не трогает конфиги):

- цепочку `xkeen` в iptables
- hook `PREROUTING -> xkeen`
- runtime-наборы `xkeen_bypass` и `xkeen_udp_route`
- перезапускает xray

### Кнопки в панели Health

- `↻ xray` — рестарт xray с graceful shutdown и port-poll'ом
- `↻ sing-box` — рестарт sing-box + port-poll `:61221`
- `↻ self-heal` — рестарт watchdog-loop'а

## Деплой

### Первый прогон на чистом роутере

`deploy_xkeen_manager_stack_to_router.ps1` — это **итеративный push**: залил файлы, рестартнул uhttpd, готово. На чистой машине (Entware поставлен, но политики `xkeen`, essential-пакетов, sing-box и `antigoblin.conf` ещё нет) он упадёт: `uhttpd not found`, `xkeen policy missing`, `sing-box not found`. Для первого раза нужен `bootstrap_antigoblin_router.ps1` — ставит пакеты, создаёт политику, скачивает sing-box по нужной arch, пишет `/opt/etc/antigoblin.conf`.

```powershell
$env:ROUTER_SSH_PASSWORD = 'пароль-ssh-роутера'
.\scripts\xkeen\bootstrap_antigoblin_router.ps1 -RouterHost 192.168.1.1
```

Идемпотентен — повторный запуск не сломает уже установленную систему.

### Полный стек (итеративно)

```powershell
$env:ROUTER_SSH_PASSWORD = 'пароль-ssh-роутера'
$env:ROUTER_SSH_USER = 'root' # опционально
$env:ANTIGOBLIN_UI_PORT = '8899' # опционально, default 8899
.\scripts\xkeen\deploy_xkeen_manager_stack_to_router.ps1 -RouterHost 192.168.1.1
```

Открыть:

```text
http://<router-ip>:<port>/     (по умолчанию 8899)
```

### Только UI

```powershell
.\scripts\xkeen\deploy_xkeen_manager_ui_to_router.ps1 -RouterHost 192.168.1.1
```

### Только backend

```powershell
.\scripts\xkeen\deploy_xkeen_manager_backend_to_router.ps1 -RouterHost 192.168.1.1
```

## Авторизация

UI использует логин и пароль от веб-интерфейса Keenetic.

Разделение такое:

- вход в UI  
  логин и пароль от Keenetic web UI (сессия проксируется на `http://<router>/auth`)
- deploy-скрипты  
  SSH-доступ через `ROUTER_SSH_USER` и `ROUTER_SSH_PASSWORD`

## Что считать нормальным runtime

- Устройства находятся в политике `xkeen` (Keenetic UI → «Приоритеты подключений»).
- Есть hook `PREROUTING → xkeen` в table `nat` (для TCP).
- В mangle-PREROUTING в **самом конце** висит TPROXY-jump для UDP-route (проверяет `xkeen_udp_route` ipset).
- `xray` слушает `:61219` (dokodemo TCP), `:61080` (socks-in TCP+UDP), `:62640` (SS-relay TCP+UDP).
- `sing-box` слушает `:61221` (TPROXY UDP), `:61225` (mixed для hy2 bridge).
- socks-in inbound имеет `settings.ip` = LAN-IP роутера (автоподставляется при apply/restart).
- Локалка, discovery и RFC1918-подсети идут через `RETURN` до `xray`.

## Базовая проверка после apply

- `xray` запущен: `netstat -lnptu | grep ':61219 '`
- `sing-box` запущен: `netstat -lnpu | grep ':61221 '`
- Цепочка `xkeen` существует: `iptables -t nat -S xkeen`
- `PREROUTING -> xkeen` existует: `iptables -t nat -S PREROUTING | grep xkeen`
- UI открывается на `<router>:<port>/`

## Диагностика внутренностей

- `tail -f /opt/var/log/xkeen-selfheal.log` — лог selfheal (`repair start/done`, socks-in ip changes, DNS resolve failures)
- `tail -f /opt/var/log/xkeen-health.log` — health snapshot (fd, mem, conntrack, VPN sockets, backoff-состояния)
- `tail -f /opt/var/log/xray-manual.log` — xray stdout/stderr + runtime warnings (`iptables_fail`, `ipset_add_fail`, `lock_stale_cleanup`, `resolve_ipv4_none`)
- `ls /tmp/xkeen-selfheal.lock/` — если файл `pid` присутствует и указывает на живой selfheal — apply/rebuild сейчас идёт
- `ls /tmp/xkeen-dns-cache/ | wc -l` — размер DNS-кэша (positive TTL 15 мин, negative TTL 2 мин)
- `cat /tmp/xkeen-xray-start-backoff.ts` — если файл есть, xray в backoff (не рестартится до этого timestamp)
