#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
export HOME="$test_dir/home"
export CODEX_HOME="$HOME/.codex"
export PATH="$test_dir/bin:/usr/bin:/bin"
mkdir -p "$test_dir/bin" "$CODEX_HOME"
export MOCK_LOG="$test_dir/codex.log"

cat > "$test_dir/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_LOG"
case "$1 $2" in
    'mcp get') grep -Fqx "[mcp_servers.$3]" "$CODEX_HOME/config.toml" ;;
    'mcp add') printf '\n[mcp_servers.%s]\ncommand = "%s"\n' "$3" "$5" >> "$CODEX_HOME/config.toml" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$test_dir/bin/codex"
printf '%s\n' '[mcp_servers.existing]' 'command = "existing"' > "$CODEX_HOME/config.toml"
printf '%s\n' 'Existing instructions.' > "$CODEX_HOME/AGENTS.md"

source <(sed '/^parse_args "\$@"/,$d' "$repo_dir/ai-tools.sh")
CHECK=false
configure_codex_integration 'TokenOptimizer,Serena,CodebaseMemory'
for name in token-optimizer serena codebase-memory-mcp existing; do
    grep -Fqx "[mcp_servers.$name]" "$CODEX_HOME/config.toml"
done
grep -Fqx 'startup_timeout_sec = 30' "$CODEX_HOME/config.toml"
grep -Fqx 'tool_timeout_sec = 120' "$CODEX_HOME/config.toml"
grep -Fqx 'Existing instructions.' "$CODEX_HOME/AGENTS.md"
grep -Fqx '<!-- ai-tools:begin -->' "$CODEX_HOME/AGENTS.md"

configure_codex_integration 'TokenOptimizer,Serena,CodebaseMemory'
test "$(grep -c '^mcp add ' "$MOCK_LOG")" -eq 3

if [ -x /usr/lib/chatgpt/resources/codex ]; then
    rm "$test_dir/bin/codex"
    hash -r
    CHECK=true
    ensure_codex_cli_path
    test "$(command -v codex)" = /usr/lib/chatgpt/resources/codex
    test ! -e "$HOME/.profile"
    export PATH="$test_dir/bin:/usr/bin:/bin"
    hash -r
    CHECK=false
    ensure_codex_cli_path
    test "$(command -v codex)" = /usr/lib/chatgpt/resources/codex
    grep -Fqx 'export PATH="/usr/lib/chatgpt/resources:$PATH"  # added by ai-tools (/usr/lib/chatgpt/resources)' "$HOME/.profile"
    PATH=/usr/bin:/bin bash -c 'source "$HOME/.profile"; test "$(command -v codex)" = /usr/lib/chatgpt/resources/codex'
    (
        export CODEX_HOME="$test_dir/real-codex"
        CODEX_AGENTS_FILE="$CODEX_HOME/AGENTS.md"
        mkdir -p "$CODEX_HOME"
        CHECK=false
        configure_codex_integration 'TokenOptimizer,Serena,CodebaseMemory'
        for name in token-optimizer serena codebase-memory-mcp; do
            codex mcp get "$name" >/dev/null
        done
        grep -Eq '^startup_timeout_sec = 30(\.0+)?$' "$CODEX_HOME/config.toml"
        grep -Eq '^tool_timeout_sec = 120(\.0+)?$' "$CODEX_HOME/config.toml"
        CHECK=true
        configure_codex_integration 'TokenOptimizer,Serena,CodebaseMemory'
    )
fi

printf 'Codex integration tests passed.\n'