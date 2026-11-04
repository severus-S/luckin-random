import argparse
import json
import os
import platform
import shutil
import subprocess
from pathlib import Path
from project import ROOT, config, generate
from validate_ipa import validate


def run(args):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), check=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--app', default='MyFirstApp')
    a = p.parse_args()
    assert platform.system() == 'Darwin', 'Xcode build requires macOS; use GitHub Actions from Windows'
    folder, c = config(a.app)
    project = generate(a.app)
    if c.get('testPackage'):
        run(['swift', 'test', '--package-path', folder])
    work = ROOT / 'build' / a.app
    out = ROOT / 'artifacts' / a.app
    out.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    run(['xcodebuild', '-version'])
    run(['xcodebuild', '-showsdks'])
    build = os.environ.get('GITHUB_RUN_NUMBER', '1')
    run(['xcodebuild', '-project', project, '-target', a.app, '-configuration', 'Release', '-sdk', 'iphoneos', '-arch', 'arm64', f'CONFIGURATION_BUILD_DIR={work / "products"}', f'OBJROOT={work / "obj"}', 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', f'CURRENT_PROJECT_VERSION={build}', 'build'])
    app = work / 'products' / f'{a.app}.app'
    assert app.is_dir(), 'Xcode produced no app'
    # Native tools validate executable architecture and plist before packaging.
    run(['plutil', '-lint', app / 'Info.plist'])
    run(['xcrun', 'lipo', app / a.app, '-verify_arch', 'arm64'])
    run(['xcrun', 'otool', '-hv', app / a.app])
    signature = subprocess.run(['codesign', '--display', str(app)], capture_output=True, text=True)
    assert signature.returncode != 0 and 'not signed at all' in signature.stderr, 'Unexpected signing state; inspect codesign before distributing unsigned IPA'
    assert not (app / '_CodeSignature').exists(), 'Unexpected signing resources'
    payload = work / 'package' / 'Payload'
    payload.mkdir(parents=True, exist_ok=True)
    dest = payload / app.name
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(app, dest, symlinks=True)
    ipa = out / f'{a.app}-unsigned.ipa'
    ipa.unlink(missing_ok=True)
    run(['ditto', '-c', '-k', '--keepParent', payload, ipa])
    result = validate(ipa, c['bundleId'])
    result.update(commit=os.environ.get('GITHUB_SHA', ''), runId=os.environ.get('GITHUB_RUN_ID', ''), unsignedBuild=True, validation='structure/plist/Mach-O/codesign unsigned check; installation not tested')
    (out / 'manifest.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    (out / 'SHA256SUMS').write_text(f"{result['sha256']}  {ipa.name}\n", encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
