#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export HOME="$test_dir/home"
export COPILOT_HOME="$HOME/custom-copilot"
export CODEX_HOME="$HOME/.codex"
export PATH="$test_dir/bin:/usr/bin:/bin"
export MOCK_LOG="$test_dir/commands.log"
mkdir -p "$test_dir/bin" "$HOME/.ai-tools/npm/bin" "$COPILOT_HOME"

cat > "$test_dir/bin/npm" <<'EOF'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >> "$MOCK_LOG"
case "$1" in
    list) printf '%s\n' '{"dependencies":{"rea-agents":{"version":"6.8.0"}}}' ;;
    view) printf '6.8.0\n' ;;
esac
EOF
cat > "$test_dir/bin/node" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$HOME/.ai-tools/npm/bin/rea" <<'EOF'
#!/usr/bin/env bash
printf 'rea %s\n' "$*" >> "$MOCK_LOG"
if [ "$*" = 'doctor --client codex' ]; then exit "${MOCK_DOCTOR_EXIT:-0}"; fi
EOF
cp "$test_dir/bin/node" "$test_dir/bin/code-insiders"
chmod +x "$test_dir/bin/npm" "$test_dir/bin/node" "$test_dir/bin/code-insiders" "$HOME/.ai-tools/npm/bin/rea"
: > "$MOCK_LOG"

source <(sed '/^parse_args "\$@"/,$d' "$repo_dir/ai-tools.sh")
CHECK=false
config="$COPILOT_MCP_CONFIG_PATH"
printf '%s\n' '{"custom":true,"mcpServers":{"existing":{"command":"keep","env":{"KEY":"value"}},"rea":{"command":"obsolete"}}}' > "$config"
cp "$config" "$test_dir/original.json"
configure_copilot_mcp 'REA'
jq -e --arg command "$REA_EXE" '.custom and .mcpServers.existing.env.KEY == "value" and .mcpServers.rea == {type:"stdio",command:$command,args:["mcp"]}' "$config" >/dev/null
backups=("$config".backup.*)
cmp "$test_dir/original.json" "${backups[0]}"
cp "$config" "$test_dir/aligned.json"
CHECK=true
configure_copilot_mcp 'REA'
cmp "$config" "$test_dir/aligned.json"

printf '%s\n' '{"mcpServers":{}}' > "$config"
cp "$config" "$test_dir/missing.json"
if configure_copilot_mcp 'REA'; then
    echo 'Expected missing REA registration to fail diagnostics' >&2; exit 1
fi
cmp "$config" "$test_dir/missing.json"
printf '%s\n' '{"mcpServers":{"rea":{"type":"stdio","command":"obsolete","args":["mcp"]}}}' > "$config"
if configure_copilot_mcp 'REA'; then
    echo 'Expected stale REA registration to fail diagnostics' >&2; exit 1
fi
rm "$config"
if configure_copilot_mcp 'REA'; then
    echo 'Expected absent configuration to fail diagnostics' >&2; exit 1
fi
test ! -e "$config"

CHECK=false
printf '%s\n' '{invalid JSON' > "$config"
cp "$config" "$test_dir/invalid.json"
if configure_copilot_mcp 'REA'; then
    echo 'Expected invalid JSON to fail registration' >&2; exit 1
fi
cmp "$config" "$test_dir/invalid.json"
printf '%s\n' '{}' > "$config"
mv "$REA_EXE" "$test_dir/rea"
if configure_copilot_mcp 'REA'; then
    echo 'Expected missing REA executable to fail registration' >&2; exit 1
fi
test "$(jq '.mcpServers // {} | length' "$config")" -eq 0
mv "$test_dir/rea" "$REA_EXE"

# A current package must still repair its Codex registration.
ensure_node() { :; }
add_user_path() { :; }
state_set_tool() { :; }
: > "$MOCK_LOG"
install_or_update_rea
grep -Fqx 'rea setup --client codex' "$MOCK_LOG"
if grep -q '^npm install' "$MOCK_LOG"; then
    echo 'A current REA package should not be reinstalled' >&2; exit 1
fi
CHECK=true
: > "$MOCK_LOG"
install_or_update_rea
if grep -q '^rea setup\|^npm install' "$MOCK_LOG"; then
    echo 'Diagnostics must not install or configure REA' >&2; exit 1
fi

# The standalone helper must include the Copilot SDK used inside Insiders.
: > "$MOCK_LOG"
bash "$repo_dir/tools/rea.sh" install --vscode
grep -Fqx 'rea setup --client codex' "$MOCK_LOG"
grep -Fqx 'rea setup --client copilot_cli --client vscode' "$MOCK_LOG"
: > "$MOCK_LOG"
bash "$repo_dir/tools/rea.sh" update --vscode
grep -Fqx 'rea setup --client copilot_cli --client vscode' "$MOCK_LOG"
: > "$MOCK_LOG"
export MOCK_DOCTOR_EXIT=1
if bash "$repo_dir/tools/rea.sh" check --vscode; then
    echo 'Expected a failed doctor to fail diagnostics' >&2; exit 1
fi
grep -Fqx 'rea doctor --client copilot_cli' "$MOCK_LOG"
grep -Fqx 'rea doctor --client vscode' "$MOCK_LOG"
if grep -q '^rea setup\|^npm install' "$MOCK_LOG"; then
    echo 'Standalone diagnostics must not configure or install REA' >&2; exit 1
fi
unset MOCK_DOCTOR_EXIT

if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -File "$repo_dir/tests/rea-integration.ps1"
fi
printf 'REA integration tests passed.\n'
