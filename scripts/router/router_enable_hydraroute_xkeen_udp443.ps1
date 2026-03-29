$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "cp -f /opt/etc/xray/configs/03_inbounds.json /opt/etc/xray/configs/03_inbounds.json.bak-hydraroute-udp443 2>/dev/null || true",
  @'
cat > /opt/etc/xray/configs/03_inbounds.json <<'EOF'
{
    "inbounds": [
        {
            "tag": "redirect",
            "port": 61219,
            "protocol": "dokodemo-door",
            "settings": {
                "network": "tcp",
                "followRedirect": true
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        },
        {
            "tag": "tproxy",
            "port": 61220,
            "protocol": "dokodemo-door",
            "settings": {
                "network": "udp",
                "followRedirect": true
            },
            "streamSettings": {
                "sockopt": {
                    "tproxy": "tproxy"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "quic"
                ]
            }
        }
    ]
}
EOF
'@,
  "ip rule add fwmark 0x111 lookup 111 2>/dev/null || true",
  "ip route add local default dev lo table 111 2>/dev/null || true",
  "iptables -t mangle -N xkeen_udp 2>/dev/null || true",
  "iptables -t mangle -F xkeen_udp",
  "iptables -t mangle -A xkeen_udp -d 192.168.1.102/32 -j RETURN",
  "iptables -t mangle -A xkeen_udp -p udp -m socket --transparent -j MARK --set-mark 0x111",
  "iptables -t mangle -A xkeen_udp -p udp -j TPROXY --on-ip 0.0.0.0 --on-port 61220 --tproxy-mark 0x111",
  "iptables -t mangle -C PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp || iptables -t mangle -I PREROUTING 1 -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -p udp -j xkeen_udp",
  "killall xray 2>/dev/null || true",
  "sleep 1",
  "XRAY_LOCATION_ASSET=/opt/etc/xray/dat XRAY_LOCATION_CONFDIR=/opt/etc/xray/configs xray run >/opt/var/log/xray-manual.log 2>&1 &",
  "sleep 2",
  "pgrep -af xray",
  "netstat -tulnp | grep 6121",
  "netstat -tulnp | grep 61220",
  "iptables -t nat -S xkeen",
  "iptables -t mangle -S xkeen_udp",
  "ip rule show | grep 'lookup 111'",
  "ip route show table 111"
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
