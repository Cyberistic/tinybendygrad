import sys
sys.path.insert(0, '/Users/cyberistic/src/tries/2026-09-30-tinybendygrad')
from tinygrad.mixin.gradient import pm_gradient
from tinygrad.uop.ops import Ops, UOp
from tinygrad.uop import upat
from tinygrad.dtype import dtypes

n = 0
for op, pats in pm_gradient.pdict.items():
  for p in pats:
    n += 1
    pat, fxn, rej = p
    rej = sorted(x.name for x in rej)
    code = upat._get_code(pat, 'ctx' in fxn.__code__.co_varnames[:fxn.__code__.co_argcount])
    print(f"tag={n-1} op={op.name} rej={rej}")
    if code is None:
      print("   <NOT COMPILED>")
    else:
      for line in code[0].split("\n")[1:]:
        print("   " + line)
print("TOTAL", n)
