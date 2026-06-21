$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot "src\CodexWoA.Build\CodexWoA.Build.psd1") -Force

Describe "Windows runtime helpers" {
    It "replaces windows-updater.node with an ARM64 no-op stub" {
        InModuleScope CodexWoA.Build {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) "codex-woa-runtime-windows-test-$([System.Guid]::NewGuid())"
            $resourcesDir = Join-Path $root "resources"
            $workDir = Join-Path $root "work"
            $nativeDir = Join-Path $resourcesDir "native"
            $updaterPath = Join-Path $nativeDir "windows-updater.node"

            try {
                New-Item -ItemType Directory -Path $nativeDir -Force | Out-Null
                New-Item -ItemType Directory -Path $workDir -Force | Out-Null
                Set-TextUtf8NoBom $updaterPath "native fixture"
                $script:Context = [pscustomobject]@{
                    Tools = [pscustomobject]@{
                        NodeGyp = "12.3.0"
                    }
                    Report = [pscustomobject]@{
                        replacements = New-Object "System.Collections.Generic.List[object]"
                    }
                }

                Mock Require-CommandPath { "pnpm" } -ParameterFilter { $Name -eq "pnpm" }
                Mock Invoke-Checked {
                    $builtDir = Join-Path (Get-Location).Path "build\Release"
                    New-Item -ItemType Directory -Path $builtDir -Force | Out-Null
                    Set-TextUtf8NoBom (Join-Path $builtDir "windows_updater.node") "arm64 stub fixture"
                }
                Mock Get-PeMachine { "arm64" }

                Install-Arm64WindowsUpdaterStub $resourcesDir "42.0.0" $workDir

                Test-Path -LiteralPath $updaterPath | Should -BeTrue
                Get-Content -LiteralPath $updaterPath -Raw | Should -Be "arm64 stub fixture"
                $stubSource = Get-Content -LiteralPath (Join-Path $workDir "windows-updater-stub\windows_updater_stub.cc") -Raw
                $stubSource | Should -Match "getCurrentPackageFamily"
                $stubSource | Should -Match "stagePackage"
                $script:Context.Report.replacements[0].name | Should -Be "windows-updater.node"
                $script:Context.Report.replacements[0].status | Should -Be "stub-arm64"
                Assert-MockCalled Invoke-Checked -Exactly -Times 1 -Scope It
            }
            finally {
                Remove-IfExists $root
            }
        }
    }
}
