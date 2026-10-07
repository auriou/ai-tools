# ai-tools

Scripts to install, update, and diagnose token optimization tools for AI coding assistants on Windows and Linux.

Manage your local tools from one command, with interactive selection, version checks, MCP configuration, and dashboard shortcuts.

## Managed tools

| Tool | Purpose | Installation source |
| --- | --- | --- |
| [RTK](https://github.com/rtk-ai/rtk) | Reduce verbose terminal output before it reaches an AI assistant. | GitHub releases |
| [Token Optimizer](https://github.com/ooples/token-optimizer-mcp) | Reduce context from file reads and searches using optimized MCP tools and caching. | npm; dashboard built from its matching Git tag |
| [Serena](https://github.com/oraios/serena) | Navigate code through symbols, definitions, and references instead of reading entire files. | `serena-agent` via uv |
| [Codebase Memory](https://github.com/DeusData/codebase-memory-mcp) | Explore repository architecture and relationships through a code graph. | Official installer and native updater |

These tools address different sources of unnecessary context. Actual token savings depend on your assistant, workflow, and whether it uses the installed tools.

## Requirements

- **Windows:** Windows x64, Windows PowerShell 5.1 or later, and an internet connection. WinGet is required to install missing Git, Node.js LTS, or uv automatically.
- **Linux:** Bash on x86_64 or ARM64, an internet connection, `curl`, `tar`, `sha256sum`, and standard Linux utilities. Extracting portable Node.js also requires support for `.tar.xz` archives. Git is needed to build/update the Token Optimizer dashboard.
- **Integrations:** VS Code, VS Code Insiders, and Codex are detected when installed; the scripts do not install these applications. RTK integration is also initialized for detected Claude installations.

On Linux, missing jq, Node.js, and uv can be installed into user-owned directories without `sudo`. Git and missing system utilities must be installed separately with your distribution's package manager. Existing Node.js installations must allow global npm package installation for Token Optimizer.

## Quick start

Review the scripts before running them. They download third-party packages and installers and can modify user-level PATH, MCP configuration, and assistant instructions.

### Windows

Download the PowerShell script and run it from a PowerShell terminal:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/auriou/ai-tools/main/ai-tools.ps1" -OutFile ai-tools.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ai-tools.ps1
```

`ExecutionPolicy Bypass` applies only to that PowerShell process; it does not change your machine's execution policy.

### Linux

Download and run the Bash script:

```bash
curl -fsSL https://raw.githubusercontent.com/auriou/ai-tools/main/ai-tools.sh -o ai-tools.sh
bash ./ai-tools.sh
```

### From a clone

```bash
git clone https://github.com/auriou/ai-tools.git
cd ai-tools
```

Then run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ai-tools.ps1` on Windows or `bash ./ai-tools.sh` on Linux.

On the first installation, choose all tools or select them individually. The script installs a reusable `ai-tools` command and saves your selection. Later runs of the installed command reuse it and update tools whose versions differ from the available release.

After installation, open a new terminal. On Windows, fully restart VS Code, VS Code Insiders, and Codex so they pick up PATH changes.

## Updating the manager script

Download the latest platform script, or pull this repository, then execute that file from any location, including Downloads. You do not need to copy it manually or change your terminal's working directory.

If a manager script is already installed, running another copy replaces only the installed script and exits before the menu, prerequisite checks, or tool updates. The destination is `%USERPROFILE%\.ai-tools\bin\ai-tools.ps1` on Windows or `~/.ai-tools/bin/ai-tools` on Linux. Detection uses the script's full path on Windows and file identity on Linux, not just its name.

The script reports the update and recommends running the installed command afterward:

```powershell
ai-tools -All
```

```bash
ai-tools --all
```

This script-only update leaves PATH, saved tool selection, state, and MCP configuration unchanged. Even if you pass `-All` or `--all` to the external copy, it only updates the manager when an installed copy exists. Run the installed command to update tools; the all-tools option also installs any missing managed tools.

If no installed copy exists, the normal first-installation workflow runs instead. Running the installed copy retains its normal behavior. Diagnostic mode (`-Check` / `--check`) never copies the script, and Bash `--help` only displays help.

## Usage

Run `ai-tools` without arguments to open the main menu: install/update, force reinstallation, dashboards, or diagnostics.

| Action | Windows | Linux |
| --- | --- | --- |
| Install/update all tools | `ai-tools -All` | `ai-tools --all` |
| Install/update selected tools | `ai-tools -Tools RTK,Serena` | `ai-tools --tools=RTK,Serena` |
| Change the saved selection | `ai-tools -ChooseTools` | `ai-tools --choose-tools` |
| Check without persistent changes | `ai-tools -Check` | `ai-tools --check` |
| Show technical details during updates | `ai-tools -Verbose` | `ai-tools --verbose` |
| Reinstall all tools | `ai-tools -ForceReinstall -All` | `ai-tools --force-reinstall --all` |
| Reinstall selected tools | `ai-tools -ForceReinstall -Tools Serena` | `ai-tools --force-reinstall --tools=Serena` |
| Skip the Token Optimizer dashboard build | `ai-tools -All -SkipDashboardBuild` | `ai-tools --all --skip-dashboard-build` |
| Do not install missing prerequisites | `ai-tools -All -SkipPrerequisiteInstall` | `ai-tools --all --skip-prerequisite-install` |

Valid tool identifiers are `RTK`, `TokenOptimizer`, `Serena`, and `CodebaseMemory`. Reinstalling a subset retains the other tools in the saved selection. Changing the selection does not uninstall deselected tools or remove their existing integrations.

On Linux, `--skip-prerequisite-install` skips automatic Node.js and uv installation, but does not skip the portable jq bootstrap.

Diagnostics query installed tools and online version sources, but do not install/update tools or persist configuration/state changes. On Linux, jq must already be available for diagnostics. Diagnostic mode cannot be combined with force reinstallation or dashboard launch.

To see script help before installing:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Help .\ai-tools.ps1 -Detailed"
```

```bash
bash ./ai-tools.sh --help
```

## Dashboards

The same shortcuts work on both platforms:

```text
ai-tools dash
ai-tools dash token
ai-tools dash serena
ai-tools dash graph
ai-tools dash rtk
```

`dash` opens a chooser for the saved selection. `token` launches the Token Optimizer dashboard at `http://localhost:3100`; `serena` starts Serena with its web dashboard; `graph` launches the Codebase Memory Graph UI at `http://localhost:9749`. `rtk` prints token savings using `rtk gain` rather than opening a web UI.

Direct UI launch is also available with `ai-tools -UI TokenOptimizer` on Windows or `ai-tools --ui=TokenOptimizer` on Linux. Dashboard processes run in the current terminal; use `Ctrl+C` to stop them.

## Files and integrations

The manager stores its files under `~/.ai-tools` (`%USERPROFILE%\.ai-tools` on Windows):

| Path | Contents |
| --- | --- |
| `bin/` | Installed manager command, RTK, and portable jq on Linux when needed |
| `state/installed.json` | Selected tools, version checks, and update history |
| `apps/` | Token Optimizer dashboard and portable Node.js on Linux when needed |
| `logs/` | Reserved log directory |

Other tools retain their own installation locations: Token Optimizer uses global npm packages, Serena uses uv, and Codebase Memory uses its official installer. The state file is a record, not the source of truth: actual installed versions are checked on each run.

For selected MCP tools, the scripts configure detected VS Code and VS Code Insiders user profiles. Managed server entries are added or replaced; unrelated entries are retained. Existing MCP files are backed up before writing. JSONC files that cannot be parsed are left unchanged with a warning.

When Codex is available, missing MCP servers are added through its CLI, Token Optimizer timeouts are configured, and a managed instruction block is added to its global `AGENTS.md`. Codex paths respect `CODEX_HOME`, defaulting to `~/.codex`. Existing Codex servers are not replaced merely because their command differs.

Copilot guidance is written to `~/.copilot/instructions/ai-tools.instructions.md`, with a backup when replacing an existing file. Serena is configured not to open its dashboard automatically, and Codebase Memory automatic indexing is enabled. RTK initializes client-specific global integration for detected Claude, Copilot, and Codex installations.

Windows uses the user PATH. Linux adds PATH entries to existing `~/.bashrc` and `~/.zshrc` files and to `~/.profile`.

## Troubleshooting

- **`ai-tools` is not found:** open a new terminal. On Linux, source your shell startup file if necessary. On Windows, restart applications that were already running.
- **A prerequisite is missing:** install it manually or rerun without the prerequisite-skip option. For WinGet, install Microsoft's App Installer if needed.
- **An MCP configuration is skipped:** check the warning and the JSON syntax. Comments or trailing commas in JSONC may prevent parsing.
- **A dashboard is unavailable:** install/select its tool first. For Token Optimizer, do not skip the dashboard build, and ensure Git is available. Local dashboard changes are preserved rather than overwritten by a Git update.
- **More detail is needed:** use `ai-tools -Check -Verbose` on Windows or `ai-tools --check --verbose` on Linux for diagnostics without persistent changes.