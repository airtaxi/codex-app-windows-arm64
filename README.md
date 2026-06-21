# Codex App Windows ARM64

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Contributors](https://img.shields.io/github/contributors/airtaxi/codex-app-windows-arm64)](https://github.com/airtaxi/codex-app-windows-arm64/graphs/contributors)

🌐 English | [한국어](README.ko.md)

> **Archived:** OpenAI now provides the official Codex app for Windows with Windows on ARM support, so this unofficial repackaging repository is no longer needed. Install and update the official Codex app from Microsoft Store instead:
>
> ```powershell
> winget install Codex -s msstore
> ```

Codex App Windows ARM64 was an unofficial repackaging script for running the official Windows x64 Codex app on Windows on ARM. It took an installed Microsoft Store Codex package, replaced the runtime and native payloads with ARM64-compatible builds where possible, and produced a locally signed ARM64 MSIX package.

This project is archived and kept only for historical reference.

## Disclaimer

This project is not affiliated with, endorsed by, sponsored by, or officially supported by OpenAI. It is an independent community tool for local experimentation and compatibility work.

OpenAI, Codex, and ChatGPT are trademarks of OpenAI. All other trademarks are the property of their respective owners.

## Legacy Requirements

- A Windows on ARM device.
- The official Codex app installed from Microsoft Store as the x64 package, or an official x64 Codex MSIX downloaded from Microsoft Store CDN.
- PowerShell 7 (`pwsh`) is recommended. Windows PowerShell is used only as a fallback.
- Node.js with `node` and `pnpm` available on `PATH`.
- Windows SDK tools, including `makeappx.exe`, `signtool.exe`, and `mt.exe`.
- `tar.exe` available on `PATH` for extracting upstream Linux ARM64 runtime assets.
- Visual Studio C++ desktop build tools with the ARM64 C++ toolchain.
- Internet access for downloading Electron, Node.js, Codex helper binaries, ripgrep, and native module build dependencies.

## Legacy Quick Install From Release

The release-based install path below is retained for historical reference only. For new installations, use the official Codex app from Microsoft Store.

With Scoop:

```powershell
scoop bucket add codex-woa https://github.com/airtaxi/codex-app-windows-arm64
scoop install codex-woa
```

Update normally:

```powershell
scoop update
scoop update codex-woa
```

Download the release zip from the [GitHub Releases](https://github.com/airtaxi/codex-app-windows-arm64/releases) page, extract it, and run:

```bat
Install.bat
```

Close Codex completely before installing. `Install.bat` runs `Install.ps1`, checks that the MSIX signer matches the included certificate, imports the local certificate into the trusted certificate store when needed, installs the generated MSIX package, and then enables the Windows Computer Use feature flag for the current user.

To remove the repack, uninstall Codex WoA through Windows Settings. The installer intentionally leaves the local certificate trust and Computer Use feature flag in place. To disable the feature flag manually, run:

```powershell
[Environment]::SetEnvironmentVariable("CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE", $null, "User")
```

## Legacy Build

Run the build wrapper from this repository:

```bat
Build-CodexWoA.bat -SourceMode StoreMsix -Force
```

`-SourceMode StoreMsix` downloads the latest official Codex x64 MSIX from the Microsoft Store link, verifies its SHA-1 hash, and uses it as the source package.

`-SourceMode Installed` uses the official x64 Codex package already installed from Microsoft Store.

`-SourceMode StoreLatest` does not download an MSIX directly. It opens Microsoft Store so you can install or update Codex officially, then continues by using the installed x64 package.

`-SourceMode Msix -SourceMsixPath <path>` extracts an official x64 Codex MSIX directly and uses it as the source package.

The default output directory is `dist`.

### Development

The build implementation lives in `src\CodexWoA.Build` and is grouped by build
domain. `Build-CodexWoA.ps1` remains the stable command-line entrypoint.

Run the fast parser, analyzer, JavaScript, and unit checks before committing:

```powershell
.\tests\Run-Checks.ps1 -InstallDependencies
```

See [docs/build-architecture.md](docs/build-architecture.md) for module boundaries
and maintenance rules.

## Outputs

A successful build creates:

- `dist\Codex-WoA_<version>_arm64.msix`
- `dist\cert\CodexWoA.cer`
- `dist\Install.ps1`
- `dist\Install.bat`
- `dist\build-report.json`

The certificate is generated locally when needed and is not committed to the repository.

## What The Script Changes

- Rewrites `AppxManifest.xml` for an ARM64 package identity.
- Replaces the Electron runtime with `win32-arm64`.
- Replaces bundled Node.js with `win-arm64`.
- Rebuilds in-process native modules such as `better-sqlite3`, `node-pty`, and plugin `classic-level` for ARM64.
- Replaces the native Windows updater with an ARM64 no-op stub so the desktop bootstrap can load while local packages stay outside Microsoft Store update flow.
- Replaces ARM64 helper executables when upstream ARM64 assets are available.
- Embeds an explicit `asInvoker` manifest in the Windows sandbox setup helper to prevent UAC installer detection after Codex copies the helper outside the MSIX package.
- Adds and validates an ARM64 WSL Codex runtime source at `app\resources\codex` and `app\resources\codex-resources\bwrap`.
- Allows x64 fallback only for separate out-of-process tools where ARM64 replacement is unavailable.

## Current Support Status

The package was a best-effort compatibility build for Windows on ARM. It is superseded by the official Codex app and should not be used for new installations.

Issues and pull requests are no longer actively accepted because the repository is archived.

## Contributors

Thanks to everyone who has contributed to this project.

<a href="https://github.com/airtaxi/codex-app-windows-arm64/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=airtaxi/codex-app-windows-arm64" alt="Contributors" />
</a>

## License

Codex App Windows ARM64 is licensed under the [MIT License](LICENSE).

## Author

Created by [Howon Lee (airtaxi)](https://github.com/airtaxi).

Built with help from OpenAI Codex.
