# `nn/pool.bend` — batchnorm, max_pool, adaptive_avg_pool, flatten

Measured 2026-10-19 04:24–04:36Z at HEAD `12149576f` (read) and HEAD `2f9a598bf`
(write; the tree is a moving target). `sysctl -n vm.loadavg` read 7.67 at start and
peaked at 20.35 mid-run from other units compiling — every `bend` invocation below
was one foreground process.

**`./bin/bend tinybendygrad/nn/pool.bend --check-only`, first line:**

```
ALL PROOFS CHECK
```

That is the whole gate. `checks/substrate.py` defines COLD as *first line != `ALL
PROOFS CHECK`*, and this file is not COLD.

## THE HEADLINE, AND IT CHANGES THE BRIEF

**There is no pool op — upstream or here — and therefore nothing to refuse on that
ground.**

`tinygrad/uop/__init__.py:13-97` is the whole `Ops` enum. Its members are `ADD MUL
SHL SHR CDIV MAX CMOD CMPLT CMPNE CMPEQ XOR OR AND THREEFRY SUB FDIV POW FLOORDIV
FLOORMOD` / `WHERE MULACC` / `RESHAPE PERMUTE EXPAND PAD UNSHARD` / `REDUCE
ALLREDUCE` and the rest. **No `MAXPOOL`, no `AVGPOOL`, no `MAXPOW2`, no `AVGPOW2`, no
`CMOV`.** Measured: `grep -rn "MAXPOW2\|AVGPOW2\|MAX_POOL\|AVG_POOL" tinygrad/` = 0
hits.

So the brief's expectation that `max_pool`/`adaptive_avg_pool` would be blocked on a
missing op is **false for this tree**, and the reason is worth more than the two
defs: **pooling in this tinygrad is a decomposition, not a UOp.**
`tinygrad/mixin/movement.py:614-632` `_pool` is repeat → shrink → reshape → shrink →
reshape → shrink → reshape → permute, and `max_pool2d` (`mixin/op.py:1333`) and
`avg_pool2d` (`:1285`) are a REDUCE over it. Every one of those movement ops is a def
in the port.

## SECOND MEASUREMENT, WHICH DECIDES WHAT "PORTED" EVEN MEANS

The vendored `tinygrad/nn/__init__.py` **has no `MaxPool2d`, no `AdaptiveAvgPool2d`
and no `Sequential`.** Measured: `grep -n "^class \|^def " tinygrad/nn/__init__.py`
= `BatchNorm(:8) Conv1d(:62) Conv2d(:80) ConvTranspose1d(:111) ConvTranspose2d(:130)
Linear(:156) GroupNorm(:179) InstanceNorm(:209) LayerNorm(:235) LayerNorm2d(:263)
RMSNorm(:281) Embedding(:374) LSTMCell(:395)` and no others. Also
`grep -rn "class MaxPool2d\|class AdaptiveAvgPool\|class Sequential" tinygrad/` = 0.

Consequences, stated per def rather than dressed up as layer ports:

- `max_pool` and `avg_pool` are ported **from the tensor methods they are made of**.
- `adaptive_avg_pool` has **no upstream class** — it is the semantic every framework
  agrees on, and the header of `pool_adaptive_avg` says exactly that.
- `flatten` is `tinygrad/helpers.py:53`, `[item for sublist in l for item in
  sublist]` — a list helper, **not a layer**. The layer of that name in a ResNet is
  `x.reshape(x.shape[0], -1)`, and that is what `pool_flatten` is.

## THIRD MEASUREMENT: `Tensor.batchnorm` IS ALSO A DECOMPOSITION

`tinygrad/mixin/op.py:1693-1698`:

```
axis_ = argfix(axis)                                                   # :1693
shape = tuple(s if ax in axis_ else 1 for ax, s in enumerate(self.shape))  # :1694
x = self - mean.reshape(shape)                                         # :1695
if weight is not None: x = x * weight.reshape(shape)                   # :1696
ret = x.mul(invstd.reshape(shape) if len(invstd.shape) == len(axis_) else invstd)  # :1697
return (ret + bias.reshape(shape)) if bias is not None else ret        # :1698
```

All five operations are defs here, so the **forward is BUILT** and ported one-def-per-
upstream-line. The part of `nn.BatchNorm` that is *not* a decomposition is the
running-statistics update, and it is REFUSED with both blockers named.

## THE PORT'S OWN IDIOMS I COPIED (`file:line`)

| idiom | where | why |
|---|---|---|
| `+q: W4` — a `Data` record, not parameters | `tinybendygrad/mixin/rand.bend:204-211` | "_pool reads `i` and `k` four times each … a `U32` cannot be read twice in one expression and cannot carry `+` as a parameter, and a `Data` record can" |
| non-consuming reader defs (`W4.i0(q: W4)`) | `mixin/rand.bend:213-219` (`PK.i`, `PK.k`) | same file, `:225-226`: "`U1.v` is a def and therefore non-consuming" |
| one def per line of the upstream chain, threading `+t` | `mixin/rand.bend:302-313` (`op_pool1`) | `O.Arena` is affine — `mixin/rand.bend:128-137` — so a building def grows a copy |
| `MX.mxw_reshape` / `mxw_permute` / `mxw_shrink` | `mixin/movement.bend:1431`, `:1449`, `:1537` | the shapes take `List<&2, U32>`, unlike `mo_reshape` which wants `List<&2, O.Const>` |
| `H.ceildiv_u32` | `helpers.bend:1606` | `_pool`'s `ceildiv` |
| the sum axis as a **literal**, not `mo_ax` | `mixin/rand.bend:325-327` | "`mo_ax` takes the tensor and would rebuild the whole of `_pool` … so the literal is the cheap correct spelling" |
| `D.refuse(...)` carrying an address | `extra/datasets/__init__.bend:40-46`, used at `extra/models/resnet.bend:166-173` | "a refusal carries the address of the work rather than a claim that there is none" |
| `main` printing rows, no expectations in-file | `mixin/rand.bend:1232-1249` | a row compared against a number this file wrote is the change-detector AGENTS.md forbids |
| shape rows via `mxw_dims_of` | `mixin/op.bend:1400-1401` | "a shape is what a caller actually consumes" |

## PER-SYMBOL STATUS, AND WHICH OPS EXIST FOR EACH POOL

**Ops that exist for pooling** (all `Ops.` members, all defs in this tree):
`RESHAPE` `PERMUTE` `EXPAND` `PAD` `SHRINK` `CONST` `ADD` `MUL` `MAX` `CDIV` `SQRT`.

| symbol | port def | status | measured row |
|---|---|---|---|
| `_pool` (2 spatial axes, 4-D NCHW) | `pool_nd` `:226` | **BUILT** | `pool_nd_8k2s2=(1)(1)(4)(4)(2)(2)`, `pool_nd_7k3s2=(1)(1)(3)(3)(3)(3)`, `pool_nd_112k3s2=(1)(1)(55)(55)(3)(3)` |
| `max_pool` | `pool_maxpool` `:250` | **BUILT** | `pool_max_8k2s2=(1)(1)(4)(4)`, `pool_max_112k3s2=(1)(1)(55)(55)` |
| `max_pool` padded | `pool_maxpool_padded` `:252` | **REFUSED** | blocker below |
| `avg_pool` | `pool_avgpool` `:260` | **BUILT** | `pool_avg_8k2s2=(1)(1)(4)(4)` |
| `avg_pool` padded | `pool_avgpool_padded` `:262` | **REFUSED** | same blocker |
| `adaptive_avg_pool` (divisible) | `pool_adaptive_avg` `:312` | **BUILT** | `adapt_56_to_7=(1)(64)(7)(7)`, `adapt_56_to_7_win=(1)(64)(7)(8)(7)(8)` |
| `adaptive_avg_pool` (`i%o != 0`) | `pool_adaptive_avg_odd` `:315` | **REFUSED** | blocker below |
| `flatten` | `pool_flatten` `:326` | **BUILT** | `flatten_8_64_7_7=(8)(3136)`, `flatten_rest=3136` |
| `batchnorm` forward | `pool_bn` `:381` | **BUILT** | `bn_bcast_2_3_4_4=(1)(3)(1)(1)` |
| `batchnorm` `rsqrt` | `pool_rsqrt` `:388` | **BUILT** | — |
| `batchnorm` `calc_stats` | `pool_bn_stats` `:396`/`:397` | **BUILT** | — |
| `batchnorm` running stats | `pool_bn_running_stats` `:415` | **REFUSED** | blocker below |
| `_pool`, `ndim != 4` | `pool_wall_4d` `:427` | **REFUSED** | blocker below |
| `_pool`, 1 spatial axis | `pool_wall_1d` `:434` | **REFUSED** (not duplicated) | — |
| reduce-rooted rows | `pool_wall_r1` `:437` | **REFUSED** | **R1**, blocker below |

`pool_nd_112k3s2=(1)(1)(55)(55)(3)(3)` is the ResNet-18 first pool measured: input
112, kernel 3, stride 2, dilation 1, **no padding** → `ceildiv((112-2)/2) = 55`.
PyTorch's `max_pool2d(3, stride=2, padding=1)` answers 56; the difference is exactly
the padding this file REFUSES, which is why it is named rather than absorbed.

## THE EXACT BLOCKER FOR EVERY REFUSAL

**1. `max_pool`/`avg_pool` PADDED — `pool_maxpool_padded` / `pool_avgpool_padded`.**
`tinygrad/mixin/op.py:1370` pads with `self.commit_dtype().min`, and
`_pad_constant`'s `value != 0` arm (`op.py:290`) is
`MovementMixin.pad(X.const_like(True, dtypes.bool), pads).where(base, value)`, which
`mixin/rand.bend:279-281` already records as `TODO(p3)` **needing `identity_element`
(`tinygrad/uop/ops.py:61`)** — not a def in this tree. A `max_pool2d` padded with ZERO
would be wrong for any negative input, so the padded arm is refused rather than built
wrong.

**2. `adaptive_avg_pool` with `i % o != 0`.** `movement.py:623-627`'s `kk`/`sz`
arithmetic is **per-axis and uniform**; unequal windows have no upstream
decomposition to port, so building one would mean the port inventing a different
algorithm and then measuring itself.

**3. `batchnorm` running statistics — `pool_bn_running_stats`.** Two blockers, both
named: **`TRAINING` is not a binding in `tinybendygrad/`** (measured:
`grep -rn "TRAINING" tinybendygrad/` = 3 hits, `nn/optim.bend:517-522` and its
`optim-mut.bend` twin, **all comments**), and **`Tensor.assign` is not a def** (only
`tn_assign_store` at `tensor.bend:1864`, the STORE UOp; `tensor.bend:2539-2541`
states the divergence outright — "Python's `is_param_` mutates in place; this
returns a new"). The **eval-time** path (`op.py:43`, `track_running_stats and not
TRAINING`) is the only path ResNet *inference* takes and it is buildable; the
training-time update is not.

**4. `_pool` for `ndim != 4` — `pool_wall_4d`.** `movement.py:618`'s
`noop = [None] * (self.ndim - len(k_))` is a count of the SOURCE tensor's axes.
`W4` carries `b0`/`b1` as **values**, so every `noop ++ [...]` shape is six wide by
construction and `movement.py:632`'s permute is `[0,1,3,5,2,4]` because
`len(noop) == 2`. Reading `noop` from `mxw_dims_of` is a different def, not a
parameter. (The brief asked for ResNet, where every pooling call is 4-D NCHW.)

**5. `_pool` for one spatial axis — `pool_wall_1d`.** **Deliberately NOT duplicated.**
`mixin/rand.bend:313`'s `op_pool1` already is it for stride 1 / dilation 1, with the
arithmetic already annotated against `movement.py` lines. A second copy is the thing
AGENTS.md calls a ledger that names a path it does not own.

**6. R1 — `pool_wall_r1`. THIS ONE COSTS THE FILE ITS UOP-LEVEL ROWS.**
`mixin/rand.bend:128-137`: "`O.Arena` is affine and a def that BUILDS grows a copy, so
two operands built in different copies name indices neither copy has … A toposort of
ONE node means the root's data src is not in the arena being walked, so the node is
not a graph at all." Measured here, symptom exactly: with `pool_nd` reading
`(1)(1)(4)(4)(2)(2)` **correctly**, `mo_max(False{}, <that>, [4,5])` read the **same**
`(1)(1)(4)(4)(2)(2)` — the pre-reduce dims — and `mo_mean` over a six-axis reshape read
an **empty string**.

**So the rows are not all the same kind of evidence, and this file says so in its own
header rather than printing twenty-one rows of uniform-looking numbers:**

- **Arena-read rows** (movement-only roots → trustworthy): `pool_nd_*`, `flatten_*`.
- **`U32`-arithmetic rows** (reduce/elementwise roots → R1): `pool_max_*`, `pool_avg_*`,
  `adapt_*`, `bn_*`. These are the *same* `_pool` arithmetic the UOp path uses, but
  they do not touch an arena, so they are **a weaker row than a node count** and are
  called that here.

## FOUR COMPILER FACTS THIS FILE PAID FOR

Recorded because each one cost a cycle and none is visible in the finished file:

1. **A nested call chain reports its parse error at the NEXT `def`, not at the broken
   line.** The seven-deep `pool_nd` expression shipped with 8 `(` and 7 `)` — one
   `, q)` short — and `bend` said `expected: a term (the keyword 'def' cannot head
   one)` at the following definition. `pool_nd` is now split into `pool_nd.mid` +
   `pool_nd`.
2. **A `case` binding is consumed, so a derived def that calls another derived def
   fails.** The first spelling put `case W4{...}` inside every def; `W4.f0` reads
   `W4.o0` and `bend` answered `W4.f0: d0 consumed more than once`. The fix is the
   one already written down at `rand.bend:225-226` — ten non-consuming reader defs.
3. **`q: W4` (non-consuming) is read once; `+q: W4` is read many times.** Readers take
   `q: W4` and callers take `+q: W4`, exactly `PK.i` / `op_pool1`.
4. **`mo_reshape` takes `List<&2, O.Const>`; `mxw_reshape` takes `List<&2, U32>`,**
   which is also the correct choice — upstream's `Tensor.reshape` goes through
   `MovementMixin.reshape`.

## WHAT THIS DOES NOT DELIVER

- **No padding arm for either pool.** `max_pool2d(3, stride=2, padding=1)` is
  ResNet-18's actual first pool and it answers **56**, not the 55 measured here.
  Blocker 1 above is the whole distance.
- **No `ndim != 4`.**
- **No node counts, no toposort rows, no comparison against CPython.** R1.
- **`nn.BatchNorm` is not a layer here.** `pool_bn` is the forward and
  `pool_bn_stats` is `calc_stats`; there is no `__init__`, no `weight`/`bias`
  allocation, no `num_batches_tracked`. Blocker 3.
- **Nothing was committed.** No git mutating command was run.