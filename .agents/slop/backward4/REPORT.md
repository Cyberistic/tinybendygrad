# backward4 — LAND THE PORT'S `gr_21` (PERMUTE) BACKWARD RULE, GATE IT AGAINST CPython, AND MEASURE `gr_17`/`gr_14`

**Status: COMPLETE. `gr_21` IS LANDED, GATED AGAINST UPSTREAM'S OWN `compute_gradient`
ON A FIXTURE BOTH SIDES BUILD, AND EVERY ONE OF ITS 36 ROWS HAS A PLANT THAT MOVES IT.**

**Owners**: `tinybendygrad/mixin/gradient.bend` (the rule + the fixture + the rows) and
`.agents/slop/backward4/`.
**NOT touched**: `checks/`, `gates/`, `references/`, `AGENTS.md`, `.agents/TODO.md`,
`.agents/TOOLS.md`, `.agents/slop/graphcmp.py`, `.agents/slop/graphcmp.bend`,
`.agents/slop/backward/`, `.agents/slop/backward2/`, `.agents/slop/backward3/`.
**VERIFIED**: `env -u GIT_INDEX_FILE git status --porcelain -- <those paths>` prints
nothing for `backward{,2,3}/`, `graphcmp.py` and `graphcmp.bend`; and
`git diff --stat HEAD -- tinybendygrad/` names **exactly one file**:
`tinybendygrad/mixin/gradient.bend | 404 ++++---` (398 insertions, 6 deletions).
**⇒ AND A GIT-INDEPENDENT WITNESS, BECAUSE `.agents/slop/backward2/` IS **UNTRACKED** IN
GIT (a prior unit's work that was never committed) AND `git status` THEREFORE CANNOT
WITNESS IT: EVERY FILE IN `backward/`, `backward2/` AND `backward3/` HAS AN MTIME
BETWEEN 17:54 AND 18:45, AND THIS UNIT STARTED AT 21:00.**
**NOTHING COMMITTED. NO MUTATING GIT COMMAND.** The only git reads were
`git rev-parse HEAD`, `git show HEAD:tinybendygrad/mixin/gradient.bend` and
`git status --porcelain`, all with `env -u GIT_INDEX_FILE`.

---

## 0. THE CAUSE, IN ONE PARAGRAPH (both sides, `file:line`)

**The previous unit's MEASUREMENTS were right and its CONCLUSION was wrong.** Upstream's
`permute` is `tinygrad/mixin/movement.py:214-231`, and its body is
`order_arg = tuple(self._resolve_dim(x) for x in argfix(order, *args))` /
`if sorted(order_arg) != list(range(self.ndim)): raise RuntimeError(...)` /
`return self._mop(Ops.PERMUTE, arg=order_arg) if order_arg != tuple(range(self.ndim)) else self`.
The two raises the previous unit measured are REAL and REPRODUCED here — on a 1-D ctx a
2-element order raises `IndexError: dim=1 out of range [-1, 0]` (from `_resolve_dim`,
`movement.py:83`) and a 1-element order against a 2-D ctx raises
`RuntimeError: order is not a valid permutation, getting (0,)` (`movement.py:230`) — **but
BOTH ARE CORRECT ANSWERS, NOT THE ABSENCE OF AN ANSWER, AND NEITHER IS THE WALL.**
**THE REAL WALL WAS THE FIXTURE, AND IT WAS AN ARTEFACT OF ONE ASSUMPTION: that a
MULTI-DIMENSIONAL `ctx` needs a RESHAPE.** It does not: upstream's `_shape` for a STACK is
`(len(self.src),) + self.src[0].shape` (`tinygrad/uop/ops.py:352-354`), so **a STACK of
1-D nodes is 2-D, and a STACK of a 2-D node and a 1-D node is 3-D** — MEASURED,
`STACK(x, y)` has `shape=(2, 2)` and `ndim=2` (`.agents/slop/backward4/probe.py`).
And `_resolve_dim` (`movement.py:81-84`) is pure integer arithmetic over `self.ndim` and
**never calls `resolve`** — so the `resolve` wall the prior art named for `gr_21` is NOT
AT `gr_21`. **⇒ `gr_21` IS LANDABLE, AND IT IS LANDED, AND IT IS GATED AGAINST
UPSTREAM'S OWN `compute_gradient` ON A FIXTURE BOTH SIDES BUILD.**

## 1. THE CAUSE, MEASURED

### 1.1 UPSTREAM PRODUCES A FULL ANSWER — the prior art's claim (B) is FALSIFIED

```
$ env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/backward4/probe.py
STACK(x, y)            op=STACK     nsrc=2 arg=None shape=(2, 2) dtype=dtypes.f32
      ndim=2 shape=(2, 2)
PERMUTE(st, (1,0))     op=PERMUTE   nsrc=1 arg=(1, 0) shape=(2, 2) dtype=dtypes.f32
      marg=(1, 0) ndim=2 shape=(2, 2)
x (1-D).permute(1,0)   RAISED IndexError: dim=1 out of range [-1, 0]
ctx = STACK(p, q)      op=STACK     nsrc=2 arg=None shape=(2, 2) dtype=dtypes.f32
      ctx.permute((1,0))     op=PERMUTE   nsrc=1 arg=(1, 0) shape=(2, 2)
```

**⇒ THE PRIOR ART's IndexError IS UPSTREAM'S CORRECT ANSWER FOR A 1-D ctx.** A 1-D ctx
admits no non-identity permutation, so a raise is the right answer. **The wall was the
FIXTURE, not the RULE.**

### 1.2 UPSTREAM'S `compute_gradient` ON THE FIXTURE — A COMPLETE ANSWER

`$ .venv/bin/python .agents/slop/backward4/oracle-pm.py` →
`.agents/slop/backward4/oracle-pm.rows` (36 gated rows).

```
oracle_pm_walk=PERMUTE/1
oracle_pm_walk_n=1
oracle_pm_rule_len=1
oracle_pm_rule_is_ctx=0
oracle_pm_rule_tok=PERMUTE/1 [STACK/2]
oracle_pm_rule_op=PERMUTE/1
oracle_pm_rule_arg=2,0,1
oracle_pm_grads_n=2
oracle_pm_keys=PERMUTE/1 STACK/2
oracle_pm_zero_n=0
oracle_pm_set_n=1
oracle_pm_set_sig=G 8 root=PERMUTE/1
oracle_pm_bw_nodes=8
oracle_pm_bw_sig=BUFFER/1@s3 [STACK/1] BUFFER/1@s4 [STACK/1] BUFFER/1@s5 [STACK/1] CONST/0@i0:2 [] PERMUTE/1 [STACK/2] STACK/1 [CONST/0@i0:2] STACK/2 [BUFFER/1@s3 BUFFER/1@s4] STACK/2 [BUFFER/1@s5 STACK/2]
oracle_pm_bw_distinct=8
```

**⇒ THE WALK IS EXACTLY ONE NODE DEEP, AND THE BACKWARD GRAPH IS EIGHT NODES.**

### 1.3 THE PORT'S `compute_gradient` ON THE SAME FIXTURE — THE SAME EIGHT NODES

```
$ BEND_NO_TELEMETRY=1 ./bin/bend tinybendygrad/mixin/gradient.bend > port.rows
pm_bw_sig=BUFFER/1@s3 [STACK/1] BUFFER/1@s4 [STACK/1] BUFFER/1@s5 [STACK/1] CONST/0@i0:2 [] PERMUTE/1 [STACK/2] STACK/1 [CONST/0@i0:2] STACK/2 [BUFFER/1@s3 BUFFER/1@s4] STACK/2 [BUFFER/1@s5 STACK/2]
```

**⇒ THE TWO SIDES' `bw_sig` ARE BYTE-IDENTICAL** — the whole eight-node graph, token for
token.

### 1.4 THE ARGSORT — THE BRIEF'S SUSPICION WAS WRONG, AND HERE IS THE PROOF

**The brief said:** *"`argsort_u32` SORTS A LIST OF *ARENA INDICES*, WHILE UPSTREAM's
`argsort` SORTS *VALUES* … SO `argsort_u32` MAY BE THE WRONG FUNCTION FOR AN `ATuple` —
IT SORTS BY THE INDEX, NOT BY THE VALUE THE INDEX POINTS AT."*

**MEASURED, ON BOTH SIDES, ON THE SAME SIX INPUTS:**

| input | upstream `argsort` (`tinygrad/helpers.py:28`) | the port's `H.argsort_u32` (`tinybendygrad/helpers.bend:602`) |
|---|---|---|
| `(0,2,1)` | `0,2,1` | `0,2,1` |
| `(1,2,0)` | `2,0,1` | `2,0,1` |
| `(2,1,0)` | `2,1,0` | `2,1,0` |
| `(1,0,2)` | `0,2,1` | `0,2,1` |
| `(2,0,1)` | `1,2,0` | `1,2,0` |
| `(1,0)` | `1,0` | `1,0` |

**⇒ THE BRIEF'S SUSPICION IS FALSE.** `argsort_u32` pairs each value with its index
(`Ix{i, v}`), sorts by `(value, index)` — Python's `sorted` is stable, so the index breaks
the ties — and projects the INDEX back out (`helpers.bend:582-602`). **⇒ IT IS UPSTREAM'S
`argsort`, AND IT IS THE RIGHT FUNCTION FOR AN `ATuple`.** The suspicion came from reading
`argsort_u32`'s NAME and not its BODY. **AND THE `argsortbyindex` PLANT (§4.4) PLANTS THE
SUSPICION IN BOTH DIRECTIONS: if the port sorted by the index, all six rows would go RED.**

### 1.5 THE INT-CONST IDENT — A SPELLING DIVERGENCE, NOT A `gr_21` DIVERGENCE

The port's `bw_ident.const` spells an int CONST as `@i` + `H.i64_text(i)` =
**`@i0:2`** (`helpers.bend:1709-1712`: an I64 prints as its TWO WORDS, `hi:lo`), while the
prior art's oracle spelled it `@i%d` = **`@i2`**. **⇒ THE PORT IS RIGHT AND THE ORACLE
WAS WRONG**, and the corpus says so in its own source: `.agents/slop/graphcmp.py:388`
`i64(x)` is `f"{x >> 32}:{x & 0xFFFFFFFF}"` — "exactly `H.i64_text`" — and
`graphcmp.py:459` `konst()` NORMALISES CPython's int to it: *"CPython's int is normalised
to the port's I64 form so `UOp.const(4)` is `l0:4` on BOTH sides rather than `i4` here
and `l0:4` there"*. **⇒ MY ORACLE PRINTS THE CORPUS'S SPELLING, AND THE PRIOR ART'S
`@i%d` WAS NEVER EXERCISED BECAUSE ITS FIXTURE HAD NO INT CONST.**

---

## 2. WHAT I EXTENDED, AND WHY

**I EXTEND `.agents/slop/backward3/`'s HARNESS DISCIPLINE AND CALL ITS CODE; I DO NOT
COPY IT AND I DO NOT EDIT IT.** `backward3/gate.py` is generic (it takes
`<port.rows> <expect.rows>` and reports `PASS`/`MISMATCH`/`UNCHECKABLE`/`MISSING` with
FOUR verdicts, and `MISMATCH` and `UNCHECKABLE` are BOTH red), and
`backward3/ctl-rows.py` is the two-class control harness. **⇒ MY `run.sh` CALLS BOTH BY
PATH** (`sys.path.insert`), so there is ONE gate implementation in the tree and no second
copy to rot. **WHAT I ADDED, because `backward3` did not have it:** (a) the
`oracleplant` arm — the CONTROL ON THE CONTROL, which `backward3/run.sh` has and which
`backward3/ctl-rows.py`'s DOCSTRING describes as "(c)" but its CODE does not implement
(**a DOC/CODE DIVERGENCE IN THE PRIOR ART, MEASURED BY READING IT, AND IT IS NOT MY
FILE TO FIX**); (b) the `head` arm with an EXPLICIT assertion that no pre-existing row
moved; (c) the `plants` arm — a MUTATION SWEEP whose COVERAGE is asserted.

**THE PRIOR ART'S HARNESS IS THE PRIOR ART'S HARNESS**: `backward3/run.sh` and
`backward2/run.sh` are the prior art's; my `run.sh` calls `backward3/gate.py` and
`backward3/ctl-rows.py` by path and adds the arms this task needs.

## 3. THE FIXTURE, ON BOTH SIDES, AND THE PROOF THEY ARE THE SAME GRAPH

### 3.1 THE TWO FIXTURES

```
P3 (the 3-D PERMUTE, the PRIMARY)          P1 (the 1-D IDENTITY PERMUTE, the CONTROL)
  l0 = BUFFER(0) shape (2,)                   leaf = BUFFER(0) shape (6,)
  l1 = BUFFER(1) shape (2,)                   per  = PERMUTE(leaf, (0,))   <- THE ROOT
  l2 = BUFFER(2) shape (2,)                   g    = BUFFER(1) shape (6,)   <- THE ROOT GRAD
  s01 = STACK(l0, l1)  shape (2, 2)          THE TARGET IS `leaf`.
  a   = STACK(s01, l2) shape (2, 2, 2)  <- THE TARGET
  per = PERMUTE(a, (1, 2, 0))          <- THE ROOT
  m0 = BUFFER(3) shape (2,)
  m1 = BUFFER(4) shape (2,)
  m2 = BUFFER(5) shape (2,)
  n01 = STACK(m0, m1)  shape (2, 2)
  ctx = STACK(n01, m2) shape (2, 2, 2)  <- THE ROOT GRAD
```

**⇒ FOUR DESIGN CLAUSES, AND EVERY ONE IS A MEASUREMENT:**

1. **A MULTI-DIMENSIONAL NODE WITH NO RESHAPE.** upstream's `_shape` for a BUFFER reads
   `self.src[0].as_shape` (`ops.py:359`) and ASSERTS `len(self.src[0].as_shape) <= 1`, so
   a BUFFER is at most 1-D; a STACK's `_shape` is `(len(self.src),) +
   self.src[0].shape` (`ops.py:352-354`), so a STACK of 1-D nodes is 2-D and a STACK of a
   2-D node and a 1-D node is 3-D.
2. **THE TARGET IS THE 3-D NODE ITSELF.** upstream's `_deepwalk` sets
   `in_target_path[u] = any(in_target_path[x] or x in targets for x in u.src)`
   (`gradient.py:112`), so a node is in the WALK only if one of its SRCS reaches a target
   — **A TARGET IS NEVER ITSELF IN THE WALK**, so the target's own rule is never needed.
   The target here is a STACK, whose rule (`ctx[i]`, `gradient.py:91`) this port cannot do
   (`gr_22` is `GSkip`). **⇒ MAKING THE 3-D NODE THE TARGET IS WHAT KEEPS THE FIXTURE
   INSIDE `gr_21` ALONE.**
3. **THE ROOT GRAD IS A STACK TOO**, because `ctx` must have `ndim == 3` or upstream's
   `_resolve_dim` (`movement.py:81-84`) rejects a 3-element order, and a BUFFER is at most
   1-D.
4. **EVERY DIMENSION IS 2**, because `per`'s shape is `a`'s shape PERMUTED and `ctx`'s
   shape must EQUAL it or the shaped-edge reduce at `gradient.py:131` fires and upstream
   raises (it needs `broadcast_axes`, which is symbolic).

**⇒ AND THE FIXTURE IS 3-D RATHER THAN 2-D FOR A REASON ABOUT TEETH, NOT ABOUT SHAPE:
A 2-ELEMENT PERMUTATION IS AN INVOLUTION, SO ITS ARGSORT IS ITSELF** (`argsort((1,0))`
is `(1,0)`, MEASURED), **so on a 2-D fixture the rule's ORDER row would read the same
whether the rule ARGSORTED or merely copied the order — A ROW THAT CANNOT GO RED IS A
LABEL.** With the order `(1, 2, 0)` the argsort is `(2, 0, 1)` and the row tells them
apart.

### 3.2 THE PORT'S SPELLING (byte for byte, `tinybendygrad/mixin/gradient.bend`)

```
def pm_leaf(+ar: O.Arena, slot: U32, size: U32) -> O.Found:
  +c = pm_c(ar, size)                                  # a BARE CONST: O.UOp.const
  +sh = gnew(O.Found.ar(c), O.OpsSTACK{}, [O.Found.i(c)], O.ANone{})
  gnew(O.Found.ar(sh), O.OpsBUFFER{}, [O.Found.i(sh)], O.AParam{fx_pa(slot)})

def pm() -> Pm:
  +l0 = pm_leaf(O.Arena.empty(), 0, 2)
  +l1 = pm_leaf(O.Found.ar(l0), 1, 2)
  +l2 = pm_leaf(O.Found.ar(l1), 2, 2)
  +s01 = gnew(O.Found.ar(l2), O.OpsSTACK{}, [O.Found.i(l0), O.Found.i(l1)], O.ANone{})
  +a = gnew(O.Found.ar(s01), O.OpsSTACK{}, [O.Found.i(s01), O.Found.i(l2)], O.ANone{})
  +per = gnew(O.Found.ar(a), O.OpsPERMUTE{}, [O.Found.i(a)], O.ATuple{[1, 2, 0]})
  +m0 = pm_leaf(O.Found.ar(per), 3, 2)
  +m1 = pm_leaf(O.Found.ar(m0), 4, 2)
  +m2 = pm_leaf(O.Found.ar(m1), 5, 2)
  +n01 = gnew(O.Found.ar(m2), O.OpsSTACK{}, [O.Found.i(m0), O.Found.i(m1)], O.ANone{})
  +ctx = gnew(O.Found.ar(n01), O.OpsSTACK{}, [O.Found.i(n01), O.Found.i(m2)], O.ANone{})
  Pm{O.Found.ar(ctx), O.Found.i(a), O.Found.i(per), O.Found.i(ctx)}
```

### 3.3 THE PROOF THEY ARE THE SAME GRAPH — NODE FOR NODE, NOT A COUNT

**THE `bw_sig` IS A NODE-FOR-NODE SIGNATURE AND BOTH SIDES PRINT IT IN THE SAME SPELLING**
(the port's `bw_tok.go`/`bw_ident.of`, `gradient.bend:2622-2660`; the oracle's
`local_token`/`ident`, `oracle-pm.py`). **⇒ THE TWO STRINGS ARE BYTE-IDENTICAL, AND
EVERY TOKEN IS ONE NODE:**

```
BUFFER/1@s3 [STACK/1]   BUFFER/1@s4 [STACK/1]   BUFFER/1@s5 [STACK/1]   CONST/0@i0:2 []
PERMUTE/1 [STACK/2]     STACK/1 [CONST/0@i0:2]  STACK/2 [BUFFER/1@s3 BUFFER/1@s4]
STACK/2 [BUFFER/1@s5 STACK/2]
```

| node | upstream | the port |
|---|---|---|
| the root grad | `STACK(STACK(m0,m1), m2)`, `m0..m2` on slots 3/4/5 | `O.OpsSTACK{}` over `BUFFER slot 3/4/5` |
| the answer | `UOp(Ops.PERMUTE, src=(ctx,), arg=(2,0,1))` | `gnew(ar, O.OpsPERMUTE{}, [ctx], O.ATuple{[2,0,1]})` |
| the leaves | `UOp(Ops.BUFFER, src=(STACK(CONST 2),), arg=ParamArg(3, f32))` | `gnew(ar, O.OpsBUFFER{}, [sh], O.AParam{fx_pa(3)})` with `sh` = `STACK(CONST 2)` |
| the shape CONST | `UOp(Ops.CONST, arg=2)` — a BARE CONST, `dtype=weakint` | `O.UOp.const(ar, O.CInt{2})` — a BARE CONST (`ops.bend:3012`) |

**⇒ EIGHT NODES, EIGHT IDENTICAL TOKENS, ZERO DIFFERENCES — AND THE COUNT ALONE WOULD NOT
HAVE PROVED IT** (the prior art's own finding: *"BOTH READINGS ARE 32 NODES WITH 11
DISTINCT OPS, SO A COUNT-BASED GATE READS THEM AS THE SAME GRAPH"*). **⇒ THE GATE
COMPARES THE SIGNATURE, WHICH IS THE WHOLE GRAPH.** **AND THE `bw_distinct` ROW MEASURES
THAT THE SIGNATURE IS LOSSLESS HERE: 8 of 8.**

### 3.4 THE DERIVED `bw` LANE — WHAT THE ORCHESTRATOR HAS TO WIRE IN

**THE CORPUS's `bw` GRAPH IS HAND-BUILT ON BOTH SIDES AND THIS UNIT DID NOT CROSS THAT
BOUNDARY.** But the two rows below are a **DERIVED** lane: the port's graph is BUILT BY
`compute_gradient` (not by hand) and CPython's twin is BUILT BY CALLING CPython's
`compute_gradient`, and the two are compared **NODE FOR NODE**:

```
pm_bw_sig   = BUFFER/1@s3 [STACK/1] BUFFER/1@s4 [STACK/1] BUFFER/1@s5 [STACK/1] CONST/0@i0:2 [] PERMUTE/1 [STACK/2] STACK/1 [CONST/0@i0:2] STACK/2 [BUFFER/1@s3 BUFFER/1@s4] STACK/2 [BUFFER/1@s5 STACK/2]
oracle_pm_bw_sig = (the same string, byte for byte)
```

**⇒ THE ORCHESTRATOR'S NEXT MOVE IS NAMED: REPLACE THE CORPUS's HAND-BUILT `bw` GRAPH
WITH A FIXTURE BUILT BY `compute_gradient` ON BOTH SIDES, AND COMPARE THE SIGNATURES
INSTEAD OF THE NODE COUNTS.** `.agents/slop/graphcmp.py`'s `g_bw` and
`.agents/slop/graphcmp.bend`'s `g_bw` are the two places, and **NEITHER IS MINE TO EDIT**.

---

## 4. THE MEASUREMENTS

### 4.1 THE GATE — 36 of 36 ROWS AGREE AGAINST CPYTHON, AND THE PRE-EXISTING 30 STILL AGREE

```
$ sh .agents/slop/backward4/run.sh check
=== check-only: ALL PROOFS CHECK  run rc=0  rows=138
=== THE GATE (a): this unit's pm_*/pm1_* rows against perm.rows -- CPython's own bytes
    rows expected: 36   PASS: 36   MISMATCH: 0   UNCHECKABLE: 0   MISSING: 0
    VERDICT: PASS
=== THE GATE (b): the prior art's walk_* rows against backward3/walk.rows
    rows expected: 16   PASS: 16   MISMATCH: 0   UNCHECKABLE: 0   MISSING: 0
    VERDICT: PASS
=== THE GATE (c): the prior art's gs_*/bw_* rows against backward2/rows.rows
    rows expected: 14   PASS: 14   MISMATCH: 0   UNCHECKABLE: 0   MISSING: 0
    VERDICT: PASS
=== VERDICT: pm-rows rc=0   walk-rows rc=0   gs/bw-rows rc=0
```

**⇒ 36 of 36 NEW ROWS PASS AGAINST CPYTHON'S OWN BYTES, AND THE 30 PRE-EXISTING GATED
ROWS ARE STILL PASS.**

### 4.2 NO PRE-EXISTING ROW MOVED — 0 of 102

```
$ sh .agents/slop/backward4/run.sh head
    HEAD's gradient.bend installed: 4477a826f04dc9d440bc04d63f884857f20d21d7227660b2828330bb0686e783
=== check-only: ALL PROOFS CHECK  run rc=0  rows=102
=== check-only: ALL PROOFS CHECK  run rc=0  rows=138
=== HEAD vs LIVE: rows head=102 live=138
    rows whose VALUE changed: 0 of 102
    gained: 36   of which NOT in this unit's row set: 0
--- rows HEAD has that LIVE does NOT (must be EMPTY):
VERDICT: PASS -- no pre-existing row moved
```

**⇒ OF HEAD's 102 ROWS: 0 CHANGED VALUE, 0 LOST, AND THE 36 GAINED ARE EXACTLY THIS
UNIT'S 36.** The prior art's measurement was *"83 OF 88 BYTE-IDENTICAL, 5 CHANGED"*;
this unit's is **0 of 102 changed**, because this unit only ADDED rules and rows.

### 4.3 THE CONTROLS — TWO CLASSES, NOT ONE

```
$ sh .agents/slop/backward4/run.sh ctl
=== THE CONTROLS (the prior art's ctl-rows.py, called BY PATH)
    (0) the UNPERTURBED expectations
    PASS  OK  (36 rows)
    (a) pm_rule_arg      wrong-but-non-empty -> MISMATCH     OK
    (b) pm_rule_arg      empty              -> UNCHECKABLE  OK
    ... (every one of the 36 rows, both perturbations) ...
CONTROLS: 36 rows x 2 perturbations + the clean run = 73 checks, failures: 0
```

**⇒ 73 CHECKS, 0 FAILURES.** For EVERY one of the 36 rows: (a) a WRONG BUT NON-EMPTY
expectation → `MISMATCH`, and EXACTLY THAT ROW is named (every other row stays `PASS`),
and (b) an EMPTY expectation → `UNCHECKABLE`, and EXACTLY THAT ROW is named. **⇒ TWO
CLASSES, AND THE ASSERTION IS ON THE CLASS, NOT MERELY ON "NOT PASS".**

**⇒ AND ONE ROW HAD TO BE CHANGED FOR THIS TO BE MEANINGFUL: `pm1_rule_arg`.** The P1
answer IS the ctx, whose arg is a PARAM and not a tuple, so there IS no order — and the
first version of that row printed the EMPTY STRING, which the gate called `UNCHECKABLE`
(RED). **⇒ "THERE IS NO ORDER HERE" IS A REAL, MEASURED VALUE AND IT NEEDS A SENTINEL,
OR THE GATE CANNOT TELL "THE ANSWER IS NOTHING" FROM "THE INSTRUMENT MEASURED NOTHING".
⇒ BOTH SIDES NOW PRINT THE WORD `none`.**

### 4.4 THE PLANTS — 36 of 36 ROWS ARE MOVED BY SOME MUTATION

```
$ sh .agents/slop/backward4/run.sh plants
    noargsort        moved  1 row(s): pm_rule_arg
    argsortbyindex   moved 14 row(s): pm_argsort_0_2_1 pm_argsort_1_0 pm_argsort_1_0_2 pm_argsort_1_2_0 pm_argsort_2_0_1 pm_argsort_2_1_0 pm_bw_distinct pm_bw_nodes pm_bw_sig pm_rule_arg pm_rule_is_ctx pm_rule_op pm_rule_tok pm_set_sig
    flagfalse        moved  8 row(s): pm1_bw_distinct pm1_bw_nodes pm1_bw_sig pm1_rule_arg pm1_rule_is_ctx pm1_rule_op pm1_rule_tok pm1_set_sig
    neverpermute     moved  8 row(s): pm_bw_distinct pm_bw_nodes pm_bw_sig pm_rule_arg pm_rule_is_ctx pm_rule_op pm_rule_tok pm_set_sig
    zerograds        moved 11 row(s): pm_bw_distinct pm_bw_nodes pm_bw_sig pm_grads_n pm_keys pm_rule_arg pm_rule_len pm_rule_op pm_rule_tok pm_set_sig pm_zero_n
    twograds         moved  1 row(s): pm1_rule_len
    nosrc            moved  6 row(s): pm_bw_distinct pm_bw_nodes pm_bw_sig pm_rule_op pm_rule_tok pm_set_sig
    emptytargets     moved  9 row(s): pm_bw_distinct pm_bw_nodes pm_bw_sig pm_grads_n pm_keys pm_set_n pm_set_sig pm_walk pm_walk_n
    targetsub        moved  7 row(s): pm_bw_distinct pm_bw_nodes pm_bw_sig pm_set_sig pm_walk pm_walk_n pm_zero_n
    collide          moved  1 row(s): pm_bw_sig
    emptyP1targets   moved  9 row(s): pm1_bw_distinct pm1_bw_nodes pm1_bw_sig pm1_grads_n pm1_keys pm1_set_n pm1_set_sig pm1_walk pm1_walk_n
    targetsubP1      moved  7 row(s): pm1_bw_distinct pm1_bw_nodes pm1_bw_sig pm1_set_sig pm1_walk pm1_walk_n pm1_zero_n
THE COVERAGE: 36 of 36 new row(s) are moved by some plant
    every new row is moved by at least one plant
PLANTS: 12 mutations, 0 VACUOUS/FAILED, 0 UNCOVERED row(s)
```

**⇒ 12 MUTATIONS, 0 VACUOUS, AND EVERY ONE OF THE 36 NEW ROWS IS MOVED BY AT LEAST ONE
PLANT.** Every mutation is applied to a COPY of the tree and is ASSERTED BY RE-READING
THE FILE; a mutation that did not land would be reported as VACUOUS, not as a verdict.

**⇒ THE TWO PLANTS THAT ANSWER THE BRIEF'S QUESTIONS DIRECTLY:**
* **`argsortbyindex`** — `helpers.bend`'s `argsort_u32` changed to sort by the INDEX
  instead of the VALUE — moves **all six `pm_argsort_*` rows** and four more.
  **⇒ THE BRIEF'S SUSPICION, PLANTED: IF THE PORT SORTED BY THE INDEX, EVERY ARGSORT ROW
  WOULD GO RED.**
* **`noargsort`** — `gr_21` copies the order instead of ARGSORTING it — moves
  `pm_rule_arg` (`2,0,1` → `1,2,0`). **⇒ THE RULE'S ORDER ROW HAS TEETH.**

**⇒ AND THE SWEEP FOUND A REAL DEFECT IN MY OWN FIRST VERSION:** the first six argsort
inputs were `(0,2,1) (1,2,0) (2,1,0) (0,1) (0,) (1,0)`, and the sweep reported
**34 of 36 covered, with `pm_argsort_0` and `pm_argsort_0_1` UNCOVERED** — because an
ALREADY-SORTED input has the same answer under a value-sort and under an index-sort.
**⇒ THE INPUTS WERE CHANGED TO SIX UNSORTED PERMUTATIONS, AND THE SWEEP NOW COVERS 36
of 36.** (And the counter in `plants.py` was split, because "1 VACUOUS/FAILED" was
really the coverage gap and the message was lying.)

### 4.5 THE CONTROL ON THE CONTROL — THE TRANSCRIPTION IS A WITNESS, NOT A TRANSCRIPT

```
$ sh .agents/slop/backward4/run.sh oracleplant
    oracleplant: the fixture's PERMUTE order (1,2,0) became (2,1,0)
    transcribed 36 oracle rows -> 36 port rows in .../perm-planted.rows
=== the EXPECTATIONS moved (the oracle moved, the port did NOT):
    < pm_rule_arg=2,0,1
    > pm_rule_arg=2,1,0
=== the PORT's rows did NOT move (this arm never touched it):
=== check-only: ALL PROOFS CHECK  run rc=0  rows=138
    the port's output is byte-identical to the base -- NOTHING MOVED
```

**⇒ PERTURBING THE ORACLE MOVED THE EXPECTATION AND THE PORT'S OUTPUT IS BYTE-IDENTICAL
TO THE BASE. A FILE THAT WERE A TRANSCRIPT OF THE PORT'S OUTPUT COULD NOT MOVE.**

### 4.6 THE DEPENDENTS STILL COMPILE

```
$ for f in tinybendygrad/mixin/op.bend tinybendygrad/tensor.bend tinybendygrad/schedule/indexing.bend \
           tinybendygrad/examples/test_pkl_imagenet.bend tinybendygrad/examples/train_resnet.bend \
           tinybendygrad/uop/symbolic.bend tinybendygrad/uop/spec.bend; do
    BEND_NO_TELEMETRY=1 ./bin/bend "$f" --check-only; done
ALL PROOFS CHECK   (x7)
```

**⇒ ALL SEVEN FILES THAT IMPORT `mixin/gradient.bend` COMPILE** (the list is from
`grep -rl "mixin/gradient" tinybendygrad/`, so it is the whole population and not a
hand list).

---

## 5. THE RULE THAT LANDED, AND ITS ONE NAMED DIVERGENCE

```bend
def gr_21_marg.of(a: O.Arg) -> List<&2, U32>:
  match a:
    case O.ATuple{ys}: ys
    case _: Nil{}

def gr_21_id.go(xs: List<&2, U32>, +i: U32, acc: Bool) -> Bool:
  match xs:
    case Nil{}: acc
    case h <> t: gr_21_id.go(t, U32.add(i, 1), Bool.and(acc, U32.is_eq(h, i)))

def gr_21_is_id(xs: List<&2, U32>) -> Bool: gr_21_id.go(xs, 0, True{})

def gr_21.build(+ar: O.Arena, +ctx: U32, inv: List<&2, U32>) -> GRes:
  +n = gnew(ar, O.OpsPERMUTE{}, [ctx], O.ATuple{inv})
  fired([O.Found.i(n)], O.Found.ar(n))

def gr_21.pick(is_id: Bool, +ar: O.Arena, +ctx: U32, inv: List<&2, U32>) -> GRes:
  match is_id:
    case True{}: fired([ctx], ar)
    case _: gr_21.build(ar, ctx, inv)
```

**THE THREE THINGS UPSTREAM'S `permute` DOES, AND WHAT THE PORT DOES WITH EACH:**

| upstream (`movement.py:214-231`) | the port | gated by |
|---|---|---|
| `_resolve_dim` — PURE INTEGER ARITHMETIC over `self.ndim`, **never calls `resolve`** | nothing to do | — |
| the IDENTITY EARLY-RETURN: `... if order_arg != tuple(range(self.ndim)) else self` | `case True{}: fired([ctx], ar)` — the answer IS `ctx`, no node built | `pm1_rule_is_ctx=1`, `pm1_rule_tok=BUFFER/1@s1 [STACK/1]` |
| the PERMUTE NODE: `self._mop(Ops.PERMUTE, arg=order_arg)` → `UOp(op, src=(self,), arg=arg)` (`ops.py:799-815`) | `gnew(ar, O.OpsPERMUTE{}, [ctx], O.ATuple{inv})` | `pm_rule_tok=PERMUTE/1 [STACK/2]`, `pm_rule_arg=2,0,1` |
| the VALIDITY RAISE: `if sorted(order_arg) != list(range(self.ndim)): raise RuntimeError(...)` | **NOT REPRODUCED** — see below | — |

**⇒ THE ONE NAMED DIVERGENCE, AND IT IS BOUNDED BY A MEASUREMENT AND NOT BY AN
ARGUMENT.** upstream's check reads `ctx.ndim`, and **the port has no `ndim`**: `ops.bend`
has no `as_shape` and no `shape`, so a node's dimension count is not available. The port
uses `len(ret.marg)` — the length of the ATuple — which IS `ret.ndim` by upstream's own
construction (`permute()` validates `sorted(order_arg) == list(range(self.ndim))`, so the
arg's length IS the ndim), and `ctx.ndim == ret.ndim` by upstream's own shaped-edge reduce
(`gradient.py:131-133` reshapes the gradient into the node's shape). **⇒ UPSTREAM'S
`compute_gradient` GUARANTEES `ctx.ndim == len(ret.marg)`, SO THE RAISE IS UNREACHABLE
FROM `compute_gradient` — AND THE PORT'S NUMBER IS THE ONE IT CAN READ.**
**⇒ THE RAISE IS REACHABLE OUTSIDE `compute_gradient` (by calling `permute()` directly
with a bad order), AND THE PORT DOES NOT REPRODUCE THAT PATH. THAT IS THE DIVERGENCE, AND
IT IS NAMED HERE RATHER THAN HIDDEN.**

---

## 6. WHAT I DID **NOT** CLOSE, SPECIFICALLY AND NAMED

### 6.1 `gr_17` (RESHAPE) — **LANDABLE WITHOUT `resolve`, AND EVERY SUBSYSTEM IT NEEDS IS ALREADY IN THE TREE**

**MEASURED** (`.agents/slop/backward4/probe-gr17.py`, which PATCHES upstream's `resolve`
and COUNTS its calls AND WHETHER ITS ARGUMENT IS A `UOp`):

```
=== gr_17: RESHAPE, on a STATIC shape
    upstream's own reshape: op=RESHAPE nsrc=2 arg=None shape=(2, 3)
    grads: RESHAPE/2->RESHAPE/2 BUFFER/1->RESHAPE/2
    resolve calls: 1   of which SYMBOLIC (a UOp argument): 0   ['bool']
    the gradient of BUFFER/1 is RESHAPE/2 arg=None shape=(6,)
```

**=> `resolve` WAS CALLED ONCE AND ITS ARGUMENT WAS A `bool` — ZERO SYMBOLIC RESOLUTIONS.
=> `gr_17` DOES NOT NEED A SYMBOLIC SOLVER.** Upstream's rule is
`(ctx.reshape(ret.src[0].shape), None)` (`gradient.py:85`) and `ctx.reshape` is
`movement.py:164-179`, whose needs are `self.shape`, `prod`, and a shape equality — **and
`prod` OF A STATIC SHAPE IS INTEGER MULTIPLICATION.**

**=> AND HERE IS THE PART THAT CHANGES THE DELIVERABLE: EVERY SUBSYSTEM `gr_17` NEEDS IS
ALREADY IN THE TREE. MEASURED, ONE ROW PER NEED:**

| what `gr_17` needs | does the port have it? | where |
|---|---|---|
| a node's SHAPE | **YES** | `O.UOp.shape(ar, tb, i)` / `F.fold.shape` — `tinybendygrad/uop/fold.bend:4764-4768` — the FOLD's shape, `Maybe<&2, List<&2, O.Sint>>` |
| the shape EQUALITY | **YES** | `F.eq_sints` — `tinybendygrad/uop/fold.bend:484` |
| "is this dimension 1" | **YES** | `F.bcast_dim.is_uop_or_ne_1` — `tinybendygrad/uop/fold.bend:341` |
| `prod` of a static shape | **YES** | `H.prod_u32` — `tinybendygrad/helpers.bend:485` |
| the shape NODE (`shape_to_shape_arg`) | **YES** | `O.shape_to_shape_arg` — `tinybendygrad/uop/ops.bend:3038-3043` — it takes `Maybe<&2, U32>` |
| the RESHAPE node builder | **YES** | `gnew` — `tinybendygrad/mixin/gradient.bend:157` |
| the RESHAPE's identity arm (`ret.shape == self.shape`) | **YES** | `F.eq_sints` over the two shapes |

**=> => `gr_17` IS LANDABLE WITH NO NEW SUBSYSTEM AT ALL. THE DELTA IS FOUR DEFS: (a) a
`List<&2, O.Sint>` -> `List<&2, U32>` projection (`SInt.u`/`SInt.i` exist,
`ops.bend:1454-1459`), (b) the source's shape read through `O.UOp.shape`, (c) the
identity test, (d) the two-slot answer `fired([node, 0], ar)` — slot 1 is upstream's
`None`, a HOLE (`gradient.py:130`'s `if v is None: continue`).**

**=> WHY `gr_21`'s IDENTITY TEST IS A LOCAL FOLD AND NOT `mixin/op.bend`'s: THE IMPORT
CYCLE.** `mixin/op.bend` HAS `mo_permute` (`tinybendygrad/mixin/op.bend:706-717`) — which
IS upstream's `permute`, identity test and all (`O.eq_u32(ys, mo_range(mo_ndim(...)))`)
— and `mo_reshape` (`:701-705`), which IS upstream's `reshape`. **=> BUT
`mixin/op.bend` IMPORTS `tensor.bend` (`:256`), AND `tensor.bend` IMPORTS
`mixin/gradient.bend` (`tensor.bend:7`), SO `mixin/gradient.bend` CANNOT IMPORT
`mixin/op.bend` — THE CYCLE WOULD CLOSE.** **=> THE PORT HAS TWO LAYERS — A TENSOR-LEVEL
`permute`/`reshape` IN `mixin/op.bend` AND A UOP-LEVEL ONE IN `mixin/gradient.bend` — AND
THIS UNIT'S `gr_21` IS THE UOP-LEVEL HALF.** (The two layers use DIFFERENT `Arg` types on
purpose: the UOp arena's `O.ATuple{ys}` (`ops.bend:1237`) and the Tensor arena's
`T.AOrder{ys}` (`tensor.bend:1611`). **=> THAT IS NOT A DIVERGENCE, IT IS TWO ARENAS.**)

**=> THE PORT REPRODUCES THE RESHAPE ARITY ON PURPOSE AND THIS UNIT DID NOT TOUCH IT**
(the brief says so). **=> AND THE MEASUREMENT SAYS THE PORT'S COMMENT AT
`gradient.bend:627-639` SHOULD BE NARROWED: the "2 gradients for a 1-src RESHAPE"
mismatch is REAL, but it is REAL FOR A **HAND-BUILT** 1-src RESHAPE — upstream's OWN
`reshape` builds a RESHAPE with **TWO** srcs (`src[0]` the value and `src[1]` the shape
node, MEASURED), and on upstream's own reshape the arity MATCHES (2 answers, 2 srcs).
=> THE PORT'S ARITY BEHAVIOUR IS CORRECT AS IT STANDS; ONLY THE COMMENT'S SCOPE IS
TOO WIDE.**

### 6.2 `gr_14` (REDUCE) — **THE REAL `resolve` WALL IS NOT WHERE THE PORT'S COMMENT SAYS, AND `gr_14` IS ALSO LANDABLE**

**MEASURED** (same instrument):

```
=== gr_14: REDUCE, on a STATIC shape
    the REDUCE node: op=REDUCE nsrc=1 arg=(Ops.ADD, 1) shape=()
    grads: REDUCE/1->BUFFER/1 BUFFER/1->BUFFER/1
    resolve calls: 0   of which SYMBOLIC (a UOp argument): 0   []
    the gradient of REDUCE/1 is BUFFER/1 arg=ParamArg(1, dtypes.float32) shape=(6,)
```

**=> `resolve` WAS CALLED **ZERO** TIMES.** Upstream's `reduce_gradient`
(`gradient.py:8-18`) has three arms, and the ADD arm is
`ctx._broadcast_to(ret.src[0].shape)` — and `_broadcast_to` (`movement.py:128-130`)
answers `self` ITSELF when `self.shape == new_shape`. **=> ON A STATIC FIXTURE WHOSE
SHAPES ALREADY AGREE, `gr_14`'s ADD ARM IS THE IDENTITY AND IT CALLS NOTHING.**

**=> SO THE PORT'S COMMENT AT `gradient.bend:603-611` IS RIGHT ABOUT THE DEPENDENCY AND
WRONG ABOUT ITS KIND.** It says `_rop`'s `resolve(self.shape[x]!=1)` and `_broadcast_to`'s
`broadcast_axes` are "BOTH SYMBOLIC" — **=> THEY ARE SYMBOLIC ONLY WHEN THE SHAPES
DIFFER OR A DIMENSION IS 1; ON A STATIC FIXTURE WHERE THEY AGREE, NEITHER IS REACHED AND
`resolve` IS NEVER CALLED AT ALL.**

**=> AND `gr_14`'s "is this dimension 1" QUESTION IS ALREADY ANSWERED IN THE TREE:
`F.bcast_dim.is_uop_or_ne_1` (`fold.bend:341`) IS EXACTLY THAT PREDICATE, and
`tensor.bend:1799` USES IT for `tn_rop`. **=> THE PORT'S COMMENT THAT `Sint` "has an
equality but NO addition and NO `as_shape`" IS TRUE ABOUT `as_shape` AND ABOUT ADDITION
— BUT THE `Sint` EQUALITY IT ALREADY HAS (`F.eq_sints`) IS THE SAME COMPARISON, AND
`bcast_dim.is_uop_or_ne_1` IS THE "IS THIS DIM 1" TEST THAT `resolve(self.shape[x]!=1)`
IS.**

**=> => `gr_14`'s ADD ARM IS LANDABLE ON A STATIC FIXTURE, AND SO IS `gr_17`, AND NEITHER
NEEDS A SYMBOLIC SOLVER. WHAT THEY DO NEED IS THE SAME THING: A STATIC SHAPE READ, WHICH
IS `O.UOp.shape`.** **=> THE PORT'S OWN `gr_14` COMMENT NAMES A `resolve` WALL THAT THE
MEASUREMENT SHOWS IS NOT REACHED ON THE STATIC FIXTURES THE PORT CAN BUILD — AND THAT IS
THE FINDING, NAMED.**

**=> AND THE MAX AND MUL ARMS (`gradient.py:12` and `:18`) REMAIN HARDER, AND FOR A
REASON THAT IS NOT `resolve` EITHER: they build a `REDUCE` node whose arg is
`(op, len(reduce_axis))` (`ops.py:641`), and `len(reduce_axis)` COUNTS THE AXES WHOSE
DIMENSION IS NOT 1 — a count over `bcast_dim.is_uop_or_ne_1`, WHICH EXISTS, BUT ALSO A
`permute` AND A `reshape` AROUND IT (`ops.py:638-642`).** **=> SO THE MAX/MUL ARMS NEED
`gr_21`'s OWN PERMUTE — WHICH THIS UNIT LANDED — AND THAT IS A SECOND ARGUMENT FOR
LANDING `gr_21` FIRST.**

### 6.3 THE BOUNDARY THIS UNIT DID NOT CROSS

**THE CORPUS's `bw` GRAPH IS HAND-BUILT ON BOTH SIDES** —
`.agents/slop/graphcmp.bend:1471`'s `g_bw()` builds 32 nodes by hand in the port's
spelling and `.agents/slop/graphcmp.py`'s `g_bw` builds the same 32 by hand in CPython's
spelling — **⇒ MAKING IT DERIVED MEANS TOUCHING BOTH, AND NEITHER IS MINE.** **⇒ THE
DERIVATION IS A NAMED NEXT MOVE FOR THE ORCHESTRATOR, NOT FOR THIS UNIT**, and §3.4 hands
over the derived lane it would plug in: a graph BUILT BY `compute_gradient` on both sides
and compared NODE FOR NODE.

### 6.4 THE 72 `fix` ROWS ARE STILL CHANGE-DETECTORS

**THE PORT's 102 ROWS INCLUDE 72 `fix`-FIXTURE ROWS WHOSE ORACLE
(`.agents/slop/notes/grad_oracle.py`) IS GONE, SO THOSE 72 ROWS ARE CHANGE-DETECTORS AND
NOT CPYTHON-GATED.** **THIS UNIT DID NOT FIX THAT AND DID NOT MAKE IT WORSE** (0 of 102
moved). **⇒ A WAY TO FIX IT, WHICH THIS UNIT DID NOT TAKE:** the oracle for the `fix`
rows is upstream's OWN `pm_gradient.rewrite` on the port's OWN `fix` fixture, and the
port's `fix()` fixture is a LIST OF NODES WITH ONE-HOP ANSWERS — so an oracle that
rebuilds the same nodes upstream-side and prints `pm_gradient.rewrite(node, ctx=…)`'s
answer would gate all 72. **⇒ THAT IS A NAMED NEXT MOVE AND IT IS THE SAME
`oracle-pm.py` MECHANISM, JUST OVER MORE NODES.**

---

### 6.5 THE NEXT MOVES, NAMED AND ORDERED

1. **`gr_17` (RESHAPE) — FOUR DEFS AND A FIXTURE.** The delta is §6.1's four defs: a
   `List<&2, O.Sint>` -> `List<&2, U32>` projection, the source's shape read through
   `O.UOp.shape`, the identity test (`F.eq_sints`), and the two-slot answer
   `fired([node, 0], ar)`. **⇒ THE FIXTURE IS THE OBVIOUS ONE AND IT IS UPSTREAM'S OWN
   `reshape`: `buf = BUFFER(STACK(CONST 6))`, `r = buf.reshape((2,3))` (TWO srcs), the
   root grad `g = gbuf.reshape((2,3))`, and the TARGET `buf` — so the walk is `[r]` and
   the answer is `RESHAPE(g, (6,))`. THE ORACLE IS `probe-gr17.py`'s fixture, which
   ALREADY ANSWERS IT.**
2. **`gr_14`'s ADD ARM — ONE COMPARISON.** `ctx._broadcast_to(ret.src[0].shape)` is
   `ctx` ITSELF when the two shapes agree, so the arm is the identity on a static
   fixture whose shapes agree. **⇒ THE FIXTURE IS THE SAME SHAPE OF THING: a REDUCE over
   a 1-D leaf with a 1-D root grad.**
3. **`gr_14`'s MAX AND MUL ARMS — THEY NEED `gr_21`'s OWN PERMUTE.** `ops.py:638-642`
   builds `self.permute(perm)` around the REDUCE, **⇒ SO `gr_21` IS A PREREQUISITE OF
   `gr_14`'s MAX/MUL ARMS, WHICH IS A SECOND ARGUMENT FOR HAVING LANDED `gr_21` FIRST.**
4. **THE CORPUS's DERIVED `bw` LANE.** §3.4 hands over the derived lane; the two files
   to change are `.agents/slop/graphcmp.py` and `.agents/slop/graphcmp.bend`, and NEITHER
   IS MINE.

## 7. THE FILES

| file | what |
|---|---|
| `tinybendygrad/mixin/gradient.bend` | **THE ONLY `.bend` FILE TOUCHED.** `gr_21` landed (the margin read, the argsort, the identity early-return, the PERMUTE node), the `Pm`/`Pm1` fixtures, the 36 rows, and the argsort rows. +398/−6. |
| `.agents/slop/backward4/oracle-pm.py` | **THE ORACLE** — upstream's own `compute_gradient` on the 3-D and 1-D fixtures, and upstream's own `argsort` on six inputs. |
| `.agents/slop/backward4/probe.py` | the node-shape probe that settled "a 2-D node needs no RESHAPE". |
| `.agents/slop/backward4/probe-gr17.py` | **THE `resolve` INSTRUMENT** — patches upstream's `resolve`, counts the calls, and classifies each argument as `UOp` (symbolic) or `bool` (static). |
| `.agents/slop/backward4/mkrows.py` / `mkrows.sh` | **THE TRANSCRIPTION** — one rule (strip the `oracle_` prefix), no exceptions, 36 rows asserted. |
| `.agents/slop/backward4/perm.rows` | **THE EXPECTATIONS — 36 rows, CPython's own bytes.** |
| `.agents/slop/backward4/run.sh` | the harness: `base`, `check`, `head`, `ctl`, `oracleplant`, `plants`. |
| `.agents/slop/backward4/plants.py` | **THE MUTATION SWEEP** and the COVERAGE assertion. |
| `.agents/slop/backward4/transcript-*.out` | the transcripts of §4. |

**⇒ NOTHING COMMITTED. NO MUTATING GIT COMMAND. ONE BEND PROCESS AT A TIME (the plant
sweep runs them SEQUENTIALLY, one child per mutation, and never in the background).**
