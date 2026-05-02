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

Write-Output "Starting router-hosted UI..."
& (Join-Path $PSScriptRoot 'start_xkeen_manager_ui_router.ps1') -RouterHost $RouterHost -Port $Port -RouterUser $RouterUser
if (-not $?) {
  throw "start_xkeen_manager_ui_router.ps1 failed"
}

Write-Output "Done. Open http://$RouterHost`:$Port/"
