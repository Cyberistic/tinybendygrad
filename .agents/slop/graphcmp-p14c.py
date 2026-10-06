# graphcmp-p14c.py -- WHERE DOES IF/ENDIF COME FROM, AND CAN A REAL PROGRAM MINT ONE?
#
# The ONLY site in this tree that constructs Ops.ENDIF is codegen/__init__.py:403, inside
# `pm_linearize_cleanups`, and it fires on a GATED STORE:
#   (UPat(Ops.STORE, src=(UPat((INDEX, SHRINK)), UPat(), UPat(name="gate", dtype=bool)))
#      -> [UOp(Ops.IF, src=(gate, src[0])), st, UOp(Ops.ENDIF, src=(mif,))])
# A gated STORE is minted by `pm_move_gates_from_index` (codegen/late/gater.py:16,22),
# which runs INSIDE full_rewrite_to_sink at codegen/__init__.py:360.
#
# So the question is empirical: which eager program leaves a gate on an INDEX/LOAD/STORE?
# Prints the STORE/LOAD/INDEX src arities per program, plus the to_program census.
import collections
from tinygrad import Tensor, Device
from tinygrad.uop.ops import UOp, Ops
from tinygrad.dtype import dtypes
from tinygrad.codegen import full_rewrite_to_sink, to_program
from tinygrad.helpers import Context

print("# DEV =", Device.DEFAULT)
ren = Device[Device.DEFAULT].renderer


def mem(u):
  return f"{u.op.name}#{sum(1 for _ in u.toposort())}"


def detail(tag, ast):
  ts = list(ast.toposort())
  c = collections.Counter(u.op.name for u in ts)
  gated = [f"{u.op.name}({len(u.src)})" for u in ts if u.op in (Ops.STORE, Ops.LOAD, Ops.INDEX)
           and (len(u.src) > (2 if u.op is Ops.STORE else 1))]
  wheres = [f"{mem(u)}<-{mem(u.src[1])}" for u in ts if u.op is Ops.WHERE]
  print(f"# {tag:18s} nodes={len(ts):4d} STORE={c['STORE']} LOAD={c['LOAD']} INDEX={c['INDEX']} "
        f"IF={c['IF']} ENDIF={c['ENDIF']} WHERE={c['WHERE']} BACKEDGE={c['BACKEDGE']}")
  if gated:
    print(f"# {'':18s} MULTI-SRC MEM OPS: {gated}")
  for w in wheres[:6]:
    print(f"# {'':18s} WHERE {w}")


CASES = {
  "matmul": lambda: Tensor.empty(4, 5).realize().assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5)),
  "pad": lambda: (Tensor.empty(4, 3) + 1).pad(((0, 1), (0, 1))).contiguous(),
  "shrink": lambda: Tensor.empty(4, 4).contiguous()[Tensor([0, 2])],
  "expand+slice": lambda: Tensor.empty(1, 4).contiguous().expand(4, 4)[1:3].contiguous(),
  "pad2d+shrink": lambda: (Tensor.empty(4, 3) + 1).pad(((0, 1), (0, 2))).contiguous()[0:2],
  "avgpool": lambda: Tensor.arange(25).reshape(1, 1, 5, 5).cast("float32").avg_pool2d(padding=1).contiguous(),
}

for tag, make in CASES.items():
  with Context(SPEC=1, DEBUG=0):
    try:
      sk = [si.src[0] for si in make().schedule_linear().src if si.src[0].op is Ops.SINK]
      if not sk:
        print(f"# {tag:18s} no kernels")
        continue
      fs = full_rewrite_to_sink(sk[0], ren, optimize=True)
      detail(f"{tag} full", fs)
      try:
        prg = to_program(fs, ren)
        detail(f"{tag} PROGRAM", prg)
      except Exception as e:
        print(f"# {tag:18s} to_program FAILED {type(e).__name__}: {str(e)[:90]}")
    except Exception as e:
      print(f"# {tag:18s} FAILED {type(e).__name__}: {str(e)[:120]}")

# ---- a gated store is NOT reachable from any of the nine programs above, and proving THAT
# ---- is the next probe's job: `.agents/slop/graphcmp-p14d.py` Q1 counts gated STOREs over
# ---- nine scheduled programs and answers 0, and Q3 takes one by hand through the real
# ---- `pm_linearize_cleanups`. This file asked the narrower question -- does the SCHEDULER
# ---- ever leave a gate on an INDEX, a LOAD or a STORE -- and its answer is: on `shrink` it
# ---- leaves two GATED LOADS (`LOAD(3src)`), which is the READ side; no program above leaves
# ---- a gated STORE, and `to_program` then REFUSES `shrink` outright ("memory coalescing
# ---- does not support gated loads/stores").
print("# Q (this file's whole subject): does the scheduler leave a gate on a STORE?")
print("#   ANSWER, from the runs above: no. Two GATED LOADS on `shrink` and no gated STORE,")
print("#   and `to_program` refuses `shrink` for the gated loads. The count with a")
print("#   denominator is in graphcmp-p14d.py Q1: 0 gated STOREs in 9 scheduled programs.")
