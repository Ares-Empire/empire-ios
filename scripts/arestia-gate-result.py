"""Require the selected Arestia gate test to have run once and passed."""
import json
import subprocess
import sys


def read_result(path, kind):
    command = ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", path]
    return json.loads(subprocess.check_output(command))


def test_cases(nodes):
    for node in nodes:
        if node["nodeType"] == "Test Case":
            yield node
        yield from test_cases(node.get("children", []))


path, test = sys.argv[1:]
identifier = f"test://com.apple.xcode/Arestia/ArestiaTests/GateTests/{test}"
try:
    summary = read_result(path, "summary")
    cases = list(test_cases(read_result(path, "tests")["testNodes"]))
    ok = (
        summary["totalTestCount"] == summary["passedTests"] == 1
        and summary["failedTests"] == summary["skippedTests"] == summary["expectedFailures"] == 0
        and summary["result"] == "Passed"
        and len(cases) == 1
        and cases[0]["nodeIdentifierURL"] == identifier
        and cases[0]["result"] == "Passed"
    )
except (KeyError, ValueError, OSError, subprocess.CalledProcessError):
    sys.exit(f"Could not verify {test} in {path}.")
if not ok:
    sys.exit(f"Expected only {test} to run and pass. See {path}.")
print(f"{test} ran once and passed.")
