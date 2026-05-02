# Dot-source this from any deploy script:
#   . (Join-Path $PSScriptRoot '_load-env.ps1')
#
# Loads KEY=VALUE pairs from <repo-root>/.env into the current process
# environment. Lines starting with # are skipped. Existing env values
# win over .env (so an explicit `$env:VAR = ...` before invocation is
# never overwritten).

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile = Join-Path $repoRoot '.env'

if (Test-Path $envFile) {
  Get-Content -Path $envFile -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if (-not $line) { return }
    if ($line.StartsWith('#')) { return }
    $eq = $line.IndexOf('=')
    if ($eq -lt 1) { return }
    $key = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim()
    if (($value.Length -ge 2) -and (
          ($value.StartsWith('"') -and $value.EndsWith('"')) -or
          ($value.StartsWith("'") -and $value.EndsWith("'"))
        )) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    if (-not [Environment]::GetEnvironmentVariable($key, 'Process')) {
      [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
  }
}
