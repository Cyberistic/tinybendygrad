"""Probe 3: REDUCE ever emitted? PARAM order? buffer bytes access? storage fmt?"""
import os, base64, pickle
os.environ["DEV"] = "PYTHON"
from tinygrad import Tensor
from tinygrad.uop.ops import Ops
from tinygrad.runtime.ops_python import PythonRenderer
from tinygrad.dtype import storage_fmt_for_dtype, dtypes

CAP = []
def grab(uops):
    CAP.append((list(uops),))
    return base64.b64encode(pickle.dumps(uops)).decode()
PythonRenderer.render = lambda self, uops: grab(uops)

def ops_of(uops): return set(str(u.op) for u in uops)

# does REDUCE ever survive to the renderer?
tests = {}
a = Tensor([1.0]*8).realize(); (a.sum()).realize(); tests["sum"]=1
a = Tensor([[1.0,2.0],[3.0,4.0]]).realize(); (a.max(axis=1)).realize(); tests["max"]=1
a = Tensor([1.0]*16).realize(); (a.prod()).realize(); tests["prod"]=1
x = Tensor([[1.0]*4]*4).realize(); y = (x @ x).realize(); tests["matmul"]=1
x = Tensor([1.0]*4).realize(); y = (x[0:2]).realize(); tests["slice"]=1
x = Tensor([1.0]*8).realize(); y = x.reshape(2,4).realize(); tests["reshape"]=1
x = Tensor([1.0]*4).realize(); y = x.contiguous().realize(); tests["contig"]=1
x = Tensor([1.0]*4).realize(); y = x.permute(0).realize(); tests["permute"]=1
x = Tensor([float(i) for i in range(8)]).realize(); y = (x>3).realize(); tests["cmp"]=1
x = Tensor([1.0]*4).realize(); y = x.log().realize(); tests["log"]=1
x = Tensor([2.0]*4).realize(); y = x.sqrt().realize(); tests["sqrt"]=1

allops = {}
for uops, in CAP:
    for u in uops: allops[str(u.op)] = allops.get(str(u.op), 0) + 1
print("=== ALL OPS EVER EMITTED ===")
for k in sorted(allops): print(f"  {k:22s} {allops[k]}")
print("REDUCE emitted:", "Ops.REDUCE" in allops)
print("FDIV emitted:", "Ops.FDIV" in allops)
print("THREEFRY emitted:", "Ops.THREEFRY" in allops)

print()
print("=== storage_fmt_for_dtype / itemsize ===")
for nm in ("float","int","uint","bool","half","bfloat16","long","uint64"):
    d = {"float":dtypes.float,"int":dtypes.int,"uint":dtypes.uint,"bool":dtypes.bool,
         "half":dtypes.half,"bfloat16":dtypes.bfloat16,"long":dtypes.long,"uint64":dtypes.uint64}[nm]
    print(f"  {nm:10s} fmt={d.fmt} itemsize={d.itemsize} storage={storage_fmt_for_dtype(d)}")

print()
print("=== PARAM ordering + bytes access ===")
CAP.clear()
p = Tensor([1.0,2.0,3.0,4.0]).realize()
print("  input raw:", bytes(p.data()).hex())
q = Tensor([9.0,8.0]).realize()
r = (p[:2] + q).realize()
uops = CAP[0][0]
print("  PARAM uops in order:", [(i, u.op, u.arg.n if hasattr(u.arg,'n') else u.arg) for i,u in enumerate(uops) if str(u.op)=='Ops.PARAM'])
print("  out bytes:", bytes(r.data()).hex())
print("  out shape", r.shape, "nbytes", len(bytes(r.data())))