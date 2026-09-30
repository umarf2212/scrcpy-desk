# Scrcpy Desk 1.1

A lightweight native macOS control panel for scrcpy. Universal app for Apple Silicon and Intel, macOS 13 Ventura or later. scrcpy 4.1 and ADB are included; no Homebrew, Java runtime, Electron, or Terminal setup is needed.

## Install & start

1. Open the DMG and drag **Scrcpy Desk.app** to **Applications**. You can also run the provided app directly from any writable folder.
2. Open the app. This personal build is ad-hoc signed, not Apple-notarized. If macOS blocks it, try opening it once, then use **System Settings → Privacy & Security → Open Anyway** and confirm. Only do this for your trusted copy. No system-wide security changes are required.
3. On Android, enable Developer options (usually tap Build number seven times), then USB debugging. Connect a data-capable USB cable, unlock the phone, and accept its debugging authorization prompt.
4. Select your device, choose a preset, and click **Start Mirroring**. scrcpy opens a separate mirroring window. Use **Stop Mirroring** or close that window to finish.

For Wi-Fi, choose **Connect over Wi-Fi**. On Android 11+, use the pairing-code dialog's IP and port to pair once, then the main Wireless debugging screen's IP and port to connect. These ports differ. A device previously configured for TCP/IP can also be connected by its IP:port.

## Features

- Automatic device refresh every five seconds, with authorization/offline states
- Responsive, Balanced, and Crisp quality presets
- Resolution cap, frame rate, bitrate and H.264/H.265/AV1 codecs
- Audio sources/codecs, keyboard/mouse modes, clipboard sync, screen off, stay awake, touch indicators
- Fullscreen, always-on-top, borderless, rotation, crop and window title
- MP4/MKV recordings with a save picker and overwrite confirmation; MKV is the default for broad codec support
- Quoted advanced arguments, command preview/copy, and bounded/exportable session logs
- Locally saved settings, graceful stop and quit, and a Finder link to the last recording
- Official GitHub engine updater, daily idle checks, SHA-256 verification and rollback

Options apply to the next session. Additional arguments run directly as scrcpy arguments, never through a shell. Avoid repeating UI options in the additional arguments field. Extra options can intentionally change mirroring behavior; see the bundled option reference. The copied command expects `scrcpy` on your shell PATH, while the app itself always uses its bundled engine.

Audio needs Android 11+; app playback capture needs Android 13+. Device encoders vary: if H.265 or AV1 fails, use Balanced/H.264. Use AAC audio with MP4 for compatibility, or MKV for more codec choices. Some vendors require an additional “USB debugging (Security settings)” switch for input control. Content protected by Android may not mirror.

Stop a recording normally to let it finalize. If an unresponsive session must be forcibly terminated, its file may be incomplete. Closing the control panel quits the app and stops its mirror session. The app does not kill the shared ADB server, which other Android tools may use.

## scrcpy updates

Open **Updates → Check & Update**, or **Scrcpy Desk → Check for scrcpy Updates…**. A newer stable release is downloaded and installed automatically after the check. The daily automatic check is on by default and can be disabled in Updates; it runs only while the app is open and idle. No mirror session is interrupted. Failed checks are shown in Updates and Activity and can be retried manually.

The updater compares version numbers numerically, selects this Mac’s architecture, requires the official GitHub asset URL and SHA-256 digest, verifies download size/hash, then checks that scrcpy and ADB run and that required CLI options remain available. Drafts, prereleases, unsupported Mac downloads, unverified assets and incompatible engines are rejected. It updates scrcpy, its matching server and bundled ADB together.

The signed app bundle is never modified. Updates are stored under `~/Library/Application Support/Scrcpy Desk/Engines/<architecture>/`. A small atomic manifest selects the engine only after installation succeeds. The previous engine and the bundled 4.1 fallback remain available. **Restore scrcpy …** rolls back and disables automatic updates to keep the restored version selected. Updated help is shown by Full option reference. No admin password, Homebrew, developer tools or restart is needed.

These updates apply to the scrcpy engine, not the native Scrcpy Desk frontend. When copying the app to another Mac, the bundled engine travels with it; that Mac can independently fetch the newest engine. Moving the app on the same Mac preserves its downloaded engine.

## Privacy & storage

No analytics. The updater contacts GitHub’s official release API and release asset servers. Device discovery uses local ADB. Wi-Fi pairing connects only to the endpoint entered. Settings are stored in macOS UserDefaults under `local.scrcpydesk.app`; recordings are saved where you choose. Logs are held in memory (bounded to approximately 120 KB) unless exported. Logs can contain device identifiers, network addresses, and paths; review them before sharing. ADB stores its standard authorization keys in `~/.android`.

## Build from source

Install Apple's Command Line Tools and Python 3, then run:

```
python3 build.py /path/to/deliverables /path/to/build-work
```

The build script downloads the official scrcpy 4.1 archives, verifies pinned SHA-256 checksums, compiles the native SwiftUI launcher for both architectures, creates the icon, ad-hoc signs the bundle and creates a compressed DMG. Internet access is required for the first build. No third-party Swift packages are used.

Run command-building/parser checks with:

```
swiftc Core.swift Tests.swift -o /tmp/scrcpydesk-tests
/tmp/scrcpydesk-tests
```

See THIRD-PARTY.md for upstream provenance. This is an independent frontend, not an official Genymobile app.
