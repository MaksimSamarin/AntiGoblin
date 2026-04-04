param(
  [string]$RouterHost = "192.168.1.1",
  [int]$Port = 8899,
  [string]$RouterUser = $(if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { "root" }),
  [switch]$ForceSeedConfigs
)

$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }

if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
  Write-Output "Installing PowerShell module Posh-SSH for current user..."
  Install-Module Posh-SSH -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
}

Import-Module Posh-SSH -ErrorAction Stop

$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = [pscredential]::new($RouterUser, $sec)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

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

function Send-RemoteFileBase64 {
  param(
    [object]$Session,
    [string]$LocalPath,
    [string]$RemotePath,
    [string]$Mode = '644'
  )

  $bytes = [System.IO.File]::ReadAllBytes($LocalPath)
  $b64 = [Convert]::ToBase64String($bytes)
  $chunks = for ($i = 0; $i -lt $b64.Length; $i += 3500) {
    $b64.Substring($i, [Math]::Min(3500, $b64.Length - $i))
  }

  Invoke-SSHCommand -SSHSession $Session -Command ": > /tmp/antigoblin-upload.b64" -TimeOut 30000 | Out-Null

  foreach ($chunk in $chunks) {
    $append = Invoke-SSHCommand -SSHSession $Session -Command "printf '%s' '$chunk' >> /tmp/antigoblin-upload.b64" -TimeOut 30000
    if ($append.ExitStatus -ne 0) {
      throw "Failed to append upload chunk for $RemotePath"
    }
  }

  $finish = Invoke-SSHCommand -SSHSession $Session -Command "/opt/bin/base64 -d /tmp/antigoblin-upload.b64 > '$RemotePath' && rm -f /tmp/antigoblin-upload.b64 && chmod $Mode '$RemotePath' && ls -lh '$RemotePath'" -TimeOut 30000
  if ($finish.ExitStatus -ne 0) {
    throw "Failed to decode/upload $RemotePath"
  }
  if ($finish.Output) { $finish.Output }
  if ($finish.Error) { Write-Output '--- STDERR ---'; $finish.Error }
}

$session = (New-SSHSession -ComputerName $RouterHost -Credential $cred -AcceptKey -ConnectionTimeout 10)[0]

try {
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
for pkg in jq gawk coreutils-base64 net-tools-netstat cron uhttpd_kn xray; do
  /opt/bin/opkg install "$pkg" >/dev/null 2>&1 || true
done

/opt/etc/init.d/S05crond enable >/dev/null 2>&1 || true
/opt/etc/init.d/S05crond restart >/dev/null 2>&1 || true

touch /opt/var/log/xray/access.log
touch /opt/var/log/xray/error.log
touch /opt/var/log/xkeen-selfheal.log

if ! ndmc -c 'show running-config' | grep -q '^    description xkeen$'; then
  WAN_IFACE="$(ndmc -c 'show interface' | /opt/bin/awk '
    /^Interface, name = / {
      iface=\$4
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
        name=\$3
        sub(/^Policy/, "", name)
        print name
      }
    ' | sort -n | /opt/bin/awk '
      BEGIN { n = 0 }
      {
        if (\$1 == n) {
          n++
        }
      }
      END { print n }
    '
  )"

  [ -n "$NEXT_POLICY_NUM" ] || NEXT_POLICY_NUM=0
  POLICY_NAME="Policy$NEXT_POLICY_NUM"

  ndmc -c "ip policy $POLICY_NAME"
  ndmc -c "ip policy $POLICY_NAME description xkeen"
  ndmc -c "ip policy $POLICY_NAME permit global $WAN_IFACE"
fi
'@
  $bootstrapResult = Invoke-SSHCommand -SSHSession $session -Command $bootstrapScript -TimeOut 180000
  if ($bootstrapResult.ExitStatus -ne 0) {
    throw (($bootstrapResult.Output + $bootstrapResult.Error) -join [Environment]::NewLine)
  }

  foreach ($item in $seedFiles) {
    $exists = Invoke-SSHCommand -SSHSession $session -Command "test -f '$($item.Remote)' && echo EXISTS || echo MISSING" -TimeOut 30000
    $shouldUpload = $ForceSeedConfigs.IsPresent -or ($exists.Output -notcontains 'EXISTS')
    if (-not $shouldUpload) {
      Write-Output "Keeping existing file: $($item.Remote)"
      continue
    }
    Send-RemoteFileBase64 -Session $session -LocalPath $item.Local -RemotePath $item.Remote -Mode $item.Mode
    Write-Output "Seeded: $($item.Remote)"
  }
}
finally {
  Remove-SSHSession -SSHSession $session | Out-Null
}

Write-Output "Deploying AntiGoblin UI..."
& (Join-Path $PSScriptRoot 'deploy_xkeen_manager_ui_to_router.ps1') -RouterHost $RouterHost -RouterUser $RouterUser
if (-not $?) {
  throw "deploy_xkeen_manager_ui_to_router.ps1 failed"
}

Write-Output "Deploying AntiGoblin backend..."
& (Join-Path $PSScriptRoot 'deploy_xkeen_manager_backend_to_router.ps1') -RouterHost $RouterHost -RouterUser $RouterUser
if (-not $?) {
  throw "deploy_xkeen_manager_backend_to_router.ps1 failed"
}

Write-Output "Starting router-hosted UI..."
& (Join-Path $PSScriptRoot 'start_xkeen_manager_ui_router.ps1') -RouterHost $RouterHost -Port $Port -RouterUser $RouterUser
if (-not $?) {
  throw "start_xkeen_manager_ui_router.ps1 failed"
}

Write-Output ""
Write-Output "Bootstrap complete."
Write-Output "Open http://$RouterHost`:$Port/"
Write-Output "Login uses Keenetic web UI credentials."
