param(
  [string]$RouterHost = "192.168.2.1",
  [string]$RemoteRoot = "/opt/share/xkeen-manager",
  [string]$RemoteApiDir = "/opt/share/xkeen-manager/api"
)

$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH -ErrorAction Stop

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$localApi = Join-Path $repoRoot 'ui\xkeen-manager\backend\routing.cgi'
$localSelfHeal = Join-Path $repoRoot 'ui\xkeen-manager\backend\xkeen-selfheal.sh'

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

$session = New-SSHSession -ComputerName $RouterHost -Credential $cred -AcceptKey -ConnectionTimeout 10

try {
  $prep = @(
    "mkdir -p $RemoteRoot",
    "mkdir -p $RemoteApiDir",
    "opkg update >/dev/null 2>&1 || true",
    "opkg install uhttpd_kn >/dev/null 2>&1 || true",
    "test -f /opt/etc/xray/configs/05_routing.json",
    "cp /opt/etc/xray/configs/05_routing.json $RemoteRoot/router-live-routing.json"
  )

  foreach ($command in $prep) {
    $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
    if ($result.Output) { $result.Output }
    if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
  }

  Send-RemoteFileBase64 -Session $session -LocalPath $localApi -RemotePath "$RemoteApiDir/routing.cgi"
  Send-RemoteFileBase64 -Session $session -LocalPath $localSelfHeal -RemotePath "$RemoteApiDir/xkeen-selfheal.sh"

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
}
finally {
  Remove-SSHSession -SSHSession $session | Out-Null
}
