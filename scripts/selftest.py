"""Offline infrastructure regression tests. Synthetic IPA fixtures are NOT build output."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from project import ROOT
from validate_ipa import validate


class WorkspaceTests(unittest.TestCase):
    def test_second_app_and_overwrite_protection(self):
        with tempfile.TemporaryDirectory(prefix='ios-template-test-') as tmp:
            base = Path(tmp)
            shutil.copytree(ROOT / 'scripts', base / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
            shutil.copytree(ROOT / 'templates', base / 'templates')
            (base / 'apps').mkdir()
            cmd = [sys.executable, str(base / 'scripts/new_app.py'), 'SecondApp', 'com.sjx13.ios.secondapp']
            subprocess.run(cmd, check=True, capture_output=True)
            app = base / 'apps/SecondApp'
            config = json.loads((app / 'app.json').read_text(encoding='utf-8'))
            self.assertEqual(config['bundleId'], 'com.sjx13.ios.secondapp')
            self.assertTrue((app / 'SecondApp.xcodeproj/project.pbxproj').exists())
            for f in app.rglob('*'):
                if f.is_file():
                    self.assertNotIn('__APP_', f.read_text(encoding='utf-8'))
                    self.assertNotIn('__BUNDLE_ID__', f.read_text(encoding='utf-8'))
            before = (app / 'app.json').read_bytes()
            self.assertNotEqual(subprocess.run(cmd, capture_output=True).returncode, 0)
            self.assertEqual(before, (app / 'app.json').read_bytes())
            duplicate = cmd[:-2] + ['ThirdApp', 'com.sjx13.ios.secondapp']
            self.assertNotEqual(subprocess.run(duplicate, capture_output=True).returncode, 0)
            traversal = cmd[:-2] + ['../Escape', 'com.sjx13.ios.escape']
            self.assertNotEqual(subprocess.run(traversal, capture_output=True).returncode, 0)
            self.assertFalse((base / 'Escape').exists())

    def fixture(self, path, *, cpu=0x0100000C, executable=True, bundle='com.test.fixture', platform='iPhoneOS', unsafe=False):
        info = {'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'Fixture', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0.0', 'MinimumOSVersion': '17.0', 'CFBundlePackageType': 'APPL', 'CFBundleSupportedPlatforms': [platform], 'UIDeviceFamily': [1]}
        with zipfile.ZipFile(path, 'w') as z:
            z.writestr('Payload/Fixture.app/Info.plist', plistlib.dumps(info))
            if executable:
                z.writestr('Payload/Fixture.app/Fixture', struct.pack('<IIIIIIII', 0xFEEDFACF, cpu, 0, 2, 0, 0, 0, 0))
            if unsafe:
                z.writestr('../escape', 'invalid')

    def test_validator_accepts_expected_fixture_and_rejects_invalid(self):
        with tempfile.TemporaryDirectory(prefix='ios-ipa-test-') as tmp:
            ipa = Path(tmp) / 'fixture.ipa'
            self.fixture(ipa)
            self.assertEqual(validate(ipa, 'com.test.fixture')['architecture'], 'arm64')
            with self.assertRaises(AssertionError):
                validate(ipa, 'com.wrong.id')
            for kwargs in ({'cpu': 7}, {'executable': False}, {'platform': 'iPhoneSimulator'}, {'unsafe': True}):
                self.fixture(ipa, **kwargs)
                with self.assertRaises((AssertionError, KeyError)):
                    validate(ipa)
            with zipfile.ZipFile(ipa, 'w') as z:
                z.writestr('readme.txt', 'A renamed ZIP is not an IPA')
            with self.assertRaises(AssertionError):
                validate(ipa)

    def test_windows_refuses_local_xcode(self):
        if sys.platform != 'win32':
            self.skipTest('Windows-only guard')
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/ci_build.py')], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('requires macOS', result.stderr)

    def test_no_template_tokens_in_real_app(self):
        for app in (ROOT / 'apps').glob('*/app.json'):
            data = json.loads(app.read_text(encoding='utf-8'))
            self.assertEqual(data['name'], app.parent.name)
            self.assertNotIn('__', data['bundleId'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
