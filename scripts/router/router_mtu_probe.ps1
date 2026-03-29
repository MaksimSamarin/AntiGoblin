$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "ip link show",
  "ifconfig 2>/dev/null",
  "ip route",
  "ping -c 3 -M do -s 1472 8.47.69.0",
  "ping -c 3 -M do -s 1460 8.47.69.0",
  "ping -c 3 -M do -s 1400 8.47.69.0",
  "ping -c 3 -M do -s 1472 185.121.234.53",
  "ping -c 3 -M do -s 1460 185.121.234.53",
  "ping -c 3 -M do -s 1400 185.121.234.53"
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
