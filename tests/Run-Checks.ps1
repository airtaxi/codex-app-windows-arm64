#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$InstallDependencies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleRoot = Join-Path $repoRoot ".tools\PowerShellModules"
$requiredModules = [ordered]@{
    Pester = "5.6.1"
    PSScriptAnalyzer = "1.22.0"
}

if ($InstallDependencies) {
    New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
    foreach ($entry in $requiredModules.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot "$($entry.Key)\$($entry.Value)"))) {
            Save-Module -Name $entry.Key -RequiredVersion $entry.Value -Path $moduleRoot -Repository PSGallery
        }
    }
}

$env:PSModulePath = "$moduleRoot$([IO.Path]::PathSeparator)$env:PSModulePath"
foreach ($entry in $requiredModules.GetEnumerator()) {
    $available = Get-Module -ListAvailable -Name $entry.Key |
        Where-Object { $_.Version -eq [version]$entry.Value } |
        Select-Object -First 1
    if ($null -eq $available) {
        throw "Required module $($entry.Key) $($entry.Value) is unavailable. Run tests\Run-Checks.ps1 -InstallDependencies."
    }
    Import-Module $available.Path -Force
}

Write-Host "Parsing PowerShell files..."
$parseErrors = New-Object System.Collections.Generic.List[object]
Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
    Where-Object {
        $_.Extension -in @(".ps1", ".psm1", ".psd1") -and
        $_.FullName -notlike "$moduleRoot*" -and
        $_.FullName -notlike "$(Join-Path $repoRoot 'dist')*" -and
        $_.FullName -notlike "$(Join-Path $repoRoot 'build')*"
    } |
    ForEach-Object {
        $tokens = $null
        $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        foreach ($parseError in $errors) {
            $parseErrors.Add($parseError)
        }
    }
if ($parseErrors.Count -gt 0) {
    $parseErrors | Format-List | Out-Host
    throw "PowerShell parser checks failed."
}

Write-Host "Running PSScriptAnalyzer..."
$analysisPaths = @(
    (Join-Path $repoRoot "Build-CodexWoA.ps1"),
    (Join-Path $repoRoot "scripts"),
    (Join-Path $repoRoot "tests")
)
$srcPath = Join-Path $repoRoot "src"
if (Test-Path -LiteralPath $srcPath) {
    $analysisPaths += $srcPath
}
$analysis = @($analysisPaths | ForEach-Object {
    Invoke-ScriptAnalyzer -Path $_ -Recurse -Settings (Join-Path $repoRoot "PSScriptAnalyzerSettings.psd1")
})
if ($analysis.Count -gt 0) {
    $analysis | Format-Table -AutoSize | Out-Host
    throw "PSScriptAnalyzer reported $($analysis.Count) issue(s)."
}

Write-Host "Checking JavaScript tools..."
$node = Get-Command "node" -ErrorAction SilentlyContinue
if ($null -eq $node) {
    throw "Required command not found: node"
}
Get-ChildItem -LiteralPath (Join-Path $repoRoot "src") -Recurse -File -Filter "*.js" -ErrorAction SilentlyContinue |
    ForEach-Object {
        & $node.Source --check $_.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "node --check failed for $($_.FullName)"
        }
    }

Write-Host "Running Pester..."
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $repoRoot "tests\Unit"
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = "Detailed"
$result = Invoke-Pester -Configuration $configuration
if ($result.Result -ne "Passed") {
    throw "Pester did not pass. Result: $($result.Result); failed tests: $($result.FailedCount); failed containers: $($result.FailedContainersCount)."
}

Write-Host "All fast checks passed." -ForegroundColor Green
