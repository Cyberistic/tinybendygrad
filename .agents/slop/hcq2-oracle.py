"""CPython oracle for tinybendygrad/runtime/support/hcq2.bend.

Prints `name=value` lines in EXACTLY the same format and with the SAME row
names as the Bend gate, so `.agents/slop/hcq2-diff.py` can diff the two lanes as
strings. Every value here is ANSWERED BY CALLING hcq2.py -- never typed.

    DEV=NULL .venv/bin/python .agents/slop/hcq2-oracle.py > /tmp/oracle.txt
"""
import sys
sys.path.insert(0, '.')
import ctypes
from tinygrad.runtime.ops_qcom import kgsl
from tinygrad.runtime.support.hcq2 import (CDTYPE, HCQ_DEVS, HCQ_CACHE_THRESH, to_name, all_devices_in,
                                           layout_args, pack_args, STAGING_SIZE, STAGING_SLOTS, HWQueue)
import tinygrad.runtime.support.hcq2 as H
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, KernelInfo, CallInfo, ProgramInfo
from tinygrad.helpers import round_up

def emit(nm, v): print(f"{nm}={v}")
def b(x): return str(bool(x))

# ===========================================================================
def consts():
  emit('hq2_cache_thresh', HCQ_CACHE_THRESH.value)
  emit('hq2_devs_n', len(HCQ_DEVS))
  names = ['NV', 'QCOM', 'CUDA', 'NULL', 'METAL', 'AMD']
  for i, n in enumerate(names, 1):
    emit(f'hq2_dev_name_{i}', n)
  emit('hq2_dev_name_0', 0)
  for n in names: emit(f'hq2_dev_id_{n}', 1 + names.index(n))
  for n in ('CPU', 'NVX', 'nv'): emit(f'hq2_dev_id_{n}', 0)
  for nm, ix in (('NV0', 'NV:0'), ('NV01', 'NV:0:1'), ('CPU012', 'CPU:0:1:2'),
                 ('bare', 'AMD'), ('nocolon', 'METAL:1')):
    emit(f'hq2_dev_head_{nm}', ix.split(':')[0])
  for s in (1, 2, 4, 8, 3, 0, 16): emit(f'hq2_cdtype_{s}', CDTYPE[s].itemsize if s in CDTYPE else 0)
  emit('hq2_cdtype_len', len(CDTYPE))
  for s in (1, 2, 4, 8): emit(f'hq2_cdtype_roundtrips_{s}', b(CDTYPE[s].itemsize == s))
  for s in (3, 16): emit(f'hq2_cdtype_rejects_{s}', b(s not in CDTYPE))
  emit('hq2_cdtype_accepts_4', b(4 in CDTYPE))
  emit('hq2_staging_size', STAGING_SIZE)
  emit('hq2_staging_slots', STAGING_SLOTS)
  emit('hq2_mock_staging_size', 4 << 20)
  emit('hq2_staging_slot_bytes', STAGING_SIZE // STAGING_SLOTS)
  for it in (1, 4, 2, 8): emit(f'hq2_chunk_it{it}', (STAGING_SIZE // STAGING_SLOTS) // it)
  slot = STAGING_SIZE // STAGING_SLOTS
  for (nm, numel, it) in (('1000_it1', 1000, 1), ('1000_it4', 1000, 4), ('big_it2', 67108865, 2), ('big_it1', 134217729, 1)):
    ch = slot // it
    emit(f'hq2_copies_{nm}', -(-numel // ch))
  for i in (0, 1, 2, 3):
    emit(f'hq2_slot_at_{i}_it1', (i % STAGING_SLOTS) * slot)
    emit(f'hq2_slot_at_{i}_it4', (i % STAGING_SLOTS) * (slot // 4) * 4)

# ===========================================================================
def names():
  for nm, parts in (('submit', ('submit', 'NV', 'COMPUTE:0')), ('cmdbuf', ('cmdbuf', 'COPY:1')),
                    ('qcom', ('submit', 'QCOM', 'COPY:0')), ('colon2', ('KERNEL', 'Foo:Bar')),
                    ('dblcolon', ('a:b:c',)), ('single', ('X',)), ('empty', ('',)),
                    ('lower', ('nv', 'compute')), ('order', ('COMPUTE', '0')),
                    ('under', ('a_b', 'c')), ('noseps', ('a', 'b'))):
    emit(f'hq2_toname_{nm}', to_name(*parts))
  for nm, devs, q in (('null', 'NULL:0', 'COPY:0'), ('amd', 'AMD:0', 'COPY:3'),
                    ('cuda', 'CUDA:1', 'COMPUTE:0'), ('qcom_encdec', 'QCOM:0', 'ENCDEC:0')):
    emit(f'hq2_submit_name_{nm}', to_name('submit', devs.split(':')[0], q.split(':')[0]))

# ===========================================================================
def allin():
  for nm, d in (('nv0', ('NV:0',)), ('cuda12', ('CUDA:1:2',)), ('cpu', ('CPU',)), ('null', ('NULL',)),
                ('nv_amd', ('NV:0', 'AMD')), ('bare', 'NV:0'), ('empty', ()), ('nvx', ('NVX',)),
                ('metal1', ('METAL:1',)), ('cpu_nv', ('CPU', 'NV')), ('amd012', ('AMD:0:1:2',)),
                ('nvx0', ('NVX:0',))):
    emit(f'hq2_all_in_{nm}', b(all_devices_in(d, HCQ_DEVS)))

# ===========================================================================
def buf(nm, n=1, dt=dtypes.uint64): return UOp.placeholder((n,), dt, 0, device=('NULL:0',), tag=nm)
def ks_to_words(ks): return [UOp.const(i + 1, {1: dtypes.uint8, 2: dtypes.uint16, 4: dtypes.uint32, 8: dtypes.uint64}[k])
                             for i, k in enumerate(ks)]
def offs(ks, base): return [o for o, _ in layout_args(ks_to_words(ks), base)]
def show(xs): return ' '.join(str(x) for x in xs)

BUF3 = [8, 8, 8]
MIXED = [1, 4, 2, 8, 4, 1]
FIVE32 = [4, 4, 4, 4, 4]
INTS = [4, 4, 4]           # `layout_args` makes a python int a uint32 (hcq2.py:75)
ONE16 = [2]
ODD = [4, 1, 8]
def layout():
  for nm, ks in (('buf3', BUF3), ('mixed', MIXED), ('five32', FIVE32), ('ints', INTS),
                 ('one16', ONE16), ('odd', ODD)):
    for base in (0, 256, 512):
      emit(f'hq2_layout_{nm}_{base}', show(offs(ks, base)))
  emit('hq2_layout_buf3_n', len(layout_args(ks_to_words(BUF3), 0)))
  emit('hq2_layout_mixed_n', len(layout_args(ks_to_words(MIXED), 0)))
  emit('hq2_layout_buf0_n', len(layout_args([], 0)))
  # THE KERNEL-ARGUMENT TRACE ITSELF: the word DTYPE list, in order.
  for nm, ks in (('mixed', MIXED), ('ints', INTS), ('buf3', BUF3)):
    emit(f'hq2_layout_words_{nm}', show([w.dtype.itemsize for _, w in layout_args(ks_to_words(ks), 0)]))
  # THE CROSS-IMPLEMENTATION ROW against `device.bend`'s `D.iter_sig`.
  from tinygrad.device import TinyELF
  from tinygrad.uop.ops import UOp as _U
  for nm, ks in (('mixed', MIXED), ('buf3', BUF3), ('five32', FIVE32)):
    sig = list(TinyELF.iter_sig(tuple((None, i, w.dtype, ()) for i, w in enumerate(ks_to_words(ks)))))
    emit(f'hq2_layout_sig_{nm}', show([o for o, _ in sig]))
  # THE THREE OFFSETS ops_nv.bend:205 and :181 PRINT.
  emit('hq2_layout_opsnv_mixed', show(offs(MIXED, 0)))
  emit('hq2_layout_opsnv_buf3var2', show(offs([8, 8, 8, 4, 4], 512)))

# ===========================================================================
def pack():
  def seq(ks, base, size):
    try:
      out = []
      for w in pack_args(layout_args(ks_to_words(ks), base), size):
        out.append(f"{'P' if w.op is Ops.BINARY else 'W'}{len(bytes(w.arg)) if w.op is Ops.BINARY else w.dtype.itemsize}")
      return ' '.join(out)
    except ValueError:
      return 'E0'
  for nm, ks, base in (('buf3_0_24', BUF3, 0), ('buf3_0_32', BUF3, 0), ('buf3_0_40', BUF3, 0),
                       ('mixed_0_32', MIXED, 0), ('mixed_0_40', MIXED, 0), ('mixed_0_64', MIXED, 0),
                       ('buf3_8_32', BUF3, 8), ('buf3_8_40', BUF3, 8), ('buf3_512_536', BUF3, 512),
                       ('mixed_0_24', MIXED, 0)):
    emit(f'hq2_pack_{nm}', seq(ks, base, int(nm.rsplit('_', 1)[1])))
  emit('hq2_pack_empty_0', seq([], 0, 0))
  emit('hq2_pack_empty_8', seq([], 0, 8))
  emit('hq2_pack_empty_16', seq([], 0, 16))
  # THE REFUSAL: `bytes(size - end)` with `end > size` is a ValueError (hcq2.py:83),
  # and `hc2_pack_mixed_0_24` is the row that sees it. A gate that cannot see a
  # raise cannot tell a truncation from a short read.
  emit('hq2_pack_refused_24', b(seq(MIXED, 0, 24) == 'E0'))

# ===========================================================================
def cstruct():
  for st in (kgsl.struct_kgsl_command_object, kgsl.struct_kgsl_gpu_command):
    s = st.__name__.replace('struct_kgsl_', '')
    flds = {n: (o, CDTYPE[ctypes.sizeof(t)]) for n, t, o, *_ in st._real_fields_ if ctypes.sizeof(t)}
    emit(f'hq2_cstruct_{s}_sizeof', ctypes.sizeof(st))
    emit(f'hq2_cstruct_{s}_nfields', len(st._real_fields_))
    emit(f'hq2_cstruct_{s}_nreal', len(flds))
    # THE FIELD ORDER, BY NAME, both directions. `ops_qcom.py:197-198` builds
    # these two descriptors and the ROW ORDER IS THE KWARGS ORDER.
    emit(f'hq2_cstruct_{s}_order', ' '.join(n for n, _, _ in st._real_fields_))
    emit(f'hq2_cstruct_{s}_offs', ' '.join(str(o) for _, _, o in st._real_fields_))
    emit(f'hq2_cstruct_{s}_szs', ' '.join(str(ctypes.sizeof(t)) for _, t, _ in st._real_fields_))
    emit(f'hq2_cstruct_{s}_cdt', ' '.join(str(flds[n][1].itemsize) for n, _, _ in st._real_fields_ if n in flds))
    for nm in st._real_fields_[0][0], 'size', 'flags', 'id', 'cmdlist', 'cmdsize', 'numcmds', 'context_id':
      f = getattr(st, nm, None)
      if f is None: continue
      emit(f'hq2_cfield_{s}_{nm}_at', f.offset)
      emit(f'hq2_cfield_{s}_{nm}_sz', f.size)
    if 'gpuaddr' in flds:
      emit('hq2_cstruct_ib_rows', show([flds[n][0] for n in ('gpuaddr', 'size', 'flags')]))
    if 'cmdlist' in flds:
      ns = ('cmdlist', 'cmdsize', 'numcmds', 'context_id')
      emit('hq2_cstruct_cmd_rows', show([flds[n][0] for n in ns]))
      emit('hq2_cstruct_cmd_rows_k', show([flds[n][1].itemsize for n in ns]))

if __name__ == '__main__':
  consts(); names(); allin(); layout(); pack(); cstruct()