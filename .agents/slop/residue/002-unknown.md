# THE FIFTH VERDICT: `UNKNOWN`, THE ROWS THAT NEED A HUMAN, AND WHAT WOULD SETTLE EACH

**1296 of 1745 rows are UNKNOWN and NONE of them is a deletion candidate.**
`sweep` has no place to record "I cannot tell", so these rows were falling through to
`return "DELETE"` -- which is not a verdict, it is the ABSENCE of one, and it is the
only bucket `--apply` destroys.

| path | why it is UNKNOWN | the cheapest test that would resolve it |
|---|---|---|
| `.agents/slop/opsbend-milestone/bend-executor` | the two citation belts disagree; git sees ['.agents/slop/bendperf/REPORT.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gitignore/after-lsfiles.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/nums.tsv` | named only from inside the residue by .agents/slop/livenum/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/cites-after.tsv` | named only from inside the residue by .agents/slop/livenum/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/cites-before.tsv` | named only from inside the residue by .agents/slop/livenum/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/adjudicated-STALE-LINE.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/sloptxt/eyeball.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/dd-gate.rows` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/dd-gate-base-182.rows` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/added.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/declared472/moved.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/ledger.tsv` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/reader-fork-census.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/dd-gate-base-172.rows` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/plan-STALE-LINE.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/restore-plan.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/pkt-0.in` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/pkt-64.in` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/name-census-report.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/emptyblob/last40.numstat` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/declared472/census_split.json` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_uops_stats.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_marker-audit.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/checks_marker-audit.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/portmarkers/guide.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/backlog/staged-before.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_linearizer.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_linearizer.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/plan.tsv` | the two citation belts disagree; git sees ['.agents/slop/stale269/plan.py'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_llm_server.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/skipped.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/othercopies.json` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-after.sha256` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.copy.sha256` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.sha256` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/py-D/D7-conf.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D7-conf.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/py-D/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D7-conf.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D7-conf.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_custom_kernel.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/strays-root/closure.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/stale269/gate-baseline.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/claims.tsv` | named only from inside the residue by .agents/slop/livenum/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/table.out` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/status-1.rows` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/live1.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/shfinish/diffpy.py` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/post.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/live1.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/post.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/differverdict/shell-D/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_hcq2.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-before.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-frozen-new.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-probe.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-v2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-fold.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-fold.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/investigate.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_compile_failures.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/quiesce/snapshot.py` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/stale71/c-67c32beb8.rows` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/agend/spec2.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/dup/stage1-census.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_real_world.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_real_world.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stalefix/MATRIX-NEW.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/s6.run1.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/figurefix/plant/D-live/D3-control-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D3-control-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/s6.run2.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/rerun/D-before/D3-control-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D3-control-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_function.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_function.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flagtable/final_compare.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_attention.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_assign.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_assign.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D3-control-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D3-control-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_allreduce.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D3-control-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D3-control-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_real_world.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendwire/reach-old-test_attention.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_attention.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D3-control-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D3-control-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_allreduce.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_schedule.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_symbolic_tensor.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_function.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_winograd.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/livenum/live.rows` | the two citation belts disagree; git sees ['.agents/slop/agend2/REPLACEMENTS.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/e2estage8/artifacts/diff.plants.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/coindependent/surface.out` | named only from inside the residue by .agents/slop/coindependent/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/jsbf16/probe.mjs` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/classified.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/flipblock/blast.rows` | named only from inside the residue by .agents/slop/flipblock/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-i64-shr-gate.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_both-census.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-cdiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-cdiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cdiv-1.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cdiv-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cdiv-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bf16/bf16_gate.c` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_multitensor.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/adjudicated-WRONG-FILE.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/graphrestore/restored.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-late.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-late.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-late-1.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-late-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-late-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-dtype.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D5-plant-dtype.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/py-D/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_arange.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_arange.out` | named only from inside the residue by .agents/slop/prune4/HANDOFF.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_repro-paths.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citemass/resolved-now.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/pinindep/indep.py` | named only from inside the residue by .agents/slop/pinindep/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/coindependent/vocab.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/coindependent/pairs.py` | named only from inside the residue by .agents/slop/coindependent/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/pinindep/sens.py` | named only from inside the residue by .agents/slop/pinindep/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-allred.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-allred.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-allred-1.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-allred-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-allred-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_arange.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/probe-arange-bend.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/ledger.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/orcdecide/retired/basenames2.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-shape.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D5-plant-shape.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/pinindep/mtime.py` | named only from inside the residue by .agents/slop/pinindep/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/repro-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/repro-before.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/decide.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-loop-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-loop-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-loop-CPU.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-loop-METAL.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-loop-NULL.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-loop.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-loop-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-loop-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-loop-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/pinindep/redundancy.py` | named only from inside the residue by .agents/slop/indextree/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_mnist_dataset.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-lin.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-lin.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-cpu.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-lin.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-lin-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-lin-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-lin-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_uops.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/coindependent/twostate.py` | named only from inside the residue by .agents/slop/coindependent/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun2/retention-before.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun2/retention-after-run.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-srcswap.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D6-matmul-ordered.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D5-plant-srcswap.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D6-matmul-ordered.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D6-commute-ordered.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-commute-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-commute-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D6-commute-ordered.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-commute-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-commute-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun2/retention-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-flip.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-flip.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-flip-CPU.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-flip-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-flip-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-flip-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/run-gates-copy.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_transcendental.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/ledger-after-my-run.tsv` | named only from inside the residue by .agents/slop/canrun/canfail.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-bytes.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D5-plant-bytes.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/run-graphcmp-ok.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/diff.live2.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/gatehealth/after-syn-clean.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-opt.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D5-plant-opt.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boundedfix/AFTER.out` | the two citation belts disagree; git sees ['.agents/slop/difftxt/DECISION.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/orcdecide/sweep.out` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-gate-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-gate-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-gate-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-gate-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-gate.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-gate-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-gate-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-gate-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/helpers-tc-gate.bn` | the two citation belts disagree; git sees ['.agents/slop/backlog/staged-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-loop-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-loop-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-pyuop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D5-plant-pyuop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citemass/cites-now.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-bw.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-bw.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bw-1.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bw-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bw-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-binblob.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-binblob-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-binblob-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-binblob-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.filelist` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D6-commute-equiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D6-commute-equiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-commute.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-commute.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/nvrows/census-MATRIX.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-commute.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-commute-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-commute-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-commute-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D6-matmul-equiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D6-matmul-equiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-matmul.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-matmul-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-matmul-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-matmul-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-alu.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-alu.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-move.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-move.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-alu-1.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-alu-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-alu-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-move-1.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-move-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-move-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-sym.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-sym-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-sym-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-sym.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-sym-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-sym-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-sym.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sym-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sym-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sym-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-buffer.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-buffer.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-buffer.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-buffer-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-buffer-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-buffer-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-bit.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-bit.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-where.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-where.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bit-1.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bit-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bit-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-where-1.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-where-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-where-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-reduce.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-reduce.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-indexed.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-indexed.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-reduce.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-reduce-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-reduce-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-reduce-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-indexed.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-indexed-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-indexed-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-indexed-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-cast.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-cast.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-group-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-group-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-group-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-group-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-cast.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cast-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cast-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cast-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-group.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-group-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-group-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-group-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-special.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-special.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-rangeflat.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-rangeflat.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-sink.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-sink.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-special.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-special-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-special-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-special-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-range.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-rangeflat.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-range-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-range-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-range-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-rangeflat-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-rangeflat-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-rangeflat-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-sink.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sink-1.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sink-2.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sink-3.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/ambig.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/menu.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boundedfix/BEFORE.out` | the two citation belts disagree; git sees ['.agents/slop/difftxt/DECISION.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/surface/report.out` | the two citation belts disagree; git sees ['.agents/slop/backlog/staged-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/offrepo/plants.tsv` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_render-gate-oracle.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/diff.live.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/gatehealth/run-gates-empty.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcfix/plant_states.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/nofile.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/after-live.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-i64-shl-gate.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/claims.py` | the two citation belts disagree; git sees ['.agents/UPSTREAM.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/clearfix/wrong-oracle-mixin-op-gate.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/clauseiv-nogate.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/account.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/markers.before.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/quiesce/freeze-check.py` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/c-afd395686.rows` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/agend/spec3.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/markers.after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/evidence.py` | the two citation belts disagree; git sees ['.agents/slop/graphcmp-report.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/instrepair/run/substrate-audit.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stalefix/MATRIX-OLD.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/picks.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipblock/blast.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/livenum/check.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_uop_graph.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/gt.rows.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/foldgap/population-after-edit.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/run34/disagree-gate.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/callprobe.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/live.py` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/substrate/artifacts/smoke/python.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/prune3/strays-keep.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/live-c.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/i64shl/magicgu.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/nostraysshape/measure2.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/cites2/instrument.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/belt2-frozen.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/tensor.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/ranges.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/post-bend-lin.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/lin-py-NULL.wire` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/py-lin.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/pyside/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D2-canon-py-lin.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/py/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/py/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/rerun/D-before/D2-canon-py-lin.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/lin-py-CPU.wire` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendpin/resolve-BEFORE.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/base-lin.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/lin.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-lin.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-lin.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/set-all-raw.rows` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/pkt-16.in` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/lin-py-METAL.wire` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_gen_float4.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/retention-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txt398/census.final.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/substrate/artifacts/smoke/python.norm` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/emptyblob/analysis.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_schedule.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_schedule.out` | named only from inside the residue by .agents/slop/prune4/HANDOFF.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/bw.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-bw.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-bw.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/offrepo/callers.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendpin/resolve-AFTER.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_symbolic_tensor.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_symbolic_tensor.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_sweep.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_sweep.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/fixures/before-verdicts.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/after-verdicts.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/belt2-final.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/20-rss-ledger.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/bounded-selftest.sh.0.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flagtable/verify_unverifiable.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/prune2/copies.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/lint_demo.sh.0.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/runfinal/quietwatch.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/after-notxt.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/before-notxt.out` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bf16/js_stride.mjs` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/cidsweep.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_graphcmp-census-audit.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/checkshells/runs/demo.sh.0.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/after-live-c.out` | named only from inside the residue by .agents/slop/exitzero/verify.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/live-c.out` | the two citation belts disagree; git sees ['.agents/slop/exitzero/verify.py'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/exitzero/before-1-plant-full.out` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/defect1-plant-full.out` | named only from inside the residue by .agents/slop/exitzero/repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/before-2-no-instrument-forced.out` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/defect2-no-instrument-forced.out` | named only from inside the residue by .agents/slop/exitzero/repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcfix/repro2.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/census-cached.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-loop.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/loop-before.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after-loop.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/rss.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citeresolve/hist.py` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-beautiful-mnist-gate.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txt398/no-txt.final.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_no-txt.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_no-txt.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_no-txt.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/stale71/no-txt.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/capture.py` | the two citation belts disagree; git sees ['.agents/slop/NVDUP.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/move.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/citeresolve/anchors.tsv` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/02-bend-matmul.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_al-verdict.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_al-verdict.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_al-verdict.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/shfinish/triage.py` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_corpus-figure.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/instrepair/run/cstyle-shapes-selftest.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/c-ec08adcfb.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/before-1-plant-n.out` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/defect1-plant-n.out` | named only from inside the residue by .agents/slop/exitzero/repro.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/binblob.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/exitzero/after-1-plant-full.out` | named only from inside the residue by .agents/slop/exitzero/verify.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/after-1-plant-n.out` | named only from inside the residue by .agents/slop/exitzero/verify.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/py-D/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/instrepair/run/cstyle-shapes-selftest.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/after-2-no-instrument-forced.out` | named only from inside the residue by .agents/slop/exitzero/verify.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/after-port-defect2.out` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/oracle-defect2.out` | named only from inside the residue by .agents/slop/exitzero/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_corpus-figure.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-late.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-late.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/whyred.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/allred.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/cdiv.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/late.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/allred.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/cdiv.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/late.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/allred.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/cdiv.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/late.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/allred.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/cdiv.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/late.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/allred.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/cdiv.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/late.rows` | the two citation belts disagree; git sees ['.agents/slop/bendsuite/git-status-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-matmul.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-matmul.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/runfinal/substrate-matmul.out` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/pin-loop.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-allred.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-allred.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/pre.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/lostinst/livecite.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/run34/corpus-figure.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-cdiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-cdiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D8b-cpython-dbg1-reachability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D8b-cpython-dbg1-reachability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/opsbend-milestone/milestone.rows` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/cidsweep.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/pinpy.py` | named only from inside the residue by .agents/slop/arghalf/pin-loop.err; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/after-oracle-defect2.out` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/10-fraction.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendpin/regressions.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/instrepair/run/pin-tables.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun2/disagree-gate-after-run.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun2/disagree-gate-after.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_simplify_valid_idx.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun2/corpus-figure-before.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_validate_oob.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_linearizer_rewrite.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcfix/skipexit-repro.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_dtype_spec.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_graph_rewrite.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/bmn.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/bmn2.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/mixin.sh.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/commute.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/prune2/inta.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/adjudicated-PAST-EOF.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/adjudicated.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/gate.rows` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/rerun2/corpus-figure-after.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_uop_symbolic.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/tensor.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_edgecases.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/alu.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/coindependent/twostate.rows` | named only from inside the residue by .agents/slop/coindependent/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_gradient.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_linearizer_failures.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_tqdm.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_allreduce.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_tensor.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_gpudims.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendpin/pin_check.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_ops.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/substrate3/node.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/stage3-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/sym.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-sym.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sym.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_call.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_norm_check.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_norm_check.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_cli.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/06-corpus-figure-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-ew-consts-gate.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/blind-spot.out` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/summary.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_ops-core-oracle.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/belt_inputs.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_winograd.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-test_winograd.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_dup-gate.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_dup-gate.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/dup-gate.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/orphan-plant.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_corpus-figure.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censroot/after-census.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/buffergraphs/emit-mselect.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-wk-f32-gate.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/final-norm_check.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/norm_check.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_norm_check.py.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/bit.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/buffergraphs/emit-mstack.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/freedreport.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_dtype.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/perdir.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/buffergraphs/emit-stage.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/tree-sha.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_env-precond.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rosterwire/oldcount.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/deadclause/plants-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/ccdead2/emit.err` | the two citation belts disagree; git sees ['.agents/slop/prune4/dups.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/txtgen/gate-BEFORE.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/gate-AFTER.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/where.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/fwdref.bend` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/group.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/portmarkers/proof.plant.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/deadclause/plants-before.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/buffergraphs/emit-custom_function.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-ew-explog-gate.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-flip-METAL.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-METAL.err` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-flip-NULL.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-NULL.err` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/pkt-4.in` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/reduce.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-reduce.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-reduce.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/rss-ledger/1.err` | the two citation belts disagree; git sees ['.agents/slop/gitignore/added.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/rss-ledger/2.err` | the two citation belts disagree; git sees ['.agents/slop/f64/run-f64.sh'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/rss-ledger/3.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/rss-ledger/6.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/msgdiff/range.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/indexed.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/gates_wk-eval-oracle.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcfix/plant_states.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/ordering.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-canon-bend-flip.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-canon-bend-flip.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_ew-consts-oracle.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_coverage.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_corpus-figure.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/cast.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/txtgen/gate_norm.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/jsfix.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/instrepair/run/mutate-dm.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/emptyact/gate-py3.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_gate.py.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/pyside/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D2-canon-py-flip.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof2.after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/py/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/py/flip.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/rerun/D-before/D2-canon-py-flip.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof.after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof.before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/proof.after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/proof.after1.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/proof.before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/laws.after.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/laws.before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/laws.after.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/py-loop.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/emptyblob/classify.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/py-lin.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/abi4.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/buffer.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/oracletxt/shape_of_stale.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/plant-hermetic.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/nums.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_gate_dtype.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_devpin.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_devpin.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_devpin.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/orcdecide/retired/manifest-write.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/rangeflat.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/binblob.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/allred.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/commute.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/indexed.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/matmul.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/special.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/plant-helpers-tc.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/buffer.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/reduce.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/rerun/run.stderr` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/cdiv.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/group.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/late.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/loop.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/move.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/range.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/where.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/cast.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/flip.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/lin.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/sink.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/alu.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/bit.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/bw.err` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/sym.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/checks_test_rewrite_bottom_up_gate.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/quiesce/watch.out` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_graphcmp-census-audit.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/beltA.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/post.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/pre.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/rangeflat.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/binblob.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/allred.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/commute.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/indexed.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/matmul.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/special.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/buffer.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/reduce.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/cdiv.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/group.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/late.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/loop.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/move.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/range.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/where.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/cast.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/flip.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/lin.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/sink.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/alu.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/bit.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/bw.err` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/sym.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/quiesce/watch2.out` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/full-fit.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/declared-completeness.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/gate.sh.0.err` | the two citation belts disagree; git sees ['.agents/slop/prune4/dups.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_llama.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_tensor_uop_mixin.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-check.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-matmul.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-reduce.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/disarm-loop.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-loop.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-lin.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sink.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-bw.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sym.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-fold.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/preconds/injectivity.json` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/gate_norm-BEFORE.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_run.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/dup-census.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/dup-gate2.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/final-dup-gate.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_dup-gate.py.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/herm.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censroot/after-hermetic.err` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_hermetic-census.py.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_fw_live.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_fw_live.py.out.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_fw_live.py.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_romless.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/probe-pristine.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/census-cache-plant.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_cli.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/01-after-bend-check.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_compile.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_compile.py.out.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_compile.py.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censroot/before-hermetic.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/runfinal/quiet1.out` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censusred/refusal.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/probe-patched.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_sz.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_sz.py.out.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_sz.py.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_run.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_run.py.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-lin.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-lin.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censroot/before-census.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/rangeflat.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/rangeflat.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/rangeflat.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/binblob.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/binblob.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/binblob.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-flip.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-fold-old.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-fold-probe.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-fold-v2.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/rss-ledger/4.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/rss-ledger/5.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/rss-ledger/retry.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-flip.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/allred.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/commute.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/indexed.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/matmul.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/special.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/allred.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/commute.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/indexed.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/matmul.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/special.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/allred.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/commute.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/indexed.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/matmul.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/special.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/buffer.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/reduce.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/buffer.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/reduce.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/buffer.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/reduce.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after-loop.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/cdiv.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/group.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/late.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/loop.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/move.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/range.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/where.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/cdiv.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/group.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/late.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/loop.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/move.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/range.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/where.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/base-loop.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/cdiv.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/group.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/late.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/loop.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/move.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/range.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/where.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/rss.tmp` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/cast.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/flip.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/lin.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/sink.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/cast.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/flip.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/lin.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/sink.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/base-lin.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/cast.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/flip.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/lin.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/sink.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/chk-postrange.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-insprobe-old.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-insprobe-v2.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-insprobe.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/alu.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/bit.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/bw.err` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after/sym.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/alu.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/bit.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after2/bw.err` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/sym.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/alu.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/bit.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/before/bw.err` | the two citation belts disagree; git sees ['.agents/slop/stale71/c-ec08adcfb.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/sym.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/beltB.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/beltB2.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-gcmp-final.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-gcmp-old.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-gcmp-v2.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_helpers.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_viz.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-gcmp-new.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/probe-patched.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/probe-pristine.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.final.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/check-after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/check-final.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/manifest-prove.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/ops-check.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citeresolve/classify.err` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-matmul.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/runfinal/substrate-matmul.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-reduce.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-loop.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/post-bend-lin.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-lin.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-sink.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/fbuild-base.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-bw.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-sym.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_gate_dtype.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/build-base.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-fold.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/launch-64/ARGV` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendperf/launch-ones-000/argv.json` | named only from inside the residue by .agents/slop/bendperf/probe.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/scan-before.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_no-shrink.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_no-shrink.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_no-shrink.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/agend2/tools.out` | named only from inside the residue by .agents/slop/agend2/measure.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_ew-explog-oracle.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_lint_demo.sh.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/range.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/agend/guide.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/checkshells/runs/sbgate-fix-absent.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/rangeflat.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/portmarkers/guide.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/help.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/checkshells/runs/sb-gate.sh.1.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/sink.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopq/base-sink.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sink.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/wt-sync.sh.0.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/before-state.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/after-state.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/now-state.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/after2/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/arghalf/before/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/after-out/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/linfix/before-out/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/base/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/final-new/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-new/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/frozen-old/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/v2-new/special.rows` | the two citation belts disagree; git sees ['.agents/slop/declared472/PLAN.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_process_replay.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_process_replay.py.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-v3.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_devgate.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/00-bytes-after.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/00-bytes-before.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-probe.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/pin-loop.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-frozen-new.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-frozen-old.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/bmn.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/bmn2.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-v2.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_no-strays.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_no-strays.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_no-strays.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/shfinish/ref/mixin.sh.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_autogen.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_device.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_disk_cache.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_dtype_weak.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_method_cache.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_pattern_matcher.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_tensor_metadata.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_uop_vmin_vmax.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_renderer_failures.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_tensor_uop_representation.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_test_rewrite_bottom_up_gate.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_const_folding.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_encodings.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_gc.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_indexing.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_llm_tokenizer.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_memory_planner.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_microbenchmarks.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_rearrange_einops.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_setitem_schedule.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_symbolic_failures.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_system_pci_scan_bus.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_uop_resolve.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/sb-gate.sh.0.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/sbgate-fix-present.out` | named only from inside the residue by .agents/slop/gitignore/added.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_wk-cd-oracle.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_elf.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_gguf.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_hashing.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_hcq_iface.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_invalid_tensor.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_isel.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_llm_mla.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_nn.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_objc.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_pickle.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_process_replay.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_randomness.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_resnet.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_rewrite_bottom_up_gate.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_schedule_cache.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_setitem.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_symbolic_ops.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_tensor_io.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_tensor_variable.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_transcendental_helpers.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_uop_repr.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_upat_compile.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/agend/pytest.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bullets/pytest.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/agend/mypy.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/agend/ruffvenv.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bullets/mypy.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bullets/ruffvenv.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/quiesce/writes.tsv` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/quiesce/writes2.tsv` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citeresolve/anchors.err` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/EXE` | the two citation belts disagree; git sees ['.agents/slop/agend/ruff.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendwire/launch-64/EXE` | the two citation belts disagree; git sees ['.agents/slop/agend/ruff.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_bounded.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/classify.err` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/after-graphcmp-broken.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/after-graphcmp-ok.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/after-live.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/after-syn-clean.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/after-syn-plant.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/clauseiv-nogate.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/run-gates-copy.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/run-gates-empty.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/run-graphcmp-broken.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/run-graphcmp-ok.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/ops-check.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.after.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.final.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/chk-postrange.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/check-after.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/check-final.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-check.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_process_replay.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_classify.sh.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citeresolve/counts-counts.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-rangeflat.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-rangeflat.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/named.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-commute.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-indexed.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-special.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-commute.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-indexed.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-special.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citemass/scan-now.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citeresolve/hist.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/cites2/final-counts.err` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-buffer.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-reduce.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-buffer.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-reduce.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-move.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-where.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-move.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-where.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-cast.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-sink.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-cast.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-sink.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-alu.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-bit.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-bw.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-sym.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/helpers-tc-gate.bd.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/msgdiff/range.out` | the two citation belts disagree; git sees ['.agents/TOOLS.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/rerun/D-before/D2-cmp-alu.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-bit.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-bw.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-sym.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citemass/resolve-now.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/foldgap/fold.md5.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_ew-explog-oracle.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/claims.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/jjhazard/heartbeat.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/jsfix.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/run.stdout` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/deadclause/residue-plant.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_wk-cd-oracle.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/cites-after.err` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/cites-before.err` | named only from inside the residue by .agents/slop/prune4/dups.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendperf/launch-ones-000/wall` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/fixures/after.rc` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/before.rc` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_render-gate-oracle.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/jjhazard/scratch.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/jjhazard/probe-b.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D10-zerorow-guard.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D8-dbg-012.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D8-dbg-03.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D10-zerorow-guard.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D8-dbg-012.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D8-dbg-03.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/substrate3/pop.before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_assign.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_linearizer.out` | the two citation belts disagree; git sees ['.agents/slop/prune4/HANDOFF.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/substrate/artifacts/smoke/python.rc` | excluded from this walk by the house rules | `owner-decision` |
