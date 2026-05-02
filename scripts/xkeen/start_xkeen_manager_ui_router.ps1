param(
  [string]$RouterHost,
  [int]$Port = 0,
  [string]$RouterUser,
  [string]$RemoteRoot = "/opt/share/xkeen-manager"
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_load-env.ps1')

if (-not $RouterHost) { $RouterHost = if ($env:ROUTER_HOST) { $env:ROUTER_HOST } else { '192.168.1.1' } }
if (-not $RouterUser) { $RouterUser = if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' } }
if (-not $Port -or $Port -le 0) { $Port = if ($env:ANTIGOBLIN_UI_PORT) { [int]$env:ANTIGOBLIN_UI_PORT } else { 8899 } }

if (-not $env:ROUTER_SSH_PASSWORD) { throw "ROUTER_SSH_PASSWORD is not set. Put it in .env or export it before running." }
$python = (Get-Command python -ErrorAction Stop).Source
$sshHelper = Join-Path $PSScriptRoot 'router_ssh.py'

function Invoke-RouterCommand {
  param(
    [string]$Command
  )

  & $python $sshHelper --host $RouterHost --user $RouterUser run --command $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Router command failed: $Command"
  }
}

Invoke-RouterCommand -Command "mkdir -p /opt/var/run"
Invoke-RouterCommand -Command "test -d $RemoteRoot"
Invoke-RouterCommand -Command "killall lighttpd 2>/dev/null || true"
Invoke-RouterCommand -Command "pkill -f '/opt/sbin/uhttpd -f -p 0.0.0.0:$Port' 2>/dev/null || true"
Invoke-RouterCommand -Command "rm -f $RemoteRoot/httpd-auth.conf"
Invoke-RouterCommand -Command "sleep 1"

$alreadyListening = (& $python $sshHelper --host $RouterHost --user $RouterUser run --command "if netstat -lnpt 2>/dev/null | grep -q ':$Port '; then echo YES; else echo NO; fi")
if ($LASTEXITCODE -ne 0) {
  throw "Failed to verify UI listener on $RouterHost"
}
if ($alreadyListening -match 'YES') {
  Write-Output "UI already listening on $Port"
} else {
  Invoke-RouterCommand -Command ": > /opt/var/log/xkeen-manager-uhttpd.log && cd $RemoteRoot && /opt/sbin/uhttpd -f -p 0.0.0.0:$Port -h $RemoteRoot -I index.html -x /api -i .cgi=/bin/sh -r 'AntiGoblin' >/opt/var/log/xkeen-manager-uhttpd.log 2>&1 &"
}

Invoke-RouterCommand -Command "sleep 2"
Invoke-RouterCommand -Command "netstat -lnpt 2>/dev/null | grep ':$Port ' || true"
Invoke-RouterCommand -Command "tail -n 10 /opt/var/log/xkeen-manager-uhttpd.log 2>/dev/null || true"

Write-Output "UI URL: http://$RouterHost`:$Port/"
Write-Output "UI auth: router web session"
