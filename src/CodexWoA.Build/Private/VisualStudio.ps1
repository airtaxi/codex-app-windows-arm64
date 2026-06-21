function Get-VsWherePath {
    $candidate = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    $command = Get-Command "vswhere.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    return $null
}

function Get-VisualStudioInstances {
    $vswhere = Get-VsWherePath
    if ($null -eq $vswhere) {
        return @()
    }

    $json = & $vswhere -all -products * -format json
    if ([string]::IsNullOrWhiteSpace(($json -join ""))) {
        return @()
    }

    $instances = $json | ConvertFrom-Json
    if ($null -eq $instances) {
        return @()
    }

    return @($instances | Where-Object { $_.isComplete -eq $true -and $_.installationPath })
}

function Get-InstalledVsComponentIds {
    param([string]$InstallationPath)

    $instanceId = Split-Path -Leaf $InstallationPath
    $instanceDir = Join-Path "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances" $instanceId
    $stateJson = Join-Path $instanceDir "state.json"
    if (Test-Path -LiteralPath $stateJson) {
        try {
            $state = Get-Content -LiteralPath $stateJson -Raw | ConvertFrom-Json
            if ($state.selectedPackages) {
                return @($state.selectedPackages.PSObject.Properties.Name)
            }
        }
        catch {
            Write-Verbose "Could not read Visual Studio state.json: $($_.Exception.Message)"
        }
    }

    return @()
}

function Test-VsComponentInstalled {
    param(
        [string]$ComponentId,
        [string]$InstallationPath
    )

    $vswhere = Get-VsWherePath
    if ($null -eq $vswhere) {
        return $false
    }

    $output = & $vswhere -all -products * -requires $ComponentId -property installationPath
    return @($output) -contains $InstallationPath
}

function Get-VsPlanComponentIds {
    param(
        [string]$InstallationPath,
        [string]$Pattern
    )

    $instancesRoot = "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances"
    if (-not (Test-Path -LiteralPath $instancesRoot)) {
        return @()
    }

    $plans = Get-ChildItem -LiteralPath $instancesRoot -Recurse -File -Filter "plan.xml" -ErrorAction SilentlyContinue
    foreach ($plan in $plans) {
        try {
            [xml]$xml = Get-Content -LiteralPath $plan.FullName -Raw
            $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
            $ns.AddNamespace("s", "http://schemas.datacontract.org/2004/07/Microsoft.VisualStudio.Setup")
            $ids = $xml.SelectNodes("//s:PackagePlan/s:Id", $ns) | ForEach-Object { $_.InnerText }
            $matchedIds = @($ids |
                ForEach-Object { ($_ -split ",")[0] } |
                Where-Object { $_ -match $Pattern } |
                Sort-Object -Unique)
            if ($matchedIds.Count -gt 0) {
                return @($matchedIds)
            }
        }
        catch {
            Write-Verbose "Could not inspect Visual Studio plan $($plan.FullName): $($_.Exception.Message)"
        }
    }

    return @()
}

function Get-Arm64CppComponentIds {
    param(
        [string]$InstallationPath,
        [string]$ToolsetVersion
    )

    $toolsetPrefix = ($ToolsetVersion -split "\.")[0..1] -join "."
    $escapedPrefix = [regex]::Escape($toolsetPrefix)
    $arm64ToolComponents = @(Get-VsPlanComponentIds $InstallationPath "^Microsoft\.VisualStudio\.Component\.VC\.$escapedPrefix\.\d+\.\d+\.ARM64$")
    if ($arm64ToolComponents.Count -gt 0) {
        return @(($arm64ToolComponents | Sort-Object -Descending | Select-Object -First 1))
    }

    return @("Microsoft.VisualStudio.Component.VC.Tools.ARM64")
}

function Find-VisualStudioCppInstance {
    $instances = Get-VisualStudioInstances
    foreach ($instance in ($instances | Sort-Object installationVersion -Descending)) {
        $toolsRoot = Join-Path $instance.installationPath "VC\Tools\MSVC"
        if (-not (Test-Path -LiteralPath $toolsRoot)) {
            continue
        }

        $toolset = Get-ChildItem -LiteralPath $toolsRoot -Directory |
            Sort-Object { [version]$_.Name } -Descending |
            Select-Object -First 1
        if ($null -eq $toolset) {
            continue
        }

        return [pscustomobject][ordered]@{
            installationPath = [string]$instance.installationPath
            displayName = [string]$instance.displayName
            installationVersion = [string]$instance.installationVersion
            toolsetVersion = [string]$toolset.Name
            toolsetPath = [string]$toolset.FullName
        }
    }

    return $null
}

function Test-Arm64CppToolchainFiles {
    param([string]$ToolsetPath)

    $compilerCandidates = @(
        (Join-Path $ToolsetPath "bin\Hostarm64\arm64\cl.exe"),
        (Join-Path $ToolsetPath "bin\Hostx64\arm64\cl.exe"),
        (Join-Path $ToolsetPath "bin\Hostx86\arm64\cl.exe")
    )
    $hasCompiler = $false
    foreach ($candidate in $compilerCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $hasCompiler = $true
            break
        }
    }

    $arm64LibDir = Join-Path $ToolsetPath "lib\arm64"
    $hasArm64Libs = $false
    if (Test-Path -LiteralPath $arm64LibDir) {
        $hasArm64Libs = $null -ne (Get-ChildItem -LiteralPath $arm64LibDir -File -Filter "*.lib" -ErrorAction SilentlyContinue | Select-Object -First 1)
    }

    return ($hasCompiler -and $hasArm64Libs)
}

function Get-VisualStudioDependencyGuidance {
    param(
        [object]$VsInfo,
        [string[]]$ComponentIds
    )

    $componentList = ($ComponentIds | ForEach-Object { "  - $_" }) -join "`n"
    $installCommand = if ($null -ne $VsInfo) {
        $setup = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\setup.exe"
        $addArgs = ($ComponentIds | ForEach-Object { "--add `"$($_)`"" }) -join " "
        "`"$setup`" modify --installPath `"$($VsInfo.installationPath)`" $addArgs --quiet --norestart --wait"
    }
    else {
        "Install Visual Studio 2026/2022 C++ desktop build tools, then add ARM64 C++ tools."
    }

    return @"
Visual Studio ARM64 C++ tools are required before rebuilding native modules.

Install these Visual Studio components:
$componentList

You can either:
  1. Re-run this script with -InstallVsDependencies, or
  2. Open Visual Studio Installer > Modify > Individual components and install ARM64 C++ tools, or
  3. Run this command:
     $installCommand
"@
}

function Install-VisualStudioComponents {
    param(
        [object]$VsInfo,
        [string[]]$ComponentIds
    )

    $setup = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\setup.exe"
    if (-not (Test-Path -LiteralPath $setup)) {
        throw "Visual Studio setup.exe was not found. $([Environment]::NewLine)$(Get-VisualStudioDependencyGuidance $VsInfo $ComponentIds)"
    }

    Write-Step "Installing Visual Studio ARM64 C++ dependencies"
    $arguments = New-Object "System.Collections.Generic.List[string]"
    $arguments.Add("modify") | Out-Null
    $arguments.Add("--installPath") | Out-Null
    $arguments.Add($VsInfo.installationPath) | Out-Null
    foreach ($componentId in $ComponentIds) {
        $arguments.Add("--add") | Out-Null
        $arguments.Add($componentId) | Out-Null
    }
    $arguments.Add("--quiet") | Out-Null
    $arguments.Add("--norestart") | Out-Null

    $exitCode = Invoke-Checked $setup ([string[]]$arguments) @(0, 3010)
    if ($exitCode -eq 3010) {
        Write-Warn "Visual Studio Installer requested a restart. If native module rebuild still fails, reboot Windows and rerun this script."
    }
}

function Ensure-VisualStudioArm64Tools {
    if ($SkipVsDependencyCheck) {
        Write-Warn "Skipping Visual Studio dependency preflight because -SkipVsDependencyCheck was provided."
        return
    }

    Write-Step "Checking Visual Studio ARM64 C++ toolchain"
    $vsInfo = Find-VisualStudioCppInstance
    if ($null -eq $vsInfo) {
        throw (Get-VisualStudioDependencyGuidance $null @(
            "Microsoft.VisualStudio.Workload.VCTools",
            "Microsoft.VisualStudio.Component.VC.Tools.ARM64"
        ))
    }

    $arm64ToolComponents = @(Get-Arm64CppComponentIds $vsInfo.installationPath $vsInfo.toolsetVersion)
    $toolchainFilesPresent = Test-Arm64CppToolchainFiles $vsInfo.toolsetPath
    $detectedMissingComponents = @($arm64ToolComponents | Where-Object { -not (Test-VsComponentInstalled $_ $vsInfo.installationPath) })
    $missingComponents = if ($toolchainFilesPresent) { @() } else { @($detectedMissingComponents) }

    $script:Context.Report.visualStudio = [ordered]@{
        displayName = $vsInfo.displayName
        installationPath = $vsInfo.installationPath
        installationVersion = $vsInfo.installationVersion
        toolsetVersion = $vsInfo.toolsetVersion
        requiredComponents = @($arm64ToolComponents)
        missingComponents = @($missingComponents)
        arm64ToolchainFilesPresent = $toolchainFilesPresent
        nodePtySpectreMitigation = "disabled in node-pty gyp before ARM64 rebuild"
    }

    if ($toolchainFilesPresent) {
        return
    }

    if ($InstallVsDependencies) {
        Install-VisualStudioComponents $vsInfo $arm64ToolComponents
        $toolchainFilesPresent = Test-Arm64CppToolchainFiles $vsInfo.toolsetPath
        $detectedMissingComponents = @($arm64ToolComponents | Where-Object { -not (Test-VsComponentInstalled $_ $vsInfo.installationPath) })
        $missingComponents = if ($toolchainFilesPresent) { @() } else { @($detectedMissingComponents) }
        $script:Context.Report.visualStudio.missingComponents = @($missingComponents)
        $script:Context.Report.visualStudio.arm64ToolchainFilesPresent = $toolchainFilesPresent
        if ($toolchainFilesPresent) {
            return
        }
    }

    throw @"
Visual Studio ARM64 C++ tools are required before rebuilding native modules.

Install this Visual Studio component:
  - $($arm64ToolComponents -join "`n  - ")

You can re-run this script with -InstallVsDependencies, or install ARM64 C++ tools from Visual Studio Installer > Modify > Individual components.
"@
}
