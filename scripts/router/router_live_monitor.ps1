$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

for ($i = 1; $i -le 18; $i++) {
  Write-Output "===== SAMPLE $i ====="

  $commands = @(
    'date',
    "ps | grep xray | grep -v grep",
    "tail -n 8 /opt/var/log/LOGhrneo.log",
    "iptables -t mangle -L -n -v | grep HydraRoute"
  )

  foreach ($command in $commands) {
    Write-Output "=== CMD: $command ==="
    $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 15000
    if ($result.Output) {
      $result.Output
    }
    if ($result.Error) {
      Write-Output '--- STDERR ---'
      $result.Error
    }
  }

  Start-Sleep -Seconds 5
}

Remove-SSHSession -SSHSession $session | Out-Null
