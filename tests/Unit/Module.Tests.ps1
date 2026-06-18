Describe "CodexWoA.Build module" {
    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $modulePath = Join-Path $repoRoot "src\CodexWoA.Build\CodexWoA.Build.psd1"
        Import-Module $modulePath -Force
    }

    It "exports only the supported public commands" {
        @(Get-Command -Module CodexWoA.Build).Name | Sort-Object |
            Should -Be @("Invoke-CodexWoABuild", "Resolve-CodexStorePackage")
    }

    It "keeps the build command CLI contract" {
        $parameters = (Get-Command Invoke-CodexWoABuild).Parameters
        foreach ($name in @("SourceMode", "SourceMsixPath", "OutputDir", "PackageIdentity", "DisplayName", "PackageVersionOverride", "PublisherSubject", "CodexReleaseTag", "NodeGypLtoMode", "InstallVsDependencies", "SkipVsDependencyCheck", "KeepWorkDir", "Force")) {
            $parameters.ContainsKey($name) | Should -BeTrue
        }
    }
}
