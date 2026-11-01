#!/usr/bin/env bash
# Copies Aresium's shared engine (aresium/src/engine, the server's own TypeScript) into the iPhone app, which runs it in
# JavaScriptCore for phone mode (empire-ios/prompts/15-aresium-phone-mode.md). Run from anywhere:
#   bash ~/empire-ios/scripts/aresium-engine.sh [path/to/aresium]
# 1. builds the bundle with `npm run engine` in the aresium repo (its dist/ is git-ignored),
# 2. copies dist/aresium-engine.js to Aresium/Aresium/Engine/ (the app's copy; the tests use it too) and writes the
#    aresium commit it came from to Engine/engine-version.txt,
# 3. refreshes the engine's test files in Aresium/AresiumTests/Engine/ (the sample source, the timing sources and the
#    readers' inputs with the server's answers), so the tests compare the bundle with answers of the same commit,
# 4. writes the shop list's licence notice (name-suggestion-index, from the header of
#    src/engine/sorting/shops.de.json) to Engine/name-suggestion-index-licence.txt, which Settings → About → Fonts &
#    licences shows (`BundledLicence.shopList`; `LicenceTests` checks it against the bundle).
# 5. copies the packed local places database and writes its ODbL attribution and download notice.
# The bundle is never edited by hand.
set -euo pipefail

aresium="${1:-$HOME/aresium}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo/Aresium/Aresium/Engine"
tests="$repo/Aresium/AresiumTests/Engine"

(cd "$aresium" && npm run --silent engine)

mkdir -p "$app" "$tests"
cp "$aresium/dist/aresium-engine.js" "$app/aresium-engine.js"
commit="$(git -C "$aresium" rev-parse HEAD)"
if [ -n "$(git -C "$aresium" status --porcelain)" ]; then commit="$commit (with uncommitted changes)"; fi
printf '%s\n' "$commit" > "$app/engine-version.txt"

for file in dashboard.sample-source.json timing-source-5000.json timing-vr-5000.csv; do
  cp "$aresium/dist/$file" "$tests/$file"
done
for file in vrbank.csv camt.xml paypal.csv; do
  cp "$aresium/src/engine/fixtures/$file" "$tests/$file"
  cp "$aresium/src/engine/fixtures/$file.expected.json" "$tests/$file.expected.json"
done
# Made-up bank files the phone-mode tests read: an unknown layout (the confirmation sheet) and a known bank.
for file in unknown-fiktivbank.csv dkb.csv; do
  cp "$aresium/src/engine/fixtures/banks/$file" "$tests/$file"
done

# The licence notice of the brand names in the shop list: the copyright line, what it covers, then the licence's text.
node -e '
const nsi = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).nsi;
const [copyright, ...licence] = nsi.licenceText;
const about = `Aresium sorts payments with brand names from the ${nsi.name} (${nsi.homepage}), version ${nsi.version}, `
  + `under the ${nsi.licence} licence:`;
require("fs").writeFileSync(process.argv[2], [copyright, about, ...licence].join("\n\n") + "\n");
' "$aresium/src/engine/sorting/shops.de.json" "$app/name-suggestion-index-licence.txt"

echo "Engine copied: $(wc -c < "$app/aresium-engine.js" | tr -d ' ') bytes from aresium $commit"

cp "$aresium/data/local-places/de.places.bin.gz" "$app/de.places.bin.gz"
node - "$aresium/data/local-places" "$app/local-places-licence.txt" <<'JS'
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const root = process.argv[2];
const data = zlib.gunzipSync(fs.readFileSync(path.join(root, 'de.places.bin.gz')));
const offsets = data.readUInt32LE(76); // Header word 19: metadata offsets.
const blob = data.readUInt32LE(80);
const meta = Array.from({length: 3}, (_, i) => data.toString('utf8',
  blob + data.readUInt32LE(offsets + i * 4), blob + data.readUInt32LE(offsets + (i + 1) * 4)));
fs.writeFileSync(process.argv[3], [
  '© OpenStreetMap contributors',
  'Local places for sorting on this iPhone. Open Database License (ODbL) 1.0.',
  'https://www.openstreetmap.org/copyright',
  'https://opendatacommons.org/licenses/odbl/1-0/',
  'Download the database: https://aresium.de/osm/local-places-de.places.bin.gz',
  `Data date: ${meta[0]}`, `Source and licence: ${meta[2]}`,
  `Packed database built from the Germany extract; aresium ${require('node:child_process').execFileSync('git', ['-C', path.join(root, '../..'), 'rev-parse', 'HEAD'], {encoding: 'utf8'}).trim()}.`,
].join('\n\n') + '\n');
JS
