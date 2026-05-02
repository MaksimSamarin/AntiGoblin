param(
  [string]$RouterHost,
  [int]$Port = 0,
  [string]$RouterUser
)

. (Join-Path $PSScriptRoot '_load-env.ps1')

if (-not $RouterHost) { $RouterHost = if ($env:ROUTER_HOST) { $env:ROUTER_HOST } else { '192.168.1.1' } }
if (-not $RouterUser) { $RouterUser = if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' } }
if (-not $Port -or $Port -le 0) { $Port = if ($env:ANTIGOBLIN_UI_PORT) { [int]$env:ANTIGOBLIN_UI_PORT } else { 8899 } }

if (-not $env:ROUTER_SSH_PASSWORD) { throw "ROUTER_SSH_PASSWORD is not set. Put it in .env or export it before running." }
$routerPassword = $env:ROUTER_SSH_PASSWORD
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($RouterUser, $sec)

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
