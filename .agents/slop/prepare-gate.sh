#!/bin/sh
# prepare-gate.sh -- the CPython gate for tinybendygrad/schedule/prepare.bend.
#
#   sh .agents/slop/prepare-gate.sh
#
# 321 rows, three lanes: CPython, bend interpreted, bend compiled. The diff IS the
# test.
#
# WHY THIS FILE HAD TO BE WRITTEN. The unit has had `.agents/slop/prepare-oracle.py`
# (828 lines) and TWO captured outputs (`prepare_bend.txt`, `prepare_native.txt`)
# since before this gate existed, and NEITHER capture was ever diffed by anything.
# They are not a gate: a capture records one run, and nothing re-ran it. Measured
# drift: the capture said `wm_buf_in=...|int` where the live file says `|i32`, 72
# lines of it, and CPython says `dtypes.int32.name == 'i32'` -- so the LIVE side was
# the correct one and the fix that made it correct was unprovable. A 990-line file
# with 321 rows and no gate is a file whose output nobody reads.
#
# The two captures are kept as the pre-fix baseline and this gate's own three lanes
# are the contract from here. A capture that disagrees with a lane is not evidence
# against the lane; it is a stale file, and the way to tell them apart is to ask
# CPython, which is what the `py` lane is.
set -e
cd "$(dirname "$0")/../.."
GT=.agents/slop/prepare-gate
mkdir -p "$GT"

check_line=$(./bin/bend tinybendygrad/schedule/prepare.bend --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "prepare-gate: --check-only says '$check_line'" >&2
  exit 1
fi

# The PORT's row names come first, and the oracle is filtered TO them. Doing it the
# other way round -- filtering both by prefix -- compares 711 oracle rows against 321
# port rows and fails on the five extra detail rows per pattern the port never
# claimed. See prepare-rows.py for why a name set and not a prefix.
./bin/bend tinybendygrad/schedule/prepare.bend 2>/dev/null \
  | grep -E '^(fma|mop|inl|dsk|ear|mcl|wm)_' > "$GT-bd.txt"
[ -s "$GT-bd.txt" ] || { echo "prepare-gate: the port printed 0 rows" >&2; exit 1; }

.venv/bin/python .agents/slop/prepare-oracle.py 2>/dev/null > "$GT-oracle.txt"
.venv/bin/python - "$GT-oracle.txt" "$GT-bd.txt" "$GT-py.txt" << 'PY'
import sys
sys.path.insert(0, ".agents/slop")
from prepare_rows import port_rows, select
oracle, bd, out = sys.argv[1], sys.argv[2], sys.argv[3]
wanted = port_rows(open(bd).read())
got, missing = select(open(oracle).read(), wanted)
if missing:
  print(f"prepare-gate: the oracle does not produce {len(missing)} of the port's rows: "
        f"{missing[:5]}", file=sys.stderr)
  sys.exit(1)
with open(out, "w") as f:
  for name, lines in got:
    # a name the oracle emits MORE than once (a duplicated row) is a finding
    if len(lines) != 1:
      print(f"prepare-gate: the oracle emits {name} {len(lines)} times", file=sys.stderr)
      sys.exit(1)
    f.write(lines[0] + "\n")
PY

./bin/bend tinybendygrad/schedule/prepare.bend -o "$GT.bin"
"$GT.bin" 2>/dev/null | grep -E '^(fma|mop|inl|dsk|ear|mcl|wm)_' > "$GT-bn.txt"
[ -s "$GT-bn.txt" ] || { echo "prepare-gate: the native lane printed 0 rows" >&2; exit 1; }

diff "$GT-py.txt" "$GT-bd.txt" || { echo "prepare-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.txt" "$GT-bn.txt" || { echo "prepare-gate: DISAGREE (native)" >&2; exit 1; }

echo "prepare-gate: $(wc -l < "$GT-py.txt" | tr -d ' ') rows, 3 lanes identical"
echo "prepare-gate: the oracle emits $(wc -l < "$GT-oracle.txt" | tr -d ' ') rows; the other $(($(wc -l < "$GT-oracle.txt") - $(wc -l < "$GT-py.txt"))) are NOT PORTED and this gate does not claim them"
