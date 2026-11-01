#!/usr/bin/env bash
# Three fresh Release app-host measurements, plus today's engine as a separate control process.
# Reads aresium; writes only this worktree. Requires its existing node_modules and an owned codex-95 simulator.
# Installs nothing and does not access the network. Does not update the engine shipped in the app.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
aresium="${1:-$HOME/aresium}"
mkdir -p "$repo/build"
node - "$aresium" "$repo/build/95-optional-engine.js" <<'JS'
const path = require('node:path');
const source = process.argv[2];
const { build } = require(path.join(source, 'node_modules/esbuild'));
const { builtinModules } = require('node:module');
const builtins = new Set(builtinModules.map(name => name.replace(/^node:/, '')));
build({
  absWorkingDir: source, entryPoints: ['src/engine/index.ts'], bundle: true,
  format: 'iife', globalName: '__AresiumEngine',
  footer: { js: 'globalThis.AresiumEngine = __AresiumEngine;' },
  platform: 'browser', target: 'es2020',
  alias: { 'csv-parse/sync': 'csv-parse/browser/esm/sync' },
  outfile: process.argv[3],
  plugins: [{ name: 'reject-node-builtins', setup(build) {
    build.onResolve({ filter: /.*/ }, ({ path }) => {
      if (path.startsWith('node:') || builtins.has(path))
        return { errors: [{ text: `Node built-in is forbidden in the engine: ${path}` }] };
    });
  } }],
}).catch(error => { console.error(error); process.exitCode = 1; });
JS
cd "$repo"
shasum -a 256 Aresium/Aresium/Engine/aresium-engine.js build/95-optional-engine.js "$aresium/data/local-places/de.json.gz"
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
        -destination 'platform=iOS Simulator,name=codex-95' -derivedDataPath build/DerivedData
        ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES "EXCLUDED_SOURCE_FILE_NAMES=$excluded_tests"
        -parallel-testing-enabled NO -only-testing:AresiumTests/LocalPlacesMeasurementTests)
for process in 1 2 3 baseline; do
  action=test-without-building
  if [[ "$process" == 1 ]]; then action=test; fi
  script="$repo/build/95-optional-engine.js"
  skip_list=0
  if [[ "$process" == baseline ]]; then
    script="$repo/Aresium/Aresium/Engine/aresium-engine.js"
    skip_list=1
  fi
  result="build/95-$measurement_tag-$process.xcresult"
  diagnostics="build/95-$measurement_tag-$process-diagnostics"
  TEST_RUNNER_LOCAL_PLACES_MEASURE=1 TEST_RUNNER_LOCAL_PLACES_SKIP_LIST="$skip_list" \
  TEST_RUNNER_LOCAL_PLACES_SCRIPT="$script" TEST_RUNNER_LOCAL_PLACES_GZIP="$aresium/data/local-places/de.json.gz" \
  xcodebuild "$action" "${common[@]}" -resultBundlePath "$result"
  xcrun xcresulttool export diagnostics --path "$result" --output-path "$diagnostics"
  rg --no-filename '^LOCAL PLACES|Test run with' "$diagnostics" -g StandardOutputAndStandardError.txt
  xcrun xcresulttool get test-results summary --path "$result" > "build/95-$measurement_tag-$process-summary.json"
done
