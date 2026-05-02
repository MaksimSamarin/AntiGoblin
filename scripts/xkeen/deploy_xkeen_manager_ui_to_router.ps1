param(
  [string]$RouterHost,
  [string]$RouterUser,
  [string]$RemoteRoot = "/opt/share/xkeen-manager"
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_load-env.ps1')

if (-not $RouterHost) { $RouterHost = if ($env:ROUTER_HOST) { $env:ROUTER_HOST } else { '192.168.1.1' } }
if (-not $RouterUser) { $RouterUser = if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' } }

if (-not $env:ROUTER_SSH_PASSWORD) { throw "ROUTER_SSH_PASSWORD is not set. Put it in .env or export it before running." }
$python = (Get-Command python -ErrorAction Stop).Source

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$uiRoot = Join-Path $repoRoot 'ui\xkeen-manager'
$sshHelper = Join-Path $PSScriptRoot 'router_ssh.py'
$files = @('index.html', 'app.js', 'styles.css', 'antigoblin-logo.png')

function Invoke-RouterCommand {
  param(
    [string]$Command
  )

  & $python $sshHelper --host $RouterHost --user $RouterUser run --command $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Router command failed: $Command"
  }
}

function Send-RemoteFile {
  param(
    [string]$LocalPath,
    [string]$RemotePath
  )

  & $python $sshHelper --host $RouterHost --user $RouterUser upload --local $LocalPath --remote $RemotePath --mode 644
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload $RemotePath"
  }
}

foreach ($file in $files) {
  $path = Join-Path $uiRoot $file
  if (-not (Test-Path $path)) {
    throw "Missing UI file: $path"
  }
}

Invoke-RouterCommand -Command "mkdir -p $RemoteRoot"

foreach ($file in $files) {
  $localFile = Join-Path $uiRoot $file
  $remoteFile = "$RemoteRoot/$file"
  Send-RemoteFile -LocalPath $localFile -RemotePath $remoteFile
  Write-Output "Uploaded: $localFile -> $remoteFile"
}

Invoke-RouterCommand -Command "ls -lh $RemoteRoot"
