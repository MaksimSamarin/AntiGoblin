$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('root', $sec)

Import-Module Posh-SSH

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$drafts = @(
  @{
    Local  = Join-Path $repoRoot 'configs\xkeen\04_outbounds.vdpsina-reality-draft.json'
    Remote = '/opt/var/xkeen-drafts/04_outbounds.json'
  },
  @{
    Local  = Join-Path $repoRoot 'configs\xkeen\05_routing.hydraroute-draft.json'
    Remote = '/opt/var/xkeen-drafts/05_routing.json'
  }
)

$session = New-SSHSession -ComputerName 192.168.2.1 -Credential $cred -AcceptKey -ConnectionTimeout 10

$mkdir = Invoke-SSHCommand -SSHSession $session -Command 'mkdir -p /opt/var/xkeen-drafts && ls -ld /opt/var/xkeen-drafts' -TimeOut 30000
if ($mkdir.Output) { $mkdir.Output }
if ($mkdir.Error) { Write-Output '--- STDERR ---'; $mkdir.Error }

foreach ($draft in $drafts) {
  $content = Get-Content -Raw $draft.Local
  $command = @"
cat > '$($draft.Remote)' <<'EOF'
$content
EOF
ls -lh '$($draft.Remote)'
"@

  $upload = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
  if ($upload.Output) { $upload.Output }
  if ($upload.Error) { Write-Output '--- STDERR ---'; $upload.Error }

  Write-Output "Staged: $($draft.Local) -> $($draft.Remote)"
}

$verify = Invoke-SSHCommand -SSHSession $session -Command 'find /opt/var/xkeen-drafts -maxdepth 1 -type f -exec ls -lh {} \; | sed -n "1,80p"' -TimeOut 30000
if ($verify.Output) { $verify.Output }
if ($verify.Error) { Write-Output '--- STDERR ---'; $verify.Error }

Remove-SSHSession -SSHSession $session | Out-Null
