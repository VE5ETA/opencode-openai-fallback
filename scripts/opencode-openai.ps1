$ErrorActionPreference = "Stop"

$profiles = [ordered]@{
  "pp" = @{
    Name = "Primary personal"
    Data = ".local\share-opencode-openai-primary-personal"
  }
  "ps" = @{
    Name = "Primary shared"
    Data = ".local\share-opencode-openai-primary-shared"
  }
  "sp" = @{
    Name = "Secondary personal"
    Data = ".local\share-opencode-openai-secondary-personal"
  }
  "ss" = @{
    Name = "Secondary shared"
    Data = ".local\share-opencode-openai-secondary-shared"
  }
}

$fallbackOrder = @("pp", "ps", "sp", "ss")

$aliases = @{
  "primary-personal" = "pp"
  "primary-shared" = "ps"
  "secondary-personal" = "sp"
  "secondary-shared" = "ss"
}

function Show-Usage {
  "Usage: ocai [login|pick] [pp|ps|sp|ss] [opencode args...]"
  ""
  "Profiles:"
  "  pp  Primary personal"
  "  ps  Primary shared"
  "  sp  Secondary personal"
  "  ss  Secondary shared"
  ""
  "Examples:"
  "  ocai"
  "  ocai debug paths"
  "  ocai pp"
  "  ocai login ps"
  '  ocai run "fix the tests"'
  '  ocai ss run "fix the tests"'
}

function Resolve-ProfileKey($selection) {
  $key = $selection.ToString().Trim().ToLowerInvariant()
  if ($aliases.ContainsKey($key)) {
    $key = $aliases[$key]
  }

  if (-not $profiles.Contains($key)) {
    return $null
  }

  return $key
}

function Get-NativeOpencodeCommand {
  $cmd = Get-Command opencode.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) {
    return $cmd.Source
  }

  $cmd = Get-Command opencode.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) {
    return $cmd.Source
  }

  return "opencode"
}

$opencodeCommand = Get-NativeOpencodeCommand

function Select-Profile {
  "OpenAI profile:"
  $keys = @($profiles.Keys)
  for ($i = 0; $i -lt $keys.Count; $i++) {
    $key = $keys[$i]
    "  $($i + 1). $key - $($profiles[$key].Name)"
  }

  $choice = (Read-Host "Choose 1-4 or code").Trim().ToLowerInvariant()
  if ($choice -match "^[1-4]$") {
    return $keys[[int]$choice - 1]
  }

  return $choice
}

$action = "run"
$selection = "pp"
$opencodeArgs = @()
$explicitProfile = $false

if ($args.Count -gt 0) {
  $first = $args[0].ToLowerInvariant()
  if ($first -in @("help", "-h", "--help")) {
    Show-Usage
    exit 0
  }

  if ($first -in @("login", "auth")) {
    $action = "login"
    if ($args.Count -gt 1) {
      $selection = $args[1]
      $explicitProfile = $true
    }
  } elseif ($first -in @("pick", "select", "profiles")) {
    $selection = Select-Profile
    $explicitProfile = $true
    if ($args.Count -gt 1) {
      $opencodeArgs = $args[1..($args.Count - 1)]
    }
  } elseif (Resolve-ProfileKey $first) {
    $selection = $args[0]
    $explicitProfile = $true
    if ($args.Count -gt 1) {
      $opencodeArgs = $args[1..($args.Count - 1)]
    }
  } else {
    $selection = "pp"
    $opencodeArgs = @($args)
  }
}

if ($action -eq "login" -and -not $explicitProfile) {
  $selection = Select-Profile
}

$key = Resolve-ProfileKey $selection
if (-not $key) {
  "Unknown OpenAI profile: $selection"
  ""
  Show-Usage
  exit 1
}

function Use-Profile($profileKey) {
  $profile = $profiles[$profileKey]
  $profileDataHome = Join-Path $env:USERPROFILE $profile.Data
  $sharedDataDir = Join-Path $env:USERPROFILE ".local\share\opencode"
  New-Item -ItemType Directory -Path $sharedDataDir -Force | Out-Null

  $env:XDG_DATA_HOME = $profileDataHome
  $env:OPENCODE_DB = Join-Path $sharedDataDir "opencode.db"
  $env:OPENCODE_OPENAI_PROFILE = $profileKey

  "Using OpenAI profile: $($profile.Name)"
  "Sessions DB: $env:OPENCODE_DB"
}

function Test-LimitOutput($text) {
  $lower = $text.ToLowerInvariant()
  return $lower.Contains("usage limit") -or
    $lower.Contains("limit reached") -or
    $lower.Contains("rate limit") -or
    $lower.Contains("too many requests") -or
    $lower.Contains("free usage exceeded") -or
    $lower.Contains("gousagelimiterror") -or
    $lower.Contains("freeusagelimiterror") -or
    $lower.Contains("insufficient_quota") -or
    $lower.Contains("insufficient quota") -or
    $lower.Contains("quota exceeded") -or
    $lower.Contains("exceeded your quota") -or
    $lower.Contains("429")
}

function Invoke-OpencodeDirect($arguments) {
  & $opencodeCommand @arguments
  $script:lastOpencodeExit = $LASTEXITCODE
}

function Invoke-OpencodeCaptured($arguments) {
  $output = & $opencodeCommand @arguments 2>&1
  $script:lastOpencodeOutput = ($output | Out-String)
  foreach ($line in $output) {
    [Console]::Out.WriteLine($line)
  }
  return $LASTEXITCODE
}

if ($action -eq "login") {
  Use-Profile $key
  Invoke-OpencodeDirect @("providers", "login", "--provider", "openai", "--method", "ChatGPT Pro/Plus (browser)")
  exit $script:lastOpencodeExit
}

$shouldFallback = -not $explicitProfile -and $opencodeArgs.Count -gt 0 -and $opencodeArgs[0].ToString().ToLowerInvariant() -eq "run"
if ($shouldFallback) {
  foreach ($profileKey in $fallbackOrder) {
    Use-Profile $profileKey
    $exit = Invoke-OpencodeCaptured $opencodeArgs
    if ($exit -eq 0) {
      exit 0
    }

    if (-not (Test-LimitOutput $script:lastOpencodeOutput)) {
      exit $exit
    }

    "OpenAI profile limit hit; trying next profile..."
  }

  exit 1
}

Use-Profile $key
Invoke-OpencodeDirect $opencodeArgs
exit $script:lastOpencodeExit
