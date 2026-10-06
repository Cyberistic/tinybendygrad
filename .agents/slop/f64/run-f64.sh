#!/bin/zsh
# .agents/slop/f64/run-f64.sh -- AN f64 KERNEL THROUGH THE PORT, END TO END.
#
#   zsh .agents/slop/f64/run-f64.sh
#
# THE CLAIM, and it is the portexec claim one dtype wider.  `portexec/run-kernel.sh`
# already proves that a KERNEL THE PORT EMITTED is live C: `render_kernel` writes it,
# `cc` compiles it, BEND allocates the buffers, fills them, LAUNCHES THE KERNEL BY
# POINTER and reads the words back, and all 64 of them match CPython.  That was done
# on `float`.  This runs the identical harness on `double`.
#
# IT IS THE SAME HARNESS, NOT A SECOND ONE.  `portexec/` is committed and is NEVER
# WRITTEN TO.  This script builds a COPY -- `tinybendygrad` copied, `bin/`
# `references/` `tinygrad/` `.venv/` symlinked, exactly as `e2e_port/run-port-mm.sh`
# `mkcopy` does at :147 -- makes TWO edits inside the copy, and calls the committed
# `run-kernel.sh mm` UNCHANGED.  Both edits are applied with `e2e_port/plant.py`,
# which REFUSES a target text that is not present exactly once, because a control
# that matched nothing is the defect it exists to catch.
#
#   E1  `portexec/gen_ffi.py`, TWO sites.  Needed because `run-kernel.sh` runs
#       `oracle.py` (step ORACLE) BEFORE it emits the f64 kernel (step PORT/mm), so
#       the expectation cannot exist when `oracle.py` runs; and because `gen_ffi.py`
#       casts every buffer argument to `(float*)` at :188, which for an f64 kernel
#       makes the CALL pass `float*` where the port's own signature says `double*`.
#       MEASURED, and it was not caught by the harness: `cc -c run.c` at step 3 runs
#       WITHOUT `-Werror` ("bend's own runtime warns"), so four
#       `-Wincompatible-pointer-types` warnings passed and the pointer values were
#       still right, so the lane went red on the ANSWER instead.  The fix is to
#       derive the cast from the PARSED signature, which is what the prototype and
#       the function-pointer typedef already do -- three of the four sites in this
#       file are dtype-aware and one was not.
#       E1a merges in the keys `f64/oracle_f64.py build()` computes.
#       E1b makes the call cast to the parsed parameter type.
#   E2  `portexec/run-kernel.sh`: re-derive `ROOT` from `$0`.  MEASURED, and
#       `e2e_port/run-port-mm.sh:145` says why: the line hard-codes `ROOT=` to the
#       live tree, so without this every plant below would be planted in a file
#       nothing reads.
#
# THE f64 FIXTURE IS `f64/emit-f64.bend`, WHICH IS `portexec/emit-mm.bend` WITH
# `S.double()` INSTEAD OF `S.single()` AND `double` INSTEAD OF `float` IN THE BODY.
# That spelling is load-bearing in three places:
#   * `gen_ffi.py` reads the buffer TYPES by PARSING the port's own signature, so
#     the shim's prototype and function-pointer typedef carry `double*` with no
#     dtype written anywhere in the harness;
#   * `gen_ffi.py`'s `NBYTESn` is `len(words) * 4`, and an f64 element is TWO u32
#     words at the 4-byte stride `fill.go`/`dump.go` already walk, so the WORD
#     COUNT IS 64 for 32 doubles and NO HARNESS CHANGE IS NEEDED for the wider
#     dtype.  This is the whole reason a two-`U32` boundary works at all: no
#     `double` ever crosses the FFI, only its two halves do.
#   * ALL THREE of `run-kernel.sh`'s OWN mm-mode plants apply VERBATIM to the f64
#     kernel text, so they are inherited controls rather than re-typed ones.
#
# THE ANSWER CANNOT BE RIGHT BY ACCIDENT:
#   * every operand is a small INTEGER except `D[0][0] = 0.5`, so the matmul is
#     exact and the ONLY rounding anywhere is the single `+ DELTA` -- no summation
#     order, no FMA contraction, no association can move it;
#   * all 32 answers are DISTINCT, so a lane that cannot tell one element from
#     another cannot pass;
#   * `out[0] = 1.0 + 2**-40 = 0x3FF0000000001000`, a value `f32` CANNOT HOLD, and
#     the P1/P1b pair moves exactly that word.
#
# EXIT: 0 iff the lane passed AND every control went red AND the C-text diff is 0.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PY="$ROOT/.venv/bin/python"
F64="$ROOT/.agents/slop/f64"
PLANT="$ROOT/.agents/slop/e2e_port/plant.py"
W=${1:-${TMPDIR}opencode/f64-lane}
NC="$W/copy"
NC2="$W/copy2"
ok=1; rc=0; ctlrc=0; CTLLOG=""; substrate=0

say()  { print -r -- "$@" }
hr()   { say ""; say "--------------------------------------------------------------------------------" }

mkdir -p "$W" || exit 1
hr
say "== 7/7 AN f64 KERNEL THROUGH THE PORT -- double, not float"
say "   harness: .agents/slop/portexec/run-kernel.sh mm, UNCHANGED, on a copy"

# ---- 0. THE SUBSTRATE, CHECKED THE WAY THAT HAS ACTUALLY BEEN FOOLED ----------
# `--check-only` REPORTS `ALL PROOFS CHECK` FOR AN EMPTY FILE (measured, and it has
# broken this tree three times), so `substrate-check.sh` checks SIZE first.
.sr() { # .sr <label> <rows-file>
  local n; n=$(grep -c '\]   py=\[' "$2" 2>/dev/null); [ -n "$n" ] || n=0
  if [ "$n" -lt 220 ]; then
    substrate=1
    say "  *** SUBSTRATE, NOT A VERDICT [$1]: the port produced $n rows (220 is the floor)"
    head -c 300 "$2.err" 2>/dev/null | sed 's/^/        /'
  else say "  [$1] $n rows"; fi
}

hr
say "== 0  THE SUBSTRATE, AND A REPAIR THAT IS CHECKED RATHER THAN ASSERTED"
LIVE_SHA=$(shasum -a 256 "$ROOT/tinybendygrad/renderer/cstyle.bend" | cut -d' ' -f1)
say "   live   renderer/cstyle.bend sha256 $LIVE_SHA"
say "   quoted cstyle-live/run-all.log:5  sha256 $(grep -m1 'live    cstyle.bend' "$ROOT/.agents/slop/cstyle-live/run-all.log" | awk '{print $NF}')"
"$ROOT/.agents/slop/substrate-check.sh" "$ROOT/tinybendygrad/renderer/cstyle.bend" > "$W/substrate.txt" 2>&1
say "   substrate-check.sh on the live file: $(head -1 "$W/substrate.txt" | awk '{print $1, $2}')"
if [ "$(head -1 "$W/substrate.txt" | awk '{print $1}')" != WARM ]; then
  say "   >>> NOT MY FILE AND NOT MY VERDICT. It carries nine verbatim copies of every"
  say "   >>> derived-fact reader block (`BArg.name`, `Uses.half`, `Emit_.uses`, `RkIn.pref`"
  say "   >>> all nine times) and `bend` refuses it with `duplicate declaration`. The"
  say "   >>> hash MOVED during this session: the same path was bed462b6.. (cold, 3205"
  say "   >>> lines) and is now the value above. The repair below touches ONLY THE COPY"
  say "   >>> and is proven lossless by a byte-identity check against the committed"
  say "   >>> good run, so no number here is attributed to a tree state of mine."
  say ""
fi

rm -rf "$NC"; mkdir -p "$NC/.agents/slop" || exit 1
cp -R "$ROOT/tinybendygrad" "$NC/tinybendygrad" || exit 1
cp -R "$ROOT/.agents/slop/portexec" "$NC/.agents/slop/portexec" || exit 1
cp -R "$F64" "$NC/.agents/slop/f64" || exit 1
ln -s "$ROOT/bin" "$NC/bin"; ln -s "$ROOT/references" "$NC/references"
ln -s "$ROOT/tinygrad" "$NC/tinygrad"; ln -s "$ROOT/.venv" "$NC/.venv"
say "   copy: tinybendygrad + portexec + f64 copied; bin/ references/ tinygrad/ .venv/ symlinked"

repair_rc=0
"$PY" "$F64/repair-dupes.py" "$ROOT/tinybendygrad/renderer/cstyle.bend" \
      "$NC/tinybendygrad/renderer/cstyle.bend" > "$W/repair.txt" 2>&1 || repair_rc=$?
grep -E 'removed [0-9]+ adjacent|duplicate .def. names|rows=|rows vs committed' "$W/repair.txt" | sed 's/^/   /'
# EXIT 3 IS A REFUSAL, NOT A VERDICT, AND `e2e.sh` TREATS IT AS `SKIP`.  A tree state
# that cannot produce the port's rows has measured NOTHING about f64, and reporting
# that as a pass would be the defect the three-outcome verdict exists to prevent.
if [ $repair_rc -ne 0 ]; then
  say ""
  say "   *** REFUSED, EXIT 3: the port's own rows could not be reproduced, so NO number"
  say "   *** below would be a verdict about f64.  $W/repair.txt has the reason."
  exit 3
fi

# THE FIXTURE. Copied over `portexec/emit-mm.bend` -- the ONE name `run-kernel.sh`
# knows -- so the committed harness runs its own mm path and nothing is patched in it.
cp "$F64/emit-f64.bend" "$NC/.agents/slop/portexec/emit-mm.bend" || exit 1

ed1a_old='    orc = json.loads((out / "oracle.json").read_text())'
ed1a_new='    orc = json.loads((out / "oracle.json").read_text())  # F64: merge in the f64 keys
    import sys as _s; _s.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "f64"))
    import oracle_f64
    orc.update(oracle_f64.build(out / "mm-rows.txt"))
    (out / "oracle.json").write_text(__import__("json").dumps(orc, indent=1))'
ed1b_old='    spread = ", ".join("(float*)((((uint64_t)f[%d] << 32) | f[%d]))" % (1 + 2 * k, 2 + 2 * k)
                       for k in range(len(args)))'
ed1b_new='    spread = ", ".join("(%s)((((uint64_t)f[%d] << 32) | f[%d]))" % (a.replace("restrict", "").strip(), 1 + 2 * k, 2 + 2 * k)
                       for k, (a, _) in enumerate(args))  # F64: cast to the PARSED type'
ed2_old='ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad'
ed2_new='ROOT=$(cd "$(dirname "$0")/../../.." && pwd)'
ed() { "$PY" "$PLANT" "$1" "$2" "$3" >/dev/null || { say "   *** EDIT $4 DID NOT APPLY -- NOT A VERDICT"; ok=0; rc=1; }; }
ed "$NC/.agents/slop/portexec/gen_ffi.py" "$ed1a_old" "$ed1a_new" E1a
ed "$NC/.agents/slop/portexec/gen_ffi.py" "$ed1b_old" "$ed1b_new" E1b
ed "$NC/.agents/slop/portexec/run-kernel.sh" "$ed2_old" "$ed2_new" E2

# ---- E3: ONE INHERITED PLANT IS A THEOREM FOR THIS FIXTURE, AND IS SAID SO ----
# `run-kernel.sh`'s own header says what to do about a control that cannot fail:
# "A control that cannot fail is reported as a theorem, not quietly counted towards
# the three" (`run-kernel.sh:215-222`, where it skips two stage-2 aliasing plants for
# exactly this reason).  The k<8 plant is one.  MEASURED: it went GREEN in this run.
# The reason is a property of the FIXTURE, not of the harness: `oracle_f64.py` builds
# B as `[I_4 ; 0]`, so `B[k][j]` is 0 for every k >= 4 and `A[i][k] * B[k][j]` is
# therefore 0 for every k >= 4 WHATEVER `A[i][k]` is.  Dropping the 8th tap cannot
# move the answer, and no choice of A can change that while B keeps its zero lower
# half -- which is the price of making `A@B` exactly `diag(2,1,1,1)`, so that
# `out[0] = 1.0 + 2**-40` is EXACT rather than the root of a rounded solve.
# So it is REPLACED BY A THEOREM LINE, in the copy, visible in the log.  It is not
# deleted silently and it is not counted as one of the controls.
ed3_old='  ctl "kernel: the first dot'"'"'s 8 taps become 7" kernel.c \
      '"'"'s/for (int k = 0; k < 8; k++) { s += data1_4/for (int k = 0; k < 7; k++) { s += data1_4/'"'"' same || rc=1'
ed3_new='  print -r -- "   THEOREM [kernel: the first dot'"'"'s 8 taps become 7] -- B is [I_4; 0] so A[i][k]*B[k][j] = 0 for EVERY k >= 4 and for ANY A; dropping the 8th tap cannot move the answer. A THEOREM, not a control."  # F64'
ed "$NC/.agents/slop/portexec/run-kernel.sh" "$ed3_old" "$ed3_new" E3

hr
say "== 1  THE LANE  --  portexec/run-kernel.sh mm, seven named steps"
rm -rf "$W/a"; mkdir -p "$W/a"
zsh "$NC/.agents/slop/portexec/run-kernel.sh" mm "$W/a" > "$W/a.log" 2>&1
lanerc=$?
grep -E 'PORT PROTOTYPE|SHIM CALL|INPUT WORDS|MISMATCH at|diff bytes|^PASS \[|^FAIL \[|RED \[|GREEN \[|VACUOUS \[|KERNEL BYTES|DISTINCT' "$W/a.log" | sed 's/^/   /'
.sr "lane A" "$W/a/port-rows.txt"
if [ "$substrate" -eq 1 ]; then
  say "   *** REFUSED, EXIT 3: the lane could not be verified because the substrate moved."
  say "   *** NO verdict about f64 is being offered here."
  exit 3
fi
[ $lanerc -ne 0 ] && { say "   *** LANE FAILED (exit $lanerc)"; grep -E '^(FAIL|SOME PROOFS|Error)' "$W/a.log" | head -4 | sed 's/^/        /'; rc=1; }
# THE CAST MUST HAVE BEEN FIXED.  If it was not, `cc` warned four times and the
# pointer values still happened to be right, which is the WORST shape: a lane that
# goes red on the answer instead of on the mismatch it has.  So the warning count is
# a row, read out of the lane's own compiler log.
ptrwarn=$(grep -c 'Wincompatible-pointer-types' "$W/a/cc-run.log" 2>/dev/null); [ -n "$ptrwarn" ] || ptrwarn=0
say "   -Wincompatible-pointer-types in run.c: $ptrwarn  (0 required)"

# ---- 2. THE PORT'S OWN C TEXT vs CPython'S, WITH AN EXTERNAL diff -------------
hr
say "== 2  THE PORT'S C TEXT AGAINST CPython'S OWN render_kernel, diffed EXTERNALLY"
say "   not read out of the lane: a number taken from the thing that produced it is"
say "   not a second witness, and e2e_port/run-port-mm.sh:118-131 says so."
diff "$W/a/port-kernel.c" "$W/a/cpython-kernel.c" > "$W/kernel.diff"
kdb=$(wc -c < "$W/kernel.diff" | tr -d ' ')
say "   port    $(head -1 "$W/a/port-kernel.c" | cut -c1-88)"
say "   cpython $(head -1 "$W/a/cpython-kernel.c" | cut -c1-88)"
say "   diff bytes = $kdb   ($(diff -q "$W/a/port-kernel.c" "$W/a/cpython-kernel.c" >/dev/null && echo IDENTICAL || echo DIFFER))"
[ "$kdb" -eq 0 ] || { say "   *** THE PORT'S f64 C TEXT IS NOT CPython's -- and the harness built the shim from it anyway"; rc=1; }

# ---- 3. THE 64/64, RECOMPUTED HERE AND NOT QUOTED FROM THE LANE ---------------
hr
say "== 3  THE 64/64 u32 WORDS (32 doubles), RECOMPUTED WITH diff AND NOT QUOTED FROM THE LANE"
awk '{print $3}' <(grep '^WORD ' "$W/a/run1.txt") > "$W/port-words.txt"
"$PY" -c 'import json,sys; print("\n".join(str(w) for w in json.load(open(sys.argv[1]))["mm_expect_words"]))' \
      "$W/a/oracle.json" > "$W/cpython-words.txt"
diff "$W/port-words.txt" "$W/cpython-words.txt" > "$W/words.diff"
say "   ROWS-PRESENT AGAINST ROWS-EXPECTED, every run: a MISSING row and a PASSING row"
say "   look identical from outside, so the count is printed rather than assumed."
say "   rows  port=$(grep -c . "$W/port-words.txt")  expected=$(grep -c . "$W/cpython-words.txt")"
say "   diff bytes = $(wc -c < "$W/words.diff" | tr -d ' ')   differing lines = $(grep -c . "$W/words.diff")"
say "   first 8 port   : $(head -8 "$W/port-words.txt" | tr '\n' ' ')"
say "   first 8 CPython: $(head -8 "$W/cpython-words.txt" | tr '\n' ' ')"
say "   (words are (lo, hi) pairs in MEMORY order: little-endian, and the lane walks"
say "    the buffer at a 4-byte stride, so element i is WORD 2i, WORD 2i+1)"
if [ "$(grep -c . "$W/port-words.txt")" -eq 64 ] && [ "$(wc -c < "$W/words.diff" | tr -d ' ')" -eq 0 ]; then
  say "   *** 64/64 MET, diff 0 bytes"
else say "   *** THE 64/64 BAR IS NOT MET"; rc=1; fi

# ---- 4. THE ONE ROW ONLY f64 CAN SHOW ----------------------------------------
hr
say "== 4  THE VALUE f32 CANNOT HOLD, WITH CPython's TWO ANSWERS SIDE BY SIDE"
if "$PY" - "$W/a/oracle.json" "$W/a/run1.txt" <<'EOF'
import json, pathlib, struct, sys
o = json.loads(pathlib.Path(sys.argv[1]).read_text())
got = [int(l.split()[2]) for l in pathlib.Path(sys.argv[2]).read_text().splitlines() if l.startswith("WORD ")]
val = lambda w: struct.unpack("<d", struct.pack("<Q", (w[1] << 32) | w[0]))[0]
print(f"   DELTA         : 2**-40 = {o['f64_delta']!r}   fixture literal {o['f64_delta_text']}")
print(f"   CPython  f64  : out[0] = (lo=0x{got[0]:08x}, hi=0x{got[1]:08x}) = 0x{(got[1]<<32)|got[0]:016x} = {val(got[:2])!r}")
print(f"   THE PORT      : out[0] = (lo=0x{o['f64_out0_words'][0]:08x}, hi=0x{o['f64_out0_words'][1]:08x})"
      f" = 0x{(o['f64_out0_words'][1]<<32)|o['f64_out0_words'][0]:016x}   agree={got[:2]==o['f64_out0_words']}")
print(f"   CPython  f32  : out[0] = 0x{o['f32_out0_words'][0]:08x} = {o['f32_out0_value']!r}"
      f"   == 1.0 exactly: {o['f32_rounds_to_one']}")
print(f"   SO: the f32 lane's word 0 is 0x{o['f32_out0_words'][0]:08x} and this lane's")
print(f"   is 0x{(got[1]<<32)|got[0]:016x}. Different numbers, same kernel shape, same")
print(f"   harness, same launch -- the WIDTH is real and is not a label.")
assert got[:2] == o["f64_out0_words"], "the port's out[0] is not the expected f64 value"
assert o["f32_rounds_to_one"], "f32 did not round to 1.0"
assert o["f64_out0_words"] != o["f32_out0_words"], "f32 and f64 did not separate"
EOF
then :; else say "   *** THE f32/f64 SEPARATION ROW FAILED ITS OWN ASSERTS"; rc=1; fi

# ---- 5. THE CONTROLS ---------------------------------------------------------
hr
say "== 5  CONTROLS -- a lane that has never failed is not known to work."
say "   C0 is mandatory: without a GREEN unmutated copy, nothing below means anything."
say ""
say "   INHERITED, NOT RE-COUNTED: run-kernel.sh mm runs its OWN three plants inside"
say "   EVERY lane above. Two went RED, VERBATIM on the f64 kernel text, which is why"
say "   emit-f64.bend keeps the mm body's shape. The third is reported as a THEOREM:"
grep -hE '^   (RED|GREEN|VACUOUS|THEOREM) \[' "$W/a.log" | sed 's/^/   /'
say ""
say "-- C0  the copy, UNPLANTED beyond E1/E2, must be green"
rm -rf "$W/c0"; mkdir -p "$W/c0"
zsh "$NC/.agents/slop/portexec/run-kernel.sh" mm "$W/c0" > "$W/c0.log" 2>&1
ctlrc=$?; CTLLOG="$W/c0.log"; substrate=0; .sr "C0" "$W/c0/port-rows.txt"
if [ "$substrate" -eq 1 ]; then say "   *** C0 NOT VERIFIED -- the substrate broke it, so C1..C3 would prove NOTHING"; rc=1
elif [ $ctlrc -eq 0 ] && ! grep -q 'MISMATCH at' "$CTLLOG"; then say "   GREEN [C0 the unmutated copy]"
else say "   *** C0 FAILED -- the copy is not green, so C1..C3 would prove NOTHING"; rc=1; fi

# A CONTROL THAT FALLS OVER IS NOT A CATCH. It must be SEMANTIC: the lane ran and
# either ANSWERED WRONGLY or was REFUSED BY ITS OWN ORACLE.  There are two distinct
# semantic outcomes and both are catches; a third outcome -- a bend `SOME PROOFS
# FAIL`, a `cc` error, a link error, an empty log -- is a fall-over and is not.
#
# WHY THE ORACLE'S OWN REFUSAL COUNTS, and it is not a way of avoiding a real red:
# `oracle_f64.build()` asserts `double* restrict data0_4` is in the port's emitted
# text, and asserts that numpy float64 and real tinygrad DEV=CPU agree on the kernel
# the PORT actually emitted.  Both are computed from the port's own stdout, so when
# a plant breaks the port's dtype or the port's constant, the oracle refuses to
# certify ANY expectation -- which is strictly stronger than reporting 64 wrong
# words, and it happens BEFORE the comparison rather than instead of it.
expect_red() { # expect_red <label> <regex a semantic red must carry>
  local label=$1 must=$2
  if [ "$substrate" -eq 1 ]; then say "   *** NOT A CATCH [$label] -- the substrate broke the lane"; return 1; fi
  if [ $ctlrc -eq 0 ]; then say "   *** GREEN [$label] -- THE LANE DID NOT NOTICE"; return 1; fi
  if grep -qE "$must" "$CTLLOG"; then
    grep -m1 'MISMATCH at' "$CTLLOG" | sed 's/^/        /'
    say "   RED   [$label] -- wrong WORDS, and the diff names which"; return 0
  fi
  # The ORACLE'S OWN REFUSAL.  `run-kernel.sh:81` reports it as
  # `FAIL[mm] gen_ffi.py: <tail of gen.log>`, so the traceback's own module name is
  # cut off and only the ASSERTION MESSAGE survives.  Both of these messages are
  # `oracle_f64.py`'s and neither is anything `bend`, `cc` or the linker can say, so
  # matching the message is matching the refusal and not a coincidence.
  if grep -qE 'AssertionError: (numpy float64 and tinygrad DEV=CPU DISAGREE|the port did not emit a double signature|the \(lo, hi\) split does not round-trip)' "$CTLLOG"; then
    grep -m1 -o 'AssertionError: .*' "$CTLLOG" | sed 's/^/        /' | cut -c1-112
    say "   REFUSED[$label] -- the ORACLE would not certify, so nothing was compared"
    return 0
  fi
  say "   *** FELL OVER [$label] -- it broke instead of answering wrongly or refusing"
  grep -E '^(FAIL|SOME PROOFS FAIL|Error|error:|Traceback)' "$CTLLOG" | head -4 | sed 's/^/        /'
  return 1
}

run_planted() { # run_planted <label> <relfile> <old> <new> <regex>
  local label=$1 file=$2 old=$3 new=$4 must=$5
  rm -rf "$NC2"; cp -R "$NC" "$NC2" || { say "   *** NOT RUN [$label]"; rc=1; return; }
  if ! "$PY" "$PLANT" "$NC2/$file" "$old" "$new" >/dev/null; then
    say "   *** NOT RUN [$label] -- the plant did not apply, so nothing was proven"; rc=1; return; fi
  substrate=0
  rm -rf "$W/p"; mkdir -p "$W/p"
  zsh "$NC2/.agents/slop/portexec/run-kernel.sh" mm "$W/p" > "$W/p.log" 2>&1
  ctlrc=$?; CTLLOG="$W/p.log"; .sr "$label" "$W/p/port-rows.txt"
  expect_red "$label" "$must" || rc=1
}

# ---- P1: THE PLANT.  A DIFFERENT SUM MUST MOVE THE ANSWER. -------------------
say ""
say "-- P1  THE CONSTANT -- 2**-40 becomes 2**-39 in the KERNEL body. A different sum"
say "        must move the answer, and this one moves the answer's LOW word: the only"
say "        word an f32 lane could never have produced. Note WHICH outcome: the oracle"
say "        REFUSES, because it recomputes from the port's own emitted body and finds"
say "        numpy float64 and tinygrad DEV=CPU no longer agreeing with the fixture."
run_planted "P1 the constant 2**-40 -> 2**-39, in the KERNEL" \
  ".agents/slop/portexec/emit-mm.bend" \
  's + 9.094947017729282e-13;' 's + 4.547473508864641e-13;' \
  '^$NOMATCH$'

# ---- P1b: THE PAIRED DISARM.  THE KERNEL IS RIGHT AND THE EXPECTATION IS WRONG.
say ""
say "-- P1b THE PAIRED DISARM -- the same one-binade shift applied to the ORACLE, with"
say "        the KERNEL UNTOUCHED. P1 alone cannot tell a correct lane from one that"
say "        reads its expectation out of its own output, because a self-read passes any"
say "        kernel plant. P1b is the half that catches it: here the kernel is RIGHT and"
say "        the expectation is wrong by one binade, and the outcome is a REFUSAL by the"
say "        oracle's own two-CPython-path cross-check (numpy float64 vs real tinygrad"
say "        DEV=CPU, both recomputed from the port's emitted body) rather than a red word."
# Three sites, because `check_fixture` exists precisely to make a moved constant a
# refusal -- so the disarm has to move the constant AND the guard together, or it
# would be caught by the guard and prove nothing about the comparison.
rm -rf "$NC2"; cp -R "$NC" "$NC2"
p1b_ok=1
"$PY" "$PLANT" "$NC2/.agents/slop/f64/oracle_f64.py" \
  'DELTA = 2.0 ** -40 ' 'DELTA = 2.0 ** -39 ' >/dev/null || p1b_ok=0
"$PY" "$PLANT" "$NC2/.agents/slop/f64/oracle_f64.py" \
  'DELTA_TEXT = "9.094947017729282e-13"' 'DELTA_TEXT = "4.547473508864641e-13"' >/dev/null || p1b_ok=0
# The guard that matters is the repr one; relax it too, or P1b is caught by the
# guard instead of by the comparison and proves nothing about the comparison.
"$PY" "$PLANT" "$NC2/.agents/slop/f64/oracle_f64.py" \
  '  if repr(DELTA) != DELTA_TEXT:' '  if False:' >/dev/null || p1b_ok=0
# And the fixture-literal check must look for the NEW literal, or the guard catches
# the plant before the arithmetic ever runs.
"$PY" "$PLANT" "$NC2/.agents/slop/f64/oracle_f64.py" \
  '  if DELTA_TEXT not in src:' '  if False:' >/dev/null || p1b_ok=0
if [ "$p1b_ok" != 1 ]; then
  say "   *** NOT RUN [P1b] -- a plant did not apply, so nothing was proven"; rc=1
else
  substrate=0
  rm -rf "$W/p1b"; mkdir -p "$W/p1b"
  zsh "$NC2/.agents/slop/portexec/run-kernel.sh" mm "$W/p1b" > "$W/p1b.log" 2>&1
  ctlrc=$?; CTLLOG="$W/p1b.log"; .sr "P1b" "$W/p1b/port-rows.txt"
  expect_red "P1b the ORACLE is one binade out and the kernel is right" \
    'MISMATCH at [1-9]' || rc=1
fi

# ---- P1c: A GENUINE WORD-LEVEL RED, AND THE PREFIX IS NOT A COMPARISON --------
say ""
say "-- P1c ONE BIT OF ONE EXPECTED WORD -- word 37 of the 64, in the ORACLE only. This"
say "        is the control that exercises the WORD COMPARISON itself, because P1 and"
say "        P1b are both caught upstream of it. And it says which word: a PREFIX is not"
say "        a comparison, and 63 agreeing words are not 64."
run_planted "P1c one bit of expected word 37, and only that word" \
  ".agents/slop/f64/oracle_f64.py" \
  '      "mm_expect_words": w,' \
  '      "mm_expect_words": [x ^ (1 if i == 37 else 0) for i, x in enumerate(w)],' \
  'MISMATCH at 1/64 words, first 5: \[\(37,'

# ---- P2: THE PORT'S OWN dtype.  THE DISCRIMINATOR. ---------------------------
say ""
say "-- P2  THE PORT -- S.double() becomes S.single() in the fixture's BArgs, so"
say "        render_dtype emits float*. Everything else is untouched: same harness,"
say "        same oracle, same launch. If this is NOT caught, then the lane was"
say "        checking a WORD COUNT and not the WIDTH, and section 4 is vacuous."
rm -rf "$NC2"; cp -R "$NC" "$NC2"
if ! "$PY" "$PLANT" "$NC2/.agents/slop/portexec/emit-mm.bend" \
      'C.BArg{"data0_4", S.double(),' 'C.BArg{"data0_4", S.single(),' >/dev/null; then
  say "   *** NOT RUN [P2] -- the plant did not apply"; rc=1
else
  mkdir -p "$W/p2r"
  "$NC2/bin/bend" "$NC2/.agents/slop/portexec/emit-mm.bend" > "$W/p2r/mm-rows.txt" 2>/dev/null
  say "   the port now says: $(grep -m1 'void mm' "$W/p2r/mm-rows.txt" | cut -c1-76)"
  substrate=0
  rm -rf "$W/p2"; mkdir -p "$W/p2"
  zsh "$NC2/.agents/slop/portexec/run-kernel.sh" mm "$W/p2" > "$W/p2.log" 2>&1
  ctlrc=$?; CTLLOG="$W/p2.log"; .sr "P2" "$W/p2/port-rows.txt"
  grep -m1 'PORT PROTOTYPE' "$CTLLOG" | cut -c1-96 | sed 's/^/   PROTOTYPE : /'
  expect_red "P2 the port emitted float* and the lane still called it f64" \
    '^$NOMATCH$' || rc=1
fi

hr
say "== WHERE THIS STAGE GETS ITS DEVICE, so it cannot be quoted as stronger than it is"
say "   the port      tinybendygrad/renderer/cstyle.bend render_kernel -> C   PORT"
say "   the compiler  cc -Wall -Werror on the PORT's kernel.c alone          PORT's text"
say "   the driver    Bend allocates, fills, LAUNCHES BY POINTER, reads back  Bend"
say "   the oracle    CPython numpy float64 AND real tinygrad DEV=CPU        CPython"
say "   NOT in the path: node, a browser, navigator.gpu, a tinygrad scheduler."
say "   STILL NOT CLAIMED: that the port SCHEDULED anything. cstyle.bend has no"
say "   _render; the loop nest is emit-f64.bend's fixture, as g_kernel() at"
say "   cstyle.bend:1879 is one. This is the portexec claim, one dtype wider."
hr
if [ $rc -eq 0 ]; then
  say "STAGE 7 PASS -- 64/64 u32 words (32 doubles) through the port's own renderer,"
  say "               diff 0 bytes, port C text == CPython, every control red."
else
  say "STAGE 7 FAILED -- stages 1-6's verdicts stand on their own; this stage's failure"
  say "               does not retract them and does not launder itself into a pass."
fi
say "(this stage's own exit status: $rc)"

# ---- 7. THE ARTIFACT e2e.sh READS, so the rows it quotes are on disk ----------
# `e2e_port/run-port-mm.sh:188` `cat`s its stage's log into `$RUN` so the verdict is
# an artifact rather than something a reader has to re-run to see.  Same here. The
# f64 numbers are ALSO written as whole `name=value` rows, because
# `agent-core.md:133` records a name-comparing harness reporting 0 for all 30
# mutations in one unit and 0 for all 68 in another -- a harness must diff whole
# `name=value` lines, not row names, or it compares nothing.
{
  printf 'F64-1 words_port=%s\n'          "$(grep -c . "$W/port-words.txt")"
  printf 'F64-1 words_expected=%s\n'     "$(grep -c . "$W/cpython-words.txt")"
  printf 'F64-1 diff_bytes=%s\n'          "$(wc -c < "$W/words.diff" | tr -d ' ')"
  printf 'F64-1 port_out0_lo=%s\n'        "$(sed -n 1p "$W/port-words.txt")"
  printf 'F64-1 port_out0_hi=%s\n'        "$(sed -n 2p "$W/port-words.txt")"
  printf 'F64-1 cpython_out0_lo=%s\n'     "$(sed -n 1p "$W/cpython-words.txt")"
  printf 'F64-1 cpython_out0_hi=%s\n'     "$(sed -n 2p "$W/cpython-words.txt")"
  printf 'F64-2 kernel_text_diff_bytes=%s\n' "$kdb"
  printf 'F64-2 ptrtype_warnings=%s\n'    "$ptrwarn"
  printf 'F64-3 out0_f64_hex=%s\n'        "$(printf '0x%016x' $(( $(sed -n 2p "$W/port-words.txt") << 32 | $(sed -n 1p "$W/port-words.txt") )))"
  printf 'F64-3 out0_f32_hex=%s\n'        "$($PY -c 'import json,sys;print("0x%08x"%json.load(open(sys.argv[1]))["f32_out0_words"][0])' "$W/a/oracle.json")"
  printf 'F64-3 f32_rounds_to_one=%s\n'   "$($PY -c 'import json,sys;print(json.load(open(sys.argv[1]))["f32_rounds_to_one"])' "$W/a/oracle.json")"
  printf 'F64-4 port_rows=%s\n'           "$(grep -c '\]   py=\[' "$W/a/port-rows.txt")"
} > "$W/f64-rows.txt" || rc=1
sed 's/^/   /' "$W/f64-rows.txt"

rm -rf "$NC2"
exit $rc