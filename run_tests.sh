#!/usr/bin/env bash
# Run the headless Godot test suite. Some suites need >2 min, so use a
# generous per-test timeout.
#
# Usage:
#   ./run_tests.sh            # full suite
#   ./run_tests.sh --quick    # skip the long-running suites for a fast check
set -u

quick=0
if [ "${1:-}" = "--quick" ]; then
  quick=1
fi

mkdir -p /tmp/majesty-testout
fail=0

if [ "$quick" -eq 1 ]; then
  tests="sim agents inspect raids heroes manual"
else
  tests="sim agents inspect raids heroes fog ecology factions terrain halls hero_progression m7_rest manual"
fi

for t in $tests; do
  echo "===== $t ====="
  timeout 300 godot --headless --script "tests/${t}_test.gd" > "/tmp/majesty-testout/${t}.txt" 2>&1
  rc=$?
  grep -iE "RESULT:|FAIL:" "/tmp/majesty-testout/${t}.txt" | sort | uniq -c
  if [ $rc -ne 0 ]; then fail=1; fi
done
exit $fail
