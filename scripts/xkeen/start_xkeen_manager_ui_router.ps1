param(
  [string]$RouterHost = "192.168.1.1",
  [int]$Port = 8899,
  [string]$RouterUser = 'root',
  [string]$RemoteRoot = "/opt/share/xkeen-manager"
)

$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('RouterUser') -and $env:ROUTER_SSH_USER) {
  $RouterUser = $env:ROUTER_SSH_USER
}

$null = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
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
