# Codex Compact Debug Checklist

Этот чек-лист нужен, чтобы локализовать обрыв `OpenAI Codex compact` в цепочке:

`PC/LAN client -> Keenetic -> HydraRoute/ipset -> Keenetic proxy routing -> xray SOCKS -> VLESS -> chatgpt.com`

Симптом:
- ошибка `stream disconnected before completion`
- обычно проявляется через 1-2 минуты
- тот же VLESS-сервер работает через `v2rayN` на ПК

## Цель

Понять, где именно рвется long-lived соединение:
- на клиенте
- в policy routing Keenetic
- в `xray`
- в `conntrack`/iptables/ipset
- на уровне `MTU/MSS`

## 1. Базовая фиксация состояния

Подключиться:

```bash
ssh root@192.168.2.1
```

Сразу записать базовый контекст:

```bash
uname -a
date
uptime
ip addr show
ip rule show
iptables -t mangle -L -n -v
ipset list HydraRoute | head -50
ps | grep -E 'xray|hydra'
netstat -tlnp | grep 1300
```

Что смотрим:
- `xray` запущен и слушает `1300`
- ipset `HydraRoute` существует
- в mangle-правилах есть счетчики, которые растут на интересующем трафике

## 2. Проверка, что chatgpt.com действительно идет через HydraRoute

Во время запуска проблемного запроса посмотреть лог HydraRoute:

```bash
tail -f /opt/var/log/LOGhrneo.log
```

Параллельно проверить наличие нужных IP в ipset:

```bash
ipset list HydraRoute | grep -E '8\.6\.|8\.47\.|151\.101\.|146\.75\.'
```

Что смотрим:
- домен `chatgpt.com` или связанные с ним адреса реально попадают в HydraRoute
- IP появляются в ipset до начала проблемного long-lived запроса

## 3. Включение временного лога xray

Перед этим сохранить текущие настройки логирования из `/opt/etc/xray`.

Временно включить более подробный лог:

```bash
grep -R "\"log\"" /opt/etc/xray
```

Если логирование выключено, на время диагностики включить `loglevel: "info"` или `debug`, затем перезапустить:

```bash
killall xray
xray run -confdir /opt/etc/xray > /opt/var/log/xray-stdout.log 2> /opt/var/log/xray-stderr.log &
```

Смотреть лог вживую:

```bash
tail -f /opt/var/log/xray-stderr.log
```

Что смотрим:
- ошибки transport/session/timeout
- сообщения о закрытии соединения
- рестарт процесса
- падения по памяти или внутренние ошибки xray

## 4. Поймать момент обрыва

Запустить проблемный запрос с клиента и одновременно смотреть:

```bash
tail -f /opt/var/log/LOGhrneo.log
```

```bash
tail -f /opt/var/log/xray-stderr.log
```

```bash
watch -n 2 "ps | grep xray"
```

Если `watch` отсутствует, то просто повторять:

```bash
ps | grep xray
```

Что фиксируем:
- точное время старта запроса
- точное время обрыва
- были ли в эту секунду сообщения в `HydraRoute`
- были ли в эту секунду сообщения в `xray`
- продолжал ли жить процесс `xray`

## 5. Проверка conntrack и таймаутов

Посмотреть системные таймауты conntrack:

```bash
sysctl -a 2>/dev/null | grep conntrack
```

Если доступен модуль статистики:

```bash
cat /proc/net/nf_conntrack | grep 443 | head
```

или:

```bash
conntrack -L | grep 443
```

Что смотрим:
- не исчезает ли запись соединения слишком рано
- нет ли признаков aggressive timeout
- не очищает ли что-то таблицу состояний

## 6. Проверка MSS/MTU

Снять MTU интерфейсов:

```bash
ip link show
ifconfig 2>/dev/null
```

Проверить правила TCPMSS:

```bash
iptables -t mangle -S | grep -i mss
iptables -t mangle -L -n -v | grep -i mss
```

Что смотрим:
- есть ли MSS clamping
- одинаково ли выглядит путь для LAN и WAN
- нет ли слишком большого MTU на одном из участков цепочки

Практический признак:
- если короткие запросы работают, а длинные или потоковые отваливаются, проблема часто в `MTU/MSS` или таймаутах потока

## 7. Сравнение с рабочим сценарием

Нужно сравнить два кейса:

1. `chatgpt.com` через роутерную схему `HydraRoute -> xray -> VLESS`
2. тот же запрос через `v2rayN` на ПК

Что сравнить:
- время жизни соединения
- размер/длительность запроса
- есть ли обрыв только на роутерном маршруте

Если только роутерный путь ломается, это резко снижает вероятность проблемы на стороне самого VLESS-сервера.

## 8. Проверка счетчиков iptables во время теста

До теста:

```bash
iptables -t mangle -L -n -v
```

После воспроизведения:

```bash
iptables -t mangle -L -n -v
```

Что смотрим:
- растут ли нужные счетчики на маркировке
- не происходит ли неожиданного обхода нужной цепочки

## 9. Минимальная гипотезная развилка

Если:
- `HydraRoute` отрабатывает нормально
- IP попадает в `ipset`
- счетчики iptables растут
- `xray` не падает
- но long-lived stream все равно рвется

то первыми проверяем:
- `MTU/MSS`
- HTTP/2-специфичное поведение
- router-side timeout/conntrack

Если:
- в момент сбоя есть ошибки в `xray-stderr.log`

то основной фокус:
- параметры `xray`
- transport/session timeout
- конкретные особенности SOCKS -> VLESS path

Если:
- `xray` перезапускается или исчезает процесс

то основной фокус:
- crash/oom
- бинарная совместимость
- нехватка памяти или файловых дескрипторов

## 10. Что сохранить после прогона

После одной полноценной неудачной попытки сохранить:

- время начала и конца теста
- кусок `LOGhrneo.log`
- кусок `xray-stderr.log`
- вывод `iptables -t mangle -L -n -v`
- вывод `ipset list HydraRoute | head -50`
- вывод `ip rule show`
- вывод `ps | grep -E 'xray|hydra'`
- вывод `ip link show`
- вывод правил `iptables -t mangle -S | grep -i mss`

## 11. Самый полезный следующий шаг после этого чек-листа

Если после прогона станет видно, что соединение живет, но поток обрывается без падения `xray`, следующим шагом стоит сделать отдельный эксперимент:

- один тест с максимальным логированием `xray`
- один тест с фокусом только на `MTU/MSS`
- один контрольный тест через `v2rayN` с тем же сценарием

Так будет проще отделить сетевую проблему роутера от проблемы конфигурации `xray`.
