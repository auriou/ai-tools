$ErrorActionPreference = "Stop"
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "ai-tools.ps1"
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
$uninstall = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Uninstall-Tools" }, $true)
Invoke-Expression $uninstall.Extent.Text

$temp = Join-Path ([IO.Path]::GetTempPath()) ("ai-tools-uninstall-" + [guid]::NewGuid())
$bin = Join-Path $temp "bin"
New-Item -ItemType Directory -Path $bin -Force | Out-Null
$TokenPackage = "@ooples/token-optimizer-mcp"
$SerenaTool = "serena-agent"
$RtkExe = Join-Path $bin "rtk.exe"
$CbmExe = Join-Path $bin "codebase-memory-mcp.exe"
$script:commands = @()
$script:failNpm = $false
$script:confirmed = $true
$script:saves = 0
$script:state = @{
    selectedTools = @("RTK", "TokenOptimizer", "Serena", "CodebaseMemory")
    tools = @{ RTK = @{}; TokenOptimizer = @{}; Serena = @{}; CodebaseMemory = @{} }
}
function Write-Warn2($Text) {}
function Write-Fail($Text) {}
function Write-OK($Text) {}
function Read-YesNo($Question, $DefaultYes) { return $script:confirmed }
function Load-State { return $script:state }
function Ensure-AiDirectories {}
function Save-State($State) { $script:saves++ }
function Test-Command($Name) { return $true }
function uv { $global:LASTEXITCODE = 0; return "serena-agent v1.0.0" }
function Invoke-External {
    param([string]$Command, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    $script:commands += "$Command $($Arguments -join ' ')"
    if ($Command -eq "npm" -and $script:failNpm) { throw "npm failed" }
}

$script:confirmed = $false
Uninstall-Tools @("RTK")
if ($script:saves -ne 0) { throw "Cancellation modified state." }

$script:confirmed = $true
$script:failNpm = $true
New-Item -ItemType File -Path $RtkExe, $CbmExe -Force | Out-Null
$failed = $false
try { Uninstall-Tools @("RTK", "TokenOptimizer", "Serena", "CodebaseMemory") } catch { $failed = $true }
if (-not $failed -or $script:saves -ne 3) { throw "Partial failure was not reported or saved." }
if (($script:state.selectedTools -join ',') -ne "TokenOptimizer") { throw "Unexpected remaining selection." }
if ((Test-Path $RtkExe) -or (Test-Path $CbmExe)) { throw "Managed executables were not removed." }
if ($script:commands -notcontains "uv tool uninstall serena-agent") { throw "Serena was not uninstalled." }

$script:failNpm = $false
Uninstall-Tools @("TokenOptimizer")
if ($script:state.selectedTools.Count -ne 0 -or $script:state.tools.Count -ne 0) { throw "Successful uninstall did not clear state." }
Write-Host "PowerShell uninstall tests passed."
Remove-Item -LiteralPath $temp -Recurse -Force