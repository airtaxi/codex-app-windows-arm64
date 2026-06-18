function Get-NpmPackageVersion {
    param(
        [string]$AsarDir,
        [string]$PackageName
    )

    $packageJson = Join-Path $AsarDir (Join-Path "node_modules\$PackageName" "package.json")
    if (-not (Test-Path -LiteralPath $packageJson)) {
        $rootPackageJson = Join-Path $AsarDir "package.json"
        $rootPackage = Get-Content -LiteralPath $rootPackageJson -Raw | ConvertFrom-Json
        $property = $rootPackage.dependencies.PSObject.Properties[$PackageName]
        $range = if ($null -ne $property) { [string]$property.Value } else { "" }
        if ([string]::IsNullOrWhiteSpace($range)) {
            throw "Could not find dependency version for $PackageName"
        }
        return $range
    }

    $package = Get-Content -LiteralPath $packageJson -Raw | ConvertFrom-Json
    return [string]$package.version
}

function Patch-BetterSqlite3ForElectron42 {
    param(
        [string]$PackageDir,
        [string]$ElectronVersion
    )

    $electronMajor = [int]($ElectronVersion.Split(".")[0])
    if ($electronMajor -lt 42) {
        return
    }

    $sourceDir = Join-Path $PackageDir "src"
    if (-not (Test-Path -LiteralPath $sourceDir)) {
        throw "better-sqlite3 source directory was not found: $sourceDir"
    }

    $mainSource = Join-Path $sourceDir "better_sqlite3.cpp"
    $macrosSource = Join-Path $sourceDir "util\macros.cpp"
    $helpersSource = Join-Path $sourceDir "util\helpers.cpp"

    $main = Get-Content -LiteralPath $mainSource -Raw
    $macros = Get-Content -LiteralPath $macrosSource -Raw
    $helpers = Get-Content -LiteralPath $helpersSource -Raw

    $needsFrameAddressShim = $main -notmatch "__builtin_frame_address"
    $needsExternalNewPatch = $main.Contains("v8::Local<v8::External> data = v8::External::New(isolate, addon);")
    $needsExternalValuePatch = $macros.Contains("static_cast<Addon*>(info.Data().As<v8::External>()->Value())")
    $needsNativeDataPropertyPatch = $helpers -match "func,\r?\n\s*0,\r?\n\s*data"

    if (-not ($needsFrameAddressShim -or $needsExternalNewPatch -or $needsExternalValuePatch -or $needsNativeDataPropertyPatch)) {
        return
    }

    if ($needsFrameAddressShim) {
        $main = $main -replace "#include <climits>", @"
#if defined(_MSC_VER) && !defined(__clang__) && !defined(__builtin_frame_address)
#include <intrin.h>
#define __builtin_frame_address(level) _AddressOfReturnAddress()
#endif

#include <climits>
"@
    }
    if ($needsExternalNewPatch) {
        $main = $main.Replace(
            "v8::Local<v8::External> data = v8::External::New(isolate, addon);",
            "v8::Local<v8::External> data = V8_EXTERNAL_NEW(isolate, addon);")
    }
    Set-TextUtf8NoBom $mainSource $main

    if (($needsExternalNewPatch -or $needsExternalValuePatch) -and $macros -notmatch "V8_EXTERNAL_POINTER_TAG") {
        $macros = $macros.Replace(
            "#define EasyIsolate v8::Isolate* isolate = v8::Isolate::GetCurrent()",
            @"
#if defined(V8_MAJOR_VERSION) && V8_MAJOR_VERSION >= 14
#define V8_EXTERNAL_POINTER_TAG v8::kExternalPointerTypeTagDefault
#define V8_EXTERNAL_NEW(isolate, value) v8::External::New((isolate), (value), V8_EXTERNAL_POINTER_TAG)
#define V8_EXTERNAL_VALUE(external) (external)->Value(V8_EXTERNAL_POINTER_TAG)
#else
#define V8_EXTERNAL_NEW(isolate, value) v8::External::New((isolate), (value))
#define V8_EXTERNAL_VALUE(external) (external)->Value()
#endif

#define EasyIsolate v8::Isolate* isolate = v8::Isolate::GetCurrent()
"@)
    }
    if ($needsExternalValuePatch) {
        $macros = $macros.Replace(
            "static_cast<Addon*>(info.Data().As<v8::External>()->Value())",
            "static_cast<Addon*>(V8_EXTERNAL_VALUE(info.Data().As<v8::External>()))")
    }
    Set-TextUtf8NoBom $macrosSource $macros

    if ($needsNativeDataPropertyPatch) {
        $helpers = $helpers -replace "(func,\r?\n\s*)0(,\r?\n\s*data)", '${1}nullptr${2}'
        Set-TextUtf8NoBom $helpersSource $helpers
    }

    Add-Replacement "better-sqlite3-source" "patched" "Electron 42 V8 API compatibility"
}

function Disable-NodePtySpectreMitigation {
    param([string]$NodePtyDir)

    if (-not (Test-Path -LiteralPath $NodePtyDir)) {
        throw "node-pty directory was not found: $NodePtyDir"
    }

    $patchedFiles = New-Object "System.Collections.Generic.List[string]"
    $targets = @(
        (Join-Path $NodePtyDir "binding.gyp"),
        (Join-Path $NodePtyDir "deps\winpty\src\winpty.gyp")
    )

    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target)) {
            continue
        }

        $before = Get-Content -LiteralPath $target -Raw
        $after = $before -replace "(?m)^\s*'SpectreMitigation'\s*:\s*'Spectre'\s*,?\r?\n", ""
        if ($after -ne $before) {
            Set-TextUtf8NoBom $target $after
            $patchedFiles.Add((Get-RelativePath $NodePtyDir $target)) | Out-Null
        }
    }

    if ($patchedFiles.Count -gt 0) {
        Add-Replacement "node-pty-spectre-mitigation" "disabled" ($patchedFiles -join ", ")
    }
}

function Prune-NodePtyNonArm64Payloads {
    param([string]$NodePtyDir)

    if (-not (Test-Path -LiteralPath $NodePtyDir)) {
        throw "node-pty directory was not found: $NodePtyDir"
    }

    $removed = New-Object "System.Collections.Generic.List[string]"

    $prebuildsRoot = Join-Path $NodePtyDir "prebuilds"
    if (Test-Path -LiteralPath $prebuildsRoot) {
        $prebuildDirs = @(Get-ChildItem -LiteralPath $prebuildsRoot -Directory -ErrorAction SilentlyContinue)
        foreach ($prebuildDir in $prebuildDirs) {
            if ($prebuildDir.Name -eq "win32-arm64") {
                continue
            }

            $removed.Add((Get-RelativePath $NodePtyDir $prebuildDir.FullName)) | Out-Null
            Remove-Item -LiteralPath $prebuildDir.FullName -Recurse -Force
        }
    }

    $conptyRoot = Join-Path $NodePtyDir "third_party\conpty"
    if (Test-Path -LiteralPath $conptyRoot) {
        $versionDirs = @(Get-ChildItem -LiteralPath $conptyRoot -Directory -ErrorAction SilentlyContinue)
        foreach ($versionDir in $versionDirs) {
            $platformDirs = @(Get-ChildItem -LiteralPath $versionDir.FullName -Directory -ErrorAction SilentlyContinue)
            foreach ($platformDir in $platformDirs) {
                if ($platformDir.Name -eq "win10-arm64") {
                    continue
                }

                $removed.Add((Get-RelativePath $NodePtyDir $platformDir.FullName)) | Out-Null
                Remove-Item -LiteralPath $platformDir.FullName -Recurse -Force
            }
        }
    }

    if ($removed.Count -gt 0) {
        Add-Replacement "node-pty-non-arm64-payloads" "pruned" ($removed -join ", ")
    }
}

function Invoke-WithTemporaryEnv {
    param(
        [hashtable]$Environment,
        [scriptblock]$ScriptBlock
    )

    $old = @{}
    foreach ($key in $Environment.Keys) {
        $old[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
    }

    try {
        & $ScriptBlock
    }
    finally {
        foreach ($key in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $old[$key], "Process")
        }
    }
}

function Get-NodeGypLtoEnvironment {
    $mode = "Auto"
    if ($null -ne $script:Context -and
        $null -ne $script:Context.Options -and
        $script:Context.Options.ContainsKey("NodeGypLtoMode") -and
        -not [string]::IsNullOrWhiteSpace($script:Context.Options.NodeGypLtoMode)) {
        $mode = $script:Context.Options.NodeGypLtoMode
    }

    if ($mode -eq "Inherit") {
        return @{}
    }

    return @{
        npm_config_enable_lto = "false"
        npm_config_enable_thin_lto = "false"
        npm_config_lto_jobs = ""
        pnpm_config_enable_lto = "false"
        pnpm_config_enable_thin_lto = "false"
        pnpm_config_lto_jobs = ""
    }
}

function Invoke-WithNodeGypLtoEnvironment {
    param([scriptblock]$ScriptBlock)

    $environment = Get-NodeGypLtoEnvironment
    if ($environment.Count -eq 0) {
        & $ScriptBlock
        return
    }

    Invoke-WithTemporaryEnv $environment $ScriptBlock
}

function Add-MsvcFrameAddressShim {
    param([string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw
    if ($content.Contains("__builtin_frame_address(level)")) {
        return $false
    }

    $shim = @"
#ifndef NODE_ADDON_API_DISABLE_DEPRECATED
#define NODE_ADDON_API_DISABLE_DEPRECATED
#endif

#if defined(_MSC_VER) && !defined(__clang__) && !defined(__builtin_frame_address)
#include <intrin.h>
#define __builtin_frame_address(level) _AddressOfReturnAddress()
#endif

"@

    Set-TextUtf8NoBom $Path ($shim + $content)
    return $true
}

function Get-NpmPackageVersionFromDirectory {
    param([string]$PackageDir)

    $packageJson = Join-Path $PackageDir "package.json"
    if (-not (Test-Path -LiteralPath $packageJson)) {
        throw "Package metadata was not found: $packageJson"
    }

    $package = Get-Content -LiteralPath $packageJson -Raw | ConvertFrom-Json
    return [string]$package.version
}

function Install-Arm64CuaNodePlatformPackage {
    param(
        [string]$ResourcesDir,
        [string]$WorkDir,
        [string]$ScopeName,
        [string]$X64PackageName,
        [string]$Arm64PackageName,
        [string]$ReportName
    )

    $nodeModulesDir = Join-Path $ResourcesDir "cua_node\bin\node_modules"
    $scopeDir = Join-Path $nodeModulesDir $ScopeName
    $x64PackageDir = Join-Path $scopeDir $X64PackageName
    if (-not (Test-Path -LiteralPath $x64PackageDir)) {
        return
    }

    $version = Get-NpmPackageVersionFromDirectory $x64PackageDir
    $arm64PackageDir = Join-Path $scopeDir $Arm64PackageName
    $arm64PackageId = "$ScopeName/$Arm64PackageName"
    if (Test-Path -LiteralPath $arm64PackageDir) {
        $arm64Version = Get-NpmPackageVersionFromDirectory $arm64PackageDir
        if ($arm64Version -eq $version) {
            Remove-Item -LiteralPath $x64PackageDir -Recurse -Force
            Add-Replacement $ReportName "arm64-present" "removed bundled x64 package; kept $arm64PackageId@$version"
            return
        }
    }

    Require-CommandPath "pnpm" | Out-Null

    $installDir = New-CleanDirectory (Join-Path $WorkDir $Arm64PackageName)
    Push-Location $installDir
    try {
        $dependencies = [ordered]@{}
        $dependencies[$arm64PackageId] = $version
        $packageJson = [ordered]@{
            private = $true
            dependencies = $dependencies
        } | ConvertTo-Json -Depth 8
        Set-TextUtf8NoBom (Join-Path $installDir "package.json") $packageJson
        Set-TextUtf8NoBom (Join-Path $installDir "pnpm-workspace.yaml") @"
packages:
  - .
"@

        Invoke-Checked "pnpm" @("install", "--ignore-scripts", "--config.node-linker=hoisted")
    }
    finally {
        Pop-Location
    }

    $sourcePackageDir = Join-Path $installDir (Join-Path "node_modules\$ScopeName" $Arm64PackageName)
    if (-not (Test-Path -LiteralPath $sourcePackageDir)) {
        throw "ARM64 package was not installed: $arm64PackageId@$version"
    }

    $peFiles = @(Get-ChildItem -LiteralPath $sourcePackageDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in @(".dll", ".node") })
    foreach ($file in $peFiles) {
        $machine = Get-PeMachine $file.FullName
        if ($machine -ne "arm64") {
            throw "ARM64 package contained a non-ARM64 binary: $($file.FullName) is $machine"
        }
    }

    Remove-IfExists $arm64PackageDir
    Copy-DirectoryRobust $sourcePackageDir $arm64PackageDir
    Remove-Item -LiteralPath $x64PackageDir -Recurse -Force

    Add-Replacement $ReportName "arm64" "replaced $ScopeName/$X64PackageName with $arm64PackageId@$version"
}

function Install-Arm64CuaNodeSharpPackage {
    param(
        [string]$ResourcesDir,
        [string]$WorkDir
    )

    Install-Arm64CuaNodePlatformPackage $ResourcesDir $WorkDir "@img" "sharp-win32-x64" "sharp-win32-arm64" "@img/sharp-win32"
}

function Install-Arm64CuaNodeCanvasPackage {
    param(
        [string]$ResourcesDir,
        [string]$WorkDir
    )

    Install-Arm64CuaNodePlatformPackage $ResourcesDir $WorkDir "@napi-rs" "canvas-win32-x64-msvc" "canvas-win32-arm64-msvc" "@napi-rs/canvas-win32-msvc"
}

function Invoke-NodeGypArm64ElectronRebuild {
    param(
        [string]$PackageDir,
        [string]$ElectronVersion
    )

    $resolvedPackageDir = (Resolve-Path -LiteralPath $PackageDir).Path
    $shortRoot = Join-Path $script:Context.Paths.RepoRoot "build\node-gyp"
    $shortRoot = New-Item -ItemType Directory -Path $shortRoot -Force
    $shortRoot = (Resolve-Path -LiteralPath $shortRoot.FullName).Path

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($resolvedPackageDir))
    }
    finally {
        $sha256.Dispose()
    }
    $hash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 12).ToLowerInvariant()
    $shortPackageDir = Join-Path $shortRoot $hash

    if (Test-Path -LiteralPath $shortPackageDir) {
        $resolvedShortPackageDir = (Resolve-Path -LiteralPath $shortPackageDir).Path
        if (-not $resolvedShortPackageDir.StartsWith($shortRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean node-gyp build path outside short root: $resolvedShortPackageDir"
        }
    }

    Write-Host "Staging native rebuild in short path: $shortPackageDir"
    Copy-DirectoryRobust $resolvedPackageDir $shortPackageDir
    Remove-IfExists (Join-Path $shortPackageDir "build")

    Push-Location $shortPackageDir
    try {
        Invoke-WithNodeGypLtoEnvironment {
            Invoke-Checked "pnpm" @(
                "dlx",
                "node-gyp@$($script:Context.Tools.NodeGyp)",
                "rebuild",
                "--arch=arm64",
                "--target=$ElectronVersion",
                "--dist-url=https://electronjs.org/headers"
            )
        }
    }
    finally {
        Pop-Location
    }

    Copy-DirectoryRobust (Join-Path $shortPackageDir "build") (Join-Path $resolvedPackageDir "build")
}

function Get-WlDeviceKitNodeModulesDirs {
    param([string]$AsarDir)

    $candidates = @(
        (Join-Path $AsarDir "node_modules\@worklouder\device-kit-oai\node_modules\@worklouder\wl-device-kit\node_modules"),
        (Join-Path $AsarDir "node_modules\%40worklouder\device-kit-oai\node_modules\%40worklouder\wl-device-kit\node_modules")
    )

    return @($candidates | Where-Object { Test-Path -LiteralPath $_ })
}

function Get-RequiredWlDeviceKitNodeModulesDir {
    param([string]$AsarDir)

    foreach ($nodeModulesDir in Get-WlDeviceKitNodeModulesDirs $AsarDir) {
        if ((Test-Path -LiteralPath (Join-Path $nodeModulesDir "node-hid\package.json")) -and
            (Test-Path -LiteralPath (Join-Path $nodeModulesDir "serialport\node_modules\@serialport\bindings-cpp\package.json"))) {
            return $nodeModulesDir
        }
    }

    throw "Could not find Work Louder device kit native module sources."
}

function Sync-WlDeviceKitNativeModuleBuilds {
    param(
        [string]$AsarDir,
        [string]$BuiltHidNode,
        [string]$BuiltSerialPortNode
    )

    if ((Get-PeMachine $BuiltHidNode) -ne "arm64") {
        throw "node-hid build did not produce an ARM64 binary: $BuiltHidNode"
    }
    if ((Get-PeMachine $BuiltSerialPortNode) -ne "arm64") {
        throw "serialport build did not produce an ARM64 binary: $BuiltSerialPortNode"
    }

    $hidBytes = [System.IO.File]::ReadAllBytes($BuiltHidNode)
    $serialPortBytes = [System.IO.File]::ReadAllBytes($BuiltSerialPortNode)

    foreach ($nodeModulesDir in Get-WlDeviceKitNodeModulesDirs $AsarDir) {
        $hidReleaseDir = Join-Path $nodeModulesDir "node-hid\build\Release"
        New-Item -ItemType Directory -Path $hidReleaseDir -Force | Out-Null
        Get-ChildItem -LiteralPath $hidReleaseDir -Filter "*.node" -File -ErrorAction SilentlyContinue |
            Remove-Item -Force
        [System.IO.File]::WriteAllBytes((Join-Path $hidReleaseDir "HID.node"), $hidBytes)

        $serialPortReleaseDirs = @(
            (Join-Path $nodeModulesDir "serialport\node_modules\@serialport\bindings-cpp\build\Release"),
            (Join-Path $nodeModulesDir "serialport\node_modules\%40serialport\bindings-cpp\build\Release")
        )
        foreach ($serialPortReleaseDir in $serialPortReleaseDirs) {
            if (-not (Test-Path -LiteralPath (Split-Path -Parent $serialPortReleaseDir))) {
                continue
            }

            New-Item -ItemType Directory -Path $serialPortReleaseDir -Force | Out-Null
            Get-ChildItem -LiteralPath $serialPortReleaseDir -Filter "*.node" -File -ErrorAction SilentlyContinue |
                Remove-Item -Force
            [System.IO.File]::WriteAllBytes((Join-Path $serialPortReleaseDir "bindings.node"), $serialPortBytes)
        }
    }
}

function Install-Arm64WlDeviceKitNativeModules {
    param(
        [string]$AsarDir,
        [string]$ElectronVersion
    )

    $nodeModulesDir = Get-RequiredWlDeviceKitNodeModulesDir $AsarDir
    $nodeHidDir = Join-Path $nodeModulesDir "node-hid"
    $serialPortBindingsDir = Join-Path $nodeModulesDir "serialport\node_modules\@serialport\bindings-cpp"

    $nodeHidVersion = Get-NpmPackageVersionFromDirectory $nodeHidDir
    $serialPortBindingsVersion = Get-NpmPackageVersionFromDirectory $serialPortBindingsDir
    $script:Context.Report.versions.nodeHid = $nodeHidVersion
    $script:Context.Report.versions.serialPortBindingsCpp = $serialPortBindingsVersion

    $nodeHidUtilHeader = Join-Path $nodeHidDir "src\util.h"
    $serialPortHeader = Join-Path $serialPortBindingsDir "src\serialport.h"
    if (Add-MsvcFrameAddressShim $nodeHidUtilHeader) {
        Add-Replacement "node-hid-source" "patched" "Electron 42 MSVC __builtin_frame_address compatibility"
    }
    if (Add-MsvcFrameAddressShim $serialPortHeader) {
        Add-Replacement "serialport-bindings-cpp-source" "patched" "Electron 42 MSVC __builtin_frame_address compatibility"
    }

    Invoke-NodeGypArm64ElectronRebuild $nodeHidDir $ElectronVersion
    Invoke-NodeGypArm64ElectronRebuild $serialPortBindingsDir $ElectronVersion

    $builtHidNode = Join-Path $nodeHidDir "build\Release\HID.node"
    $builtSerialPortNode = Join-Path $serialPortBindingsDir "build\Release\bindings.node"
    if (-not (Test-Path -LiteralPath $builtHidNode)) {
        throw "node-hid ARM64 build output was not found: $builtHidNode"
    }
    if (-not (Test-Path -LiteralPath $builtSerialPortNode)) {
        throw "serialport ARM64 build output was not found: $builtSerialPortNode"
    }

    Sync-WlDeviceKitNativeModuleBuilds $AsarDir $builtHidNode $builtSerialPortNode
    Add-Replacement "node-hid" "arm64" "rebuilt for Electron $ElectronVersion"
    Add-Replacement "serialport-bindings-cpp" "arm64" "rebuilt for Electron $ElectronVersion"
}

function Build-Arm64NativeModules {
    param(
        [string]$AsarDir,
        [string]$ElectronVersion,
        [string]$WorkDir
    )

    Write-Step "Building ARM64 native Node modules"
    Require-CommandPath "node" | Out-Null
    Require-CommandPath "pnpm" | Out-Null

    $betterSqliteVersion = Get-NpmPackageVersion $AsarDir "better-sqlite3"
    $nodePtyVersion = Get-NpmPackageVersion $AsarDir "node-pty"
    $script:Context.Report.versions.betterSqlite3 = $betterSqliteVersion
    $script:Context.Report.versions.nodePty = $nodePtyVersion

    $buildDir = New-CleanDirectory (Join-Path $WorkDir "native-build")
    Push-Location $buildDir
    try {
        $packageJson = [ordered]@{
            private = $true
            dependencies = [ordered]@{
                "better-sqlite3" = $betterSqliteVersion
                "node-pty" = $nodePtyVersion
            }
            devDependencies = [ordered]@{
                "electron" = $ElectronVersion
                "@electron/rebuild" = $script:Context.Tools.ElectronRebuild
                "node-gyp" = $script:Context.Tools.NodeGyp
            }
        } | ConvertTo-Json -Depth 8
        Set-TextUtf8NoBom (Join-Path $buildDir "package.json") $packageJson
        Set-TextUtf8NoBom (Join-Path $buildDir "pnpm-workspace.yaml") @"
packages:
  - .
overrides:
  node-gyp: $($script:Context.Tools.NodeGyp)
allowBuilds:
  better-sqlite3: true
  node-pty: true
"@

        Invoke-Checked "pnpm" @("install", "--ignore-scripts", "--config.node-linker=hoisted")

        $betterSqliteDir = Join-Path $buildDir "node_modules\better-sqlite3"
        $nodePtyDir = Join-Path $buildDir "node_modules\node-pty"
        Patch-BetterSqlite3ForElectron42 $betterSqliteDir $ElectronVersion
        Disable-NodePtySpectreMitigation $nodePtyDir

        Push-Location $betterSqliteDir
        try {
            $prebuildExit = Invoke-Checked "pnpm" @(
                "dlx",
                "prebuild-install@$($script:Context.Tools.PrebuildInstall)",
                "--runtime", "electron",
                "--target", $ElectronVersion,
                "--arch", "arm64",
                "--platform", "win32"
            ) @(0, 1)
            if ($prebuildExit -eq 0) {
                Add-Replacement "better-sqlite3" "prebuilt-arm64" "electron $ElectronVersion"
            }
            else {
                Add-Replacement "better-sqlite3" "prebuilt-miss" "falling back to @electron/rebuild"
            }
        }
        finally {
            Pop-Location
        }

        $electronRebuild = Join-Path $buildDir "node_modules\.bin\electron-rebuild.cmd"
        if (-not (Test-Path -LiteralPath $electronRebuild)) {
            throw "electron-rebuild command was not found: $electronRebuild"
        }

        Invoke-WithNodeGypLtoEnvironment {
            Invoke-Checked $electronRebuild @(
                "-v", $ElectronVersion,
                "--arch", "arm64",
                "--force",
                "-w", "better-sqlite3,node-pty"
            )
        }

        Prune-NodePtyNonArm64Payloads $nodePtyDir
    }
    finally {
        Pop-Location
    }

    foreach ($moduleName in @("better-sqlite3", "node-pty")) {
        $source = Join-Path $buildDir "node_modules\$moduleName"
        $destination = Join-Path $AsarDir "node_modules\$moduleName"
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Native build did not produce $moduleName"
        }
        Remove-IfExists $destination
        Copy-DirectoryRobust $source $destination
        Add-Replacement $moduleName "arm64" "rebuilt for Electron $ElectronVersion"
    }

    Install-Arm64WlDeviceKitNativeModules $AsarDir $ElectronVersion
}
