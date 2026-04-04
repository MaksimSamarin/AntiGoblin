param(
  [string]$RouterHost = "192.168.1.1",
  [string]$RouterUser = 'root',
  [string]$RemoteRoot = "/opt/share/xkeen-manager",
  [string]$RemoteApiDir = "/opt/share/xkeen-manager/api",
  [string]$RemoteRuntimeDir = "/opt/share/xkeen-manager/runtime",
  [string]$RemoteSelfhealLoop = "/opt/share/xkeen-manager/api/xkeen-selfheal-loop.sh",
  [string]$RemoteSelfhealInit = "/opt/etc/init.d/S25antigoblin-selfheal",
  [string]$RemoteInitScript = "/opt/etc/init.d/S26antigoblin",
  [string]$RemoteCronScript = "/opt/etc/cron.1min/50-antigoblin-selfheal",
  [string]$RemoteFsHook = "/opt/etc/ndm/fs.d/50-antigoblin.sh",
  [string]$RemoteUsbHook = "/opt/etc/ndm/usb.d/50-antigoblin.sh"
)

$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('RouterUser') -and $env:ROUTER_SSH_USER) {
  $RouterUser = $env:ROUTER_SSH_USER
}

$null = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$python = (Get-Command python -ErrorAction Stop).Source

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sshHelper = Join-Path $PSScriptRoot 'router_ssh.py'
$localApi = Join-Path $repoRoot 'ui\xkeen-manager\backend\routing.cgi'
$localSelfHeal = Join-Path $repoRoot 'ui\xkeen-manager\backend\xkeen-selfheal.sh'
$localSelfhealLoop = Join-Path $repoRoot 'scripts\xkeen\antigoblin-selfheal-loop.sh'
$localSelfhealInit = Join-Path $repoRoot 'scripts\xkeen\antigoblin-selfheal.initd.sh'
$localInitScript = Join-Path $repoRoot 'scripts\xkeen\antigoblin.initd.sh'
$localCronScript = Join-Path $repoRoot 'scripts\xkeen\antigoblin-selfheal.cron.sh'
$localRemountHook = Join-Path $repoRoot 'scripts\xkeen\antigoblin-remount-hook.sh'
$localBypassDomains = Join-Path $repoRoot 'configs\xkeen\bypass-domains.sample.txt'
$localBypassCidrs = Join-Path $repoRoot 'configs\xkeen\bypass-cidrs.sample.txt'

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
    [string]$Mode = '755'
  )

  & $python $sshHelper --host $RouterHost --user $RouterUser upload --local $LocalPath --remote $RemotePath --mode $Mode
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload $RemotePath"
  }
}

if (-not (Test-Path $localApi)) {
  throw "Missing backend file: $localApi"
}
if (-not (Test-Path $localSelfHeal)) {
  throw "Missing self-heal file: $localSelfHeal"
}
if (-not (Test-Path $localSelfhealLoop)) {
  throw "Missing self-heal loop script: $localSelfhealLoop"
}
if (-not (Test-Path $localSelfhealInit)) {
  throw "Missing self-heal init script: $localSelfhealInit"
}
if (-not (Test-Path $localInitScript)) {
  throw "Missing init script: $localInitScript"
}
if (-not (Test-Path $localCronScript)) {
  throw "Missing cron script: $localCronScript"
}
if (-not (Test-Path $localRemountHook)) {
  throw "Missing remount hook: $localRemountHook"
}
if (-not (Test-Path $localBypassDomains)) {
  throw "Missing bypass domains sample: $localBypassDomains"
}
if (-not (Test-Path $localBypassCidrs)) {
  throw "Missing bypass CIDRs sample: $localBypassCidrs"
}

Invoke-RouterCommand -Command "mkdir -p $RemoteRoot"
Invoke-RouterCommand -Command "mkdir -p $RemoteApiDir"
Invoke-RouterCommand -Command "mkdir -p $RemoteRuntimeDir"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/cron.1min"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/xray/configs"
Invoke-RouterCommand -Command "opkg update >/dev/null 2>&1 || true"
Invoke-RouterCommand -Command "opkg install uhttpd_kn >/dev/null 2>&1 || true"

Send-RemoteFile -LocalPath $localApi -RemotePath "$RemoteApiDir/routing.cgi"
Send-RemoteFile -LocalPath $localSelfHeal -RemotePath "$RemoteApiDir/xkeen-selfheal.sh"
Send-RemoteFile -LocalPath $localSelfhealLoop -RemotePath $RemoteSelfhealLoop
Send-RemoteFile -LocalPath $localSelfhealInit -RemotePath $RemoteSelfhealInit
Send-RemoteFile -LocalPath $localInitScript -RemotePath $RemoteInitScript
Send-RemoteFile -LocalPath $localCronScript -RemotePath $RemoteCronScript
Send-RemoteFile -LocalPath $localRemountHook -RemotePath $RemoteFsHook
Send-RemoteFile -LocalPath $localRemountHook -RemotePath $RemoteUsbHook

$ensureRuntime = @(
  @{ Local = $localBypassDomains; Remote = "$RemoteRuntimeDir/bypass-domains.txt" },
  @{ Local = $localBypassCidrs; Remote = "$RemoteRuntimeDir/bypass-cidrs.txt" }
)
foreach ($item in $ensureRuntime) {
  $remoteExists = (& $python $sshHelper --host $RouterHost --user $RouterUser run --command "test -f '$($item.Remote)' && echo EXISTS || echo MISSING")
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to verify runtime file: $($item.Remote)"
  }
  if ($remoteExists -match 'EXISTS') {
    Write-Output "Keeping existing runtime file: $($item.Remote)"
    continue
  }
  Send-RemoteFile -LocalPath $item.Local -RemotePath $item.Remote
  Write-Output "Seeded runtime file: $($item.Remote)"
}

$cronCmd = @'
rm -f /opt/var/spool/cron/crontabs/root 2>/dev/null || true
CRON_INIT=""
for candidate in /opt/etc/init.d/S10cron /opt/etc/init.d/S05crond; do
  if [ -x "$candidate" ]; then
    CRON_INIT="$candidate"
    break
  fi
done
[ -n "$CRON_INIT" ] && "$CRON_INIT" restart >/dev/null 2>&1 || true
'@
Invoke-RouterCommand -Command $cronCmd
Invoke-RouterCommand -Command "chmod 755 '$RemoteSelfhealLoop' '$RemoteSelfhealInit' '$RemoteInitScript' '$RemoteCronScript' '$RemoteFsHook' '$RemoteUsbHook' && '$RemoteSelfhealInit' restart >/dev/null 2>&1 || true && '$RemoteInitScript' restart >/dev/null 2>&1 || true"
