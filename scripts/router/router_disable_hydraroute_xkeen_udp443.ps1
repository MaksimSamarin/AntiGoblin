$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "iptables -t mangle -D PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp 2>/dev/null || true",
  "iptables -t mangle -F xkeen_udp 2>/dev/null || true",
  "iptables -t mangle -X xkeen_udp 2>/dev/null || true",
  "ip rule del fwmark 0x111 lookup 111 2>/dev/null || true",
  "ip route flush table 111 2>/dev/null || true",
  "if [ -f /opt/etc/xray/configs/03_inbounds.json.bak-hydraroute-udp443 ]; then cp -f /opt/etc/xray/configs/03_inbounds.json.bak-hydraroute-udp443 /opt/etc/xray/configs/03_inbounds.json; fi",
  "killall xray 2>/dev/null || true",
  "sleep 1",
  "XRAY_LOCATION_ASSET=/opt/etc/xray/dat XRAY_LOCATION_CONFDIR=/opt/etc/xray/configs xray run >/opt/var/log/xray-manual.log 2>&1 &",
  "sleep 2",
  "pgrep -af xray",
  "netstat -tulnp | grep 61219",
  "netstat -tulnp | grep 61220 || true",
  "iptables -t mangle -S | grep xkeen_udp || true",
  "ip rule show | grep 'lookup 111' || true"
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
