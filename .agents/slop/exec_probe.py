"""Probe: dump the uop list PythonProgram.__call__ actually receives. No numpy."""
import os, sys, base64, pickle, collections
os.environ["DEV"] = "PYTHON"
os.environ["CCACHE"] = "0"
os.environ["SCACHE"] = "0"
from tinygrad import Tensor, Device
from tinygrad.uop.ops import Ops, UOp
from tinygrad.runtime.ops_python import PythonRenderer
import tinygrad.engine.realize as RZ

seen = collections.Counter()
CALLS = []

def dump(uops):
    seen.update((str(u.op), str(u.dtype)) for u in uops)
    print(f"--- uops: {len(uops)}")
    for i, u in enumerate(uops):
        ss = []
        for v in u.src:
            try: ss.append(f"{v.op}/{v.dtype}")
            except Exception: ss.append(f"{v.op}/ERR")
        try: mn = u.max_numel()
        except Exception: mn = "-"
        extra = ""
        if str(u.op) in ("Ops.SPECIAL", "Ops.RANGE"):
            extra = f" SPECIAL={u.arg}"
        print(f"{i:3d} {u.op!s:20s} dt={str(u.dtype):14s} arg={str(u.arg)[:30]:30s} as={getattr(u,'addrspace',None)} srcs={ss} numel={mn}{extra}")
    return base64.b64encode(pickle.dumps(uops)).decode()

PythonRenderer.render = lambda self, uops: dump(uops)

_orig_call = RZ.Compiled.__call__ if hasattr(RZ, "Compiled") else None

def which(name, fn):
    print("=========== %s ===========" % name)
    fn()

def k_add():
    a = Tensor([1.0,2.0,3.0,4.0]).realize()
    b = Tensor([10.0,20.0,30.0,40.0]).realize()
    c = (a+b).realize()
    print("result", c.data().tolist())

def k_sum():
    a = Tensor([1.0,2.0,3.0,4.0]).realize()
    r = a.sum().realize()
    print("result", r.data().tolist())

def k_mm():
    m1 = Tensor([[1.0,2.0],[3.0,4.0]]).realize()
    m2 = Tensor([[5.0,6.0],[7.0,8.0]]).realize()
    mm = (m1@m2).realize()
    print("result", mm.data().tolist())

def k_cast():
    a = Tensor([1,2,3,4], dtype=None).realize()
    b = a.float().realize()
    print("result", b.data().tolist())

def k_biggrid():
    a = Tensor(list(range(64)), dtype=None).realize()
    b = (a*2+1).realize()
    print("result", b.data().tolist())

which("elementwise add", k_add)
which("sum reduce", k_sum)
which("matmul", k_mm)
which("int->float cast", k_cast)
which("grid 64", k_biggrid)

print()
print("=========== OP HISTOGRAM ===========")
for k, v in sorted(seen.items()):
    print(f"{k[0]:24s} {k[1]:16s} {v}")