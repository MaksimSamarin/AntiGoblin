# План миграции на XKeen

## Цель

Заменить текущий выборочный путь `HydraRoute + Proxy0 + manual xray` на путь под управлением `XKeen`, но сделать это контролируемо и с готовым откатом.

## Предусловия

- утилита `xkeen` установлена в `/opt/sbin/xkeen`;
- текущий ручной путь на роутере все еще активен;
- миграция через `xkeen -i` еще не запускалась или не завершалась штатно.

## Этап 1. Резервная копия

Запустить:

- [xkeen_backup_state.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_backup_state.ps1)

Ожидаемый результат:

- backup-архив сохраняется в `snapshots/xkeen-migration/<timestamp>/`.

## Этап 2. Осмотр текущего layout XKeen

Запустить:

- [xkeen_probe_layout.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_probe_layout.ps1)
- [xkeen_preflight.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_preflight.ps1)

Задача:

- подтвердить текущий layout `xray`;
- убедиться, что policy `xkeen` еще не активна или не конфликтует;
- понять, чем именно хочет управлять `xkeen`;
- проверить наличие нужных kernel/`iptables` возможностей перед cutover.

## Этап 3. Контролируемое окно миграции

Только в заранее запланированное окно:

1. остановить ручной путь `xray`;
2. временно снять влияние `HydraRoute` на маршрутизацию;
3. запустить [xkeen_stage_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_stage_drafts.ps1);
4. выполнить `xkeen -i`;
5. проверить сгенерированные сущности:
   - `/opt/etc/xray/configs`;
   - `/opt/etc/init.d/S24xray`;
   - `rci/show/ip/policy`;
6. запустить [xkeen_apply_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_apply_drafts.ps1);
7. запустить `xray` под управлением `XKeen`;
8. повесить на policy `xkeen` только одно тестовое устройство.

## Этап 4. Первая валидация

Проверять в таком порядке:

1. обычный HTTPS;
2. долгий HTTPS;
3. `Codex compact`.

Не добавлять сложную выборочную доменную маршрутизацию, пока full-device routing хотя бы для одного клиента не стабилен.

## Этап 5. Откат

Если миграция не удалась:

- использовать [xkeen-cutover-checklist.md](/e:/Домашние проекты/VPN на роутере/docs/runbooks/xkeen-cutover-checklist.md) как последовательность в окне миграции;
- использовать [xkeen_rollback_notes.md](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_rollback_notes.md);
- восстановить `/opt/etc/xray`;
- вернуть исходный способ запуска сервиса;
- вернуть устройство на старый маршрут.
