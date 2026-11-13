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
function Assert($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}
function Expect-Failure([scriptblock]$Action, [string]$Message) {
    $failure = $null
    try { & $Action } catch { $failure = $_.Exception.Message }
    Assert ($failure -and $failure.Contains($Message)) "Expected failure containing '$Message', got '$failure'"
}

$TokenPackage = "@ooples/token-optimizer-mcp"
$SerenaPypi = "https://pypi.org/pypi/serena-agent/json"
$RtkApiLatest = "rtk-release"
$CbmApiLatest = "cbm-release"
$CbmInstallerUrl = "https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1"
$SkipDashboardBuild = $false
$SkipPrerequisiteInstall = $true
$script:Version = "8.2.3"
$script:MissingAsset = $false
$script:MissingPythonRequirement = $false
$script:NpmFailure = $false
$script:PythonMissing = $false
$script:Calls = @()
$script:MetadataCalls = 0

function Get-InstallArchitecture { "amd64" }
function Get-GitHubLatestRelease($Url) {
    $script:MetadataCalls++
    $names = if ($Url -eq $RtkApiLatest) { @("rtk-x86_64-pc-windows-msvc.zip") } else { @("codebase-memory-mcp-windows-amd64.zip","checksums.txt") }
    $assets = @()
    if (-not $script:MissingAsset) {
        $assets = @($names | ForEach-Object { [pscustomobject]@{ name = $_; browser_download_url = "https://example.invalid/$_" } })
    }
    [pscustomobject]@{ tag_name = "v$script:Version"; assets = $assets }
}
function Invoke-RestMethod($Uri) {
    $script:MetadataCalls++
    if ($Uri -eq $SerenaPypi) {
        $requires = if ($script:MissingPythonRequirement) { "" } else { ">=3.12,<3.14" }
        return [pscustomobject]@{ info = [pscustomobject]@{ version = $script:Version; requires_python = $requires } }
    }
    [pscustomobject]@{ version = $script:Version; engines = [pscustomobject]@{ node = ">=24.5 <25"; npm = "^11.2" } }
}
function Ensure-Node {}
function Ensure-Git {}
function Ensure-Uv {}
function Test-Command { $true }
function node { "v24.5.0" }
function npm { "11.2.0" }
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $Headers)
    $script:Calls += "download $Uri"
    [IO.File]::WriteAllText($OutFile, "{}")
}
function Invoke-External {
    param($Command, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    $script:Calls += "$Command $($Arguments -join ' ')"
    if ($Command -eq "npm" -and $script:NpmFailure) { throw "EBADENGINE" }
    if ($Command -eq "uv" -and $Arguments[0] -eq "python") { $script:PythonMissing = $false }
}
function uv {
    $script:Calls += "uv $($args -join ' ')"
    $global:LASTEXITCODE = if ($script:PythonMissing) { 1 } else { 0 }
    if ($script:PythonMissing) { Write-Error "No compatible interpreter" } else { "C:\python-compatible\python.exe" }
}

Initialize-InstallPlan @("RTK","TokenOptimizer","Serena","CodebaseMemory")
$script:Version = "9.0.0"
Assert ((Get-TokenLatestVersion) -eq "8.2.3") "Token Optimizer target changed after planning"
Assert ((Get-SerenaLatestVersion) -eq "8.2.3") "Serena target changed after planning"
Assert ((Get-CbmLatestVersion) -eq "8.2.3") "Codebase Memory target changed after planning"
Assert ($script:MetadataCalls -eq 4) "Targets were queried again"

$help = (Show-RequiredPrerequisites @("TokenOptimizer","Serena") 6>&1 | Out-String)
Assert ($help.Contains("Node.js: >=24.5 <25")) "Node installation guidance lost the published version range"
Assert ($help.Contains('npm install --global "npm@^11.2"')) "npm guidance must quote and use the published range"
Assert ($help.Contains("winget install -e --id Git.Git")) "Dashboard guidance must explain how to install Git"
Assert ($help.Contains('uv python install ">=3.12,<3.14"')) "Python guidance must quote and use the published range"
$SkipDashboardBuild = $true
$help = (Show-RequiredPrerequisites @("TokenOptimizer") 6>&1 | Out-String)
Assert (-not $help.Contains("Git.Git") -and -not $help.Contains("uv python")) "Guidance recommended prerequisites for unselected features"
$SkipDashboardBuild = $false

$Check = $true
function Get-RtkInstalledVersion { "8.2.3" }
$state = New-DefaultState
Install-OrUpdate-Rtk $state
Assert ($state.tools.RTK.latest -eq "8.2.3") "RTK did not reuse the planned release"
Assert ($script:MetadataCalls -eq 4) "RTK queried a new release after planning"
$Check = $false

Test-InstallPrerequisites @("TokenOptimizer","Serena")
Assert ([bool]($script:Calls -like "npm install *--dry-run*--ignore-scripts*--engine-strict*--force=false *@8.2.3")) "npm preflight is not strict, script-free, and pinned"
Assert ([bool]($script:Calls -like "npm ci *--dry-run*--ignore-scripts*--engine-strict*")) "Dashboard dependencies were not checked"
Assert ([bool]($script:Calls -like "download */v8.2.3/package-lock.json")) "Dashboard preflight used a different release"
Assert ([bool]($script:Calls -like "uv python find *>=3.12,<3.14")) "Python requirements were hardcoded instead of read from metadata"
Assert ($SerenaPython -eq "C:\python-compatible\python.exe") "Compatible Python was not retained"

$script:NpmFailure = $true
Expect-Failure { Test-InstallPrerequisites @("TokenOptimizer") } "prerequisite check failed"
$script:NpmFailure = $false
$script:PythonMissing = $true
Expect-Failure { Test-InstallPrerequisites @("Serena") } "No Python matching"
$SkipPrerequisiteInstall = $false
Test-InstallPrerequisites @("Serena")
Assert ([bool]($script:Calls -like "uv python install >=3.12,<3.14")) "Compatible Python was not provisioned when allowed"

function Set-Acl {}
function powershell.exe {
    $script:Calls += "installer $env:CBM_DOWNLOAD_URL"
    $global:LASTEXITCODE = 0
}
$previousDownloadUrl = $env:CBM_DOWNLOAD_URL
Install-CbmOfficial
Assert ([bool]($script:Calls -like "download */v8.2.3/install.ps1")) "Codebase Memory downloaded an unchecked installer"
Assert ([bool]($script:Calls -like "installer */releases/download/v8.2.3")) "Codebase Memory did not pin the archive version"
Assert ($env:CBM_DOWNLOAD_URL -eq $previousDownloadUrl) "Codebase Memory leaked its download override"

$script:MissingAsset = $true
Expect-Failure { Initialize-InstallPlan @("RTK") } "no asset"
$script:MissingAsset = $false
$script:MissingPythonRequirement = $true
Expect-Failure { Initialize-InstallPlan @("Serena") } "missing its version or Python requirements"
Write-Host "PowerShell prerequisite regression tests passed."
