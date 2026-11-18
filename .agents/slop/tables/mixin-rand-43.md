<!-- FROM: tinybendygrad/mixin/rand.bend:43 -->
# BLOCK:
# THE WALLS. Four of the first five are OWNERSHIP walls (the def lives in a file this unit
# may not write); only W6 is a device-state wall. Each `TODO(pN)` below is the tracker.
#
#   W1 `arange`, reached from rand.py:26, is `full(...)._cumalu(0, Ops.ADD) + (start - step)`
#      and its chain (`_cumalu` op.py:752 -> `_pad_constant` op.py:282 -> `_pool`
#      movement.py:598 -> `repeat`/`expand`/`_broadcast_to`/`broadcast_axes`) is
#      `mixin/op.bend`'s W4. The BORROWED BLOCK in this file is those defs SPECIALISED to the
#      one case `arange`/`_cumalu` reach -- each step exact, not convenient, because
#      `_cumalu`'s pad entries are non-negative, `identity_element(ADD, dt)` is 0 so
#      `_pad_constant`'s `where` half is never built, and `_pool` is called with
#      `stride=1, dilation=1` on a 1-D source. Gated by `arange3`/`arange5`.
#      TODO(p3) mixin/op.py:166  `arange` -- delete the `op_` block and call `mixin/op.bend`'s
#        `mo_arange` when that file grows it. `arange` is also reached by `mixin/op.py:166 symbol=arange
#        linspace`, `:215 eye`, `:233 _tri`, `:236 triu`, `:259 tril` and
#        `nn/__init__.py:366 symbol=_embedding_fwd` (`_embedding_fwd`), so this block is worth more than this file.
#   W2 `cat` (op.py:731), reached from rand.py:15, :29 and tensor.py:471, is `mixin/op.bend`'s
#      W6. PORTED: `op_cat1`, the two-operand all-equal `dim=0` case -- the only one
#      `_threefry_random_bits`, `random_bits` and `_next_counter` reach. `stack`
#      (movement.py:270) is upstream's `stack` def, and the `Ops.STACK` arm of upstream's
#      `_mop` (ops.py:809-812) calls both `dtype_from_uop` (ops.py:116
#      symbol=dtype_from_uop) and `ccast` (ops.py:618 symbol=ccast) -- which is
#      `tensor.bend`'s own `TODO(p3)`, so that is why `cat` is W2 at all.
#      TODO(p3) mixin/op.py:731  `cat`'s unequal-shape arm (`itertools.accumulate` plus a
#        `pad` and a `usum` per tensor) and its `dim != 0` case.
#   W3 `_getitem` (op.py:74), reached from rand.py:14, :101 and tensor.py:520-524, is
#      `mixin/op.bend`'s W1 (a seven-way index sum type). PORTED: `rd_take`/`rd_slice`/
#      `rd_scalar` -- the only arms this file reaches.
#      WALL(p3) mixin/op.py:74  `_getitem` for a negative int, a two-sided slice, an -- BLOCKED: needs the other INDEX FORMS -- a negative int, a two-sided slice, an `Ellipsis`, a `list`, a `Tensor` index and `None`. Each is a Python index TYPE, and Bend has one index form.
#   W4 `cos`/`log`, reached from rand.py:103, are three lines of already-ported ops each, but
#      `mixin/elementwise.bend` has neither. PORTED: `rd_cos`/`rd_log`, each CALLING
#      `E.ew_sin`/`E.ew_log2` rather than re-deriving them.
#      WALL(p3) tinygrad/mixin/elementwise.py:499 symbol=cos  `cos` for half/bfloat16, where -- BLOCKED: needs the half/bfloat16 ARM. `least_upper_float` EXISTS and `least_upper_dtype` does NOT (checked as defs), and the two folds become CASTs rather than the identity, so f32's `rd_cos` does not reach them.
#      done(p3) tinygrad/mixin/elementwise.py:828 symbol=log  `log`. -- done, not blocked: `ew_log` is in `mixin/elementwise.bend` and `rd_log` below calls it; gated at `gates/ew-explog-gate.py` (3 rows, 3 lanes byte-identical). measured with `^def ew_log\(`. The header's `has neither` was true before that landed.
#   W5 `multinomial`'s two arms are `topk` (op.py:976, the bitonic sort -- `mixin/op.bend`'s
#      W5) and `cumsum` (op.py:770 -> `_cumalu` -> `identity_element`). PORTED: the
#      `unsqueeze` selection and both guards, and the trailing `.cast(dtypes.i32)`.
#      TODO(p3) mixin/rand.py:270  `multinomial`'s cdf arm -- `cumsum` -> `identity_element`.
#      TODO(p3) mixin/rand.py:275  `multinomial`'s Efraimidis-Spirakis arm -- `topk`.
#   W6 `dropout`'s `if not TRAINING` (rand.py:294) reads helpers.py's `TRAINING` ContextVar --
#      an environment seam, not a graph -- so it is a `Bool` PARAMETER; the three-way arm
#      selection is PORTED and gated.
#      TODO(p3) mixin/rand.py:296  `dropout`'s general arm -- `where` over a float mask.
#        (`.clone().where(self, 0) / (1.0 - p)` needs `where` over a float mask, and a
#        division by a Python float whose promotion is not the same rule as every other
#        binop here.)
#      TODO(p3) tinygrad/helpers.py  `TRAINING` -- the ContextVar read.
#      WALL(p3) mixin/rand.py:315 `repeat_interleave`  `scaled_dot_product_attention`'s GQA arm. -- BLOCKED: needs the GQA arm -- a head-group reshape around the same matmul.
#      WALL(p3) mixin/rand.py:319 `matmul`  `scaled_dot_product_attention`'s matmul. -- BLOCKED: needs the batched matmul.
#      WALL(p3) mixin/rand.py:323 `tril`  `scaled_dot_product_attention`'s causal mask. -- BLOCKED: needs the causal mask.
#      WALL(p3) mixin/rand.py:327 `softmax`  `scaled_dot_product_attention`'s `attn_mask` arm. -- BLOCKED: needs the `attn_mask` arm.
#      WALL(p3) mixin/rand.py:82  `rand_like`'s device-tuple arm. -- BLOCKED: needs a MULTI-DEVICE `Tensor`: this is `rand_like`'s `isinstance(self.device, tuple)` arm, and the port's `Tensor{ar, uop, ...}` carries ONE arena.
#      TODO(p3) mixin/rand.py:249  `randperm` -- `argsort`.
#
