$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  'ls -l /opt/sbin/xkeen /opt/bin/xkeen 2>/dev/null || true',
  'find /opt -maxdepth 3 \( -name "xkeen" -o -name ".xkeen" -o -path "/opt/etc/xkeen*" \) 2>/dev/null | sed -n "1,120p"',
  'ls -l /opt/etc/xray 2>/dev/null',
  'find /opt/etc -maxdepth 2 -type d | grep -E "xkeen|xray" | sed -n "1,120p"',
  '/opt/sbin/xkeen -h 2>&1 | sed -n "1,200p"',
  'ps | grep -E "[x]keen|[x]ray"'
)

foreach ($command in $commands) {
  Write-Output "=== CMD: $command ==="
  $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
  if ($result.Output) {
    $result.Output
  }
  if ($result.Error) {
    Write-Output '--- STDERR ---'
    $result.Error
  }
}

Remove-SSHSession -SSHSession $session | Out-Null
