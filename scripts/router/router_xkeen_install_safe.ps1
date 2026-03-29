$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  'opkg install tar curl >/tmp/opkg-xkeen-prep.log 2>&1; tail -n 60 /tmp/opkg-xkeen-prep.log',
  'which curl || ls -l /opt/bin/curl 2>/dev/null || true',
  'cd /tmp && /opt/bin/curl -fL https://github.com/Skrill0/XKeen/releases/latest/download/xkeen.tar -o xkeen.tar && ls -lh xkeen.tar',
  'tar -tvf /tmp/xkeen.tar | sed -n "1,80p"',
  'tar -xvf /tmp/xkeen.tar -C /opt/sbin --overwrite >/tmp/xkeen-install.log 2>&1; tail -n 80 /tmp/xkeen-install.log',
  'find /opt/sbin -maxdepth 2 \( -name "xkeen" -o -name "_xkeen" -o -name ".xkeen" \) | sed -n "1,120p"',
  'ls -l /opt/sbin/xkeen 2>/dev/null || true',
  '/opt/sbin/xkeen -h 2>&1 | sed -n "1,120p"'
)

foreach ($command in $commands) {
  Write-Output "=== CMD: $command ==="
  $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 240000
  if ($result.Output) {
    $result.Output
  }
  if ($result.Error) {
    Write-Output '--- STDERR ---'
    $result.Error
  }
}

Remove-SSHSession -SSHSession $session | Out-Null
