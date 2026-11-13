#!/usr/bin/env bash
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed '/^parse_args "\$@"$/,$d' "$root/ai-tools.sh")
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

assert() {
    if ! "$@"; then echo "Assertion failed: $*" >&2; exit 1; fi
}
expect_failure() {
    if "$@"; then echo "Expected failure: $*" >&2; exit 1; fi
}
VERSION=8.2.3
MISSING_ASSET=false
MISSING_PYTHON_REQUIREMENT=false
NPM_FAILURE=false
SKIP_PREREQUISITE_INSTALL=true
get_rtk_asset_name() { echo rtk-x86_64-unknown-linux-musl.tar.gz; }
detect_arch() { echo amd64; }
get_github_latest_release() {
    echo query >> "$test_dir/queries"
    if [ "$MISSING_ASSET" = true ]; then echo '{"tag_name":"v8.2.3","assets":[]}'; return; fi
    printf '{"tag_name":"v%s","assets":[' "$VERSION"
    printf '{"name":"rtk-x86_64-unknown-linux-musl.tar.gz","browser_download_url":"https://example.invalid/rtk"},'
    printf '{"name":"codebase-memory-mcp-linux-amd64-portable.tar.gz","browser_download_url":"https://example.invalid/cbm"},'
    printf '{"name":"checksums.txt","browser_download_url":"https://example.invalid/checksums"}]}'
}
curl() {
    case "$2" in
        *registry.npmjs.org*)
            echo query >> "$test_dir/queries"
            printf '{"version":"%s","engines":{"node":">=24.5 <25","npm":"^11.2"}}' "$VERSION"
            ;;
        "$SERENA_PYPI")
            echo query >> "$test_dir/queries"
            local requires=">=3.12,<3.14"
            if [ "$MISSING_PYTHON_REQUIREMENT" = true ]; then requires=""; fi
            printf '{"info":{"version":"%s","requires_python":"%s"}}' "$VERSION" "$requires"
            ;;
        */install.sh)
            echo "$*" >> "$test_dir/calls"
            echo ':'
            ;;
        *raw.githubusercontent.com*)
            echo "$*" >> "$test_dir/calls"
            printf '{}' > "$4"
            ;;
        *) echo "Unexpected request: $*" >&2; return 1 ;;
    esac
}
ensure_node() { :; }
ensure_git() { :; }
ensure_uv() { :; }
node() { echo v24.5.0; }
npx() { :; }
npm() {
    if [ "$1" = --version ]; then echo 11.2.0; return; fi
    echo "npm $*" >> "$test_dir/calls"
    [ "$NPM_FAILURE" = false ]
}
uv() {
    echo "uv $*" >> "$test_dir/calls"
    if [ "$2" = install ]; then rm -f -- "$test_dir/python-missing"; return; fi
    if [ -f "$test_dir/python-missing" ]; then return 1; fi
    echo /compatible/python
}

initialize_install_plan "RTK,TokenOptimizer,Serena,CodebaseMemory" || exit 1
VERSION=9.0.0
assert test "$(get_token_latest_version)" = 8.2.3
assert test "$(get_serena_latest_version)" = 8.2.3
assert test "$(get_cbm_latest_version)" = 8.2.3
assert test "$(wc -l < "$test_dir/queries")" -eq 4
help=$(show_required_prerequisites "TokenOptimizer,Serena" 2>&1)
assert grep -Fq 'Node.js: >=24.5 <25' <<< "$help"
assert grep -Fq 'npm install --global "npm@^11.2"' <<< "$help"
assert grep -Fq 'sudo apt install git' <<< "$help"
assert grep -Fq 'uv python install ">=3.12,<3.14"' <<< "$help"
SKIP_DASHBOARD_BUILD=true
help=$(show_required_prerequisites TokenOptimizer 2>&1)
if grep -Eq 'apt install git|uv python' <<< "$help"; then
    echo "Guidance recommended prerequisites for unselected features" >&2
    exit 1
fi
SKIP_DASHBOARD_BUILD=false
get_rtk_installed_version() { echo 8.2.3; }
state_set_tool() { echo "$*" >> "$test_dir/state-calls"; }
CHECK=true
install_or_update_rtk || exit 1
CHECK=false
assert grep -q '^RTK 8.2.3 8.2.3 up-to-date' "$test_dir/state-calls"
assert test "$(wc -l < "$test_dir/queries")" -eq 4
test_install_prerequisites "TokenOptimizer,Serena" || exit 1
assert grep -q 'npm install --global --dry-run --ignore-scripts --engine-strict --force=false @ooples/token-optimizer-mcp@8.2.3' "$test_dir/calls"
assert grep -q 'npm ci .*--dry-run --ignore-scripts --engine-strict --force=false' "$test_dir/calls"
assert grep -q '/v8.2.3/package-lock.json' "$test_dir/calls"
assert grep -q 'uv python find .*>=3.12,<3.14' "$test_dir/calls"
assert test "$SERENA_PYTHON" = /compatible/python

NPM_FAILURE=true
expect_failure test_install_prerequisites TokenOptimizer
NPM_FAILURE=false
touch "$test_dir/python-missing"
expect_failure test_install_prerequisites Serena
SKIP_PREREQUISITE_INSTALL=false
test_install_prerequisites Serena || exit 1
assert grep -q 'uv python install >=3.12,<3.14' "$test_dir/calls"
bash() {
    cat >/dev/null
    echo "installer $CBM_DOWNLOAD_URL" >> "$test_dir/calls"
}
CBM_DOWNLOAD_URL=previous-value
install_cbm_official || exit 1
assert grep -q '/v8.2.3/install.sh' "$test_dir/calls"
assert grep -q 'installer .*/releases/download/v8.2.3' "$test_dir/calls"
assert test "$CBM_DOWNLOAD_URL" = previous-value
MISSING_ASSET=true
expect_failure initialize_install_plan RTK
MISSING_ASSET=false
MISSING_PYTHON_REQUIREMENT=true
expect_failure initialize_install_plan Serena
echo "Bash prerequisite regression tests passed."
