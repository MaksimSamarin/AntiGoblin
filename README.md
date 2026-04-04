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
- `iptables` для перехвата только тех `TCP`-направлений, которые отмечены как `REDIRECT` в правилах UI
- `xray` для маршрутизации в `vless-reality` или `direct`

Текущая живая модель runtime:

- `TCP` устройств из `xkeen` идет через `xray` только для UI-групп с типом `REDIRECT`
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
- [docs/runbooks/deploy-from-zero.md](docs/runbooks/deploy-from-zero.md)  
  Развертывание с нуля одной командой.

## Развертывание

Базовый публичный сценарий теперь один:

```powershell
$env:ROUTER_SSH_PASSWORD = 'пароль-ssh-доступа'
.\scripts\xkeen\bootstrap_antigoblin_router.ps1 -RouterHost 192.168.1.1
```

Что делает bootstrap:

- подключается к роутеру по `SSH`
- проверяет `Entware/OPKG` в `/opt`
- ставит нужные пакеты Entware
- создает UI-видимую политику Keenetic `xkeen`, если ее еще нет
- раскладывает базовые sample-конфиги `xray`
- выкатывает UI и backend
- запускает `AntiGoblin` на `:8899`

После этого открой:

```text
http://192.168.1.1:8899/
```

Для входа в UI используются логин и пароль от web-интерфейса `Keenetic`.

После bootstrap вручную остается только:

- открыть UI `AntiGoblin`
- заполнить `VLESS Reality`
- включить нужные routing-группы
- назначить нужные устройства в политику `xkeen` в Keenetic UI

Инварианты проекта:

- `AntiGoblin` имеет право трогать только устройства из политики `xkeen`
- любые другие политики Keenetic, например `no_vpn`, не должны попадать в `xray`
- bootstrap создает `xkeen` как дополнительную политику вида `Policy42+`, чтобы она была видна в Keenetic UI

Полная пошаговая инструкция:

- [docs/runbooks/deploy-from-zero.md](docs/runbooks/deploy-from-zero.md)

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

Bypass собирается из двух источников:

- hardcoded runtime-файлы:
  - `/opt/share/xkeen-manager/runtime/bypass-domains.txt`
  - `/opt/share/xkeen-manager/runtime/bypass-cidrs.txt`
- UI-группы с типом трафика `Bypass`

Все эти направления попадают в runtime `xkeen_bypass` и обходят `xray` через `RETURN`.

## Правила проекта

- Проект должен оставаться generic для любого совместимого Keenetic.
- В репозиторий нельзя класть live-снапшоты роутера, секреты и личные черновики.
- После каждого подтвержденного бага и решения нужно обновлять [docs/troubleshooting.md](docs/troubleshooting.md).
- После изменения архитектуры нужно обновлять:
  - [README.md](README.md)
  - [docs/architecture.md](docs/architecture.md)
  - [docs/project-map.md](docs/project-map.md)
  - [docs/PROMPT.md](docs/PROMPT.md)
