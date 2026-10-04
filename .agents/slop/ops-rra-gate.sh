#!/bin/sh
# ops-rra-gate.sh -- the CPython gate for `resolve_returned_after` (ops.py:1899).
#
#   sh .agents/slop/ops-rra-gate.sh
#
# Eight rows, three lanes: CPython, bend interpreted, bend compiled. The diff IS the
# test. It runs the lanes ITSELF rather than calling ops-gate.sh, because that script
# exits non-zero ON a diff, and a mutation has to tell "the row moved" from "the file
# stopped compiling" -- two different findings one exit code cannot separate.
set -e
cd "$(dirname "$0")/../.."
GT=.agents/slop/ops-rra-gate
mkdir -p "$GT"

check_line=$(./bin/bend tinybendygrad/uop/ops.bend --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "ops-rra-gate: --check-only says '$check_line'" >&2
  exit 1
fi

run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" 2> "$out.err" | grep '^rra_' > "$out.tmp" && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  echo "ops-rra-gate: lane produced 0 rra_ rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

.venv/bin/python .agents/slop/ops-rra-oracle.py | grep '^rra_' > "$GT-py.txt"
run_lane "$GT-bd.txt" ./bin/bend tinybendygrad/uop/ops.bend
./bin/bend tinybendygrad/uop/ops.bend -o "$GT.bin"
run_lane "$GT-bn.txt" "$GT.bin"

diff "$GT-py.txt" "$GT-bd.txt" || { echo "ops-rra-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.txt" "$GT-bn.txt" || { echo "ops-rra-gate: DISAGREE (native)" >&2; exit 1; }

echo "ops-rra-gate: $(wc -l < "$GT-py.txt" | tr -d ' ') rows, 3 lanes identical"
