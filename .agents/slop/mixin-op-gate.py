#!/usr/bin/env python3
"""mixin-op-gate.py -- the CPython oracle for tinybendygrad/mixin/op.bend.

Prints one row per claim, in the same ORDER and the same
`name=<count> OP/<nsrc> ...` format `tinybendygrad/mixin/op.bend` prints, so the two
lanes diff byte for byte:

    .venv/bin/python .agents/slop/mixin-op-gate.py           > /tmp/py.txt
    ./bin/bend tinybendygrad/mixin/op.bend                  > /tmp/bd.txt
    ./bin/bend tinybendygrad/mixin/op.bend -o /tmp/bn && /tmp/bn > /tmp/bn.txt
    diff /tmp/py.txt /tmp/bd.txt && diff /tmp/py.txt /tmp/bn.txt

NOTHING IS EXECUTED. Every row is the SIGNATURE of the lazy graph -- a `toposort()` with
each node's op and src COUNT -- so no device is needed and the oracle is pure Python.

EVERY FIXTURE IS DERIVED FROM CPython rather than restated from the `.bend` file, which
is the only reason the comparison means anything: a row restated from the port would
agree with a wrong port.

THREE ROWS ARE BEND-ONLY and are listed at the foot rather than filtered silently --
`rop_gap`, `exp_cast`, `commit_weak` and `bin_promote` name a refusal or a defect rather
than a graph Python can be asked for, so this script prints none of them and
`mixin-op-gate.sh` filters them by NAME rather than by position.
"""
import sys

sys.path.insert(0, '.')
from tinygrad import Tensor  # noqa: E402


def sig(t) -> str:
  us = t.uop.toposort()
  return f"{len(us)} " + " ".join(f"{u.op.name}/{len(u.src)}" for u in us) + " "


def shape(t) -> str:
  """THE FOLDED SHAPE AND DTYPE of a result.

  A signature cannot print a shape: a RESHAPE's shape arg is a bare `CONST` and the
  signature prints only `CONST/0`, so `RESHAPE(REDUCE, CONST(4))` and
  `RESHAPE(REDUCE, CONST(1))` are the SAME SIGNATURE and a wrong shape is invisible to
  every other row. `mo_at`'s index was off by one and this row is what caught it, so
  the oracle has to have it too.
  """
  # `S.Dt.nm` is `float`; Python prints `dtypes.float`, so the `dtypes.` prefix is
  # stripped here rather than in the `.bend` file -- the `.bend` file prints what
  # the fold says and a row must not be doctored to match.
  return "".join(f"({d})" for d in t.shape) + f" {str(t.dtype).removeprefix('dtypes.')}"


def shrow(name, t) -> None:
  print(f"{name}={shape(t)}")


def row(name, t) -> None:
  print(f"{name}={sig(t)}")


# --- the fixtures. `Tensor([1.,2.,3.,4.], device='PYTHON')` is ONE BUFFER and
# `Tensor([[1.,2.],[3.,4.]], device='PYTHON')` is that buffer RESHAPED, which is why
# `lit1d` and `lit2d` are rows and not setup.
def fx1d() -> Tensor: return Tensor([1., 2., 3., 4.], device='PYTHON')
def i1d() -> Tensor: return Tensor([1, 2, 3, 4], device='PYTHON')
def fx2d() -> Tensor: return Tensor([[1., 2.], [3., 4.]], device='PYTHON')

# --- 1-2: the fixtures, as rows.
row('lit1d', fx1d())
row('lit2d', fx2d())

# --- 3-5: `max`/`sum` (reduce.py:73/:20) and `_reduce`'s keepdim reshape (:18).
row('max0', fx1d().max(axis=0))
row('sum0', fx1d().sum(axis=0))
row('sum0kd', fx1d().sum(axis=0, keepdim=True))

# --- 6-8: `min` (op.py:473), and the pair that sees the OUTER `_inverse`.
row('min0', fx1d().min(axis=0))
row('min0i', i1d().min(axis=0))
row('min0kd', fx1d().min(axis=0, keepdim=True))

# --- 9-12: `mean` (op.py:496). `meanN` is `axis=None`, which is `range(ndim)`.
row('mean0', fx1d().mean(axis=0))
row('mean0kd', fx1d().mean(axis=0, keepdim=True))
row('meanN', fx1d().mean())
row('mean0_2d', fx2d().mean(axis=0))

# --- 13-15: `var` (op.py:523), its `correction=0` arm, and `std` (:568). `correction=0`
# is `smax(n - 0, 0)`, so the denominator CONST is the SAME interned node `mean`'s is --
# which is why `var0c0` is 13 nodes and `var0` is 15 rather than 17.
row('var0', fx1d().var(axis=0))
row('var0c0', fx1d().var(axis=0, correction=0))
row('std0', fx1d().std(axis=0))

# --- 16-19: the tuples. `var_mean` (op.py:551) and `std_mean` (:592) return pairs, so
# each half is its own toposort -- and `var_mean` evaluates `var` FIRST (op.py:566).
row('varmean0_v', fx1d().var_mean(axis=0)[0])
row('varmean0_m', fx1d().var_mean(axis=0)[1])
row('stdmean0_s', fx1d().std_mean(axis=0)[0])
row('stdmean0_m', fx1d().std_mean(axis=0)[1])

# --- 20: `normalize`'s `p == 0` arm (op.py:627). `dim=0` because the reduce is over the
# FIRST axis, which is the only axis `tensor.bend`'s `tn_rop` builds a PERMUTE-free
# REDUCE for (W3).
row('norm0', fx2d().normalize(p=0, dim=0))

# --- 21-23: `logsumexp` (op.py:630), and its `keepdim` arm.
row('lse0', fx1d().logsumexp(axis=0))
row('lse0kd', fx1d().logsumexp(axis=0, keepdim=True))

# --- 24-26: the softmax family (op.py:657/:663/:686/:709). `softmax0` is 15 nodes and
# `logsoftmax0` is 18 over a graph whose shared prefix is 13: `_softmax` is called by
# both and its nodes are interned ONCE. `t_two_rules` measures that from ONE arena.
row('softmax0', fx1d().softmax(axis=0))
row('logsoftmax0', fx1d().log_softmax(axis=0))
row('softmin0', fx1d().softmin(axis=0))

# --- 27: THE TWO-RULES-CLAIM-ONE-NODE ROW, on the CPython side. Python's `ucache` is
# global, so these two calls really do share the thirteen `_softmax` nodes; printing
# them from one process is the measurement and not an assumption.
_t = fx1d()
_sm = _t.softmax(axis=0)
_lsm = _t.log_softmax(axis=0)
print(f"two_rules_sm={sig(_sm)} two_rules_lsm={sig(_lsm)}")

# --- 28: `_softmax`'s THREE OUTPUTS (op.py:657-661) on their own. They are rows because
# `log_softmax` and `softmax` differ ONLY in which of `m`/`e` they use (op.py:683/:706),
# and inside `log_softmax` alone the choice is UNFALSIFIABLE: `ss = e.sum(axis,
# keepdim=True)` already pulls `e` into the graph, so `m - ss.log()` and `e - ss.log()`
# have the SAME toposort. Printed apart, `m` is 8 nodes and `e` is 11.
_s3m, _s3e, _s3ss = fx1d()._softmax(axis=0, dtype=None)
print(f"softmax3_m={sig(_s3m)} softmax3_e={sig(_s3e)} softmax3_ss={sig(_s3ss)}")

# --- 29-33: THE SHAPE ROWS, in the same positions as `t_sh_*` in the `.bend` file.
shrow('sh_sum0kd', fx1d().sum(axis=0, keepdim=True))
shrow('sh_mean0', fx1d().mean(axis=0))
shrow('sh_lse0', fx1d().logsumexp(axis=0))
shrow('sh_lse0kd', fx1d().logsumexp(axis=0, keepdim=True))
shrow('sh_norm0', fx2d().normalize(p=0, dim=0))

# --- THE BEND-ONLY ROWS. `rop_gap` is `T.tn_rop`'s own shape refusal; `exp_cast` pins
# that `exp`'s three casts are the IDENTITY for a float32 source; `commit_weak` is the
# `commit_dtype` refusal `UOp._min_max` (ops.py:1104) forces; `bin_promote` is W9.
#
#   rop_gap        T.tn_rop's `ne1.of` returns None when the fold cannot answer a
#                  source's shape, and `reduce` then hands `self` back UNCHANGED.
#   exp_cast       exp's three casts on a non-float32 source.
#   commit_weak    a weakint node's `commit_dtype` under the P3 `_min_max`.
#   bin_promote    `mo_promote`'s remint arm and its is_invalid arm, both with the arena
#                  threaded correctly.
BEND_ONLY = ('rop_gap', 'exp_cast', 'commit_weak', 'bin_promote')
