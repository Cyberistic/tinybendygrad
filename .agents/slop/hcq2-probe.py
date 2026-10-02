"""CPython oracle probe for hcq2.py. Every expectation in hcq2.bend is generated
BY CALLING THIS, never hand-typed. Run with DEV=NULL so no device is present."""
import sys
sys.path.insert(0, '.')
import ctypes
import tinygrad.runtime.support.hcq2 as H
from tinygrad.runtime.support.hcq2 import (CDTYPE, HCQ_DEVS, HCQ_CACHE_THRESH, to_name, all_devices_in,
                                           layout_args, pack_args, BatchCtx, timeline, timeline_value, make_submit,
                                           STAGING_SIZE, STAGING_SLOTS)
from tinygrad.runtime.ops_qcom import kgsl
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, KernelInfo, CallInfo, ProgramInfo

def buf(nm): return UOp.placeholder((8,), dtypes.uint64, 0, device=('NULL:0',), tag=nm)
b0, b1, b2 = buf('a'), buf('b'), buf('c')
r = UOp.range(8, 0)

def mk(bufs, outs=(0,), ins=(1,)):
  sink = UOp(Ops.SINK, src=((r+r).cast(dtypes.uint64),), arg=KernelInfo("k"))
  prg = UOp(Ops.PROGRAM, src=(sink,), arg=ProgramInfo(outs=outs, ins=ins))
  return UOp(Ops.CALL, src=(prg, *bufs), arg=CallInfo())

batch = [(mk([b0, b1]), ('NULL:0',), 'COMPUTE:0'),
         (mk([b1, b2]), ('NULL:0',), 'COPY:0'),
         (mk([b2, b0]), ('NULL:0',), 'COPY:1')]

print('=== module constants')
print('HCQ_CACHE_THRESH', HCQ_CACHE_THRESH.value)
print('HCQ_DEVS', sorted(HCQ_DEVS))
print('CDTYPE', sorted((k, v.name, v.itemsize) for k, v in CDTYPE.items()))
print('STAGING_SIZE', STAGING_SIZE, 'STAGING_SLOTS', STAGING_SLOTS)

print('=== to_name (hcq2.py:63)')
for parts in (('submit', 'NV', 'COMPUTE:0'), ('cmdbuf', 'COPY:1'), ('submit', 'QCOM', 'COPY:0'),
              ('KERNEL', 'Foo:Bar'), ('a:b:c',), ('X',), ('',), ('nv', 'compute')):
  print('to_name', parts, '->', repr(to_name(*parts)))

print('=== all_devices_in (hcq2.py:38)')
for d, c in ((('NV:0',), HCQ_DEVS), (('CUDA:1:2',), HCQ_DEVS), (('CPU',), HCQ_DEVS),
             (('NULL',), HCQ_DEVS), (('NV:0', 'AMD'), HCQ_DEVS), ('NV:0', HCQ_DEVS),
             ((), HCQ_DEVS), (('NVX',), HCQ_DEVS), (('METAL:1',), HCQ_DEVS)):
  print('all_devices_in', d, '->', all_devices_in(d, c))

print('=== layout_args (hcq2.py:74-76)')
buf3 = [buf('a'), buf('b'), buf('c')]
mixed = [UOp.const(1, dtypes.uchar), UOp.const(2, dtypes.uint), UOp.const(3, dtypes.uint16),
         UOp.const(4, dtypes.ulong), UOp.const(5, dtypes.uint32), UOp.const(6, dtypes.uint8)]
five32 = [UOp.const(i, dtypes.uint32) for i in range(5)]
ints = [7, 8, 9]
one16 = [UOp.const(1, dtypes.uint16)]
odd = [UOp.const(1, dtypes.uint32), UOp.const(2, dtypes.uint8), UOp.const(3, dtypes.uint64)]
for nm, a in (('buf3', buf3), ('mixed', mixed), ('five32', five32), ('ints', ints),
              ('one16', one16), ('odd', odd)):
  for off in (0, 256, 512):
    print('layout', nm, off, '->', [o for o, _ in layout_args(a, off)])

print('=== layout_args word dtypes (the words themselves, in order)')
for nm, a in (('mixed', mixed), ('ints', ints)):
  print('layout_words', nm, '->', [str(w.dtype) for _, w in layout_args(a, 0)])

print('=== pack_args (hcq2.py:78-83)')
def pk(rows, size):
  try:
    return [('BINARY', len(bytes(w.arg))) if w.op is Ops.BINARY else ('W', str(w.dtype)) for w in pack_args(rows, size)]
  except Exception as e:
    return ('ERR', type(e).__name__)
for nm, a, sizes in (('buf3', buf3, (24, 32, 40)), ('mixed', mixed, (32, 40, 64))):
  for size in sizes:
    print('pack', nm, size, '->', pk(layout_args(a, 0), size))
print('pack buf3 at8 size32 ->', pk(layout_args(buf3, 8), 32))
print('pack buf3 at8 size40 ->', pk(layout_args(buf3, 8), 40))
print('pack buf3 at512 size536 ->', pk(layout_args(buf3, 512), 536))
print('pack mixed size24 (underflow) ->', pk(layout_args(mixed, 0), 24))
print('pack empty size0 ->', pk([], 0))
print('pack empty size8 ->', pk([], 8))

print('=== cstruct field tables (hcq2.py:100-101)')
for st in (kgsl.struct_kgsl_command_object, kgsl.struct_kgsl_gpu_command):
  flds = {n: (o, CDTYPE[ctypes.sizeof(t)]) for n, t, o, *_ in st._real_fields_ if ctypes.sizeof(t)}
  print('struct', st.__name__, 'sizeof', ctypes.sizeof(st))
  for n, t, o, *_ in st._real_fields_:
    print('   field', n, 'at', o, 'size', ctypes.sizeof(t), 'cdtype', str(flds.get(n, ('skipped',))[1]))
  # the qcom.py:197-198 row order IS the kwargs order
  print('   flds order', [(n, flds[n][0], str(flds[n][1])) for n in flds])
  for names in (('gpuaddr', 'size', 'flags'), ('cmdlist', 'cmdsize', 'numcmds', 'context_id')):
    if all(n in flds for n in names):
      print('   cstruct rows', ','.join(names), '->', [(flds[n][0], str(flds[n][1])) for n in names])

print('=== BatchCtx')
ctx = H.BatchCtx(batch, False)
ctxp = H.BatchCtx(batch, True)
print('queues', sorted((k, v) for k, v in ctx.queues.items()))
print('last', sorted((k, v) for k, v in ctx.last.items()))
print('prev', ctx.prev)
print('peers', sorted((k, sorted(v)) for k, v in ctx.peers.items()))
print('signal_tags', sorted(ctx.signal_tags))
print('epilogue_queue NULL:0', ctx.epilogue_queue('NULL:0'))
print('slots NULL:0', ctx.slots['NULL:0'].max_numel(), 'NULL', ctx.slots['NULL'].max_numel())
print('P slots NULL:0', ctxp.slots['NULL:0'].max_numel(), 'NULL', ctxp.slots['NULL'].max_numel())
for t in range(3):
  print('stamps', t, ctx.stamps(('NULL:0',), t), 'P', ctxp.stamps(('NULL:0',), t))
for i in range(4):
  print('slot', i, 'marg', ctx.slot(('NULL:0',), i).marg)
print('queue_signal COMPUTE:0', ctx.queue_signal(('NULL:0',), 'COMPUTE:0').marg)
print('queue_signal COPY:1', ctx.queue_signal(('NULL:0',), 'COPY:1').marg)
print('sched_timeline', ctx.sched_timeline(('NULL:0',)).marg)

print('=== _wait_ins (hcq2.py:242-252) / _start_ins (:254-256)')
for i, (l, d, q) in enumerate(batch):
  print('wait_ins', i, [(u.op.name, u.arg, tuple(s.op.name for s in u.src)) for u in H._wait_ins(ctx, l, d[0], q, i)])
print('start_ins', [(u.op.name, u.arg, tuple(s.op.name for s in u.src)) for u in H._start_ins(ctx, 'NULL:0', 'COMPUTE:0')])

print('=== _build_queues (hcq2.py:258-283) THE STEP ORDER')
for k, v in H._build_queues(ctx).items():
  print('Q', k, [u.op.name + (':' + str(u.arg) if u.op is Ops.INS else '') for u in v])
for k, v in H._build_queues(ctxp).items():
  print('QP', k, [u.op.name + (':' + str(u.arg) if u.op is Ops.INS else '') for u in v])

print('=== _finalize_batch (hcq2.py:285-311)')
fb = H._finalize_batch(ctx)
print('finalize', fb.op.name, fb.arg.aux.device, 'nargs', fb.arg.aux.nargs, 'table', fb.arg.aux.table)
print('kerns', [(k[0], k[1], k[3], k[4], k[5]) for k in fb.arg.aux.kernels])
print('written_bufs', len(fb.arg.aux.written_bufs))
print('host_deps', fb.arg.aux.host_deps)
print('body sink', fb.body.arg.name, fb.body.tag)
for s in fb.body.src[0].src:
  print('  cmds', s.op.name, s.arg if s.op.name == Ops.LINEAR else '')
print('submit src', [(u.op.name, u.arg if u.op.name == 'CUSTOM_FUNCTION' else '') for u in fb.body.src])
print('slots args', [(str(s.dtype), s.max_numel(), tuple(s.device), s.tag) for s in fb.src[1:]])

print('=== sched_batches queue naming (hcq2.py:314-333)')
print('num_peers_formula', 'COPY:{((pi-pj)-1)%len(peers)%num_queues}')
for pi, pj, np_, nq in ((0, 1, 2, 1), (1, 0, 2, 1), (0, 1, 2, 2), (3, 1, 4, 8), (2, 0, 3, 1), (0, 3, 4, 8)):
  print('copyq', pi, pj, np_, nq, '->', f"COPY:{(pi-pj-1)%np_%nq}")

print('=== timeline / make_submit (hcq2.py:65-70)')
tl = timeline(('NULL:0',))
print('timeline', tl.op.name, tl.shape, tl.dtype, tl.tag, tl.arg)
print('timeline_value', timeline_value(('NULL:0',)).op.name, [s.op.name for s in timeline_value(('NULL:0',)).src])
sm = make_submit(UOp(Ops.NOOP), UOp(Ops.NOOP), devs='NULL:0', queue='COPY:0')
print('make_submit body arg', sm.body.arg[0], sm.body.arg[1], 'nsrc', len(sm.body.src))
sm2 = make_submit(UOp(Ops.NOOP), devs=('AMD:0', 'AMD:1'), queue='COMPUTE:0')
print('make_submit tuple', sm2.body.arg[0], sm2.body.arg[1])