"""Build a source-only handoff; never includes credentials, dependencies or IPA files."""
import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FOLDERS = ['apps/LuckinRandom', 'services/luckin-random', 'docs/luckin-random', 'templates/SwiftUI-App']
FILES = ['AGENTS.md', '.gitignore', '.gitattributes', '.github/workflows/build-ios.yml',
         'scripts/project.py', 'scripts/ci_build.py', 'scripts/validate_ipa.py',
         'scripts/selftest.py', 'scripts/new_app.py', 'scripts/new-app.ps1',
         'scripts/common.ps1', 'scripts/build-ios.ps1', 'scripts/download-ipa.ps1',
         'scripts/deploy-ios.ps1', 'scripts/publish-ios.ps1', 'scripts/package-luckin.py',
         'docs/IOS_WORKFLOW.md', 'docs/BUILD_AND_DEPLOY.md', 'docs/SIDELOAD_AND_RENEW.md',
         'docs/TROUBLESHOOTING.md']
EXCLUDE = {'node_modules', 'dist', '.local', '.build', '.swiftpm', '__pycache__', 'xcuserdata'}


def main():
    paths = [ROOT / f for f in FILES]
    for folder in FOLDERS:
        for path in (ROOT / folder).rglob('*'):
            if not path.is_file() or EXCLUDE.intersection(path.relative_to(ROOT).parts):
                continue
            if path.name.startswith('.env') or path.suffix in {'.sqlite', '.ipa', '.p12', '.p8', '.mobileprovision', '.log', '.pyc'}:
                continue
            paths.append(path)
    out = ROOT / 'artifacts/LuckinRandom-source-0.1.0.zip'
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(set(paths)):
            z.write(path, path.relative_to(ROOT).as_posix())
        z.writestr('README.md', '# Luckin Random source 0.1.0\n\nSource only; no IPA, no real payment validation.\n\nStart with docs/luckin-random/PROGRESS.md and BUILD.md.\nBackend: services/luckin-random/README.md. Native app: apps/LuckinRandom/README.md.\n')
    with zipfile.ZipFile(out) as z:
        assert z.testzip() is None
        assert not any(EXCLUDE.intersection(Path(n).parts) for n in z.namelist())
    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    out.with_suffix('.zip.sha256').write_text(f'{digest}  {out.name}\n', encoding='utf-8')
    print(out)
    print(f'{len(set(paths)) + 1} files; SHA256 {digest}; source package, NOT IPA')


if __name__ == '__main__':
    main()
