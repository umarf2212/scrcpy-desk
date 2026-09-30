# Bundled components

Scrcpy Desk is an independent native frontend for scrcpy. It is not affiliated with or endorsed by Genymobile or Google.

## scrcpy 4.1

Official source and release: https://github.com/Genymobile/scrcpy/releases/tag/v4.1
Source code and build instructions: https://github.com/Genymobile/scrcpy/tree/v4.1
License: Apache License 2.0. The upstream LICENSE is preserved inside each Engine architecture folder, along with upstream icons and manual. The client and server are from the official release archives. Client code is unchanged; binaries receive a local ad-hoc signature for packaging.

- scrcpy-macos-aarch64-v4.1.tar.gz SHA-256: 20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3
- scrcpy-macos-x86_64-v4.1.tar.gz SHA-256: ee2a7223bc8dbdc4f482db1134bcf441178dafb833492b71ca4c22090c58ce72

The official static scrcpy builds include FFmpeg, SDL and libusb. Their licenses and corresponding source/build information are available from:

- FFmpeg: https://ffmpeg.org/legal.html and https://github.com/FFmpeg/FFmpeg
- SDL: https://github.com/libsdl-org/SDL (zlib license)
- libusb: https://github.com/libusb/libusb (LGPL 2.1 or later)
- Upstream release build scripts: https://github.com/Genymobile/scrcpy/tree/v4.1/release

## Android Debug Bridge

ADB is included from the same official scrcpy release archives. The architecture-specific slice is retained and ad-hoc signed. Android Open Source Project: https://android.googlesource.com/platform/packages/modules/adb/
ADB licensing and notices: https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/NOTICE

Retain the bundled upstream notices when redistributing. Before public distribution, review all static dependency license requirements and use your own Developer ID signing/notarization.
