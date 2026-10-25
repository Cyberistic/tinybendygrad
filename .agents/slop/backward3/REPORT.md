# backward3 — RESTORE THE CPYTHON SIDE OF THE BACKWARD WALK'S `walk_*` ROWS

**Started** `date -u` = **Sun Oct 25 15:20:36 UTC 2026**.
**HEAD at start**: `git rev-parse HEAD` = **`59c0140ee86124c2fe6318369cc5bb9104424667`**.
**HEAD at the last measurement**: **`9a8b172918c5994a259ba4e635883513b7da1d8e`** (2026-10-25T15:44Z —
every arm of §4 re-run at that HEAD).
**⇒ THE TREE MOVED UNDER THIS UNIT** (two different HEADs, named above). Every measurement
below names the command that produced it, and the ones that depend on the tree's state
carry the HEAD they were taken at.

**Owns**: `tinybendygrad/mixin/gradient.bend` (its fixture), `.agents/slop/backward/oracle-cg.py`
(the stale oracle), `.agents/slop/backward3/`.
**Did NOT touch**: any other `.bend` file, `checks/`, `gates/`, `references/`, `AGENTS.md`,
`.agents/TODO.md`, `.agents/TOOLS.md`, `.agents/slop/backward2/`.
**NOTHING COMMITTED. NO MUTATING GIT COMMAND.** The only git reads were
`git rev-parse HEAD` and `git show HEAD:tinybendygrad/mixin/gradient.bend`, both with
`env -u GIT_INDEX_FILE`.

---

## 0. THE CAUSE, IN ONE PARAGRAPH

**The oracle died because upstream's `_shape` for a BUFFER reads `self.src[0].as_shape`**
(`tinygrad/uop/ops.py:359`, inside `case Ops.BUFFER | Ops.ALLOC | Ops.PARAM:`), **and the
oracle's leaves were SRC-LESS**: `.agents/slop/backward/oracle-cg.py:36-38` built
`UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float32))` with no `src`, so the first
`k._shape` that `compute_gradient` reads (`tinygrad/mixin/gradient.py:130`) raised
`IndexError: tuple index out of range` — MEASURED, the traceback is in
`transcript-oracle.out`'s sibling, and the run died at `oracle-cg.py:83` **after printing
five rows**. **The port's fixture has the SAME shape for the same reason**:
`tinybendygrad/mixin/gradient.bend:1521` was
`gnew(ar, O.OpsBUFFER{}, Nil{}, O.AParam{fx_pa(slot)})` — a `BUFFER` with `Nil{}` srcs —
and it built EVERY leaf in the file (`fx_buf` is the only leaf builder, and `dag()` and
`fix()` both go through it). **⇒ AND THE FIX MUST CHANGE THE EXPECTATIONS, because giving
a leaf a src CHANGES THE GRAPH**: an empty STACK is a node, so the leaf's node set grows
by one, the toposort grows from 6 to 7, the `in_target_path` flags grow from six to seven,
the `BUFFER` tokens change from `BUFFER/0` to `BUFFER/1`, and the two gradient node counts
grow (`5`→`6` and `4`→`5`) because a gradient's operands ARE the leaves. **⇒ So the fix is
two-sided: give BOTH sides' leaves the empty-STACK src, AND re-transcribe the expectations
BY SCRIPT** — the expectations are CPython's bytes, never typed.

---

## 1. THE CAUSE, MEASURED

```
$ env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward/oracle-cg.py
oracle_dag_n_toposort=6
oracle_dag_walk=MUL/2 ADD/2 ADD/2
oracle_dag_walk_n=3
oracle_dag_inpath=0 0 1 0 1 1
oracle_dag_n_inpath=3
Traceback (most recent call last):
  File ".../tinygrad/mixin/gradient.py", line 130, in compute_gradient
    if k._shape is not None and v._shape is not None and k._shape != v._shape:
  File ".../tinygrad/uop/ops.py", line 359, in _shape
    assert len(self.src[0].as_shape) <= 1
IndexError: tuple index out of range
rc=1
```

**⇒ FIVE ROWS EMITTED, THEN DEATH.** The 15 `walk_*` rows' CPython side was a RECORD
(`BACKWARD-WALK.md`'s table, and the port's own rows) and not a measurement.

**THE FIXTURE'S LEAVES, ON BOTH SIDES, BEFORE AND AFTER:**

| side | before | after |
|---|---|---|
| oracle | `oracle-cg.py:36-38` `UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float32))` — no `src` | `oracle-cg.py` `leaf(slot)` = `UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=()),), arg=ParamArg(slot, dtypes.float32))` |
| port | `gradient.bend:1521` `gnew(ar, O.OpsBUFFER{}, Nil{}, O.AParam{fx_pa(slot)})` — `Nil{}` srcs | `gnew(O.Found.ar(sh), O.OpsBUFFER{}, [O.Found.i(sh)], O.AParam{fx_pa(slot)})` with `sh` an EMPTY `STACK` |

**WHY THE EMPTY STACK**: `as_shape` of an empty STACK is `()` (`ops.py:789`), so
`BUFFER(STACK())`'s `_shape` is `()` — SCALAR — and the shaped-edge reduce at
`gradient.py:131` never fires. **`build1` AND `build2` BOTH USE `leaf()`**, so no two
leaves can disagree about their shape: a fixture that is half-changed is a fixture that
compares two different graphs.

---

## 2. WHAT I EXTENDED, AND WHY

**`.agents/slop/backward2/` — the previous unit's harness — IS WHAT I EXTENDED, AND I DID
NOT EDIT IT.** It has the three things this task needs and that the older
`.agents/slop/backward/` does not: a gate that compares the port against an expectation
FILE (`gate.py`), a control harness that perturbs each expectation (`ctl-rows.py`), and a
`run.sh` whose `apply` asserts every edit by RE-READING the file (`checks/walk-mutate.sh`
once shipped a vacuous plant, and the assertion is what caught it). **I copied its
DISCIPLINE into `.agents/slop/backward3/run.sh` rather than its files**, because I am not
the owner of `backward2/` and because the walk rows need a gate that `backward2/` does not
have.

**THE PRIOR ART'S HARNESS IS STILL THE PRIOR ART'S HARNESS, AND I RAN IT VERBATIM**:
`sh checks/walk-mutate.sh <arm>` — it is the walk rows' own plant/disarm harness
(`plant_reverse`, `plant_noguard`, `disarm_comment`, `disarm_name`) and it is NOT in the
forbidden list. **AND THE PREVIOUS UNIT'S HARNESS TOO**:
`sh .agents/slop/backward2/run.sh <arm>` for the `gs_*`/`bw_*` rows' gate and its eight
plants. **Both are delegated to verbatim from `backward3/run.sh`**, so the plants are the
SAME CODE, not a re-typed copy that could silently drift.

**THE OLDER `.agents/slop/backward/` TOOLING**: `oracle-cg.py` (FIXED, and it is the
oracle the 15 rows came from), `REPORT.md` (the prior art's plant/disarm transcript — read,
not edited), `run-oracle.sh` (now a 7-line stub that only resolves `.venv`'s `tinygrad`;
the brief's "the transcript/rows the prior art owns under `.agents/slop/backward/`" — the
prior art's `oracle-cg.txt` is **GONE**: the no-`.txt` sweep took it, and `BACKWARD-WALK.md`
still cites it at line 10. **So the prior art's recorded output could not be re-read; it had
to be RE-MEASURED, which is the whole point of this unit.**).

---

## 3. THE FILES

| file | what |
|---|---|
| `tinybendygrad/mixin/gradient.bend` | **THE ONLY `.bend` FILE TOUCHED.** `fx_buf` gains the empty-STACK src (+3 lines) and **six comment blocks** were corrected (§8). |
| `.agents/slop/backward/oracle-cg.py` | **THE ORACLE, FIXED.** `leaf()`; `build1`/`build2` both use it; `main()` reordered so the first fixture's rows are emitted before the second fixture's; the second fixture is GUARDED and its raise is printed AS A ROW. |
| `.agents/slop/backward3/mkrows.py` | **THE TRANSCRIPTION.** The oracle's rows → the expectations. A rule plus ONE named exception; the `srcs=` cut; the composed row. |
| `.agents/slop/backward3/mkrows.sh` | runs the oracle and `mkrows.py`. |
| `.agents/slop/backward3/walk.rows` | **THE EXPECTATIONS — 16 rows, CPython's own bytes.** |
| `.agents/slop/backward3/oracle-cg.rows` | the oracle's output (30 rows). |
| `.agents/slop/backward3/gate.py` | **THE GATE, WITH FOUR VERDICTS**: `PASS` / `MISMATCH` / `UNCHECKABLE` / `MISSING`. |
| `.agents/slop/backward3/ctl-rows.py` | **THE CONTROLS** — two classes per row, plus the control on the control. |
| `.agents/slop/backward3/run.sh` | the harness: `base`, `check`, `head`, `ctl`, `oracleplant`, `walkplants`, `prev`. |
| `.agents/slop/backward3/transcript-*.out` | the transcripts of §4–§6. |

---

## 4. THE MEASUREMENTS

### 4.1 THE ORACLE RUNS AGAIN — and it runs FURTHER than it ever has

```
$ sh .agents/slop/backward3/mkrows.sh
transcribed 15 oracle rows -> 16 port rows in .agents/slop/backward3/walk.rows
```

**`oracle-cg.py` now exits 0** and emits **30 rows**: the **15** `oracle_dag_*` rows of the
first fixture, **7 rows that were previously UNREACHABLE** (`oracle_pmul`, `oracle_pmul0`,
`oracle_pmul1`, `oracle_seed`, `oracle_fwdwalk_n`, `oracle_fwdwalk_skipped`,
`oracle_fwdwalk_a` — the prior art's `REPORT.md` names them as "never emitted" because
`main()` died in the first fixture), **5 `oracle_hole_*` rows** (the second fixture's WALK
is computable even though its GRADIENTS are not), and **2 diagnostic rows**
(`oracle_hole_error=...`, `oracle_hole_computed=no`).

**⇒ THE SECOND FIXTURE NO LONGER DIES SILENTLY.** It still cannot be computed — the
shaped-edge reduce at `gradient.py:131` raises `RuntimeError: cannot broadcast ... into ()`,
because its EXPAND's shape src is an ADD whose `as_shape` is a ONE-tuple (`ops.py:788`)
while a leaf's is `()` — **but the instrument now says so in a ROW instead of dying**, which
is this tree's doctrine 2 (`DEAD` is the one nobody writes down).

### 4.2 THE GATE — the 16 `walk_*` ROWS AGREE AGAINST CPYTHON AGAIN

```
$ sh .agents/slop/backward3/run.sh check
=== check-only: ALL PROOFS CHECK  run rc=0  rows=102
=== THE GATE (a): the port's walk rows against walk.rows -- CPython's own bytes
    rows expected: 16   PASS: 16   MISMATCH: 0   UNCHECKABLE: 0   MISSING: 0
    VERDICT: PASS
=== THE GATE (b): the previous unit's gs_*/bw_* rows against backward2/rows.rows
    rows expected: 14   PASS: 14   MISMATCH: 0   UNCHECKABLE: 0   MISSING: 0
    VERDICT: PASS
=== VERDICT: walk-rows rc=0   gs/bw-rows rc=0
```

**⇒ 16 of 16 `walk_*` rows PASS against CPython's own bytes, and the previous unit's 14
`gs_*`/`bw_*` rows are still PASS.**

**THE EXPECTATIONS, AND WHERE EACH BYTE CAME FROM** (`.agents/slop/backward3/walk.rows`):

```
walk_row=MUL/2 ADD/2 ADD/2 | grads_n=6        <- COMPOSED from walk_sig + walk_grads_n
walk_n_toposort=7                              <- oracle_dag_n_toposort
walk_sig=MUL/2 ADD/2 ADD/2                     <- oracle_dag_walk
walk_walk_n=3                                  <- oracle_dag_walk_n
walk_inpath=0 0 0 1 0 1 1                      <- oracle_dag_inpath
walk_n_inpath=3                                <- oracle_dag_n_inpath
walk_grads_n=6                                 <- oracle_dag_grads_n
walk_grad_a=6 root=ADD/2                       <- oracle_dag_grad_a, ` srcs=` cut
walk_grad_b=5 root=MUL/2                       <- oracle_dag_grad_b, ` srcs=` cut
walk_grad_c=2 root=CAST/1                      <- oracle_dag_grad_c, ` srcs=` cut
walk_grad_p=2 root=CAST/1                      <- oracle_dag_grad_p, ` srcs=` cut
walk_grad_q=2 root=CAST/1                      <- oracle_dag_grad_q, ` srcs=` cut
walk_grad_r=2 root=CAST/1                      <- oracle_dag_grad_r, ` srcs=` cut
walk_keys=ADD/2 MUL/2 ADD/2 BUFFER/1 BUFFER/1 BUFFER/1   <- oracle_dag_keys
walk_skip_n=0                                  <- oracle_dag_skip_n
walk_hole_n=0                                  <- oracle_dag_hole_n
```

**THE NAME MAP IS A RULE AND ONE NAMED EXCEPTION** (`mkrows.py`): `oracle_dag_<x>` →
`walk_<x>`, **except** `oracle_dag_walk` → `walk_sig` (the port's row is named after what
it IS). **A FIFTEEN-ENTRY HAND LIST WOULD BE A SECOND COPY OF THE CORRESPONDENCE**, and a
second copy rots without anyone noticing.

**THE COMPOSED ROW**: the oracle prints `oracle_dag_walk` and `oracle_dag_grads_n` as TWO
rows and never prints `walk_row`; the script composes it from the two.

### 4.3 THE 88 PRE-EXISTING ROWS — 83 BYTE-IDENTICAL, 5 CHANGED, 14 ADDED

```
$ sh .agents/slop/backward3/run.sh head
    HEAD's gradient.bend installed: 1a1d034d3c5561ea0566181e88823b1b76ff95bed9d11cfa8f07460d13d22b0b
=== check-only: ALL PROOFS CHECK  run rc=0  rows=88
=== check-only: ALL PROOFS CHECK  run rc=0  rows=102
=== HEAD vs LIVE: rows head=88 live=102
--- rows LIVE has that HEAD does NOT (must be EXACTLY the previous unit's 14):
    bw_distinct=11
    bw_nodes=11
    bw_sig=...
    gs_grads_n=6
    gs_hole_n=1
    gs_inpath=0 0 0 1 1 1 1
    gs_keys=ADD/2 MUL/2 ADD/2 BUFFER/1 EXPAND/2 BUFFER/1
    gs_n_inpath=4
    gs_set_n=3
    gs_set_sig=...
    gs_skip_n=0
    gs_walk_n=4
    gs_walk=MUL/2 EXPAND/2 ADD/2 ADD/2
    gs_zero_n=1
--- rows whose VALUE changed (must be EXACTLY the five the leaf fix moved):
    walk_inpath:      head: 0 0 1 0 1 1        live: 0 0 0 1 0 1 1
    walk_keys:        head: ... BUFFER/0 ...   live: ... BUFFER/1 ...
    walk_grad_a:      head: 5 root=ADD/2       live: 6 root=ADD/2
    walk_grad_b:      head: 4 root=MUL/2       live: 5 root=MUL/2
    walk_n_toposort:  head: 6                 live: 7
    rows whose VALUE changed: 5
    rows byte-identical: 83 of 88
```

**⇒ OF HEAD's 88 ROWS: 83 ARE BYTE-IDENTICAL AND 5 CHANGED — AND THE 5 ARE EXACTLY THE
ROWS THE LEAF FIX WAS SUPPOSED TO MOVE**, and their new values are CPython's (§4.2).
**⇒ NOTHING IS MISSING** (the "rows HEAD has that LIVE does NOT" list is exactly those
five, because a changed VALUE is a changed LINE; the value diff above is the precise one).
**⇒ LIVE's 14 ADDITIONS ARE EXACTLY THE PREVIOUS UNIT'S `gs_*`/`bw_*` ROWS.**

**⇒ AND THE 72 ROWS THAT ARE NEITHER `walk_*` NOR `gs_*` NOR `bw_*` (the `fix` fixture's
rule-table rows — `claims=32`, `keep_pair=12`, `rej_gate=11`, …) ARE ALL BYTE-IDENTICAL.**
**MEASURED, NOT ASSUMED**: `fx_buf` is shared by `fix()` and `dag()`, so the leaf change
touched BOTH fixtures, and the diff above shows that not one of `fix`'s 72 rows moved.

### 4.4 THE PLANTS STILL MOVE — BOTH HARNESSES, VERBATIM

**THE PRIOR ART'S HARNESS** (`sh checks/walk-mutate.sh <arm>`, run by
`backward3/run.sh walkplants`; the base is re-persisted AFTER the leaf fix, or every row
would move):

| arm | rows moved | the rows |
|---|---|---|
| `plant_reverse` (`reversed(walk)` → `walk`, `gradient.py:119`) | **16** | `walk_row`, `walk_keys`, `walk_grad_a/_b/_c`, `walk_grads_n`, `walk_skip_n` (7 — the prior art measured 7) **plus the 9 `gs_*`/`bw_*` rows the previous unit's fixture now contributes** |
| `plant_noguard` (the `in_target_path` guard dropped, `gradient.py:114`) | **7** | `walk_row`, `walk_sig`, `walk_walk_n`, `walk_skip_n` + `gs_walk`, `gs_walk_n`, `gs_skip_n` |
| `disarm_comment` (a comment's text) | **0** | — |
| `disarm_name` (a local parameter name, signature + body) | **0** | — |

**THE DISARMS ARE NOT VACUOUS**: the harness prints the working copy's sha256 and the
output's sha256 separately, and in both disarms the FILE's sha256 changed while the
OUTPUT's did not (`5028744e…` both times). **⇒ "Nothing moved" and "nothing moved because
nothing was done" are different, and the sha256s are what says which.**

**THE PREVIOUS UNIT'S HARNESS** (`sh .agents/slop/backward2/run.sh <arm>`, run by
`backward3/run.sh prev`):

| arm | rows moved | arm | rows moved |
|---|---|---|---|
| `check` | **14 of 14 compared, 0 mismatched, VERDICT: PASS** | `plant_droptarget` | **6** |
| `plant_gswap` | **3** | `plant_flags` | **9** |
| `plant_nozero` | **4** | `disarm_comment` | **0** |
| `plant_setorder` | **1** | `disarm_name` | **0** |
| `plant_nohole` | **3** | `plant_noguard` | **7** |
| `plant_skipseed` | **19** | | |

**⇒ EVERY ONE OF THE PREVIOUS UNIT'S EIGHT PLANTS STILL MOVES, AND BOTH DISARMS STILL
MOVE NOTHING.**

**⇒ TWO COUNTS MOVED, AND BOTH FOR A STRUCTURAL REASON, NOT A NEW BUG:**
`plant_flags` moved **9** rows (the previous unit measured 4) and `plant_noguard` moved
**7** (measured 6). **THE REASON IS THE STACK**: `plant_flags` makes the `in_target_path`
FLAG always true, and `dw_any.go` over an EMPTY src list is `False` — so before the fix a
leaf (which had NO srcs) kept its flag `False` and the walk was unchanged; after the fix a
leaf's only src is the STACK, the flag becomes `True`, and the walk grows to six nodes
(`BUFFER/1 BUFFER/1 MUL/2 BUFFER/1 ADD/2 ADD/2`). **⇒ THE FIX MADE THE WALK ROWS MORE
SENSITIVE, which is what a fix should do, and the transcript names every row that moved.**

### 4.5 THE DEPENDENTS STILL COMPILE

```
$ ./bin/bend tinybendygrad/mixin/op.bend --check-only
ALL PROOFS CHECK
$ ./bin/bend tinybendygrad/tensor.bend --check-only
ALL PROOFS CHECK
```

(`tinybendygrad/mixin/op.bend` and `tinybendygrad/tensor.bend` are the two files that
import `mixin/gradient.bend`; `schedule/indexing.bend` and the two `examples/` files also
import it and were NOT re-checked — **NAMED GAP**.)

---

## 5. THE CONTROLS — TWO CLASSES, NOT ONE

```
$ sh .agents/slop/backward3/run.sh ctl
=== THE CONTROLS
(0) the UNPERTURBED expectations
    PASS  OK  (16 rows)
    (a) walk_grad_a      wrong-but-non-empty -> MISMATCH     OK
    (b) walk_grad_a      empty              -> UNCHECKABLE  OK
    ... (every row, both perturbations) ...
    (a) walk_walk_n      wrong-but-non-empty -> MISMATCH     OK
    (b) walk_walk_n      empty              -> UNCHECKABLE  OK
CONTROLS: 16 rows x 2 perturbations + the clean run = 33 checks, failures: 0
```

**⇒ 33 CHECKS, 0 FAILURES.** For EVERY one of the 16 rows:

* **(a) a WRONG BUT NON-EMPTY expectation → `MISMATCH`, and EXACTLY THAT ROW is named**
  (every other row stays `PASS`), and
* **(b) an EMPTY expectation → `UNCHECKABLE`, and EXACTLY THAT ROW is named**.

**⇒ TWO CLASSES, AND THE ASSERTION IS ON THE CLASS, NOT MERELY ON "NOT PASS"**: a gate
that only caught emptiness would be catching **vacuity** and not **wrongness**, and the
wrong-but-non-empty case is the one that proves it. The gate reports `PASS` / `MISMATCH` /
`UNCHECKABLE` / `MISSING` separately, and **an `UNCHECKABLE` row is a RED verdict** — an
expectation with no value is a MISSING expectation, and the tree's doctrine 2 says
`SKIP` is not `PASS` and `DEAD` is not a zero.

---

## 6. THE CONTROL ON THE CONTROL — THE TRANSCRIPTION IS A WITNESS, NOT A TRANSCRIPT

**THE QUESTION**: a gate whose expectations were copied from the port's own output is a
tautology. **THE ANSWER IS MEASURED IN TWO DIRECTIONS.**

### 6.1 THE ORACLE MOVES THE EXPECTATIONS AND THE PORT DOES NOT

```
$ sh .agents/slop/backward3/run.sh oracleplant
    oracleplant: the DAG's second ADD became a MUL: applied and VERIFIED
transcribed 15 oracle rows -> 16 port rows in .../walk-planted.rows
=== the EXPECTATIONS moved (the oracle moved, the port did NOT):
    < walk_row=MUL/2 ADD/2 ADD/2 | grads_n=6
    > walk_row=MUL/2 MUL/2 ADD/2 | grads_n=6
    < walk_sig=MUL/2 ADD/2 ADD/2
    > walk_sig=MUL/2 MUL/2 ADD/2
    < walk_grad_a=6 root=ADD/2
    > walk_grad_a=8 root=ADD/2
    < walk_grad_c=2 root=CAST/1
    > walk_grad_c=5 root=MUL/2
    < walk_keys=ADD/2 MUL/2 ADD/2 BUFFER/1 BUFFER/1 BUFFER/1
    > walk_keys=ADD/2 MUL/2 MUL/2 BUFFER/1 BUFFER/1 BUFFER/1
=== the PORT's rows did NOT move (this arm never touched it):
=== check-only: ALL PROOFS CHECK  run rc=0  rows=102
    the port's output is byte-identical to the base -- NOTHING MOVED
```

**⇒ FIVE EXPECTATION ROWS MOVED WHILE THE PORT'S OUTPUT IS BYTE-IDENTICAL.** A file that
were a transcript of the port's output could not move when only the oracle moved. **⇒ THE
DIRECTION OF THE DEPENDENCE IS ORACLE → FILE, AND THE PORT IS NOT IN IT.**

### 6.2 THE PORT MOVES AND THE EXPECTATIONS DO NOT

**The converse is the plant arm, and it is §4.4's table**: `plant_reverse` moves 16 of the
port's rows and `walk.rows` does not change by one byte. **⇒ THE EXPECTATIONS ARE A
FUNCTION OF THE ORACLE IN BOTH DIRECTIONS OF PERTURBATION.**

### 6.3 AND THE EXPECTATIONS ARE NOT WHAT THE PORT PRINTED

**`walk.rows` disagrees with HEAD's port output on FIVE of the sixteen rows** (§4.3) — the
expectations carry values the port did **not** print before the leaf fix. **⇒ THE
EXPECTATION FILE IS NOT A TRANSCRIPT OF THE PORT'S OUTPUT, AT HEAD OR NOW.**

### 6.4 AND THE TRANSCRIPTION'S BYTES ARE THE ORACLE'S BYTES

`mkrows.py` opens **exactly one path** — the oracle's output file — and applies a name
rule, one named exception, one documented cut (` srcs=`, the prior art's NAMED LOSS of
`osig`'s third field) and one composition. **No value in `walk.rows` was typed by a
human**, and the file cannot be produced from the port's output at all: the port prints
**102** rows and this file has **16**, under **different names** (`walk_*` vs
`oracle_dag_*`), and one of the 16 (`walk_row`) is a row **the oracle never prints**.

---

## 7. WHAT WAS *NOT* CLOSED

### 7.1 THE `bw` GRAPH'S ABSENCE FROM THE CORPUS'S POPULATION — **NOT CLOSED**, AND THE BLOCKERS ARE NAMED

**THE BRIEF'S NAMED NEXT STEP IS `gr_21` (PERMUTE)**, at
`tinybendygrad/mixin/gradient.bend:675`, which is `GSkip{}` today, with the file's own
comment saying "the whole rule is: read the ATuple, argsort it, build the PERMUTE", and
with `O.ATuple{ys: List<&2, U32>}` (`ops.bend:1237`) and `H.argsort_u32`
(`helpers.bend:602`) already present.

**⇒ I DID NOT LAND `gr_21`, AND HERE IS WHY, MEASURED.**

**(1) THE FILE'S OWN COMMENT DESCRIBES HALF THE RULE.** upstream's rule is
`tinygrad/mixin/gradient.py:88`:
`(UPat(Ops.PERMUTE, name="ret"), lambda ctx, ret: (ctx.permute(argsort(ret.marg)),))` —
and `UOp.permute` is **`tinygrad/mixin/movement.py:228`**, which is NOT a raw `_mop`:

```python
order_arg = tuple(self._resolve_dim(x) for x in argfix(order, *args))   # reads self.ndim
if sorted(order_arg) != list(range(self.ndim)):
  raise RuntimeError(f"order is not a valid permutation, getting {order_arg}")
return self._mop(Ops.PERMUTE, arg=order_arg) if order_arg != tuple(range(self.ndim)) else self
```

**⇒ THE RULE ALSO READS `ctx.ndim` (= `len(ctx.shape)`, `movement.py:36`), RAISES TWICE,
AND RETURNS `ctx` ITSELF FOR THE IDENTITY.** The comment describes the `_mop` half.

**(2) MEASURED, ON THIS TREE'S OWN `tinygrad/`** (`env -u PYTHONPATH LC_ALL=C DEV=NULL
.venv/bin/python -`):

| ctx | `marg` | upstream's answer |
|---|---|---|
| `UOp.const(1.0, f32)` (ndim 0) | `()` | **`ctx` ITSELF** — no new node |
| `UOp.const(1.0, f32)` (ndim 0) | `(0,)` | **`RuntimeError: order is not a valid permutation, getting (0,)`** |
| `UOp.const(1.0, f32)` (ndim 0) | `(1, 0)` | **`IndexError: dim=1 out of range [-1, 0]`** |
| `RESHAPE(BUFFER(6), STACK(2,3))` (ndim 2) | `(1, 0)` | **`PERMUTE(RESHAPE(...), arg=(1,0))`** — 11 nodes |
| `RESHAPE(BUFFER(6), STACK(2,3))` (ndim 2) | `(0, 1)` | **`ctx` ITSELF** — the identity |

**(3) ⇒ EVERY FIXTURE IN `gradient.bend` IS SCALAR** (all `_shape` are `()`, §4.2's
`walk_inpath` and the `CAST/1` roots), **and upstream RAISES on a scalar ctx for every
non-empty `marg`.** **⇒ THERE IS NO CPYTHON ANSWER TO GATE `gr_21` AGAINST ON ANY FIXTURE
IN THIS FILE.** The first non-degenerate answer needs a **SHAPED** fixture, and a shaped
fixture is where this port's walls are: `gr_17`'s own TODO (`gradient.bend:638`) and
`gr_14`'s (`gradient.bend:605`) are both `resolve` on a `Sint` — **`uop/symbolic.py` is
not ported, and Phase P3 owns it** — and the shaped-edge reduce at `gradient.py:131-133`
needs `broadcast_axes` and `sum_acc_dtype`, which are not ported either.

**(4) ⇒ LANDING `gr_21` ALONE WOULD NOT PUT THE `bw` GRAPH IN THE CORPUS'S POPULATION.**
The corpus's `bw` graph is `g_bw()` at `.agents/slop/graphcmp.bend:1471`, 32 nodes, op
census `ALLOC 2 CAST 1 CONST 4 EXPAND 2 GROUP 1 MUL 2 PERMUTE 4 REDUCE 2 RESHAPE 8 STACK 6`
(`.agents/slop/backward-graph/REPORT.md` §1; `graphcmp.py:1493`, `graphcmp.bend:1443`).
**⇒ IT NEEDS ALL THREE MOVEMENT RULES**: `gr_21` (PERMUTE), `gr_17` (RESHAPE, `GSkip{}` at
`gradient.bend:639`) and `gr_14` (REDUCE, `GSkip{}` at `gradient.bend:606`). **⇒ TWO OF THE
THREE ARE HARD WALLS ON `resolve`.**

**(5) ⇒ AND THE CORPUS'S `bw` GRAPH IS A HAND-BUILT FIXTURE, NOT A `compute_gradient`
OUTPUT.** `g_bw()` builds it node for node (`graphcmp.bend:1471-1526`), in both languages.
**⇒ THE PORT'S `bw` GRAPH (what `compute_gradient` builds) AND THE CORPUS'S `bw` GRAPH ARE
DIFFERENT GRAPHS, and putting the port's into the corpus's population needs a NEW corpus
graph — in `.agents/slop/graphcmp.bend`, which is NOT this unit's file.**

**⇒ SO: `gr_21` IS LANDABLE IN PRINCIPLE** (the pieces exist: `O.Arena.arg` reads the
node's arg, `O.ATuple{ys}` carries the margin, `H.argsort_u32` argsorts it, and
`gnew(ar, O.OpsPERMUTE{}, [ctx], O.ATuple{...})` builds the node — `movement.bend:1001`
builds the same node today), **but it would be an UNGATED RULE**: no CPython answer exists
on a scalar fixture, and the shaped fixture that would give one needs the `resolve` wall.
**⇒ A RULE WITH NO GATE IS A CLAIM OF UNKNOWN VALUE, and this file's own `gbool` note says
so. ⇒ I DID NOT LAND IT, AND I DID NOT LAND A HALF OF IT.**

### 7.2 THE 72 `fix` ROWS ARE **NOT** GATED AGAINST CPYTHON

**THEIR ORACLE IS GONE.** `gradient.bend:1720` cites
`.agents/slop/notes/grad_oracle.py` as the source of its numbers (`recip 12 sin 10 log2 8
…`) — **and that file is NOT in the tree** (`ls .agents/slop/notes/` shows
`bend2-constraints.md`, `c2d-refusal-gate.md`, `compare`, `kn-truth.py`,
`sz-odin-precedent.md`, `upstream-bugs.md`). **⇒ THOSE 72 ROWS ARE BYTE-IDENTICAL
CHANGE-DETECTORS, NOT CPYTHON-GATED** — and that is a pre-existing condition, not one this
unit created. **⇒ THE LEAF FIX TOUCHED THE `fix` FIXTURE TOO** (`fx_buf` is shared) **and
MEASURED THAT NOT ONE OF ITS 72 ROWS MOVED** (§4.3) — so the change is invisible to every
row that exists, and it makes the port's `BUFFER` upstream-faithful (upstream's BUFFER
ALWAYS carries a shape src).

### 7.3 THE PRIOR ART'S RECORDED ORACLE OUTPUT IS GONE

`BACKWARD-WALK.md:10` cites `.agents/slop/backward/oracle-cg.{py,txt}`; the `.txt` was
taken by the no-`.txt` sweep. **⇒ THE 15 ROWS' PRIOR VALUES COULD NOT BE RE-READ; THEY HAD
TO BE RE-MEASURED**, and the values this unit re-measured for the eleven rows the leaf
does not touch are the prior art's (`walk_sig=MUL/2 ADD/2 ADD/2`, `walk_walk_n=3`,
`walk_n_inpath=3`, `walk_grads_n=6`, `walk_skip_n=0`, `walk_hole_n=0`,
`walk_grad_c/_p/_q/_r=2 root=CAST/1`) — **so the eleven agree with the RECORD and the five
that moved have no record to agree with.**

### 7.4 THE DEPENDENTS' FULL SET

`mixin/op.bend` and `tensor.bend` were re-checked (§4.5). **`schedule/indexing.bend` and
`examples/test_pkl_imagenet.bend` / `examples/train_resnet.bend` also import
`mixin/gradient.bend` and were NOT re-checked. NAMED GAP.**

### 7.5 NOTHING WAS COMMITTED

`git status --porcelain=v1` shows `M tinybendygrad/mixin/gradient.bend`,
`M .agents/slop/backward/oracle-cg.py` and the untracked `.agents/slop/backward3/`.
**No mutating git command was run**; the only git reads were `git rev-parse HEAD` and
`git show HEAD:tinybendygrad/mixin/gradient.bend`, both with `env -u GIT_INDEX_FILE`.

---

## 8. THE COMMENTS IN `gradient.bend` THAT WERE FALSE, AND NOW ARE NOT

| where (line numbers are the CURRENT file) | what it said | what it says now |
|---|---|---|
| `:1086-1096` | "every node in that fixture is a SCALAR" — true, but it did not say WHY the fixture was scalar at all | says the leaves are `BUFFER(STACK())`, whose `_shape` is `()` (`ops.py:359`, `:789`) |
| `:1521-1533` (`fx_buf`) | no comment at all — the src-less leaf was UNDOCUMENTED | the leaf's `_shape` requirement, `ops.py:359`, the IndexError, and "every leaf in this file is built here" |
| `:2139` | "The committed oracle prints twenty rows for this fixture and then DIES" | the oracle's FIFTEEN rows, the second fixture's raise, and the seven rows that are now reachable |
| `:2187` (`dag()`) | "THE THREE BUFFERS ARE ON DISTINCT SLOTS" | adds that `fx_buf` gives every leaf an empty-STACK src, so the port's graph and CPython's are the same graph |
| `:2268` (`dag_inpath`) | `oracle_dag_inpath=0 0 1 0 1 1`, "`a` and `b` … have no srcs" | `0 0 0 1 0 1 1` over SEVEN nodes, and the STACK's own flag is `0` because it has no srcs |
| `:2304` (`dag_skip_n`/`dag_hole_n`) | "CPython cannot compute it at all" | CPython computes the hole fixture's WALK but not its GRADIENTS |
| `:2328` (`dag_grad_root`) | `grad_a` → `5 root=ADD/2`, `grad_b` → `4 root=MUL/2` | `6` and `5`, plus WHY the counts moved (a leaf's node set grew by the STACK) |
| `:2416` (`gs_leaf`) | "the prior art's oracle NO LONGER RUNS" | it does now, and `fx_buf` gives every leaf the same empty-STACK src |

---

## 9. THE EXACT NEXT STEPS, IN ORDER

1. **THE SHAPED FIXTURE.** Everything else about `gr_21` is ready; what is missing is a
   fixture with a real shape, so that upstream's `permute` does not raise. **That needs
   `uop/symbolic.py`'s `resolve`, `broadcast_axes` and `sum_acc_dtype` — Phase P3.**
2. **`gr_17` (RESHAPE)** — `ctx.reshape(ret.src[0].shape)`: a FOLD read of the shape plus
   `prod` for the `-1` arm. Same wall.
3. **`gr_14` (REDUCE)** — `_rop`'s `resolve(self.shape[x] != 1)` and `_broadcast_to`'s
   `broadcast_axes`. Same wall, and it is the wall that makes upstream itself raise on a
   shaped seed.
4. **A NEW CORPUS GRAPH** for the port's `bw` graph — a hand-built fixture that the port's
   `compute_gradient` reproduces — in `.agents/slop/graphcmp.bend`, which is not this
   unit's file.
5. **RESTORE `.agents/slop/notes/grad_oracle.py`** — it is the CPython oracle for the 72
   `fix` rows and it was pruned. Until it is back, those 72 rows are change-detectors.
6. **THE `srcs=` MULTISET** — `osig`'s third field is still a NAMED LOSS. It needs an
   alphabetical rank for every op (`Ops.value` is DECLARATION order and disagrees with
   the oracle's STRING order).
