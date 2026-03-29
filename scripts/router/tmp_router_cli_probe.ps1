$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }`r`n$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
 = New-Object System.Management.Automation.PSCredential('root', )
Import-Module Posh-SSH
 = New-SSHSession -ComputerName 192.168.2.1 -Credential  -AcceptKey -ConnectionTimeout 10
 = @(
  'which cli',
  'which ndmc',
  'which ndmq',
  'ls /bin /sbin /usr/bin /usr/sbin 2>/dev/null | grep -E "^(cli|ndm|ndmc|ndmq)$"',
  'ps | grep -E "ndm|cli|proxy"'
)
foreach ( in ) {
  Write-Output "=== CMD:  ==="
   = Invoke-SSHCommand -SSHSession  -Command  -TimeOut 30000
  if (.Output) { .Output }
  if (.Error) { Write-Output '--- STDERR ---'; .Error }
}
Remove-SSHSession -SSHSession  | Out-Null
