# XKeen Manager UI

## Что Это

Локальная и роутерная панель для управления `XKeen/xray` без ручного редактирования `04_outbounds.json` и `05_routing.json`.

Источник истины для панели:
- `/opt/share/xkeen-manager/xkeen-ui-state.json`

Боевые файлы `xray`:
- `/opt/etc/xray/configs/04_outbounds.json`
- `/opt/etc/xray/configs/05_routing.json`

Backend:
- `/opt/share/xkeen-manager/api/routing.cgi`
- `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`

Веб-сервер:
- `uhttpd` на `8899`

## Как Работает

- UI читает и сохраняет `xkeen-ui-state.json`
- `Сохранить` пишет только `state`
- `Сохранить и применить`:
  - сохраняет `state`
  - генерирует `04_outbounds.json`
  - генерирует `05_routing.json`
  - делает backup боевых файлов
  - перезапускает `xray`
- `Восстановить` чинит runtime:
  - `xkeen`
  - `xkeen_udp`
  - `ip rule`
  - процесс `xray`

## Кнопки

- `Импорт`
  Загружает сохраненный `state` из файла.

- `Скачать`
  Сохраняет текущий `state` в файл.

- `Сохранить`
  Сохраняет только профиль и группы на роутере, без применения в `xray`.

- `Сохранить и применить`
  Сохраняет `state` и применяет его в боевые конфиги `xray`.

- `Восстановить`
  Восстанавливает runtime-хуки и процесс `xray`, если Keenetic пересобрал `iptables`.

## Локальный Запуск

```powershell
.\scripts\xkeen\start_xkeen_manager_ui.ps1
```

Адрес:

```text
http://127.0.0.1:8765/
```

## Развертывание На Роутере

Полный стек одной командой:

```powershell
$env:ROUTER_SSH_PASSWORD='keenetic'
.\scripts\xkeen\deploy_xkeen_manager_stack_to_router.ps1
```

Или по частям:

```powershell
$env:ROUTER_SSH_PASSWORD='keenetic'
.\scripts\xkeen\deploy_xkeen_manager_ui_to_router.ps1
.\scripts\xkeen\deploy_xkeen_manager_backend_to_router.ps1
.\scripts\xkeen\start_xkeen_manager_ui_router.ps1
```

Адрес:

```text
http://192.168.2.1:8899/
```

Остановить:

```powershell
$env:ROUTER_SSH_PASSWORD='keenetic'
.\scripts\xkeen\stop_xkeen_manager_ui_router.ps1
```

## Проверки После Применения

После успешного применения `xray` должен слушать:

- `61219/tcp`
- `61220/udp`

Runtime self-heal пишет лог сюда:

- `/opt/var/log/xkeen-selfheal.log`
