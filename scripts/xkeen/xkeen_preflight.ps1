$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  '/opt/sbin/xkeen -h 2>&1 | sed -n "1,80p"',
  'find /opt/sbin/.xkeen -maxdepth 2 -type f 2>/dev/null | sed -n "1,80p"',
  'find /opt/etc/xray -maxdepth 2 -type f 2>/dev/null | sed -n "1,120p"',
  'find /lib/modules/4.9-ndm-5 -type f \( -name "xt_TPROXY.ko" -o -name "xt_socket.ko" -o -name "xt_multiport.ko" \) | sed -n "1,80p"',
  'iptables -j TPROXY -h >/dev/null 2>&1; echo "iptables TPROXY=$?"',
  'iptables -m socket -h >/dev/null 2>&1; echo "iptables socket=$?"',
  'iptables -m multiport -h >/dev/null 2>&1; echo "iptables multiport=$?"',
  'curl -kfsS localhost:79/rci/show/ip/policy 2>/dev/null | sed -n "1,160p"',
  'ps | grep -E "[x]ray|[x]keen|[h]ev-socks5"'
)

foreach ($command in $commands) {
  Write-Output "=== CMD: $command ==="
  $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
  if ($result.Output) { $result.Output }
  if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
}

Remove-SSHSession -SSHSession $session | Out-Null
