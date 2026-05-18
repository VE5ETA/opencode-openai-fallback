$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot "install.ps1"
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("ocof-install-test-" + [guid]::NewGuid().ToString("N"))
$bin = Join-Path $temp "bin"
$npmCapture = Join-Path $temp "npm-calls.txt"
$powerShell = Join-Path $PSHOME "powershell.exe"
$minimalPath = "$bin;$env:SystemRoot\System32\WindowsPowerShell\v1.0;$env:SystemRoot\System32;$env:SystemRoot"
$oldUserProfile = $env:USERPROFILE
$oldPath = $env:Path

try {
  New-Item -ItemType Directory -Path $bin -Force | Out-Null
  @'
@echo off
echo %*>>"%OCOF_NPM_CAPTURE%"
echo @echo off>"%~dp0opencode.cmd"
echo exit /b 0>>"%~dp0opencode.cmd"
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $bin "npm.cmd") -Encoding ASCII

  $env:USERPROFILE = $temp
  $env:Path = $minimalPath
  $env:OCOF_NPM_CAPTURE = $npmCapture

  $existingConfigDir = Join-Path $temp ".config\opencode"
  New-Item -ItemType Directory -Path $existingConfigDir -Force | Out-Null
  @'
{
  // Existing user config with JSONC trailing commas.
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "existing-plugin",
  ],
}
'@ | Set-Content -LiteralPath (Join-Path $existingConfigDir "opencode.jsonc") -Encoding UTF8

  $existingProfileDir = Join-Path $temp "Documents\WindowsPowerShell"
  New-Item -ItemType Directory -Path $existingProfileDir -Force | Out-Null
  $existingProfilePath = Join-Path $existingProfileDir "Microsoft.PowerShell_profile.ps1"
  "# existing profile content" | Set-Content -LiteralPath $existingProfilePath -Encoding UTF8

  & $powerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer -SourceRoot $repoRoot | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "install.ps1 exited with $LASTEXITCODE"
  }

  $pluginPath = Join-Path $temp ".config\opencode\plugin\openai-auto-fallback.mjs"
  $helperPath = Join-Path $temp ".config\opencode\opencode-openai.ps1"
  $configPath = Join-Path $temp ".config\opencode\opencode.jsonc"
  $profilePath = Join-Path $temp "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"

  if (-not (Test-Path -LiteralPath $pluginPath)) { throw "Expected plugin at $pluginPath" }
  if (-not (Test-Path -LiteralPath $helperPath)) { throw "Expected helper at $helperPath" }
  if (-not (Test-Path -LiteralPath $configPath)) { throw "Expected config at $configPath" }
  if (-not (Test-Path -LiteralPath $profilePath)) { throw "Expected PowerShell profile at $profilePath" }

  $npmText = Get-Content -LiteralPath $npmCapture -Raw
  if ($npmText -notmatch 'install\s+-g\s+opencode-ai') {
    throw "Expected npm install -g opencode-ai, got: $npmText"
  }

  $config = Get-Content -LiteralPath $configPath -Raw
  if ($config -notmatch '\./plugin/openai-auto-fallback\.mjs') {
    throw "Expected plugin entry in opencode config"
  }
  if ($config -notmatch 'existing-plugin') {
    throw "Expected existing plugin entry to be preserved"
  }

  $profile = Get-Content -LiteralPath $profilePath -Raw
  if ($profile -notmatch 'opencode-openai-fallback BEGIN' -or $profile -notmatch 'function ocai' -or $profile -notmatch 'function opencode') {
    throw "Expected managed PowerShell profile block with ocai and opencode functions"
  }
  if ($profile -notmatch 'Get-Command opencode\.cmd' -or $profile -notmatch 'Get-Command opencode\.exe') {
    throw "Expected ocraw to support both opencode.cmd and opencode.exe"
  }
  $profileBackups = @(Get-ChildItem -LiteralPath $existingProfileDir -Filter "Microsoft.PowerShell_profile.ps1.backup-before-openai-fallback-*" -File)
  if ($profileBackups.Count -ne 1) {
    throw "Expected one PowerShell profile backup, found $($profileBackups.Count)"
  }

  Remove-Item -LiteralPath $temp -Recurse -Force
  New-Item -ItemType Directory -Path $bin -Force | Out-Null
  @'
@echo off
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $bin "opencode.cmd") -Encoding ASCII
  $env:USERPROFILE = $temp
  $env:Path = $minimalPath

  & $powerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer -SourceRoot $repoRoot -NoOpencodeFunction | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "install.ps1 -NoOpencodeFunction exited with $LASTEXITCODE"
  }

  $profilePath = Join-Path $temp "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
  $profile = Get-Content -LiteralPath $profilePath -Raw
  if ($profile -notmatch 'function ocai') {
    throw "Expected ocai function in no-wrapper mode"
  }
  if ($profile -match 'function opencode') {
    throw "Did not expect opencode function in no-wrapper mode"
  }

  "PASS: install.ps1 installs opencode, opencode fallback files, config, and profile functions"
} finally {
  $env:USERPROFILE = $oldUserProfile
  $env:Path = $oldPath
  $env:OCOF_NPM_CAPTURE = $null
  if (Test-Path -LiteralPath $temp) {
    Remove-Item -LiteralPath $temp -Recurse -Force
  }
}
