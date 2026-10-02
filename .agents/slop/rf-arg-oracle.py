#!/usr/bin/env python3
"""rf-arg-oracle.py -- the `py=` values for the rows that gate the `mp_replace`
ARG repair in rangeify.bend.

WHY THIS FILE EXISTS.  `movement.bend`'s `mp_replace` was widened by
e959ece3798f ("fix movement.bend: the port (not Python) had the inversion") from
`(op, ar, self, src)` to `(op, arg, ar, self, src)`, because `UOp.replace`
(ops.py:252) takes `arg` as a kwarg: `new_args = (kwargs.pop("op", self.op),
kwargs.pop("src", self.src), kwargs.pop("arg", self.arg), ...)`.  Four call
sites in rangeify.bend were left on the 4-arg form, so the file stopped
compiling.  The repair passes each rule's OWN node's arg.

The repair is NOT provable by the compiler going quiet: every node the four
rules can reach in rangeify.bend's fixture is an AFTER, an MSTACK or a CALL, and
ALL of them are given `O.ANone` in the fixture.  So a row of the shape
`eq_arg(rebuilt_arg, original_arg)` degenerates to `eq_arg(ANone, ANone)` --
true whether the port preserves the arg or hardcodes `ANone`.  These rows
therefore need a node whose arg is NOT None, and a CALL's arg in CPython is a
`KernelInfo`, which is NOT None.

`KernelInfo()` is the same value as Bend's `O.KernelInfo.of()`
(`KernelInfo{"test", Nil{}, None{}, 0}` == name='test', applied_opts=(),
opts_to_apply=None, beam=0), so the two sides are comparable.

Four facts per rewrite, plus the answer as one string: the claim count (first
wins -- pm_add_buffers has several CALL patterns), the arity, whether the
stripped src0 is b4, and whether the arg is the node's OWN.  A row that only
counted srcs could not see the repair at all."""
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, ParamArg, KernelInfo, AxisType
from tinygrad.dtype import dtypes, AddrSpace, Invalid
from tinygrad.schedule.indexing import BufferizeOpts
from tinygrad.schedule import rangeify as R

IDX = dtypes.weakint
def C(n): return UOp.const(n, IDX)
def B(n=4, a=AddrSpace.GLOBAL, s=0): return UOp(Ops.BUFFER, arg=ParamArg(s, dtypes.i32, n, addrspace=a))

c0, c4 = C(0), C(4)
b4 = B(4, AddrSpace.GLOBAL, 0)
r0 = UOp.range(4, 0)
stg2 = UOp(Ops.STAGE, (b4, r0), arg=BufferizeOpts(device='CPU'))
ix_stg = UOp(Ops.INDEX, (stg2, r0))
rs = UOp(Ops.RESHAPE, (b4, c4))

# CLIK: the fixture's CALLI shape (CALL(IXSTG, RS)) but carrying a REAL Kernel
# arg instead of None, so the arg is observable.  `estimates` is not in Bend's
# KernelInfo, which is the documented NOT-PORTED field, so it stays default.
KERN = KernelInfo()
clik = UOp(Ops.CALL, (ix_stg, rs), arg=KERN)
# CLIK0: the same node with NO arg -- the negative that proves the rows are not
# passing because every CALL answers the same thing.
clik0 = UOp(Ops.CALL, (ix_stg, rs))

def claims(pm, u): return len([1 for pat, f in pm.patterns if pat.match(u, {})])
def n(x): return 0 if x is None else 1

def fact(u, res, label):
  """the four facts, as ONE line"""
  if res is None: return f"{label} = None"
  return (f"{label} = op_is_call={int(res.op is Ops.CALL)} nsrc={len(res.src)} "
          f"src0_is_b4={int(res.src[0] is b4)} arg_is_own_kernel={int(res.arg == KERN)} "
          f"arg_is_none={int(res.arg is None)} is_self={int(res is u)}")

print("### CLAIM COUNTS (first wins -- pm_add_buffers has several CALL patterns)")
print("ab_claim_clik =", claims(R.pm_add_buffers, clik))
print("nic_claim_clik =", claims(R.pm_no_indexing_calls, clik))

print("### ab_7 -- drop RESHAPEs on KERNEL, rangeify.py:267")
print("ab7_clik_own  =", fact(clik, R.pm_add_buffers.rewrite(clik), "ab7_clik"))
print("ab7_clik0_own =", fact(clik0, R.pm_add_buffers.rewrite(clik0), "ab7_clik0"))
# the arg survives as the SAME OBJECT, not merely an equal one
_ab7 = R.pm_add_buffers.rewrite(clik)
print("ab7_clik_arg_is_object =", int(_ab7 is not None and _ab7.arg is KERN))
# and a port that hardcoded ANone would answer this instead:
print("ab7_clik_arg_would_be_none =", int(_ab7 is not None and _ab7.arg is None))

print("### no_indexing_calls -- rangeify.py:143-158")
print("nic_clik_own  =", fact(clik, R.pm_no_indexing_calls.rewrite(clik), "nic_clik"))
_nic = R.pm_no_indexing_calls.rewrite(clik)
print("nic_clik_arg_is_object =", int(_nic is not None and _nic.arg is KERN))

print("### the OTHER two repaired sites: the arg is genuinely None there")
# remove_noop_afters (rangeify.py:251) and ct_8 (rangeify.py:128) rebuild an
# AFTER and an MSTACK, and both have arg=None in CPython.  So `ANone` is the
# RIGHT answer at those two sites -- and a Bend row there is `eq_arg(ANone,
# ANone)`, a tautology.  Reported as a blind spot, NOT closed with a row.
n0 = UOp(Ops.NOOP)
nx = UOp(Ops.NOOP, (c0,))
e_n0 = UOp(Ops.END, (n0,))
e_nx = UOp(Ops.END, (nx,))
# the SAME `after` fixture rf-rows.py uses, so this row is comparable with its rows
af = UOp(Ops.AFTER, (b4, e_n0, e_nx, UOp(Ops.END, (b4,))))
sh0 = UOp(Ops.SHRINK, (b4, C(0), c4))
mst = UOp(Ops.MSTACK, (sh0, UOp(Ops.SHRINK, (b4, C(1), C(2)))))
_raf = R.remove_noop_afters(af)
print("raf_after_arg_is_none =", int(_raf.arg is None), "| op_is_AFTER =", int(_raf.op is Ops.AFTER))
print("mstack_arg_is_none =", int(mst.arg is None))
print("ct8_claim_mstack =", claims(R.pm_const_buffer_folding, mst))