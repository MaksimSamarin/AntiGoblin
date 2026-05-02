# Runbook: AntiGoblin UI

## Что это

`AntiGoblin` — router-hosted UI для управления:

- профилями
- routing-группами
- `VLESS Reality`
- сгенерированным `xray`-конфигом на роутере

## Файлы на роутере

UI state:

- `/opt/share/xkeen-manager/xkeen-ui-state.json`

Сгенерированные файлы `xray`:

- `/opt/etc/xray/configs/04_outbounds.json`
- `/opt/etc/xray/configs/05_routing.json`

Backend:

- `/opt/share/xkeen-manager/api/routing.cgi`
- `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`
- `/opt/share/xkeen-manager/api/xkeen-runtime.sh`

## Действия в UI

### `Сохранить`

Пишет только UI state на роутере.

### `Сохранить и применить`

Делает все сразу:

- сохраняет state
- генерирует `04_outbounds.json`
- генерирует `05_routing.json`
- валидирует `xray`-конфиг
- делает backup
- перезапускает `xray`

### `Рестарт`

Чинит только runtime:

- цепочку `xkeen`
- hook `PREROUTING -> xkeen`
- runtime-наборы `xkeen_bypass` и `xkeen_udp_route`
- процесс `xray`, если это нужно

State при этом заново не генерирует.

## Деплой

### Полный стек

```powershell
$env:ROUTER_SSH_PASSWORD = 'пароль-ssh-роутера'
$env:ROUTER_SSH_USER = 'root' # опционально
.\scripts\xkeen\deploy_xkeen_manager_stack_to_router.ps1 -RouterHost 192.168.1.1
```

Открыть:

```text
http://192.168.1.1:8899/
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
  логин и пароль от Keenetic web UI
- deploy-скрипты  
  SSH-доступ через `ROUTER_SSH_USER` и `ROUTER_SSH_PASSWORD`

## Что считать нормальным runtime

Нормальная живая схема:

- устройства находятся в политике `xkeen`
- есть hook `PREROUTING` для mark, найденного у политики `description xkeen`
- `TCP` уходит в `61219`
- `UDP` идет напрямую, кроме UI-групп с включенным `UDP через VPN`
- локалка и discovery идут через `RETURN`

## Базовая проверка после apply

- `xray` запущен
- порт `61219` слушается
- цепочка `xkeen` существует
- `PREROUTING -> xkeen` существует
- UI на `:8899` открывается
