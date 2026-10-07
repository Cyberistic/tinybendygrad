# THE FIFTH VERDICT: `UNKNOWN`, THE ROWS THAT NEED A HUMAN, AND WHAT WOULD SETTLE EACH

**409 of 944 rows are UNKNOWN and NONE of them is a deletion candidate.**
`sweep` has no place to record "I cannot tell", so these rows were falling through to
`return "DELETE"` -- which is not a verdict, it is the ABSENCE of one, and it is the
only bucket `--apply` destroys.

| path | why it is UNKNOWN | the cheapest test that would resolve it |
|---|---|---|
| `.agents/slop/webgpu_call.fresh.mjs` | named only from inside the residue by .agents/slop/canrun/census/checks_sweep.py.out; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/opsbend-milestone/bend-executor` | the two citation belts disagree; git sees ['.agents/slop/arghalf/pin-tree/tinygrad/runtime/ops_bend.py'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/stale269/ledger.tsv` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/oracles259/classified.json` | named only from inside the residue by .agents/slop/gatecensus/classify.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/restore-plan.tsv` | named only from inside the residue by .agents/slop/stale269/plan.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/plan.tsv` | the two citation belts disagree; git sees ['.agents/slop/stale269/plan.py'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/stale269/skipped.tsv` | named only from inside the residue by .agents/slop/stale269/plan.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/oracles259/othercopies.json` | named only from inside the residue by .agents/slop/oracles259/othercopies.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-after.sha256` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.copy.sha256` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.sha256` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/after.out` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-67c32beb8.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/stale71/table.out` | named only from inside the residue by .agents/slop/stale71/c-afd395686.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/status-1.rows` | named only from inside the residue by .agents/slop/stale71/c-afd395686.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/live1.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/post.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/live1.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/post.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/fixures/before.out` | the two citation belts disagree; git sees ['.agents/slop/fixures/reconcile-dangling.py'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-fold.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-fold.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stalefix/MATRIX-NEW.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/s6.run1.txt` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/s6.run2.txt` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/diff.plants.txt` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/stale269/plan.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/clearfix/wrong-oracle-i64-shr-gate.py` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/oracles259/census.out` | named only from inside the residue by .agents/slop/stale269/rows.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/restore.py` | named only from inside the residue by .agents/slop/stale269/restore.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cdiv-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cdiv-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cdiv-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bf16/bf16_gate.c` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/graphrestore/restored.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-late-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-late-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-late-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/repro-paths.out` | named only from inside the residue by .agents/slop/stale71/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-allred-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-allred-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-allred-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/ledger.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/fixures/repro-after.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/repro-before.out` | named only from inside the residue by .agents/slop/fixures/reconcile-dangling.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/decide.py` | named only from inside the residue by .agents/slop/stale269/decide.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-loop-CPU.txt` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-loop-METAL.txt` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-loop-NULL.txt` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-loop.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-loop-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-loop-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-loop-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-cpu.txt` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-lin.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-lin-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-lin-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-lin-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-flip-CPU.txt` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-flip-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-flip-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-flip-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/ledger-after-my-run.tsv` | named only from inside the residue by .agents/slop/canrun/canfail.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boundedfix/AFTER.out` | the two citation belts disagree; git sees ['.agents/slop/difftxt/DECISION.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/spine/03-diff-gate.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-gate-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-gate-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-gate-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/helpers-tc-gate.bd` | named only from inside the residue by .agents/slop/stale71/c-afd395686.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/helpers-tc-gate.bn` | named only from inside the residue by .agents/slop/stale71/c-afd395686.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bw-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bw-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bw-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-binblob.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-binblob-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-binblob-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-binblob-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.filelist` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-commute.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-commute-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-commute-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-commute-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-matmul.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-matmul-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-matmul-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-matmul-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-alu-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-alu-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-alu-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-move-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-move-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-move-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-sym.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sym-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sym-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-buffer.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-buffer-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-buffer-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-buffer-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bit-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bit-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bit-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-where-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-where-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-reduce.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-reduce-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-reduce-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-indexed.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-indexed-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-indexed-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-indexed-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-cast.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cast-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cast-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cast-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-group.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-group-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-group-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-group-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-special.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-special-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-special-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-range.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-rangeflat.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-range-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-range-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-range-3.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-rangeflat-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-rangeflat-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-sink.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sink-1.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sink-2.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/ambig.py` | named only from inside the residue by .agents/slop/stale269/ambig.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/offrepo/reached.tsv` | named only from inside the residue by .agents/slop/offrepo/where.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/menu.py` | named only from inside the residue by .agents/slop/stale269/menu.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boundedfix/BEFORE.out` | the two citation belts disagree; git sees ['.agents/slop/difftxt/DECISION.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/offrepo/plants.tsv` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/nofile.py` | named only from inside the residue by .agents/slop/stale269/nofile.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-i64-shl-gate.py` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-mixin-op-gate.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/account.py` | named only from inside the residue by .agents/slop/stale269/account.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/evidence.py` | the two citation belts disagree; git sees ['.agents/slop/graphcmp-report.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/stalefix/MATRIX-OLD.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/picks.py` | named only from inside the residue by .agents/slop/stale269/picks.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/helpers-tc-gate.rows.err` | named only from inside the residue by .agents/slop/stale71/c-afd395686.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/callprobe.py` | named only from inside the residue by .agents/slop/loopfix/callprobe.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/ranges.py` | named only from inside the residue by .agents/slop/stale269/ranges.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/belt-now/base.rows` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/lin-py-NULL.wire` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/pyside/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/rerun/lin-py-CPU.wire` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendpin/resolve-BEFORE.rows` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/base-lin.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-lin.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-lin.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/set77.rows` | named only from inside the residue by .agents/slop/stale71/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/lin-py-METAL.wire` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/retention-after.out` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-bw.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-bw.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/offrepo/callers.tsv` | named only from inside the residue by .agents/slop/offrepo/callers.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/frac.py` | named only from inside the residue by .agents/slop/arghalf/frac.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/rows.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/fixures/before-verdicts.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/after-verdicts.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bf16/js_stride.mjs` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/census-cached.out` | named only from inside the residue by .agents/slop/stale71/c-afd395686.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-loop.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-beautiful-mnist-gate.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/skipexit/artifacts/SKIP.post-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/arghalf/cargpin.py` | named only from inside the residue by .agents/slop/arghalf/FINDINGS.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/no-txt.out` | named only from inside the residue by .agents/slop/stale71/c-afd395686.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/move.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/move.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/move.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/move.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/move.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/move.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/move.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/move.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/02-bend-matmul.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/skipexit/artifacts/FAIL.post-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/FAIL.pre-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/SKIP.pre-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/arghalf/after/binblob.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/binblob.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/binblob.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/binblob.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/binblob.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/binblob.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/binblob.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/binblob.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/census.sh` | named only from inside the residue by .agents/slop/arghalf/FINDINGS.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-matmul.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-matmul.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/before.err` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/pre.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/opsbend-milestone/milestone.txt` | named only from inside the residue by .agents/slop/opsbend-milestone.sh; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/skipexit/artifacts/GREEN.post-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/GREEN.pre-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/arghalf/reprpin.py` | named only from inside the residue by .agents/slop/arghalf/FINDINGS.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/pinpy.py` | named only from inside the residue by .agents/slop/arghalf/pin-loop.err; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/commute.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/commute.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/commute.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/commute.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/commute.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/commute.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/commute.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/commute.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/alu.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/alu.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/alu.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/alu.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/alu.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/alu.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/alu.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/alu.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/stage3-after.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-sym.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sym.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/06-corpus-figure-after.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/at-135bf0204/plant-measure.json` | named only from inside the residue by .agents/slop/abi4check/plant-measure.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-ew-consts-gate.py` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/blind-spot.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/now/plant-measure.json` | named only from inside the residue by .agents/slop/abi4check/plant-measure.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/orphan-plant.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-wk-f32-gate.py` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/bit.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/bit.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/bit.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/bit.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/bit.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/bit.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/bit.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/bit.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/gate-BEFORE.err` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/gate-AFTER.err` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/where.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/where.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/where.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/where.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/where.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/where.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/where.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/where.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/group.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/group.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/group.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/group.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/group.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/group.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/group.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/group.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-ew-explog-gate.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-flip-METAL.err` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-METAL.err` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-flip-NULL.err` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-NULL.err` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-reduce.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-reduce.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/rss-ledger/2.err` | the two citation belts disagree; git sees ['.agents/slop/f64/run-f64.sh'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/indexed.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/indexed.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/indexed.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/indexed.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/indexed.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/indexed.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/indexed.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/indexed.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/cast.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/cast.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/cast.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/cast.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/cast.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/cast.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/cast.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/cast.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/gate_norm.err` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/pyside/flip.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/buffer.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/buffer.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/buffer.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/buffer.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/buffer.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/buffer.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/buffer.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/buffer.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/run.stderr` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/declared-completeness.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-check.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-matmul.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-reduce.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/disarm-loop.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-loop.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-lin.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sink.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-bw.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sym.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-fold.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/preconds/injectivity.json` | named only from inside the residue by .agents/slop/preconds/injectivity.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/gate_norm-BEFORE.err` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/census-cache-plant.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/01-after-bend-check.out` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/arity.bend` | named only from inside the residue by .agents/slop/arghalf/FINDINGS.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/base-loop.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/base-lin.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-matmul.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-reduce.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-loop.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-lin.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-sink.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-bw.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-sym.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-fold.err` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/range.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/range.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/range.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/range.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/range.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/range.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/range.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/range.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/rangeflat.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/rangeflat.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/rangeflat.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/rangeflat.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/rangeflat.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/rangeflat.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/rangeflat.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/rangeflat.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-sink.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sink.rows` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/special.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/special.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/special.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/base/special.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/final-new/special.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-new/special.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/frozen-old/special.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/v2-new/special.rows` | named only from inside the residue by .agents/slop/loopfix/belt2-final.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/opsbend-milestone/check.txt` | the two citation belts disagree; git sees ['.agents/slop/NVDUP.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/plant-check.out` | named only from inside the residue by .agents/slop/stale71/c-ec08adcfb.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/helpers-tc-gate.bd.err` | named only from inside the residue by .agents/slop/stale71/c-afd395686.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/opsbend-milestone/build.txt` | named only from inside the residue by .agents/slop/opsbend-milestone.sh; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/run.stdout` | named only from inside the residue by .agents/slop/stale71/c-67c32beb8.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/after.rc` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/before.rc` | named only from inside the residue by .agents/slop/unknowns/after.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/skipexit/artifacts/FAIL.post-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/FAIL.pre-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/GREEN.post-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/GREEN.pre-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/SKIP.post-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/SKIP.pre-fix.err` | excluded from this walk by the house rules | `owner-decision` |
