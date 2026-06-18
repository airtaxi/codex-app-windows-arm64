function Invoke-CodexWoABuild {
    [CmdletBinding()]
    param(
        [ValidateSet("Prompt", "StoreMsix", "Installed", "StoreLatest", "Msix")]
        [string]$SourceMode = "Prompt",
        [string]$SourceMsixPath = "",
        [string]$OutputDir = "",
        [string]$PackageIdentity = "OpenAI.Codex.WoA",
        [string]$DisplayName = "Codex WoA",
        [string]$PackageVersionOverride = "",
        [string]$PublisherSubject = "CN=Codex WoA Local",
        [string]$CodexReleaseTag = "latest",
        [ValidateSet("Auto", "Disabled", "Inherit")]
        [string]$NodeGypLtoMode = "Auto",
        [switch]$InstallVsDependencies,
        [switch]$SkipVsDependencyCheck,
        [switch]$KeepWorkDir,
        [switch]$Force
    )

    $repoRoot = $script:RepoRoot
    $options = @{
        SourceMode = $SourceMode
        SourceMsixPath = $SourceMsixPath
        OutputDir = $OutputDir
        PackageIdentity = $PackageIdentity
        DisplayName = $DisplayName
        PackageVersionOverride = $PackageVersionOverride
        PublisherSubject = $PublisherSubject
        CodexReleaseTag = $CodexReleaseTag
        NodeGypLtoMode = $NodeGypLtoMode
        InstallVsDependencies = [bool]$InstallVsDependencies
        SkipVsDependencyCheck = [bool]$SkipVsDependencyCheck
        KeepWorkDir = [bool]$KeepWorkDir
        Force = [bool]$Force
    }

    $script:Context = New-BuildContext -Options $options -RepoRoot $repoRoot
    Invoke-BuildOrchestration -Context $script:Context
}
