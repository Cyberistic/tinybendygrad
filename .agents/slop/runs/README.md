# `runs/` — BASELINES, captured BEFORE any edit, 2026-10-03

The core brief's rule: *capture a baseline immediately before any mutation run, and
wait for the substrate to settle between steps*. These are those baselines, taken
before the 1:1 split touched anything, and they are what the three split invariants
are proved against.

| file | rows | of |
|---|---|---|
| `base_codegen_late.bend.txt` | 128 | `codegen/late.bend`, the pre-split MERGED file |
| `base_runtime_ops_cpu_null.bend.txt` | 308 | `runtime/ops_cpu_null.bend`, the pre-split MERGED file |
| `base_renderer_tc_ptx.bend.txt` | 620 | `renderer/tc_ptx.bend`, the pre-split MERGED file |
| `base_codegen_kernel.bend.txt` | 38 | `codegen/kernel.bend` — must not move; three files import it |
| `base_codegen_rewriter.bend.txt` | 54 | `codegen/rewriter.bend` — must not move; `kernel.bend` imports it |
| `base_runtime_ops_cl.bend.txt` | 445 | `runtime/ops_cl.bend` — the NEXT split's baseline (`ops_cuda.py`, `ops_hip.py`) |
| `base_renderer_nir.bend.txt` | 102 | `renderer/nir.bend` — carries `runtime/support/c.py`'s port |
| `base_exec_gate.txt` | 18 ok | `runtime/executor.bend`'s gate, `ok`-line form not `name=value` |
| `base_runtime_executor.bend.txt` | 0 | `runtime/executor.bend` prints **no rows**: its `main` is a driver that takes a PACKET path, so a bare run prints `No such file or directory`. Its gate is `.agents/slop/exec_gate.bend` (18 ok / 0 FAIL). A 0-row file is not a broken file, and the next unit should not spend an hour on it the way this one nearly did. |

The three the split gates use are ALSO checked in under their own names —
`late-pre-split.txt`, `ops_cpu_null-pre-split.txt`, `tc_ptx-pre-split.txt` — because
those are the files the `*-gate.sh` scripts diff and a script should not reach into a
subdirectory to find its oracle.

`.err` files are bend's stderr for the same runs; they are empty for every
gate-green file, because `--check-only` and a run agree here.
