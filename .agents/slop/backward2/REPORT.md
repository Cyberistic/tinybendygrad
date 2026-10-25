# BACKWARD2 — `grad_set` and the `bw` graph

**Started 2026-10-25T14:51Z.** HEAD at start: `8c632e58a00033b8e6336078feb0a7907e47e7a0`.
**HEAD at the last measurement: `652ff34f39bac5f23aa57b4c3c023682ebd3ef98`** (2026-10-25T15:15Z).
**The tree MOVED under this unit** — the HEAD is not the one the unit started on, and
`tinybendygrad/mixin/gradient.bend`'s sha256 at HEAD is the SAME at both readings
(`1a1d034d3c5561ea0566181e88823b1b76ff95bed9d11cfa8f07460d13d22b0b`), so nobody else
touched the file while it ran.

**Owns:** `tinybendygrad/mixin/gradient.bend` (parked), `.agents/slop/backward2/`.
**Last measurement: 2026-10-25T15:17:43Z, HEAD `652ff34f39bac5f23aa57b4c3c023682ebd3ef98`.**
**Did NOT touch:** any other `.bend`, `checks/`, `gates/`, `references/`, `AGENTS.md`,
`.agents/TODO.md`, `.agents/TOOLS.md`. **NOTHING COMMITTED. NO MUTATING GIT COMMAND.**
**NO NEW `.bend` FILE** — the oracle, the harness and the controls are all under
`.agents/slop/backward2/` and are Python and shell.

---

## 0. THE CONTRACT, IN ONE PARAGRAPH

**`grad_set` MUST** take the `CState` that `compute_gradient` produced and the target
list, and answer **one slot per target, IN TARGET ORDER**, where a target that has an
entry in `grads` gets that entry and a target that does **not** gets upstream's
`x.const_like(0)` SUBSTITUTE — a real `CONST(0)` interned into the walk's arena and
cast to **the target's own dtype**, so a float32 target gets `CAST(CONST 0.0)` and a
weakfloat target gets the bare `CONST`. **The `bw` graph MUST** be the backward UOp
graph those slots live in: the union of the node sets of the gradient values, **read
out of the hash-consed arena** (a node IS its own key), described by an **index-free**
signature — one token per node, the token carrying the node's class (`OP/nsrc`), an
**IDENT** that tells two same-class nodes apart (a CONST's f32 bits, a BUFFER's PARAM
slot) and the sorted tokens of its srcs — and the signature is **complete on this
fixture** because every node's token is distinct (`bw_distinct` MEASURES that, it does
not assert it). **The port's shape is not upstream's**: Bend has no dict and no
tuple, so `grads` is a `Grads` pair of parallel lists, the answer is a `GSet` record
carrying the slots, the per-slot IS-SUBSTITUTE flags, the grown arena and the
substitute count, and the graph is read from `O.Arena` rather than from Python's
`UOp` objects.

---

## 1. WHAT LANDED

`tinybendygrad/mixin/gradient.bend`, **+406 lines, 1 deletion** (the deletion is the
last line's trailing whitespace; the ROW is unchanged) — 2 456 → 2 862 lines,
**88 rows → 102 rows**.

| what | where | upstream |
|---|---|---|
| `grad_set` / `grad_set.go` | `:2509`, `:2514` | `mixin/op.py:471` |
| `gs_slot.of` / `gs_slot.sub` | `:2500`, `:2490` | the `if x in grads else` |
| `gs_zero.of` | `:2483` | `ops.py:581-583` (`const_like`) |
| `gs_dt` | `:2471` | the `dtype or self.dtype` half |
| `GSet` / `Gs` / `GRun` | `:2427`ff, `:2389`ff, `:2432`ff | Bend's no-dict shapes |
| `gs` fixture + `gs_leaf` + `gs_targets.of` + `gs_run` | `:2411`, `:2397`, `:2425`, `:2441` | the oracle's fixture |
| `bw_ident.*` / `bw_token` / `bw_srcs` / `bw_tok` | `:2548`–`:2590` | the graph signature |
| `bw_add` / `bw_union` / `bw_sig` / `bw_nodes` / `bw_distinct` | `:2597`–`:2746` | the `bw` graph |

**THE 14 NEW ROWS** (all CPython's own bytes, transcribed BY SCRIPT):

```
gs_walk=MUL/2 EXPAND/2 ADD/2 ADD/2      gs_set_n=3
gs_walk_n=4                             gs_zero_n=1
gs_inpath=0 0 0 1 1 1 1                 gs_set_sig=G 7 root=ADD/2 | G 6 root=MUL/2 | Z 2 root=CAST/1
gs_n_inpath=4                           bw_nodes=11
gs_grads_n=6                            bw_distinct=11
gs_keys=ADD/2 MUL/2 ADD/2 BUFFER/1 EXPAND/2 BUFFER/1
gs_skip_n=0                             bw_sig=ADD/2 [CAST/1 CAST/1] ADD/2 [CAST/1 MUL/2] BUFFER/1@s0 [STACK/0]
gs_hole_n=1                                        BUFFER/1@s1 [STACK/0] CAST/1 [CONST/0@f0]
                                                          CAST/1 [CONST/0@f1065353216] CONST/0@f0 []
                                                          CONST/0@f1065353216 [] MUL/2 [ADD/2 BUFFER/1@s0]
                                                          MUL/2 [ADD/2 BUFFER/1@s1] STACK/0 []
```

---

## 2. THE MEASUREMENTS, AND EVERY ONE NAMES ITS COMMAND

### 2.1 THE GATE — the port's rows against CPython

```
$ sh .agents/slop/backward2/run.sh check
=== arm=check  check-only: ALL PROOFS CHECK  run rc=0  rows=102
=== THE GATE: the port's new rows against rows.rows (CPython's values)
    rows compared: 14 of 14   mismatched: 0   VERDICT: PASS
```

`rows.rows` is produced by `sh .agents/slop/backward2/mkrows.sh`, which runs
`env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward2/oracle-gs.py`
and strips the `oracle_` prefix **BY SCRIPT**. **No expectation was typed by hand.**

### 2.2 THE PRE-EXISTING ROWS ARE BYTE-IDENTICAL

```
$ sh .agents/slop/backward2/run.sh head
    HEAD's gradient.bend installed: 1a1d034d3c5561ea0566181e88823b1b76ff95bed9d11cfa8f07460d13d22b0b
=== arm=head  check-only: ALL PROOFS CHECK  run rc=0  rows=88
=== HEAD vs LIVE: rows head=88 live=102
--- rows HEAD has that LIVE does NOT (must be EMPTY):
--- rows LIVE has that HEAD does NOT (must be EXACTLY the new rows):
    bw_distinct=11
    bw_nodes=11
    bw_sig=...
    gs_grads_n=6
    gs_hole_n=1
    gs_inpath=0 0 0 1 1 1 1
    gs_keys=ADD/2 MUL/2 ADD/2 BUFFER/1 EXPAND/2 BUFFER/1
    gs_n_inpath=4
    gs_set_n=3
    gs_set_sig=G 7 root=ADD/2 | G 6 root=MUL/2 | Z 2 root=CAST/1
    gs_skip_n=0
    gs_walk_n=4
    gs_walk=MUL/2 EXPAND/2 ADD/2 ADD/2
    gs_zero_n=1
--- rows that CHANGED VALUE (must be EMPTY):
    rows whose VALUE changed: 0
```

**⇒ 88 pre-existing rows, 0 changed value, 0 missing, 14 additions.** (The prior art
said "72 pre-existing rows"; HEAD's file carries **88** — the count moved since, and
the number quoted here is the one the diff prints.)

### 2.3 THE PLANTS AND THE DISARMS

`sh .agents/slop/backward2/run.sh base` first (it persists the differ's baseline),
then each arm. **The differ diffs whole `name=value` lines, not row names.**

| arm | the edit | rows moved | the rows |
|---|---|---|---|
| `plant_gswap` | the MUL rule's operands **UNCROSSED** (`gradient.py:80`) | **3** | `bw_nodes`, `bw_sig`, `bw_distinct` |
| `plant_nozero` | the ZERO SUBSTITUTE → the arena's reserved index 0 | **4** | `gs_set_sig`, `bw_nodes`, `bw_sig`, `bw_distinct` |
| `plant_setorder` | the gradient SET built in **REVERSE** order | **1** | `gs_set_sig` — **and `gs_set_n` and `gs_zero_n` do NOT move** |
| `plant_nohole` | the EXPAND's **HOLE** filled in (`gradient.py:86`) | **3** | `gs_hole_n`, `gs_grads_n`, `gs_keys` |
| `plant_noguard` | the `in_target_path` GUARD dropped (`gradient.py:114`) | **6** | `walk_*` + `gs_walk`, `gs_walk_n`, `gs_skip_n` |
| `plant_skipseed` | the SEED dropped, so the root SKIPS (`gradient.py:120`) | **19** | incl. `gs_skip_n` 0→4 |
| `plant_droptarget` | the THIRD TARGET dropped | **6** | `gs_set_n`, `gs_zero_n`, `gs_set_sig`, `bw_*` |
| `plant_flags` | the `in_target_path` FLAG always true (`gradient.py:112`) | **4** | `gs_walk`, `gs_walk_n`, `gs_inpath`, `gs_n_inpath` |
| `disarm_comment` | a comment's text | **0** | — |
| `disarm_name` | a local parameter name (signature + body) | **0** | — |

**⇒ EVERY ONE OF THE 14 NEW ROWS IS MOVED BY AT LEAST ONE PLANT**, and the two
disarms move nothing.

### 2.4 THE CONTROL ON THE CONTROL — a WRONG BUT NON-EMPTY expectation

```
$ .venv/bin/python .agents/slop/backward2/ctl-rows.py \
      .agents/slop/backward2/port.rows .agents/slop/backward2/rows.rows
(c) the UNPERTURBED expectations -> PASS  OK
(a) gs_walk        wrong-but-non-empty -> FAIL  mismatched=['gs_walk']  OK
(b) gs_walk        empty              -> FAIL  mismatched=['gs_walk']  OK
... (every row, both perturbations) ...
CONTROLS: 14 rows x 2 perturbations + the clean run -> failures: 0
```

**⇒ 29 controls, 0 failures.** For every row, (a) a wrong but **non-empty** value
fails and **exactly that row** is named, and (b) an **empty** value fails and names
the same row. **A gate that only caught empties would be catching vacuity, not
wrongness; this one catches both, and the "wrong but non-empty" case is the one that
proves it.**

### 2.5 THE ORACLE

`env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward2/oracle-gs.py`
→ **16 rows**, all of them CPython's own bytes, **14 of them gated** (`gs_set_order`
and `bw_ops` are CPython's own diagnostics and are named as not gated in §6). Its
fixture and its two "no gradient" reasons are in its docstring.

---

## 3. THE FINDING THAT MATTERS MOST: **THE PRIOR ART'S ORACLE NO LONGER RUNS**

```
$ env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward/oracle-cg.py
oracle_dag_inpath=0 0 1 0 1 1
oracle_dag_n_inpath=3
Traceback (most recent call last):
  ...
  File ".../tinygrad/mixin/gradient.py", line 130, in compute_gradient
    if k._shape is not None and v._shape is not None and k._shape != v._shape:
  File ".../tinygrad/uop/ops.py", line 359, in _shape
    assert len(self.src[0].as_shape) <= 1
IndexError: tuple index out of range
```

**`.agents/slop/backward/oracle-cg.py` — the oracle the 15 `walk_*` rows were
transcribed from — DIES on the tree's own `tinygrad/`.** The reason is upstream's
`_shape` for a BUFFER, which reads `self.src[0].as_shape` (`ops.py:359`), and the
prior art's fixture builds `UOp(Ops.BUFFER, arg=ParamArg(0, dtypes.float32))` — a
BUFFER with **no src**. It ran on 2026-10-07; it does not run today.

**⇒ THE 15 `walk_*` ROWS' CPYTHON SIDE IS STALE AND CANNOT BE RE-VERIFIED TODAY.**
The port's rows are unchanged (2.3 measures that) and the values still agree with the
oracle's **recorded** output, but the recording is not reproducible against the
current upstream.

**THE FIX IS THE LEAF.** A leaf whose src is an **EMPTY STACK** has `as_shape` `()`
(`ops.py:789`), so `_shape` is `()` — SCALAR — and the shaped-edge reduce at
`gradient.py:131` never fires. MEASURED by `probe2.py` (three leaf kinds × three
fixtures): `L1` = `BUFFER(STACK())` computes; a src-less BUFFER raises `IndexError`;
a CONST leaf computes but has `weakfloat` dtype, which changes the zero substitute.

⇒ **The new fixture's leaf is `BUFFER(STACK())`** and the oracle builds the same.

---

## 4. THE FIXTURE, AND WHY IT IS THIS ONE

```
a = BUFFER(0)   sh = STACK()   p = MUL(a, b)
b = BUFFER(1)   e = EXPAND(p, sh)   q = ADD(a, e)
z = BUFFER(9)   r = ADD(p, q)       <- the root
```

**TWO DIFFERENT REASONS FOR A TARGET TO HAVE NO GRADIENT**, and they are different
reasons, so the fixture needs two mechanisms:

* **`sh` — a REAL HOLE.** upstream's EXPAND rule answers `(ctx, None)`
  (`gradient.py:86`), so `sh` receives nothing. `gs_hole_n = 1`. **The prior art's
  `walk_hole_n = 0` was a fact about ITS fixture and not a coverage statement; this
  is the fixture that makes it non-zero.**
* **`z` — a DETACHED TARGET.** It is on no path, so `grads` has no entry and the
  `const_like(0)` substitute fires. `gs_zero_n = 1`, and the substitute is
  `CAST(CONST 0.0)` — the same `CAST(CONST)` pair `gconst` builds.

**THE EXPAND'S SHAPE SRC MUST BE AN EMPTY STACK.** `as_shape` of a CONST is `(val,)`
(`ops.py:787`) and of a non-STACK is `(ssimplify(self),)` (`ops.py:788`) — both
ONE-tuples — so an EXPAND over a CONST-1 shape has `_shape` `(1,)`, the shaped-edge
reduce fires and CPython raises `RuntimeError: cannot broadcast (1,) into ()`.
**MEASURED**: that is exactly what a CONST-1 shape src does. `as_shape` of an EMPTY
STACK is `()`, so the EXPAND's `marg` is `()` and its `_shape` is `()`.

**THE ACCUMULATE FIRES TWICE** (`gradient.py:138`): `p` is written by the root and by
the EXPAND, `a` by `q` and by `p`. `gs_keys` is the INSERTION ORDER
(`ADD/2 MUL/2 ADD/2 BUFFER/1 EXPAND/2 BUFFER/1`) and it is a dict-shaped row, not a
bag: an append-only table that lost would print the toposort order instead.

---

## 5. THE `bw` SIGNATURE, AND WHY IT IS BUILT THE WAY IT IS

**IT IS INDEX-FREE, AND THAT IS FORCED.** The port's arena indices and CPython's
construction order are two different numberings of two different interning processes,
so a signature keyed on them would compare two different things. The corpus solves
this with a structural differ (`.agents/slop/graphcmp.py:940` `row_of` + the
differ's bipartite pairing) — that machinery is not reachable from inside a `.bend`
file, so the signature is built to be index-free instead.

**THE IDENT IS WHAT MAKES IT A SIGNATURE AND NOT A CENSUS.** With the class token
alone (`OP/nsrc`), `a` and `b` are both `BUFFER/1` — the signature could not see the
MUL rule's operands being SWAPPED, which is upstream's `gradient.py:80`
(`ret.src[1]*ctx`, `ret.src[0]*ctx`) and is THE bug a backward-graph row exists for.
So the token carries an **IDENT**: a CONST's **f32 bits** (`@f1065353216`) and a
BUFFER's **PARAM slot** (`@s0`, `@s1`, `@s9`).

**⇒ `plant_gswap` IS THE MEASUREMENT OF THAT CLAIM**: the swap moves `bw_sig`,
`bw_nodes` and `bw_distinct` and **NOTHING ELSE** — `gs_set_sig` does not move
(the slot's root op and node count are unchanged), and no count row moves at all.

**`bw_distinct = 11` IS THE INJECTIVITY ROW AND IT IS MEASURED, NOT ASSERTED.**
`bw_sig` is a COMPLETE description of this graph only if no two nodes share a token.
The row counts the DISTINCT tokens and it reads 11 — the same as `bw_nodes` — so on
THIS fixture the signature IS the graph. **The limit is named**: this is the 1-ROUND
WEISFEILER-LEMAN refinement, so two graphs that differ only in WHICH node of the same
class a src points to would share a signature — and the injectivity row is what
says whether that is true here.

---

## 6. THE WALLS, AT `file:line`

| what | where | why |
|---|---|---|
| **THE CORPUS's `bw` GRAPH IS NOT REPRODUCIBLE BY THE PORT's `compute_gradient`** | `.agents/slop/graphcmp.bend:1471` (`g_bw`) vs `mixin/gradient.bend:606`, `:639`, `:675` | the corpus's `bw` op census is `ALLOC 2 CAST 1 CONST 4 EXPAND 2 GROUP 1 MUL 2 PERMUTE 4 REDUCE 2 RESHAPE 8 STACK 6` (`.agents/slop/backward-graph/REPORT.md` §1), and the port's rules for **PERMUTE (`gr_21`), RESHAPE (`gr_17`) and REDUCE (`gr_14`) are `GSkip{}`** — so the port's walk STOPS at the first of them (the named divergence at `mixin/gradient.bend:1430`). **⇒ The port's `bw` graph and the corpus's `bw` graph are DIFFERENT GRAPHS.** The corpus's is hand-built in both languages; the port's is what the gradient machinery BUILDS. |
| `gr_21` PERMUTE — **the one the file's own comment says is buildable** | `mixin/gradient.bend:675` | `ctx.permute(argsort(ret.marg))`; `ret.marg` for a PERMUTE is `self.arg`, an `O.ATuple{ys: List<&2, U32>}` (`ops.bend:1237`), and **`helpers.bend`'s `argsort_u32` ALREADY EXISTS** (`helpers.bend:602`) and `helpers.bend` IS imported as `H`. **The rule is `GSkip{}` anyway** — the comment says "the whole rule is: read the ATuple, argsort it, build the PERMUTE". **⇒ THIS IS THE NEXT STEP, and it is a HALF-HOUR OF WORK, not a research problem.** |
| `gr_17` RESHAPE | `mixin/gradient.bend:639` | `ctx.reshape(ret.src[0].shape)` — a FOLD read of the shape plus `prod` for the `-1` arm. The port's fold carries shapes; the `prod`/`-1` arm is the open part. |
| `gr_14` REDUCE (`reduce_gradient`) | `mixin/gradient.bend:606` | `_rop`'s `resolve(self.shape[x] != 1)` and `_broadcast_to`'s `broadcast_axes` are both `resolve` on a `Sint`, and **`uop/symbolic.py`'s `resolve` is NOT ported** (Phase P3 owns `symbolic`). **⇒ A HARD WALL, and it is also a place CPython ITSELF raises** on a shaped seed. |
| `const_like`'s EXPAND arm | `mixin/gradient.bend:2483` | `x._mop(Ops.EXPAND, arg=self._shape)` when `self._shape` is truthy. **Unreachable here** — a target's `_shape` is `None` or `()` and `()` is FALSY. **NAMED OMISSION.** |
| the shaped-edge reduce | `gradient.py:131` | `broadcast_axes` + `sum_acc_dtype`. **Not reached by this fixture** (every shape is `()`), and **CPython raises on the shaped fixtures** — so there is no CPython answer to gate against. |
| the `tensor.bend` DIVERGENCE | `tensor.bend:1960` (`tn_bwd_slot`) | the port's `tensor.bend` answers the substitute with the arena's reserved index 0 because it cannot intern a float literal. `mixin/gradient.bend` CAN (`gconst`), and `plant_nozero` shows the difference is visible: `Z 2 root=CAST/1` vs `Z 1 root=NOOP/0`. **⇒ The VALUE is now built here; `tensor.bend` still selects it.** Wiring `tensor.bend` to this def is **NOT DONE** — `tensor.bend` is not this unit's file. |
| `bw_ops` | — | the oracle prints a per-op count as a DIAGNOSTIC; **it is not gated**, because `bw_sig` already names every node and every op in the backward graph and a per-op COUNT is a second reading of the same row. |
| `oracle_gs_set_order` | — | CPython's own diagnostic; **not gated**, because the target order is visible in `gs_set_sig` (the three slots have three different signatures). |

---

## 7. THE THINGS MEASURED THAT THE PORT NOW SAYS OUT LOUD

1. **A CLASS-ONLY TOKEN IS A CENSUS, NOT A SIGNATURE.** The first `bw_sig` was built
   from `OP/nsrc` alone and it could not see the MUL rule's operands swapped, because
   `a` and `b` are both `BUFFER/1`. Adding the IDENT (the CONST's bits, the BUFFER's
   slot) is what turned it into a row that catches the swap. **MEASURED**:
   `plant_gswap` moves `bw_sig` and moves no count.
2. **`plant_setorder` MOVES ONE ROW AND IT IS THE SIGNATURE.** The gradient SET built
   in reverse leaves `gs_set_n = 3` and `gs_zero_n = 1` **UNCHANGED** — the counts
   are right — and only `gs_set_sig` moves. **A COUNT-ONLY GATE WOULD CALL THAT MUTANT
   GREEN.** This is the prior art's `plant_noguard`-leaves-`walk_grads_n`-at-6
   argument, reproduced on a NEW row.
3. **`gs_targets` WAS A DEF WITH NO CALLER.** The first revision spelled `[a, b, z]`
   in `gs_run` as well as in `gs_targets`, and `gs_targets` was then dead — which is
   this file's own note about `gbool` ("a def claiming a CPython expression with no
   caller is a claim of unknown value"). **MEASURED**: `plant_droptarget`, which edits
   `gs_targets`, moved **0** rows while the def was dead. It is now the ONE place the
   targets are spelled, and the same plant moves **6** rows.
4. **`gs_skip_n` NEEDED A PLANT OF ITS OWN.** It is 0 on this fixture, and a row that
   is 0 needs a mutation that makes it non-zero: `plant_skipseed` (the seed dropped,
   so the root hits `gradient.py:120`'s `continue`) moves it 0 → 4.
5. **A MATCH CANNOT SCRUTINISE A COMPUTED VALUE NOR A LOCAL BINDER.** Three separate
   compile errors, each naming the rule: `match O.Arena.srcs(ar, n)` (computed),
   `match List.contains(...)` (computed), and `match g:` after `+ts = gs_targets(g)`
   (a local statement precedes it). **⇒ the shape that works is a def whose PARAMETER
   is the thing being matched.**
6. **`+` ON A BINDER MEANS "USED MORE THAN ONCE".** `case +t <> ts:` is what lets
   `grad_set.go` use the target twice; without it: "t (consumed more than once)".

---

## 8. WHAT IS *NOT* CLAIMED

- **The port's `bw` graph is NOT the corpus's `bw` graph.** They are different graphs
  (see §6). The corpus's `bw` is a hand-built fixture that already agrees
  (`.agents/slop/backward-graph/REPORT.md`); the port's is what the gradient machinery
  builds, and it is the one this unit gated.
- **THE 15 PRE-EXISTING `walk_*` ROWS' CPYTHON SIDE IS STALE** (§3). Their VALUES
  are unchanged and are 0-changed against HEAD (§2.2), but the oracle that produced
  them no longer runs, so they cannot be re-verified against CPython today. **THIS IS
  A FINDING ABOUT THE PRIOR ART, NOT A DEFECT IN IT** — the oracle ran on 2026-10-07
  and upstream's `_shape` changed since.
- **THE FIXTURE IS SCALAR-SHAPED.** Every `_shape` is `()`, so the shaped-edge reduce
  (`gradient.py:131`) is never exercised — and CPython raises on the shaped fixtures,
  so there is no CPython answer to gate against anyway. **NAMED WALL.**
- **`gs_inpath` and `gs_n_inpath` ARE THE FLAGS, NOT THE WALK.** `plant_noguard`
  (the walk's FILTER) moves `gs_walk` and `gs_walk_n` and does **not** move them;
  `plant_flags` (the flag PASS) moves all four. **The two are different objects and
  the row names say which is which.**
- **THE `bw` SIGNATURE IS 1-ROUND WEISFEILER-LEMAN.** On this fixture it is COMPLETE
  (`bw_distinct = bw_nodes = 11`, MEASURED). On a bigger graph it would be a
  refinement and not a description, and the injectivity row is what tells you which
  case you are in.
- **NOTHING WAS COMMITTED.** `git status` shows `tinybendygrad/mixin/gradient.bend`
  modified and `.agents/slop/backward2/` untracked. **No mutating git command was
  run**; the only git reads were `git rev-parse HEAD`, `git status --porcelain=v1`,
  `git diff --stat HEAD -- <path>` and `git show HEAD:<path>`, all with
  `env -u GIT_INDEX_FILE`.

---

## 9. THE EXACT NEXT STEP

**STEP 1 — `gr_21` (PERMUTE), in `mixin/gradient.bend:675`.** It is `GSkip{}` and
the file's own comment says the whole rule is "read the ATuple, argsort it, build the
PERMUTE". The pieces EXIST: `O.ATuple{ys: List<&2, U32>}` (`ops.bend:1237`),
`H.argsort_u32` (`helpers.bend:602`), and `helpers.bend` is already imported. The
rule is `ctx.permute(argsort(ret.marg))` — one `gnew` with an `O.ATuple` arg. **A
PERMUTE on the `gs` fixture would then put a PERMUTE in the port's `bw` graph, and
the signature would gain a node whose IDENT is the PERMUTE's MARGIN** — which is the
first `bw` graph in the port that carries an `arg` other than a dtype.

**STEP 2 — `gr_17` (RESHAPE), `mixin/gradient.bend:639`.** `ctx.reshape(ret.src[0].shape)`
is a FOLD read of the source's shape plus the `prod`/`-1` arm. The fold carries the
shape; the open part is the `-1` inference.

**STEP 3 — `gr_14` (REDUCE), `mixin/gradient.bend:606`, IS A HARD WALL.**
`reduce_gradient` needs `_rop`'s `resolve(shape[x] != 1)` and `_broadcast_to`'s
`broadcast_axes`, and **`uop/symbolic.py`'s `resolve` is not ported** (Phase P3 owns
`symbolic`). **Do not attempt it before `symbolic.py` lands.**

**STEP 4 — WIRE `tensor.bend`'s `tn_bwd_slot` TO THIS `grad_set`.** `tensor.bend:1960`
answers the substitute with the arena's reserved index 0 (a NAMED DIVERGENCE);
`mixin/gradient.bend` now builds the real `CAST(CONST 0.0)`. **`tensor.bend` is NOT
this unit's file** — the change is one line and it needs that file's owner.

**STEP 5 — RE-VERIFY THE PRIOR ART'S ORACLE.** `.agents/slop/backward/oracle-cg.py`
no longer runs (§3). The fix is the LEAF: `BUFFER(STACK())` instead of a src-less
BUFFER, which is the same one-line change this unit's fixture makes. **The 15
`walk_*` rows' expectations then become reproducible again** — and that is a
prerequisite for anyone claiming the walk is gated against CPython *today*.

**STEP 6 — `.agents/TODO.md`'s `backward-walk` ROW IS STALE** and this unit did not
edit it (it is not this unit's file). It says "STEPS 2 AND 3 (`grad_set`, the `bw`
graph) ARE NOT DONE"; `grad_set` is done and measured here, and the `bw` graph is
done **for the port's own gradient machinery** — while the corpus's `bw` graph is
still out of reach for the reasons in §6.

---

## 10. THE FILES

| file | what |
|---|---|
| `tinybendygrad/mixin/gradient.bend` | **THE ONLY `.bend` FILE TOUCHED.** +406 lines. |
| `.agents/slop/backward2/REPORT.md` | this file |
| `.agents/slop/backward2/oracle-gs.py` | the CPython oracle — the fixture, the gradient set, the `bw` graph |
| `.agents/slop/backward2/oracle-gs.rows` | the oracle's output |
| `.agents/slop/backward2/rows.rows` | **the expectations — transcribed BY SCRIPT from the oracle** |
| `.agents/slop/backward2/mkrows.sh` | the transcription (never by hand) |
| `.agents/slop/backward2/gate.py` | the gate: the port's rows vs `rows.rows` |
| `.agents/slop/backward2/ctl-rows.py` | the per-row controls, and the control on the control |
| `.agents/slop/backward2/run.sh` | the harness: `check`, `head`, 8 plants, 2 disarms |
| `.agents/slop/backward2/probe.py`, `probe2.py` | the probes that found the stale oracle and the working leaf |
| `.agents/slop/backward2/port.rows` | the port's output (102 rows) |
| `.agents/slop/backward2/transcript-head.out`, `transcript-plants.out` | the transcripts of §2.2 and §2.3 |
