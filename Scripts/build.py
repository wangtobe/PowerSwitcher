#!/usr/bin/env python3
"""Build a relocatable Universal 2 app with Apple's installed command-line tools."""
from pathlib import Path
import os, plistlib, shutil, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
VERSION = '1.6.1'
def run(*args): subprocess.run(args, check=True)
def generate(destination):
    # The app prepends mode and daily timers at runtime (see PowerCommand.script).
    body = (ROOT / 'Scripts/power.sh').read_text()
    assert '"""#' not in body
    text = 'enum PowerScripts {\n'
    text += 'static let body = #"""\n' + body + '"""# + "\\n"\n'
    text += '}\n'
    destination.write_text(text)

def main():
    with tempfile.TemporaryDirectory(prefix='powerswitcher-build-') as tmp:
        work = Path(tmp)
        generate(work / 'PowerScripts.swift')
        # Compile copied sources so personal filesystem paths are not embedded.
        sources = []
        for source in sorted((ROOT / 'Sources').glob('*.swift')):
            shutil.copyfile(source, work / source.name)
            sources.append(str(work / source.name))
        sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
        binaries = []
        for arch in ('arm64', 'x86_64'):
            binary = work / arch
            run('xcrun', 'swiftc', '-O', '-sdk', sdk, '-target', arch + '-apple-macos13.0',
                '-module-cache-path', str(work / 'cache'), *sources,
                str(work / 'PowerScripts.swift'), '-o', str(binary))
            binaries.append(str(binary))
        app = work / 'PowerSwitcher.app'
        contents = app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Resources').mkdir()
        run('xcrun', 'lipo', '-create', *binaries, '-output', str(contents / 'MacOS/PowerSwitcher'))
        shutil.copyfile(ROOT / 'Assets/PowerIcon.icns', contents / 'Resources/PowerIcon.icns')
        info = dict(CFBundleExecutable='PowerSwitcher', CFBundleIdentifier='org.powerswitcher.app',
                    CFBundleName='PowerSwitcher', CFBundleDisplayName='PowerSwitcher', CFBundleDevelopmentRegion='en', CFBundleLocalizations=['en', 'zh-Hans', 'zh-Hant'], CFBundlePackageType='APPL',
                    NSHumanReadableCopyright='© 2026 Tobe Wang & contributors', CFBundleShortVersionString=VERSION, CFBundleVersion='11', CFBundleIconFile='PowerIcon',
                    LSMinimumSystemVersion='13.0', LSUIElement=True, NSHighResolutionCapable=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        identity = os.environ.get('SIGNING_IDENTITY', '-')
        args = ['codesign', '--force', '--sign', identity]
        if identity != '-': args += ['--options', 'runtime', '--timestamp']
        run(*args, str(app))
        run('codesign', '--verify', '--strict', str(app))
        run(str(contents / 'MacOS/PowerSwitcher'), '--self-test')
        dist = ROOT / 'dist'; dist.mkdir(exist_ok=True)
        archive = dist / ('PowerSwitcher-' + VERSION + '-universal-installer.zip')
        # Zip in temporary storage to avoid cloud-provider metadata contaminating signatures.
        run('/usr/bin/ditto', '-c', '-k', '--norsrc', '--keepParent', str(app), str(work / 'release.zip'))
        shutil.copyfile(work / 'release.zip', archive)
        print(archive)
if __name__ == '__main__': main()
