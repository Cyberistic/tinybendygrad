#!/bin/zsh
# .agents/slop/e2e_port/run-port-mm.sh -- e2e.sh STAGE 6, ADDED.
#
# THE SAME MATMUL, RUN THROUGH THE PORT.  Stages 1-4 of `e2e.sh` pass 64/64 u32 words
# against CPython on a real `apple/metal-3` WebGPU adapter -- BY ASKING NODE FOR
# `navigator.gpu`.  Nothing in the port's own runtime is in that path, and that has
# been true since the artifact was written.  This stage runs the SAME matmul with NO
# NODE, NO BROWSER, NO `navigator.gpu`, and NO TINYGRAD PYTHON SCHEDULER in the
# execution path:
#
#   ./bin/bend -> the port's `renderer/cstyle.bend` `render_kernel` emits C
#   cc         -> compiles that C, and compiles Bend's own `bend -o` output
#   link, run  -> Bend allocates the buffers, fills them, LAUNCHES THE KERNEL BY
#                 POINTER, reads 64 words back and prints them
#
# The machinery is `portexec`'s and is REUSED, not copied: this file calls
# `portexec/run-kernel.sh` twice and adds only what that file does not do -- a
# coverage table carrying the DENOMINATOR, and four negative controls it does not
# run.  `portexec/` is committed and is never written to.
#
# WHAT IS STILL TRUE AND UNCHANGED.  Stage 5's header names the wall: there is no
# Bend-emitting renderer; the renderers emit C, PTX, WGSL, LLVM IR and NIR.  That wall
# is UNTOUCHED.  This stage does not need one -- the render side emits C exactly as it
# always did, `cc` compiles it, and BEND is the driver.  So the claim here is the same
# one `portexec` makes and no larger: the port's KERNEL INTERFACE AND SIGNATURE
# ASSEMBLY is semantically live C that a compiler accepts and a machine executes.
# `cstyle.bend:49` still says `Ops.SHRINK` has no dtype in `fold.bend`, so
# `render_type` cannot be driven from a graph and the kernel BODY is a fixture
# (`emit-mm.bend`'s literals, exactly as `g_kernel()` at `cstyle.bend:1879` is one).
# `portexec` did not schedule this matmul and neither does this stage.
#
# EXIT STATUS: 0 iff both lanes passed AND every control went red.  `e2e.sh` does NOT
# use it -- the script's exit status stays stage 4's, exactly as stage 5's does.
#
#   zsh .agents/slop/e2e_port/run-port-mm.sh [workdir]
set -u
# ROOT: one level up from `checks/`, and ASSERTED. See `.agents/slop/shells/README.md`.
# NOT the same arithmetic as the `ROOT=` line this script PATCHES into
# `.agents/slop/portexec/run-kernel.sh` (see `mkcopy`): that copy is planted at
# `.agents/slop/portexec/` under the workdir, which IS three levels down, so `../../..` is
# correct there and wrong here.
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.." || exit 2
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 3; }
ROOT=$PWD
PY="$ROOT/.venv/bin/python"
PORTEXEC="$ROOT/.agents/slop/portexec"
PLANT="$ROOT/.agents/slop/e2e_port/plant.py"
W=${1:-${TMPDIR}/e2e-port-mm}
# BESIDE THE GATE, IN GIT.  This was `$ROOT/runs/e2e/e2e-mm-oracle.json`, under the
# ROOT `runs/` ignore rule (`cf2d14fa4` untracked it with 168 siblings).  A gate's
# required input under an ignore rule cannot be seen in a clone: `checks/e2e.py:20`
# and `.gitignore:137` both recorded the conflict and neither fixed it.  The bytes are
# RECOVERED BYTE-IDENTICAL from `cf2d14fa4^` (`sha256 39686a96...`), exactly as
# `e2efix` recovered stage 7's fixture to the tracked `gates/cstyle-live.rows`.  A
# `.gitignore` negation inside `runs/` was REJECTED: it would leave `runs/e2e/`
# ignored, so tracking the file would make clause V's IGNORED-BUT-INDEXED rule fire.
ORACLE="$ROOT/checks/e2e-mm-oracle.json"
NC="$W/copy"
rc=0
ok=1
ctlrc=0
CTLLOG=""
mkdir -p "$W"
cleanup() { rm -rf "$NC"; }
trap cleanup EXIT

say() { print -r -- "$@" }
hr() { say ""; say "--------------------------------------------------------------------------------"; }

# ---- 0. THE EXPECTATION MUST EXIST -------------------------------------------
# A missing record must never read as a lane failure.  `oracle.py:150` sets
# `mm_missing` rather than substituting a matmul of its own, and the lane would then
# die inside `gen_ffi.py` with a KeyError -- which reads as the PORT being broken.
if [ ! -f "$ORACLE" ]; then
  say "  REFUSED, NOT A VERDICT: $ORACLE is absent."
  say "  The expectation is e2e_mm.py's OWN record of the 64 answer words, and this stage"
  say "  will not compute a replacement: a self-computed expectation would make the"
  say "  comparison against CPython a comparison against a different program."
  say "  Run e2e.sh stage 1 first: .venv/bin/python .agents/slop/e2e_mm.py"
  exit 3
fi

# ---- SUBSTRATE vs A VERDICT --------------------------------------------------
# A ZERO IS A REQUEST FOR A FIXTURE, NOT A COVERAGE CLAIM.  `run-kernel.sh` once
# reported "port produced 0 rows in 8 attempts" when the cause was a CONCURRENT AGENT's
# edit to `helpers.bend:2551`, which the port's own imports drag in.  So this is
# checked on EVERY lane and EVERY control, the port's own stderr is printed, and the
# state is named SUBSTRATE -- in a control too, where a substrate break would
# otherwise wear the costume of a successful catch.
substrate=0
substrate_note() {  # substrate_note <workdir>
  local rows
  rows=$(grep -c '\]   py=\[' "$1/port-rows.txt" 2>/dev/null || print -r -- 0)
  if [ "$rows" -lt 220 ]; then
    substrate=1
    say "      *** SUBSTRATE, NOT A VERDICT: the port produced $rows rows (220 is the floor) ***"
    say "      the port's own stderr, so the wall is NAMED and not guessed:"
    head -c 400 "$1/port-rows.err" 2>/dev/null | sed 's/^/        /'
    say ""
  fi
}

# ---- lane: run one portexec lane, and say which step broke, and is it SUBSTRATE
lane() {  # lane <mode> <label> <workdir> <logfile>
  local mode=$1 label=$2 work=$3 log=$4 lrc
  say "  [$label] zsh portexec/run-kernel.sh $mode   -- steps 1..6, each named in the log"
  zsh "$PORTEXEC/run-kernel.sh" "$mode" "$work" > "$log" 2>&1
  lrc=$?
  grep -E 'STEP [1-6]|MISMATCH at|diff bytes|^PASS \[|^FAIL \[|RED \[|GREEN \[' "$log" | sed 's/^/      /'
  substrate_note "$work"
  if [ $substrate -eq 1 ]; then
    say "      *** this lane is NOT VERIFIED and NOT REFUTED -- the substrate moved ***"
    rc=1
  elif [ $lrc -ne 0 ]; then
    say "      *** LANE FAILED (exit $lrc); the FAIL[] line above names the step ***"
    rc=1
  fi
  return $lrc
}

hr
say "== 6/6 THE MATMUL THROUGH THE PORT  -- execution: no Node, no browser, no adapter,"
say "        no tinygrad Python scheduler in the execution path"

hr
say "   [EXEC] lane A -- kern2 CLANG, ONE OF THE PORT'S OWN 227 ROWS"
lane stage2 EXEC "$W/a" "$W/a.log" || rc=1

hr
say "   [EXEC] lane B -- the four-buffer (A@B)@Cm kernel from emit-mm.bend, called FROM BEND"
lane mm EXEC "$W/b" "$W/b.log" || rc=1

# ---- the 64/64 diff in BYTES, recomputed HERE and not quoted from the lane -----
# The lane printed "diff bytes: 0" from a python list comparison.  That number is
# MEASURED AGAIN here by a DIFFERENT mechanism -- awk field extraction, then the
# external `diff`, byte-counted -- because an answer read out of the instrument that
# produced it is not a second witness.
awk '{print $3}' <(grep '^WORD ' "$W/b/run1.txt") > "$W/port-words.txt"
"$PY" -c 'import json,sys; print("\n".join(str(w) for w in json.load(open(sys.argv[1]))["answer_u32"]))' \
  "$ORACLE" > "$W/cpython-words.txt"
diff "$W/port-words.txt" "$W/cpython-words.txt" > "$W/words.diff"
say ""
say "   THE 64/64, RECOMPUTED WITH diff AND NOT READ OUT OF THE LANE:"
say "     words port=$(grep -c . "$W/port-words.txt")  CPython=$(grep -c . "$W/cpython-words.txt")  differing lines=$(grep -c . "$W/words.diff")  diff bytes=$(wc -c < "$W/words.diff" | tr -d ' ')"
say "     first 8 port   : $(head -8 "$W/port-words.txt" | tr '\n' ' ')"
say "     first 8 CPython: $(head -8 "$W/cpython-words.txt" | tr '\n' ' ')"

# ---- the denominator, in the artifact's own output ---------------------------
hr
say "== COVERAGE  how much of the port is EXECUTION and how much is TEXT, with the denominator"
"$PY" "$ROOT/.agents/slop/e2e_port/coverage.py" "$W/a/port-rows.txt" "$W/a.log" "$W/b.log" \
  || { say "  *** coverage.py died -- a table that cannot be built is not a coverage claim ***"; rc=1; }

# ---- the controls ------------------------------------------------------------
# ON A COPY.  `tinybendygrad` is COPIED and everything else is symlinked, exactly as
# `e2e_negctl.sh:44-56` does it: `.bend` imports are RELATIVE, so a flat scratch copy
# cannot resolve them, and a `$TMPDIR` copy that cannot resolve them produced 22
# phantom blind spots in one unit.  The live tree is only ever READ.  ONE LINE of the
# copy's `run-kernel.sh` is rewritten, and it is the line that makes this work at all:
# it hard-codes ROOT= to the live tree, so without the patch every plant below would be
# planted in a file nothing reads.
mkcopy() {
  ok=1
  rm -rf "$NC"
  mkdir -p "$NC/.agents/slop" "$NC/checks" || return 1
  cp -R "$ROOT/tinybendygrad" "$NC/tinybendygrad" || return 1
  cp -R "$PORTEXEC" "$NC/.agents/slop/portexec" || return 1
  cp "$ORACLE" "$NC/checks/e2e-mm-oracle.json" || return 1
  ln -s "$ROOT/bin" "$NC/bin"; ln -s "$ROOT/references" "$NC/references"
  ln -s "$ROOT/tinygrad" "$NC/tinygrad"; ln -s "$ROOT/.venv" "$NC/.venv"
  "$PY" "$PLANT" "$NC/.agents/slop/portexec/run-kernel.sh" \
    "ROOT=$ROOT" 'ROOT=$(cd "$(dirname "$0")/../../.." && pwd)' > /dev/null || return 1
  say "   copy: tinybendygrad + portexec copied; bin/ references/ tinygrad/ .venv/ symlinked"
}

planted() {  # planted <file> <old> <new>
  "$PY" "$PLANT" "$1" "$2" "$3" || { say "    *** THE PLANT DID NOT APPLY -- this control did not run ***"; ok=0; }
}

run_copy_lane() {  # run_copy_lane <portexec mode> <log tag>
  substrate=0
  zsh "$NC/.agents/slop/portexec/run-kernel.sh" "$1" "$W/c-$2" > "$W/c-$2.log" 2>&1
  ctlrc=$?
  CTLLOG="$W/c-$2.log"
  substrate_note "$W/c-$2"
  return $ctlrc
}

# A CONTROL THAT FALLS OVER IS NOT A CATCH.  `e2e_negctl.sh:168` refuses a gate that
# CRASHED rather than reporting a red row, and `nv_nvdev_gate.py` hid all 15
# disagreements behind a traceback.  So a red control must be SEMANTIC: the lane ran,
# produced numbers, and they were wrong.
expect_red() {  # expect_red <label> <regex the log must carry>
  local label=$1 must=$2
  if [ "$substrate" -eq 1 ]; then
    say "    *** NOT A CATCH [$label] -- the substrate broke this lane, so nothing was proven ***"
    return 1
  fi
  if [ $ctlrc -eq 0 ]; then say "    *** GREEN [$label] -- THE LANE DID NOT NOTICE ***"; return 1; fi
  if ! grep -q 'MISMATCH at' "$CTLLOG"; then
    say "    *** RED BUT NOT SEMANTIC [$label] -- it fell over instead of answering wrongly ***"
    grep -E '^(FAIL|SOME PROOFS FAIL|Error|error:)' "$CTLLOG" | head -4 | sed 's/^/        /'
    return 1
  fi
  if grep -qE "$must" "$CTLLOG"; then say "    RED   [$label]"; return 0; fi
  say "    *** went red, but NOT on the words naming the break [$label] ***"
  grep 'MISMATCH at' "$CTLLOG" | head -2 | sed 's/^/        /'
  return 1
}

ctl() {  # ctl <label> <regex the log must carry> <portexec mode> <log tag>
  if [ "$ok" != 1 ]; then say "    *** NOT RUN [$1] -- the copy or the plant above failed ***"; rc=1; return; fi
  run_copy_lane "$3" "$4"
  # THE PROTOTYPE IS THE EVIDENCE for a plant on the port: `gen_ffi.py` parses the
  # signature out of the port's OWN emitted C, so this line IS what the port said under
  # the plant, and the reader can see the reversal rather than take it on trust.
  grep -E 'PORT PROTOTYPE|SHIM CALL' "$CTLLOG" | sed 's/^/      /'
  expect_red "$1" "$2" || rc=1
}

hr
say "== NEGATIVE CONTROLS  -- a lane that has never failed is not known to work."
say "   C0 is mandatory: without a GREEN unmutated copy, nothing below means anything."

say ""
say "-- C0  the copy, UNMUTATED, must be green"
if mkcopy; then
  run_copy_lane mm C0
  if [ "$substrate" -eq 1 ]; then
    say "    *** C0 NOT VERIFIED -- the substrate broke the copy's lane, so C1..C4 would prove NOTHING ***"; rc=1
  elif [ $ctlrc -eq 0 ] && ! grep -q 'MISMATCH at' "$CTLLOG"; then
    say "    GREEN [C0 the unmutated copy]"
  else
    say "    *** C0 FAILED -- the copy is not green, so C1..C4 would prove NOTHING ***"
    grep -E 'MISMATCH at|^FAIL \[' "$CTLLOG" | head -3 | sed 's/^/        /'; rc=1
  fi
else rc=1; fi

# ---- C1: THE PORT.  Nobody had run this one for ANY execution lane. ----------
say ""
say "-- C1  THE PORT -- cstyle.bend's buftypes.go accumulates at the HEAD instead of the"
say "        tail, so render_kernel emits the four buffers in REVERSE order. List.append(a,"
say "        A, xs, ys) IS xs ++ ys -- bend2-constraints.md position 1590, and this is that"
say "        rule with a compiler attached."
mkcopy && planted "$NC/tinybendygrad/renderer/cstyle.bend" \
  'case h <> t: buftypes.go(dev, t, List.append(&2, String, acc, [buftype(dev, h)]))' \
  'case h <> t: buftypes.go(dev, t, List.append(&2, String, [buftype(dev, h)], acc))'
ctl "C1 THE PORT reverses its own emitted buffer order" 'MISMATCH at 64/64 words' mm C1

# ---- C2: VACUITY.  A wrong-but-plausible computation must not satisfy the lane.
say ""
say "-- C2  VACUITY -- the second dot reads data1_4 instead of the local tmp, so the kernel"
say "        computes a REAL matmul A@C instead of (A@B)@C: 64 real multiply-adds still"
say "        execute and 64 real words still come back. If the lane accepted this, then"
say "        what it was checking was a matmul and not the CHAINED dot."
mkcopy && planted "$NC/.agents/slop/portexec/emit-mm.bend" \
  'for (int k = 0; k < 8; k++) { s += tmp[i*8+k]' \
  'for (int k = 0; k < 8; k++) { s += data1_4[i*8+k]'
ctl "C2 a single matmul A@C is not (A@B)@C" 'MISMATCH at 64/64 words' mm C2

# ---- C3: THE EXPECTATION, and the comparison's completeness. ------------------
say ""
say "-- C3  THE EXPECTATION -- ONE BIT of word 37 of the 64 answer words, in the copy's"
say "        oracle record. One bit must turn it red AND name index 37 and no other: a"
say "        PREFIX is not a comparison, and 63 agreeing words are not 64."
ok=1
mkcopy && "$PY" - "$NC/checks/e2e-mm-oracle.json" <<'EOF' || ok=0
import json, pathlib, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
assert len(d["answer_u32"]) == 64, len(d["answer_u32"])
d["answer_u32"][37] ^= 1
p.write_text(json.dumps(d, indent=1))
print(f"    planted e2e-mm-oracle.json: answer_u32[37] ^= 1  ->  {d['answer_u32'][37]}")
EOF
ctl "C3 one bit of one expected word, and only that word" 'MISMATCH at 1/64 words, first 5: \[\(37,' mm C3

# ---- C4: the same PORT plant on the ONE-INPUT row. ----------------------------
say ""
say "-- C4  THE PORT, on lane A's one-input row kern2 CLANG. Reported because the answer"
say "        was NOT the predicted one: that kernel reads ONE buffer, so reversing its two"
say "        parameters was expected to be a THEOREM, as portexec's stage-2 theorems are."
say "        It is not. The harness readback address is fixed by POSITION, so the buffer"
say "        that must be read lands on the one that must be written, and word 0 goes to 0."
mkcopy && planted "$NC/tinybendygrad/renderer/cstyle.bend" \
  'case h <> t: buftypes.go(dev, t, List.append(&2, String, acc, [buftype(dev, h)]))' \
  'case h <> t: buftypes.go(dev, t, List.append(&2, String, [buftype(dev, h)], acc))'
ctl "C4 THE PORT, on the one-input row" 'MISMATCH at 1/4 words' stage2 C4

hr
say "-- INHERITED, NOT RE-COUNTED: portexec/run-kernel.sh runs three plants of its own"
say "    inside EVERY lane above, and each went red in this run:"
grep -hE '^   (RED|GREEN|VACUOUS) \[' "$W/a.log" "$W/b.log" | sort -u | sed 's/^/    /'

hr
say "== WHERE EACH STAGE OF e2e.sh GETS ITS DEVICE, so this cannot be quoted as stronger"
say "   than it is:"
say "   1  oracle       CPython tinygrad DEV=CPU            the EXPECTATION, not an execution"
say "   2  port (pure)  no device; prints a program        TEXT"
say "   3  gpu          NODE + headless Chrome + navigator.gpu (apple/metal-3)   ASKS NODE"
say "   4  gate         diffs two recorded texts           TEXT"
say "   5  ops_bend     the port's own runtime, in Bend     EXECUTION (one f32 add, 3 scalars)"
say "   6  THIS STAGE   the port's render_kernel + cc + Bend   EXECUTION (64/64 matmul words)"
say "   --  and the 227-row cstyle gate this stage does NOT re-run: cstyle-gate.py:554"
say "       builds BOTH lanes from a recorded stdout, so all 227 of ITS rows are TEXT."

hr
if [ $rc -eq 0 ]; then
  say "STAGE 6 PASS -- 64/64 u32 words through the port's own renderer, diff 0 bytes, and"
  say "               every negative control went red."
else
  say "STAGE 6 FAILED -- stages 1-5's verdict above stands on its own; the script's exit"
  say "               status is STILL stage 4's and is unaffected by this line."
fi
say "(this stage's own exit status, for a caller that wants it: $rc)"
exit $rc
