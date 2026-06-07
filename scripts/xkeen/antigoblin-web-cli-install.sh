#!/bin/sh
# Запуск установщика AntiGoblin через Keenetic Web CLI.
#
# Использование в http://192.168.1.1/a после установки Entware:
#
#   exec sh -c "/opt/bin/wget -O - https://raw.githubusercontent.com/MaksimSamarin/AntiGoblin/main/scripts/xkeen/antigoblin-web-cli-install.sh | /opt/bin/sh"
#
# Этот скрипт не ставит Entware. Он только запускает обычный on-router
# установщик AntiGoblin из Web CLI без отдельного SSH-подключения.

set -eu

PATH=/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

REPO_OWNER="${ANTIGOBLIN_REPO_OWNER:-MaksimSamarin}"
REPO_NAME="${ANTIGOBLIN_REPO_NAME:-AntiGoblin}"
REPO_BRANCH="${ANTIGOBLIN_REPO_BRANCH:-main}"
INSTALL_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/install.sh"
INSTALL_FILE="/opt/tmp/antigoblin-install.sh"

log() {
  printf '==> %s\n' "$*"
  logger -t antigoblin-web-cli "$*" 2>/dev/null || true
}

die() {
  printf 'ОШИБКА: %s\n' "$*" >&2
  logger -t antigoblin-web-cli "ОШИБКА: $*" 2>/dev/null || true
  exit 1
}

require_entware() {
  [ -d /opt ] || die "/opt не смонтирован. Сначала установите и включите Entware."
  [ -x /opt/bin/sh ] || die "/opt/bin/sh не найден. Entware не инициализирован."
  [ -x /opt/bin/wget ] || die "/opt/bin/wget не найден. Entware не инициализирован."
  mkdir -p /opt/tmp
}

main() {
  require_entware

  log "Скачиваем установщик AntiGoblin"
  /opt/bin/wget -O "$INSTALL_FILE" "$INSTALL_URL" >/dev/null 2>&1 || die "не удалось скачать $INSTALL_URL"
  chmod 700 "$INSTALL_FILE" 2>/dev/null || true

  log "Запускаем установщик AntiGoblin"
  exec /opt/bin/sh "$INSTALL_FILE"
}

main "$@"
