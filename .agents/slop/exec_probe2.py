"""Probe 2: local_size, Ops enum, loop-producing kernels."""
import os, sys, base64, pickle, collections
os.environ["DEV"] = "PYTHON"
from tinygrad import Tensor
from tinygrad.uop.ops import Ops, GroupOp
from tinygrad.runtime.ops_python import PythonRenderer

seen = collections.Counter()
CALLS = []

def dump(uops):
    seen.update((str(u.op), str(u.dtype)) for u in uops)
    for i, u in enumerate(uops):
        if str(u.op) in ("Ops.RANGE", "Ops.BACKEDGE", "Ops.END", "Ops.IF", "Ops.ENDIF", "Ops.SPECIAL", "Ops.REDUCE", "Ops.BARRIER"):
            ss = [f"{v.op}" for v in u.src]
            print(f"  LOOPOP {i:3d} {u.op!s:18s} dt={u.dtype} arg={str(u.arg)[:40]} srcs={ss}")
    return base64.b64encode(pickle.dumps(uops)).decode()

PythonRenderer.render = lambda self, uops: dump(uops)

# intercept the actual call
import tinygrad.runtime.ops_python as OP
_oldcall = OP.PythonProgram.__call__
def spy(self, *bufs, **kw):
    CALLS.append({k: v for k, v in kw.items()})
    return _oldcall(self, *bufs, **kw)
OP.PythonProgram.__call__ = spy

print("=== Ops members with 'DEFINE' or 'RANGE' or 'PARAM' or 'BUFFER' ===")
print([o for o in dir(Ops) if not o.startswith("_") and any(t in o for t in ("DEFINE","RANGE","PARAM","BUFFER","REDUCE","SPECIAL","BARRIER","BINARY","CALL","GROUP"))])
print()
print("=== GroupOp.ALU members ===")
print(sorted(str(m) for m in GroupOp.ALU))
print()

def k1():
    a = Tensor(list(range(8)), dtype=None).realize(); b = (a+1).realize(); b.data().tolist()
def k2():
    a = Tensor(list(range(100)), dtype=None).realize(); b = a.sum().realize(); b.data().tolist()
def k3():
    a = Tensor([[float(i*4+j) for j in range(4)] for i in range(4)]).realize(); b = a.sum(axis=1).realize(); print("rowsum", b.data().tolist())
def k4():
    a = Tensor(list(range(1000)), dtype=None).realize(); b = (a*3+7).realize(); b.data().tolist()[:4]
def k5():
    a = Tensor([1.0]*64).realize(); b = (a/2).realize(); print("div", b.data().tolist()[:3])
def k6():
    a = Tensor(list(range(64)), dtype=None).realize(); b = (a < 32).realize(); print("cmp", b.data().tolist()[:4])
def k7():
    a = Tensor(list(range(32)), dtype=None).realize(); b = (a & 15).realize(); print("and", b.data().tolist()[:4])
def k8():
    a = Tensor([[1.0,2.0],[3.0,4.0]]).realize(); b = a.sum().realize(); print("2dsum", b.data().tolist())

for name, f in [("k1 small",k1),("k2 sum100",k2),("k3 rowsum",k3),("k4 big",k4),("k5 div",k5),("k6 cmp",k6),("k7 and",k7),("k8 2dsum",k8)]:
    print(f"--- {name}")
    try: f()
    except Exception as e: print("  ERR", type(e).__name__, e)

print()
print("=== CALL KWARGS (global_size / local_size) ===")
for c in CALLS[:12]:
    print({k: v for k, v in c.items() if k in ("global_size","local_size","vals")})

print()
print("=== OP HISTOGRAM ===")
for k, v in sorted(seen.items()):
    print(f"{k[0]:24s} {k[1]:16s} {v}")