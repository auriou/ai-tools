#!/usr/bin/env bash
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed '/^parse_args "\$@"$/,$d' "$root/ai-tools.sh")
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT

STATE_DIR="$temp/state"
INSTALLED_STATE_PATH="$STATE_DIR/installed.json"
TOKEN_DASHBOARD_DIR="$temp/dashboard"
TOKEN_DASHBOARD_BUILD_PATH="$STATE_DIR/build.txt"
MANAGED_SCRIPT_PATH="$temp/not-installed"
BIN_DIR="$temp/bin"
SERENA_BIN_DIR="$temp/serena"
INTERACTIVE_MENU=false
mkdir -p "$STATE_DIR" "$TOKEN_DASHBOARD_DIR/.git"
printf '%s' '{"selectedTools":["RTK"],"lastRun":"previous","tools":{}}' > "$INSTALLED_STATE_PATH"
cp "$INSTALLED_STATE_PATH" "$temp/original.json"
FAILURE=ci
CONFIGURATION_FAILURE=false
PREFLIGHT_FAILURE=true

install_self() { :; }
check_dependencies() { :; }
ensure_jq() { :; }
ensure_node() { :; }
ensure_git() { :; }
initialize_install_plan() { :; }
test_install_prerequisites() { [ "$PREFLIGHT_FAILURE" = false ]; }
resolve_selected_tools() { RESOLVED_TOOLS_CSV=TokenOptimizer; }
get_token_installed_version() { echo 1.2.3; }
get_token_latest_version() { echo 1.2.3; }
configure_copilot_mcp() { [ "$CONFIGURATION_FAILURE" = false ]; }
configure_codex_integration() { :; }
configure_copilot_instructions() { :; }
git() {
    if [ "$1" = rev-parse ]; then echo commit-123; fi
    return 0
}
npm() {
    echo "$*" >> "$temp/npm-calls"
    mkdir -p "$TOKEN_DASHBOARD_DIR/node_modules"
    if [ "$FAILURE" = ci ] && [ "$1" = ci ]; then return 1; fi
    if [ "$FAILURE" = build ] && [ "$1" = run ]; then return 1; fi
    return 0
}
assert() {
    if ! "$@"; then echo "Assertion failed: $*" >&2; exit 1; fi
}
run_main() {
    # Keep main's exit and state cleanup trap isolated from the test runner.
    (main)
}
expect_failure() {
    if run_main; then echo "Expected installation failure" >&2; exit 1; fi
    assert cmp "$INSTALLED_STATE_PATH" "$temp/original.json"
}

FORCE_REINSTALL=true
expect_failure
assert test ! -f "$temp/npm-calls"
FORCE_REINSTALL=false
PREFLIGHT_FAILURE=false
expect_failure
assert test ! -f "$TOKEN_DASHBOARD_BUILD_PATH"
FAILURE=build
expect_failure
assert test ! -f "$TOKEN_DASHBOARD_BUILD_PATH"
FAILURE=""
CONFIGURATION_FAILURE=true
expect_failure
assert test -f "$TOKEN_DASHBOARD_BUILD_PATH"
CONFIGURATION_FAILURE=false
run_main || exit 1
assert "$JQ" -e '.tools.TokenOptimizer.status == "up-to-date" and .lastRun != "previous"' "$INSTALLED_STATE_PATH"
cp "$INSTALLED_STATE_PATH" "$temp/original.json"
calls=$(wc -l < "$temp/npm-calls")
run_main || exit 1
assert test "$(wc -l < "$temp/npm-calls")" -eq "$calls"
cp "$INSTALLED_STATE_PATH" "$temp/original.json"
FORCE_REINSTALL=true
FAILURE=ci
expect_failure
assert test ! -f "$TOKEN_DASHBOARD_BUILD_PATH"
calls=$(wc -l < "$temp/npm-calls")
FORCE_REINSTALL=false
FAILURE=""
run_main || exit 1
assert test "$(wc -l < "$temp/npm-calls")" -eq "$((calls + 2))"
cp "$INSTALLED_STATE_PATH" "$temp/original.json"
CHECK=true
run_main || exit 1
assert cmp "$INSTALLED_STATE_PATH" "$temp/original.json"
CHECK=false
SKIP_DASHBOARD_BUILD=true
rm -f -- "$TOKEN_DASHBOARD_BUILD_PATH"
calls=$(wc -l < "$temp/npm-calls")
run_main || exit 1
assert test "$(wc -l < "$temp/npm-calls")" -eq "$calls"
assert test ! -f "$TOKEN_DASHBOARD_BUILD_PATH"
echo "Bash installation regression tests passed."
