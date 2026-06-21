$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot "src\CodexWoA.Build\CodexWoA.Build.psd1") -Force

Describe "Common helpers" {
    It "recognizes ARM64 hosts from processor architecture environment fallbacks" {
        InModuleScope CodexWoA.Build {
            $oldProcessorArchitecture = $env:PROCESSOR_ARCHITECTURE
            $oldProcessorArchiteW6432 = $env:PROCESSOR_ARCHITEW6432

            try {
                $env:PROCESSOR_ARCHITECTURE = "ARM64"
                $env:PROCESSOR_ARCHITEW6432 = ""

                Test-IsArm64Host | Should -BeTrue
            }
            finally {
                $env:PROCESSOR_ARCHITECTURE = $oldProcessorArchitecture
                $env:PROCESSOR_ARCHITEW6432 = $oldProcessorArchiteW6432
            }
        }
    }

    It "finds Windows SDK tools in legacy direct architecture directories" {
        InModuleScope CodexWoA.Build {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) "codex-woa-common-test-$([System.Guid]::NewGuid())"
            $kitRoot = Join-Path $root "Windows Kits\10\bin"
            $toolPath = Join-Path $kitRoot "x64\makeappx.exe"

            try {
                New-Item -ItemType Directory -Path (Split-Path -Parent $toolPath) -Force | Out-Null
                Set-TextUtf8NoBom $toolPath "tool fixture"

                Mock Test-IsArm64Host { $false }
                Mock Join-Path {
                    param($Path, $ChildPath)

                    if ($Path -eq ${env:ProgramFiles(x86)} -and $ChildPath -eq "Windows Kits\10\bin") {
                        return $kitRoot
                    }

                    return [System.IO.Path]::Combine($Path, $ChildPath)
                }

                Find-WindowsKitTool "makeappx.exe" | Should -Be $toolPath
            }
            finally {
                Remove-IfExists $root
            }
        }
    }
}
