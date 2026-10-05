# THE FIFTH VERDICT: `UNKNOWN`, THE ROWS THAT NEED A HUMAN, AND WHAT WOULD SETTLE EACH

**97 of 366 rows are UNKNOWN and NONE of them is a deletion candidate.**
`sweep` has no place to record "I cannot tell", so these rows were falling through to
`return "DELETE"` -- which is not a verdict, it is the ABSENCE of one, and it is the
only bucket `--apply` destroys.

| path | why it is UNKNOWN | the cheapest test that would resolve it |
|---|---|---|
| `.agents/slop/webgpu_call.fresh.mjs` | named only from inside the residue by .agents/slop/e2e_mm_run.mjs; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/opsbend-milestone/bend-executor` | the two citation belts disagree; git sees ['.agents/slop/opsbend-milestone.sh'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/_cite/cites.json` | named only from inside the residue by .agents/slop/_cite/cite.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/strays/artifacts/ops.staged-blob-24323` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/strays/artifacts/memory.staged-mem-33281` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/strays/artifacts/memory.staged-mem-33929` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/strays/artifacts/memory.staged-mem-44257` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/slopcopies/CITATIONS.tsv` | named only from inside the residue by .agents/slop/slopcopies/MANIFEST.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/variants/gk-opt1.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/sbgate/audit.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/clearfix/harness.py` | named only from inside the residue by .agents/slop/notes/bend2-constraints.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/clearfix-repro.py` | named only from inside the residue by .agents/slop/clearfix/clearfix-repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/pre.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/boundedfix/repro.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/e2estage8/artifacts/live1.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/post.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/live1.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/post.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/graphrestore/union.py` | named only from inside the residue by .agents/slop/graphrestore/RESTORE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/s6.run1.txt` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/s6.run2.txt` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/diff.plants.txt` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/bf16/bf16_gate.c` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/ishr/base.bd.rows` | named only from inside the residue by .agents/slop/ishr/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/graphrestore/restored.py` | named only from inside the residue by .agents/slop/graphrestore/portside.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boundedfix/bounded-prefix.py` | named only from inside the residue by .agents/slop/boundedfix/REPRO.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/variants/FIX-mixin-op-gate-disagree.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/NOW-mixin-op-gate-disagree.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/smoke-disagree.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/OPT2-mixin-op-gate-drift.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/OPT2-mixin-op-gate-green.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/FIX-mixin-op-gate-drift.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/FIX-mixin-op-gate-green.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/NOW-mixin-op-gate-drift.py` | named only from inside the residue by .agents/slop/clearfix/clearfix-repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/variants/NOW-mixin-op-gate-green.py` | named only from inside the residue by .agents/slop/clearfix/clearfix-repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/variants/smoke-green.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/freeze.py` | named only from inside the residue by .agents/slop/clearfix/clearfix-repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/variants/FIX-beautiful-mnist-gate-disagree.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/NOW-beautiful-mnist-gate-disagree.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/OPT2-beautiful-mnist-gate-drift.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/OPT2-beautiful-mnist-gate-green.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/FIX-beautiful-mnist-gate-drift.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/FIX-beautiful-mnist-gate-green.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/NOW-beautiful-mnist-gate-drift.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/clearfix/variants/NOW-beautiful-mnist-gate-green.py` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/fixures/repro-before.out` | named only from inside the residue by .agents/slop/fixures/reconcile-dangling.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/REPRO.rows` | named only from inside the residue by .agents/slop/boundedfix/repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/diff.live2.txt` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/boundedfix/REPRO.rows` | named only from inside the residue by .agents/slop/boundedfix/repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boundedfix/AFTER.out` | untracked, and nothing renders or names it | `commit-or-drop` |
| `.agents/slop/e2estage8/artifacts/diff.live.txt` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/graphrestore/portside.py` | named only from inside the residue by .agents/slop/graphrestore/RESTORE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/oracle-beautiful-mnist-gate.sh` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4/path-verdict.rows` | named only from inside the residue by .agents/slop/abi4/README.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bf16/dtype_js_probe.mjs` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-mixin-op-gate.py` | named only from inside the residue by .agents/slop/clearfix/variants/FIX-mixin-op-gate-disagree.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/gk/gk-artifacts/now-mixin-op-gate/bd.rows` | the two citation belts disagree; git sees ['.agents/slop/ishr/REPORT.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/clearfix/gk/gk-artifacts/now-mixin-op-gate/bn.rows` | named only from inside the residue by .agents/slop/clearfix/REPRO.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/strays-root/.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/difftxt/rename-experiment.out` | named only from inside the residue by .agents/slop/difftxt/DECISION.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bf16/js_stride.mjs` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-beautiful-mnist-gate.py` | named only from inside the residue by .agents/slop/clearfix/variants/FIX-beautiful-mnist-gate-disagree.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/docs-agree-BEFORE.out` | named only from inside the residue by .agents/slop/txtgen/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/pre.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/opsbend-milestone/milestone.txt` | named only from inside the residue by .agents/slop/opsbend-milestone.sh; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/docs-agree-AFTER.out` | named only from inside the residue by .agents/slop/txtgen/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stalefix/PLANT.rows` | named only from inside the residue by .agents/slop/stalefix/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/04-corpus-figure-before.out` | named only from inside the residue by .agents/slop/spine/SPINE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/10-corpus-figure-final.out` | named only from inside the residue by .agents/slop/spine/SPINE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stalefix/oracle-short.py` | named only from inside the residue by .agents/slop/stalefix/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/difftxt/repro-AFTER.out` | named only from inside the residue by .agents/slop/difftxt/DECISION.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/difftxt/repro-BEFORE.out` | named only from inside the residue by .agents/slop/difftxt/DECISION.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/07-option-b-bend-check.out` | named only from inside the residue by .agents/slop/spine/SPINE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/00-before-bend-check.out` | named only from inside the residue by .agents/slop/spine/SPINE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stalefix/broken.bend` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stalefix/green.bend` | named only from inside the residue by .agents/slop/stalefix/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/08-final-bend-check.out` | named only from inside the residue by .agents/slop/spine/SPINE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4/probe/wrap_fp8fr.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/wrap_fp8to.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/fp8fr.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/wrap_bf16.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/wrap_fp16.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/bf16.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/fp8to.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/min_base.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `runs/portexec/cpython-clang_kernel.c` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/abi4/probe/fp16.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/min_D.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/min_M.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `.agents/slop/abi4/probe/min_rel.bend` | a TOOL whose own directory has no committed report | `commit-the-report-that-explains-it` |
| `runs/portexec/cpython-base_kernel.c` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/abi4/probe/min_prim.bend` | named only from inside the residue by .agents/slop/abi4/README.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/opsbend-milestone/check.txt` | the two citation belts disagree; git sees ['.agents/slop/NVDUP.md'], the scanner sees [] | `belts-disagree` |
| `runs/portexec/cpython-vec4_typedef.c` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/opsbend-milestone/build.txt` | named only from inside the residue by .agents/slop/opsbend-milestone.sh; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/05-differ-run.out` | named only from inside the residue by .agents/slop/spine/SPINE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/09-differ-run-final.out` | named only from inside the residue by .agents/slop/spine/SPINE.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
