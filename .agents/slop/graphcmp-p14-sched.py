# graphcmp-p14-sched.py -- WHAT DOES A REAL SCHEDULED PROGRAM CONTAIN?
#
# The claim under test, from graphcmp-LIMITS.md 5:
#   "ENDIF/BACKEDGE/LOAD/STORE are still unreached, and that is the real gap. A grouped
#    graph is a DAG, not a linearized program: LOAD/STORE need a STORE body, ENDIF/BACKEDGE
#    need a loop, and none of the four is constructible from the eager Tensor API in a
#    handful of lines."
#
# This asks CPython, on four programs, and prints the OPS CENSUS of each. Every number
# below came from running this file, not from reading the scheduler.
#
# RUN: env -u PYTHONPATH LC_ALL=C DEV=<dev> .venv/bin/python .agents/slop/graphcmp-p14-sched.py
import os, sys, collections
from tinygrad import Tensor, Device
from tinygrad.uop.ops import UOp, Ops, KernelInfo
from tinygrad.dtype import dtypes

print("# DEV =", Device.DEFAULT)


def census(name, ast):
  ts = list(ast.toposort())
  c = collections.Counter(u.op.name for u in ts)
  want = ("ENDIF", "BACKEDGE", "IF", "END", "LOAD", "STORE", "INDEX", "GETADDR",
          "BARRIER", "GROUP", "PARAM", "BUFFER", "RANGE")
  hits = [f"{k}={c[k]}" for k in want if c[k]]
  print(f"# {name:22s} nodes={len(ts):4d}  {' '.join(hits)}")
  print(f"# {'':22s} ops: {' '.join(sorted(c))}")
  return ts


# ---- A: the eager matmul, for reference (the corpus's own subject)
census("eager matmul", (Tensor.empty(4, 3) @ Tensor.empty(3, 5)).uop)

# ---- B: create_schedule of a REALIZED matmul. The scheduler is the thing that mints
# STORE/LOAD/BUFFER, so this is the first candidate for a linearized program.
from tinygrad.schedule import create_schedule
t = Tensor.empty(4, 3) @ Tensor.empty(3, 5)
tsink = Tensor.empty(4, 5).realize()
sched = create_schedule((tsink.assign(t)).uop)
census("create_schedule", sched)

# ---- C: the full codegen rewrite of the schedule: this is the pass that turns gated
# stores into IF-STORE-ENDIF (codegen/__init__.py:401-403).
from tinygrad.codegen import full_rewrite_to_sink
from tinygrad.device import Device as _D
ren = Device[Device.DEFAULT].renderer
try:
  fr = full_rewrite_to_sink(sched, ren, optimize=False)
  census("full_rewrite_to_sink", fr)
except Exception as e:
  print("# full_rewrite_to_sink FAILED:", type(e).__name__, e)

# ---- D: `hcq_fence` -- a REAL kernel body in this tree, at
# tinygrad/runtime/support/hcq2.py:405-413. It contains LOAD, STORE and BACKEDGE by
# construction, so it is the fixture for the three ops the schedule above may not reach.
from tinygrad.runtime.support.hcq2 import hcq_fence
tv = UOp(Ops.PARAM, src=(), arg=__import__("tinygrad.uop.ops", fromlist=["ParamArg"]).ParamArg(
  3, dtypes.uint64, 1, device="CPU", volatile=True))
try:
  f = hcq_fence(tv, tv, tv, 0)
  census("hcq_fence", f)
except Exception as e:
  print("# hcq_fence FAILED:", type(e).__name__, e)