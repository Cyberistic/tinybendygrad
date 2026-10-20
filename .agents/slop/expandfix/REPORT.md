# THE EXPAND marg: `nn_expand` / `cr_expand` handed the WHOLE TARGET to `Ops.EXPAND`

**VERDICT: CONFIRMED, VERBATIM.** `tinybendygrad/nn/layers.bend`'s `nn_expand` and
`tinybendygrad/mixin/creation.bend`'s `cr_expand` build `Ops.EXPAND` with the whole
target as `marg`. CPython's `_broadcast_to` puts **the left-added dims and then the
dims of the source axes that were 1 and became bigger** there, with a squeeze before
and a permute after. The port's own reading of the wrong marg is
`tuple(self.marg) + ps` (`tinygrad/uop/ops.py:397`), i.e. **THE TARGET CONCATENATED
WITH THE SOURCE**.

Measured, on the port's own node, before the fix:

```
case3_repeat_mid  expand marg=1,64,4,58,4,58  shape=1,64,4,58,4,58,1,64,1,58,1,58
```

**which is the prior unit's `1,64,4,58,4,58,1,64,1,58,1,58` exactly**, and CPython's
answer for the same input is `1,64,4,58,4,58`.

- **HEAD when the defect was verified:** `f006c785ff8e296e44269be7a6139e194f21027d`
- **HEAD when the patch was cut:** `3dd131588a39200834bae321be9711d005362992`
- **Measured:** 2026-10-20 17:00:35 UTC (the tree is a MOVING TARGET; the two HEADs
  above are byte-identical for the three patched files — `git diff --stat` between
  them over those three paths is EMPTY — and the working copy still matches HEAD for
  them, so the diff's base is current.)
- **No commit was made. No file outside `.agents/slop/expandfix/` was written.**

---

## 1. THE RULE, QUOTED FROM CPython

`tinygrad/mixin/movement.py:128-146` — `_broadcast_to` — verbatim:

```python
  def _broadcast_to(self, new_shape: tuple[sint, ...]) -> Self:
    if self.shape == new_shape:
      return self
    if self.ndim > len(new_shape):
      raise ValueError(f"cannot broadcast tensor to fewer dimensions. shape={self.shape} to {new_shape=}")
    # first unsqueeze left with 1s https://data-apis.org/array-api/latest/API_specification/broadcasting.html
    shape, _ = _align_left(self.shape, new_shape)
    # for each dimension, check either dim is 1, or it does not change
    if not all(s == ns or s == 1 for s, ns in zip(shape, new_shape)):
      raise ValueError(f"cannot broadcast {self.shape} to {new_shape=}")
    # EXPAND only adds dims on the left. squeeze 1s that need expanding, EXPAND on left, permute back.
    n_left = len(new_shape) - len(self.shape)
    expand_at = tuple(i-n_left for i in broadcast_axes(self.shape, new_shape) if i >= n_left)
    kept = tuple(i for i in range(len(self.shape)) if i not in expand_at)
    squeezed = self.reshape(tuple(self.shape[i] for i in kept))
    expanded = squeezed._mop(Ops.EXPAND, arg=new_shape[:n_left] + tuple(new_shape[n_left+i] for i in expand_at))
    # expanded shape = [left] + [expand_at dims] + [kept dims], permute to new_shape
    perm = tuple(range(n_left)) + tuple(
      n_left + (expand_at.index(i) if i in expand_at else len(expand_at) + kept.index(i)) for i in range(len(self.shape)))
    return expanded.permute(perm)
```

with `tinygrad/uop/ops.py:93-97`:

```python
def broadcast_axes(src_shape:tuple[sint, ...], out_shape:tuple[sint, ...]) -> tuple[int, ...]:
  # out axes that are added or expanded
  if (nleft:=len(out_shape)-len(src_shape)) < 0: raise RuntimeError(f"cannot broadcast {src_shape} into {out_shape}")
  return tuple(range(nleft)) + tuple(nleft+i for i,s in enumerate(src_shape) if resolve(s == 1, default=False) and resolve(out_shape[nleft+i] != 1))
```

**STATED PLAINLY.** Write `src` for the source's shape and `dst` for the target's.

1. `n_left = len(dst) - len(src)` — the number of dims ADDED ON THE LEFT.
2. A source axis `i` **expands** iff `src[i] == 1` and `dst[n_left+i] != 1`. Those
   axes are `expand_at` (in SOURCE coordinates).
3. `kept` = the source axes that do not expand. `squeezed = src` restricted to `kept`
   — **the expanding axes are DROPPED from the source before the expand.**
4. **The marg is `dst[:n_left]` ++ `dst[n_left+i]` for each `i` in `expand_at`** — the
   left-added dims' sizes, then the sizes of the source axes that were 1 and became
   bigger. **It is NOT `dst`.**
5. `expanded`'s shape is `marg ++ kept`'s shape, and a `permute` puts it back, so
   **the result's shape IS `dst`.**

**A 0-dim source is the degenerate case where `n_left == len(dst)` and `expand_at` is
empty, so the marg IS the whole target** and the squeeze and the permute are
no-ops. That is why `full` / `const_like` were never wrong.

**THE PRIOR UNIT'S PHRASING IS IMPRECISE ON ONE POINT AND THE MEASUREMENT SETTLES
IT.** "only the left-added dims" is the rule for the left half only; the marg ALSO
carries the sizes of the source axes that were 1 and became bigger. For conv2d
(`n_left == 0`) the marg is `(rcout,)` — one dim that is **not** left-added — and
CPython's own `expand` marg, read off the node, is exactly `8` for `rcout == 8`
(`.agents/slop/expandfix/cpython-cases.rows`).

`tinygrad/uop/ops.py:397` is the reader: `case Ops.EXPAND: return tuple(self.marg) + ps`.

---

## 2. THE TWO SITES (and the shared def they now call)

| site | what it stood for | the source | the target |
|---|---|---|---|
| `tinybendygrad/nn/layers.bend:520` `nn_expand` | `nn_repeat` (`:523`) and conv2d (`:742`) | `mxw_reshape(t, unsq)` / `mxw_reshape(p, pre(1,…))` | `ex` / `pre(rcout,…)` |
| `tinybendygrad/mixin/creation.bend:271` `cr_expand` | `nn/pool.bend:191` (`_pool`'s repeat), `creation.bend:361`, `creation.bend:419`, `mixin/rand.bend:194` | `mxw_reshape(t, lift)` / a 0-dim CONST / `mxw_reshape(t, [])` | `tiled` / `ds` / `[r]` |

The two were the same code (`T.tn_mop(…, O.OpsEXPAND{}, T.ADims{…})`) with two
different `U32 -> O.Const` projections (`nn_ks` and `cr_cdims`).

**THE FIX puts ONE def in `tinybendygrad/mixin/movement.bend` — the file that OWNS
the movement ops and whose own header already said `_broadcast_to` is "portable for a
CONCRETE shape and NOT DONE" — and makes both sites call it.** `mxw_bcast` is
`_broadcast_to` for a concrete shape:

```
mxw_bcast(t, dst):
  src  = mxw_dims_of(t)                       # the source's DECLARED shape
  base = len(dst) - len(src)                  # n_left
  tail = dst[base:]                           # dst[n_left:]
  mg   = [ tail[i] for i where src[i] == 1 and tail[i] != 1 ]     # the marg's tail
  sq   = [ src[i]  for i where NOT (src[i] == 1 and tail[i] != 1) ]  # the squeezed dims
  ne   = len(mg)
  perm = range(base) ++ [ base+e if expanding else base+ne+k ]     # CPython's perm
  marg = dst[:base] ++ mg
  -> mxw_reshape(t, sq)  ->  mxw_expand(·, marg)  ->  mxw_permute(·, perm)
```

`mxw_reshape` and `mxw_permute` already carry CPython's identity tests
(`movement.py:185` / `:231`), so **the 0-dim-source sites build EXACTLY the nodes
they built before** — the squeeze is a no-op reshape and the permute is the identity,
and both wrappers drop their node. That is why the fix does not disturb `full`,
`const_like` or `mixin/rand.bend`.

**THE PATCH IS THREE FILES, NOT TWO**, and the third is not optional: `cr_expand`
needs `mixin/movement.bend`'s `mxw_reshape` / `mxw_permute`, so
`mixin/creation.bend` must import it (`import ./movement.bend as MX`). **THERE IS NO
IMPORT CYCLE**: `mixin/movement.bend` imports `mixin/op.bend`, `tensor.bend`,
`uop/ops.bend`, `uop/fold.bend`, `helpers.bend`, `LAWS/spec.bend` — and none of them
imports `mixin/creation.bend`. `mixin/creation.bend`'s header line 32-35 of
`mixin/movement.bend` ("portable for a CONCRETE shape and NOT DONE") is UPDATED in
the same patch, because it is no longer true.

**`nn/pool.bend` AND `mixin/rand.bend` DO NOT CHANGE**: `cr_expand`'s SIGNATURE is
unchanged, so `pool.bend:191` picks the fix up for free.

---

## 3. THE PROOF

**THE INSTRUMENT.** `mixin/movement.bend:1332 mxw_dims_of` is the port's merge point
for "the shape of ANY node"; the marg is read off the node with the port's own
`mxm_marg` / `MxMarg.ds`. **THE FOLD IS NOT THE INSTRUMENT HERE**: `uop/fold.bend`'s
`expand_ds` (`:1700`) computes `tuple(marg) + src_shape(0, ss)`, and `src_shape`
reads the FOLD, which DEFERS the six movement ops (`uop/fold.bend:1620-1626`) — so
**the fold CANNOT fold an EXPAND whose source is a movement node**, before the fix
or after it. `uop/fold.bend:1700`'s FORMULA is faithful (`tuple(self.marg) + ps` IS
`tinygrad/uop/ops.py:397`) and **WAS NOT TOUCHED**; `fold.bend:6858`'s M1 row reads
like an accusation and is an equivalent mutation, the same class as M10.

**THE MEASUREMENT MUST READ AN INTERMEDIATE.** The final RESHAPE's marg is the
TARGET in the broken tree AND in the fixed one — that is why `nn/pool.bend`'s
existing rows read RIGHT in the broken tree (`pool_nd_8k2s2=(1)(1)(4)(4)(2)(2)`) and
why the defect hid. The probe therefore prints **every node** of the graph with its
op and its shape.

**`cases.rows` holds the seven cases**, each with CPython's marg and shape (read off
CPython's own node by instrumenting `UOp._mop`) and the port's marg before and after
(read off the port's own node). Every case:

| case | CPython marg | port BEFORE marg | port AFTER marg |
|---|---|---|---|
| `case1_conv_expand` | `8` | `1,1,4,8,14,14,3,3` | `8` |
| `case2_repeat` | `4,4` | `1,64,4,58,4,58` | `4,4` |
| `case3_repeat_mid` | `4,4` | `1,64,4,58,4,58` | `4,4` |
| `case4_pool_maxpool` | `4,4` | `1,64,4,58,4,58` | `4,4` |
| `case5_scalar_expand` | `2,3,4` | `2,3,4` | `2,3,4` — **UNCHANGED** |
| `case6_left_added` | `2,3` | `2,3,4` | `2,3` |
| `case7_middle_one` | `3` | `2,3,5` | `3` |

and the port's AFTER result shape is the TARGET in every case
(`permute shape=1,1,4,8,14,14,3,3`, `1,64,4,58,4,58`, `2,3,4`, `2,3,5`).

**THE NODE SEQUENCE NOW MATCHES CPYTHON'S.** CPython's `conv2d` toposort ends
`…|STACK|RESHAPE|CONST|EXPAND|PERMUTE` and the port's fixed graph ends
`…|RESHAPE(1,1,3,32,32,3,3)|CONST|EXPAND(8,1,1,3,32,32,3,3)|PERMUTE(1,1,3,8,32,32,3,3)` —
the squeeze RESHAPE, the EXPAND whose marg is the single CONST `8` (a one-element
shape arg is the CONST ITSELF and not a STACK, `tinygrad/uop/ops.py:106-108`), and
the PERMUTE.

**THE REGRESSION SWEEP.** Every row suite in the tree was run on the pristine tree
and on the patched tree and diffed. **ALL OF THEM ARE BYTE-IDENTICAL** except one:
`tinybendygrad/nn/layers.bend`'s `dbg_conv_sig`, the conv2d graph's node count,
**`n=51` -> `n=55`**. The node-list diff of that graph shows the two expands and
nothing else:

```
+Ops.RESHAPE(1,3,34,34)                      <- the squeeze
+Ops.STACK(3)                                <- the marg (4,4)
-Ops.STACK(7)  Ops.EXPAND(0,1,3,4,34,4,34,1,1,3,1,34,1,34)
+Ops.EXPAND(0,4,4,1,3,34,34)                 <- marg (4,4)
+Ops.PERMUTE(0,1,3,4,34,4,34)                <- back to the target
+Ops.STACK(7)  Ops.RESHAPE(1,1,3,32,32,3,3)
-Ops.STACK(8)  Ops.EXPAND(1,1,3,8,32,32,3,3,1,1,3,1,32,32,3,3)
+Ops.EXPAND(8,1,1,3,32,32,3,3)               <- marg (8,)
+Ops.PERMUTE(1,1,3,8,32,32,3,3)              <- back to the target
```

Suites run and diffed, ALL IDENTICAL: `tinybendygrad/nn/pool.bend`,
`tinybendygrad/nn/layers.bend` (except the one row above), `tinybendygrad/nn/datasets.bend`,
`tinybendygrad/nn/onnx.bend`, `tinybendygrad/nn/optim.bend`, `tinybendygrad/nn/state.bend`,
`tinybendygrad/nn/torch.bend`, `tinybendygrad/mixin/rand.bend`,
`tinybendygrad/mixin/creation.bend`, `tinybendygrad/mixin/op.bend`,
`tinybendygrad/mixin/movement.bend`, `tinybendygrad/mixin/elementwise.bend`,
`tinybendygrad/mixin/reduce.bend`, `tinybendygrad/mixin/gradient.bend`,
`tinybendygrad/uop/movement.bend`, `tinybendygrad/uop/ops.bend`,
`tinybendygrad/uop/fold.bend`, and the fifteen model suites under
`tinybendygrad/extra/models/` (`bert`, `clip`, `convnext`, `efficientnet`,
`inception`, `llama`, `mask_rcnn`, `resnet`, `retinanet`, `rnnt`, `t5`,
`transformer`, `unet`, `unet3d`, `vit`).

---

## 4. THE BLAST RADIUS — EVERY CALL SITE, NAMED

**THE SEVEN CALL SITES OF `nn_expand` / `cr_expand`, AND WHAT EACH ONE IS NOW:**

| call site | the source's shape | before | after |
|---|---|---|---|
| `tinybendygrad/nn/layers.bend:524` (`nn_repeat`) | `(bs,cin,1,H,1,W)` | marg = the whole target | marg = the repeat counts `(r0,r1)` |
| `tinybendygrad/nn/layers.bend:742` (conv2d) | `(bs,groups,cin,1,*oyx,*HW)` | marg = the whole target | marg = `(rcout,)` |
| `tinybendygrad/nn/pool.bend:191` (`_pool`'s repeat) | `(b0,b1,1,i0,1,i1)` | marg = the whole target | marg = `(kk0,kk1)` |
| `tinybendygrad/mixin/creation.bend:361` (`const_like`) | `()` | marg = the whole target | **UNCHANGED** |
| `tinybendygrad/mixin/creation.bend:419` (`full`) | `()` | marg = the whole target | **UNCHANGED** |
| `tinybendygrad/mixin/rand.bend:194` | `()` (reshaped to `[]`) | marg = the whole target | **UNCHANGED** |

**SO: `pool_maxpool` IS REPAIRED, AND NOT BY A POOL FIX.** `nn/pool.bend:191`'s
`pool_rep.rp` calls `CR.cr_expand`, and `cr_expand` is now `_broadcast_to`, so the
`_pool` chain's expand carries the repeat counts. **There is no separate pool
defect** — the prior unit's reading is confirmed: the pool was a victim of the
expand, not a pool bug. `pool_maxpool`'s measured marg goes from
`1,64,4,58,4,58` to `4,4` (`cases.rows`, `case4_pool_maxpool`).

**NOTHING ELSE IN THE TREE DEPENDS ON THE OLD (WRONG) SHAPE.** The consumers of an
EXPAND's shape are all GENERIC — they read the marg, not a particular one:

- `tinybendygrad/uop/fold.bend:1700 expand_ds` — `both(marg, ps)`: the marg is
  whatever the node carries ✓.
- `tinybendygrad/mixin/movement.bend:707 mxm_shape.expand` — `mx_cat(MxMarg.ds(m), ps)` ✓.
- `tinybendygrad/mixin/movement.bend:798` / `:816` — the identity tests ✓.
- `tinybendygrad/mixin/creation.bend:325 cr_mop(t, O.OpsRESHAPE{}, ds)` — a RESHAPE,
  not an EXPAND ✓ untouched.
- `tinybendygrad/mixin/rand.bend:264` — PAD/SHRINK ✓ untouched.
- `tinybendygrad/tensor.bend:2389` / `:2396` — TEST ROWS (`t_mop_exp0`, `t_mop_exp`),
  not call sites ✓.
- `tinybendygrad/mixin/gradient.bend:1576` — a hand-built TEST FIXTURE ✓.
- `tinybendygrad/schedule/prepare.bend:267 pr_expand` — the SCHEDULE's own rewrite,
  a different subsystem and a different graph. **IT DOES NOT DEPEND ON THE OLD
  SHAPE** and it was not touched. (It is worth a separate look: CPython's
  `tinygrad/schedule/prepare.py` emits NO `Ops.EXPAND` at all, so that port is a
  divergence of its own — OUT OF SCOPE HERE, NAMED SO IT IS NOT LOST.)

**STILL NOT PORTED, AND STILL A WALL (not touched, named so nobody thinks the fix
covered it):**

- **`mixin/gradient.bend:596-604`** records that CPython's
  `ctx._broadcast_to(ret.src[0].shape)` (`tinygrad/mixin/gradient.py:9`, the ADD
  gradient) is **NOT PORTED** because `broadcast_axes` needs `resolve` on a `Sint`.
  The fix does not change that: the gradient's ADD arm is still a wall, not a
  wrong shape.
- **THE FOLD still cannot fold an EXPAND over a movement source** (see §3). The
  fix does not change that either, and the port's own answer for such a node is
  `mixin/movement.bend`'s `mxw_dims_of`.

---

## 5. THE FILES

- `.agents/slop/expandfix/expand.diff` — the patch, `diff -u` against the REAL files
  (`tinybendygrad/mixin/creation.bend`, `tinybendygrad/nn/layers.bend`,
  `tinybendygrad/mixin/movement.bend`).
- `.agents/slop/expandfix/cases.rows` — the seven cases: input, CPython's marg and
  shape, the port's marg and shape BEFORE and AFTER.
- `.agents/slop/expandfix/REPORT.md` — this file.
- `.agents/slop/expandfix/probe/expandfix.bend` — the Bend probe.
- `.agents/slop/expandfix/cpython_cases.py`, `cpython_seq.py`, `cpython_probe.py`,
  `join_cases.py` — the CPython instruments and the joiner.
- `.agents/slop/expandfix/scratch/` — the PATCHED tree. `.agents/slop/expandfix/scratch-before/`
  — the PRISTINE tree, for the BEFORE measurement.
- `.agents/slop/expandfix/port-before.rows`, `port-after.rows`,
  `conv2d-before.rows`, `conv2d-after.rows`, `before-nn_*.rows`, `after-nn_*.rows`,
  `rows/` — the raw row dumps of the sweep.

**HOW TO APPLY AND CHECK:**

```
# at the REPO ROOT (the diff's paths are a/tinybendygrad/... , so -p1)
git apply .agents/slop/expandfix/expand.diff          # three files
bin/bend .agents/slop/expandfix/scratch/probe/expandfix.bend
```

**THE PATCH WAS VERIFIED END TO END**: a pristine copy of `tinybendygrad/` was
made, `expand.diff` was applied to it with `patch -p2` (the copy's root IS the
`tinybendygrad/` CONTENT, so the strip is one deeper than at the repo root), and the
probe on the patched copy printed the §3 AFTER rows — the same rows the patched
`scratch/` tree prints.

**WHAT I DID NOT DO.** No commit (the orchestrator lands it). No edit to any file
outside `.agents/slop/expandfix/`. **`tinybendygrad/mixin/movement.bend`,
`tinybendygrad/mixin/creation.bend` and `tinybendygrad/nn/layers.bend` are
BYTE-IDENTICAL TO HEAD** (`git hash-object` vs `git rev-parse HEAD:<path>` — `git
diff HEAD` is unreliable on this tree because the index is armed). **`.agents/TODO.md`
is NOT ticked off** — the brief restricts writes to `.agents/slop/expandfix/`, and
the tree's rule says the tick must go in `TODO.md`; the orchestrator should do that.
No `checks/differ.py`, no `gates/`, no `checks/e2e*`, no `checks/sweep.py`, no
`checks/bounded.py`, no corpus-wide run, no pytest/mypy/ruff. Every `bend` run was on
a scratch copy, one process at a time, never backgrounded.
