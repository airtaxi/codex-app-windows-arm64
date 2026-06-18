function Enable-ChromeExtensionHostX64Fallback {
    param([string]$ResourcesDir)

    $chromePluginDir = Join-Path $ResourcesDir "plugins\openai-bundled\plugins\chrome"
    if (-not (Test-Path -LiteralPath $chromePluginDir)) {
        return
    }

    $arm64HostDir = Join-Path $chromePluginDir "extension-host\windows\arm64"
    $arm64Host = Join-Path $arm64HostDir "extension-host.exe"
    if (Test-Path -LiteralPath $arm64Host) {
        return
    }

    $x64Host = Join-Path $chromePluginDir "extension-host\windows\x64\extension-host.exe"
    if (-not (Test-Path -LiteralPath $x64Host)) {
        return
    }

    New-Item -ItemType Directory -Path $arm64HostDir -Force | Out-Null
    Copy-Item -LiteralPath $x64Host -Destination $arm64Host -Force

    Write-Warn "Chrome extension native messaging host is not native ARM64; copied the bundled x64 host into the ARM64 path for Windows on ARM x64 emulation."
    Add-Replacement "chrome-extension-host" "x64-emulated-arm64-path" "copied bundled x64 extension-host.exe to extension-host\windows\arm64; no installManifest.mjs patch"
}

function Get-PluginClassicLevelPackageDirs {
    param([string]$ResourcesDir)

    $bundledRoot = Join-Path $ResourcesDir "plugins\openai-bundled"
    if (-not (Test-Path -LiteralPath $bundledRoot)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $bundledRoot -Recurse -Directory -Filter "classic-level" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\node_modules\\classic-level$" })
}

function Prune-PluginClassicLevelNonArm64WindowsPrebuilds {
    param([string]$ResourcesDir)

    $removed = New-Object "System.Collections.Generic.List[string]"
    $classicLevelDirs = @(Get-PluginClassicLevelPackageDirs $ResourcesDir)
    foreach ($classicLevelDir in $classicLevelDirs) {
        $prebuildRootPath = Join-Path $classicLevelDir.FullName "prebuilds"
        if (-not (Test-Path -LiteralPath $prebuildRootPath)) {
            continue
        }

        $windowsPrebuilds = @(Get-ChildItem -LiteralPath $prebuildRootPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "win32-*" -and $_.Name -ne "win32-arm64" })
        foreach ($windowsPrebuild in $windowsPrebuilds) {
            $removed.Add((Get-RelativePath $ResourcesDir $windowsPrebuild.FullName)) | Out-Null
            Remove-Item -LiteralPath $windowsPrebuild.FullName -Recurse -Force
        }
    }

    if ($removed.Count -gt 0) {
        Add-Replacement "classic-level-non-arm64-windows-prebuilds" "pruned" ($removed -join ", ")
    }
}

function Rebuild-PluginClassicLevelArm64NativeModules {
    param([string]$ResourcesDir)

    Require-CommandPath "node" | Out-Null
    Require-CommandPath "pnpm" | Out-Null

    $rebuilt = New-Object "System.Collections.Generic.List[string]"
    $classicLevelDirs = @(Get-PluginClassicLevelPackageDirs $ResourcesDir)
    foreach ($classicLevelDir in $classicLevelDirs) {
        Push-Location $classicLevelDir.FullName
        try {
            Invoke-WithNodeGypLtoEnvironment {
                Invoke-Checked "pnpm" @(
                    "dlx",
                    "node-gyp@$($script:Context.Tools.NodeGyp)",
                    "rebuild",
                    "--arch=arm64"
                )
            }
        }
        finally {
            Pop-Location
        }

        $builtNode = Join-Path $classicLevelDir.FullName "build\Release\classic_level.node"
        if (-not (Test-Path -LiteralPath $builtNode)) {
            throw "classic-level ARM64 build output was not found: $builtNode"
        }

        if ((Get-PeMachine $builtNode) -ne "arm64") {
            throw "classic-level build did not produce an ARM64 binary: $builtNode"
        }

        $rebuilt.Add((Get-RelativePath $ResourcesDir $classicLevelDir.FullName)) | Out-Null
    }

    if ($rebuilt.Count -gt 0) {
        Add-Replacement "classic-level" "arm64" ($rebuilt -join ", ")
    }
}

function Enable-ComputerUseX64Fallback {
    param([string]$ResourcesDir)

    $computerUseHelperCandidates = @(
        (Join-Path $ResourcesDir "cua_node\bin\node_modules\@oai\sky\bin\windows\codex-computer-use.exe")
    )

    foreach ($helperPath in $computerUseHelperCandidates) {
        if (-not (Test-Path -LiteralPath $helperPath)) {
            continue
        }

        $machine = Get-PeMachine $helperPath
        if ($machine -eq "arm64") {
            Add-Replacement "computer-use-helper" "arm64" (Get-RelativePath $ResourcesDir $helperPath)
            return
        }

        if ($machine -eq "x64") {
            Write-Warn "Computer Use helper is not native ARM64; keeping the bundled x64 helper for Windows on ARM x64 emulation."
            Add-Replacement "computer-use-helper" "x64-emulated" (Get-RelativePath $ResourcesDir $helperPath)
            return
        }
    }
}
