# `nn/argmax.bend` -- THE GRAPH-LEVEL `argmax` IS BUILT, AND Q4's REFUSAL WAS TWO BUGS IN `mixin/rand.bend`

MEASURED 2026-10-23T00:41Z, RE-TAKEN 2026-10-23T00:44Z AFTER THE LAST EDIT.
**EVERY ROW IN THIS REPORT WAS PRODUCED BY A `./bin/bend` RUN AT THAT HEAD.**

* **HEAD measured: `8dde14ef7460f4cf9d5c9ef3d3aee23601bd428b`** ("the project is on
  Bend v2.0.38, and every pin that names the compiler moved with it", 2026-10-23
  03:33:22 +0300).
* **The tree MOVED under this session.** The first reading of HEAD, before any
  measurement, was `98b17949dd78a3a773c7e40ac079267739faaa28`. Every number below was
  RE-TAKEN at `8dde14ef` and the two readings AGREE: the other unit's commit touched
  `.agents/TODO.md`, `.agents/TOOLS.md`, `checks/bend-health.py`, `checks/bend-health.rows`,
  `checks/differ.py`, `checks/gate_norm.py`, `gates/pin-cite-gate.py`,
  `gates/specfold-gate.py`, `gates/specfold-oracle.py`, `gates/specfold.bend`,
  `tinybendygrad/nn/item.bend`, `tinybendygrad/runtime/support/autogen.bend`,
  `tinybendygrad/uop/spec.bend`, `tools/get-bend.sh` -- **NONE OF WHICH IS A FILE THIS
  RESULT DEPENDS ON** (`uop/fold.bend`, `mixin/op.bend`, `mixin/movement.bend`,
  `mixin/creation.bend`, `mixin/elementwise.bend`, `nn/layers.bend` are all untouched by
  that commit).
* **THE POPULATION DID NOT MOVE:** `mixin/rand.bend` prints **55 rows before and 55
  rows after**, and the diff names **EXACTLY TWELVE** changed rows -- `arange3_g`,
  `fold_np`, `arange5_g`, `fold5_np`, `tfb3_g`, `bits6_g`, `btr6_g`, `rand23_g`,
  `rand23nc_g`, `ctrl_rand_g`, `rand_like23_g`, `ctrl_arange3_g`. **NO `ref_*` ROW AND NO
  `st_*_v` ROW MOVED.**
* **NOTHING WAS COMMITTED.** `tinybendygrad/nn/argmax.bend` and `tinybendygrad/mixin/rand.bend`
  are MODIFIED and UNCOMMITTED; `.agents/slop/nnargmax2/` is UNTRACKED.
* The artifacts: `probe.bend` + `probe.out` + `probe.err` (the capability probe),
  `argmax.out` + `argmax.err` (the rows), `rows.rows` (TAB-separated name/got/want),
  `control.out` (the perturbed run), `rand_before.out` + `rand_after.out` (the
  before/after of `mixin/rand.bend`'s own rows), `oracle_arange.py` +
  `oracle_argmax.py` (the CPython lanes).

---

## 1. WHAT THE GRAPH-LEVEL `argmax` NEEDS THAT THE LIST FORM DOES NOT HAVE

Upstream's `Tensor.argmax` (`tinygrad/mixin/op.py:863-888`) is four lines:

```
m   = self.eq(self.max(axis=axis, keepdim=True))                                    # op.py:886
idx = m * type(self).arange(self.shape[axis], 0, -1).reshape(...)                   # op.py:887
return (self.shape[axis] - idx.max(axis=axis, keepdim=keepdim)).cast(dtypes.int32)  # op.py:888
```

**THE LIST FORM (`nn_argmax`) IS THE SAME FORMULA EVALUATED ON THE VALUES.** It has an
ANSWER -- and the six rows are upstream's answers, re-checked against CPython in
`.venv`: 0 disagreements of 6.

**THE GRAPH FORM (`nn_argmax_g`) IS THE SAME RECIPE AS A UOP GRAPH, AND WHAT IT NEEDS
THAT THE LIST FORM DOES NOT HAVE IS EXACTLY ONE THING: A NODE WHOSE SHAPE IS `[n]`.**
Not a value -- a SHAPE. Concretely, three things the list form never asks for:

1. **`arange(n, 0, -1)` AS A GRAPH.** The list form carries the position `j` in an
   accumulator (`nn_argmax.best`, `tinybendygrad/nn/argmax.bend:83-89`) and so never
   needs the counter tensor at all; the graph form needs the tensor because
   `m * arange` IS A NODE (`Ops.MUL`). Upstream's `arange` is `tinygrad/mixin/op.py:166-195`
   and its `arange(n, 0, -1)` arm is a `full` + a `_cumalu` + an `ADD` + a `cast`.
2. **THE SHAPE OF THAT NODE.** `idx = m * arange` is a BROADCAST: `m` has the input's
   shape and `arange` has `[n]`, and the graph has to know that to be a graph at all.
   The port's fold answers the shape of a node from the node's own shape rules
   (`tinybendygrad/uop/fold.bend:2610`, `dt_shape`), so a node whose shape cannot be
   derived is a node the whole graph cannot be reasoned about.
3. **THE SHAPE OF THE RESULT.** `idx.max(axis=axis, keepdim=keepdim)` reduces an axis, and
   the port's `nn_reduce` (`tinybendygrad/nn/layers.bend:259-264`) READS THE INPUT'S
   SHAPE to decide `reduce_axis` (`ops.py:633`'s `resolve(self.shape[x] != 1)`). A
   0-dim `idx` and a 4-element `idx` are indistinguishable to a reducer that cannot
   read shapes, and the reducer's answer decides which axis is reduced.

**⇒ THE ONE THING THAT WAS MISSING WAS #2 AND #3, AND IT WAS MISSING BECAUSE THE
FOLD REFUSED TO READ THE `arange`'S SHAPE. THAT IS Q4, AND Q4's CAUSE WAS FOUND.**

---

## 2. Q4's DIAGNOSIS -- WHICH LAYER REFUSED, AND WHY

### 2a. THE OLD PROBE'S "EMPTY" WAS THREE DIFFERENT THINGS

`.agents/slop/nnargmax/probe.bend` (2026-10-22) read **EMPTY** on both readers for the
`arange` root and concluded "the port cannot produce an index vector along the axis".
**THAT READING WAS NOT WRONG BUT IT WAS NOT A DIAGNOSIS, AND THE REASON IS NAMED:**

* `tinybendygrad/mixin/op.bend:271-282` -- `mo_dims` answers `List<&2, O.Sint>` and
  answers **`Nil{}` for THREE DIFFERENT THINGS**: a node the fold cannot resolve
  (`fold.shape`'s outer `Maybe` is `None`), a node with NO shape (the inner `Maybe` is
  `None`), **and a node whose shape IS the empty list -- A 0-dim SHAPE**. Upstream
  agrees the CONST is 0-dim (`tinygrad/uop/ops.py:351-352`, `case Ops.CONST: return ()`)
  and the port agrees (`tinybendygrad/uop/fold.bend:2219-2220`, `const_ds` ->
  `dt_of(dt, Some{Nil{}})`).
* `tinybendygrad/nn/layers.bend:84-90` -- `nn_u32` maps `Nil{}` BACK to `Some{[]}`, so
  `nn_shape` cannot tell a refusal from a 0-dim shape either.
* `tinybendygrad/mixin/movement.bend:1296-1305` -- `mxw_dims`/`mxw_fold_shape` go
  through `mo_dims`, so the MOVEMENT WALK HAS THE SAME THREE-WAY AMBIGUITY. The old
  probe asked `mxw_dims_of` and `mo_dims` and got the SAME EMPTY STRING FROM BOTH, and
  took that agreement as confirmation. **IT WAS THE SAME AMBIGUITY, TWICE.**

**⇒ THE READER THAT CAN TELL THE THREE APART IS `F.fold.shape`
(`tinybendygrad/uop/fold.bend:4764`), WHICH ANSWERS THE DOUBLE `Maybe`.** The probe in
this directory uses it, and it is what `nn/argmax.bend`'s `nn_argmax_g.shp` uses.

### 2b. THE CAUSE: TWO NODES WHOSE PRODUCTS DISAGREE WITH THEIR SOURCE'S

MEASURED, `probe.bend`, `A_ar_nodes` / `A_ar_res` (before the fix). The `arange`'s
toposort is 26 nodes and **10 of them are NOT IN THE FOLD'S TABLE AT ALL**; the first
one in dependency order is node 9:

```
9: Ops.RESHAPE[7 8]   NO-TABLE
   src[0] = 7  (Ops.RESHAPE, shape [1,4])
   src[1] = 8  (Ops.STACK with ZERO srcs, shape ())
```

**`src[1]` IS THE SHAPE ARG, AND IT IS THE EMPTY TUPLE.** So node 9 is
`RESHAPE([1, 4] -> ())`: the source's product is 4 and the target's is 1.

**AND UPSTREAM REFUSES THAT RESHAPE TOO -- IT RAISES.**
`tinygrad/uop/ops.py:395-399`:

```
case Ops.RESHAPE:
  if not all(x >= 0 for x in self.marg): raise ValueError(...)
  if resolve(prod(ps) != prod(self.marg), False): raise ValueError(f"bad reshape: {ps} -> {self.marg}")
  return self.marg
```

**⇒ THE PORT'S FOLD IS FAITHFUL. `tinybendygrad/uop/fold.bend:2180-2189`'s
`reshape_ds` IS THAT `raise`, PORTED AS A REFUSAL: `reshape_ok`
(`uop/fold.bend:2146-2149`) is the product test and `dt_of_if` drops the node when it
fails. SO THE PORT WAS BUILDING A GRAPH THAT CPYTIN WOULD REFUSE, AND THE FOLD WAS
SAYING SO BY BEING UNABLE TO ANSWER IT.**

**⇒ AND ONE UNANSWERABLE NODE MAKES THE WHOLE GRAPH UNANSWERABLE**, because a node's
shape is a function of its source's shape and `Kahn.gather` refuses a node whose src is
unresolved (`uop/fold.bend:4658-4672`).

### 2c. THE TWO SITES, BOTH IN `tinybendygrad/mixin/rand.bend`, WHICH I OWN

**SITE 1 -- `op_expand_lead`.** Upstream's `repeat`
(`tinygrad/mixin/movement.py:591-610`) is
`self.reshape(unsqueezed_shape).expand(expanded_shape).reshape(final_shape)`, and
`_broadcast_to` (`movement.py:128-147`) squeezes with
`squeezed = self.reshape(tuple(self.shape[i] for i in kept))` (`movement.py:142`) --
**THE KEPT DIMS `(i,)`, NOT `()`**. The port wrote

```
def op_expand_lead(+t: T.Tensor, r: U32) -> T.Tensor:
  CR.cr_expand(MX.mxw_reshape(t, []), [r])          # <-- 0-dim RESHAPE, AND [r], NOT [r, i]
```

**BOTH HALVES ARE UPSTREAM ERRORS**: the `mxw_reshape(t, [])` is a 0-dim reshape of a
`[1, i]` source (`prod 1` against `prod i`), and the target `[r]` is not upstream's
`expanded_shape = [r, i]`. **AND THE SECOND HALF WAS REDUNDANT**: `mxw_bcast`
(`tinybendygrad/mixin/movement.bend:2017-2028`) does the squeeze to the kept dims
itself (`movement.bend:2026`, `mxw_bc_sq`).

**SITE 2 -- `op_pool1.sh`.** Upstream's `_pool` (`tinygrad/mixin/movement.py:614-632`)
USES `i * f + d` TWICE AND THE TWO USES ARE NOT THE SAME NUMBER:

```
x = x.shrink_to(noop + [k * (i * f + d) ...])           movement.py:626   -> k * iz
x = x.reshape(noop + flatten((k, (i * f + d)) ...))       movement.py:627   -> [k, iz]
```

The port had ONE number, `op_pool1.sz = k * (i * f + 1)`, and used it for BOTH. So the
reshape was to `[k, k * (i*f+1)]` where upstream's is `[k, i*f+1]` -- **THE TWO DIFFER
BY THE FACTOR `k`**, so the port's reshape had `prod = k² * (i*f+1)` against a source of
`prod = k * (i*f+1)`. For `arange(4)`: upstream's number is `iz = 5` and the port's was
`sz = 20`.

**⇒ BOTH SITES ARE FIXED. AFTER THE FIX THE `arange` ROOT READS `SHAPE[4]` AND EVERY
NODE IN IT IS IN THE FOLD'S TABLE.**

### 2d. THE LAYER THAT REFUSED, NAMED

| layer | file:line | what it says |
|---|---|---|
| the movement walk | `tinybendygrad/mixin/movement.bend:1335-1336` (`mxw_dims_of`) | for a NON-movement op it defers to `mxw_fold_shape` (`:1304-1305`), which goes through `mo_dims` -- **so it carries `mo_dims`'s three-way ambiguity** |
| the fold's shape ladder | `tinybendygrad/uop/fold.bend:2610` (`dt_shape`) | the op -> shape dispatch; `Ops.RESHAPE` goes to `reshape_ds` |
| the fold's RESHAPE arm | `tinybendygrad/uop/fold.bend:2180-2189` (`reshape_ds`) + `:2146-2149` (`reshape_ok`) | **THIS IS THE LAYER THAT REFUSED**, and it refused because the port's RESHAPE was illegal -- upstream's `ops.py:398` would have raised |
| the fold's CONST arm | `tinybendygrad/uop/fold.bend:2219-2220` (`const_ds`) | the CONST's shape is `()` -- **and `mo_dims` reads that as a refusal** |
| the fold's EXPAND arm | `tinybendygrad/uop/fold.bend:1736-1737` (`expand_ds`) | `marg + src_shape`, upstream's `ops.py:400-401`; **THIS ARM ALWAYS WORKED**: `B_full_root_nnshape=SHAPE[4]` -- a `full` (CONST -> CAST -> EXPAND) HAS A READABLE SHAPE |
| the read the layers use | `tinybendygrad/nn/layers.bend:94-95` (`nn_shape`) | `nn_u32(M.mo_dims(...))` -- the second collapse |

**⇒ AND THE ANSWER TO THE BRIEF'S NARROW QUESTION -- "CAN THE PORT BUILD A NODE WHOSE
SHAPE IS `[n]`?" -- IS YES, AND IT ALWAYS COULD: `CR.cr_full` BUILDS ONE
(`B_full_root_nnshape=SHAPE[4]`, MEASURED). WHAT IT COULD NOT DO IS BUILD UPSTREAM'S
`arange` GRAPH, BECAUSE TWO OF THAT GRAPH'S NODES WERE ILLEGAL.**

---

## 3. THE FIX

**TWO EDITS, BOTH IN `tinybendygrad/mixin/rand.bend` (WHICH I OWN), BOTH INSIDE THE
`arange` BLOCK.**

1. `op_expand_lead` (`rand.bend:237`) -- now
   `CR.cr_expand(t, [r, i])`: the target is upstream's `expanded_shape = [r, i]` and the
   squeeze to the kept dims is `mxw_bcast`'s own.
2. `op_pool1` (`rand.bend:360-365`) -- a NEW `op_pool1.iz = i * f + 1` carries upstream's
   `i * f + d`, and `op_pool1.sh` reshapes to `[k, iz]` instead of `[k, sz]`.

**AND `arange` IS NOW GENERALISED OVER `step`, `offset` AND `dtype`**
(`rand.bend:418-450`) so that `op_arange_neg` -- upstream's `arange(n, 0, -1)`, THE CALL
`op.py:887` MAKES -- exists:

* `lo, hi = (stop - step, start) = (1, n)` (`op.py:188`, the `step < 0` arm),
* `output_len = ceildiv(stop - start, step) = n` (`op.py:193`),
* `acc_dtype = dt` because `dt` is not a float (`op.py:194`),
* the value is `full((n,), -1)._cumalu(0, Ops.ADD) + (start - step)` =
  `[-1, -2, ..., -n] + (n + 1)` = `[n, n-1, ..., 1]`,
* **and the dtype is `commit_int(1, n)` (`op.py:190`), MEASURED IN CPYTIN: `int32`**
  (`oracle_arange.py`, `cp_arange4_neg_dtype=dtypes.i32`, `cp_arange4_neg_values=[4, 3, 2, 1]`).

**THE `arange(n)` ARM'S GRAPH IS UNCHANGED IN SHAPE BUT ITS ROOT OP MOVED** -- see §5.

### MEASURED, BEFORE AND AFTER, THE SAME DRIVER, THE SAME TREE

```
BEFORE  arange3_g=26 op=CAST nsrc=1 srcops=ADD                        fold_np=False
AFTER   arange3_g=24 op=ADD nsrc=2 srcops=REDUCE|CONST                 fold_np=True
CPython n=31  op=ADD nsrc=2 srcops=REDUCE|CONST
```

**⇒ THE ROOT OP AND THE SRC-OPS NOW AGREE WITH CPYTIN'S EXACTLY. ONLY THE NODE COUNT
DIFFERS: 24 AGAINST 31.** (`rand_before.out`, `rand_after.out`,
`oracle_arange.py`'s `cp_arange3_u32`.)

---

## 4. THE GRAPH-LEVEL `argmax`, ITS ROWS, AND THE CONTROL

`tinybendygrad/nn/argmax.bend` NOW HAS BOTH FORMS:

* `nn_argmax` -- the LIST form, unchanged, its six rows unchanged.
* `nn_argmax_g` -- the GRAPH form: `nn_argmax_g.mx` (`self.max`), `nn_argmax_g.m`
  (`self.eq`), `nn_argmax_g.ar` (`arange(n, 0, -1)`), `nn_argmax_g.idx` (`m * arange`),
  `nn_argmax_g.imx` (`idx.max`), `nn_argmax_g.sub` + `nn_argmax_g.out`
  (`(n - idx.max(...)).cast(int32)`).

**THE ROWS, AND EVERY `want` IS CPYTHON'S OWN** -- read off
`.agents/slop/nnargmax2/oracle_argmax.py`, WHICH ASKS CPYTIN ITSELF:

```
cp_t   = (4,) dt=dtypes.f32     cp_mx  = (1,) dt=dtypes.f32
cp_m   = (4,) dt=dtypes.bool    cp_ar  = (4,) dt=dtypes.i32
cp_idx = (4,) dt=dtypes.i32     cp_imx = ()   dt=dtypes.i32
cp_res = ()   dt=dtypes.i32    cp_out = ()   dt=dtypes.i32
```

**THE DTYPE NAMES ARE TRANSLATED ONCE** (`dtypes.f32` -> the port's `f32`, `dtypes.i32` ->
`i32`, `dtypes.bool` -> `bool`) and the translation is stated in the file, because a row
that prints `dtypes.f32` on one side and `f32` on the other is not a row.

**MEASURED (`argmax.out`, 20 rows, all green):**

```
argmax_unique got=1 want=1        argmax_tie3 got=0 want=0
argmax_tie2 got=1 want=1          argmax_tie_last got=0 want=0
argmax_neg got=1 want=1           argmax_zero got=2 want=2
g_t_shape got=(4,) want=(4,)      g_t_dt got=f32 want=f32
g_mx_shape got=(1,) want=(1,)     g_mx_dt got=f32 want=f32
g_m_shape got=(4,) want=(4,)      g_m_dt got=bool want=bool
g_ar_shape got=(4,) want=(4,)     g_ar_dt got=i32 want=i32
g_idx_shape got=(4,) want=(4,)    g_idx_dt got=i32 want=i32
g_imx_shape got=() want=()        g_imx_dt got=i32 want=i32
g_out_shape got=() want=()        g_out_dt got=i32 want=i32
```

**THE SAME ROWS ARE IN `rows.rows`, TAB-SEPARATED `name`, `got`, `want`.**

### THE CONTROL

**PERTURB ONE EXPECTATION AND THE ROW GOES RED.** `g_ar_shape`'s `want` was changed from
`"(4,)"` to `"(5,)"` and the driver re-run (`control.out`):

```
g_ar_shape got=(4,) want=(5,)      <-- RED
```

**AND RESTORED** (the file was restored from a byte copy and `diff` against it is
EMPTY):

```
g_ar_shape got=(4,) want=(4,)      <-- GREEN
```

**⇒ THE ROW IS A CHECK AND NOT A LABEL.**

### THE READER THE ROWS USE, AND WHY IT IS NOT `nn_shape`

`nn/argmax.bend`'s `nn_argmax_g.shp` asks `F.fold.shape`
(`tinybendygrad/uop/fold.bend:4764`), THE DOUBLE `Maybe`, and answers `NO-TABLE` /
`NO-SHAPE` for the two refusals and CPython's `(4,)` / `()` for a shape.
**`nn/layers.bend`'s `nn_shape` CANNOT BE USED HERE: UPSTREAM'S `imx` IS 0-dim, SO A
READER THAT CONFLATES A REFUSAL WITH A 0-dim SHAPE WOULD PRINT `()` FOR A REFUSAL AND
THE ROW WOULD PASS ON NOTHING.**

---

## 5. WHAT I DID **NOT** DO, NAMED

### 5a. THE `arange` GRAPH IS STILL NOT CPYTHON'S GRAPH: 24 NODES AGAINST 31

**THE SEVEN MISSING NODES ARE ONE MISSING `PAD` AND THE POOL ARITHMETIC THAT FOLLOWS
IT.** Upstream's `_cumalu` pads the axis by `(shape[axis]-1, 0)` (`op.py:754`), so
upstream's `_pool` (`movement.py:614-632`) SEES A SOURCE OF LENGTH `2i-1`. The port's
`op_padc` (`rand.bend:325`) PASSES THE MARG'S SECOND HALF AS `[i]` WHERE UPSTREAM'S IS
`[2i-1]` (`movement.py:190`'s `(x[0], s+x[0]+x[1])`), so the PAD's shape EQUALS its
source's and `movement.py:190`'s `return self if ret.shape == self.shape else ret` FOLDS
THE PAD AWAY.

**⇒ CONSEQUENCE, STATED SO NOBODY INVENTS A WIDER CLAIM: THE PORT'S `_pool` ARITHMETIC IS
COMPUTED ON THE UNPADDED LENGTH, SO THE PORT'S `arange` VALUES ARE NOT UPSTREAM'S. THE
VALUES ARE NOT OBSERVABLE IN THE PORT (IT HAS NO EXECUTOR) AND NO ROW HERE CLAIMS THEM.
THE `argmax`'s VALUES ARE CHECKED BY THE LIST FORM, WHICH IS UPSTREAM'S FORMULA.**

**FIXING THAT IS A `_pad_constant`/`_pool` RE-DERIVATION AND IT IS NOT DONE HERE.**

### 5b. THE `arange`'s TRAILING `.cast(dtype)` STILL DOES NOT FOLD

Upstream's `.cast(dtype)` (`op.py:195`) IS A FOLD WHEN THE DTYPE ALREADY MATCHES, AND
THE PORT'S `op_arange.cast` DOES NOT FOLD IT -- THAT IS `mixin/op.bend`'s W9b
(`mo_promote` REMINTS A WEAK CONST) AND **`mixin/op.bend` IS NOT THIS UNIT'S FILE**. THE
PORT'S `arange` THEREFORE CARRIES ONE EXTRA `CAST` NODE AGAINST CPYTHON'S.

### 5c. `gates/rand_census-gate.py` HAS TWO ROWS WHOSE CLAIM HAS EXPIRED

**`fold_np` AND `fold5_np` ARE THE ROWS WHOSE WHOLE CLAIM IS "THE FOLD CANNOT ANSWER
THIS GRAPH", AND AFTER THE FIX THE FOLD CAN.** MEASURED: `fold_np=False` before,
`fold_np=True` after (`rand_before.out` / `rand_after.out`; the row is
`tinybendygrad/mixin/rand.bend:1035-1038`'s `rd_np`, printed by `rand.bend:1063` and
`:1068`).

**AND `gates/rand_census-gate.py:328-333` PUTS BOTH IN ITS `NEG` SET -- "THE `_d`/`_np`
ROWS WHOSE WHOLE CLAIM IS THAT THE FOLD CANNOT ANSWER -- A CLASS WHOSE EXPECTED ANSWER
IS FALSE".**

**⇒ THAT GATE WILL GO RED ON THOSE TWO ROWS, AND THAT IS THE FIX WORKING. THE FIX IS
NOT TO MOVE THE ROW BACK; IT IS TO MOVE THE ROW OUT OF `NEG` AND TO RE-PIN THE
DECLARED DIVERGENCES.** `gates/` IS **NOT THIS UNIT'S FILE** AND **THE BRIEF FORBIDS
RUNNING ANY GATE**, SO THAT UPDATE IS A NAMED HAND-OVER, NOT SOMETHING DONE HERE.

### 5d. THE OTHER `mixin/rand.bend` ROWS THAT MOVED

MEASURED, `diff rand_before.out rand_after.out` -- **TWELVE ROWS MOVE, AND EVERY ONE OF
THEM IS A ROW THAT CONTAINS THE `arange` GRAPH**:

```
arange3_g    26 -> 24      fold_np     False -> True
arange5_g    26 -> 24      fold5_np    False -> True
tfb3_g       51 -> 48      bits6_g     53 -> 50
btr6_g       65 -> 63      rand23_g    70 -> 67
rand23nc_g   65 -> 63      ctrl_rand_g 70 -> 67
rand_like23_g 70 -> 67     ctrl_arange3_g 26 -> 24
```

**NO OTHER ROW MOVED, AND NO `ref_*` ROW AND NO `st_*_v` ROW MOVED.** THE 55-ROW
POPULATION IS UNCHANGED.

### 5e. THE SCOPE OF THE `argmax` ITSELF

**THE LIST FORM IS A 1-D F32 FORMULA AND THE GRAPH FORM IS A 1-D F32 GRAPH.** Upstream's
`argmax` takes an AXIS and any dtype (`op.py:863`). **THE WIDENING IS NAMED AND IT IS
NOT DONE HERE:**

* **THE AXIS.** The port's `nn_reduce` (`nn/layers.bend:188-191`) DOES build the
  PERMUTE that upstream's `_rop` needs (`ops.py:636`), so a multi-axis reduce is
  reachable -- **but the port's REDUCE DROPS THE HEAD AXES** (`uop/fold.bend:908-910`'s
  `reduce_dims` -> `drop_n`, and `nn/layers.bend:113-134`'s own header says so: "THE
  PORT'S REDUCE REDUCES THE FIRST `num_axes` AXES"), and upstream's `argmax` RESHAPES
  THE INDEX VECTOR TO `self.shape[axis], *[1]*(self.ndim-axis-1)` (`op.py:887`), WHICH
  THE 1-D FORM DOES NOT NEED. **⇒ A 2-D `argmax` NEEDS BOTH THE MULTI-AXIS REDUCE
  CORRECTED AND THE INDEX VECTOR'S RESHAPE BUILT, AND NEITHER IS DONE.**
* **THE DTYPE.** The graph form's index vector is `int32` because upstream's
  `commit_int(1, n)` IS `int32` FOR EVERY `n` THAT FITS (`rand.bend:441`'s TODO),
  and the mask is `bool` and the input is `f32`. **A DIFFERENT INPUT DTYPE IS NOT
  TRIED.**
* **THE VALUES.** The graph form has no value. The LIST form is what checks the values.

---

## 6. THE MACHINERY THAT WAS USED, AND WHAT WAS NOT RUN

* `./bin/bend` (the repo's own shim onto `references/bend/bend2/main.ts`), **ONE bend
  process at a time, never in the background**, with `BEND_NO_TELEMETRY=1` so the
  compiler's "a newer bend is available" notice does not land on stderr.
* `.venv/bin/python` for the CPython lanes (`oracle_arange.py`, `oracle_argmax.py`).
* **NOT RUN, PER THE BRIEF:** `checks/differ.py`, `gates/*`, `checks/e2e*`,
  `checks/sweep.py`, `checks/bounded.py`, `checks/port-compile-gate.py`, any corpus run,
  `pytest`, `mypy`, `ruff`.
* **NOT COMMITTED.** `git read` only, always with `env -u GIT_INDEX_FILE`.

## 7. THE FILE LIST

| path | what |
|---|---|
| `tinybendygrad/nn/argmax.bend` | **EDITED** -- the graph-level `argmax` and its 14 rows, added beside the list form and its 6 |
| `tinybendygrad/mixin/rand.bend` | **EDITED** -- `op_expand_lead`, `op_pool1.iz`/`sz`/`sh`, the generalised `arange`, `op_arange_neg`, and the header records that the fix made stale |
| `.agents/slop/nnargmax2/probe.bend` + `probe.out` + `probe.err` | the capability probe and its output |
| `.agents/slop/nnargmax2/argmax.out` + `argmax.err` | the 20 rows |
| `.agents/slop/nnargmax2/rows.rows` | TAB-separated name/got/want |
| `.agents/slop/nnargmax2/control.out` | the perturbed run |
| `.agents/slop/nnargmax2/rand_before.out` + `rand_after.out` | `mixin/rand.bend`'s own rows, before and after |
| `.agents/slop/nnargmax2/oracle_arange.py` + `oracle_argmax.py` | the CPython lanes |
