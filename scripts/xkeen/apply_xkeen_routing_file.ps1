param(
  [string]$RoutingFile = ".\\05_routing.generated.json"
)

$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$resolvedRoutingFile = Resolve-Path -LiteralPath $RoutingFile -ErrorAction Stop

$routing = Get-Content -Raw -LiteralPath $resolvedRoutingFile | ConvertFrom-Json
if (-not $routing.routing -or -not $routing.routing.rules) {
  throw "Routing file does not look like xray routing config: $resolvedRoutingFile"
}

$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH -ErrorAction Stop

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$remoteTemp = "/opt/etc/xray/configs/05_routing.json.upload-$timestamp"
$remoteBackup = "/opt/etc/xray/configs/05_routing.json.bak-$timestamp"

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

try {
  Write-Output "Applying routing file: $resolvedRoutingFile"

  $precheck = Invoke-SSHCommand -SSHSession $session -Command 'test -d /opt/etc/xray/configs && echo CONFIG_DIR_OK || echo CONFIG_DIR_MISSING' -TimeOut 30000
  if ($precheck.Output -notcontains 'CONFIG_DIR_OK') {
    throw 'Remote xray config directory /opt/etc/xray/configs does not exist.'
  }

  Set-SCPItem -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -Force -Path $resolvedRoutingFile -Destination $remoteTemp

  $validate = Invoke-SSHCommand -SSHSession $session -Command @"
python3 - <<'PY'
import json
p='$remoteTemp'
with open(p,'r',encoding='utf-8') as f:
    data=json.load(f)
assert 'routing' in data and 'rules' in data['routing']
print('JSON_OK')
print('RULES=' + str(len(data['routing']['rules'])))
for rule in data['routing']['rules']:
    if 'ip' in rule:
        print('IP_COUNT=' + str(len(rule['ip'])))
        break
PY
"@ -TimeOut 30000
  if ($validate.Output) { $validate.Output }
  if ($validate.Error) { Write-Output '--- STDERR ---'; $validate.Error }

  $commands = @(
    "cp /opt/etc/xray/configs/05_routing.json $remoteBackup 2>/dev/null || true",
    "mv $remoteTemp /opt/etc/xray/configs/05_routing.json",
    "killall xray 2>/dev/null || true",
    "nohup sh -c 'XRAY_LOCATION_ASSET=/opt/etc/xray/dat XRAY_LOCATION_CONFDIR=/opt/etc/xray/configs xray run' >/opt/var/log/xray-manual.log 2>&1 &",
    "sleep 2",
    "netstat -lnptu | grep -E '61219|61220' || true",
    "tail -n 5 /opt/var/log/xray-manual.log || true"
  )

  foreach ($command in $commands) {
    Write-Output "=== CMD: $command ==="
    $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
    if ($result.Output) { $result.Output }
    if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
  }

  Write-Output "Applied routing file successfully. Backup: $remoteBackup"
}
finally {
  Remove-SSHSession -SSHSession $session | Out-Null
}
