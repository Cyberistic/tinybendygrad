"""CPython oracle #2 for hcq2.py: the BATCH. `BatchCtx.__post_init__`,
`_wait_ins`, `_start_ins`, `_build_queues` and `_finalize_batch`, over several
batch SHAPES so the gate is not fitted to one fixture.

`BatchCtx.__post_init__` needs real UOps and `Device.canonicalize`, so this runs
with DEV=NULL -- no device is present and `hcq2.py` imports cleanly, exactly as
ops_cl's oracle did for its own vendor tables.
"""
import sys
sys.path.insert(0, '.')
import tinygrad.runtime.support.hcq2 as H
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, KernelInfo, CallInfo, ProgramInfo

def buf(nm):
  return UOp.placeholder((8,), dtypes.u64, 0, device=('NULL:0',), tag=nm)

B = {n: buf(n) for n in 'abcdef'}
r = UOp.range(8, 0)
sink = UOp(Ops.SINK, src=((r + r).cast(dtypes.u64),), arg=KernelInfo("k"))

def mk(bufs):
  prg = UOp(Ops.PROGRAM, src=(sink,), arg=ProgramInfo(outs=(0,), ins=(1,)))
  return UOp(Ops.CALL, src=(prg, *bufs), arg=CallInfo())

# Each fixture is a list of (device, queue, (bufrange0, bufrange1)). bufrange0 is
# WRITTEN (ProgramInfo.outs = (0,)) and bufrange1 is READ.
SHAPES = {
  'three': [('NULL:0', 'COMPUTE:0', ('a', 'b')), ('NULL:0', 'COPY:0', ('b', 'c')),
            ('NULL:0', 'COPY:1', ('c', 'a'))],
  'two':    [('NULL:0', 'COMPUTE:0', ('a', 'b')), ('NULL:0', 'COMPUTE:0', ('b', 'a'))],
  'fifo':   [('NULL:0', 'COMPUTE:0', ('a', 'b')), ('NULL:0', 'COMPUTE:0', ('c', 'd'))],
  'copyq':  [('NULL:0', 'COMPUTE:0', ('a', 'b')), ('NULL:0', 'COPY:0', ('c', 'a'))],
  'revis':  [('NULL:0', 'COMPUTE:0', ('a', 'b')), ('NULL:0', 'COMPUTE:0', ('c', 'd')),
             ('NULL:0', 'COMPUTE:0', ('b', 'e'))],
}

def step(u):
  if u.op is Ops.INS: return 'INS_' + u.arg[0]
  if u.op is Ops.CALL: return 'CALL'
  return u.op.name

def show(cmds): return ' '.join(step(u) for u in cmds)

def marg(u):
  a = u.marg
  return str(a[0][0]) if a else '-'

def emit(nm, v): print(f"{nm}={v}")

for nm, shp in SHAPES.items():
  batch = [(mk([B[x], B[y]]), (d,), q) for d, q, (x, y) in shp]
  for prof in (False, True):
    sfx = '' if not prof else '_p'
    ctx = H.BatchCtx(batch, prof)
    devs = sorted({d[0] for _, d, _ in batch})
    emit(f'hq2_b{nm}{sfx}_npairs', len({(d[0], q) for _, d, q in batch}))
    for d in devs:
      dn = d.replace(':', '')
      emit(f'hq2_b{nm}{sfx}_nq', len(ctx.queues.get(d, [])))
      emit(f'hq2_b{nm}{sfx}_slots', ctx.slots[d].max_numel())
      emit(f'hq2_b{nm}{sfx}_epi', ctx.epilogue_queue(d))
      emit(f'hq2_b{nm}{sfx}_stl', marg(ctx.sched_timeline((d,))))
    emit(f'hq2_b{nm}{sfx}_sig_tags', ' '.join(str(t) for t in sorted(ctx.signal_tags)))
    emit(f'hq2_b{nm}{sfx}_prevcnt', sum(1 for p in ctx.prev if p is None))
    emit(f'hq2_b{nm}{sfx}_prevlast', ctx.prev[-1] if ctx.prev[-1] is not None else 0)
    emit(f'hq2_b{nm}{sfx}_npeers', len(ctx.peers.get((batch[0][1][0], batch[0][2]), ())))
    for tag, (_, d, q) in enumerate(batch):
      emit(f'hq2_b{nm}{sfx}_wait{tag}', show(H._wait_ins(ctx, batch[tag][0], d[0], q, tag)))
      st = ctx.stamps(d, tag)
      emit(f'hq2_b{nm}{sfx}_stamps{tag}', ' '.join(str(s) for s in st) if st else '-')
      emit(f'hq2_b{nm}{sfx}_qsig{tag}', marg(ctx.queue_signal(d, q)))
    emit(f'hq2_b{nm}{sfx}_start0', show(H._start_ins(ctx, batch[0][1][0], batch[0][2])))
    qs = H._build_queues(ctx)
    emit(f'hq2_b{nm}{sfx}_nqueues', len(qs))
    for (d, q), cmds in qs.items():
      key = f'{d[0].replace(":", "")}_{q.replace(":", "")}'
      emit(f'hq2_b{nm}{sfx}_q_{key}', show(cmds))
    fb = H._finalize_batch(ctx)
    emit(f'hq2_b{nm}{sfx}_final_devs', ' '.join(fb.arg.aux.device))
    emit(f'hq2_b{nm}{sfx}_final_kerns', len(fb.arg.aux.kernels))
    emit(f'hq2_b{nm}{sfx}_final_nargs', fb.arg.aux.nargs)
    emit(f'hq2_b{nm}{sfx}_final_table', fb.arg.aux.table)
    emit(f'hq2_b{nm}{sfx}_final_tag', fb.body.tag)
    emit(f'hq2_b{nm}{sfx}_final_name', fb.body.arg.name)
    emit(f'hq2_b{nm}{sfx}_final_nsubs', len(fb.src) - 1)
    emit(f'hq2_b{nm}{sfx}_final_skipwait', fb.arg.aux.skip_wait)

# The pure geometry, asked of ONE BatchCtx, because the slots formula is the
# `2 * (nq + 1 + 2*ncall if profile)` of hcq2.py:232.
batch = [(mk([B['a'], B['b']]), ('NULL:0',), 'COMPUTE:0'), (mk([B['b'], B['c']]), ('NULL:0',), 'COPY:0'),
         (mk([B['c'], B['a']]), ('NULL:0',), 'COPY:1')]
for prof in (False, True):
  ctx = H.BatchCtx(batch, prof)
  sfx = '' if not prof else '_p'
  emit(f'hq2_geom{sfx}_slots', ctx.slots['NULL:0'].max_numel())
  emit(f'hq2_geom{sfx}_peerslots', ctx.slots['NULL'].max_numel())
  for i in range(4):
    emit(f'hq2_geom{sfx}_slot{i}', marg(ctx.slot(('NULL:0',), i)))
  emit(f'hq2_geom{sfx}_qsig_c0', marg(ctx.queue_signal(('NULL:0',), 'COMPUTE:0')))
  emit(f'hq2_geom{sfx}_qsig_c1', marg(ctx.queue_signal(('NULL:0',), 'COPY:1')))
  emit(f'hq2_geom{sfx}_stl', marg(ctx.sched_timeline(('NULL:0',))))
  emit(f'hq2_geom{sfx}_qsig_c0', marg(ctx.queue_signal(('NULL:0',), 'COMPUTE:0')))
  emit(f'hq2_geom{sfx}_qsig_c1', marg(ctx.queue_signal(('NULL:0',), 'COPY:1')))
  emit(f'hq2_geom{sfx}_stl', marg(ctx.sched_timeline(('NULL:0',))))
  for t in range(4):
    st = ctx.stamps(('NULL:0',), t)
    emit(f'hq2_geom{sfx}_stamps{t}', ' '.join(str(x) for x in st) if st else '-')
  # :237 is `2*i, 2*i+2` -- TWO u64 slots, [signal] then [timestamp], per the
  # comment at :231. The width is a claim.
