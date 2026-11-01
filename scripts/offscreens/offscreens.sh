#!/bin/zsh
# Records 3 s of Core Animation's offscreen passes for an app on a booted simulator and sums them per frame.
# usage: scripts/offscreens/offscreens.sh <simulator udid> <bundle id> <out.txt> [launch arguments...]
# A screen that animates (Arestemis's hunt with -sampleData) should list no shadow, mask or group passes per frame
# (CLAUDE.md, brief 87). Option 31 is CA_PRINT_OFFSCREENS on iOS 27.0 (17 colours offscreen layers, 0 flushes).
set -eu
here=${0:a:h}
udid=$1 bundle=$2 out=$3; shift 3
tool=${TMPDIR:-/tmp}/empire-cadebug
[[ -x $tool && $tool -nt $here/cadebug.swift ]] || swiftc -O -o $tool $here/cadebug.swift
xcrun simctl launch --terminate-running-process $udid $bundle "$@" >/dev/null
sleep 6
xcrun simctl spawn $udid log stream --level debug --style compact --predicate 'category == "CADebug"' > $out 2>&1 &
pid=$!
sleep 1
$tool $udid 31 on >/dev/null; sleep 3; $tool $udid 31 off >/dev/null
sleep 0.5; kill $pid
python3 -I $here/offsum.py $out
