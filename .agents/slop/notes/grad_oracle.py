import sys
sys.path.insert(0, '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops
from tinygrad.mixin.gradient import compute_gradient

def C(v, dt=None): return UOp.const(v, dt)

def g_of(g):
  if g is None: return "None"
  if g.op is Ops.NOOP: return "NOOP"
  try: return Tensor(g).numpy().tolist()
  except Exception as e: return f"<{type(e).__name__}>"

def show(name, root, tgts, rg):
  grads = compute_gradient(root, rg, set(tgts))
  print(f"=== {name}  root={root.op.name} nsrc={len(root.src)} ngrads={len(grads)}")
  for k in tgts:
    v = grads.get(k)
    print(f"   grad[{k.op.name} {k.arg}] = {g_of(v)}")

F = dtypes.float
# 1 ADD
a = C(1.0, F); b = C(2.0, F)
show("add", UOp(Ops.ADD, src=(a,b)), [a,b], C(1.0,F))
# 2 MUL
show("mul", UOp(Ops.MUL, src=(a,b)), [a,b], C(1.0,F))
# 3 nested ADD(MUL(a,b), c)
c = C(3.0, F)
show("muladd", UOp(Ops.ADD, src=(UOp(Ops.MUL, src=(a,b)), c)), [a,b,c], C(1.0,F))
# 4 unary family
for nm, op in [("exp2",Ops.EXP2),("log2",Ops.LOG2),("sqrt",Ops.SQRT),("sin",Ops.SIN),("reciprocal",Ops.RECIPROCAL)]:
  show(nm, UOp(op, src=(a,)), [a], C(1.0,F))
# 5 MAX tie and non-tie
show("max_nontie", UOp(Ops.MAX, src=(a,b)), [a,b], C(1.0,F))
show("max_tie", UOp(Ops.MAX, src=(a,a)), [a], C(1.0,F))
# 6 POW
e = C(2.0, F)
show("pow", UOp(Ops.POW, src=(b,e)), [b,e], C(1.0,F))
show("pow_e0", UOp(Ops.POW, src=(b,C(0.0,F))), [b,C(0.0,F)], C(1.0,F))
# 7 CAST
ai = C(1, dtypes.int32)
show("cast", UOp(Ops.CAST, src=(ai,), arg=dtypes.float), [ai], C(1.0,F))
# 8 TRUNC
show("trunc", UOp(Ops.TRUNC, src=(C(1.7,F),)), [C(1.7,F)], C(1.0,F))
# 9 CMPLT -> (None,None)
lt = UOp(Ops.CMPLT, src=(a,b))
show("cmplt", lt, [a,b], C(True,dtypes.bool))
# 10 WHERE
z = C(True, dtypes.bool)
show("where", UOp(Ops.WHERE, src=(z,a,b)), [a,b], C(1.0,F))
# 11 SINK -> ctx.src
show("sink", UOp(Ops.SINK, src=(a,b)), [a,b], UOp(Ops.SINK, src=(C(1.0,F), C(1.0,F))))
# 12 RESHAPE
r0 = C(1.0,F)
print("reshape: SKIPPED -- python asserts len(lgrads)==len(src); rule returns 2 for 1 src")
# 13 EXPAND
print("expand: SKIPPED -- same arity assert")
# 14 BITCAST -> (None,)
show("bitcast", UOp(Ops.BITCAST, src=(ai,), arg=dtypes.float), [ai], C(1.0,F))
# 15 STAGE / CONTIGUOUS_BACKWARD
show("stage", UOp(Ops.STAGE, src=(a,)), [a], C(1.0,F))
# 16 AFTER+STORE clone: AFTER(STORE(dest,val), dest) -> (None, ctx)
d0 = UOp(Ops.STORE_PLACEHOLDER) if False else None
# 17 zero-src node counted in grads (root itself)
show("rootonly", a, [a], C(1.0,F))
# 18 STORE (None, ctx)
show("store", UOp(Ops.STORE, src=(a,b)), [a,b], C(1.0,F))
# 19 REDUCE ADD
big = UOp(Ops.ADD, src=(a,b))
red = UOp(Ops.REDUCE, src=(big,), arg=(Ops.ADD, 1))
show("reduce_add", red, [a,b], C(1.0,F))
# 20 NOOP passthrough is skipped by compute_gradient
noop = UOp(Ops.NOOP, src=())
show("noop", UOp(Ops.ADD, src=(a, noop)), [a], C(1.0,F))
# 21 DETACH is dropped from the walk
print("detach: SKIPPED -- DETACH with 0 srcs has no _shape in python")
# 22 double grad accumulate (k receives two contributions)
x1 = C(1.0,F); x2 = C(2.0,F); x3 = C(3.0,F)
