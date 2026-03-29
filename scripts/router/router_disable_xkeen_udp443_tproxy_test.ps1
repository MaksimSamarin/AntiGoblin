$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "iptables -t mangle -D PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen_udp443 2>/dev/null || true",
  "iptables -t mangle -F xkeen_udp443 2>/dev/null || true",
  "iptables -t mangle -X xkeen_udp443 2>/dev/null || true",
  "ip rule del fwmark 0x1/0x1 table 100 pref 100 2>/dev/null || true",
  "ip route flush table 100 2>/dev/null || true",
  "if [ -f /opt/etc/xray/configs/03_inbounds.json.bak-udp443-tproxy ]; then cp -f /opt/etc/xray/configs/03_inbounds.json.bak-udp443-tproxy /opt/etc/xray/configs/03_inbounds.json; fi",
  "/opt/etc/init.d/S24xray restart",
  "sleep 2; ps | grep '[x]ray'",
  "netstat -tulnp | grep 6122 || true",
  "iptables -t mangle -S | grep xkeen_udp443 || true",
  "ip rule show | grep 'fwmark 0x1' || true"
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
