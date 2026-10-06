# `cites2` — the 23 re-derived, the 4 deleted subjects landed, and the instrument measured

Unit `cites2`, 2026-10-07. **STATIC-ONLY: `bend` was NOT run.** Python only, `.venv/bin/python`,
no `.txt`, no commit, no `git add`, no `@`. Discovery walks `checks/*.{py,sh,bend}` with
`.agents/slop/cites2/scan.py` (the `chkcites` walk, re-run) and resolves each cite by NEEDLE with
`.agents/slop/cites2/resolve.py`.

Every number below carries its reading. Several HEADs, because other units commit continuously:

| reading | HEAD | population | resolves | non-resolving |
|---|---|---|---|---|
| before my edits (re-derivation) | `aa457fd251c2` | **36** | 11 | **25** = 16 DRIFT + 4 DELETED + 5 NARR |
| after my 5 edits | `7c07d57026fe` | **31** | 11 | **20** = 16 DRIFT + 4 NARR |
| re-check (HEAD moved under other units) | `6c272be01b9b` → `a004625af377` | **31** | 11 | **20** |

## 0. The count moved: 34 → 36, and why

`chkcites` measured **34** at `b4dc69094`. Re-derived at `aa457fd251c2` the population is **36**:
two cites were added by another unit in `checks/differ.py:177`, both on `ops.bend`
(`:4560` and `:4554`). **The prior `23` is 23 of 34; the class is 25 of 36 at my reading.** The
`.bend:<N>` population is a LIVE population — quoting a count without its HEAD is the defect it
measures.

## 1. The 25 non-resolving at `aa457fd251c2`, by name

RESOLVES **11**: `abi_gate.py:94`, `env-precond.py:48`, `gate_norm.py:242`, `nl-gate.py:16`,
`nl-gate.py:91`, `nvrows-deadrow-gate.py:95/96/213`, `run-port-mm.sh:27`, `stage1-census.py:204`,
`unowned.py:66`.

**16 DRIFT — every one targets a live file** (`ops.bend` 4 locations, `render.bend` 12):

```
differ.py:149        ops.bend:1066    disagree-gate.py:103 ops.bend:1057
differ.py:177        ops.bend:4560    differ.py:177        ops.bend:4554
rn-gate.py:10,26,98,171,250   render.bend:2148
rn-gate.py:40,133,251,399     render.bend:2809-2819
rn-gate.py:51,172             render.bend:2693
rn-gate.py:164                render.bend:2763
```

**4 DELETED — the `cstyle.bend` subjects** (nothing to renumber; §2):

```
e2e.py:55   e2e.sh:228          -> renderer/cstyle.bend:2984-3015  (seven-dtype `rd_row`)
run-f64.sh:411  run-port-mm.sh:29 -> cstyle.bend:1879              (`g_kernel()`)
```

**5 NARR — a recorded position, not a claim** (§5 says why they must NOT be renumbered):

```
nl-gate.py:39, 477   ops.bend:7837   (the port's own failure NAMED `vd_text` at 7837)
nl-gate.py:40, 477   ops.bend:7874   (it then NAMED `vd_dbg.of` at 7874 -- "a different line")
run-port-mm.sh:87    helpers.bend:2551 (a past concurrent edit)
```

## 2. The four DELETED subjects — what died, and was anything replaced? LANDED

**The mass mover is `e51904b04`** (`a3301f1c0` its parent, `git merge-base --is-ancestor` = YES).
Its `cstyle.bend` diff is **ONE hunk**, `@@ -1313,1061 +1313,4 @@`, replacing **1061 lines with 4
marker-comment lines** — the entire test-driver tail. `cstyle.bend` went **2373 → 1315** lines.
**Its message ("four singleton markers, each measured as a genuine absence") does not disclose the
truncation** — the commit that killed these four subjects never says it did. (`564733bed` is an
unreachable jj twin: same parent, same timestamp, a different tree, and the same deletion.)

| subject | what `e51904b04` deleted | moved or died? |
|---|---|---|
| `def rd_row(nm: String, py: String, +dev: U32, +d: S.Dt)` — the seven-dtype dispatch (f32/f16/bf16/bool/u8/fp8e4m3/i32 × six devices) | the def (was `cstyle.bend:1711` at the parent) and its 7×6 call block | **DIED.** The name survives only as an unrelated `def rd_row(nm: String, +t: T.Tensor)` in `mixin/rand.bend:865`; the dispatch is nowhere. |
| `def g_kernel() -> List<&2, String>` | the def (was `:1878` at the parent) | **DIED.** `git grep 'def g_kernel' HEAD -- '*.bend'` = 0; the `.agents/slop` harnesses use `NN()/bs()/body()`. |

**Nothing replaced either.** The expected ROWS survive as DATA — `gates/cstyle-live.rows` (228
lines; `double` names only the `tmap` type maps and one `hipocml` preamble, and **0 of the 42 `rd`
rows**, so the seven-dtype claim holds) and `oracles/cstyle-*.rows` — but the driver that printed
them is gone. `render_dtype` (the callee) survives at `cstyle.bend:773`.

**The landing (4 edits, one per cite — delete the claim, record the reason in place):**

| file | before | after |
|---|---|---|
| `checks/e2e.py:55` | cites `renderer/cstyle.bend:2984-3015` | names `rd_row`, records `e51904b04` DELETED it (1061 lines) and the rows survive as data |
| `checks/e2e.sh:228` | same | same |
| `checks/run-f64.sh:411` | `as g_kernel() at cstyle.bend:1879 is one` | `as g_kernel() in cstyle.bend was one before e51904b04 deleted it` |
| `checks/run-port-mm.sh:29` | `exactly as g_kernel() at cstyle.bend:1879 is one` | `cstyle.bend's own g_kernel() fixture was DELETED by e51904b04` |

Re-resolved after: all four `cstyle.bend` cite strings are gone from `checks/`; the population fell
36 → 31. `py_compile` on `e2e.py`, `zsh -n` on all three scripts — clean.

**A RESET, RECORDED.** A `jj` worktree operation at 00:37:03 discarded the first application of all
five edits (uncommitted worktree changes, exactly the hazard the brief names). They were RE-APPLIED
and re-verified; the four edits are `grep`-present in `checks/` and the dead cite strings are absent.
**LANDS HERE ARE UNCOMMITTED AND A `jj` CHECKOUT CAN TAKE THEM AGAIN.**

## 3. The live targets — REPORTED, not edited (name + SHOULD-BE)

At `7c07d570` (`.agents/slop/cites2/resolved-post.tsv`). Every number here MOVES in the same commit
that moves it, so these belong to the live owners (`ops.bend`/`render.bend`, and `differ.py`).

| citing file:line | cite | SHOULD BE | file the target belongs to |
|---|---|---|---|
| `checks/differ.py:149` | `ops.bend:1066` | `ops.bend:1208` (`ATuple{ys: List<&2, U32>}`) | **`differ.py` is NOT mine** |
| `checks/differ.py:177` | `ops.bend:4560` | `ops.bend:4586` (`def UOp.mselect`; ABlob note `4575-4584`) | **`differ.py` is NOT mine** |
| `checks/differ.py:177` | `ops.bend:4554` | `ops.bend:4582` (the `WALL(p3)` close) | **`differ.py` is NOT mine** |
| `checks/disagree-gate.py:103` | `ops.bend:1057` | `ops.bend:1060` (`#   dtype: DType = dtypes.void`) | `checks/` (mine) |
| `checks/rn-gate.py:10,26,98,171,250` | `render.bend:2148` | `render.bend:2020` (`def py_row`) | `render.bend` (other unit) |
| `checks/rn-gate.py:51,172` | `render.bend:2693` | `render.bend:2558` (`def rnd_row`; range now `2558-2568`) | `render.bend` |
| `checks/rn-gate.py:164` | `render.bend:2763` | `render.bend:2752` (`def pu_line`) | `render.bend` |
| `checks/rn-gate.py:40,133,251,399` | `render.bend:2809-2819` | `render.bend:3014-3023` (the five wraps `AKern`…`AParam3`) | `render.bend` |

**Owned but live, reported not edited:** `gates/ops-core-gate.py:12` cites `ops.bend:5044-5045` for
"the five CONST-identity claims whose CPython answers are MEASURED in the port's own notes". `5044`
is the `vmin`/`vmax` three-valued `Bnd` wall. The CONST-identity cluster's note block is
**`ops.bend:5425-5437`** (its `t_hashcons`/zeros/nan tests at `:5440-5475`). SHOULD BE
`ops.bend:5425-5437`.

**NARRATIVES on a live target, do NOT renumber** — `checks/nl-gate.py:39,40,477`. The sentence
records what two CONSECUTIVE failures NAMED (`vd_text` at 7837, then `vd_dbg.of` at 7874) to prove
"the file moved between the failures". Re-pointing 7837 to today's `def vd_text` (`ops.bend:8416`)
would ERASE the evidence the sentence exists to carry. `vd_dbg` is absent tree-wide at HEAD (`git
grep` = 0 outside the prose that quotes it); the number is a historical datum, not an anchor.

## 4. The one non-live cite — LANDED

`checks/run-port-mm.sh:87` cited `helpers.bend:2551` for a PAST concurrent edit. A narrative has no
current anchor to re-resolve, so the number was marked historical so no scanner or reader treats it
as a live pointer: **`` edit to `helpers.bend` (line 2551 then; the file has moved since) ``**. The
claim (a concurrent edit to `helpers.bend` broke the substrate) is unchanged; only the rotting
number is demoted. `zsh -n` clean.

## 5. The instrument: is a bare `.bend:<N>` right? MEASURED NO for 22 of 31

`checks/disagree-gate.py`'s `CITES = (path, line, must_contain, why)` is strict: `lane_citations`
reads the line and `cited()` requires the needle AND no identifier char after it, so a MOVED line
FAILS LOUDLY instead of pointing at the wrong thing. Measured at `7c07d570`, how many of the 31
surviving cites are IMMUNE under that shape (the anchor is UNIQUE in its file, so the number is
redundant) versus how many GENUINELY need a number:

| verdict | count | what it means |
|---|---|---|
| **IMMUNE** | **22** | the tight anchor appears on exactly ONE line — drop the number entirely |
| **NEEDS-NUMBER** | **5** | the anchor repeats, so a number (or a longer anchor) stays |
| DEAD | 0 (was 4) | the four `cstyle` subjects — landed in §2; a needle-instrument catches these as `gone` |
| HAND | **4** | the `nl-gate` narratives — a `(path, needle)` instrument is WRONG here |

**The 22 IMMUNE collapse to 16 distinct anchors** (e.g. `def py_row` is one anchor behind five
cites). **The 5 NEEDS-NUMBER cite locations are 2 logical pins:** `WALL(p3)` in `ops.bend` (18 hits) and
the five hand-written wraps in `render.bend` (`arg_repr A(Kern|Progr|Param)` = 5 hits; the range
`2809-2819` cannot be a single `(path,line)` anyway, so it expands to five anchors — six rows in the
table below, shared by the four `rn-gate.py:40,133,251,399` cites).

**Why the count was wrong twice, in one line each:** a `+7` guess was applied to a `+575` drift
(`awmma`); `rows.pick3` moved 1485→1490→1556→1563→1564 in one session (`adevfix`/`names-deadlane`
reconciled it by hand). A bare number is a MEASUREMENT with no rule, so it cannot fail — it can only
be stale. The `(path, must_contain)` shape is a RULE, and it fails on the move.

**Paste-ready conversion (do NOT mass-convert — `differ.py` is another unit's, `ops.bend`/`render.bend`
are live). This is the measured mapping; three rows need a longer anchor or a line because they
repeat:**

```python
# cites2 conversion, MEASURED 2026-10-07 at HEAD 7c07d570.
# `lane_citations` must accept a 3-tuple for IMMUNE rows (no line) -- the anchor IS the pin.
CITES = (
  # ---- IMMUNE: unique anchor, NO line. (label arg = why) ----
  ("tinybendygrad/dtype.bend",              "def Dt.i64_trunc",           "the port's i64 trunc"),
  ("tinybendygrad/uop/ops.bend",            "ATuple{ys: List<&2, U32>}",  "PERMUTE/FLIP's one arg type"),
  ("tinybendygrad/uop/ops.bend",            "def UOp.mselect",            "mselect's AInt arm"),
  ("tinybendygrad/uop/ops.bend",            "#   dtype: DType = dtypes.void", "CallInfo's dtype field"),
  ("tinybendygrad/helpers.bend",            'getenv_int("DEBUG", 0)',     "the DEBUG reader (code, not the comment)"),
  ("tinybendygrad/base.bend",               "0x7FC00000",                 "the JS NaN collapse"),
  ("tinybendygrad/renderer/nir_llvmir.bend",'String.concat([nm, " = ["]', "the nl row shape"),
  ("tinybendygrad/runtime/support/nv/ip.bend", "import Base",             "package-relative import (the nv twin)"),
  ("tinybendygrad/LAWS/spec.bend",          "import Base",                "package-relative import"),
  ("tinybendygrad/runtime/support/nv/nvdev.bend", "def emit(xs: List<&2, String>)", "the nv emit"),
  ("tinybendygrad/uop/render.bend",         "def py_row(",                "the row shape"),
  ("tinybendygrad/uop/render.bend",         "def rnd_row(",               "the rnd rows"),
  ("tinybendygrad/uop/render.bend",         "def pu_line(",               "the pu line"),
  ("tinybendygrad/renderer/cstyle.bend",    "Ops.SHRINK.*HAS NO DTYPE",   "the SHRINK wall"),
  ("tinybendygrad/mixin/elementwise.bend",  "def ew_add",                 "the ew dispatch"),
  (".agents/slop/ag-emit.bend",             "bend2-constraints.md",       "the quoted path"),
  # ---- NEEDS-NUMBER: anchor repeats; a longer anchor or the line stays ----
  ("tinybendygrad/uop/ops.bend",    4582, "WALL(p3)",           "the mselect wall note (18 in file)"),
  ("tinybendygrad/uop/render.bend", 3014, "arg_repr AKern",     "wrap 1 of 5"),
  ("tinybendygrad/uop/render.bend", 3016, "arg_repr AProgr",    "wrap 2 of 5"),
  ("tinybendygrad/uop/render.bend", 3019, "arg_repr AParam1",   "wrap 3 of 5"),
  ("tinybendygrad/uop/render.bend", 3021, "arg_repr AParam2",   "wrap 4 of 5"),
  ("tinybendygrad/uop/render.bend", 3023, "arg_repr AParam3",   "wrap 5 of 5"),
)
# NOT IN CITES: checks/nl-gate.py:39,40,477 -- historical failure positions, stay prose.
```

## 6. Artifacts (all under `.agents/slop/cites2/`)

* `scan.py`/`raw.tsv`/`counts.err` — the discovery walk and the 36-cite reading at `aa457fd251c2`.
* `raw-post.tsv`/`counts-post.err` — the 31-cite reading at `7c07d57026fe`.
* `resolve.py`/`resolved.tsv`/`resolved-post.tsv` — needle resolution before/after.
* `instrument.py`/`instrument-post.tsv` — the IMMUNE/NEEDS-NUMBER/DEAD/HAND measurement.
