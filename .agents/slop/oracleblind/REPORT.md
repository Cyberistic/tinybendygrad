# INPUT SENSITIVITY ACROSS THE WHOLE ORACLE POPULATION — 98 oracles, four perturbation classes

**Deliverable**: `gates/oracleblind-census.py` (the instrument) and `gates/oracleblind.rows` (the
98-row table). Both new. Nothing else in the tree was edited, and **no oracle was repaired** — see
item 8.

```
.venv/bin/python gates/oracleblind-census.py            # the census (writes gates/oracleblind.rows)
.venv/bin/python gates/oracleblind-census.py --plant    # 6 self-test directions, synthetic oracles
.venv/bin/python gates/oracleblind-census.py --report   # census only, rc never charged
.venv/bin/python gates/oracleblind-census.py --only X   # one oracle; prints, NEVER writes the table
```

---

## 1. THE DENOMINATOR: 98, discovered by a walk

**Two reads, kept apart, both counted.** Neither is a hand list.

1. **`GATE-DECLARED` (83).** `gates/gates-pop.py` is imported **BY PATH** (`_homes`, `_buckets`) —
   the derivation the tree already owns, per `gates/gate-surface.py:76` ("the population is not a
   second list, it is `gates/gates-pop.py:discover()`, loaded by path"). Homes derived:
   **`('checks', 'gates')`**. **255 `.py` readers parsed, 0 unreadable, 23 non-`.py` readers NOT
   parsed by this instrument** (counted, not silently dropped). Each gate's `Gate(oracle=...)`
   argument is its OWN declaration of the CPython side; `_resolve_gate_oracle` follows literals,
   module-level names, `str(X)` and the `HERE / "x.py"` BinOp. **0 unresolved declarations.**
2. **`WALK-ONLY` (15).** Every `.py` under a home whose stem carries `oracle`, which no gate names.
   A shape, so a separate class, not merged in. **`gates/oracleblind-census.py` is in its own
   population** (its stem carries `oracle`) and is reported `CANNOT BE PERTURBED — SELF`, because
   running a perturbed copy of a census is unbounded recursion.

**87 of the 98 exist on disk. 11 do not** — names in code with nothing behind them
(`.wgsl-mut-oracle.py`, `graphcmp-oracle.py`, `viz_oracle.py`, `oracle_planted.py`, …), each
reported `CANNOT BE PERTURBED — the declared path does not exist`. `_locate` resolves with
`gatekit.Gate._resolve`'s own two-base rule; the base that matched is printed per row
(`[beside-the-gate]` / `[repo-root]`).

**Nine oracles a gate names live under `.agents/slop/`** — a swept tree (`beautiful-mnist-gate.py`,
`bitcastrow/bc-oracle.py`, `graphcmp-oracle.py`, `graphcmp-dbg-oracle.py`, `i64shl/shl-oracle.py`,
`ishr/shr-oracle.py`, `mixin-op-gate.py`, `nl/nl-oracle.py`, and the absent `xd1/render-gate-oracle.py`).

**TWO are byte-identical twins** of a `gates/` file, by sha256:
`gates/beautiful-mnist-oracle.py` ≡ `.agents/slop/beautiful-mnist-gate.py` (`3ed7851f84da0f04`) and
`gates/mixin-op-oracle.py` ≡ `.agents/slop/mixin-op-gate.py` (`7b98e6fd06f059f4`).
**Two more are the SAME SIZE and are NOT identical** — `i64-shl` (9 820 B vs 9 257 B: different
sizes) and `i64-shr` (16 339 B both sides, `8e3146b3de4d6ca2` vs `57cb1d30d5c88dfa`). **I predicted
three twins from a byte-size comparison and the sha said two**, which is the cheapest possible
reminder that a size is not a hash.

---

## 2. THE TABLE — `gates/oracleblind.rows`, 98 rows + header, **sha256 `614ea700469eeea9`, 35 858 B, byte-identical at `PYTHONHASHSEED` default and 3 (separate processes)**

Columns: `oracle · class · verdict · floor_of_rows · rows · base_sha · sites · unreachable ·
deterministic · rc · EMPTY · VALID-DIFFERENT · BOUNDARY · ENV · ARGV · crashed_by · seed_stable ·
comparisons · dead_labels · surface_owner · why · declared_by · argv · env`

Each perturbation cell reads `<rows_moved>@<output_sha12>` plus `C` (row count changed), `M`
(multiset of `name=value` tokens changed), `o` (ORDER ONLY — a rotation manufactures this by
construction, so it is never counted toward a floor), `SEED-UNSTABLE` (the sha does not reproduce
across two seeds, so it is not printed as a number that looks reproducible and is not), or
`CRASH rc=N`.

| verdict | n | of which GATE-DECLARED |
|---|---|---|
| `SENSITIVE` (with floor) | **39** | 32 |
| `ALL VALID INPUTS AGREE` | **28** | 25 |
| `CANNOT BE PERTURBED` | **26** | 23 |
| `IGNORES ITS INPUT` | **5** | 3 |

**Floors, `SENSITIVE`, the low and high ends** (rows that move, of rows held):

```
 1/5  tn_dunder_neg   1/8 tn_neg        2/15 tn_nodes       2/38 mo_graph_census   2/4  rd_graph
 2/8  replace         3/3 ew-explog     3/8 render_val_s     6/117 autogen          6/6  qcom_cache
 7/7  wk-cd          8/8 render_val_s  12/12 graphcmp-dbg   13/22 wk-eval          18/18 wk-f32
19/54 rw-gate        21/21 ew-consts   22/28 fold_graph    25/25 oracle-txt-census 32/32 ops-core
39/39 bc-u32         44/48 regalloc    53/151 i64-shl       60/60 tc_ptx_types     68/102 render-gate
84/301 i64-shr      103/108 qcom_stage3 205/205 nl        227/227 wgsl_render    438/588 qcom
594/620 tc_ptx_render 726/726 rng_graph 1164/1178 amd_dsl
```

**0 of 98 oracles are nondeterministic**, and **`seed_stable = ALL` on every row** — every applied
perturbation's output reproduces across two hash seeds.

---

## 3. EVERY ORACLE THAT IGNORES ITS INPUT — with the line

`IGNORES ITS INPUT` is a **reference count**, not a diff: the label is bound at module level and has
**zero `ast.Name(Load)` occurrences in the file**. **Five**, with the line:

| oracle | rows | sites | the line |
|---|---|---|---|
| `gates/crp_graph_census-oracle.py` | 287 | 69 | `gates/crp_graph_census-oracle.py:81  PRI_OFF is bound and never loaded` |
| `gates/ops_python_census-oracle.py` | 85 | 217 | `gates/ops_python_census-oracle.py:190  CTOR_PARAMS is bound and never loaded` |
| `gates/realize_graph_census-oracle.py` | 1004 | 271 | `gates/realize_graph_census-oracle.py:167  l2` · `:199  l4` — bound, never loaded |
| `checks/rw-gate-oracle.py` | 54 | 59 | `checks/rw-gate-oracle.py:30  FLAT is bound and never loaded` |
| `gates/oracle-census-gate.py` | 0 | 602 | `:132 LIVE_HOMES` · `:403 VERDICTS` · `:404 PLANTS` — all bound, never loaded |

**Four of these are LIVE FINDINGS about live gates**, not artifacts: `crp`'s `PRI_OFF`,
`ops_python`'s `CTOR_PARAMS`, `realize`'s `l2`/`l4` and `rw-gate`'s `FLAT` are fixtures written into
an oracle and never read, over **287 / 85 / 1004 / 54 rows**. The fifth (`oracle-census-gate.py`) is
admitted by the **filename shape** — it is a gate, not an oracle — and its three dead tables are real
but incidental.

**NOT REPAIRED.** Repairing any of these means deciding what they were meant to catch, which is the
`gates/autogen-oracle.py` reason: *inventing what it should catch*. `l2`/`l4`, `CTOR_PARAMS`, `PRI_OFF`
and `FLAT` may each be a pin a census deliberately stopped reading; **nothing in the tree says which**,
and I am not going to guess. This is the decision the brief told me not to make, and I did not make it.

---

## 4. EVERY ORACLE WHERE TWO VALID INPUTS AGREE — the class garbage cannot reveal

**28 `ALL VALID INPUTS AGREE`.** Every one has **≥1 completed comparison** and **every site loaded**.
The two agreeing inputs are named in the table by their output sha: **two classes produced output
whose sha256 prefix is the base's**, and that equality *is* the agreement — checkable, not asserted.

**Hand-verified end to end, `gates/tn_sqrt-oracle.py`, outside the instrument.** The fixture is
`UOp(Ops.CONST, src=(), arg=4)`. Four inputs, four runs:

```
arg=4  ->  b375c95ddfa3e914        arg=5  ->  b375c95ddfa3e914
arg=0  ->  b375c95ddfa3e914        arg=-4 ->  b375c95ddfa3e914
```

`.sqrt()` sets `op is SQRT`, `srcs == (self,)`, `arg is None`, does not mutate its input, and is
reachable — **all five properties are input-independent**, so the oracle reads its input and the
property is constant. That is `ALL VALID INPUTS AGREE` and **not** blindness.

**The 28, with the classes that completed** (`cmp` = completed comparisons of 3):

- **cmp=3, all three classes byte-identical (19):** `tn_add_sub` · `tn_and_or_xor` · `tn_binop2_cmp`
  · `tn_bitwise_not` · `tn_ceil_floor` · `tn_contiguous_backward` · `tn_detach` · `tn_fdiv_mod` ·
  `tn_isfinite` · `tn_isnan` · `tn_logical_not` · `tn_lshift_rshift` · `tn_maximum` · `tn_mul` ·
  `tn_relu` · `tn_relu6` · `tn_sin_log2_exp2_rsqrt` · `tn_sqrt` · `tn_trunc_reciprocal_threefry` ·
  `tn_where` · `uop_cast`. **This whole family asks STRUCTURAL questions** — *which op*, *which srcs*,
  *is arg ANone*, *did it mutate* — and no operand value changes an answer to any of them.
- **cmp=2 (1):** `mo_graph_census` — `EMPTY` and `BOUNDARY` agree; `VALID-DIFFERENT` crashes.
- **cmp=1 (8):** `cr_graph_census` · `ew_graph_census` · `md_graph_census` · `mx_graph_census` ·
  `tn_graph_census` (all: only `VALID-DIFFERENT` completes) · `mo_graph_census` · `graphcmp-oracle` ·
  `oracle-census-gate`. **Each says so in its `why`**, e.g.
  `… 0 of 51 rows moved over 1 completed comparison(s); 2 class(es) CRASHED and were excluded`.

**THE FINDING THAT MATTERS MOST: the `tn_*` family — 22 of 28 — is blind to VALUES, not to
STRUCTURE.** Its rows would not notice if an operand were wrong. `gates/tn_mul-oracle.py`'s
`VALID-DIFFERENT` (`arg=3 → 4`, `arg=5 → 6`) and `BOUNDARY` (`3 → −3`, `5 → −5`) were run **by hand**:
byte-identical output both times. Whether that is a defect is the port's question, not mine — but it
is now a **number** (`0 of 13 rows`) instead of an impression.

---

**26.** Four causes, each with its own decider:

**(a) 11 -- the declared path does not exist.** `.agents/slop/xd1/render-gate-oracle.py`,
`.wgsl-mut-oracle.py`, `amd-mut-oracle.py`, `crp-mut-oracle.py`, `cstyle-mut-oracle.py`,
`graphcmp-dbg-oracle.py`, `graphcmp-oracle.py`, `oracle.py`, `oracle_planted.py`,
`realize-mut-oracle.py`, `viz_oracle.py`. **Decider:** the mutation harnesses that name them
(`gates/wgsl_render_census-mutate.py` etc.) either write the mutant or drop the name. **Not
perturbed because there is nothing to perturb.**

**(b) 1 -- refuses without arguments.** `checks/oracle_f64.py`, `rc=3`:
`== REFUSED, NOT A VERDICT: needs <workdir> <mm-rows>; got 0 argument(s). Without them there is no
denominator to publish.` **`checks/oracle_f64.py:305` already records that `gates/gate-surface.py`
runs it with no arguments and calls that the exact wrong thing.** **Decider:** a real `<workdir>`
holding a real `mm-rows` file -- a recorded f64 run -- passed as `argv[1:2]`.

**(c) 2 -- no fixture of its own; the input is `tinygrad`'s own code.** `gates/tn_minimum-oracle.py`
(its input IS `tinygrad.uop.ops.Ops`) and `gates/tn_binop_sweep-oracle.py`. **0 reachable literal
sites and 0 bound-but-unloaded labels.** Perturbing it means editing `tinygrad/`, which this unit was
told is read-only. **Decider: an import shim that patches `tinygrad.uop.ops` (resp.
`tinygrad.tensor`) before the oracle runs** -- a `sitecustomize`-style wrapper, not a tree edit.
(`gates/tn_nary_arena-oracle.py` moved here too: its only fixture is `arg=True`, a **bool keyword
argument**, which the census refuses to perturb -- see the cost note in section 10.)

**(d) 11 -- every applicable perturbation class CRASHED, so 0 comparisons completed.**
`beautiful-mnist-gate.py` . `gates/beautiful-mnist-oracle.py` . `cstyle_render_census` . `datasets`
. `linearizer_census` . `md_graph_census` . `mx_graph_census` . `onnx_census` . `op_graph_census`
. `ptx_render_census` . `rand_census` . `state_census`.

**These are the honest answer to "what would decide it": a perturbation THE FIXTURE SURVIVES.** The
classes empty, rotate and sign-flip; these oracles survive none of them. **Decider for each: the
crash's first traceback line**, which names the site the fixture cannot lose.
`gates/state_census-oracle.py` is the worked example: `WLS = ("torch","collections","numpy","_codecs")`
empties to `()`, and `inspect.getsource` on nothing raises.

**(e) 1 -- SELF.** `gates/oracleblind-census.py`. **Decider: nothing; it is the instrument.**

*`checks/render-gate-oracle.py`, `cr_graph_census`, `decomp_graph_census`, `ew_graph_census`,
`gr_graph_census`, `graphcmp-oracle` and `tn_nodes` sat in this bucket until the
heterogeneous-container guard (item 21) landed; refusing to rotate a binding tuple gave three of
them a usable class back. **The guard's cost is real and is listed in section 10.***

## 6. THE PLANT — proof the census goes red on an oracle made insensitive

`--plant` builds **seven synthetic oracles** (and one direct rule assertion) and runs the whole
machinery on each. **7/7 green.** Each exists because of a measured failure of this file:

| plant | asserts | the failure it exists for |
|---|---|---|
| `plant-good` | `SENSITIVE`, 3 comparisons | the positive direction must be reachable |
| `plant-constant` | `IGNORES ITS INPUT` | **`VALUES = [1,2,4,8]` + `print("answer=42")` — a fixture written and never read.** The `gates/autogen-oracle.py` shape |
| `plant-nofix` | `CANNOT BE PERTURBED` | an oracle whose input is `tinygrad`'s code must NOT read as `IGNORES ITS INPUT` — the two are opposites |
| `plant-crash` | `ALL VALID INPUTS AGREE`, **2 completed comparisons, `crashed=['EMPTY']** | a crash must not steal the other classes' completed comparisons |
| `plant-allcrash` | `CANNOT BE PERTURBED`, **comparisons=0** | **0 completed comparisons is DEAD, not agreement. This was wrong on 19 of 98 oracles before the guard existed** |
| `plant-boolkw` | asserts the **SURFACE**: `bool sites=0`, `unreachable_has_flag=True`, `other_sites=2` | a bool keyword argument is a FLAG — flipping `reverse=True` changes *which method is under test* |
| `plant-mixed` | asserts the **RULE**: heterogeneous container refused rotation AND truncation, homogeneous still rotates | **the seed-instability in item 21** — rotating `("cast", g_cast)` is not a different input, it is a re-binding |

Two plants assert the **surface or the rule** rather than a verdict, **on purpose**: a verdict could
be red for a reason unrelated to the property, which is the `.agents/TODO.md` trap (*a fixture
retyped by hand agrees with the instrument by construction*) pointed at the plant. `plant-mixed`
went through **three** spellings before it could reach its own subject.

---

## 7. COST

- **wall 200.3 s** for all 98 (≈5 runs each; ~660 subprocesses).
- **peak child RSS 736 MiB** (`resource.getrusage(RUSAGE_CHILDREN).ru_maxrss`; **bytes on macOS,
  KiB on Linux** — the first version divided by 1024 unconditionally and printed `71872 MiB` for a
  70 MiB figure).
- Scratch lives in `gates/artifacts/sensitiv/` (`.gitignore`d) and is **unlinked per run**: the
  directory is **empty** after a full census. `__file__` is **textually substituted** for the
  original's absolute path in every copy, so the 7 oracles carrying a `__file__` derivation resolve
  identically; the substitution count is per-row. The tree is otherwise untouched: of **663** dirty
  paths in `git status`, **2 are mine**.
- **Byte-reproducible across seeds, in SEPARATE PROCESSES, twice over:**
  1. **the table**: `gates/oracleblind.rows` reads **sha256 `614ea700469eeea9`** at
     `PYTHONHASHSEED` default and at `PYTHONHASHSEED=3`, two whole runs of all 98.
  2. **the population derivation**: `homes=('checks','gates') n=98 absent=11 unresolved=0
     order_sha=b13824c3f1830575` at seeds **1, 2 and 7**.
  No in-process two-build comparison — that is theatre, and `gates/oracle-census-gate.py`'s
  seed-independence plant says why. **This one was NOT stable on the first attempt**: it failed at
  seed 3 on **1 row of 98** and the cause is item 21.

---

## 8. THE BRIEF'S `autogen-oracle.py` CLAIM, RE-MEASURED — half right, and the wrong half is load-bearing

The brief states: *"`gates/autogen-oracle.py` IS NOT INPUT-SENSITIVE: ALL 51 ROWS ARE BYTE-IDENTICAL
FOR THE REAL HEADER AND FOR `GARBAGE NOT C AT ALL`, AND 43 OF 51 NEVER TOUCH IT."*

**Measured, by hand, outside the instrument:**

```
$ .venv/bin/python gates/autogen-oracle.py gates/ag-fixture.h        | wc -l   -> 117
$ .venv/bin/python gates/autogen-oracle.py <'GARBAGE NOT C AT ALL'>  | wc -l   ->  53
```

**117 rows for the real header, 53 for garbage — and 56 of the 106 distinct row names MOVE.** The
census's own ARGV arm, run correctly, answers **EMPTY=54 · GARBAGE=56 · VALID-DIFFERENT=6**, floor
**6 of 117**, verdict **`SENSITIVE`**.

So:

- **TRUE, and slightly stronger than stated:** the header-insensitive set is **50 row names**, not 43
  of 51. They are exactly the module's own tables — 6 `###` section headers, 13 `ag.tmap`, 4
  `ag.uints/ints/fps/specs`, `ag.arc_families`, 13 `ag.base_rules`, `cxkind_count`, and the 8
  `gen|` preamble lines (`import ctypes`, `dll`, `from typing import Literal, TypeAlias`, …).
  **Not one of them mentions a symbol from the header.**
- **FALSE as a verdict on the file:** the other **64 physical rows** — the whole `### GEN output`
  block — are driven entirely by the header and vanish under garbage.

**The number that matters and the brief does not carry is `VALID-DIFFERENT = 6`.** Given a
*different but still valid* C header (`gates/ag-fixture.h` plus one extra
`typedef struct { unsigned long long c_lo, c_hi; } sensitiv_other_shape_t;`), `autogen-oracle.py`
moves **6 of 117 rows**. **Garbage moves 56; a valid header moves 6.** That is the floor the brief
asked for and the number nobody had.

**THE INSTRUMENTION CAVEAT, STATED BECAUSE IT IS A WEAKNESS:** no gate declares
`gates/autogen-oracle.py`'s `argv`. Its CONTROL baseline is **CHOSEN, not discovered** —
`gates/ag-fixture.h`, sha256 `baf29edd9523` — and the row prints `argv: CHOSEN:` so a reader cannot
miss it. **A different declared baseline would move the floor.**

---

## 9. THINGS I FOUND AND DID NOT DO

1. **No oracle was repaired.** Not one. The grant allowed it where the fix is mechanical and the
   intended behaviour is written down; for these four the intended behaviour is *absent*, and
   `gates/autogen-oracle.py`'s "repairing it would mean inventing what it should catch" is the
   class's definition. **The four dead fixtures in item 3 are the clearest candidates and I left all
   four alone deliberately.**
2. **Two byte-identical oracle twins** across `gates/` and `.agents/slop/` (`beautiful-mnist`,
   `mixin-op`, shas above). Dead weight: the `gates/` copies are `WALK-ONLY` — no gate names them —
   and the gate diffs against the `.agents/slop/` one, which lives in a tree `AGENTS.md` records as
   sweepable. **`gates/i64-shl-oracle.py` and `gates/i64-shr-oracle.py` are near-duplicates that are
   NOT identical** (same size, different sha on `i64-shr`), so they cannot be collapsed by content
   and I did not touch them. **Not deleted** — deletion is not mine to make, and a gate naming one of
   the two would break.
3. **11 oracles survive no perturbation at all** (item 5d). The instrument reports the crash but not
   the site, because the class that would name it is the class that crashed. **The decider is named
   per row; I did not build it.**
4. **`gates/oracle-census-gate.py` emits 0 rows on stdout** — its census goes to stderr and the
   table needs `--table`. It is admitted to this population by **filename shape** and is an
   instrument, not an oracle. A shape-based admission admitting an instrument is the filename-class
   defect in miniature; it is reported, not silently dropped.
5. **23 non-`.py` gate readers are not parsed** by this instrument (`.sh` entry points, which
   `gates_pop._buckets` finds by shebang). A shell gate that names an oracle would be invisible
   here. **Counted in the summary**, not hidden.
6. **The heterogeneous-container guard has a cost and I did not hide it.**
   `gates/tn_nary_arena-oracle.py`'s entire fixture is `UOp(Ops.CONST, src=(), arg=True)` — a
   **bool keyword argument**, which the census refuses to perturb because flipping a bool keyword
   changed *which method was under test* for `gates/tn_mul-oracle.py`. That file therefore reports
   **0 usable classes** and `CANNOT BE PERTURBED`. **The same is true of any container holding a
   label beside a callable** — a rotation would re-bind it. **`gates/render_val_s-oracle.py`,
   `gates/mo_graph_census-oracle.py`, `md_graph_census` and `mx_graph_census` each lost their
   VALID-DIFFERENT class to this guard** and would be measured properly only by a fixture-level
   substitution rather than a source-level one.

---

## 10. EVERY WRONG REJECTION AND BLIND SPOT IN THE EXTRACTOR, WITH ITS CAUSE

The brief: *your extractor will be wrong in places — report every one with its cause.* Each of these
was **found by a measurement or by the plant**, not by inspection, and each is recorded in the
instrument's own header at the line that carries it.

| # | what it got wrong | cause | found by |
|---|---|---|---|
| 1 | AST-parsed 8 `checks/*.sh` as Python and reported 8 `SyntaxError`s | this file reporting its own blindness as the tree's unreadable gates; `gates_pop` classifies shell by shebang | first run |
| 2 | admitted 3 phantom oracles `unused.py` | `gates/gatekit.py`'s `device_plant`/`output_plant` build `Gate(oracle="unused.py")`; a plant is not a declaration | first run |
| 3 | admitted 55 non-oracle `.py` collaborators as "absent" | the literal rule admitted every tracked `.py` a gate names — `gatekit.py`, `coindep.py`. The name must carry `oracle` | first run |
| 4 | reported 54 of 67 gate-declared oracles absent | resolved bare names against the repo root only; `gatekit._resolve` tries `HERE` then `ROOT` | first run |
| 5 | `str(ORACLE)` unresolved in 2 gates | `ORACLE = HERE / "x.py"` is a BinOp no `literal_eval` folds | first run |
| 6 | returned a `Constant` **node** where a string was wanted | `consts` maps string → node; one `.value` missing | first run |
| 7 | found **zero** `os.environ[K] = v` assignments | `os.environ[K] = v` puts the Subscript in `targets`, not `value` — **the wrong side of an assignment** | debugging `I64SHL_SEED` |
| 8 | reported 7 `*_graph_census-oracle.py` as `IGNORES ITS INPUT / 0 sites` | the whole fixture is inside `print(f"…")`; f-strings were excluded wholesale | run |
| 9 | then blind to `(1,2,8,16)` inside `f"…{sig(base().reshape(1,2,8,16))}"` | excluding a `JoinedStr` protects the format TEXT and blinds the interpolated EXPRESSION | run |
| 10 | `tn_nary_arena` 0 sites | `arg=True` — a `bool` excluded as a "flag" | run |
| 11 | `cr_graph_census` **CRASHED** counts as `SENSITIVE floor=7364 of 0 rows` | flipping `capture_output=True` broke the oracle's **own plumbing**; 7364 git paths on stdout | run |
| 12 | **19 of 98** oracles `ALL VALID INPUTS AGREE` on **0 completed comparisons** | every class crashed; `0 disagreements over 0 comparisons is not agreement` | run |
| 13 | `autogen` `CANNOT BE PERTURBED` while its ARGV arm had measured 103 moved rows | the comparison count covered only the LITERAL classes | run |
| 14 | `autogen` ARGV `EMPTY=103 GARBAGE=103 VALID-DIFFERENT=103` | **`invoke(probe, argv=[probe])` ran `python <a C header>`.** Three identical numbers, one failure | hand-check vs. direct run |
| 15 | `VALUES = [7,7]` perturbed to `[8,8]` / `[0,0]` / `[-7,-7]` | `scan` seeded from `iter_child_nodes(node)` and never tested `node` — **a container class applied to a container's elements is arithmetic on the fixture, not the class** | `plant-crash` |
| 16 | `tn_mul` `SENSITIVE floor=1 of 13` | flipping `reverse=True` changed **which method was under test**, not the fixture; hand-checked: `arg 3→4`, `5→6`, `3→−3` all byte-identical | hand-check |
| 17 | `--only wk-` **overwrote the 99-row table with 4 rows** | `--only` shared the write path; a filter that narrows the answer and overwrites it cannot be noticed | seed check |
| 18 | `ru_maxrss / 1024` on macOS printed `71872 MiB` for 70 MiB | `ru_maxrss` is KiB on Linux, **bytes** on macOS | first run |
| 19 | `plant-boolkw` passed for the wrong reason | the bool default was excluded by *skipping `FunctionDef`*, so the documented keyword rule was not the operative one — **a guard that is not the operative one is a comment** | plant |
| 20 | `plant-mixed` was unreachable through `surface()` | `surface` stops at the OUTERMOST literal, so the inner `("a", <lambda>)` is never a site; the plant asserted on the outer list, which rotates harmlessly | plant |
| 21 | **the table was NOT byte-reproducible across seeds** — 1 row of 98, `checks/render-gate-oracle.py`, VALID-DIFFERENT sha `262ee6b14086` at seed 1 and `d35e814c92b8` at seed 3 | VALID-DIFFERENT **rotated a heterogeneous container**, `("cast", g_cast)` → `(g_cast, "cast")`, which re-bound `for nm, f in …` and drove the oracle into an error path that prints `repr(<function>)` — **which embeds a heap address**. A rotation is a different INPUT only when the container's elements are interchangeable | second seed |
| 22 | 35 of 98 marked `SEED-UNSTABLE`, including `tn_sqrt` whose output I had verified at three seeds BY HAND | the seed re-run executed **after** `finally: sp.unlink()`, so `invoke` found no file and compared the sha of an empty string. **A stability check run against a deleted subject manufactures an instability** | seed check |
| 23 | `seed_stable` reported `True` for the row that had just been unstable | the per-class value was OVERWRITTEN on each loop iteration; it belongs in `kinds[kind]` and the row aggregates it | re-inspection |

**The net effect of 19–23 on the reported numbers: `SENSITIVE` fell 62 → 39 and
`CANNOT BE PERTURBED` rose, because 23 rows had been moved by perturbations that changed the
oracle's PLUMBING or its BINDINGS rather than its data.**

**THE RESIDUAL BLIND SPOTS, with their sizes, all printed per row:**

- **`unreachable` column** — literals the exclusion rules removed. `bool` keyword/default flags are
  counted here with the reason (`gates/tn_nary_arena-oracle.py`'s `arg=True` is the live instance:
  **it IS the value under test, and it is excluded**).
- **`strings_untouched` per class** — a string's "other valid value" is not knowable mechanically
  and inventing one is forbidden, so string literals are only emptied.
- **`0 of 3 classes completed`** on 13 oracles — reported as `CANNOT BE PERTURBED`, never as
  agreement.
- **`surface_owner`** — when a fixture lives in a sibling module (`gates/bc-u32-oracle.py`'s `ROWS`
  is in `bc_u32_table.py`), the row names that module, so a reader never attributes its rows to the
  wrong file.

**NOT AN EXTRACTION ERROR, AND WORTH NAMING: the 22 `tn_*` oracles that agree on every input.** That
is a property of what they ask — *which op*, *which srcs*, *is arg ANone* — and no operand value
changes an answer to any of it. **A gate built only from those rows cannot see a wrong operand.** I
measured it; I am not calling it a defect, because whether the operand values belong in those rows is
a question about the port's design and the brief told me not to invent the answer.

## 11. THE ONE-PARAGRAPH SUMMARY

**39 of 98 oracles are input-sensitive, with floors from 1/5 to 1164/1178. 28 answer identically
for every input the census could build, and 22 of those are the `tn_*` family, which asks only
structural questions — so the honest headline is not "39 oracles are fine" but "39 are demonstrably
fine and 28 are demonstrably BLIND TO VALUES, which is a different and weaker claim than blind to
garbage". 5 hold a fixture they never read, at named lines. 26 cannot be perturbed, and for 11 of
those the reason is that the perturbation kills them. The brief's named instance,
`gates/autogen-oracle.py`, is SENSITIVE with floor 6 of 117 — and the number it lacked is that a
*valid but different* header moves 6 rows while garbage moves 56.**