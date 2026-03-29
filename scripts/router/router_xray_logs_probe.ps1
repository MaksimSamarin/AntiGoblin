$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "tail -n 60 /opt/var/log/xray-error.log",
  "tail -n 60 /opt/var/log/xray-access.log",
  "grep -n '8.47.69.0\\|chatgpt\\|ab.chatgpt\\|ws.chatgpt\\|185.121.234.53' /opt/var/log/xray-access.log | tail -n 40",
  "grep -n 'compact\\|timeout\\|failed\\|error\\|closed\\|disconnect' /opt/var/log/xray-error.log | tail -n 40"
)

foreach ($command in $commands) {
  Write-Output "=== CMD: $command ==="
  $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 20000
  if ($result.Output) {
    $result.Output
  }
  if ($result.Error) {
    Write-Output '--- STDERR ---'
    $result.Error
  }
}

Remove-SSHSession -SSHSession $session | Out-Null
