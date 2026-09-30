import sys
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes
from tinygrad.uop.movement import mop_cleanup

def buf(size=None, image=None):
  return UOp(Ops.BUFFER, src=(UOp(Ops.SPECIAL, arg="x", src=(UOp.const(1),)),),
              arg=ParamArg(slot=0, dtype=dtypes.int32, size=size, image=image))

b4   = buf(size=4)
b0   = buf()
# a BARE CONST: `UOp.const(i)` with no dtype is `dtypes.from_py(i)` = weakint, and a
# weakint CONST has no CAST partner. `UPat.cvar` and `UPat(Ops.CONST)` both need
# `.op is Ops.CONST`, so a dtyped CONST would not match them.
C0, C1, C2, C4 = (UOp.const(i) for i in (0, 1, 2, 4))

# --- rule 0: SHRINK over SHRINK, rank 1 (both marg args CONST)
S1 = UOp(Ops.SHRINK, src=(b4, C2, C2))
S2 = UOp(Ops.SHRINK, src=(S1, C1, C1))
# --- rule 0, rank 2 (both marg args STACK)
B24 = buf(image=(2, 4))
S3 = UOp(Ops.SHRINK, src=(B24, UOp(Ops.STACK, src=(C0, C1)), UOp(Ops.STACK, src=(C1, C1))))
S4 = UOp(Ops.SHRINK, src=(S3, UOp(Ops.STACK, src=(C1, C1)), UOp(Ops.STACK, src=(C1, C1))))

# --- rules 1 + 2
R1 = UOp(Ops.RESHAPE, src=(b4, C4))                                  # shape (4,)
R2 = UOp(Ops.RESHAPE, src=(R1, UOp(Ops.STACK, src=(C4,))))           # shape (4,), a DIFFERENT arg node
R3 = UOp(Ops.RESHAPE, src=(b4, C4))                                  # rule 2 alone

# --- rules 3 + 4
P1 = UOp(Ops.PERMUTE, src=(B24,), arg=(1, 0))
P2 = UOp(Ops.PERMUTE, src=(P1,), arg=(1, 0))
P3 = UOp(Ops.PERMUTE, src=(B24,), arg=(0, 1))

# --- rule 5
bimg = buf(image=(2, 7))
o1 = buf(size=2)
o2 = buf(size=7)
IDX2 = UOp(Ops.INDEX, src=(bimg, o1))
SRC  = UOp(Ops.INDEX, src=(b0, IDX2))
# rule 5's inner pattern `UPat(Ops.INDEX, src=(UPat.var("src"), UPat(Ops.CONST)))`
# has strict_length=True, so each stacked element must be a TWO-src INDEX. And
# `stk.shape == src.shape` needs `buf.shape[0] == 2` exactly, because
# `_shape`'s STACK arm is `(len(src),) + self.src[0].shape`.
E0 = UOp(Ops.INDEX, src=(bimg, C0))
E1 = UOp(Ops.INDEX, src=(bimg, C1))
STK = UOp(Ops.STACK, src=(E0, E1))

# --- rule 6
SS  = UOp(Ops.STACK, src=(C0, C1, C2))
IX2 = UOp(Ops.INDEX, src=(SS, C1))
IX3 = UOp(Ops.INDEX, src=(SS, C1, C0))
IX5 = UOp(Ops.INDEX, src=(SS, C0, C0, C1))

# --- rule 7
J1 = UOp(Ops.INDEX, src=(b4, C0))
J2 = UOp(Ops.INDEX, src=(J1, C1))
J3 = UOp(Ops.INDEX, src=(UOp(Ops.INDEX, src=(SS, C1)),))   # INDEX(STACK, CONST) as the inner

# --- rule 8
K1 = UOp(Ops.INDEX, src=(B24, o1))
K2 = UOp(Ops.INDEX, src=(K1, o2))
K3 = UOp(Ops.INDEX, src=(UOp(Ops.INDEX, src=(B24, STK)), o2))   # a STACK as the index arg

def rw(nm, u):
  r = mop_cleanup.rewrite(u)
  print(f"rw_{nm:16} {'None' if r is None else str(r).splitlines()[0]}")

print("== shapes ==")
print("R1", R1.shape, "R2", R2.shape, "STK", STK.shape, "bimg", bimg.shape)
print("== rewrites ==")
rw("shrink1", S2)
rw("shrink2", S4)
rw("reshape_merge", R2)
rw("reshape_noop", R3)
rw("permute_merge", P2)
rw("permute_noop", P3)
rw("stack_idx", STK)
rw("const_idx2", IX2)
rw("const_idx3", IX3)
rw("const_idx5", IX5)
rw("idx_idx", J2)
rw("idx_shaped", K2)
rw("idx_shaped_stack", K3)
rw("unclaimed", UOp(Ops.ADD, src=(C0, C1)))
print("== margs ==")
for nm, x, s in (("r1", S1, S2), ("r2", S3, S4)):
  m = tuple((o + p, n) for (o, _), (p, n) in zip(x.marg, s.marg))
  enc = 0
  for (o, n) in m: enc = enc * 100 + o * 10 + n
  print(f"marg_{nm} x={x.marg} s={s.marg} merged={m} enc={enc} n={len(m)}")
  print(f"mop_{nm}", s.src[0]._mop(Ops.SHRINK, m), " simplify_is_self=",
        s.src[0]._mop(Ops.SHRINK, m).src[1].op)
print("== the table ==")
for i, (p, _) in enumerate(mop_cleanup.patterns):
  print(f"  {i} op={p.op.name} len_src={'any' if p.src is None or isinstance(p.src, UPat) else len(p.src[0])}"
        f" rej={sorted(o.name for o in p.early_reject)}")
print("n_patterns", len(mop_cleanup.patterns))
