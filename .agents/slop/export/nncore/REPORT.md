# nn/layers.bend — the LAYER vocabulary

Read 2026-10-19 04:24–04:42 UTC, HEAD `12149576f` at the start and `2cbd67ca2` at the
end. **No commit was made.** Load at start `7.67` (`sysctl -n vm.loadavg`).

## The one number that matters

```
$ ./bin/bend tinybendygrad/nn/layers.bend --check-only
ALL PROOFS CHECK
Use --verdict for mathematical validity.
```

`checks/substrate.py:31` defines COLD as "the FIRST line of the instrument's merged
output is not the literal string `ALL PROOFS CHECK`". The file is **WARM**. 64 defs,
613 lines, no dead def (audited: every def has a call site except the three entry
points `nn_relu` / `nn_linear` / `nn_conv2d`, whose callers are an example, not this
file).

## Status per symbol — THREE BUILT, and one honest gap

| symbol | upstream | status |
|---|---|---|
| `relu` | `mixin/elementwise.py:672` | **BUILT, row-verified.** `got=1,4,8,8 want=1,4,8,8` |
| `nn.Linear.__call__` | `nn/__init__.py:180` + `mixin/op.py:1254` | **BUILT, graph interns, SHAPE ROW EMPTY** |
| `Tensor.conv2d` | `mixin/op.py:1562` | **BUILT, graph interns, SHAPE ROW EMPTY** |
| `resolve_pool_pads` | `helpers.py:59` | **BUILT, row-verified** |
| `flat_to_grouped` | `helpers.py:58` | **BUILT** |
| `_pad_constant` | `mixin/op.py:282` | **BUILT for `value == 0`**; the `has_neg` arm is unreachable (§5) |
| `_pool` | `mixin/movement.py:604` | **BUILT** — the chain; all arithmetic is movement.bend's |
| `_rop` | `uop/ops.py:630` | **BUILT** (§4) |

**THE GAP, STATED PLAINLY.** `nn_linear` and `nn_conv2d` intern a graph and print an
**empty** folded shape where CPython prints a shape. The graph is right and the
read-back is not:

```
dbg_dot_sig  got=n=20 op=Ops.CAST nsrc=1 srcops=Ops.PERMUTE     <- nn_dot's root CAST is over a PERMUTE
fold_cc_sig  got=n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE   <- the SAME expression, hand-built, has the REDUCE
dot_2d got=  want=2,4                                           <- empty
conv_p1_s1 got=  want=1,8,32,32                                 <- empty
```

So inside `nn_dot`, `nn_reduce` built its PERMUTE and `T.tn_rop` answered
`O.Found{ar, self}` — the `case 0n` arm at `tensor.bend:1841` — meaning
`tn_rop.len(axis)` was `0`. `tn_rop.len` is `List.length` of the axis list I pass,
`nn_range(nn_len32(rn))`, so `rn` was empty, which means
`nn_reduce.at(ds, a) == 1` for every `a`, which means `ds = nn_shape(c)` was empty
at that point. **`I DID NOT DIAGNOSIS IT.** The chain works when driven by hand from
the same `xw` (`fold_cc` reads `2,4`), so the difference is inside `nn_dot.pair`, and
the one thing it does that the hand-built row does not is call `M.mo_reshape` /
`M.mo_permute` (mixin/op.bend:664 / :680) instead of `MX.mxw_reshape` /
`MX.mxw_permute` on shapes produced by `nn_ks`. **That is the next thing to look at
and it is not a guess about a fold wall.**

Nothing else in the file is blocked on that, and `relu` — which shares no reduce and
no movement — is verified against CPython in the same run.

## 1. The wall text was wrong in both directions

`nn/__init__.bend:227-232` says:

- `x.linear` — walled on `linear_with_vars` (movement.py) and `mixin/op.bend` W8.
- `x.conv2d` — "SIDE B, not built".
- `Tensor.relu` — not built.

Measured against the tree:

- **`linear_with_vars` is not reached.** `Tensor.linear` (`mixin/op.py:1254`) is
  `x = self.mul(weight) if len(weight.shape) == 1 else self.dot(weight)`. For
  `nn.Linear` the weight is 2-D, so it takes `dot`, and `dot` (`mixin/op.py:367`) is
  RESHAPE + RESHAPE + PERMUTE + MUL + REDUCE + CAST. WMMA is `dot`'s *handler*
  (`mixin/op.bend`'s W8 names the WMMA lowering); the layer's own arithmetic never
  selects it.
- **`SIDE B` is empty.** `tinybendygrad/mixin/op.bend:1523` is that file's LAST line
  and reads `# SIDE B's SECTION GOES BELOW THIS LINE.` There is nothing to wait on.
  `mixin/op.bend:246` reserves that half for whoever writes it; this file is not that
  unit, so `conv2d` is built here.
- **`relu` was already built.** `tensor.bend:774` is `tn_relu`, gated at
  `gates/tn_relu-gate.py`. `nn_relu` is a **name onto it, not a second copy of its
  body** — a repeated line is a shared function, and the layer entry point and the
  tensor method cannot both spell `(self > 0).where(self, 0)`.

## 2. The idioms I copied, with `file:line`

| idiom | where it came from | what `layers.bend` does with it |
|---|---|---|
| `Found` = `(arena, index)`; `O.UOp.new(ar, op, srcs, arg, tag)` | `schedule/__init__.bend:1085` | used only through `T.tn_mop` / `T.tn_alu.put` |
| `tn_alu.put` and never hand-written `tn_new(ar, Found.i(f))` | `tensor.bend:275` (five measured bugs) | every builder ends in a `tn_*` wrapper |
| `tn_binop` + `O.Arena.merge` for two arenas | `tensor.bend:301` | `T.tn_mul` is called, not re-spelled |
| `mo_reshape` / `mo_permute` / `mo_sum` / `mo_cast_t` | `mixin/op.bend:664 / :680 / :811 / :370` | called; `mo_sum` is REPLACED by `nn_sum` (§4) |
| `mxw_reshape` / `mxw_permute` / `mxw_pad` / `mxw_shrink` / `mxw_buf` | `mixin/movement.bend:1431 / :1449 / :1520 / :1537 / :1228` | `_pool`'s chain is built from these |
| the whole of `_pool`'s shape arithmetic | `mixin/movement.bend:237-402` | called, never re-spelled |
| `mxw_base` fixture (`BUFFER` + `RESHAPE`) and `mxw_sig` | `mixin/movement.bend:1724 / :1377` | the row fixtures and the graph rows |
| `nn_mt` (`make_tuple`) and `nn_groups` (`in//groups`) | `nn/__init__.bend:151 / :175` | CALLED via `import ./__init__.bend as NN`, not copied |
| `mo_ki` (`U32 -> O.Const`) | `mixin/op.bend:340` | `nn_ks` is one walk over it |
| `mo_range` (`[0..n)`) | `mixin/op.bend:331` | `nn_range` delegates to `M.mo_range` |

**A bend-syntax fact that cost four compile cycles and is worth writing down**: a
`match` cannot scrutinise a computed value, not even a def call
(`match nn_range.done(n, i):` is REFUSED — "give it its own def" means a *parameter*).
The two working answers are `Bool.pick(Type, cond, a, b)` (strict — both arms are
built) and threading the `Bool` in as the LAST parameter so the decreasing argument
stays to its left. A self-call also needs a **structurally** decreasing argument:
`U32.add(i, 1)` is not one, a list tail is.

## 3. `_broadcast_shape` IS PORTED, so the "broadcasting case" wall is the wrong half

`nn/__init__.bend:299` walls the broadcasting case of `__mul__` on the SHAPE FOLD.
**The shape fold answers it**: `F.bcast_shape` is `uop/fold.bend:672`, over
`bcast.first(_align_left(sh))`, and `F.alu_ds` (`fold.bend:999`) is where every
elementwise `OpsMUL`/`OpsADD` node's shape is read from. Measured in this run:

```
fold_xr got=2,1,3   (RESHAPE)
fold_wr got=1,4,3   (RESHAPE + PERMUTE)
fold_xw got=2,4,3   (MUL of two DIFFERENTLY SHAPED tensors, merged arenas)
```

What `nn/__init__` calls walled is the **other** half of `_broadcasted`
(`mixin/elementwise.py:24`): `ufix` → `least_upper_dtype` → `cast(out_dtype)`. That is
`mo_promote`'s job (`mixin/op.bend`'s W9b) and `layers.bend` **refuses it by name**
rather than assuming it — `nn_dot.dts` answers `None` unless both `tn_dtype`s are
readable and `least_upper_dtypes` is applied to them.

## 4. The one real port defect I found in a file I do not own

`T.tn_rop` (`tensor.bend:1843`) is `_rop` with its permute missing:

- `tn_rop.perm.of` (`tensor.bend:1815`) answers `self` in **both arms** — its own
  comment says so.
- `F.reduce_dims.put` (`fold.bend:892`) answers `drop_n(shape, num_axes)`, and
  `S.drop_n` (`LAWS/spec.bend:270`) drops **from the head**.

CPython pairs those two exactly: `_rop` says *"permute so reduced axes are at the
FRONT"* (`uop/ops.py:636`) and builds
`UOp(Ops.REDUCE, src=(self.permute(perm),), arg=(op, len(reduce_axis)))` (:637). **So
the port's REDUCE reduces the FIRST `num_axes` axes**, and every layer reduce over a
trailing axis is wrong without the permute. Measured here, before the fix:

```
sum(axis=-1)      over (2,4,3)  ->  (4,3)     CPython: (2,4)
sum(axis=-1,kd)   over (2,4,3)  ->  (1,4,3)   CPython: (2,4,1)
```

Both are legal shapes of a plausible size, so **no node count and no op name sees it** —
the same "right count, wrong graph" hole `mixin/movement.bend:246` writes about.

`tensor.bend` is not this unit's file, so `nn_reduce` (`layers.bend`) rebuilds ops.py:636
and hands `T.tn_rop` the front axes `[0 .. len(reduce_axis)-1]`. The REDUCE node and its
arg are unchanged. After the fix: `fold_sm got=2,4` and `fold_cc_sig
got=n=20 op=Ops.REDUCE nsrc=1 srcops=Ops.PERMUTE`.

### Three more defects in my own code, all caught by rows and all green now

1. **`nn_u32.go` appended at the tail AND reversed** — Bend's `List.append(a, A, xs,
   ys)` IS `xs ++ ys`, so a walk that descends while accumulating up rebuilds the list
   in order and the `List.reverse` transposed every shape. `--check-only` was GREEN and
   `where_xshape` printed `3,2` for `[2,3]`. `mixin/movement.bend:246` records the same
   fact from the other side. `nn_ks.go`, `nn_rep.*.go` and `nn_zipcat.go` reverse
   nowhere; `nn_pads.grp` is the one place a reversal is wanted, because
   `flat_to_grouped` genuinely reverses.
2. **`kept` was built from axis INDICES instead of the dim VALUES at those indices**
   (`ops.py:638` is `tuple(s for i, s in enumerate(self.shape) if i not in axis)`). It
   reshaped a `(2,4)` REDUCE to `(0,1)`, which the fold cannot read, so the row printed
   nothing.
3. **`reduce_axis`'s filter zipped `axis` with `shape` positionally** instead of reading
   `shape[axis[j]]`. It agrees with CPython only when `axis` IS `range(ndim)`, which is
   true of `mixin/op.bend`'s own rows (`t_sh_sum0kd` reduces axis 0 of a 1-D tensor) and
   false of every layer.

## 5. `has_neg` is unreachable, not ported

`_pad_constant` opens with `has_neg = not all(resolve(p >= 0) for p in flatten(pX))`
(`mixin/op.py:285`) and takes a `shrink`-then-`smax` arm on it (:286-287). `padding`
arrives here as `U32`, which has no negative, so the arm cannot be written. It is
unreachable for a reason that is upstream's too: `nn.Conv2d`'s `padding` is an int or a
tuple of non-negative ints and `resolve_pool_pads` invents none. A caller that genuinely
needs shrink-then-pad passes the shrunk tensor and the positive pads, which is what the
arm computes. **Named in the file's header, not hidden.**

## 6. The rows, and where the expectations came from

`./bin/bend tinybendygrad/nn/layers.bend` (run, not just checked). Every `want` below was
read off **CPython in this repo's `.venv`** on 2026-10-19:

```
.venv/bin/python -c "
from tinygrad import Tensor
from tinygrad.helpers import flat_to_grouped, resolve_pool_pads
x = Tensor.empty(1,3,32,32)
for pad in [1,(1,1),(0,0),(1,2)]:
  pp = resolve_pool_pads(pad, 2); g = flat_to_grouped(pp)
  p = x._pad_constant(((0,0),)*2 + g, 0.0)
  print(repr(pad), pp, g, p.shape, p._pool((3,3),(1,1),(1,1)).shape)
print(Tensor.rand(2,3).linear(Tensor.rand(4,3).transpose()).shape)
print(Tensor.rand(2,3).dot(Tensor.rand(3,4)).shape)
"
# 1       [1,1,1,1] ((1,1),(1,1)) (1,3,34,34) (1,3,32,32,3,3)
# (1,1)   [1,1,1,1] ((1,1),(1,1)) (1,3,34,34) (1,3,32,32,3,3)
# (0,0)   [0,0,0,0] ((0,0),(0,0)) (1,3,32,32) (1,3,30,30,3,3)
# (1,2)   [2,2,1,1] ((1,1),(2,2)) (1,3,34,36) (1,3,32,34,3,3)
# (2,4) / (2,4)
.venv/bin/python -c "
from tinygrad import Tensor
x = Tensor.empty(1,3,32,32); w = Tensor.empty(8,3,3,3)
print(x.conv2d(w, None, 1, 1, 1, 1).shape)   # (1, 8, 32, 32)
print(x.conv2d(w).shape)                      # (1, 8, 30, 30)
print(x.conv2d(w, None, 1, 2, 1, 1).shape)   # (1, 8, 16, 16)
print(Tensor.rand(2,576).linear(Tensor.rand(10,576).transpose(), Tensor.rand(10)).shape)  # (2, 10)
print(Tensor.rand(2,3).dot(Tensor.rand(3)).shape)   # (2,)
"
```

Two of those readings shaped the code and are worth keeping: **`flat_to_grouped`
reverses the pair order** (`[2,2,1,1] -> ((1,1),(2,2))`), which cancels
`resolve_pool_pads`'s own reversal so `padding=(1,2)` pads the FIRST axis by 1; and
**`_pool`'s output shape is `noop ++ o_ ++ k_`**, so a `permute` that did not move every
`o` after every `k` would print `noop ++ k_ ++ o_` and disagree.

## 7. Two row printers that are NOT `mxw_dims_of`, and why

`nn_row.shp` reads `nn_shape` — `M.mo_dims` over the real fold. It originally read
`MX.mxw_dims_of` (`mixin/movement.bend:1332`), which is a **fuelled walk** over a
movement chain and answered the EMPTY list on the 19-node `dot` graph and `1,8` on the
37-node `conv2d` graph. A row that prints a truncated shape reads as a wrong port, so the
row reads the fold the layer itself reads. `mxw_dims_of` is fine for what
`mixin/movement.bend` uses it for; this file's graphs are one merge and one elementwise
tower deeper than its fuel covers.

## 8. What I did NOT touch, and what I did not verify

- Wrote **only** `tinybendygrad/nn/layers.bend` and this directory. No other file was
  modified. **No commit, no mutating git command, no `git add`.**
- Ran no gate, no `differ.py`, no `e2e`, no `sweep.py`, no `bounded.py`, no corpus loop,
  no `pytest`/`mypy`/`ruff`, no `mixed*`/`sz`/`nir` compiles. The only `bend`
  invocations were `--check-only` and a plain run of **my own file**.
- The `.venv/bin/python` calls above are 8-line oracle reads, not the suite.
- **I did not verify the VALUES of `linear` and `conv2d`** — only that their graphs
  intern and what the root ops are. `relu`, `resolve_pool_pads` and the whole `_rop`
  chain ARE verified. **A count without a denominator is not a result**, so: 3 of the 3
  symbols named in the brief are BUILT, 1 of the 3 (`relu`) is shape-verified against
  CPython, and the other 2 have an unnamed blocker that is in `nn_dot.pair`, not in a
  fold or an op.
- `sequential`, `flatten`, `max_pool`, `adaptive_avg_pool`, `batchnorm` are **not mine**
  (another unit's file) and are untouched.