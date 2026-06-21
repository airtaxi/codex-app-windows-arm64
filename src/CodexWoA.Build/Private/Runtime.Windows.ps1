function Read-PngUInt32BigEndian {
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )

    return (($Bytes[$Offset] -shl 24) -bor ($Bytes[$Offset + 1] -shl 16) -bor ($Bytes[$Offset + 2] -shl 8) -bor $Bytes[$Offset + 3])
}

function New-IcoFromPng {
    param(
        [string]$PngPath,
        [string]$IcoPath
    )

    $png = [System.IO.File]::ReadAllBytes($PngPath)
    if ($png.Length -lt 24 -or $png[0] -ne 0x89 -or $png[1] -ne 0x50 -or $png[2] -ne 0x4E -or $png[3] -ne 0x47) {
        throw "Icon source is not a PNG file: $PngPath"
    }

    $width = Read-PngUInt32BigEndian $png 16
    $height = Read-PngUInt32BigEndian $png 20
    $iconWidth = if ($width -ge 256) { 0 } else { [byte]$width }
    $iconHeight = if ($height -ge 256) { 0 } else { [byte]$height }

    New-Item -ItemType Directory -Path (Split-Path -Parent $IcoPath) -Force | Out-Null
    $stream = [System.IO.File]::Create($IcoPath)
    try {
        $writer = New-Object System.IO.BinaryWriter($stream)
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]1)
        $writer.Write([byte]$iconWidth)
        $writer.Write([byte]$iconHeight)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$png.Length)
        $writer.Write([uint32]22)
        $writer.Write($png)
    }
    finally {
        $stream.Dispose()
    }
}

function Get-RceditPath {
    param([string]$CacheDir)

    $rceditVersion = "v2.0.0"
    $rceditName = "rcedit-x64.exe"
    $rceditPath = Join-Path $CacheDir $rceditName
    $expectedHash = "3E7801DB1A5EDBEC91B49A24A094AAD776CB4515488EA5A4CA2289C400EADE2A"
    if (-not (Test-Path -LiteralPath $rceditPath)) {
        Download-File "https://github.com/electron/rcedit/releases/download/$rceditVersion/$rceditName" $rceditPath
    }

    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $rceditPath).Hash
    if ($actualHash -ne $expectedHash) {
        throw "rcedit SHA256 mismatch: $actualHash"
    }

    return $rceditPath
}

function Set-CodexExecutableIcon {
    param(
        [string]$PackageRoot,
        [string]$CodexExe,
        [string]$CacheDir
    )

    $iconPng = Join-Path $PackageRoot "assets\icon.png"
    if (-not (Test-Path -LiteralPath $iconPng)) {
        Write-Warn "Could not patch Codex.exe icon because assets\icon.png was not found."
        return
    }

    $iconIco = Join-Path $CacheDir "CodexWoA.ico"
    New-IcoFromPng $iconPng $iconIco
    $rcedit = Get-RceditPath $CacheDir
    Invoke-Checked $rcedit @($CodexExe, "--set-icon", $iconIco)
    Add-Replacement "Codex.exe-icon" "patched" "assets\icon.png"
}

function Install-Arm64ElectronRuntime {
    param(
        [string]$AppDir,
        [string]$ElectronVersion,
        [string]$CacheDir
    )

    Write-Step "Replacing Electron runtime with win32-arm64 v$ElectronVersion"
    $zipName = "electron-v$ElectronVersion-win32-arm64.zip"
    $zipPath = Join-Path $CacheDir $zipName
    $url = "https://github.com/electron/electron/releases/download/v$ElectronVersion/$zipName"
    if (-not (Test-Path -LiteralPath $zipPath)) {
        Download-File $url $zipPath
    }

    $runtimeDir = Join-Path $CacheDir "electron-win32-arm64-$ElectronVersion"
    Expand-ZipClean $zipPath $runtimeDir

    $resourcesDir = Join-Path $AppDir "resources"
    $savedResources = Join-Path (Split-Path -Parent $AppDir) "resources.saved"
    Remove-IfExists $savedResources
    Move-Item -LiteralPath $resourcesDir -Destination $savedResources

    Get-ChildItem -LiteralPath $AppDir -Force | Remove-Item -Recurse -Force
    Copy-DirectoryRobust $runtimeDir $AppDir
    Remove-IfExists (Join-Path $AppDir "resources")
    Move-Item -LiteralPath $savedResources -Destination $resourcesDir

    $electronExe = Join-Path $AppDir "electron.exe"
    $codexExe = Join-Path $AppDir "Codex.exe"
    if (-not (Test-Path -LiteralPath $electronExe)) {
        throw "Electron runtime did not contain electron.exe"
    }
    Move-Item -LiteralPath $electronExe -Destination $codexExe -Force
    Set-CodexExecutableIcon (Split-Path -Parent $AppDir) $codexExe $CacheDir

    Add-Replacement "electron-runtime" "arm64" $zipName
}

function Install-Arm64Node {
    param(
        [string]$ResourcesDir,
        [string]$NodeVersion,
        [string]$CacheDir
    )

    Write-Step "Replacing Node.js with win-arm64 v$NodeVersion"
    $existingCandidates = @(Get-ChildItem -LiteralPath $ResourcesDir -Recurse -File -Filter "node.exe" -Depth 3 -ErrorAction Stop)
    if ($existingCandidates.Count -eq 0) {
        throw "Could not find existing node.exe under $($ResourcesDir) to replace"
    }
    if ($existingCandidates.Count -gt 1) {
        $paths = ($existingCandidates.FullName -join "`n")
        throw "Found multiple node.exe candidates under $($ResourcesDir):`n$paths"
    }

    $zipName = "node-v$NodeVersion-win-arm64.zip"
    $zipPath = Join-Path $CacheDir $zipName
    $url = "https://nodejs.org/dist/v$NodeVersion/$zipName"
    if (-not (Test-Path -LiteralPath $zipPath)) {
        Download-File $url $zipPath
    }

    $nodeDir = Join-Path $CacheDir "node-win-arm64-$NodeVersion"
    Expand-ZipClean $zipPath $nodeDir
    $armNodeExe = Get-ChildItem -LiteralPath $nodeDir -Recurse -File -Filter "node.exe" | Select-Object -First 1
    if ($null -eq $armNodeExe) {
        throw "Node archive did not contain node.exe"
    }

    Copy-Item -LiteralPath $armNodeExe.FullName -Destination $existingCandidates[0].FullName -Force
    Add-Replacement "node.exe" "arm64" $zipName
}

function Get-GitHubRelease {
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$Tag
    )

    $headers = @{ Accept = "application/vnd.github+json" }
    if ($Tag -eq "latest") {
        return Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/latest" -Headers $headers
    }

    return Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag" -Headers $headers
}

function Download-GitHubReleaseAsset {
    param(
        [object]$Release,
        [string]$AssetName,
        [string]$Destination
    )

    $asset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
    if ($null -eq $asset) {
        throw "Release asset not found: $AssetName"
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        Download-File $asset.browser_download_url $Destination
    }

    return $Destination
}

function Install-Arm64CodexHelpers {
    param(
        [string]$ResourcesDir,
        [string]$CacheDir,
        [string]$ReleaseTag
    )

    Write-Step "Replacing Codex helper executables from openai/codex"
    $release = Get-GitHubRelease "openai" "codex" $ReleaseTag
    $script:Context.Report.versions.codexRelease = $release.tag_name

    $mapping = @(
        @{ asset = "codex-aarch64-pc-windows-msvc.exe"; target = "codex.exe"; required = $false },
        @{ asset = "codex-command-runner-aarch64-pc-windows-msvc.exe"; target = "codex-command-runner.exe"; required = $false },
        @{ asset = "codex-windows-sandbox-setup-aarch64-pc-windows-msvc.exe"; target = "codex-windows-sandbox-setup.exe"; required = $false },
        @{ asset = "codex-app-server-aarch64-pc-windows-msvc.exe"; target = "codex-app-server.exe"; required = $false },
        @{ asset = "codex-responses-api-proxy-aarch64-pc-windows-msvc.exe"; target = "codex-responses-api-proxy.exe"; required = $false }
    )

    foreach ($item in $mapping) {
        $targetPath = Join-Path $ResourcesDir $item.target
        if (-not (Test-Path -LiteralPath $targetPath) -and -not $item.required) {
            continue
        }

        try {
            $downloadPath = Join-Path $CacheDir $item.asset
            Download-GitHubReleaseAsset $release $item.asset $downloadPath | Out-Null
            Copy-Item -LiteralPath $downloadPath -Destination $targetPath -Force
            Add-Replacement $item.target "arm64" $item.asset
        }
        catch {
            if ($item.required) {
                throw
            }
            Write-Warn "Could not replace $($item.target); keeping original out-of-process fallback. $($_.Exception.Message)"
            Add-Replacement $item.target "fallback" $_.Exception.Message
        }
    }
}

function Install-Arm64Ripgrep {
    param(
        [string]$ResourcesDir,
        [string]$CacheDir
    )

    Write-Step "Replacing rg.exe with ripgrep arm64"
    $release = Get-GitHubRelease "BurntSushi" "ripgrep" "latest"
    $tag = $release.tag_name.TrimStart("v")
    $assetName = "ripgrep-$tag-aarch64-pc-windows-msvc.zip"
    $zipPath = Join-Path $CacheDir $assetName
    Download-GitHubReleaseAsset $release $assetName $zipPath | Out-Null

    $ripgrepDir = Join-Path $CacheDir "ripgrep-arm64-$tag"
    Expand-ZipClean $zipPath $ripgrepDir
    $rgExe = Get-ChildItem -LiteralPath $ripgrepDir -Recurse -File -Filter "rg.exe" | Select-Object -First 1
    if ($null -eq $rgExe) {
        throw "ripgrep archive did not contain rg.exe"
    }

    Copy-Item -LiteralPath $rgExe.FullName -Destination (Join-Path $ResourcesDir "rg.exe") -Force
    Add-Replacement "rg.exe" "arm64" $assetName
}

function New-WindowsUpdaterStubSource {
    param([string]$PackageDir)

    New-Item -ItemType Directory -Path $PackageDir -Force | Out-Null
    Set-TextUtf8NoBom (Join-Path $PackageDir "package.json") @"
{
  "private": true,
  "name": "codex-woa-windows-updater-stub",
  "version": "1.0.0",
  "gypfile": true
}
"@
    Set-TextUtf8NoBom (Join-Path $PackageDir "binding.gyp") @"
{
  "targets": [
    {
      "target_name": "windows_updater",
      "sources": [ "windows_updater_stub.cc" ],
      "defines": [ "NAPI_VERSION=8" ]
    }
  ]
}
"@
    Set-TextUtf8NoBom (Join-Path $PackageDir "windows_updater_stub.cc") @"
#include <node_api.h>

static napi_value MakeBoolean(napi_env env, bool value) {
  napi_value result;
  napi_get_boolean(env, value, &result);
  return result;
}

static napi_value MakeResolvedBoolean(napi_env env, bool value) {
  napi_deferred deferred;
  napi_value promise;
  napi_create_promise(env, &deferred, &promise);
  napi_resolve_deferred(env, deferred, MakeBoolean(env, value));
  return promise;
}

static napi_value MakeResolvedString(napi_env env, const char* value) {
  napi_deferred deferred;
  napi_value promise;
  napi_value result;
  napi_create_promise(env, &deferred, &promise);
  napi_create_string_utf8(env, value, NAPI_AUTO_LENGTH, &result);
  napi_resolve_deferred(env, deferred, result);
  return promise;
}

static napi_value MakeString(napi_env env, const char* value) {
  napi_value result;
  napi_create_string_utf8(env, value, NAPI_AUTO_LENGTH, &result);
  return result;
}

static napi_value HasUpdate(napi_env env, napi_callback_info info) {
  return MakeResolvedBoolean(env, false);
}

static napi_value CanSilentlyDownload(napi_env env, napi_callback_info info) {
  return MakeBoolean(env, false);
}

static napi_value TrySilentDownloadStoreUpdates(napi_env env, napi_callback_info info) {
  return MakeResolvedString(env, "NoUpdates");
}

static napi_value TrySilentDownloadAndInstallStoreUpdates(napi_env env, napi_callback_info info) {
  return MakeResolvedString(env, "NoUpdates");
}

static napi_value GetCurrentPackageFamily(napi_env env, napi_callback_info info) {
  return MakeString(env, "");
}

static napi_value StagePackage(napi_env env, napi_callback_info info) {
  return MakeResolvedBoolean(env, false);
}

static napi_value ActivateStagedPackage(napi_env env, napi_callback_info info) {
  return MakeResolvedBoolean(env, false);
}

static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"hasUpdate", 0, HasUpdate, 0, 0, 0, napi_default, 0},
      {"canSilentlyDownload", 0, CanSilentlyDownload, 0, 0, 0, napi_default, 0},
      {"trySilentDownloadStoreUpdates", 0, TrySilentDownloadStoreUpdates, 0, 0, 0, napi_default, 0},
      {"trySilentDownloadAndInstallStoreUpdates", 0, TrySilentDownloadAndInstallStoreUpdates, 0, 0, 0, napi_default, 0},
      {"getCurrentPackageFamily", 0, GetCurrentPackageFamily, 0, 0, 0, napi_default, 0},
      {"stagePackage", 0, StagePackage, 0, 0, 0, napi_default, 0},
      {"activateStagedPackage", 0, ActivateStagedPackage, 0, 0, 0, napi_default, 0},
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
"@
}

function Install-Arm64WindowsUpdaterStub {
    param(
        [string]$ResourcesDir,
        [string]$ElectronVersion,
        [string]$WorkDir
    )

    $updaterPath = Join-Path $ResourcesDir "native\windows-updater.node"
    if (-not (Test-Path -LiteralPath $updaterPath)) {
        return
    }

    Write-Step "Replacing Windows updater native module with ARM64 no-op stub"
    Require-CommandPath "pnpm" | Out-Null

    $stubDir = New-CleanDirectory (Join-Path $WorkDir "windows-updater-stub")
    New-WindowsUpdaterStubSource $stubDir

    Push-Location $stubDir
    try {
        Invoke-Checked "pnpm" @(
            "dlx",
            "node-gyp@$($script:Context.Tools.NodeGyp)",
            "rebuild",
            "--arch=arm64",
            "--target=$ElectronVersion",
            "--dist-url=https://electronjs.org/headers"
        )
    }
    finally {
        Pop-Location
    }

    $builtNode = Join-Path $stubDir "build\Release\windows_updater.node"
    if (-not (Test-Path -LiteralPath $builtNode)) {
        throw "Windows updater ARM64 stub build output was not found: $builtNode"
    }
    if ((Get-PeMachine $builtNode) -ne "arm64") {
        throw "Windows updater stub build did not produce an ARM64 binary: $builtNode"
    }

    Copy-Item -LiteralPath $builtNode -Destination $updaterPath -Force
    Add-Replacement "windows-updater.node" "stub-arm64" "local package disables Microsoft Store updater"
}
