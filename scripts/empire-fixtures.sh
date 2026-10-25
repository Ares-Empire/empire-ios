#!/bin/bash
# Refreshes the Empire app's server samples from the hub's own generator (run from anywhere):
#   bash ~/empire-ios/scripts/empire-fixtures.sh [path/to/ares-empire]
# The hub builds its exact answers with its own code (ares-empire tools/empire_samples.py). They become the decoding
# tests' fixtures (Empire/EmpireTests/ServerSamples, ServerSamplesTests) and the app's sample mode (Preview Content:
# the admin's and a member's /api/empire). Run it after the hub API changes, then run the Empire tests.
set -euo pipefail
hub="${1:-$HOME/ares-empire}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$here/Empire/EmpireTests/ServerSamples"
rm -f "$out"/*.json
python3 "$hub/tools/empire_samples.py" "$out" >/dev/null
cp "$out/empire.admin.json" "$here/Empire/Empire/Preview Content/empire.admin.json"
cp "$out/empire.member.json" "$here/Empire/Empire/Preview Content/empire.user.json"
echo "Empire samples refreshed from $hub ($(ls "$out" | wc -l | tr -d ' ') files)"
