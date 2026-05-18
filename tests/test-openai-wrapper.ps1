$ErrorActionPreference = "Stop"

$script = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\opencode-openai.ps1"
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("ocai-test-" + [guid]::NewGuid().ToString("N"))
$bin = Join-Path $temp "bin"
$capture = Join-Path $temp "capture.json"
$oldUserProfile = $env:USERPROFILE
$oldPath = $env:Path
$oldCapture = $env:OCAI_TEST_CAPTURE
$oldFailCodes = $env:OCAI_FAIL_LIMIT_CODES
$oldFailText = $env:OCAI_FAIL_TEXT

try {
  New-Item -ItemType Directory -Path $bin -Force | Out-Null
  @'
$profileCode = switch -Wildcard ($env:XDG_DATA_HOME) {
  "*share-opencode-openai-primary-personal" { "pp"; break }
  "*share-opencode-openai-primary-shared" { "ps"; break }
  "*share-opencode-openai-secondary-personal" { "sp"; break }
  "*share-opencode-openai-secondary-shared" { "ss"; break }
  default { "unknown" }
}

$data = [ordered]@{
  PROFILE = $profileCode
  OPENCODE_OPENAI_PROFILE = $env:OPENCODE_OPENAI_PROFILE
  XDG_DATA_HOME = $env:XDG_DATA_HOME
  OPENCODE_DB = $env:OPENCODE_DB
  ARGS = @($args)
}
$data | ConvertTo-Json -Compress | Add-Content -LiteralPath $env:OCAI_TEST_CAPTURE -Encoding UTF8

$limitCodes = @($env:OCAI_FAIL_LIMIT_CODES -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($limitCodes -contains $profileCode) {
  if ($env:OCAI_FAIL_TEXT) { $env:OCAI_FAIL_TEXT } else { "usage limit reached" }
  exit 42
}

"ok"
exit 0
'@ | Set-Content -LiteralPath (Join-Path $bin "opencode-stub.ps1") -Encoding ASCII

  @'
@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0opencode-stub.ps1" %*
exit /b %ERRORLEVEL%
'@ | Set-Content -LiteralPath (Join-Path $bin "opencode.cmd") -Encoding ASCII

  $env:USERPROFILE = $temp
  $env:Path = "$bin;$oldPath"
  $env:OCAI_TEST_CAPTURE = $capture
  $env:OCAI_FAIL_LIMIT_CODES = ""

  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script pp debug paths | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "ocai helper exited with $LASTEXITCODE"
  }

  $actual = Get-Content -LiteralPath $capture | Select-Object -Last 1 | ConvertFrom-Json
  $expectedDataHome = Join-Path $temp ".local\share-opencode-openai-primary-personal"
  $expectedDb = Join-Path $temp ".local\share\opencode\opencode.db"

  if ($actual.XDG_DATA_HOME -ne $expectedDataHome) {
    throw "Expected XDG_DATA_HOME '$expectedDataHome', got '$($actual.XDG_DATA_HOME)'"
  }

  if ($actual.OPENCODE_OPENAI_PROFILE -ne "pp") {
    throw "Expected OPENCODE_OPENAI_PROFILE 'pp', got '$($actual.OPENCODE_OPENAI_PROFILE)'"
  }

  if ($actual.OPENCODE_DB -ne $expectedDb) {
    throw "Expected OPENCODE_DB '$expectedDb', got '$($actual.OPENCODE_DB)'"
  }

  if (@($actual.ARGS)[0] -ne "debug" -or @($actual.ARGS)[1] -ne "paths") {
    throw "Expected forwarded args 'debug paths', got '$($actual.ARGS -join " ")'"
  }

  Remove-Item -LiteralPath $capture -Force
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script debug paths | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "ocai default helper exited with $LASTEXITCODE"
  }

  $default = Get-Content -LiteralPath $capture | Select-Object -Last 1 | ConvertFrom-Json
  if ($default.PROFILE -ne "pp") {
    throw "Expected default profile pp, got '$($default.PROFILE)'"
  }

  if (@($default.ARGS)[0] -ne "debug" -or @($default.ARGS)[1] -ne "paths") {
    throw "Expected default forwarded args 'debug paths', got '$($default.ARGS -join " ")'"
  }

  Remove-Item -LiteralPath $capture -Force
  $env:OCAI_FAIL_LIMIT_CODES = "pp,ps"
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script run "hello" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "ocai fallback run exited with $LASTEXITCODE"
  }

  $attempts = @(Get-Content -LiteralPath $capture | ForEach-Object { $_ | ConvertFrom-Json })
  $profiles = @($attempts | ForEach-Object { $_.PROFILE })
  if (($profiles -join ",") -ne "pp,ps,sp") {
    throw "Expected fallback profiles pp,ps,sp, got '$($profiles -join ",")'"
  }

  $last = $attempts[-1]
  if (@($last.ARGS)[0] -ne "run" -or @($last.ARGS)[1] -ne "hello") {
    throw "Expected fallback forwarded args 'run hello', got '$($last.ARGS -join " ")'"
  }

  Remove-Item -LiteralPath $capture -Force
  $env:OCAI_FAIL_LIMIT_CODES = "pp"
  $env:OCAI_FAIL_TEXT = "quota configuration missing"
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script run "hello" | Out-Null
  if ($LASTEXITCODE -ne 42) {
    throw "Expected non-limit quota text to stop with exit 42, got $LASTEXITCODE"
  }

  $nonLimitAttempts = @(Get-Content -LiteralPath $capture | ForEach-Object { $_ | ConvertFrom-Json })
  $nonLimitProfiles = @($nonLimitAttempts | ForEach-Object { $_.PROFILE })
  if (($nonLimitProfiles -join ",") -ne "pp") {
    throw "Expected non-limit quota text to stay on pp, got '$($nonLimitProfiles -join ",")'"
  }

  "PASS: ocai profiles use isolated auth storage, shared session DB, default pp, and run fallback"
} finally {
  $env:USERPROFILE = $oldUserProfile
  $env:Path = $oldPath
  $env:OCAI_TEST_CAPTURE = $oldCapture
  $env:OCAI_FAIL_LIMIT_CODES = $oldFailCodes
  $env:OCAI_FAIL_TEXT = $oldFailText
  if (Test-Path -LiteralPath $temp) {
    Remove-Item -LiteralPath $temp -Recurse -Force
  }
}
