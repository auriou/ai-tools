# ai-tools

Installer version: **1.1.4**.

Scripts to install, update, and diagnose token optimization tools for AI coding assistants on Windows and Linux.

Manage your local tools from one command, with interactive selection, version checks, MCP configuration, and dashboard shortcuts.

## Managed tools

| Tool | Purpose | Installation source |
| --- | --- | --- |
| [RTK](https://github.com/rtk-ai/rtk) | Reduce verbose terminal output before it reaches an AI assistant. | GitHub releases |
| [Token Optimizer](https://github.com/ooples/token-optimizer-mcp) | Reduce context from file reads and searches using optimized MCP tools and caching. | npm; dashboard built from its matching Git tag |
| [Serena](https://github.com/oraios/serena) | Navigate code through symbols, definitions, and references instead of reading entire files. | `serena-agent` via uv |
| [Codebase Memory](https://github.com/DeusData/codebase-memory-mcp) | Explore repository architecture and relationships through a code graph. | Official installer and native updater |
| [REA](https://github.com/morluto/rea) | Analyze Android APKs and binaries via Codex MCP. | Isolated user-level npm installation |

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

## Running a downloaded manager script

The Windows and Linux scripts contain a shared manager version (currently `1.1.4`). When executed from Downloads or another path outside the installed manager, they compare this version with the user's installed copy **before** changing anything:

| Installed manager | Behavior |
| --- | --- |
| Not installed | Ask permission to install the manager, then offer tool selection and installation. |
| Same version | Ask whether to force-reinstall selected tools. Explicit command-line options are passed to the installed manager. |
| Older / legacy version | Ask permission to update the manager, back up the previous script, then offer the current tool list and update selected tools. |
| Newer than the downloaded copy | Refuse to downgrade; leave everything unchanged. |

If you decline, no installation or update is performed. Existing selected tools remain in the state file. Confirming the same-version prompt starts the installed manager in force-reinstall mode and lets you choose tools. Explicit command-line options are forwarded unchanged. When proceeding with a new or updated manager without explicit command-line options, the selection menu includes newly supported tools such as REA; the selected tools are installed or updated afterward.

For normal **tool-only updates** when the manager version is already current, run the installed command (`ai-tools`, `ai-tools --all` or `ai-tools -All`), not the downloaded script.

The installed manager script lives at `%USERPROFILE%\.ai-tools\bin\ai-tools.ps1` on Windows or `~/.ai-tools/bin/ai-tools` on Linux. The old script is backed up alongside it before any manager upgrade.


## Usage

Run `ai-tools` without arguments to open the main menu: install/update, force reinstallation, dashboards, diagnostics, or uninstall tools.

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

Valid tool identifiers are `RTK`, `TokenOptimizer`, `Serena`, `CodebaseMemory`, and `REA`. Reinstalling a subset retains the other tools in the saved selection. Changing the selection does not uninstall deselected tools or remove their existing integrations.

Choose **Uninstall tools** in the main menu to remove all tools or select them individually. A confirmation is required; successfully removed tools are also removed from the saved selection. Failed removals stay selected. RTK and Codebase Memory are removed only from their managed executable paths; Token Optimizer and Serena are removed using the `npm` and `uv` available on PATH. REA is uninstalled from its isolated npm prefix; its MCP registration is retained for explicit removal using REA’s official uninstall workflow. The manager, prerequisites, dashboards, tool data, PATH entries, and assistant configuration are retained. Remove unwanted MCP entries manually: an existing `npx` entry can download Token Optimizer again. Other copies of executables outside the managed paths are not removed.

Installation state (selection, versions, and last successful run) is saved only after all selected tools and integrations complete successfully. A failed installation exits with an error and can be retried with the installed command, including the force-reinstall options above; an installed package version does not prevent retrying a failed dashboard build. The Token Optimizer dashboard records its Git commit only after both `npm ci` and `npm run build` succeed. Missing build records (including older installations) trigger a rebuild on the next update. Explicitly skipping the dashboard build remains supported.

On Linux, `--skip-prerequisite-install` skips automatic Node.js, uv, and compatible Python installation, but does not skip the portable jq bootstrap.

Diagnostics query installed tools and online version sources, but do not install/update tools or persist configuration/state changes. On Linux, jq must already be available for diagnostics. Diagnostic mode cannot be combined with force reinstallation or dashboard launch.

### Automatic prerequisite checks

Before installing or updating any selected tool, the manager resolves the target versions once and checks:

- **Token Optimizer:** Node/npm requirements from the published npm metadata, plus dependency engine requirements using npm's strict, script-free dry run. Unless the dashboard is skipped, a second dry run checks the matching Git tag's lockfile, including development dependencies.
- **Serena:** the target release's `requires_python` from PyPI. uv finds a compatible interpreter, or installs one if prerequisite installation is allowed. Python 3.13 is no longer hardcoded.
- **RTK / Codebase Memory:** availability of a release archive for the OS and architecture. Linux uses musl RTK archives and portable Codebase Memory archives.

The preflight begins by displaying the prerequisites for all selected tools, their published version ranges, and installation/update commands for the current platform. This includes Node.js/npm, Git when building the dashboard, and uv/Python for Serena. This list describes requirements, not a claim that every prerequisite is missing: already compatible prerequisites do not need reinstalling. The suggested latest LTS commands are only appropriate when that release satisfies the displayed Node.js range. After a manual installation or update, reopen the terminal and retry the same command.

An incompatible existing Node/npm installation stops the run with required and detected versions; update it and retry. Force reinstallation does not bypass these checks. Missing prerequisites may still be bootstrapped before the checks finish, but no selected tool is installed until all checks pass. npm and uv may populate their caches.

Installations use the checked target versions, not a second `latest` lookup. Codebase Memory updates use its version-specific official installer instead of the native updater, so a newer release appearing during the run cannot change the target.

These checks do not compile native dependencies or execute installation scripts. Missing compilers, system libraries, and other undeclared runtime requirements can still cause an installation to fail; failed runs never confirm successful installation state. Diagnostic mode retains its version-reporting behavior and does not run installation simulations.

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
| `state/token-optimizer-dashboard-build.txt` | Git commit of the last successful dashboard build |
| `apps/` | Token Optimizer dashboard and portable Node.js on Linux when needed |
| `logs/` | Reserved log directory |

Other tools retain their own installation locations: Token Optimizer uses global npm packages, Serena uses uv, Codebase Memory uses its official installer, and REA is installed to `~/.ai-tools/npm` (Linux) or `%USERPROFILE%\.ai-tools\npm` (Windows) with a dedicated npm prefix. The state file is a record, not the source of truth: actual installed versions are checked on each run.

For selected MCP tools, the scripts configure the portable Copilot user MCP file at `$COPILOT_HOME/mcp-config.json`, or `~/.copilot/mcp-config.json` when `COPILOT_HOME` is not set. Managed server entries are added or replaced under `mcpServers`; unrelated entries are retained. The file is backed up before writing, and files that cannot be parsed are left unchanged with a warning. The portable file is shared across Copilot profiles and compatible Copilot tools. Legacy per-profile VS Code `mcp.json` files are not modified; use VS Code's **Migrate** action to move existing servers, or the same server may remain configured in both locations.

When Codex is available, missing MCP servers are added through its CLI, Token Optimizer timeouts are configured, and a managed instruction block is added to its global `AGENTS.md`. Codex paths respect `CODEX_HOME`, defaulting to `~/.codex`. Existing Codex servers are not replaced merely because their command differs.

On Linux, the manager also detects the CLI bundled with the Codex desktop application or the Codex VS Code / VS Code Insiders extension when `codex` is not on PATH. Bundled CLI directories are used only for the current process, since extension updates may replace them.

Copilot guidance is written to `~/.copilot/instructions/ai-tools.instructions.md`, with a backup when replacing an existing file. Serena is configured not to open its dashboard automatically, and Codebase Memory automatic indexing is enabled. RTK initializes client-specific global integration for detected Claude, Copilot, and Codex installations.

Windows uses the user PATH. Linux adds PATH entries to existing `~/.bashrc` and `~/.zshrc` files and to `~/.profile`.

When one tool download fails (for example an HTTP 503 from the RTK release server), the manager retries that download and continues processing other selected tools. Failed tools are reported at the end; rerun the installed manager to retry them.

## Troubleshooting

- **`ai-tools` is not found:** open a new terminal. On Linux, source your shell startup file if necessary. On Windows, restart applications that were already running.
- **Codebase Memory rejects `~/.local/bin` permissions on Linux:** review the directory's permissions, then run `chmod go-w "$HOME/.local/bin"` and retry with `"$HOME/.ai-tools/bin/ai-tools" --all` to finish installation and configuration.
- **A prerequisite is missing:** install it manually or rerun without the prerequisite-skip option. For WinGet, install Microsoft's App Installer if needed.
- **An MCP configuration is skipped:** check the warning and the JSON syntax. Comments or trailing commas in JSONC may prevent parsing.
- **A dashboard is unavailable:** install/select its tool first. For Token Optimizer, do not skip the dashboard build, and ensure Git is available. Local dashboard changes are preserved rather than overwritten by a Git update.
- **More detail is needed:** use `ai-tools -Check -Verbose` on Windows or `ai-tools --check --verbose` on Linux for diagnostics without persistent changes.
## REA integration (Linux and Windows)

REA is the fifth selectable tool. Install/update it from the main menu, or use `ai-tools --tools=REA` on Linux and `ai-tools -Tools REA` on Windows. It is managed independently of the other tools and installed to a user-owned npm prefix without `sudo` or changes to the normal global npm prefix. The official REA setup wizard registers the MCP server for Codex; this is shared with the Codex VS Code/Insiders extension. REA is also registered automatically in the portable Copilot SDK user MCP configuration when VS Code, VS Code Insiders, Copilot CLI, or that configuration file is detected. Starting with manager version 1.1.3, rerunning installation/update repairs registrations even when the REA package is already current; diagnostics report missing or stale portable Copilot REA entries without writing configuration. This does not modify legacy VS Code profile `mcp.json` files or install native analysis engines. See [REA setup instructions](tools/README-rea.md).

The standalone Linux helper `bash tools/rea.sh install|update|check [--vscode]` remains available. Existing saved selections are preserved; run `--choose-tools` or `-ChooseTools` to opt into REA. `--all`/`-All` includes it.
