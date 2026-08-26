#!/usr/bin/env bash
# Regression test for the `path-profile` monitor.
#
#   ./build.sh wizeng x86-64-linux        # build first
#   test/monitors/path_profile_test.sh    # then run this
#
# Each path_profile_*.wat has a matching .expected holding the `func`/`counts[]` lines the monitor
# should print. Regenerate them (after verifying a change is intended!) with REGEN=1.

set -u
cd "$(dirname "$0")/../.." || exit 1

WIZENG=${WIZENG:-./bin/wizeng.x86-64-linux}
if [ ! -x "$WIZENG" ]; then
    echo "no engine at $WIZENG -- run: ./build.sh wizeng x86-64-linux"
    exit 1
fi

fail=0
run() { # <name> <wasm>
    local name=$1 wasm=$2 exp="test/monitors/path_profile_$1.expected"
    local got
    got=$("$WIZENG" --monitors=path-profile "$wasm" 2>&1 | grep -E "^func|counts\[")
    if [ "${REGEN:-0}" = "1" ]; then echo "$got" > "$exp"; echo "regen  $name"; return; fi
    if [ "$got" = "$(cat "$exp")" ]; then
        echo "ok     $name"
    else
        echo "FAIL   $name"
        diff <(cat "$exp") <(echo "$got") | sed 's/^/         /'
        fail=1
    fi
}

for wat in test/monitors/path_profile_*.wat; do
    wasm="${wat%.wat}.wasm"
    [ "$wat" -nt "$wasm" ] && wat2wasm "$wat" -o "$wasm"
    run "$(basename "${wat%.wat}" | sed 's/^path_profile_//')" "$wasm"
done
run demo_paths demo_paths.wasm

# Invariant that must hold for every function: the counts sum to the number of activations.
# Not machine-checked here (activation counts are not in the output) but see doc §8.

exit $fail
