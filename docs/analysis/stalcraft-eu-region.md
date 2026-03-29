# Проблема: Stalcraft определяет EU регион

## Симптом

При запуске игры лаунчер определяет EU регион вместо RU, хотя пользователь находится в России.

## Как работает определение региона

Stalcraft использует CDN Fastly для первого соединения. Fastly — это сеть серверов по всему миру: когда игра подключается к `stalcraft.net`, она попадает на ближайший сервер Fastly. Fastly видит IP входящего соединения и сообщает игре регион.

Если соединение пришло с европейского IP (например, через VPN-сервер в Европе) → Fastly говорит "EU" → игра выбирает EU регион.

## Почему Stalcraft шёл через европейский VPN

Stalcraft **не добавлен** в список доменов HydraRoute. Казалось бы, он должен идти напрямую.

Но `stalcraft.net` и `youtube.com` резолвятся в **одинаковые IP-адреса** Fastly:
- `8.6.112.0` — оба домена
- `8.47.69.0` — оба домена

Оба сайта арендуют CDN у Fastly и получают один и тот же адрес склада.

Когда HydraRoute резолвил youtube.com → получал `8.6.112.0` → добавлял в ipset → помечал весь трафик на этот IP как "везти через VPN". Stalcraft приходил на тот же IP → автоматически уходил через VPN → европейский сервер → EU регион.

## Почему domain-правило в xray не спасало

В xray было правило: `stalcraft.net → direct`. Но оно не срабатывало.

Причина: Keenetic передаёт трафик в xray через интерфейс t2s0 с голым **IP-адресом** в SOCKS5, без доменного имени. xray видел `8.6.112.0:443` и не знал, что это Stalcraft, — domain-правило просто не с чем было сопоставить.

## Неудачная попытка фикса

Добавили IP-правило в xray: `8.6.112.0/21 → direct`.

Сломало ChatGPT — он тоже живёт на тех же Fastly IP. ChatGPT пошёл напрямую → заблокирован в России.

## Финальное решение — TLS SNI sniffing

Включили `sniffing` на SOCKS-inbound в xray:

```json
"sniffing": {
  "enabled": true,
  "destOverride": ["http", "tls"],
  "routeOnly": true
}
```

Каждое HTTPS-соединение начинается с TLS-рукопожатия, в котором клиент открытым текстом указывает домен назначения — это называется **SNI** (Server Name Indication). xray читает SNI прямо из трафика, даже если SOCKS5 передал только IP.

Теперь:
- Stalcraft подключается к `8.6.112.0:443`, SNI = `stalcraft.net` → domain-правило срабатывает → direct → российский IP → RU регион ✓
- ChatGPT подключается к `8.6.112.0:443`, SNI = `chatgpt.com` → нет direct-правила → VLESS → работает ✓

## Итоговый routing_config.json

```json
{
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
      {
        "type": "field",
        "domain": ["stalcraft.net", "exbo.net", "cdn77.org"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["<SOCKS_USERNAME>"],
        "outboundTag": "<SOCKS_USERNAME>"
      }
    ]
  }
}
```
