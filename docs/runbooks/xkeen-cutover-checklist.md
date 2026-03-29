# Чеклист переключения на XKeen

Использовать только во время запланированного окна миграции.

## Цель

Переключиться с текущего пути `HydraRoute + Proxy0 + manual xray` на путь под управлением `XKeen` контролируемо и с готовым откатом.

## Подготовленные артефакты

- backup: [xkeen_backup_state.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_backup_state.ps1)
- preflight: [xkeen_preflight.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_preflight.ps1)
- stage drafts: [xkeen_stage_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_stage_drafts.ps1)
- apply drafts: [xkeen_apply_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_apply_drafts.ps1)
- rollback notes: [xkeen_rollback_notes.md](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_rollback_notes.md)

## Последовательность

1. Запустить [xkeen_backup_state.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_backup_state.ps1).
2. Запустить [xkeen_preflight.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_preflight.ps1).
3. Запустить [xkeen_stage_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_stage_drafts.ps1).
4. Остановить текущий ручной путь `xray` и временно снять влияние `HydraRoute`.
5. Запустить `xkeen -i` на роутере.
6. Убедиться, что появились `/opt/etc/xray/configs` и policy `xkeen`.
7. Запустить [xkeen_apply_drafts.ps1](/e:/Домашние проекты/VPN на роутере/scripts/xkeen/xkeen_apply_drafts.ps1).
8. Запустить сервис под управлением `XKeen`.
9. Назначить только тестовый клиент `192.168.2.106` на policy `xkeen`.
10. Проверить:
   - обычный HTTPS;
   - долгий HTTPS;
   - `Codex compact`.

## Критерии успеха

- тестовый клиент получает рабочий интернет через `XKeen`;
- `Codex compact` больше не рвется;
- остальная часть роутера остается незатронутой.

## Когда откатываться

Откатываться сразу, если:

- тестовый клиент теряет обычный доступ в интернет;
- сервис `xray/XKeen` не удерживается в рабочем состоянии;
- policy routing на роутере ведет себя неожиданно;
- `Codex compact` все еще падает, а новый путь не дает другой практической пользы.

## Фактические заметки из успешной миграции

Миграция `2026-03-29` в итоге сработала, но потребовала платформенных фиксов:

- `xkeen -i` интерактивный и требует ответов:
  - GeoIP: `0`;
  - GeoSite: `0`;
  - automatic updates: `0`.
- `XKeen` ожидал, что policy `xkeen` уже создана в UI роутера; сам он ее автоматически не создавал.
- сгенерированный `/opt/etc/init.d/S24xray` пришлось чинить вручную:
  - добавить `name_client="xray"`;
  - заменить `busybox ps` на обычный `ps`.
- стоковый `/opt/etc/xray/configs/02_transport.json` оказался несовместим с текущим `Xray 26.2.6`;
  - текущий рабочий фикс — `{}` в этом файле.

## Текущий результат

После этих фиксов:

- `XKeen`-`xray` работает на `61219`;
- `HydraRoute` продолжает давать выбор и маркировку;
- помеченный трафик перенаправляется через цепочку `xkeen`;
- `Codex compact` работает по новому пути.
