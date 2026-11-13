$previousErrorActionPreference = $ErrorActionPreference
$previousPath = $env:PATH
$previousLastExitCode = $global:LASTEXITCODE
$fixtureRoot = Join-Path $PSScriptRoot (".rea-fixtures-" + [guid]::NewGuid().ToString("N"))

try {
    $ErrorActionPreference = "Stop"
    & {
        $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "ai-tools.ps1"
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "ai-tools.ps1 has syntax errors: $parseErrors" }
        foreach ($name in @("Set-McpServerEntry", "Move-McpServerEntry", "Set-McpServersInFile", "Configure-CopilotMcp", "Install-OrUpdate-Rea")) {
            $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            if (-not $function) { throw "Function not found: $name" }
            . ([scriptblock]::Create($function.Extent.Text))
        }

        function Write-Info($Text) {}
        function Write-Warn2($Text) {}
        function Write-Section($Text) {}
        function Write-OK($Text) {}
        function Assert-Throws([scriptblock]$Action, [string]$Message) {
            $caught = $false
            try { & $Action } catch {
                if ($_.Exception.Message -notlike "*$Message*") { throw }
                $caught = $true
            }
            if (-not $caught) { throw "Expected error containing: $Message" }
        }
        function Get-FixtureSnapshot {
            @(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
                "$($_.FullName)|$($_.LastWriteTimeUtc.Ticks)|$((Get-FileHash -LiteralPath $_.FullName).Hash)"
            }) -join "`n"
        }
        function Assert-ReadOnly([scriptblock]$Action) {
            $before = Get-FixtureSnapshot
            & $Action
            if ((Get-FixtureSnapshot) -cne $before) { throw "Operation changed fixture files or created a backup." }
        }
        function New-Config([object]$Config) {
            $path = Join-Path $fixtureRoot ([guid]::NewGuid().ToString("N") + ".json")
            [IO.File]::WriteAllText($path, ($Config | ConvertTo-Json -Depth 30))
            return $path
        }
        function New-ReaEntry {
            return @{ type = "stdio"; command = $ReaExe; args = @("mcp") }
        }

        New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
        $ReaPrefix = Join-Path $fixtureRoot "bin"
        New-Item -ItemType Directory -Path $ReaPrefix | Out-Null
        $ReaExe = Join-Path $ReaPrefix "rea.cmd"
        [IO.File]::WriteAllText($ReaExe, "fixture only; never executed")
        $Check = $false
        $ForceReinstall = $false
        $ReaPackage = "fixture-rea"

        $CopilotMcpConfigPath = New-Config @{
            keep = @{ enabled = $true }
            mcpServers = @{ unrelated = @{ command = "untouched"; args = @("one", "two") }; rea = @{ command = "old" } }
        }
        function Get-CopilotMcpTargets { return @($CopilotMcpConfigPath) }
        $original = [IO.File]::ReadAllText($CopilotMcpConfigPath)
        Configure-CopilotMcp @("REA")
        $registered = Get-Content -LiteralPath $CopilotMcpConfigPath -Raw | ConvertFrom-Json
        if ($registered.mcpServers.rea.type -cne "stdio" -or $registered.mcpServers.rea.command -cne $ReaExe -or
            $registered.mcpServers.rea.args.Count -ne 1 -or $registered.mcpServers.rea.args[0] -cne "mcp") {
            throw "REA-only selection did not register the expected MCP entry."
        }
        if (-not $registered.keep.enabled -or $registered.mcpServers.unrelated.command -cne "untouched" -or
            ($registered.mcpServers.unrelated.args -join ",") -cne "one,two") { throw "Unrelated configuration was changed." }
        $backups = @(Get-ChildItem -Path "$CopilotMcpConfigPath.backup.*")
        if ($backups.Count -ne 1 -or [IO.File]::ReadAllText($backups[0].FullName) -cne $original) { throw "Original configuration was not backed up." }

        $Check = $true
        Assert-ReadOnly { Configure-CopilotMcp @("REA") }
        $missingPath = Join-Path $fixtureRoot "missing/config.json"
        Assert-ReadOnly { Assert-Throws { Set-McpServersInFile $missingPath @("REA") } "missing or stale" }
        if (Test-Path (Split-Path $missingPath -Parent)) { throw "Check created a directory." }
        foreach ($config in @(@{}, @{ mcpServers = @{ unrelated = @{ command = "untouched" } } })) {
            $path = New-Config $config
            Assert-ReadOnly { Assert-Throws { Set-McpServersInFile $path @("REA") } "missing or stale" }
        }
        foreach ($field in @("type", "command", "args", "extraArgs", "scalarArgs")) {
            $entry = New-ReaEntry
            switch ($field) {
                "type" { $entry.type = "http" }
                "command" { $entry.command = "old-rea" }
                "args" { $entry.args = @("setup") }
                "extraArgs" { $entry.args = @("mcp", "extra") }
                "scalarArgs" { $entry.args = "mcp" }
            }
            $path = New-Config @{ mcpServers = @{ rea = $entry } }
            Assert-ReadOnly { Assert-Throws { Set-McpServersInFile $path @("REA") } "missing or stale" }
        }

        $invalidPath = Join-Path $fixtureRoot "invalid.json"
        [IO.File]::WriteAllText($invalidPath, "{invalid")
        foreach ($checkMode in @($true, $false)) {
            $Check = $checkMode
            Assert-ReadOnly { Assert-Throws { Set-McpServersInFile $invalidPath @("REA") } "Cannot parse" }
            foreach ($invalidConfig in @("null", "[]", '{"mcpServers":null}')) {
                [IO.File]::WriteAllText($invalidPath, $invalidConfig)
                Assert-ReadOnly { Assert-Throws { Set-McpServersInFile $invalidPath @("REA") } "Invalid REA" }
            }
            [IO.File]::WriteAllText($invalidPath, "{invalid")
        }
        Remove-Item -LiteralPath $ReaExe
        $Check = $true
        Assert-ReadOnly { Set-McpServersInFile $CopilotMcpConfigPath @("REA") }
        $Check = $false
        Assert-ReadOnly { Assert-Throws { Set-McpServersInFile $CopilotMcpConfigPath @("REA") } "executable not found" }
        Assert-ReadOnly { Assert-Throws { Set-McpServersInFile $missingPath @("REA") } "executable not found" }
        if (Test-Path (Split-Path $missingPath -Parent)) { throw "Missing executable created a directory." }

        [IO.File]::WriteAllText($ReaExe, "fixture only; never executed")
        $calls = [System.Collections.Generic.List[string]]::new()
        function Test-Command($Name) { return $Name -eq "npm" }
        function npm { $global:LASTEXITCODE = 0; return "1.0.0" }
        function Normalize-Version($Version) { return $Version }
        function Compare-VersionText($Installed, $Latest) { return $Installed -eq $Latest }
        function Get-ReaInstalledVersion { return "1.0.0" }
        function Ensure-Node { $calls.Add("ensure-node") }
        function Test-ReaNodeVersion { return $true }
        function Add-UserPath($Path) { $calls.Add("add-path") }
        function Set-ToolState {}
        function Invoke-External {
            param([string]$Command, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
            $calls.Add("$Command $($Arguments -join ' ')")
        }
        $Check = $false
        Install-OrUpdate-Rea @{}
        $expectedSetup = "$ReaExe setup --client codex"
        if (@($calls | Where-Object { $_ -ceq $expectedSetup }).Count -ne 1 -or
            @($calls | Where-Object { $_ -like "npm install*" }).Count -ne 0) { throw "Same-version setup was not invoked without reinstalling." }
        $calls.Clear()
        $Check = $true
        Assert-ReadOnly { Install-OrUpdate-Rea @{} }
        if ($calls.Count) { throw "Check attempted prerequisite installation, PATH changes, or setup." }
        Write-Host "PowerShell REA integration tests passed."
    }
} finally {
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    $env:PATH = $previousPath
    $global:LASTEXITCODE = $previousLastExitCode
    $ErrorActionPreference = $previousErrorActionPreference
}
