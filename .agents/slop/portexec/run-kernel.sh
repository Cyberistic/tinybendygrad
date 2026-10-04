#!/bin/zsh
# .agents/slop/portexec/run-kernel.sh -- CALL A KERNEL THE PORT EMITTED, FROM BEND.
#
#   zsh .agents/slop/portexec/run-kernel.sh [mode] [workdir]    mode: stage2 (default) | mm
#
# THE FOUR STEPS ARE REPORTED SEPARATELY, because "it did not work" is not a
# report:
#   STEP 1  bend -o     run-kernel.bend -> run.c   (the shim is INLINED; never
#                                                   concatenate it by hand)
#   STEP 2  cc          the PORT's kernel.c alone, -Wall -Werror
#   STEP 3  cc          bend's run.c alone  (-Wall only: bend's OWN generated
#                       runtime emits uninitialised-register warnings that are
#                       not the port's and not this harness's)
#   STEP 4  LINK        run.o + kernel.o
#   STEP 5  RUN         twice, and the two outputs must be cmp-identical
#   STEP 6  COMPARE     every WORD against CPython's, byte for byte
#   STEP 7  CONTROLS    three plants, each of which MUST turn the lane red
#
# NOTHING IN THE LIVE PORT TREE IS EDITED. The kernel text is read out of the
# port's own stdout; every artefact lands in $WORK.
set -u
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
PY="$ROOT/.venv/bin/python"
# `$1` IS THE MODE AND `$2` IS THE WORK DIR. They are positional, so the two must
# not be swapped -- `run-kernel.sh mm /some/dir` is right and
# `run-kernel.sh /some/dir` sets MODE to a path and exits 127 with no useful
# message, which is what happened the first time the work dir was made
# configurable.
MODE=${1:-stage2}
case "$MODE" in stage2|mm) ;; *) print -r -- "unknown mode '$MODE' (want stage2 | mm)"; exit 2 ;; esac
WORK=${2:-${WORK:-$TMPDIR/portexec}}
mkdir -p "$WORK"; cd "$ROOT" || exit 1
fail() { print -r -- "FAIL[$MODE] $1"; exit 1; }

# THE ROW NAME AND THE WORD KEY ARE THE MODE'S. `kern2 MM` is a PLACEHOLDER: the
# matmul's kernel is not one of the 227 gate rows, it comes from emit-mm.bend,
# and gen_ffi.py ignores the row argument in `mm` mode.
if [ "$MODE" = mm ]; then ROW="kern2 MM        "; WK=mm_A; WANT=mm_expect_words; NW=64
else                            ROW="kern2 CLANG      "; WK=stage1_in_words; WANT=stage1_expect_words; NW=4; fi

# ---------------------------------------------------------------- ORACLE
print -r -- "== ORACLE  CPython: render_kernel + numpy + a real DEV=CPU run"
"$PY" .agents/slop/portexec/oracle.py "$WORK" > "$WORK/oracle.log" 2>&1 \
  || fail "oracle.py: $(tail -2 "$WORK/oracle.log" | tr '\n' ' ')"

# ---------------------------------------------------------------- PORT
print -r -- "\n== PORT  ./bin/bend cstyle.bend"
# THE PORT'S RUN IS RETRIED AND THE ROW COUNT IS CHECKED, NOT THE EXIT STATUS,
# for the reason e2e.sh names: bend stack-overflows on roughly one run in twenty
# and prints NOTHING, and an empty capture is indistinguishable from "not
# started". 12 attempts rather than 8, because MEASURED on 2026-10-04: this loop
# burned all 8 and reported `port produced 0 rows in 8 attempts` while the cause
# was a CONCURRENT AGENT's edit to `tinybendygrad/helpers.bend:2551`
# (`i64_dec.go`/`i64_dec.step`, mutual recursion that Bend refuses) -- which the
# port's own imports drag in. That is NOT this lane's verdict and NOT this
# lane's file; the failure is reported as SUBSTRATE so it cannot be read as one.
i=0; rows=0
while [ $i -lt 12 ]; do
  i=$((i+1))
  ./bin/bend tinybendygrad/renderer/cstyle.bend > "$WORK/port-rows.txt" 2> "$WORK/port-rows.err"
  rows=$(grep -c '\]   py=\[' "$WORK/port-rows.txt"); [ "$rows" -ge 220 ] && break
  print -r -- "   attempt $i gave $rows rows, retrying" >&2; sleep 2
done
[ "$rows" -ge 220 ] || { print -r -- "   --- the port's own stderr, so the wall is NAMED ---" >&2
  head -c 400 "$WORK/port-rows.err" >&2; print -r -- "" >&2
  fail "SUBSTRATE: the port produced $rows rows in 12 attempts. The port's imports reach helpers.bend; if its stderr names a def that is NOT in renderer/cstyle.bend, another agent is mid-edit and this is NOT a verdict on this lane."; }
print -r -- "   $rows rows"

# The mm kernel is EMITTED BY THE PORT TOO: gen_ffi.py asks the port for it via
# emit-mm.bend, which calls cstyle.bend's own `render_kernel`. Stage 2's kernel
# is one of the port's own 227 gate rows.
if [ "$MODE" = mm ]; then
  print -r -- "   emitting the 4-buffer kernel through cstyle.bend's render_kernel"
  ./bin/bend .agents/slop/portexec/emit-mm.bend > "$WORK/mm-rows.txt" 2> "$WORK/mm-rows.err" \
    || { head -6 "$WORK/mm-rows.err"; fail "emit-mm.bend did not run"; }
  grep -q 'KERNEL_BEGIN' "$WORK/mm-rows.txt" || { head -4 "$WORK/mm-rows.txt"; fail "emit-mm.bend printed no KERNEL_BEGIN marker"; }
fi

print -r -- "\n== GEN  shim + kernel object + the Bend program"
"$PY" .agents/slop/portexec/gen_ffi.py "$WORK" "$ROW" "$MODE" > "$WORK/gen.log" 2>&1 \
  || fail "gen_ffi.py: $(tail -3 "$WORK/gen.log" | tr '\n' ' ')"
sed 's/^/   /' "$WORK/gen.log"

# ---------------------------------------------------------------- STEP 1
print -r -- "\n== STEP 1  bend -o"
./bin/bend "$WORK/run-kernel.bend" -o "$WORK/run.c" > "$WORK/bendo.log" 2>&1 \
  || { head -c 500 "$WORK/bendo.log"; fail "STEP1 bend -o"; }
[ -f "$WORK/run.c" ] || fail "STEP1 bend -o produced no run.c"
grep -q "klaunch_run" "$WORK/run.c" || fail "STEP1 bend -o did NOT inline shim.c -- the law wiring is missing"
print -r -- "   ok, $(wc -c < "$WORK/run.c" | tr -d ' ') bytes; shim inlined at line $(grep -n klaunch_run "$WORK/run.c" | head -1 | cut -d: -f1)"

# ---------------------------------------------------------------- STEP 2
print -r -- "\n== STEP 2  cc the PORT's kernel alone (-Wall -Werror)"
cc -Wall -Werror -c "$WORK/kernel.c" -o "$WORK/kernel.o" 2> "$WORK/cc-kernel.log" \
  || { sed 's/^/   /' "$WORK/cc-kernel.log"; fail "STEP2 cc on the port's kernel"; }
print -r -- "   ok, $(wc -c < "$WORK/kernel.o" | tr -d ' ') bytes, zero warnings"

# ---------------------------------------------------------------- STEP 3
print -r -- "\n== STEP 3  cc bend's run.c (-Wall only; bend's own runtime warns)"
cc -c "$WORK/run.c" -o "$WORK/run.o" 2> "$WORK/cc-run.log" || { sed 's/^/   /' "$WORK/cc-run.log"; fail "STEP3 cc on run.c"; }
print -r -- "   ok, $(wc -c < "$WORK/run.o" | tr -d ' ') bytes"

# ---------------------------------------------------------------- STEP 4
print -r -- "\n== STEP 4  LINK run.o + kernel.o"
cc "$WORK/run.o" "$WORK/kernel.o" -o "$WORK/run.bin" 2> "$WORK/link.log" \
  || { sed 's/^/   /' "$WORK/link.log"; fail "STEP4 LINK"; }
print -r -- "   ok"

# ---------------------------------------------------------------- STEP 5
# THE TWO RUNS ARE COMPARED ON THE WORD AND DONE LINES ONLY, and the reason is
# MEASURED rather than guessed: the `_NAT` lines carry ASLR-dependent addresses and
# differ on every run by construction (ffi-experiment E8 records exactly this --
# "the address is ASLR-dependent and changed every run", so the invariant is C and
# Bend agreeing on the SAME PROCESS's address, never either against a constant).
# Comparing whole stdout would call a correct lane non-deterministic.
print -r -- "\n== STEP 5  RUN (twice; the WORD lines must be cmp-identical)"
"$WORK/run.bin" > "$WORK/run1.txt" 2>&1; rc=$?
[ $rc -eq 0 ] || { sed 's/^/   /' "$WORK/run1.txt"; fail "STEP5 RUN rc=$rc"; }
"$WORK/run.bin" > "$WORK/run2.txt" 2>&1
grep -E '^(WORD|DONE)' "$WORK/run1.txt" > "$WORK/w1.txt"; grep -E '^(WORD|DONE)' "$WORK/run2.txt" > "$WORK/w2.txt"
cmp -s "$WORK/w1.txt" "$WORK/w2.txt" || { diff "$WORK/w1.txt" "$WORK/w2.txt" | head -8; fail "STEP5 RUN is not deterministic"; }
grep -E '_NAT ' "$WORK/run1.txt" | sed 's/^/   /'
grep -E '_NAT ' "$WORK/run2.txt" | sed 's/^/   (ASLR moved them) /'
# THE TWO BUFFERS MUST BE DISTINCT ADDRESSES, or the kernel is self-aliased and
# the lane is green for the wrong reason. This is the check whose absence let the
# first version of this script pass with both buffer pointers equal.
distinct=$("$PY" -c "
import sys
n=[int(l.split()[1]) for l in open(sys.argv[1]) if '_NAT ' in l and not l.startswith('WORD')]
b=[x for x in n if x != n[0]]
print('yes' if len(set(b))==len(b) and b else 'NO')" "$WORK/run1.txt")
[ "$distinct" = yes ] || fail "STEP5 the kernel's buffer arguments are NOT distinct -- the call is self-aliased"
print -r -- "   $NW WORD lines, identical across two runs, and the buffer Nats are DISTINCT"

# ---------------------------------------------------------------- STEP 6
print -r -- "\n== STEP 6  COMPARE against CPython, byte for byte"
"$PY" - "$WORK" "$WANT" "$NW" "$MODE" <<'EOF'
import json, pathlib, sys
w, key, n = pathlib.Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
o = json.loads((w / "oracle.json").read_text())
got = [int(l.split()[2]) for l in (w / "run1.txt").read_text().splitlines() if l.startswith("WORD ")]
want = o[key]
naddr = [int(l.split()[1]) for l in (w / "run1.txt").read_text().splitlines() if "_NAT " in l]
naddr2 = [int(l.split()[1]) for l in (w / "run2.txt").read_text().splitlines() if "_NAT " in l]
print(f"   port   : {len(got)} words, first 8 {got[:8]}")
print(f"   CPython: {len(want)} words, first 8 {want[:8]}")
assert len(got) == n, f"expected {n} WORD lines, got {len(got)}"
# THE POINTER CLAIM, and it is the Stage 2 measurement: every Nat Bend printed is
# under 2^51 (the MEASURED Nat ceiling) and the two runs' addresses DIFFER, which
# is what ASLR looks like and is why no address is ever compared to a constant.
print(f"   Nat run1: {naddr}  all < 2^51: {all(a < 2**51 for a in naddr)}")
print(f"   Nat run2: {naddr2}  all < 2^51: {all(a < 2**51 for a in naddr2)}  (ASLR moved them: {naddr != naddr2})")
if got != want:
  bad = [(i, g, x) for i, (g, x) in enumerate(zip(got, want)) if g != x]
  print(f"   MISMATCH at {len(bad)}/{len(want)} words, first 5: {bad[:5]}")
  print("FAIL [compare] the port's kernel ran and produced different words")
  sys.exit(1)
print(f"   equal  : True   diff bytes: 0   ({len(got)}/{len(want)} words)")
print(f"PASS [{sys.argv[3]}] {len(got)} u32 words bit-identical to CPython, through the port's own runtime")
EOF
rc=$?
[ $rc -eq 0 ] || exit $rc

# ---------------------------------------------------------------- STEP 7
# THE LANE MUST BE ABLE TO FAIL. Three controls in this project were found unable
# to fail and one left six lanes green.
#
# TWO SHAPES OF PLANT, AND THE DISTINCTION IS NOT COSMETIC. `bend -o` INLINES the
# shim into run.c, so a plant applied to `shim.c` AFTER step 1 changes a file that
# nothing reads any more. An earlier version did exactly that and the control was
# VACUOUS -- the sed matched nothing, so it reported that rather than silently
# passing, which is the only reason it was noticed. So a shim plant RE-RUNS step 1.
ctl() {  # name, file, sed-expr, re-bend?
  local nm=$1 file=$2 expr=$3 rebend=$4
  cp "$WORK/$file" "$WORK/ctl.bak"
  sed "$expr" "$WORK/ctl.bak" > "$WORK/$file"
  if cmp -s "$WORK/ctl.bak" "$WORK/$file"; then
    print -r -- "   VACUOUS [$nm] the sed matched nothing in $file"; cp "$WORK/ctl.bak" "$WORK/$file"; return 1
  fi
  if [ "$rebend" = rebend ]; then
    ./bin/bend "$WORK/run-kernel.bend" -o "$WORK/run.c" >/dev/null 2>&1 || {
      print -r -- "   RED-VIA-BEND [$nm]"; cp "$WORK/ctl.bak" "$WORK/$file"; return 0; }
  fi
  cc -c "$WORK/run.c" -o "$WORK/ck-run.o" 2>/dev/null && cc -Wall -Werror -c "$WORK/kernel.c" -o "$WORK/ck-k.o" 2>/dev/null \
    && cc "$WORK/ck-run.o" "$WORK/ck-k.o" -o "$WORK/ctl.bin" 2>/dev/null && "$WORK/ctl.bin" > "$WORK/ctl.txt" 2>&1
  cp "$WORK/ctl.bak" "$WORK/$file"; rm -f "$WORK/ctl.bak"
  [ "$rebend" = rebend ] && ./bin/bend "$WORK/run-kernel.bend" -o "$WORK/run.c" >/dev/null 2>&1
  "$PY" - "$WORK" "$WANT" <<'EOF'
import json, pathlib, sys
w, key = pathlib.Path(sys.argv[1]), sys.argv[2]
try:
  o = json.loads((w / "oracle.json").read_text())
  got = [int(l.split()[2]) for l in (w / "ctl.txt").read_text().splitlines() if l.startswith("WORD ")]
except Exception: sys.exit(0)
sys.exit(0 if got != o[key] else 1)
EOF
  if [ $? -eq 0 ]; then print -r -- "   RED [$nm]"; return 0
  else print -r -- "   GREEN [$nm] *** THE LANE DID NOT NOTICE ***"; return 1; fi
}
rc=0
# THE PLANTS ARE MODE-SPECIFIC, because a plant whose text is not in the file is a
# VACUOUS control and the VACUOUS branch above is there to say so out loud. The
# first mm run reported two of them: `+1.0f` is not in a matmul body.
if [ "$MODE" = mm ]; then
  ctl "kernel: the first dot's 8 taps become 7" kernel.c \
      's/for (int k = 0; k < 8; k++) { s += data1_4/for (int k = 0; k < 7; k++) { s += data1_4/' same || rc=1
  ctl "bend program: fill B into A's buffer (re-runs bend -o)" run-kernel.bend \
      's/fill.go(in_B(), B_hi, B_lo, 0)/fill.go(in_B(), A_hi, A_lo, 0)/' rebend || rc=1
else
  ctl "kernel: +1.0f -> +2.0f (the PORT's own body text)" kernel.c \
      's/val0\[0\]+1\.0f/val0[0]+2.0f/' same || rc=1
  ctl "bend program: fill the OUTPUT buffer, not the input (re-runs bend -o)" run-kernel.bend \
      's/fill.go(in_src(), src_hi, src_lo, 0)/fill.go(in_src(), dst_hi, dst_lo, 0)/' rebend || rc=1
fi
# SKIP THE CALL. Two aliasing plants were tried first and BOTH ARE THEOREMS for
# `kern2 CLANG`, measured rather than assumed: that kernel reads only `data1_4`,
# writes only `data0_4`, and its answer is a function of ONE buffer, so making the
# two buffer slots equal -- in either direction -- cannot change it, and BOTH
# aliased runs printed exactly the correct four words. A control that cannot fail
# is reported as a theorem, not quietly counted towards the three. The matmul has
# no such theorem: it reads THREE buffers, so the same aliasing plant DOES turn it
# red, and that is the plant used for `mm`.
ctl "shim: never call the kernel (re-runs bend -o)" shim.c \
    's/^  ((port_kern_t)(uintptr_t)f\[0\])/  if (0) ((port_kern_t)(uintptr_t)f[0])/' rebend || rc=1
[ $rc -eq 0 ] && print -r -- "\nPASS [controls] every plant turned the lane red" \
               || print -r -- "\nFAIL [controls] a plant left the lane GREEN"
exit $rc
