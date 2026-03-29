$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "cp /var/run/proxy-cfg-t2s0 /var/run/proxy-cfg-t2s0.bak-codex",
  "sed -i 's/read-write-timeout: 20000/read-write-timeout: 120000/' /var/run/proxy-cfg-t2s0",
  "grep -n 'read-write-timeout' /var/run/proxy-cfg-t2s0",
  "kill 12203",
  "sleep 3",
  "ps | grep hev-socks5-tunnel | grep -v grep",
  "cat /proc/\\$(ps | grep hev-socks5-tunnel | grep -v grep | awk '{print \\$1}' | head -1)/cmdline | tr '\\000' ' '",
  "cat /var/run/proxy-cfg-t2s0 | grep 'read-write-timeout'"
)

foreach ($command in $commands) {
  Write-Output \"=== CMD: $command ===\"
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
