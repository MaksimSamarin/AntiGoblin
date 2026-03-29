$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$commands = @(
  'test -d /opt/etc/xray/configs',
  "mkdir -p /opt/etc/xray/configs/.pre-user-drafts-$timestamp",
  "cp -a /opt/etc/xray/configs/04_outbounds.json /opt/etc/xray/configs/.pre-user-drafts-$timestamp/04_outbounds.json 2>/dev/null || true",
  "cp -a /opt/etc/xray/configs/05_routing.json /opt/etc/xray/configs/.pre-user-drafts-$timestamp/05_routing.json 2>/dev/null || true",
  'cp -f /opt/var/xkeen-drafts/04_outbounds.json /opt/etc/xray/configs/04_outbounds.json',
  'cp -f /opt/var/xkeen-drafts/05_routing.json /opt/etc/xray/configs/05_routing.json',
  'ls -lh /opt/etc/xray/configs/04_outbounds.json /opt/etc/xray/configs/05_routing.json',
  'sed -n "1,160p" /opt/etc/xray/configs/04_outbounds.json',
  'sed -n "1,220p" /opt/etc/xray/configs/05_routing.json'
)

foreach ($command in $commands) {
  Write-Output "=== CMD: $command ==="
  $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
  if ($result.ExitStatus -ne 0 -and $command -eq 'test -d /opt/etc/xray/configs') {
    throw 'XKeen config directory /opt/etc/xray/configs does not exist yet. Run xkeen -i first.'
  }
  if ($result.Output) { $result.Output }
  if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
}

Write-Output "Applied staged drafts to /opt/etc/xray/configs with backup suffix .pre-user-drafts-$timestamp"

Remove-SSHSession -SSHSession $session | Out-Null
