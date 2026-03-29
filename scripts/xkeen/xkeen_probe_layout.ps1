$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  '/opt/sbin/xkeen -h 2>&1 | sed -n "1,220p"',
  'find /opt/sbin/.xkeen -maxdepth 3 -type f 2>/dev/null | sed -n "1,220p"',
  'find /opt/etc/xray -maxdepth 3 -type f 2>/dev/null | sed -n "1,220p"',
  'find /opt/etc/init.d -maxdepth 1 -type f | grep -E "xray|cron" | sed -n "1,120p"',
  'curl -kfsS localhost:79/rci/show/ip/policy 2>/dev/null | sed -n "1,220p"'
)

foreach ($command in $commands) {
  Write-Output "=== CMD: $command ==="
  $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
  if ($result.Output) { $result.Output }
  if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
}

Remove-SSHSession -SSHSession $session | Out-Null
