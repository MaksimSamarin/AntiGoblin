# XKeen Rollback Notes

Use this path if the current `AntiGoblin + xkeen + xray` runtime breaks routing on the router.

## Fast Rollback

1. Restore `/opt/etc/xray` from the latest backup created by `xkeen_backup_state.ps1`.
2. Restore `/opt/share/xkeen-manager/xkeen-ui-state.json` if state was damaged.
3. Restart `xray`.
4. Run `xkeen-selfheal.sh --force` to rebuild the live `xkeen` chain.

## Router Checks

```sh
ps | grep -E '[x]ray|[u]httpd'
ip rule show
iptables -t nat -S xkeen
iptables -t nat -S PREROUTING | grep xkeen
iptables -t mangle -S PREROUTING | grep xkeen
ls -l /opt/etc/xray/configs
```

## Important

- do not restore retired runtime experiments
- do not re-enable `xkeen_udp` or `xkeen_quic` unless there is a proven reason
- restore state and `xray` config first, then runtime
