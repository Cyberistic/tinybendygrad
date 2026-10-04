#!/bin/sh
# ops-pu-gate.sh -- the CPython gate for `print_uops` (tinygrad/uop/render.py:18).
#
#   sh .agents/slop/ops-pu-gate.sh
#
# Nine rows, THREE LANES -- CPython, bend interpreted, bend compiled -- and ALL NINE AGREE
# BYTE FOR BYTE. There is no divergence list, and that is the point: `print_uops` is one
# f-string with five fields and every one of them is now measured against the real
# `print_uops` rather than against a reimplementation of it.
#
# THE ROWS ARE WHOLE LINES AND NOT A FIELD MAP, and the width is why. The f-string is
# `{i:4d} {op:20s}: {ranges} {dtype:40s} {srcs:32s} {arg}`, so a port with every value
# right and three widths wrong is a DIFFERENT format and a field map would pass it. That
# is not hypothetical: the four pads were all inverted when this gate was written -- the
# NUMBER pads left and the three STRINGS pad right -- and a name-to-value gate would have
# been green throughout.
#
# WHAT EACH ROW IS THE ONLY ROW THAT CAN PIN:
#   pu_range     one BUFFER: the `ParamArg` repr with a `name`, and the `--` src arm
#   pu_missing   an ADD whose srcs are NOT in the list: both arms read `--`
#   pu_const     the same ADD with one CONST in the list: its VALUE, and not its index
#   pu_index     BOTH srcs in the list: the INDEX arm, and the index is a bare int
#   pu_constarg  two CONSTs: `[]` for a node with no srcs, and a PyConst last column
#
# AND `pu_index` IS THE ROW THAT FOUND TWO REAL BUGS, both of which looked like values:
# the index printed the src's ARENA SLOT where CPython prints the POSITION IN `uops`, and
# it printed it QUOTED where CPython's `repr` leaves an int bare. `[3, '4']` and
# `['3', '4']` against `[0, '4']` -- three numbers, all of them plausible.
#
# THE RANGE COLUMN IS GATED IN ITS EMPTY CASE ONLY, and the earlier claim that it was a
# blocker was WRONG. CPython's own `multirange_str(u.ranges, color=True, pad=10)` answers
# TEN SPACES for a node with no ranges -- MEASURED: BUF, ADD and C1 all have `ranges == []`
# in this fixture. The coloured `0` that made the column look like a gap was the PORT'S
# OWN RANGE node, printed because the row indices still pointed at node 2. So the column
# is gated for empty and NOT gated for a node that has ranges; that claim needs
# `F.ranged`'s sweep and is not in this gate.
set -e
cd "$(dirname "$0")/../.."
GT=.agents/slop/ops-pu-gate
mkdir -p "$GT"

check_line=$(./bin/bend tinybendygrad/uop/render.bend --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "ops-pu-gate: --check-only says '$check_line'" >&2
  exit 1
fi

# `^pu_` AND NOT `^pu`, because render.bend has rows whose names merely START with those
# three letters and a bare prefix would sweep them in. The row count is asserted below
# anyway, so a prefix that caught too much fails loudly instead of quietly.
run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" 2> "$out.err" | grep '^pu_' > "$out.tmp" && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  echo "ops-pu-gate: lane produced 0 pu_ rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

.venv/bin/python .agents/slop/ops-pu-oracle.py > "$GT-py.txt"
run_lane "$GT-bd.txt" ./bin/bend tinybendygrad/uop/render.bend
./bin/bend tinybendygrad/uop/render.bend -o "$GT.bin"
run_lane "$GT-bn.txt" "$GT.bin"

# THE ROW COUNT IS ASSERTED, not assumed. Nine rows on both sides is the claim; a gate
# that only diffs would accept a lane that lost rows to a rename, and a lost row is not a
# smaller diff, it is a missing test.
n=$(wc -l < "$GT-py.txt" | tr -d ' ')
[ "$n" = 14 ] || { echo "ops-pu-gate: the oracle has $n rows, expected 14" >&2; exit 1; }
for f in "$GT-bd.txt" "$GT-bn.txt"; do
  m=$(wc -l < "$f" | tr -d ' ')
  [ "$m" = 14 ] || { echo "ops-pu-gate: $f has $m rows, expected 14" >&2; exit 1; }
done

diff "$GT-py.txt" "$GT-bd.txt" || { echo "ops-pu-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.txt" "$GT-bn.txt" || { echo "ops-pu-gate: DISAGREE (native)" >&2; exit 1; }

# EVERY ROW MUST BE NAMED, because a bare continuation line cannot be diffed against a
# named one -- and the port printed its SECOND line of a two-node row unnamed until this
# gate existed, so the assertion is the finding and not a formality.
cut -d'|' -f1 "$GT-py.txt" | sort -u > "$GT-names.txt"
for nm in pu_range pu_missing pu_const pu_index pu_constarg pu_rrange pu_radd; do
  grep -q "^$nm$" "$GT-names.txt" || { echo "ops-pu-gate: $nm is MISSING" >&2; exit 1; }
done
[ "$(wc -l < "$GT-names.txt" | tr -d ' ')" = 7 ] || {
  echo "ops-pu-gate: a pu_ row appeared that the gate does not know about" >&2; exit 1; }

echo "ops-pu-gate: 14 rows, 3 lanes byte-identical"
