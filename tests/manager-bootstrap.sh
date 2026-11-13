#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
sed '/^parse_args "\$@"$/,$d' "$root/ai-tools.sh" > "$temp/ai-tools-source.sh"
source "$temp/ai-tools-source.sh"

MANAGED_SCRIPT_PATH="$temp/managed-ai-tools"
printf 'AI_TOOLS_VERSION="%s"\n' "$AI_TOOLS_VERSION" > "$MANAGED_SCRIPT_PATH"
EXTERNAL_COPY=true
ORIGINAL_ARGS=()
CONFIRM_REINSTALL=true
PROMPT_COUNT=0
read_yes_no() {
    [[ "$1" == "Force reinstall selected tools now?" && "$2" == false ]]
    PROMPT_COUNT=$((PROMPT_COUNT + 1))
    [ "$CONFIRM_REINSTALL" = true ]
}
install_self() { return 0; }
bash() { printf '%s\n' "$@" > "$temp/launch-args"; }

handle_external_copy
grep -Fxq "$MANAGED_SCRIPT_PATH" "$temp/launch-args"
grep -Fxq -- "--force-reinstall" "$temp/launch-args"
[ "$PROMPT_COUNT" -eq 1 ]

rm "$temp/launch-args"
ORIGINAL_ARGS=()
CONFIRM_REINSTALL=false
handle_external_copy
[ ! -f "$temp/launch-args" ]

CONFIRM_REINSTALL=true
ORIGINAL_ARGS=(--check)
PROMPT_COUNT=0
handle_external_copy
grep -Fxq -- "--check" "$temp/launch-args"
[ "$PROMPT_COUNT" -eq 0 ]

echo "Manager bootstrap tests passed."
