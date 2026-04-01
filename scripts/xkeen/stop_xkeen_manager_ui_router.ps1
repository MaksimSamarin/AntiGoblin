param(
  [string]$RouterHost = "192.168.2.1",
  [int]$Port = 8899
)

$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH -ErrorAction Stop

$session = New-SSHSession -ComputerName $RouterHost -Credential $cred -AcceptKey -ConnectionTimeout 10

try {
  $killCommand = @"
PID=`$(netstat -lnpt 2>/dev/null | awk '`$4 ~ /:$Port`$/ && `$6 == "LISTEN" { split(`$7, a, "/"); print a[1]; exit }')
[ -n "`$PID" ] && kill "`$PID" 2>/dev/null || true
"@

  $commands = @(
    $killCommand,
    "killall lighttpd 2>/dev/null || true",
    "sleep 1",
    "netstat -lnpt 2>/dev/null | grep ':$Port ' || true"
  )

  foreach ($command in $commands) {
    $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 30000
    if ($result.Output) { $result.Output }
    if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
  }

  Write-Output "Stopped router-hosted UI on port $Port"
}
finally {
  Remove-SSHSession -SSHSession $session | Out-Null
}
