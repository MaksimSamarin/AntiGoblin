$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path $repoRoot 'configs\sing-box\sing-box-tun-test.json'
$config = Get-Content -LiteralPath $configPath -Raw

$commands = @(
  @"
cat > /opt/etc/sing-box-tun-test.json <<'EOF'
$config
EOF
"@,
  "/opt/bin/sing-box check -c /opt/etc/sing-box-tun-test.json",
  "killall sing-box 2>/dev/null || true",
  "rm -f /opt/var/log/sing-box-test.log /opt/var/log/sing-box-test.stdout",
  "sh -c '/opt/bin/sing-box run -c /opt/etc/sing-box-tun-test.json >/opt/var/log/sing-box-test.stdout 2>&1 &'",
  "sleep 3",
  "ip route replace table 200 192.168.1.0/24 dev eth2.4 scope link",
  "ip route replace table 200 192.168.2.0/24 dev br0 scope link",
  "ip route replace table 200 default dev sbtest0 scope link",
  "ip rule del priority 104 fwmark 0xffffaac lookup 200 2>/dev/null || true",
  "ip rule add priority 104 fwmark 0xffffaac lookup 200",
  "iptables -t mangle -D PREROUTING -m mark --mark 0x0 -m connmark --mark 0x0/0xffff0000 -s 192.168.2.106 -m set --match-set HydraRoute dst -j CONNMARK --set-xmark 0xffffaac/0xffffffff 2>/dev/null || true",
  "iptables -t mangle -I PREROUTING 6 -m mark --mark 0x0 -m connmark --mark 0x0/0xffff0000 -s 192.168.2.106 -m set --match-set HydraRoute dst -j CONNMARK --set-xmark 0xffffaac/0xffffffff",
  "ip rule show",
  "ip route show table 200",
  "iptables -t mangle -S PREROUTING | sed -n '1,20p'",
  "netstat -tlnp | grep 10888",
  "ip link show sbtest0"
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
