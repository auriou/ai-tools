#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export HOME="$test_dir/home"
export USERPROFILE="$HOME"
export LOCALAPPDATA="$HOME/localappdata"
export PATH="$test_dir/mock-bin:$PATH"
export MOCK_LOG="$test_dir/commands.log"
mkdir -p "$HOME/.ai-tools/bin" "$HOME/.ai-tools/state" "$HOME/.ai-tools/apps/token-optimizer-dashboard" "$HOME/.local/bin" "$test_dir/mock-bin"
cp "$repo_dir/ai-tools.sh" "$HOME/.ai-tools/bin/ai-tools"

cat > "$test_dir/mock-bin/npm" <<'EOF'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >> "$MOCK_LOG"
exit "${MOCK_NPM_EXIT:-0}"
EOF
cat > "$test_dir/mock-bin/uv" <<'EOF'
#!/usr/bin/env bash
printf 'uv %s\n' "$*" >> "$MOCK_LOG"
if [ "$*" = 'tool list' ]; then
    printf 'serena-agent v1.0.0\n'
    exit 0
fi
exit "${MOCK_UV_EXIT:-0}"
EOF
chmod +x "$test_dir/mock-bin/npm" "$test_dir/mock-bin/uv"

state="$HOME/.ai-tools/state/installed.json"
reset_fixture() {
    printf '%s' '{"selectedTools":["RTK","TokenOptimizer","Serena","CodebaseMemory"],"tools":{"RTK":{},"TokenOptimizer":{},"Serena":{},"CodebaseMemory":{}}}' > "$state"
    : > "$HOME/.ai-tools/bin/rtk"
    : > "$HOME/.local/bin/codebase-memory-mcp"
    : > "$HOME/.ai-tools/apps/token-optimizer-dashboard/user-data"
    : > "$MOCK_LOG"
}

reset_fixture
printf '5\na\nn\n' | bash "$HOME/.ai-tools/bin/ai-tools" >/dev/null 2>&1
test -f "$HOME/.ai-tools/bin/rtk"
jq -e '.selectedTools | length == 4' "$state" >/dev/null
test ! -s "$MOCK_LOG"

printf '5\nc\ny\nn\nn\nn\nn\ny\n' | bash "$HOME/.ai-tools/bin/ai-tools" >/dev/null 2>&1
test ! -e "$HOME/.ai-tools/bin/rtk"
jq -e '.selectedTools == ["TokenOptimizer","Serena","CodebaseMemory"] and (.tools | has("RTK") | not)' "$state" >/dev/null
test -f "$HOME/.local/bin/codebase-memory-mcp"

reset_fixture
export MOCK_NPM_EXIT=1
if printf '5\na\ny\n' | bash "$HOME/.ai-tools/bin/ai-tools" >/dev/null 2>&1; then
    printf 'Expected npm failure to fail the command\n' >&2
    exit 1
fi
unset MOCK_NPM_EXIT
jq -e '.selectedTools == ["TokenOptimizer"] and (.tools | has("TokenOptimizer"))' "$state" >/dev/null
test -f "$HOME/.ai-tools/apps/token-optimizer-dashboard/user-data"
grep -q '^uv tool uninstall serena-agent$' "$MOCK_LOG"

if command -v pwsh >/dev/null 2>&1; then
    reset_fixture
    cp "$repo_dir/ai-tools.ps1" "$HOME/.ai-tools/bin/ai-tools.ps1"
    : > "$HOME/.ai-tools/bin/rtk.exe"
    printf '5\nc\ny\nn\nn\nn\ny\n' | pwsh -NoProfile -File "$HOME/.ai-tools/bin/ai-tools.ps1" >/dev/null 2>&1
    test ! -e "$HOME/.ai-tools/bin/rtk.exe"
    jq -e '.selectedTools == ["TokenOptimizer","Serena","CodebaseMemory"] and (.tools | has("RTK") | not)' "$state" >/dev/null
    pwsh -NoProfile -File "$repo_dir/tests/uninstall.ps1"
fi

printf 'Uninstall tests passed.\n'