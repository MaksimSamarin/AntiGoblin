$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "ls -l /var/run/proxy-fb-Proxy0",
  "cat /var/run/proxy-fb-Proxy0",
  "ps | grep -E 'hev-socks5-tunnel|Proxy0|proxy-cfg-t2s0' | grep -v grep",
  "find /etc/init.d -maxdepth 1 -type f | grep -i proxy || true",
  "find /usr/bin -maxdepth 1 -type f | grep -i proxy || true"
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
