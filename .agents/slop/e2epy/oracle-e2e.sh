#!/bin/sh
# .agents/slop/e2e.sh -- THE ONE COMMAND. `./.agents/slop/e2e.sh` and it either
# prints PASS or FAIL and exits 0 or 1.
#
# SEVEN STAGES, and the order is the order the claims come in. Stages 5, 6 and 7 were ADDED and
# are described at their own blocks, which are the only place their claims are written down; this
# header is a table of contents, not the claim. Stage 8 is RETIRED -- see its block below, and the
# reason is a denominator of 0, which is not a smaller stage but the absence of one:
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
ROOT=${E2E_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
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
# NOTE THE ASYMMETRY, WHICH THE EXIT STATUS BELOW MAKES EXPLICIT: CLAIM INDEPENDENCE
# is why `FAIL` is 1 and not 2 or 3, and it is a claim only about stages that RAN.
# A stage that measured NOTHING retracts even that, which is why `SKIP` is its own
# status, 4, and not 0.  Evidence `.agents/slop/skipexit/FINDINGS.md` §2.
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
# TODO(stage-5-denominator): `tail -3` IS THE DENOMINATOR AND IT IS ALSO WHAT A CRASH REPLACES. The
# milestone's own last three lines are the expectation-file comparison, but when it dies first they
# are a traceback (measured 2026-10-05: `FileNotFoundError: .agents/slop/
# ops_bend-milestone-expected.txt`), so a stage that ran and printed NOTHING COUNTABLE leaves the
# artifact unable to say what it would have measured. NOT FIXED HERE, DELIBERATELY: changing what
# this stage prints is a change to the artifact on BOTH sides of the porting rule, and the oracle is
# frozen so that such a change is a separate deliberate act rather than a side effect of retiring
# stage 8. `.agents/slop/e2estage8/verdicts.py` reports it as `DENOMINATOR None` until then.
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
# STAGE 8, THE JAVASCRIPT LANE.  RETIRED, NOT RE-POINTED, BECAUSE ITS DENOMINATOR
# IS 0.  Its prose went with its code on purpose: an essay about a stage that no
# longer runs is how a reader is told a stage exists when it does not, and the
# docstring is the one a reader trusts.
#
# WHAT IT WAS.  `jstage.py` ran `runtime/dtype.js` through `bend -o` under node and
# compared 20 rows against CPython.
#
# WHY 0, IN THE STAGE'S OWN WORDS, because it printed the denominator every run and
# then said the rest out loud:
#     rows that REACH `dtype.js`      0
#     rows that are pure `dtype.bend` 20   (NOT the JS lane)
#     FAIL  the plant moved 0 rows, so this stage CANNOT fail on the bug it exists for
# `dtype.bend` declares 0 `IO(` laws, 0 of 137+ `.bend` files import
# `runtime/dtype.{c,js}`, and `runtime/dtype.js` is not one byte of the emitted
# bundle.  A GATE WHOSE DENOMINATOR IS ZERO IS NOT A GATE: it can never fail, so it
# can never pass either, and it makes the seven around it look like a suite.
#
# WHAT REPLACES IT IS A CITATION, NOT A STAGE.  `.agents/slop/lastlaw/run.py`
# measures the same pure `dtype.bend` arithmetic at 1330/1330 (102 i64 + 1228 fp8)
# against the same CPython callables, so stage 8's 19 rows were a 19-row echo of a
# 1330-row gate.  Evidence: `.agents/slop/deadreg/REPORT.md` §2.  Re-point this
# stage ONLY if a `Dt.*` law becomes a seam again, which is the one change that
# would make a denominator non-zero -- re-declaring one as a seam is what
# `.agents/slop/LASTLAW.md` undid, and it must not be undone to keep a row count.
#
# THE CENSUS THAT KEEPS IT GONE IS `e2estage8/verdicts.py`: it counts every
# emitted stage's denominator out of the artifact and exits 1 on any stage that is
# emitted with 0, and it exits 1 on any disagreement between the stage names in this
# file's prose, the stage headers this file emits, and the stage headers in a run's
# transcript.  A retirement nobody can check is a comment.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# THE EXIT STATUS. NO LONGER STAGE 4's, AND NOT 0 FOR A RUN THAT MEASURED NOTHING.
#
#   0  every stage ran and every stage agreed
#   1  one or more stages RAN and FAILED
#   2  NOTHING WAS MEASURED. Either this file is not at a repo root -- asserted above, before any
#      stage, so the directory it reached is named on stderr -- or eight `bend` attempts produced no
#      rows, which `set -e` aborts inside stage 2. Both are refusals with no verdict lines at all,
#      which is why they share a status: a caller cannot tell from the number which refusal it was,
#      so a caller that needs to know reads the stderr, and both refusals say what they are.
#   3  the frozen oracle moved: nothing was compared
#   4  NOTHING FAILED BUT SOMETHING MEASURED NOTHING
#
# WHY 4 AND NOT 0, because the earlier 0 was defended with a reason that is true of FAIL
# and NOT of SKIP.  It said: a passing stage does not retract the others' claims; a stage
# that RAN and FAILED is what makes the gate exit 1.  That is claim independence and it is
# correct -- but it presupposes the passing stage measured SOMETHING.  A skipped stage
# measured nothing, and a stage that measured nothing retracts every claim resting on it,
# including the passing stages' claim to be evidence about this tree.  So three states came
# out of the exit status as TWO NUMBERS, and a caller reading only `$?` was told 0 for a
# run in which the port was never judged.  A gate that exits 0 having done nothing is worse
# than no gate, because it is trusted.  `checks/bounded.py` added `5`/`6` for this same
# reason and records the cost of a status that cannot mean one thing.
echo "--- verdicts: $FAILS failed, $SKIPS skipped ---"
if [ "$FAILS" -gt 0 ]; then
  echo "FAIL -- $FAILS stage(s) ran and failed. The per-stage verdicts above stand on their own:"
  echo "       a failing stage does not retract the others' claims, and this script now says so in"
  echo "       its exit status, which it did not before."
  exit 1
fi
if [ "$SKIPS" -gt 0 ]; then
  echo "PASS WITH $SKIPS SKIP(S) -- nothing failed, but $SKIPS stage(s) measured NOTHING."
  echo "       PASS-WITH-SKIP IS NOT PASS, AND THE EXIT STATUS SAYS SO: 4, NOT 0. Read the"
  # THE BACKTICKS ARE ESCAPED, AND THAT IS MEASURED, NOT TYPOGRAPHY. `sh` reads an unescaped
# backtick pair as COMMAND SUBSTITUTION, so the first cut of this line ran `\$?` -- i.e. `0` -- as a
# command and put `line 314: 0: command not found` on the gate's STDERR. It showed up as a
# `stderr: DIFFERS (118 vs 0 bytes)` on `plant-no-node` and nowhere else, because that is the only
# plant whose PATH is short enough for the subshell to reach. The port prints a literal string and
# has no such hazard; escaping makes the two sides emit the same bytes.
echo "       skipped lines above. A caller that only reads \`\$?\` can no longer mistake this"
  echo "       for a clean pass; that was the defect."
  exit 4
fi
echo "PASS -- every stage ran and every stage agreed."
exit 0
