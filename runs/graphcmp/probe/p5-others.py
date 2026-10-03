import os, sys
os.environ["DEV"]="CPU"
import tinygrad
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops, AxisType, AddrSpace
from tinygrad.codegen.opt import Opt, OptOps
sys.path.insert(0, os.path.join(os.path.dirname(__file__),"..","..","..",".agents","slop"))
print("tree:", tinygrad.__file__)

print("=== A. an UNKNOWN ENUM through _carg ===")
def _carg_probe(x):
  import enum, dataclasses
  if hasattr(x, "__dataclass_fields__"):
    return f"{type(x).__name__}(" + "".join(f"{n}=?" for n in x.__dataclass_fields__) + ")"
  d = {k:v for k,v in vars(x).items() if k!="grad_fxn"}
  return f"{type(x).__name__}(" + "".join(f"{k}=?" for k,v in d.items()) + ")"
print("  OptOps.TC   ->", _carg_probe(OptOps.TC))
print("  OptOps.SWAP ->", _carg_probe(OptOps.SWAP))
print("  OptOps.TC == OptOps.SWAP ?", _carg_probe(OptOps.TC)==_carg_probe(OptOps.SWAP), " <-- COLLAPSE if True")
print("  vars(OptOps.TC) =", vars(OptOps.TC))
print("  Opt(OptOps.TC,0,4) fields:", [f.name for f in dataclasses.fields(Opt)] if False else list(vars(Opt(OptOps.TC,0,4))))

print()
print("=== B. PYLITERAL holding a UOp: dtype / shape / toposort ===")
c4 = UOp.const(4)
p = UOp(Ops.PYLITERAL, (), (c4,))
print("  dtype:", p.dtype.name)
try: print("  shape:", p.shape)
except Exception as e: print("  shape RAISES:", type(e).__name__)
try: print("  _shape:", p._shape)
except Exception as e: print("  _shape:", type(e).__name__)
print("  toposort:", [n.op.name for n in p.toposort()])
print("  arg is the SAME object as c4:", p.arg[0] is c4)
print("  key:", p.key.hex()[:24])

print()
print("=== C. realized BUFFER: shape / dtype / arg fields ===")
t = Tensor.empty(4,3); t.realize()
for n in t.uop.toposort():
  if n.op is Ops.BUFFER:
    a=n.arg
    print("  dtype:", n.dtype.name, "shape:", n.shape, "nsrc:", len(n.src))
    print("  ParamArg.fieldnames:", list(vars(a).keys()))
    print("  buffer.slot:", getattr(a.buffer,"slot","<no slot attr>"))
    print("  Buffer stable attrs: size=%r offset=%r nbytes=%r device=%r dtype=%r is_allocated=%r trace_num=%r" % (
      a.buffer.size, a.buffer.offset, a.buffer.nbytes, a.buffer.device, a.buffer.dtype.name, a.buffer.is_allocated, a.buffer.trace_num))
    print("  today's normal form text: realized" + "i" + str(a.buffer))
    print("  repr(Buffer):", repr(a.buffer))
    break

print()
print("=== D. BINARY: shape from arg length (ops.py:365) ===")
b = UOp(Ops.BINARY, (), b"abcd")
print("  dtype:", b.dtype.name, "shape:", b.shape, "len(arg):", len(b.arg))
b2 = UOp(Ops.BINARY, (), b"wxyz")
print("  two blobs, same length, equal str(argstr)?", b.argstr()==b2.argstr(), "| same key?", b.key==b2.key, "| same repr:", repr(b)==repr(b2))
print("  UOp.unique_num:", b.n if hasattr(b,'n') else "n/a", b2.n)

print()
print("=== E. which Ops raise on shape (the N vs R split) ===")
for op in (Ops.SINK, Ops.PARAM, Ops.PYLITERAL, Ops.BINARY, Ops.CALL, Ops.PROGRAM, Ops.LINEAR, Ops.SOURCE, Ops.BACKEDGE, Ops.BARRIER, Ops.GROUP, Ops.IF, Ops.ENDIF, Ops.NOOP, Ops.REWRITE_ERROR, Ops.MSELECT):
  try:
    u = UOp(op, (UOp.const(4),) if op in (Ops.LOAD,Ops.STORE,Ops.INDEX,Ops.GATHER) else (), None)
    print(f"  {op.name:15} shape={u.shape!r}")
  except Exception as e:
    print(f"  {op.name:15} shape RAISES {type(e).__name__}")
