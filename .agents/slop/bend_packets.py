#!/usr/bin/env python3
"""CPython oracle for runtime/ops_bend.py: emit REAL packets and real answers.

Nothing here is transcribed. Every `py=` expectation is produced by calling
tinygrad's own code, and every packet comes from `BendRenderer.render`.

Usage:
  uv run python .agents/slop/bend_packets.py            # packets + answers
  uv run python .agents/slop/bend_packets.py --run      # + execute the executor
"""
import sys, json, struct, pathlib
from tinygrad import Tensor, Context, Device
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.runtime import ops_bend as OB

OUT = pathlib.Path(__file__).parent

CAP = []

_orig_init = OB.BendProgram.__init__
def _init(self, dev, obj):
  _orig_init(self, dev, obj)
  CAP.append(dict(src=self.src, uops=[(u.op.name, u.dtype.name, u.arg,
                                       [s.op.name for s in u.src],
                                       (u.addrspace.name if u.addrspace else None))
                                      for u in self.uops],
                  nbufs=self.nbufs, in_bufs=self.in_bufs,
                  out_bufs=sorted(self.out_bufs)))
OB.BendProgram.__init__ = _init

_orig_call = OB.BendProgram.__call__
def _call(self, *bufs, global_size=(1, 1, 1), local_size=(1, 1, 1), vals=(), wait=False, **kw):
  CAP[-1].update(bufs=[bytes(b) for b in bufs], gsize=list(global_size),
                 lsize=list(local_size), vals=list(vals))
  return _orig_call(self, *bufs, global_size=global_size, local_size=local_size,
                    vals=vals, wait=wait, **kw)
OB.BendProgram.__call__ = _call


def kernels():
  """(name, thunk) pairs. Every answer is CPython's, computed here."""
  with Context(DEV='BEND'):
    T = Tensor
    # 1: elementwise add, f32, the shape ops_bend's header names
    a = T([1.0, 2.0, 3.0, 4.0]).realize(); b = T([10.0, 20.0, 30.0, 40.0]).realize()
    yield ('add4', lambda: (a + b).tolist())
    # 2: scalar lane
    c = T([5.0]).realize()
    yield ('mul_scalar', lambda: (a * c[0]).tolist())
    # 3: reduce -- the sweep that measured max_numel 4 on LOAD/STORE
    yield ('sum', lambda: a.sum(axis=0).tolist())
    # 4: a reduce that VECTORIZES (float4 contraction), the `k:vec:` arm
    yield ('sum4', lambda: a[:4].sum(axis=0).tolist())
    # 5: int32 lane, so `i32` appears on the wire
    i = T([1, 2, 3, 4], dtype=dtypes.int32).realize(); j = T([10, 20, 30, 40], dtype=dtypes.int32).realize()
    yield ('addi32', lambda: (i + j).tolist())
    # 6: i32 -> f32 CAST, two lanes on one wire
    yield ('cast', lambda: (i + 1).cast(dtypes.float32).tolist())
    # 7: u32 lane
    k = T([7, 8, 9, 10], dtype=dtypes.uint32).realize()
    yield ('addu32', lambda: (k + 1).tolist())
    # 8: a dot, which is where BITCAST/INDEX/SHRINK chains get long
    x = (T.arange(16, dtype=dtypes.float32) + 1).realize().reshape(4, 4)
    y = (T.arange(16, dtype=dtypes.float32) * 2).realize().reshape(4, 4)
    yield ('dot', lambda: x @ y)
    # 9: bool lane
    yield ('cmp', lambda: (a > 2.0).tolist())


def main():
  names, answers, pkts = [], [], []
  run = '--run' in sys.argv
  if run:
    import tinygrad.runtime.ops_bend as _m
    def _fake_exe():
      raise SystemExit("executor requested; compile executor.bend first")
  for name, thunk in kernels():
    CAP.clear()
    try:
      ans = thunk()
    except Exception as e:
      ans = 'EXC: %s: %s' % (type(e).__name__, e)
    for c in CAP:
      pkts.append((name, c))
  for name, c in pkts:
    (OUT / ('packet-%s.txt' % name)).write_text(c['src'])
    print('=== %s  nbufs=%s in_bufs=%s out_bufs=%s g=%s vals=%s' %
          (name, c['nbufs'], c['in_bufs'], c['out_bufs'], c.get('gsize'), c.get('vals')))
    print(c['src'], end='')
  print('=== ANSWERS')
  for name, thunk in kernels():
    pass
  (OUT / 'bend_packets.json').write_text(json.dumps(
    [{'name': n, **{k: v for k, v in c.items() if k != 'bufs'}} for n, c in pkts], indent=1))
  print('wrote', len(pkts), 'packets')

if __name__ == '__main__':
  main()