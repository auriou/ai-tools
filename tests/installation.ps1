$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root "ai-tools.ps1"), [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}
$main = $ast.EndBlock.Statements[-1].Body.Extent.Text
$main = [scriptblock]::Create($main.Substring(1, $main.Length - 2))
$temp = Join-Path ([IO.Path]::GetTempPath()) ("ai-tools-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $Check = $false
    $ForceReinstall = $false
    $All = $true
    $Tools = @("TokenOptimizer")
    $UI = $null
    $Command = $null
    $SkipDashboardBuild = $false
    $StateDir = $temp
    $InstalledStatePath = Join-Path $temp "installed.json"
    $ManagedScriptPath = Join-Path $temp "not-installed.ps1"
    $TokenDashboardDir = Join-Path $temp "dashboard"
    $TokenDashboardBuildPath = Join-Path $temp "build.txt"
    New-Item -ItemType Directory -Path (Join-Path $TokenDashboardDir ".git") -Force | Out-Null
    [IO.File]::WriteAllText($InstalledStatePath, '{"selectedTools":["RTK"],"lastRun":"previous","tools":{}}')
    $original = Get-Content $InstalledStatePath -Raw
    $script:Failure = "ci"
    $script:NpmCalls = 0
    $script:ConfigurationFailure = $false
    $script:PreflightFailure = $true

    function Refresh-ProcessPath {}
    function Install-Self {}
    function Read-MainAction { "update" }
    function Resolve-SelectedTools { "TokenOptimizer" }
    function Ensure-Node {}
    function Ensure-Git {}
    function Initialize-InstallPlan {}
    function Test-InstallPrerequisites {
        if ($script:PreflightFailure) { throw "incompatible prerequisites" }
    }
    function Test-Command { $true }
    function Get-TokenInstalledVersion { "1.2.3" }
    function Get-TokenLatestVersion { "1.2.3" }
    function Configure-CopilotMcp {
        if ($script:ConfigurationFailure) { throw "configuration failed" }
    }
    function Configure-CodexIntegration {}
    function Configure-CopilotInstructions {}
    function Show-UiCommands {}
    function git {
        $global:LASTEXITCODE = 0
        if ($args[0] -eq "rev-parse") { "commit-123" }
    }
    function Invoke-External {
        param($Command, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
        if ($Command -ne "npm") { throw "Unexpected command: $Command" }
        $script:NpmCalls++
        New-Item -ItemType Directory -Path (Join-Path $TokenDashboardDir "node_modules") -Force | Out-Null
        if (($script:Failure -eq "ci" -and $Arguments[0] -eq "ci") -or
            ($script:Failure -eq "build" -and $Arguments[0] -eq "run")) {
            throw "npm $($Arguments -join ' ') failed"
        }
    }
    function Assert($Condition, $Message) {
        if (-not $Condition) { throw $Message }
    }
    function Expect-Failure {
        $failed = $false
        try { . $main } catch { $failed = $true }
        Assert $failed "Installation must fail"
        Assert ((Get-Content $InstalledStatePath -Raw) -eq $original) "Failure changed saved installation state"
    }

    $ForceReinstall = $true
    Expect-Failure
    Assert ($script:NpmCalls -eq 0) "Installation started before prerequisite checks passed"
    $ForceReinstall = $false
    $script:PreflightFailure = $false
    Expect-Failure
    Assert (-not (Test-Path $TokenDashboardBuildPath)) "npm ci failure confirmed the build"
    $script:Failure = "build"
    Expect-Failure
    Assert (-not (Test-Path $TokenDashboardBuildPath)) "npm build failure confirmed the build"
    $script:Failure = ""
    $script:ConfigurationFailure = $true
    Expect-Failure
    Assert (Test-Path $TokenDashboardBuildPath) "Successful build was not recorded"
    $script:ConfigurationFailure = $false
    . $main
    $saved = Get-Content $InstalledStatePath -Raw | ConvertFrom-Json
    Assert ($saved.tools.TokenOptimizer.status -eq "up-to-date") "Success did not save tool state"
    $original = Get-Content $InstalledStatePath -Raw
    $calls = $script:NpmCalls
    . $main
    Assert ($script:NpmCalls -eq $calls) "Successful unchanged build ran again"
    $original = Get-Content $InstalledStatePath -Raw
    $ForceReinstall = $true
    $script:Failure = "ci"
    Expect-Failure
    Assert (-not (Test-Path $TokenDashboardBuildPath)) "Failed forced rebuild kept a success record"
    $calls = $script:NpmCalls
    $ForceReinstall = $false
    $script:Failure = ""
    . $main
    Assert ($script:NpmCalls -eq ($calls + 2)) "Normal retry did not run npm ci and npm run build"
    $original = Get-Content $InstalledStatePath -Raw
    $Check = $true
    . $main
    Assert ((Get-Content $InstalledStatePath -Raw) -eq $original) "Diagnostics changed saved state"
    $Check = $false
    $SkipDashboardBuild = $true
    Remove-Item -LiteralPath $TokenDashboardBuildPath
    $calls = $script:NpmCalls
    . $main
    Assert ($script:NpmCalls -eq $calls) "Explicit dashboard skip ran npm"
    Assert (-not (Test-Path $TokenDashboardBuildPath)) "Explicit dashboard skip confirmed a build"
    Write-Host "PowerShell installation regression tests passed."
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}
