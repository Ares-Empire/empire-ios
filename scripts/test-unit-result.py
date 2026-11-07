"""Print counts and failing names only; keep diagnostics in the local result bundle."""
import json
import subprocess
import sys

app, path, status, elapsed, output = sys.argv[1:]
result = subprocess.run(
    ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", path, "--compact"],
    capture_output=True, text=True,
)
try:
    data = json.loads(result.stdout)
    tests = data["totalTestCount"] - data["skippedTests"]
    failures = data["failedTests"]
    duration = data.get("finishTime", 0) - data.get("startTime", 0)
    ok = status == "0" and failures == 0 and tests > 0 and data["result"] == "Passed"
    names = sorted({f.get("testIdentifierString") or f.get("testName", "Unknown test")
                    for f in data["testFailures"]})
except (ValueError, KeyError):
    tests, failures, duration, ok, names = 0, 0, float(elapsed), False, []
print(f"{app}: {tests} tests, {failures} failures, {duration:.2f}s" + ("" if ok else " (FAILED)"))
for name in names:
    print(f"  {name}")
if not ok and not names:
    print(f"  No failing test names available (build/launch/result failure; see build/test-unit/{app}.log).")
with open(output, "a") as file:
    file.write(json.dumps(dict(tests=tests, failures=failures, duration=duration, ok=ok)) + "\n")
sys.exit(0 if ok else 1)
