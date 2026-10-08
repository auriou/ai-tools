#!/usr/bin/env bash
# ai-tools.sh - Install, update, and diagnose local AI tools on Linux.
#
# Managed tools: RTK, Token Optimizer MCP (+dashboard), Serena, Codebase Memory MCP (+Graph UI).
# Portable: no sudo or system package manager required (Git is only checked).
#
# The script installs itself in: ~/.ai-tools/bin/ai-tools
# and adds ~/.ai-tools/bin (+ ~/.local/bin if needed) to the user PATH
# (through ~/.bashrc and ~/.zshrc when present, with ~/.profile as a fallback).
#
# Usage : ai-tools --help
# Without arguments: updates, reinstallation, dashboards, or diagnostics menu.

set -uo pipefail

# ===========================================================================
# Managed locations
# ===========================================================================

AI_ROOT="$HOME/.ai-tools"
BIN_DIR="$AI_ROOT/bin"
STATE_DIR="$AI_ROOT/state"
APPS_DIR="$AI_ROOT/apps"
LOGS_DIR="$AI_ROOT/logs"

INSTALLED_STATE_PATH="$STATE_DIR/installed.json"
MANAGED_SCRIPT_PATH="$BIN_DIR/ai-tools"

JQ_BIN="$BIN_DIR/jq"
JQ="jq"

# RTK
RTK_OWNER="rtk-ai"
RTK_REPO="rtk"
RTK_API_LATEST="https://api.github.com/repos/$RTK_OWNER/$RTK_REPO/releases/latest"
RTK_EXE="$BIN_DIR/rtk"

# Token Optimizer
TOKEN_PACKAGE="@ooples/token-optimizer-mcp"
TOKEN_DASHBOARD_REPO="https://github.com/ooples/token-optimizer-mcp.git"
TOKEN_DASHBOARD_DIR="$APPS_DIR/token-optimizer-dashboard"

# Node.js (Token Optimizer prerequisite, portable download)
NODE_APPS_DIR="$APPS_DIR/nodejs"

# Serena
SERENA_TOOL="serena-agent"
SERENA_BIN_DIR="$HOME/.local/bin"
SERENA_PYPI="https://pypi.org/pypi/serena-agent/json"

# Codebase Memory
CBM_INSTALL_DIR="$HOME/.local/bin"
CBM_EXE="$CBM_INSTALL_DIR/codebase-memory-mcp"
CBM_INSTALLER_URL="https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh"
CBM_API_LATEST="https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/latest"

# Copilot global user instructions
COPILOT_INSTRUCTIONS_DIR="$HOME/.copilot/instructions"
AI_INSTRUCTION_FILE="$COPILOT_INSTRUCTIONS_DIR/ai-tools.instructions.md"
COPILOT_CONFIG_HOME="${COPILOT_HOME:-$HOME/.copilot}"
COPILOT_MCP_CONFIG_PATH="$COPILOT_CONFIG_HOME/mcp-config.json"

# Codex global user instructions
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_AGENTS_FILE="$CODEX_HOME/AGENTS.md"

ALL_TOOL_NAMES=(RTK TokenOptimizer Serena CodebaseMemory)

# ===========================================================================
# Options / runtime state
# ===========================================================================

CHECK=false
CHOOSE_TOOLS=false
ALL=false
FORCE_REINSTALL=false
INTERACTIVE_MENU=true
TOOLS=""
UI=""
COMMAND=""
DASHBOARD=""
SKIP_DASHBOARD_BUILD=false
SKIP_PREREQUISITE_INSTALL=false
VERBOSE=false

# ===========================================================================
# Output (all messages go to stderr; stdout is reserved for computed values)
# ===========================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

write_section() {
    local text="$1" mode="${2:-}"
    if [ "$mode" != "always" ] && [ "$VERBOSE" != true ]; then return; fi
    {
        echo ""
        echo -e "${GRAY}==============================================================================${NC}"
        echo -e "${CYAN} $text${NC}"
        echo -e "${GRAY}==============================================================================${NC}"
    } >&2
}
write_ok()   { echo -e "${GREEN}[OK]${NC}   $1" >&2; }
write_info() { [ "$VERBOSE" = true ] && echo -e "${CYAN}[INFO]${NC} $1" >&2; return 0; }
write_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
write_fail() { echo -e "${RED}[ERR]${NC}  $1" >&2; }

show_help() {
    cat <<'EOF'
Usage: ai-tools [options] [dash [token|serena|graph|rtk]]

Install, update, and diagnose local AI tools on Linux.
Managed tools: RTK, Token Optimizer (+dashboard), Serena, Codebase Memory.

If already installed, running an external copy updates only the manager script.
Then run 'ai-tools --all' to install or update all tools.

Options:
    --check                       Diagnostics only; no persistent changes.
    --choose-tools                Reopen managed tool selection.
    --all                         Select all four tools without prompting.
    --force-reinstall             Reinstall tools even if they are up to date.
    --tools=A,B,C                 Explicit selection (RTK,TokenOptimizer,Serena,CodebaseMemory).
    --ui=NAME                     Launch the requested UI (RTK|TokenOptimizer|Serena|CodebaseMemory).
    --skip-dashboard-build        Do not build the Token Optimizer dashboard.
    --skip-prerequisite-install   Do not install missing prerequisites (fail if missing).
    --verbose                     Show technical details.
    -h, --help                    Show this help.

Commands:
    (no arguments)    Main menu: updates, reinstallation, dashboards, diagnostics.
    dash              Show managed dashboards and ask which one to launch.
    dash token        Launch the Token Optimizer dashboard directly.
    dash serena       Launch the Serena dashboard directly.
    dash graph        Launch the Codebase Memory Graph UI directly.
    dash rtk          Show RTK savings with 'rtk gain'.
EOF
}

parse_args() {
    if [ $# -gt 0 ]; then INTERACTIVE_MENU=false; fi
    while [ $# -gt 0 ]; do
        case "$1" in
            --check) CHECK=true; shift ;;
            --choose-tools) CHOOSE_TOOLS=true; shift ;;
            --all) ALL=true; shift ;;
            --force-reinstall) FORCE_REINSTALL=true; shift ;;
            --tools=*|--ui=*)
                if [ -z "${1#*=}" ]; then
                    write_fail "Missing value for ${1%%=*}."
                    exit 1
                fi
                case "$1" in
                    --tools=*) TOOLS="${1#*=}" ;;
                    --ui=*) UI="${1#*=}" ;;
                esac
                shift
                ;;
            --tools|--ui)
                if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
                    write_fail "Missing value for $1."
                    exit 1
                fi
                case "$1" in
                    --tools) TOOLS="$2" ;;
                    --ui) UI="$2" ;;
                esac
                shift 2
                ;;
            --skip-dashboard-build) SKIP_DASHBOARD_BUILD=true; shift ;;
            --skip-prerequisite-install) SKIP_PREREQUISITE_INSTALL=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            dash)
                COMMAND="dash"; shift
                if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
                    DASHBOARD="$1"; shift
                fi
                ;;
            *)
                write_fail "Unknown argument: $1 (see --help)"
                exit 1
                ;;
        esac
    done
}

validate_args() {
    if [ "$CHECK" = true ] && [ "$FORCE_REINSTALL" = true ]; then
        write_fail "--force-reinstall and --check cannot be combined."
        exit 1
    fi
    if [ "$CHECK" = true ] && { [ -n "$UI" ] || [ "$COMMAND" = "dash" ]; }; then
        write_fail "--check cannot launch a dashboard."
        exit 1
    fi
    if [ -n "$TOOLS" ]; then
        local t
        local saved_ifs="$IFS"
        IFS=','
        for t in $TOOLS; do
            case "$t" in
                RTK|TokenOptimizer|Serena|CodebaseMemory) : ;;
                *) IFS="$saved_ifs"; write_fail "Invalid tool in --tools: $t"; exit 1 ;;
            esac
        done
        IFS="$saved_ifs"
    fi
    if [ -n "$UI" ]; then
        case "$UI" in
            RTK|TokenOptimizer|Serena|CodebaseMemory) : ;;
            *) write_fail "Invalid UI: $UI (expected RTK|TokenOptimizer|Serena|CodebaseMemory)"; exit 1 ;;
        esac
    fi
    if [ -n "$DASHBOARD" ]; then
        case "$DASHBOARD" in
            token|serena|graph|rtk) : ;;
            *) write_fail "Invalid dashboard: $DASHBOARD (expected token|serena|graph|rtk)"; exit 1 ;;
        esac
    fi
}

# ===========================================================================
# Directories / PATH / self-installation
# ===========================================================================

ensure_ai_directories() {
    mkdir -p "$AI_ROOT" "$BIN_DIR" "$STATE_DIR" "$APPS_DIR" "$LOGS_DIR"
}

add_user_path() {
    local dir="$1"
    [ -n "$dir" ] || return
    if [ ! -d "$dir" ]; then
        write_warn "PATH not updated because the directory does not exist: $dir"
        return
    fi

    case ":$PATH:" in
        *":$dir:"*) : ;;
        *) export PATH="$dir:$PATH" ;;
    esac

    if [ "$CHECK" = true ]; then return 0; fi

    local marker="# added by ai-tools ($dir)"
    local line="export PATH=\"$dir:\$PATH\"  $marker"
    local rc_file

    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc_file" ] && ! grep -qF "$marker" "$rc_file" 2>/dev/null; then
            printf '\n%s\n' "$line" >> "$rc_file"
            write_ok "Added to PATH ($rc_file): $dir"
        fi
    done

    touch "$HOME/.profile"
    if ! grep -qF "$marker" "$HOME/.profile" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$HOME/.profile"
        write_ok "Added to PATH ($HOME/.profile): $dir"
    fi
}

ensure_codex_cli_path() {
    # Codex on Linux is usually installed in ~/.local/bin, /usr/local/bin,
    # /usr/bin, or an npm/nvm directory already in PATH. Discover the
    # executable instead of assuming a single location.
    if command -v codex >/dev/null 2>&1; then
        return 0
    fi

    local candidates=(
        "$HOME/.local/bin/codex"
        "$HOME/.npm-global/bin/codex"
        "/usr/local/bin/codex"
        "/usr/bin/codex"
        "/opt/codex/bin/codex"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [ -x "$candidate" ]; then
            if [ "$CHECK" = true ]; then export PATH="$(dirname "$candidate"):$PATH"; else add_user_path "$(dirname "$candidate")"; fi
            hash -r 2>/dev/null || true
            write_info "Codex CLI detected: $candidate"
            return 0
        fi
    done

    # Fallback for nonstandard local installations.
    local found=""
    for candidate in "$HOME/.local" "$HOME/.npm-global" "$HOME/.nvm"; do
        [ -d "$candidate" ] || continue
        found=$(find "$candidate" -type f -name codex -perm -u+x 2>/dev/null | head -n1)
        if [ -n "$found" ]; then
            if [ "$CHECK" = true ]; then export PATH="$(dirname "$found"):$PATH"; else add_user_path "$(dirname "$found")"; fi
            hash -r 2>/dev/null || true
            write_info "Codex CLI detected: $found"
            return 0
        fi
    done

    return 1
}

install_self() {
    local update_only="${1:-false}"
    if [ "$update_only" != true ]; then
        ensure_ai_directories || return 1
        add_user_path "$BIN_DIR" || return 1
    fi

    local source="${BASH_SOURCE[0]}"
    [ -f "$source" ] || return
    source="$(cd "$(dirname "$source")" && pwd)/$(basename "$source")"

    if [ ! "$source" -ef "$MANAGED_SCRIPT_PATH" ]; then
        cp "$source" "$MANAGED_SCRIPT_PATH" || return 1
        if [ "$update_only" = true ]; then
            write_ok "Manager script updated: $MANAGED_SCRIPT_PATH"
        else
            write_ok "Script installed: $MANAGED_SCRIPT_PATH"
        fi
    fi
    chmod +x "$MANAGED_SCRIPT_PATH" 2>/dev/null || true
}

# ===========================================================================
# Generic helpers
# ===========================================================================

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "unsupported" ;;
    esac
}

normalize_version() {
    local v="${1:-}"
    [ -n "$v" ] || return 0
    printf '%s' "$v" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?' | head -n1
}

compare_version_text() {
    local a b
    a=$(normalize_version "${1:-}")
    b=$(normalize_version "${2:-}")
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" = "$b" ]
}

get_github_latest_release() {
    curl -fsSL -H "User-Agent: ai-tools-updater" -H "Accept: application/vnd.github+json" "$1"
}

check_dependencies() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v tar  >/dev/null 2>&1 || missing+=("tar")
    command -v sha256sum >/dev/null 2>&1 || missing+=("sha256sum")
    if [ ${#missing[@]} -gt 0 ]; then
        write_fail "Missing system tools: ${missing[*]}. Install them using your distribution's package manager."
        exit 1
    fi
}

# ===========================================================================
# Portable jq (bootstrap: jq is not yet available to parse the API response)
# ===========================================================================

ensure_jq() {
    if command -v jq >/dev/null 2>&1; then
        JQ="jq"
        return 0
    fi
    if [ -x "$JQ_BIN" ]; then
        JQ="$JQ_BIN"
        return 0
    fi

    if [ "$CHECK" = true ]; then
        write_warn "jq is missing (required for state and MCP configuration)."
        return 1
    fi

    write_info "jq is missing: installing a portable copy..."
    mkdir -p "$BIN_DIR"

    local arch asset
    arch=$(detect_arch)
    case "$arch" in
        amd64) asset="jq-linux-amd64" ;;
        arm64) asset="jq-linux-arm64" ;;
        *) write_fail "Unsupported architecture for jq: $(uname -m)"; exit 1 ;;
    esac

    local api="https://api.github.com/repos/jqlang/jq/releases/latest"
    local release_json
    release_json=$(curl -fsSL -H "User-Agent: ai-tools-updater" "$api") || { write_fail "Cannot reach the GitHub API for jq."; exit 1; }

    local dl_url cs_url
    dl_url=$(printf '%s' "$release_json" | grep -o "\"browser_download_url\":[[:space:]]*\"[^\"]*/${asset}\"" | head -n1 | sed -E 's/.*"(https:[^"]+)".*/\1/')
    cs_url=$(printf '%s' "$release_json" | grep -o '"browser_download_url":[[:space:]]*"[^"]*/sha256sum.txt"' | head -n1 | sed -E 's/.*"(https:[^"]+)".*/\1/')

    [ -n "$dl_url" ] || { write_fail "jq release asset not found: $asset"; exit 1; }

    local tmp; tmp=$(mktemp -d)
    curl -fsSL -H "User-Agent: ai-tools-updater" -o "$tmp/$asset" "$dl_url" || { write_fail "jq download failed."; rm -rf "$tmp"; exit 1; }

    if [ -n "$cs_url" ]; then
        curl -fsSL -H "User-Agent: ai-tools-updater" -o "$tmp/sha256sum.txt" "$cs_url" || true
        if [ -f "$tmp/sha256sum.txt" ]; then
            local expected actual
            expected=$(awk -v f="$asset" '$2==f {print $1}' "$tmp/sha256sum.txt" | head -n1)
            if [ -n "$expected" ]; then
                actual=$(sha256sum "$tmp/$asset" | awk '{print $1}')
                if [ "$expected" != "$actual" ]; then
                    write_fail "Invalid jq checksum (expected $expected, got $actual)."
                    rm -rf "$tmp"
                    exit 1
                fi
            fi
        fi
    fi

    install -m 755 "$tmp/$asset" "$JQ_BIN"
    rm -rf "$tmp"
    JQ="$JQ_BIN"
    write_ok "jq installed: $JQ_BIN"
}

# ===========================================================================
# Persistent state (installed.json, through jq)
# ===========================================================================

state_init() {
    if [ "$CHECK" = true ]; then
        local source_path="$INSTALLED_STATE_PATH"
        INSTALLED_STATE_PATH=$(mktemp) || return 1
        trap 'rm -f -- "$INSTALLED_STATE_PATH"' EXIT
        if [ -s "$source_path" ]; then
            cp "$source_path" "$INSTALLED_STATE_PATH" || return 1
        fi
    else
        mkdir -p "$STATE_DIR" || return 1
    fi
    if [ ! -s "$INSTALLED_STATE_PATH" ]; then
        printf '%s' '{"schemaVersion":1,"selectedTools":[],"lastRun":null,"tools":{}}' > "$INSTALLED_STATE_PATH"
        return
    fi
    if ! "$JQ" -e . "$INSTALLED_STATE_PATH" >/dev/null 2>&1; then
        if [ "$CHECK" = true ]; then
            write_warn "Cannot read installed.json. Running diagnostics with empty temporary state."
        else
            local backup="$INSTALLED_STATE_PATH.corrupt.$(date +%Y%m%d-%H%M%S)"
            cp "$INSTALLED_STATE_PATH" "$backup" || return 1
            write_warn "Cannot read installed.json. Backup: $backup"
        fi
        printf '%s' '{"schemaVersion":1,"selectedTools":[],"lastRun":null,"tools":{}}' > "$INSTALLED_STATE_PATH"
    fi
}

state_get_selected_tools() {
    "$JQ" -r '.selectedTools // [] | join(",")' "$INSTALLED_STATE_PATH" 2>/dev/null
}

state_set_selected_tools() {
    local csv="$1" tmp
    local json_arr
    json_arr=$(printf '%s' "$csv" | "$JQ" -R 'split(",") | map(select(length>0))')
    tmp=$(mktemp)
    "$JQ" --argjson sel "$json_arr" '.selectedTools=$sel' "$INSTALLED_STATE_PATH" > "$tmp" && mv "$tmp" "$INSTALLED_STATE_PATH"
}

state_set_tool() {
    local tool="$1" installed="${2:-}" latest="${3:-}" status="$4" was_updated="${5:-false}"
    local prev_installed
    prev_installed=$("$JQ" -r --arg t "$tool" '.tools[$t].installed // empty' "$INSTALLED_STATE_PATH" 2>/dev/null)

    local updated_from="null"
    if [ "$was_updated" = "true" ] && [ -n "$prev_installed" ] && [ -n "$installed" ] && [ "$prev_installed" != "$installed" ]; then
        updated_from="\"$prev_installed\""
    fi

    local now tmp
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    tmp=$(mktemp)
    "$JQ" --arg t "$tool" \
          --arg installed "$installed" \
          --arg latest "$latest" \
          --arg status "$status" \
          --argjson updatedFrom "$updated_from" \
          --arg lastChecked "$now" \
          '.tools[$t] = {
              installed: (if $installed == "" then null else $installed end),
              latest: (if $latest == "" then null else $latest end),
              status: $status,
              updatedFrom: $updatedFrom,
              lastChecked: $lastChecked
          }' "$INSTALLED_STATE_PATH" > "$tmp" && mv "$tmp" "$INSTALLED_STATE_PATH"
}

state_save_last_run() {
    local now tmp
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    tmp=$(mktemp)
    "$JQ" --arg now "$now" '.lastRun=$now' "$INSTALLED_STATE_PATH" > "$tmp" && mv "$tmp" "$INSTALLED_STATE_PATH"
}

# ===========================================================================
# Interactive selection
# ===========================================================================

show_tool_descriptions() {
    write_section "Available AI tools" always
    {
        echo -e "${YELLOW}1. RTK${NC}"
        echo "   Purpose: reduce terminal output before it reaches the model."
        echo "   Useful for: git, tests, logs, Docker, kubectl, and other verbose commands."
        echo "   In short: 'show less'."
        echo ""
        echo -e "${YELLOW}2. Token Optimizer${NC}"
        echo "   Purpose: reduce the context returned by file reads and searches."
        echo "   Useful for: smart_read, smart_grep, smart_glob, smart_diff, caching, reports."
        echo "   In short: 'read less'."
        echo ""
        echo -e "${YELLOW}3. Serena${NC}"
        echo "   Purpose: navigate code by symbols instead of reading entire files."
        echo "   Useful for: classes, functions, methods, definitions, and references."
        echo "   In short: 'go straight to the right symbol'."
        echo ""
        echo -e "${YELLOW}4. Codebase Memory${NC}"
        echo "   Purpose: build structured memory of the repository and its relationships."
        echo "   Useful for: architecture, dependencies, calls, impact, and semantic search."
        echo "   Includes a local Graph UI."
        echo "   In short: 'understand the whole repository'."
        echo ""
        echo "How they work together:"
        echo "   RTK -> terminal | Token Optimizer -> context | Serena -> symbols | Codebase Memory -> architecture"
    } >&2
}

read_yes_no() {
    local question="$1" default_yes="${2:-true}"
    local suffix="[y/N]"
    [ "$default_yes" = true ] && suffix="[Y/n]"
    local reply
    while true; do
        read -r -p "$question $suffix " reply || return 1
        if [ -z "$reply" ]; then
            [ "$default_yes" = true ] && return 0 || return 1
        fi
        case "$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')" in
            o|oui|y|yes) return 0 ;;
            n|non|no) return 1 ;;
        esac
        write_warn "Please answer Y or N."
    done
}

# Sets SELECTED_TOOLS_CSV (avoids capturing stdout from an interactive menu).
select_tools_interactive() {
    local action="${1:-Install}"
    SELECTED_TOOLS_CSV=""
    show_tool_descriptions
    {
        echo ""
        echo "What would you like to do?"
        echo "  [A] $action all tools"
        echo "  [C] Choose individual tools"
        echo "  [Q] Quit"
        echo ""
    } >&2

    local choice
    while true; do
        read -r -p "Choice [A/C/Q] " choice || return 1
        choice=$(printf '%s' "${choice:-A}" | tr '[:lower:]' '[:upper:]')
        case "$choice" in
            A)
                SELECTED_TOOLS_CSV=$(IFS=,; echo "${ALL_TOOL_NAMES[*]}")
                return
                ;;
            C)
                local selected=()
                read_yes_no "$action RTK ?" true && selected+=("RTK")
                read_yes_no "$action Token Optimizer ?" true && selected+=("TokenOptimizer")
                read_yes_no "$action Serena ?" true && selected+=("Serena")
                read_yes_no "$action Codebase Memory ?" true && selected+=("CodebaseMemory")
                SELECTED_TOOLS_CSV=$(IFS=,; echo "${selected[*]}")
                return
                ;;
            Q)
                SELECTED_TOOLS_CSV=""
                return
                ;;
            *) write_warn "Invalid choice." ;;
        esac
    done
}

# Sets RESOLVED_TOOLS_CSV.
resolve_selected_tools() {
    if [ "$ALL" = true ]; then
        RESOLVED_TOOLS_CSV=$(IFS=,; echo "${ALL_TOOL_NAMES[*]}")
        return
    fi
    if [ -n "$TOOLS" ]; then
        RESOLVED_TOOLS_CSV="$TOOLS"
        return
    fi
    if [ "$FORCE_REINSTALL" = true ]; then
        select_tools_interactive Reinstall || return 1
        RESOLVED_TOOLS_CSV="$SELECTED_TOOLS_CSV"
        return
    fi

    local state_selected
    state_selected=$(state_get_selected_tools)
    if [ "$CHECK" = true ] && [ -z "$state_selected" ]; then
        RESOLVED_TOOLS_CSV=$(IFS=,; echo "${ALL_TOOL_NAMES[*]}")
        return
    fi
    if [ "$CHOOSE_TOOLS" = true ] || [ -z "$state_selected" ]; then
        select_tools_interactive || return 1
        RESOLVED_TOOLS_CSV="$SELECTED_TOOLS_CSV"
        return
    fi

    RESOLVED_TOOLS_CSV="$state_selected"
}

read_main_action() {
    write_section "AI Tools" always
    {
        echo "  [1] Install / update"
        echo "  [2] Force reinstallation"
        echo "  [3] Dashboards"
        echo "  [4] Diagnostics"
        echo "  [Q] Quit"
    } >&2
    local choice
    while true; do
        read -r -p "Choice [1-4/Q] " choice || return 1
        case "$choice" in
            1) MAIN_ACTION=update; return 0 ;;
            2) MAIN_ACTION=reinstall; return 0 ;;
            3) MAIN_ACTION=dash; return 0 ;;
            4) MAIN_ACTION=check; return 0 ;;
            q|Q) MAIN_ACTION=quit; return 0 ;;
            *) write_warn "Invalid choice." ;;
        esac
    done
}

# ===========================================================================
# Prerequisites
# ===========================================================================

ensure_git() {
    if command -v git >/dev/null 2>&1; then
        write_info "Git : $(git --version)"
        return 0
    fi
    write_warn "Git is missing. Install it using your distribution's package manager (apt/dnf/pacman/zypper...). The Token Optimizer dashboard cannot be managed without Git."
    return 1
}

ensure_node() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
        write_info "Node : $(node --version) / npm $(npm --version)"
        return 0
    fi

    if [ "$CHECK" = true ]; then
        write_warn "Node/npm/npx are missing or incomplete."
        return 1
    fi
    if [ "$SKIP_PREREQUISITE_INSTALL" = true ]; then
        write_fail "Node/npm/npx are missing."
        exit 1
    fi

    write_info "Installing portable Node.js LTS..."
    local arch node_arch
    arch=$(detect_arch)
    case "$arch" in
        amd64) node_arch="x64" ;;
        arm64) node_arch="arm64" ;;
        *) write_fail "Unsupported architecture for Node.js: $(uname -m)"; exit 1 ;;
    esac

    local index_json version
    index_json=$(curl -fsSL "https://nodejs.org/dist/index.json") || { write_fail "Cannot reach nodejs.org."; exit 1; }
    version=$(printf '%s' "$index_json" | "$JQ" -r '[.[] | select(.lts != false)][0].version // empty')
    [ -n "$version" ] || { write_fail "Node.js LTS version not found."; exit 1; }

    local archive="node-${version}-linux-${node_arch}.tar.xz"
    local url="https://nodejs.org/dist/${version}/${archive}"
    local shasums_url="https://nodejs.org/dist/${version}/SHASUMS256.txt"

    mkdir -p "$NODE_APPS_DIR"
    local tmp; tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/$archive" "$url" || { write_fail "Node.js download failed."; rm -rf "$tmp"; exit 1; }
    curl -fsSL -o "$tmp/SHASUMS256.txt" "$shasums_url" || true

    if [ -f "$tmp/SHASUMS256.txt" ]; then
        local expected actual
        expected=$(awk -v f="$archive" '$2==f {print $1}' "$tmp/SHASUMS256.txt" | head -n1)
        if [ -n "$expected" ]; then
            actual=$(sha256sum "$tmp/$archive" | awk '{print $1}')
            if [ "$expected" != "$actual" ]; then
                write_fail "Invalid Node.js checksum."
                rm -rf "$tmp"
                exit 1
            fi
        fi
    fi

    rm -rf "${NODE_APPS_DIR:?}/${version}"
    mkdir -p "$NODE_APPS_DIR/$version"
    if ! tar -xf "$tmp/$archive" -C "$NODE_APPS_DIR/$version" --strip-components=1; then
        write_fail "Node.js extraction failed."
        rm -rf "$tmp" "${NODE_APPS_DIR:?}/${version}"
        exit 1
    fi
    rm -rf "$tmp"

    add_user_path "$NODE_APPS_DIR/$version/bin"
    write_ok "Node.js installed: $version"
}

ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        write_info "uv : $(uv --version)"
        [ -d "$SERENA_BIN_DIR" ] && add_user_path "$SERENA_BIN_DIR"
        return 0
    fi

    if [ "$CHECK" = true ]; then
        write_warn "uv is missing."
        return 1
    fi
    if [ "$SKIP_PREREQUISITE_INSTALL" = true ]; then
        write_fail "uv is missing."
        exit 1
    fi

    write_info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh || { write_fail "uv installation failed."; exit 1; }
    add_user_path "$SERENA_BIN_DIR"
}

# ===========================================================================
# RTK
# ===========================================================================

get_rtk_installed_version() {
    local exe=""
    if [ -x "$RTK_EXE" ]; then exe="$RTK_EXE"
    elif command -v rtk >/dev/null 2>&1; then exe="rtk"
    fi
    [ -n "$exe" ] || return 0
    normalize_version "$("$exe" --version 2>&1)"
}

install_or_update_rtk() {
    write_section "RTK"

    local installed latest release_json arch asset
    installed=$(get_rtk_installed_version)
    release_json=$(get_github_latest_release "$RTK_API_LATEST") || { write_fail "Cannot reach GitHub for RTK."; return 1; }
    latest=$(printf '%s' "$release_json" | "$JQ" -r '.tag_name // empty' | sed 's/^v//')

    write_info "Installed: ${installed:-not installed}"
    write_info "Available: ${latest:-unknown}"

    if [ "$CHECK" = true ]; then
        local status="not-installed"
        if [ -n "$installed" ]; then
            if compare_version_text "$installed" "$latest"; then status="up-to-date"; else status="update-available"; fi
        fi
        state_set_tool "RTK" "$installed" "$latest" "$status"
        return 0
    fi

    arch=$(detect_arch)
    case "$arch" in
        amd64) asset="rtk-x86_64-unknown-linux-musl.tar.gz" ;;
        arm64) asset="rtk-aarch64-unknown-linux-gnu.tar.gz" ;;
        *) write_fail "Unsupported architecture for RTK: $(uname -m)"; return 1 ;;
    esac

    local was_updated=false
    if [ "$FORCE_REINSTALL" = true ] || [ -z "$installed" ] || ! compare_version_text "$installed" "$latest"; then
        was_updated=true
        local dl_url cs_url
        dl_url=$(printf '%s' "$release_json" | "$JQ" -r --arg name "$asset" '.assets[] | select(.name==$name) | .browser_download_url')
        cs_url=$(printf '%s' "$release_json" | "$JQ" -r '.assets[] | select(.name=="checksums.txt") | .browser_download_url')
        [ -n "$dl_url" ] || { write_fail "RTK release asset not found: $asset"; return 1; }

        local tmp; tmp=$(mktemp -d)
        write_info "Downloading RTK $latest..."
        curl -fsSL -H "User-Agent: ai-tools-updater" -o "$tmp/$asset" "$dl_url" || { write_fail "RTK download failed."; rm -rf "$tmp"; return 1; }

        if [ -n "$cs_url" ]; then
            curl -fsSL -H "User-Agent: ai-tools-updater" -o "$tmp/checksums.txt" "$cs_url" || true
            if [ -f "$tmp/checksums.txt" ]; then
                local expected actual
                expected=$(awk -v f="$asset" '$2==f {print $1}' "$tmp/checksums.txt" | head -n1)
                if [ -n "$expected" ]; then
                    actual=$(sha256sum "$tmp/$asset" | awk '{print $1}')
                    if [ "$expected" != "$actual" ]; then
                        write_fail "Invalid RTK checksum."
                        rm -rf "$tmp"
                        return 1
                    fi
                fi
            fi
        fi

        if ! tar -xzf "$tmp/$asset" -C "$tmp"; then
            write_fail "RTK extraction failed."
            rm -rf "$tmp"
            return 1
        fi
        local candidate
        candidate=$(find "$tmp" -type f -name "rtk" | head -n1)
        [ -n "$candidate" ] || { write_fail "rtk is missing from the archive."; rm -rf "$tmp"; return 1; }
        if ! install -m 755 "$candidate" "$RTK_EXE"; then
            write_fail "RTK installation failed."
            rm -rf "$tmp"
            return 1
        fi
        rm -rf "$tmp"
        write_ok "RTK installed/updated: $latest"
    else
        write_info "RTK is already up to date."
    fi

    add_user_path "$BIN_DIR"
    installed=$(get_rtk_installed_version)

    if command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ]; then
        write_info "Claude detected -> checking/initializing global RTK integration..."
        if "$RTK_EXE" init -g >/dev/null 2>&1; then
            write_info "RTK init -g completed."
        else
            write_warn "Could not apply rtk init -g."
        fi
    fi

    if [ -n "$(get_copilot_mcp_targets)" ]; then
        write_info "Copilot detected -> checking/initializing global RTK integration..."
        if "$RTK_EXE" init -g --copilot >/dev/null 2>&1; then
            write_info "RTK init -g --copilot completed."
        else
            write_warn "Could not apply rtk init -g --copilot."
        fi
    fi

    if command -v codex >/dev/null 2>&1 || [ -d "$CODEX_HOME" ]; then
        write_info "Codex detected -> checking/initializing global RTK integration..."
        if "$RTK_EXE" init -g --codex >/dev/null 2>&1; then
            write_info "RTK init -g --codex completed."
        else
            write_warn "Could not apply rtk init -g --codex."
        fi
    fi

    state_set_tool "RTK" "$installed" "$latest" "up-to-date" "$was_updated"
}

# ===========================================================================
# Token Optimizer
# ===========================================================================

get_token_installed_version() {
    command -v npm >/dev/null 2>&1 || return 0
    local json
    json=$(npm list -g "$TOKEN_PACKAGE" --depth=0 --json 2>/dev/null) || return 0
    printf '%s' "$json" | "$JQ" -r --arg pkg "$TOKEN_PACKAGE" '.dependencies[$pkg].version // empty' 2>/dev/null
}

get_token_latest_version() {
    command -v npm >/dev/null 2>&1 || return 0
    npm view "$TOKEN_PACKAGE" version 2>/dev/null | tr -d '\r'
}

update_token_dashboard() {
    local token_version="$1"
    if [ "$SKIP_DASHBOARD_BUILD" = true ]; then
        write_warn "Token Optimizer dashboard skipped (--skip-dashboard-build)."
        return
    fi
    if [ -z "$token_version" ]; then
        write_warn "Unknown Token Optimizer version: dashboard not updated."
        return
    fi
    if ! command -v git >/dev/null 2>&1; then
        write_warn "Git unavailable: Token Optimizer dashboard not managed."
        return
    fi

    local need_build="$FORCE_REINSTALL" has_local_changes=false
    local release_tag="v${token_version}"

    if [ -d "$TOKEN_DASHBOARD_DIR/.git" ]; then
        local rc=0
        (
            cd "$TOKEN_DASHBOARD_DIR" || exit 99
            changes=$(git status --porcelain 2>/dev/null)
            if [ -n "$changes" ]; then
                write_warn "Token Optimizer dashboard has local changes: Git update skipped."
                exit 10
            fi
            target=$(git rev-parse --verify --quiet "refs/tags/${release_tag}^{commit}" 2>/dev/null || true)
            if [ -z "$target" ]; then
                remote_tag=$(git ls-remote --tags --refs origin "refs/tags/${release_tag}" 2>/dev/null || true)
                if [ -z "$remote_tag" ]; then
                    write_warn "Release ${release_tag} not found in the repository: dashboard not updated."
                    exit 11
                fi
                git fetch --depth 1 origin "refs/tags/${release_tag}:refs/tags/${release_tag}" || exit 12
                target=$(git rev-parse --verify --quiet "refs/tags/${release_tag}^{commit}" 2>/dev/null || true)
            fi
            current=$(git rev-parse HEAD 2>/dev/null || true)
            if [ "$current" != "$target" ]; then
                git checkout "$release_tag" || exit 12
                exit 20
            fi
            exit 0
        ) || rc=$?

        case "$rc" in
            10) has_local_changes=true ;;
            11) return ;;
            20) need_build=true ;;
            0) : ;;
            *) write_warn "Token Optimizer dashboard update incomplete (exit code $rc)." ;;
        esac
    else
        if [ -d "$TOKEN_DASHBOARD_DIR" ]; then
            local backup="$TOKEN_DASHBOARD_DIR.backup.$(date +%Y%m%d-%H%M%S)"
            mv "$TOKEN_DASHBOARD_DIR" "$backup"
            write_warn "Previous dashboard directory moved: $backup"
        fi
        git clone --depth 1 --branch "$release_tag" "$TOKEN_DASHBOARD_REPO" "$TOKEN_DASHBOARD_DIR" || { write_warn "Token Optimizer dashboard clone failed."; return; }
        need_build=true
    fi

    [ -d "$TOKEN_DASHBOARD_DIR/node_modules" ] || need_build=true

    if [ "$need_build" = true ]; then
        if (cd "$TOKEN_DASHBOARD_DIR" && npm ci && npm run build); then
            write_ok "Token Optimizer dashboard built."
        else
            write_warn "Token Optimizer dashboard build failed."
        fi
    elif [ "$has_local_changes" = true ]; then
        write_ok "Local Token Optimizer dashboard preserved."
    else
        write_info "Token Optimizer dashboard is already up to date."
    fi
}

install_or_update_token_optimizer() {
    write_section "Token Optimizer"

    ensure_node
    if ! command -v npm >/dev/null 2>&1; then
        state_set_tool "TokenOptimizer" "" "" "prerequisite-missing"
        return
    fi

    local installed latest
    installed=$(get_token_installed_version)
    latest=$(get_token_latest_version)

    write_info "Installed: ${installed:-not installed}"
    write_info "Available: ${latest:-unknown}"

    local was_updated=false
    if [ "$CHECK" != true ]; then
        if [ "$FORCE_REINSTALL" = true ] || [ -z "$installed" ] || { [ -n "$latest" ] && ! compare_version_text "$installed" "$latest"; }; then
            was_updated=true
            local install_args=(install -g)
            if [ "$FORCE_REINSTALL" = true ]; then install_args+=(--force); fi
            if ! npm "${install_args[@]}" "${TOKEN_PACKAGE}@latest"; then
                write_fail "Token Optimizer installation failed."
                return 1
            fi
            installed=$(get_token_installed_version)
            write_ok "Token Optimizer : $installed"
        else
            write_info "Token Optimizer is already up to date."
        fi

        update_token_dashboard "$installed"
    fi

    local status="not-installed"
    if [ -n "$installed" ]; then
        if [ -n "$latest" ] && compare_version_text "$installed" "$latest"; then status="up-to-date"; else status="update-available"; fi
    fi
    state_set_tool "TokenOptimizer" "$installed" "$latest" "$status" "$was_updated"
}

# ===========================================================================
# Serena
# ===========================================================================

get_serena_installed_version() {
    if command -v serena >/dev/null 2>&1; then
        normalize_version "$(serena --version 2>&1)"
        return
    fi
    if command -v uv >/dev/null 2>&1; then
        local line
        line=$(uv tool list 2>/dev/null | grep -E '^serena-agent[[:space:]]+v?[0-9]+\.[0-9]+\.[0-9]' | head -n1)
        [ -n "$line" ] && normalize_version "$(printf '%s' "$line" | awk '{print $2}')"
    fi
}

get_serena_latest_version() {
    local json
    json=$(curl -fsSL -H "User-Agent: ai-tools-updater" "$SERENA_PYPI" 2>/dev/null) || return 0
    printf '%s' "$json" | "$JQ" -r '.info.version // empty'
}

install_or_update_serena() {
    write_section "Serena"

    ensure_uv
    if ! command -v uv >/dev/null 2>&1; then
        state_set_tool "Serena" "" "" "prerequisite-missing"
        return
    fi

    [ -d "$SERENA_BIN_DIR" ] && add_user_path "$SERENA_BIN_DIR"

    local installed latest
    installed=$(get_serena_installed_version)
    latest=$(get_serena_latest_version)

    write_info "Installed: ${installed:-not installed}"
    write_info "Available: ${latest:-unknown}"

    local was_updated=false
    if [ "$CHECK" != true ]; then
        if [ "$FORCE_REINSTALL" = true ]; then
            was_updated=true
            if ! uv tool install --force -p 3.13 "$SERENA_TOOL"; then
                write_fail "Serena reinstallation failed."
                return 1
            fi
        elif [ -z "$installed" ]; then
            was_updated=true
            if ! uv tool install -p 3.13 "$SERENA_TOOL"; then
                write_fail "Serena installation failed."
                return 1
            fi
        elif [ -n "$latest" ] && ! compare_version_text "$installed" "$latest"; then
            was_updated=true
            if ! uv tool upgrade "$SERENA_TOOL"; then
                write_fail "Serena update failed."
                return 1
            fi
        else
            write_info "Serena is already up to date."
        fi

        [ -d "$SERENA_BIN_DIR" ] && add_user_path "$SERENA_BIN_DIR"
        installed=$(get_serena_installed_version)

        local serena_config="$HOME/.serena/serena_config.yml"
        if [ ! -f "$serena_config" ] && command -v serena >/dev/null 2>&1; then
            write_info "Initializing Serena for the first time..."
            serena init || write_warn "serena init did not complete automatically."
        fi
        if [ -f "$serena_config" ]; then
            if grep -qE '^[[:space:]]*web_dashboard_open_on_launch[[:space:]]*:' "$serena_config"; then
                sed -i -E 's/^[[:space:]]*web_dashboard_open_on_launch[[:space:]]*:.*/web_dashboard_open_on_launch: false/' "$serena_config"
            else
                printf '\nweb_dashboard_open_on_launch: false\n' >> "$serena_config"
            fi
            write_info "Serena configuration updated (dashboard will not open automatically)."
        fi
    fi

    local status="not-installed"
    if [ -n "$installed" ]; then
        if [ -n "$latest" ] && compare_version_text "$installed" "$latest"; then status="up-to-date"; else status="update-available"; fi
    fi
    state_set_tool "Serena" "$installed" "$latest" "$status" "$was_updated"
}

# ===========================================================================
# Codebase Memory
# ===========================================================================

get_cbm_command() {
    if [ -x "$CBM_EXE" ]; then echo "$CBM_EXE"; return; fi
    command -v codebase-memory-mcp >/dev/null 2>&1 && echo "codebase-memory-mcp"
}

get_cbm_installed_version() {
    local cmd; cmd=$(get_cbm_command)
    [ -n "$cmd" ] || return 0
    normalize_version "$("$cmd" --version 2>&1)"
}

get_cbm_latest_version() {
    local json
    json=$(get_github_latest_release "$CBM_API_LATEST") || return 0
    printf '%s' "$json" | "$JQ" -r '.tag_name // empty' | sed 's/^v//'
}

install_cbm_official() {
    if ! curl -fsSL "$CBM_INSTALLER_URL" | bash -s -- --skip-config; then
        write_fail "Official Codebase Memory installation failed."
        return 1
    fi
}

install_or_update_codebase_memory() {
    write_section "Codebase Memory"

    local installed latest
    installed=$(get_cbm_installed_version)
    latest=$(get_cbm_latest_version)

    write_info "Installed: ${installed:-not installed}"
    write_info "Available: ${latest:-unknown}"

    local was_updated=false
    if [ "$CHECK" != true ]; then
        if [ "$FORCE_REINSTALL" = true ] || [ -z "$installed" ]; then
            was_updated=true
            install_cbm_official || return 1
        elif [ -n "$latest" ] && ! compare_version_text "$installed" "$latest"; then
            was_updated=true
            write_info "Updating Codebase Memory..."
            local updated=false cbm_cmd
            cbm_cmd=$(get_cbm_command)
            if [ -n "$cbm_cmd" ] && "$cbm_cmd" update; then
                local after; after=$(get_cbm_installed_version)
                compare_version_text "$after" "$latest" && updated=true
            fi
            if [ "$updated" != true ]; then
                write_warn "Native updater did not complete successfully -> using the official installer."
                install_cbm_official || return 1
            fi
        else
            write_info "Codebase Memory is already up to date."
        fi

        [ -d "$CBM_INSTALL_DIR" ] && add_user_path "$CBM_INSTALL_DIR"
        installed=$(get_cbm_installed_version)

        local cbm_cmd; cbm_cmd=$(get_cbm_command)
        if [ -n "$cbm_cmd" ]; then
            if "$cbm_cmd" config set auto_index true >/dev/null 2>&1; then
                write_info "Codebase Memory auto_index = true"
            else
                write_warn "Cannot enable auto_index."
            fi
        fi
    fi

    local status="not-installed"
    if [ -n "$installed" ]; then
        if [ -n "$latest" ] && compare_version_text "$installed" "$latest"; then status="up-to-date"; else status="update-available"; fi
    fi
    state_set_tool "CodebaseMemory" "$installed" "$latest" "$status" "$was_updated"
}

# ===========================================================================
# Copilot global MCP configuration
# ===========================================================================

get_copilot_mcp_targets() {
    if command -v code >/dev/null 2>&1 ||
       command -v code-insiders >/dev/null 2>&1 ||
       command -v copilot >/dev/null 2>&1 ||
       [ -f "$COPILOT_MCP_CONFIG_PATH" ]; then
        printf '%s\n' "$COPILOT_MCP_CONFIG_PATH"
    fi
}

set_mcp_servers_in_file() {
    local path="$1" selected_csv="$2"

    local config="{}"
    if [ -s "$path" ]; then
        if "$JQ" -e . "$path" >/dev/null 2>&1; then
            config=$(cat "$path")
        else
            write_warn "Cannot parse JSON/JSONC; file left unchanged: $path"
            return
        fi
    fi

    local changed=false

    case ",$selected_csv," in *,TokenOptimizer,*)
        config=$(printf '%s' "$config" | "$JQ" '.mcpServers = ((.mcpServers // {}) + {"token-optimizer": {type:"stdio", command:"npx", args:["-y","@ooples/token-optimizer-mcp@latest"]}})')
        changed=true
    ;; esac

    case ",$selected_csv," in *,Serena,*)
        config=$(printf '%s' "$config" | "$JQ" '.mcpServers = ((.mcpServers // {}) + {"serena": {type:"stdio", command:"serena", args:["start-mcp-server","--context=vscode"]}})')
        changed=true
    ;; esac

    case ",$selected_csv," in *,CodebaseMemory,*)
        config=$(printf '%s' "$config" | "$JQ" '.mcpServers = ((.mcpServers // {}) + {"codebase-memory": {type:"stdio", command:"codebase-memory-mcp", args:[]}})')
        changed=true
    ;; esac

    [ "$changed" = true ] || return

    if [ "$CHECK" = true ]; then
        write_info "MCP target detected: $path"
        return
    fi

    mkdir -p "$(dirname "$path")" || return 1

    if [ -s "$path" ]; then
        local backup="$path.backup.$(date +%Y%m%d-%H%M%S)"
        cp "$path" "$backup" || return 1
        write_info "MCP backup: $backup"
    fi

    printf '%s' "$config" | "$JQ" '.' > "$path" || return 1
    write_info "MCP configured: $path"
}

configure_copilot_mcp() {
    local selected_csv="$1"
    write_section "Copilot global MCP configuration"

    local mcp_relevant=false
    case ",$selected_csv," in *,TokenOptimizer,*|*,Serena,*|*,CodebaseMemory,*) mcp_relevant=true ;; esac
    if [ "$mcp_relevant" != true ]; then
        write_info "No MCP tools selected."
        return
    fi

    local targets; targets=$(get_copilot_mcp_targets)
    if [ -z "$targets" ]; then
        write_warn "VS Code / Copilot not detected. Configure MCP servers after installing or configuring Copilot."
        return
    fi

    local target
    while IFS= read -r target; do
        if [ -n "$target" ]; then
            set_mcp_servers_in_file "$target" "$selected_csv" || return 1
        fi
    done <<< "$targets"
}

# ===========================================================================
# Codex MCP configuration
# ===========================================================================

test_codex_mcp_server() {
    command -v codex >/dev/null 2>&1 || return 1
    codex mcp get "$1" >/dev/null 2>&1
}

add_codex_mcp_server() {
    local name="$1" command="$2"
    shift 2

    if test_codex_mcp_server "$name"; then
        write_info "Codex MCP server already configured: $name"
        return 0
    fi

    if [ "$CHECK" = true ]; then
        write_warn "Codex MCP server is missing: $name"
        return 1
    fi

    if ! codex mcp add "$name" -- "$command" "$@"; then
        write_fail "Codex MCP server configuration failed: $name"
        return 1
    fi

    if ! test_codex_mcp_server "$name"; then
        write_fail "Codex MCP server is missing after configuration: $name"
        return 1
    fi

    write_ok "Codex MCP server configured: $name"
}

set_codex_mcp_timeouts() {
    local name="$1" startup_timeout="$2" tool_timeout="$3"
    local config_path="$CODEX_HOME/config.toml"
    local section="[mcp_servers.$name]"

    if [ ! -f "$config_path" ]; then
        write_warn "Codex configuration not found: $config_path"
        return
    fi

    if ! awk -v section="$section" '$0 == section { found=1 } END { exit found ? 0 : 1 }' "$config_path"; then
        write_warn "Codex MCP section not found: $name"
        return
    fi

    local current_section
    current_section=$(awk -v section="$section" '
        $0 == section { in_section=1; next }
        in_section && /^\[/ { exit }
        in_section { print }
    ' "$config_path")
    if printf '%s\n' "$current_section" | grep -Eq "^startup_timeout_sec[[:space:]]*=[[:space:]]*$startup_timeout[[:space:]]*$" &&
       printf '%s\n' "$current_section" | grep -Eq "^tool_timeout_sec[[:space:]]*=[[:space:]]*$tool_timeout[[:space:]]*$"; then
        write_info "Codex MCP timeouts already configured: $name"
        return
    fi

    if [ "$CHECK" = true ]; then
        write_warn "Codex MCP timeouts need updating: $name"
        return
    fi

    local tmp
    tmp=$(mktemp) || { write_fail "Cannot create a temporary file for Codex."; return 1; }
    if ! awk -v section="$section" -v startup="$startup_timeout" -v tool="$tool_timeout" '
        $0 == section { in_section=1; print; next }
        in_section && /^\[/ {
            print "startup_timeout_sec = " startup
            print "tool_timeout_sec = " tool
            in_section=0
        }
        in_section && /^(startup_timeout_sec|tool_timeout_sec)[[:space:]]*=/ { next }
        { print }
        END {
            if (in_section) {
                print "startup_timeout_sec = " startup
                print "tool_timeout_sec = " tool
            }
        }
    ' "$config_path" > "$tmp"; then
        write_fail "Codex timeout update failed: $name"
        rm -f "$tmp"
        return 1
    fi

    cp "$config_path" "$config_path.backup.$(date +%Y%m%d-%H%M%S)" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$config_path"
    write_ok "Codex MCP timeouts configured: $name"
}

set_codex_instructions() {
    local selected_csv="$1"
    case ",$selected_csv," in *,TokenOptimizer,*|*,Serena,*|*,CodebaseMemory,*) : ;; *) return ;; esac

    local begin="<!-- ai-tools:begin -->"
    local end="<!-- ai-tools:end -->"
    local block
    block=$( {
        printf '%s\n' "$begin" '# Local AI tools' ''
        case ",$selected_csv," in *,TokenOptimizer,*)
            printf '%s\n' '## Token Optimizer' \
                '- Use a named optimizer tool only when it is visible in the current tool inventory.' \
                '- Prefer `smart_read`, `smart_grep`, and `smart_glob` for large or repeated reads and searches.' ''
        ;; esac
        case ",$selected_csv," in *,Serena,*)
            printf '%s\n' '## Serena' \
                '- Prefer Serena for symbol-level code navigation: classes, functions, methods, definitions, and references.' \
                '- Activate the current project with Serena before symbol-level analysis.' ''
        ;; esac
        case ",$selected_csv," in *,CodebaseMemory,*)
            printf '%s\n' '## Codebase Memory' \
                '- Prefer Codebase Memory for architecture, dependency, impact, and repository-wide semantic questions.' \
                '- Index a repository before structural exploration when no current graph is available.' ''
        ;; esac
        printf '%s\n' "$end"
    } )

    local tmp
    tmp=$(mktemp) || { write_fail "Cannot create a temporary file for Codex."; return 1; }
    if [ -f "$CODEX_AGENTS_FILE" ] && grep -qF "$begin" "$CODEX_AGENTS_FILE" && grep -qF "$end" "$CODEX_AGENTS_FILE"; then
        awk -v begin="$begin" -v end="$end" -v block="$block" '
            $0 == begin {
                if (!replaced) { print block; replaced=1 }
                in_block=1
                next
            }
            in_block {
                if ($0 == end) { in_block=0 }
                next
            }
            { print }
        ' "$CODEX_AGENTS_FILE" > "$tmp"
    elif [ -s "$CODEX_AGENTS_FILE" ]; then
        cat "$CODEX_AGENTS_FILE" > "$tmp"
        printf '\n\n%s\n' "$block" >> "$tmp"
    else
        printf '%s\n' "$block" > "$tmp"
    fi

    if [ -f "$CODEX_AGENTS_FILE" ] && cmp -s "$CODEX_AGENTS_FILE" "$tmp"; then
        write_info "Global Codex instructions are already up to date."
        rm -f "$tmp"
        return
    fi

    if [ "$CHECK" = true ]; then
        if [ -f "$CODEX_AGENTS_FILE" ]; then
            write_warn "Global Codex instructions need updating: $CODEX_AGENTS_FILE"
        else
            write_warn "Global Codex instructions are missing: $CODEX_AGENTS_FILE"
        fi
        rm -f "$tmp"
        return
    fi

    mkdir -p "$CODEX_HOME"
    if [ -f "$CODEX_AGENTS_FILE" ]; then
        cp "$CODEX_AGENTS_FILE" "$CODEX_AGENTS_FILE.backup.$(date +%Y%m%d-%H%M%S)" || { rm -f "$tmp"; return 1; }
    fi
    mv "$tmp" "$CODEX_AGENTS_FILE"
    write_ok "Global Codex instructions: $CODEX_AGENTS_FILE"
}

configure_codex_integration() {
    local selected_csv="$1"
    case ",$selected_csv," in *,TokenOptimizer,*|*,Serena,*|*,CodebaseMemory,*) : ;; *) return ;; esac

    write_section "MCP Codex"
    ensure_codex_cli_path || true
    if ! command -v codex >/dev/null 2>&1; then
        write_warn "Codex not detected. Its MCP servers can be configured after installation."
        return
    fi

    if [[ ",$selected_csv," == *,TokenOptimizer,* ]]; then
        if add_codex_mcp_server "token-optimizer" "npx" "-y" "@ooples/token-optimizer-mcp@latest"; then
            set_codex_mcp_timeouts "token-optimizer" 30 120 || return 1
        elif [ "$CHECK" != true ]; then
            return 1
        fi
    fi
    if [[ ",$selected_csv," == *,Serena,* ]] && ! add_codex_mcp_server "serena" "serena" "start-mcp-server" "--project-from-cwd" && [ "$CHECK" != true ]; then
        return 1
    fi
    if [[ ",$selected_csv," == *,CodebaseMemory,* ]] && ! add_codex_mcp_server "codebase-memory-mcp" "codebase-memory-mcp" && [ "$CHECK" != true ]; then
        return 1
    fi

    set_codex_instructions "$selected_csv"
}

# ===========================================================================
# Global Copilot instructions
# ===========================================================================

configure_copilot_instructions() {
    local selected_csv="$1"
    local needs=false
    case ",$selected_csv," in *,TokenOptimizer,*|*,Serena,*|*,CodebaseMemory,*) needs=true ;; esac
    [ "$needs" = true ] || return 0

    write_section "Copilot user instructions"

    if [ "$CHECK" = true ]; then
        if [ -f "$AI_INSTRUCTION_FILE" ]; then
            write_info "Global instructions found: $AI_INSTRUCTION_FILE"
        else
            write_warn "Global instructions are missing: $AI_INSTRUCTION_FILE"
        fi
        return
    fi

    mkdir -p "$COPILOT_INSTRUCTIONS_DIR" || return 1

    local tmp; tmp=$(mktemp) || return 1
    {
        printf -- '---\n'
        printf 'applyTo: "**"\n'
        printf 'description: "Use local AI tooling efficiently and minimize context usage"\n'
        printf -- '---\n\n'
        printf '# Local AI tools\n\n'
        printf 'Minimize unnecessary context and prefer the specialized local tools when they are relevant.\n\n'

        case ",$selected_csv," in *,TokenOptimizer,*)
            printf '## Token Optimizer\n'
            printf -- '- Prefer Token Optimizer for large or repeated reads and searches.\n'
            printf -- '- Prefer `smart_read`, `smart_grep`, `smart_glob` and `smart_diff` when they reduce context.\n'
            printf -- '- Avoid repeatedly loading complete large files.\n\n'
        ;; esac

        case ",$selected_csv," in *,Serena,*)
            printf '## Serena\n'
            printf -- '- Prefer Serena for symbol-level code navigation: classes, functions, methods, definitions and references.\n'
            printf -- '- Activate the current project with Serena when needed before symbol-level analysis.\n\n'
        ;; esac

        case ",$selected_csv," in *,CodebaseMemory,*)
            printf '## Codebase Memory\n'
            printf -- '- Prefer Codebase Memory for architecture, dependency, impact and repository-wide semantic questions.\n'
            printf -- '- If the current repository is not indexed yet and indexing is useful, index it before repository-wide analysis.\n\n'
        ;; esac
    } > "$tmp"

    if [ -f "$AI_INSTRUCTION_FILE" ] && cmp -s "$AI_INSTRUCTION_FILE" "$tmp"; then
        write_info "Global instructions are already up to date."
        rm -f "$tmp"
        return
    fi

    if [ -f "$AI_INSTRUCTION_FILE" ]; then
        cp "$AI_INSTRUCTION_FILE" "$AI_INSTRUCTION_FILE.backup.$(date +%Y%m%d-%H%M%S)" || { rm -f "$tmp"; return 1; }
    fi

    mv "$tmp" "$AI_INSTRUCTION_FILE" || { rm -f "$tmp"; return 1; }
    write_ok "Global Copilot instructions: $AI_INSTRUCTION_FILE"
}

# ===========================================================================
# UI / dashboards
# ===========================================================================

open_url() {
    local url="$1"
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 &
    else
        write_info "Open manually: $url"
    fi
}

launch_ui() {
    local which="$1"
    ensure_ai_directories

    case "$which" in
        RTK)
            if [ -x "$RTK_EXE" ]; then
                "$RTK_EXE" gain
            elif command -v rtk >/dev/null 2>&1; then
                rtk gain
            else
                write_fail "RTK is missing."
                return 1
            fi
            ;;
        TokenOptimizer)
            [ -d "$TOKEN_DASHBOARD_DIR" ] || { write_fail "Token Optimizer dashboard is missing. Run 'ai-tools' first."; exit 1; }
            command -v npm >/dev/null 2>&1 || { write_fail "npm is missing."; exit 1; }
            write_info "Dashboard Token Optimizer -> http://localhost:3100"
            open_url "http://localhost:3100"
            (cd "$TOKEN_DASHBOARD_DIR" && npm run dashboard)
            ;;
        Serena)
            command -v serena >/dev/null 2>&1 || { write_fail "Serena is missing."; exit 1; }
            write_info "Starting Serena with its dashboard..."
            serena start-mcp-server --context=vscode --open-web-dashboard true
            ;;
        CodebaseMemory)
            local cmd; cmd=$(get_cbm_command)
            [ -n "$cmd" ] || { write_fail "Codebase Memory is missing."; exit 1; }
            write_info "Graph UI -> http://localhost:9749"
            open_url "http://localhost:9749"
            "$cmd" --ui=true --port=9749
            ;;
    esac
}

# Sets DASHBOARD_UI_RESULT ("" if cancelled/unavailable).
resolve_dashboard_ui() {
    local selected_csv="$1" dashboard_arg="$2"
    DASHBOARD_UI_RESULT=""

    local keys=() labels=() uis=()
    case ",$selected_csv," in *,TokenOptimizer,*) keys+=("token"); labels+=("Token Optimizer"); uis+=("TokenOptimizer") ;; esac
    case ",$selected_csv," in *,Serena,*) keys+=("serena"); labels+=("Serena"); uis+=("Serena") ;; esac
    case ",$selected_csv," in *,CodebaseMemory,*) keys+=("graph"); labels+=("Codebase Memory Graph"); uis+=("CodebaseMemory") ;; esac
    case ",$selected_csv," in *,RTK,*) keys+=("rtk"); labels+=("RTK (gain)"); uis+=("RTK") ;; esac

    if [ ${#keys[@]} -eq 0 ]; then
        write_fail "No dashboards available. Run 'ai-tools' first to install or select a tool."
        return 1
    fi

    if [ -n "$dashboard_arg" ]; then
        local i
        for i in "${!keys[@]}"; do
            if [ "${keys[$i]}" = "$dashboard_arg" ]; then
                DASHBOARD_UI_RESULT="${uis[$i]}"
                return 0
            fi
        done
        write_fail "Dashboard '$dashboard_arg' is not managed on this machine."
        return 1
    fi

    write_section "Dashboards" always
    local i
    for i in "${!keys[@]}"; do
        echo "  [$((i + 1))] ${labels[$i]}" >&2
    done
    echo "  [Q] Quit" >&2

    local choice
    while true; do
        read -r -p "Choice [1-${#keys[@]}/Q] " choice
        choice=$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')
        if [ "$choice" = "q" ]; then return 0; fi
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#keys[@]}" ]; then
                DASHBOARD_UI_RESULT="${uis[$idx]}"
                return 0
            fi
        fi
        write_warn "Invalid choice."
    done
}

launch_dashboard() {
    local selected_csv="$1" dashboard_arg="$2"
    resolve_dashboard_ui "$selected_csv" "$dashboard_arg" || return 1
    if [ -n "$DASHBOARD_UI_RESULT" ]; then
        launch_ui "$DASHBOARD_UI_RESULT"
    else
        return 0
    fi
}

# ===========================================================================
# Summary
# ===========================================================================

show_state_summary() {
    local selected_csv="$1"
    write_section "Summary" always

    local saved_ifs="$IFS" tool
    IFS=','
    for tool in $selected_csv; do
        IFS="$saved_ifs"
        [ -n "$tool" ] || continue

        local entry
        entry=$("$JQ" -c --arg t "$tool" '.tools[$t] // empty' "$INSTALLED_STATE_PATH" 2>/dev/null)
        if [ -z "$entry" ] || [ "$entry" = "null" ]; then
            printf "  %-20s %s\n" "$tool" "not checked" >&2
            continue
        fi

        local status installed updated_from summary color
        status=$(printf '%s' "$entry" | "$JQ" -r '.status // "?"')
        installed=$(printf '%s' "$entry" | "$JQ" -r '.installed // empty')
        updated_from=$(printf '%s' "$entry" | "$JQ" -r '.updatedFrom // empty')

        if [ -n "$updated_from" ] && [ -n "$installed" ]; then
            summary="$updated_from -> $installed  updated"
        elif [ -n "$installed" ]; then
            summary="$installed  $status"
        else
            summary="$status"
        fi

        case "$status" in
            up-to-date) color="$GREEN" ;;
            update-available) color="$YELLOW" ;;
            *) color="$GRAY" ;;
        esac

        printf "${color}  %-20s %s${NC}\n" "$tool" "$summary" >&2
        IFS=','
    done
    IFS="$saved_ifs"
}

show_ui_commands() {
    local selected_csv="$1"
    local has_dashboard=false
    case ",$selected_csv," in *,RTK,*|*,TokenOptimizer,*|*,Serena,*|*,CodebaseMemory,*) has_dashboard=true ;; esac
    [ "$has_dashboard" = true ] || return

    write_section "Shortcuts" always
    {
        echo "  ai-tools                      Open the main menu"
        echo "  ai-tools --force-reinstall --all  Reinstall all tools"
        echo "  ai-tools dash                 Choose and launch a dashboard"
        echo "  ai-tools --check              Check without making changes"
        echo "  ai-tools --verbose            Show technical details"
    } >&2
}

# ===========================================================================
# MAIN
# ===========================================================================

main() {
    if [ "$CHECK" != true ] && [ -f "$MANAGED_SCRIPT_PATH" ] &&
       [ ! "${BASH_SOURCE[0]}" -ef "$MANAGED_SCRIPT_PATH" ]; then
        install_self true || return 1
        echo "No tools were installed or updated." >&2
        echo "Run 'ai-tools --all' to install or update all tools." >&2
        return 0
    fi

    if [ "$INTERACTIVE_MENU" = true ]; then
        read_main_action || return 1
        case "$MAIN_ACTION" in
            quit) return 0 ;;
            check) CHECK=true ;;
            dash) COMMAND=dash ;;
            reinstall)
                FORCE_REINSTALL=true
                select_tools_interactive Reinstall || return 1
                TOOLS="$SELECTED_TOOLS_CSV"
                if [ -z "$TOOLS" ]; then return 0; fi
                ;;
        esac
    fi
    check_dependencies || return 1
    if [ "$CHECK" != true ]; then
        install_self || return 1
    fi
    if [ -d "$BIN_DIR" ]; then add_user_path "$BIN_DIR" || return 1; fi
    if [ -d "$SERENA_BIN_DIR" ]; then add_user_path "$SERENA_BIN_DIR" || return 1; fi
    ensure_jq || return 1

    state_init || return 1

    if [ -n "$UI" ]; then
        launch_ui "$UI"
        exit $?
    fi

    if [ "$COMMAND" = "dash" ]; then
        local selected_csv; selected_csv=$(state_get_selected_tools)
        launch_dashboard "$selected_csv" "$DASHBOARD"
        exit $?
    fi

    resolve_selected_tools || return 1
    local selected_csv="$RESOLVED_TOOLS_CSV"

    if [ -z "$selected_csv" ]; then
        write_warn "No tools selected. Nothing to do."
        exit 0
    fi

    if [ "$CHECK" != true ]; then
        local managed_csv="$selected_csv"
        if [ "$FORCE_REINSTALL" = true ]; then
            managed_csv=$(printf '%s' "$(state_get_selected_tools),$selected_csv" | "$JQ" -Rr 'split(",") | map(select(length > 0)) | unique | join(",")') || return 1
        fi
        state_set_selected_tools "$managed_csv" || return 1
    fi

    write_section "AI Tools" always
    {
        echo "Tools managed on this machine: $(printf '%s' "$selected_csv" | tr ',' ' ')"
        if [ "$CHECK" = true ]; then
            echo "Mode: DIAGNOSTICS ONLY"
        elif [ "$FORCE_REINSTALL" = true ]; then
            echo "Mode: FORCED REINSTALLATION"
        else
            echo "Mode: INSTALL / UPDATE"
        fi
    } >&2

    case ",$selected_csv," in *,TokenOptimizer,*)
        ensure_node
        [ "$SKIP_DASHBOARD_BUILD" = true ] || ensure_git
    ;; esac
    case ",$selected_csv," in *,Serena,*) ensure_uv ;; esac

    case ",$selected_csv," in *,RTK,*) install_or_update_rtk || exit 1 ;; esac
    case ",$selected_csv," in *,TokenOptimizer,*) install_or_update_token_optimizer || exit 1 ;; esac
    case ",$selected_csv," in *,Serena,*) install_or_update_serena || exit 1 ;; esac
    case ",$selected_csv," in *,CodebaseMemory,*) install_or_update_codebase_memory || exit 1 ;; esac

    configure_copilot_mcp "$selected_csv" || return 1
    configure_codex_integration "$selected_csv" || exit 1
    configure_copilot_instructions "$selected_csv" || return 1

    state_save_last_run || return 1
    show_state_summary "$selected_csv"
    show_ui_commands "$selected_csv"

    if [ "$CHECK" != true ]; then
        write_warn "After the first installation, open a new terminal (or source ~/.bashrc / ~/.profile) to pick up PATH changes."
        write_ok "Installation / update completed."
    else
        write_ok "Diagnostics completed. No updates were applied."
    fi
}

parse_args "$@"
validate_args
main
