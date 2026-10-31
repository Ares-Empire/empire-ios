#!/usr/bin/env python3
"""Run the Settings UI experiment using Aresus's existing UI-test target, without project edits.

Prepare once with --prepare; then run before and after for each size against the chosen app binary.
The source temporarily placed in AresusUITests is removed after its build. Use only codex-57.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
p = argparse.ArgumentParser()
p.add_argument("phase")
p.add_argument("size", type=int, choices=[1250, 5000])
p.add_argument("--app", type=Path, default=Path("build/DerivedData/Build/Products/Debug-iphonesimulator/Aresium.app"))
p.add_argument("--prepare", action="store_true")
p.add_argument("--profile", action="store_true", help="Only open and scroll, for a separate profiler run")
a = p.parse_args()
base = Path(f"build/57-{a.phase}-{a.size}")
common = ["-project", "Aresus/Aresus.xcodeproj", "-scheme", "Aresus", "-destination",
          "platform=iOS Simulator,name=codex-57", "-derivedDataPath", "build/UITiming"]
if a.prepare:
    target = Path("Aresus/AresusUITests/SettingsTimingUITests.swift")
    if target.exists():
        raise SystemExit(f"Remove the previous temporary harness first: {target}")
    shutil.copyfile("scripts/57-settings-timing-ui.swift", target)
    try:
        with open(str(base) + "-runner-build.log", "w") as log:
            subprocess.run(["xcodebuild", "build-for-testing", *common], stdout=log, stderr=subprocess.STDOUT, check=True)
    finally:
        target.unlink()
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"], text=True))
device = next((d for group in devices["devices"].values() for d in group if d["name"] == "codex-57"), None)
if device is None:
    raise SystemExit('Create codex-57 with the iPhone 17 / iOS 27.0 runtime first (AGENTS.md).')
if device["state"] == "Shutdown":
    subprocess.run(["xcrun", "simctl", "boot", "codex-57"], check=True)
subprocess.run(["xcrun", "simctl", "bootstatus", "codex-57", "-b"], check=True)
subprocess.run(["xcrun", "simctl", "install", "codex-57", str(a.app)], check=True)
env = dict(os.environ, TEST_RUNNER_SETTINGS_SIZE=str(a.size))
if a.profile:
    env["TEST_RUNNER_SETTINGS_PROFILE"] = "1"
with open(str(base) + "-ui.log", "w") as log:
    result = subprocess.run(["xcodebuild", "test-without-building", *common,
                             "-only-testing:AresusUITests/SettingsTimingUITests",
                             "-resultBundlePath", str(base) + ".xcresult"],
                            env=env, stdout=log, stderr=subprocess.STDOUT)
container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", "codex-57",
                                         "de.ares-empire.aresium", "data"], text=True).strip())
for kind in ["turns", "spans"]:
    source = container / "tmp" / f"57-settings-{kind}.jsonl"
    if source.exists():
        shutil.copyfile(source, str(base) + f"-{kind}.jsonl")
turns = [json.loads(line) for line in Path(str(base) + "-turns.jsonl").read_text().splitlines()]
steps = []
for line in Path(str(base) + "-ui.log").read_text().splitlines():
    match = re.search(r"SETTINGS_STEP size=(\d+) step=(.*?) start=(\S+) end=(\S+)", line)
    if not match:
        continue
    _, name, start, end = match.groups()
    start, end = float(start), float(end)
    samples = [t for t in turns if start <= t["start"] <= end]
    steps.append(dict(step=name, ms=max((t["ms"] for t in samples), default=0),
                      cpu=max((t["cpu"] for t in samples), default=0), start=start, end=end))
# Scrolling has several separate gesture windows; retain each range and take its longest turn.
combined = {}
for step in steps:
    name = step["step"]
    entry = combined.setdefault(name, dict(step=name, ms=0, cpu=0, windows=[]))
    entry["ms"] = max(entry["ms"], step["ms"])
    entry["cpu"] = max(entry["cpu"], step["cpu"])
    entry["windows"].append(dict(start=step["start"], end=step["end"]))
steps = list(combined.values())
Path(str(base) + "-summary.json").write_text(json.dumps(steps, indent=2) + "\n")
for step in steps:
    print(f'{step["step"]:28s} {step["ms"]:9.2f} ms wall {step["cpu"]:9.2f} ms CPU')
raise SystemExit(result.returncode)
