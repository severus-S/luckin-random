"""Standard-library-only native Xcode project generator; run after adding Swift files."""
import argparse
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def config(app):
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,49}", app):
        raise ValueError("App name must be a simple ASCII identifier")
    folder = ROOT / "apps" / app
    data = json.loads((folder / "app.json").read_text(encoding="utf-8"))
    assert data["name"] == app, "App name mismatch"
    assert re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}", data["bundleId"]), "Invalid bundle ID"
    assert re.fullmatch(r"\d+\.\d+\.\d+", data["version"]), "Invalid version"
    assert re.fullmatch(r"\d+\.\d+", data["deploymentTarget"]), "Invalid deployment target"
    if "buildNumber" in data:
        assert type(data["buildNumber"]) is int and 0 < data["buildNumber"] < 1_000_000_000, "Invalid build number"
    assert isinstance(data.get('displayName', app), str) and re.fullmatch(r'[\w \u4e00-\u9fff.-]{1,50}', data.get('displayName', app)), 'Invalid display name'
    if "allowArbitraryNetworkLoads" in data:
        assert type(data["allowArbitraryNetworkLoads"]) is bool, "Invalid network loads flag"
    purpose = data.get("crossWebsiteTrackingUsageDescription")
    if purpose is not None:
        assert isinstance(purpose, str) and 1 <= len(purpose) <= 300 and not any(ch in purpose for ch in "\r\n\x00"), "Invalid tracking purpose"
    return folder, data


def generate(app):
    folder, c = config(app)
    files = sorted((folder / "Sources").rglob("*.swift"))
    assert files, "No Swift sources"
    uid = lambda n: f"{n:024X}"
    entries, refs, builds = [], [], []
    for i, path in enumerate(files):
        ref, build = uid(100+i*2), uid(101+i*2)
        rel = path.relative_to(folder).as_posix()
        assert re.fullmatch(r"[A-Za-z0-9_./-]+", rel), "Unsafe source path"
        entries += [f'{ref} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel}"; sourceTree = "<group>"; }};', f'{build} = {{isa = PBXBuildFile; fileRef = {ref}; }};']
        refs.append(ref)
        builds.append(build)
    resources = []
    catalogs = sorted(folder.glob("Resources/*.xcassets"))
    for i, path in enumerate(catalogs):
        ref, build = uid(10000+i*2), uid(10001+i*2)
        rel = path.relative_to(folder).as_posix()
        assert re.fullmatch(r"[A-Za-z0-9_./-]+", rel), "Unsafe asset path"
        entries += [f'{ref} = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "{rel}"; sourceTree = "<group>"; }};', f'{build} = {{isa = PBXBuildFile; fileRef = {ref}; }};']
        refs.append(ref)
        resources.append(build)
    icon_settings = ""
    if any((path / "AppIcon.appiconset/Contents.json").is_file() for path in catalogs):
        icon_settings = "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"
    privacy_settings = ""
    generated_info = {}
    if c.get("crossWebsiteTrackingUsageDescription"):
        generated_info["NSCrossWebsiteTrackingUsageDescription"] = c["crossWebsiteTrackingUsageDescription"]
    if c.get("allowArbitraryNetworkLoads"):
        generated_info["NSAppTransportSecurity"] = {"NSAllowsArbitraryLoads": True}
    if generated_info:
        (folder / "GeneratedInfo.plist").write_bytes(plistlib.dumps(generated_info))
        privacy_settings = 'INFOPLIST_FILE = "GeneratedInfo.plist";'
    settings = f'''CODE_SIGNING_ALLOWED = NO; CODE_SIGNING_REQUIRED = NO; CODE_SIGN_IDENTITY = "";
        PRODUCT_BUNDLE_IDENTIFIER = "{c['bundleId']}"; PRODUCT_NAME = "{app}";
        SDKROOT = iphoneos; SUPPORTED_PLATFORMS = iphoneos; ARCHS = arm64;
        IPHONEOS_DEPLOYMENT_TARGET = {c['deploymentTarget']}; TARGETED_DEVICE_FAMILY = 1;
        SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-O";
        GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = "{c.get('displayName', app)}";
        INFOPLIST_KEY_UILaunchScreen_Generation = YES;
        INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
        INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
        MARKETING_VERSION = {c['version']}; CURRENT_PROJECT_VERSION = {c.get('buildNumber', 1)};
        {icon_settings}
        {privacy_settings}'''
    objects = f'''
{uid(1)} = {{isa = PBXProject; buildConfigurationList = {uid(8)}; compatibilityVersion = "Xcode 14.0"; mainGroup = {uid(2)}; productRefGroup = {uid(3)}; projectDirPath = ""; targets = ({uid(4)},); }};
{uid(2)} = {{isa = PBXGroup; children = ({','.join(refs)},{uid(3)},); sourceTree = "<group>"; }};
{uid(3)} = {{isa = PBXGroup; children = ({uid(5)},); name = Products; sourceTree = "<group>"; }};
{uid(4)} = {{isa = PBXNativeTarget; buildConfigurationList = {uid(9)}; buildPhases = ({uid(6)}, {uid(7)}, {uid(12)},); buildRules = (); dependencies = (); name = "{app}"; productName = "{app}"; productReference = {uid(5)}; productType = "com.apple.product-type.application"; }};
{uid(5)} = {{isa = PBXFileReference; explicitFileType = wrapper.application; path = "{app}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
{uid(6)} = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(builds)},); runOnlyForDeploymentPostprocessing = 0; }};
{uid(7)} = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
{uid(12)} = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(resources)},); runOnlyForDeploymentPostprocessing = 0; }};
{uid(8)} = {{isa = XCConfigurationList; buildConfigurations = ({uid(10)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
{uid(9)} = {{isa = XCConfigurationList; buildConfigurations = ({uid(11)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
{uid(10)} = {{isa = XCBuildConfiguration; buildSettings = {{CLANG_ENABLE_MODULES = YES; }}; name = Release; }};
{uid(11)} = {{isa = XCBuildConfiguration; buildSettings = {{{settings}}}; name = Release; }};
'''
    project = folder / f"{app}.xcodeproj"
    project.mkdir(exist_ok=True)
    (project / "project.pbxproj").write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + objects + '\n'.join(entries) + f'\n}}; rootObject = {uid(1)}; }}\n', encoding="utf-8")
    return project


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("app")
    print(generate(p.parse_args().app))
