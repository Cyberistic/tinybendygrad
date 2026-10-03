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

echo "== 1/4 oracle (CPython tinygrad, DEV=CPU)"
"$PY" .agents/slop/e2e_mm.py

echo "== 2/4 port (pure bend, no GPU)"
bend_run

echo "== 3/4 gpu (real WebGPU adapter, headless Chrome)"
node .agents/slop/e2e_mm_run.mjs

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
if [ "$rc" -eq 0 ]; then echo "PASS"; else echo "FAIL"; fi
exit "$rc"
