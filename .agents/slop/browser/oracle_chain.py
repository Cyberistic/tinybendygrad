#!/usr/bin/env python3
"""oracle_chain.py -- CPYTHON's OWN C FOR THE FOUR-KERNEL CHAIN.

WHY IT EXISTS: the port renders the relu's flat read as `(*(data1_196+0))` while the conv/pool/linear
reads are correct. The port's INDEX for that read is the ONLY applied-graph INDEX still in the
UNFOLDED 5-src form (`PARAM,CONST,CONST,RANGE,RANGE`), and the renderer reads only `src[1]`. That is
either (a) a port defect -- a missing fold -- or (b) what CPython does too, in which case the defect is
in the PROGRAM's shape and this file is the witness that says so. THE ORACLE DECIDES.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.schedule import create_schedule  # noqa: E402
from tinygrad.schedule.rangeify import get_kernel_graph  # noqa: E402
from tinygrad.schedule.prepare import prepare_rangeify  # noqa: E402
from tinygrad.uop.ops import Ops, UOp  # noqa: E402


def build():
  """`.agents/slop/browser/fchain.bend`'s `fchain_prog`, transcribed."""
  h1 = Tensor.empty(196).realize().reshape(1, 1, 14, 14)
  x = Tensor.empty(784).realize().reshape(1, 1, 28, 28)
  w1 = Tensor.empty(4).realize().reshape(1, 1, 2, 2)
  c1 = x.reshape(1, 1, 14, 2, 14, 2) * w1.reshape(1, 1, 1, 2, 1, 2)
  a1 = h1.assign(c1.sum(axis=(3, 5))).uop
  v1 = h1.reshape(1, 1, 14, 14)
  a2 = h1.assign(v1.relu()).uop
  h3 = Tensor.empty(49).realize().reshape(1, 1, 7, 7)
  v2 = h1.reshape(1, 1, 7, 2, 7, 2)
  a3 = h3.assign(v2.max(axis=(3, 5))).uop
  y = Tensor.empty(10).realize().reshape(1, 10)
  w2 = Tensor.empty(490).realize().reshape(49, 10)
  lhs = h3.reshape(1, 1, 49)
  rhs = w2.reshape(1, 49, 10).permute(0, 2, 1)
  a4 = y.assign((lhs * rhs).sum(axis=2)).uop
  return UOp.sink(a1, a2, a3, a4)


def main():
  with Context(DEV="CPU"):
    sink = build()
  kg = get_kernel_graph(prepare_rangeify(sink))
  print("py_kg_index_nodes=BEGIN")
  for u in kg.toposort():
    if u.op is Ops.CALL:
      for v in u.src[0].toposort():
        if v.op is Ops.INDEX:
          print(f"  call idx nsrc={len(v.src)} srcops={[w.op.name for w in v.src]}")
  print("py_kg_index_nodes=END")
  lin = create_schedule(kg)
  print(f"py_lin_n={len(lin.src)}")
  from tinygrad.device import Device
  from tinygrad.codegen import do_to_program
  for i, k in enumerate(lin.src):
    print(f"py_ast{i}=BEGIN")
    for u in k.src[0].toposort():
      if u.op is Ops.INDEX:
        print(f"  idx nsrc={len(u.src)} srcops={[s.op.name for s in u.src]}")
    print(f"py_ast{i}=END")
    prg = do_to_program(k.src[0], Device["CPU"].renderer)
    src = prg.src[2].arg
    print(f"py_k{i}=BEGIN")
    print(src)
    print(f"py_k{i}=END")


if __name__ == "__main__":
  main()
