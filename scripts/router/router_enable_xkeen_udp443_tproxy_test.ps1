$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "cp -f /opt/etc/xray/configs/03_inbounds.json /opt/etc/xray/configs/03_inbounds.json.bak-udp443-tproxy",
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
  "sed -n '1,240p' /opt/etc/xray/configs/03_inbounds.json",
  "ip rule add fwmark 0x1/0x1 table 100 pref 100 2>/dev/null || true",
  "ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null || true",
  "iptables -t mangle -N xkeen_udp443 2>/dev/null || true",
  "iptables -t mangle -F xkeen_udp443",
  "iptables -t mangle -C PREROUTING -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen_udp443 || iptables -t mangle -I PREROUTING 1 -m connmark --mark 0xffffaab -m conntrack ! --ctstate INVALID -j xkeen_udp443",
  "iptables -t mangle -A xkeen_udp443 -d 192.168.1.102/32 -j RETURN",
  "iptables -t mangle -A xkeen_udp443 -p udp --dport 443 -j TPROXY --on-port 61220 --tproxy-mark 0x1/0x1",
  "/opt/etc/init.d/S24xray restart",
  "sleep 2; ps | grep '[x]ray'",
  "netstat -tulnp | grep 6122",
  "iptables -t mangle -S xkeen_udp443",
  "iptables -t mangle -L PREROUTING -n -v | sed -n '1,20p'",
  "ip rule show | grep 'fwmark 0x1'",
  "ip route show table 100"
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
