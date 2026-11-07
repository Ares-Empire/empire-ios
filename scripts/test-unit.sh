#!/bin/bash
# The same isolated simulator unit-test run locally and on GitHub. Bash 3.2 compatible.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo 'Usage: bash scripts/test-unit.sh [--all | <App> ...] [--timing] [--keep-simulator]'
}
apps=()
all=0 timing=0 keep=0
for argument in "$@"; do
    case "$argument" in
        --all) all=1 ;;
        --timing) timing=1 ;;
        --keep-simulator) keep=1 ;;
        -h|--help) usage; exit 0 ;;
        Aresium|Empire|Arestemis|Aresus|Arestoteles) apps+=("$argument") ;;
        *) usage >&2; exit 2 ;;
    esac
done
if (( all && ${#apps[@]} )); then usage >&2; exit 2; fi
if (( all || ${#apps[@]} == 0 )); then apps=(Aresium Empire Arestemis Aresus Arestoteles); fi

# Explicit inventory: keep budgets in the tests unchanged. Measurements run only with --timing.
timing_tests() {
    case "$1" in
        Aresium) printf '%s\n' \
            'AresiumTests/NameSearchTests/indexedSearchOfFiveThousandPaymentsStaysFast()' \
            'AresiumTests/PickerTimingTests' \
            'AresiumTests/LocalPlacesMeasurementTests' \
            'AresiumTests/EngineTests/timings()' \
            'AresiumTests/PhonePickerBatchTests/oneSortWithThe5000PaymentTimingSource()' \
            'AresiumTests/BatchChangesTests/fiveHundredRowsFromSixtyShopsStaysWithinBudget()' \
            'AresiumTests/FixedCostTimingTests' ;;
        Arestemis) printf '%s\n' 'ArestemisTests/SpellingTests/timeoutReturnsWithinBudget()' ;;
        Arestoteles) printf '%s\n' 'ArestotelesTests/VaultTimingTests' \
            'ArestotelesTests/BestMatchesTests/noAnswerInTimeShowsNothingAndCancelsTheRequest()' ;;
    esac
}

mkdir -p build/test-unit
udid='' child='' summary=''
locks=()
cleanup() {
    cleanup_status=$?
    trap - EXIT INT TERM
    if [[ -n "$child" ]]; then
        kill -TERM "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    if [[ -n "$udid" ]]; then
        if (( keep )); then
            echo "Kept simulator: $udid"
        elif ! xcrun simctl delete "$udid" >/dev/null; then
            echo "Could not delete owned simulator $udid." >&2
            if (( cleanup_status == 0 )); then cleanup_status=1; fi
        fi
    fi
    # Bash 3.2 treats expansion of an empty array as unbound under set -u.
    if (( ${#locks[@]} )); then
        for lock in "${locks[@]}"; do
            if ! rmdir "$lock" && (( cleanup_status == 0 )); then cleanup_status=1; fi
        done
    fi
    if [[ -n "$summary" ]]; then rm -f "$summary"; fi
    exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Different apps may run together; never overwrite another invocation's result or derived data.
for app in "${apps[@]}"; do
    lock="build/test-unit/.$app.lock"
    if ! mkdir "$lock" 2>/dev/null; then
        echo "$app: another run owns $lock (remove it only if that run has ended)." >&2
        exit 2
    fi
    locks+=("$lock")
done
runtime=$(xcrun simctl list runtimes --json | python3 -c '
import json, sys
runtimes = [r["identifier"] for r in json.load(sys.stdin)["runtimes"]
            if r.get("isAvailable") and r.get("version", "").split(".")[:2] == ["27", "0"] and r["name"].startswith("iOS ")]
if not runtimes:
    sys.exit("An available iOS 27.0 simulator runtime is required.")
print(sorted(runtimes)[0])')
udid=$(xcrun simctl create "test-unit-$(uuidgen)" 'iPhone 17' "$runtime")
failed=0
summary=$(mktemp "$PWD/build/test-unit/summary.XXXXXX")
for app in "${apps[@]}"; do
    filters=()
    if (( ! timing )); then filters+=("-only-testing:${app}Tests"); fi
    while IFS= read -r test; do
        [[ -n "$test" ]] || continue
        if (( timing )); then
            filters+=("-only-testing:$test")
        else
            echo "Skipping $test: speed/measurement test; use --timing."
            filters+=("-skip-testing:$test")
        fi
    done < <(timing_tests "$app")
    if (( timing && ${#filters[@]} == 0 )); then
        echo "$app: 0 tests, 0 failures, 0.00s (no timing tests)"
        continue
    fi
    case "$app" in
        Aresium|Empire) filters+=("-skip-testing:${app}Tests/SharedLoginProbe") ;;
    esac
    result="build/test-unit/$app.xcresult"
    rm -rf "$result"
    started=$SECONDS
    # Avoid a ten-minute simulator sysdiagnose after an assertion failure; test issues stay in the result bundle.
    # Ad-hoc signing preserves simulator entitlements (Keychain/App Groups) without an Apple account.
    env -u TEST_RUNNER_SHARED_LOGIN_PROBE -u TEST_RUNNER_SHARED_LOGIN_PROBE_TOKEN \
        TEST_RUNNER_PICKER_TIMINGS="$timing" TEST_RUNNER_VAULT_TIMINGS="$timing" TEST_RUNNER_FIXED_COST_TIMINGS="$timing" \
        TEST_RUNNER_LOCAL_PLACES_MEASURE="$timing" TEST_RUNNER_LOCAL_PLACES_PACKED=1 \
        TEST_RUNNER_LOCAL_PLACES_SCRIPT="$PWD/Aresium/Aresium/Engine/aresium-engine.js" \
        TEST_RUNNER_LOCAL_PLACES_GZIP="$PWD/Aresium/Aresium/Engine/de.places.bin.gz" \
        xcodebuild test -project "$app/$app.xcodeproj" -scheme "$app" -configuration Debug \
        -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "build/test-unit/$app" \
        -resultBundlePath "$result" -parallel-testing-enabled NO -collect-test-diagnostics never "${filters[@]}" \
        CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
        >"build/test-unit/$app.log" 2>&1 &
    child=$!
    status=0
    wait "$child" || status=$?
    child=''
    if ! python3 scripts/test-unit-result.py "$app" "$result" "$status" "$((SECONDS-started))" "$summary"; then
        failed=1
    fi
done
python3 - "$summary" <<'PY'
import json, sys
with open(sys.argv[1]) as file:
    rows = [json.loads(line) for line in file]
print(f"Total: {sum(r['tests'] for r in rows)} tests, {sum(r['failures'] for r in rows)} failures, "
      f"{sum(r['duration'] for r in rows):.2f}s; {sum(not r['ok'] for r in rows)} app runs failed")
PY
rm "$summary"
exit "$failed"
