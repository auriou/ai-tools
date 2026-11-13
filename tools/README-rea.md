# REA (Reverse Engineer Anything) for Codex and Copilot

[REA](https://github.com/morluto/rea) is an optional reverse-engineering MCP server. The main `ai-tools` manager supports Linux and Windows and includes REA as its fifth selectable tool. The standalone helper below is Linux-only. Neither integration modifies Android projects.

## User-level setup

From the root of this repository, on Parrot OS or another Linux distribution:

```bash
bash tools/rea.sh install
```

REA is installed using npm into `~/.ai-tools/npm`, **without sudo** and without modifying the repository's dependencies or the user's npm global prefix. The official `rea setup` wizard will ask for approval before registering the MCP server in the **user-level Codex configuration** (normally `~/.codex/config.toml`). Codex CLI and the Codex VS Code extension share that configuration.

To configure **Copilot SDK** (including its chat inside VS Code Insiders) and the separate **VS Code MCP integration** as well:

```bash
bash tools/rea.sh install --vscode
```

The helper's `--vscode` flag runs official setup for both `copilot_cli` and `vscode`: installing the skill or configuring Codex alone does not connect REA to Copilot SDK. The `vscode` client may target the stable VS Code profile; it does not establish a connection in Insiders. Verify REA in the active chat's MCP server list after restarting. Review setup changes before approving, especially if REA was previously registered through an npm cache or another installation.

The main manager (`ai-tools --tools=REA` on Linux or `ai-tools -Tools REA` on Windows) automatically registers REA in the detected portable Copilot user configuration (`$COPILOT_HOME/mcp-config.json`, defaulting to `~/.copilot/mcp-config.json`). It uses the stable executable in the dedicated npm prefix and preserves unrelated server entries. Version 1.1.3 also repairs registrations when the package is already current. Legacy VS Code profile configurations are not modified by the main manager.

## Update and diagnostics

```bash
bash tools/rea.sh update
bash tools/rea.sh check
```

Append `--vscode` to update/check the optional Copilot SDK and VS Code integrations. The helper checks every selected client even when one diagnostic fails and returns a failure if any selected client fails. The update command refreshes the global package within the same user prefix and reruns official setup to keep registrations aligned. Both setup and updates can change user-level MCP configuration, but do not modify project files. Check mode only inspects the installation.

To run `rea` directly, add this directory to your shell PATH:

```bash
export PATH="$HOME/.ai-tools/npm/bin:$PATH"
```

You can add that line to `~/.bashrc` or `~/.zshrc` if desired. The script itself does not modify shell startup files.

## Requirements and limitations

- Supported Node.js releases: 22.23.4+, 24.22.1+, or 26.12.1+ within those major versions; npm.
- APK analysis capabilities also depend on an installed JDK and JADX; ADB and Apktool are optional for additional device/resource workflows.
- The script reports missing Android dependencies but does **not** install them.
- Restart Codex / VS Code Insiders after setup.
- If registration fails, use `bash tools/rea.sh check` and inspect the official [REA installation guide](https://github.com/morluto/rea/blob/main/docs/installation.md).
- This integration does not automatically uninstall REA or remove its MCP registrations. Use the official `rea uninstall` workflow after reviewing what it will remove.
- Only analyze applications you own or are authorized to inspect.

Existing saved selections are preserved; choose REA explicitly or use `--all` / `-All` to include it. MCP registration verifies configuration, not the live chat connection or availability of every analysis engine.
