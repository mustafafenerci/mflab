# macOS and Linux builds

MF Lab is a Flutter desktop app. Windows, macOS and Linux share the UI and the Docker logic; everything
that depends on the operating system goes through `lib/platform.dart` (`Os`) or a `Platform` branch in
`lib/engine.dart` and `lib/preflight.dart`.

## What differs per platform

| Area | Windows | macOS | Linux |
| --- | --- | --- | --- |
| Work folder | `C:\MFLab\<user>` | `~/MFLab` | `~/MFLab` |
| Config pointer | `%APPDATA%\MFLab` | `~/Library/Application Support/MFLab` | `~/.config/MFLab` |
| Installer | Inno Setup `.exe` | `.dmg` | `.deb`, `.tar.gz` |
| In-app update | silent installer | opens the release page | opens the release page |
| Tray icon / autostart | yes | not yet | not yet |
| Docker | Docker Desktop (WSL 2) | Docker Desktop (started with `open -a Docker`) | Docker Engine (user must be in the `docker` group) |
| Desktop shortcuts | `.lnk` / `.url` | `.webloc` folder on the Desktop | `.desktop` folder on the Desktop |
| Zip for homework | PowerShell `Compress-Archive` | `zip` | `zip` (a `.deb` dependency) |
| File picker | PowerShell dialog | `osascript` | `zenity` or `kdialog` |

## Build locally

```bash
flutter pub get
flutter analyze && flutter test --exclude-tags network

# macOS (on a Mac)
flutter build macos --release
bash scripts/package_macos.sh 1.2.2 dist        # dist/MFLab-v1.2.2-macos.dmg

# Linux (on Ubuntu/Debian)
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
flutter build linux --release
bash scripts/package_linux.sh 1.2.2 dist        # .deb and .tar.gz
```

## macOS signing and notarization

Without secrets the workflow produces an ad-hoc signed `.dmg` (Gatekeeper shows a warning; users have to
right-click, Open). For a signed and notarized build add these repository secrets
(Settings, Secrets and variables, Actions):

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | `base64 -i DeveloperIDApplication.p12` (Developer ID Application certificate exported from Keychain Access) |
| `MACOS_CERTIFICATE_PWD` | the password chosen when exporting the `.p12` |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` (`security find-identity -v -p codesigning`) |
| `APPLE_ID` | the Apple ID e-mail |
| `APPLE_TEAM_ID` | the 10-character team id |
| `APPLE_APP_PASSWORD` | an app-specific password from appleid.apple.com |

The bundle identifier is `com.mustafafenerci.mflab` (`macos/Runner/Configs/AppInfo.xcconfig`); change it
there if the Apple Developer account uses another identifier. The app sandbox is turned off in
`macos/Runner/*.entitlements` on purpose: MF Lab has to start Docker and read the user's work folder.

## Release

Pushing a tag `vX.Y.Z` runs `.github/workflows/release.yml`: the Windows, Linux and macOS jobs each upload
their files (plus `.sha256`) to the same GitHub release. `ci.yml` builds all three on every push.

## Not done yet

* English user interface (all texts are Turkish today).
* Tray icon, autostart and silent self-update on macOS and Linux.
* Linux: AppImage / Flatpak, arm64.
