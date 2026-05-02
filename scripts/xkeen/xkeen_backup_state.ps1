param(
  [string]$RouterHost,
  [string]$RouterUser
)

. (Join-Path $PSScriptRoot '_load-env.ps1')

if (-not $RouterHost) { $RouterHost = if ($env:ROUTER_HOST) { $env:ROUTER_HOST } else { '192.168.1.1' } }
if (-not $RouterUser) { $RouterUser = if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' } }

if (-not $env:ROUTER_SSH_PASSWORD) { throw "ROUTER_SSH_PASSWORD is not set. Put it in .env or export it before running." }
$routerPassword = $env:ROUTER_SSH_PASSWORD
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($RouterUser, $sec)

Import-Module Posh-SSH

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "snapshots\xkeen-migration\$timestamp"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$session = New-SSHSession -ComputerName $RouterHost -Credential $cred -AcceptKey -ConnectionTimeout 10

$commands = @(
  "mkdir -p /tmp/xkeen-backup-$timestamp",
  "cp -a /opt/etc/xray /tmp/xkeen-backup-$timestamp/xray 2>/dev/null || true",
  "cp -a /opt/etc/init.d/S24xray /tmp/xkeen-backup-$timestamp/S24xray 2>/dev/null || true",
  "sh -c 'ip rule show > /tmp/xkeen-backup-$timestamp/ip-rule.txt'",
  "sh -c 'ip route show table all > /tmp/xkeen-backup-$timestamp/ip-route-all.txt'",
  "sh -c 'iptables -t mangle -S > /tmp/xkeen-backup-$timestamp/iptables-mangle.txt'",
  "sh -c 'iptables -t nat -S > /tmp/xkeen-backup-$timestamp/iptables-nat.txt 2>/dev/null || true'",
  "ndmc -c 'show version' > /tmp/xkeen-backup-$timestamp/show-version.txt",
  "cd /tmp && /opt/bin/tar -czf xkeen-backup-$timestamp.tar.gz xkeen-backup-$timestamp",
  "ls -lh /tmp/xkeen-backup-$timestamp.tar.gz"
)

foreach ($command in $commands) {
  Write-Output "=== CMD: $command ==="
  $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 120000
  if ($result.Output) { $result.Output }
  if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
}

$scpParams = @{
  ComputerName = $RouterHost
  Credential   = $cred
  AcceptKey    = $true
  Path         = "/tmp/xkeen-backup-$timestamp.tar.gz"
  PathType     = 'File'
  Destination  = $backupDir
}

Get-SCPItem @scpParams

Write-Output "Saved backup to: $backupDir"

Remove-SSHSession -SSHSession $session | Out-Null
