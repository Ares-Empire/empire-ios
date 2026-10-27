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
