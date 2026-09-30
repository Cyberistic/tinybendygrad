import sys
sys.path.insert(0, '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
from tinygrad.dtype import dtypes, least_upper_dtype, strong_dtype, weak_dtype
from tinygrad.uop import Ops, GroupOp
from tinygrad.uop.ops import UOp
from tinygrad.uop import weak as W

def sh(x):
  return "None" if x is None else (x.render().replace("\n", " ").replace("  ", "") if isinstance(x, UOp) else str(x))

K = lambda b: UOp.const(b)
def ADD(a, b): return UOp(Ops.ADD, src=(a, b))
def MUL(a, b): return UOp(Ops.MUL, src=(a, b))

# ---- fixture A: a weak NON-const src beside a concrete half ---------------
wl  = ADD(K(3), K(5))                            # ADD, dtype weakint, not a CONST
h1  = UOp.const(1.0, dtypes.half)
print("A wl      ", wl.dtype, [s.dtype for s in wl.src])
u   = MUL(wl, h1)
print("A u.dtype  ", u.dtype, "| src dts", [s.dtype for s in u.src])
print("A dts      ", W.derived_dtypes(u, u.src))
r = W.commit_weak_srcs(u)
print("A commit   ", sh(r), "|", None if r is None else r.dtype, "| src dts", None if r is None else [s.dtype for s in r.src])

# ---- fixture B: the STORE rule, mixed ------------------------------------
val  = K(4.0)                                    # weakfloat
st   = UOp(Ops.STORE, src=(h1, val))
print("B store dt ", [s.dtype for s in st.src])
rb = st.replace(src=(st.src[0], st.src[1].ccast(st.src[0].dtype), *st.src[2:]))
print("B rewritten", [s.dtype for s in rb.src], "| same node?", rb is st)

# ---- fixture C: uncast_const ---------------------------------------------
hn   = MUL(UOp.const(1.0, dtypes.half), UOp.const(3.0, dtypes.half))  # half, not a CAST
wc   = UOp.const(2.0, dtypes.half)               # CAST(CONST(weakfloat), half)
u2   = ADD(hn, wc)
print("C src ops  ", [s.op for s in u2.src], [s.dtype for s in u2.src])
print("C promo    ", W.promo_dtype(u2.src), "| u.dtype", u2.dtype)
rc = W.uncast_const(u2)
print("C uncast   ", None if rc is None else [s.dtype for s in rc.src], "| same node?", rc is u2)

# ---- fixture D: derived_dtypes on a non-broadcastable --------------------
s3  = UOp(Ops.LOAD, src=(UOp.const(4),))
print("D load dts ", W.derived_dtypes(s3, s3.src), "| u.dtype", s3.dtype)

# ---- fixture E: derived_dtypes None on a weak result ---------------------
s4  = ADD(K(3), K(5))                            # dtype weakint
print("E dts      ", W.derived_dtypes(s4, s4.src), "| meet weak?", W.promo_dtype(s4.src) in dtypes.weaks)

# ---- the lattice rows the gate pins --------------------------------------
for pair in [(dtypes.weakint, dtypes.weakint), (dtypes.weakint, dtypes.weakfloat),
             (dtypes.weakfloat, dtypes.weakfloat), (dtypes.weakint, dtypes.int32),
             (dtypes.weakint, dtypes.half), (dtypes.weakfloat, dtypes.half)]:
  print("L", pair[0].name, "^", pair[1].name, "=", least_upper_dtype(*pair).name)
for d in [dtypes.weakint, dtypes.weakfloat, dtypes.int32, dtypes.half, dtypes.bool]:
  print("S", d.name, "strong=", strong_dtype(d).name, "weak=", weak_dtype(d).name)