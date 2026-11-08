# REA (Reverse Engineer Anything) for Codex

[REA](https://github.com/morluto/rea) is an optional Android APK reverse-engineering MCP server. This integration is **Linux-only** for now. It does not modify Android projects or the existing four-tool `ai-tools` selection.

## User-level setup

From the root of this repository, on Parrot OS or another Linux distribution:

```bash
bash tools/rea.sh install
```

REA is installed using npm into `~/.ai-tools/npm`, **without sudo** and without modifying the repository's dependencies or the user's npm global prefix. The official `rea setup` wizard will ask for approval before registering the MCP server in the **user-level Codex configuration** (normally `~/.codex/config.toml`). Codex CLI and the Codex VS Code extension share that configuration.

To configure the separate **VS Code MCP integration** as well (useful for GitHub Copilot Agent mode):

```bash
bash tools/rea.sh install --vscode
```

The `--vscode` flag is **not required** if you only use Codex within VS Code / Insiders. Review setup changes before approving, especially if REA was previously registered through an npm cache or another installation.

## Update and diagnostics

```bash
bash tools/rea.sh update
bash tools/rea.sh check
```

Append `--vscode` to update/check the optional VS Code integration. The update command refreshes the global package within the same user prefix and reruns official setup to keep registrations aligned. Both setup and updates can change user-level MCP configuration, but do not modify project files. Check mode only inspects the installation.

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

This is a standalone optional integration: the existing `ai-tools --all`, saved selection, and Windows PowerShell manager are unchanged.
