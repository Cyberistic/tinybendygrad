#!/usr/bin/env python
# THE ORACLE for tinybendygrad/mixin/movement.bend. Every expectation in the
# gate is printed by THIS file, never by the port agreeing with itself.
#
# For each movement op: node count, root op, src count, the src OP SEQUENCE, and
# `_shape`. The src OP SEQUENCE is the row that catches "a movement that swaps
# two srcs has the right count and the wrong graph".
import sys
sys.path.insert(0, '.')
from tinygrad import Tensor, UOp
from tinygrad.uop import Ops


def as_uop(x):
  return x._uop if isinstance(x, Tensor) else x


def sig(u):
  """node count, root op, nsrc, src op sequence, shape"""
  return (len(list(u.toposort())), u.op, len(u.src), tuple(str(s.op) for s in u.src), u.shape)


def row(name, t, extra=""):
  u = as_uop(t)
  n, op, ns, sops, sh = sig(u)
  print(f"{name} nodes={n} op={op} nsrc={ns} srcops={','.join(sops)} shape={sh} {extra}")


def margof(t):
  """marg is the cached_property; it is what the fold calls ssimplify on."""
  u = as_uop(t)
  try:
    return "(" + ",".join(str(x) for x in u.marg) + ")"
  except Exception as e:
    return f"ERR:{e}"


def margrow(name, t):
  row(name, t, "marg=" + margof(t))


base = Tensor.empty(1, 4, 8, 8)   # N,C,H,W  -- the conv2d/pool input
b3 = Tensor.empty(2, 4, 6, 6)

print("### BASELINE")
row("base", base)
print()

print("### SIMPLE MOVEMENT OPS  (each: node count, root op, src count, src op seq, shape)")
margrow("reshape_2_8_16", base.reshape(1, 2, 8, 16))
margrow("reshape_1_1_256", base.reshape(1, 1, 256))
row("permute_nchw", base.permute(0, 1, 2, 3))       # identity -> self, NO node
row("permute_1_0", base.permute(1, 0, 2, 3))
row("permute_3120", base.permute(3, 1, 2, 0))
margrow("flip_0", base.flip(0))
row("flip_01", base.flip((0, 1)))
margrow("pad_1_1", base.pad(((0, 0), (0, 0), (1, 1), (1, 1))))
margrow("pad_0_0_noop", base.pad(((0, 0), (0, 0), (0, 0), (0, 0))))
margrow("shrink", base.shrink(((0, 1), (0, 4), (1, 5), (1, 5))))
margrow("pad_to", base.pad_to((1, 4, 10, 10)))
row("expand", Tensor.empty(1, 4, 1, 8).expand(1, 4, 8, 8))
row("expand_1d", Tensor.empty(1).expand(5))
row("stack0", Tensor.empty(2, 3).stack(Tensor.empty(2, 3), dim=0))
row("stack1", Tensor.empty(2, 3).stack(Tensor.empty(2, 3), dim=1))
row("squeeze", Tensor.empty(2, 1, 2).squeeze())
row("squeeze1", Tensor.empty(2, 1, 2).squeeze(1))
row("unsqueeze0", Tensor.empty(2, 3).unsqueeze(0))
row("flatten", Tensor.empty(2, 3, 4).flatten())
row("unflatten", Tensor.empty(3, 4, 1).unflatten(1, (2, 2)))
row("split2", Tensor.empty(5, 2).split(2)[1])
row("split_list", Tensor.empty(5, 2).split([1, 4])[0])
row("chunk", Tensor.empty(12, 2).chunk(6)[1])
row("diag", Tensor.empty(3).diag())
row("diagonal", Tensor.empty(3, 3).diagonal())
row("roll1", Tensor.empty(4).roll(shifts=1, dims=0))
row("repeat_2", Tensor.empty(3).repeat(2))
row("repeat_4_2", Tensor.empty(3, 4).repeat(4, 2))
row("repeat_interleave2", Tensor.empty(3).repeat_interleave(2))
row("meshgrid", Tensor.empty(3).meshgrid(Tensor.empty(4))[0])
row("unfold", Tensor.empty(8).unfold(0, 2, 2))
row("transpose", base.transpose(2, 3))
print()

print("### repeat, in full  (the shapes _pool depends on)")
for shp, rep in [((3,), (2,)), ((3, 4), (4, 2)), ((3, 4), (4, 2, 1)), ((1, 4, 8, 8), (1, 1, 2, 2))]:
  t = Tensor.empty(*shp)
  row(f"repeat{shp}x{rep}", t.repeat(*rep))
print()

print("### _pool  -- THE W1/W2 CRUX. movement.py:598")
cases = [
  ("pool_k3_s2", (1, 4, 8, 8), (3, 3), 2, 1),
  ("pool_k2_s2", (1, 4, 8, 8), (2, 2), 2, 1),
  ("pool_k3_s1", (1, 4, 8, 8), (3, 3), 1, 1),
  ("pool_k3_s2_d2", (1, 4, 8, 8), (3, 3), 2, 2),
  ("pool_k1_s1", (1, 4, 8, 8), (1, 1), 1, 1),
  ("pool_k2_s3", (1, 4, 8, 8), (2, 2), 3, 1),
  ("pool_k3_s4", (1, 4, 8, 8), (3, 3), 4, 1),
  ("pool_1d", (1, 4, 8), (3,), 2, 1),
  ("pool_3d", (1, 4, 4, 4, 4), (2, 2, 2), 2, 1),
  ("pool_odd", (1, 4, 7, 7), (3, 3), 2, 1),
]
for nm, shp, k, s, d in cases:
  t = Tensor.empty(*shp)
  u = t._pool(k, s, d)
  row(nm, u)
print()

print("### max_pool2d (W2) and conv2d (W1) OUTER SHAPES")
x = Tensor.empty(4, 1, 28, 28)
w = Tensor.empty(8, 1, 3, 3)
row("maxpool2d", x.max_pool2d(2))
# conv2d's own _pool call, from op.py:1562
xx = Tensor.empty(4, 1, 28, 28).pad(((0, 0), (0, 0), (1, 1), (1, 1)))
row("conv2d_poolpre", xx._pool((3, 3), 1, 1))
row("conv2d_poolpost", x.max_pool2d(2)._pool((3, 3), 1, 1))
print()

from tinygrad.uop.ops import ssimplify as ssimplifyof

print("### ssimplify ON A MOVEMENT MARG -- the arm that decides W1/W2")
# `marg` is what `as_shape` ssimplify is called on. For a CONCRETE shape every
# element is a python int, and `ssimplify(int) = int` (ops.py:94), so the whole
# as_shape chain is an UNWRAP. For a SYMBOLIC shape it is not.
u = as_uop(Tensor.empty(1, 4, 8, 8).pad(((0, 0), (0, 0), (1, 1), (1, 1))))
print("pad marg          =", margof(u))
print("pad marg kinds    =", tuple(type(x).__name__ for x in u.marg))
print("pad marg ops      =", tuple(type(getattr(x, 'op', None)).__name__ for x in u.marg))
print("pad src1          =", u.src[1].op, "nsrc", len(u.src[1].src), tuple(str(s.op) for s in u.src[1].src))
print("pad src2          =", u.src[2].op, "nsrc", len(u.src[2].src), tuple(str(s.op) for s in u.src[2].src))
p = as_uop(Tensor.empty(1, 4, 8, 8).permute(1, 0, 2, 3))
print("perm marg         =", margof(p), "argtype", type(p.arg).__name__, "arg", p.arg)
r = as_uop(Tensor.empty(1, 4, 8, 8).reshape(1, 2, 8, 16))
print("reshape src1      =", r.src[1].op, "nsrc", len(r.src[1].src), tuple(str(s.op) for s in r.src[1].src))
print("reshape marg      =", margof(r))
# a SINK of one CONST is a bare CONST (shape_to_shape_arg, ops.py:110)
f = as_uop(Tensor.empty(2, 12).flatten())
print("flatten src1      =", f.src[1].op, "nsrc", len(f.src[1].src), "(a 1-tuple SINK is a bare CONST)")
f1 = as_uop(Tensor.empty(1, 4, 8, 8).flatten(2, 3))
print("flatten1d src1    =", f1.src[1].op, "nsrc", len(f1.src[1].src), "marg", margof(f1))
print()
concrete = [Tensor.empty(1, 4, 8, 8).pad(((0, 0), (0, 0), (1, 1), (1, 1))),
            Tensor.empty(1, 4, 8, 8).shrink(((0, 1), (0, 4), (1, 5), (1, 5))),
            Tensor.empty(1, 4, 8, 8).reshape(1, 2, 8, 16),
            Tensor.empty(1, 4, 8, 8).permute(1, 0, 2, 3),
            Tensor.empty(1, 4, 8, 8)._pool((3, 3), 2, 1),
            as_uop(Tensor.empty(4, 1, 28, 28).max_pool2d(2)).src[0],
            as_uop(Tensor.empty(4, 1, 28, 28).pad(((0, 0), (0, 0), (1, 1), (1, 1))))._pool((3, 3), 1, 1)]
allint = True
for t in concrete:
  tu = as_uop(t)
  for x in tu.marg if tu.op.name not in ("PERMUTE", "FLIP") else tu.arg:
    if not isinstance(x, tuple) and type(x) is not int: allint = False
print("every concrete marg elem is a plain int:", allint)
print()

print("### SYMBOLIC: the arm that does NOT close")
from tinygrad.uop.ops import UOp as _U
n = _U.variable("N", 4, 64)
sym = as_uop(Tensor.empty(1, 4, 8, 8) + n)
print("symbolic add shape=", sym.shape, "dtype", sym.dtype)
try:
  sp = as_uop(sym.permute(1, 0, 2, 3))
  print("symbolic perm marg=", margof(sp), "elem kinds", tuple(type(x).__name__ for x in sp.marg))
except Exception as e:
  print("symbolic perm marg ERR:", type(e).__name__, e)
try:
  sr = as_uop(sym.reshape(1, 2, 8, 16))
  print("symbolic reshape shape=", sr.shape, "src1", sr.src[1].op,
        "as_shape kinds", tuple(type(x).__name__ for x in sr.src[1].as_shape))
except Exception as e:
  print("symbolic reshape ERR:", type(e).__name__, e)
