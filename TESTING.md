# Verification

## scrcpy 5.0 in 1.3.2 — October 8, 2026

- Official Apple Silicon and Intel scrcpy 5.0 archives match the pinned GitHub SHA-256 digests and upstream SHA256SUMS.txt. Both archives include the matching Android server; its hash matches the separately published scrcpy-server-v5.0 asset.
- Both launcher targets compile for macOS 13+. The launcher contains arm64 and x86_64 slices; each packaged scrcpy and ADB binary has the intended architecture. The engine binaries' minimum OS versions remain below macOS 13.
- Bundled Apple Silicon scrcpy reports 5.0 and ADB reports 37.0.1-15733141. All 24 CLI flags used by the frontend are present in the 5.0 help, including virtual display support. The generated option reference includes --hwdec.
- 39 core checks and 40 updater checks passed. Updater coverage includes a newer bundle superseding an older cached engine, preserving downloaded engines at or above the bundled version, and rollback skipping superseded engines. Real 5.0 archive installation, checksum/extraction failure handling, and the live GitHub API/download checksum check passed.
- Process integration passed for discovery, session launch/stop, recording, virtual display arguments, Wi-Fi pairing and automatic connection, separate USB/Wi-Fi environments, and private-server cleanup. The fixture's Unix socket requires execution outside the sandbox.
- Universal app signature verified with codesign --verify --deep --strict. Compressed DMG checksum verified with hdiutil; a read-only mount contains the signed app, working scrcpy 5.0, and the Applications shortcut. Apple's icon and disk-image tools required execution outside the sandbox.

To repeat updater verification with the current engine:

```
gh api repos/Genymobile/scrcpy/releases/tags/v5.0 > /tmp/scrcpy-5.0-release.json
gh release download v5.0 --repo Genymobile/scrcpy --pattern 'scrcpy-macos-aarch64-v5.0.tar.gz' --dir /tmp/scrcpy-5.0
swiftc Core.swift Updater.swift UpdaterTests.swift -o /tmp/scrcpy-updater-tests
/tmp/scrcpy-updater-tests /tmp/scrcpy-5.0-release.json /tmp/scrcpy-5.0/scrcpy-macos-aarch64-v5.0.tar.gz --live
```

Use the x86_64 archive on an Intel Mac. No live phone mirroring or Intel hardware execution was performed for this engine update. The app remains ad-hoc signed and is not Apple-notarized. Earlier verification results below describe prior releases.

Verified on Apple Silicon running macOS 26:

- Both arm64 and x86_64 launcher targets compile with a macOS 13 deployment target.
- 24 core checks pass: device parsing, quoted arguments, literal shell metacharacters, option mapping, no-control exclusions, recording paths, invalid input, presets and settings serialization.
- Integration harness passes against deterministic mock ADB/scrcpy processes: async discovery, selected device, process launch, argument preservation, recording path containing spaces, normal completion, stopping a live process, network connect workflow and invalid-input rejection. Run `./test-integration.sh` to repeat.
- Real app launched and inspected through macOS accessibility and screenshots: empty state, preset selection updates, advanced command preview, reset and wireless pairing sheet.
- Bundled arm64 scrcpy and ADB launch and print their versions. Official archive SHA-256 values match the pinned upstream values.
- DMG checksum verified; mounted read-only and verified the contained app signature and Applications shortcut.
- Universal launcher inspected and app's ad-hoc signature verified using `codesign --verify --deep --strict`.

Limits: no Android device was attached, so live video/audio, physical input, real Wi-Fi pairing and real recording playback were not tested. Intel binaries were built and packaged but were not run on an Intel Mac. This personal build is not Developer ID signed or notarized.

## Updater in 1.1

UpdaterTests.swift covers numeric version ordering, stable-release and architecture selection, download-origin and SHA-256 requirements, official-archive installation, generated help, checksum/extraction failure preserving the active engine, persistent engine selection, rollback, bundled fallback, corrupted manifest handling, path validation and HTTP errors. Install tests use an isolated temporary Application Support substitute and the real official 4.1 archive. They exercise an update candidate from 4.0 without changing the app’s bundled version.

Compile and run (provide official release JSON and a matching archive):

```
swiftc Core.swift Updater.swift UpdaterTests.swift -o /tmp/scrcpy-updater-tests
/tmp/scrcpy-updater-tests /path/to/release.json /path/to/arm64.tar.gz --live
```

Use the x86_64 archive on an Intel Mac. The optional --live checks the actual GitHub API and downloads/checksums the current Mac asset. There was no newer release than 4.1 at implementation time; the app correctly reports that it is up to date.

Results: all 33 updater checks passed, plus a live GitHub API/download SHA-256 check. The existing process integration suite also passed after the change. The 1.1 native UI was inspected and its Check & Update action visibly reported that scrcpy 4.1 is up to date. Both launcher architectures compiled; the new app signature and compressed DMG checksum verified.

## Wi-Fi discovery in 1.2

- 29 core checks passed, including Android mDNS service parsing, distinct pairing/connection ports, IPv6 endpoints, and matching device names across random service suffixes.
- Process integration passed with an unpaired phone visible before authorization, one automatic connection attempt per advertisement, inline connection diagnostics, code pairing followed by automatic connection to the correct port, and diagnostic clearing on success. Existing recording, stop, arguments and invalid-input checks also passed.
- Both launcher architectures compile for macOS 13+. ADB commands execute serially to avoid competing daemon startup attempts.
- Live app discovery found the Samsung phone advertised on the local network. Inspected screenshots and accessibility of the Wi-Fi sheet at the top and bottom: instructions wrap fully and all controls are reachable by scrolling.
- The existing idle ADB daemon initially returned “No route to host” despite a successful direct TCP reachability check. Restarted the daemon under the new app; that routing error cleared. The user subsequently paired the phone and confirmed live mirroring works.
- 33 updater checks passed using the pinned 4.1 release fixture and official archive.

## Desktop option in 1.3

- 37 core checks passed, including older settings preservation, desktop resolution/density persistence, migration from manually entered virtual-display arguments, toggle-off behavior, and rejection of conflicting display selection.
- Process integration passed and confirmed that enabling the option launches scrcpy with `--new-display=1920x1080/160`. Existing session, recording and Wi-Fi checks passed.
- Both arm64 and x86_64 launchers compile for macOS 13+. Native UI inspection verified the Display card, toggle, resolution/density controls, command preview, and preservation of the existing bitrate setting.
- App signature and DMG checksum verified. The user previously confirmed this virtual-display command opens their desktop; no Android device was connected during this update’s UI check.

## Naming update in 1.3.1

Renamed the option and related help/error/documentation text to Desktop mode / virtual display. Both architectures compile. Native UI confirms the generic label and saved desktop configuration; app signature and DMG checksum verified.

## Layout redesign feature branch

- Applied Impeccable's layout, distill, clarify, Operate, and craft-floor guidance directly to the native SwiftUI interface. The context launcher could not initialize its cache in the sandbox; no engine detector ran because its HTML/CSS checks do not apply to SwiftUI.
- Both arm64 and x86_64 launchers compile for macOS 13+. The universal preview app signature verifies.
- 37 core checks and the process integration suite passed. No session-command or connection-model changes were needed.
- Native inspection covered Mirror, Audio, Control, Advanced, Activity, Updates, and the Wi-Fi sheet. Regular and near-minimum-width windows were checked (1220 and 843 points wide). Guidance wraps; the persistent session action stays visible; lower settings, command copy, and expanded manual Wi-Fi connection remain reachable by scrolling.
- The existing bitrate of 30 Mbps and enabled 1920 × 1080 / 160 dpi virtual display were preserved. Toggling the virtual display off hides its controls and updates the session summary; turning it back on restores the values.
- No phone was connected during the layout inspection. Live session behavior remains covered by the prior phone verification and process fixtures.

## Wi-Fi daemon isolation fix — October 3, 2026

- Reproduced “No route to host” from the detached shared ADB daemon while a direct TCP connection to the advertised phone port succeeded. The daemon came from an earlier app build.
- Wi-Fi now uses an app-owned foreground ADB process with a private Unix socket. USB and emulator scanning are disabled in that process; USB stays on the shared server. Pairing, discovery, device refresh, and wireless scrcpy sessions consistently use the private transport.
- 39 core checks passed. Process integration passed with a simulated shared-server routing failure, successful private-server connection/pairing, shared USB device preservation, separate USB/Wi-Fi scrcpy environments, one reused server, and private socket cleanup on shutdown. The fixture requires local IPC permission; the sandbox blocked its Unix socket, so the successful run used elevated execution.
- Both launcher architectures compile, and the universal preview app signature verifies.
- Live verification with the Samsung S23 Ultra: automatic Wi-Fi connection succeeded with existing pairing keys. A scrcpy session created the 1920 × 1080 / 160 dpi virtual display; server/device output and Metal texture rendering confirmed the working stream. Stopped the test session normally; the phone remains connected and ready.
- Process inspection confirmed the Wi-Fi server is a child of the running preview app. The original shared ADB daemon remained running throughout.
