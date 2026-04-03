param(
  [string]$RouterHost = "192.168.1.1",
  [string]$RouterUser = $(if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' }),
  [string]$RemoteRoot = "/opt/share/xkeen-manager"
)

$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($RouterUser, $sec)

Import-Module Posh-SSH -ErrorAction Stop

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$uiRoot = Join-Path $repoRoot 'ui\xkeen-manager'
$files = @('index.html', 'app.js', 'styles.css', 'antigoblin-logo.png')

function Send-RemoteFileBase64 {
  param(
    [object]$Session,
    [string]$LocalPath,
    [string]$RemotePath
  )

  $bytes = [System.IO.File]::ReadAllBytes($LocalPath)
  $b64 = [Convert]::ToBase64String($bytes)
  $chunks = for ($i = 0; $i -lt $b64.Length; $i += 3500) {
    $b64.Substring($i, [Math]::Min(3500, $b64.Length - $i))
  }

  Invoke-SSHCommand -SSHSession $Session -Command ": > /tmp/xkeen-ui-upload.b64" -TimeOut 30000 | Out-Null

  foreach ($chunk in $chunks) {
    $append = Invoke-SSHCommand -SSHSession $Session -Command "printf '%s' '$chunk' >> /tmp/xkeen-ui-upload.b64" -TimeOut 30000
    if ($append.ExitStatus -ne 0) {
      throw "Failed to append upload chunk for $RemotePath"
    }
  }

  $finish = Invoke-SSHCommand -SSHSession $Session -Command "/opt/bin/base64 -d /tmp/xkeen-ui-upload.b64 > '$RemotePath' && rm -f /tmp/xkeen-ui-upload.b64 && ls -lh '$RemotePath'" -TimeOut 30000
  if ($finish.ExitStatus -ne 0) {
    throw "Failed to decode/upload $RemotePath"
  }
  if ($finish.Output) { $finish.Output }
  if ($finish.Error) { Write-Output '--- STDERR ---'; $finish.Error }
}

foreach ($file in $files) {
  $path = Join-Path $uiRoot $file
  if (-not (Test-Path $path)) {
    throw "Missing UI file: $path"
  }
}

$session = New-SSHSession -ComputerName $RouterHost -Credential $cred -AcceptKey -ConnectionTimeout 10

try {
  $prep = @(
    "mkdir -p $RemoteRoot"
  )

  foreach ($command in $prep) {
    $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 30000
    if ($result.Output) { $result.Output }
    if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
  }

  foreach ($file in $files) {
    $localFile = Join-Path $uiRoot $file
    $remoteFile = "$RemoteRoot/$file"
    Send-RemoteFileBase64 -Session $session -LocalPath $localFile -RemotePath $remoteFile
    Write-Output "Uploaded: $localFile -> $remoteFile"
  }

  $verify = Invoke-SSHCommand -SSHSession $session -Command "ls -lh $RemoteRoot" -TimeOut 30000
  if ($verify.Output) { $verify.Output }
  if ($verify.Error) { Write-Output '--- STDERR ---'; $verify.Error }
}
finally {
  Remove-SSHSession -SSHSession $session | Out-Null
}
