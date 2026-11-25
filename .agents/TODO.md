# TODO

`160` categories: **52 open**, 108 closed.
The full history is `.agents/slop/todo-archive-20261125.md` — this file is the board, that file is the evidence.

**No row here is a verdict.** A green claim below is a record of a run on a tree that has
since moved; the only verdict is `.venv/bin/python gates/corpuswitness-gate.py`.

Closed categories keep one row and no prose. Open ones keep the head of their block.

## Open

| category | bar | done | status |
|---|---|---|---|
| `recovery` | `[########.......]` | 11/15 | the plan is `.agents/slop/checklist.md`; Phases 0-2 and 4.1 done 2026-11-25 |
| `wgsl-perf` | `[##########]` | 10/10 | THE WGSL TURN IS ~22x FASTER (24,862 ms -> ~1,110 ms): THE FOLD WAS |
84% OF IT AND WAS A KAHN SORT OF AN ARENA WHOSE INDEX ORDER IS ALREADY A TOPOLOGICAL ORDER
(0 VIOLATIONS IN 1,698,277 EDGES), AND THE TABLE's LOOKUP WAS 35.7% OF THE TURN. THE NEXT
LEVER IS THE ARENA's O(n) ACCESSORS. |
| `render-perf` | `[########]` | 6/9 | THE RENDER IS ~25% FASTER OVER THE THREE LANDED CHANGES, AND |
| `decomp-census` | `[#####]` | 3/5 | 39 rows, 23 exact, 16 declared (11 PROMOTION · 2 WALL · |
| `upstream-comments` | `[######....]` | 6/10 | **UPSTREAM'S **COMMENTS **PORTED**, **⇒⇒† AND **THE **AUDIT **SAYS |
| `backward-walk` | `[#########]` | 1/3 | `compute_gradient` + `_deepwalk` LANDED in |
| `turn-cost` | `[######..]` | 6/7 | **THE SHIPPED DAEMON TURN**, AGAINST `ClangRenderer`'s |
| `walkthroughs` | `[######...]` | 6/7 | E2E-PROVES-COMPUTE 1/1  <- runs/e2e/ |
| `clangshim` | `[#######...]` | 7/10 | ONE generated .c, ONE import, ONE cc: |
| `gate-disagree` | `[#########]` | 9/10 | dtype rows 209, 7 disagreements (was 19). +28 `f2f` rows: |
| `dtype-js-abi-gate` | `[#########.]` | 6/10 | **`checks/abi_gate.py` HAD TWO STALE CONSTANTS AND NO |
| `lane-liveness` | `[###########]` | 13/15 | census: the 39 wired lanes tabulated |
| `dup-rows` | `[#########.]` | 8/10 | 10 = census, usb, ops_nv-oracle, ops_nv-port, hcq2, |
| `false-fails` | `[#########]` | 9/10 | The apostrophe guard LANDED (`checks/cites-census.py:394`, |
| `repro-anchor` | `[##........]` | 1/3 | THE FIX I LANDED 2026-10-15 WAS READING **ONE FIFTH** OF ITS OWN |
| `ledgerdrift` | `[#####.....]` | 1/3 | DISPATCHED UNIT 2026-10-15. `.agents/TOOLS.md` names **367** paths |
| `shapecensus` | `[####......]` | 1/3 | DISPATCHED UNIT 2026-10-15. **226 instruments / 244 rows**, |
| `UNPUSHED-DELETES` | `[#####.....]` | 1/3 | **LOUDER THAN THE PUSH BLOCKER, AND FOUND BY THE `unpushed` UNIT.** |
| `stale-ref` | `[####......]` | 1/3 | MEASURED over the tracked tree: **103 sites read a remote-tracking ref; |
| `corpus-MIXTURE` | `[#####.....]` | 1/2 | **THE 31/2/34 READING IS NOT A MEASUREMENT OF ONE TREE, AND EVERY NUMBER I |
| `digest-residue` | `[##########]` | 2/3 | **AFTER MY `f62666ad6`, THE DIGEST PINS 387 INPUTS AND COVERS |
| `comment-cut` | `[#######.]` | 7/8 | **THE **PORT's **COMMENT **MASS **IS **CUT **BY **THE |
| `nn-laws` | `[##........]` | 1/3 | **LAWS ARE THE RIGHT MECHANISM FOR PART OF THIS, BUT THE SPEC IR CANNOT |
| `nn-layers` | `[#######...]` | 3/7 | THE LAYERS LAND, AND ONE OF THEM FOUND A REAL DEFECT IN A FILE IT DOES |
| `five-units` | `[#####.....]` | 2/5 | FIVE UNITS, AND THE HEADLINE IS NOT A NEW DEFECT BUT A CORRECTION TO ONE. |
| `nn-path` | `[####......]` | 2/4 | **TWO REAL DEFECTS ON THE CONV2D PATH, LANDED, AND BOTH UNITS REFUTED A PRIOR |
| `freshness-reach` | `[###.....]` | 1/3 | **A GOVERNING DOCUMENT'S CLAIM WAS HALF FALSE WHILE IT LIVED, AND THE |
| `commit-recipe-race` | `[##]` | 2/3 | **THE PRESCRIBED COMMIT RECIPE SWEEPS 40 OF 40 TRIALS UNDER A RACE, AND THE HAZARD |
| `substrate-break` | `[###]` | 2/4 | **THE COMMITTED TREE DID NOT COMPILE, AND THE TREE'S OWN GATES SAID SO BY REFUSING |
| `ops-rule1-family` | `[##]` | 2/3 | **FOUR `match`-ON-A-CALL SITES IN ANOTHER UNIT'S IN-FLIGHT `uop/ops.bend` POISONED THE |
| `argmax-ported` | `[####]` | 3/4 | **THE RECIPE IS PORTED AND VERIFIED; THE GRAPH IS REFUSED WITH THE MEASUREMENT.** |
| `item-ported` | `[###]` | 3/4 | **`Tensor.item` IS PORTED TO THE EDGE THE PORT CAN REACH, AND THE WALL IS NAMED.** |
| `brief-citation-error` | `[##]` | 2/3 | **I ASSERTED A MEASUREMENT I HAD NOT MADE, IN A WORKER'S BRIEF, AND IT PROPAGATED. THIS |
| `mo-at-forward` | `[####]` | 3/4 | **`mo_at` COUNTED THE INDEX FROM THE END, SO EVERY RANK>=2 KEEPDIM REDUCE AND EVERY |
| `verdict-hunt` | `[##]` | 2/3 | **NO BOUNTY WIN, AND A REAL UPSTREAM BUG IN THE #1182 FAMILY -- IN THE OPPOSITE |
| `safe-ts-trust-gap` | `[##]` | 2/3 | **THE LEAN SIDE IS CLOSED, SO THE TRUST GAP IS THE 1,573 LINES IN FRONT OF IT.** |
| `mnist-e2e` | `[###]` | 3/4 | **AN END-TO-END MNIST RUNS ON THE BEND DEVICE AND AGREES WITH CPython -- AND IT COSTS |
| `exec-apply` | `[###.]` | 3/4 | **THE APPLY REWRITE: **THE **GRAPH'S SHAPE** NOW MATCHES CPYTHON's.** |
| `exec-wa` | `[##]` | 2/5 | **W-A -- THE AFFINE EXPRESSION: **ONE MISSING RULE**, NOT A MISSING MODULE.** |
| `cite-class` | `[#########]` | 4/5 | **FOURTEEN UPSTREAM CITATIONS IN `uop/ops.bend` WERE WRONG BY TWO |
| `cite-slice` | `[######...]` | 3/5 | **THE 603 ARE THE CLASS, AND THE SLICE THAT IS NOT `runtime/**` |
| `upstream-suite` | `[###.........]` | 3/3 | **THE UPSTREAM SUITE IS BEING PORTED ONE FILE AT A TIME, |
| ``load-census` | `[####.....]` | 4/7 | ` — the ledger, the guard, the retrospective, and the starvation |
| `claimaudit` | `[####......]` | 1/3 | AN ADVERSARIAL RE-AUDIT OF THE ORCHESTRATOR'S OWN COMMITS, and it found |
| `onespelling` | `[##........]` | 1/3 | THE CLASS AS AN INSTRUMENT, WITH A CONTROL THAT EARNED ITS KEEP. |
| `onespelling-precision` | `[##........]` | 2/3 | **A CENSUS OF 254 FINDINGS NOBODY HAD READ IS NOT A MEASUREMENT, |
| ``target-census` | `[###......]` | 3/6 | ` · `target-plant  [#########] 9/9` · `target-roundtrip  [##.......] 2/7` |
| `paramarg-spec` | `[##]` | 2/3 | **THE PORT's `ParamArg` IS MISSING **UPSTREAM's **13th **FIELD** (`spec`). |
| `fold-graph-arity` | `[##]` | 2/3 | **`gates/fold_graph_census.bend` **IS **BROKEN **AND **THE **FIX **CHANGES |
| `wk-eval-oracle` | `[##]` | 2/3 | **`gates/wk-eval-oracle.py` **IS **THE **CPYTHON **HALF **OF **THE **SAME |
| `untracked-oracle-fragments` | `[##]` | 2/3 | **`oracles/probe-su.bend` **AND **`oracles/probe-targetparse.bend` |
| `e2e-fixture-render-kernel` | `[##]` | 2/3 | **`checks/.e2e-fixture/{f64/emit-f64,portexec/emit-mm}.bend` |
| `spec-pattern-vs-body` | `[##]` | 2/3 | **A **RULE **WHOSE **MATCH **TEST **IS **IN **THE **BODY **INSTEAD **OF |
| `ledger-pop` | `[#######.]` | 7/8 | **THE **FIVE **UNOWNED **ROWS **THE **GATE **REPORTED **WERE |

| `shader-pad-lane` | `[#########...]` | 9/11 | the plan is `.agents/slop/shader-pad-lane/PLAN.md`; THE PAD ARM AND THE ZERO-FILL ARE LANDED AND THE SCHEDULE BUILDS A KERNEL |

## Closed

| category | done | status |
|---|---|---|
| `no-txt` | 3/3 | generators, NOT files: `helpers-tc-gate.sh` `$GT.py` -> |
| `amd-dsl-census` | 9/9 | 9 census CLASSES retired, 3 left: `MSG_TEXT` 26 · |
| `cstyle-census` | 9/9 | 425 rows, 3 lanes, rc=0 (WAS 361, AND 358 BEFORE THAT). |
| `runtime-lane` | 10/10 | **THE **`runtime/` **LANE's **COMMENT **MASS **CUT **AND |
| `table-files` | 10/10 | **THE **TABLES **LEAVE **THE **COMMENT **BLOCKS.** **⇒⇒† AND |
| `spec-as-laws` | 9/9 | python-to-bend  [###.......] 5/96  (0 defs outstanding) |
| `proofs` | 34/34 | oracle-green     [#####.....] 5/5 |
| `dtype-js-abi` | 3/3 | `runtime/dtype.js` read `p.fst`/`p.snd` against a record |
| `dtype-js-abi4` | 3/3 | ABI-4 **REPAIRED IN THE TREE**, 3 lines, no net line |
| `mut-REQUEST` | 0/0 | 31 MOVED / 5 THEOREM / 0 REQUEST |
| `false-zeros` | 0/0 | 0 unmarked (was 14) across 21 records |
| `row-reader` | 3/3 | formats F1/F2/F3, 39 pairs, 0 keys lost |
| `arena-aliasing` | 8/8 | 1100 read sites audited, 1 DEFECT fixed (+2 rows), |
| `ops-python-exec` | 9/9 | the EXECUTOR census, 153 fixtures x 2 lanes, rc=0. |
| `stack-sslot` | 1/1 | `Prog.stack.at` read each STACK src's arena |
| `arena-array` | 10/10 | THE VALUE ARENA IS ONE `Array<Elem>` (`cfb5b90e5`, |
| `gates-sweep` | 10/10 | `/tmp/sweep.sh` is FOREIGN and NON-COMPLIANT (shell, |
| `exitcodes` | 3/3 | **MEASURED, THE EXIT CONTRACT DECIDED, AND THE INSTRUMENT PROMOTED AND GREEN.** |
| `rn-phantom-exact` | 3/3 | THE CLASS IS EXACTLY 3, AND A UNIT FOUND A LARGER FINGERPRINT BESIDE IT. |
| `malformed-trees` | 3/3 | **THREE MALFORMED TREES, NOT ONE -- VERIFIED.** MEASURED 2026-10-17: |
| `dictkeyed` | 3/3 | **A DICT KEYED BY PATH CANNOT REPRESENT A DUPLICATE PATH ENTRY, SO THE |
| `index-arm-duplicate` | 4/4 | **A PASS WHOSE COUNT IS MEASURED WITH A DATATYPE THAT CANNOT HOLD |
| `no-txt-green` | 3/3 | **rc=0, AND IT WAS TWO SEPARATE CAUSES, NOT ONE.** (1) The 3 hard |
| `gate-DIVERGENCE` | 3/3 | **`gate` DIVERGES BY ONE CHILD, AND MY OWN PREMISE WAS WRONG ON THE UNIT.** |
| `lin-DIVERGENCE` | 3/3 | **`lin` DIVERGES BY EXACTLY ONE NODE, NOT ~42** -- the `9,50c9,49` hunk |
| `loop-REFUSAL` | 3/3 | **`loop` IS NEITHER A PORT GAP NOR A CORRECT REFUSAL -- IT IS A STALE HARNESS |
| `unaccounted-states` | 3/3 | **THE SUMMARY HAS NO ROW FOR FOUR STATES THIS RUN ACTUALLY PRODUCED.** |
| `substrate-coverage` | 3/3 | **A DIGEST THAT OMITS THE SUBJECT OF THE COMPARISON IS A PIN ON THE |
| `corpus-GREEN` | 2/2 | **VERIFIED BY ME AT 2026-10-18T21:22:18Z: `graphs-agree=33`, |
| `oracle-selfcheck` | 3/3 | **A RED LIGHT ON A GREEN ROAD: THE PIN IS RED FOR A REASON THAT NO LONGER |
| `census-rc` | 3/3 | **THE SAME FAILURE AS `oracle-selfcheck`, NOT AN INDEPENDENT ONE** -- |
| `immovable-denoms` | 3/3 | **SEVEN SUMMARY ROWS CARRY A DENOMINATOR TYPED IN CODE, SO THEY CANNOT |
| `driver-coverage` | 3/3 | **TWO DRIVERS THE RUN EXECUTES WERE NOT IN THE DIGEST, AND A GREP CENSUS |
| `comment-cut-runtime-nn-mixin` | 9/9 | **THE **COMMENT **CUT** **ON **THE **runtime/ **nn/ **mixin/** |
| `comment-decay-restored` | 3/3 | **A SWEEP THAT DELETES A FILE MAKES A LATER RESTORE INVISIBLE TO |
| `substrate-head` | 3/3 | **A DIGEST WITH NO COMMIT IN IT CANNOT BE COMPARED TO A TREE.** |
| `repro-ran` | 3/3 | **THE REPRO RUNS, AND THE DIFFERENCE IS SOLVED BY RE-TAKING IT, WHICH |
| `dw3-guard` | 4/4 | **THE `dw >= 3` MATMUL ARM, AND THE MOST IMPORTANT FINDING OF THE PAIR IS THAT |
| `all-three-green` | 3/3 | **2026-10-20T20:40Z: THE CORPUS IS GREEN, REPRODUCIBLE, **AND CURRENT** -- |
| `refused-is-3` | 4/4 | **ELEVEN SITES PRINTED `REFUSED` AND EXITED 2, AND THE CLASS IS NOW CLOSED.** |
| `exitcode-census` | 3/3 | **A NEW TRACKED GATE THAT FOUND 23 REAL DEFECTS, AND IT IS GREEN BECAUSE |
| `index-disarmed` | 2/2 | **THE ARMED-INDEX HAZARD WAS LIVE AND IS NOW CLOSED, AND THE SHAPE IS |
| `nn-rows-vacuous` | 4/4 | **THE NN LAYERS NOW HAVE A COMPARER, AND **EVERY ONE OF THE 31 ROWS CAN GO RED** -- |
| `corpus-witness-stale` | 3/3 | **THE CORPUS WITNESS IS STALE, AND THE TREE'S OWN INSTRUMENTS SAY SO IN TWO INDEPENDENT |
| `imagenet-distance` | 3/3 | **THE MEASURED DISTANCE TO *"RUN IMAGENET USING BEND"*, RE-TAKEN 2026-10-26. THE CHAIN |
| `nn-rows-gate` | 4/4 | **THE NN LAYERS HAVE A COMPARER, AND **THE HOLE IN IT IS CLOSED**: A DELETED ROW |
| `mixin-op-red` | 3/3 | **A TRACKED GATE WAS RED AT HEAD ON 11 ROWS, AND THE ELEVEN ARE NOW CLOSED.** MEASURED |
| `oracle-two-copies` | 3/3 | **THE GATE'S CPython ORACLE WAS A COPY UNDER `.agents/slop/` AND A SECOND COPY SAT |
| `mo-squeeze-row` | 4/4 | **THE THIRD CALL SITE OF `mo_at` NOW HAS A ROW THAT GOES RED, SO TWO OF THE THREE ARE |
| `corpus-stale-fix` | 3/3 | **THE `mo_at` FIX MOVED THE SUBSTRATE, THE WITNESS WENT STALE, AND THE TREE'S OWN |
| `mixin-op-corrected` | 3/3 | **A CLAIM OF MINE DID NOT SURVIVE RE-MEASUREMENT, AND IT WAS WRITTEN DOWN IN THE LEDGER |
| `verdict-outside-repo` | 3/3 | **THE VERDICT IS DECIDED BY A BINARY OUTSIDE THE REPOSITORY, AND A `--verdict` LANE |
| `mixin-op-closed` | 3/3 | **THE WALL THAT `mo-squeeze-row` NAMED HAS FALLEN, AND THE ELEVEN HAVE BEEN CLOSED -- |
| `corpus-green-again` | 3/3 | **THE CORPUS IS GREEN, REPRODUCIBLE **AND** CURRENT AGAIN, WITH THE `mo_at` FIX IN THE |
| `bend-upgrade-38` | 3/3 | **THE PROJECT WAS ON BEND `v2.0.38` (SUPERSEDED BY `bend-upgrade-39` BELOW), AND EVERY PI… |
| `bend-upgrade-39` | 3/3 | **THE PROJECT IS ON BEND `v2.0.39`, AND EVERY PIN THAT NAMES THE COMPILER MOVED WITH |
| `argmax-graph` | 4/4 | **THE GRAPH-LEVEL `argmax` IS BUILT AND GREEN, AND THE BLOCKER WAS **TWO BUGS**, NOT |
| `imagenet-loader` | 4/4 | **THE IMAGENET LOADER IS NO LONGER A STUB: ALL THREE DEFS ARE REAL.** |
| `verdict-lane` | 4/4 | **THE FIRST INSTRUMENT THAT CHECKS THIS PORT'S PROOFS AGAINST THE LEAN-VERIFIED |
| `rand-census-expired` | 3/3 | **A GATE'S CLAIM EXPIRED BECAUSE A FIX WORKED, THE GATE WAS UPDATED, AND THE UPDATE |
| `keepdim-dedup` | 3/3 | **THE PORT HAD *TWO* IMPLEMENTATIONS OF THE KEEPDIM TARGET -- ONE RIGHT AND ONE WRONG |
| `nn-rows-complete` | 4/4 | **THE NN LAYERS' VERIFICATION IS COMPLETE: **31 OF 31 ROWS CAN NOW GO RED** -- AND |
| `backward-pass` | 4/4 | **THE BACKWARD PASS HAS FIVE OF ITS PIECES, AND THE FIVETH -- `gr_21` -- IS GATED |
| `backward-holes` | 3/3 | **BOTH NAMED HOLES BELOW THE BACKWARD PASS ARE NOW ADDRESSED, AND THE FIRST WAS A |
| `repro-diff-poison` | 3/3 | **A NAME `cmd_repro` WRITES WAS NOT DECLARED, AND IT POISONED THE CORPUS'S CENTRAL |
| `repro-subject-verdict` | 3/3 | **TWO RUNS THAT MEASURED DIFFERENT SUBJECTS WERE REPORTED AS *FAIL*, WHICH READS AS |
| `exec-broadcast-max` | 3/3 | **THE BROADCAST LANE AND THE `max` LANE ARE FIXED, AND NEITHER WAS WHAT IT LOOKED |
| `exec-e2e-instrument` | 3/3 | **THE INSTRUMENT THAT MEASURES THE EXECUTOR WAS DEAD, AND WRONG IN THREE WAYS AT ONCE, |
| `pins-exempt-rows` | 3/3 | **A PIN THAT EXEMPTS A ROW FROM THE COMPARISON IS NOT A PIN, IT IS AN EXEMPTION -- AND |
| `exec-conv-lane` | 4/4 | **THE BEND EXECUTOR IS NOW 1:1 WITH UPSTREAM's OWN INTERPRETER ON THE WHOLE EXECUTOR |
| `comment-is-a-hypothesis` | 3/3 | **A CAUSE NAMED IN A COMMENT IS A HYPOTHESIS, AND THIS TREE HAS NOW MEASURED THAT |
| `exec-seams-trace-only` | 3/3 | **THE PORT's FAST DEVICES EXIST AS PORTS AND THEIR SEAMS ARE *TRACE-ONLY* -- **THAT |
| `exec-fast-lane` | 3/3 | **A MNIST FORWARD PASS IN THE PORT's OWN LANGUAGE RUNS IN 0.17 s (THE JS LANE) OR 0.46 |
| `exec-cpu-seam` | 3/3 | **THE PORT's OWN `CPU` DEVICE NOW COMPILES AND RUNS A KERNEL, AND ITS C IS BYTE- |
| `exec-devlane` | 3/3 | **THE PORT's `Device` LANE HAS EVERY STAGE AND NOTHING DRIVES THEM -- AND THE GAP IS |
| `exec-linrender` | 3/3 | **THE PORT's OWN ARENA REACHES THE PORT's OWN RENDERER: UPSTREAM's KERNEL, BYTE FOR |
| `exec-devmap` | 4/4 | **THE PORT's OWN `Device` LANE: STAGES **4-9** ARE MEASURED AND GREEN, AND STAGES |
| `exec-rmap` | 4/4 | **THE RANGE MAP: **5 OF 11** ENTRIES AGREE, **0 MISSING**, AND **ALL SIX |
| `PUSH-BLOCKED` | 3/3 | **RESOLVED 2026-10-18T00:17Z: THE PUSH SUCCEEDED.** The corrupt commit |
| `vz-absent-oracle` | 4/4 | FOUND BY THE `actionable` UNIT AS A BYSTANDER, and it is a |
| `rn-recoverable` | 4/4 | MEASURED 2026-10-17 by a dispatched unit, and IT CORRECTED MY OWN |
| `const-identity` | 7/7 | **THE PORT's CONSTANT IDENTITY DIVERGES FROM UPSTREAM's IN BOTH |
| `render-derive` | 10/10 | **744 `py=` CELLS WERE TRANSCRIPTIONS, AND THE FIX IS NOT TO |
| `cite-slice2` | 5/5 | **THE 78 WERE A CLASS, AND THE CLASS IS 1 -- AND THE 1 IS |
| `cite-runtime` | 5/5 | **THE OTHER HALF OF THE 603 IS `runtime/**`, AND IT IS 0.** |
| `cite-slice4` | 5/5 | **THE `.bend`-TO-`.bend` LINE POINTERS ARE 17 FILES AND |
| `no-arrow` | 1/1 | **THE U+21D2 CHARACTER IS GONE FROM THE WHOLE TREE, AND IT IS |
| `ops-python-render` | 1/1 | ``` |
| `wire-pair-control` | 1/1 | ``` |
| `pin-tree-oracle` | 1/1 | ``` |
| `arange-ucache` | 1/1 | ``` |
| `elf` | 20/20 | ``` |
| `unfalsifiable` | 4/4 | the four headline numbers, each with plant+disarm |
| `Progress:` | 5/5 | - [x] **SUB-1** `substrate-check.sh` keeps half 1 (size first, verdict second). VERIFIED |
| `difftxt-contract` | 3/3 | ``` |
| ``checks/*.sh`` | 9/9 | · `.agents/slop/shells/` |
| `two-spellings` | 4/4 | A NEGATIVE RESULT, WHICH IS THE POINT. Three defects found 2026-10-16 were |
| `gatespop-root-spell` | 3/3 | **THE ONE-SPELLING FIX, MEASURED, BUILT, AND THEN REFUSED ON THE |
| `sweep-population` | 3/3 | **THE SWEEP'S POPULATION IS A NAMING SUFFIX -- AND THE CLAIM I BUILT ON IT |
| ``session-instruments` | 20/20 | ` · `corpus-current  [###.........] 3/3` · `ledger-debt  [##........] 2/4` |
| ``link-buf` | 10/10 | ` · `link-plant  [##########] 8/8` · `link-oracle  [#########.] 26/26` · `link-consumer [… |
| ``ops-python-count` | 9/9 | ` · `ops-python-plant  [#########] 9/9` |
| ``port-edits` | 22/22 | ` · `instruments  [##########........] 10/14` · `corpus-current  [####........] 4/4` |
| `x86-derive` | 9/9 | 774 LITERAL `py=` cells -> 0 in `renderer/isa/x86.bend`. |
| `specfold-lane` | 3/3 | **A **LANE **THAT **EXHIBITS `d4160980e`'s **DIVERGENCE **EXISTS, **AND **IT **GOES **RED… |
| `pin-cite-false-positives` | 5/5 | **THE **GATE **REPORTED **516 **CITATIONS **THAT **HOLD |
| `absence-class` | 5/5 | **THE **CENSUS **HAD **NO **CLASS **FOR **A **CITATION **WHOSE |
| `decode-numbers-js` | 3/3 | **THE DECODE'S 2,814 NUMBERS ARE PARSED IN JS NOW, AND THE WALL CLOCK |

---

## Open categories, in full

### wgsl-perf  `[##########]` 10/10

wgsl-perf     [##########] 10/10      THE WGSL TURN IS ~22x FASTER: 24,862 ms -> ~1,110 ms, AND
                                         THE WGSL IS BYTE-IDENTICAL (3,773 bytes, sha256
                                         366d44bb...eea30) AT EVERY STEP.
                                         THE **SEVEN **CHANGES, **AND **EVERY **ONE **IS **MEASURED**:
                                         **THE **FOLD **WAS **A **KAHN **SORT, **AND **THE **ARENA's
                                         **INDEX **ORDER **IS **ALREADY **A **TOPOLOGICAL **ORDER**
                                         (`.agents/slop/wgslperf/topo-check.py`: **0 **VIOLATIONS **IN
                                         **1,698,277 **EDGES **OVER **1,815 **FOLDS**), **⇒⇒† AND **SO
                                         **THE **FOLD **IS **ONE **FORWARD **PASS** -- **⇒⇒† AND **THE
                                         **SORT **COST **495,015,580 **CONSUMER **VISITS**, **5,333,512
                                         **ARENA **WALKS **AND **866,746 **TABLE **COPIES **A **TURN**.
                                         THE **TABLE **IS **PREPENDED, **NOT **APPENDED** (**A **CONS **IS
                                         **O(1)** **AND **`List.append` **IS **O(n)**), **⇒⇒† AND **AND **THE
                                         **TABLE **IS **A **SPINE **OF **CHUNKS**, **⇒⇒† AND **AND **A
                                         **LOOKUP **IS **~31 **CELLS **AND **NOT **~383**
                                         (`.agents/slop/wgslperf/prof-read.py`: **THE **FLAT **LOOKUP **WAS
                                         **35.7% **OF **THE **TURN**). **AND **THE **RANGE **TABLE's **PUT
                                         **WAS **12.8%** (⇒⇒† AND **THE **PROFILE's **CALL **TREE **NAMES
                                         **THE **CALLER**) **⇒⇒† AND **AND **IT **IS **A **CONS **NOW**.
                                         **AND **THE **OP **INTERNING's **COMPARISON **IS **HALVED**:
                                         **THE **WANTED **NODE's **OP **VALUE **IS **HOISTED **OUT **OF
                                         **THE **SCAN** (⇒⇒† AND **`Ops.value` **IS **A **SIXTY-ARM
                                         **MATCH**, **⇒⇒† AND **41,973,508 **CALLS **AND **1,684,550,390
                                         **TAG **COMPARISONS **A **TURN**), **⇒⇒† AND **AND **THE **SRCS,
                                         **THE **ARG **AND **THE **TAG **ARE **COMPARED **ONLY **WHEN
                                         **THE **OP **MATCHES** (⇒⇒† AND **`Bool.and` **EVALUATES **BOTH
                                         **OF **ITS **ARGUMENTS**): **21,325,576 **CALLS **AND
                                         **801,275,119 **TAG **COMPARISONS**, **⇒⇒† AND **AND **`eq_arg`
                                         **20,735,255 -> 1,136,865**. **AND **THE **RANGE **TABLE **IS
                                         **A **SPINE **OF **CHUNKS** (⇒⇒† AND **THE **SAME **SHAPE **AS
                                         **THE **FOLD's **OWN **TABLE**). **AND **THE **ARENA's **NODES
                                         **ARE **CHUNKED** (⇒⇒† AND **`O.Arena.at` **WAS **21.5% **OF **THE
                                         **TURN** **AND **492,349,364 **CELLS **WALKED **A **TURN**),
                                         **⇒⇒† AND **AND **THE **NODE's **DEPTH **IS **IN **THE **NODE**
                                         (⇒⇒† AND **THE **DEPTH **IS **ZERO **FOR **EVERY **NODE**,
                                         **⇒⇒† AND **17,554 **NODES, **ALL **ZERO**, **⇒⇒† AND **AND **A
                                         **PARALLEL **`shp` **LIST **IS **A **SECOND **SOURCE **OF
                                         **TRUTH**).
                                         **AND **THE **INTERNING's **SCAN **STOPS **AT **THE
                                         **MATCH** (⇒⇒† AND **THE **MATCH **IS **AT **A **MEAN **INDEX
                                         **OF **147.7 **OF **~244**, **⇒⇒† AND **AND **THE **OLD **FORM
                                         **WALKED **~40% **MORE **NODES **THAN **IT **NEEDED **TO**).
                                         **AND **THE **NODE **CARRIES **THE **OP's **NUMBER** (⇒⇒† AND
                                         **`Ops.value` **IS **A **SIXTY-ARM **MATCH **AND **THE
                                         **INTERNING **ASKED **FOR **IT **21,325,576 **TIMES **A **TURN**,
                                         **⇒⇒† AND **AND **THE **NUMBERS **ARE **THE **DECLARATION
                                         **ORDER** **AND **THEY **DO **NOT **MOVE**). **AND **THE
                                         **ARENA's **DEFAULT **NODE **IS **BUILT **ONLY **ON **A **MISS**,
                                         **AND **THE **TOPOSORT's **CACHE **IS **CONCED** (⇒⇒† AND
                                         **`List.append` **COPIES **THE **WHOLE **LIST**).
                                         THE **SEVEN **CHANGES **OF **THIS **UNIT**: **THE **TURN
                                         **3,373 **ms -> ~1,110 **ms **OF **WALL** (⇒⇒† AND **AND **THE
                                         **WGSL **IS **BYTE-IDENTICAL**, **⇒⇒† AND **AND **THE **CORPUS
                                         **IS **GREEN **ON **THIS **TREE** (⇒⇒† AND **38 **OF **38
                                         **GRAPHS **AGREE, **38 **BYTE-IDENTICAL, **expect-moved=0**,
                                         **⇒⇒† AND **AND **340 **OF **340 **FILES **IDENTICAL **ACROSS
                                         **TWO **CLEAN **RUNS**, **⇒⇒† AND **AND
                                         **`gates/corpuswitness-gate.py` **READS **`claim state=OK
                                         **verdict=REPRODUCIBLE`**).
                                         THE **NEXT **LEVERS, **AND **THEY **ARE **MEASURED** (⇒⇒† AND
                                         **V8's **OWN **PROFILE **OF **THE **COMPILED **FORM **AT **1,226
                                         **SAMPLES**): **THE **INTERNING's **SCAN **IS **16.1%** (⇒⇒† AND
                                         **THE **EARLY **EXIT**, **⇒⇒† AND **AND **THE **MATCH **IS **AT
                                         **A **MEAN **INDEX **OF **147.7 **OF **~244**) **⇒⇒† AND **AND
                                         **`Ops.value` **IS **11.6%** **⇒⇒† AND **AND **`List.append` **IS
                                         **8.3%** (⇒⇒† AND **THE **ARENA's **FLAT **LIST **IS **O(n) **TO
                                         **APPEND**) **⇒⇒† AND **AND **THE **FOLD's **TABLE **IS **~9%**
                                         **⇒⇒† AND **AND **THE **GC **IS **3.5%** ✓.
                                         THE RECORD: **`.agents/slop/PARITY.md` **§138.32-§138.46**.

### render-perf  `[########]` 6/9

render-perf     [########] 6/9          THE RENDER IS ~25% FASTER OVER THE THREE LANDED CHANGES, AND
                                         **THE **DECIMAL **COUNT **IS **THE **BIGGEST **OF **THEM**
                                         (44dce3f52, **⇒⇒† AND **THE **PAIRED **MEDIAN **0.8587**
                                         **AGAINST **A **NOISE **FLOOR **OF **0.9427**).
                                         THE THREE: **THE **INDENT **IS **A **TABLE **OF **LITERALS**
                                         (d93deb9b6), **80 **`String.concat`** **CALLS **BECOME
                                         **`++`** (4ec516fc7), **AND **THE **DIGIT **COUNT **IS **A
                                         **CHAIN **OF **COMPARISONS **AGAINST **THE **POWERS **OF **TEN**
                                         (44dce3f52) -- **⇒⇒† AND **THE **STRING **WORK **IS **DOWN
                                         **FROM **0.81 ms **TO **0.15 ms **A **TURN**.
                                         **⇒⇒† AND **THE **CORPUS **CERTIFICATE **IS **GREEN **ON **THE
                                         **NEW **SUBSTRATE** (38/38, 340/340 repro, witness PASS,
                                         **ON **`61d46bff7`**).
                                         **⇒⇒† AND **AND **THE **TARGETS **THAT **ARE **OUT**, **ALL

*…27 more lines in the archive.*

### decomp-census  `[#####]` 3/5

decomp-census   [#####] 3/5          39 rows, 23 exact, 16 declared (11 PROMOTION · 2 WALL ·
                                         1 UNBUILT · 2 FINDING), rc=0. THE 11's STATED CAUSE WAS
                                         FALSE (`UOp.__init__`/`_broadcasted` are not the
                                         inserter; `ElementwiseMixin._broadcasted`,
                                         mixin/elementwise.py:24-32 is) -- corrected in 3 files.
                                         282 entries, ONE measured TARGET multiset
                                         (`u32 263, i64 17, i32 2`), asserted every run; the
                                         hand-written SIX-pair table it replaced read
                                         `u32 263, i64 14, i32 5` and COULD NOT BE CHECKED.
                                         `deleted()` is no longer a COUNT on `lg1`:
                                         `witnesses()` MEASURES ZERO alternative witnesses.
                                         **A CAST'S `ADt` IS IN THE TOKEN (`OP/NSRC[TARGET]`)
                                         AND 12 OF 13 MUTATIONS THAT BREAK ONLY IT MOVE A ROW.**
                                         Mutation moved 27/38; 6 of the 11 and all 5 other

*…1 more lines in the archive.*

### upstream-comments  `[######....]` 6/10

upstream-comments [######....] 6/10      **UPSTREAM'S **COMMENTS **PORTED**, **⇒⇒† AND **THE **AUDIT **SAYS
                                         **HOW **MUCH **OF **UPSTREAM'S **REASONING **THE **PORT **CARRIES**:**
                                         **2,406 **UPSTREAM **COMMENT **BLOCKS**, **⇒⇒† AND **495 **PORTED**
                                         **(21.2% **OF **THE **2,339 **SCORED**)**, **⇒⇒† AND **1,618
                                         **`GAP-NO-CITATION`**, **97 **`GAP-CITED-NO-REASONING`** (A **STAMP**),
                                         **129 **`GAP-DIFFERENT-REASONING`**, **⇒⇒† AND **AND **THE **PORT
                                         **CARRIES **1,557 **COMMENT **BLOCKS **OF **ITS **OWN** (⇒⇒† AND **IT **IS
                                         **NOT **A **TRANSCRIPT**)**. **⇒⇒† AND **THE **RATE **IS **WILDLY
                                         **UNEVEN**: `schedule/multi.py` 30/36, `schedule/rangeify.py` 30/49,
                                         **⇒⇒† AND **`mixin/op.py` 2/99, `renderer/x86.py` 1/126 (⇒⇒† AND **THE
                                         **PORT **CITES **`x86.py` **62 **TIMES **BY **`symbol=`** **AND **CARRIES
                                         **1 **OF **ITS **126 **COMMENT **BLOCKS**)**.
                                         **⇒⇒† AND **THE **BIGGER **FINDING **IS **THE **PORT'S **OWN
                                         **CITATIONS**: **THE **AUDIT **FOUND **103 **BAD** (72 **OUT-OF-RANGE**),

*…15 more lines in the archive.*

### backward-walk  `[#########]` 1/3

backward-walk   [#########] 2/3      THE SHAPED-EDGE REDUCE LANDED (`670e480fa`): `g1` went
                                        `RESHAPE[MUL/6,STACK/1]` -> `RESHAPE[RESHAPE/6,STACK/1]`,
                                        `sh_g1`/`sh_w1n` `:0:` -> `:4:1x1x2x2`; CPython measured
                                        (`gw=(1,1,1,2,1,2)`) and the oracle is FD-checked
                                        (`tstep-oracle.py`, rel 1.2e-5). Remaining: the metadata
                                        pass. `compute_gradient` + `_deepwalk` LANDED in
                                        `mixin/gradient.bend`. **15/15 rows AGREE with
                                        CPython**, headline `walk_row=MUL/2 ADD/2 ADD/2 |
                                        grads_n=6` == `oracle_dag_walk` +
                                        `oracle_dag_grads_n`. 72 pre-existing rows
                                        BYTE-IDENTICAL. `plant_reverse` moves 7 rows,
                                        `plant_noguard` moves 3, TWO DISARMS move 0 --
                                        and `plant_noguard` LEAVES `walk_grads_n` AT 6,
                                        which is the measured reason the row is a
                                        signature and not a count.
                                        `.agents/slop/BACKWARD-WALK.md`,
                                        `.agents/slop/backward/walk-{row.txt,plant.md}`,
                                        `walk-mutate.sh`. G-1..G-8 appended at
                                        bend2-constraints.md 24665+.

*…2 more lines in the archive.*

### turn-cost  `[######..]` 6/7

turn-cost       [######..] 6/7      **THE SHIPPED DAEMON TURN**, AGAINST `ClangRenderer`'s
                                         0.12-2.54 ms. **MEASURED ON THE 782-UOP WIRE, WITH
                                         CLOCKS **INSIDE** THE DAEMON** (`PARITY.md` §136):
                                         wall **3.97 ms** = read 0.73 (MOSTLY THE CALLER's WAIT)
                                         + **decode 0.99** + **render 2.26** + ~0.99 (THE CALLER's
                                         ROUND TRIP), **THE PORT's OWN SHARE IS 82%**.
                                         **§137 CUT THE **RENDER** BY 13%** (THE OP EQUALITY:
                                         A 75-ARM CHAIN BECAME ONE COMPARISON PER LITERAL), AND
                                         THE **WHOLE TURN** IS **0.9432**. `same C: True`.
                                         **§138 CUT THE **DECODE** TWICE**: **(a)** THE WIRE WAS
                                         SPLIT **TWICE** -> ONE EFFECT, ONE SPLIT, TWO LISTS IN A
                                         `Data` TYPE (VERDICT **0.8526**); **AND (b)** EVERY
                                         PAYLOAD FIELD RE-SPLIT THE PAYLOAD -- 258 PRELUDE
                                         `String.split` CALLS A TURN -> **113** (VERDICT

*…67 more lines in the archive.*

### walkthroughs  `[######...]` 6/7

walkthroughs    [######...] 6/7      E2E-PROVES-COMPUTE 1/1  <- runs/e2e/

### clangshim  `[#######...]` 7/10

clangshim       [#######...] 7/10    ONE generated .c, ONE import, ONE cc:
                                        **324 bindings -> 308 laws -> 305 LINKED ->
                                        290 CALLED**, each step measured twice.
                                        Stage 3 falsifiable row 8/8, with the plant
                                        (set 0/5/7 -> get 0/5/7) AND its paired
                                        disarm (5 twice -> 5). Stage 1 one
                                        function. Stage 4 all 19 drops attributed.
                                        **Not a device runtime: E2E-PROVES-COMPUTE
                                        is still 1/1 and these are signatures that
                                        link and return values.**
                                        See `.agents/slop/clangshim/CLANGSHIM.md`.
                                        S-1..S-14 appended at bend2-constraints.md
                                        24580+.

### gate-disagree  `[#########]` 9/10

gate-disagree   [#########] 9/10    dtype rows 209, 7 disagreements (was 19). +28 `f2f` rows:
                                        the whole float-decomp region, previously UNREACHABLE
                                        from `main` and therefore ungated for a whole session.

### dtype-js-abi-gate  `[#########.]` 6/10

dtype-js-abi-gate [#########.] 6/10  **`checks/abi_gate.py` HAD TWO STALE CONSTANTS AND NO
                                        DECLARATION; it now runs, and its red is 2 clusters.**
                                        **`parents[2]` -> `parents[0]`** (right only at
                                        `.agents/slop/abi/`, 3 levels down; `57d0fc387`
                                        moved the file up two and repointed every CITATION
                                        while carrying both CONSTANTS). **`checks/abi.json`
                                        WAS DELETED, not misplaced**: `371cc64c9` ("sweep:
                                        3,603 FILES DELETED") removed
                                        `.agents/slop/abi/abi.json` (441 lines) two commits
                                        BEFORE the move -- so the slop->checks move carried
                                        nothing, it found nothing to carry. Restored
                                        BYTE-EXACT (`46db02f2`, one blob for its whole
                                        life) and verified against the CALLER, not just for
                                        existence: 0 shape errors, all 9 generated-body

*…42 more lines in the archive.*

### lane-liveness  `[###########]` 13/15

lane-liveness   [###########] 13/15  census: the 39 wired lanes tabulated
                                       LIVE/RECORDED/TAUTOLOGICAL; repair pass:
                                       **38 of 39 now run both sides; 31 of those 38
                                       compare values that CAN differ; 7 print
                                       BYTE-IDENTICAL stdout (1,408 of 7,917 shared
                                       rows) and `rebase-gate.py` now SAYS SO on every
                                       run; 1 lane still compares ZERO rows
                                       (`dtype.bend`, a PORT defect).**
                                       6-lane census matrix: 5 ARMED, 1 DISARMED
                                       (`dtype-gate.py`). 5-lane repair matrix: 5 ARMED.
                                       See `.agents/slop/LANE-LIVENESS.md` (census) and
                                       `.agents/slop/revive/REVIVE.md` (repair).
                                       L-1..L-11 at bend2-constraints.md 23557+,
                                       V-1..V-13 appended at 24347+.

### dup-rows  `[#########.]` 8/10

dup-rows        [#########.] 8/10   10 = census, usb, ops_nv-oracle, ops_nv-port, hcq2,
                                       llvmir, tc_ptx, fold-dup, fold-93, guard. 8 CLOSED
                                       or CLASSIFIED, 2 need a `.bend` edit this unit must
                                       not make. 78 live lane texts / 39 ports: 11 of 78
                                       texts carried a duplicate, 48 measurements lost,
                                       RECONCILES 130 = 82 cont + 0 `=` + 48 dup. usb FIXED
                                       (75 -> 0, oracle-only, 0 names renamed, port bytes
                                       unmoved). **ops_nv ORACLE FIXED 27 -> 0** (see
                                       NVDUP below), so the tree now reads 21 and RECONCILES
                                       103 = 82 cont + 0 `=` + 21 dup.
 nv-backends     [##########] 10/10  `runtime/ops_nv.bend` + `runtime/ops_nvme.bend`, and
                                       THEIR GATES. **THE BRIEF SAID `ops_nv.bend` WAS "0 LINES" AND IT
                                       WAS A 94-LINE TOMBSTONE** -- a comment header describing a body
                                       that commit `564733bed` deleted BY ACCIDENT (a 1378-file

*…36 more lines in the archive.*

### false-fails  `[#########]` 9/10

false-fails     [#########] 9/10     The apostrophe guard LANDED (`checks/cites-census.py:394`,
                                       `(?<![\w`])'([^']{4,})'`) and PASSED the bar: on one frozen
                                       snapshot it retired 16 FAIL rows and silenced 0 PASS rows
                                       (M=0 < N=16), so it is not REFUTED. Every REFUSED guard
                                       keeps its measured N/M in
                                       `.agents/slop/residual/REPORT.md`. Of the 51 NEW FAILs,
                                       30 are FALSE (23 FALSE-SHAPE, 7 FALSE-SUBJECT), 19 are
                                       TRUE-STALE and 2 are TRUE -- both of those corrected
                                       (51 -> 49). The immovable pair: `WITHIN-LIMITS` (absent
                                       from the file -> false FAIL) and `ARTIFACTS-FRESH` (present
                                       -> true PASS) have IDENTICAL SHAPE and OPPOSITE verdicts.

### repro-anchor  `[##........]` 1/3

repro-anchor [##........] 1/3      THE FIX I LANDED 2026-10-15 WAS READING **ONE FIFTH** OF ITS OWN
                                       POPULATION, and a dispatched unit found the proof. Removing the
                                       SUFFIX SET was right and stands; the **ANCHOR** was never
                                       right. `REF`'s `(?:^|\s)` requires the path to start a line or
                                       follow whitespace, and **MARKDOWN WRITES A PATH IN BACKTICKS** --
                                       so the character before it is a backtick, not a space. Same
                                       for `"..."` in Python: `checks/rn-gate.py:74` spells
                                       `ORACLE = [".agents/slop/xd1/render-gate-oracle.py", "--gate"]`
                                       and that oracle is **ABSENT from disk, ABSENT from HEAD, and
                                       its whole `.agents/slop/xd1/` DIRECTORY IS GONE**. **A LIVE
                                       GATE NAMES AN ORACLE THAT DOES NOT EXIST**, invisible to the
                                       instrument whose whole subject is that paths must exist.
                                       MEASURED over the same 543 reports: named **716 -> 3473**
                                       (**4.9x**), dangling **108 -> 434**, **LOST: NONE** (a strict

*…38 more lines in the archive.*

### ledgerdrift  `[#####.....]` 1/3

ledgerdrift [#####.....] 1/3      DISPATCHED UNIT 2026-10-15. `.agents/TOOLS.md` names **367** paths
                                       (denominator: 1,637 backtick spans in the committed file, byte-equal
                                       to the worktree); **235 present, 132 absent**, **1 of the 132 is an
                                       INSTRUMENT**: `.agents/slop/xd1/render-gate-oracle.py`, invoked by
                                       literal at `checks/rn-gate.py:74`, absent from disk and HEAD --
                                       **the same defect `repro-anchor` found independently.** The other
                                       131 are prose. **THREE CONTRADICTIONS FOR ONE DENOMINATOR, all
                                       stated plainly:** `TOOLS.md`'s header says 164/169/85; its own
                                       generator's `toolsledger/paths.tsv` says 160/173/96; `AGENTS.md`
                                       says 153/180. **AND THE GENERATOR ITSELF IS A WRONG INSTRUMENT**:
                                       `.agents/slop/toolsledger/extract.py:29-32` resolves every token against ONE base (the repo
                                       root), but the ledger does not write paths from the root
                                       (`uop/ops.bend` means `tinybendygrad/uop/ops.bend`), so re-running
                                       it as written keeps reporting drift that IS NOT DRIFT. The unit

*…8 more lines in the archive.*

### shapecensus  `[####......]` 1/3

shapecensus [####......] 1/3      DISPATCHED UNIT 2026-10-15. **226 instruments / 244 rows**,
                                       enumerated by `rglob("*.py")` over `checks/` (72) + `gates/`
                                       (154) -- no document's list contributes a row. Classified:
                                       **acceptable 41, neutral 110, NOT ACCEPTABLE 93 of 244.**
                                       Confirmed FIXED: `LIVE_UNITS` (`:768` is the tombstone),
                                       `gates-pop.py HOMES` (an AST measurement at `:1504`),
                                       `verdicts.py PROSE` (my 2026-10-15 fix, confirmed present).
                                       **STILL PRESENT: `artefacts_ok()`'s `present` arm is
                                       `D.glob("*.txt")` at `checks/differ.py:1131`** even though
                                       `MISSING`/`UNEXPECTED` now run off `declared()` -- **the same
                                       population, two mechanisms, in one function.** The unit also
                                       caught `gates/rng_graph_census-gate.py:104-106` **commenting
                                       "THE TWO DISCOVERY RULES ... Eleven is `grep -c` (MEASURED) ...
                                       Neither is typed from a table of rows" while typing

*…8 more lines in the archive.*

### UNPUSHED-DELETES  `[#####.....]` 1/3

UNPUSHED-DELETES [#####.....] 1/3  **LOUDER THAN THE PUSH BLOCKER, AND FOUND BY THE `unpushed` UNIT.**
                                       MEASURED 2026-10-17 over the **49-commit** range
                                       `52d77134b..c0795853a`: **THREE pins files are ON
                                       `origin/master` AND ABSENT FROM LOCAL `HEAD`** -- confirmed
                                       directly:
                                       `gates/oracleblind.rows`, `gates/assertlit.rows`,
                                       `gates/falseclaim.rows`. **THEY EXIST ON DISK, BUT GIT'S INDEX
                                       HOLDS `e69de29b` (the EMPTY blob) FOR ALL THREE, so they are
                                       UNTRACKED and a commit right now would DELETE THEM FROM THE
                                       TREE.** And one is a **REQUIRED INPUT of a live gate**:
                                       `gates/oracleblind-census.py:118` sets
                                       `REPORT = HERE / "oracleblind.rows"`. **AND I MIS-STATED WHY, VERIFIED AND CORRECTED 2026-10-17:**
                                       `02329daf`'s OWN MESSAGE NAMES ALL THREE --
                                       *"LIVE WORK AND ARE **NOT** IN THIS COMMIT*: gates/assertlit.rows,

*…21 more lines in the archive.*

### stale-ref  `[####......]` 1/3

stale-ref [####......] 1/3      MEASURED over the tracked tree: **103 sites read a remote-tracking ref;
                                       EXACTLY ONE obtains the remote's state from git rather than from
                                       the ref cache -- and it is a GitHub ACTION, not an instrument.**
                                       Split: **SELF-REFRESHING 1 · STALE-CITATION 35 (34%) · SOUND 29 ·
                                       MENTION 38.** **`gates/git-massdelete-gate.py` `mode_push` IS THE
                                       TEMPLATE**: it takes the sha from git's pre-push stdin, so it is
                                       STRUCTURALLY IMMUNE without fetching. **A STALE CITATION THAT
                                       REACHED A TRUE VERDICT**: `UPSTREAM-PIN.md:22` says `59 commits
                                       ahead`; true when taken, now **212 commits behind** the pinned
                                       sha and **271** behind `upstream/master` -- the LABEL rotted
                                       while the number looked current. **`duptree/REPORT.md:36` cites
                                       `origin/master is 52d77134b` -- AND `TODO.md` PROVES THAT WAS THE
                                       CACHED VALUE** while `ls-remote` said `473d7ce98`; cache and
                                       remote agree TODAY, which is exactly why it is invisible. The

*…5 more lines in the archive.*

### corpus-MIXTURE  `[#####.....]` 1/2

corpus-MIXTURE [#####.....] 1/2  **THE 31/2/34 READING IS NOT A MEASUREMENT OF ONE TREE, AND EVERY NUMBER I
                                       QUOTED THIS SESSION IS AFFECTED.** MEASURED 2026-10-18T20:32Z by
                                       calling `checks/differ.py`'s OWN `substrate_bad()` in-process (no
                                       compile): **`substrate-start=a842e832` but
                                       `substrate-end=7f84fd3d` -- "THE SUBSTRATE MOVED WHILE THE RUN WAS
                                       IN FLIGHT, so `D/` holds a MIXTURE of two substrates and no
                                       artifact set here describes one thing."** `checks/differ.py`
                                       itself was modified at **20:29:01Z** and the summary rewritten at
                                       **20:32** -- **THE GATE MOVED WHILE THE RUN WAS IN FLIGHT.** A
                                       dispatched unit's replay identifies the moved member exactly:
                                       **1 of the 156 declared inputs**, `checks/differ.py`, and
                                       restoring that one member's sha folds the digest back to
                                       `a842e832` exactly. **SO: `graphs-agree=31` IS A COUNT OVER
                                       ARTIFACTS FROM TWO TREES, AND 10 OF 17 PINS ARE INDEPENDENTLY

*…6 more lines in the archive.*

### digest-residue  `[##########]` 2/3

digest-residue [##########] 2/3  **AFTER MY `f62666ad6`, THE DIGEST PINS 387 INPUTS AND COVERS
                                       `tinygrad/*.py` 213/213 -- CONFIRMED. THE RESIDUAL GAP IS
                                       NAMED AND SMALL.** Correctness inputs **387 of 389 = 99.5%**;
                                       whole-run coverage by file count is **387 of ~1351 ~ 29%**.
                                       Two UNCOVERED drivers, both named: **`.agents/slop/
                                       graphcmp-dbg.bend`** (run by `graphcmp.py:3021`) and
                                       **`.agents/slop/graphcmp-empty.bend`** (`differ.py:903`'s
                                       `else` branch, which IS TAKEN -- the comment claiming it was
                                       deleted is now FALSE). **A GREP CENSUS MISSED THE FIRST
                                       ENTIRELY AND INVENTED FOUR PHANTOM DRIVERS FROM
                                       DOCSTRINGS.** **`bin/bend` RESOLVES TO
                                       `references/bend/bend2/main.ts`: PHYSICALLY IN THE REPO,
                                       VERSIONED NOWHERE (`git ls-files references` = 0), so the
                                       digest pins a 5-LINE POINTER and not the 93-FILE POINTEe --

*…5 more lines in the archive.*

### comment-cut  `[#######.]` 7/8

comment-cut        [#######.] 7/8      **THE **PORT's **COMMENT **MASS **IS **CUT **BY **THE
                                         **RULE **AND **THE **RULE **HAS **FOUR **DEFECTS **THAT
                                         **THE **CUT **FOUND**, **AND **EVERY **ONE **OF **THEM
                                         **IS **A **CLASS **ANOTHER **UNIT **ALSO **FOUND** **AND
                                         **REPAIRED**.
                                         **THE **RULE** (`AGENTS.md:16`, **`.agents/slop/comments/RULE.md`**):
                                         **A **COMMENT **EARNS **ITS **PLACE **IN **ONE **OF
                                         **THREE **WAYS** -- **DIFFERENCE** (**WHAT **THE **PORT
                                         **DOES **THAT **UPSTREAM **DOES **NOT**, **NAMING **THE
                                         **UPSTREAM **LINE**), **WEIRD** (**WHY **SOMETHING **LOOKS
                                         **WRONG **BUT **IS **NOT**), **MEASURED** (**THE **NUMBER
                                         **THAT **JUSTIFIES **THE **CODE**). **EVERYTHING **ELSE
                                         **IS **NARRATION** **AND **NARRATION **IS **WHAT **GETS
                                         **CUT**.

*…260 more lines in the archive.*

### nn-laws  `[##........]` 1/3

nn-laws [##........] 1/3   **LAWS ARE THE RIGHT MECHANISM FOR PART OF THIS, BUT THE SPEC IR CANNOT
                                       YET STATE THE LAWS -- AND THE PROOF GATE IS ALREADY RED.**
                                       MEASURED 2026-10-19. `LAWS.bend` holds **35 laws, BY NAME**:
                                       `reshape_preserves_numel`, `permute_preserves_numel`,
                                       `flip_preserves_numel`, `pad_numel_is_the_new_shape`,
                                       `shrink_numel_is_the_new_shape`,
                                       `stack_numel_is_the_leading_axis_times_the_operands`,
                                       `reduce_numel_divides_by_the_reduced_axes`,
                                       `broadcast_is_elementwise_max`, the ALU decompositions
                                       (`neg_is_mul_by_minus_one` ... `mulacc_is_add_of_mul`),
                                       `store_matches_its_buffer`, `max_dim_idempotent`,
                                       `zip_max_idempotent`. **A LAW IS AN EQUATION PROVED BY
                                       REFLEXIVITY BETWEEN A CLAIM IN `spec/tinyspec.tex` AND THE CODE
                                       THAT EMITS IT** -- `LAWS/alu.bend`'s own header: *"the spec's

*…26 more lines in the archive.*

### nn-layers  `[#######...]` 3/7

nn-layers [#######...] 3/7     THE LAYERS LAND, AND ONE OF THEM FOUND A REAL DEFECT IN A FILE IT DOES
                                       NOT OWN. `tinybendygrad/nn/layers.bend` (64 defs, 613 lines,
                                       `ALL PROOFS CHECK` -- WARM, not COLD) and
                                       `tinybendygrad/nn/pool.bend` (573 lines, same). **BOTH
                                       PREMISES OF THE BRIEF WERE WRONG AND FINDING THAT OUT IS THE
                                       RESULT.** (1) `relu` WAS ALREADY BUILT at `tensor.bend:774`;
                                       `nn_relu` is a NAME ONTO IT, not a second copy. (2) **`mixin/op.bend`
                                       SIDE B IS EMPTY** -- `:1523` is that file's LAST line, so
                                       `conv2d` had nothing to wait on and was built in `layers.bend`.
                                       (3) **THERE IS NO POOL OP, UPSTREAM OR HERE**: the whole `Ops`
                                       enum (`tinygrad/uop/__init__.py:13-97`) has **0** lines
                                       mentioning pool, and `grep -rn "MAXPOW2|AVGPOW2" tinygrad/` = **0
                                       hits** -- **pooling in this tinygrad is a DECOMPOSITION**, so a
                                       pool could not be "a UOp call missing an op".

*…32 more lines in the archive.*

### five-units  `[#####.....]` 2/5

five-units [#####.....] 2/5   FIVE UNITS, AND THE HEADLINE IS NOT A NEW DEFECT BUT A CORRECTION TO ONE.
                                       **1. `ropfix` -- THE `tn_rop.perm` CANDIDATE IS CORRECT AND PROVEN,
                                       AND ITS BLAST RADIUS IS MEASURED AS ZERO.** Candidate diff
                                       (114 lines, `patch --dry-run` clean, `ALL PROOFS CHECK`) on
                                       `sum(-1)` over `(2,4,3)`: CPython `(2,4)` · BEFORE `(4,3)` ·
                                       AFTER **`(2,4)`**, control axis `[0]` unmoved, and
                                       `[0,2]` `(3)` -> `(4)`. Its graph becomes CPython's
                                       `REDUCE(PERMUTE(RESHAPE(...)),(ADD,1))`.
                                       **BLAST RADIUS: `ZERO OF 34 CORPUS GRAPHS CAN CHANGE** --
                                       `graphcmp.bend` makes **1** `T.tn_*` call (`tn_wrap_uop`)
                                       and **0** `T.tn_rop` calls, every graph being built
                                       node-for-node. **SO THE CORPUS IS 34/34 GREEN *WHILE THIS
                                       DEFECT IS LIVE*, AND ITS GREENNESS IS NOT EVIDENCE EITHER
                                       WAY.** NOT LANDED: `mixin/op.bend`'s `norm0` row moves

*…56 more lines in the archive.*

### nn-path  `[####......]` 2/4

nn-path [####......] 2/4  **TWO REAL DEFECTS ON THE CONV2D PATH, LANDED, AND BOTH UNITS REFUTED A PRIOR
                                       CLAIM WHILE CONFIRMING THE DEFECT.** (1) **`nn_dot.xshape`
                                       USED A HEAD DROP WHERE CPYTHON USES A TAIL SLICE.**
                                       `List.drop` (`references/bend/bend2/base.bend:993`) IS A HEAD
                                       DROP -- MEASURED `drop([2,4,3],1) = [4,3]`, `drop([2,4,3],2) = [3]` --
                                       and `List.take` (`:984`) is its complement, so **`take(xs, k)` IS
                                       `xs[:k]`** and the tree's own `uop/fold.bend:485 drop_last` is
                                       the same idiom. **NO ARGUMENT VALUE TURNS A HEAD DROP INTO A
                                       TAIL DROP**, so the prior unit's "one argument" fix was REFUTED
                                       -- and its OWN report says its control replaced the whole TERM
                                       with a literal, so that control never proved the rule either.
                                       FIXED with a new `nn_tail_drop` (2 lines) and the port's OWN
                                       rows now move from **`<EMPTY>`** to CPython's answers:
                                       `dot_2d` -> `2,4`, `dot_1d` -> `2`, `linear` -> `2,10`, and

*…31 more lines in the archive.*

### freshness-reach  `[###.....]` 1/3

freshness-reach [###.....] 1/3  **A GOVERNING DOCUMENT'S CLAIM WAS HALF FALSE WHILE IT LIVED, AND THE
                                       UNIT CAUGHT IT.** `AGENTS.md` claimed *"13 FRESHNESS INSTRUMENTS,
                                       0 REACHABLE FROM ANY SURFACE ... `.github/workflows/` HAS 9 FILES
                                       AND 0 NAME A GATE"*. **MEASURED: 10 workflows, and `edge-gates.yml`
                                       DOES NAME THE CHAIN** -- `edge-gates.yml:96` -> `gates/edge-runner.py`
                                       -> `checks/gatesweep.py` -> the 13 -- and it landed 16h36m AFTER
                                       the census was taken (`ac186c3d9`), so the census was never
                                       re-run. **THE CLAIM IS GONE FROM `AGENTS.md` NOW (the concurrent
                                       session rewrote it), so there was nothing left to correct; the
                                       finding is kept here as the record.**
                                       **BUT THE CHAIN IS SEVERED AT ONE NODE**: `gates/edge-trace.rows:6`
                                       READS `checks/gatesweep.py OVER-BUDGET SKIP MEASURED-30.31s`, so
                                       **THE REACHABILITY IS REAL AND THE EXECUTION IS NOT.** And the
                                       census's own predicate is BYTE CONTAINMENT -- **a COMMENT IS

*…16 more lines in the archive.*

### commit-recipe-race  `[##]` 2/3

commit-recipe-race   [##] 2/3  **THE PRESCRIBED COMMIT RECIPE SWEEPS 40 OF 40 TRIALS UNDER A RACE, AND THE HAZARD
                                       FIRED ON ME.** MEASURED 2026-10-22 at HEAD `a50ec806e`, instrument
                                       `.agents/slop/idxrace/idxrace.py` (Python, throwaway repo, no `bend`, no
                                       corpus, no network). **THE INCIDENT: MY OWN COMMIT `64169355a` CARRIED 866
                                       DELETIONS ACROSS 5 PATHS -- INCLUDING `tinybendygrad/device.bend` (441 LINES, A
                                       SUBSTRATE FILE) AND THREE `.agents/slop/linkbuf/` TOOLS (422 LINES) -- BECAUSE
                                       THE RECIPE WAS `PARENT=$(git rev-parse HEAD); git read-tree "$PARENT"; git add;
                                       git commit`, AND ANOTHER UNIT COMMITTED BETWEEN THE `rev-parse` AND THE
                                       `commit`.** THE COMMIT'S TREE WAS THE OLD TREE, SO IT REVERTED 5 PATHS AND
                                       DELETED 4 OF THEM. **`git show --stat` CAUGHT IT** (which is why `AGENTS.md`
                                       mandates it), AND THE CONCURRENT SESSION **RE-LANDED IT ON TOP** (`4f189e21c`:
                                       *"RE-LAND of fa8d62f01 -- a concurrent commit REVERTED IT, and the remedy is to
                                       re-land, never to reset"*) WITHOUT BEING ASKED. **THE BYTES ON DISK WERE NEVER
                                       TOUCHED** (`git read-tree` without `-u` does not touch the working tree), so

*…13 more lines in the archive.*

### substrate-break  `[###]` 2/4

substrate-break      [###] 2/4  **THE COMMITTED TREE DID NOT COMPILE, AND THE TREE'S OWN GATES SAID SO BY REFUSING
                                       RATHER THAN ANSWERING.** MEASURED 2026-10-22T07:4xZ: `gates/nn-rows-gate.py`
                                       ANSWERED **REFUSED (3)** ON THE LIVE TREE, NAMING `uop/ops.bend:8951` -- AND A
                                       SECOND AGENT INDEPENDENTLY MEASURED THE SAME THING AT 04:16Z WITH A
                                       **DIFFERENT** ERROR, BECAUSE **THE BREAKAGE MOVED UNDER IT.** ISOLATING IT:
                                       `git archive HEAD tinybendygrad` INTO A SCRATCH AND RUNNING `--check-only`
                                       SHOWED **HEAD'S PORT DID NOT COMPILE.** TWO BREAKS, BOTH COMMITTED: **(1)
                                       `uop/weak.bend:395` `wk_derived` BUILT A 6-FIELD `F.Derived` WHILE
                                       `uop/fold.bend:688` `Derived` HAS 8 FIELDS (`dt, shape, dev, addr, base,
                                       unbase, sbase, ended`) -- INTRODUCED BY `0e9a93435` (THE COMMIT THAT ADDED THE
                                       `unsharded_base`/`storage_base` FAMILY), WHICH ADDED THE TWO FIELDS AND NEVER
                                       UPDATED `weak.bend`. **THE ERROR ONLY SURFACED WHEN THE FILE WAS *IMPORTED*,
                                       NOT WHEN IT WAS CHECKED ALONE** -- SO `fold.bend --check-only` SAID `ALL PROOFS
                                       CHECK` WHILE `mixin/op.bend --check-only` SAID THAT IT EXPECTED A `Derived`

*…11 more lines in the archive.*

### ops-rule1-family  `[##]` 2/3

ops-rule1-family     [##] 2/3  **FOUR `match`-ON-A-CALL SITES IN ANOTHER UNIT'S IN-FLIGHT `uop/ops.bend` POISONED THE
                                       WHOLE SUBSTRATE, AND I REPAIRED THEM IN THE WORKING TREE WITHOUT COMMITTING THE
                                       FILE.** MEASURED 2026-10-22T07:35Z: `ops.bend:8951` `match Char.is_digit(c):`
                                       -- BEND RULE 1, A MATCH CANNOT SCRUTINISE A COMPUTED VALUE -- AND THE ERROR
                                       POISONED **EVERY** FILE THAT IMPORTS `uop/ops.bend` (`ops.bend`, `fold.bend`,
                                       `mixin/op.bend`, `mixin/movement.bend`, `mixin/rand.bend`, `tensor.bend`,
                                       `nn/layers.bend`, `nn/pool.bend`, `nn/item.bend` -- 9 OF 9 FAILED `--check-
                                       only`), **AND BEND REFUSES TO EXECUTE A PROGRAM WHOSE IMPORTED PROOFS FAIL**,
                                       SO THE SUBSTRATE WAS DEAD FOR EXECUTION. **IT WAS A FAMILY, NOT ONE SITE:
                                       FIXING ONE MOVED THE ERROR TO THE NEXT.** THE FOUR SITES WERE `fs.sp.dim.digit`
                                       (:8951), `fs.step` (:9045), `fs.step.io` (:9050) AND `fs.sz.go` (:9068). **THE
                                       REPAIR IS THE PORT'S OWN IDIOM: A `.of` DEF THAT TAKES THE `Bool` AS A
                                       *PARAMETER* AND A CALLER THAT COMPUTES IT** -- `pm_r_tag_m.of` (ops.bend:4429)
                                       AND `pm_sub_m.of` (ops.bend:4454) ARE THE SAME SHAPE -- WHICH ALSO KEEPS THE

*…9 more lines in the archive.*

### argmax-ported  `[####]` 3/4

argmax-ported        [####] 3/4  **THE RECIPE IS PORTED AND VERIFIED; THE GRAPH IS REFUSED WITH THE MEASUREMENT.**
                                       `tinybendygrad/nn/argmax.bend` IMPLEMENTS UPSTREAM'S `Tensor.argmax` RECIPE
                                       (`tinygrad/mixin/op.py:863-887`) ON A LIST, AND **THE TIE-BREAKING RULE IS A
                                       CONSEQUENCE OF THE FORMULA** (`arange(n,0,-1)` IS `[n..1]`, SO `idx[j]` IS `n -
                                       j` AT A MAXIMUM, SO `idx.max` PICKS THE SMALLEST `j` AMONG THE MAXIMA -- THE
                                       FIRST OCCURRENCE) RATHER THAN AN ASSERTION ABOUT IT, WHICH IS WHY THE TIE ROWS
                                       CAN BE CHECKED. **6 OF 6 ROWS GREEN ON THE COMMITTED TREE PLUS THE `weak.bend`
                                       FIX, AND `ALL PROOFS CHECK`; AND THE `want` VALUES ARE UPSTREAM'S, NOT THIS
                                       FILE'S OUTPUT -- THE ORCHESTRATOR RE-CHECKED ALL SIX AGAINST CPython IN `.venv`
                                       INDEPENDENTLY: 0 DISAGREEMENTS OF 6.** **AND THE GRAPH-LEVEL `argmax` IS
                                       REFUSED, WITH THE MEASUREMENT: `probe.bend` ASKS FOUR QUESTIONS AND Q4 -- CAN
                                       THE PORT PRODUCE AN INDEX VECTOR ALONG THE AXIS -- **FAILS**: THE `arange`'s
                                       SHAPE READS EMPTY **THROUGH BOTH THE FOLD AND THE MOVEMENT WALK** (ASKED TWICE
                                       BECAUSE `examples/beautiful_mnist.bend` RECORDS THAT THE TWO DISAGREE ON AN

*…7 more lines in the archive.*

### item-ported  `[###]` 3/4

item-ported          [###] 3/4  **`Tensor.item` IS PORTED TO THE EDGE THE PORT CAN REACH, AND THE WALL IS NAMED.**
                                       UPSTREAM (`tinygrad/mixin/op.py:22-32`) IS AN `assert self.numel() == 1` AND
                                       THEN A **READ**: A REALIZED DEVICE BUFFER COPIED TO THE HOST AND REINTERPRETED
                                       THROUGH THE DTYPE'S `fmt` (`tensor.py:285-301`, `:274-283`), WITH THE DTYPE'S
                                       BYTE WIDTH (`dtype.py:63`) AND A WEAK DTYPE COMMITTED FIRST (`tensor.py:294`,
                                       `mixin/dtype.py:16-17`). **THE PORT HAS THE PRECONDITION AND THE DTYPE HALF,
                                       AND HAS NO WAY AT ALL TO DO THE BUFFER HALF**: `uop/ops.bend:5296` SAYS *"NO
                                       LIVE `Buffer`"*, `engine/realize.bend:60` LISTS `realize.py:145 exec_copy` AS A
                                       FOREIGN EFFECT, AND `nn/onnx.bend:49` SAYS *"Nothing in this port can read a
                                       byte out of a tensor"*. **SO `tinybendygrad/nn/item.bend` PUTS UPSTREAM'S
                                       PRECONDITION FIRST -- A MULTI-ELEMENT TENSOR IS UPSTREAM'S `AssertionError`,
                                       VERBATIM, AND THE PORT DOES **NOT** RETURN THE FIRST ELEMENT -- THEN READS FROM
                                       THE ONE PLACE A VALUE EXISTS (A CONST NODE'S `APy{v}`) WITH `commit_dtype` FOR
                                       THE WEAK-DTYPE COMMIT, AND NAMES A REFUSAL EVERYWHERE ELSE.** THE RESULT IS A

*…11 more lines in the archive.*

### brief-citation-error  `[##]` 2/3

brief-citation-error [##] 2/3  **I ASSERTED A MEASUREMENT I HAD NOT MADE, IN A WORKER'S BRIEF, AND IT PROPAGATED. THIS
                                       IS THE SESSION'S OWN CLASS AND I WAS THE OFFENDER.** MEASURED 2026-10-22: I
                                       BRIEFED AN AGENT WITH *"**MEASURED**: `Buf.at` EXISTS -- A BUFFER ELEMENT READ
                                       -- THIS IS THE MOST LIKELY PRIMITIVE `item` IS BUILT ON"* AND *"`mo_at` --
                                       INDEXES A TENSOR"*. **BOTH ARE FALSE.** `Buf.at`
                                       (`runtime/ops_python.bend:836`) ANSWERS *THE B-TH BUFFER IN A LIST OF BUFFERS*
                                       -- THE PYTHON BACKEND'S ARGUMENT BINDING -- AND RETURNS A `Buf`, **NOT A
                                       SCALAR**; AND `mo_at` (`mixin/op.bend:316`) IS `enumerate(self.shape)`'S INDEX,
                                       **A SHAPE HELPER, NOT A TENSOR INDEX**.** **WHAT I HAD ACTUALLY MEASURED WAS
                                       THAT THE *NAMES* EXIST. I CONFLATED EXISTENCE WITH SEMANTICS, WHICH IS EXACTLY
                                       THE RECURRING CLASS THIS TREE KEEPS FIXING -- AN INSTRUMENT (OR A BRIEF)
                                       READING ONE SPELLING OF A THING -- **AND I LABELLED IT `MEASURED`, WHICH IS THE
                                       ONE THING A CITATION MUST NEVER BE.** THE WORKER CAUGHT IT AND SAID SO IN ITS
                                       REPORT, WHICH IS THE SYSTEM WORKING; **BUT THE ERROR WAS MINE AND IT WAS

*…7 more lines in the archive.*

### mo-at-forward  `[####]` 3/4

mo-at-forward        [####] 3/4  **`mo_at` COUNTED THE INDEX FROM THE END, SO EVERY RANK>=2 KEEPDIM REDUCE AND EVERY
                                       RANK>=2 REDUCED COUNT WAS WRONG -- AND NOTHING IN THE TREE COULD SEE IT.**
                                       MEASURED 2026-10-22. `mixin/op.bend`'s `mo_at` ANSWERED `len(t)` -- THE TAIL'S
                                       LENGTH -- WHILE ITS THREE NEIGHBOURS ARE ALL **FORWARD**: `mo_dim_at` READS
                                       `mo_dims` AT A FORWARD INDEX, `mo_resolve` ADDS `total` TO A NEGATIVE AXIS
                                       (UPSTREAM'S `_resolve_dim`, reduce.py:15), AND `mo_range` BUILDS `0..n-1`. SO
                                       THE PORT'S AXIS LIST IS FORWARD AND THE WALK'S INDEX WAS NOT. **THE
                                       CONSEQUENCES, AGAINST CPython IN `.venv`: THE KEEPDIM TARGET FOR `(2,2)` ON
                                       AXIS `[0]` IS `(1)(2)` (reduce.py:18) AND THE PORT ANSWERED `(2)(1)` -- THE
                                       ORDER IS WRONG EVEN ON A SQUARE; THE REDUCED COUNT FOR `(2,3)` ON AXIS `[0]` IS
                                       2 AND THE PORT ANSWERED 3; AND `nn/layers.bend:230` HAD ALREADY MEASURED IT ON
                                       `(2,4,3)` WITH AXIS `[2]`, WHERE `mo_keep_ds` ANSWERED `(1,4,3)` AND CPython
                                       ANSWERS `(2,4,1)`.** **AND NOTHING COULD SEE IT: THE PORT'S ONLY RANK-2 FIXTURE
                                       IS `(2,2)` -- WHERE THE COUNT IS ACCIDENTALLY RIGHT BECAUSE THE TWO DIMENSIONS

*…20 more lines in the archive.*

### verdict-hunt  `[##]` 2/3

verdict-hunt         [##] 2/3  **NO BOUNTY WIN, AND A REAL UPSTREAM BUG IN THE #1182 FAMILY -- IN THE OPPOSITE
                                       DIRECTION.** MEASURED 2026-10-22 AT `v2.0.37` / `4ff8545`. REPORT:
                                       `.agents/slop/verdict-hunt/REPORT.md` (21 KB), CANDIDATES AND 89 RECEIPTS
                                       BESIDE IT. **THE CLOSEST RESULT IS `c10_ctxdead.bend`: `--verdict` PASSES
                                       (rc=0, `ALL PROOFS CHECK`) AND THE BendTT THE KERNEL ACTUALLY READS CONTAINS A
                                       **LIVE** KERNEL TERM OF TYPE `Empty` -- `(λ{(,): λ{}} x0)`, WHICH IS `Prj(Efq)
                                       x0`, AND `Prj(Efq) : ∀x0 : Empty -> P` FOR ANY `P`.** **IT IS NOT THE BOUNTY:
                                       THE REGION IS UNREACHABLE IN BEND'S OWN CHECKER (`ctx_dead`), SO THE `Empty` IS
                                       NEVER A VALUE OF A RUNNING PROGRAM, AND THE DEF'S TYPE IS A **FUNCTION** `Empty
                                       -> ... -> Empty`, NOT `Empty`.** **THE ROOT CAUSE, NAMED: bend2's CHECKER
                                       (`bend.ts:3626-3631`) ALLOWS AN EMPTY MATCH `match x:` WITH NO CASES WHEN
                                       `ctx_dead(book, ctx)`, AND `ctx_dead` (`bend.ts:842-853`) MEANS *SOME LIVE
                                       BINDER IN THE CONTEXT HAS AN EMPTIED-ADT TYPE* -- WHILE `safe.ts:746-758`
                                       ANSWERS THAT MATCH WITH THE `s.empty` BRANCH, I.E. WITH A **LIVE VALUE OF AN

*…13 more lines in the archive.*

### safe-ts-trust-gap  `[##]` 2/3

safe-ts-trust-gap    [##] 2/3  **THE LEAN SIDE IS CLOSED, SO THE TRUST GAP IS THE 1,573 LINES IN FRONT OF IT.**
                                       MEASURED 2026-10-22 AT `v2.0.37`: `references/bend/bend2/bendtt.lean` IS
                                       **3,895 LINES / 172,753 B** AND IS THE WHOLE KERNEL *AND* ITS CLAIMS *AND*
                                       THEIR PROOFS (its own header, lines 8-13: *"1. THEORY ... 2. CLAIMS ... 3.
                                       PROOF"*). **A SEARCH FOR `sorry` / `admit` / `axiom` / `native_decide` /
                                       `unsafe` / `@[implemented_by]` FINDS **NONE**; THE 16 HITS ARE ALL `partial
                                       def` IN THE `.bendtt` TEXT PARSER.** SO THE KERNEL'S TRUST BASE IS THE LEAN
                                       COMPILER PLUS THE C COMPILER BEHIND `leanc -O3`, AND **THE KERNEL IS CLOSED**.
                                       **AND THAT IS WHY THE BOUNTY IS HARD, AND IT IS THE MOST IMPORTANT THING THE
                                       HUNT FOUND: `--verdict` **DOES NOT CHECK THAT THE TRANSLATION IS FAITHFUL**.**
                                       `bend2/main.ts:808` `cli_verdict` DOES `book_promises(book)` AND THEN
                                       `Safe.safe_check(book)`, AND `safe_check` (`safe.ts:1570`) IS `safe_book(book)`
                                       -- **THE 1,573-LINE TYPESCRIPT ELABORATOR** -- FOLLOWED BY
                                       `kernel_check(got.text)`, WHICH RUNS THE LEAN KERNEL. **THERE IS NO SECOND

*…15 more lines in the archive.*

### mnist-e2e  `[###]` 3/4

mnist-e2e            [###] 3/4  **AN END-TO-END MNIST RUNS ON THE BEND DEVICE AND AGREES WITH CPython -- AND IT COSTS
                                       7 MINUTES 17 SECONDS PER IMAGE, WHICH IS 303.9 DAYS PER EPOCH.** MEASURED
                                       2026-10-27, IN `.agents/slop/mnist/REPORT.md`. **THE MODEL:
                                       `tinybendygrad/nn/mnist_cnn.bend` (278 LINES) IS **GENERATED** BY
                                       `.agents/slop/mnist/gen_mnist_cnn.py` FROM THE CPython MODEL's CONSTANTS -- SO
                                       NO `want=` IN IT IS TYPED BY HAND, **AND THE PORT's COPY OF THE MODEL AND THE
                                       RUNNING MODEL CANNOT DRIFT APART SILENTLY.** **THE GATE:
                                       `.agents/slop/mnist/oracle_shapes.py` READS **15 ROWS, 15 MATCH, 0 MISMATCH**
                                       -- NINE SHAPE ROWS COMPARED AGAINST CPython's OWN `nn.Conv2d(...)(x).shape`,
                                       `Tensor.max_pool2d(...)`, `Tensor.flatten(1)` AND `nn.Linear(...)(x).shape`,
                                       THREE GRAPH ROWS COMPARED AGAINST A FIXTURE-MATCHED CPython CONSTRUCTION, AND
                                       TWO POOL ROWS COMPARED AGAINST THE GENERATED `want=`. **THE DATA PATH: MNIST
                                       PREPARED AS `.npy` AND READ WITH **THE PORT's OWN `ops_npy` DEVICE** -- **NO
                                       HTTP, NO GZIP, NO TAR, NO JPEG, NO PIL.** **THE TRAINING: ON CPython's `CPU`

*…22 more lines in the archive.*

### exec-apply  `[###.]` 3/4

exec-apply           [###.] 3/4  **THE APPLY REWRITE: **THE **GRAPH'S SHAPE** NOW MATCHES CPYTHON's.**
                                       MEASURED 2026-10-29, IN `.agents/slop/rangify/APPLY.md`. **THE PORT's OWN
                                       `tinybendygrad/schedule/rangify.bend` NOW APPLIES UPSTREAM's
                                       `pm_apply_rangeify` **AS A **FIXED POINT** (UPSTREAM's
                                       `unified_rewrite` LOOP, `ops.py`), **AND THE **FIVE RULES** IN
                                       UPSTREAM's ORDER (`.agents/slop/rangify/rr-rules.py` **ASKS UPSTREAM's OWN
                                       MATCHER ABOUT EVERY NODE**), **AND THE MAP IS **THE (OLD, FINAL) PAIRS**
                                       WITH **THE FRESH NODES** (`INDEX`, `END`, `STAGE`) FINALISED TOO.
                                       **THE PORT's `rr_out` IS **22** NODES AND CPython's IS **27**,
                                       **8** AGREE, **AND THE **OP CENSUS MATCHES** EXCEPT FOR `ADD` — **AND
                                       `ADD` IS **THE AFFINE EXPRESSION** (`_apply_reshape`), **AND THAT IS
                                       **THE `symbolic` REWRITER** WALL (W-A). **AND THE COMPARISON IS
                                       `.agents/slop/rangify/cmp-out.py`, **NODE FOR NODE**.**
                                       ****WHAT IS STILL OPEN:** **THE `symbolic` REWRITER** (W-A) **AND THE

*…4 more lines in the archive.*

### exec-wa  `[##]` 2/5

exec-wa             [##] 2/5  **W-A -- THE AFFINE EXPRESSION: **ONE MISSING RULE**, NOT A MISSING MODULE.**
                                       MEASURED 2026-10-30, IN `.agents/slop/rangify/WA.md`. **AND THE TREE's PROSE
                                       SAID THE PORT HAS *"NO `symbolic` REWRITER"*, AND **THE PORT HAS **FOUR OF THE
                                       FIVE RULES** W-A NEEDS, ALREADY PORTED** -- **AND THE PROSE WAS WRONG IN THE
                                       DIRECTION THAT MAKES THE WORK LOOK BIGGER THAN IT IS.**
                                       **AND THE WORK LIST WAS MEASURED BY ASKING UPSTREAM's OWN CODE, NOT BY
                                       REASONING ABOUT IT**: `.agents/slop/rangify/rr-reshape.py` BUILDS THE
                                       **UNSIMPLIFIED** EXPRESSION WITH UPSTREAM's OWN `UOp` API AND PRINTS BOTH
                                       SIDES, AND `.agents/slop/rangify/rr-reshape-rules.py` WRAPS THE MATCHER AND
                                       READS `UPat.location`, **WHICH IS `get_location()`**. **27 REWRITE STEPS,
                                       FIVE DISTINCT RULES, EACH WITH UPSTREAM's OWN FILE AND LINE:** `symbolic.py:120`
                                       (`x+0 -> x`, **HAVE**), `symbolic.py:122` (`x*1 -> x`, **HAVE**), `symbolic.py:161`
                                       (`fold_const_alu`, **HAVE**), `symbolic.py:230` (**THE COMMUTATIVE FLIP**,
                                       **MISSING** -- `symbolic.bend`'s OWN INVENTORY NAMES ITS WALL: **`UOp.tuplize`**),

*…14 more lines in the archive.*

### cite-class  `[#########]` 4/5

cite-class        [#########] 4/5  **FOURTEEN UPSTREAM CITATIONS IN `uop/ops.bend` WERE WRONG BY TWO
                                       TO TWENTY-SIX LINES, AND NO INSTRUMENT COULD SEE THEM.** The
                                       `TODO(pN)` population is a SUBSET: `gates/pin-cite-gate.py` reads a
                                       file's HEADER BLOCK and `gates/todo-cite-gate.py` reads the lines a
                                       marker touches, and these sat in the BODY -- in the comment that
                                       explains a rule and points at the upstream line it came from.
                                       **THE CENSUS** (`.agents/slop/citeclass/census.py`, the instrument,
                                       and the rows): 2624 citations tree-wide, **302** carry a marker on
                                       their own line, **2322** are outside the tagged population, and
                                       **603** of those are false at the pin. `remove_all_tags` IS NOT IN
                                       upstream's `ops.py` AT ALL, so the port's rule is named as the port's
                                       own and the SURVIVING construct is cited (`tinygrad/uop/spec.py:207`,
                                       `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`). **THE POPULATION
                                       CHANGED** -- a citation carrying an explicit `symbol=` is now in

*…11 more lines in the archive.*

### cite-slice  `[######...]` 3/5

cite-slice        [######...] 3/5    **THE 603 ARE THE CLASS, AND THE SLICE THAT IS NOT `runtime/**`
                                        WENT FROM 331 FALSE TO 78.** Measured on TWO FROZEN trees
                                        (`git archive` of the base and of the fix) with the SAME
                                        instruments: BEFORE `65b333037` 331 false of 1211 citations
                                        in my slice, AFTER `52c9f5ce5` **78** of 1212. `runtime/**`
                                        is 269 before AND 269 after -- another unit's, untouched.
                                        **61 FILES, 237 LINES, ALL COMMENT-ONLY** (every file strips
                                        to the same code as HEAD through `strip_comments()`, and every
                                        LINE COUNT is unchanged because 61 of them are cited by other
                                        files). **61 of 61 COMPILE `WITHIN-LIMITS`** under
                                        `checks/bounded.py --mb 2048`, one `bend` at a time. **THE
                                        DURABLE FORM IS `symbol=`, AND IT IS ONLY ADDED WHERE THE
                                        GATE CAN RESOLVE THE SUBJECT** -- that gate's corpus is
                                        `tinygrad/` only, so `examples/llama.py` and an ambiguous

*…13 more lines in the archive.*

### upstream-suite  `[###.........]` 3/3

upstream-suite   [###.........] 3/3   **THE UPSTREAM SUITE IS BEING PORTED ONE FILE AT A TIME,
                                        AND THREE FILES ARE DONE.**
                                        **THE ARCHITECTURE, AND IT IS THE TREE's OWN:**
                                        UPSTREAM's `.py` TESTS CANNOT RUN AGAINST THE PORT
                                        (`import tinygrad` RESOLVES TO THE VENDORED UPSTREAM
                                        PYTHON, AND THE PORT IS `.bend`), SO EACH PORTED FILE
                                        IS **A `.bend` DRIVER THAT CALLS THE PORT's DEFS AND
                                        PRINTS `name=value` ROWS + A `.py` ORACLE THAT BUILDS
                                        THE SAME GRAPH IN CPython's OWN `tinygrad` AND PRINTS
                                        THE SAME ROWS + A GATE THAT DIFFS THEM
                                        POSITIONALLY** (`gates/gatekit.py`).
                                        **AND NO EXPECTED VALUE IS EVER TRANSCRIBED FROM
                                        UPSTREAM's TEST INTO A `.bend` LITERAL.** THE UPSTREAM
                                        EXPECTED VALUES ARE THE ORACLE's JOB; A ROW THAT
- [x] **THE THIRD FILE: `tinybendygrad/uop/divandmod.bend` -- FOUR ARMS AND A
      `UOp.divide_exact` FIX.** AND TWO OF THE WALLS THE HEAD NAMED WERE NOT
      WALLS AT ALL, AND ONE MEASUREMENT WAS **GENERALISED INTO A WALL** AND
      WAS **WRONG**.
      **`factor_remainder` (`divandmod.py:78-91`):** THE NAMED WALLS WERE
      `const_like` (A TODO IN `ops.bend`) AND `new_x.vmin` OVER A SUM, AND
      NEITHER IS ONE -- THE PORT HAS `F.UOp.vmin` OVER A `BTable`, AND
      `const_like` IS NOT NEEDED BECAUSE A **VARIABLE**'s `_shape` IS `()` AND
      SO `x.const_like(0)` IS A BARE `CONST 0` AND NOT AN `EXPAND`.
      **AND TWO SUMS, NOT ONE:** UPSTREAM's `factor_remainder` USES PYTHON's
      BUILTIN `sum` (`:89` AND `:91`), WHICH STARTS WITH THE INT `0`, WHILE
      `remove_nested_mod` USES `UOp.usum` (`:33`), WHICH STARTS WITH THE FIRST
      ELEMENT. THE PORT HAS BOTH.
      **AND THE ARM'S CONSTANT BRANCH (`:83-85`) IS REACHABLE, AND A CONST
      DIVISOR IS NOT AN UNREACHABLE ONE.** THE FIRST DRAFT MEASURED "EVERY
      CONST-DIVISOR SHAPE CRASHES UPSTREAM" AND GENERALISED IT INTO A WALL;
      **THE MEASUREMENT WAS OF THE WRONG SHAPES.** `divide_by_gcd`'s GUARD IS
      `gcd.op is Ops.CONST and gcd.val==1` AND THE GCD IS
      `uops[0].const_like(gcd)` (`ops.py:1037`), SO IT IS A **BARE `CONST`**
      WHEN `uops[0]`'s `_shape` IS `()` -- **A VARIABLE DERIVATION** -- AND THEN
      THE ARM **IS** REACHED. MEASURED 2026-11-25: `(6a+b)//4` ANSWERS
      `ADD(DIV(ADD(ADD(ADD(c0,MUL(MUL(a,c1),c2)),b),c0),c4),ADD(c0,MUL(MUL(a,c1),c1)))`.
      **AND THE PORT's ANSWER WAS A DEEP `ADD(c0, ADD(c0, ...))` NEST INSTEAD, AND
      THE CAUSE WAS NOT THE ARITHMETIC:** THE `quo`/`rem` LISTS HOLD **INDICES**,
      AN INDEX IS ONLY MEANINGFUL IN **ITS OWN ARENA**, AND `UOp.divides` AND
      `UOp.alu` **GROW** THE ARENA -- SO THE TWO TERMS WERE BUILT IN **TWO
      BRANCHES** OF ONE ARENA AND READ EACH OTHER's INDICES, AND A STALE ARENA
      READS THE ARENA's **BOTTOM NOOP NODE**. THE FIX IS **ONE CHAIN**: EVERY
      NODE IS BUILT FROM THE PREVIOUS NODE's ARENA.
      **`nested_div` (`divandmod.py:23-25`):** PORTED, AND IT NEEDS `divides`
      **ALONE** -- `k` IS `x.src[1].divides(c)` AND IT IS A **CONST** QUOTIENT,
      SO `k.vmin > 0` IS A CONST's VALUE AND NOT A `vmin` FOLD. AND `k = 1`
      STILL FIRES, BECAUSE `1 > 0` IS TRUE.
      **AND `UOp.divide_exact` HAD A REAL DEFECT:** UPSTREAM's `new_count` IS
      `Counter(num) - Counter(den)` (`ops.py:1044-1045`) AND ITS TEST IS
      `all(v>=0 ...)` (`:1046`), SO A FACTOR IN THE DIVISOR AND NOT IN THE
      NUMERATOR HAS A **NEGATIVE** COUNT. THE PORT CHECKED ONLY THE OTHER HALF
      AND ANSWERED `divide_exact(6x, y)` WITH A QUOTIENT WHERE UPSTREAM ANSWERS
      `None`.
      **THE ROWS:** `gates/divandmod-cases.rows`'s FOUR `fr_*` ROWS, FIVE `nd_*`
      ROWS AND TWO `frc_*` ROWS, READ BY BOTH THE DRIVER AND THE ORACLE, AND
      `gates/ops-core.bend`'s `de_den` ROW. **THE GATE:** SIXTEEN ROWS, SIXTEEN
      AGREE; `gates/ops-core-gate.py`: FORTY-FIVE ROWS, THREE LANES.
      **THE PLANT:** TWELVE CASES, ALL RED -- THE `+sum(quo)`, THE SUM's LEADING
      `+0`, THE `x.const_like(0)`, THE CONSTANT BRANCH's TEST, THE
      POSITIVE-QUOTIENT GUARD, THE CONSTANT BRANCH's MULTIPLICATION AND **THE
      ARENA THREADING** -- SO EVERY PART IS LOAD-BEARING.
      **AND THE GATE's ROW COUNT IS READ FROM THE CASE FILE** AND IS NOT A
      HAND-KEPT NUMBER, BECAUSE A SECOND COPY OF A LIST A GENERATOR OWNS IS
      WHAT THE AGENT RULES CALL OUT BY NAME.


*…4701 more lines in the archive.*

### `load-census  `[####.....]` 4/7

`load-census [####.....] 4/7` — the ledger, the guard, the retrospective, and the starvation
sweep are DONE; **3 are OPEN and are NOT this unit's files** (`loadwatch.py`, `baseline.json`).

- [x] **THE LEDGER — `.agents/slop/baseline-ledger.{md,txt,json}`.** Every recorded baseline with
      its path, revision, row count, load-or-`UNKNOWN` and verdict. **DENOMINATOR 234, in 13
      files.** `OK 0`, `RE-MEASURED-ALONGSIDE 215`, `SUSPECT 19`. A txt dump is identified against
      `baseline.json` by **ROW-NAME-SET EQUALITY**, never by a typed port name. **NOTHING WAS
      RE-RUN** — no lane was executed to produce a number in the ledger.
- [x] **RECOVERABLE / UNRECOVERABLE: 0 and 234.** A capture records a load in **0 of 234**, an
      elapsed time in **0 of 234**, a **revision in 0 of 234**. So the "source file unchanged"
      half of the test is **UNDECIDABLE, not merely unmet** — there is nothing for the working copy
      to be compared against, so no baseline can be shown to describe the tree it judges. Across
      the whole record layer: **92 of 1,816** sensitive counts load-qualified (**5.1%**).
- [x] **THE MECHANICAL TEST — `load-census.py --guard`**, in the style of `parser_cache_guard()`.

*…805 more lines in the archive.*

### claimaudit  `[####......]` 1/3

claimaudit [####......] 1/3      AN ADVERSARIAL RE-AUDIT OF THE ORCHESTRATOR'S OWN COMMITS, and it found
                                       **10 FALSE claims, FOUR OF THEM MINE.** Selection stated and
                                       reproducible: commits dated 2026-10-16 whose message mentions one
                                       of ten named literals -- **24 commits** -- and the unit says the
                                       cut is ambiguous (a 200-commit window gives 86, a last-20 window
                                       16) and that it chose the boundary it did not invent.
                                       **165 CLAIMS EXTRACTED AND CHECKED: 103 CONFIRMED, 44
                                       UNVERIFIABLE, 8 STALE, 10 FALSE.** **MINE, AND ALL FOUR ARE
                                       CITATIONS OR COUNTS:** (a) `9fad284ea` claimed
                                       `verdict_of`'s unassigned branch is `:98` -- `:98` is blank, the
                                       returns are `:104` and `:107`, **so the original `:97` AND the
                                       correction were both wrong**, in the commit whose subject is a
                                       number that reproduced under no definition (`:107` is now fixed
                                       and verified); (b) `059c22cab` cited lines `267`/`268`/`270`

*…19 more lines in the archive.*

### onespelling  `[##........]` 1/3

onespelling [##........] 1/3      THE CLASS AS AN INSTRUMENT, WITH A CONTROL THAT EARNED ITS KEEP.
                                       `.agents/slop/onespelling/census.py` (543 lines) walks the
                                       COMMITTED tree (`git ls-tree -r HEAD`, never the index),
                                       `ast.parse`s every `.py`, and enumerates **100,951** module-level
                                       literals to find **307 candidate sites** in five kinds.
                                       Verdicts **254 POSITIVE / 27 NEGATIVE / 26 UNKNOWN**, and it finds
                                       all three known positives -- `REF`'s anchor reads **728** names
                                       where a widened one reads **3510**, so **2,782 spellings are
                                       invisible**, with the delimiter histogram measured (backtick
                                       x8,983 dominates). **THE CONTROL REFUSED THREE TIMES DURING
                                       DEVELOPMENT AND EVERY REFUSAL FOUND A REAL BUG**, the first being
                                       that `os.path.dirname` is an attribute OF AN ATTRIBUTE so
                                       `func.value.id == "os"` is false -- **THE INSTRUMENT HAD THE
                                       SECOND SPELLING OF A MODULE AND COULD NOT SEE IT**, which is the

*…11 more lines in the archive.*

### onespelling-precision  `[##........]` 2/3

onespelling-precision [##........] 2/3  **A CENSUS OF 254 FINDINGS NOBODY HAD READ IS NOT A MEASUREMENT,
                                       AND WHAT IT TAUGHT IS ABOUT INSTRUMENT DESIGN, NOT ABOUT THE TREE.**
                                       `.agents/slop/onespelling-precision/` re-ran the census and drew a
                                       hand-labelled sample. **PER-KIND PRECISION, NO POOLED NUMBER**
                                       (a pooled number across kinds with different base rates is the thing
                                       this project keeps refusing): `prose-basename-citation` **11 of 40 =
                                       0.275** [0.161, 0.428], `regex-anchor-set` **1 of 3**, `single-base-
                                       resolver` **2 of 3**; `extension-set` and `module-attr-table` have
                                       **0 positives and therefore no denominator at all**. **THE
                                       STRUCTURAL FINDING BEATS THE NUMBERS.** Every other kind routes
                                       through `probe[kind](site)` and returns POSITIVE / NEGATIVE /
                                       UNKNOWN from evidence (`census.py:196-201`, `:248-259`), but
                                       `prose-basename-citation` is built INLINE at `:453` with
                                       **`verdict="POSITIVE"` WRITTEN INTO THE LITERAL**: there is no

*…29 more lines in the archive.*

### `target-census  `[###......]` 3/6

`target-census  [###......] 3/6` · `target-plant  [#########] 9/9` · `target-roundtrip  [##.......] 2/7`

### 1. **THE DEFECT, AND THE IMPORT GRAPH THAT DECIDES WHERE THE ONE RECORD GOES**

Upstream has ONE `Target` (`tinygrad/helpers.py:198`) and upstream's `uop/ops.py:13` and
`runtime/ops_python.py:9` both IMPORT it from there. The port had TWO, with the same five fields
and DIFFERENT identities -- `runtime/ops_python.bend:2420` (the record, its accessors and the DEV
parser) and `uop/ops.bend:1025` (the record and `Target.of()`) -- so a parsed `Target` could not
go into a `ProgramInfo`, and the two could drift apart with nothing noticing.

`uop/ops.bend` CANNOT import `runtime/ops_python.bend`: the latter imports `../uop/ops.bend`, so the
edge would close a cycle (MEASURED, not remembered -- `.agents/slop/programinfo/a.bend` imports
`b.bend` and `b.bend` imports `a.bend`, and the compiler answers "an import cycle through ...").
`helpers.bend` is a LEAF -- it imports `Base` and nothing else -- and BOTH consumers already import

*…60 more lines in the archive.*

### paramarg-spec  `[##]` 2/3

paramarg-spec [##] 2/3  **THE PORT's `ParamArg` IS MISSING **UPSTREAM's **13th **FIELD** (`spec`).
                       **MY **FIRST **FRAMING **OF **THIS **WAS **WRONG **AND **THIS **IS **THE
                       **CORRECTED **ONE.** MEASURED
                       2026-10-22: upstream's `tinygrad/uop/ops.py:25-42` declares **13** fields --
                       `slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image,
                       buffer, bind_on_realize, val, spec` -- and the port's `tinybendygrad/uop/ops.bend:869-883`
                       declares **12**. **THE MISSING ONE IS `spec: BufferSpec|None = None`** -- *"the
                       memory the linker gives an ALLOC"* -- **AND upstream's `ParamArg.__repr__` INCLUDES
                       `spec` IN ITS `fields` TUPLE**, so the port's rendering cannot show the ALLOC's
                       memory spec at all. **THE **PORT **IS **THE **ONE **THAT **IS **SHORT.**  **AND
                       `rg -c 'ParamArg\{' tinybendygrad/` COUNTS **106 **CONSTRUCTION **SITES** ACROSS
                       **31 **FILES**, **SO **THIS **IS **A **WORK **QUEUE, **NOT **A **DISPATCH.**
                       **AND **THE **CORRECTED **MEASUREMENT, **WHICH **MAKES **IT **A **SMALL **ITEM
                       **AND **NOT **A **BEHAVIOUR **GAP:** **UPSTREAM's `arg.spec` **HAS

*…42 more lines in the archive.*

### fold-graph-arity  `[##]` 2/3

fold-graph-arity [##] 2/3  **`gates/fold_graph_census.bend` **IS **BROKEN **AND **THE **FIX **CHANGES
                       **THE **FIXTURE, **THE **ROWS **AND **THE **GATE's **ORACLE.** MEASURED
                       2026-10-22 by the compile-census unit: the driver passes a **REAL** size, so
                       **dropping **upstream's **`ParamArg.size` **FIELD **LOSES **IT** -- **THE **FIX
                       **IS **THE **PORT's **OWN **`O.UOp.new.param`** (**size **-> **ALLOC **`src[0]`**),
                       **WHICH **IS **THE **SAME **CHANGE **THE **PORT's **`ParamArg` **MADE **AND **THE
                       **SAME **ONE **`paramarg-spec` **IS **NAMING.**  ****THE **ROW **IS **VISIBLE**:
                       **`gates/compile-census-verdict.rows` **CARRIES **A **`FAIL` **ROW **WITH **THE
                       **EXACT **ERROR **FOR **EACH **OF **THE **7 **BREAKAGES.**


### wk-eval-oracle  `[##]` 2/3

wk-eval-oracle [##] 2/3  **`gates/wk-eval-oracle.py` **IS **THE **CPYTHON **HALF **OF **THE **SAME
                       **UPSTREAM **CHANGE, **AND **THE **GATE's **VERDICT **IS **UNCHANGED** -- **REFUSED
                       **BEFORE, **REFUSED **AFTER** -- **THE **REASON **MOVED **FROM **THE **DRIVER
                       **TO **THE **ORACLE.** MEASURED: a PARAM with `src=()` MEANS **`src[0]`** RAISES
                       **`IndexError`**. ****AND **FIXING **IT **WRONGLY **WOULD **TURN **A
                       **`REFUSED` **INTO **A **`FAIL`**, **WHICH **IS **THE **DANGEROUS **DIRECTION.**


### untracked-oracle-fragments  `[##]` 2/3

untracked-oracle-fragments [##] 2/3  **`oracles/probe-su.bend` **AND **`oracles/probe-targetparse.bend`
                       **ARE **UNTRACKED** -- **NEVER **IN **GIT** -- **AND **THE **DIALECT **GATE
                       **REPORTS **34 **"LOST" **CLAIMS **IN **THE **CONTEXT **FILES**, **AND **THE
                       **GATE's **OWN **TEXT **SAYS **SO**: *"judged by their own gate; their 'lost' is
                       **this **gate's **tag **rule **reading **probe **labels, **not **a **missing
                       **row**"*. ****A **FIX **COULD **NOT **BE **COMMITTED **FOR **A **FILE **THE
                       **REPOSITORY **DOES **NOT **OWN.**


### e2e-fixture-render-kernel  `[##]` 2/3

e2e-fixture-render-kernel [##] 2/3  **`checks/.e2e-fixture/{f64/emit-f64,portexec/emit-mm}.bend`
                       **NAME **`C.render_kernel`, **AND **THE **PORT **NO **LONGER **HAS **IT.** MEASURED
                       2026-10-22 by the compile-census unit. ****AND **`checks/e2e.py`'s **STAGE **3
                       **CANNOT **START **BECAUSE **OF **IT**, **WHICH **IS **WHY **THE **EDGE **TRACE's
                       **ONLY **REMAINING **`DEAD` **ROW **IS **`checks/e2e.py`** -- **AND **A **GATE
                       **THAT **CANNOT **START **IS **NOT **"DEAD"**, **IT **IS **`REFUSED`**, **AND **THE
                       **EDGE **NOW **SAYS **SO.**


### spec-pattern-vs-body  `[##]` 2/3

spec-pattern-vs-body [##] 2/3  **A **RULE **WHOSE **MATCH **TEST **IS **IN **THE **BODY **INSTEAD **OF
                       **THE **PATTERN **ANSWERS `False` **WHERE **UPSTREAM **ANSWERS `None`, **AND **THAT
                       **MAKES **EVERY **LATER **RULE **IN **THE **SAME **BLOCK **UNREACHABLE.** MEASURED
                       2026-10-22 by the unit that added upstream's two missing shared rules: upstream's
                       rule 19 is a **PATTERN** (a node whose `src[0]` is not in the set does not *match*,
                       so the rule is **SKIPPED**), and the port had that src-op test in the **BODY** -- and
                       **a `False` STOPS THE FOLD, SO THE PORT ANSWERED `False` WHERE UPSTREAM ANSWERS
                       `None`, WHICH MADE UPSTREAM's RULE 20 UNREACHABLE, AND THE PORT STILL REJECTED
                       `AFTER(ADD(1,2))`. **A **SILENT **WRONG **ANSWER.** **AND **THE **TREE's **OWN
                       **DELTA **INSTRUMENT **COMPARES **THE **RULES' **OP **SETS**, **NOT **THEIR **SRC
                       **SETS**, **SO **THE **INSTANCE **WAS **INVISIBLE **TO **IT** -- **AND **THE **AUDIT
                       **OF **"UPSTREAM **PATTERN **CLAUSES **vs **THE **PORT's **BODY**" **IS **OPEN.**
                       **AND **THE **DISTINCTION **IS **THE **AUDIT**: **A **TEST **ON **THE **MATCHED
                       **NODE **IS **LEGITIMATELY **A **BODY **TEST**; **A **TEST **OF **WHETHER **IT

*…2 more lines in the archive.*

### ledger-pop  `[#######.]` 7/8

ledger-pop       [#######.] 7/8  **THE **FIVE **UNOWNED **ROWS **THE **GATE **REPORTED **WERE
                                         **FIVE **MUTATION-HARNESS **STAGING **COPIES**, **AND
                                         **A **COPY **THE **LEDGER **ADMITTED **IS **A **ROW
                                         **NO **COMMIT **CAN **OWE.** **THE **POPULATION
                                         **NOW **EXCLUDES **THEM **BY **NAME**, **AND **THE
                                         **LEDGER **RETIRES **THE **FIVE **ROWS.**
```

### shader-pad-lane  `[#########...]` 9/11

shader-pad-lane  [#########...] 9/11  **THE SCHEDULE NOW BUILDS THE SHADER'S KERNEL AND THE
                                         RUNNER EMITS ITS C.** THE ROOT CAUSE WAS MEASURED
                                         (THE RANGIFY APPLY KEPT `PAD` AS A WALL) AND THE
                                         PREREQUISITES WERE LANDED; UPSTREAM's PAD ARM
                                         (`indexing.py:169-173`) AND UPSTREAM's ZERO-FILL
                                         (`indexing.py:98-103`) ARE LANDED TOO, SO THE
                                         SCHEDULE BUILDS A KERNEL (`kernels=1`), THE GRAPH IS
                                         `SINK -> AFTER -> (INDEX, CALL)` WITH THREE
                                         BUFFERS, AND THE C IS
                                         `circle(data0_256, data1_256, data2_256)` WITH THE
                                         DISTANCE FIELD's `__builtin_sqrtf` IN IT. FOUR
                                         DEFECTS ARE LEFT AND EACH IS NAMED IN
                                         `shaders/README.md`: THE UNLOWERED `MAX`, THE GATE
                                         THAT DOES NOT RIDE, THE `weakint` DTYPE, AND THE
                                         FOUR RANGES WHERE UPSTREAM HAS TWO. THE PLAN IS
                                         `.agents/slop/shader-pad-lane/PLAN.md` AND THE FULL
                                         HISTORY IS THE ARCHIVE'S `THE MILESTONE` ITEM.

- [x] **THE FIVE UNOWNED ROWS WERE STAGING COPIES.** `gates/.wgsl-mut-oracle.py`,
      `gates/amd-mut-gate.py`, `gates/amd-mut-oracle.py`, `gates/cstyle-mut-oracle.py`,
      `gates/realize-mut-oracle.py`. MEASURED: **no A or D event anywhere in this tree's
      history** (never committed), and each one's own first docstring line names the file it
      COPIES (`amd-mut-gate.py` opens `"""amd_dsl_census-gate.py -- ...`) -- the tree's
      `.gitignore` convention in words: "a mutation harness stages a REVISION of a file".

*…3449 more lines in the archive.*
