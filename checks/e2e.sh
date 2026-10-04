#!/bin/sh
# .agents/slop/e2e.sh -- THE ONE COMMAND. `./.agents/slop/e2e.sh` and it either
# prints PASS or FAIL and exits 0 or 1.
#
# FOUR STAGES, and the order is the order the claims come in:
#
#   1. ORACLE      `.venv/bin/python .agents/slop/e2e_mm.py` traces a real
#                  `(A @ B) @ C` out of tinygrad on DEV=CPU, takes tinygrad's own
#                  WGSL for each of the two launches, and writes
#                  runs/e2e/e2e-mm-oracle.json plus the .bend that will be run.
#   2. PORT        `./bin/bend .agents/slop/e2e_mm.bend` runs the PURE half. This
#                  is the half that needs no GPU: it prints the program the port
#                  built. Read the FIRST LINE, never the exit status --
#                  `--check-only` exits 1 on a clean file and a broken .bend prints
#                  `SOME PROOFS FAIL` and exits 0.
#   3. GPU         `node .agents/slop/e2e_mm_run.mjs` compiles the same .bend with
#                  `bend -o`, serves it with a byte copy of
#                  tinybendygrad/runtime/webgpu_call.js, and walks it on a real
#                  WebGPU adapter in headless Chrome.
#   4. GATE        `.venv/bin/python .agents/slop/e2e_mm_gate.py` diffs whole
#                  `name=value` rows and prints PASS or FAIL.
#
# `.venv/bin/python`, never `python3`: the editable tinygrad install exists only in
# `.venv` (3.12), and PATH's python3 has no `.pth`, so a `python3` here would
# resolve to a different tree and report zero rows rather than fail.
#
# NOTHING IN THE LIVE PORT TREE IS EDITED. Stage 3 emits into .agents/slop/e2e/,
# which is this unit's own directory, and stage 2 only reads.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
PY="$ROOT/.venv/bin/python"
RUN="$ROOT/runs/e2e"
mkdir -p "$RUN"

# bend stack-overflows on roughly one run in twenty and prints NOTHING, and a
# zero-row result is indistinguishable from "not started". So the run is retried
# and the row count is checked, not just the exit status.
bend_run() {
  i=0
  while [ "$i" -lt 8 ]; do
    i=$((i + 1))
    if ./bin/bend .agents/slop/e2e_mm.bend > "$RUN/e2e-mm-bend.txt" 2> "$RUN/e2e-mm-bend.err"; then
      n=$(grep -c '=' "$RUN/e2e-mm-bend.txt" || true)
      if [ "$n" -gt 20 ]; then
        echo "bend: $n rows (attempt $i)"
        return 0
      fi
    fi
    echo "bend: attempt $i produced $n rows, retrying" >&2
    sleep 1
  done
  echo "bend: no run produced rows in 8 attempts -- SUBSTRATE OR FIXTURE, not a verdict" >&2
  head -3 "$RUN/e2e-mm-bend.err" >&2 2>/dev/null || true
  return 2
}

# ---------------------------------------------------------------------------
# THE VERDICT ACCUMULATOR. ADDED AFTER A MEASURED DEFECT, NOT FOR STYLE.
#
# STAGES 5 AND 6 PRINTED `STAGE n FAILED` AND THE SCRIPT STILL EXITED 0, because the
# exit was `$rc` -- STAGE 4's. MEASURED HERE, by renaming `run-port-mm.sh` away so
# stage 6 could not start:
#     mm_e2e_failed=0 / PASS ... STAGE 6 FAILED ... exit 0
# A STAGE THAT FAILS AND DOES NOT REACH THE EXIT STATUS IS A ROW THAT CANNOT FAIL,
# IN THE PROJECT'S ONE EXECUTABLE ARTIFACT.
#
# TWO THINGS ARE BEING KEPT APART, AND THE OLD CODE CONFLATED THEM:
#   CLAIM INDEPENDENCE -- stage 6 failing must NOT retract "stage 4's matmul is
#     green". TRUE, and each verdict is still printed on its own.
#   ARTIFACT SOUNDNESS -- a stage that RAN and FAILED must make the SCRIPT fail.
#     Also true, and it is what was missing.
# Hence three outcomes, not two. `SKIP` IS NOT `PASS`: a stage that could not run
# has measured nothing, and reporting it as a pass is the same defect one level up.
FAILS=0
SKIPS=0
verdict () {  # verdict <stage> <rc>
  if [ "$2" -eq 0 ]; then echo "  $1: PASS"
  else echo "  $1: FAIL (rc=$2)"; FAILS=$((FAILS + 1)); fi
}
skip () {     # skip <stage> <why>
  echo "  $1: SKIP -- $2"; SKIPS=$((SKIPS + 1))
}

echo "== 1/4 oracle (CPython tinygrad, DEV=CPU)"
"$PY" .agents/slop/e2e_mm.py

echo "== 2/4 port (pure bend, no GPU)"
bend_run

echo "== 3/4 gpu (real WebGPU adapter, headless Chrome)"
# THE ONE STAGE THAT ASKS NODE. IT IS THE ONLY STAGE THAT NEEDS A BROWSER, SO IT IS
# ALSO THE ONLY STAGE THAT CAN BE UNAVAILABLE. AN UNAVAILABLE STAGE IS `SKIP`, NEVER
# `PASS`: it measured nothing, and calling that a pass is the same defect one level
# up. Stages 5 and 6 need no browser at all, which is the point of them.
if command -v node >/dev/null 2>&1; then
  set +e; node .agents/slop/e2e_mm_run.mjs; nsrc=$?; set -e
  verdict "stage 3 gpu (node)" "$nsrc"
else
  skip "stage 3 gpu (node)" "no \`node\` on PATH; stage 3 measured nothing"
fi

echo "== 4/4 gate"
# THE EXIT STATUS IS THE PYTHON ONE, NOT `tee`'s. MEASURED in this harness, and it
# is the exact trap this repo keeps paying for: `"$PY" gate.py | tee out.txt` makes
# `$?` the status of `tee`, so a gate that CRASHED printed `PASS`. POSIX sh has no
# PIPESTATUS, so the gate writes its own file and the status is read from the
# command itself.
set +e
"$PY" .agents/slop/e2e_mm_gate.py "$RUN/e2e-mm-bend.txt" > "$RUN/e2e-mm-gate.txt" 2>&1
rc=$?
set -e
cat "$RUN/e2e-mm-gate.txt"
verdict "stage 4 gate (matmul vs CPython, via WebGPU)" "$rc"

# ---------------------------------------------------------------------------
# STAGE 5, THE PORT'S OWN DEVICE. ADDED, NOT SUBSTITUTED: everything above is
# UNCHANGED and its PASS/FAIL is what this script still returns. Read stage 5 as a
# SEPARATE claim with its own verdict, because it answers a different question.
#
# STAGES 1-4 ask: does the port build a matmul program and does a REAL WebGPU
# adapter run it? The adapter is the BROWSER's, reached over
# `.agents/slop/e2e/webgpu_call.js`. Nothing in the port's own runtime is in that
# path.
#
# STAGE 5 asks: does the PORT'S OWN `ops_bend` runtime execute? It allocates three
# buffers in Bend's memory, writes a known pattern, launches
# `tinybendygrad/runtime/ops_python.bend` -- which IS the executor, and which
# `ops_bend.py:151` builds with `./bin/bend ... -o` -- reads PACKET.out back, and
# compares it against an expectation written down BEFORE any run
# (`.agents/slop/ops_bend-milestone-expected.txt`). No Node, no browser, no adapter,
# and no tinygrad Python scheduler in the path.
#
# It is NOT COMPOSED WITH STAGES 1-4 ON PURPOSE. This stage does not run a matmul;
# it runs ONE elementwise add over three f32 scalars. Joining them would need the
# render side to emit Bend source, and NOTHING DOES -- MEASURED: the only three
# files under `tinybendygrad/` that mention `bendexec` are `ops_python.bend` (the
# executor), `ops_bend.bend` (this port) and `ops_bend.mut.bend` (a scratch copy).
# The renderers in `tinybendygrad/renderer/` emit C, PTX, WGSL, LLVM IR and NIR;
# there is no Bend renderer. That is the wall, and it is named rather than worked
# around.
# ---------------------------------------------------------------------------
echo "== 5/5 port's own device (the port's ops_bend runtime executes)"
set +e
./.agents/slop/opsbend-milestone.sh > "$RUN/e2e-opsbend.txt" 2>&1
msrc=$?
set -e
tail -3 "$RUN/e2e-opsbend.txt"
verdict "stage 5 ops_bend (kernel executes in Bend)" "$msrc"
# THE COMMENT THAT USED TO BE HERE WAS RIGHT AND INCOMPLETE. "A failure here must not
# retract a green matmul: the two claims are independent" -- TRUE, and each verdict is
# now printed separately above. What it did NOT say is that the failure must still
# REACH THE EXIT STATUS, and omitting that is what let this stage print FAILED while
# the script exited 0. Both halves now hold: the claim stands on its own, and the
# artifact still fails.

# ---------------------------------------------------------------------------
# STAGE 6, THE SAME MATMUL RUN THROUGH THE PORT. ADDED, NOT SUBSTITUTED: nothing
# above this line is changed and its PASS/FAIL is still what this script returns.
# Read stage 6 as a SEPARATE claim with its own verdict, because it answers the
# question stage 3 cannot.
#
# STAGES 1-4 ASKING NODE FOR A DEVICE IS THE GAP STAGE 6 CLOSES, not a mistake in
# them. Stage 3 reaches a real `apple/metal-3` adapter through
# `.agents/slop/e2e/webgpu_call.js`, driven by `node`; nothing in the port's own
# runtime is in that path, and that has been true since the artifact was written.
# Stage 6 runs the SAME `(A @ B) @ Cm` with NO NODE, NO BROWSER, NO
# `navigator.gpu` AND NO TINYGRAD PYTHON SCHEDULER in the execution path:
# `cstyle.bend`'s `render_kernel` emits the C, `cc` compiles it, and BEND allocates
# the buffers, fills them, LAUNCHES THE KERNEL BY POINTER and reads 64 words back.
# It also prints the COVERAGE TABLE, so the artifact cannot be quoted as stronger
# than 1 of the port's 227 gate rows is executed.
#
# THE WALL STAGE 5 NAMES IS UNCHANGED. There is still no Bend-emitting renderer,
# and nothing here needed one: the render side emits C exactly as it always did.
# What is now proven live is the port's KERNEL INTERFACE AND SIGNATURE ASSEMBLY --
# the same claim `portexec/STAGE3.md` makes, and no larger. The kernel BODY is
# still `emit-mm.bend`'s fixture. The mechanism is upstream's own CPU backend
# (`ops_cpu.py:29-72`), not an invention, and it is portexec's, reused unchanged.
#
# Like stage 5, this stage's verdict does NOT become the script's exit status.
# ---------------------------------------------------------------------------
echo "== 6/6 the matmul THROUGH THE PORT (no Node, no browser, no navigator.gpu)"
set +e
zsh .agents/slop/e2e_port/run-port-mm.sh > "$RUN/e2e-port-mm.txt" 2>&1
psrc=$?
set -e
cat "$RUN/e2e-port-mm.txt"
verdict "stage 6 port (matmul THROUGH the port, no Node)" "$psrc"

# ---------------------------------------------------------------------------
# STAGE 7, THE SAME KERNEL ONE DTYPE WIDER.  ADDED, NOT SUBSTITUTED: nothing above
# this line is changed, stages 1-6 are byte-unchanged, and their verdicts still are
# what the per-stage lines say they are.  Read stage 7 as a SEPARATE claim.
#
# STAGES 1-6 RUN `float`.  STAGE 7 RUNS `double`, through the SAME committed harness
# -- `.agents/slop/portexec/run-kernel.sh mm`, unchanged, on a copy.  The port emits
# `void mm(double* restrict data0_4, ...)`; `cc -Wall -Werror` compiles it; BEND
# allocates three buffers, fills them, LAUNCHES THE KERNEL BY POINTER and reads 64
# `U32` words back; all 64 are bit-identical to CPython's, diff 0 bytes.  No Node, no
# browser, no `navigator.gpu`, no tinygrad scheduler.
#
# WHY IT IS ITS OWN STAGE AND NOT A WIDER CLAIM ON STAGE 6: because `render_dtype`
# HAS NO `f64` GATE ROW.  `renderer/cstyle.bend:2984-3015` calls `rd_row` for exactly
# seven dtypes -- f32, f16, bf16, bool, u8, fp8e4m3, i32 -- across six devices, and
# f64 is not among them, so all 227 rows are silent about `double*`.  `tmap CLANG`
# does carry the NAME `double`, and a name in a type map is not a `double*` in a
# signature that a compiler accepted and a machine executed.
#
# THE NO-`double`-CROSSES-THE-FFI HALF IS THE POINT.  An f64 element is TWO `U32`
# words at the 4-byte stride `fill.go`/`dump.go` already walk, so the word count is
# still 64 for 32 doubles and the harness needed no change to be dtype-general.  That
# is the same two-`U32` route `W64.md:124-160` measured, now on a KERNEL.
#
# AND IT IS THE ROW f32 CANNOT HAVE.  `out[0] = 1.0 + 2**-40 = 0x3FF0000000001000`,
# which rounds to exactly `1.0` (`0x3F800000`) in f32.  Same kernel shape, same
# harness, same launch, different width, different answer -- so the width is not a
# label.  CPython's two answers are printed side by side, never asserted apart.
# ---------------------------------------------------------------------------
echo "== 7/7 the SAME kernel in f64 THROUGH THE PORT (no Node, no browser, no adapter)"
set +e
zsh .agents/slop/f64/run-f64.sh > "$RUN/e2e-f64.txt" 2>&1
fsrc=$?
set -e
# A stage that DID NOT RUN must be SKIP, never PASS.  `run-f64.sh` exits 3 without
# running a lane when its substrate is cold, and 3 is a refusal, not a failure.
if [ "$fsrc" -eq 3 ]; then
  skip "stage 7 f64 (double through the port, no Node)" "run-f64.sh refused: its substrate is cold; see $RUN/e2e-f64.txt"
elif [ "$fsrc" -eq 127 ]; then
  skip "stage 7 f64 (double through the port, no Node)" "\`zsh\` is not available; stage 7 measured NOTHING"
else
  grep -E 'STAGE 7 (PASS|FAILED)|64/64 MET|IDENTICAL|port now says|REFUSED\[|RED   \[|GREEN \[|THEOREM \[|F64-[0-9]' \
    "$RUN/e2e-f64.txt" | sed 's/^/  /'
  verdict "stage 7 f64 (double through the port, no Node)" "$fsrc"
fi

# ---------------------------------------------------------------------------
# STAGE 8, THE JAVASCRIPT LANE.  ADDED, NOT SUBSTITUTED: bytes 1..12449 above are
# UNCHANGED, stages 1-7 are byte-for-byte as they were, and each of their verdicts
# is still exactly what its own line says.  Read stage 8 as a SEPARATE claim with
# its own verdict, because it answers the question stages 1-7 cannot.
#
# STAGES 1-7 ALL RUN THE BEND OR C LANE.  Every one of them: `e2e_mm.py` traces
# tinygrad, `e2e_mm.bend` runs the pure half, `e2e_mm_run.mjs` drives a real WebGPU
# adapter, `run-port-mm.sh` emits C and compiles it with `cc`, `run-f64.sh` does the
# same one dtype wider.  `node` appears ONCE, in stage 3, and there it is a BROWSER
# DRIVER -- `navigator.gpu` -- and no part of the port's runtime is in that path.
# `bend -o out.js` is a real target and `tinybendygrad/runtime/dtype.js` is a real
# lane, and as of this line NO stage above executed either.
#
# WHAT THAT COST, MEASURED, IN ORDER, AND NONE OF IT WAS A LOUD FAILURE:
#   * `dtype.c:205` read two FRAME SLOTS where the seam has one argument and
#     returned TWO ALLOCATION ADDRESSES.
#   * `dtype.js:137` read `p.fst`/`p.snd` against fields `hi`/`lo`.  Both were
#     `undefined`, and `undefined >>> 0 === 0`, so `i64_of` was identically 0 --
#     `Dt.i64_trunc`, the IDENTITY, was not the identity -- and the lane disagreed
#     with CPython on 9 of 12 rows while printing a plausible row for each.
#   * three `of32` misplacements: 57/98 -> 98/98 once found.
# A gate caught each one.  A GATE IS NOT THE ARTIFACT, and this file is the
# artifact a reader runs.
#
# THE CLAIM, IN ONE SENTENCE, WITH ITS DENOMINATOR -- the whole of it, and it is
# SMALL on purpose:  `node` runs `runtime/dtype.js` through `bend -o`, exits 0,
# prints all 20 rows the gate asks for, and agrees with CPython on the 19 of them
# CPython can answer.  `ceildiv(x, 0)` answers 0 in both lanes where CPython
# raises, so that row is counted `diverge` and is in NEITHER pass nor fail.
#
# OF THOSE 20, 12 REACH `dtype.js` AND 8 DO NOT, and the gate prints the split on
# its own line rather than letting a reader assume 20.  MEASURED 2026-10-05:
# `dtype.bend` has been rewritten so that `Dt.bf16`, `Dt.fp16` and `Dt.fp8_to` are
# PURE defs, so the three CIDs `dtype.js` registers for them are DEAD -- registered
# and never called -- and those rows measure `dtype.bend`.  The gate derives that
# split from the substrate's own declarations on every run, so a tree that moves
# back is counted correctly without an edit here.
#
# WHAT THE STAGE'S OWN HEADER STATES AS ITS LIMIT, because a reader who reads only
# this file must not be able to quote it as more:  EXECUTED IS NOT BOUND.  The
# census that says so with numbers is `.agents/slop/CLANGFILL.md` §2 -- 320
# executed, 256 of them called with at least one NULL argument, 175 answering a
# refusal sentinel -- and it is `clangfill/gate.py`, which drives `cc` against
# `libclang`.  IT IS NOT A JS CENSUS: `clangshim/apply-port-lane.py:130` records
# that the libclang lane cannot be emitted to JS at all.  What stage 8 borrows is
# the SHAPE of that caution and states its own limit in the terms it can measure --
# every argument in it is a bend literal, so there is no NULL-argument class here.
#
# THE THREE OUTCOMES ARE THE THREE OUTCOMES.  A stage that COULD NOT RUN is `SKIP`
# and never `PASS`, and the refusal is REAL rather than theoretical: with the
# substrate cold -- a zero-byte `cstyle.bend` planted, or `dtype.bend` under
# concurrent edit as it was on 2026-10-05 -- `bend -o` fails and the gate exits 3
# having measured nothing.  That is `SKIP`, exactly as `run-f64.sh`'s exit 3 is at
# stage 7, and a gate that refuses must not be reported green.
#
# AND THE LESSON THIS STAGE IS BUILT ON, WHICH COST THE JS LANE TWICE: node's exit
# status is READ, and a row that is ABSENT is a FAILURE rather than a neutral.
# `abi4_gate.py` once passed 98/98 and `abi_gate.py` once reported "node agrees with
# CPython on 12/12" while `node` had exited 1 with EMPTY stdout, because `vs()`
# excludes absent rows from `bad` -- so A DEAD LANE COUNTED AS A LANE NEVER WRONG.
# Both gates now exit on node's status or a short row set, and so does this one.
# ---------------------------------------------------------------------------
echo "== 8/8 the JS dtype LANE under node (bend -o emits JS; node is what runs it)"
# ONE TEMP, ONE WRITE, ONE ATOMIC MOVE.  This is the shape `graphcmp-run.sh:38-56`
# adopted after the SECOND time this project was bitten by it: the version that
# appended `rc=$?` to the SAME file the child had just written left a window between
# the two, and a run killed in that window produced a report MISSING its last line
# and with no `rc=` stamp -- which the stability step then reported as a
# reproducibility difference where the difference was "the second file is shorter".
# The temp is INSIDE `$RUN` and dot-named, so `mv` is same-directory and therefore
# atomic, and a temp left by a kill is never read as a report.
rm -f "$RUN"/.tmp.e2e-jsstage.txt
set +e
{ "$PY" .agents/slop/jstage/jsstage.py > "$RUN/.tmp.e2e-jsstage.txt" 2>&1
  echo "rc=$?" >> "$RUN/.tmp.e2e-jsstage.txt"; }
mv "$RUN/.tmp.e2e-jsstage.txt" "$RUN/e2e-jsstage.txt"
jsrc=$?
set -e
# `jsrc` is `mv`'s, and the GATE's status is the LAST LINE of the report.  It is
# read with `tail` and not with a pipeline, for the same reason stage 4 does not
# pipe its gate into `tee`: POSIX sh has no PIPESTATUS, so `$?` after a pipe is the
# status of the LAST command in it and a gate that CRASHED would print PASS.
jsgate=$(grep -c '^rc=' "$RUN/e2e-jsstage.txt" || true)
jsstage_rc=$(sed -n 's/^rc=\([0-9]*\)$/\1/p' "$RUN/e2e-jsstage.txt" | tail -1)
: "${jsstage_rc:=-1}"
grep -E '^(THE CLAIM|  substrate measured|  rows asked|  rows that|  CIDs|  rows CPython|  `node` exit|  ROWS PRESENT|  node agrees|  PLANT|  DISARM|===== VERDICT|REFUSED|SUBSTRATE MEASURED)' \
  "$RUN/e2e-jsstage.txt" | sed 's/^/  /'
if [ "$jsrc" -ne 0 ] || [ "$jsgate" -ne 1 ]; then
  # THE STAGE ITSELF DID NOT RUN.  Nothing was measured, so this is SKIP and not
  # FAIL -- but it is also not PASS, and it says which of the two went wrong.
  skip "stage 8 js lane (node on runtime/dtype.js)" \
    "the gate did not complete: mv rc=$jsrc, rc= stamps=$jsgate (want 1/1); see $RUN/e2e-jsstage.txt"
elif [ "$jsstage_rc" -eq 3 ]; then
  # REFUSAL, and THE SUBSTANCE OF IT IS ABOVE: `bend -o` would not emit, so the
  # lane never ran.  `SKIP` IS NOT `PASS` -- a stage that could not run has measured
  # NOTHING, and saying PASS here is the same defect one level up.
  skip "stage 8 js lane (node on runtime/dtype.js)" \
    "jsstage.py REFUSED (rc 3): its substrate would not compile; see $RUN/e2e-jsstage.txt"
else
  verdict "stage 8 js lane (node on runtime/dtype.js, 20 rows vs CPython)" "$jsstage_rc"
fi

# ---------------------------------------------------------------------------
# THE EXIT STATUS. IT IS NO LONGER STAGE 4's, AND THAT IS THE FIX.
#
# Every stage that RAN and FAILED now decides. `SKIP` does not -- a stage that could
# not run measured nothing, and must not be laundered into a pass by the same
# arithmetic that would hide a real failure.
echo "--- verdicts: $FAILS failed, $SKIPS skipped ---"
if [ "$FAILS" -gt 0 ]; then
  echo "FAIL -- $FAILS stage(s) ran and failed. The per-stage verdicts above stand on their own:"
  echo "       a failing stage does not retract the others' claims, and this script now says so in"
  echo "       its exit status, which it did not before."
  exit 1
fi
if [ "$SKIPS" -gt 0 ]; then
  echo "PASS WITH $SKIPS SKIP(S) -- nothing failed, but $SKIPS stage(s) measured NOTHING."
  echo "       PASS-WITH-SKIP IS NOT PASS. Read the skipped lines above."
  exit 0
fi
echo "PASS -- every stage ran and every stage agreed."
exit 0
