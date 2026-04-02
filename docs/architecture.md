# Архитектура: Keenetic + Entware + AntiGoblin + XKeen/xray

## Что живет на роутере

- UI: `http://192.168.2.1:8899/`
- state: `/opt/share/xkeen-manager/xkeen-ui-state.json`
- backend:
  - `/opt/share/xkeen-manager/api/routing.cgi`
  - `/opt/share/xkeen-manager/api/xkeen-selfheal.sh`
- `xray` configs:
  - `/opt/etc/xray/configs/04_outbounds.json`
  - `/opt/etc/xray/configs/05_routing.json`

## Источник истины

Единственный source of truth:

- `xkeen-ui-state.json`

Из него UI/backend собирает:

- `04_outbounds.json`
- `05_routing.json`

## Поток трафика

### Уровень Keenetic

Устройства, назначенные в политику `xkeen`, получают mark:

- `0xffffaaa`

### Уровень iptables

Для mark `0xffffaaa` трафик попадает в цепочку `xkeen`.

Текущая живая модель:

```text
RETURN 192.168.2.0/24
RETURN 224.0.0.0/4
RETURN 255.255.255.255/32
RETURN 192.168.1.102/32
REDIRECT tcp -> 61219
RETURN
```

Смысл:

- локалка и discovery не трогаются;
- весь остальной `TCP` устройств из `xkeen` идет в `xray`;
- `UDP` не перехватывается и идет напрямую обычным путем роутера.

## xray

`xray` используется как TCP transport и routing engine:

- inbound `redirect` на `61219`
- inbound `tproxy` на `61220` в конфиге остается, но live path его не использует
- outbound `vless-reality`
- outbound `direct`

После попадания в `xray` уже `05_routing.json` решает:

- что отправлять в `vless-reality`
- что отправлять в `direct`

## Self-heal

`xkeen-selfheal.sh`:

- следит, чтобы `xray` был жив;
- следит, чтобы `xkeen` и hook `PREROUTING -> xkeen` были на месте;
- удаляет старые хвосты `xkeen_udp`, `xkeen_quic`, `xkeen_vpn`, `HydraRoute`;
- не восстанавливает больше старые `HydraRoute`-hooks.

Cron запускает self-heal несколько раз в минуту.

## Что удалено

С роутера удалены:

- `HydraRoute`
- `hrneo`
- `hrweb`
- `/opt/etc/HydraRoute`
- `/opt/etc/init.d/S99hrneo`
- `/opt/etc/ndm/netfilter.d/015-hrneo.sh`

Текущая схема не зависит от `HydraRoute`.
