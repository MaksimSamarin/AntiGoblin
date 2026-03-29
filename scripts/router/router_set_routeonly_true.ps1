$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  'sed -i ''s/"routeOnly": false/"routeOnly": true/'' /opt/etc/xray/vpngroup_config.json',
  "killall xray; xray run -confdir /opt/etc/xray >/dev/null 2>&1 &",
  "sleep 2; ps | grep xray | grep -v grep",
  "grep -n 'routeOnly' /opt/etc/xray/vpngroup_config.json"
)

foreach ($command in $commands) {
  Write-Output "=== CMD: $command ==="
  $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 30000
  if ($result.Output) {
    $result.Output
  }
  if ($result.Error) {
    Write-Output '--- STDERR ---'
    $result.Error
  }
}

Remove-SSHSession -SSHSession $session | Out-Null
