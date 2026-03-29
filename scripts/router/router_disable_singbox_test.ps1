$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "iptables -t mangle -D PREROUTING -m mark --mark 0x0 -m connmark --mark 0x0/0xffff0000 -s 192.168.2.106 -m set --match-set HydraRoute dst -j CONNMARK --set-xmark 0xffffaac/0xffffffff 2>/dev/null || true",
  "ip rule del priority 104 fwmark 0xffffaac lookup 200 2>/dev/null || true",
  "ip route flush table 200 2>/dev/null || true",
  "killall sing-box 2>/dev/null || true",
  "ip rule show",
  "ip route show table 200 2>/dev/null || true",
  "iptables -t mangle -S PREROUTING | sed -n '1,20p'",
  "ps | grep '[s]ing-box' || true",
  "ip link show sbtest0 2>/dev/null || true"
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
