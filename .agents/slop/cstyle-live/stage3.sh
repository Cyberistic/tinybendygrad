#!/bin/zsh
# STAGE 3 -- CALL THE EMITTED KERNEL FROM BEND.
#
# Reproduce:  zsh .agents/slop/cstyle-live/stage3.sh
#
# THE CHAIN, and each step is named in the output:
#   step1  bend stage3.bend -o stage3.c   # INLINES shim3.c, which carries the port's own
#                                          # emitted C text verbatim
#   step2  cc stage3.c -o stage3.out
#   step3  (link, same cc invocation)
#   step4  ./stage3.out
#
# WHAT IS ASKED OF BEND: allocate the input and output buffers, fill them, obtain the
# kernel's entry point AS A `Nat`, call through it, and read the output back.
#
# THE ALLOCATOR IS ops_bend.bend's, REUSED NOT REWRITTEN. `Mem`, `Mem.of`, `Mem.base`,
# `Mem.nbytes`, `first.of`, `raw_alloc` and the no-op `raw_free` are IMPORTED from
# `tinybendygrad/runtime/ops_bend.bend` and used as they are. What cannot be imported is
# `raw_alloc`'s BACKING STORE, and the reason is a measurement rather than a preference:
# `ops_bend.bend:1476`'s `raw_alloc` answers `Mem{base = Store.top(s), nbytes}` where
# `Store.ms` is a `List<&2, U32>`, so `Mem.base` is an INDEX INTO A BEND LIST, and Bend
# exposes no address for a `List` at all. This script PRINTS both numbers side by side --
# the Bend list index is 0, and a C `mmap` of the same 16 bytes is a real address -- so the
# two number spaces are visible rather than asserted. Same contract (bump, no free),
# different substrate; that swap is the whole difference between ops_bend's allocator (which
# executes a uop graph) and this one (whose bytes are handed to a C function that needs an
# address).
set -u
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
BEND=$REPO/bin/bend
L=$REPO/.agents/slop/cstyle-live
W="$TMPDIR/cstyle-live"
R=$W/tree/tinybendygrad/renderer
cd "$W" || exit 1
rm -rf "$W/s3"; mkdir -p "$W/s3"
pass=1

# THE LANE READER. `$1` is `BEND_LANE` and `$2` is the index -- comparing `$1` against the
# two-word key yields the EMPTY string for every lane, which reads as a MISMATCH and, worse,
# made the negative control "pass" for the wrong reason. MEASURED on the first run of this
# script. Four lanes are REQUIRED to be present: an absent lane is a failure of THIS
# HARNESS, not a disagreement by the kernel, and returning 1 says so out loud.
#
# ⚠ NOT THE WHOLE STDOUT EITHER: it carries `C_MMAP_ADDR`, `C_FREE_RETURNS_SAME_ADDRESS` and
# `ENTRY_NAT`, which are ASLR-DEPENDENT and differ between two runs of the SAME binary --
# MEASURED, an earlier version reported "run1 != run2" over nothing but addresses while the
# four lanes under test were already identical. The lanes are the claim.
lanes() {
  local out i
  for i in 0 1 2 3; do
    out=$(awk -v i="$i" '$1=="BEND_LANE" && $2==i {print $3}' "$1")
    [[ -n $out ]] || { print -r -- "  !! harness: BEND_LANE $i is ABSENT from $1"; return 1; }
    print -r -- "$out"
  done | tr '\n' ' ' | sed 's/ $//'
}

# ---------------------------------------------------------------- the kernel text
$BEND "$R/emit-real.bend" 2>/dev/null > "$W/live.txt" || { print -r -- "step0 bend FAILED"; exit 1; }
python3 "$L/unlive.py" "$W/live.txt" 'live CLANG full' "$W/s3/kernel.c" | sed 's/^/  /'
print -r -- "  kernel text sha256 $(shasum -a 256 "$W/s3/kernel.c" | cut -d' ' -f1)"

# ---------------------------------------------------------------- the shim
{
  print -r -- "// ---- BEGIN the emitted C text of tinybendygrad/renderer/cstyle.bend, verbatim ----"
  cat "$W/s3/kernel.c"
  print -r -- "// ---- END the emitted C text ----"
  cat "$L/stage3-shim.c"
} > "$R/shim3.c"

# THE ASSERTION, and it is why the text is inserted rather than retyped: a hand-typed kernel
# would make every row below a claim about a kernel nobody rendered.
sed -n '/BEGIN the emitted C text/,/END the emitted C text/p' "$R/shim3.c" \
  | sed '1d;$d' > "$W/s3/embedded.c"
if cmp -s "$W/s3/kernel.c" "$W/s3/embedded.c"; then
  print -r -- "  shim3.c carries the port's text verbatim (cmp empty)"
else
  print -r -- "  !! shim3.c's embedded kernel text DIFFERS from the port's output"; exit 1
fi

# ---------------------------------------------------------------- the numbers
# COMPUTED, never typed: the inputs are float32 byte strings and every expectation comes
# from `cstyle-numbers.py`, i.e. from tinygrad's CPU backend running the same program.
to_nats() { python3 -c "
import sys
b = bytes.fromhex(sys.argv[1])
print(' '.join(str(int.from_bytes(b[i:i+4], 'little')) for i in range(0, len(b), 4)))" "$1"; }
IN_HEX=0000803fcdcccc3d000020c000007040          # [1.0, 0.1, -2.5, 3.75], from CPython
BAD_HEX=0000803f0000803f000020c000007040        # lane 1 changed to 1.0f
set -- $(to_nats $IN_HEX); IN0=$1; IN1=$2; IN2=$3; IN3=$4
WANT_HEX=$(cd "$REPO" && python3 "$L/cstyle-numbers.py" --in $IN_HEX)
BADWANT_HEX=$(cd "$REPO" && python3 "$L/cstyle-numbers.py" --in $BAD_HEX)
set -- $(to_nats "$WANT_HEX"); W0=$1; W1=$2; W2=$3; W3=$4
set -- $(to_nats "$BADWANT_HEX"); X0=$1; X1=$2; X2=$3; X3=$4
print -r -- "  input  bit patterns (Nat): $IN0 $IN1 $IN2 $IN3"
print -r -- "  expect bit patterns (Nat): $W0 $W1 $W2 $W3   [tinygrad CPU backend, hex $WANT_HEX]"
print -r -- "  control input            : $BAD_HEX  expect $X0 $X1 $X2 $X3"

sed -e "s/@IN0@/$IN0/" -e "s/@IN1@/$IN1/" -e "s/@IN2@/$IN2/" -e "s/@IN3@/$IN3/" \
    "$L/stage3.bend.tmpl" > "$R/stage3.bend"
# ⚠ THE CONTROL SUBSTITUTES LANE 1's VALUE, and it must still fill EVERY placeholder: a
# one-line `sed s/@IN1@/.../` leaves `@IN0@`, `@IN2@` and `@IN3@` in the file, and the guard
# below is what catches it -- MEASURED, that is exactly what the first version did. The
# guard is not decoration: an unsubstituted `@IN0@` is a PARSE error at step 1, and a
# silently different program if it ever were not.
sed -e "s/@IN0@/$IN0/" -e "s/@IN1@/$IN0/" -e "s/@IN2@/$IN2/" -e "s/@IN3@/$IN3/" \
    "$L/stage3.bend.tmpl" > "$R/stage3_bad.bend"
grep -q '@IN' "$R/stage3.bend" && { print -r -- "  !! unsubstituted placeholder left in stage3.bend"; exit 1; }
grep -q '@IN' "$R/stage3_bad.bend" && { print -r -- "  !! unsubstituted placeholder left in stage3_bad.bend"; exit 1; }

# ---------------------------------------------------------------- the four steps
cd "$R" || exit 1
print -r -- ""
print -r -- "=== step1: bend stage3.bend -o stage3.c  (INLINES shim3.c) ==="
"$BEND" stage3.bend -o "$W/s3/stage3.c" 2>"$W/s3/bend.err"
if [[ ! -s $W/s3/stage3.c ]]; then
  print -r -- "  step1 bend -o FAILED:"; head -14 "$W/s3/bend.err" | sed 's/^/    /'; exit 1
fi
print -r -- "  step1 ok, $(wc -c < $W/s3/stage3.c | tr -d ' ') bytes emitted; the port's text is inside it $(grep -c 'BEGIN the emitted C text' "$W/s3/stage3.c") time(s)"

print -r -- ""
print -r -- "=== step2+3: cc stage3.c -o stage3.out ==="
cc "$W/s3/stage3.c" -o "$W/s3/stage3.out" 2>"$W/s3/cc.err"
if [[ $? -ne 0 ]]; then
  print -r -- "  step2 COMPILE/LINK FAILED:"; head -8 "$W/s3/cc.err" | sed 's/^/    /'; exit 1
fi
print -r -- "  step2 compiled ok; step3 linked ok"

print -r -- ""
print -r -- "=== step4: run it, twice, two processes ==="
for run in 1 2; do
  "$W/s3/stage3.out" > "$W/s3/out$run.txt" 2> "$W/s3/err$run.txt" \
    || { print -r -- "  step4 RUN FAILED rc=$?"; head -5 "$W/s3/err$run.txt" | sed 's/^/    /'; exit 1; }
  print -r -- "  --- run$run, Bend's own stdout ---"; sed 's/^/    /' "$W/s3/out$run.txt"
  print -r -- "  --- run$run, the C side own stderr ---"; sed 's/^/    /' "$W/s3/err$run.txt"
done
l1=$(lanes "$W/s3/out1.txt") || pass=0
l2=$(lanes "$W/s3/out2.txt") || pass=0
if [[ -n $l1 && $l1 == "$l2" ]]; then
  print -r -- "  the four lanes are identical across two processes"
else
  print -r -- "  !! the lanes differ between the two runs"; pass=0
fi

print -r -- ""
print -r -- "=== THE VERDICT: BEND's OWN numbers vs CPYTHON's ==="
print -r -- "  bend    bit patterns: $l1"
print -r -- "  cpython bit patterns: $W0 $W1 $W2 $W3"
if [[ -n $l1 && $l1 == "$W0 $W1 $W2 $W3" ]]; then
  print -r -- "  MATCH -- all four lanes, bit for bit"
else
  print -r -- "  MISMATCH"; pass=0
fi

print -r -- ""
print -r -- "=== NEGATIVE CONTROL: lane 1's input changed, and the EXPECTED ANSWER CHANGES TOO ==="
print -r -- "  a control that only checked 'the output moved' would pass on a kernel that moved"
print -r -- "  it for the WRONG reason, so the perturbed run is compared against CPython's"
print -r -- "  perturbed answer rather than merely against the original one."
"$BEND" stage3_bad.bend -o "$W/s3/bad.c" 2>"$W/s3/bad.bend.err"
if [[ ! -s $W/s3/bad.c ]]; then
  print -r -- "  step1 for the control FAILED:"; head -8 "$W/s3/bad.bend.err" | sed 's/^/    /'; exit 1
fi
cc "$W/s3/bad.c" -o "$W/s3/bad.out" 2>"$W/s3/bad.cc.err"
if [[ $? -ne 0 ]]; then
  print -r -- "  step2 for the control FAILED:"; head -5 "$W/s3/bad.cc.err" | sed 's/^/    /'; exit 1
fi
"$W/s3/bad.out" > "$W/s3/bad.txt" 2>/dev/null
bad=$(lanes "$W/s3/bad.txt") || pass=0
print -r -- "  bend, perturbed input : $bad"
print -r -- "  cpython, same input   : $X0 $X1 $X2 $X3"
if [[ -n $bad && $bad == "$X0 $X1 $X2 $X3" ]]; then
  print -r -- "  control PASSED: the perturbed run equals CPython's perturbed answer, so the"
  print -r -- "  MATCH above is a computation and not a coincidence."
elif [[ -n $bad && $bad != "$W0 $W1 $W2 $W3" ]]; then
  print -r -- "  control PARTIAL: the output moved but not to CPython's perturbed answer."
  print -r -- "  got $bad, CPython says $X0 $X1 $X2 $X3"; pass=0
else
  print -r -- "  !! CONTROL FAILED: the perturbed run produced the ORIGINAL answer, so the"
  print -r -- "     MATCH above proves NOTHING."; pass=0
fi
print -r -- ""
print -r -- "STAGE 3: $([[ $pass -eq 1 ]] && print PASS || print FAIL)"