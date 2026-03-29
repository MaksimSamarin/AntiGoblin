$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "grep -n 'httpbin\\|chatgpt\\|openai\\|google\\|youtube\\|anthropic\\|deepl' /opt/etc/HydraRoute/domain.conf",
  "tail -n 20 /opt/etc/HydraRoute/domain.conf"
)

foreach ($command in $commands) {
  Write-Output \"=== CMD: $command ===\"
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
