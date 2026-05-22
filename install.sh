#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ENTRY="./plugin/openai-auto-fallback.mjs"
CONFIG_DIR="${HOME}/.config/opencode"
PLUGIN_DIR="${CONFIG_DIR}/plugin"
HELPER_PATH="${CONFIG_DIR}/opencode-openai.sh"
CONFIG_PATH="${CONFIG_DIR}/opencode.jsonc"

SKIP_OPENCODE_INSTALL=0
NO_OPENCODE_FUNCTION=0
SOURCE_ROOT=""
SOURCE_BASE="https://raw.githubusercontent.com/VE5ETA/opencode-openai-fallback/main"
SHELL_RC=""

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  --skip-opencode-install     Do not attempt to install opencode if missing
  --no-opencode-function      Do not wrap plain `opencode` in your shell profile
  --source-root <path>        Install from a local checkout (defaults to this script directory when available)
  --source-base <url>         Raw GitHub base URL for downloads (default: repo main branch)
  --shell-rc <path>           Shell rc file to update (default: inferred from $SHELL)
  -h, --help                  Show help
EOF
}

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-opencode-install) SKIP_OPENCODE_INSTALL=1 ;;
    --no-opencode-function) NO_OPENCODE_FUNCTION=1 ;;
    --source-root)
      [[ $# -ge 2 ]] || die "--source-root requires a value"
      SOURCE_ROOT="$2"
      shift
      ;;
    --source-base)
      [[ $# -ge 2 ]] || die "--source-base requires a value"
      SOURCE_BASE="$2"
      shift
      ;;
    --shell-rc)
      [[ $# -ge 2 ]] || die "--shell-rc requires a value"
      SHELL_RC="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

test_opencode_installed() {
  command -v opencode >/dev/null 2>&1
}

install_opencode_if_missing() {
  if test_opencode_installed; then
    log "opencode is already installed."
    return
  fi

  if [[ $SKIP_OPENCODE_INSTALL -eq 1 ]]; then
    die "opencode was not found. Re-run without --skip-opencode-install or install opencode first."
  fi

  if need_cmd npm; then
    log "Installing opencode with npm: npm install -g opencode-ai"
    npm install -g opencode-ai
  fi

  if test_opencode_installed; then
    return
  fi

  if need_cmd brew; then
    log "Installing opencode with Homebrew: brew install opencode"
    brew install opencode
  fi

  if test_opencode_installed; then
    return
  fi

  die "Could not install opencode automatically. Install it from https://opencode.ai/docs/ and rerun."
}

script_source="${BASH_SOURCE[0]-$0}"
script_dir="$(cd "$(dirname "$script_source")" && pwd)"
local_root=""
if [[ -n "$SOURCE_ROOT" ]]; then
  local_root="$SOURCE_ROOT"
elif [[ -f "${script_dir}/plugin/openai-auto-fallback.mjs" ]]; then
  local_root="$script_dir"
fi

install_repo_file() {
  local relative="$1"
  local destination="$2"

  mkdir -p "$(dirname "$destination")"

  if [[ -n "$local_root" ]]; then
    local source="${local_root}/${relative}"
    [[ -f "$source" ]] || die "Missing source file: $source"
    cp "$source" "$destination"
    return
  fi

  local base="${SOURCE_BASE%/}"
  local uri="${base}/${relative}"
  if need_cmd curl; then
    curl -fsSL "$uri" -o "$destination"
  elif need_cmd wget; then
    wget -qO "$destination" "$uri"
  else
    die "curl or wget is required to download: $uri"
  fi
}

backup_with_stamp() {
  local target="$1"
  [[ -f "$target" ]] || return 0
  local stamp
  stamp="$(date +%Y%m%d%H%M%S)"
  local backup="${target}.backup-before-openai-fallback-${stamp}"
  cp "$target" "$backup"
  log "Backed up existing file: $backup"
}

ensure_plugin_registered() {
  mkdir -p "$CONFIG_DIR"
  need_cmd node || die "node is required to update ${CONFIG_PATH}. Install Node.js and rerun."

  node - "$CONFIG_PATH" "$PLUGIN_ENTRY" <<'NODE'
const fs = require("node:fs")
const path = require("node:path")

const configPath = process.argv[2]
const pluginEntry = process.argv[3]

function stripJsonc(text) {
  let out = ""
  let inString = false
  let escaped = false
  let lineComment = false
  let blockComment = false

  for (let i = 0; i < text.length; i++) {
    const char = text[i]
    const next = i + 1 < text.length ? text[i + 1] : "\0"

    if (lineComment) {
      if (char === "\n" || char === "\r") {
        lineComment = false
        out += char
      }
      continue
    }

    if (blockComment) {
      if (char === "*" && next === "/") {
        blockComment = false
        i++
      }
      continue
    }

    if (inString) {
      out += char
      if (escaped) escaped = false
      else if (char === "\\") escaped = true
      else if (char === '"') inString = false
      continue
    }

    if (char === '"') {
      inString = true
      out += char
      continue
    }

    if (char === "/" && next === "/") {
      lineComment = true
      i++
      continue
    }

    if (char === "/" && next === "*") {
      blockComment = true
      i++
      continue
    }

    out += char
  }

  return out
}

function stripTrailingCommas(text) {
  let out = ""
  let inString = false
  let escaped = false

  for (let i = 0; i < text.length; i++) {
    const char = text[i]

    if (inString) {
      out += char
      if (escaped) escaped = false
      else if (char === "\\") escaped = true
      else if (char === '"') inString = false
      continue
    }

    if (char === '"') {
      inString = true
      out += char
      continue
    }

    if (char === ",") {
      let j = i + 1
      while (j < text.length && /\s/.test(text[j])) j++
      if (j < text.length && (text[j] === "]" || text[j] === "}")) {
        continue
      }
    }

    out += char
  }

  return out
}

function readConfig() {
  if (!fs.existsSync(configPath)) {
    return { $schema: "https://opencode.ai/config.json", plugin: [] }
  }
  const raw = fs.readFileSync(configPath, "utf8")
  if (!raw.trim()) return { $schema: "https://opencode.ai/config.json", plugin: [] }
  try {
    return JSON.parse(stripTrailingCommas(stripJsonc(raw)))
  } catch (err) {
    const backup = `${configPath}.backup-before-openai-fallback`
    fs.copyFileSync(configPath, backup)
    throw new Error(`Could not parse ${configPath}. Backup written to ${backup}. Fix the JSONC and rerun. Parse error: ${err.message}`)
  }
}

const config = readConfig()
if (!config.$schema) config.$schema = "https://opencode.ai/config.json"
if (!Array.isArray(config.plugin)) config.plugin = config.plugin ? [config.plugin] : []

if (!config.plugin.some((value) => typeof value === "string" && value === pluginEntry)) {
  config.plugin.push(pluginEntry)
}

if (fs.existsSync(configPath)) {
  const stamp = new Date().toISOString().replace(/[-:TZ.]/g, "").slice(0, 14)
  fs.copyFileSync(configPath, `${configPath}.backup-before-openai-fallback-${stamp}`)
}

fs.mkdirSync(path.dirname(configPath), { recursive: true })
fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n", "utf8")
NODE
}

detect_shell_rc() {
  if [[ -n "$SHELL_RC" ]]; then
    printf '%s\n' "$SHELL_RC"
    return
  fi

  local shell="${SHELL:-}"
  local shellLower
  shellLower="$(lower "$shell")"

  if [[ "$shellLower" == *"zsh" ]]; then
    printf '%s\n' "${HOME}/.zshrc"
    return
  fi

  if [[ "$shellLower" == *"bash" ]]; then
    if [[ -f "${HOME}/.bashrc" ]]; then
      printf '%s\n' "${HOME}/.bashrc"
    elif [[ -f "${HOME}/.bash_profile" ]]; then
      printf '%s\n' "${HOME}/.bash_profile"
    else
      printf '%s\n' "${HOME}/.profile"
    fi
    return
  fi

  if [[ -f "${HOME}/.zshrc" ]]; then
    printf '%s\n' "${HOME}/.zshrc"
  elif [[ -f "${HOME}/.bashrc" ]]; then
    printf '%s\n' "${HOME}/.bashrc"
  else
    printf '%s\n' "${HOME}/.profile"
  fi
}

ensure_shell_profile() {
  local rc
  rc="$(detect_shell_rc)"

  local begin="# >>> opencode-openai-fallback BEGIN"
  local end="# <<< opencode-openai-fallback END"

  local existing=""
  if [[ -f "$rc" ]]; then
    existing="$(cat "$rc")"
  else
    mkdir -p "$(dirname "$rc")" 2>/dev/null || true
  fi

  if [[ "$existing" != *"$begin"* ]] && printf '%s\n' "$existing" | grep -Eq '(^|[[:space:]])(alias[[:space:]]+ocai=|ocai[[:space:]]*\(\)|function[[:space:]]+ocai[[:space:]]*\()'; then
    log "Shell profile already defines ocai outside the managed block; leaving profile unchanged: $rc"
    return
  fi

  local include_opencode=1
  if [[ $NO_OPENCODE_FUNCTION -eq 1 ]]; then
    include_opencode=0
  elif printf '%s\n' "$existing" | grep -Eq '(^|[[:space:]])(alias[[:space:]]+opencode=|opencode[[:space:]]*\(\)|function[[:space:]]+opencode[[:space:]]*\()'; then
    include_opencode=0
  fi

  local block
  if [[ $include_opencode -eq 1 ]]; then
    block="$(cat <<EOF
$begin
ocai() {
  "\$HOME/.config/opencode/opencode-openai.sh" "\$@"
}

opencode() {
  ocai "\$@"
}

ocraw() {
  command opencode "\$@"
}

ocpp() { ocai pp "\$@"; }
ocps() { ocai ps "\$@"; }
ocsp() { ocai sp "\$@"; }
ocss() { ocai ss "\$@"; }
$end
EOF
)"
  else
    block="$(cat <<EOF
$begin
ocai() {
  "\$HOME/.config/opencode/opencode-openai.sh" "\$@"
}

ocraw() {
  command opencode "\$@"
}

ocpp() { ocai pp "\$@"; }
ocps() { ocai ps "\$@"; }
ocsp() { ocai sp "\$@"; }
ocss() { ocai ss "\$@"; }
$end
EOF
)"
  fi

  backup_with_stamp "$rc"

  if [[ "$existing" == *"$begin"* ]]; then
    local tmp
    local block_file
    tmp="$(mktemp)"
    block_file="$(mktemp)"
    printf '%s\n' "$block" > "$block_file"
    awk -v begin="$begin" -v end="$end" -v block_file="$block_file" '
      function print_block() {
        while ((getline line < block_file) > 0) print line
        close(block_file)
      }
      $0 == begin { print_block(); inblock = 1; next }
      $0 == end { inblock = 0; next }
      !inblock { print }
    ' "$rc" > "$tmp"
    mv "$tmp" "$rc"
    rm -f "$block_file"
  else
    if [[ -n "$existing" && "${existing: -1}" != $'\n' ]]; then
      printf '\n' >> "$rc"
    fi
    printf '\n%s\n' "$block" >> "$rc"
  fi

  log "Shell profile updated: $rc"
}

install_opencode_if_missing
mkdir -p "$PLUGIN_DIR"
install_repo_file "plugin/openai-auto-fallback.mjs" "${PLUGIN_DIR}/openai-auto-fallback.mjs"
install_repo_file "scripts/opencode-openai.sh" "$HELPER_PATH"
chmod +x "$HELPER_PATH"
ensure_plugin_registered
ensure_shell_profile

log "Installed opencode-openai-fallback."
log "Open a new terminal window and restart opencode before testing."
log "Login commands: ocai login pp; ocai login ps; ocai login sp; ocai login ss"
