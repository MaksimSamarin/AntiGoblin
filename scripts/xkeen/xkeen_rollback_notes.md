# XKeen Rollback Notes

Use this rollback path if a future `xkeen -i` migration breaks routing or overwrites the current manual xray setup.

## Fast rollback

1. Stop XKeen-managed xray/service if it was enabled.
2. Restore `/opt/etc/xray` from the latest backup archive created by `xkeen_backup_state.ps1`.
3. Restore `/opt/etc/init.d/S24xray` if XKeen replaced it.
4. Restart the original manual xray process.
5. Re-enable the previous HydraRoute-based workflow if it had been disabled.

## Manual checks on router

```sh
ps | grep -E '[x]keen|[x]ray'
ip rule show
iptables -t mangle -S
ls -l /opt/etc/xray
```

## Important

- Do not run `xkeen -dk` or `xkeen -dx` blindly on a mixed setup without checking what was installed.
- Prefer restoring from the pre-migration backup tarball first.
