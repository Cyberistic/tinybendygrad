# arenaparam — the 62 self-parenting nodes, the shape choice, and the second corpus run

REPORT of the unit that finished what `1af4ba921` / `4206c96de` left on purpose. Every
number below was produced by a command run in this session; nothing is transcribed from the
prior unit's prose except where a prose claim is explicitly being corrected.

Machine: 16.0 GB `hw.memsize`, so the sum-precondition is 9.6 GB. Every `bend` in this
report ran ALONE, sequentially, under `checks/bounded.py --mb 2048` (corpus: `--mb 4096`),
and the verdict is the `[bounded]` TOKEN, never `$?`.

---

## 0. THE STATE I INHERITED, MEASURED

| what | value | how |
|---|---|---|
| `git ls-files` vs `git ls-tree -r HEAD --name-only` | **8733 vs 7632** | **THE DEFAULT INDEX IS ARMED.** `git diff -- tinybendygrad/` named **30 files changed** on a tree where `git diff HEAD -- tinybendygrad/` named **1**. That is 29 phantom paths. |
| `runs/graphcmp/D/D0-repro.txt` | mtime **Oct 17 01:50**, `repro-files=242 repro-identical=242 repro-rc=rc=0` | `differ.py`'s `repro_bad()` pins only `repro-rc`, so a two-day-old artifact was **satisfying the second-witness pin** while describing a run from before the size→src migration. |
| `runs/graphcmp/D/D0-run-summary.txt` | `graphs-agree=31 graphs-disagree=2`, `substrate-start == substrate-end` | ONE run. Denominator 1. |

## 1. THE THREE FUNCTIONS, BEFORE AND AFTER

**They are UNCHANGED.** Shape (A) does not touch `ops.bend`. This is the whole point of
shape (A) and it is stated here rather than left to be inferred.

`tinybendygrad/uop/ops.bend:2997-3010`, verbatim, before and after:

```python
def shape_to_shape_arg.of(+ar: Arena, +made: Arena, n: Maybe<&2, U32>) -> Found:
  match n:
    case Some{k}: UOp.const(made, CInt{H.i64_of_i32(k)})
    case None{}: UOp.new(made, OpsSTACK{}, Nil{}, ANone{}, TNone{})

def shape_to_shape_arg(+ar: Arena, n: Maybe<&2, U32>) -> U32:
  Found.i(shape_to_shape_arg.of(ar, ar, n))

def param_src(+ar: Arena, n: Maybe<&2, U32>) -> List<&2, U32>:
  [shape_to_shape_arg(ar, n)]
```

The one NEW def is in `tinybendygrad/function.bend`, beside that file's own `fx_node`:

```python
def fx_node.param(+ar: O.Arena, +op: O.Op, size: Maybe<&2, U32>, arg: O.Arg) -> O.Found:
  O.UOp.new.param(ar, op, size, arg, O.TNone{})
```

`shape_to_shape_arg` and `param_src` now have **0 call sites each** and are kept, not
deleted: `gates/arenasrc_census.py` reads that count, and deleting the helper would make the
census's `0` true for a reason that is not "nobody calls it".

## 2. THE POPULATION, DISCOVERED — AND THE BRIEF'S "62 IN 17" IS RIGHT

`gates/arenasrc_census.py` walks `ROOT.rglob("*.bend")` over `tinybendygrad/` (141 files)
and classifies every `param_src(` call by the innermost call that contains it.

```
FILES-WALKED                              141
REFUSED-STATEMENTS                          6   (all in runtime/ops_bend.bend: multi-line string literals)
REFUSED-STATEMENTS-CARRYING-A-SITE          0   <-- the 6 hide no site
TOTAL-param_src-CALL-SITES                 66   BEFORE
CLASS  param_src/O.UOp.new                  62
CLASS  param_src/fx_node                     4
```

**So 66 call sites, of which 62 are `UOp.new` and 4 are `function.bend`'s own `fx_node`
constructor. 62 `UOp.new` sites in 17 files — the brief's figure, confirmed by
measurement, and the 4 `fx_node` sites are a shape nobody had counted.** After the change:
`TOTAL-param_src-CALL-SITES 0`.

Two instruments (`gates/arenasrc_census.py` and `.agents/slop/arenaparam/census.py`) were
written independently of each other and agree on 66 → 0 and on 53 `nil-src` nodes.

### THE INSTRUMENT HAD THREE REAL DEFECTS, EACH FOUND BY A REFUSAL

1. **A FILE-GLOBAL BRACKET STACK IS WRONG.** `codegen/decomp/dtype-mut.bend:2646` is
   `... S.int32()), "# l2i\n"])` — a `#` INSIDE a string. One quote of drift and the pass
   swallows the closing `"])`, leaves the stack open to EOF, and REFUSES a file that
   parses. Fixed by grouping lines until the **running** depth returns to 0.
2. **A FILE-GLOBAL STACK IS ALSO WRONG FOR A DEGENERATE CASE.** `uop/weak.bend:287` opens
   `Bool.pick(` and closes it on 292; a per-line depth test breaks on 293's blank line and
   reports "unbalanced" for a well-formed call.
3. **`depth_of` MUST SKIP STRING SPANS.** `uop/upat.bend:1437` is `String.split(fmt, '{')`
   and a naive character count reads that `'{'` as an opener — nine files reported as
   holding an unclosed statement until this was fixed.

Bend accepts BOTH quote characters; `upat.bend:1426` is `String.split(p, '}')`.

## 3. (A) OR (B) — CHOSE **(A)**, AND HERE IS THE ERROR COUNT THAT DECIDES IT

### (B) MEASURED, ON THE HARDEST SITE

`mixin/movement.bend:1229` is `mxw_buf.of(ar, O.UOp.new(ar, K, O.param_src(ar, Some{size}), ...))`
— the port's own builder, and the one call in the tree where the `param_src` result is an
argument of an ENCLOSING call, so (B) cannot be a textual substitution.

BEFORE: `TOKEN=WITHIN-LIMITS peak=566MB errLines=0`.

Applied (B): `param_src`'s return type → `Found` in `ops.bend`; the site rewritten to bind
`+sf = O.param_src(...)` first. Then:

```
TOKEN=WITHIN-LIMITS  peak=252MB  errLines=1
SOME PROOFS FAIL
Error: - expected : List<&2, U32>   - observed : O.Found
Location: g_add
uop/fold.bend:4308   +b = O.UOp.new(O.Found.ar(s), O.OpsBUFFER{}, O.param_src(O.Found.ar(s), Some{4}), ...)
```

**The error is not at the site I migrated.** It is 4,300 lines away in a file I did not
touch, because bend's type error is global and reports one site at a time. Fixing it:

```
TOKEN=WITHIN-LIMITS  peak=466MB  errLines=1
Location: g_mv_r23
uop/fold.bend:5255   +b = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, O.param_src(O.Arena.empty(), Some{6}), ...)
```

**One error. Then one error again. Two iterations produced two single errors and no
denominator.** The same two numbers a 1-site migration and a 61-site migration both print.
(B) costs 62 edit→check→fix cycles across 17 files, each cycle a full-tree type check, and
at no point does the output tell you how many sites remain. Both files were restored
byte-exactly afterwards (`git diff HEAD -- tinybendygrad/` empty).

### (A) MEASURED, ON THE SAME FILE AND THE LARGEST ONE

`uop/fold.bend` holds 23 of the 62. BEFORE: `TOKEN=WITHIN-LIMITS peak=291MB errLines=0`.
AFTER `UOp.new.param(ar, KIND, size, ARG, TAG)` ×23: **`TOKEN=WITHIN-LIMITS peak=340MB
errLines=0`.** One invocation, zero errors.

The reason is structural and was checkable before running anything: **`UOp.new` and
`UOp.new.param` both take FIVE arguments.** (A) is arity-neutral — it moves the size
expression from the `src` slot to the `size` slot of a five-argument constructor — so there
is no arity cascade to hide a half-done migration in. The brief's "breaks in pieces" is
TRUE of (B) and FALSE of (A), and the two error counts above are what makes the difference
a measurement instead of an opinion.

### THE CLAIM THE REWRITER CHECKS RATHER THAN ASSUMES

(A) is sound only if `param_src`'s arena argument **is** `UOp.new`'s arena argument,
textually. If any site passed two different arenas the rewrite would be a behaviour change.
Every site is compared; a mismatch is a REFUSAL that aborts the whole run. Measured: **0
mismatches in 62 sites.** (`--apply` writes nothing at all if any site refuses — the same
"a partial migration is a build break, not a partial result" rule the prior unit's tool
used.)

### AND THE PRIOR UNIT'S "ONE COMMAND" IS FALSE OF THE TOOL AS SHIPPED

`.agents/slop/sizetosrc/thread_src.py --apply` on the 17 files prints
`TOTAL 62 rewritten, 15 REFUSED` and then **`NOTHING APPLIED`, rc=1**. The 62 are fine; the
15 refusals are the `Nil{}`-src population it *also* reaches for, and it cannot recover
their sizes without a hand list of `AParam` helper signatures (`SIZE_ARG`) — a
doctrine-1 violation in its own right. It writes nothing. My rewriter is the same tool with
that population out of scope.

## 4. THE THREE ACCEPTANCE ROWS, BEFORE AND AFTER

BEFORE — `.agents/slop/sizetosrc/paramsrc_probe.bend` (the only instrument that emitted
these names), `TOKEN=WITHIN-LIMITS peak=319MB`:

```
idiom_Some12    nsrc=1 next=2 op=BUFFER src0=1 src0_op=BUFFER src0_nsrc=1 size=N    <- self-parent
idiom_None      nsrc=1 next=2 op=BUFFER src0=1 src0_op=BUFFER src0_nsrc=1 size=N
threaded_Some12 nsrc=1 next=3 op=BUFFER src0=1 src0_op=CONST  src0_nsrc=0 size=12   <- GOOD
threaded_Some0  nsrc=1 next=3 op=BUFFER src0=1 src0_op=CONST  src0_nsrc=0 size=0
threaded_None   nsrc=1 next=3 op=BUFFER src0=1 src0_op=STACK  src0_nsrc=0 size=N
mxw_buf         nsrc=1 next=2 op=BUFFER src0=1 src0_op=BUFFER src0_nsrc=1 size=N    <- BAD, the port's OWN builder
reintern_4_4=True distinct_4_6=True distinct_0_1=True distinct_0_none=True
```

AFTER — `gates/arenasrc_rows.bend`, `TOKEN=WITHIN-LIMITS peak=380MB`, rc=0:

```
idiom_src0_op=BUFFER idiom_size=N idiom_nsrc=1 idiom_next=2      <- the CONTROL, still bad ON PURPOSE
threaded_src0_op=CONST threaded_size=12 threaded_nsrc=1 threaded_next=3
mxw_buf_src0_op=CONST  mxw_buf_size=12  mxw_buf_nsrc=1 mxw_buf_next=3    <- WAS BUFFER / N / next=2
mxw_buf0_src0_op=CONST mxw_buf0_size=0  mxw_buf0_nsrc=1 mxw_buf0_next=3  <- zero is a shape
fx_buf_src0_op=CONST   fx_buf_size=12   fx_buf_nsrc=1 fx_buf_next=3      <- function.bend's builder
reintern_4_4=True distinct_4_6=True distinct_0_1=True distinct_0_none=True
```

**`next` 2 → 3 is the size CONST being interned at all; `src0_op` BUFFER → CONST is the
node no longer being its own parent; `size` N → 12 is `ParamArg.size` finally being able
to read `src[0]`.** `mxw_buf` — the port's own bottom-of-every-graph builder — is the one
that matters and it moved.

### WHY THE INSTRUMENT MOVED, AND WHY IT IS A NEW `gates/` GATE

The probe lived at `.agents/slop/sizetosrc/paramsrc_probe.bend`. `AGENTS.md` records that a
prune took seven of nine gate drivers out from under gates and that "a gate's required input
belongs beside the gate **in git**". A gate row that lives in a swept directory is a row
that will stop being emitted and nobody will notice. So the driver is now
`gates/arenasrc_probe.bend`, the checker `gates/arenasrc_probe-check.py`, and the population
`gates/arenasrc_census.py`. The file is named **without** the `-gate.py` suffix on purpose:
`checks/gatesweep.py` discovers `gates/*-gate.py` by directory walk, and a new `*-gate.py`
would join the 95-gate sweep and the `gates/gates-pop.ledger.tsv` without being registered.

## 5. THE PLANT

`gates/arenasrc_probe-check.py --plant PATH:LINE` rewrites ONE migrated line back to the
throwaway-arena spelling, re-runs the lane, restores the byte-exact original, and re-runs.

```
$ .venv/bin/python gates/arenasrc_probe-check.py --plant tinybendygrad/mixin/movement.bend:1229
PLANT   tinybendygrad/mixin/movement.bend:1229 -> mxw_buf_src0_op=BUFFER mxw_buf_size=N mxw_buf_next=2
                                         mxw_buf0_src0_op=BUFFER mxw_buf0_size=N mxw_buf0_next=2
RESTORE tinybendygrad/mixin/movement.bend:1229 -> 20/20 rows back
== PASS: the plant moved the row and the restore put it back   rc=0
```

`git diff HEAD -- tinybendygrad/` after the restore is the migration diff and nothing else.

**THE PLANT FAILED FOUR TIMES FIRST, AND EVERY FAILURE IS THE POINT.**

1. `i = j + 1` sat one indent too deep inside a quote-skip `while`, so the string was never
   skipped and every five-argument call read as one argument — **0 of 62 sites planned.**
2. The replacement span started at the callee's `(` instead of its NAME, printing
   `O.UOp.newO.UOp.new.param` in 23 places in `fold.bend`.
3. The splice ended at the opening bracket instead of past the original call's closer,
   keeping the original argument list: `... O.TNone{}(ar, O.OpsBUFFER{}, Some{size}, ...`.
   The lane emitted **NOTHING** — and the first version of the plant check asked only
   "did the row change?", so a **dead lane scored as a successful plant.** It now requires
   *a measured row to change AND no measured row to go absent*, and it reports
   `the planted lane emitted no value for N row(s)` otherwise.
4. `O.UOp.new.param_src` and a bare `param_src` are both "expected : a defined name" —
   `param_src` is a SIBLING of the `UOp` namespace, not a member. The helper name is now
   derived from the sibling relation, not from a name pattern.

**TWO PLANTS ON OTHER SITES CORRECTLY REFUSED**, which is the second half of "a fix with no
plant has not been shown to be able to fail":

```
$ ... --plant tinybendygrad/uop/fold.bend:4308   -> == FAIL: the plant changed no row this gate measures,
                                                      so it is planted somewhere this lane cannot see
$ ... --plant tinybendygrad/tensor.bend:2251     -> == FAIL: (same)
```

`g_add` and `g_buf` are fixture builders in their files' own test sections and do not feed
the measured builders. The gate says so instead of passing. Nothing is bound at import
that the plant moves — `--plant` is read and resolved inside `main()` — which is the
`gapcensus-gate`/`UP`-`PORT` failure this was told about.

## 6. THE 18 FILES RE-VERIFIED — NONE SKIPPED

`bend <file> --check-only`, one at a time, `--mb 2048`, `SPEC=1 DEV=CPU`. The brief names
17; **18 were touched** (`function.bend` additionally, for its own `fx_node` constructor),
so 18 were verified.

| file | TOKEN | peak RSS | errors |
|---|---|---|---|
| tinybendygrad/codegen/simplify.bend | WITHIN-LIMITS | 426 MB | 0 |
| tinybendygrad/engine/realize.bend | WITHIN-LIMITS | 457 MB | 0 |
| tinybendygrad/function.bend | WITHIN-LIMITS | 469 MB | 0 |
| tinybendygrad/mixin/creation.bend | WITHIN-LIMITS | 472 MB | 0 |
| tinybendygrad/mixin/elementwise.bend | WITHIN-LIMITS | 446 MB | 0 |
| tinybendygrad/mixin/movement.bend | WITHIN-LIMITS | 436 MB | 0 |
| tinybendygrad/mixin/op.bend | WITHIN-LIMITS | 415 MB | 0 |
| tinybendygrad/nn/optim.bend | WITHIN-LIMITS | **646 MB** (max) | 0 |
| tinybendygrad/renderer/__init__.bend | WITHIN-LIMITS | 490 MB | 0 |
| tinybendygrad/schedule/__init__.bend | WITHIN-LIMITS | 414 MB | 0 |
| tinybendygrad/schedule/memory.bend | WITHIN-LIMITS | 427 MB | 0 |
| tinybendygrad/schedule/prepare.bend | WITHIN-LIMITS | 465 MB | 0 |
| tinybendygrad/tensor.bend | WITHIN-LIMITS | 454 MB | 0 |
| tinybendygrad/uop/fold.bend | WITHIN-LIMITS | 412 MB | 0 |
| tinybendygrad/uop/movement.bend | WITHIN-LIMITS | 468 MB | 0 |
| tinybendygrad/uop/spec.bend | WITHIN-LIMITS | 479 MB | 0 |
| tinybendygrad/uop/validate.bend | WITHIN-LIMITS | 488 MB | 0 |
| tinybendygrad/uop/weak.bend | WITHIN-LIMITS | 479 MB | 0 |

**18 of 18 verified, 0 skipped.** Largest single peak 646 MB against a 9.6 GB
sum-precondition; the runs were strictly sequential, so the sum never exceeded the max.
`checks/bounded.py` also prints `MACHINE: **VIOLATED** -- loadavg …, swap free 1.10 of
17.00 GiB` on these runs; that is ITS OWN warning about the machine, not the child's
verdict, and the TOKEN is the contract.

## 7. THE BETTER ACCEPTANCE SIGNAL: 7 GATES WENT RED → GREEN, 0 WENT THE OTHER WAY

The prior unit's reason for not running the fix was "it moves node counts in 17 more files
I could not re-verify". Node counts are other instruments' business, so I measured them
rather than argued: `checks/gatesweep.py` over all **95** gates, once with the 18 files
restored to HEAD and once with the migration applied.

```
BEFORE (HEAD)      TALLY: DEAD=3  FAIL=27  PASS=57  REFUSED=7  SKIP=1
AFTER  (migrated)  TALLY: DEAD=3  FAIL=20  PASS=64  REFUSED=7  SKIP=1
verdict changes: 7   -- all FAIL -> PASS, none PASS -> FAIL, none DEAD/REFUSED/SKIP moved
```

```
gates/axisflip-gate.py         FAIL -> PASS
gates/beautiful-mnist-gate.py  FAIL -> PASS
gates/groupflip-gate.py        FAIL -> PASS
gates/mixin-op-gate.py         FAIL -> PASS
gates/mo_graph_census-gate.py  FAIL -> PASS
gates/mx_graph_census-gate.py  FAIL -> PASS
gates/rd_graph_census-gate.py  FAIL -> PASS
```

`mx_graph_census` is the gate whose subject is `mxw_buf` itself. **The 20 gates still FAILing
and the 3 DEAD were already red at HEAD and are unchanged by this work** — including
`paramarg-shape-gate` and `paramarg-site-gate`, which the brief records as settled and which
I did not touch.

## 8. THE CORPUS: TWO RUNS

### 8a. WHY `repro` CANNOT FINISH — MEASURED, NOT GUESSED

`checks/differ.py repro` is two clean runs byte-compared, wrapped in a health gate:
`clean_run()` refuses any run whose `unhealthy()` is non-empty, retries `wait=9` times, and
`cmd_repro` returns 2 when it never is. I called `differ.py`'s OWN `unhealthy()` — loaded by
path, not reimplemented — against the run on disk:

```
unhealthy() -> 7 complaint(s)
  - expect-moved=3 (expected 0)
  - graphs-agree=31 (expected 34)
  - byte-identical=20 (expected 34)
  - stable-pairs=4 of 5 (expected 5 of 5)
  - stable-failed=1 of 5 (expected 0 of 5)
  - oracle-selfcheck=# ORACLE SELFCHECK: FAIL (expected # ORACLE SELFCHECK: OK)
  - census-rc=rc=1 (expected rc=0)
```

**`clean_run` can never succeed on this tree, so `repro` retries to exhaustion and never
returns a verdict.** The "600 s" the brief recorded is that loop, not a ceiling: the
worst case is `2 × 9 attempts × (9 × 60 s substrate probes + a ~182–250 s run + 30 s sleep)`.
I launched `repro` under `--seconds 5400` anyway to measure rather than assume, and killed
it once `unhealthy()` gave the reason.

**AND THE STALE FILE IS NOT MERELY STALE — IT IS GREEN.**

```
repro_bad() -> []   # D0-repro.txt, mtime Oct 17 01:50, reads repro-files=242 repro-rc=rc=0
```

`repro_bad()` pins only `repro-rc`, so a two-day-old artifact from before the size→src
migration is **currently satisfying the second-witness pin**. Anyone reading
`checks/corpus-figure.py`'s `RUN HEALTH` would see it green. **It is named here as STALE,
and it is left on disk unchanged** — `repro` is the only writer of that file and I did not
get a green run to write, so writing a value by hand would be exactly the transcription the
brief forbids.

### 8b. THE TWO RUNS, TAKEN DIRECTLY — **242 OF 242 IDENTICAL**

`checks/differ.py repro`'s health gate cannot pass, so the comparison it exists for was
taken without it: `.agents/slop/arenaparam/tworuns.py` runs `differ.py run` TWICE and
snapshots each with `differ.py`'s OWN `snap()` (sha256 over the non-blank lines of every
declared artifact), byte-compares, and prints `unhealthy()` for each run so the comparison
is read NEXT TO the health verdict rather than instead of it.

```
TOKEN: [bounded] WITHIN-LIMITS  rc=0  peak-RSS=899 MB (ceiling 4096)  357s
# run A: rc=1 in 179s, 242 files snapshotted
# run A unhealthy: expect-moved=3 (expected 0)
# run A unhealthy: graphs-agree=31 (expected 34)
# run A unhealthy: byte-identical=20 (expected 34)
# run A unhealthy: stable-pairs=4 of 5 (expected 5 of 5)
# run A unhealthy: stable-failed=1 of 5 (expected 0 of 5)
# run A unhealthy: oracle-selfcheck=# ORACLE SELFCHECK: FAIL (expected # ORACLE SELFCHECK: OK)
# run A unhealthy: census-rc=rc=1 (expected rc=0)
# run B: rc=1 in 177s, 242 files snapshotted
# run B unhealthy: ... the same 7 ...
TWORUNS: 242 of 242 files identical across two clean runs: True
```

**DENOMINATOR: 242 declared artifacts, 2 runs, 0 differences. THEY AGREE.**
`differ.py run` itself exits **1** on both, because it ends by reading its own pins — the
same 7 complaints. So the verdict is reproducible and the tree is still short of the pins
`PINS` declares, which is a separate question from reproducibility and is not one I fixed.

### 8c. THE CORPUS VERDICT, BEFORE AND AFTER — IT DID NOT MOVE

`diff` of the two summaries, HEAD run vs migrated run:

```
23,24c23,24
< substrate-start=5b8f1f87d4d1cc5069d13f913a1c5c3db987b4c182d0b4aa1e44ac2f02d7e6b0
< substrate-end=5b8f1f87d4d1cc5069d13f913a1c5c3db987b4c182d0b4aa1e44ac2f02d7e6b0
---
> substrate-start=9528bb5e2489ad69fd3b3f99d7bd149e0548bace934560636f40fcf7ffb3191f
> substrate-end=9528bb5e2489ad69fd3b3f99d7bd149e0548bace934560636f40fcf7ffb3191f
```

**The two summaries are byte-identical except for the two substrate rows, and the substrate
rows are exactly the ones that must change** — the migration changed 18 files under
`tinybendygrad/`, and `substrate_digest()` measured **live** agrees with the run's own rows
(`9528bb5e…` both sides). So this is a real HEAD-vs-migrated comparison and not another
HEAD-vs-HEAD:

```
                       BEFORE (HEAD)   AFTER (migrated)
graphs=                     34             34
graphs-answered=            34             34
graphs-unset=                0              0
graphs-agree=               31             31     <- unchanged
graphs-disagree=             2              2     <- unchanged
expect-moved=                3              3     <- unchanged
byte-identical=             20             20     <- unchanged
```

**The corpus is `agree 31 / disagree 2 / unset 0` before and after.** The self-loop was
real, is fixed, and is verified by rows and by 7 gates — and **it was not what the 3
disagreeing graphs disagree about.** Saying otherwise would be the one thing this whole
report exists to avoid.

### 8d. A SUBSTRATE ALMOST FOOLED ME, AND THE CHECK THAT CAUGHT IT

After the killed `repro`, the summary on disk was **byte-identical** to the pre-migration
one, substrate digest included — which reads as "the corpus did not move". It was not a
finding. `substrate_digest()` measured **live** read:

```
substrate_digest() NOW       : 9528bb5e2489ad69fd3b3f99d7bd149e0548bace934560636f40fcf7ffb3191f
summary's substrate-start/end: 5b8f1f87d4d1cc5069d13f913a1c5c3db987b4c182d0b4aa1e44ac2f02d7e6b0
entries in the digest        : 156
```

That run had been taken while my 18 files were **temporarily restored to HEAD** for the
gatesweep baseline, so it compared HEAD against HEAD. **`substrate-start`/`-end` are the
rows that say which tree a verdict is about, and reading the other 21 rows without them is
how a run gets attributed to the wrong substrate.**

## 9. `Nil{}-src`: THE NEXT POPULATION, MEASURED

The brief names "207 `Nil{}-src` SITES". Measured, with the rule stated:

```
ALL Nil{}-src UOp.new sites (any kind): total=88  tracked=68  untracked=20  files=23
   kinds: OpsPARAM 44, OpsBUFFER 10, OpsNOOP 9, OpsSINK 4, OpsSOURCE 3, OpsBINARY 3, ...

AParam-nodes only (a node OWNS A size only if its arg is the param record):
   total=53  tracked=38  untracked=15  files=16
   kinds: OpsPARAM 44, OpsBUFFER 9, OpsALLOC 0
```

So **53, not 207**, and **38 of the 53 are git-tracked** — the other 15 are in untracked
`*-mut.bend` mutation-harness scratch (`op-mut.bend` 7, `realize-mut.bend` 6, `dtype-mut.bend`
1, `.linearizer-mut.bend` 1), which is exactly the population the brief tells me not to
edit or add. **207 matches neither of my two populations**, so either its rule is looser
still or it is a stale figure; I am not going to guess which, and I did not go looking for
a third rule to make it come out.

**This is a DIFFERENT DEFECT from the self-loop and the acceptance rows cannot tell them
apart — both print `size=N`.** `nsrc == 0` is not `nsrc == 1`-with-a-wrong-index: the node
simply has no size node, so `ParamArg.size(ar, i)`, which reads `src[0]`, answers `None`.
The 44 `PARAM` sites are the ones that matter most, because upstream's `ops.py:1222` gives
a scalar PARAM an EMPTY STACK (`ops.py:1003`) and a named PARAM a CONST — so an empty
`src` is right for some of those 44 and wrong for the rest, and **which is which is not a
census question, it is a fold question.** Not acted on: 44 sites is a second migration and
the brief's mandate was the 62.

## 10. FOUND, NOT DONE

- `param_src` and `shape_to_shape_arg` are now dead code with 0 call sites. Kept so the
  census's `0` is a statement about call sites rather than about a deletion.
- The 6 REFUSED statements in `runtime/ops_bend.bend` are multi-line string literals my
  line-local lexer cannot read. **They carry no `param_src` site**
  (`REFUSED-STATEMENTS-CARRYING-A-SITE 0`), so the hole is in the instrument, not in the
  repair.
- `checks/gatesweep.py` names 95 gates and `FAIL=20` of them are red at HEAD. Not mine,
  not touched, not enumerated further.
- `differ.py`'s `repro` worst case is `wait=9` attempts × (9 × 60 s substrate probes +
  a ~182 s run + 30 s sleep) per run, twice. See §8 for what that cost and what I did.