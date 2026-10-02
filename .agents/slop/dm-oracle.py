from tinygrad.uop.ops import UOp, Ops
from tinygrad.dtype import dtypes
from tinygrad.uop.divandmod import div_and_mod_symbolic

_seen = {}
def sh(u):
  if u.op is Ops.CONST: return f"C({u.val})"
  if u.op is Ops.PARAM: return "P" + str(u.arg.name)
  if u.op is Ops.CAST: return sh(u.src[0])
  ss = [s for s in u.src if s.op is not Ops.CAST]
  return u.op.name + ("(" + ",".join(sh(s) for s in ss) + ")" if ss else "")

def show(nm, node):
  try:
    r = div_and_mod_symbolic.rewrite(node)
  except Exception as e:
    print(f"{nm:<9} {sh(node):<40} -> RAISED {type(e).__name__}")
    return
  print(f"{nm:<9} {sh(node):<40} -> {'' if r is None else sh(r):<42} dt={node.dtype.name}")

def val(nm, node):
  """the number the rewrite DENOTES -- a value row, not a restatement"""
  try:
    r = div_and_mod_symbolic.rewrite(node)
  except Exception as e:
    print(f"{nm:<9} VALUE -> RAISED {type(e).__name__}")
    return
  if r is None:
    print(f"{nm:<9} VALUE -> none")
    return
  print(f"{nm:<9} VALUE in={node.simplify().render():<8} out={r.simplify().render()}")

I, W = dtypes.i32, dtypes.weakint
C = lambda v: UOp.const(v, W)
xw = UOp.variable("x", 0, 100, dtype=W)
xi = UOp.variable("i", 0, 100, dtype=I)
p4 = UOp.variable("p", 0, 12, multiple_of=4, dtype=W)
p3 = UOp.variable("q", 0, 12, multiple_of=3, dtype=W)
p1 = UOp.variable("z", 0, 12, multiple_of=1, dtype=W)
w  = UOp.variable("w", 0, 100, dtype=W)

print("== TREE ROWS (a PARAM numerator, so the shape survives) ==")
show("t0_a",   (xw // C(3) + C(5)) // C(7))
show("t0_b",   (C(5) + xw // C(3)) // C(7))
show("t0_c",   (xw // C(3) + C(10)) // C(7))   # rule 1 ALSO fires -> first-wins
show("t0_neg", (xw // C(3) + C(5)) // C(-7))
show("t0_d0",  (xw // C(3) + C(5)) // C(0))
show("t1_fd",  (xw + C(10)) // C(7))
show("t1_fm",  (xw + C(10)) % C(7))
show("t1_same",(xw + C(3)) // C(7))
show("t1_swap",(C(10) + xw) // C(7))
show("t1_d1",  (xw + C(10)) // C(1))
show("t1_dn",  (xw + C(10)) // C(-7))
show("t1_d0",  (xw + C(10)) // C(0))
show("t1_i",   (xi + C(10)) // C(7))
show("t2_cst", C(6) // C(4))
show("t2_cst2",C(6) % C(4))
show("t2_cn",  C(-7) // C(4))
show("t2_cm",  C(-7) % C(4))
show("t2_pm",  p4 % C(4))
show("t2_p1",  p1 % C(1))
show("t2_pd",  p4 // C(4))
show("t2_p3",  p3 % C(4))
show("t2_var", w % C(4))
show("n_3src", UOp(Ops.FLOORDIV, (xw + C(10), C(7), C(1))))
print()
print("== VALUE ROWS (a CONST numerator, so simplify() gives a NUMBER) ==")
for xv in (1000, -1000, 21, -21, 7, -7, 0):
  x = C(xv)
  val(f"v0_{xv}",  (x // C(3) + C(5)) // C(7))
  val(f"v0c_{xv}", (x // C(3) + C(10)) // C(7))
  val(f"v1_{xv}",  (x + C(10)) // C(7))
  val(f"v1m_{xv}", (x + C(10)) % C(7))
  val(f"v1n_{xv}", (x + C(10)) // C(-7))
  val(f"v1d1_{xv}",(x + C(10)) // C(1))
  val(f"v2n_{xv}", (x // C(4)))
  val(f"v2m_{xv}", (x % C(4)))
  val(f"v2c_{xv}", C(-7) // C(4))
  val(f"v2r_{xv}", C(-7) % C(4))
