#!/bin/bash
# One login for all Empire apps: the Empire app saves a test token in the shared Keychain, then Aresium must read it.
# Usage: scripts/check-shared-login.sh <simulator udid>. Parallel testing stays off: it runs tests on throw-away
# clones of the simulator, which share no Keychain between the two runs.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="$1"; TOKEN="shared-login-probe-$(date +%s)"
export TEST_RUNNER_SHARED_LOGIN_PROBE_TOKEN="$TOKEN"
TEST_RUNNER_SHARED_LOGIN_PROBE=write xcodebuild test -project Empire/Empire.xcodeproj -scheme Empire \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath Empire/build/DD \
  -parallel-testing-enabled NO -only-testing:EmpireTests/SharedLoginProbe -quiet && echo "Empire app saved the token"
TEST_RUNNER_SHARED_LOGIN_PROBE=read xcodebuild test -project Aresium/Aresium.xcodeproj -scheme Aresium \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath Aresium/build/DD-gw \
  -parallel-testing-enabled NO -only-testing:AresiumTests/SharedLoginProbe -quiet && echo "PASS: Aresium read the Empire app's login"
