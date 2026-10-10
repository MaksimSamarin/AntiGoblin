#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Entware jq on Keenetic is compiled without ONIGURUMA. Regex helpers parse
# successfully on development machines but fail at runtime on the router.
if grep -nE '(^|[^[:alnum:]_])test\(' \
    ui/xkeen-manager/backend/xkeen-runtime.sh \
    ui/xkeen-manager/backend/routing.cgi \
    scripts/xkeen/antigoblin-geodata.sh \
    scripts/xkeen/antigoblin-subscription-refresh.sh; then
  echo 'FAIL: router jq expressions require regex support unavailable in Entware jq' >&2
  exit 1
fi

echo 'PASS: router jq expressions do not require ONIGURUMA regex support'
