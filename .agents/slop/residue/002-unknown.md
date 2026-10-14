# THE FIFTH VERDICT: `UNKNOWN`, THE ROWS THAT NEED A HUMAN, AND WHAT WOULD SETTLE EACH

**1794 of 2414 rows are UNKNOWN and NONE of them is a deletion candidate.**
`sweep` has no place to record "I cannot tell", so these rows were falling through to
`return "DELETE"` -- which is not a verdict, it is the ABSENCE of one, and it is the
only bucket `--apply` destroys.

| path | why it is UNKNOWN | the cheapest test that would resolve it |
|---|---|---|
| `.agents/slop/opsbend-milestone/bend-executor` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gitignore/after-lsfiles.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/nums.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/cites-after.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/cites-before.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/movement.AFTER.bend` | named only from inside the residue by .agents/slop/concise/AFTER.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/prune4/dups.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/adjudicated-STALE-LINE.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/sloptxt/eyeball.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/dd-gate.rows` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/dd-gate-base-182.rows` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/added.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/declared472/moved.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/ledger.tsv` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/msgdiff2/pct-whole.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/reader-fork-census.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/concise/AFTER.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/dd-gate-base-172.rows` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/plan-STALE-LINE.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/restore-plan.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/pkt-0.in` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/pkt-64.in` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/name-census-report.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/emptyblob/last40.numstat` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/declared472/census_split.json` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_uops_stats.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/v_checks_marker-audit.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/diffrule/survey.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_marker-audit.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/portmarkers/guide.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/backlog/staged-before.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d1-derive.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-old-test_linearizer.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_linearizer.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/plan.tsv` | the two citation belts disagree; git sees ['.agents/slop/stale269/plan.py'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/bendsuite/bend/test_llm_server.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/skipped.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/diffrule/porting.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/oracles259/othercopies.json` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/othercopies.json` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-after.sha256` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.copy.sha256` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.sha256` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitsurvey/advisory.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/py-D/D7-conf.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D7-conf.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/refusals/refusal-read.py` | named only from inside the residue by .agents/slop/diffrule/survey.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/refusals/discover.out` | named only from inside the residue by .agents/slop/refusals/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/py-D/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D0-ops-probe.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/after-report.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D7-conf.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D7-conf.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_custom_kernel.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D0-ops-probe.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/baseline-report.out` | named only from inside the residue by .agents/slop/untrack/census-from.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/strays-root/closure.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/stale269/gate-baseline.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2epy/artifacts/live.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/differverdict/shell-D/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/claims.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/midrun/midrun.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whyarms/armsites.json` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale71/table.out` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/synonyms/twelfth.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale71/status-1.rows` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/live1.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/shfinish/diffpy.py` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/post.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/live1.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2estage8/artifacts/post.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/differverdict/shell-D/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D4-cross-range.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_hcq2.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/warm-oracle/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipthird/e2-base-tinybendygrad_uop_fold.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/mv-AFTER.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mv-BEFORE.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mv-PRISTINE.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mv-ZERO.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/fold-gate-PRE.rows` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bitcastrow/base.rows` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/loopfix/selftest-before.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/selftest-frozen-new.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/selftest-probe.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/selftest-v2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-fold.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-fold.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/diffrule/separation.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gitignore/investigate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/refusals/refusals.rows` | named only from inside the residue by .agents/slop/refusals/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_compile_failures.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x4-fix.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D8-dbg-012.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d2-argv.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/base-render.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e2-base-tinybendygrad_uop_render.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale71/c-67c32beb8.rows` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d6-decisive.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/agend/spec2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/after2-gate-surface.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/final-gate-surface.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/dup/stage1-census.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/msgdiff2/pct.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/base-gate-surface.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_real_world.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_real_world.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitsurvey/space.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stalefix/MATRIX-NEW.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2estage8/artifacts/s6.run1.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/modulerefuse/fixmeasure.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D3-control-gate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D3-control-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/s6.run2.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/rerun/D-before/D3-control-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D3-control-loop.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-old-test_function.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_function.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flagtable/final_compare.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_attention.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-old-test_assign.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_assign.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D3-control-binblob.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D3-control-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_allreduce.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D3-control-matmul.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D3-control-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipthird/e2-base-tinybendygrad_uop_ops.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_real_world.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-old-test_attention.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_attention.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/declare/COMPARE.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D3-control-group.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D3-control-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_allreduce.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/twelfth2.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x6-plant.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_schedule.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_symbolic_tensor.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_function.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_winograd.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d9-broken.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/live.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2estage8/artifacts/diff.plants.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/coindependent/surface.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/plantthe46/coindep-surface-now.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/boolexit/class.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/shapes.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/declaretwo/rename-plan.rows` | named only from inside the residue by .agents/slop/declaretwo/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boolexit/residual.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x3-class.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/jsbf16/probe.mjs` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/135bf0204-run.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipblock/blast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/clearfix/wrong-oracle-i64-shr-gate.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x1-derive.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitsurvey/space.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d3-census.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d5-subjects.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitcode/subject.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/checks_both-census.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-cdiv.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-cdiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cdiv-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-cdiv-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-cdiv-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e2-base-tinybendygrad_schedule_prepare.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bf16/bf16_gate.c` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_multitensor.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/adjudicated-WRONG-FILE.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/graphrestore/restored.py` | named only from inside the residue by .agents/slop/agend/ruff.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-late.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-late.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-late-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-late-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-late-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D0-coverage-census.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/shell-D/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/LEDGER.SNAPSHOT.tsv` | named only from inside the residue by .agents/slop/untrack/census-from.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-dtype.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D5-plant-dtype.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/py-D/D4-cross-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/diffrule/price.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d8-asymmetry.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-old-test_arange.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_arange.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/diffrule/separation.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/checks_repro-paths.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/citemass/resolved-now.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/pinindep/indep.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/pinindep/sens.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-allred.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-allred.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-allred-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-allred-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-allred-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d1-derive.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D8-dbg-03.out` | named only from inside the residue by .agents/slop/capstream/PLAN.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_arange.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/probe-arange-bend.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/shell-D/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boolexit/class.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/plantthe46/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/ledger.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/oracles259/basenames2.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/basenames2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-shape.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D5-plant-shape.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/pinindep/mtime.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/fixures/repro-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/repro-before.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/diffrule/triage.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d4-vacuous.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/decide.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-loop-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-loop-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitsurvey/shellentry.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/probe-loop-CPU.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-loop-METAL.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-loop-NULL.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-loop.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-loop-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-loop-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-loop-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_mnist_dataset.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-lin.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-lin.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-cpu.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-lin.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-lin-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-lin-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-lin-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_uops.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/prune4/dircopies.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/boolexit/residual.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/slowgate/attribute.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/coindependent/twostate.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun2/retention-before.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun2/retention-after-run.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d7-run.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x5-vacuous.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/control.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/flip-PRISTINE.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/final-flip.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-srcswap.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D6-matmul-ordered.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D5-plant-srcswap.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D6-matmul-ordered.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d3-census.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D6-commute-ordered.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-commute-a.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-commute-b.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D6-commute-ordered.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-commute-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-commute-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun2/retention-after.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-sym1.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D5-plant-sym1.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-flip.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-flip.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-flip-CPU.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-flip-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-flip-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-flip-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/run-gates-copy.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_transcendental.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/shapes.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/ledger-after-my-run.tsv` | named only from inside the residue by .agents/slop/canrun/canfail.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-bytes.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D5-plant-bytes.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatehealth/run-graphcmp-ok.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2estage8/artifacts/diff.live2.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/gatehealth/after-syn-clean.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-opt.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D5-plant-opt.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boundedfix/AFTER.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/orcdecide/sweep.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/twopass/diff-loop.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/summary.json'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-gate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-gate-a.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-gate-b.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-gate-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-gate-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-gate.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-gate-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-gate-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-gate-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-bytediff.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/helpers-tc-gate.bn` | the two citation belts disagree; git sees ['.agents/slop/backlog/staged-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/twopass/diff-bw.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-loop.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-loop-a.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-loop-b.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/boolexit/livehunt.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D5-plant-pyuop.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D5-plant-pyuop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d6-decisive.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/citemass/cites-now.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d7-run.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-bw.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-bw.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bw-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-bw-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-bw-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/diffrule/survey.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/flip-handoff.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-binblob.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/after-msgdiff.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/twopass/diff-matmul.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/spine/03-diff-binblob.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-binblob-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-binblob-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-binblob-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/twopass/diff-move.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before.filelist` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/diff-sym.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D6-commute-equiv.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D6-commute-equiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-commute.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-commute.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/nvrows/census-MATRIX.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-commute.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-commute-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-commute-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-commute-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D6-matmul-equiv.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D6-matmul-equiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-matmul.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-matmul.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-matmul-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-matmul-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-matmul-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/twopass/diff-reduce.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/twopass/diff-unshard.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/final-unshard.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/diff-stage.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/final-stage.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-alu.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-alu.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-move.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-move.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-alu-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-alu-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-alu-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-move-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-move-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-move-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-sym.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-sym-a.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-sym-b.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-sym.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-sym-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-sym-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-sym.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sym-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-sym-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-sym-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-buffer.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-buffer.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-buffer.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-buffer-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-buffer-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-buffer-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-bit.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-bit.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/diff-range.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-where.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-where.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-bit-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-bit-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-bit-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d6-decisive.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-where-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-where-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-where-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/twelfth.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/subtree/census5.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-reduce.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-reduce.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-indexed.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-indexed.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-reduce.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-reduce-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-reduce-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-reduce-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/spine/03-diff-indexed.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-indexed-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-indexed-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-indexed-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-cast.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-cast.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-group.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-group-a.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D9-stability-group-b.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-group-a.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D9-stability-group-b.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-cast.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-cast-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-cast-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-cast-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/spine/03-diff-group.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-group-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-group-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-group-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-special.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-special.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-range.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-rangeflat.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D1-graph-rangeflat.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D1-graph-sink.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-graph-sink.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-special.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-special-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-special-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-special-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/spine/03-diff-range.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/03-diff-rangeflat.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-range-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-range-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-range-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-rangeflat-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-rangeflat-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-rangeflat-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/spine/03-diff-sink.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unsetexp/trial-sink-1.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-sink-2.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unsetexp/trial-sink-3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/ambig.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whyarms/watch.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/substrateid/blockers.out` | named only from inside the residue by .agents/slop/substrateid2/who.invokes; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/menu.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/boundedfix/BEFORE.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/hooks/surface-report.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/surface/report.out` | the two citation belts disagree; git sees ['.agents/slop/backlog/staged-before.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/offrepo/plants.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/checks_render-gate-oracle.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2estage8/artifacts/diff.live.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/boolexit/reach.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/diffrule/porting.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unshardfold/refusal-population.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitcode/plant-runner.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x1-derive.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/droppedinput/falsify.py` | the two citation belts disagree; git sees ['.agents/TODO.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatehealth/run-gates-empty.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/ledger/runit.py` | named only from inside the residue by .agents/slop/exitsurvey/space.out; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcfix/plant_states.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/closure1.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/nofile.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/synonyms/tables.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/after-live.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/clearfix/wrong-oracle-i64-shl-gate.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/refusals/satisfied.py` | named only from inside the residue by .agents/slop/refusals/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/prune4/untracked-unnamed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/tables.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/claims.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/prune4/candidates.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/boolexit/livehunt.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/clearfix/wrong-oracle-mixin-op-gate.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/discover.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/clauseiv-nogate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/account.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/final-msgdiff.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/closure2.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/markers.before.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/c-afd395686.rows` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/agend/spec3.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/portmarkers/markers.after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/evidence.py` | the two citation belts disagree; git sees ['.agents/slop/graphcmp-report.md'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/instrepair/run/substrate-audit.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stalefix/MATRIX-OLD.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/picks.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/droppedinput/twolists.py` | named only from inside the residue by .agents/slop/droppedinput/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipblock/blast.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/check.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_uop_graph.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d2-argv.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/gt.rows.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/foldgap/population-after-edit.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/modulerefuse/x3-class.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/slowgate/oracle_f64-plant.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/run34/disagree-gate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/callprobe.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x2-argv.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/live.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/substrate/artifacts/smoke/python.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/prune3/strays-keep.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/live-c.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/droppedinput/token.py` | named only from inside the residue by .agents/slop/diffrule/survey.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/i64shl/magicgu.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/livenum/named.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/resolve.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/cites2/instrument.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/belt2-frozen.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/shfinish/ref/tensor.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/ranges.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d2-argv.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/mv-BEFORE.diff` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/belt-now/B1-uncompilable.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/belt-now/B2-throws-on-load.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/belt-now/B3-marker-only.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/belt-now/base.rows` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/abi4check/now/bind-eq.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/post-bend-lin.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/lin-py-NULL.wire` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendpin/resolve-BEFORE.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/base-lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/lin.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-lin.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-lin.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale71/set-all-raw.rows` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/pkt-16.in` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/lin-py-METAL.wire` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_gen_float4.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d4-vacuous.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/charge.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/retention-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d3-census.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x6-plant.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/txt398/census.final.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/modulerefuse/restore.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/substrate/artifacts/smoke/python.norm` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/suffixset/final-plants.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/emptyblob/analysis.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/after-plants.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/slowgate/class-census.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-old-test_schedule.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_schedule.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/bw.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-bw.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-bw.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/modulerefuse/x2-argv.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/offrepo/callers.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-bw-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/x4-fix.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendpin/resolve-AFTER.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d8-asymmetry.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/verdictcollide/tables.rows` | named only from inside the residue by .agents/slop/untrack/census-from.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipthird/e2-base-tinybendygrad_mixin_movement.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/mv-ZERO.rows` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/reach-old-test_symbolic_tensor.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_symbolic_tensor.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_sweep.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_sweep.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/fixures/before-verdicts.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/after-verdicts.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/modulerefuse/fixmeasure.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/nameless/oracle-txt-census.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/unreachable/d5-subjects.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtexec/collide.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitsurvey/advisory.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/pm-now.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/belt2-final.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/slowgate/attribution.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/20-rss-ledger.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/pm-135.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/bounded-selftest.sh.0.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/differ-AFTER.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/diffrule/price.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flagtable/verify_unverifiable.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/prune2/copies.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/checkshells/runs/lint_demo.sh.0.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/coindependent/twostate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gitignore/after-notxt.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gitignore/before-notxt.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bf16/js_stride.mjs` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/base-msgdiff.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/cidsweep.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_graphcmp-census-audit.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/msgdiff2/pid-whole.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/artifacts/plant.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/checkshells/runs/demo.sh.0.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/after-live-c.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/live-c.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/before-1-plant-full.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/defect1-plant-full.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/hooks/run.tsv` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/before-2-no-instrument-forced.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/defect2-no-instrument-forced.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/orcfix/repro2.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale71/census-cached.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-loop.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/loop-before.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after-loop.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/rss.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/slowgate/cap-plants.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/clearfix/wrong-oracle-beautiful-mnist-gate.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/modulerefuse/argv.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/skipexit/artifacts/SKIP.post-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/txt398/no-txt.final.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/synonyms/control.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_no-txt.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_no-txt.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_no-txt.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/capture.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/prune4/move-or-copy.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/declare/declare.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/artifacts/plant-refuse.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-refuse.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-no-node.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/arghalf/after/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/move.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/artifacts/plant-passskip.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-passskip.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/citeresolve/anchors.tsv` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/02-bend-matmul.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_al-verdict.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_al-verdict.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_al-verdict.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/checks_corpus-figure.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-move-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/instrepair/run/cstyle-shapes-selftest.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipthird/e2-base-tinybendygrad_tensor.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e3-s2.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale71/c-ec08adcfb.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/skipexit/artifacts/FAIL.post-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/FAIL.pre-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-stage8red.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-stage8red.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/SKIP.pre-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/exitzero/before-1-plant-n.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/defect1-plant-n.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/binblob.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/artifacts/plant-pass.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/exitzero/after-1-plant-full.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/after-1-plant-n.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/artifacts/plant-no-zsh.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/differverdict/py-D/D0-coverage-census.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d9-broken.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/instrepair/run/cstyle-shapes-selftest.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/after-2-no-instrument-forced.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/after-port-defect2.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitzero/oracle-defect2.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/diffrule/triage.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-binblob-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/v_checks_corpus-figure.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/figure2/run-nodev.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-late.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-late.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/whyred.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/allred.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/cdiv.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/late.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/allred.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/cdiv.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/late.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/allred.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/cdiv.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/late.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/allred.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/cdiv.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/late.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/allred.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/cdiv.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/late.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-matmul.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-matmul.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/runfinal/substrate-matmul.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/pin-loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-allred.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-allred.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/plant-breaks.rows` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/sitefiles.rows` | named only from inside the residue by .agents/slop/argowner/closure.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2estage8/artifacts/pre.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/lostinst/livecite.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/synonyms/twelfth2.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/run34/corpus-figure.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/artifacts/plant-no-zsh.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-cdiv.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-cdiv.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D8b-cpython-dbg1-reachability.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D8b-cpython-dbg1-reachability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/synonyms/reach.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/opsbend-milestone/milestone.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/opsbend-milestone/milestone.sh` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/skipexit/artifacts/GREEN.pre-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/plantthe46/unreach.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/midrun/evidence/broken-d1-err.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/shfinish/ref/cidsweep.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/pinpy.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/shellgates/divergence-final.rows` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bitcastrow/port-post.rows` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/exitzero/after-oracle-defect2.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/10-fraction.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendpin/regressions.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/instrepair/run/pin-tables.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun2/disagree-gate-after-run.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun2/disagree-gate-after.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D2-bytediff.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/modulerefuse/x5-vacuous.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_simplify_valid_idx.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun2/corpus-figure-before.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_validate_oob.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/clangshim/s1.c` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_linearizer_rewrite.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/orcfix/skipexit-repro.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/skipexit/repro.now.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_dtype_spec.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_graph_rewrite.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/midrun/evidence/broken-d10-err.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/txtexec/inspect_plan.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/shfinish/ref/bmn.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/bmn2.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/mixin.sh.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/commute.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/prune2/inta.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/stale269/adjudicated-PAST-EOF.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/stale269/adjudicated.tsv` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d8-asymmetry.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/gate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun2/corpus-figure-after.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-commute-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_uop_symbolic.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/shfinish/ref/tensor.err` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_edgecases.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/alu.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/coindependent/twostate.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_gradient.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_linearizer_failures.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_tqdm.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_allreduce.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_tensor.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_gpudims.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendpin/pin_check.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_ops.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/substrate3/node.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2epy/artifacts/plant-stage8red.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-stage8red.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-passskip.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-passskip.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-no-zsh.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-no-zsh.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-refuse.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-refuse.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-pass.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-pass.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/fixures/stage3-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2epy/artifacts/plant.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/arghalf/after/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/sym.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-sym.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sym.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_call.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_norm_check.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_norm_check.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/denominator/probe.before.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/denominator/sandbox.before.err` | named only from inside the residue by .agents/slop/substrateid2/gate.py.namers; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_cli.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/06-corpus-figure-after.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whichgroup/snap/rows-sym-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-threefry-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/at-135bf0204/plant-measure.json` | named only from inside the residue by .agents/slop/abi4check/plant-measure.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/clearfix/wrong-oracle-ew-consts-gate.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D1-verdicts.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/fixures/blind-spot.out` | named only from inside the residue by .agents/slop/capstream/final_split.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whichgroup/snap/rows-wmma-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/refusals/satisfied.out` | named only from inside the residue by .agents/slop/refusals/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/summary.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/now/plant-measure.json` | named only from inside the residue by .agents/slop/abi4check/plant-measure.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_ops-core-oracle.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/belt_inputs.py` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whichgroup/snap/rows-late-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-old-test_winograd.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-test_winograd.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/v_checks_dup-gate.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/after-nl-gate.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/base-nl-gate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/final-nl-gate.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_dup-gate.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/dup-gate.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/declare/compare.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-mulacc-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/txtgen/orphan-plant.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_corpus-figure.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censroot/after-census.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/buffergraphs/emit-mselect.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/clearfix/wrong-oracle-wk-f32-gate.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/final-norm_check.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/norm_check.out` | the two citation belts disagree; git sees ['.agents/slop/citeresolve/hist.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_norm_check.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/after-gate-surface.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/bit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/buffergraphs/emit-mstack.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-cdiv-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/ops1.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gitignore/freedreport.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/refusals/recheck-declaretwo.out` | named only from inside the residue by .agents/slop/untrack/census-from.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_dtype.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-bit-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gitignore/perdir.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/hooks/_probe_pop.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/buffergraphs/emit-stage.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/txtexec/nonrows.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/shfinish/ref/tree-sha.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/readerdecl/manifests.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/after-no-txt.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/suffixset/base-no-txt.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/final-no-txt.out` | named only from inside the residue by .agents/slop/untrack/census.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_env-precond.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/exitsurvey/advisory.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rosterwire/oldcount.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/deadclause/plants-after.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-mstack-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/ccdead2/emit.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/txtgen/gate-BEFORE.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/ops2.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/gate-AFTER.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/where.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/fwdref.bend` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/group.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/portmarkers/proof.plant.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/deadclause/plants-before.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/buffergraphs/emit-custom_function.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-unshard-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/denominator/vacuous.err` | the two citation belts disagree; git sees ['.agents/slop/untrack/census-from.rows'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/argowner/upat.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipthird/e2-exp-tinybendygrad_schedule_prepare.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/clearfix/wrong-oracle-ew-explog-gate.py` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e2-exp-tinybendygrad_mixin_movement.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/probe-flip-METAL.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-METAL.err` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whichgroup/snap/rows-stage-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/probe-flip-NULL.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/probe-lin-NULL.err` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whichgroup/snap/rows-where-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/cinit.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d4-vacuous.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/pkt-4.in` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-group-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e2-exp-tinybendygrad_tensor.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e3-s1.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e2-exp-tinybendygrad_uop_render.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/exp-render.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/reduce.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-reduce.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-reduce.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipthird/e2-exp-tinybendygrad_uop_fold.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e2-exp-tinybendygrad_uop_upat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/exp-upat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/rss-ledger/1.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/rss-ledger/2.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/rss-ledger/3.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/rss-ledger/6.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/msgdiff/range.err` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/argowner/final-upat.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipthird/e2-exp-tinybendygrad_uop_ops.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/indexed.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/handoff-flip.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/base-upat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/flipthird/e2-base-tinybendygrad_uop_upat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/gates_wk-eval-oracle.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/whichgroup/snap/rows-reduce-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/reach-old.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/msgdiff2/pid.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/orcfix/plant_states.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/oracles259/ordering.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/ordering.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/refusals/recheck-exitcode.out` | named only from inside the residue by .agents/slop/untrack/census-from.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2epy/artifacts/plant-deadbend.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-deadbend.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-thin.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-thin.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/figurefix/plant/D-live/D2-canon-bend-flip.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-canon-bend-flip.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_ew-consts-oracle.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/skipexit/artifacts/GREEN.post-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/canrun/census/v_checks_coverage.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_corpus-figure.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/midrun/evidence/broken-stability.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/cast.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/named-BEFORE.rows` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/gate_norm.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/jsfix.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/instrepair/run/mutate-dm.py.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/emptyact/gate-py3.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_gate.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/laws17/proof2.after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof.after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof.before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/proof.after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/proof.after1.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/proof.before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/laws.after.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/laws.before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/laws.after.err` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whichgroup/snap/rows-cast-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/fixtures/plant-no-node/runs/e2e/e2e-mm-bend.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/runs/e2e/e2e-mm-bend.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/fixtures/plant-pass/runs/e2e/e2e-mm-bend.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/fixtures/plant-passskip/runs/e2e/e2e-mm-bend.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/fixtures/plant-refuse/runs/e2e/e2e-mm-bend.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/fixtures/plant/runs/e2e/e2e-mm-bend.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/midrun/evidence/broken-run-summary.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/py-loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/emptyblob/classify.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/py-lin.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/now-py3.stderr` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/now-venv.stderr` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/abi4.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/buffer.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/oracletxt/shape_of_stale.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/slowgate/residue-full.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/plant-hermetic.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/refusals/recheck-onewalk.out` | named only from inside the residue by .agents/slop/untrack/census-from.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/unreachable/d9-broken.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/nums.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_gate_dtype.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/whichgroup/snap/rows-buffer-py.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_devpin.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_devpin.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_devpin.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/oracles259/manifest-write.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/manifest-write.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/rangeflat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/binblob.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/allred.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/commute.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/indexed.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/matmul.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/special.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/plant-helpers-tc.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/buffer.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/reduce.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/run.stderr` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/before-out/cdiv.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/group.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/late.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/move.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/range.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/where.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/cast.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/flip.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/lin.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/sink.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/alu.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/bit.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/bw.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/sym.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_test_rewrite_bottom_up_gate.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/slowgate/residue-120.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/quiesce/watch.out` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_graphcmp-census-audit.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/beltA.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/now/bind-lt.bend.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/post.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/pre.out` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/after-out/rangeflat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/binblob.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/allred.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/commute.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/indexed.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/matmul.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/special.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/buffer.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/reduce.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/cdiv.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/group.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/late.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/move.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/range.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/where.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/cast.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/flip.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/lin.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/sink.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/alu.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/bit.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/bw.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/sym.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/quiesce/watch2.out` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/full-fit.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/txtgen/declared-completeness.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/now/bind-lt.bend.said` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/gate.sh.0.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/checks_llama.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_tensor_uop_mixin.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
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
| `.agents/slop/txtgen/gate_norm-BEFORE.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_run.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/dup-census.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/dup-gate2.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/final-dup-gate.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/denominator/real.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_dup-gate.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/herm.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censroot/after-hermetic.err` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_hermetic-census.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_fw_live.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_fw_live.py.out.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_fw_live.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/checks_romless.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/probe-pristine.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/pm-135.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/txtgen/census-cache-plant.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_cli.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/spine/01-after-bend-check.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_compile.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_compile.py.out.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_compile.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/135bf0204-run.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censroot/before-hermetic.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censusred/refusal.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/probe-patched.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D0-selfcheck.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_sz.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_sz.py.out.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_sz.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/v_checks_run.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_run.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-lin.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-lin.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/censroot/before-census.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/rangeflat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/rangeflat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/rangeflat.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/binblob.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/binblob.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/binblob.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-flip.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-fold-old.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-fold-probe.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-fold-v2.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/rss-ledger/4.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/rss-ledger/5.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/rss-ledger/retry.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-flip.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/allred.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/commute.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/indexed.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/matmul.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/special.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/allred.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/commute.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/indexed.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/matmul.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/special.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/allred.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/commute.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/indexed.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/matmul.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/special.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/buffer.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/reduce.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/buffer.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/reduce.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/buffer.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/reduce.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/twopass/fold-gate-PRE.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after-loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/cdiv.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/group.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/late.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/move.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/range.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/where.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/cdiv.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/group.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/late.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/move.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/range.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/where.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/base-loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/cdiv.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/group.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/late.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/loop.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/move.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/range.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/where.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/rss.tmp` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/cast.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/flip.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/lin.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/sink.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/cast.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/flip.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/lin.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/sink.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/base-lin.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/cast.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/flip.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/lin.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/sink.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/chk-postrange.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-insprobe-old.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-insprobe-v2.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-insprobe.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/alu.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/bit.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/bw.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/sym.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/alu.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/bit.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/bw.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/sym.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/alu.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/bit.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/bw.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/sym.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/beltB.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/beltB2.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/b-gcmp-final.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-gcmp-old.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-gcmp-v2.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_helpers.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_viz.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/b-gcmp-new.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/probe-patched.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/probe-pristine.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-loop.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.after.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.final.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/render.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/flipthird/md5-a.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/fold-chk.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/check-after.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/check-final.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/oracles259/manifest-prove.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/manifest-prove.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/twopass/base-check.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/final-check.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/land-check.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/ops-check.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/ops3.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/chk.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/f.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citeresolve/classify.err` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mx-AFTER.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mx-BEFORE.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-matmul.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/runfinal/substrate-matmul.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-reduce.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-loop.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/post-bend-lin.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-lin.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-sink.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/fbuild-base.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-bw.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/base-sym.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mv-AFTER.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mv-BEFORE.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mv-PRISTINE.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/mv-ZERO.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/v_checks_gate_dtype.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/build-base.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-fold.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/fold-gate.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/hooks/surface-time.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/launch-64/ARGV` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendperf/launch-ones-000/argv.json` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/scan-before.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_no-shrink.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_no-shrink.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_no-shrink.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/agend2/tools.out` | named only from inside the residue by .agents/slop/agend2/measure.py; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_ew-explog-oracle.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/checks_lint_demo.sh.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/range.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/agend/guide.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/abi4check/pm-now.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/checkshells/runs/sbgate-fix-absent.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/rangeflat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/portmarkers/guide.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/portmarkers/help.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D9-stability.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D9-stability.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/table-now.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/arghalf/after/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/checkshells/runs/sb-gate.sh.1.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/sink.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/base-sink.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopq/plant-sink.rows` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/checkshells/runs/wt-sync.sh.0.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gitignore/before-state.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gitignore/after-state.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gitignore/now-state.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/after2/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/before/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/after-out/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/linfix/before-out/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/base/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/final-new/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-new/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/frozen-old/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/v2-new/special.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/v_checks_process_replay.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_process_replay.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/selftest-v3.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/checks_devgate.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/denominator/t2.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/00-bytes-after.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/00-bytes-before.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/slowgate/residue-full.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/selftest-probe.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/pin-loop.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/selftest-before.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-frozen-new.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/selftest-frozen-old.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/shfinish/ref/bmn.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/shfinish/ref/bmn2.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D1-verdicts.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/loopfix/selftest-v2.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/checks_no-strays.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/canrun/census/v_checks_no-strays.py.out` | the two citation belts disagree; git sees ['.agents/slop/emptyblob/EMPTY.tsv'], the scanner sees [] | `belts-disagree` |
| `.agents/slop/gatesrun/checks_no-strays.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/shfinish/ref/mixin.sh.out` | named only from inside the residue by .agents/slop/_cite/cites.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_autogen.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_device.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_disk_cache.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_dtype_weak.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_method_cache.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_pattern_matcher.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_tensor_metadata.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_uop_vmin_vmax.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_renderer_failures.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_tensor_uop_representation.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/artifacts/plant-deadbend.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-deadbend.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-thin.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-thin.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/gatesrun/checks_test_rewrite_bottom_up_gate.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_const_folding.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_encodings.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_gc.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_indexing.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_llm_tokenizer.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_memory_planner.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_microbenchmarks.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_rearrange_einops.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_setitem_schedule.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_symbolic_failures.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_system_pci_scan_bus.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_uop_resolve.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/checkshells/runs/sb-gate.sh.0.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/checkshells/runs/sbgate-fix-present.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatesrun/gates_wk-cd-oracle.py.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_elf.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_gguf.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_hashing.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_hcq_iface.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_invalid_tensor.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_isel.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_llm_mla.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_nn.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_objc.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_pickle.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_process_replay.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_randomness.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_resnet.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_rewrite_bottom_up_gate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_schedule_cache.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_setitem.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_symbolic_ops.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_tensor_io.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_tensor_variable.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_transcendental_helpers.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_uop_repr.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_upat_compile.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/agend/pytest.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bullets/pytest.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/suffixset/ledger.sha256.before` | named only from inside the residue by .agents/slop/untrack/census-from.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/agend/mypy.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/agend/ruffvenv.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bullets/mypy.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bullets/ruffvenv.err` | named only from inside the residue by .agents/slop/emptyblob/last40.numstat; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citeresolve/anchors.err` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendwire/EXE` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendwire/launch-64/EXE` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/census/v_checks_bounded.py.out.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/e2epy/artifacts/plant-stage1red.oracle.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-stage1red.port.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/fixtures/plant-thin/runs/e2e/e2e-mm-bend.rows` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/fixtures/plant/runs/e2e/e2e-jsstage.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/oracles259/classify.err` | named only from inside the residue by .agents/slop/citeresolve/REPORT.md; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/orcdecide/retired/classify.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/after-graphcmp-broken.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/after-graphcmp-ok.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/after-live.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/after-syn-clean.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/after-syn-plant.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/clauseiv-nogate.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/run-gates-copy.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/run-gates-empty.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/run-graphcmp-broken.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/gatehealth/run-graphcmp-ok.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/arghalf/ops-check.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/argowner/fold-chk.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/ops3.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/render.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.after.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/laws17/proof-all.final.out` | named only from inside the residue by .agents/slop/gitignore/after-lsfiles.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/linfix/chk-postrange.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/check-after.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopfix/check-final.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/loopq/plant-check.out` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/twopass/final-check.out` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/canrun/census/checks_process_replay.py.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_classify.sh.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/citeresolve/counts-counts.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-rangeflat.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-rangeflat.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-binblob.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/named.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-binblob.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-commute.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-indexed.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-matmul.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-special.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-commute.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-indexed.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-matmul.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-special.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citemass/scan-now.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/citeresolve/hist.err` | named only from inside the residue by .agents/slop/prune4/untracked-unnamed.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/cites2/final-counts.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-buffer.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-reduce.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-buffer.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-reduce.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-group.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-loop.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-move.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-range.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-where.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-group.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-move.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-range.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-where.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-cast.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-gate.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-sink.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D2-cmp-cast.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-gate.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-sink.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/argowner/handoff-flip.err` | named only from inside the residue by .agents/slop/untrack/git-head.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-alu.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-bit.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-bw.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D2-cmp-sym.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/helpers-tc-gate.bd.err` | named only from inside the residue by .agents/slop/backlog/staged-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-alu.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-bit.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-bw.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D2-cmp-sym.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/citemass/resolve-now.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/foldgap/fold.md5.rows` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_ew-explog-oracle.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/claims.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/jjhazard/heartbeat.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/canrun/jsfix.out` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/run.stdout` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/deadclause/residue-plant.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/differverdict/pristine/runs/graphcmp/D/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/shell-D/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-oracle/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-planted/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/differverdict/warm-python/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D0-selfcheck.out` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/gates_wk-cd-oracle.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/cites-after.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/livenum/cites-before.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/diff` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/grep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/tail` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/env` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/sed` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/tr` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/wc` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/bendperf/launch-ones-000/wall` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/chmod` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/mkdir` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/sleep` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/fixures/after.rc` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/fixures/before.rc` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/gatesrun/checks_render-gate-oracle.py.err` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/jjhazard/scratch.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/cat` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/zsh` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/jjhazard/probe-b.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-deadbend/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-node/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-no-zsh/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-pass/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-passskip/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-refuse/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-stage1red/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/plant-thin/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-fail/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-green/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/cp` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/ls` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/mv` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/e2epy/fixtures/repro-skip/sandbox/rm` | symlink | `readlink-target (this tree has 167 and lstat is the only safe size)` |
| `.agents/slop/abi4check/135bf0204-run.rc` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/now-py3.rc` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/abi4check/now-venv.rc` | named only from inside the residue by .agents/slop/emptyblob/summary.json; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/figurefix/plant/D-live/D10-zerorow-guard.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D8-dbg-012.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/figurefix/plant/D-live/D8-dbg-03.rows` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/rerun/D-before/D10-zerorow-guard.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D8-dbg-012.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/rerun/D-before/D8-dbg-03.rows` | named only from inside the residue by .agents/slop/bendsuite/git-status-before.rows; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/substrate3/pop.before.err` | named only from inside the residue by .agents/slop/citeresolve/hist.tsv; a tool chain or a shadow tree, indistinguishable here | `residue-internal-citer` |
| `.agents/slop/bendsuite/bend/test_assign.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/bendsuite/bend/test_linearizer.out` | belt A did not run: the run's citation budget was spent before this row | `rerun-with-more-seconds` |
| `.agents/slop/substrate/artifacts/smoke/python.rc` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-no-node.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-stage1red.oracle.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/e2epy/artifacts/plant-stage1red.port.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/FAIL.post-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/FAIL.pre-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/GREEN.post-fix.out` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/GREEN.pre-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/SKIP.post-fix.err` | excluded from this walk by the house rules | `owner-decision` |
| `.agents/slop/skipexit/artifacts/SKIP.pre-fix.err` | excluded from this walk by the house rules | `owner-decision` |
