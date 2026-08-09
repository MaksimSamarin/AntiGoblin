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
$python = (Get-Command python -ErrorAction Stop).Source
$sshHelper = Join-Path $PSScriptRoot 'router_ssh.py'

function Invoke-RouterCommand {
  param([string]$Command)
  & $python $sshHelper --host $RouterHost --user $RouterUser run --command $Command
  if ($LASTEXITCODE -ne 0) { throw "Router command failed: $Command" }
}

$killCommand = @"
PID=`$(netstat -lnpt 2>/dev/null | awk '`$4 ~ /:$Port`$/ && `$6 == "LISTEN" { split(`$7, a, "/"); print a[1]; exit }')
[ -n "`$PID" ] && kill "`$PID" 2>/dev/null || true
"@

Invoke-RouterCommand -Command $killCommand
Invoke-RouterCommand -Command "killall lighttpd 2>/dev/null || true"
Invoke-RouterCommand -Command "sleep 1"
Invoke-RouterCommand -Command "netstat -lnpt 2>/dev/null | grep ':$Port ' || true"

Write-Output "Stopped router-hosted UI on port $Port"
