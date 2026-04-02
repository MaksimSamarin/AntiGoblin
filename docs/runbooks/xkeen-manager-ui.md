# AntiGoblin UI

## Что это

Локальная и роутерная панель для управления `XKeen/xray` без ручного редактирования `04_outbounds.json` и `05_routing.json`.

Источник истины:

- `/opt/share/xkeen-manager/xkeen-ui-state.json`

Боевые файлы `xray`:

- `/opt/etc/xray/configs/04_outbounds.json`
- `/opt/etc/xray/configs/05_routing.json`

Backend:

- `/opt/share/xkeen-manager/api/routing.cgi`
- `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`

## Как работает

- UI читает и сохраняет `xkeen-ui-state.json`
- `Сохранить` пишет только state
- `Сохранить и применить`:
  - сохраняет state
  - генерирует `04_outbounds.json`
  - генерирует `05_routing.json`
  - делает backup боевых файлов
  - перезапускает `xray`
- `Рестарт` чинит runtime:
  - `xkeen`
  - hook `PREROUTING -> xkeen`
  - процесс `xray`

## Локальный запуск

```powershell
.\scripts\xkeen\start_xkeen_manager_ui.ps1
```

Адрес:

```text
http://127.0.0.1:8765/
```

## Развертывание на роутере

```powershell
$env:ROUTER_SSH_PASSWORD='keenetic'
.\scripts\xkeen\deploy_xkeen_manager_stack_to_router.ps1
```

Адрес:

```text
http://192.168.2.1:8899/
```

## Проверки

После успешного применения `xray` должен слушать:

- `61219/tcp`
- `61220/udp`

Self-heal пишет лог сюда:

- `/opt/var/log/xkeen-selfheal.log`
