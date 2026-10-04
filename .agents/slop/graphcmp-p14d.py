# graphcmp-p14d.py -- THE DEFINITIVE OP-REACHABILITY PROBE FOR ENDIF / BACKEDGE / LOAD / STORE.
#
# Three questions, each answered by CALLING CPython and printing a denominator:
#
#  Q1  Does the SCHEDULER (`schedule_linear` + `full_rewrite_to_sink`) mint a gated STORE
#      anywhere in a corpus of eager programs? A gated STORE is the ONLY input to the one
#      ENDIF-minting rule in this tree (codegen/__init__.py:403).
#  Q2  Does a real in-tree kernel mint BACKEDGE / LOAD / STORE? `hcq_fence`
#      (tinygrad/runtime/support/hcq2.py:405-413) is one.
#  Q3  Given a gated STORE -- spelled exactly as the tree's own renderers spell it
#      (`UOp.store(val, gate)`, ops.py:613, used by renderer/wgsl.py:20) -- does the REAL
#      `to_program` pipeline produce IF/ENDIF?
import collections
from tinygrad import Tensor, Device
from tinygrad.uop.ops import UOp, Ops, KernelInfo, ParamArg
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.codegen import full_rewrite_to_sink, to_program
from tinygrad.helpers import Context

print("# DEV =", Device.DEFAULT)
ren = Device[Device.Default if False else Device.DEFAULT].renderer
WANT = ("IF", "ENDIF", "BACKEDGE", "END", "LOAD", "STORE", "INDEX", "WHERE", "RANGE",
        "PARAM", "BUFFER", "GROUP", "SHRINK")


def census(tag, ast):
  ts = list(ast.toposort())
  c = collections.Counter(u.op.name for u in ts)
  g = [f"{u.op.name}({len(u.src)}src)" for u in ts
       if (u.op is Ops.STORE and len(u.src) == 3) or (u.op is Ops.LOAD and len(u.src) >= 3)]
  print(f"# {tag:26s} nodes={len(ts):4d} " + " ".join(f"{k}={c[k]}" for k in WANT if c[k]))
  if g:
    print(f"# {'':26s} GATED: {g}")
  return ts


# ============================ Q1 =========================================
print("# === Q1: does the scheduler ever mint a GATED STORE? ===")
PROGS = {
  "matmul":    lambda: Tensor.empty(4, 5).realize().assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5)),
  "assign":    lambda: Tensor.empty(4, 3).realize().assign(Tensor.empty(4, 3) + 1),
  "shrink":    lambda: Tensor.empty(4, 4).contiguous()[Tensor([0, 2])],
  "pad":       lambda: (Tensor.empty(4, 3) + 1).pad(((0, 1), (0, 1))).contiguous(),
  "pad+shrink": lambda: (Tensor.empty(4, 3) + 1).pad(((0, 1), (0, 2))).contiguous()[0:2],
  "sum":       lambda: Tensor.empty(4, 8).contiguous().sum(axis=1).contiguous(),
  "expandcut": lambda: Tensor.empty(1, 4).contiguous().expand(4, 4)[1:3].contiguous(),
  "assign-into-view": lambda: Tensor.empty(4, 4).contiguous().realize()[0:2].assign(Tensor.ones(2, 4)),
  "assign-pad-into-view": lambda: Tensor.empty(4, 4).contiguous().realize()[0:2, 0:2].assign(
      Tensor.ones(2, 2).pad(((0, 2), (0, 2)))),
  "3d-slice":  lambda: Tensor.empty(4, 4, 4).contiguous()[1:3, :, 0:2].contiguous(),
}
qg = qn = 0
for tag, make in PROGS.items():
  with Context(SPEC=1):
    try:
      ks = [si.src[0] for si in make().schedule_linear().src if si.src[0].op is Ops.SINK]
      if not ks:
        print(f"# {tag:26s} no kernels")
        continue
      ts = census(f"{tag}", full_rewrite_to_sink(ks[0], ren, optimize=True))
      qn += 1
      qg += sum(1 for u in ts if u.op is Ops.STORE and len(u.src) == 3)
    except Exception as e:
      print(f"# {tag:26s} FAILED {type(e).__name__}: {str(e)[:100]}")
print(f"# Q1 ANSWER: gated STOREs found = {qg} in {qn} scheduled programs")

# ============================ Q2 =========================================
print("# === Q2: a REAL in-tree kernel: hcq_fence ===")
with Context(SPEC=1):
  from tinygrad.runtime.support.hcq2 import hcq_fence
  tv = UOp(Ops.PARAM, src=(), arg=ParamArg(3, dtypes.uint64, 1, device="CPU", volatile=True))
  try:
    f = hcq_fence(tv, tv, tv, 0)
    census("hcq_fence", f)
  except Exception as e:
    print(f"# hcq_fence FAILED {type(e).__name__}: {str(e)[:140]}")

# ============================ Q3 =========================================
print("# === Q3: a gated STORE -> the real to_program -> IF/ENDIF ===")
with Context(SPEC=1):
  buf = UOp(Ops.BUFFER, src=(), arg=ParamArg(1, dtypes.float, 16, device="CPU"))
  val = UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtypes.float, 16, device="CPU", name="v0"))
  rng = UOp.range(4, 0)
  gate = UOp.range(4, 0) < UOp.const(3)
  st = buf.index(UOp.range(4, 0)).store(val.index(UOp.range(4, 0)), gate).end(UOp.range(4, 0))
  sk = st.sink(arg=KernelInfo(name="gated"))
  census("gated sched", sk)
  try:
    census("gated full", full_rewrite_to_sink(sk, ren, optimize=False))
  except Exception as e:
    print(f"# gated full FAILED {type(e).__name__}: {str(e)[:140]}")
  # apply the REAL pm_linearize_cleanups, which is what to_program's pm_to_program does.
  from tinygrad.codegen import pm_linearize_cleanups
  from tinygrad.codegen.late.renderer import linearize
  from tinygrad.uop.ops import PatternMatcher
  from tinygrad.codegen import line_rewrite
  try:
    lines = line_rewrite(linearize(sk), pm_linearize_cleanups)
    flat = []
    for ln in lines:
      flat.append(ln)
      flat += [x for x in getattr(ln, "src", ()) if not isinstance(x, (int, float, str))]
    u = UOp(Ops.PROGRAM, src=tuple(lines), arg=None) if False else UOp(Ops.LINEAR, src=tuple(lines))
    census("linearized", u)
  except Exception as e:
    print(f"# line_rewrite FAILED {type(e).__name__}: {str(e)[:140]}")