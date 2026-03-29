# Чеклист отладки Codex Compact

`PC/LAN client -> Keenetic -> HydraRoute/ipset -> Keenetic proxy routing -> xray SOCKS -> VLESS -> chatgpt.com`

Симптом:

- ошибка `stream disconnected before completion`;
- обычно проявляется через 1-2 минуты;
- тот же VLESS-сервер работает через `v2rayN` на ПК.

## Цель

Понять, на каком уровне ломается путь:

- на клиенте;
- в policy routing Keenetic;
- в `xray`;
- в `conntrack`/`iptables`/`ipset`;
- на уровне `MTU/MSS`.

## 1. Базовая фиксация состояния

```bash
date
ps | grep -E 'xray|hydra'
netstat -tlnp | grep 1300
ipset list HydraRoute | head -30
iptables -t mangle -L -n -v
tail -n 50 /opt/var/log/LOGhrneo.log
```

Ожидания:

- `xray` запущен и слушает `1300`;
- `ipset HydraRoute` существует;
- в `mangle`-правилах есть растущие счетчики на интересующем трафике.

## 2. Проверка, что `chatgpt.com` действительно идет через HydraRoute

На роутере:

```bash
grep -n 'chatgpt.com' /opt/etc/HydraRoute/domain.conf
tail -f /opt/var/log/LOGhrneo.log
ipset list HydraRoute | grep -E '8\\.|151\\.|199\\.'
```

Ожидания:

- домен `chatgpt.com` или связанные адреса реально попадают в `HydraRoute`;
- соответствующие IP появляются в `ipset`.

## 3. Включение временного лога xray

Перед тестом:

```bash
cp /opt/etc/xray/vpngroup_config.json /opt/etc/xray/vpngroup_config.json.bak-codex
sed -i 's/"loglevel": "warning"/"loglevel": "info"/' /opt/etc/xray/vpngroup_config.json
killall xray
```

Проверка:

```bash
tail -f /opt/var/log/xray-error.log
tail -f /opt/var/log/xray-access.log
```

Ищем:

- `sniffed domain: chatgpt.com`;
- `taking detour`;
- `tunneling request`;
- transport/session ошибки;
- `broken pipe`, если они появятся.

## 4. Поймать момент обрыва

Во время запуска `compact`:

```bash
watch -n 1 "conntrack -L | grep 192.168.2.106 | grep 443 | head"
```

Дополнительно:

```bash
netstat -tanp | grep ':1300'
```

Смысл:

- понять, кто первым закрывает соединение;
- увидеть, долго ли живет поток;
- отделить падение `xray` от закрытия входящего SOCKS-сокета.

## 5. Проверка conntrack и таймаутов

```bash
cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_close_wait
cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_fin_wait
```

Смысл:

- исключить слишком агрессивные системные TCP-timeout.

## 6. Проверка MSS/MTU

Проверка интерфейсов:

```bash
ip link
```

Временный диагностический тест:

```bash
iptables -t mangle -A FORWARD -o t2s0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

Откат:

```bash
iptables -t mangle -D FORWARD -o t2s0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

Смысл:

- проверить гипотезу про слишком крупные TCP-сегменты по пути.

## 7. Сравнение с рабочим сценарием

Что уже важно было сравнить:

- тот же VLESS-сервер через `v2rayN` на ПК работает;
- generic long-lived HTTPS через VPN надо проверить отдельно;
- поведение на роутере и на ПК различается именно моделью доставки трафика.

## 8. Проверка счетчиков iptables во время теста

```bash
iptables -t mangle -L -n -v
iptables -t nat -L -n -v
```

Смысл:

- убедиться, что трафик реально проходит через ожидаемые цепочки;
- увидеть, не перестает ли матчиться правило в момент обрыва.

## 9. Минимальная развилка гипотез

Если:

- `xray` не падает;
- `chatgpt.com` реально туннелируется;
- обычный long-lived HTTPS работает;
- а `compact` все равно рвется;

то наиболее вероятны:

- проблема в слое доставки трафика до `xray`;
- проблема в `hev-socks5-tunnel` / built-in proxy-client path Keenetic;
- чувствительность `Codex compact` к специфическому streaming/reconnect-паттерну.

## 10. Что сохранить после прогона

Сохранить:

- хвосты `xray-error.log` и `xray-access.log`;
- вывод `conntrack`;
- счетчики `iptables`;
- текущее содержимое `/var/run/proxy-cfg-t2s0`, если используется старый путь.

## 11. Самый полезный следующий шаг после этого чек-листа

Если старый путь все еще используется и виден `hev-socks5-tunnel`, самый полезный следующий шаг — проверить его runtime-конфиг и таймауты, особенно `read-write-timeout`.
