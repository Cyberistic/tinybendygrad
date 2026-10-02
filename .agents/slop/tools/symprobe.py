from tinygrad.uop.ops import UOp, Ops, PatternMatcher, UPat, GroupOp
from tinygrad.dtype import dtypes, Invalid, InvalidType
from tinygrad.uop.symbolic import (invalid_pat, invalid_gate, bare_const, pm_remove_invalid, fold_const_alu)

PORTED = PatternMatcher([
  (invalid_pat.broadcast(), lambda i: i),
  (UPat(GroupOp.Unary|{Ops.CAST, Ops.BITCAST}, src=(invalid_pat,)), lambda i: i),
  (invalid_pat.where(UPat(), UPat()), lambda i: i),
  (invalid_gate.where(UPat.var("a"), UPat.var("b")), lambda cond,x,i,a,b: cond.where(x.where(a,b), i)),
  (UPat(Ops.STORE, src=(UPat(Ops.INDEX, src=(UPat(), invalid_pat), allow_any_len=True).or_casted(), UPat())), lambda i: UOp(Ops.NOOP)),
  (UPat(Ops.LOAD, src=(UPat(Ops.INDEX, src=(UPat(), invalid_pat), allow_any_len=True).or_casted(),), allow_any_len=True, name="x"),
   lambda x,i: x.src[1] if len(x.src) > 1 else x.const_like(0)),
  (UPat({Ops.ADD, Ops.XOR, Ops.OR}, src=[UPat.var("x"), UPat.const(0)]), lambda x: x),
  (UPat.var("x") // UPat.var("x"), lambda x: x.const_like(1)),
  ((UPat.var("x") ^ UPat.var("y")) ^ UPat.var("y"), lambda x,y: x),
  (UPat(GroupOp.ALU-{Ops.THREEFRY}, src=bare_const, name="a"), fold_const_alu),
  ((UPat.var("x") * UPat.var("x")).reciprocal(), lambda x: x.reciprocal()*x.reciprocal()),
  (UPat(Ops.GROUP, src=(UPat.var("x"),)), lambda x: x),
  (UPat((Ops.SINK, Ops.GROUP), name="root"),
   lambda root: UOp(root.op, src=tuple([y for x in root.src for y in (x.src if x.op in {Ops.NOOP,Ops.STACK,Ops.SINK,Ops.GROUP} else (x,))]),
                  arg=root.arg)
     if any(x.op in {Ops.NOOP,Ops.STACK,Ops.SINK,Ops.GROUP} for x in root.src) else None),
])

REMOVE_FROM_SINK_LIKE = {Ops.NOOP, Ops.STACK, Ops.SINK, Ops.GROUP}
def sh(u):
  if u.op is Ops.CONST:
    a = u.arg
    if isinstance(a, InvalidType): return "bad"
    if isinstance(a, bool): return "bt" if a else "bf"
    return ("c%d" % a) if a >= 0 else ("m%d" % -a)
  if u.op is Ops.PARAM: return {dtypes.weakint:"x", dtypes.bool:"xb", dtypes.weakfloat:"xf", dtypes.i32:"xi"}[u.dtype]
  if u.op in (Ops.CAST, Ops.BITCAST): return "(%s:%s %s)" % (u.op.name.lower(), u.arg.name, " ".join(sh(s) for s in u.src))
  return "(%s%s)" % (u.op.name.lower(), "".join(" "+sh(s) for s in u.src))

C = lambda v: UOp.const(v, dtypes.weakint)
x = UOp.variable("x", 0, 100)
xb = UOp.variable("xb", 0, 1, dtype=dtypes.bool)
print("dt of bare const:", C(7).dtype, " bad:", UOp.const(Invalid).dtype, " bt:", UOp.const(True).dtype)
print("dt of x/xb:", x.dtype, xb.dtype, " int32 const:", sh(UOp.const(7, dtypes.i32)))
for nm, u in [
  ("add0", C(7) + C(0)),
  ("div1", C(7) // C(7)),
  ("div2", C(7) // C(2)),
  ("xorb", (C(5) ^ C(7)) ^ C(7)),
  ("xorb0", (C(5) ^ C(7)) ^ C(9)),
  ("alu", C(5) + C(6)),
  ("alu3f", C(5) * C(6)),
  ("pow", C(2) ** C(3)),
  ("recip", (x*x).reciprocal()),
  ("group", UOp(Ops.GROUP, (C(7),))),
  ("sink", UOp(Ops.GROUP, (UOp(Ops.STACK, (C(7), C(2))), C(3)))),
  ("castbad", UOp(Ops.CAST, (UOp.const(Invalid),), dtypes.bool)),
  ("store", UOp(Ops.STORE, (UOp(Ops.INDEX, (C(2), UOp.const(Invalid))), C(9)))),
]:
  r = PORTED.rewrite(u)
  print("%-8s %-34s -> %-30s dt=%s" % (nm, sh(u), "norewrite" if r is None else sh(r), u.dtype))
