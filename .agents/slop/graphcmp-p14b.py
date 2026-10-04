# graphcmp-p14b.py -- A REAL LINEARIZED PROGRAM: schedule_linear + full_rewrite_to_sink.
#
# Q: does invoking the scheduler reach ENDIF / BACKEDGE / LOAD / STORE?
# Run on several programs and print each one's op census.
import collections
from tinygrad import Tensor, Device
from tinygrad.uop.ops import UOp, Ops
from tinygrad.dtype import dtypes
from tinygrad.codegen import full_rewrite_to_sink, to_program
from tinygrad.helpers import Context

print("# DEV =", Device.DEFAULT)
ren = Device[Device.DEFAULT].renderer
WANT = ("ENDIF", "IF", "BACKEDGE", "END", "LOAD", "STORE", "INDEX", "GETADDR",
        "BARRIER", "GROUP", "PARAM", "BUFFER", "RANGE", "WHERE", "SHRINK")


def census(tag, ast):
  try:
    ts = list(ast.toposort())
  except Exception as e:
    print(f"# {tag:26s} TOPOSORT FAILED {type(e).__name__}: {e}")
    return None
  c = collections.Counter(u.op.name for u in ts)
  print(f"# {tag:26s} nodes={len(ts):4d}  {' '.join(f'{k}={c[k]}' for k in WANT if c[k])}")
  return ts


def sched_sinks(expr):
  lin = expr.schedule_linear()
  return [si.src[0] for si in lin.src if si.src[0].op is Ops.SINK]


def probe(tag, make):
  with Context(SPEC=1):
    try:
      expr = make()
    except Exception as e:
      print(f"# {tag:26s} BUILD FAILED {type(e).__name__}: {e}")
      return
    try:
      sinks = sched_sinks(expr)
    except Exception as e:
      print(f"# {tag:26s} SCHEDULE FAILED {type(e).__name__}: {e}")
      return
    print(f"# {tag:26s} kernels={len(sinks)}")
    for i, sk in enumerate(sinks):
      if census(f"{tag} sched[{i}]", sk) is None:
        continue
      try:
        census(f"{tag} full[{i}]", full_rewrite_to_sink(sk, ren, optimize=False))
      except Exception as e:
        print(f"# {tag:26s} full[{i}] FAILED {type(e).__name__}: {e}")


probe("matmul", lambda: Tensor.empty(4, 5).realize().assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5)))
probe("copy", lambda: Tensor.empty(4, 3).contiguous())
probe("assign", lambda: Tensor.empty(4, 3).realize().assign(Tensor.empty(4, 3) + 1))
probe("shrink", lambda: Tensor.empty(4, 4).contiguous()[Tensor([0, 2])])
probe("pad", lambda: (Tensor.empty(4, 3) + 1).pad(((0, 1), (0, 1))).contiguous())
probe("sum", lambda: Tensor.empty(4, 8).contiguous().sum(axis=1).contiguous())

# `to_program` is where pm_linearize_cleanups injects IF/ENDIF (codegen/__init__.py:426).
print("# --- to_program (IF/ENDIF live here) ---")
for tag, make in (("matmul", lambda: Tensor.empty(4, 5).realize().assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5))),
                  ("pad", lambda: (Tensor.empty(4, 3) + 1).pad(((0, 1), (0, 1))).contiguous()),
                  ("shrink", lambda: Tensor.empty(4, 4).contiguous()[Tensor([0, 2])])):
  with Context(SPEC=1):
    try:
      sk = sched_sinks(make())[0]
      fs = full_rewrite_to_sink(sk, ren, optimize=False)
      census(f"prg {tag}", to_program(fs, ren))
    except Exception as e:
      print(f"# prg {tag:21s} FAILED {type(e).__name__}: {e}")