#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo "Usage: bash scripts/arestia-gate.sh install IPHONE_UDID" >&2
    echo "       bash scripts/arestia-gate.sh test IPHONE_UDID wrong-websocket|wrong-post|right|echo" >&2
    exit 2
}

[[ $# -ge 2 && -n "$2" ]] || usage
action=$1
device=$2
input=arestia-gate.local.json
case "$action" in
    install)
        [[ $# -eq 2 ]] || usage
        build_action=build
        ;;
    test)
        [[ $# -eq 3 ]] || usage
        case "$3" in
            wrong-websocket) test_name=testWrongWebSocketPin ;;
            wrong-post) test_name=testWrongPOSTPin ;;
            right) test_name=testRightPin ;;
            echo) test_name=testEchoRoundTrip ;;
            *) usage ;;
        esac
        if [[ ! -f "$input" ]]; then
            echo "Missing $input. See docs/apps/Arestia.md for the local test input." >&2
            exit 2
        fi
        build_action=build-for-testing
        ;;
    *) usage ;;
esac

derived=build/arestia-gate/device
bundle=de.ares-empire.arestia
build_options=(
    -project Arestia/Arestia.xcodeproj -scheme Arestia -configuration Debug
    -destination "platform=iOS,id=$device" -derivedDataPath "$derived"
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ARESTIA_GATE'
)

xcodebuild "$build_action" "${build_options[@]}"
xcrun devicectl device install app --device "$device" "$derived/Build/Products/Debug-iphoneos/Arestia.app"

if [[ "$action" == test ]]; then
    xcrun devicectl device copy to --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" --source "$input" --destination "Library/Caches/$input"
    run_dir=$(mktemp -d "$derived/results.XXXXXX")
    result="$run_dir/Gate.xcresult"
    xcodebuild test-without-building "${build_options[@]}" \
        -parallel-testing-enabled NO -collect-test-diagnostics never \
        -resultBundlePath "$result" "-only-testing:ArestiaTests/GateTests/$test_name"
    python3 scripts/arestia-gate-result.py "$result" "$test_name"
fi
