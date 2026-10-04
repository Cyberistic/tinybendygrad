#!/bin/sh
# key-pad-mutate.sh -- CALIBRATE `.agents/slop/key-pad-sweep.bend` BY INJECTING DEFECTS.
#
#   sh .agents/slop/key-pad-mutate.sh
#
# WHAT IT IS FOR. A pad sweep that has never been seen to FAIL is not known to be able to.
# So this injects four defect classes into `tinybendygrad/uop/ops.bend` -- one at a time,
# each a DIFFERENT KIND of wrongness, not four spellings of one -- runs the sweep, and
# diffs whole `name=value` lines. It then RESTORES and asserts the md5, because a mutation
# run that leaves the tree mutated is how a concurrent agent loses a commit.
#
# THE FOUR CLASSES, and why these four:
#   C1 wrong CONSTANT   `intern.find` is seeded at index 1, so node 0 is never a candidate.
#   C2 wrong OFFSET     `UOp.of.intern.put` reads `Arena.next - 2` instead of `- 1`.
#   C3 STALE ARENA      the intern HIT branch appends anyway, so a hit is a miss.
#   C4 DROPPED FIELD    `eq_tag`'s bool/int crossing is removed -- the defect this round
#                       actually fixed, re-injected so the sweep is measured against the
#                       class it was built for rather than against a proxy.
#
# EVERY MUTATION RUNS ON A `$TMPDIR` COPY OF THE FILE AND IS COPIED IN ONLY FOR THE RUN,
# then the pristine bytes are put back and the md5 asserted. There is no path here that
# leaves `tinybendygrad/uop/ops.bend` different from how it started.
set -u
cd "$(dirname "$0")/../.."

TARGET=tinybendygrad/uop/ops.bend
SWEEP=.agents/slop/key-pad-sweep.bend
T=$(mktemp -d)
trap 'cp "$T/PRISTINE" "$TARGET" 2>/dev/null; rm -rf "$T"' EXIT INT TERM

cp "$TARGET" "$T/PRISTINE"
PRISTINE_MD5=$(md5 -q "$T/PRISTINE")
echo "pristine md5 = $PRISTINE_MD5"

run_sweep() { sh .agents/slop/runrows.sh "$SWEEP" "$T/sweep.txt" 2>/dev/null; }

# The SECOND lane, and it is the reason C1/C2 being invisible above is a statement about
# the PAD SWEEP rather than about the file: `ops.bend`'s own 284 rows are a pad-0 sweep
# over a much wider set of arms. A defect class that the pad sweep misses and the main
# gate catches has been handed off, not lost.
run_opsrows() { sh .agents/slop/runrows.sh tinybendygrad/uop/ops.bend "$T/ops.txt" 2>/dev/null; }

# `restore` puts the pristine bytes back. Called before every mutation so a mutation that
# fails to apply cannot inherit the previous one's tree.
restore() { cp "$T/PRISTINE" "$TARGET"; }

restore
run_sweep
cp "$T/sweep.txt" "$T/BASE.txt"
run_opsrows
cp "$T/ops.txt" "$T/OPSBASE.txt"
echo "base: sweep $(grep -c . "$T/BASE.txt") lines, ops.bend $(grep -c . "$T/OPSBASE.txt") lines"

mutate() {
  name="$1"; find="$2"; repl="$3"
  restore
  python3 - "$TARGET" "$find" "$repl" <<'PY'
import sys
p, find, repl = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
n = s.count(find)
assert n == 1, f"pattern occurs {n} times, expected 1: {find!r}"
open(p, 'w').write(s.replace(find, repl))
print(f"  applied {find[:48]!r}")
PY
  [ $? -ne 0 ] && { echo "$name: MUTATION DID NOT APPLY"; return 1; }
  if run_sweep; then
    echo "$name: pad-sweep lines moved = $(diff "$T/BASE.txt" "$T/sweep.txt" | grep -c '^[<>]')"
    diff "$T/BASE.txt" "$T/sweep.txt" | grep '^[<>]' | sed 's/^/    /'
  else
    echo "$name: pad-sweep NO ROWS (compile failure or stack overflow)"
  fi
  if run_opsrows; then
    echo "$name: ops.bend lines moved = $(diff "$T/OPSBASE.txt" "$T/ops.txt" | grep -c '^[<>]')"
    diff "$T/OPSBASE.txt" "$T/ops.txt" | grep '^[<>]' | head -10 | sed 's/^/    /'
  else
    echo "$name: ops.bend NO ROWS (compile failure or stack overflow)"
  fi
}

echo
echo "=== C1 wrong CONSTANT: intern.find seeded at 1 ==="
mutate C1 "intern.find(t, st, U32.add(k, 1), want, depth)" "intern.find(t, st, U32.add(k, 2), want, depth)"

echo
echo "=== C2 wrong OFFSET: UOp.of.intern.put reads next-2 ==="
mutate C2 "case None{}: U32.sub(Arena.next(ar), 1)" "case None{}: U32.sub(Arena.next(ar), 2)"

echo
echo "=== C3 STALE ARENA: the intern HIT branch appends anyway ==="
mutate C3 "case Some{i}: ar" "case Some{i}: intern.put.shp(ar, want, depth)"

echo
echo "=== C4 DROPPED FIELD: eq_tag's bool/int crossing removed ==="
mutate C4 "    case TInt{y1}: eq_bool(Bool.not(U32.is_zero(y1)), b)
" ""
restore

echo
NOW=$(md5 -q "$TARGET")
echo "restored md5 = $NOW"
[ "$NOW" = "$PRISTINE_MD5" ] && echo "TREE RESTORED, md5 matches" || { echo "TREE NOT RESTORED -- ABORT"; exit 1; }