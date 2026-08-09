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
  # remount-hook is installed to usb.d only. Historically shipped in both
  # fs.d and usb.d, which caused a double-fire on USB Entware mounts and
  # raced with selfheal. RemoteFsHook is kept only to clean up the legacy
  # copy on upgrade.
  [string]$RemoteFsHookLegacy = "/opt/etc/ndm/fs.d/50-antigoblin.sh",
  [string]$RemoteUsbHook = "/opt/etc/ndm/usb.d/50-antigoblin.sh",
  [string]$RemoteNetfilterHook = "/opt/etc/ndm/netfilter.d/50-antigoblin.sh"
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
$localNetfilterHook = Join-Path $repoRoot 'scripts\xkeen\antigoblin-netfilter-hook.sh'

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
    [string]$Mode = '755',
    [switch]$IfMissing
  )

  if ($IfMissing) {
    & $python $sshHelper --host $RouterHost --user $RouterUser run --command "test -f '$RemotePath'"
    if ($LASTEXITCODE -eq 0) {
      Write-Output "skip existing: $RemotePath"
      return
    }
  }

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
if (-not (Test-Path $localNetfilterHook)) {
  throw "Missing netfilter hook: $localNetfilterHook"
}

Invoke-RouterCommand -Command "mkdir -p $RemoteRoot"
Invoke-RouterCommand -Command "mkdir -p $RemoteApiDir"
Invoke-RouterCommand -Command "mkdir -p $RemoteRuntimeDir"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/cron.1min"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/xray/configs"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/sing-box"
Invoke-RouterCommand -Command "mkdir -p /opt/etc/ndm/netfilter.d"
Invoke-RouterCommand -Command "opkg update >/dev/null 2>&1 || true"
Invoke-RouterCommand -Command "opkg install uhttpd_kn >/dev/null 2>&1 || true"
Invoke-RouterCommand -Command "opkg install conntrack >/dev/null 2>&1 || true"
Invoke-RouterCommand -Command "opkg install tar gzip wget ca-bundle >/dev/null 2>&1 || true"

Send-RemoteFile -LocalPath $localApi -RemotePath "$RemoteApiDir/routing.cgi"
Send-RemoteFile -LocalPath $localSelfHeal -RemotePath "$RemoteApiDir/xkeen-selfheal.sh"
Send-RemoteFile -LocalPath $localRuntime -RemotePath "$RemoteApiDir/xkeen-runtime.sh"
# 02_relay.json и sing-box/xkeen.json — runtime-сгенерируемые файлы
# (перезаписываются backend'ом из state.json при каждом Apply). Sample-файл
# трогаем только если файла ещё нет на роутере (первая установка).
Send-RemoteFile -LocalPath $localXrayRelay -RemotePath "/opt/etc/xray/configs/02_relay.json" -Mode '644' -IfMissing
Send-RemoteFile -LocalPath $localSingboxConfig -RemotePath "/opt/etc/sing-box/xkeen.json" -Mode '644' -IfMissing
Send-RemoteFile -LocalPath $localSelfhealLoop -RemotePath $RemoteSelfhealLoop
Send-RemoteFile -LocalPath $localSelfhealInit -RemotePath $RemoteSelfhealInit
Send-RemoteFile -LocalPath $localSingboxInit -RemotePath $RemoteSingboxInit
Send-RemoteFile -LocalPath $localSysctlInit -RemotePath $RemoteSysctlInit
Send-RemoteFile -LocalPath $localInitScript -RemotePath $RemoteInitScript
Send-RemoteFile -LocalPath $localCronScript -RemotePath $RemoteCronScript
Send-RemoteFile -LocalPath $localRemountHook -RemotePath $RemoteUsbHook
Send-RemoteFile -LocalPath $localNetfilterHook -RemotePath $RemoteNetfilterHook
Invoke-RouterCommand -Command "rm -f '$RemoteFsHookLegacy' 2>/dev/null || true"


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
    aarch64|arm64)   ARCH_CANDIDATES="arm64-musl arm64" ;;
    armv7l|armv7*)   ARCH_CANDIDATES="armv7-musl armv7" ;;
    mipsel*)         ARCH_CANDIDATES="mipsle-softfloat mipsle" ;;
    mips*)           ARCH_CANDIDATES="mips-softfloat mips" ;;
    x86_64|amd64)    ARCH_CANDIDATES="amd64-musl amd64" ;;
    *)               ARCH_CANDIDATES="$(uname -m)" ;;
  esac
  FETCH="curl"; [ -x /opt/bin/curl ] || FETCH="wget"
  rm -rf /tmp/antigoblin-sing-box /tmp/antigoblin-sing-box.tar.gz
  mkdir -p /tmp/antigoblin-sing-box
  ok=0
  for arch_try in $ARCH_CANDIDATES; do
    url="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${arch_try}.tar.gz"
    if [ "$FETCH" = "curl" ]; then
      /opt/bin/curl -fsSL -o /tmp/antigoblin-sing-box.tar.gz "$url" 2>/dev/null && { ok=1; break; }
    else
      wget -q -O /tmp/antigoblin-sing-box.tar.gz "$url" 2>/dev/null && { ok=1; break; }
    fi
  done
  if [ "$ok" = "1" ]; then
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
Invoke-RouterCommand -Command "chmod 755 '$RemoteSelfhealLoop' '$RemoteSelfhealInit' '$RemoteSingboxInit' '$RemoteSysctlInit' '$RemoteInitScript' '$RemoteCronScript' '$RemoteUsbHook' '$RemoteNetfilterHook' && '$RemoteSysctlInit' start >/dev/null 2>&1 || true && '$RemoteSingboxInit' restart >/dev/null 2>&1 || true && '$RemoteSelfhealInit' restart >/dev/null 2>&1 || true && '$RemoteInitScript' restart >/dev/null 2>&1 || true"
