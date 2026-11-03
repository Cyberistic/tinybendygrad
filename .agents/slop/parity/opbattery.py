#!/usr/bin/env python3
"""opbattery.py -- 31 small ops through the DEFAULT Bend lane, against tinygrad's CPU device.

    .venv/bin/python .agents/slop/parity/opbattery.py

WHY THIS EXISTS: `gates/ops_bend_exec-e2e.py` covers 7 kernels. That is enough to catch a broken
interpreter loop and NOT enough to catch a partial renderer: this battery found FOUR defects in one
run (a non-finite float const spelled `inff`, an unreachable `CBool` arm, a signed `u32` const, and
int consts truncated to 32 bits) because it reaches `exp`, `log2`, `sin`, reduces, casts and int ops
that the 7 do not.

THE ORACLE IS tinygrad's OWN CPU DEVICE (`DEV=CPU`), not the PYTHON emulator: the CPU device is what
the port's compiled lane is supposed to match.
"""
import os, sys
ROOT="/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"; sys.path.insert(0, ROOT)
os.environ.pop("BEND_C", None); os.environ.pop("BEND_PORT_C", None)
import numpy as np
import ops_bend as OB
sys.modules["tinygrad.runtime.ops_bend"] = OB
from tinygrad import Tensor, Context
from tinygrad.dtype import dtypes

F = lambda xs: Tensor(np.array(xs, dtype=np.float32))
I = lambda xs: Tensor(np.array(xs, dtype=np.int32))
def cases():
  a, b = F([[1,2],[3,4]]), F([[5,6],[7,8]])
  i, j = I([[7,8],[9,10]]), I([[3,1],[2,5]])
  return [
    ("add", lambda: F([[1,2],[3,4]]) + F([[5,6],[7,8]])),
    ("sub", lambda: F([[1,2],[3,4]]) - F([[5,6],[7,8]])),
    ("mul", lambda: F([[1,2],[3,4]]) * F([[5,6],[7,8]])),
    ("div", lambda: F([[1,2],[3,4]]) / F([[5,6],[7,8]])),
    ("maximum", lambda: F([[1,2],[3,4]]).maximum(F([[5,0],[1,9]]))),
    ("relu", lambda: F([[-1,2],[-3,4]]).relu()),
    ("exp", lambda: F([[0,1],[2,3]]).exp()),
    ("log2", lambda: F([[1,2],[4,8]]).log2()),
    ("sqrt", lambda: F([[1,4],[9,16]]).sqrt()),
    ("recip", lambda: F([[1,2],[4,8]]).reciprocal()),
    ("sin", lambda: F([[0,1],[2,3]]).sin()),
    ("trunc", lambda: F([[1.7,-1.7],[2.2,-2.2]]).trunc()),
    ("cmplt", lambda: F([[1,5],[3,0]]) < F([[2,4],[3,1]])),
    ("cmpeq", lambda: F([[1,5],[3,0]]) == F([[2,5],[3,1]])),
    ("cast_f2i", lambda: F([[1.7,2.2],[3.9,4.1]]).cast(dtypes.int32)),
    ("cast_i2f", lambda: I([[1,2],[3,4]]).cast(dtypes.float32)),
    ("cast_bool", lambda: F([[0,1],[2,0]]).cast(dtypes.bool)),
    ("iadd", lambda: I([[7,8],[9,10]]) + I([[3,1],[2,5]])),
    ("imul", lambda: I([[7,8],[9,10]]) * I([[3,1],[2,5]])),
    ("idiv", lambda: I([[7,8],[9,10]]) // I([[3,1],[2,5]])),
    ("imod", lambda: I([[7,8],[9,10]]) % I([[3,1],[2,5]])),
    ("shl", lambda: I([[1,2],[3,4]]) << 2),
    ("shr", lambda: I([[8,16],[24,32]]) >> 2),
    ("and", lambda: I([[6,7],[8,9]]) & I([[3,5],[7,9]])),
    ("sum", lambda: F([[1,2],[3,4]]).sum(axis=1)),
    ("max", lambda: F([[1,5],[3,2]]).max(axis=0)),
    ("matmul2", lambda: F([[1,2],[3,4]]) @ F([[5,6],[7,8]])),
    ("permute", lambda: F([[1,2,3],[4,5,6]]).permute(1,0)),
    ("pad", lambda: F([[1,2],[3,4]]).pad(((1,1),(1,1)))),
    ("cat", lambda: F([[1,2]]).cat(F([[3,4]]), dim=0)),
    ("bitcast", lambda: I([[1,2],[3,4]]).bitcast(dtypes.float32)),
    # THE NARROW FLOAT PATHS: untested until 2026-11-03, when each was measured through the DEFAULT lane
    # and then written down here so the claim has an instrument rather than an absence of failures.
    ("fp8e4m3", lambda: F([[1.5,2.25],[3.0,4.5]]).cast(dtypes.fp8e4m3).cast(dtypes.float32)),
    ("fp8e5m2", lambda: F([[1.5,2.25],[3.0,4.5]]).cast(dtypes.fp8e5m2).cast(dtypes.float32)),
    ("fp8e4m3fnuz", lambda: F([[1.5,2.25],[3.0,4.5]]).cast(dtypes.fp8e4m3fnuz).cast(dtypes.float32)),
    ("fp8e5m2fnuz", lambda: F([[1.5,2.25],[3.0,4.5]]).cast(dtypes.fp8e5m2fnuz).cast(dtypes.float32)),
    ("f64", lambda: F([[1.5,2.25],[3.0,4.5]]).cast(dtypes.float64).cast(dtypes.float32)),
    ("half_arith", lambda: (F([[1.5,2.0],[3.0,4.0]]).cast(dtypes.half) * F([[2.0,2.0],[2.0,2.0]]).cast(dtypes.half)).cast(dtypes.float32)),
    ("bf16_arith", lambda: (F([[1.5,2.0],[3.0,4.0]]).cast(dtypes.bfloat16) + F([[1.0,1.0],[1.0,1.0]]).cast(dtypes.bfloat16)).cast(dtypes.float32)),
    ("half_reduce", lambda: F([[1.5,2.0],[3.0,4.0]]).cast(dtypes.half).sum(axis=1).cast(dtypes.float32)),
  ]
def run(dev, mk):
  with Context(DEV=dev):
    return mk().realize().numpy()
ok=bad=0; fails=[]
for name, mk in cases():
  try: want = run("CPU", mk)
  except Exception as e: print(f"== {name}: ORACLE REFUSED {type(e).__name__}: {str(e)[:70]}"); continue
  try:
    got = run("BEND", mk)
    same = np.array_equal(got, want)
    print(f"== {name:10s} {'MATCH' if same else 'MISMATCH'}")
    ok+=same; bad+= (not same)
    if not same: fails.append((name, got, want))
  except Exception as e:
    print(f"== {name:10s} FAILED {type(e).__name__}: {str(e)[:120]}"); bad+=1; fails.append((name,None,None))
print(f"# {ok} match, {bad} failed")
for n,g,w in fails[:6]:
  if g is not None: print(f"  {n}: bend={str(g)[:60]} cpu={str(w)[:60]}")
