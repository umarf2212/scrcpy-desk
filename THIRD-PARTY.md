# Bundled components

Scrcpy Desk is an independent native frontend for scrcpy. It is not affiliated with or endorsed by Genymobile or Google.

## scrcpy 5.0

Official source and release: https://github.com/Genymobile/scrcpy/releases/tag/v5.0
Source code and build instructions: https://github.com/Genymobile/scrcpy/tree/v5.0
License: Apache License 2.0. The upstream LICENSE is preserved inside each Engine architecture folder, along with upstream icons and manual. The client and server are from the official release archives. Client code is unchanged; binaries receive a local ad-hoc signature for packaging.

- scrcpy-macos-aarch64-v5.0.tar.gz SHA-256: 7cb4e41c859b05b36e89dc9be6c353cc5980c00d7f7f6a763b5b355551b82e9c
- scrcpy-macos-x86_64-v5.0.tar.gz SHA-256: dacb995c8eb42528cb96b2da2a2e3110fe5c82281378e6044fc7cccf48a7c39a

The official static scrcpy builds include FFmpeg, SDL, libusb and dav1d. Their licenses and corresponding source/build information are available from:

- FFmpeg: https://ffmpeg.org/legal.html and https://github.com/FFmpeg/FFmpeg
- SDL: https://github.com/libsdl-org/SDL (zlib license)
- libusb: https://github.com/libusb/libusb (LGPL 2.1 or later)
- dav1d: https://code.videolan.org/videolan/dav1d (BSD 2-clause license)
- Upstream release build scripts: https://github.com/Genymobile/scrcpy/tree/v5.0/release

## Android Debug Bridge

ADB 37.0.1 (37.0.1-15733141) is included from the same official scrcpy 5.0 release archives. The architecture-specific slice is retained and ad-hoc signed. Android Open Source Project: https://android.googlesource.com/platform/packages/modules/adb/
ADB licensing and notices: https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/NOTICE

Retain the bundled upstream notices when redistributing. Before public distribution, review all static dependency license requirements and use your own Developer ID signing/notarization.
