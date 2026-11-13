$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$sourceScript = Join-Path $root "ai-tools.ps1"
$managerVersion = Select-String -LiteralPath $sourceScript -Pattern '^\$AiToolsVersion = "([0-9]+(?:\.[0-9]+)*)"' |
    Select-Object -First 1
if (-not $managerVersion) { throw "Manager version was not found." }
$version = $managerVersion.Matches[0].Groups[1].Value
$temp = Join-Path ([IO.Path]::GetTempPath()) ("ai-tools-bootstrap-" + [guid]::NewGuid())
$profile = Join-Path $temp "profile"
$bin = Join-Path $profile ".ai-tools\bin"
$managedScript = Join-Path $bin "ai-tools.ps1"
$marker = Join-Path $profile "forwarded.txt"
$wrapper = Join-Path $temp "invoke.ps1"
New-Item -ItemType Directory -Path $bin -Force | Out-Null

$manager = @"
param([switch]`$ForceReinstall,[switch]`$Check,[string[]]`$Tools)
`$AiToolsVersion = "$version"
[IO.File]::WriteAllText("$marker", "`$(`$ForceReinstall.IsPresent)|`$(`$Check.IsPresent)|`$(`$Tools -join ',')")
"@
[IO.File]::WriteAllText($managedScript, $manager)
$invoker = @"
`$env:USERPROFILE = '$profile'
`$env:APPDATA = '$(Join-Path $profile "AppData\Roaming")'
`$env:LOCALAPPDATA = '$(Join-Path $profile "AppData\Local")'
& '$sourceScript' @args
exit `$LASTEXITCODE
"@
[IO.File]::WriteAllText($wrapper, $invoker)

try {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh).Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add("-NoProfile")
    $startInfo.ArgumentList.Add("-File")
    $startInfo.ArgumentList.Add($wrapper)
    $startInfo.ArgumentList.Add("-ForceReinstall")
    $startInfo.ArgumentList.Add("-Tools")
    $startInfo.ArgumentList.Add("RTK")
    $startInfo.Environment["USERPROFILE"] = $profile
    $startInfo.Environment["APPDATA"] = Join-Path $profile "AppData\Roaming"
    $startInfo.Environment["LOCALAPPDATA"] = Join-Path $profile "AppData\Local"

    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Downloaded manager failed: $stdout`n$stderr" }
    if (-not (Test-Path $marker) -or (Get-Content $marker -Raw) -ne "True|False|RTK") {
        throw "Explicit force-reinstall options were not forwarded to the installed manager."
    }
    Write-Host "PowerShell manager bootstrap tests passed."
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
