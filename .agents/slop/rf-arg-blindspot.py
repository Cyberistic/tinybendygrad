#!/usr/bin/env python3
"""rf-arg-blindspot.py -- are M1 and M4 fixable with a fixture, or unfixable?

M1 is `remove_noop_afters` passing `ANone` instead of its own node's arg.
M4 is `ct_8` (the deviceless-MSTACK arm) doing the same.  Both moved 0 rows.
The honest answer differs per op, so it is MEASURED rather than assumed:

  * if CPython admits an AFTER / an MSTACK with a NON-None arg, then M1/M4 are a
    REQUEST FOR A FIXTURE -- the zero is my fixture's fault and a row can be had.
  * if CPython admits no such node, then `ANone` is the CORRECT answer at that
    site, the two spellings are the same function over every reachable input, and
    the zero is a THEOREM that no fixture can break.

`ct_8` has a second, independent reason to move nothing: it only fires when
`pm_const_buffer_folding` claims the node, so its reachability is measured too."""
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops, ParamArg, KernelInfo, AxisType
from tinygrad.dtype import dtypes, AddrSpace, Invalid
from tinygrad.schedule.indexing import BufferizeOpts
from tinygrad.schedule import rangeify as R

IDX = dtypes.weakint
def C(n): return UOp.const(n, IDX)
def B(s=0, a=AddrSpace.GLOBAL): return UOp(Ops.BUFFER, arg=ParamArg(s, dtypes.int32, 4, addrspace=a))
def claims(pm, u): return len([1 for pat, f in pm.patterns if pat.match(u, {})])

b4, c0, c1, c2, c4 = B(0), C(0), C(1), C(2), C(4)
r0 = UOp.range(4, 0)
sh0 = UOp(Ops.SHRINK, (b4, c0, c4))
sh1 = UOp(Ops.SHRINK, (b4, c1, c2))

print("### can an MSTACK carry a non-None arg?")
for name, a in (("ANone", None), ("ARange", UOp.range(4,0).arg), ("KernelInfo", KernelInfo())):
  try:
    m = UOp(Ops.MSTACK, (sh1, sh0), arg=a)
    print(f"  MSTACK arg={name:12} OK -> arg is {m.arg!r}")
  except Exception as e:
    print(f"  MSTACK arg={name:12} REJECTED {type(e).__name__}: {e}")

print("### can an AFTER carry a non-None arg?")
e0 = UOp(Ops.END, (UOp(Ops.NOOP, (c0,)),))
for name, a in (("ANone", None), ("KernelInfo", KernelInfo()),
                ("ParamArg", ParamArg(0, dtypes.int32, 4, addrspace=AddrSpace.GLOBAL))):
  try:
    x = UOp(Ops.AFTER, (b4, e0), arg=a)
    print(f"  AFTER  arg={name:12} OK -> arg is {x.arg!r}")
  except Exception as e:
    print(f"  AFTER  arg={name:12} REJECTED {type(e).__name__}: {e}")

print("### the arg is None for EVERY node the two rules rebuild, over the fixture")
mst = UOp(Ops.MSTACK, (sh1, sh0))
after = UOp(Ops.AFTER, (b4, e0, UOp(Ops.END, (UOp(Ops.NOOP, (c1,)),)), UOp(Ops.END, (b4,))))
print("  mstack.arg is None =", int(mst.arg is None))
print("  after.arg  is None =", int(after.arg is None))
_raf = R.remove_noop_afters(after)
print("  remove_noop_afters(after) is None =", int(_raf is None),
      "| (so this AFTER is NOT rebuilt, and M1 needs a node that DOES shrink)")

# the node that DOES shrink: AFTER(b4, e0, e1, ek), exactly the Bend fixture's `af`
nx = UOp(Ops.NOOP, (c0,))
e_nx = UOp(Ops.END, (nx,))
ek = UOp(Ops.END, (b4,))
af_shrink = UOp(Ops.AFTER, (b4, e0, e_nx, ek))
_raf2 = R.remove_noop_afters(af_shrink)
print("  remove_noop_afters(af_shrink) is None =", int(_raf2 is None),
      "| arg is None =", int(_raf2 is not None and _raf2.arg is None),
      "| nsrc =", 0 if _raf2 is None else len(_raf2.src))
# and with a NON-None arg: does the rebuild preserve it?  (M1's missing fixture)
af_kern = UOp(Ops.AFTER, (b4, e0, e_nx, ek), arg=KernelInfo())
_raf3 = R.remove_noop_afters(af_kern)
print("  remove_noop_afters(af_kern) is None =", int(_raf3 is None),
      "| arg is own Kernel =", int(_raf3 is not None and _raf3.arg == KernelInfo()),
      "| nsrc =", 0 if _raf3 is None else len(_raf3.src))

print("### ct_8 reachability: does pm_const_buffer_folding EVER claim the fixture's MSTACK?")
stg2 = UOp(Ops.STAGE, (b4, r0), arg=BufferizeOpts(device='CPU'))
ix_stg = UOp(Ops.INDEX, (stg2, r0))
mst_ix = UOp(Ops.MSTACK, (ix_stg, sh0))
for nm, u in (("mst", mst), ("mst_ix", mst_ix), ("after", after), ("stg2", stg2),
              ("ix_stg", ix_stg), ("b4", b4)):
  print(f"  claim_{nm:7} =", claims(R.pm_const_buffer_folding, u))
print("  ct8 patterns:", [i for i, (pat, f) in enumerate(R.pm_const_buffer_folding.patterns)])