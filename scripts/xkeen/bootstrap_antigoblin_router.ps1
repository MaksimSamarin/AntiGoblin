param(
  [string]$RouterHost,
  [int]$Port = 0,
  [string]$RouterUser,
  [switch]$ForceSeedConfigs
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_load-env.ps1')

if (-not $RouterHost) { $RouterHost = if ($env:ROUTER_HOST) { $env:ROUTER_HOST } else { '192.168.1.1' } }
if (-not $RouterUser) { $RouterUser = if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' } }
if (-not $Port -or $Port -le 0) { $Port = if ($env:ANTIGOBLIN_UI_PORT) { [int]$env:ANTIGOBLIN_UI_PORT } else { 8899 } }

if (-not $env:ROUTER_SSH_PASSWORD) { throw "ROUTER_SSH_PASSWORD is not set. Put it in .env or export it before running." }
$python = (Get-Command python -ErrorAction Stop).Source

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sshHelper = Join-Path $PSScriptRoot 'router_ssh.py'

$seedFiles = @(
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\01_log.sample.json'); Remote = '/opt/etc/xray/configs/01_log.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\02_relay.sample.json'); Remote = '/opt/etc/xray/configs/02_relay.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\03_inbounds.sample.json'); Remote = '/opt/etc/xray/configs/03_inbounds.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\04_outbounds.sample.json'); Remote = '/opt/etc/xray/configs/04_outbounds.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\05_routing.sample.json'); Remote = '/opt/etc/xray/configs/05_routing.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\sing-box-xkeen.sample.json'); Remote = '/opt/etc/sing-box/xkeen.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\xkeen-ui-state.sample.json'); Remote = '/opt/share/xkeen-manager/xkeen-ui-state.json'; Mode = '644' }
)

foreach ($item in $seedFiles) {
  if (-not (Test-Path $item.Local)) {
    throw "Missing seed file: $($item.Local)"
  }
}

function Invoke-RouterCommand {
  param(
    [string]$Command
  )

  if ($Command -match "`n") {
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
      Set-Content -Path $tmpFile -Value $Command -NoNewline
      Get-Content -Path $tmpFile -Raw | & $python $sshHelper --host $RouterHost --user $RouterUser run --stdin
    }
    finally {
      Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
  } else {
    & $python $sshHelper --host $RouterHost --user $RouterUser run --command $Command
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Router command failed: $Command"
  }
}

function Send-RemoteFile {
  param(
    [string]$LocalPath,
    [string]$RemotePath,
    [string]$Mode = '644'
  )

  $binaryExts = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.woff', '.woff2', '.zip', '.tar', '.gz')
  $ext = [System.IO.Path]::GetExtension($LocalPath).ToLower()
  $extraArgs = @()
  if ($binaryExts -contains $ext) { $extraArgs += '--binary' }

  & $python $sshHelper --host $RouterHost --user $RouterUser upload --local $LocalPath --remote $RemotePath --mode $Mode @extraArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload $RemotePath"
  }
}

$bootstrapScript = @'
set -eu

if [ ! -d /opt ] || [ ! -x /opt/bin/opkg ]; then
  echo 'ERROR: Entware/OPKG not found in /opt. Install Entware on the router first.'
  exit 10
fi

mkdir -p /opt/etc/xray/configs
mkdir -p /opt/etc/xray/dat
mkdir -p /opt/etc/sing-box
mkdir -p /opt/share/xkeen-manager
mkdir -p /opt/share/xkeen-manager/api
mkdir -p /opt/share/xkeen-manager/runtime
mkdir -p /opt/var/log
mkdir -p /opt/var/run

/opt/bin/opkg update >/dev/null 2>&1 || true
# Essentials — stack won't run without them; fail hard so a broken
# opkg / no-network situation is caught here, not silently later.
# Mirrors install.sh install_packages().
ESSENTIAL_PKGS="xray uhttpd_kn iptables ipset conntrack jq gawk ca-bundle"
OPTIONAL_PKGS="cron curl wget tar gzip coreutils-base64 coreutils-timeout net-tools-netstat"

MISSING=""
for pkg in $ESSENTIAL_PKGS; do
  if ! /opt/bin/opkg list-installed | grep -q "^${pkg} "; then
    /opt/bin/opkg install "$pkg" >/dev/null 2>&1 || MISSING="$MISSING $pkg"
  fi
done
if [ -n "$MISSING" ]; then
  echo "ERROR: failed to install essential packages:$MISSING" >&2
  exit 12
fi
for pkg in $OPTIONAL_PKGS; do
  if ! /opt/bin/opkg list-installed | grep -q "^${pkg} "; then
    /opt/bin/opkg install "$pkg" >/dev/null 2>&1 || true
  fi
done

if ! command -v sing-box >/dev/null 2>&1; then
  SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.8}"
  # Match install.sh: try multiple asset names per arch since sing-box
  # release naming has changed across versions.
  case "$(uname -m)" in
    aarch64|arm64)   ARCH_CANDIDATES="arm64-musl arm64" ;;
    armv7l|armv7*)   ARCH_CANDIDATES="armv7-musl armv7" ;;
    armv6l|armv6*)   ARCH_CANDIDATES="armv7-musl armv7" ;;
    mipsel*)         ARCH_CANDIDATES="mipsle-softfloat mipsle" ;;
    mips*)           ARCH_CANDIDATES="mips-softfloat mips" ;;
    x86_64|amd64)    ARCH_CANDIDATES="amd64-musl amd64" ;;
    *)               ARCH_CANDIDATES="$(uname -m)" ;;
  esac
  # Entware wget is wget-nossl by default — HTTPS through it does not work.
  # Prefer curl; opkg install it above should have covered this.
  FETCH="curl"
  [ -x /opt/bin/curl ] || FETCH="wget"
  rm -rf /tmp/antigoblin-sing-box /tmp/antigoblin-sing-box.tar.gz
  mkdir -p /tmp/antigoblin-sing-box
  ok=0
  for arch_try in $ARCH_CANDIDATES; do
    url="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${arch_try}.tar.gz"
    if [ "$FETCH" = "curl" ]; then
      /opt/bin/curl -fsSL -o /tmp/antigoblin-sing-box.tar.gz "$url" 2>/dev/null && { ok=1; break; }
    else
      wget -q -O /tmp/antigoblin-sing-box.tar.gz "$url" 2>/dev/null && { ok=1; break; }
    fi
  done
  if [ "$ok" = "1" ]; then
    tar -xzf /tmp/antigoblin-sing-box.tar.gz -C /tmp/antigoblin-sing-box
    SING_BOX_BIN="$(find /tmp/antigoblin-sing-box -type f -name sing-box | head -n 1)"
    if [ -n "$SING_BOX_BIN" ]; then
      cp "$SING_BOX_BIN" /opt/sbin/sing-box
      chmod 755 /opt/sbin/sing-box
    fi
  fi
fi

CRON_INIT=""
for candidate in /opt/etc/init.d/S10cron /opt/etc/init.d/S05crond; do
  if [ -x "$candidate" ]; then
    CRON_INIT="$candidate"
    break
  fi
done
[ -n "$CRON_INIT" ] && "$CRON_INIT" enable >/dev/null 2>&1 || true
[ -n "$CRON_INIT" ] && "$CRON_INIT" restart >/dev/null 2>&1 || true

mkdir -p /opt/var/log/xray
touch /opt/var/log/xray/access.log
touch /opt/var/log/xray/error.log
touch /opt/var/log/xkeen-selfheal.log
touch /opt/var/log/xkeen-health.log

XKEEN_DESC_RE='description(([[:space:]]*[=:])|([[:space:]]+))[[:space:]]*"?xkeen($|[":,[:space:]])'
if ! ndmc -c 'show ip policy' 2>/dev/null | grep -Eq "$XKEEN_DESC_RE"; then
  WAN_IFACE="$(ndmc -c 'show interface' | /opt/bin/awk '
    /^Interface, name = / {
      iface=$4
      gsub(/"/, "", iface)
      next
    }
    /defaultgw:[[:space:]]+yes/ {
      print iface
      exit
    }
  ')"

  if [ -z "$WAN_IFACE" ]; then
    echo 'ERROR: failed to detect active WAN interface for xkeen policy creation.'
    exit 11
  fi

  NEXT_POLICY_NUM="$(
    ndmc -c 'show running-config' | /opt/bin/awk '
      /^ip policy Policy[0-9]+$/ {
        name=$3
        sub(/^Policy/, "", name)
        if (name >= 42) {
          print name
        }
      }
    ' | sort -n | /opt/bin/awk '
      BEGIN { n = 42 }
      {
        if ($1 == n) {
          n++
        }
      }
      END { print n }
    '
  )"

  [ -n "$NEXT_POLICY_NUM" ] || NEXT_POLICY_NUM=42
  POLICY_NAME="Policy$NEXT_POLICY_NUM"

  ndmc -c "ip policy $POLICY_NAME"
  ndmc -c "ip policy $POLICY_NAME description xkeen"
  ndmc -c "ip policy $POLICY_NAME permit global $WAN_IFACE"
  saved=0
  for _try in 1 2 3; do
    if ndmc -c "system configuration save" >/dev/null 2>&1; then saved=1; break; fi
    sleep 1
  done
  [ "$saved" = "1" ] || echo 'WARN: system configuration save failed after 3 tries; policy may not survive reboot.'
fi
'@
Invoke-RouterCommand -Command $bootstrapScript

foreach ($item in $seedFiles) {
  $exists = (& $python $sshHelper --host $RouterHost --user $RouterUser run --command "test -f '$($item.Remote)' && echo EXISTS || echo MISSING")
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to inspect seed file on router: $($item.Remote)"
  }
  # 04_outbounds / 05_routing are runtime-owned: backend regenerates them
  # from the UI state on every apply, and sample files intentionally omit
  # the vless-reality outbound. Overwriting an existing installation with
  # samples would strip the working outbound until the user hits Save+Apply
  # again. Even under -ForceSeedConfigs we keep them if they exist.
  $isRuntimeOwned = ($item.Remote -eq '/opt/etc/xray/configs/04_outbounds.json') -or `
                    ($item.Remote -eq '/opt/etc/xray/configs/05_routing.json')
  $shouldUpload = ($exists -notmatch 'EXISTS') -or ($ForceSeedConfigs.IsPresent -and -not $isRuntimeOwned)
  if (-not $shouldUpload) {
    Write-Output "Keeping existing file: $($item.Remote)"
    continue
  }
  Send-RemoteFile -LocalPath $item.Local -RemotePath $item.Remote -Mode $item.Mode
  Write-Output "Seeded: $($item.Remote)"
}

Write-Output "Deploying AntiGoblin UI..."
& (Join-Path $PSScriptRoot 'deploy_xkeen_manager_ui_to_router.ps1') -RouterHost $RouterHost -RouterUser $RouterUser

Write-Output "Deploying AntiGoblin backend..."
& (Join-Path $PSScriptRoot 'deploy_xkeen_manager_backend_to_router.ps1') -RouterHost $RouterHost -RouterUser $RouterUser

Write-Output "Writing UI port config /opt/etc/antigoblin.conf..."
Invoke-RouterCommand -Command "printf 'PORT=%s\n' '$Port' > /opt/etc/antigoblin.conf && chmod 644 /opt/etc/antigoblin.conf"

Write-Output "Starting router-hosted UI..."
& (Join-Path $PSScriptRoot 'start_xkeen_manager_ui_router.ps1') -RouterHost $RouterHost -Port $Port -RouterUser $RouterUser

Write-Output "Repairing xkeen/xray runtime..."
Invoke-RouterCommand -Command "/opt/share/xkeen-manager/api/xkeen-selfheal.sh --force"

Write-Output ""
Write-Output "Bootstrap complete."
Write-Output "Open http://$RouterHost`:$Port/"
Write-Output "Login uses Keenetic web UI credentials."
