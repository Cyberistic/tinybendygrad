#!/usr/bin/env python3
"""upstream-kernel-oracle.py -- WHAT UPSTREAM'S SCHEDULED KERNEL LOOKS LIKE.

    .venv/bin/python shaders/upstream-kernel-oracle.py

The shader's port has to END UP with the kernel upstream's own pipeline produces. This
file answers "what is that kernel?", so the port's rows can be compared with something
that is not the port's own reading of itself.

WHY IT PATCHES `create_schedule`. Upstream turns a graph into kernels in exactly one
place -- `lower_sink_to_linear` (`tinygrad/schedule/__init__.py:117`) calls
`create_schedule(get_kernel_graph(prepare_rangeify(function)))` -- and the kernel sink it
passes is the graph the whole schedule runs on. `get_kernel_graph` on its own answers a
GRAPH (`SINK`, `PAD`, `SHRINK`), not a kernel; `create_schedule` on a graph with no
realized output answers NOTHING (`LINEAR srcs= []`). So the oracle patches
`create_schedule`, realizes the tensor (which is what reaches the scheduler at all), and
dumps the sink it was handed -- the kernel body.

WHAT IT ANSWERS, AND WHY IT MATTERS HERE. The port's kernel graph carries `PAD` and
`SHRINK`; upstream's SCHEDULED kernel carries NEITHER: the `PAD` became a `WHERE` (a
value-level zero fill with the range's valid as the gate) and the `SHRINK` became an
`INDEX` at a shifted range. The distance field is MATERIALIZED (`STORE=1`): upstream
realizes a node whose consumers read it at different ranges (`indexing.py:267`), so the
neighbour read is a buffered read. Those three facts are the port's remaining work, and
this file is the measurement of them.

THE ROWS ARE A CENSUS, NOT A DUMP: op counts and the END's src kinds. A dump would
change shape with every upstream edit and would say nothing that a count does not.
"""

import sys

import tinygrad.schedule as sched
from tinygrad import Tensor

N = 16
RADIUS = 0.5
EPS = 0.0001

# THE FORMULA, SPELLED AS `shaders/shader-oracle.py` SPELLS IT: the same primitives, in
# the same order, so the two oracles build the same graph.
def shader(x: Tensor, y: Tensor) -> Tensor:
  dd = (x * x + y * y).sqrt() - RADIUS
  right = dd.pad((0, 1, 0, 0)).shrink(((0, N), (1, N + 1)))
  down = dd.pad((0, 0, 0, 1)).shrink(((1, N + 1), (0, N)))
  dx = dd - right
  dy = dd - down
  fw = dx.maximum(-dx) + dy.maximum(-dy)
  num = dd + fw
  den = (fw + fw) + EPS
  lo = (num / den).maximum(0.0)
  hi = (lo - 1.0).maximum(0.0)
  return 1.0 - (lo - hi)


def kernel_bodies(sink):
  """the kernel bodies inside a scheduled sink: the CALL bodies."""
  for u in sink.toposort():
    if u.op.name == "CALL":
      yield u.body


def main() -> int:
  captured = []
  real_create_schedule = sched.create_schedule

  def spy(sched_sink):
    captured.append(sched_sink)
    return real_create_schedule(sched_sink)

  sched.create_schedule = spy
  try:
    shader(Tensor.empty(N, N), Tensor.empty(N, N)).realize()
  finally:
    sched.create_schedule = real_create_schedule

  if not captured:
    print("kg_capture=NO")
    return 1

  for tag, sink in enumerate(captured):
    bodies = list(kernel_bodies(sink))
    for bi, body in enumerate(bodies):
      census = {}
      for u in body.toposort():
        census[u.op.name] = census.get(u.op.name, 0) + 1
      print(f"kg{tag}_{bi}_census=" + " ".join(f"{k}={census[k]}" for k in sorted(census)))
      ends = [u for u in body.toposort() if u.op.name == "END"]
      for e in ends:
        print(f"kg{tag}_{bi}_end_srcs=" + " ".join(s.op.name for s in e.src))
  return 0


if __name__ == "__main__":
  sys.exit(main())
