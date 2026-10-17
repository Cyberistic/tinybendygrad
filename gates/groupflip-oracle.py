#!/usr/bin/env python3
"""groupflip-oracle.py -- CPython's TOPOSORT for `UOp.group` and `Tensor.flip`, AS THEY ARE NOW.

    .venv/bin/python gates/groupflip-oracle.py

ELEVEN ROWS, THE SAME ELEVEN `gates/groupflip.bend` PRINTS, FROM CPython. Every row is the
whole `toposort()` in walk order, one entry per node, `-- <OP>x<nsrc>[<src ops>]`, joined with
`|`. A return value is not printed and a dtype is not printed: the behaviour under test is the
OP SEQUENCE, because the corpus (`checks/differ.py run`, 34 graphs) treats the graph as the
contract, and a `flip` that returns the right answer over the wrong nodes is not ported.

THE FIXTURES ARE CPYTHON'S OWN CALL SITES, NOT TRANSCRIPTIONS:

  `UOp.group`   ops.py:536-538. Upstream's `group` filters `None` out of its arguments and its
                one-src guard counts the UNFILTERED length, so the arms are: zero srcs ->
                `UOp(Ops.STACK).after()` and `after` is `... if len(src) else self`, so a BARE
                STACK; one src -> `srcs[0]` itself and NO node; two or more -> `AFTER(STACK,
                ...)`. `group2` is the corpus's own `g_group` shape (`ops.py` `UOp.group` over
                an ADD and a MUL on one base) and `group6` is `g_commute`'s arity.
  `Tensor.flip` movement.py:233-267, the loop over `axis_arg`. The base is (4,4,4,4) and NOT
                (1,4,8,8), because `if resolve((n:=ret.shape[axis]) <= 1, False): continue`
                skips a length-1 axis and the ORDER witness (`flip_01` against `flip_10`) is
                vacuous unless both axes compose. `flip_none` is `flip(())`, which is upstream's
                own empty `axis_arg`: `argfix(())` is `()` (helpers.py:22, one argument that is
                a tuple) and the loop body never runs.

NEITHER SIDE SORTS BY `Ops.value`, so the two toposorts are comparable without a
canonicalisation pass: upstream's `UOp.toposort` (ops.py:286) is a stack walk pushing
`reversed(node.src)`, and the port's is the same walk. The port's `Ops.value` numbers are
offset by one at position 14 and two from position 73 (`GROUP` at 14, `FLIP` at 73, per
`gates/opseven-gate.py`'s measured `_removed()`), and a CONSTANT shift preserves the relative
order, so the two sequences are directly comparable. Nothing below normalises that away: a
disagreement prints as a disagreement.

ONE CASE IS NOT A ROW AND ITS GAP IS A NUMBER. Upstream's `group` takes `*srcs: UOp|None` and
the port's takes `List<&2, U32>` -- already filtered, with no spelling for an absent element,
because `Nil{}` is the EMPTY list and not a missing one. So `UOp.group(None, a)` is
`AFTER(STACK, a)` upstream and `a` on the port, and there is no way for the port to print
upstream's answer. A row the port cannot print measures nothing, so it is not one; it is
printed to STDERR instead, which keeps the gap in the transcript rather than in a comment.
That is `gates/opseven-oracle.py`'s own `pyliteral_frozenset` shape.
"""

import os
import sys

sys.path.insert(0, os.environ.get("TGROOT", ""))

from tinygrad.dtype import dtypes
from tinygrad.tensor import Tensor
from tinygrad.uop import Ops
from tinygrad.uop.ops import UOp


def topo(u, cut=0):
  """`-- <OP>x<nsrc>[<src ops, comma-joined>]`, one entry per node, in `UOp.toposort` order.

  `Ops.` IS PREFIXED ON BOTH SIDES: `tinybendygrad/uop/ops.bend`'s `Ops.name` is the PREFIXED
  table (`Rng.sig` prints `Ops.ADD`), and `checks/differ.py`'s canonical rows are prefixed too,
  so prefixing here is the form the rest of the tree already compares. `f"{n.op}"` is the same
  string -- `FastEnum.__str__` is `Enum.__str__`.

  `cut` DROPS THE FIRST `cut` NODES, and only the flip rows use it. Upstream moved a BUFFER's
  size out of `ParamArg` into a size CONST src (`ParamArg`, ops.py:25-37, has no `size` member
  -- that field is what `.agents/slop/graphcmp.py`'s `paramarg` (:710) still reads, and that read
  is why the corpus's CPython lane cannot be re-run at all) while the port's `mxw_pbuf` still
  puts it in the arg, so a base is `BUFFERx1[CONST]` here and `BUFFERx0[]` there. The base ROOT
  is `Ops.RESHAPEx2[Ops.BUFFER,Ops.STACK]` on both sides, so the rows keep it and drop everything
  below it, and `cut` is `len(base.toposort()) - 1`. Whether that prefix assumption holds is not
  claimed: it is checked by the diff, because a wrong cut puts the rows out of step.

  `{order}` IS PRINTED FOR A PERMUTE BECAUSE `Ops.PERMUTEx1` CANNOT TELL ONE PERMUTATION FROM
  ANOTHER AND A REVERSED ONE IS STILL A PERMUTATION. MEASURED: with only the op, the nsrC and the
  src op SEQUENCE in the row, the port's `transpose(0, 1)` order came out `[3,2,0,1]` -- the
  REVERSE of `[1,0,2,3]` -- and `flip_1` read AGREE, because a reversed permutation has the same
  length, the same op and the same src op. `n.arg` IS the order here: upstream's
  `_mop(Ops.PERMUTE, order)` stores the order tuple directly (ops.py:805-806, `src_args = []`),
  so nothing has to be resolved through CONSTs on this side."""
  out = []
  for n in list(u.toposort())[cut:]:
    order = ",".join(str(x) for x in n.arg) if n.op is Ops.PERMUTE else ""
    out.append(f"{n.op}x{len(n.src)}[{','.join(str(s.op) for s in n.src)}]{{{order}}}")
  return "|".join(out)


def row(nm, u, cut=0):
  print(f"{nm}={topo(u, cut)}")


# THE BASE IS BUILT TWICE AND THE GROUP ROWS DO NOT USE IT: `fbase()` is the (4,4,8,8) flip
# base, and a flip needs a SHAPE, which needs a storage node -- and a storage node is where the
# `ParamArg.size` divergence lives. `topo`'s docstring names it and the flip rows pay for it with
# a CUT; the group rows need no storage at all, so they use CONSTs and pay nothing.
def fbase():
  """The port's `mxw_base()` RESHAPED to (4, 4, 8, 8), BUILT AS TWO RESHAPES.

  TWO, and not one: the port's `mxw_base` is already `RESHAPE(BUFFER, STACK(1,4,8,8))`, so
  `mxw_reshape(base, [4,4,8,8])` is `RESHAPE(RESHAPE(BUFFER, STACK), STACK)` -- a NESTED one --
  and a single reshape here would answer `RESHAPE(BUFFER, STACK)` and disagree on `flip_none`,
  the one row whose whole content is the base. So this builds the port's base first and then
  reshapes it again, and the two lanes' base ROOT is the same node.

  THE ORDER WITNESS NEEDS BOTH AXES >= 2 AND NOT (1, 4, 8, 8): upstream's own guard skips an
  axis of length 1 (`if resolve((n:=ret.shape[axis]) <= 1, False): continue`, movement.py:255),
  so on (1, 4, 8, 8) `flip(1, 0)` and `flip(1)` would be the same graph and `flip_10` would be a
  byte-identical copy of `flip_1`. The target is (4, 4, 4, 4) AND NOT (4, 4, 8, 8) because the
  buffer is `new_buffer("PYTHON", 256, ...)` -- 256 ELEMENTS, `prod((1,4,8,8))` -- and CPython's
  `_shape` checks every reshape's size (ops.py:395: `bad reshape: (1, 4, 8, 8) -> (4, 4, 8, 8)`,
  MEASURED) while the port's `mxw_reshape` does not. `prod((4,4,4,4)) == prod((1,4,8,8)) == 256`,
  so the SAME 256-element buffer is legal on both sides and no row has to apologise for a size."""
  buf = UOp.new_buffer("PYTHON", 256, dtypes.float)
  return buf._mop(Ops.RESHAPE, (1, 4, 8, 8))._mop(Ops.RESHAPE, (4, 4, 4, 4))


# --- UOp.group, all four arms, over SIX DISTINCT CONSTs. CONSTs and not arithmetic nodes
#     because of the `ParamArg.size` divergence `topo`'s docstring names: a BUFFER is
#     `BUFFERx1[CONST]` here and `BUFFERx0[]` on the port, so any base inside a group row would
#     carry that difference before it said anything about `group`. Six DISTINCT values so the
#     six are six interned nodes. `group2` and `group3` are the shapes the corpus's `g_group`
#     and `g_where` reach; `group6` is `g_commute`'s arity.
a, b, c, d, e, f = (UOp.const(v) for v in (1, 2, 3, 4, 5, 6))
row("group0", UOp.group())
row("group1", UOp.group(a))
row("group2", UOp.group(a, b))
row("group3", UOp.group(a, b, c))
row("group6", UOp.group(a, b, c, d, e, f))

# --- THE `None` GAP. `group` FILTERS, so this is `AFTER(STACK, a)` upstream and `a` on the
#     port, which cannot spell it. Not a row; a number. ---
_N = UOp.group(None, a)
sys.stderr.write(f"gap_none_filter=op={_N.op.name} nsrc={len(_N.src)} port_can_spell=no\n")

# --- Tensor.flip, over the (4,4,4,4) base, WITH THE CUT. ---
# AND THE BASE IS THE LIMIT OF WHAT THIS LANE CAN ASK, NOT A NEUTRAL CHOICE: all four dims are 4,
# so `shape[0] == shape[axis]` on every axis and the defect that replaced `x.shape[1:]`
# (`movement.py:257-259`, over `x = ret.transpose(0, axis)`) with `shape[1:]` is the IDENTITY on
# every row below. `gates/axisflip-gate.py` is the gate that can see it, on (2,4,4,8).
FB = Tensor(fbase())
CUT = len(list(FB.uop.toposort())) - 1
row("flip_none", FB.flip(()).uop, CUT)
row("flip_0", FB.flip(0).uop, CUT)
row("flip_1", FB.flip(1).uop, CUT)
row("flip_01", FB.flip(0, 1).uop, CUT)
row("flip_10", FB.flip(1, 0).uop, CUT)
row("flip_3", FB.flip(3).uop, CUT)
sys.stderr.write(f"cut={CUT} base_root={list(FB.uop.toposort())[CUT - 1].op}\n")

sys.stderr.write(f"n_ops={len(tuple(Ops))} has_GROUP={hasattr(Ops, 'GROUP')} has_FLIP={hasattr(Ops, 'FLIP')}\n")