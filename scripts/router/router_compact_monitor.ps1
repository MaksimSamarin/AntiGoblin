$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

for ($i = 1; $i -le 30; $i++) {
  Write-Output "===== SAMPLE $i ====="

  $commands = @(
    'date',
    "ps | grep xray | grep -v grep",
    "tail -n 12 /opt/var/log/xray-error.log",
    "tail -n 12 /opt/var/log/xray-access.log",
    "cat /proc/net/nf_conntrack | grep 192.168.2.106 | grep 443 | tail -12"
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

  Start-Sleep -Seconds 5
}

Remove-SSHSession -SSHSession $session | Out-Null
