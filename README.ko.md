# Codex App Windows ARM64

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![기여자](https://img.shields.io/github/contributors/airtaxi/codex-app-windows-arm64)](https://github.com/airtaxi/codex-app-windows-arm64/graphs/contributors)

🌐 [English](README.md) | 한국어

Codex App Windows ARM64는 공식 Windows x64 Codex 앱을 Windows on ARM에서 실행하기 위한 비공식 재패키징 스크립트입니다. Microsoft Store에 설치된 Codex x64 패키지를 가져와 가능한 런타임과 네이티브 payload를 ARM64 호환 빌드로 교체하고, 로컬 자체 서명 ARM64 MSIX 패키지를 생성합니다.

이 프로젝트는 OpenAI가 Codex 앱의 공식 Windows ARM64 지원을 제공할 때까지 유지될 예정입니다.

## Disclaimer

이 프로젝트는 OpenAI와 제휴 관계가 없으며, OpenAI가 보증하거나 후원하거나 공식 지원하는 프로젝트가 아닙니다. 로컬 실험과 호환성 작업을 위한 독립 커뮤니티 도구입니다.

OpenAI, Codex 및 ChatGPT는 OpenAI의 상표입니다. 그 외 모든 상표는 각 소유자의 자산입니다.

## 요구사항

- Windows on ARM 장치.
- Microsoft Store에서 설치한 공식 Codex x64 앱 또는 Microsoft Store CDN에서 다운로드한 공식 x64 Codex MSIX.
- PowerShell 7(`pwsh`) 권장. Windows PowerShell은 fallback으로만 사용됩니다.
- `PATH`에서 사용할 수 있는 Node.js, `node`, `pnpm`.
- `makeappx.exe`, `signtool.exe`, `mt.exe`를 포함한 Windows SDK 도구.
- upstream Linux ARM64 runtime asset 압축 해제를 위해 `PATH`에서 사용할 수 있는 `tar.exe`.
- ARM64 C++ toolchain이 포함된 Visual Studio C++ desktop build tools.
- Electron, Node.js, Codex helper 바이너리, ripgrep, 네이티브 모듈 빌드 의존성 다운로드를 위한 인터넷 연결.

## Release에서 빠르게 설치

Scoop 사용:

```powershell
scoop bucket add codex-woa https://github.com/airtaxi/codex-app-windows-arm64
scoop install codex-woa
```

일반적인 업데이트:

```powershell
scoop update
scoop update codex-woa
```

[GitHub Releases](https://github.com/airtaxi/codex-app-windows-arm64/releases) 페이지에서 release zip을 다운로드하고 압축을 푼 뒤 다음 파일을 실행합니다.

```bat
Install.bat
```

설치하기 전에 Codex를 완전히 종료하세요. `Install.bat`은 `Install.ps1`을 실행합니다. 설치 스크립트는 MSIX 서명자가 포함된 인증서와 일치하는지 확인하고, 필요하면 로컬 인증서를 신뢰 저장소에 등록하고, 생성된 MSIX 패키지를 설치한 뒤 현재 사용자의 Windows Computer Use 기능 플래그를 활성화합니다.

재패키징 앱을 제거하려면 Windows 설정에서 Codex WoA를 제거하세요. 설치 프로그램은 로컬 인증서 신뢰 및 Computer Use 기능 플래그를 의도적으로 유지합니다. 기능 플래그를 수동으로 비활성화하려면 다음 명령을 실행하세요.

```powershell
[Environment]::SetEnvironmentVariable("CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE", $null, "User")
```

## 빌드

이 저장소에서 빌드 래퍼를 실행합니다.

```bat
Build-CodexWoA.bat -SourceMode StoreMsix -Force
```

`-SourceMode StoreMsix`는 최신 공식 Codex x64 MSIX를 Microsoft Store 링크에서 다운로드하고 SHA-1을 검증한 뒤 소스 패키지로 사용합니다.

`-SourceMode Installed`는 Microsoft Store에서 이미 설치된 공식 Codex x64 패키지를 사용합니다.

`-SourceMode StoreLatest`는 MSIX를 직접 다운로드하지 않습니다. Microsoft Store를 열어 Codex를 공식 경로로 설치하거나 업데이트하게 한 뒤, 설치된 x64 패키지를 사용해 계속 진행합니다.

`-SourceMode Msix -SourceMsixPath <path>`는 공식 x64 Codex MSIX를 직접 추출해 소스 패키지로 사용합니다.

기본 출력 디렉터리는 `dist`입니다.

## 출력물

빌드가 성공하면 다음 파일이 생성됩니다.

- `dist\Codex-WoA_<version>_arm64.msix`
- `dist\cert\CodexWoA.cer`
- `dist\Install.ps1`
- `dist\Install.bat`
- `dist\build-report.json`

인증서는 필요할 때 로컬에서 생성되며 저장소에 커밋하지 않습니다.

## 스크립트가 변경하는 것

- `AppxManifest.xml`을 ARM64 패키지 identity에 맞게 재작성합니다.
- Electron 런타임을 `win32-arm64`로 교체합니다.
- 번들된 Node.js를 `win-arm64`로 교체합니다.
- `better-sqlite3`, `node-pty`, plugin `classic-level` 같은 in-process 네이티브 모듈을 ARM64로 rebuild합니다.
- Desktop bootstrap이 로드할 수 있도록 native Windows updater를 ARM64 no-op stub으로 교체하고, 로컬 패키지는 Microsoft Store 업데이트 흐름 밖에 둡니다.
- upstream ARM64 asset이 있는 helper 실행 파일을 ARM64 버전으로 교체합니다.
- Codex가 Windows sandbox setup helper를 MSIX 패키지 외부로 복사한 뒤 UAC installer detection이 발생하지 않도록 명시적인 `asInvoker` manifest를 삽입합니다.
- `app\resources\codex` 및 `app\resources\codex-resources\bwrap`에 ARM64 WSL Codex runtime source를 추가하고 검증합니다.
- ARM64 대체가 불가능한 별도 out-of-process 도구에만 x64 fallback을 허용합니다.

## 현재 지원 상태

이 패키지는 Windows on ARM을 위한 best-effort 호환성 빌드입니다. 앱 실행, 로그인 흐름, 대화 사용, ARM64 `node-pty`, ARM64 `rg.exe` 교체는 로컬에서 검증했지만, 공식 OpenAI 지원을 대체하지는 않습니다.

네이티브 의존성 업데이트, helper 바이너리 교체, 패키징 검증, Windows on ARM 런타임 동작과 관련된 제보와 pull request를 환영합니다.

## 기여자

이 프로젝트에 기여해 주신 모든 분들께 감사드립니다.

<a href="https://github.com/airtaxi/codex-app-windows-arm64/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=airtaxi/codex-app-windows-arm64" alt="기여자" />
</a>

## 라이선스

Codex App Windows ARM64는 [MIT 라이선스](LICENSE)로 배포됩니다.

## 제작자

[이호원 (airtaxi)](https://github.com/airtaxi)이 만들었습니다.

OpenAI Codex의 도움을 받아 제작되었습니다.
