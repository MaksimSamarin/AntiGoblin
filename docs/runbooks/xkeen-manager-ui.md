# XKeen Manager UI

## Что Это

Локальный MVP-интерфейс для управления правилами `XKeen/xray` без `HydraRoute`.

Цель:

- хранить группы в одном месте;
- редактировать домены и CIDR через простой UI;
- генерировать готовый `05_routing.json` для `XKeen/xray`;
- постепенно уйти от гибридной схемы `HydraRoute -> XKeen`.

## Что Уже Умеет

- редактировать `direct`-домены;
- создавать группы;
- задавать для группы:
  - имя;
  - комментарий;
  - `outboundTag`;
  - список доменов;
  - список CIDR;
- импортировать существующий `routing.json`;
- экспортировать `state.json`;
- экспортировать итоговый `05_routing.json`.
- показывать готовую `apply`-команду для накатки файла на роутер.
- при первом открытии загружать боевой снапшот `routing.json`, заранее снятый с роутера.

## Что Пока Не Делает

- не пишет файлы на роутер напрямую;
- не применяет конфиг автоматически;
- не редактирует `04_outbounds.json`;
- не заменяет пока все возможности `HydraRoute`.

Это намеренно маленький MVP.

## Как Запустить

```powershell
.\scripts\xkeen\start_xkeen_manager_ui.ps1
```

По умолчанию UI откроется на:

```text
http://127.0.0.1:8765/
```

## Как Применить Сгенерированный JSON

1. В UI нажать `Скачать routing.json`.
2. В папке с загруженным файлом выполнить:

```powershell
.\scripts\xkeen\apply_xkeen_routing_file.ps1 -RoutingFile .\05_routing.generated.json
```

Скрипт:

- валидирует JSON локально;
- делает backup текущего `/opt/etc/xray/configs/05_routing.json`;
- загружает новый файл на роутер;
- вручную перезапускает `xray`;
- проверяет, что listeners `61219` и `61220` поднялись.

## Где Лежат Файлы

- UI:
  - [index.html](/e:/Домашние проекты/VPN на роутере/ui/xkeen-manager/index.html)
  - [app.js](/e:/Домашние проекты/VPN на роутере/ui/xkeen-manager/app.js)
  - [styles.css](/e:/Домашние проекты/VPN на роутере/ui/xkeen-manager/styles.css)
- live snapshot для автозагрузки:
  - [router-live-routing.json](/e:/Домашние проекты/VPN на роутере/ui/xkeen-manager/router-live-routing.json)
- sample state:
  - [xkeen-ui-state.sample.json](/e:/Домашние проекты/VPN на роутере/configs/xkeen/xkeen-ui-state.sample.json)

## Ближайший Следующий Шаг

Если MVP приживется, следующая разумная эволюция такая:

1. хранить не только UI-state, но и нормализованный project source of truth;
2. добавить генерацию не только `05_routing.json`, но и сопутствующего набора файлов;
3. добавить безопасную кнопку `stage/apply` через существующие PowerShell-скрипты.
