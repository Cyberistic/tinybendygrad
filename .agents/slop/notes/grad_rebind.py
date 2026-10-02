import sys
sys.path.insert(0, '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
from tinygrad import dtypes
from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.mixin.gradient import pm_gradient, compute_gradient
F = dtypes.f32

def buf(slot): return UOp(Ops.BUFFER, src=(), arg=ParamArg(slot, F, 4, device='PYTHON'))
def gate(): return UOp(Ops.CALL, src=(), arg=None)

b = buf(0)
g = gate()
after_wrap = UOp(Ops.AFTER, src=(b, g))
val = UOp.const(1.0, F)

print("=== THE NAME-REBIND FIXTURE ===")
print("dest = AFTER(buf, gate); t = buf.  dest is t?", after_wrap is b)
print("dest.buf_uop is t.buf_uop?", after_wrap.buf_uop is b.buf_uop)
u = UOp(Ops.AFTER, src=(after_wrap, UOp(Ops.STORE, src=(b, val))))
r = pm_gradient.rewrite(u, ctx=UOp.const(1.0, F))
print("rewrite ->", r)
print("  (None means NO RULE FIRED -- tags 28 skip, 29 skips on identity, 30 walks and fails)")
for i, (op, pats) in enumerate(pm_gradient.pdict.items()):
  for p in pats:
    if op is Ops.AFTER:
      pass
# which tags claim it?
from tinygrad.uop.ops import UPat
claims = []
k = 0
for op, pats in pm_gradient.pdict.items():
  for (pat, fxn, rej) in pats:
    if op is not u.op: k += 1; continue
    if op is Ops.AFTER:
      try:
        v = pat.match(u)
        if v is not None: claims.append((k, sorted(x.name for x in v)))
      except Exception as e: claims.append((k, f"ERR {e}"))
    k += 1
print("AFTER tags claiming this node:", claims)

print()
print("=== with the identity check REMOVED, tag 29 would claim it ===")
u2 = UOp(Ops.AFTER, src=(after_wrap, UOp(Ops.STORE, src=(UOp.const(1.0,F), val))))
claims2 = []
k = 0
for op, pats in pm_gradient.pdict.items():
  for (pat, fxn, rej) in pats:
    if op is u2.op:
      v = pat.match(u2)
      if v is not None: claims2.append(k)
    k += 1
print("AFTER tags claiming a DIFFERENT node:", claims2)

print()
print("=== other rule semantics ===")
a = UOp.const(1.0, F); b2 = UOp.const(2.0, F)
print("a>b ->", (UOp(Ops.CMPLT, src=(a,b2))).op.name, "(MAX rule builds this)")
print("a.eq(b) ->", UOp(Ops.CMPNE, src=(a,b2)).op.name)
print("where ->", UOp(Ops.WHERE, src=(UOp.const(True,dtypes.bool), a, b2)).op.name)
print("CAST const_like: ret.src[0].dtype for a CAST ->", UOp(Ops.CAST, src=(UOp.const(1,dtypes.i32),), arg=F).src[0].dtype)
print("POW grads:", [str(x)[:40] for x in pm_gradient.rewrite(UOp(Ops.POW, src=(b2,a)), ctx=a)])
print("MAX grads:", [str(x)[:40] for x in pm_gradient.rewrite(UOp(Ops.MAX, src=(a,b2)), ctx=a)])
print("RECIP grads:", [str(x)[:60] for x in pm_gradient.rewrite(UOp(Ops.RECIPROCAL, src=(a,)), ctx=a)])
print("SIN grads:", [str(x)[:80] for x in pm_gradient.rewrite(UOp(Ops.SIN, src=(a,)), ctx=a)])
print("SQRT grads:", [str(x)[:60] for x in pm_gradient.rewrite(UOp(Ops.SQRT, src=(a,)), ctx=a)])
print("LOG2 grads:", [str(x)[:80] for x in pm_gradient.rewrite(UOp(Ops.LOG2, src=(a,)), ctx=a)])
print("EXP2 grads:", [str(x)[:60] for x in pm_gradient.rewrite(UOp(Ops.EXP2, src=(a,)), ctx=a)])
print("TRUNC grads:", [str(x)[:60] for x in pm_gradient.rewrite(UOp(Ops.TRUNC, src=(a,)), ctx=a)])
print("WHERE grads:", [str(x)[:60] for x in pm_gradient.rewrite(UOp(Ops.WHERE, src=(UOp.const(True,dtypes.bool),a,b2)), ctx=a)])