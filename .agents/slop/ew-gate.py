"""The CPython side of `tinybendygrad/mixin/elementwise.bend`'s gate.

Prints the SAME rows, in the same order, in the same format, so the two lanes diff
byte for byte:

    .venv/bin/python .agents/slop/ew-gate.py > /tmp/py.txt
    ./bin/bend tinybendygrad/mixin/elementwise.bend > /tmp/bd.txt
    diff /tmp/py.txt /tmp/bd.txt

This script is the AUTHORITY. It is the only side of that diff that was derived from
CPython rather than from the port, so it must be regenerated, never hand-edited. It
is an EMITTER and not a differ: it cannot report "0 rows compared", so the recipe's
`diff` is what says whether anything moved -- and a `diff` that prints nothing means
the two files are identical, which is a claim about BYTES and not about rows. Print
`wc -l` on both sides before believing a clean diff.

NOTHING IS EXECUTED. Every graph row is the SIGNATURE of the lazy graph
elementwise.py BUILDS -- `n=<count> OP/<nsrc> ...` in DFS-postorder toposort with
the bare `Enum.name` -- so the oracle needs no device, which is the whole reason
this is a graph gate and not an execution gate.

WHAT IS PINNED, and why each row exists:

  * the COUNT is in every signature row, because a boolean row that says "the ADD
    is there" cannot see a dropped CONST.
  * `ew_add_rev` / `ew_sub_rev` put the BUFFER on the rhs and the CONST on the lhs
    (or the reverse), so the two operand orders print DIFFERENT signatures. Two
    CONSTs would print the same one either way round -- tensor.bend's mutation M15
    is exactly that hole.
  * `ew_op*` and `ew_src0*` read the OP and the INDEX of a named node. tensor.bend's
    M5 found that a signature prints the op and the arity and never the arg, and
    gradient.bend's rows found that a wrong op with the right node COUNT is
    invisible; both holes are closed here by rows that read the value.
  * `ew_promo_*` is the PROMOTION matrix -- elementwise.py:29-33's `promote` -- one
    row per cell of (weak?, base is CONST?, dtype already the weak one?). The
    conjunction `dtype in weaks AND base.op is CONST` is the thing a mutation from
    `and` to `or` would break, and a one-sided fixture cannot see it.
  * `ew_both` is the TWO-RULES-CLAIM-ONE-NODE row: `t + t` on a non-weak operand
    promotes BOTH sides, they hash-cons to ONE CAST, and a first-wins /
    conjunction bug is invisible unless the two answers DISAGREE, so the negative
    side asks for the node COUNT and not for a particular index.
  * `ew_no_promo2` is `sub`'s NOTE -- "alu, not +: _broadcasted already promoted
    these" -- stated as a row: the second promote would add a node, and this row
    is what sees it.
"""
import sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from tinygrad.tensor import Tensor
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes
from tinygrad.dtype import least_upper_dtype, weak_dtype, Invalid

def sig(u, nm):
  ts = list(u.toposort())
  print('%s=%d %s' % (nm, len(ts), ' '.join('%s/%d' % (x.op.name, len(x.src)) for x in ts) + ' '))

def row(nm, b):
  print('%s=%s' % (nm, 'True' if b else 'False'))

def cnt(u, nm):
  print('%s=%d' % (nm, len(u.toposort())))

# `k` counts BACK FROM THE END, because `toposort` is DFS-POSTORDER and the root is
# last. k=0 is the node the method returned; k=1 is its src0's node.
def node(u, k):
  ts = list(u.toposort())
  return ts[len(ts) - 1 - k]

# `k` here is a SRC SLOT of the ROOT, and ONLY that. It is tempting to reuse it as a
# depth as well, since for `sub`'s five nodes depth 1 and slot 1 happen to land on the
# same MUL -- but they are different questions, and conflating them silently reads
# MUL.src[1] (a CONST) where the row means root.src[1] (the MUL). So: `k == -1` is the
# root's own op, otherwise it is the root's src slot `k`.
def opat(u, k, nm):
  print('%s=%s' % (nm, node(u, 0).op.name if k == -1 else node(u, 0).src[k].op.name))

def src0op(u, nm):
  print('%s=%s' % (nm, node(u, 0).src[0].op.name))

# the DERIVED-VALUE read: src `k` of the returned node's dtype NAME. This is the
# row that sees `promote`, because `promote` changes a node's DTYPE and not its op,
# its arity or its node count -- a CONST(3) lifted from weakint to weakfloat is the
# same op with the same srcs, so the SIGNATURE row `ew_promo_remint` cannot see it.
def dtsrc(u, k, nm):
  print('%s=%s' % (nm, str(node(u, 0).src[k].dtype)[7:]))

# a float32 BUFFER of four and an int8 BUFFER of four, both device PYTHON, so the
# two promotion cells that need a non-weak dtype both have a fixture.
f4 = Tensor([1., 2., 3., 4.], device='PYTHON')
i4 = Tensor([1, 2, 3, 4], device='PYTHON', dtype=dtypes.i8)
u4 = Tensor([1, 2, 3, 4], device='PYTHON')
c3 = Tensor(3)
cT = Tensor(True)

# --- the twelve ops the dunder table in tensor.bend's header names --------------
sig(c3.uop.add(Tensor(5).uop), 'ew_add')
sig(f4.uop.add(c3.uop), 'ew_add_f')
sig(c3.uop.add(f4.uop), 'ew_add_rev')          # reverse: the CONST comes first
sig(i4.uop.add(u4.uop), 'ew_add_int8')         # both non-weak: a CAST each side
sig(c3.uop.sub(Tensor(5).uop), 'ew_sub')
sig(c3.uop.mul(Tensor(5).uop), 'ew_mul')
sig(u4.uop.bitwise_and(c3.uop), 'ew_and')
sig(u4.uop.bitwise_or(c3.uop), 'ew_or')
sig(u4.uop.bitwise_xor(c3.uop), 'ew_xor')
sig(u4.uop.lshift(c3.uop), 'ew_shl')
sig(u4.uop.rshift(c3.uop), 'ew_shr')
sig(u4.uop.maximum(c3.uop), 'ew_max')
sig(u4.uop.pow(Tensor(2).uop), 'ew_pow')

# --- the comparison family: three are a binop and three are its negation --------
sig(u4.uop._binop(Ops.CMPLT, c3.uop, False), 'ew_lt')
sig(c3.uop._binop(Ops.CMPLT, u4.uop, True), 'ew_gt')
sig((u4.uop._binop(Ops.CMPLT, c3.uop, False)).logical_not(), 'ew_ge')
sig((c3.uop._binop(Ops.CMPLT, u4.uop, True)).logical_not(), 'ew_le')
sig(u4.uop.ne(c3.uop), 'ew_ne')
sig(u4.uop.eq(c3.uop), 'ew_eq')

# --- the unary alu family: no promotion at all ---------------------------------
sig(u4.uop.alu(Ops.DETACH), 'ew_detach')
sig(u4.uop.alu(Ops.CONTIGUOUS_BACKWARD), 'ew_contig_bwd')
sig(u4.uop.alu(Ops.RECIPROCAL), 'ew_recip')
sig(u4.uop.alu(Ops.TRUNC), 'ew_trunc')
sig(u4.uop.alu(Ops.SQRT), 'ew_sqrt')
sig(u4.uop.alu(Ops.LOG2), 'ew_log2')
sig(u4.uop.alu(Ops.EXP2), 'ew_exp2')
sig(u4.uop.alu(Ops.SIN), 'ew_sin')
sig(u4.uop.alu(Ops.THREEFRY, c3.uop), 'ew_threefry')

# --- the composed ones: neg, logical_not, where, square, mod, fmod ------------
sig(u4.uop.neg(), 'ew_neg')
sig(cT.uop.neg(), 'ew_neg_bool')
sig(cT.uop.logical_not(), 'ew_lnot')
sig(u4.uop.logical_not(), 'ew_lnot_i')
sig(cT.uop.where(Tensor(1).uop, Tensor(2).uop), 'ew_where')
sig(u4.uop.square(), 'ew_square')
sig(u4.uop.mod(c3.uop), 'ew_mod')
sig(u4.uop.fmod(c3.uop), 'ew_fmod')

# --- THE PROMOTION MATRIX, one row per cell ------------------------------------
# promote (elementwise.py:29-33):
#   if base.is_invalid: return t
#   if t.dtype in weaks and base.op is CONST:
#     return t if t.dtype == weak_dtype(out_dtype) else remint(t._uop, dt)
#   return t.cast(out_dtype)
# out_dtype = least_upper_dtype(x.dtype, y.dtype)
#
# cell 1: BOTH weak CONSTs -> out weakint, weak_dtype(out) == weakint, so BOTH
#         sides are returned UNTOUCHED. This is the row that says the fixture set
#         is not all-weak, and it is the ONLY cell where no node is minted.
sig(c3.uop.add(Tensor(5).uop), 'ew_promo_weak_keep')
# cell 2: a weakint CONST against a strong int32 -> out int32, weak_dtype(int32)
#         == weakint == t.dtype, so the CONST is STILL untouched and only the
#         BUFFER is cast. The cell where the two halves disagree.
sig(u4.uop.add(c3.uop), 'ew_promo_weak_keep2')
# cell 3: a weakint CONST against a float32 -> out float32, weak_dtype == weakfloat
#         != weakint, so the CONST is REMINTed and a new CONST is built.
sig(f4.uop.add(c3.uop), 'ew_promo_remint')
# cell 4: both non-weak -> no weak arm at all, both sides CAST.
sig(i4.uop.add(u4.uop), 'ew_promo_cast')
# cell 5: a BOOL CONST against an int32 -> out int32, weak_dtype == weakint, and
#         bool is not in `weaks`, so the bool CONST takes the CAST arm.
sig(u4.uop.add(cT.uop), 'ew_promo_bool_cast')
# cell 6: bool against bool -> out bool, both untouched.
sig(cT.uop.add(Tensor(False).uop), 'ew_promo_bool_keep')
# cell 7, `promote`'s FIRST arm: `if t._uop.base.is_invalid: return t`. An Invalid
# bool is NOT in `dtypes.weaks`, so without this arm it would be CAST to the
# out_dtype. The arm returns the tensor untouched, so the ADD's src1 is the Invalid
# CONST itself and NOT a CAST over it -- which is the claim this row makes.
sig(f4.uop.add(Tensor(UOp(Ops.CONST, src=(), arg=dtypes.bool.const(Invalid))).uop), 'ew_promo_invalid')
# `remint`'s RECURSION: `remint` only descends when `u.op is not Ops.CONST`, and
# every other weak fixture is a bare CONST. `DETACH` is the node for this: ops.py:787
# has `base` descend through `Ops.DETACH` explicitly, so a DETACH over a weakint
# CONST is weak AND has a CONST base -- the one cell that sends `promote` down
# `remint`'s recursive arm. `CONTIGUOUS_BACKWARD` is neither a Movement nor a
# DETACH, so its base is itself and `promote` casts instead; measured, and rejected.
sig(f4.uop.add(c3.detach().uop), 'ew_remint_recurse')
# NOT HERE, and the reason is worth recording: the `+u.src[1:]` ORDER needs a
# `GroupOp.Movement` node with a shape arg (RESHAPE/EXPAND/PAD), because a DETACH has
# one src and `src[1:]` is then empty -- so `[head] ++ []` and `[] ++ [head]` are the
# same list and mutation M5 is unfalsifiable by any row. On CPython such a node takes
# the WEAK arm; in this port the same fixture takes the CAST arm, which makes it a
# question about `uop/fold.bend`'s dtype for a two-src Movement op and not about this
# file. Measured (`4 CONST/0 CONST/0 EXPAND/2 CAST/1`), not assumed.

# --- the two-rules-claim-one-node row -----------------------------------------
# `t + t`: BOTH operands are promoted by the SAME rule and hash-cons to ONE CAST,
# so the count is what distinguishes "one promote, reused" from "two promotes".
sig(u4.uop.add(u4.uop), 'ew_both')

# --- sub's NOTE, as a row: `_broadcasted` already promoted, so no second --------
sig(i4.uop.sub(u4.uop), 'ew_sub_no_promo2')
cnt(i4.uop.sub(u4.uop), 'ew_sub_n')

# --- THE COUNT AND THE INDEX/OP ROWS ------------------------------------------
# the COUNT row: a whole graph's node count, so a dropped or duplicated node moves.
cnt(c3.uop.add(Tensor(5).uop), 'ew_count_add')
# the OP rows, reading the returned node and its named SRC. `sub` is
# `a.alu(Ops.ADD, -b)` and `-b` is `b * -1`, so the root is an ADD and NOT an
# Ops.SUB, and src1 is a MUL. Reading the root sees the swapped op; reading src1
# sees `neg` being spelled as a bare CONST.
opat(c3.uop.sub(Tensor(5).uop), -1, 'ew_op_sub0')
opat(c3.uop.sub(Tensor(5).uop), 1, 'ew_op_sub1')
# `eq` is `ne(...).logical_not()` and `logical_not` is `cast(bool).ne(True)`, so
# the root is a CMPNE and so is src0 -- NOT a CMPEQ. This is gradient.bend's
# "x.eq(y) spelled CMPEQ" row, one level up.
opat(u4.uop.eq(c3.uop), -1, 'ew_op_eq0')
opat(u4.uop.eq(c3.uop), 0, 'ew_op_eq_s0')
# the INDEX rows: the root's src0's OP, so `reverse` swapping the two operands
# moves. c3 is CONST(3) and f4 is a BUFFER, so a forward add's src0 is the BUFFER
# and a reverse add's src0 is the promoted CONST -- DIFFERENT readings, SAME count.
src0op(c3.uop.add(f4.uop), 'ew_src0_rev')
src0op(f4.uop.add(c3.uop), 'ew_src0_fwd')
cnt(c3.uop.add(f4.uop), 'ew_count_rev')
# and the DTYPE rows, which are the only reads that see `promote`. `f4.add(c3)`'s
# src1 is a weakint CONST that `remint` lifts to weakfloat, and it is the SAME op
# with the SAME srcs either way, so the signature above cannot tell them apart.
dtsrc(f4.uop.add(c3.uop), 1, 'ew_dt_remint')
dtsrc(c3.uop.add(f4.uop), 1, 'ew_dt_remint_rev')
dtsrc(u4.uop.add(c3.uop), 1, 'ew_dt_keep')
dtsrc(c3.uop.add(Tensor(5).uop), 1, 'ew_dt_weak')
dtsrc(i4.uop.add(u4.uop), 1, 'ew_dt_cast')
dtsrc(u4.uop.add(cT.uop), 1, 'ew_dt_bool_cast')

# --- THE SECOND CONJUNCT: `promote`'s `t._uop.base.op is Ops.CONST` -------------
# elementwise.py:31-33 is a CONJUNCTION, and every fixture above holds a weak CONST,
# so the second conjunct is never load-bearing. The one CPython-reachable weak tensor
# that is not a CONST is an ALGEBRAIC result, and that is this fixture: `Tensor(3) +
# Tensor(5)` is weakint whose base op is ADD, so promoting THAT against an int32 must
# take the CAST arm -- `weak_dtype(int32)` is weakint, so the weak arm would keep it.
# These two rows print in the port's order (immediately after `ew_dt_bool_cast`) so
# the diff stays a positional one.
#
# `ew_promo_nc` -- the SIGNATURE of that graph -- is deliberately NOT here, and the
# reason is not laziness: the port builds it from a BUFFER of a weak dtype, and
# CPython cannot build that at all. `Tensor.empty(..., dtype=dtypes.weakint)` raises
# `cannot create storage for weak dtype dtypes.weakint` (tinygrad/mixin/creation.py:37),
# so the port's fixture has no CPython counterpart and a row printed here would be
# comparing two different graphs. Measured both ways: this fixture is
# `7 CONST/0 CONST/0 ADD/2 CAST/1 CONST/0 CAST/1 ADD/2 ` and the port's is
# `5 BUFFER/0 ADD/2 CAST/1 BUFFER/0 ADD/2 `. The two DERIVED values below agree,
# which is why they are gates and the count is not.
NC = (Tensor(3) + Tensor(5)).uop + Tensor(7, dtype=dtypes.i32).uop
dtsrc(NC, 0, 'ew_dt_promo_nc')
opat(NC, 0, 'ew_op_promo_nc')

# --- the promotion lattice itself, from dtype.py:193 ----------------------------
row('ew_lud_weakint_int32', least_upper_dtype(dtypes.weakint, dtypes.i32) == dtypes.i32)
row('ew_lud_bool_int32', least_upper_dtype(dtypes.bool, dtypes.i32) == dtypes.i32)
row('ew_lud_weakint_float32', least_upper_dtype(dtypes.weakint, dtypes.f32) == dtypes.f32)
row('ew_lud_int8_uint8', least_upper_dtype(dtypes.i8, dtypes.u8) == dtypes.i16)
row('ew_wd_int32', weak_dtype(dtypes.i32) == dtypes.weakint)
row('ew_wd_float32', weak_dtype(dtypes.f32) == dtypes.weakfloat)
row('ew_wd_bool', weak_dtype(dtypes.bool) == dtypes.bool)
row('ew_weaks', tuple(dtypes.weaks) == (dtypes.weakint, dtypes.weakfloat))
# NOTE ON A ROW THAT IS DELIBERATELY ABSENT: `least_upper_dtype(void, int32)`
# RAISES KeyError in CPython -- void is not in the lattice at all -- while
# fold.bend's `least_upper.of` answers `void`. That is a real divergence and it is
# deliberately NOT a gate row, because a row has no Python value to be compared
# against and a row that restates the port's own answer is worthless. It is recorded
# in the Bend header instead.