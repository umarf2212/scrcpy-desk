#!/usr/bin/env python3
"""Build a self-contained, ad-hoc signed Universal macOS app and DMG. macOS + Swift CLT required."""
import hashlib, pathlib, plistlib, shutil, subprocess, sys, tarfile, urllib.request
SOURCE = pathlib.Path(__file__).resolve().parent
OUT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else SOURCE.parent
WORK = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else SOURCE / 'build'
OUT.mkdir(parents=True, exist_ok=True); WORK.mkdir(parents=True, exist_ok=True)
def run(*args): subprocess.run([str(a) for a in args], check=True)
releases = {
 'arm64': ('aarch64', '20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3'),
 'x86_64': ('x86_64', 'ee2a7223bc8dbdc4f482db1134bcf441178dafb833492b71ca4c22090c58ce72')}
app = OUT / 'Scrcpy Desk.app'
if app.exists(): shutil.rmtree(app)
macos = app / 'Contents/MacOS'; resources = app / 'Contents/Resources'
macos.mkdir(parents=True); resources.mkdir()
for arch, (upstream, checksum) in releases.items():
    archive = WORK / f'vendor/{arch}.tar.gz'; archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists(): urllib.request.urlretrieve(f'https://github.com/Genymobile/scrcpy/releases/download/v4.1/scrcpy-macos-{upstream}-v4.1.tar.gz', archive)
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == checksum, 'Upstream checksum mismatch'
    dest = resources / f'Engine/{arch}'; dest.mkdir(parents=True)
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            name = pathlib.PurePosixPath(member.name).name
            if name in ['scrcpy', 'scrcpy-server', 'adb', 'LICENSE', 'scrcpy.png', 'disconnected.png', 'scrcpy.1'] and member.isfile():
                (dest / name).write_bytes(tar.extractfile(member).read())
    for exe in ['scrcpy', 'adb']:
        (dest / exe).chmod(0o755)
        if exe == 'adb':
            run('lipo', dest / exe, '-thin', arch, '-output', dest / 'adb-thin')
            (dest / 'adb-thin').replace(dest / exe)
        run('codesign', '--force', '--sign', '-', dest / exe)
    binary = WORK / f'ScrcpyDesk-{arch}'
    run('swiftc', '-swift-version', '5', '-O', '-target', f'{arch}-apple-macosx13.0', SOURCE / 'Core.swift', SOURCE / 'Model.swift', SOURCE / 'Updater.swift', SOURCE / 'App.swift', '-o', binary, '-module-cache-path', WORK / 'module-cache')
run('lipo', '-create', WORK / 'ScrcpyDesk-arm64', WORK / 'ScrcpyDesk-x86_64', '-output', macos / 'ScrcpyDesk')
run('swift', '-module-cache-path', WORK / 'module-cache', SOURCE / 'Icon.swift', WORK / 'icon.png')
iconset = WORK / 'AppIcon.iconset'; iconset.mkdir(exist_ok=True)
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        target = iconset / f'icon_{size}x{size}{"@2x" if scale == 2 else ""}.png'
        run('sips', '-z', size * scale, size * scale, WORK / 'icon.png', '--out', target)
run('iconutil', '-c', 'icns', iconset, '-o', resources / 'AppIcon.icns')
info = {'CFBundleName': 'Scrcpy Desk', 'CFBundleDisplayName': 'Scrcpy Desk', 'CFBundleIdentifier': 'local.scrcpydesk.app', 'CFBundleVersion': '2', 'CFBundleShortVersionString': '1.1.0', 'CFBundleExecutable': 'ScrcpyDesk', 'CFBundlePackageType': 'APPL', 'CFBundleIconFile': 'AppIcon', 'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication', 'NSLocalNetworkUsageDescription': 'Connect to Android devices with wireless debugging on your local network.'}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
helptext = subprocess.check_output([str(resources / 'Engine/arm64/scrcpy'), '--help']) if subprocess.check_output(['uname', '-m']).strip() == b'arm64' else subprocess.check_output([str(resources / 'Engine/x86_64/scrcpy'), '--help'])
(resources / 'scrcpy-help.txt').write_bytes(helptext)
for name in ['README.md', 'THIRD-PARTY.md']: shutil.copy2(SOURCE / name, resources / name)
run('codesign', '--force', '--deep', '--sign', '-', app)
run('codesign', '--verify', '--deep', '--strict', '--verbose=2', app)
stage = WORK / 'dmg-stage'
if stage.exists(): shutil.rmtree(stage)
stage.mkdir(); shutil.copytree(app, stage / app.name); (stage / 'Applications').symlink_to('/Applications')
shutil.copy2(SOURCE / 'README.md', stage / 'Read Me.md')
dmg = OUT / 'Scrcpy-Desk-1.1-Universal.dmg'
if dmg.exists(): dmg.unlink()
run('hdiutil', 'create', '-volname', 'Scrcpy Desk', '-srcfolder', stage, '-ov', '-format', 'UDZO', dmg)
print(f'Built {app}\nBuilt {dmg}')
