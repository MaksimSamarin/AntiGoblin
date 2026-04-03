# AntiGoblin

`AntiGoblin` — это панель управления для `Keenetic + Entware + XKeen/xray`, которая живет на самом роутере.

Проект дает понятный рабочий сценарий:

1. Развернуть стек на Keenetic.
2. Открыть UI.
3. Заполнить `VLESS Reality`.
4. Создать группы маршрутизации.
5. Нажать `Сохранить и применить`.

После этого роутер использует:

- политику Keenetic `xkeen` для выбора устройств
- `iptables` для перехвата `TCP` трафика этой политики
- `xray` для маршрутизации в `vless-reality` или `direct`

Текущая живая модель runtime:

- `TCP` устройств из `xkeen` идет через `xray`
- `UDP` идет напрямую
- локалка и discovery обходят `xray` через `RETURN`

## Структура проекта

- [docs/architecture.md](docs/architecture.md)  
  Текущая архитектура на Keenetic и Entware.
- [docs/project-map.md](docs/project-map.md)  
  Где лежит код, скрипты, конфиги и документация.
- [docs/PROMPT.md](docs/PROMPT.md)  
  Рабочий prompt для разработчика проекта.
- [docs/troubleshooting.md](docs/troubleshooting.md)  
  Подтвержденные баги, причины и рабочие решения.
- [docs/runbooks/xkeen-manager-ui.md](docs/runbooks/xkeen-manager-ui.md)  
  Как пользоваться UI и как выкатывать проект.

## Развертывание

Требования:

- Keenetic с `Entware`, смонтированным в `/opt`
- установленный в Entware `xray`
- PowerShell на рабочей машине
- модуль PowerShell `Posh-SSH`
- переменная окружения `ROUTER_SSH_PASSWORD`
- опционально `ROUTER_SSH_USER`, по умолчанию `root`

Полный деплой:

```powershell
$env:ROUTER_SSH_PASSWORD = 'пароль-ssh-роутера'
# опционально
$env:ROUTER_SSH_USER = 'root'
.\scripts\xkeen\deploy_xkeen_manager_stack_to_router.ps1 -RouterHost 192.168.1.1
```

Открыть UI:

```text
http://192.168.1.1:8899/
```

Для входа в UI используются логин и пароль от веб-интерфейса Keenetic.

## Источник истины

Единственный источник истины для UI:

- `/opt/share/xkeen-manager/xkeen-ui-state.json`

Из него backend генерирует:

- `/opt/etc/xray/configs/04_outbounds.json`
- `/opt/etc/xray/configs/05_routing.json`

## Runtime-файлы

UI и backend на роутере:

- `/opt/share/xkeen-manager/`
- `/opt/share/xkeen-manager/api/routing.cgi`
- `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`

Runtime bypass-списки:

- `/opt/share/xkeen-manager/runtime/bypass-domains.txt`
- `/opt/share/xkeen-manager/runtime/bypass-cidrs.txt`

## Правила проекта

- Проект должен оставаться generic для любого совместимого Keenetic.
- В репозиторий нельзя класть live-снапшоты роутера, секреты и личные черновики.
- После каждого подтвержденного бага и решения нужно обновлять [docs/troubleshooting.md](docs/troubleshooting.md).
- После изменения архитектуры нужно обновлять:
  - [README.md](README.md)
  - [docs/architecture.md](docs/architecture.md)
  - [docs/project-map.md](docs/project-map.md)
  - [docs/PROMPT.md](docs/PROMPT.md)
