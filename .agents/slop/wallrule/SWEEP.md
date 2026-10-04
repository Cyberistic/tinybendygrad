# SWEEP — every recorded wall, and what happened to it. 2026-10-05.

Reproduce: `.venv/bin/python .agents/slop/wallrule/wallcheck.py` (writes `wallcheck.out`)
Read the instrument's reasoning and the disagreement history: `walls.truth.tsv`.

**19 rows. 15 graded against an independently hand-measured truth. 4 refused (3 `RUN`, whose
prerequisite is a re-run and not a symbol). Agreement 15/15, error rate 0/15.**
Outcomes: **4 LANDED · 3 GONE · 3 SPLIT · 5 STANDS · 4 OUT-OF-SCOPE.**

## RETIRED — the capability ARRIVED, or the defect is FIXED. 7 rows.

| id | the wall as recorded | what retired it, and where it landed |
|---|---|---|
| `W1a` | `i64_mul` is absent — "NOWHERE. Not helpers.bend, not dtype.bend, not any tinygrad .py" (`mixin/dtype.bend:52`) | `helpers.bend:2206 def i64_mul(+a: I64, +b: I64) -> I64`, pure. Also `:1819 i64_shl` |
| `W1b` | `i64_div` and `i64_mod` do not exist, so `_min_max` cannot be total (`mixin/dtype.bend:65`) | `helpers.bend:1969 i64_div`, `:2100 i64_mod`, pure. `cdiv_i64:2244` / `cmod_i64:2248` in upstream's own spelling |
| `W2` | `Dt.fp8_from` is blocked on an fp8 seam | `dtype.bend:1060 Dt.fp8_from`, `:1128 float_to_fp8`; the file had grown a DECODER (`Dt.fp8_to:916`) and kept an imported body for the other direction. `grep -c 'import "'` = 0 |
| `W6` | `substrate-check.sh` does not run (`line 245`) | `#!/bin/zsh`, and `zsh substrate-check.sh <files>` prints `SUBSTRATE CLEAN` and exits 0. `sh -n` fails at `:245` — a true measurement of a different interpreter |
| `W7` | `nvdev.bend` has one unguarded `CID` site | `nvdev.bend` has 2 `CID` lines, **both comments**, `:66` among them. There was never a code site to guard |
| `W10` | the store walk is blocked on `is_any` | `UPat.is_any` declared at work `:2002` and HEAD `:2165` |
| `W11` | `dtype.bend`'s 14 seams make every importer red | 0 foreign imports at work and at HEAD; the seams have pure bodies. **Re-verify on load — `OPS-1` records this cold set moving mid-measurement** |

## RE-DATED, NOT DELETED — 8 rows. **This is the majority and it is the finding.**

**The common failure is not that a wall was wrong. It is that nobody re-asked the question
after the answer arrived.** Every row below is annotated with its new date and a recheck
command rather than deleted, because a deleted wall is a wall somebody will re-derive.

### SPLIT — wait for the rewrite. 3 rows. **Both answers are true right now.**

`uop/ops.bend` is **6,306 working lines against HEAD's 8,334**; another unit is mid-rewrite.

| id | HEAD | working copy | note |
|---|---|---|---|
| `W4` | `ParamArg.no_slot` at `:1328`, **10** occurrences | **0** | `O.ParamArg.no_slot` is missing AND present. Which answer you get depends on which tree you read |
| `W8` | `AOpLit{op: Op}` at `:1079`, `eq_arg.AOpLit` at `:1866` | **0** | therefore `noneshape/ns-oparg.bend` compiles or not depending on which tree you ask. **That file says no constructor exists and one now does — it is the record of a fixed hole, and it is the point of the rule** |
| `U7` | `def t_const` at `nvdev.bend:1272` | **0** (2,300 work lines vs HEAD's 2,345) | NV-1's dead def is mid-removal. A half-deleted def is a rewrite in progress, not a retired wall |

### STANDS — the wall's premise is still in the file. 5 rows. All re-dated with a recheck.

| id | where | the finding |
|---|---|---|
| `U1` | `uop/fold.bend:513` | **A FALSE DECISION CITATION, LIVE.** *"`helpers.bend` has `i64_add` and `i64_sub` but no `i64_mul` or `i64_div`"* is the stated warrant for "a dim is not a value this port needs 64-bit arithmetic for". `helpers.bend:2206` and `:1969` declare both. **The decision may still be right and nobody can tell from the file — which is what makes a false premise inside a decision worse than one inside a note** |
| `U2` | `uop/fold.bend:2655` | **A STANDING INSTRUCTION WHOSE TRIGGER ALREADY FIRED.** *"when helpers.bend grows them these defs go there and the callers do not change"* — they grew, and `def mm.u64.{of,lt,le,eq,is_zero}` at `:2681` is a private signed+unsigned ladder beside four helpers helpers.bend now exports. **Nothing polls whether a wall's own remedy arrived** |
| `U4` | `opspy/corpus.py:6` | **THREE FIGURES FOR ONE QUANTITY, ALL THREE IN THE TREE:** `61 of 77` here, `60 of 77` at notes OPS-3, `53 of 77` when the script is actually run |
| `U5` | `uop/weak.bend:15` | names `i64_mul`, `i64_div`, `i64_mod` as missing; all three are declared. Its *other* claim, "there is no F32 min/max", was NOT checked and is **not counted** |
| `U6` | `runtime/ops_python.bend:1469` | `type Args is Data:` — a gather row of `path, gx, gy, gz, vals, ok` — in a file that imports the domain arg type as `O.Arg`. **27 `Args.` uses, 0 `O.Arg`, 47 bare `Arg`, so a grep for `Arg` in that file answers a different question than it appears to** |

## REFUSED — 4 rows. The instrument declines to judge, and says so.

`W3` the `#ifdef CID(x)` C lane · `W5` and `U3` the corpus figures · `W9` the JS NaN payload
census. **A `RUN` row's prerequisite is a re-run, not a text symbol, so it is not graded by a
grep and is not guessed at with a pattern.** Two of the three were re-run by hand:

- `W5`/`U3` — `corpus.py` prints `# UNION over 22 built graphs of 22 declared: 53 distinct ops
  of 77`. `graphcmp.py:1388-1392` declares **22** graphs. The wall's `13 / 34 / 43 not reached`
  is superseded, and so is its own correction.
- `W9` — `NAN kept 8388608 / 16777214   quiet 8388608   signalling 0`. **The loss is exactly
  the signalling NaNs**, so "keeps 0 of 199,999" is superseded by a measurement that ran.
- `W3` — **NOT re-run. This unit ran no compiler**, because two `bend` processes took all
  system memory and crashed the machine on 2026-10-05. Its prerequisite is an emit, and the
  emit is the one artefact that cannot be grepped because it does not exist until something
  generates it. **Left refused rather than answered from the previous generation's transcript.**

## THE WALLS NOBODY RECORDED — `WALL/5`

A grep can only re-measure walls in the ledger, so the ledger's completeness is itself a wall
on the instrument. Four found by reading, none in any ledger:

1. **`#ifdef CID(...)`** — the `CID` macro a `cc` run rejects (`runtime/sz.c:126`), plus SZ-5's
   real point: a guard must wrap the whole C group, not only its `io_eff`.
2. **the `NV` dead arms** — NV-1's `def t_const`; the working copy has already dropped it and
   nobody recorded that.
3. **the `sz.c` stat/lstat shim** — `sz.bend:51`.
4. **the `Args` spelling** — `ops_python.bend:1469` (now `U6`).

## WHAT THE INSTRUMENT GOT WRONG, AND WHY THE ERROR RATE IS THE INTERESTING NUMBER

**Hit rate is 100% — every anchor matches — and that is not the number that matters.** The
informative numbers are **0/15 against an independent truth file** and **4 refusals, reported as
refusals rather than folded into agreement.**

**Four plants, all fired, all files restored byte-identical (`cmp`):**

| plant | expected | got |
|---|---|---|
| rename `def i64_mul(` | W1a flips | `LANDED` → `SPLIT (pin only, work=0 pin=1@2206)` |
| re-add `import "./runtime/dtype.c"` to `dtype.bend` | W11 flips | `GONE` → `SPLIT (work only)` — a **LIVE** defect in the copy that would ship |
| rename `def mm.u64.of(` | U2 flips | `STANDS` → `SPLIT (pin only, work=0 pin=1@2681)` |
| the same plant **before `SPLIT` existed** | must fail | **still `STANDS`** — this is how `SPLIT` was found |

**Five failures, and four of them are the class this unit exists to stop:**

1. **whole-tree patterns** → `PRESENT` for 11 of 11, several matching the wall's own prose.
2. **working copy only** → W4/W8 `STANDS` for capabilities at HEAD.
3. **`runtime/dtype.c emit` is not a path** → a grep of nothing, read as `GONE`, reported as a
   measurement for two instrument generations.
4. **`[[:space:]]` is a nested set to Python's `re`** → one anchor of eighteen could not
   compile and would have graded **forever**. Anchors are translated; the ledger is not
   rewritten, because a second dialect in a second file is a wall of its own.
5. **a coarse anchor cannot fail** → `^def (i64_mul|i64_div|i64_mod|i64_shl)\(` read `work=4`;
   a plant removing one of the four moved it to 3 and the verdict did not change. Split into
   `W1a`/`W1b`; the single-symbol plant now fires. **This is why an error rate needs a
   denominator and a hit rate alone is a sentiment.**

**One labeller, stated rather than hidden.** Every truth row was measured by the agent that
wrote the anchors, so **0/15 is a self-consistency rate** — it cannot catch an anchor and its
truth wrong in the *same* way, which is this project's dominant failure mode. **It earned its
place in its first run anyway: 3 of 18 hand-labels were wrong and the instrument was right on
all three** — `W4`/`W8` read off the working copy alone, and `U7` called a def RETIRED because
the working copy had half-deleted it while HEAD still carries it. **That is the class: the
hand-measured answer was the stale one.**

## NOT MINE, REPORTED

`mixin/dtype.bend`'s header · `uop/fold.bend:513` and `:2655` · `uop/weak.bend:15` ·
`opspy/corpus.py:6` · `noneshape/ns-oparg.bend` · `agent-core.md` (the addition is drafted as
`WALL/7` in `RULE.md`). **No file inside `tinybendygrad/` was created, edited or deleted by this
unit; every plant was restored with `cmp` before the report was written.**