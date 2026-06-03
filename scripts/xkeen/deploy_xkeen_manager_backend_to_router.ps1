param(
  [string]$RouterHost,
  [string]$RouterUser,
  [string]$RemoteRoot = "/opt/share/xkeen-manager",
  [string]$RemoteApiDir = "/opt/share/xkeen-manager/api",
  [string]$RemoteRuntimeDir = "/opt/share/xkeen-manager/runtime",
  [string]$RemoteSelfhealLoop = "/opt/share/xkeen-manager/api/xkeen-selfheal-loop.sh",
  [string]$RemoteSelfhealInit = "/opt/etc/init.d/S25antigoblin-selfheal",
  [string]$RemoteSingboxInit = "/opt/etc/init.d/S24antigoblin-singbox",
  [string]$RemoteSysctlInit = "/opt/etc/init.d/S20antigoblin-sysctl",
  [string]$RemoteInitScript = "/opt/etc/init.d/S26antigoblin",
  [string]$RemoteCronScript = "/opt/etc/cron.1min/50-antigoblin-selfheal",
  [string]$RemoteFsHook = "/opt/etc/ndm/fs.d/50-antigoblin.sh",
  [string]$RemoteUsbHook = "/opt/etc/ndm/usb.d/50-antigoblin.sh"
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_load-env.ps1')

if (-not $RouterHost) { $RouterHost = if ($env:ROUTER_HOST) { $env:ROUTER_HOST } else { '192.168.1.1' } }
if (-not $RouterUser) { $RouterUser = if ($env:ROUTER_SSH_USER) { $env:ROUTER_SSH_USER } else { 'root' } }

if (-not $env:ROUTER_SSH_PASSWORD) { throw "ROUTER_SSH_PASSWORD is not set. Put it in .env or export it before running." }
$python = (Get-Command python -ErrorAction Stop).Source

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sshHelper = Join-Path $PSScriptRoot 'router_ssh.py'
$localApi = Join-Path $repoRoot 'ui\xkeen-manager\backend\routing.cgi'
$localSelfHeal = Join-Path $repoRoot 'ui\xkeen-manager\backend\xkeen-selfheal.sh'
$localRuntime = Join-Path $repoRoot 'ui\xkeen-manager\backend\xkeen-runtime.sh'
$localXrayRelay = Join-Path $repoRoot 'configs\xkeen\02_relay.sample.json'
$localSingboxConfig = Join-Path $repoRoot 'configs\xkeen\sing-box-xkeen.sample.json'
$localSelfhealLoop = Join-Path $repoRoot 'scripts\xkeen\antigoblin-selfheal-loop.sh'
$localSelfhealInit = Join-Path $repoRoot 'scripts\xkeen\antigoblin-selfheal.initd.sh'
$localSingboxInit = Join-Path $repoRoot 'scripts\xkeen\antigoblin-singbox.initd.sh'
$localSysctlInit = Join-Path $repoRoot 'scripts\xkeen\antigoblin-sysctl.initd.sh'
$localInitScript = Join-Path $repoRoot 'scripts\xkeen\antigoblin.initd.sh'
$localCronScript = Join-Path $repoRoot 'scripts\xkeen\antigoblin-selfheal.cron.sh'
$localRemountHook = Join-Path $repoRoot 'scripts\xkeen\antigoblin-remount-hook.sh'

function Invoke-RouterCommand {
  param(
    [string]$Command
  )

  if ($Command -match "`n") {
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
      Set-Content -Path $tmpFile -Value $Command -NoNewline
      Get-Content -Path $tmpFile -Raw | & $python $sshHelper --host $RouterHost --user $RouterUser run --stdin
    }
    finally {
      Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
  } else {
    & $python $sshHelper --host $RouterHost --user $RouterUser run --command $Command
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Router command failed: $Command"
  }
}

function Send-RemoteFile {
  param(
    [string]$LocalPath,
    [string]$RemotePath,
    [string]$Mode = '755'
  )

  & $python $sshHelper --host $RouterHost --user $RouterUser upload --local $LocalPath --remote $RemotePath --mode $Mode
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to upload $RemotePath"
  }
}

if (-not (Test-Path $localApi)) {
  throw "Missing backend file: $localApi"
}
if (-not (Test-Path $localSelfHeal)) {
  throw "Missing self-heal file: $localSelfHeal"
}
if (-not (Test-Path $localRuntime)) {
  throw "Missing runtime file: $localRuntime"
}
if (-not (Test-Path $localXrayRelay)) {
  throw "Missing xray relay config: $localXrayRelay"
}
if (-not (Test-Path $localSingboxConfig)) {
  throw "Missing sing-box config: $localSingboxConfig"
}
if (-not (Test-Path $localSelfhealLoop)) {
  throw "Missing self-heal loop script: $localSelfhealLoop"
}
if (-not (Test-Path $localSelfhealInit)) {
  throw "Missing self-heal init script: $localSelfhealInit"
}
if (-not (Test-Path $localSingboxInit)) {
  throw "Missing sing-box init script: $localSingboxInit"
}
if (-not (Test-Path $localSysctlInit)) {
  throw "Missing sysctl init script: $localSysctlInit"
}
if (-not (Test-Path $localInitScript)) {
  throw "Missing init script: $localInitScript"
}
if (-not (Test-Path $localCronScript)) {
  throw "Missing cron script: $localCronScript"
}
if (-not (Test-Path $localRemountHook)) {
  throw "Missing remount hook: $localRemountHook"
}

Invoke-RouterCommand -Command "mkdir -p $RemoteRoot"
Invoke-RouterCommand -Command "mkdir -p $RemoteApiDir"
Invoke-RouterCommand -Command "mkdir -p $RemoteRuntimeDir"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/cron.1min"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/xray/configs"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/sing-box"
Invoke-RouterCommand -Command "opkg update >/dev/null 2>&1 || true"
Invoke-RouterCommand -Command "opkg install uhttpd_kn >/dev/null 2>&1 || true"
Invoke-RouterCommand -Command "opkg install conntrack >/dev/null 2>&1 || true"
Invoke-RouterCommand -Command "opkg install tar gzip wget ca-bundle >/dev/null 2>&1 || true"

Send-RemoteFile -LocalPath $localApi -RemotePath "$RemoteApiDir/routing.cgi"
Send-RemoteFile -LocalPath $localSelfHeal -RemotePath "$RemoteApiDir/xkeen-selfheal.sh"
Send-RemoteFile -LocalPath $localRuntime -RemotePath "$RemoteApiDir/xkeen-runtime.sh"
Send-RemoteFile -LocalPath $localXrayRelay -RemotePath "/opt/etc/xray/configs/02_relay.json" -Mode '644'
Send-RemoteFile -LocalPath $localSingboxConfig -RemotePath "/opt/etc/sing-box/xkeen.json" -Mode '644'
Send-RemoteFile -LocalPath $localSelfhealLoop -RemotePath $RemoteSelfhealLoop
Send-RemoteFile -LocalPath $localSelfhealInit -RemotePath $RemoteSelfhealInit
Send-RemoteFile -LocalPath $localSingboxInit -RemotePath $RemoteSingboxInit
Send-RemoteFile -LocalPath $localSysctlInit -RemotePath $RemoteSysctlInit
Send-RemoteFile -LocalPath $localInitScript -RemotePath $RemoteInitScript
Send-RemoteFile -LocalPath $localCronScript -RemotePath $RemoteCronScript
Send-RemoteFile -LocalPath $localRemountHook -RemotePath $RemoteFsHook
Send-RemoteFile -LocalPath $localRemountHook -RemotePath $RemoteUsbHook


$cronCmd = @'
rm -f /opt/var/spool/cron/crontabs/root 2>/dev/null || true
CRON_INIT=""
for candidate in /opt/etc/init.d/S10cron /opt/etc/init.d/S05crond; do
  if [ -x "$candidate" ]; then
    CRON_INIT="$candidate"
    break
  fi
done
[ -n "$CRON_INIT" ] && "$CRON_INIT" restart >/dev/null 2>&1 || true
'@
Invoke-RouterCommand -Command $cronCmd
$installSingbox = @'
if ! command -v sing-box >/dev/null 2>&1; then
  SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.8}"
  case "$(uname -m)" in
    aarch64|arm64) SING_BOX_ARCH=arm64-musl ;;
    armv7l|armv7*) SING_BOX_ARCH=armv7 ;;
    mipsel*) SING_BOX_ARCH=mipsle ;;
    mips*) SING_BOX_ARCH=mips ;;
    *) SING_BOX_ARCH="$(uname -m)" ;;
  esac
  SING_BOX_URL="${SING_BOX_URL:-https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${SING_BOX_ARCH}.tar.gz}"
  rm -rf /tmp/antigoblin-sing-box /tmp/antigoblin-sing-box.tar.gz
  mkdir -p /tmp/antigoblin-sing-box
  if wget --no-check-certificate -O /tmp/antigoblin-sing-box.tar.gz "$SING_BOX_URL" >/dev/null 2>&1; then
    tar -xzf /tmp/antigoblin-sing-box.tar.gz -C /tmp/antigoblin-sing-box
    SING_BOX_BIN="$(find /tmp/antigoblin-sing-box -type f -name sing-box | head -n 1)"
    if [ -n "$SING_BOX_BIN" ]; then
      cp "$SING_BOX_BIN" /opt/sbin/sing-box
      chmod 755 /opt/sbin/sing-box
    fi
  fi
fi
'@
Invoke-RouterCommand -Command $installSingbox

$patchXrayInit = @'
XRAY_INIT="/opt/etc/init.d/S24xray"
if [ -f "$XRAY_INIT" ] && grep -q 'ARGS="run -confdir /opt/etc/xray"' "$XRAY_INIT" 2>/dev/null && ! grep -q 'ARGS="run -confdir /opt/etc/xray/configs"' "$XRAY_INIT" 2>/dev/null; then
  cp "$XRAY_INIT" "$XRAY_INIT.bak-antigoblin-confdir" 2>/dev/null || true
  sed 's#ARGS="run -confdir /opt/etc/xray"#ARGS="run -confdir /opt/etc/xray/configs"#' "$XRAY_INIT" > "$XRAY_INIT.tmp" \
    && cat "$XRAY_INIT.tmp" > "$XRAY_INIT" \
    && rm -f "$XRAY_INIT.tmp" \
    && chmod 755 "$XRAY_INIT"
fi
'@
Invoke-RouterCommand -Command $patchXrayInit
Invoke-RouterCommand -Command "chmod 755 '$RemoteSelfhealLoop' '$RemoteSelfhealInit' '$RemoteSingboxInit' '$RemoteSysctlInit' '$RemoteInitScript' '$RemoteCronScript' '$RemoteFsHook' '$RemoteUsbHook' && '$RemoteSysctlInit' start >/dev/null 2>&1 || true && '$RemoteSingboxInit' restart >/dev/null 2>&1 || true && '$RemoteSelfhealInit' restart >/dev/null 2>&1 || true && '$RemoteInitScript' restart >/dev/null 2>&1 || true"
