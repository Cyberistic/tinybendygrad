#!/usr/bin/env python3
# dd-fresh.py -- CALL CPython and print, for each `l2i` fixture, the nodes that
# were FRESHLY interned inside its window (this is what the `<nm>n=` row counts)
# with their repr, so a port/oracle `n` disagreement can be attributed to a
# specific node instead of guessed at.
#
# imports dd-oracle for its instrumentation (PROMO + ORDER + ucache patching)
# so this file cannot disagree with the real oracle about what "fresh" means.
import sys
sys.path.insert(0, '.')
import importlib.util
spec = importlib.util.spec_from_file_location("ddoracle", ".agents/slop/dd-oracle.py")
DDO = importlib.util.module_from_spec(spec)
sys.modules["ddoracle"] = DDO
spec.loader.exec_module(DDO)   # runs the patching, not main()

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass
ORDER = DDO.ORDER
kept = DDO.kept

want = sys.argv[1:] or ["lg1", "lg2", "lg3", "lg4", "lg5", "lg6", "lg7", "lg8",
                        "lg9", "lga", "lgb", "lge", "lgu"]
for nm, op, dt, xdt, n in DDO.L2I():
    if nm not in want:
        continue
    w = DDO.ws(xdt, n)
    b = len(ORDER)
    try:
        r = DDO.DD.l2i(op, dt, *w)
    except Exception as e:
        print("%s REFUSED %s" % (nm, type(e).__name__))
        continue
    if not isinstance(r, tuple):
        r = (r,)
    fresh = kept(ORDER[b:])
    print("=== %s  n=%d   answer=%s" % (nm, len(fresh), DDO.tree(r[0])))
    for i, u in enumerate(fresh):
        print("   %2d %s" % (i, u))

# the f32-source CAST arm, dtype.py:35-38
fa0, fa1 = DDO.WPOOL[dtypes.f32][:2]
b = len(ORDER)
fr = DDO.DD.l2i(Ops.CAST, dtypes.float32, fa0, fa1)
print("=== lgu  n=%d   answer=%s" % (len(kept(ORDER[b:])), DDO.tree(fr)))
for i, u in enumerate(kept(ORDER[b:])):
    print("   %2d %s" % (i, u))
