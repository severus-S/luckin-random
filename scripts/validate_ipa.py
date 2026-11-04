"""Validate actual ZIP payload, plist, arm64 Mach-O and checksums; never signs."""
import argparse
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path


def validate(path, expected_bundle=None):
    path = Path(path)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None, "Corrupt ZIP entry"
        names = z.namelist()
        assert all(not n.startswith('/') and '..' not in n.split('/') for n in names), "Unsafe archive path"
        plists = [n for n in names if n.startswith("Payload/") and n.endswith(".app/Info.plist") and n.count('/') == 2]
        assert len(plists) == 1, "Expected one Payload/*.app/Info.plist"
        root = plists[0].rsplit('/', 1)[0] + '/'
        info = plistlib.loads(z.read(plists[0]))
        for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleVersion", "CFBundleShortVersionString", "MinimumOSVersion"):
            assert info.get(key), f"Missing {key}"
        assert info.get("CFBundlePackageType") == "APPL", "Not an application"
        assert info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Not an iPhoneOS build"
        assert 1 in info.get("UIDeviceFamily", []), "iPhone unsupported"
        if expected_bundle:
            assert info["CFBundleIdentifier"] == expected_bundle, "Bundle ID mismatch"
        exe = info["CFBundleExecutable"]
        assert '/' not in exe and '\\' not in exe, "Unsafe executable name"
        binary = z.read(root + exe)
        assert len(binary) >= 32, "Empty/truncated executable"
        magic, cpu, subtype, filetype = struct.unpack_from('<IIII', binary)
        assert magic == 0xFEEDFACF and cpu == 0x0100000C and filetype == 2, "Expected thin arm64 MH_EXECUTE Mach-O"
        return {"ipa": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "bundleId": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"], "minimumOS": info["MinimumOSVersion"], "architecture": "arm64", "signatureValidation": "not performed; Windows structural validation only"}


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('ipa')
    p.add_argument('--bundle-id')
    a = p.parse_args()
    print(json.dumps(validate(a.ipa, a.bundle_id), indent=2))
