#Requires -Version 5.1
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

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "src\CodexWoA.Build\CodexWoA.Build.psd1"
Import-Module $modulePath -Force
Invoke-CodexWoABuild @PSBoundParameters
exit 0
