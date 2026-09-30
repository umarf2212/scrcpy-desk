# Verification

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
