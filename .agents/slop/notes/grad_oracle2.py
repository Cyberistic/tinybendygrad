import sys
sys.path.insert(0, '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.mixin.gradient import compute_gradient, pm_gradient

def C(v, dt=None): return UOp.const(v, dt)
F = dtypes.f32

def g_of(g):
  if g is None: return "None"
  if g.op is Ops.NOOP: return "NOOP"
  try: return Tensor(g).numpy().tolist()
  except Exception as e: return f"<{type(e).__name__}>"

def show(name, root, tgts, rg):
  grads = compute_gradient(root, rg, set(tgts))
  print(f"=== {name}  root={root.op.name} nsrc={len(root.src)} ngrads={len(grads)}")
  for k in tgts:
    print(f"   grad = {g_of(grads.get(k))}")

# TWO CONTRIBUTIONS to one node: ADD(MUL(x1,x2), MUL(x1,x3))
x1 = C(1.0,F); x2 = C(2.0,F); x3 = C(3.0,F)
show("two_contrib", UOp(Ops.ADD, src=(UOp(Ops.MUL,src=(x1,x2)), UOp(Ops.MUL,src=(x1,x3)))), [x1,x2,x3], C(1.0,F))

# pm_gradient rewrite directly -- the rule table, arity and all
print()
for nm, u in [("ADD", UOp(Ops.ADD, src=(x1,x2))),
              ("MUL", UOp(Ops.MUL, src=(x1,x2))),
              ("CAST", UOp(Ops.CAST, src=(C(1,dtypes.i32),), arg=F)),
              ("TRUNC", UOp(Ops.TRUNC, src=(x1,))),
              ("CMPLT", UOp(Ops.CMPLT, src=(x1,x2))),
              ("STORE", UOp(Ops.STORE, src=(x1,x2))),
              ("BITCAST", UOp(Ops.BITCAST, src=(C(1,dtypes.i32),), arg=F)),
              ("SINK", UOp(Ops.SINK, src=(x1,x2))),
              ("STAGE", UOp(Ops.STAGE, src=(x1,))),
              ("RESHAPE", UOp(Ops.RESHAPE, src=(x1,), arg=(1,))),
              ("EXPAND", UOp(Ops.EXPAND, src=(x1,), arg=(1,))),
              ("RECIPROCAL", UOp(Ops.RECIPROCAL, src=(x1,))),
              ("SQRT", UOp(Ops.SQRT, src=(x1,))),
              ("EXP2", UOp(Ops.EXP2, src=(x1,))),
              ("LOG2", UOp(Ops.LOG2, src=(x1,))),
              ("SIN", UOp(Ops.SIN, src=(x1,))),
              ("MAX", UOp(Ops.MAX, src=(x1,x2))),
              ("POW", UOp(Ops.POW, src=(x1,x2))),
              ("WHERE", UOp(Ops.WHERE, src=(C(True,dtypes.bool),x1,x2))),
              ("COPY", UOp(Ops.COPY, src=(x1,), arg='METAL')),
              ]:
  try:
    r = pm_gradient.rewrite(u, ctx=x1)
    print(f"{nm:14} nsrc={len(u.src)} -> {None if r is None else len(r)} {[g_of(v) for v in r] if r else None}")
  except Exception as e:
    print(f"{nm:14} nsrc={len(u.src)} -> RAISES {type(e).__name__}: {e}")

# the AFTER family -- the name rebind
print()
buf = UOp(Ops.BUFFER, src=(), arg=__import__('tinygrad').uop.ops.ParamArg(0, F, 4, device='PYTHON'))
val = C(1.0,F)
st = UOp(Ops.STORE, src=(buf,val))
af = UOp(Ops.AFTER, src=(buf, st))
for nm, u, ctx in [("AFTER(STORE(dest,dest))", af, x1),
                   ("AFTER(STORE(dest,other))", UOp(Ops.AFTER, src=(buf, UOp(Ops.STORE, src=(buf, UOp(Ops.ADD, src=(x1,x2)))))), x1)]:
  r = pm_gradient.rewrite(u, ctx=ctx)
  print(f"{nm:28} -> {None if r is None else [g_of(v) for v in r]}")

# what does an ORDERING-ONLY after look like: AFTER(d2, STORE(d1, v)) -- dest != t
d2 = UOp(Ops.BUFFER, src=(), arg=__import__('tinygrad').uop.ops.ParamArg(1, F, 4, device='PYTHON'))
after2 = UOp(Ops.AFTER, src=(d2, UOp(Ops.STORE, src=(buf,val))))
r = pm_gradient.rewrite(after2, ctx=x1)
print("AFTER(STORE(t,dest)) ordering-only ->", None if r is None else [g_of(v) for v in r])
print("buf_uop(d2) is buf_uop(buf)?", d2.buf_uop is buf.buf_uop)