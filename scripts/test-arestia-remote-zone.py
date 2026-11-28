#!/usr/bin/env python3
"""Regression tests for the ATS build phases and their private zone-file reader."""

import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/arestia_remote_zone.py"
PROJECT = ROOT / "Arestia/Arestia.xcodeproj/project.pbxproj"


class ArestiaRemoteZoneTests(unittest.TestCase):
    def test_ats_phases_keep_sandboxing_enabled(self):
        parsed = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(PROJECT)])
        project = json.loads(parsed)
        objects = project["objects"]
        project_settings = objects[project["rootObject"]]["buildConfigurationList"]
        for configuration in objects[project_settings]["buildConfigurations"]:
            self.assertEqual(objects[configuration]["buildSettings"]["ENABLE_USER_SCRIPT_SANDBOXING"], "YES")

        for target_name in ("Arestia", "ArestiaControlsExtension"):
            with self.subTest(target=target_name):
                target = next(value for value in objects.values()
                              if value["isa"] == "PBXNativeTarget" and value["name"] == target_name)
                configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
                for configuration in configurations:
                    settings = objects[configuration]["buildSettings"]
                    self.assertNotEqual(settings.get("ENABLE_USER_SCRIPT_SANDBOXING"), "NO")
                    self.assertEqual(settings["INFOPLIST_FILE"], "$(DERIVED_FILE_DIR)/ArestiaInfo.plist")
                phase = next(objects[key] for key in target["buildPhases"]
                             if objects[key].get("name") == "Set remote ATS exception")
                self.assertIn("$(SRCROOT)/$(ARESTIA_INFO_PLIST_SOURCE)", phase["inputPaths"])
                self.assertIn("$(SRCROOT)/../scripts/arestia_remote_zone.py", phase["inputPaths"])
                self.assertIn("$(ARESTIA_REMOTE_ZONE_FILE:default=$(HOME)/.config/arestia/remote-zone)",
                              phase["inputPaths"])
                self.assertEqual(phase["outputPaths"], ["$(INFOPLIST_FILE)"])

    def test_missing_zone_file_uses_default_only_in_debug(self):
        build = ROOT / "build"
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            folder = Path(temporary)
            source, generated, zone = (folder / name for name in ("source.plist", "generated.plist", "missing-zone"))
            source.write_bytes(plistlib.dumps({}))
            command = [sys.executable, str(SCRIPT), str(source), str(generated)]
            environment = dict(os.environ, ARESTIA_REMOTE_ZONE_FILE=str(zone))

            debug = subprocess.run(command, env=dict(environment, CONFIGURATION="Debug"),
                                   capture_output=True, text=True, timeout=2)
            self.assertEqual(debug.returncode, 0, debug.stderr)
            info = plistlib.loads(generated.read_bytes())
            self.assertEqual(info["NSAppTransportSecurity"], {"NSExceptionDomains": {"home.example.net": {
                "NSIncludesSubdomains": True, "NSExceptionAllowsInsecureHTTPLoads": True}}})

            release = subprocess.run(command, env=dict(environment, CONFIGURATION="Release"),
                                     capture_output=True, text=True, timeout=2)
            self.assertEqual(release.returncode, 1)
            self.assertIn("remote zone file is missing", release.stderr)

    def test_zone_file_requires_a_regular_file_without_waiting_on_fifo(self):
        build = ROOT / "build"
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=build) as temporary:
            folder = Path(temporary)
            source, generated, zone = (folder / name for name in ("source.plist", "generated.plist", "zone"))
            source.write_bytes(plistlib.dumps({"CFBundleDisplayName": "Example"}))
            environment = dict(os.environ, ARESTIA_REMOTE_ZONE_FILE=str(zone), CONFIGURATION="Release")

            def generate():
                return subprocess.run([sys.executable, str(SCRIPT), str(source), str(generated)],
                                      env=environment, capture_output=True, text=True, timeout=2)

            os.mkfifo(zone)
            result = generate()
            self.assertEqual(result.returncode, 1)
            self.assertIn("remote zone file must be a regular file", result.stderr)
            self.assertFalse(generated.exists())

            zone.unlink()
            zone.write_text("testing.home.example.net\n", encoding="ascii")
            result = generate()
            self.assertEqual(result.returncode, 0, result.stderr)
            info = plistlib.loads(generated.read_bytes())
            self.assertEqual(info["CFBundleDisplayName"], "Example")
            self.assertEqual(info["NSAppTransportSecurity"],
                             {"NSExceptionDomains": {"testing.home.example.net": {
                                 "NSIncludesSubdomains": True, "NSExceptionAllowsInsecureHTTPLoads": True}}})


if __name__ == "__main__":
    unittest.main()
