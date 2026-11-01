#!/usr/bin/env bash
# Three fresh Release app-host measurements, plus today's engine as a separate control process.
# Reads aresium; writes only this worktree. Requires an owned codex-98 simulator.
# Installs nothing and does not access the network. Uses the refreshed engine shipped in the app.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
aresium="${1:-$HOME/aresium}"
mkdir -p "$repo/build"
cd "$repo"
shasum -a 256 Aresium/Aresium/Engine/aresium-engine.js "$aresium/data/local-places/de.places.bin.gz"
# Existing tests use DEBUG-only app helpers. Exclude those test sources for a genuine Release measurement;
# no project file or production compilation conditions change. No test filename overlaps an app filename.
excluded_tests="$(python3 - <<'PY'
from pathlib import Path
print(' '.join(sorted(p.name for p in Path('Aresium/AresiumTests').rglob('*.swift')
                      if p.name != 'LocalPlacesMeasurementTests.swift')))
PY
)"
measurement_tag="$(date +%Y%m%d-%H%M%S)"
common=(-project Aresium/Aresium.xcodeproj -scheme Aresium -configuration Release
        -destination 'platform=iOS Simulator,name=codex-98' -derivedDataPath build/DerivedData
        ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES "EXCLUDED_SOURCE_FILE_NAMES=$excluded_tests"
        -parallel-testing-enabled NO -only-testing:AresiumTests/LocalPlacesMeasurementTests)
for process in 1 2 3 baseline; do
  action=test-without-building
  if [[ "$process" == 1 ]]; then action=test; fi
  script="$repo/Aresium/Aresium/Engine/aresium-engine.js"
  skip_list=0
  if [[ "$process" == baseline ]]; then skip_list=1; fi
  result="build/98-$measurement_tag-$process.xcresult"
  diagnostics="build/98-$measurement_tag-$process-diagnostics"
  TEST_RUNNER_LOCAL_PLACES_PACKED=1 TEST_RUNNER_LOCAL_PLACES_MEASURE=1 TEST_RUNNER_LOCAL_PLACES_SKIP_LIST="$skip_list" \
  TEST_RUNNER_LOCAL_PLACES_SCRIPT="$script" TEST_RUNNER_LOCAL_PLACES_GZIP="$aresium/data/local-places/de.places.bin.gz" \
  xcodebuild "$action" "${common[@]}" -resultBundlePath "$result"
  xcrun xcresulttool export diagnostics --path "$result" --output-path "$diagnostics"
  rg --no-filename '^LOCAL PLACES|Test run with' "$diagnostics" -g StandardOutputAndStandardError.txt
  xcrun xcresulttool get test-results summary --path "$result" > "build/98-$measurement_tag-$process-summary.json"
done
