#!/usr/bin/env bash
# REA user-level installation, update and diagnostics for Codex and optional VS Code MCP.
set -euo pipefail

MODE="${1:-}"
case "$MODE" in
  install|update|check) shift ;;
  *) echo "Usage: bash tools/rea.sh {install|update|check} [--vscode]" >&2; exit 2 ;;
esac
VSCODE=false
for arg in "$@"; do
  case "$arg" in
    --vscode) VSCODE=true ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

REA_PREFIX="$HOME/.ai-tools/npm"
REA_BIN="$REA_PREFIX/bin/rea"
export PATH="$REA_PREFIX/bin:$PATH"

node_supported() {
  node -e '
    const [major, minor, patch] = process.versions.node.split(".").map(Number);
    const ok = (major === 22 && (minor > 23 || (minor === 23 && patch >= 4))) ||
      (major === 24 && (minor > 22 || (minor === 22 && patch >= 1))) ||
      (major === 26 && (minor > 12 || (minor === 12 && patch >= 1)));
    process.exit(ok ? 0 : 1);
  '
}

check_requirements() {
  command -v node >/dev/null || { echo "Node.js missing." >&2; return 1; }
  command -v npm >/dev/null || { echo "npm missing." >&2; return 1; }
  if ! node_supported; then
    echo "Unsupported Node.js $(node --version). REA requires 22.23.4+, 24.22.1+, or 26.12.1+ in the corresponding major series." >&2
    return 1
  fi
}

check_install() {
  if [ ! -x "$REA_BIN" ]; then echo "REA not installed at $REA_BIN"; return 1; fi
  "$REA_BIN" --version
  "$REA_BIN" doctor --client codex
  if [ "$VSCODE" = true ]; then "$REA_BIN" doctor --client vscode; fi
  for dep in java jadx adb apktool; do
    if command -v "$dep" >/dev/null 2>&1; then
      echo "[OK] $dep: $(command -v "$dep")"
    else
      echo "[OPTIONAL] $dep missing (Android analysis capabilities may be limited)"
    fi
  done
}

if [ "$MODE" = check ]; then
  check_install
  exit
fi

check_requirements
mkdir -p "$REA_PREFIX"
case "$MODE" in
  install)
    npm install --global --prefix "$REA_PREFIX" rea-agents
    ;;
  update)
    # Updating the same stable user-level prefix preserves the MCP entrypoint path.
    npm install --global --prefix "$REA_PREFIX" rea-agents@latest
    ;;
esac

if [ ! -x "$REA_BIN" ]; then
  echo "REA executable missing after installation: $REA_BIN" >&2
  exit 1
fi

echo "Review REA's proposed Codex MCP configuration changes before approving."
"$REA_BIN" setup --client codex
if [ "$VSCODE" = true ]; then
  echo "Review REA's proposed VS Code MCP configuration changes before approving."
  "$REA_BIN" setup --client vscode
fi
echo "REA: $REA_BIN"
echo "Restart Codex / VS Code Insiders to load the MCP server."
echo "For terminal access, add $REA_PREFIX/bin to your shell PATH."
echo "Run: bash tools/rea.sh check$( [ "$VSCODE" = true ] && printf ' --vscode' )"
