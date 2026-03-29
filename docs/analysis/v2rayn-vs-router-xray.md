# Сравнение v2rayN и xray на роутере

## Назначение

Эта заметка сравнивает известный рабочий путь на ПК с роутерным путем, который ломался на `Codex compact`.

## Рабочий клиент на ПК

Путь:

- `C:\Users\Home-PC\Desktop\v2rayN-windows-64`

Обнаруженные компоненты:

- GUI: `v2rayN V7.18.0 X64`;
- core: `Xray 26.2.4 (go1.25.6 windows/amd64)`.

Важные наблюдения из `guiNConfig.json`:

- `TunModeItem.EnableTun = true`;
- `TunModeItem.AutoRoute = true`;
- `TunModeItem.StrictRoute = true`;
- `TunModeItem.Stack = "gvisor"`;
- `TunModeItem.Mtu = 9000`;
- локальный SOCKS inbound-порт: `10808`;
- sniffing на inbound включен;
- `RouteOnly = false`;
- `MuxEnabled = false`;
- `Loglevel = "warning"`;
- `DomainStrategy = "AsIs"`;
- `EnableIPv6Address = false`.

Активный выбранный профиль из `guiNDB.db` (`IndexId = 5076900947224219232`):

- remarks: `vdpsina-samara_pc`;
- address: `<VLESS_SERVER_HOST>`;
- port: `<VLESS_SERVER_PORT>`;
- protocol family: `VLESS`;
- network: `tcp`;
- stream security: `reality`;
- flow: `xtls-rprx-vision`;
- security: `none`;
- fingerprint: `random`;
- SNI: `<REALITY_SERVER_NAME>`;
- public key: тот же, что у роутерного профиля;
- shortId: тот же, что у роутерного профиля;
- user ID: тот же, что у роутерного профиля.

## Клиент на роутере

Наблюдавшееся окружение роутера:

- router xray: `26.2.6 (go1.25.7 linux/arm64)`;
- inbound: SOCKS на `1300`;
- sniffing включен;
- `routeOnly = true`;
- путь доставки трафика:
  - LAN-клиент;
  - HydraRoute/ipset;
  - Keenetic fwmark / proxy client;
  - `t2s0`;
  - SOCKS inbound на router xray;
  - VLESS outbound.

## Ключевые различия

### 1. Модель доставки

ПК:

- `v2rayN` использует TUN-режим со стеком `gvisor` и strict routing.

Роутер:

- трафик подается в SOCKS inbound через proxy routing Keenetic;
- `xray` не работает с локальным TUN-стеком.

Это было самым сильным архитектурным отличием.

### 2. Режим inbound sniffing

ПК:

- sniffing включен;
- `RouteOnly = false`.

Роутер:

- sniffing включен;
- `routeOnly = true`.

Это могло влиять на то, как внутри применяются destination metadata.

Обновление после live-теста от `2026-03-29`:

- роутер временно переключался с `routeOnly = true` на `routeOnly = false`;
- `Codex compact` все равно падал с той же ошибкой;
- поэтому это различие теперь считается менее вероятной корневой причиной.

### 3. Стратегия доменов

ПК:

- `DomainStrategy = "AsIs"`.

Роутер:

- routing-конфиг использует `IPOnDemand`.

Это меньшее, но все же заметное отличие в работе с доменами и IP.

### 4. Поведение IPv6

ПК:

- `EnableIPv6Address = false`.

Роутер:

- логи `HydraRoute` и состояние системы показывали смешанную работу с IPv4 и IPv6 DNS;
- реально наблюдавшийся путь `chatgpt.com compact` был в основном через IPv4 Fastly IP.

### 5. Runtime и платформа

ПК:

- Windows + `v2rayN` + `Xray 26.2.4`.

Роутер:

- Keenetic/Entware + `Xray 26.2.6`.

Разница версий невелика. Архитектура и модель подачи трафика были заметно важнее.

### 6. Паритет outbound-профиля

Активный профиль на ПК и outbound на роутере по сути совпадали:

- тот же host;
- тот же port;
- тот же UUID;
- тот же `flow`;
- те же параметры `Reality`;
- та же политика fingerprint.

Это делало сам outbound-сервер и профиль гораздо менее вероятной корневой причиной.

## Текущая интерпретация

Удаленный VLESS-сервер маловероятно был корнем проблемы, потому что через `v2rayN` на ПК он работал.

Самые вероятные причины на тот момент были такими:

- путь доставки Keenetic в SOCKS inbound;
- различие между TUN-mode клиентом и поведением роутерного SOCKS-inbound;
- чувствительность `Codex compact` именно к такой модели соединения, даже если обычный долгий HTTPS работал.

## Новое сильное подтверждение из live-мониторинга сокетов

Мониторинг роутера показал, что локальный процесс, который кормит SOCKS у `xray`, это:

- `hev-socks5-tu`.

Наблюдаемая связь сокетов:

- `hev-socks5-tu -> 192.168.2.1:1300`;
- `xray <- :1300`.

Наблюдаемое поведение при закрытии:

- сторона `xray` переходила в `CLOSE_WAIT`;
- сторона пира переходила в `FIN_WAIT2`.

Текущая интерпретация:

- inbound SOCKS, похоже, закрывался локальным слоем доставки раньше, чем `xray` сам инициировал закрытие;
- это делало `hev-socks5-tu` / Keenetic proxy delivery гораздо более подозрительными, чем outbound-профиль VLESS.

## Самые полезные следующие проверки

1. сравнить, меняет ли что-то `RouteOnly = false` на роутере;
2. сравнить `domainStrategy` на роутере с `AsIs` на ПК;
3. проверить, зависит ли `Codex compact` от специфического HTTP/2 или reconnect-паттерна, который переживает TUN, но не SOCKS-injected routing.
