param(
  [switch]$SkipOpencodeInstall,
  [switch]$NoOpencodeFunction,
  [string]$SourceRoot,
  [string]$SourceBase = "https://raw.githubusercontent.com/VE5ETA/opencode-openai-fallback/main"
)

$ErrorActionPreference = "Stop"

$pluginEntry = "./plugin/openai-auto-fallback.mjs"
$configDir = Join-Path $env:USERPROFILE ".config\opencode"
$pluginDir = Join-Path $configDir "plugin"
$helperPath = Join-Path $configDir "opencode-openai.ps1"
$configPath = Join-Path $configDir "opencode.jsonc"
$localRoot = if ($SourceRoot) {
  $SourceRoot
} elseif ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot "plugin\openai-auto-fallback.mjs"))) {
  $PSScriptRoot
} else {
  $null
}

function Get-NativeCommand($names) {
  foreach ($name in $names) {
    $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
  }
  return $null
}

function Test-OpencodeInstalled {
  return [bool](Get-NativeCommand @("opencode.cmd", "opencode.exe", "opencode"))
}

function Install-OpencodeIfMissing {
  if (Test-OpencodeInstalled) {
    "opencode is already installed."
    return
  }

  if ($SkipOpencodeInstall) {
    throw "opencode was not found. Re-run without -SkipOpencodeInstall or install opencode first."
  }

  $npm = Get-NativeCommand @("npm.cmd", "npm")
  if ($npm) {
    "Installing opencode with npm: npm install -g opencode-ai"
    & $npm install -g opencode-ai
    if ($LASTEXITCODE -ne 0) { throw "npm failed to install opencode-ai." }
    $npmPrefix = (& $npm prefix -g 2>$null | Select-Object -First 1)
    if ($npmPrefix -and (Test-Path -LiteralPath $npmPrefix) -and (($env:Path -split ';') -notcontains $npmPrefix)) {
      $env:Path = "$npmPrefix;$env:Path"
    }
    if (Test-OpencodeInstalled) { return }
  }

  $scoop = Get-NativeCommand @("scoop.cmd", "scoop")
  if ($scoop) {
    "Installing opencode with Scoop: scoop install opencode"
    & $scoop install opencode
    if ($LASTEXITCODE -ne 0) { throw "Scoop failed to install opencode." }
    if (Test-OpencodeInstalled) { return }
  }

  $choco = Get-NativeCommand @("choco.exe", "choco")
  if ($choco) {
    "Installing opencode with Chocolatey: choco install opencode -y"
    & $choco install opencode -y
    if ($LASTEXITCODE -ne 0) { throw "Chocolatey failed to install opencode." }
    if (Test-OpencodeInstalled) { return }
  }

  throw "Could not install opencode automatically. Install Node.js and rerun this script, or install opencode from https://opencode.ai/docs/ first."
}

function Install-RepoFile($relativePath, $destinationPath) {
  New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
  if ($localRoot) {
    $sourcePath = Join-Path $localRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
      throw "Missing source file: $sourcePath"
    }
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    return
  }

  $uri = "$($SourceBase.TrimEnd('/'))/$($relativePath -replace '\\','/')"
  Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $destinationPath
}

function Remove-JsoncComments($text) {
  $output = New-Object System.Text.StringBuilder
  $inString = $false
  $escaped = $false
  $lineComment = $false
  $blockComment = $false

  for ($i = 0; $i -lt $text.Length; $i++) {
    $char = $text[$i]
    $next = if ($i + 1 -lt $text.Length) { $text[$i + 1] } else { [char]0 }

    if ($lineComment) {
      if ($char -eq "`r" -or $char -eq "`n") {
        $lineComment = $false
        [void]$output.Append($char)
      }
      continue
    }

    if ($blockComment) {
      if ($char -eq "*" -and $next -eq "/") {
        $blockComment = $false
        $i++
      }
      continue
    }

    if ($inString) {
      [void]$output.Append($char)
      if ($escaped) {
        $escaped = $false
      } elseif ($char -eq "\") {
        $escaped = $true
      } elseif ($char -eq '"') {
        $inString = $false
      }
      continue
    }

    if ($char -eq '"') {
      $inString = $true
      [void]$output.Append($char)
      continue
    }

    if ($char -eq "/" -and $next -eq "/") {
      $lineComment = $true
      $i++
      continue
    }

    if ($char -eq "/" -and $next -eq "*") {
      $blockComment = $true
      $i++
      continue
    }

    [void]$output.Append($char)
  }

  return $output.ToString()
}

function Remove-JsonTrailingCommas($text) {
  $output = New-Object System.Text.StringBuilder
  $inString = $false
  $escaped = $false

  for ($i = 0; $i -lt $text.Length; $i++) {
    $char = $text[$i]

    if ($inString) {
      [void]$output.Append($char)
      if ($escaped) {
        $escaped = $false
      } elseif ($char -eq "\") {
        $escaped = $true
      } elseif ($char -eq '"') {
        $inString = $false
      }
      continue
    }

    if ($char -eq '"') {
      $inString = $true
      [void]$output.Append($char)
      continue
    }

    if ($char -eq ',') {
      $j = $i + 1
      while ($j -lt $text.Length -and [char]::IsWhiteSpace($text[$j])) { $j++ }
      if ($j -lt $text.Length -and ($text[$j] -eq ']' -or $text[$j] -eq '}')) {
        continue
      }
    }

    [void]$output.Append($char)
  }

  return $output.ToString()
}

function ConvertTo-Hashtable($value) {
  if ($null -eq $value) { return $null }

  if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string] -and $value -isnot [System.Management.Automation.PSCustomObject]) {
    return @($value | ForEach-Object { ConvertTo-Hashtable $_ })
  }

  if ($value -is [System.Management.Automation.PSCustomObject]) {
    $table = [ordered]@{}
    foreach ($property in $value.PSObject.Properties) {
      $table[$property.Name] = ConvertTo-Hashtable $property.Value
    }
    return $table
  }

  return $value
}

function Read-OpencodeConfig {
  if (-not (Test-Path -LiteralPath $configPath)) {
    return [ordered]@{
      '$schema' = "https://opencode.ai/config.json"
      plugin = @()
    }
  }

  $raw = Get-Content -LiteralPath $configPath -Raw
  if (-not $raw.Trim()) {
    return [ordered]@{
      '$schema' = "https://opencode.ai/config.json"
      plugin = @()
    }
  }

  try {
    $json = Remove-JsonTrailingCommas (Remove-JsoncComments $raw)
    return ConvertTo-Hashtable ($json | ConvertFrom-Json)
  } catch {
    $backupPath = "$configPath.backup-before-openai-fallback"
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    throw "Could not parse $configPath. Backup written to $backupPath. Fix the JSONC and rerun install.ps1. Parse error: $($_.Exception.Message)"
  }
}

function Save-OpencodeConfig($config) {
  if (Test-Path -LiteralPath $configPath) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupPath = "$configPath.backup-before-openai-fallback-$stamp"
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    "Backed up existing opencode config: $backupPath"
  }

  $config | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $configPath -Encoding UTF8
}

function Ensure-PluginRegistered {
  $config = Read-OpencodeConfig
  if (-not $config.Contains('$schema')) {
    $config['$schema'] = "https://opencode.ai/config.json"
  }

  if (-not $config.Contains('plugin') -or $null -eq $config['plugin']) {
    $config['plugin'] = @()
  }

  $plugins = @($config['plugin'])
  foreach ($plugin in $plugins) {
    if ($plugin -is [string] -and $plugin -eq $pluginEntry) {
      "opencode plugin is already registered."
      return
    }
  }

  $plugins += $pluginEntry
  $config['plugin'] = @($plugins)
  Save-OpencodeConfig $config
}

function Ensure-PowerShellProfile {
  $profilePath = $PROFILE.CurrentUserCurrentHost
  if ([string]::IsNullOrWhiteSpace($profilePath)) {
    $profilePath = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
  }
  $profileDir = Split-Path -Parent $profilePath
  New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

  $existing = if (Test-Path -LiteralPath $profilePath) { Get-Content -LiteralPath $profilePath -Raw } else { "" }
  $begin = "# >>> opencode-openai-fallback BEGIN"
  $end = "# <<< opencode-openai-fallback END"
  $includeOpencodeFunction = -not $NoOpencodeFunction -and $existing -notmatch '(?m)^\s*function\s+opencode\b'

  $opencodeFunction = if ($includeOpencodeFunction) {
@'

function opencode {
  ocai @args
}
'@
  } else { "" }

  $block = @"
$begin
function ocai {
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "`$env:USERPROFILE\.config\opencode\opencode-openai.ps1" @args
}
$opencodeFunction

function ocraw {
  `$cmd = Get-Command opencode.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not `$cmd) {
    `$cmd = Get-Command opencode.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  }
  if (-not `$cmd) {
    throw "Could not find raw opencode executable."
  }
  & `$cmd.Source @args
}

function ocpp {
  ocai pp @args
}

function ocps {
  ocai ps @args
}

function ocsp {
  ocai sp @args
}

function ocss {
  ocai ss @args
}
$end
"@

  $pattern = "(?s)\r?\n?" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end) + "\r?\n?"
  if ($existing -match [regex]::Escape($begin)) {
    $updated = [regex]::Replace($existing, $pattern, "`r`n$block`r`n")
  } elseif ($existing -match '(?m)^\s*function\s+ocai\b') {
    "PowerShell profile already defines ocai outside the managed block; leaving profile unchanged: $profilePath"
    return
  } else {
    $updated = ($existing.TrimEnd() + "`r`n`r`n" + $block + "`r`n").TrimStart()
  }

  if (Test-Path -LiteralPath $profilePath) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    Copy-Item -LiteralPath $profilePath -Destination "$profilePath.backup-before-openai-fallback-$stamp" -Force
  }

  Set-Content -LiteralPath $profilePath -Value $updated -Encoding UTF8
  "PowerShell profile updated: $profilePath"
}

Install-OpencodeIfMissing
New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
Install-RepoFile "plugin\openai-auto-fallback.mjs" (Join-Path $pluginDir "openai-auto-fallback.mjs")
Install-RepoFile "scripts\opencode-openai.ps1" $helperPath
Ensure-PluginRegistered
Ensure-PowerShellProfile

"Installed opencode-openai-fallback."
"Open a new PowerShell window and restart opencode before testing."
"Login commands: ocai login pp; ocai login ps; ocai login sp; ocai login ss"
