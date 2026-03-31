param(
  [int]$Port = 8765
)

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$uiRoot = Join-Path $repoRoot 'ui\xkeen-manager'

if (-not (Test-Path $uiRoot)) {
  throw "UI directory not found: $uiRoot"
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
  $python = Get-Command py -ErrorAction SilentlyContinue
}

if (-not $python) {
  throw 'Python launcher not found. Install Python or add it to PATH.'
}

$cmd = if ($python.Name -eq 'py.exe' -or $python.Name -eq 'py') {
  "py -m http.server $Port"
} else {
  "python -m http.server $Port"
}

Write-Host "Starting XKeen Manager UI at http://127.0.0.1:$Port/" -ForegroundColor Green
Write-Host "UI root: $uiRoot"

Start-Process "http://127.0.0.1:$Port/"
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location -LiteralPath '$uiRoot'; $cmd"
