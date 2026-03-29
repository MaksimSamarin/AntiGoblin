$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "ps | grep hev | grep -v grep",
  "which hev-socks5-tu || true",
  "find /opt -maxdepth 4 \\( -iname '*hev*' -o -iname '*socks5-tu*' \\) 2>/dev/null | head -50",
  "find /etc -maxdepth 4 \\( -iname '*hev*' -o -iname '*socks5-tu*' \\) 2>/dev/null | head -50",
  "strings /proc/12203/cmdline 2>/dev/null || cat /proc/12203/cmdline 2>/dev/null"
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
