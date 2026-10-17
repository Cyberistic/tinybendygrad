# tnvalue: DOES THE *VALUE* OF A `tn_*` ORACLE'S FIXTURE REACH ITS ROWS?

Unit: one session, 2026-10-17. Grant: `gates/tn_*-oracle.py`, `gates/tn_graph_census*`,
`gates/oracleblind*`. **No `.bend` file, no `checks/*`, no `gates/gatekit.py`, no
`gates/*-gate.py`, no `oracles/*`, no `.agents/TODO.md` was touched. `tinygrad/` was read and
never written.** `bend` was **never executed** by this unit, so no `bend` peak RSS is claimed.

## 0. THE STARTING MEASUREMENT, RUN NOT REBUILT

`gates/oracleblind-census.py` was run to completion, in one process, on this tree.

| | |
|---|---|
| exit | **0** |
| wall | **275.0 s** (`/usr/bin/time -l` `275.05 real`) |
| peak child RSS | **726 MiB** (`peak_child_mib()` 726; `/usr/bin/time -l` `761380864 B` = 726.5 MiB — the two agree) |
| verdicts | SENSITIVE **39** · ALL VALID INPUTS AGREE **28** · CANNOT BE PERTURBED **26** · IGNORES ITS INPUT **5** |
| new `sha256` | `0cc47cebe9d96def` vs the committed `614ea700469eeea9` |

**THE SHA MOVED AND NONE OF IT IS MINE.** Exactly **2** of 98 rows changed
`(verdict, rows, base_sha, sites)`, and **0 of the changed rows are `tn_*`**:

* `gates/op_graph_census-oracle.py` `base_sha c79c3c954284 → b6823b002d4d`
* `gates/rand_census-oracle.py` `sites 64 → 62`

`git status` in a disarmed index reports **both as `A` (staged-added)** — another unit's staged,
in-flight work — and `checks/substrate-current.py` appeared beside `checks/substrate-snapshot.py`,
which is why the `declared_by` column of 3 more rows changed text. **The `ALL VALID INPUTS AGREE`
set is byte-identical at 28, and all 23 `tn_*` rows are byte-identical in
`(verdict, rows, base_sha, sites)` across two runs 275 s apart in different processes.**

**CORRECTION TO THE BRIEF: it is 23 `tn_*` of the 28, not 22.** Read from the committed table,
not counted by hand: 28 AGREE − 5 non-`tn_*` (`graphcmp-oracle.py` (slop), `decomp_`,
`ew_graph_`, `gr_graph_`, `uop_cast-`) = **23**. Whichever oracle the prior unit excluded to get
22, `tn_graph_census-oracle.py` is in the census table as AGREE and is counted here.

## 1. WHICH ASKED VALUES ARE DERIVABLE FROM CPYTHON, AND WHICH ARE NOT

**276 rows across the 23 oracles.** Classified by the row's VALUE EXPRESSION, on the AST.

### DERIVABLE — **252 of 276.** The asked quantity is read out of CPython's own graph.

Buckets are by the row's value expression, counted over all 23 (AST walk, MEASURED):

| asked value | n | the derivation, verbatim from the oracles | payload-sensitive? |
|---|---|---|---|
| op identity (`.op is Ops.X`) | 92 | `int(r.uop.op is Ops.<X>)`, and inside every `*_does_not_mutate_input` | no |
| src identity/shape | 55 | `int(r.uop.src == (c_uop, d_uop))`, `int(len(r.uop.src) == 3)`, `int(r.uop.src[0].op is Ops.<X>)` | no |
| graph signature (`tn_graph_census`, all 51 of its rows) | 51 | `sig(r)` = `len(seq(r.uop))`, `r.uop.op.name`, `len(src)`, src op names | **2 rows yes** |
| arg-is-ANone | 43 | `int(r.uop.arg is None)` | no |
| value out of the graph | 5 | `int(r_ceil.uop.src[1].src[1].arg == 1)`, `int(r.src[0] is c)`, … | no |
| derived negative | 5 | `int(... .op is not Ops.NOOP)` | no |
| dtype out of the graph | 1 | `int(c.dtype is dtypes.bool)` | dtype, not payload |

### NOT DERIVABLE — **24 rows, and this is the deliverable**

**24 of 276 (8.7%), in 19 of the 23 oracles, are the literal `int(1)`.** Row names:
`add_sub_is_reachable`, `and_or_xor_is_reachable`, `binop2_cmp_is_reachable`,
`ge_is_reachable`, `ceil_floor_is_reachable`, `contiguous_backward_is_reachable`,
`detach_is_reachable`, `fdiv_mod_is_reachable`, `isfinite_is_reachable`,
`isnan_is_reachable`, `logical_not_is_reachable`, `maximum_is_reachable`,
`mul_is_reachable`, `pow_is_reachable`, `relu_is_reachable`, `relu6_is_reachable`,
`sin_is_reachable`, `log2_is_reachable`, `exp2_is_reachable`, `rsqrt_is_reachable`,
`sqrt_is_reachable`, `trunc_is_reachable`, `threefry_is_reachable`, `where_is_reachable`.

**THEY ARE CONSTANTS ON BOTH SIDES, AND THE COUNTS MATCH 1:1.** For every one of the 19 the
matching `gates/tn_*.bend` carries the same number of bare `True{}` row bodies — 24 py, 24 bend,
19 files each, same set. `gates/tn_sqrt.bend`:

```
def row_sqrt_reachable() -> Bool:
  True{}
```

`gates/gatekit.py:660` compares the lanes **byte for byte**, so two agreeing constants are
indistinguishable from agreement. **This is exactly the defect
`gates/tn_bitwise_not-oracle.py`'s own header names** — *"the two lanes compared `1 == 1` there
and the gate would have stayed green with the port entirely broken"* — and
`gates/tn_bitwise_not.bend` is the only `tn_*.bend` with **no** `True{}`, having been repaired
into `row_signed_xor` on both sides. **THE REPAIR IS A TWO-LANE CHANGE**, so it is out of this
unit's grant by construction, and changing only the oracle converts a dead row into a red gate
rather than into a live one.

## 2. SHOULD THE VALUE AXIS BE ADDED? **NO. MEASUREMENT BELOW.**

**21 of the 23 are ladderable** (they hold a CONST payload literal); `tn_isnan-oracle.py` and
`tn_nary_arena-oracle.py` hold none and are **absent from the ladder by measurement, not by
omission** — 17 rows.

Ladder = the brief's four, `v, v+1, 0, -v`, every rung a valid input of the same shape.
**2 rows of 259 moved.** Both of them:

* **`tn_graph_census`: `tn_relu` and `tn_relu6` — a GENUINE, DERIVABLE VALUE AXIS.**
  `sig()` counts `seq(r.uop)`, deduped by identity. MEASURED at `arg=` 4 / 5 / −4 → **4 nodes**,
  at `arg=` **0** → **3 nodes**. Cause, named and measured: at payload 0, `relu`'s
  `(self > 0).where(self, 0)` (`tinygrad/mixin/elementwise.py:683`, def at `:674`) makes
  `src[1] is src[2]` **True** — `where`'s two `CONST 0` srcs **coalesce to one node**. Not
  folding; coalescing. This is a value CPython derived from its own graph, it is not the argument,
  and it is the only such axis in the population.
* `linearizer_census-oracle.py`: `lin_u17`, `lin_u8` — **outside** the `tn_*` set, not mine.

**THE OTHER 33 MOVED ROWS ARE NOT A VALUE AXIS. THEY ECHO THE PAYLOAD.**
`gates/tn_nodes-oracle.py` prints `n0=Ops.CONST/0 srcs=- arg=f4 dt=weakfloat` and
`n11=Ops.CONST/0 srcs=- arg=i0:4 dt=weakint` — `arg=f4` **is** the payload with a float suffix.
That is the brief's own prohibition, *never print an argument as an expected value*, in the wild.
33 echo rows across `tn_nodes` (2), `linearizer_census` (20), `cstyle_render_census` (6),
`realize_graph_census` (5) — and, after another unit added `cstyle-mut-oracle.py` mid-session,
6 more in that mutant (**39** whole-population). **A movement count cannot tell an echo from an
axis; this file can, and `plant echo` is the direction that proves it.**

**WHY ZERO ROWS MOVE, CITED NOT INFERRED.** `tinygrad/uop/ops.py:627`

```python
def alu(self, op, *src:UOp, **kwargs): return UOp(op, src=(self, *src), **kwargs)
```

`alu` is the one construction path. The op comes from the **method**, the srcs from
**argument order** `(self, *src)`, `arg` is whatever `kwargs` carries (nothing → ANone), and
**`self.arg` is never read**. Measured across the ops: `4*{0,1,2,−1,−2,4}` all emit `MUL`,
`4+{...}` all `ADD`, `4**{0,1,2,3,−1,4}` all `POW`, `4−{0,1,4,8}` all `ADD`. **There is no
folding at construction — folding is a rewrite pass — so `sqrt(CONST{4}).op is SQRT` and
`sqrt(CONST{5}).op is SQRT` are BOTH CORRECT CPython, and the rows SHOULD agree.**

**THE COST OF ADDING IT.** `gates/tn_fdiv_mod-gate.py` declares `ROWS` as a named tuple and pins
both lanes: `pins=[(lane, row) for lane in ("py", "bd") for row in ROWS]`. **A new row needs the
`.bend` lane to emit the same name and the gate's `ROWS` to list it.** Adding a row to the
oracle alone makes `py.rows` long by one against `want = rows` → `DEAD`/`FAIL`. **So the value
axis CANNOT be added within this grant, and should not be: 252 of the 276 rows ask a question
whose answer does not depend on the value, and re-asking them per value would be 252 rows of
change-detector.**

**THE ONE AXIS THAT IS REAL IS THE DTYPE, NOT THE PAYLOAD.** Measured over **37 ops × 4 dtypes**
(`int32/float32/uint8/bool`), normalising a pure re-`CAST` away: **4 of 37 have a dtype-selective
graph** — `neg` (`MUL`→`CMPNE` on bool), `bitwise_not` (`XOR`→`CMPNE` on bool), `fdiv`
(`FLOORDIV`→`WHERE` on float and bool), `mod` (`FLOORMOD`→`ADD` on float and bool). **33 of 37 do
not.** **3 of the 4 are already covered by existing arms in this same family** — `bitwise_not` by
`tn_bitwise_not-oracle.py`'s bool+int arms, `neg` by `tn_neg-oracle.py:42` and
`tn_dunder_neg-oracle.py:40`. **The 4th, `fdiv`/`mod`, is `tn_fdiv_mod`'s int arm, and the gate's
own header names it walled**: *"the float-arm (`cast(default_float).alu(FDIV, b)` path past the
int guard) is walled on the dtype fold."* So the one genuine value axis is already carried by 3
of 4 ops and deliberately out of scope for the fourth.

**SO: THE VALUE AXIS SHOULD NOT BE ADDED, AND `ALL VALID INPUTS AGREE` IS THE RIGHT VERDICT FOR
20 OF THE 21.** `tn_graph_census` is the exception that proves the axis exists, and it proves it
in one oracle.

## 3. ROWS ADDED

**None to any `tn_*` oracle, and the measurement says that is correct** (§2: the gate pins row
*names* in `ROWS` and compares *values* byte for byte, so an oracle-only edit makes a gate red,
and a `.bend`-only edit cannot exist). Rows added to **`gates/tnvalue.rows`**, 31 rows, all of
them measured:

| column | what it can distinguish |
|---|---|
| `ladder` | the FOUR rungs the verdict is a claim about; `ptx.bend`'s alias defect was `V-LADDER-STABLE` over 2 rungs under a name saying 4 |
| `verdict` | `V-LADDER-STABLE` / `V-LADDER-SENSITIVE` — deliberately NOT "V-invariant" (§4) |
| `value_axis_rows` | a moved row that does **not** echo the payload = a real derived axis |
| `echo_rows` | a moved row whose value CONTAINS the rung's text = the forbidden shape, named |
| `constant_rows` | a row whose value expression consults nothing = `DEAD`, `DEAD`-on-one-side vs `DEAD`-on-both |
| `blind_verdict` | the parent census's verdict, read from `gates/oracleblind.rows` |

## 4. MUTATIONS THAT MOVED ZERO ROWS, CAUSE NAMED

**Every rung of every site, in all 26 `V-LADDER-STABLE` oracles.** Cause for all of them, one
cause, cited: `tinygrad/uop/ops.py:627` — `alu` reads the method and the argument order and never
reads `self.arg`, and nothing folds at construction (§2). Named per doctrine: **a dead def in the
fixture is not the cause — the cause is that the ASKED PROPERTY IS CONSTANT OVER THE INPUT
DOMAIN, and that is a correct answer, not a defect.**

Two mutations moved zero rows for a **different** cause, and both are instrument defects this unit
owned and fixed:

* **THE LADDER DEGENERATED ON ZERO.** `v, v+1, 0, -v` at `v=0` is `0, 1, 0, 0` — **two** distinct
  rungs. MEASURED on the population: `gates/cstyle_render_census-oracle.py` and
  `gates/realize_graph_census-oracle.py` each hold a payload site of **0**, so both were carrying
  it. Cause: **a ladder that silently loses rungs** — `ptx.bend`'s alias defect again, the
  instrument reporting a denominator it was not measuring. Fixed: candidates are taken in order
  and the first four distinct values win; `plant ladder-degenerate` pins `ladder(0)` and
  `ladder(-1)`.
* **THIS FILE PERTURBED THE POPULATION IT READS ITS VERDICTS FROM — BY NAMING A THING THAT DOES NOT
  EXIST.** The worst of the four, and **not** found by a mutation. The parent census admits every
  `.py` string constant a reader mentions that carries `oracle`
  (`gates/oracleblind-census.py:276` records the version that "answered **55 absent on disk**").
  My first version spelled a suffix as the literal `"-oracle.py"`, so the parent read a
  **6-character string constant** as a declaration of an oracle and the population went
  **98 → 99** with a new `CANNOT BE PERTURBED` row whose **key is literally `-oracle.py`**,
  `declared_by: gates/tnvalue-census.py:literal [unresolved]`. A second literal,
  `"tn_sqrt-oracle.py"`, reclassified that real file from WALK-ONLY to GATE-DECLARED — *a different
  claim about the same file*. **MEASURED AFTER THE FIX: population 98, `-oracle.py` absent,
  nothing declared by this file, `oracleblind-census` back to WALK-ONLY.** Cause: a `.py` literal
  is a **declaration**, not a path. Fixed with `oracle_path()` / `bend_for()` / `BLIND_STEM`, which
  build every such name from parts, and **`plant no-declaration` now asserts the whole class over
  this file's own AST** — verified live, not vacuous: it finds `['-oracle.py',
  'tn_sqrt-oracle.py']` in a literal-carrying source, `[]` in a prose-only source, correctly
  ignoring `checks/no-txt.py` (no `oracle`), and `[]` in this file. **The prose that explains the
  repair quotes the forbidden literals, and `oracleblind-census.py`'s `_docs()` is what keeps those
  mentions from becoming declarations again.**
* **THE VERDICT NAME OVERCLAIMED, AND MY OWN PLANT REFUTED IT.** The first version said
  `V-INVARIANT`. `plant invariant` asserts a row reading `c.arg == 1` moves when the payload is
  retyped — but the ladder is `4, 5, 0, −4` and **1 is not one of them**, so the row did not move
  and **the instrument was right while the name was a lie.** **A fixed ladder has a detection
  hole, and no care at the call site fills it: the value a row is sensitive to is not knowable
  without reading the row, and reading the row is what forbids printing the argument.** Renamed
  to `V-LADDER-STABLE`, which claims four points and not the integers, with the four declared in
  every row of the table. `plant hole` pins the hole in the direction that would make it visible.

Four own-goal failures, recorded because they are the class this tree produces most of. **All
four were caught by this unit's own plant or by a population count, and none by an oracle.**

* **`constant_rows` first read the printed `=1`** and would have called
  `gates/tn_relu-oracle.py`'s `relu_has_three_srcs=1` dead — that is `len(r.uop.src) == 3`, a real
  query. A census that cannot tell a derived row from a literal is `autogen-oracle` one level
  down. Now an AST test.
* **then it counted `int`'s own `Name` as a query** and reported **0** constant rows on a
  population holding **24**. An instrument that reports zero where the answer is 24 is worse than
  one that reports 24 wrongly. Now: no `Attribute`, no `Subscript`, every `Name` a builtin.

## 5. THE PLANT — 9 of 9, **NO RED IS A TRACEBACK**

`gates/tnvalue-census.py --plant` → **rc=0**, **10 `PASS`**, 0 `FAIL`, 0 tracebacks; every
direction is asserted on an `observed:` line, and **4 of the 10 caught a real defect in this unit's
own work** (`ladder`, `constant` ×2, `echo`'s first spelling, `no-declaration`).

`offsets` · `ladder` · `stable` (a **real** `tinygrad` `sqrt` graph; and in the oracle that also
reads a value, **only the value row** moves, so "this oracle moved" and "THIS ROW moved" are held
apart) · `sensitive` (so the classifier is not a one-sided constant) · `hole` (a row keyed outside
the ladder does **not** move and is still reported stable) · `constant` (`int(1)` is CONSTANT,
`int(len(r.uop.src) == 3)` is DERIVED, both printing 1) · `constant-fires` (fired on the **real**
`gates/tn_sqrt-oracle.py`, not a synthetic) · `echo` · `ladder-degenerate` · `no-declaration`.

**Per the precedent set by `gates/falseclaim-census-gate.py`: this plant has NO direction that is
expected to fail by raising.** All 9 exit 0 with a verdict, and the `echo`/`hole` directions are
the "a raising mutation is counted as a plant failure" trap avoided by construction.

## 6. PEAK RSS AND RUNTIME

| | value | instrument |
|---|---|---|
| `gates/oracleblind-census.py`, 98 oracles × 4 classes | wall **275.0 s**, peak child RSS **726 MiB** (726.5 MiB by `/usr/bin/time -l`), rc **0** | run 2026-10-17, one process |
| `gates/tnvalue-census.py --plant` | 9 subprocesses, well under a second | |
| `gates/tnvalue-census.py`, 32 oracles × 4 rungs | wall **32.7 s**, peak child RSS **70 MiB**, rc **0**, `sha256 8ee867e34d39131e`, 32 rows | 3 runs, 2026-10-17 |
| the dtype sweep, 37 ops × 4 dtypes | 1 CPython process, in-process, no `bend` | |

**THE POPULATION MOVED MID-SESSION AND ONLY THE WHOLE-POPULATION NUMBERS WITH IT.** Run 1 gave
**31** oracles / `sha 3fdde5898450ccee`; run 3 gave **32** / `sha 8ee867e34d39131e`. The new row is
`cstyle-mut-oracle.py`, added by another unit mid-session — it is a mutation-derived oracle and
carries **the same 6 echo rows** as `cstyle_render_census-oracle.py`
(`ri_array_0/1/4`, `ri_swizzle_0/1/4`), which is what a mutant of it should do. Echoes therefore
went 33 → 39. **The `tn_*` subset was invariant across all three runs**: 25 `tn_*` oracles,
23 `V-LADDER-STABLE` + 2 `V-LADDER-SENSITIVE`, 24 CONSTANT rows in 19 of the 23 `AGREE` oracles,
2 rows moved. **So the numbers this report argues from are the `tn_*` ones, and they did not
move; a population-wide digest on this tree is not a stable number and is quoted with its
population, not alone.**

**The `tn_*` census's peak was NOT in the record. It is now, with a timestamp: 70-71 MiB at
2026-10-17, `gates/tnvalue-census.py`, 30.2-32.7 s over three runs.** No `bend` was run by this
unit, so no `bend` peak is claimed. No two `bend` processes were ever concurrent because there
were none; the only concurrent load was the 275 s CPython census against other units' work, at
726 MiB peak.

## 7. FOUND AND NOT DONE

* **The 24 two-lane constant rows are a real defect and are NOT fixable inside this grant.** The
  repair precedent (`a67d8bb79`-shaped, as `tn_bitwise_not` did it) touches the `.bend` lane.
  **Whoever holds `.bend` can repair 24 rows across 19 files by turning each `True{}` into a
  query both lanes can answer** — the shape is already written in `gates/tn_bitwise_not.bend` as
  `row_signed_xor`. Until then `gatekit`'s byte comparison cannot fail on any of them.
* **`tn_fdiv_mod`'s float arm** is the one genuinely dtype-selective graph with no arm
  (`fdiv`, `mod`), and its gate header already names it walled. Not mine: it needs `.bend`.
* **`tn_isnan-oracle.py` and `tn_nary_arena-oracle.py` cannot be laddered at all** — they hold no
  CONST payload literal. They are excluded from `gates/tnvalue.rows` by construction and reported
  here rather than padded into the denominator.
* **`linearizer_census-oracle.py`'s `lin_u17` / `lin_u8`** move without echoing the payload, so
  they may be a second real axis. Outside the `tn_*` grant; not chased.
* **`gates/oracleblind.rows`'s sha is not stable across sessions** because the table records other
  units' concurrent edits (`declared_by`, `sites`, `base_sha`). **A census whose own digest moves
  for reasons outside it should carry the run timestamp in the file**, or a reader cannot tell a
  real movement from a neighbour's commit.
* **`oracleblind.rows`'s `dead_labels` column cannot see a constant row.** It looks for *bound but
  unloaded* names; `print(f"...={int(1)}")` is neither. The `constant_rows` column here is the
  complement, and the two together cover what neither covers alone.