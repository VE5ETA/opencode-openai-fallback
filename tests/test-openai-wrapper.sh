#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/scripts/opencode-openai.sh"

temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

home="${temp}/home"
bin="${temp}/bin"
capture="${temp}/capture.txt"
mkdir -p "$home" "$bin"

export HOME="$home"
export PATH="$bin:$PATH"
export OCAI_TEST_CAPTURE="$capture"

cat > "${bin}/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

profile="${OPENCODE_OPENAI_PROFILE:-}"
printf 'PROFILE=%s\tXDG_DATA_HOME=%s\tOPENCODE_DB=%s\tARGS=%s\n' \
  "$profile" "${XDG_DATA_HOME:-}" "${OPENCODE_DB:-}" "$*" >> "${OCAI_TEST_CAPTURE}"

case ",${OCAI_FAIL_LIMIT_CODES:-}," in
  *,"$profile",*)
    printf '%s\n' "${OCAI_FAIL_TEXT:-usage limit reached}"
    exit 42
    ;;
esac

printf '%s\n' "ok"
exit 0
EOF
chmod +x "${bin}/opencode"

rm -f "$capture"
bash "$script" pp debug paths >/dev/null
line="$(tail -n 1 "$capture")"
expected_data_home="${HOME}/.local/share-opencode-openai-primary-personal"
expected_db="${HOME}/.local/share/opencode/opencode.db"

[[ "$line" == PROFILE=pp$'\t'* ]] || { echo "Expected PROFILE=pp, got: $line" >&2; exit 1; }
[[ "$line" == *$'\t'"XDG_DATA_HOME=${expected_data_home}"$'\t'* ]] || { echo "Expected XDG_DATA_HOME=${expected_data_home}, got: $line" >&2; exit 1; }
[[ "$line" == *$'\t'"OPENCODE_DB=${expected_db}"$'\t'* ]] || { echo "Expected OPENCODE_DB=${expected_db}, got: $line" >&2; exit 1; }
[[ "$line" == *$'\t'"ARGS=debug paths" ]] || { echo "Expected forwarded args 'debug paths', got: $line" >&2; exit 1; }

rm -f "$capture"
bash "$script" debug paths >/dev/null
line="$(tail -n 1 "$capture")"
[[ "$line" == PROFILE=pp$'\t'* ]] || { echo "Expected default profile pp, got: $line" >&2; exit 1; }

rm -f "$capture"
export OCAI_FAIL_LIMIT_CODES="pp,ps"
bash "$script" run hello >/dev/null
profiles=()
while IFS= read -r attempt; do
  profiles+=("${attempt%%$'\t'*}")
done < "$capture"
got_profiles="$(IFS=,; echo "${profiles[*]//PROFILE=/}")"
[[ "$got_profiles" == "pp,ps,sp" ]] || { echo "Expected fallback profiles pp,ps,sp, got: $got_profiles" >&2; exit 1; }

rm -f "$capture"
export OCAI_FAIL_LIMIT_CODES="pp"
export OCAI_FAIL_TEXT="quota configuration missing"
set +e
bash "$script" run hello >/dev/null
exit_code=$?
set -e
[[ $exit_code -eq 42 ]] || { echo "Expected non-limit quota text to stop with exit 42, got $exit_code" >&2; exit 1; }
count="$(wc -l < "$capture" | tr -d '[:space:]')"
[[ "$count" == "1" ]] || { echo "Expected non-limit attempt count 1, got $count" >&2; exit 1; }

echo "PASS: ocai shell helper uses isolated auth storage, shared session DB, default pp, and run fallback"
