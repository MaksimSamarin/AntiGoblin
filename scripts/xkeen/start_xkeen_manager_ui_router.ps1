param(
  [string]$RouterHost = "192.168.1.1",
  [int]$Port = 8899,
  [string]$RouterUser = $(if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' }),
  [string]$RemoteRoot = "/opt/share/xkeen-manager"
)

$routerPassword = if ($env:ROUTER_SSH_PASSWORD) { $env:ROUTER_SSH_PASSWORD } else { throw "Set ROUTER_SSH_PASSWORD before running this script." }
$sec = ConvertTo-SecureString $routerPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($RouterUser, $sec)

Import-Module Posh-SSH -ErrorAction Stop

$session = New-SSHSession -ComputerName $RouterHost -Credential $cred -AcceptKey -ConnectionTimeout 10

try {
  $commands = @(
    "mkdir -p /opt/var/run",
    "test -d $RemoteRoot",
    "killall lighttpd 2>/dev/null || true",
    "pkill -f '/opt/sbin/uhttpd -f -p 0.0.0.0:$Port' 2>/dev/null || true",
    "rm -f $RemoteRoot/httpd-auth.conf",
    "cd $RemoteRoot && /opt/sbin/uhttpd -f -p 0.0.0.0:$Port -h $RemoteRoot -I index.html -x /api -i .cgi=/bin/sh -r 'AntiGoblin' >/opt/var/log/xkeen-manager-uhttpd.log 2>&1 &",
    "sleep 2",
    "netstat -lnpt 2>/dev/null | grep ':$Port ' || true",
    "tail -n 10 /opt/var/log/xkeen-manager-uhttpd.log 2>/dev/null || true"
  )

  foreach ($command in $commands) {
    $result = Invoke-SSHCommand -SSHSession $session -Command $command -TimeOut 30000
    if ($result.ExitStatus -ne 0 -and $command -eq "test -d $RemoteRoot") {
      throw "Remote UI directory not found: $RemoteRoot. Run deploy_xkeen_manager_ui_to_router.ps1 first."
    }
    if ($result.Output) { $result.Output }
    if ($result.Error) { Write-Output '--- STDERR ---'; $result.Error }
  }

  Write-Output "UI URL: http://$RouterHost`:$Port/"
  Write-Output "UI auth: router web session"
}
finally {
  Remove-SSHSession -SSHSession $session | Out-Null
}
