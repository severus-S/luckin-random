import argparse
import json
import re
import shutil
from project import ROOT, config, generate

p = argparse.ArgumentParser(description="Create a reusable SwiftUI app without modifying existing apps")
p.add_argument("name")
p.add_argument("bundle_id")
a = p.parse_args()
if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,49}", a.name):
    p.error("Invalid app name")
if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}", a.bundle_id):
    p.error("Invalid bundle ID")
for file in (ROOT / "apps").glob("*/app.json"):
    if json.loads(file.read_text(encoding="utf-8"))["bundleId"] == a.bundle_id:
        p.error("Bundle ID already belongs to another app")
target = ROOT / "apps" / a.name
if target.exists():
    p.error("App already exists; refusing overwrite")
shutil.copytree(ROOT / "templates" / "SwiftUI-App", target)
for file in target.rglob("*"):
    if file.is_file():
        file.write_text(file.read_text(encoding="utf-8").replace("__APP_NAME__", a.name).replace("__BUNDLE_ID__", a.bundle_id), encoding="utf-8")
config(a.name)
print(generate(a.name))
