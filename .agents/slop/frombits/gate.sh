#!/bin/zsh
# FROMBITS GATE -- BOTH LANES, BOTH HALVES.
#
#   census   F32.from_bits round-trips the WHOLE 2^32 space, C lane, in chunks,
#            and counts the NaN payloads that survive against a denominator.
#   laws     the six dtype.bend laws retired on the back of from_bits, diffed
#            against CPython + tinygrad/dtype.py, whole `name=value` lines.
#
# THE JS CENSUS IS A SEPARATE, SMALLER CLAIM. The JS runtime cannot carry a NaN
# payload at all (comp.ts:539), so a whole-space JS census would spend its whole
# budget re-measuring one known collapse. `JS_NAN` patterns of the NaN region are
# swept instead and the collapse is asserted with the SAME denominator machinery,
# so the two lanes answer the same question and disagree.
set -e
ROOT=${0:A:h}/../../..
HERE=${0:A:h}
BEND=$ROOT/bin/bend
TMP=${TMPDIR:-/tmp}/fbgate.$$
mkdir -p $TMP
trap 'rm -rf $TMP' EXIT

$BEND $HERE/sweep.bend --check-only > $TMP/check.txt 2>&1 || true
grep -q 'ALL PROOFS CHECK' $TMP/check.txt || {
  echo "SWEEP NOT CLEAN"; cat $TMP/check.txt; exit 1; }
$BEND $ROOT/tinybendygrad/base.bend --check-only > $TMP/check2.txt 2>&1 || true
grep -q 'ALL PROOFS CHECK' $TMP/check2.txt || {
  echo "base.bend NOT CLEAN"; cat $TMP/check2.txt; exit 1; }

$BEND $HERE/sweep.bend -o $TMP/sweep.c > /dev/null 2>&1
cc -w -O2 -o $TMP/sweepc $TMP/sweep.c -lm
$BEND $HERE/gate_dtype.bend -o $TMP/gd.c > /dev/null 2>&1
cc -w -O2 -o $TMP/gdc $TMP/gd.c -lm

python3 $HERE/expect.py --census > $TMP/expect.txt

# Chunk sizes are the largest MEASURED to run, minus a margin. Bend has no tail
# call, so a recursion's depth IS its iteration count: the JS runtime overflows
# at ~40000 (20000 ran) and the C runtime at ~300M (200M ran).
JS_N=20000
C_N=200000000
JS_NAN=200000

echo "=== census: C lane, WHOLE 2^32 space ==="
python3 $HERE/run.py --lane c --binary $TMP/sweepc --chunk $C_N \
  --expect $TMP/expect.txt

echo "=== census: JS lane, the NaN region ==="
python3 $HERE/run.py --lane js --bend $BEND --sweep $HERE/sweep.bend \
  --chunk $JS_N --start 2139095040 --space $((2139095040 + JS_NAN)) \
  --expect $TMP/expect.txt

echo "=== laws: JS lane (NaN-answering rows skipped, count printed) ==="
python3 $HERE/gate_dtype.py --lane js --bend $BEND

echo "=== laws: C lane (every row) ==="
python3 $HERE/gate_dtype.py --lane c --binary $TMP/gdc
