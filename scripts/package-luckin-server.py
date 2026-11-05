"""Build/test locally; package locked, pure-JavaScript runtime for Linux."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'services/luckin-random'
output = root / 'artifacts/luckin-server'
output.mkdir(parents=True, exist_ok=True)
npm = shutil.which('npm.cmd' if os.name == 'nt' else 'npm')
if not npm:
    raise SystemExit('Node.js 22.14+ and npm are required')
for args in (['ci', '--ignore-scripts', '--no-audit', '--no-fund'], ['test']):
    subprocess.run([npm, *args], cwd=source, check=True)
with tempfile.TemporaryDirectory(prefix='luckin-runtime-') as temporary:
    stage = Path(temporary)
    for name in ('package.json', 'package-lock.json'):
        shutil.copy2(source / name, stage / name)
    for name in ('dist', 'migrations'):
        shutil.copytree(source / name, stage / name)
    subprocess.run([npm, 'ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=stage, check=True)
    if list(stage.rglob('*.node')):
        raise SystemExit('Native dependency detected: a target-platform build is required')
    def metadata(info):
        info.uid = info.gid = info.mtime = 0
        info.uname = info.gname = ''
        info.mode = 0o755 if info.isdir() else 0o644
        return info
    package = output / 'backend-runtime.tar.gz'
    with package.open('wb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for item in sorted(stage.iterdir()):
                archive.add(item, arcname=item.name, filter=metadata)
digest = hashlib.sha256(package.read_bytes()).hexdigest()
(output / 'manifest.json').write_text(json.dumps({'sha256': digest, 'tests': 'npm test passed (Mock only); see command output', 'nativeDependencies': False}, indent=2) + '\n', encoding='utf-8')
print(f'{package}\nSHA256 {digest}')
