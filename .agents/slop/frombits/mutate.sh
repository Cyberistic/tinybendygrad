#!/bin/zsh
# PLANT AND DISARM. THE DISARM RUNS FIRST.
#
# "A disarm that moves something is not a failed disarm -- it is a defect that has
# not been named yet." TWICE, here, and both were mine:
#
#   D1  replaced `(bits & 0x7F800000) != 0x7F800000` with `bits < 0x7F800000`.
#       That is false for EVERY pattern with the sign bit set, so it is a
#       different predicate, not a different spelling. MOVED 116984 rows.
#   D2  replaced `is_eq(masked, c)` with `is_ne(masked, c)`. Those are
#       COMPLEMENTS, so this inverted the test rather than respelling it.
#       MOVED 215288 rows.
#
# Both were caught, and caught only because the run diffs whole `name=value`
# lines against CPython. D3 changes the EXPRESSION and not the SENSE --
# `is_eq` against the complement of `is_ne` -- and moves 0.
#
# THE LIVE TREE IS NEVER EDITED. The first version of this script mutated
# `tinybendygrad/dtype.bend` in place and restored it from a snapshot on EXIT,
# and a run killed by the 120s tool timeout left plant P1 sitting in the live
# tree -- answering a plausible float for 214016 rows and STILL COMPILING. That
# is a disarm that removed the fix and became a second mutation. So every
# mutation here is applied to a copy inside a SYMLINKED TREE, which a driver in
# `$TMP` imports instead of the live file. Nothing to restore, because nothing
# in `tinybendygrad/` is written.
#
# THE PLANTS.
#   P1  `F32.from_bits` -> `U32.to_f32` in `Dt.bf16`. THE TRAP THE BRIEF NAMES:
#       `U32.to_f32` is the NUMERIC conversion and it is a `U32 -> F32` law, so
#       it TYPE-CHECKS. The port compiles clean and answers a plausible float.
#   P2  the fp8 exponent shift `U32.sub(sig, 1)` -> `sig`. One bit of exponent,
#       silently wrong for every code. A bug this lane really made and fixed.
#   P3  the fp8 exponent MASK `fp8_exp_max(kind)` -> `127`.
#   P4  the CENSUS's own NaN test, blinded. `mismatch` and `sum_in` are computed
#       from the round trip and the inputs, so this must move the NaN COUNTERS and
#       nothing else -- which is the claim, and it is the claim that a gate whose
#       denominator comes from the thing under test cannot support.
#
#       IT PASSED THE FIRST TIME, over a 400000000-pattern window. That window
#       contains ZERO NaN patterns -- the first one is at 2139095040 -- so
#       blinding the NaN test changed nothing in it and the run said PASS. A NaN
#       census over a NaN-free window is a claim about no patterns. `run.py` now
#       REFUSES a partial range whose NaN denominator is 0 rather than reporting
#       a zero, and P4 runs over the whole space.
set -e
ROOT=${0:A:h}/../../..
HERE=${0:A:h}
BEND=$ROOT/bin/bend
TMP=${TMPDIR:-/tmp}/fbmut.$$
mkdir -p $TMP
DT=$ROOT/tinybendygrad/dtype.bend

# THE TREE IS COPIED, NOT SYMLINKED. Two reasons, both measured:
#   * `dtype.bend` resolves `./LAWS/spec.bend` and `./helpers.bend` relative to
#     ITSELF, so a lone mutated copy in $TMP finds nothing -- agent-core records
#     that as "22 phantom blind spots in one unit".
#   * symlinking does not help either: `book_load` realpaths every file
#     (bend.ts:960), so the imported NAME comes out relative to the REAL path and
#     `bend` rejects it with a message about the hub. Copying is 1MB.
# The only difference in the whole closure is the file under test.
rm -rf $TMP/tinybendygrad
cp -R $ROOT/tinybendygrad $TMP/tinybendygrad

cat > $TMP/tinybendygrad/drv.bend <<EOF
import Base
import ./base.bend as F
import ./helpers.bend as H
import ./dtype.bend as D

def r1(p: U32, b: U32) -> String:
  String.concat(["bf16_", U32.show(p), "=", U32.show(F32.bits(D.Dt.bf16(b))), " "])

def r16(p: U32, b: U32) -> String:
  String.concat(["fp16_", U32.show(p), "=",
                 U32.show(F32.bits(D.Dt.fp16(F.F32.from_bits(b)))), " "])

def r8(+p: U32, k: U32, kind: U32) -> String:
  String.concat(["fp8_", U32.show(k), "_", U32.show(U32.and(p, 255)), "=",
                 U32.show(F32.bits(D.Dt.fp8_to(U32.and(p, 255), kind))), " "])

def one(+p: U32) -> List<&2, String>:
  [r1(p, p), r16(p, p), r8(p, 0, 0), r8(p, 1, 1), r8(p, 2, 2), r8(p, 3, 3)]

def sweep(m: Nat, fuel: Word(m), +start: U32, +i: U32,
          acc: List<&2, String>) -> List<&2, String>:
  match m fuel:
    case 0n WNil{}:
      List.reverse(&2, String, acc)
    case 1n+p WCon{b, rest}:
      pat = U32.add(start, i)
      sweep(p, rest, start, U32.add(i, 1),
            List.append(&2, String, one(pat), acc))

def run(start: U32, cn: U32) -> String:
  +count = U32.to_nat(cn)
  String.concat(sweep(count, Word.zero(count), start, 0, Nil{}))

def main() -> IO(Unit):
  do IO<Unit>:
    st : U32 <- H.getenv_int("FB_START", 0)
    cn : U32 <- H.getenv_int("FB_COUNT", 0)
    p : Unit <- IO.print(run(st, cn))
    return p
EOF

snap() { cp $DT $TMP/tinybendygrad/dtype.bend; }
# `bend` resolves a non-hub import's NAME as `path.relative(top, file)` and then
# demands that name match /^(\/|(\.\.\/)*)(Name\/)*Name$/ (bend.ts:967). `top` is
# the CWD, so the driver only elaborates if `bend` is RUN FROM $TMP -- from the
# repo root the name comes out `../../var/folders/.../base` and the import is
# rejected with a message about the hub, which is not what is wrong.
build() {
  (cd $TMP && $BEND tinybendygrad/drv.bend -o gd.c) > /dev/null 2>&1 || {
    echo "  BUILD FAILED"; (cd $TMP && $BEND tinybendygrad/drv.bend --check-only) 2>&1 | head -6; return 1; }
  cc -w -O2 -o $TMP/gdc $TMP/gd.c -lm
}
run() { python3 $HERE/gate_dtype.py --lane c --binary $TMP/gdc 2>&1 | head -1; }
mut() { python3 - "$TMP/tinybendygrad/dtype.bend" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert old in s, "site not found: " + old[:60]
open(p, "w").write(s.replace(old, new))
PY
}

python3 $HERE/expect.py --census > $TMP/expect.txt

echo "=== BASE ==="
snap; build; run

echo "=== DISARM D3  (bf16 isfinite: is_eq(m,c) -> not(is_ne(m,c))) ==="
mut "U32.is_eq(U32.and(bits, 2139095040),
                                           2139095040)" \
    "Bool.not(U32.is_ne(U32.and(bits, 2139095040),
                                           2139095040))"
build; run

echo "=== PLANT P1  (F32.from_bits -> U32.to_f32: THE TRAP) ==="
snap
mut "def Dt.bf16(+bits: U32) -> F32:
  F.F32.from_bits(" \
    "def Dt.bf16(+bits: U32) -> F32:
  U32.to_f32("
echo "  type-check of the planted file:"
(cd $TMP && $BEND tinybendygrad/dtype.bend --check-only) 2>&1 | head -2 | sed 's/^/  /'
build; run

echo "=== PLANT P2  (fp8 exponent shift: U32.sub(sig, 1) -> sig) ==="
snap
mut "U32.shrn(x, U32.to_nat(U32.sub(sig, 1)))" "U32.shrn(x, U32.to_nat(sig))"
build; run

echo "=== PLANT P3  (fp8 exponent mask: fp8_exp_max(kind) -> 127) ==="
snap
mut "fp8_exp_max(kind))
  fp8_decode.sat(" "127)
  fp8_decode.sat("
build; run

echo "=== PLANT P4  (the CENSUS's own NaN test, blinded) ==="
cp $HERE/sweep.bend $TMP/sweep.orig.bend
python3 - "$HERE/sweep.bend" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "U32.is_ne(U32.and(p, 8388607), 0)"
new = "U32.is_gt(U32.and(p, 8388607), 4294967295)"
assert old in s, "P4 site not found"
open(p, "w").write(s.replace(old, new))
PY
$BEND $HERE/sweep.bend -o $TMP/sw.c > /dev/null 2>&1
cc -w -O2 -o $TMP/swc $TMP/sw.c -lm
python3 $HERE/run.py --lane c --binary $TMP/swc --chunk 200000000 \
  --expect $TMP/expect.txt 2>&1 | tail -6
cp $TMP/sweep.orig.bend $HERE/sweep.bend

echo "=== CONTROL: census, unblinded, whole space ==="
snap; build
$BEND $HERE/sweep.bend -o $TMP/sw.c > /dev/null 2>&1
cc -w -O2 -o $TMP/swc $TMP/sw.c -lm
python3 $HERE/run.py --lane c --binary $TMP/swc --chunk 200000000 \
  --expect $TMP/expect.txt 2>&1 | tail -6

echo "=== LIVE TREE UNTOUCHED ==="
(cd $TMP && $BEND $DT --check-only) 2>&1 | head -2
