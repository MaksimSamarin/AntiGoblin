#!/bin/sh
# Запуск установщика AntiGoblin через Keenetic Web CLI.
#
# Использование в http://192.168.1.1/a после установки Entware:
#
#   exec sh -c "/opt/bin/curl -fsSL https://raw.githubusercontent.com/MaksimSamarin/AntiGoblin/main/scripts/xkeen/antigoblin-web-cli-install.sh | /opt/bin/sh"
#
# Если curl ещё не установлен в Entware:
#
#   exec sh -c "/opt/bin/opkg install curl >/dev/null 2>&1; /opt/bin/curl -fsSL https://raw.githubusercontent.com/MaksimSamarin/AntiGoblin/main/scripts/xkeen/antigoblin-web-cli-install.sh | /opt/bin/sh"
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

FETCHER_BIN=""
FETCHER_TYPE=""

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
  mkdir -p /opt/tmp
}

# Default Entware ships wget-nossl (no HTTPS), так что предпочитаем curl,
# затем wget с TLS, как последний шанс — ставим curl через opkg.
_try_wget() {
  cand="$1"
  [ -x "$cand" ] || return 1
  "$cand" --version 2>&1 | grep -qiE '\+https|gnutls|openssl|ssl/tls' || return 1
  FETCHER_BIN="$cand"
  FETCHER_TYPE="wget"
  return 0
}

ensure_https_fetcher() {
  [ -n "$FETCHER_BIN" ] && return 0

  if [ -x /opt/bin/curl ]; then
    FETCHER_BIN="/opt/bin/curl"; FETCHER_TYPE="curl"; return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    FETCHER_BIN="$(command -v curl)"; FETCHER_TYPE="curl"; return 0
  fi
  _try_wget /opt/bin/wget     && return 0
  _try_wget /opt/usr/bin/wget && return 0
  if command -v wget >/dev/null 2>&1; then
    _try_wget "$(command -v wget)" && return 0
  fi

  if [ -x /opt/bin/opkg ]; then
    log "Нет HTTPS-загрузчика, пробую: opkg install curl"
    /opt/bin/opkg update >/dev/null 2>&1 || true
    /opt/bin/opkg install curl >/dev/null 2>&1 || true
    if [ -x /opt/bin/curl ]; then
      FETCHER_BIN="/opt/bin/curl"; FETCHER_TYPE="curl"; return 0
    fi
  fi

  die "Нет HTTPS-загрузчика (curl или wget-ssl). Установите вручную: opkg install curl"
}

fetch_to() {
  ensure_https_fetcher
  url="$1"; dest="$2"
  case "$FETCHER_TYPE" in
    curl) "$FETCHER_BIN" -fsSL -o "$dest" "$url" ;;
    wget) "$FETCHER_BIN" -q -O "$dest" "$url" ;;
    *)    die "fetcher не определён" ;;
  esac
}

main() {
  require_entware
  ensure_https_fetcher

  log "Скачиваем установщик AntiGoblin (через $FETCHER_TYPE)"
  fetch_to "$INSTALL_URL" "$INSTALL_FILE" || die "не удалось скачать $INSTALL_URL"
  chmod 700 "$INSTALL_FILE" 2>/dev/null || true

  log "Запускаем установщик AntiGoblin"
  exec /opt/bin/sh "$INSTALL_FILE"
}

main "$@"
