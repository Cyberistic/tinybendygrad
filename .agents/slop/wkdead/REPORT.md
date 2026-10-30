# WHY THE `uop/weak.bend` -> `mixin/dtype.bend` ROUTE LOOKED DEAD, AND WHAT IT WAS

MEASURED 2026-10-30 on the tree at `HEAD` `8899ed1ad` plus this unit's commit.
Every number here was produced by running the instrument named beside it.

---

## 0. THE ANSWER IN ONE PARAGRAPH

**THE ROUTE WAS NOT DEAD. THE CENSUS WAS MEASURING THE WRONG POPULATION.**

`mixin/dtype.bend`'s `commit_dtype` (and the five readers above it) are reached by
`gates/wk-cd-gate.py` and `gates/wk-eval-gate.py` -- **A GATE IS A CALLER**. The census
that declared the route dead walked `tinybendygrad/` and found no call site there, which
is a true reading of a narrower population than the one the report claimed.

**ONE OF THE FIVE WAS GENUINELY UNGATED** -- `wk_is_virtual` -- and its stated reason
was **A CLAIM THAT WAS FALSE**: `uop/ops.bend:5345` said "no def in the port sets
`ParamArg`'s device field, so EVERY node is virtual and the reader has no negative
witness". MEASURED: `renderer/__init__.bend:450` builds a `ParamArg` with
`device = Some{S.D1{0}}`, and `fold.bend`'s `device_of.param` reads
`O.ParamArg.device(pa)`. **The negative witness existed all along.**

---

## 1. WHAT THE BRIEF SAID, AND WHICH HALF OF IT WAS TRUE

The brief and `.agents/slop/corpuscoverage/REPORT.md` §3(b) said:

> `tinybendygrad/mixin/dtype.bend` (177 defs) has a route in `tinybendygrad/uop/weak.bend`
> -- the `wk_eval_*` / `wk_is_virtual` / `wk_commit_dtype` functions -- and **that route
> has NO CALLERS ANYWHERE IN THE PORT.**

### 1.1 THE FIVE DEFS ARE IN `uop/weak.bend`, NOT `mixin/dtype.bend`

MEASURED (`grep -rn "^def wk_eval_int" tinybendygrad/ --include="*.bend"`):

| def | file:line |
|---|---|
| `wk_eval_int` | `tinybendygrad/uop/weak.bend:229` |
| `wk_eval_float` | `tinybendygrad/uop/weak.bend:237` |
| `wk_eval_bool` | `tinybendygrad/uop/weak.bend:245` |
| `wk_is_virtual` | `tinybendygrad/uop/weak.bend:268` |
| `wk_commit_dtype` | `tinybendygrad/uop/weak.bend:297` |

**THE REPORT MISATTRIBUTED THE FILE.** That matters because the report's conclusion is
about `mixin/dtype.bend`, and the five defs are in `uop/weak.bend`.

### 1.2 "NO CALLERS IN THE PORT" IS TRUE. "NO CALLERS ANYWHERE" IS FALSE.

MEASURED, the call sites of each of the five, over the WHOLE tree:

| def | call site |
|---|---|
| `wk_commit_dtype` | `gates/wk-cd.bend:48` |
| `wk_eval_int` | `gates/wk-eval.bend:80, 104` |
| `wk_eval_float` | `gates/wk-eval.bend:86, 118` |
| `wk_eval_bool` | `gates/wk-eval.bend:92, 111` |
| `wk_is_virtual` | **NONE** |

**SO FOUR OF THE FIVE ARE GATED AND LIVE, AND ONE IS NOT.**

### 1.3 AND TWO OF THE GATES DID NOT RUN

`gates/wk-cd-gate.py` PASSED (7 rows, 3 lanes, 0 divergences). `gates/wk-eval-gate.py`
**REFUSED** (rc=3) -- and the tree ALREADY KNEW:

```
gates/oracleblind.rows:108
  gates/wk-eval-oracle.py  GATE-DECLARED  CANNOT BE PERTURBED  ...
  rc=1: IndexError: tuple index out of range
```

**SO A GATE THAT REFUSES IS A GATE THAT MEASURES NOTHING, AND THIS ONE HAD BEEN
REFUSING SINCE THE RE-VENDOR.** `gates/help-census.rows:224` records it PASSING at
`951.0 s / 42.46 MB` -- a dated reading from BEFORE `77e6c2bec`
("re-vendor tinygrad/ to upstream 5c2bf39d6 (2026-10-20) -- 299 commits").

---

## 2. WHY `wk-eval-gate` REFUSED -- MEASURED, AND IT IS THE ORACLE'S FIXTURE

`gates/wk-eval-oracle.py:50` built its PARAM by hand:

```python
return UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtype, vmin_vmax=(lo, hi)))
```

**`src=()` IS A MALFORMED PARAM.** Upstream's `UOp.param` (`ops.py:1218`) ALWAYS gives a
PARAM at least one src (`src=(shape_to_shape_arg(...),)`), and `_shape` (`ops.py:359`)
reads `self.src[0].as_shape` **unguarded**.

MEASURED, the exact path:

```
ops.py:507   vmin, vmax = (simple_self:=self.simplify())._min_max
ops.py:501   return graph_rewrite(self, symbolic, name="simplify")
symbolic.py:275  lambda x: x.const_like(x.vmin) if ... x.vmin == x.vmax else None
ops.py:583   ret._mop(Ops.EXPAND, arg=self._shape) if self._shape and ...
ops.py:359   assert len(self.src[0].as_shape) <= 1
             IndexError: tuple index out of range
```

**THE PORT'S LANE NEVER SAW IT**, because the port has no `simplify`; only the CPython
lane read the shape.

MEASURED, the same fixture built the way upstream builds it:

```
UOp.param(0, dtypes.int32, vmin_vmax=(5,5))  ->  src=(UOp(Ops.STACK,...),)   int(u) = 5
```

**⇒ THE FIX IS ONE LINE IN THE ORACLE, AND THE GATE'S 22 ROWS ARE THE PORT'S OWN.**

---

## 3. THE ONE THAT WAS GENUINELY UNGATED: `wk_is_virtual`

`uop/ops.bend:5344` (BEFORE this unit's commit) said:

> PORTED BUT UNGATED, AND THE REASON IS A FIXTURE, NOT A DEF. ... `fold.bend`'s
> `mw_pa` hard-codes `ParamArg`'s device field to `None{}` and **no def in the port sets
> it**, so EVERY node is virtual and the reader has no negative witness. MEASURED: both
> candidate rows came out `True`, and two rows that are always `True` cannot fail.

### 3.1 THE CLAIM IS FALSE, AND THE FIXTURE IS NOT `mw_pa`

MEASURED: `renderer/__init__.bend:450`

```bend
def pa_g(slot: U32, dt: S.Dt) -> O.ParamArg:
  O.ParamArg{slot, dt, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}
```

**THE DEVICE FIELD (field 7 of `ParamArg`) IS `Some{S.D1{0}}`.** And
`fold.bend:2285`:

```bend
def device_of.param(arg: O.Arg) -> Maybe<&2, S.Dev>:
  match arg:
    case O.AParam{pa}: O.ParamArg.device(pa)
```

**⇒ A NODE THAT CARRIES A `Dev` WAS REACHABLE ALL ALONG, AND THE CLAIM WAS NEVER TRUE.**

### 3.2 THE GATE, AND IT IS A CROSS OF TWO INDEPENDENT QUESTIONS

`ops.py:902` is `return self.device is None or self.dtype in dtypes.weaks`.

| | device PRESENT | device ABSENT |
|---|---|---|
| **strong dtype** | `False` | `True` |
| **weak dtype** | `True` | `True` |

The two `True` cells on the WEAK row are the point: a reader that only asked the DEVICE
question answers `False` for a weak node that carries a device, and a reader that only
asked the DTYPE question answers `False` for a strong node without one. **Only the
disjunction answers all four, and only the disjunction is `ops.py:902`.**

`gates/wk-isvirt-gate.py` -- 5 rows, 3 lanes (CPython, bend interpreted, bend compiled):

```
iv_dev_strong=False     iv_dev_weakint=True     iv_nodev_strong=True
iv_nodev_weakint=True   iv_dev_single=False
```

**BOTH LANES AGREE, 5 of 5, 0 DIVERGENCES.**

---

## 4. THE MUTATION TABLE, AND EVERY ENTRY WAS RUN

A gate whose mutations move NOTHING is a label. All of these were applied to the port,
the gate was re-run, and the port was restored (byte-identical to `HEAD`).

| # | mutation | gate verdict | rows that moved (MEASURED) |
|---|---|---|---|
| 1 | `wk_is_virtual` drops the device half | **rc=1 FAIL** | `iv_nodev_strong` (1 of 5) |
| 2 | `wk_is_virtual` drops the dtype half | **rc=1 FAIL** | `iv_dev_weakint` (1 of 5) |
| 3 | `wk_is_virtual` returns the AND of the halves | **rc=1 FAIL** | `iv_dev_weakint`, `iv_nodev_strong` (2 of 5) |

`gates/wk-eval-gate.py`, same discipline:

| # | mutation | gate verdict | rows that moved (MEASURED) |
|---|---|---|---|
| A | the ORACLE's malformed src-less PARAM is put back | **rc=3 REFUSED** | the gate measures NOTHING |
| B | the PORT's `wk_same` answers `True{}` always | **rc=1 FAIL** | `int_on_range_val` (`none` -> `0:1`) |

**⇒ BOTH DIRECTIONS ARE FALSIFIABLE: A BROKEN ORACLE STOPS THE GATE, AND A BROKEN PORT
STOPS IT TOO.**

---

## 5. THE VERDICTS, BEFORE AND AFTER

| gate | BEFORE | AFTER |
|---|---|---|
| `gates/wk-cd-gate.py` | rc=0, 7 rows, 3 lanes, 0 divergences | rc=0, unchanged |
| `gates/wk-eval-gate.py` | **rc=3 REFUSED** (measured nothing) | **rc=0, 22 rows, 3 lanes, 0 divergences** |
| `gates/wk-isvirt-gate.py` | **DID NOT EXIST** | **rc=0, 5 rows, 3 lanes, 0 divergences** |

And the substrate: `bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --check-only` reads
**`ALL PROOFS CHECK`**, `WITHIN-LIMITS`.

---

## 6. WHAT A READER SHOULD TAKE FROM THIS

1. **A GATE IS A CALLER.** A reachability census that walks the PORT ALONE will call a
   gated reader unreachable. **THE POPULATION WAS THE BUG**, and the census is the
   instrument that has to be corrected -- not the port's code.
2. **A GATE THAT REFUSES IS A GATE THAT MEASURES NOTHING**, and this one had been
   refusing since the re-vendor. `gates/oracleblind.rows:108` HAD THE CRASH RECORDED
   since the day it was written -- the tree knew and the gate was still cited as passing.
3. **A CLAIM THAT NO DEF SETS A FIELD IS A CLAIM ABOUT A SEARCH, NOT ABOUT THE TREE.**
   `uop/ops.bend:5345` was false on the day it was written: `renderer/__init__.bend:450`
   had set the field all along. **THE STALE REASON WAS THE WALL**, and the fixture did
   not have to change -- only the reader of the claim.
4. **THE PORT'S OWN FIXTURE DOES NOT HAVE TO MATCH UPSTREAM'S BUILDER, BUT THE ORACLE'S
   DOES.** The port's PARAM has no src and the port has no `simplify`; upstream's PARAM
   always has one and upstream's `_shape` reads `src[0]` unguarded. **A HAND-BUILT
   FIXTURE IN AN ORACLE IS A CLAIM ABOUT UPSTREAM'S INVARIANTS**, and this one was wrong.
5. **THE REPORT NAMED THE RIGHT WALL AND THE WRONG FILE.** `mixin/dtype.bend`'s
   `commit_dtype` IS live (`mixin/creation.bend:451`, `mixin/op.bend:427`,
   `nn/item.bend:241`), but the FIVE READERS THE REPORT NAMED ARE IN `uop/weak.bend`.

---

## 7. WHAT WAS NOT CHANGED, AND WHY

- **`tinybendygrad/mixin/dtype.bend` was NOT deleted and `uop/weak.bend`'s route was NOT
  removed.** Four of the five readers are gated and live; the fifth is now gated too.
- **`tinybendygrad/uop/ops.bend` is a SHARED PATH** -- another unit was editing it
  (adding `renderer/estimates.bend`) while this unit worked. This unit's change to it is
  a COMMENT BLOCK (the corrected `is_virtual` marker) and it is left in the working tree
  for that unit's commit, not committed here.
- **NO LAW, PROOF, GRAPH OR GATE ROW WAS WEAKENED OR DELETED.** The `wk-eval` gate's
  divergence count went from "REFUSED" to "0 divergences", and the `wk-isvirt` gate is
  new with 5 rows.
