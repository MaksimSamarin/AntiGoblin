$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10
$result = Invoke-SSHCommand -SSHSession $session -Command "iptables -t mangle -S FORWARD | grep TCPMSS || true" -TimeOut 10000
if ($result.Output) {
  $result.Output
}
if ($result.Error) {
  $result.Error
}
Remove-SSHSession -SSHSession $session | Out-Null
