#Requires -Version 5.1

<#
.SYNOPSIS
    Install, update, and diagnose local AI tools on Windows.

    Managed tools:
    - RTK
    - Token Optimizer MCP + dashboard
    - Serena + dashboard
    - Codebase Memory MCP + Graph UI

    The script installs itself in:
    %USERPROFILE%\.ai-tools\bin\ai-tools.ps1

    and adds only:
    %USERPROFILE%\.ai-tools\bin
    to the user PATH.

.DESCRIPTION
    FIRST RUN
        - explains the purpose of each tool;
        - offers "Install all" or individual tool selection;
        - saves the selection in ~/.ai-tools/state/installed.json.

    SUBSEQUENT RUNS
        - reuses the saved selection;
        - checks installed and available versions;
        - updates only what needs updating;
        - checks/repairs MCP configuration for VS Code / VS Code Insiders / Codex;
        - updates the state file.

    RUNNING A DOWNLOADED COPY
        - if the manager is already installed, an external copy updates only
            the installed script and exits without changing tools or configuration;
        - run 'ai-tools -All' afterward to install or update all tools;
        - diagnostic mode never copies the script.

    MAIN PARAMETERS
    .\ai-tools.ps1
        Shows the menu: updates, reinstallation, dashboards, or diagnostics.

    .\ai-tools.ps1 -ForceReinstall -All
        Reinstalls all tools, even if they are up to date.

    .\ai-tools.ps1 -ForceReinstall -Tools Serena,TokenOptimizer
        Reinstalls only the specified tools.

    .\ai-tools.ps1 -check
        Diagnostics only; no installation or updates.

    .\ai-tools.ps1 -verbose
        Shows versions, prerequisites, paths, and technical commands.

    .\ai-tools.ps1 -ChooseTools
        Reopens managed tool selection.

    .\ai-tools.ps1 -All
        Selects all four tools without prompting.

    .\ai-tools.ps1 -Tools RTK,TokenOptimizer,Serena,CodebaseMemory
        Explicit selection, useful for automation.

    .\ai-tools.ps1 dash
        Shows managed tool dashboards and asks which one to launch.

    .\ai-tools.ps1 dash token
    .\ai-tools.ps1 dash serena
    .\ai-tools.ps1 dash graph
        Launches the requested dashboard directly.

    .\ai-tools.ps1 dash rtk
        Shows RTK savings with 'rtk gain'.

    .\ai-tools.ps1 -UI TokenOptimizer
    .\ai-tools.ps1 -UI Serena
    .\ai-tools.ps1 -UI CodebaseMemory
        Launches the requested interface (automation compatibility).

.NOTES
    - RTK uses the latest GitHub Windows x64 release.
    - Token Optimizer is managed through npm.
    - Serena is managed through uv.
    - Codebase Memory uses its native installer/updater.
    - installed.json is a state log, NOT the source of truth:
        every run also checks actual binaries / package managers.
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$ChooseTools,
    [switch]$All,
    [switch]$ForceReinstall,

    [ValidateSet("RTK","TokenOptimizer","Serena","CodebaseMemory")]
    [string[]]$Tools,

    [ValidateSet("RTK","TokenOptimizer","Serena","CodebaseMemory")]
    [string]$UI,

    [Parameter(Position=0)]
    [ValidateSet("dash")]
    [string]$Command,

    [Parameter(Position=1)]
    [ValidateSet("token","serena","graph","rtk")]
    [string]$Dashboard,

    [switch]$SkipDashboardBuild,
    [switch]$SkipPrerequisiteInstall
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ===========================================================================
# Managed locations
# ===========================================================================

$AiRoot     = Join-Path $env:USERPROFILE ".ai-tools"
$BinDir     = Join-Path $AiRoot "bin"
$StateDir   = Join-Path $AiRoot "state"
$AppsDir    = Join-Path $AiRoot "apps"
$LogsDir    = Join-Path $AiRoot "logs"

$InstalledStatePath = Join-Path $StateDir "installed.json"
$ManagedScriptPath  = Join-Path $BinDir "ai-tools.ps1"

# RTK
$RtkOwner      = "rtk-ai"
$RtkRepo       = "rtk"
$RtkAssetName  = "rtk-x86_64-pc-windows-msvc.zip"
$RtkExe        = Join-Path $BinDir "rtk.exe"
$RtkApiLatest  = "https://api.github.com/repos/$RtkOwner/$RtkRepo/releases/latest"

# Token Optimizer
$TokenPackage       = "@ooples/token-optimizer-mcp"
$TokenDashboardRepo = "https://github.com/ooples/token-optimizer-mcp.git"
$TokenDashboardDir  = Join-Path $AppsDir "token-optimizer-dashboard"

# Serena
$SerenaTool   = "serena-agent"
$SerenaBinDir = Join-Path $env:USERPROFILE ".local\bin"
$SerenaPypi   = "https://pypi.org/pypi/serena-agent/json"

# Codebase Memory
$CbmInstallDir   = Join-Path $env:LOCALAPPDATA "Programs\codebase-memory-mcp"
$CbmExe          = Join-Path $CbmInstallDir "codebase-memory-mcp.exe"
$CbmInstallerUrl = "https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1"
$CbmApiLatest    = "https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/latest"

# Copilot global user instructions
$CopilotInstructionsDir = Join-Path $env:USERPROFILE ".copilot\instructions"
$AiInstructionFile      = Join-Path $CopilotInstructionsDir "ai-tools.instructions.md"
$CopilotHome             = if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) { $env:COPILOT_HOME } else { Join-Path $env:USERPROFILE ".copilot" }
$CopilotMcpConfigPath    = Join-Path $CopilotHome "mcp-config.json"

# Codex global user instructions
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$CodexAgentsFile = Join-Path $CodexHome "AGENTS.md"

$AllToolNames = @("RTK","TokenOptimizer","Serena","CodebaseMemory")

# ===========================================================================
# Output
# ===========================================================================

function Write-Section([string]$Text,[switch]$Always) {
    if (-not $Always -and $VerbosePreference -ne "Continue") { return }
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor DarkGray
}
function Write-OK([string]$Text)    { Write-Host "[OK]   $Text" -ForegroundColor Green }
function Write-Info([string]$Text)  {
    if ($VerbosePreference -eq "Continue") {
        Write-Host "[INFO] $Text" -ForegroundColor Cyan
    }
}
function Write-Warn2([string]$Text) { Write-Host "[WARN] $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text)  { Write-Host "[ERR]  $Text" -ForegroundColor Red }

function Show-ToolDescriptions {
    Write-Section "Available AI tools"

    Write-Host "1. RTK" -ForegroundColor Yellow
    Write-Host "   Purpose: reduce terminal output before it reaches the model."
    Write-Host "   Useful for: git, tests, logs, Docker, kubectl, and other verbose commands."
    Write-Host "   In short: 'show less'."
    Write-Host ""

    Write-Host "2. Token Optimizer" -ForegroundColor Yellow
    Write-Host "   Purpose: reduce the context returned by file reads and searches."
    Write-Host "   Useful for: smart_read, smart_grep, smart_glob, smart_diff, caching, reports."
    Write-Host "   In short: 'read less'."
    Write-Host ""

    Write-Host "3. Serena" -ForegroundColor Yellow
    Write-Host "   Purpose: navigate code by symbols instead of reading entire files."
    Write-Host "   Useful for: classes, functions, methods, definitions, and references."
    Write-Host "   In short: 'go straight to the right symbol'."
    Write-Host ""

    Write-Host "4. Codebase Memory" -ForegroundColor Yellow
    Write-Host "   Purpose: build structured memory of the repository and its relationships."
    Write-Host "   Useful for: architecture, dependencies, calls, impact, and semantic search."
    Write-Host "   Includes a local Graph UI."
    Write-Host "   In short: 'understand the whole repository'."
    Write-Host ""

    Write-Host "How they work together:" -ForegroundColor White
    Write-Host "   RTK -> terminal | Token Optimizer -> context | Serena -> symbols | Codebase Memory -> architecture"
}

# ===========================================================================
# Directories / PATH / helpers
# ===========================================================================

function Ensure-AiDirectories {
    foreach ($d in @($AiRoot,$BinDir,$StateDir,$AppsDir,$LogsDir)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

function Refresh-ProcessPath {
    $machine = [Environment]::GetEnvironmentVariable("Path","Machine")
    $user    = [Environment]::GetEnvironmentVariable("Path","User")
    $env:Path = "$machine;$user"
}

function Add-UserPath([string]$PathToAdd) {
    if ([string]::IsNullOrWhiteSpace($PathToAdd)) { return }
    if (-not (Test-Path $PathToAdd)) {
        Write-Warn2 "PATH not updated because the directory does not exist: $PathToAdd"
        return
    }

    if ($Check) {
        $env:Path = "$PathToAdd;$env:Path"
        return
    }

    $current = [Environment]::GetEnvironmentVariable("Path","User")
    $entries = @()
    if ($current) {
        $entries = $current -split ";" | Where-Object { $_ -and $_.Trim() }
    }

    $target = $PathToAdd.Trim().TrimEnd("\")
    $exists = $false
    foreach ($entry in $entries) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd("\")
        if ($expanded -ieq $target) {
            $exists = $true
            break
        }
    }

    if (-not $exists) {
        $newValue = (($entries + $PathToAdd) -join ";")
        [Environment]::SetEnvironmentVariable("Path",$newValue,"User")
        Write-OK "Added to the user PATH: $PathToAdd"
    } else {
        Write-Info "Already in the user PATH: $PathToAdd"
    }

    Refresh-ProcessPath
}

function Ensure-CodexCliPath {
    # The Codex Windows app installs its CLI in a versioned subdirectory of
    # %LOCALAPPDATA%\OpenAI\Codex\bin. Discover it instead of hardcoding
    # a directory that changes with each update.
    $codexBinRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
    if (-not (Test-Path $codexBinRoot)) { return $false }

    $codexExe = Get-ChildItem -LiteralPath $codexBinRoot -Recurse -Filter "codex.exe" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $codexExe) { return $false }

    if ($Check) {
        # Diagnostics must not modify the user PATH.
        $env:Path = "$($codexExe.DirectoryName);$env:Path"
    } else {
        Add-UserPath $codexExe.DirectoryName
    }
    Write-Info "Codex CLI detected: $($codexExe.FullName)"
    return $true
}

function Test-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-External {
    param(
        [Parameter(Mandatory=$true)][string]$Command,
        [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
    )
    Write-Host "       > $Command $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

function Normalize-Version([string]$Version) {
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    $m = [regex]::Match($Version, 'v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z\.-]+)?)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $Version.Trim().TrimStart("v")
}

function Compare-VersionText([string]$A,[string]$B) {
    $na = Normalize-Version $A
    $nb = Normalize-Version $B
    if (-not $na -or -not $nb) { return $false }
    return ($na -eq $nb)
}

function Get-GitHubLatestRelease([string]$Url,[string]$UserAgent = "ai-tools-updater") {
    $headers = @{
        "User-Agent" = $UserAgent
        "Accept"     = "application/vnd.github+json"
    }
    return Invoke-RestMethod -Uri $Url -Headers $headers
}

# ===========================================================================
# Persistent state
# ===========================================================================

function New-DefaultState {
    return @{
        schemaVersion  = 1
        selectedTools  = @()
        lastRun        = $null
        tools          = @{}
    }
}

function Load-State {
    if (-not (Test-Path $InstalledStatePath)) {
        return New-DefaultState
    }

    try {
        $raw = Get-Content $InstalledStatePath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return New-DefaultState }
        $obj = $raw | ConvertFrom-Json

        $state = New-DefaultState
        if ($obj.schemaVersion) { $state.schemaVersion = [int]$obj.schemaVersion }
        if ($obj.selectedTools) { $state.selectedTools = @($obj.selectedTools) }
        if ($obj.lastRun)       { $state.lastRun = [string]$obj.lastRun }

        if ($obj.tools) {
            foreach ($p in $obj.tools.PSObject.Properties) {
                $entry = @{}
                foreach ($ep in $p.Value.PSObject.Properties) {
                    $entry[$ep.Name] = $ep.Value
                }
                $state.tools[$p.Name] = $entry
            }
        }
        return $state
    } catch {
        $backup = "$InstalledStatePath.corrupt.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        if ($Check) {
            Write-Warn2 "Cannot read installed.json. Running diagnostics with empty state."
        } else {
            Copy-Item $InstalledStatePath $backup -Force -ErrorAction SilentlyContinue
            Write-Warn2 "Cannot read installed.json. Backup: $backup"
        }
        return New-DefaultState
    }
}

function Save-State($State) {
    $State.lastRun = (Get-Date).ToString("o")
    $json = $State | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($InstalledStatePath,$json,(New-Object Text.UTF8Encoding($false)))
}

function Set-ToolState($State,[string]$Tool,[string]$Installed,[string]$Latest,[string]$Status,[bool]$WasUpdated=$false) {
    $previousInstalled = $null
    if ($State.tools.ContainsKey($Tool)) {
        $previousInstalled = [string]$State.tools[$Tool].installed
    }

    $updatedFrom = if ($WasUpdated -and $previousInstalled -and $Installed -and $previousInstalled -ne $Installed) { $previousInstalled } else { $null }
    $State.tools[$Tool] = @{
        installed   = $Installed
        latest      = $Latest
        status      = $Status
        updatedFrom = $updatedFrom
        lastChecked = (Get-Date).ToString("o")
    }
}

# ===========================================================================
# Script self-installation
# ===========================================================================

function Install-Self([switch]$UpdateOnly) {
    if (-not $UpdateOnly) {
        Ensure-AiDirectories
        Add-UserPath $BinDir
    }

    $source = $MyInvocation.ScriptName
    if ([string]::IsNullOrWhiteSpace($source) -or -not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $source = $PSCommandPath
    }

    if ($source -and (Test-Path -LiteralPath $source -PathType Leaf)) {
        $sourceFull = [IO.Path]::GetFullPath($source)
        $destFull   = [IO.Path]::GetFullPath($ManagedScriptPath)

        if ($sourceFull -ine $destFull) {
            Copy-Item -LiteralPath $sourceFull -Destination $ManagedScriptPath -Force
            if ($UpdateOnly) {
                Write-OK "Manager script updated: $ManagedScriptPath"
            } else {
                Write-OK "Script installed: $ManagedScriptPath"
            }
        }
    }

    if ($UpdateOnly) { return }

    # A .cmd wrapper enables the "ai-tools" command in CMD/PowerShell.
    $cmdPath = Join-Path $BinDir "ai-tools.cmd"
    $cmd = '@echo off' + "`r`n" +
           'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ai-tools.ps1" %*' + "`r`n"
    [IO.File]::WriteAllText($cmdPath,$cmd,(New-Object Text.ASCIIEncoding))
}

# ===========================================================================
# Interactive selection
# ===========================================================================

function Read-YesNo([string]$Question,[bool]$DefaultYes=$true) {
    $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
    while ($true) {
        $r = Read-Host "$Question $suffix"
        if ([string]::IsNullOrWhiteSpace($r)) { return $DefaultYes }
        switch ($r.Trim().ToLowerInvariant()) {
            "o"   { return $true }
            "oui" { return $true }
            "y"   { return $true }
            "yes" { return $true }
            "n"   { return $false }
            "non" { return $false }
            "no"  { return $false }
        }
        Write-Warn2 "Please answer Y or N."
    }
}

function Select-ToolsInteractive([string]$Action = "Install") {
    Show-ToolDescriptions

    Write-Host ""
    Write-Host "What would you like to do?" -ForegroundColor White
    Write-Host "  [A] $Action all tools"
    Write-Host "  [C] Choose individual tools"
    Write-Host "  [Q] Quit"
    Write-Host ""

    while ($true) {
        $choice = (Read-Host "Choice [A/C/Q]").Trim().ToUpperInvariant()
        if (-not $choice) { $choice = "A" }

        switch ($choice) {
            "A" { return @($AllToolNames) }
            "C" {
                $selected = @()
                if (Read-YesNo "$Action RTK ?" $true) {
                    $selected += "RTK"
                }
                if (Read-YesNo "$Action Token Optimizer ?" $true) {
                    $selected += "TokenOptimizer"
                }
                if (Read-YesNo "$Action Serena ?" $true) {
                    $selected += "Serena"
                }
                if (Read-YesNo "$Action Codebase Memory ?" $true) {
                    $selected += "CodebaseMemory"
                }
                return $selected
            }
            "Q" { return @() }
            default { Write-Warn2 "Invalid choice." }
        }
    }
}

function Resolve-SelectedTools($State) {
    if ($All) {
        return @($AllToolNames)
    }

    if ($Tools -and $Tools.Count -gt 0) {
        return @($Tools | Select-Object -Unique)
    }

    if ($ForceReinstall) {
        return @(Select-ToolsInteractive "Reinstall")
    }
    if ($Check -and (-not $State.selectedTools -or $State.selectedTools.Count -eq 0)) {
        return @($AllToolNames)
    }

    if ($ChooseTools -or -not $State.selectedTools -or $State.selectedTools.Count -eq 0) {
        return @(Select-ToolsInteractive)
    }

    return @($State.selectedTools)
}

function Read-MainAction {
    Write-Section "AI Tools" -Always
    Write-Host "  [1] Install / update"
    Write-Host "  [2] Force reinstallation"
    Write-Host "  [3] Dashboards"
    Write-Host "  [4] Diagnostics"
    Write-Host "  [Q] Quit"
    while ($true) {
        switch ((Read-Host "Choice [1-4/Q]").Trim().ToLowerInvariant()) {
            "1" { return "update" }
            "2" { return "reinstall" }
            "3" { return "dash" }
            "4" { return "check" }
            "q" { return "quit" }
            default { Write-Warn2 "Invalid choice." }
        }
    }
}

# ===========================================================================
# Prerequisites
# ===========================================================================

function Ensure-Winget {
    if (-not (Test-Command "winget")) {
        throw "winget is missing. Install 'App Installer' from Microsoft Store and try again."
    }
}

function Ensure-Git {
    if (Test-Command "git") {
        Write-Info "Git : $((& git --version) -join ' ')"
        return
    }
    if ($Check) {
        Write-Warn2 "Git is missing."
        return
    }
    if ($SkipPrerequisiteInstall) { throw "Git is missing." }

    Ensure-Winget
    Write-Info "Installing Git..."
    Invoke-External winget "install" "--id" "Git.Git" "-e" "--accept-package-agreements" "--accept-source-agreements"
    Refresh-ProcessPath
    if (Test-Path "$env:ProgramFiles\Git\cmd") { Add-UserPath "$env:ProgramFiles\Git\cmd" }
}

function Ensure-Node {
    if ((Test-Command "node") -and (Test-Command "npm") -and (Test-Command "npx")) {
        Write-Info "Node : $(& node --version) / npm $(& npm --version)"
        if (-not $Check -and -not (Test-Path "$env:APPDATA\npm")) {
            New-Item -ItemType Directory -Path "$env:APPDATA\npm" -Force | Out-Null
        }
        Add-UserPath "$env:APPDATA\npm"
        return
    }

    if ($Check) {
        Write-Warn2 "Node/npm/npx are missing or incomplete."
        return
    }
    if ($SkipPrerequisiteInstall) { throw "Node/npm/npx are missing." }

    Ensure-Winget
    Write-Info "Installing Node.js LTS..."
    Invoke-External winget "install" "--id" "OpenJS.NodeJS.LTS" "-e" "--accept-package-agreements" "--accept-source-agreements"
    Refresh-ProcessPath
    if (Test-Path "$env:ProgramFiles\nodejs") { Add-UserPath "$env:ProgramFiles\nodejs" }
    if (Test-Path "$env:APPDATA\npm") { Add-UserPath "$env:APPDATA\npm" }
}

function Ensure-Uv {
    if (Test-Command "uv") {
        Write-Info "uv : $(& uv --version)"
        if (Test-Path $SerenaBinDir) { Add-UserPath $SerenaBinDir }
        return
    }

    if ($Check) {
        Write-Warn2 "uv is missing."
        return
    }
    if ($SkipPrerequisiteInstall) { throw "uv is missing." }

    Ensure-Winget
    Write-Info "Installing uv..."
    Invoke-External winget "install" "--id" "astral-sh.uv" "-e" "--accept-package-agreements" "--accept-source-agreements"
    Refresh-ProcessPath
    if (Test-Path $SerenaBinDir) { Add-UserPath $SerenaBinDir }
}

# ===========================================================================
# RTK
# ===========================================================================

function Get-RtkInstalledVersion {
    if (Test-Path $RtkExe) {
        try { return Normalize-Version ((& $RtkExe --version 2>&1 | Out-String).Trim()) } catch {}
    }
    if (Test-Command "rtk") {
        try { return Normalize-Version ((& rtk --version 2>&1 | Out-String).Trim()) } catch {}
    }
    return $null
}

function Install-OrUpdate-Rtk($State) {
    Write-Section "RTK"

    $installed = Get-RtkInstalledVersion
    $release   = Get-GitHubLatestRelease $RtkApiLatest "ai-tools-rtk-updater"
    $latest    = Normalize-Version $release.tag_name

    Write-Info "Installed: $(if($installed){$installed}else{'not installed'})"
    Write-Info "Available: $latest"

    if ($Check) {
        $status = if ($installed -and (Compare-VersionText $installed $latest)) { "up-to-date" } elseif ($installed) { "update-available" } else { "not-installed" }
        Set-ToolState $State "RTK" $installed $latest $status
        return
    }

    $wasUpdated = $ForceReinstall -or -not $installed -or -not (Compare-VersionText $installed $latest)
    if ($wasUpdated) {
        $asset = $release.assets | Where-Object { $_.name -eq $RtkAssetName } | Select-Object -First 1
        if (-not $asset) { throw "RTK Windows release asset not found: $RtkAssetName" }

        $tmp = Join-Path $env:TEMP "ai-tools-rtk-$([guid]::NewGuid().ToString('N'))"
        $zip = Join-Path $tmp $RtkAssetName
        $ext = Join-Path $tmp "extract"
        New-Item -ItemType Directory -Path $ext -Force | Out-Null

        try {
            Write-Info "Downloading RTK $latest..."
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers @{ "User-Agent"="ai-tools-rtk-updater" }
            Expand-Archive -LiteralPath $zip -DestinationPath $ext -Force

            $candidate = Get-ChildItem $ext -Filter "rtk.exe" -Recurse | Select-Object -First 1
            if (-not $candidate) { throw "rtk.exe is missing from the archive." }

            Copy-Item $candidate.FullName $RtkExe -Force
            Write-OK "RTK installed/updated: $latest"
        } finally {
            try {
                if ([System.IO.Directory]::Exists($tmp)) {
                    [System.IO.Directory]::Delete($tmp, $true)
                }
            } catch {
                Write-Warn2 "RTK temporary cleanup skipped: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Info "RTK is already up to date."
    }

    Add-UserPath $BinDir
    Refresh-ProcessPath

    $installed = Get-RtkInstalledVersion

    # Each client manages hooks and instructions in its own directory.
    if ((Test-Command "claude") -or (Test-Path (Join-Path $env:USERPROFILE ".claude"))) {
        try {
            Write-Info "Claude detected -> checking/initializing global RTK integration..."
            & $RtkExe init -g | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Info "RTK init -g completed." }
        } catch {
            Write-Warn2 "Could not apply rtk init -g: $($_.Exception.Message)"
        }
    }

    if (@(Get-CopilotMcpTargets).Count -gt 0) {
        try {
            Write-Info "Copilot detected -> checking/initializing global RTK integration..."
            & $RtkExe init -g --copilot | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Info "RTK init -g --copilot completed." }
        } catch {
            Write-Warn2 "Could not apply rtk init -g --copilot: $($_.Exception.Message)"
        }
    }

    if ((Test-Command "codex") -or (Test-Path (Join-Path $env:USERPROFILE ".codex"))) {
        try {
            Write-Info "Codex detected -> checking/initializing global RTK integration..."
            & $RtkExe init -g --codex | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Info "RTK init -g --codex completed." }
        } catch {
            Write-Warn2 "Could not apply rtk init -g --codex: $($_.Exception.Message)"
        }
    }

    Set-ToolState $State "RTK" $installed $latest "up-to-date" $wasUpdated
}

# ===========================================================================
# Token Optimizer
# ===========================================================================

function Get-TokenInstalledVersion {
    if (-not (Test-Command "npm")) { return $null }
    try {
        $json = & npm list -g $TokenPackage --depth=0 --json 2>$null | Out-String
        if (-not $json) { return $null }
        $obj = $json | ConvertFrom-Json
        $dep = $obj.dependencies.PSObject.Properties[$TokenPackage]
        if ($dep) { return Normalize-Version $dep.Value.version }
    } catch {}
    return $null
}

function Get-TokenLatestVersion {
    if (-not (Test-Command "npm")) { return $null }
    try { return Normalize-Version ((& npm view $TokenPackage version 2>$null | Out-String).Trim()) } catch {}
    return $null
}

function Update-TokenDashboard([string]$TokenVersion) {
    if ($SkipDashboardBuild) {
        Write-Warn2 "Token Optimizer dashboard skipped (-SkipDashboardBuild)."
        return
    }

    if (-not $TokenVersion) {
        Write-Warn2 "Unknown Token Optimizer version: dashboard not updated."
        return
    }

    Ensure-Git
    if (-not (Test-Command "git")) {
        Write-Warn2 "Git unavailable: Token Optimizer dashboard not managed."
        return
    }

    $needBuild = [bool]$ForceReinstall
    $hasLocalChanges = $false
    $releaseTag = "v$TokenVersion"
    $tagCommitReference = "refs/tags/$releaseTag" + "^{commit}"

    if (Test-Path (Join-Path $TokenDashboardDir ".git")) {
        Push-Location $TokenDashboardDir
        try {
            $changes = (& git status --porcelain 2>$null | Out-String).Trim()
            if ($changes) {
                $hasLocalChanges = $true
                Write-Warn2 "Token Optimizer dashboard has local changes: Git update skipped."
            } else {
                $target = (& git rev-parse --verify --quiet $tagCommitReference 2>$null | Out-String).Trim()
                if (-not $target) {
                    $remoteTag = (& git ls-remote --tags --refs origin "refs/tags/$releaseTag" 2>$null | Out-String).Trim()
                    if (-not $remoteTag) {
                        Write-Warn2 "Release $releaseTag not found in the repository: dashboard not updated."
                        return
                    }

                    Invoke-External git "fetch" "--depth" "1" "origin" "refs/tags/${releaseTag}:refs/tags/${releaseTag}"
                    $target = (& git rev-parse --verify --quiet $tagCommitReference 2>$null | Out-String).Trim()
                }

                $current = (& git rev-parse HEAD 2>$null | Out-String).Trim()
                if ($current -ne $target) {
                    Invoke-External git "checkout" $releaseTag
                    $needBuild = $true
                }
            }
        } finally { Pop-Location }
    } else {
        if (Test-Path $TokenDashboardDir) {
            $backup = "$TokenDashboardDir.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item $TokenDashboardDir $backup
            Write-Warn2 "Previous dashboard directory moved: $backup"
        }
        Invoke-External git "clone" "--depth" "1" "--branch" $releaseTag $TokenDashboardRepo $TokenDashboardDir
        $needBuild = $true
    }

    if (-not (Test-Path (Join-Path $TokenDashboardDir "node_modules"))) {
        $needBuild = $true
    }

    if ($needBuild) {
        Push-Location $TokenDashboardDir
        try {
            Invoke-External npm "ci"
            Invoke-External npm "run" "build"
        } finally { Pop-Location }
        Write-OK "Token Optimizer dashboard built."
    } elseif ($hasLocalChanges) {
        Write-OK "Local Token Optimizer dashboard preserved."
    } else {
        Write-Info "Token Optimizer dashboard is already up to date."
    }
}

function Install-OrUpdate-TokenOptimizer($State) {
    Write-Section "Token Optimizer"

    Ensure-Node
    if (-not (Test-Command "npm")) {
        Set-ToolState $State "TokenOptimizer" $null $null "prerequisite-missing"
        return
    }

    $installed = Get-TokenInstalledVersion
    $latest    = Get-TokenLatestVersion

    Write-Info "Installed: $(if($installed){$installed}else{'not installed'})"
    Write-Info "Available: $(if($latest){$latest}else{'unknown'})"

    $wasUpdated = $false
    if (-not $Check) {
        if ($ForceReinstall -or -not $installed -or ($latest -and -not (Compare-VersionText $installed $latest))) {
            $wasUpdated = $true
            if ($ForceReinstall) {
                Invoke-External npm "install" "-g" "--force" "$TokenPackage@latest"
            } else {
                Invoke-External npm "install" "-g" "$TokenPackage@latest"
            }
            $installed = Get-TokenInstalledVersion
            Write-OK "Token Optimizer : $installed"
        } else {
            Write-Info "Token Optimizer is already up to date."
        }

        Update-TokenDashboard $installed
    }

    $status = if (-not $installed) { "not-installed" } elseif ($latest -and (Compare-VersionText $installed $latest)) { "up-to-date" } else { "update-available" }
    Set-ToolState $State "TokenOptimizer" $installed $latest $status $wasUpdated
}

# ===========================================================================
# Serena
# ===========================================================================

function Get-SerenaInstalledVersion {
    if (Test-Command "serena") {
        try { return Normalize-Version ((& serena --version 2>&1 | Out-String).Trim()) } catch {}
    }

    if (Test-Command "uv") {
        try {
            $txt = (& uv tool list 2>$null | Out-String)
            $m = [regex]::Match($txt,'(?m)^serena-agent\s+v?([0-9]+\.[0-9]+\.[0-9][^\s]*)')
            if ($m.Success) { return Normalize-Version $m.Groups[1].Value }
        } catch {}
    }
    return $null
}

function Get-SerenaLatestVersion {
    try {
        $p = Invoke-RestMethod -Uri $SerenaPypi -Headers @{ "User-Agent"="ai-tools-updater" }
        return Normalize-Version $p.info.version
    } catch {
        return $null
    }
}

function Install-OrUpdate-Serena($State) {
    Write-Section "Serena"

    Ensure-Uv
    if (-not (Test-Command "uv")) {
        Set-ToolState $State "Serena" $null $null "prerequisite-missing"
        return
    }

    if (Test-Path $SerenaBinDir) { Add-UserPath $SerenaBinDir }
    Refresh-ProcessPath

    $installed = Get-SerenaInstalledVersion
    $latest    = Get-SerenaLatestVersion

    Write-Info "Installed: $(if($installed){$installed}else{'not installed'})"
    Write-Info "Available: $(if($latest){$latest}else{'unknown'})"

    $wasUpdated = $false
    if (-not $Check) {
        if ($ForceReinstall) {
            $wasUpdated = $true
            Invoke-External uv "tool" "install" "--force" "-p" "3.13" $SerenaTool
        } elseif (-not $installed) {
            $wasUpdated = $true
            Invoke-External uv "tool" "install" "-p" "3.13" $SerenaTool
        } elseif ($latest -and -not (Compare-VersionText $installed $latest)) {
            $wasUpdated = $true
            Invoke-External uv "tool" "upgrade" $SerenaTool
        } else {
            Write-Info "Serena is already up to date."
        }

        if (Test-Path $SerenaBinDir) { Add-UserPath $SerenaBinDir }
        Refresh-ProcessPath
        $installed = Get-SerenaInstalledVersion

        $serenaConfig = Join-Path $env:USERPROFILE ".serena\serena_config.yml"
        if (-not (Test-Path $serenaConfig) -and (Test-Command "serena")) {
            Write-Info "Initializing Serena for the first time..."
            try {
                & serena init
                if ($LASTEXITCODE -ne 0) { Write-Warn2 "serena init returned $LASTEXITCODE." }
            } catch {
                Write-Warn2 "serena init did not complete automatically."
            }
        }
        if (Test-Path $serenaConfig) {
            try {
                $configText = Get-Content -LiteralPath $serenaConfig -Raw
                if ($configText -match '(?m)^\s*web_dashboard_open_on_launch\s*:') {
                    $configText = [regex]::Replace($configText, '(?m)^\s*web_dashboard_open_on_launch\s*:\s*.*$', 'web_dashboard_open_on_launch: false')
                } else {
                    $configText = $configText.TrimEnd() + "`r`nweb_dashboard_open_on_launch: false`r`n"
                }
                Set-Content -LiteralPath $serenaConfig -Value $configText -NoNewline
                Write-Info "Serena configuration updated (dashboard will not open automatically)."
            } catch {
                Write-Warn2 "Cannot update Serena configuration: $($_.Exception.Message)"
            }
        }
    }

    $status = if (-not $installed) { "not-installed" } elseif ($latest -and (Compare-VersionText $installed $latest)) { "up-to-date" } else { "update-available" }
    Set-ToolState $State "Serena" $installed $latest $status $wasUpdated
}

# ===========================================================================
# Codebase Memory
# ===========================================================================

function Get-CbmInstalledVersion {
    $cmd = $null
    if (Test-Path $CbmExe) { $cmd = $CbmExe }
    elseif (Test-Command "codebase-memory-mcp") { $cmd = (Get-Command "codebase-memory-mcp").Source }

    if ($cmd) {
        try { return Normalize-Version ((& $cmd --version 2>&1 | Out-String).Trim()) } catch {}
    }
    return $null
}

function Get-CbmLatestVersion {
    try {
        $release = Get-GitHubLatestRelease $CbmApiLatest "ai-tools-cbm-updater"
        return Normalize-Version $release.tag_name
    } catch {
        return $null
    }
}

function Install-CbmOfficial {
    $installerTempDir = Join-Path $env:LOCALAPPDATA "Temp\ai-tools-cbm-$([guid]::NewGuid().ToString('N'))"
    $tmpInstaller = Join-Path $installerTempDir "install.ps1"
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    try {
        New-Item -ItemType Directory -Path $installerTempDir -Force | Out-Null
        $stagingAcl = New-Object System.Security.AccessControl.DirectorySecurity
        $stagingAcl.SetAccessRuleProtection($true, $false)
        $stagingOwner = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User
        $stagingAcl.SetOwner($stagingOwner)
        $stagingAcl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            $stagingOwner, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Acl -LiteralPath $installerTempDir -AclObject $stagingAcl

        $env:TEMP = $installerTempDir
        $env:TMP = $installerTempDir
        Invoke-WebRequest -Uri $CbmInstallerUrl -OutFile $tmpInstaller -Headers @{ "User-Agent"="ai-tools-updater" }
        Unblock-File $tmpInstaller -ErrorAction SilentlyContinue

        # --skip-config avoids automatic hooks/configuration for other agents.
        # VS Code and Insiders configuration is managed below.
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmpInstaller --ui --skip-config
        if ($LASTEXITCODE -ne 0) {
            throw "Codebase Memory installer failed ($LASTEXITCODE)."
        }
    } finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
        Remove-Item -LiteralPath $installerTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-OrUpdate-CodebaseMemory($State) {
    Write-Section "Codebase Memory"

    $installed = Get-CbmInstalledVersion
    $latest    = Get-CbmLatestVersion

    Write-Info "Installed: $(if($installed){$installed}else{'not installed'})"
    Write-Info "Available: $(if($latest){$latest}else{'unknown'})"

    $wasUpdated = $false
    if (-not $Check) {
        if ($ForceReinstall -or -not $installed) {
            $wasUpdated = $true
            Install-CbmOfficial
        } elseif ($latest -and -not (Compare-VersionText $installed $latest)) {
            $wasUpdated = $true
            Write-Info "Updating Codebase Memory..."
            $updated = $false

            try {
                $cbmCmd = if (Test-Path $CbmExe) { $CbmExe } else { (Get-Command "codebase-memory-mcp").Source }
                & $cbmCmd update
                $versionAfterUpdate = Get-CbmInstalledVersion
                if ($LASTEXITCODE -eq 0 -and (Compare-VersionText $versionAfterUpdate $latest)) {
                    $updated = $true
                }
            } catch {}

            if (-not $updated) {
                Write-Warn2 "Native updater did not complete successfully -> using the official installer."
                Install-CbmOfficial
            }
        } else {
            Write-Info "Codebase Memory is already up to date."
        }

        if (Test-Path $CbmInstallDir) { Add-UserPath $CbmInstallDir }
        Refresh-ProcessPath
        $installed = Get-CbmInstalledVersion

        $cbmCmd = if (Test-Path $CbmExe) { $CbmExe } elseif (Test-Command "codebase-memory-mcp") { (Get-Command "codebase-memory-mcp").Source } else { $null }
        if ($cbmCmd) {
            try {
                & $cbmCmd config set auto_index true | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Info "Codebase Memory auto_index = true" }
            } catch {
                Write-Warn2 "Cannot enable auto_index."
            }
        }
    }

    $status = if (-not $installed) { "not-installed" } elseif ($latest -and (Compare-VersionText $installed $latest)) { "up-to-date" } else { "update-available" }
    Set-ToolState $State "CodebaseMemory" $installed $latest $status $wasUpdated
}

# ===========================================================================
# Copilot global MCP configuration
# ===========================================================================

function Get-ExecutablePath([string]$CommandName,[string]$Fallback) {
    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if ($Fallback -and (Test-Path $Fallback)) { return $Fallback }
    return $CommandName
}

function Set-McpServersInFile([string]$Path,[string[]]$Selected) {
    $dir = Split-Path $Path -Parent

    if (Test-Path $Path) {
        $raw = Get-Content $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $config = [pscustomobject]@{}
        } else {
            try {
                $config = $raw | ConvertFrom-Json
            } catch {
                Write-Warn2 "Cannot parse JSON/JSONC; file left unchanged: $Path"
                return
            }
        }
    } else {
        $config = [pscustomobject]@{}
    }

    if (-not $config.PSObject.Properties["mcpServers"]) {
        $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([pscustomobject]@{})
    }

    $changed = $false

    # Copilot's portable MCP configuration is shared across profiles and tools.
    if ($Selected -contains "TokenOptimizer") {
        $value = [pscustomobject]@{
            type    = "stdio"
            command = "npx"
            args    = @("-y","@ooples/token-optimizer-mcp@latest")
        }
        if ($config.mcpServers.PSObject.Properties["token-optimizer"]) {
            $config.mcpServers."token-optimizer" = $value
        } else {
            $config.mcpServers | Add-Member NoteProperty "token-optimizer" $value
        }
        $changed = $true
    }

    if ($Selected -contains "Serena") {
        $value = [pscustomobject]@{
            type    = "stdio"
            command = "serena"
            args    = @("start-mcp-server","--context=vscode")
        }
        if ($config.mcpServers.PSObject.Properties["serena"]) {
            $config.mcpServers.serena = $value
        } else {
            $config.mcpServers | Add-Member NoteProperty "serena" $value
        }
        $changed = $true
    }

    if ($Selected -contains "CodebaseMemory") {
        $value = [pscustomobject]@{
            type    = "stdio"
            command = "codebase-memory-mcp"
            args    = @()
        }
        if ($config.mcpServers.PSObject.Properties["codebase-memory"]) {
            $config.mcpServers."codebase-memory" = $value
        } else {
            $config.mcpServers | Add-Member NoteProperty "codebase-memory" $value
        }
        $changed = $true
    }

    if (-not $changed) { return }

    if ($Check) {
        Write-Info "MCP target detected: $Path"
        return
    }

    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    if (Test-Path $Path) {
        $backup = "$Path.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $Path $backup -Force
        Write-Info "MCP backup: $backup"
    }

    $json = $config | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($Path,$json,(New-Object Text.UTF8Encoding($false)))
    Write-Info "MCP configured: $Path"
}

function Get-CopilotMcpTargets {
    $stableInstalled = (Test-Command "code") -or
                       (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code") -or
                       (Test-Path "$env:APPDATA\Code")

    $insidersInstalled = (Test-Command "code-insiders") -or
                         (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders") -or
                         (Test-Path "$env:APPDATA\Code - Insiders")

    $copilotCliInstalled = Test-Command "copilot"
    if (-not ($stableInstalled -or $insidersInstalled -or $copilotCliInstalled) -and
        -not (Test-Path $CopilotMcpConfigPath)) {
        return @()
    }

    return @($CopilotMcpConfigPath)
}

function Configure-CopilotMcp([string[]]$Selected) {
    Write-Section "Copilot global MCP configuration"

    $mcpTools = @($Selected | Where-Object { $_ -in @("TokenOptimizer","Serena","CodebaseMemory") })
    if ($mcpTools.Count -eq 0) {
        Write-Info "No MCP tools selected."
        return
    }

    $targets = @(Get-CopilotMcpTargets)
    if ($targets.Count -eq 0) {
        Write-Warn2 "VS Code / Copilot not detected. Configure MCP servers after installing or configuring Copilot."
        return
    }

    foreach ($target in $targets) {
        Set-McpServersInFile $target $Selected
    }
}

# ===========================================================================
# Codex MCP configuration
# ===========================================================================

function Test-CodexMcpServer([string]$Name) {
    if (-not (Test-Command "codex")) { return $false }

    & codex mcp get $Name 1>$null 2>$null
    return $LASTEXITCODE -eq 0
}

function Add-CodexMcpServer([string]$Name,[string]$Command,[string[]]$Arguments) {
    if (Test-CodexMcpServer $Name) {
        Write-Info "Codex MCP server already configured: $Name"
        return $true
    }

    if ($Check) {
        Write-Warn2 "Codex MCP server is missing: $Name"
        return $false
    }

    $codexArgs = @("mcp","add",$Name,"--",$Command) + $Arguments
    Invoke-External -Command "codex" -Arguments $codexArgs

    if (-not (Test-CodexMcpServer $Name)) {
        throw "Codex MCP server '$Name' was not detected after configuration."
    }

    Write-OK "Codex MCP server configured: $Name"
    return $true
}

function Set-CodexMcpTimeouts([string]$Name,[int]$StartupTimeout,[int]$ToolTimeout) {
    $configPath = Join-Path $CodexHome "config.toml"
    if (-not (Test-Path $configPath)) {
        Write-Warn2 "Codex configuration not found: $configPath"
        return
    }

    $old = Get-Content $configPath -Raw
    $sectionPattern = "(?ms)^\[mcp_servers\." + [regex]::Escape($Name) + "\]\r?\n.*?(?=^\[|\z)"
    $match = [regex]::Match($old,$sectionPattern)
    if (-not $match.Success) {
        Write-Warn2 "Codex MCP section not found: $Name"
        return
    }

    $hasStartupTimeout = $match.Value -match "(?m)^startup_timeout_sec\s*=\s*$StartupTimeout\s*$"
    $hasToolTimeout = $match.Value -match "(?m)^tool_timeout_sec\s*=\s*$ToolTimeout\s*$"
    if ($hasStartupTimeout -and $hasToolTimeout) {
        Write-Info "Codex MCP timeouts already configured: $Name"
        return
    }

    if ($Check) {
        Write-Warn2 "Codex MCP timeouts need updating: $Name"
        return
    }

    $lineEnding = if ($old.Contains("`r`n")) { "`r`n" } else { "`n" }
    $section = [regex]::Replace($match.Value,"(?m)^(startup_timeout_sec|tool_timeout_sec)\s*=.*\r?\n?","")
    $section = $section.TrimEnd("`r","`n") + $lineEnding +
               "startup_timeout_sec = $StartupTimeout" + $lineEnding +
               "tool_timeout_sec = $ToolTimeout" + $lineEnding
    $content = $old.Substring(0,$match.Index) + $section + $old.Substring($match.Index + $match.Length)

    Copy-Item $configPath "$configPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
    [IO.File]::WriteAllText($configPath,$content,(New-Object Text.UTF8Encoding($false)))
    Write-OK "Codex MCP timeouts configured: $Name"
}

function Set-CodexInstructions([string[]]$Selected) {
    $needsInstruction = ($Selected -contains "TokenOptimizer") -or
                        ($Selected -contains "Serena") -or
                        ($Selected -contains "CodebaseMemory")
    if (-not $needsInstruction) { return }

    $begin = "<!-- ai-tools:begin -->"
    $end = "<!-- ai-tools:end -->"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($begin)
    $lines.Add("# Local AI tools")
    $lines.Add("")

    if ($Selected -contains "TokenOptimizer") {
        $lines.Add("## Token Optimizer")
        $lines.Add("- Use a named optimizer tool only when it is visible in the current tool inventory.")
        $lines.Add("- Prefer `smart_read`, `smart_grep`, and `smart_glob` for large or repeated reads and searches.")
        $lines.Add("")
    }

    if ($Selected -contains "Serena") {
        $lines.Add("## Serena")
        $lines.Add("- Prefer Serena for symbol-level code navigation: classes, functions, methods, definitions, and references.")
        $lines.Add("- Activate the current project with Serena before symbol-level analysis.")
        $lines.Add("")
    }

    if ($Selected -contains "CodebaseMemory") {
        $lines.Add("## Codebase Memory")
        $lines.Add("- Prefer Codebase Memory for architecture, dependency, impact, and repository-wide semantic questions.")
        $lines.Add("- Index a repository before structural exploration when no current graph is available.")
        $lines.Add("")
    }

    $lines.Add($end)
    $block = $lines -join "`r`n"
    $old = if (Test-Path $CodexAgentsFile) { Get-Content $CodexAgentsFile -Raw } else { "" }
    $pattern = "(?s)" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end)
    $content = if ([regex]::IsMatch($old,$pattern)) {
        [regex]::Replace($old,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($match) $block },1)
    } elseif ([string]::IsNullOrWhiteSpace($old)) {
        $block + "`r`n"
    } else {
        $old.TrimEnd("`r","`n") + "`r`n`r`n" + $block + "`r`n"
    }

    if ($old -eq $content) {
        Write-Info "Global Codex instructions are already up to date."
        return
    }

    if ($Check) {
        if ($old) { Write-Warn2 "Global Codex instructions need updating: $CodexAgentsFile" }
        else { Write-Warn2 "Global Codex instructions are missing: $CodexAgentsFile" }
        return
    }

    New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
    if (Test-Path $CodexAgentsFile) {
        Copy-Item $CodexAgentsFile "$CodexAgentsFile.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
    }
    [IO.File]::WriteAllText($CodexAgentsFile,$content,(New-Object Text.UTF8Encoding($false)))
    Write-OK "Global Codex instructions: $CodexAgentsFile"
}

function Configure-CodexIntegration([string[]]$Selected) {
    $mcpTools = @($Selected | Where-Object { $_ -in @("TokenOptimizer","Serena","CodebaseMemory") })
    if ($mcpTools.Count -eq 0) { return }

    Write-Section "MCP Codex"

    # Detect Codex even when installed before ai-tools or through
    # Microsoft Store, without requiring manual PATH configuration.
    Ensure-CodexCliPath | Out-Null

    if (-not (Test-Command "codex")) {
        Write-Warn2 "Codex not detected. Its MCP servers can be configured after installation."
        return
    }

    if ($Selected -contains "TokenOptimizer") {
        if (Add-CodexMcpServer "token-optimizer" "npx" @("-y","@ooples/token-optimizer-mcp@latest")) {
            Set-CodexMcpTimeouts "token-optimizer" 30 120
        }
    }
    if ($Selected -contains "Serena") {
        $null = Add-CodexMcpServer "serena" "serena" @("start-mcp-server","--project-from-cwd")
    }
    if ($Selected -contains "CodebaseMemory") {
        $null = Add-CodexMcpServer "codebase-memory-mcp" "codebase-memory-mcp" @()
    }

    Set-CodexInstructions $Selected
}

# ===========================================================================
# Global Copilot instructions
# ===========================================================================

function Configure-CopilotInstructions([string[]]$Selected) {
    $needsInstruction = ($Selected -contains "TokenOptimizer") -or
                        ($Selected -contains "Serena") -or
                        ($Selected -contains "CodebaseMemory")

    if (-not $needsInstruction) { return }

    Write-Section "Copilot user instructions"

    if ($Check) {
        if (Test-Path $AiInstructionFile) { Write-Info "Global instructions found: $AiInstructionFile" }
        else { Write-Warn2 "Global instructions are missing: $AiInstructionFile" }
        return
    }

    New-Item -ItemType Directory -Path $CopilotInstructionsDir -Force | Out-Null

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("---")
    $lines.Add('applyTo: "**"')
    $lines.Add('description: "Use local AI tooling efficiently and minimize context usage"')
    $lines.Add("---")
    $lines.Add("")
    $lines.Add("# Local AI tools")
    $lines.Add("")
    $lines.Add("Minimize unnecessary context and prefer the specialized local tools when they are relevant.")
    $lines.Add("")

    if ($Selected -contains "TokenOptimizer") {
        $lines.Add("## Token Optimizer")
        $lines.Add("- Prefer Token Optimizer for large or repeated reads and searches.")
        $lines.Add("- Prefer `smart_read`, `smart_grep`, `smart_glob` and `smart_diff` when they reduce context.")
        $lines.Add("- Avoid repeatedly loading complete large files.")
        $lines.Add("")
    }

    if ($Selected -contains "Serena") {
        $lines.Add("## Serena")
        $lines.Add("- Prefer Serena for symbol-level code navigation: classes, functions, methods, definitions and references.")
        $lines.Add("- Activate the current project with Serena when needed before symbol-level analysis.")
        $lines.Add("")
    }

    if ($Selected -contains "CodebaseMemory") {
        $lines.Add("## Codebase Memory")
        $lines.Add("- Prefer Codebase Memory for architecture, dependency, impact and repository-wide semantic questions.")
        $lines.Add("- If the current repository is not indexed yet and indexing is useful, index it before repository-wide analysis.")
        $lines.Add("")
    }

    $content = ($lines -join "`r`n") + "`r`n"

    if (Test-Path $AiInstructionFile) {
        $old = Get-Content $AiInstructionFile -Raw
        if ($old -eq $content) {
            Write-Info "Global instructions are already up to date."
            return
        }

        Copy-Item $AiInstructionFile "$AiInstructionFile.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
    }

    [IO.File]::WriteAllText($AiInstructionFile,$content,(New-Object Text.UTF8Encoding($false)))
    Write-OK "Global Copilot instructions: $AiInstructionFile"
}

# ===========================================================================
# UI
# ===========================================================================

function Show-UiCommands([string[]]$Selected) {
    $hasDashboard = $Selected -contains "RTK" -or $Selected -contains "TokenOptimizer" -or $Selected -contains "Serena" -or $Selected -contains "CodebaseMemory"
    if (-not $hasDashboard) { return }

    Write-Section "Shortcuts" -Always
    Write-Host "  ai-tools       Open the main menu"
    Write-Host "  ai-tools -ForceReinstall -All  Reinstall all tools"
    Write-Host "  ai-tools dash  Choose and launch a dashboard"
    Write-Host "  ai-tools -check  Check without making changes"
    Write-Host "  ai-tools -verbose  Show technical details"
}

function Launch-UI([string]$Which) {
    Ensure-AiDirectories
    Refresh-ProcessPath

    switch ($Which) {
        "RTK" {
            if (Test-Path $RtkExe) {
                Invoke-External $RtkExe "gain"
            } elseif (Test-Command "rtk") {
                Invoke-External rtk "gain"
            } else {
                throw "RTK is missing."
            }
        }

        "TokenOptimizer" {
            if (-not (Test-Path $TokenDashboardDir)) {
                throw "Token Optimizer dashboard is missing. Run 'ai-tools' first."
            }
            if (-not (Test-Command "npm")) { throw "npm is missing." }

            Write-Info "Dashboard Token Optimizer -> http://localhost:3100"
            Start-Process "http://localhost:3100"
            Push-Location $TokenDashboardDir
            try { & npm run dashboard } finally { Pop-Location }
        }

        "Serena" {
            if (-not (Test-Command "serena")) { throw "Serena is missing." }
            Write-Info "Starting Serena with its dashboard..."
            & serena start-mcp-server --context=vscode --open-web-dashboard true
        }

        "CodebaseMemory" {
            $cmd = if (Test-Path $CbmExe) { $CbmExe } elseif (Test-Command "codebase-memory-mcp") { (Get-Command "codebase-memory-mcp").Source } else { $null }
            if (-not $cmd) { throw "Codebase Memory is missing." }

            Write-Info "Graph UI -> http://localhost:9749"
            Start-Process "http://localhost:9749"
            & $cmd --ui=true --port=9749
        }
    }
}

function Resolve-DashboardUI([string[]]$Selected,[string]$Dashboard) {
    $available = @()
    if ($Selected -contains "TokenOptimizer") {
        $available += [pscustomobject]@{ Key = "token"; Label = "Token Optimizer"; UI = "TokenOptimizer" }
    }
    if ($Selected -contains "Serena") {
        $available += [pscustomobject]@{ Key = "serena"; Label = "Serena"; UI = "Serena" }
    }
    if ($Selected -contains "CodebaseMemory") {
        $available += [pscustomobject]@{ Key = "graph"; Label = "Codebase Memory Graph"; UI = "CodebaseMemory" }
    }
    if ($Selected -contains "RTK") {
        $available += [pscustomobject]@{ Key = "rtk"; Label = "RTK (gain)"; UI = "RTK" }
    }

    if ($available.Count -eq 0) {
        throw "No dashboards available. Run 'ai-tools' first to install or select a tool."
    }

    if ($Dashboard) {
        $target = @($available | Where-Object { $_.Key -eq $Dashboard })
        if ($target.Count -eq 0) {
            throw "Dashboard '$Dashboard' is not managed on this machine."
        }
        return $target[0].UI
    }

    Write-Section "Dashboards" -Always
    for ($index = 0; $index -lt $available.Count; $index++) {
        Write-Host "  [$($index + 1)] $($available[$index].Label)" -ForegroundColor White
    }
    Write-Host "  [Q] Quit" -ForegroundColor DarkGray

    while ($true) {
        $choice = (Read-Host "Choice [1-$($available.Count)/Q]").Trim().ToLowerInvariant()
        if ($choice -eq "q") { return $null }
        if ($choice -match "^\d+$") {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $available.Count) {
                return $available[$index].UI
            }
        }
        Write-Warn2 "Invalid choice."
    }
}

function Launch-Dashboard([string[]]$Selected,[string]$Dashboard) {
    $ui = Resolve-DashboardUI $Selected $Dashboard
    if ($ui) { Launch-UI $ui }
}

# ===========================================================================
# Summary
# ===========================================================================

function Show-StateSummary($State,[string[]]$Selected) {
    Write-Section "Summary" -Always

    foreach ($tool in $Selected) {
        $entry = $State.tools[$tool]
        if (-not $entry) {
            Write-Host ("{0,-20} {1}" -f $tool,"not checked")
            continue
        }

        $status    = if ($entry.status)    { $entry.status }    else { "?" }
        $installed = if ($entry.installed) { [string]$entry.installed } else { $null }
        $updatedFrom = if ($entry.updatedFrom) { [string]$entry.updatedFrom } else { $null }
        $summary = if ($updatedFrom -and $installed) {
            "$updatedFrom -> $installed  updated"
        } elseif ($installed) {
            "$installed  $status"
        } else {
            $status
        }

        $color = if ($status -eq "up-to-date") { "Green" } elseif ($status -eq "update-available") { "Yellow" } else { "Gray" }
        Write-Host ("  {0,-20} {1}" -f $tool,$summary) -ForegroundColor $color
    }
}

# ===========================================================================
# MAIN
# ===========================================================================

try {
    Refresh-ProcessPath

    if (-not $Check -and
        (Test-Path -LiteralPath $ManagedScriptPath -PathType Leaf) -and
        ([IO.Path]::GetFullPath($PSCommandPath) -ine [IO.Path]::GetFullPath($ManagedScriptPath))) {
        Install-Self -UpdateOnly
        Write-Host "No tools were installed or updated."
        Write-Host "Run 'ai-tools -All' to install or update all tools."
        exit 0
    }

    if ($PSBoundParameters.Count -eq 0) {
        switch (Read-MainAction) {
            "quit" { exit 0 }
            "check" { $Check = $true }
            "dash" { $Command = "dash" }
            "reinstall" {
                $ForceReinstall = $true
                $Tools = @(Select-ToolsInteractive "Reinstall")
                if ($Tools.Count -eq 0) { exit 0 }
            }
        }
    }

    $state = Load-State

    if ($ForceReinstall -and $Check) {
        throw "-ForceReinstall and -Check cannot be combined."
    }
    if ($Check -and ($UI -or $Command -eq "dash")) {
        throw "-Check cannot launch a dashboard."
    }
    if (-not $Check) { Install-Self }

    if ($UI) {
        Launch-UI $UI
        exit 0
    }

    if ($Command -eq "dash") {
        Launch-Dashboard @($state.selectedTools) $Dashboard
        exit 0
    }

    $selected = @(Resolve-SelectedTools $state)

    if ($selected.Count -eq 0) {
        Write-Warn2 "No tools selected. Nothing to do."
        exit 0
    }

    # Diagnostics must never modify the saved selection.
    if (-not $Check) {
        if ($ForceReinstall) {
            $state.selectedTools = @((@($state.selectedTools) + $selected) | Select-Object -Unique)
        } else {
            $state.selectedTools = @($selected)
        }
    }

    Write-Section "AI Tools" -Always
    Write-Host "Tools managed on this machine: $($selected -join ', ')" -ForegroundColor White
    if ($Check) {
        Write-Host "Mode: DIAGNOSTICS ONLY" -ForegroundColor Yellow
    } elseif ($ForceReinstall) {
        Write-Host "Mode: FORCED REINSTALLATION" -ForegroundColor Yellow
    } else {
        Write-Host "Mode: INSTALL / UPDATE" -ForegroundColor Green
    }

    # Install only the prerequisites required by the selected tools.
    if ($selected -contains "TokenOptimizer") {
        Ensure-Node
        if (-not $SkipDashboardBuild) { Ensure-Git }
    }
    if ($selected -contains "Serena") {
        Ensure-Uv
    }

    # Tools
    if ($selected -contains "RTK")            { Install-OrUpdate-Rtk $state }
    if ($selected -contains "TokenOptimizer") { Install-OrUpdate-TokenOptimizer $state }
    if ($selected -contains "Serena")         { Install-OrUpdate-Serena $state }
    if ($selected -contains "CodebaseMemory") { Install-OrUpdate-CodebaseMemory $state }

    # Configure MCP only after binaries are installed / available.
    Configure-CopilotMcp $selected
    Configure-CodexIntegration $selected
    Configure-CopilotInstructions $selected

    if (-not $Check) { Save-State $state }
    Show-StateSummary $state $selected
    Show-UiCommands $selected

    if (-not $Check) {
        Write-Warn2 "After the first installation, fully close and restart VS Code, VS Code Insiders, and Codex to pick up PATH changes."
        Write-OK "Installation / update completed."
    } else {
        Write-OK "Diagnostics completed. No updates were applied."
    }
}
catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
}
