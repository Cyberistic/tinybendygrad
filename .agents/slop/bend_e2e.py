#!/usr/bin/env python3
"""END TO END for tinygrad/runtime/ops_bend.py: build the Bend executor, run real
kernels on the BEND device, and compare against CPython's own answer.

THIS IS THE ARTEFACT. Every other oracle in this project drives CPython's pure
functions against a fake device; this one COMPILES AND RUNS.

    uv run python .agents/slop/bend_e2e.py

It prints, per case, the answer the BEND device produced, the answer CPython's
PYTHON device produced for the same expression, and the packet
`BendRenderer.render` emitted. The packets land in
`.agents/slop/packet-<case>.txt`, the same files the Bend gate diffs its
`bend_emit_<case>` row against, so the E2E and the gate read the SAME artefact.
"""
import pathlib, sys
from tinygrad import Tensor, Context, Device
from tinygrad.dtype import dtypes

OUT = pathlib.Path(__file__).parent
CAP = []

import tinygrad.runtime.ops_bend as OB
OB.executor  # the cached builder; reading it is what makes the import real
_orn = OB.BendRenderer.render
def _render(self, uops):
    CAP.append(uops)
    return _orn(self, uops)
OB.BendRenderer.render = _render
_oi = OB.BendProgram.__init__
def _init(self, dev, obj):
    _oi(self, dev, obj)
    CAP[-1] = (self, obj)
OB.BendProgram.__init__ = _init


def cases():
  T = Tensor
  with Context(DEV='BEND'):
    a = T([1.0, 2.0, 3.0, 4.0]).realize()
    b = T([10.0, 20.0, 30.0, 40.0]).realize()
    i = T([1, 2, 3, 4], dtype=dtypes.int32).realize()
    j = T([7, 8, 9, 10], dtype=dtypes.uint32).realize()
    xs = (T.arange(16, dtype=dtypes.float32) + 1).realize().reshape(4, 4)
    ys = (T.arange(16, dtype=dtypes.float32) * 2).realize().reshape(4, 4)
    return [('add4', lambda: (a + b)), ('sum4', lambda: a[:4].sum(axis=0)),
            ('addi32', lambda: i + i), ('addu32', lambda: j + 1),
            ('cast', lambda: (i + 1).cast(dtypes.float32)),
            ('cmp', lambda: a > 2.0), ('dot', lambda: (xs @ ys))]


def ref(thunk):
  """CPython's own answer, from the PYTHON device -- the emulator ops_bend.py
  was forked from, and the oracle for this file."""
  with Context(DEV='PYTHON'):
    return thunk().tolist()


def main():
  exe = OB.executor()
  print('# executor built once, keyed by executor.bend mtime+size:')
  print('#   ', exe)
  ok = bad = 0
  for name, thunk in cases():
    CAP.clear()
    try:
      got = thunk().tolist()
    except Exception as e:
      print(f'== {name}: FAILED {type(e).__name__}: {e}'); bad += 1; continue
    want = ref(thunk)
    same = repr(got) == repr(want)
    ok, bad = (ok + 1, bad) if same else (ok, bad + 1)
    print(f'== {name}: bend={got} python={want} {"MATCH" if same else "MISMATCH"}')
    if CAP:
      (OUT / f'packet-{name}.txt').write_text(CAP[-1][1].lib.decode())
  print(f'# {ok} match, {bad} mismatch')
  return 0 if bad == 0 else 1


if __name__ == '__main__':
  sys.exit(main())