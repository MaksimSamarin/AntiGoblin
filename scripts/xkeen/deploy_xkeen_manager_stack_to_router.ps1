param(
  [string]$RouterHost = "192.168.2.1",
  [int]$Port = 8899
)

$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }

Write-Output "Deploying XKeen Manager UI..."
& (Join-Path $PSScriptRoot 'deploy_xkeen_manager_ui_to_router.ps1') -RouterHost $RouterHost
if ($LASTEXITCODE -ne 0) {
  throw "deploy_xkeen_manager_ui_to_router.ps1 failed"
}

Write-Output "Deploying XKeen Manager backend..."
& (Join-Path $PSScriptRoot 'deploy_xkeen_manager_backend_to_router.ps1') -RouterHost $RouterHost
if ($LASTEXITCODE -ne 0) {
  throw "deploy_xkeen_manager_backend_to_router.ps1 failed"
}

Write-Output "Starting router-hosted UI..."
& (Join-Path $PSScriptRoot 'start_xkeen_manager_ui_router.ps1') -RouterHost $RouterHost -Port $Port
if ($LASTEXITCODE -ne 0) {
  throw "start_xkeen_manager_ui_router.ps1 failed"
}

Write-Output "Done. Open http://$RouterHost`:$Port/"
