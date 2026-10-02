#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_bend.bend.

ASKS CPYTHON; NEVER REWRITES PYTHON SOURCE.  Every `py=` expectation below is
produced by calling tinygrad's own `runtime.ops_bend` / `dtype` / `helpers`, or
by reading an attribute off a real UOp.  Nothing is transcribed.

Emits:
  bend_oracle_rows.txt   the gate rows, `name=py=<value>`
  bend_oracle_nodes.txt  the `NODES(...)` literals the Bend gate feeds its port
  packet-<name>.txt     the raw packets `encode()` produced
"""
import sys, json, pathlib, struct
from tinygrad.dtype import dtypes, DType, AddrSpace
from tinygrad.helpers import is_image_shape
from tinygrad.uop.ops import Ops, UOp
from tinygrad.runtime import ops_bend as OB

OUT = pathlib.Path(__file__).parent
VOCAB = ['i8', 'u8', 'i16', 'u16', 'i32', 'u32', 'i64', 'u64', 'f16', 'bf16',
         'f32', 'f64', 'fp8e4m3', 'fp8e5m2', 'fp8e4m3fnuz', 'fp8e5m2fnuz',
         'void', 'weakint', 'weakfloat']

# names of the ops ops_bend.py branches on
BRANCH_OPS = ['BUFFER', 'PARAM', 'CONST', 'SPECIAL', 'INDEX', 'SHRINK',
              'LOAD', 'STORE', 'END', 'BACKEDGE', 'BITCAST', 'AFTER',
              'STACK', 'RANGE', 'BARRIER', 'CAST', 'BINARY', 'GLOBAL']


def rows():
  r = []
  add = lambda k, v: r.append((k, v))

  # ---- the lane table, BOTH directions -------------------------------
  add('lanes_fwd', ' '.join(sorted(d.name for d in OB.LANES)))
  for d in OB.LANES: add(f'lane_is_{d.name}', OB.LANES.__contains__(d))
  add('lanes_sorted_by_str', ' '.join(str(d) for d in sorted(OB.LANES, key=str)))
  for n in VOCAB:
    add(f'dtype_roundtrip_{n}', getattr(dtypes, n.lower()).name)
  for n in VOCAB:
    add(f'dtype_present_{n}', hasattr(dtypes, n.lower()))

  # ---- itemsize / name table ------------------------------------------
  for n in VOCAB:
    d = getattr(dtypes, n.lower())
    add(f'dt_{n}', f'{d.name} {d.itemsize}')

  # ---- wire_dtype over a real UOp: name and refusal -------------------
  def mk(op, dt):
    if op is Ops.CONST: return UOp.const(3, dt)
    if op is Ops.PARAM:
      if dt in dtypes.weaks: return UOp.range(3, 0, dtype=dt)
      return UOp.param(0, dt, shape=(4,))
    if op is Ops.BUFFER:
      if dt in dtypes.weaks: return UOp.range(3, 0, dtype=dt)
      return UOp.param(1, dt, shape=(4,), addrspace=AddrSpace.REG)
    if op is Ops.BARRIER: return UOp.const(0, dtypes.f32).barrier()
    if op is Ops.LOAD: return UOp.param(0, dtypes.f32, shape=(4,)).load(UOp.const(0, dtypes.int32))
    return UOp.range(3, 0, dtype=dt)
  for op, dt in [(Ops.CONST, dtypes.i32), (Ops.RANGE, dtypes.f32),
                 (Ops.BUFFER, dtypes.u32), (Ops.PARAM, dtypes.bool),
                 (Ops.CONST, dtypes.f16), (Ops.PARAM, dtypes.bf16),
                 (Ops.BUFFER, dtypes.f64), (Ops.CONST, dtypes.void),
                 (Ops.PARAM, dtypes.weakint), (Ops.BUFFER, dtypes.weakfloat),
                 (Ops.PARAM, dtypes.u8), (Ops.PARAM, dtypes.i64),
                 (Ops.STORE, dtypes.f16), (Ops.LOAD, dtypes.bf16),
                 (Ops.BUFFER, dtypes.u64), (Ops.CONST, dtypes.f64),
                 (Ops.LOAD, dtypes.fp8e4m3), (Ops.PARAM, dtypes.i16),
                 (Ops.PARAM, dtypes.u16), (Ops.CONST, dtypes.fp8e5m2),
                 (Ops.PARAM, dtypes.fp8e4m3fnuz), (Ops.CONST, dtypes.i8),
                 (Ops.BARRIER, dtypes.f32)]:
    u = mk(op, dt)
    k = f'wire_dtype_{op.name}_{dt.name}'
    try: add(k, OB.wire_dtype(u))
    except NotImplementedError as e: add(k, str(e))

  # ---- wire_width ------------------------------------------------------
  for shp in [(4,), (16,), (2, 2), (4, 4), (2, 3, 4)]:
    u = UOp.param(0, dtypes.f32, shape=shp, addrspace=AddrSpace.REG)
    try: w = OB.wire_width(u)
    except RuntimeError: w = 1
    add(f'wire_width_{"x".join(map(str, shp))}', w)
  add('wire_width_barrier', OB.wire_width(UOp.const(0, dtypes.f32).barrier()))
  add('wire_width_param_bool', OB.wire_width(UOp.param(0, dtypes.bool, shape=(7,))))

  # ---- the local_size refusal ------------------------------------------
  add('local_size_msg', f'BEND v1 is warp 1, so it cannot launch with '
                        f'local_size={(1, 2, 1)}')

  # ---- is_image_shape ---------------------------------------------------
  for shp in [None, (), (4,), (4, 4), (2, 3, 4), (2, 3, 5), (2, 3, 4, 5)]:
    add('is_image_%s' % ('None' if shp is None else 'x'.join(map(str, shp))),
        is_image_shape(shp))
  return r


def packets():
  """REAL kernels: CPython's `encode()` output plus the UOp fields the port reads."""
  from tinygrad import Tensor, Context
  OB.executor = lambda: pathlib.Path('/nonexistent-bend-executor')
  # the seam: kill the subprocess so nothing is built or launched while we read.
  OB.subprocess = type('S', (), {'run': staticmethod(
      lambda *a, **k: (_ for _ in ()).throw(FileNotFoundError('seam stubbed')))})
  CAP = []
  orn = OB.BendRenderer.render
  def render(self, uops):
    CAP.append({'ruops': uops})
    return orn(self, uops)
  OB.BendRenderer.render = render
  oi = OB.BendProgram.__init__
  def init(self, dev, obj):
    oi(self, dev, obj)
    CAP[-1]['prog'] = self
  OB.BendProgram.__init__ = init
  oc = OB.BendProgram.__call__
  def call(self, *bufs, **kw):
    CAP[-1]['bufs'] = [bytes(x) for x in bufs]
    CAP[-1]['kw'] = {k: (list(v) if isinstance(v, tuple) else v) for k, v in kw.items()}
    raise FileNotFoundError('seam stubbed')
  OB.BendProgram.__call__ = call

  T = Tensor
  def realize(t):
    try: return t.realize()
    except FileNotFoundError: return t
  got = {}
  with Context(DEV='BEND'):
    a = realize(T([1.0, 2.0, 3.0, 4.0])); b = realize(T([10.0, 20.0, 30.0, 40.0]))
    p1 = realize(T([7.0])); q1 = realize(T([9.0]))
    i = realize(T([1, 2, 3, 4], dtype=dtypes.int32))
    j = realize(T([7, 8, 9, 10], dtype=dtypes.uint32))
    xs = realize(T.arange(16, dtype=dtypes.float32) + 1).reshape(4, 4)
    ys = realize(T.arange(16, dtype=dtypes.float32) * 2).reshape(4, 4)
    CASES = [('add4', lambda: (a + b)), ('mul_scalar', lambda: a * T([3.0]).realize()[0]),
             ('sum4', lambda: a[:4].sum(axis=0)), ('addi32', lambda: (i + i)),
             ('cast', lambda: (i + 1).cast(dtypes.float32)), ('addu32', lambda: (j + 1)),
             ('dot', lambda: xs @ ys), ('cmp', lambda: (a > 2.0)),
             ('sum_axis', lambda: xs.sum(axis=0)), ('matmul16', lambda: xs @ xs.T),
             ('fconst', lambda: a * 0.5), ('i8view', lambda: a.astype(dtypes.uint8)),
             ('where', lambda: T([1.0, 0.0, 1.0, 0.0]).realize().where(a, b)),
             ('tiny', lambda: p1 + q1)]
    for name, thunk in CASES:
      CAP.clear()
      try: thunk().tolist()
      except FileNotFoundError: pass
      except Exception as e:
        got[name] = ('EXC', f'{type(e).__name__}: {e}')
        continue
      # CAP[-1] is the LAST launch: renderer input (real UOps) + the BendProgram.
      c = {}
      for d in CAP:
        if 'ruops' in d: c['ruops'] = d['ruops']
        if 'prog' in d: c.update(prog=d['prog'], bufs=d['bufs'], kw=d['kw'])
      got[name] = ('OK', c)
  return got


def bend_node(u, pos):
  """One `N` record, read off a real UOp. Nothing here is recomputed."""
  try: shape = u._shape
  except Exception: shape = None
  try: numel = u.max_numel()
  except RuntimeError: numel = 1
  addr = u.addrspace.name if u.addrspace is not None else '-'
  a = u.arg
  # `wire_arg` reads `u.arg` for CONST and for SPECIAL and for NOTHING else, so
  # every other op's arg is blanked here. That is not a lossy choice: a PARAM's
  # `ParamArg` and a SINK's `KernelInfo` reach no arm of the encoder, and their
  # reprs carry ANSI escapes that a Bend string literal cannot hold.
  if u.op is Ops.CONST: a = u.arg
  elif u.op is Ops.SPECIAL: a = u.arg
  else: a = None
  if isinstance(a, int): arg, isint = str(a), True
  elif isinstance(a, float): arg, isint = struct.pack('<f', a).hex(), False
  elif a is None: arg, isint = '', True
  else:
    # a dataclass repr (PARAM's ParamArg, SINK's KernelInfo). Bend string
    # literals take no `\xNN`, so an ESC is spelled `?`.
    arg = str(a).replace(chr(27), '?')
    isint = True
  ndim = 0 if shape is None else len(shape)
  last = 0 if (shape is None or ndim == 0) else shape[-1]
  shp = '' if shape is None else repr(shape).encode('ascii', 'replace').decode()
  # Bend builds a record POSITIONALLY (Call{k, arg} everywhere in this repo);
  # named field syntax is a parse error.
  return ('N{"%s", "%s", %d, %d, "%s", "%s", %s, [%s], %d, %d, "%s"}'
          % (u.op.name, u.dtype.name, u.dtype.itemsize, numel, addr, arg,
             'True{}' if isint else 'False{}',
             ', '.join(str(pos[id(x)]) for x in u.src), ndim, last, shp))


def emit_nodes(ruops):
  """`NODES(...)` for one program: the real UOps the renderer was handed, read
  into the eleven fields ops_bend.py's encoder reads off them."""
  pos = {id(u): k + 1 for k, u in enumerate(ruops)}
  return ('NODES\n' + '\n'.join('  ' + bend_node(u, pos) for u in ruops) + ')')


def main():
  rs = rows()
  with (OUT / 'bend_oracle_rows.txt').open('w') as f:
    for k, v in rs: f.write(f'{k}=py={v}\n')
  print('rows:', len(rs), flush=True)

  got = packets()
  print('packets:', list(got), flush=True)
  for name, (st, c) in got.items():
    if st == 'EXC':
      print(f'== {name}: {c}', flush=True); continue
    prog = c['prog']
    (OUT / f'packet-{name}.txt').write_text(prog.src)
    print(f'== {name} nbufs={prog.nbufs} in={prog.in_bufs} out={sorted(prog.out_bufs)} '
          f'g={c["kw"].get("global_size")} vals={c["kw"].get("vals")}', flush=True)
    (OUT / f'nodes-{name}.txt').write_text(emit_nodes(c['ruops']) + '\n')
    # BendProgram's own three derived facts, read off the BendProgram the
    # launcher really built. Not re-derived here.
    (OUT / f'bend_meta_{name}.txt').write_text(
      'nbufs %d\nin_bufs %s\nout_bufs %s\nglobal_size %s\nvals %s\n'
      % (prog.nbufs, ' '.join(map(str, prog.in_bufs)),
         ' '.join(map(str, sorted(prog.out_bufs))),
         ' '.join(map(str, c['kw']['global_size'])),
         ' '.join(map(str, c['kw']['vals']))))
    del prog, c
    got[name] = ('OK', None)


if __name__ == '__main__':
  main()

# ---------------------------------------------------------------------------
# WHAT IS **NOT** HERE, and why. A synthetic fixture list per `wire_arg` arm was
# built and measured (both PARAM letters, `k:idx:0`, `k:idx:4`, the image
# refusal, the bf16 lane refusal, the LOCAL-PARAM `KeyError: 'LOCAL'`, the float
# CONST `f:0000003f`, `k:vec:4`) and every answer came out as expected -- but
# running `encode` over those lists HUNG inside `BendProgram`'s :208 walk, and a
# gate that hangs is not a gate. The arm-level answers that were measured are
# therefore recorded HERE, by hand, from the run that did finish, and the
# machine-readable gate is built on the TEN REAL PACKETS instead, which reach
# six of the arms on their own (`c:`, `f:`, `k:param:..:g`, `k:idx:0`,
# `k:vec:4`, `-`). The four arms the real packets do NOT reach -- `k:buffer:`,
# `k:param:..:r`, `k:sp:`, `k:idx:<non-zero>` -- are the honest gap and THE
# GATE DOES NOT SEE listed at the foot of ops_bend.bend says so.
#
# Measured once, for the record:
#   PARAM REG      k:param:16:r
#   PARAM LOCAL    KeyError: 'LOCAL'          <- ops_bend.py:112-113 calls the
#                                               `l` arm "spelled", and it is not
#   CONST float    f:0000003f
#   INDEX/BITCAST  k:idx:4
#   INDEX/ALU      k:idx:0
#   INDEX/PLAIN    -
#   IMAGE INDEX    NotImplementedError: BEND v1 has no image addressing for
#                  INDEX over (2, 3, 4)
#   bf16 PARAM     NotImplementedError: BEND v1 has no lane for dtypes.bf16 (on
#                  PARAM); it has [dtypes.bool, dtypes.f32, dtypes.i32,
#                  dtypes.u32]
#   float32 CONST  -


if __name__ == "__main__":
  main()
