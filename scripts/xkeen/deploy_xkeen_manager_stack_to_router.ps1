param(
  [string]$RouterHost,
  [int]$Port = 0,
  [string]$RouterUser
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_load-env.ps1')

if (-not $RouterHost) { $RouterHost = if ($env:ROUTER_HOST) { $env:ROUTER_HOST } else { '192.168.1.1' } }
if (-not $RouterUser) { $RouterUser = if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' } }
if (-not $Port -or $Port -le 0) { $Port = if ($env:ANTIGOBLIN_UI_PORT) { [int]$env:ANTIGOBLIN_UI_PORT } else { 8899 } }

if (-not $env:ROUTER_SSH_PASSWORD) { throw "ROUTER_SSH_PASSWORD is not set. Put it in .env or export it before running." }

Write-Output "Deploying XKeen Manager UI..."
& (Join-Path $PSScriptRoot 'deploy_xkeen_manager_ui_to_router.ps1') -RouterHost $RouterHost -RouterUser $RouterUser
if (-not $?) {
  throw "deploy_xkeen_manager_ui_to_router.ps1 failed"
}

Write-Output "Deploying XKeen Manager backend..."
& (Join-Path $PSScriptRoot 'deploy_xkeen_manager_backend_to_router.ps1') -RouterHost $RouterHost -RouterUser $RouterUser
if (-not $?) {
  throw "deploy_xkeen_manager_backend_to_router.ps1 failed"
}

Write-Output "Persisting UI port to /opt/etc/antigoblin.conf..."
# S26antigoblin (init.d) reads PORT from this file at boot. Without the
# write, `deploy_stack ... -Port N` only affects the running uhttpd
# instance; after a reboot the init script falls back to the previous
# value (or the default 8899) — silent drift between dev and prod port.
$writeConfCmd = "printf 'PORT=%s`n' '$Port' > /opt/etc/antigoblin.conf && chmod 644 /opt/etc/antigoblin.conf"
& python (Join-Path $PSScriptRoot 'router_ssh.py') `
    --host $RouterHost --user $RouterUser run --command $writeConfCmd
if (-not $?) {
  Write-Warning "Failed to write /opt/etc/antigoblin.conf on router (non-fatal; boot may fall back to old port)."
}

Write-Output "Starting router-hosted UI..."
& (Join-Path $PSScriptRoot 'start_xkeen_manager_ui_router.ps1') -RouterHost $RouterHost -Port $Port -RouterUser $RouterUser
if (-not $?) {
  throw "start_xkeen_manager_ui_router.ps1 failed"
}

Write-Output "Done. Open http://$RouterHost`:$Port/"
