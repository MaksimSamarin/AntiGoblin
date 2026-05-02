# Развертывание с нуля

Цель: выполнить одну команду на рабочем ПК и получить на роутере установленный `AntiGoblin`, базовый `xray`-набор и рабочий UI.

## Что делает bootstrap

Скрипт:

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
  - `iptables`
  - `ipset`
  - `conntrack`
- создает UI-видимую политику Keenetic `xkeen`, если ее еще нет
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

## Что проверить после чистой установки

После bootstrap должно выполняться следующее:

- UI открывается на `http://ROUTER_IP:8899/`
- `xray` слушает `61219`
- в Keenetic UI видна отдельная политика `xkeen`
- `xkeen` существует отдельно от пользовательских политик, например `no_vpn`
- `AntiGoblin` цепляется только к mark политики `xkeen`
- `/opt/share/xkeen-manager/api/xkeen-runtime.sh` есть на роутере

Важно:

- bootstrap создает `xkeen` как дополнительную политику `Policy42+`
- это нужно для нормальной видимости в Keenetic UI
- после создания bootstrap делает `system configuration save`
- существующие пользовательские политики bootstrap трогать не должен
- если политика `xkeen` уже существует, bootstrap обязан использовать именно ее и не создавать новую

Если пользователь позже удалит `xkeen` в Keenetic UI:

- `xkeen-selfheal.sh` должен создать ее заново автоматически;
- после создания он должен сделать `system configuration save`;
- новая `xkeen` снова должна стать единственной политикой, к которой цепляется `AntiGoblin`;
- существующие пользовательские политики, например `no_vpn`, трогаться не должны.

## Если bootstrap остановился

Самая частая причина:

- на роутере нет `Entware/OPKG` в `/opt`

Тогда сначала нужно включить поддержку `Entware` на Keenetic и смонтировать `/opt`.

После этого достаточно повторно выполнить ту же bootstrap-команду.
