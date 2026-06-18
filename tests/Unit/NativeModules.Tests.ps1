$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot "src\CodexWoA.Build\CodexWoA.Build.psd1") -Force

Describe "Native module helpers" {
    It "disables inherited Node LTO settings for node-gyp by default and restores the process environment" {
        InModuleScope CodexWoA.Build {
            $envNames = @(
                "npm_config_enable_thin_lto",
                "npm_config_enable_lto",
                "npm_config_lto_jobs",
                "pnpm_config_enable_thin_lto",
                "pnpm_config_enable_lto",
                "pnpm_config_lto_jobs"
            )
            $oldValues = @{}
            foreach ($envName in $envNames) {
                $oldValues[$envName] = [Environment]::GetEnvironmentVariable($envName, "Process")
            }
            try {
                [Environment]::SetEnvironmentVariable("npm_config_enable_thin_lto", "original-thin", "Process")
                [Environment]::SetEnvironmentVariable("npm_config_lto_jobs", "original-jobs", "Process")
                $script:Context = [pscustomobject]@{
                    Options = @{
                        NodeGypLtoMode = "Auto"
                    }
                }

                $script:CapturedNodeGypLtoEnv = $null
                Invoke-WithNodeGypLtoEnvironment {
                    $script:CapturedNodeGypLtoEnv = [ordered]@{
                        npmThinLto = [Environment]::GetEnvironmentVariable("npm_config_enable_thin_lto", "Process")
                        npmLto = [Environment]::GetEnvironmentVariable("npm_config_enable_lto", "Process")
                        npmLtoJobs = [Environment]::GetEnvironmentVariable("npm_config_lto_jobs", "Process")
                        pnpmThinLto = [Environment]::GetEnvironmentVariable("pnpm_config_enable_thin_lto", "Process")
                        pnpmLto = [Environment]::GetEnvironmentVariable("pnpm_config_enable_lto", "Process")
                        pnpmLtoJobs = [Environment]::GetEnvironmentVariable("pnpm_config_lto_jobs", "Process")
                    }
                }

                $captured = $script:CapturedNodeGypLtoEnv
                $captured.npmThinLto | Should -Be "false"
                $captured.npmLto | Should -Be "false"
                $captured.npmLtoJobs | Should -Be ""
                $captured.pnpmThinLto | Should -Be "false"
                $captured.pnpmLto | Should -Be "false"
                $captured.pnpmLtoJobs | Should -Be ""
                [Environment]::GetEnvironmentVariable("npm_config_enable_thin_lto", "Process") | Should -Be "original-thin"
                [Environment]::GetEnvironmentVariable("npm_config_lto_jobs", "Process") | Should -Be "original-jobs"
            }
            finally {
                foreach ($envName in $envNames) {
                    [Environment]::SetEnvironmentVariable($envName, $oldValues[$envName], "Process")
                }
                Remove-Variable -Scope Script -Name CapturedNodeGypLtoEnv -ErrorAction SilentlyContinue
            }
        }
    }

    It "inherits existing Node LTO settings when requested" {
        InModuleScope CodexWoA.Build {
            $oldThinLto = [Environment]::GetEnvironmentVariable("npm_config_enable_thin_lto", "Process")
            try {
                [Environment]::SetEnvironmentVariable("npm_config_enable_thin_lto", "keep-me", "Process")
                $script:Context = [pscustomobject]@{
                    Options = @{
                        NodeGypLtoMode = "Inherit"
                    }
                }

                $script:CapturedNodeGypInheritedLtoEnv = $null
                Invoke-WithNodeGypLtoEnvironment {
                    $script:CapturedNodeGypInheritedLtoEnv = [Environment]::GetEnvironmentVariable("npm_config_enable_thin_lto", "Process")
                }

                $captured = $script:CapturedNodeGypInheritedLtoEnv
                $captured | Should -Be "keep-me"
                [Environment]::GetEnvironmentVariable("npm_config_enable_thin_lto", "Process") | Should -Be "keep-me"
            }
            finally {
                [Environment]::SetEnvironmentVariable("npm_config_enable_thin_lto", $oldThinLto, "Process")
                Remove-Variable -Scope Script -Name CapturedNodeGypInheritedLtoEnv -ErrorAction SilentlyContinue
            }
        }
    }

    It "replaces the bundled cua_node sharp x64 package with the matching ARM64 package" {
        InModuleScope CodexWoA.Build {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) "codex-woa-native-modules-test-$([System.Guid]::NewGuid())"
            $resourcesDir = Join-Path $root "resources"
            $workDir = Join-Path $root "work"
            $imgDir = Join-Path $resourcesDir "cua_node\bin\node_modules\@img"
            $x64PackageDir = Join-Path $imgDir "sharp-win32-x64"

            try {
                New-Item -ItemType Directory -Path $x64PackageDir -Force | Out-Null
                New-Item -ItemType Directory -Path $workDir -Force | Out-Null
                Set-TextUtf8NoBom (Join-Path $x64PackageDir "package.json") '{"version":"0.34.5"}'

                $script:Context = [pscustomobject]@{
                    Report = [pscustomobject]@{
                        replacements = New-Object "System.Collections.Generic.List[object]"
                    }
                }

                Mock Require-CommandPath { "pnpm" } -ParameterFilter { $Name -eq "pnpm" }
                Mock Invoke-Checked {
                    $installedPackageDir = Join-Path (Get-Location).Path "node_modules\@img\sharp-win32-arm64"
                    New-Item -ItemType Directory -Path $installedPackageDir -Force | Out-Null
                    Set-TextUtf8NoBom (Join-Path $installedPackageDir "package.json") '{"version":"0.34.5"}'
                    Set-TextUtf8NoBom (Join-Path $installedPackageDir "README.md") "arm64 sharp fixture"
                }

                Install-Arm64CuaNodeSharpPackage $resourcesDir $workDir

                (Test-Path -LiteralPath $x64PackageDir) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $imgDir "sharp-win32-arm64\package.json")) | Should -BeTrue
                (Get-Content -LiteralPath (Join-Path $imgDir "sharp-win32-arm64\README.md") -Raw) | Should -Be "arm64 sharp fixture"
                $script:Context.Report.replacements[0].name | Should -Be "@img/sharp-win32"
                $script:Context.Report.replacements[0].status | Should -Be "arm64"

                Assert-MockCalled Invoke-Checked -Exactly -Times 1 -Scope It
            }
            finally {
                Remove-IfExists $root
            }
        }
    }

    It "replaces the bundled cua_node canvas x64 package with the matching ARM64 package" {
        InModuleScope CodexWoA.Build {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) "codex-woa-native-modules-test-$([System.Guid]::NewGuid())"
            $resourcesDir = Join-Path $root "resources"
            $workDir = Join-Path $root "work"
            $napiRsDir = Join-Path $resourcesDir "cua_node\bin\node_modules\@napi-rs"
            $x64PackageDir = Join-Path $napiRsDir "canvas-win32-x64-msvc"

            try {
                New-Item -ItemType Directory -Path $x64PackageDir -Force | Out-Null
                New-Item -ItemType Directory -Path $workDir -Force | Out-Null
                Set-TextUtf8NoBom (Join-Path $x64PackageDir "package.json") '{"version":"1.0.0"}'

                $script:Context = [pscustomobject]@{
                    Report = [pscustomobject]@{
                        replacements = New-Object "System.Collections.Generic.List[object]"
                    }
                }

                Mock Require-CommandPath { "pnpm" } -ParameterFilter { $Name -eq "pnpm" }
                Mock Invoke-Checked {
                    $installedPackageDir = Join-Path (Get-Location).Path "node_modules\@napi-rs\canvas-win32-arm64-msvc"
                    New-Item -ItemType Directory -Path $installedPackageDir -Force | Out-Null
                    Set-TextUtf8NoBom (Join-Path $installedPackageDir "package.json") '{"version":"1.0.0"}'
                    Set-TextUtf8NoBom (Join-Path $installedPackageDir "README.md") "arm64 canvas fixture"
                }

                Install-Arm64CuaNodeCanvasPackage $resourcesDir $workDir

                (Test-Path -LiteralPath $x64PackageDir) | Should -BeFalse
                (Test-Path -LiteralPath (Join-Path $napiRsDir "canvas-win32-arm64-msvc\package.json")) | Should -BeTrue
                (Get-Content -LiteralPath (Join-Path $napiRsDir "canvas-win32-arm64-msvc\README.md") -Raw) | Should -Be "arm64 canvas fixture"
                $script:Context.Report.replacements[0].name | Should -Be "@napi-rs/canvas-win32-msvc"
                $script:Context.Report.replacements[0].status | Should -Be "arm64"

                Assert-MockCalled Invoke-Checked -Exactly -Times 1 -Scope It
            }
            finally {
                Remove-IfExists $root
            }
        }
    }
}
