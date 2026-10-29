#!/usr/bin/env bash
# Archive one app and upload it to App Store Connect, where it shows up in TestFlight.
#
#   scripts/testflight.sh <Aresium|Empire|Arestemis|Aresus|Arestoteles> [--export-only]
#
# --export-only signs the app for the App Store and writes the .ipa to build/testflight/<App>/ without uploading.
# Before every new upload of an app, raise CURRENT_PROJECT_VERSION in its project (README → Releasing): App Store
# Connect refuses a build number it already has. The archive is kept where Xcode's Organizer lists it.
set -euo pipefail

APP="${1:?usage: scripts/testflight.sh <App> [--export-only]}"
MODE="${2:-}"
case "$MODE" in
  "") DESTINATION=upload ;;
  --export-only) DESTINATION=export ;;
  *) echo "Unknown option: $MODE" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/$APP/$APP.xcodeproj"
[ -d "$PROJECT" ] || { echo "No project at $PROJECT" >&2; exit 1; }

# An uploaded build must match a commit, so its build number can be traced back.
if [ -n "$(git -C "$ROOT" status --porcelain -- "$APP" Shared)" ]; then
  echo "Uncommitted changes in $APP/ or Shared/: commit them first." >&2
  exit 1
fi

setting() {
  xcodebuild -project "$PROJECT" -scheme "$APP" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' -v key="$1" '$1 ~ "^ *"key"$" { print $2; exit }'
}
TEAM="$(setting DEVELOPMENT_TEAM)"
VERSION="$(setting MARKETING_VERSION)"
BUILD="$(setting CURRENT_PROJECT_VERSION)"
[ -n "$TEAM" ] || { echo "$APP has no DEVELOPMENT_TEAM" >&2; exit 1; }

OUT="$ROOT/build/testflight/$APP"   # build/ is gitignored
mkdir -p "$OUT"
LOG="$OUT/xcodebuild.log"
ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/$APP $VERSION ($BUILD) $(date +%H.%M).xcarchive"

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$DESTINATION</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<!-- false: the build may also go to external testers and the App Store later (README → Releasing). -->
	<key>testFlightInternalTestingOnly</key><false/>
</dict>
</plist>
EOF

fail() { echo "$1 failed. Errors:" >&2; grep -E "error:|Error|FAILED" "$LOG" | sort -u | head -20 >&2; echo "Full log: $LOG" >&2; exit 1; }

echo "Archiving $APP $VERSION ($BUILD), team $TEAM ..."
xcodebuild archive -project "$PROJECT" -scheme "$APP" -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates > "$LOG" 2>&1 || fail "Archive"

if [ "$DESTINATION" = upload ]; then echo "Uploading to App Store Connect ..."; else echo "Exporting ..."; fi
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT" -allowProvisioningUpdates >> "$LOG" 2>&1 || fail "Export"

echo "Done: $APP $VERSION ($BUILD)."
echo "Archive: $ARCHIVE"
[ "$DESTINATION" = upload ] && echo "App Store Connect processes it for a few minutes, then it shows in TestFlight."
exit 0
