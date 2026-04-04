# Развертывание с нуля

Цель: выполнить одну команду на рабочем ПК и получить на роутере установленный `AntiGoblin`, базовый `xray`-набор и рабочий UI.

## Что делает bootstrap

Скрипт:

- при необходимости ставит `Posh-SSH` на рабочий ПК
- подключается к Keenetic по `SSH`
- проверяет наличие `Entware/OPKG` в `/opt`
- создает каталоги проекта
- ставит нужные пакеты Entware:
  - `xray`
  - `uhttpd_kn`
  - `jq`
  - `gawk`
  - `coreutils-base64`
  - `net-tools-netstat`
  - `cron`
- создает политику Keenetic `xkeen`, если ее еще нет
- раскладывает базовые sample-конфиги:
  - `01_log.json`
  - `03_inbounds.json`
  - `04_outbounds.json`
  - `05_routing.json`
  - `xkeen-ui-state.json`
- выкатывает UI и backend
- запускает web UI на `:8899`
- ставит init-скрипт `S26antigoblin` для автоподъема UI после reboot
- ставит hook-скрипты для восстановления после возврата `/opt` и USB-событий

Важно:

- bootstrap не трогает уже существующие конфиги по умолчанию
- чтобы перезаписать их sample-версией, используй флаг `-ForceSeedConfigs`

## Одна команда

```powershell
$env:ROUTER_SSH_PASSWORD = 'пароль-ssh-доступа'
.\scripts\xkeen\bootstrap_antigoblin_router.ps1 -RouterHost 192.168.1.1
```

Если `SSH`-пользователь не `root`:

```powershell
$env:ROUTER_SSH_PASSWORD = 'пароль-ssh-доступа'
$env:ROUTER_SSH_USER = 'root'
.\scripts\xkeen\bootstrap_antigoblin_router.ps1 -RouterHost 192.168.1.1
```

После этого открой:

```text
http://192.168.1.1:8899/
```

Для входа используются логин и пароль от web-интерфейса `Keenetic`.

После bootstrap вручную остается только:

- открыть `AntiGoblin`
- заполнить `VLESS Reality`
- включить нужные routing-группы
- перевести нужные устройства в политику `xkeen` в web-интерфейсе Keenetic

## Если bootstrap остановился

Самая частая причина:

- на роутере нет `Entware/OPKG` в `/opt`

Тогда сначала нужно включить поддержку `Entware` на Keenetic и смонтировать `/opt`.

После этого достаточно повторно выполнить ту же bootstrap-команду.
