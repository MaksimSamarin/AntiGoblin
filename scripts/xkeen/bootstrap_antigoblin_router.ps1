param(
  [string]$RouterHost = "192.168.1.1",
  [int]$Port = 8899,
  [string]$RouterUser = 'root',
  [switch]$ForceSeedConfigs
)

$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('RouterUser') -and $env:ROUTER_SSH_USER) {
  $RouterUser = $env:ROUTER_SSH_USER
}

$null = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$python = (Get-Command python -ErrorAction Stop).Source

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sshHelper = Join-Path $PSScriptRoot 'router_ssh.py'

$seedFiles = @(
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\01_log.sample.json'); Remote = '/opt/etc/xray/configs/01_log.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\03_inbounds.sample.json'); Remote = '/opt/etc/xray/configs/03_inbounds.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\04_outbounds.sample.json'); Remote = '/opt/etc/xray/configs/04_outbounds.json'; Mode = '644' },
  @{ Local = (Join-Path $repoRoot 'configs\xkeen\05_routing.sample.json'); Remote = '/opt/etc/xray/configs/05_routing.json'; Mode = '644' },
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

  & $python $sshHelper --host $RouterHost --user $RouterUser upload --local $LocalPath --remote $RemotePath --mode $Mode
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
mkdir -p /opt/share/xkeen-manager
mkdir -p /opt/share/xkeen-manager/api
mkdir -p /opt/share/xkeen-manager/runtime
mkdir -p /opt/var/log
mkdir -p /opt/var/run

/opt/bin/opkg update >/dev/null 2>&1 || true
for pkg in jq gawk coreutils-base64 net-tools-netstat cron uhttpd_kn xray iptables ipset; do
  /opt/bin/opkg install "$pkg" >/dev/null 2>&1 || true
done

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

if ! ndmc -c 'show ip policy' 2>/dev/null | grep -q 'description = xkeen:'; then
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
  ndmc -c "system configuration save" >/dev/null 2>&1 || true
fi
'@
Invoke-RouterCommand -Command $bootstrapScript

foreach ($item in $seedFiles) {
  $exists = (& $python $sshHelper --host $RouterHost --user $RouterUser run --command "test -f '$($item.Remote)' && echo EXISTS || echo MISSING")
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to inspect seed file on router: $($item.Remote)"
  }
  $shouldUpload = $ForceSeedConfigs.IsPresent -or ($exists -notmatch 'EXISTS')
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

Write-Output "Starting router-hosted UI..."
& (Join-Path $PSScriptRoot 'start_xkeen_manager_ui_router.ps1') -RouterHost $RouterHost -Port $Port -RouterUser $RouterUser

Write-Output "Repairing xkeen/xray runtime..."
Invoke-RouterCommand -Command "/opt/share/xkeen-manager/api/xkeen-selfheal.sh --force"

Write-Output ""
Write-Output "Bootstrap complete."
Write-Output "Open http://$RouterHost`:$Port/"
Write-Output "Login uses Keenetic web UI credentials."
