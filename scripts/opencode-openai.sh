#!/usr/bin/env bash
set -euo pipefail

profiles_key_to_name() {
  case "$1" in
    pp) printf '%s\n' "Primary personal" ;;
    ps) printf '%s\n' "Primary shared" ;;
    sp) printf '%s\n' "Secondary personal" ;;
    ss) printf '%s\n' "Secondary shared" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

profiles_key_to_data_dir() {
  case "$1" in
    pp) printf '%s\n' ".local/share-opencode-openai-primary-personal" ;;
    ps) printf '%s\n' ".local/share-opencode-openai-primary-shared" ;;
    sp) printf '%s\n' ".local/share-opencode-openai-secondary-personal" ;;
    ss) printf '%s\n' ".local/share-opencode-openai-secondary-shared" ;;
    *) return 1 ;;
  esac
}

resolve_profile_key() {
  local selection="$1"
  selection="$(printf '%s' "$selection" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$selection" in
    primary-personal) selection="pp" ;;
    primary-shared) selection="ps" ;;
    secondary-personal) selection="sp" ;;
    secondary-shared) selection="ss" ;;
  esac

  case "$selection" in
    pp|ps|sp|ss) printf '%s\n' "$selection" ;;
    *) printf '%s\n' "" ;;
  esac
}

show_usage() {
  cat <<'EOF'
Usage: ocai [login|pick] [pp|ps|sp|ss] [opencode args...]

Profiles:
  pp  Primary personal
  ps  Primary shared
  sp  Secondary personal
  ss  Secondary shared

Examples:
  ocai
  ocai debug paths
  ocai pp
  ocai login ps
  ocai run "fix the tests"
  ocai ss run "fix the tests"
EOF
}

select_profile() {
  printf '%s\n' "OpenAI profile:"
  printf '%s\n' "  1. pp - Primary personal"
  printf '%s\n' "  2. ps - Primary shared"
  printf '%s\n' "  3. sp - Secondary personal"
  printf '%s\n' "  4. ss - Secondary shared"
  printf '%s' "Choose 1-4 or code: "

  local choice
  IFS= read -r choice
  choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$choice" in
    1) printf '%s\n' "pp" ;;
    2) printf '%s\n' "ps" ;;
    3) printf '%s\n' "sp" ;;
    4) printf '%s\n' "ss" ;;
    *) printf '%s\n' "$choice" ;;
  esac
}

use_profile() {
  local key="$1"
  local data_dir
  data_dir="$(profiles_key_to_data_dir "$key")" || return 1

  local profile_data_home="${HOME}/${data_dir}"
  local shared_data_dir="${HOME}/.local/share/opencode"
  mkdir -p "$shared_data_dir"

  export XDG_DATA_HOME="$profile_data_home"
  export OPENCODE_DB="${shared_data_dir}/opencode.db"
  export OPENCODE_OPENAI_PROFILE="$key"

  printf '%s\n' "Using OpenAI profile: $(profiles_key_to_name "$key")"
  printf '%s\n' "Sessions DB: ${OPENCODE_DB}"
}

is_limit_output() {
  local text="$1"
  local lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" == *"usage limit"* ]] ||
    [[ "$lower" == *"limit reached"* ]] ||
    [[ "$lower" == *"rate limit"* ]] ||
    [[ "$lower" == *"too many requests"* ]] ||
    [[ "$lower" == *"free usage exceeded"* ]] ||
    [[ "$lower" == *"gousagelimiterror"* ]] ||
    [[ "$lower" == *"freeusagelimiterror"* ]] ||
    [[ "$lower" == *"insufficient_quota"* ]] ||
    [[ "$lower" == *"insufficient quota"* ]] ||
    [[ "$lower" == *"quota exceeded"* ]] ||
    [[ "$lower" == *"exceeded your quota"* ]] ||
    [[ "$lower" == *"429"* ]]
}

invoke_opencode_direct() {
  command opencode "$@"
  return $?
}

invoke_opencode_captured() {
  local tmp="$1"
  shift
  : > "$tmp"
  command opencode "$@" 2>&1 | tee "$tmp"
  return "${PIPESTATUS[0]}"
}

action="run"
selection="pp"
explicit_profile=0
opencode_args=()

if [[ $# -gt 0 ]]; then
  first="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$first" in
    help|-h|--help)
      show_usage
      exit 0
      ;;
    login|auth)
      action="login"
      if [[ $# -gt 1 ]]; then
        selection="$2"
        explicit_profile=1
        shift 2
      else
        shift
      fi
      ;;
    pick|select|profiles)
      selection="$(select_profile)"
      explicit_profile=1
      shift
      opencode_args=("$@")
      ;;
    *)
      if [[ -n "$(resolve_profile_key "$1")" ]]; then
        selection="$1"
        explicit_profile=1
        shift
        opencode_args=("$@")
      else
        selection="pp"
        opencode_args=("$@")
      fi
      ;;
  esac
fi

if [[ "$action" == "login" && $explicit_profile -eq 0 ]]; then
  selection="$(select_profile)"
fi

key="$(resolve_profile_key "$selection")"
if [[ -z "$key" ]]; then
  printf '%s\n' "Unknown OpenAI profile: $selection"
  printf '\n'
  show_usage
  exit 1
fi

if [[ "$action" == "login" ]]; then
  use_profile "$key"
  invoke_opencode_direct providers login --provider openai --method "ChatGPT Pro/Plus (browser)"
  exit $?
fi

should_fallback=0
if [[ $explicit_profile -eq 0 && ${#opencode_args[@]} -gt 0 && "$(printf '%s' "${opencode_args[0]}" | tr '[:upper:]' '[:lower:]')" == "run" ]]; then
  should_fallback=1
fi

  fallback_order=("pp" "ps" "sp" "ss")
  if [[ $should_fallback -eq 1 ]]; then
    tmp="$(mktemp)"
    for profile_key in "${fallback_order[@]}"; do
      use_profile "$profile_key"
      set +e
      invoke_opencode_captured "$tmp" "${opencode_args[@]}"
      exit_code=$?
      set -e
      if [[ $exit_code -eq 0 ]]; then
        rm -f "$tmp"
        exit 0
      fi

      output="$(cat "$tmp" 2>/dev/null || true)"
      if ! is_limit_output "$output"; then
        rm -f "$tmp"
        exit "$exit_code"
      fi

    printf '%s\n' "OpenAI profile limit hit; trying next profile..."
  done
  rm -f "$tmp"
  exit 1
fi

use_profile "$key"
invoke_opencode_direct "${opencode_args[@]}"
exit $?
