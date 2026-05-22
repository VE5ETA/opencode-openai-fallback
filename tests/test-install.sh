#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="${repo_root}/install.sh"

run_case() {
  local no_opencode_function="$1"

  local temp
  temp="$(mktemp -d)"
  trap 'rm -rf "$temp"' RETURN

  local home="${temp}/home"
  local bin="${temp}/bin"
  local rc="${temp}/rc"
  mkdir -p "$home" "$bin"

  export HOME="$home"
  export PATH="$bin:$PATH"

  cat > "${bin}/opencode" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${bin}/opencode"

  mkdir -p "${HOME}/.config/opencode"
  cat > "${HOME}/.config/opencode/opencode.jsonc" <<'EOF'
{
  // Existing user config with JSONC trailing commas.
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "existing-plugin",
  ],
}
EOF

  printf '%s\n' "# existing profile content" > "$rc"

  if [[ "$no_opencode_function" == "1" ]]; then
    bash "$installer" --source-root "$repo_root" --shell-rc "$rc" --no-opencode-function >/dev/null
  else
    bash "$installer" --source-root "$repo_root" --shell-rc "$rc" >/dev/null
  fi

  [[ -f "${HOME}/.config/opencode/plugin/openai-auto-fallback.mjs" ]] || { echo "Expected plugin installed" >&2; exit 1; }
  [[ -f "${HOME}/.config/opencode/opencode-openai.sh" ]] || { echo "Expected helper installed" >&2; exit 1; }
  [[ -x "${HOME}/.config/opencode/opencode-openai.sh" ]] || { echo "Expected helper to be executable" >&2; exit 1; }

  config="$(cat "${HOME}/.config/opencode/opencode.jsonc")"
  printf '%s\n' "$config" | grep -q '"existing-plugin"' || { echo "Expected existing plugin entry preserved" >&2; exit 1; }
  printf '%s\n' "$config" | grep -Fq '"./plugin/openai-auto-fallback.mjs"' || { echo "Expected fallback plugin entry present" >&2; exit 1; }

  profile="$(cat "$rc")"
  printf '%s\n' "$profile" | grep -q 'opencode-openai-fallback BEGIN' || { echo "Expected managed shell block present" >&2; exit 1; }
  printf '%s\n' "$profile" | grep -q '^ocai()' || { echo "Expected ocai function present" >&2; exit 1; }
  if [[ "$no_opencode_function" == "1" ]]; then
    if printf '%s\n' "$profile" | grep -q '^opencode()'; then
      echo "Did not expect opencode wrapper function in no-wrapper mode" >&2
      exit 1
    fi
  else
    if ! printf '%s\n' "$profile" | grep -q '^opencode()'; then
      echo "Expected opencode wrapper function in default mode" >&2
      exit 1
    fi
  fi
}

run_case 0
run_case 1

echo "PASS: install.sh installs fallback files, config, and shell functions"
