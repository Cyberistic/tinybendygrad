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
