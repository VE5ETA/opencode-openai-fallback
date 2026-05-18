$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$blockedFiles = @()
$blockedContent = @()

$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force | Where-Object {
  $_.FullName -notmatch '\\.git(\\|$)' -and
  $_.FullName -notmatch '\\node_modules(\\|$)'
}

foreach ($file in $files) {
  if ($file.Name -eq "auth.json" -or $file.Name -eq "opencode.db" -or $file.Name -eq ".env" -or $file.Name.StartsWith(".env.")) {
    $blockedFiles += $file.FullName
    continue
  }

  $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $text) {
    continue
  }

  $relative = $file.FullName.Substring($repoRoot.Length).TrimStart("\")
  if ($text -match 'Bearer\s+eyJ[A-Za-z0-9_-]+\.' -or
      $text -match 'sk-proj-[A-Za-z0-9_-]{20,}' -or
      $text -match 'sk-[A-Za-z0-9_-]{20,}' -or
      $text -match 'github_pat_[A-Za-z0-9_]{20,}' -or
      $text -match 'npm_[A-Za-z0-9]{20,}' -or
      $text -match '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----' -or
      $text -match '"refresh"\s*:\s*"[A-Za-z0-9._-]{20,}"' -or
      $text -match '"access"\s*:\s*"[A-Za-z0-9._-]{20,}"' -or
      $text -match '"refresh_token"\s*:\s*"[A-Za-z0-9._-]{20,}"' -or
      $text -match '"access_token"\s*:\s*"[A-Za-z0-9._-]{20,}"' -or
      $text -match '"id_token"\s*:\s*"[A-Za-z0-9._-]{20,}"' -or
      $text -match '"client_secret"\s*:\s*"[^"]{8,}"') {
    $blockedContent += $relative
  }
}

if ($blockedFiles.Count -or $blockedContent.Count) {
  if ($blockedFiles.Count) {
    "Blocked secret-like files:"
    $blockedFiles | ForEach-Object { "  $_" }
  }
  if ($blockedContent.Count) {
    "Blocked token-like content in:"
    $blockedContent | ForEach-Object { "  $_" }
  }
  exit 1
}

"PASS: no auth files or token-looking secrets found"
