param(
  [string]$RouterHost = "192.168.1.1",
  [string]$RouterUser = $(if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' }),
  [string]$RemoteRoot = "/opt/share/xkeen-manager",
  [string]$RemoteApiDir = "/opt/share/xkeen-manager/api",
  [string]$RemoteRuntimeDir = "/opt/share/xkeen-manager/runtime",
  [string]$RemoteInitScript = "/opt/etc/init.d/S26antigoblin",
  [string]$RemoteFsHook = "/opt/etc/ndm/fs.d/50-antigoblin.sh",
  [string]$RemoteUsbHook = "/opt/etc/ndm/usb.d/50-antigoblin.sh"
)

$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($RouterUser, $sec)

Import-Module Posh-SSH -ErrorAction Stop

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$localApi = Join-Path $repoRoot 'ui\xkeen-manager\backend\routing.cgi'
$localSelfHeal = Join-Path $repoRoot 'ui\xkeen-manager\backend\xkeen-selfheal.sh'
$localInitScript = Join-Path $repoRoot 'scripts\xkeen\antigoblin.initd.sh'
$localRemountHook = Join-Path $repoRoot 'scripts\xkeen\antigoblin-remount-hook.sh'
$localBypassDomains = Join-Path $repoRoot 'configs\xkeen\bypass-domains.sample.txt'
$localBypassCidrs = Join-Path $repoRoot 'configs\xkeen\bypass-cidrs.sample.txt'

function Send-RemoteFileBase64 {
  param(
    [object]$Session,
    [string]$LocalPath,
    [string]$RemotePath
  )

  $bytes = [System.IO.File]::ReadAllBytes($LocalPath)
  $b64 = [Convert]::ToBase64String($bytes)
  $chunks = for ($i = 0; $i -lt $b64.Length; $i += 3500) {
    $b64.Substring($i, [Math]::Min(3500, $b64.Length - $i))
  }

  Invoke-SSHCommand -SSHSession $Session -Command ": > /tmp/xkeen-api-upload.b64" -TimeOut 30000 | Out-Null

  foreach ($chunk in $chunks) {
    $append = Invoke-SSHCommand -SSHSession $Session -Command "printf '%s' '$chunk' >> /tmp/xkeen-api-upload.b64" -TimeOut 30000
    if ($append.ExitStatus -ne 0) {
      throw "Failed to append upload chunk for $RemotePath"
    }
  }

  $finish = Invoke-SSHCommand -SSHSession $Session -Command "/opt/bin/base64 -d /tmp/xkeen-api-upload.b64 > '$RemotePath' && rm -f /tmp/xkeen-api-upload.b64 && chmod 755 '$RemotePath' && ls -lh '$RemotePath'" -TimeOut 30000
  if ($finish.ExitStatus -ne 0) {
    throw "Failed to decode/upload $RemotePath"
  }
  if ($finish.Output) { $finish.Output }
  if ($finish.Error) { Write-Output '--- STDERR ---'; $finish.Error }
}

if (-not (Test-Path $localApi)) {
  throw "Missing backend file: $localApi"
}
if (-not (Test-Path $localSelfHeal)) {
  throw "Missing self-heal file: $localSelfHeal"
}
if (-not (Test-Path $localInitScript)) {
  throw "Missing init script: $localInitScript"
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

$session = New-SSHSession -ComputerName $RouterHost -Credential $cred -AcceptKey -ConnectionTimeout 10

try {
  $prep = @(
    "mkdir -p $RemoteRoot",
    "mkdir -p $RemoteApiDir",
    "mkdir -p $RemoteRuntimeDir",
    "opkg update >/dev/null 2>&1 || true",
    "opkg install uhttpd_kn >/dev/null 2>&1 || true",
    "test -f /opt/etc/xray/configs/05_routing.json"
  )

  foreach ($command in $prep) {
    $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
    if ($result.Output) { $result.Output }
    if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
  }

  Send-RemoteFileBase64 -Session $session -LocalPath $localApi -RemotePath "$RemoteApiDir/routing.cgi"
  Send-RemoteFileBase64 -Session $session -LocalPath $localSelfHeal -RemotePath "$RemoteApiDir/xkeen-selfheal.sh"
  Send-RemoteFileBase64 -Session $session -LocalPath $localInitScript -RemotePath $RemoteInitScript
  Send-RemoteFileBase64 -Session $session -LocalPath $localRemountHook -RemotePath $RemoteFsHook
  Send-RemoteFileBase64 -Session $session -LocalPath $localRemountHook -RemotePath $RemoteUsbHook

  $ensureRuntime = @(
    @{ Local = $localBypassDomains; Remote = "$RemoteRuntimeDir/bypass-domains.txt" },
    @{ Local = $localBypassCidrs; Remote = "$RemoteRuntimeDir/bypass-cidrs.txt" }
  )
  foreach ($item in $ensureRuntime) {
    $remoteExists = Invoke-SSHCommand -SSHSession $session -Command "test -f '$($item.Remote)' && echo EXISTS || echo MISSING" -TimeOut 30000
    if ($remoteExists.Output -contains 'EXISTS') {
      Write-Output "Keeping existing runtime file: $($item.Remote)"
      continue
    }
    Send-RemoteFileBase64 -Session $session -LocalPath $item.Local -RemotePath $item.Remote
    Write-Output "Seeded runtime file: $($item.Remote)"
  }

  $cronCmd = @"
( /opt/bin/crontab -l 2>/dev/null || true ) | grep -Fv '/opt/share/xkeen-manager/api/xkeen-selfheal.sh' > /tmp/xkeen-cron.new
echo '* * * * * /opt/share/xkeen-manager/api/xkeen-selfheal.sh >/dev/null 2>&1' >> /tmp/xkeen-cron.new
echo '* * * * * sleep 15; /opt/share/xkeen-manager/api/xkeen-selfheal.sh >/dev/null 2>&1' >> /tmp/xkeen-cron.new
echo '* * * * * sleep 30; /opt/share/xkeen-manager/api/xkeen-selfheal.sh >/dev/null 2>&1' >> /tmp/xkeen-cron.new
echo '* * * * * sleep 45; /opt/share/xkeen-manager/api/xkeen-selfheal.sh >/dev/null 2>&1' >> /tmp/xkeen-cron.new
/opt/bin/crontab /tmp/xkeen-cron.new
rm -f /tmp/xkeen-cron.new
/opt/etc/init.d/S05crond restart >/dev/null 2>&1 || true
"@
  $cronResult = Invoke-SSHCommand -SSHSession $session -Command $cronCmd -TimeOut 120000
  if ($cronResult.Output) { $cronResult.Output }
  if ($cronResult.Error) { Write-Output '--- STDERR ---'; $cronResult.Error }

  $initResult = Invoke-SSHCommand -SSHSession $session -Command "chmod 755 '$RemoteInitScript' '$RemoteFsHook' '$RemoteUsbHook' && '$RemoteInitScript' restart >/dev/null 2>&1 || true" -TimeOut 120000
  if ($initResult.Output) { $initResult.Output }
  if ($initResult.Error) { Write-Output '--- STDERR ---'; $initResult.Error }
}
finally {
  Remove-SSHSession -SSHSession $session | Out-Null
}
