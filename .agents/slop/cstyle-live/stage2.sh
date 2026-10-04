#!/bin/zsh
# STAGE 2 -- DOES IT RUN, AND DOES IT AGREE WITH CPython?
#
# Reproduce:  zsh .agents/slop/cstyle-live/stage2.sh
#
# THE FOUR STEPS ARE NAMED EVERYWHERE: `bend` / `cc` / link / run. A failure says which.
#
# THE EXPECTATION IS NOT TYPED. `cstyle-numbers.py` computes it by RUNNING tinygrad's CPU
# backend on the same program -- the path that emits C with cstyle.py, compiles it with
# clang, mmaps it and calls it (tinygrad/runtime/ops_cpu.py:29-72). Readings from the
# PYTHON device (no compiler at all) and from float64 arithmetic are printed too, so the
# reader can see the fixture is SENSITIVE: if f64 agreed with the f32 kernel here, the lane
# could not fail and would be worthless.
#
# TWO INPUTS, for two different reasons, and neither is a duplicate of the other:
#   TIE      [1, 2, 3, 4] -- the exact program `cstyle-oracle.py` captured, so the compiled
#                           kernel and its originating program are ONE artifact.
#   DISTINCT [1, 0.1, -2.5, 3.75] -- four DIFFERENT values, one of them (0.1) not
#                           representable in float32. Four equal values would hide a
#                           lane-ordering bug, and 1..5 are all exactly representable so
#                           they would hide a dtype bug.
set -u
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
BEND=$REPO/bin/bend
L=$REPO/.agents/slop/cstyle-live
W="$TMPDIR/cstyle-live"
export W
cd "$W" || exit 1
TIE=0000803f000000400000404000008040
DIST=0000803fcdcccc3d000020c000007040

print -r -- "=== STEP 0 (bend): the port's emitted text ==="
$BEND "$W/tree/tinybendygrad/renderer/emit-real.bend" 2>/dev/null > "$W/live.txt" \
  || { print -r -- "  step1 bend FAILED"; exit 1; }
python3 "$L/unlive.py" "$W/live.txt" 'live CLANG full' "$W/live_clang_full.c" | sed 's/^/  /'
print -r -- "  the exact kernel:"
sed 's/^/    | /' "$W/live_clang_full.c"

print -r -- ""
print -r -- "=== BYTE-IDENTITY WITH WHAT CPYTHON ACTUALLY COMPILED AND RAN ==="
(cd "$REPO" && PYTHONPATH=. DEV=CPU python3 "$L/cstyle-oracle.py" > "$W/cpython_real.c") \
  || { print -r -- "  oracle FAILED"; exit 1; }
if diff -q "$W/cpython_real.c" "$W/live_clang_full.c" >/dev/null; then
  print -r -- "  IDENTICAL   port   sha256 $(shasum -a 256 "$W/live_clang_full.c" | cut -d' ' -f1)"
  print -r -- "  IDENTICAL   cpython sha256 $(shasum -a 256 "$W/cpython_real.c" | cut -d' ' -f1)"
else
  print -r -- "  DIFFER:"; diff "$W/cpython_real.c" "$W/live_clang_full.c" | sed 's/^/    /'
fi

print -r -- ""
print -r -- "=== STEP 2+3 (cc + link): the emitted text and a host driver, ONE TU ==="
cp "$L/stage2-driver.c" "$W/stage2-driver.c"
print -r -- "  \$ cc -x c -O2 stage2-driver.c -o stage2.out    # driver #includes the emitted text"
cc -x c -O2 "$W/stage2-driver.c" -o "$W/stage2.out" 2>"$W/stage2.cc.err"
if [[ $? -ne 0 ]]; then
  print -r -- "  step2 COMPILE FAILED:"; head -5 "$W/stage2.cc.err" | sed 's/^/    /'; exit 1
fi
print -r -- "  step2 compiled ok;  step3 link ok"

pass=1
for name in TIE DISTINCT; do
  if [[ $name == TIE ]]; then IN_HEX=$TIE; else IN_HEX=$DIST; fi
  print -r -- ""
  print -r -- "=== STEP 4 (run), fixture $name ==="
  python3 "$L/stage2-io.py" in "$W/in_$name.bin" $IN_HEX | sed 's/^/  /'
  print -r -- "  \$ ./stage2.out in_$name.bin out_$name.bin   # TWICE, two processes"
  for run in 1 2; do
    "$W/stage2.out" "$W/in_$name.bin" "$W/out_${name}_$run.bin" \
      || { print -r -- "  step4 RUN FAILED rc=$?"; pass=0; break; }
    print -r -- "    run$run sha256 $(shasum -a 256 "$W/out_${name}_$run.bin" | cut -d' ' -f1)"
  done
  print -r -- "  run1 vs run2: $(python3 "$L/stage2-io.py" diff "$W/out_${name}_1.bin" "$W/out_${name}_2.bin" | sed 's/.*: //') differing bytes"
  print -r -- "  CPython's numbers for the same program (never typed):"
  (cd "$REPO" && python3 "$L/cstyle-numbers.py" --in $IN_HEX --all) | sed 's/^/    /'
  CPU_HEX=$(cd "$REPO" && python3 "$L/cstyle-numbers.py" --in $IN_HEX)
  print -r -- "    CPU expectation hex: $CPU_HEX"
  for run in 1 2; do
    python3 "$L/stage2-io.py" out "$W/out_${name}_$run.bin" $CPU_HEX | sed 's/^/    /' || pass=0
  done
done

print -r -- ""
print -r -- "=== NEGATIVE CONTROL: a comparison that CAN fail ==="
print -r -- "  flipping one low bit of in[1] (0.1f becomes a different float32):"
python3 -c "
import pathlib
b = bytearray(pathlib.Path('$W/in_DISTINCT.bin').read_bytes()); b[5] ^= 1
pathlib.Path('$W/in_bad.bin').write_bytes(bytes(b))"
"$W/stage2.out" "$W/in_bad.bin" "$W/out_bad.bin"
# ⚠ NOT `if cmd | sed; then`. A pipeline's exit status is the LAST command's, so
# `stage2-io.py` exiting 1 on MISMATCH was swallowed by `sed` exiting 0 and the control
# reported FAILURE while its own output said MISMATCH. MEASURED: the first run of this
# script printed "MISMATCH ... differing bytes: 1" on one line and "!! CONTROL FAILED" on
# the next. The status is taken from the python process itself, then printed.
python3 "$L/stage2-io.py" out "$W/out_bad.bin" 00000040cdcc8c3f0000c0bf00009840 \
  > "$W/control.txt" 2>&1
ctl=$?
sed 's/^/  /' "$W/control.txt"
if [[ $ctl -ne 0 ]]; then
  print -r -- "  control PASSED (perturbed input -> MISMATCH), so the OKs above mean something."
else
  print -r -- "  !! CONTROL FAILED: a perturbed input still matched, so the OKs above prove"
  print -r -- "     NOTHING and every one of them must be discarded."
  pass=0
fi
print -r -- ""
print -r -- "STAGE 2: $([[ $pass -eq 1 ]] && print PASS || print FAIL)"