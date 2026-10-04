#!/bin/sh
# arena-sweep.sh -- run `.agents/slop/arena-sweep-jit.bend` at SEVERAL arena sizes and report
# whether the sensitive rows move. The `dd-sweep.sh` shape, for engine/jit.bend.
#
# WHY A SWEEP AND NOT ONE RUN. The `pl_step` literal-`0` bug read back as `srcops=Ops.NOOP`
# at k=0, and index 0 is the arena BOTTOM in EVERY size, so k=0 alone cannot tell a right
# answer from a wrong one. The `l2i_cdiv.abs` precedent is the same: an arena-aliasing defect
# in dtype.bend AGREED at one node-count configuration and broke at the next. So a fix is not
# evidence until it has held at several sizes, and k=0 is one of the sizes rather than the
# only one.
#
# THE ORACLE IS ASSERTED FIRST, BEFORE ANY DIFF IS REPORTED. A sweep that compares a changed
# port against nothing prints "no rows moved" for a program that printed nothing at all, and
# that is the failure mode `rebase-gate.py` exists to distinguish. So this script first
# checks that the k=0 block of the sweep REPRODUCES the committed gate's rows; only then does
# it diff the sizes.
#
# bend's machine stack overflows on ~1 run in 20 and prints ZERO rows, which is
# indistinguishable from "not started", so every attempt is LOOPED and a run with no `# k=`
# block is retried. Never gate on the exit code.
#
# usage: arena-sweep.sh
set -u
PROBE=.agents/slop/arena-sweep-jit.bend
COMMITTED=.agents/slop/arena-jit-fixed.txt
ORACLE=.agents/slop/jit-prune-oracle.txt
OUT=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/arena-sweep-jit.txt

i=0
while [ "$i" -lt 12 ]; do
  i=$((i + 1))
  perl -e 'alarm 2400; exec @ARGV' ./bin/bend "$PROBE" > "$OUT" 2>"$OUT.err"
  if grep -q '^# k=' "$OUT"; then break; fi
  sleep 8
done

if ! grep -q '^# k=' "$OUT"; then
  echo "SWEEP FAILED after $i attempts -- zero rows printed" >&2
  head -3 "$OUT.err" >&2
  exit 1
fi
echo "sweep ok (attempt $i), $(grep -c '^# k=' "$OUT") configurations"

# ASSERT THE ORACLE FIRST, AND ASSERT IT AGAINST CPython, NOT ONLY AGAINST THE PORT.
# Two assertions, in order, and the order is the point:
#   1. the sweep's k=0 block reproduces the gate's own rows, so the sweep is measuring the
#      same thing the gate measures and not a private fixture of its own;
#   2. the k=0 values equal what CPython answers for the same fixture, so the value being
#      held constant is a RIGHT answer rather than a stable wrong one.
# A sweep that skips (2) is the `nv_query_litter` shape: port and oracle both wrong, zero
# disagreements reported.
echo
echo "=== ASSERTION 1: does the sweep's k=0 reproduce the gate's rows?"
for r in prune_sig_kept prune_sig_once; do
  a=$(grep "^$r=" "$COMMITTED" | head -1 | sed "s/^$r=//")
  b=$(grep "^$r=" "$OUT" | head -1 | sed "s/^$r=//")
  if [ -z "$a" ]; then echo "  NO ROW $r in $COMMITTED -- refusing"; exit 1; fi
  if [ -z "$b" ]; then echo "  NO ROW $r in the sweep k=0 block -- refusing"; exit 1; fi
  if [ "$a" = "$b" ]; then
    echo "  REPRODUCED $r = $b"
  else
    echo "  MISMATCH $r"
    echo "    gate:   $a"
    echo "    sweep:  $b"
    exit 1
  fi
done

echo
echo "=== ASSERTION 2: do those values equal CPython's?"
for r in prune_sig_kept prune_sig_once; do
  a=$(grep "^$r=" "$ORACLE" | head -1 | sed "s/^$r=//")
  b=$(grep "^$r=" "$COMMITTED" | head -1 | sed "s/^$r=//")
  if [ "$a" = "$b" ]; then
    echo "  CPYTHON AGREES $r = $a"
  else
    echo "  CPYTHON DISAGREES $r"
    echo "    cpython: $a"
    echo "    port:    $b"
    exit 1
  fi
done

# NOW DIFF THE SIZES. The `# k=` line is the size, so it is excluded; everything else must be
# byte-identical across all six configurations.
echo
echo "=== SIZE SWEEP: every row except the '# k=' banner, across k = 0,1,2,5,17,64"
# The rows are the `name=value` LINES, and blank lines are separators, not rows. The first
# version compared raw line counts and read `42 rows / 7 distinct` as "rows MOVE", when the
# truth is the reverse: 6 real rows each printed 6 times, once per size, plus 6 blanks.
# A verdict computed on line counts is a verdict on the FILE FORMAT.
grep -v '^# k=' "$OUT" | grep -v '^[[:space:]]*$' > "$OUT.rows"
n=$(wc -l < "$OUT.rows" | tr -d ' ')
u=$(sort -u "$OUT.rows" | wc -l | tr -d ' ')
sizes=$(grep -c '^# k=' "$OUT")
per=$((n / sizes))
echo "  $per row(s) per configuration, $n lines total across $sizes sizes, $u distinct"
# CONSTANT iff every distinct row appears exactly ONCE PER SIZE. The first version tested
# `n == u`, which is false for any file that prints the same row in every block -- i.e. it
# reported "a size-sensitive defect survives" on a sweep whose whole result was CLEAN, and
# the reporter had to be corrected by reading the uniq -c table underneath it.
maxc=$(sort "$OUT.rows" | uniq -c | sort -rn | head -1 | awk '{print $1}')
if [ "$u" = "$per" ] && [ "$maxc" = "$sizes" ]; then
  echo "  RESULT: every row is byte-identical at all six sizes -- NO SIZE-SENSITIVE ROW"
else
  echo "  RESULT: a row's value depends on the size (max copies of one row = $maxc, want $sizes)"
  sort "$OUT.rows" | uniq -c | sort -rn | sed 's/^/    /'
fi
echo
echo "=== per-size block (raw)"
grep '^# k=' "$OUT"
echo
echo "full output: $OUT"