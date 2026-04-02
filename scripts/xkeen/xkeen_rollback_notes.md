# Заметки по откату XKeen

Используй этот путь отката, если текущая схема `AntiGoblin + xkeen + xray` ломает маршрутизацию.

## Быстрый откат

1. Восстановить `/opt/etc/xray` из последнего backup-архива, созданного `xkeen_backup_state.ps1`.
2. Восстановить `xkeen-ui-state.json`, если был поврежден state.
3. Перезапустить `xray`.
4. Прогнать `xkeen-selfheal.sh --force`, чтобы вернуть живую цепочку `xkeen`.

## Ручные проверки на роутере

```sh
ps | grep -E '[x]ray|[u]httpd'
ip rule show
iptables -t nat -S xkeen
iptables -t nat -S PREROUTING | grep xkeen
iptables -t mangle -S PREROUTING | grep xkeen
ls -l /opt/etc/xray/configs
```

## Важно

- не восстанавливать `HydraRoute`;
- не поднимать обратно `xkeen_udp` и `xkeen_quic` без отдельной причины;
- сначала откатывать state и `xray`-конфиги, потом уже runtime.
