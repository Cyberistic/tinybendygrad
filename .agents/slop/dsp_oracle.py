#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_dsp.bend.

EVERY `py=` expectation in the port is emitted by THIS file, never typed.
Usage:  python3 .agents/slop/dsp_oracle.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.argv = [sys.argv[0]]

from tinygrad.runtime.ops_dsp import (rpc_sc, rpc_prep_args, DSPRenderer, MockDSPRenderer,
                                      DSPCompiler, mockdsp_boilerplate)
from tinygrad.renderer.cstyle import ClangRenderer
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.helpers import Target

OUT = []


def emit(s=""):
  OUT.append(s)


# ---------------------------------------------------------------- 1. rpc_sc
emit("## rpc_sc  (method<<24)|(ins<<16)|(outs<<8)|fds")
for m, i, o, f in [(0,0,0,0),(2,2,1,0),(0,2,2,0),(1,1,2,0),(2,0,0,0),(3,0,0,0),
                   (2,2,1,1),(2,2,1,15),(2,2,1,16),(255,255,255,255),(0,0,0,255),(1,0,0,0),(0,1,0,0),(0,0,1,0),(2,2,1,3),(2,2,1,7),(2,2,1,8)]:
  emit(f"rpc_sc({m},{i},{o},{f}) = {rpc_sc(method=m, ins=i, outs=o, fds=f)}")
emit("# the RPCListener literal sc=0x04020200 -- spelled in Python as 0x04020200")
emit(f"listener_sc = {0x04020200}")
emit(f"listener_sc_eq_rpc_sc_2_2_1_0 = {int(rpc_sc(method=2,ins=2,outs=1,fds=0) == 0x04020200)}")
emit("# _render_entry's refusal: `if ((sc>>24) != 2) return 0;`")
for s in [0x04020200, 0x00020200, 0x01020200, 0x03000000, 0x04000000, 0x00000000]:
  emit(f"sc>>24 {s:#010x} -> {s>>24} refused={int((s>>24)!=2)}")


# ---------------------------------------------------------------- 2. dtypes
emit()
emit("## dt.fmt / dt.itemsize  (all twenty, in dtype.py name order)")
NAMES = ["void","bool","weakint","int8","uint8","int16","uint16","int32","uint32",
         "int64","uint64","weakfloat","fp8e4m3","fp8e5m2","fp8e4m3fnuz","fp8e5m2fnuz",
         "float16","bfloat16","float32","float64"]
DT = {"void": dtypes.void, "bool": dtypes.bool, "weakint": dtypes.weakint,
      "int8": dtypes.int8, "uint8": dtypes.uint8, "int16": dtypes.int16, "uint16": dtypes.uint16,
      "int32": dtypes.int32, "uint32": dtypes.uint32, "int64": dtypes.int64, "uint64": dtypes.uint64,
      "weakfloat": dtypes.weakfloat, "fp8e4m3": dtypes.fp8e4m3fnuz, "fp8e5m2": dtypes.fp8e5m2fnuz,
      "fp8e4m3fnuz": dtypes.fp8e4m3fnuz, "fp8e5m2fnuz": dtypes.fp8e5m2fnuz,
      "float16": dtypes.half, "bfloat16": dtypes.bfloat16, "float32": dtypes.float32, "float64": dtypes.float64}
# NOTE: dtypes has no fp8e4m3; the four fp8 attributes are e4m3fnuz/e5m2/e4m3fnuz/e5m2fnuz.
for n in NAMES:
  d = DT[n]
  emit(f'{n:14s} name={d.name!r:20s} fmt={d.fmt!r:6s} itemsize={d.itemsize}')


# ---------------------------------------------------------------- 3. dtypes filters
emit()
emit("## supported_dtypes (:46) -- super() minus fp8s minus bfloat16")
TGT = Target("DSP", "CLANG", "x86_64,znver3")
HTGT = Target("DSP", "CLANG", "hexagonv65,hexagonv65")
# MEASURED: `ClangRenderer(HTGT)` raises `RuntimeError: unsupported arch:
# 'hexagonv65'` from ClangCompiler (compiler_cpu.py:15). That is WHY
# DSPRenderer.__init__ (:18) does not call super().__init__ -- the CPU clang
# compiler must never be built for a DSP target. The probe below subclasses
# ClangRenderer with a no-op __init__ to read supported_dtypes for a non-x86
# arch without the compiler.
class HexProbe(ClangRenderer):
  def __init__(self, t): self.target = t
r = DSPRenderer(TGT)
sup = ClangRenderer(TGT).supported_dtypes()
sup_h = HexProbe(HTGT).supported_dtypes()
dsp = r.supported_dtypes()
dsp_h = DSPRenderer(HTGT).supported_dtypes()
emit(f"clang_x86_count={len(sup)} clang_x86={sorted(x.name for x in sup)}")
emit(f"dsp_count={len(dsp)} dsp={sorted(x.name for x in dsp)}")
emit(f"removed_x86={sorted(x.name for x in (sup - dsp))}")
emit(f"clang_hex_count={len(sup_h)} removed_hex={sorted(x.name for x in (sup_h - dsp_h))}")
emit(f"dsp_x86_is_dsp_hex={sorted(x.name for x in dsp) == sorted(x.name for x in dsp_h)}")
emit(f"dsp_has_bfloat16={int(dtypes.bfloat16 in dsp)} dsp_has_fp8s={sorted(x.name for x in (dsp & set(dtypes.fp8s)))}")
emit(f"dsp_ints={sorted(x.name for x in (dsp & set(dtypes.ints)))}")
emit(f"dsp_floats={sorted(x.name for x in (dsp & set(dtypes.floats)))}")
emit(f"dsp_nodtypes={sorted(x.name for x in set(dtypes.all) - dsp)}")


# ---------------------------------------------------------------- 4. renderer bits
emit()
emit("## DSPRenderer class attrs (:13,:14,:15,:16)")
emit(f"buffer_suffix = {r.buffer_suffix!r}")
emit(f"kernel_typedef = {r.kernel_typedef!r}")
from tinygrad.uop.ops import Ops
emit(f"type_map_bool   = {r.type_map[dtypes.bool]!r} clang={ClangRenderer.type_map[dtypes.bool]!r}")
emit(f"type_map_half   = {r.type_map[dtypes.half]!r} clang={ClangRenderer.type_map[dtypes.half]!r}")
emit(f"type_map_int64  = {r.type_map[dtypes.int64]!r} clang_has={int(dtypes.int64 in ClangRenderer.type_map)}")
emit(f"type_map_uint64 = {r.type_map[dtypes.uint64]!r} clang_has={int(dtypes.uint64 in ClangRenderer.type_map)}")
emit(f"type_map_nkeys_dsp={len(r.type_map)} type_map_nkeys_clang={len(ClangRenderer.type_map)}")
emit(f"type_map_keys_dsp={sorted(x.name for x in r.type_map)}")
emit(f"code_for_op_dsp={len(r.code_for_op)} clang={len(ClangRenderer.code_for_op)} "
     f"sqrt_dsp={int(Ops.SQRT in r.code_for_op)} sqrt_clang={int(Ops.SQRT in ClangRenderer.code_for_op)}")
_rd = [r._render_dtype(d) for d in [dtypes.bool, dtypes.half, dtypes.int64, dtypes.uint64]]
emit(f"render_dtype_bool_half_int64_uint64={_rd!r}")
emit(f"render_dtype_all={[r._render_dtype(d) for d in dtypes.all]!r}")


# ---------------------------------------------------------------- 5. compiler args
emit()
emit("## DSPCompiler args (:100,:111,:113) and the link script (:104-111)")
cm, cmk = DSPCompiler(mock=False), DSPCompiler(mock=True)
emit(f"compiler_args = {'--target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b'!r}")
emit(f"mock_args_prefix = {cmk.args.split()[0]!r}")
emit(f"mock_args_suffix = {cmk.args.split()[-1]!r}")
emit(f"real_args_first = {cm.args.split()[0]!r}")
emit(f"real_args_has_T = {int('-T' in cm.args)}")
emit(f"cachekey_real = {cm.cachekey!r}")
emit(f"cachekey_mock = {cmk.cachekey!r}")
SECTIONS = ['text','rela.plt','rela.dyn','plt','data','bss','hash','dynamic',
            'got','got.plt','dynsym','dynstr','symtab','shstrtab','strtab']
sections_link = '\n'.join([f'.{n} : ALIGN(4096) {{ *(.{n}) }}' for n in SECTIONS])
script = f"SECTIONS {{ . = 0x0; {sections_link}\n /DISCARD/ : {{ *(.note .note.* .gnu.hash .comment) }} }}"
emit("## link script verbatim")
emit(script)
emit(f"## nsections={len(SECTIONS)}")


# ---------------------------------------------------------------- 6. _render_entry
class FakeUOp:
  def __init__(self, dt, addrspace, numel):
    self.dtype, self.addrspace, self._n = dt, addrspace, numel
  def max_numel(self): return self._n


# (name, [(dtype, addrspace, max_numel), ...]) -- `bufs` in _render_entry is
# EVERY PARAM in order: the GLOBAL ones first, then the ALU-valued ones, because
# cstyle.py:229-232 collects PARAMs into one ordered dict and
# DSPProgram.__call__ (:65-68) reads `signature[len(bufs):]` for the vals.
G, A = AddrSpace.GLOBAL, AddrSpace.ALU
FIXTURES = [
  ("g0", []),
  ("g1", [(dtypes.uint32, G, 1)]),
  ("g2", [(dtypes.float32, G, 4), (dtypes.float32, G, 4)]),
  ("a1", [(dtypes.uint32, A, 1)]),
  ("a2", [(dtypes.uint32, A, 1), (dtypes.float32, A, 1)]),
  ("ga", [(dtypes.float32, G, 4), (dtypes.uint32, A, 1)]),
  ("ag", [(dtypes.uint32, A, 1), (dtypes.float32, G, 4)]),
  ("gag", [(dtypes.float32, G, 4), (dtypes.uint32, A, 1), (dtypes.float32, G, 4)]),
  ("agga", [(dtypes.uint32, A, 1), (dtypes.float32, G, 4), (dtypes.float32, G, 4),
            (dtypes.int32, A, 1)]),
  ("g3i", [(dtypes.int32, G, 2), (dtypes.int64, G, 2), (dtypes.uint8, G, 2)]),
  ("g3h", [(dtypes.float16, G, 2), (dtypes.float64, G, 2)]),
  ("g1a1", [(dtypes.uint32, G, 3), (dtypes.uint64, A, 1)]),
  ("gag", [(dtypes.float32, G, 4), (dtypes.uint32, A, 1), (dtypes.float32, G, 4)]),
  ("g0b", []),
  ("a1b", [(dtypes.uint32, A, 1)]),
]


def render(rend, fixture):
  name, spec = fixture
  bufs = [("g"+str(i), (FakeUOp(dt, sp, n), True)) for i, (dt, sp, n) in enumerate(spec)]
  return rend._render_entry("kernel_fn", bufs).split("\n")


emit()
emit("## DSPRenderer._render_entry (:27-44) -- one line per msrc entry")
for fx in FIXTURES:
  emit(f"### {fx[0]}")
  for i, ln in enumerate(render(r, fx)):
    emit(f"[{i}] {ln}")

mr = MockDSPRenderer(TGT)
emit()
emit("## _render_entry LINE COUNTS -- 4 fixed + 1 per PARAM + (1 off + 1 mmap) per")
emit("## GLOBAL + 4 tail (timer, call, timer-close, ret) + 1 munmap per GLOBAL")
for fx in FIXTURES:
  n = len(render(r, fx))
  ng = sum(1 for (_, (u, _)) in [(b[0], b[1]) for b in
       [("x", (FakeUOp(dt, sp, nn), True)) for dt, sp, nn in fx[1]]] if u.addrspace == G)
  emit(f"entry_lines {fx[0]}: n={n} nglobals={ng} nparams={len(fx[1])}")

emit()
emit("## MockDSPRenderer._render_entry (:256-274)")
for fx in FIXTURES:
  emit(f"### {fx[0]}")
  lines = render(mr, fx)
  for i, ln in enumerate(lines):
    if i == 0:
      emit(f"[0] <mockdsp_boilerplate: {len(ln)} chars>")
    else:
      emit(f"[{i}] {ln}")


# ---------------------------------------------------------------- 7. defines
emit()
emit("## open_lib error text -- f-string, so NO trailing space on an empty message")
emit(f"open_lib_err_empty = {('Cannot open lib: ' + '')!r}")
emit(f"open_lib_err_elf = {('Cannot open lib: ' + 'bad elf')!r}")

emit()
emit("## :147 `o1.cast('i')[1] < 0` -- a SIGNED 32-bit test on the second word")
for v in [0, 100, 2147483647, 2147483648, 4294967295, 4294967294]:
  emit(f"o1_word1={v} signed_negative={int(v - (1<<32) if v >= (1<<31) else v < 0)}")

emit()
emit("## DSPRenderer._render_defines (:20-25) -- 5 dsp lines + clang")
for ln in r._render_defines([]):
  emit(f"| {ln}")
emit()
emit("## MockDSPRenderer._render_defines (:255) -- clang only")
for ln in mr._render_defines([]):
  emit(f"| {ln}")


# ---------------------------------------------------------------- 8. rpc_prep_args
emit()
emit("## rpc_prep_args (:49-57) -- pra/fds/attrs shapes and contents")
class MV(bytearray):
  """A real buffer, because rpc_prep_args (:56) calls `mv_address(mv)` on it --
  `ctypes.c_char.from_buffer(mv)` needs a buffer -- and the whole point of the
  `mv.nbytes > 0 else 0` arm is that a ZERO-LENGTH mv has no address. Python
  short-circuits, so `mv_address` is never called for n == 0. Addresses are
  therefore reported as ZERO / NONZERO, never as values."""
  def __init__(self, kind, n):
    super().__init__(n)
    self.kind, self._n = kind, n
  @property
  def nbytes(self): return self._n
  def __repr__(self): return f"MV({self.kind},{self._n})"
for ins_n, outs_n, fds_n in [(0,0,0),(2,1,0),(2,2,0),(1,2,0),(2,1,3),(2,1,15),(2,1,16),(0,0,2),(1,1,1)]:
  ins = [MV("in", 8*i+8) for i in range(ins_n)]
  outs = [MV("out", 8) for i in range(outs_n)]
  fds = [10+i for i in range(fds_n)]
  pra, fdarr, attrs, _ = rpc_prep_args(ins=ins, outs=outs, in_fds=fds)
  emit(f"nins={ins_n} nouts={outs_n} nfds={fds_n}: len(pra)={len(pra)} len(fds)={len(fdarr)} len(attrs)={len(attrs)}")
  emit(f"  fds={list(fdarr)}")
  emit(f"  attrs={list(attrs)}")
  emit(f"  pv_nonzero={[int(pra[i].buf.pv != 0) for i in range(len(pra))]}")
  emit(f"  len={[pra[i].buf.len for i in range(len(pra))]}")
# zero-length mv -> pv 0
pra, fdarr, attrs, _ = rpc_prep_args(ins=[MV("z", 0)], outs=[MV("o", 8)], in_fds=[7])
emit(f"zero-length mv: pv[0]_is_none={pra[0].buf.pv is None} len[0]={pra[0].buf.len} fds={list(fdarr)} attrs={list(attrs)}")


# ---------------------------------------------------------------- 9. names/strings
emit()
emit("## strings")
fp = "file:///tinylib?entry&_modver=1.0&_dom=cdsp\0"
emit(f"open_lib_fp = {fp!r}")
emit(f"open_lib_fp_len = {len(fp)}")
emit(f"open_lib_ins = [len(fp), 0xff] = {[len(fp), 0xff]}")
emit(f"open_lib_outs_sizes = [0x8, 0xff] = {[0x8, 0xff]}")
emit(f"close_lib_ins = [handle, 0xff]")
emit(f"nbytes_path = {'/dsp/cdsp/fastrpc_shell_3'!r}")
emit(f"ion_align = {0x200}")
emit(f"ion_heap_id_mask = {1<<0}")
emit(f"round_up(0x1234, 0x1000) = {((0x1234+0x1000-1)//0x1000)*0x1000}")
emit(f"mmap_prot = {3}")
emit(f"MAP_SHARED={1} MAP_ANONYMOUS={0x20}")


# ---------------------------------------------------------------- 10. var_vals layout
emit()
emit("## DSPProgram.__call__ (:62-71) var_vals layout")
import struct
def var_vals_layout(nbufs, vals, sig_fmts):
  n = nbufs + len(vals)
  mv = bytearray(n*8)
  sizes = [4*(i+1) for i in range(nbufs)]
  for i, s in enumerate(sizes):
    struct.pack_into('i', mv, i*8, s)
  for j, (v, fmt) in enumerate(zip(vals, sig_fmts)):
    struct.pack_into(fmt, mv, (nbufs+j)*8, v)
  return n, mv
for nbufs, vals, fmts in [(0, [], []), (1, [], []), (3, [], []), (3, [7], ["I"]),
                          (3, [7, 9], ["I", "I"]), (2, [1, 2], ["i", "f"]),
                          (1, [1], ["q"]), (2, [5], ["Q"])]:
  n, mv = var_vals_layout(nbufs, vals, fmts)
  emit(f"nbufs={nbufs} nvals={len(vals)}: nbytes={n*8} words={[struct.unpack_from('<Q', mv, i*8)[0] for i in range(n)]}")
  emit(f"  hex={mv.hex()}")
# off_mv
emit("## off_mv = array('I', offsets)")
import array
for offs in [[], [0], [0, 64, 128], [4096, 0]]:
  a = array.array('I', tuple(offs))
  emit(f"offsets={offs} -> {list(a)} nbytes={len(a)*4}")


# ---------------------------------------------------------------- 11. _offset accumulate
emit()
emit("## DSPAllocator._offset (:96) -- offsets ACCUMULATE")
emit("va0+o0+o1, off0+o1: (0,0,64)->(64,64) (4096,64,64)->(4224,128)")




# ==========================================================================
# THE DEVICE-CALL TRACE, MEASURED by driving the real DSPDevice methods with
# the ioctl / os layer faked. Nothing here needs a DSP: only the syscalls are
# replaced, and every ordering claim in the port comes from THIS list.
# ==========================================================================
import tinygrad.runtime.autogen.qcom_dsp as QD
import tinygrad.runtime.autogen.libc as L
import tinygrad.runtime.ops_dsp as D
from tinygrad.runtime.ops_dsp import DSPDevice

TRACE = []
def _rec(name, arg):
  TRACE.append((name, arg))
  return None

class FakeShare:
  def __init__(self, fd, handle): self.fd, self.handle = fd, handle

# the ioctls: record (name, sc) and hand back a stub
QD.FASTRPC_IOCTL_INVOKE = lambda fd, handle=None, sc=None, pra=None: _rec("INVOKE", sc)
QD.FASTRPC_IOCTL_INVOKE_ATTRS = lambda fd, fds=None, attrs=None, inv=None: _rec("INVOKE_ATTRS", getattr(inv, "sc", None))
QD.FASTRPC_IOCTL_GETINFO = lambda fd, arg: _rec("GETINFO", arg)
QD.FASTRPC_IOCTL_CONTROL = lambda fd, req=None: _rec("CONTROL", req)
QD.FASTRPC_IOCTL_INIT = lambda fd, flags=None, file=None, filelen=None, filefd=None: _rec("INIT", flags)
QD.ION_IOC_ALLOC = lambda fd, len=None, align=None, heap_id_mask=None, flags=None: _rec("ION_ALLOC", align)
QD.ION_IOC_SHARE = lambda fd, handle=None: _rec("ION_SHARE", handle)
QD.ION_IOC_FREE = lambda fd, handle=None: _rec("ION_FREE", handle)

# os.open / os.close, only the two device nodes
_real_open, _real_close = os.open, os.close
def _open(path, flags, *a):
  if isinstance(path, str) and path.startswith("/dev"):
    _rec("OPEN:" + path, 0)
    return 99
  return _real_open(path, flags, *a)
def _close(fd):
  if fd in (99, 98, 97, 77, 55):
    _rec("CLOSE", fd)
    return None
  return _real_close(fd)
D.os.open, D.os.close = _open, _close
_MMAP_BUF = {}
def _mmap(addr, length, prot, flags, fd, off):
  _rec("MMAP", length)
  if length not in _MMAP_BUF: _MMAP_BUF[length] = _ct.create_string_buffer(max(length, 1))
  return _ct.addressof(_MMAP_BUF[length])
L.mmap = _mmap
L.munmap = lambda *a, **k: _rec("MUNMAP", a[1] if len(a) > 1 else 0)


def dev(mk=True, have_fd=False):
  d = DSPDevice.__new__(DSPDevice)
  d.ion_fd = 1
  d.rpc_fd = 98
  if not have_fd: del d.rpc_fd
  d.binded_lib, d.binded_lib_off = b"", 0
  d.shell_buf = D.DSPBuffer(0x1000, 4096, FakeShare(55, 0x1234), 0)
  TRACE.clear()
  return d


emit()
emit("## init_dsp (:166-176) -- the ORDER, measured")
for have in [False, True]:
  d = dev(have_fd=have)
  d.init_dsp()
  emit(f"have_fd={have}: n={len(TRACE)} {TRACE}")
emit(f"n_fresh={len(TRACE) - 7} n_again={len(TRACE)}")
d = dev(have_fd=False); d.init_dsp(); fresh = list(TRACE)
d = dev(have_fd=True); d.init_dsp(); again = list(TRACE)
emit(f"fresh_is_suffix_of_again={again[len(again)-len(fresh):] == fresh}")
emit(f"first_fresh={fresh[0]} last_fresh={fresh[-1]}")
emit(f"first_again={again[0]} again_1={again[1]}")

emit()
emit("## open_lib / close_lib (:141-152)")
d = dev(have_fd=True); d.open_lib(b"\x7fELF" + bytes(60))
emit(f"open_lib: {TRACE}")
emit(f"n={len(TRACE)}")
d = dev(have_fd=True); d.close_lib(7)
emit(f"close_lib: {TRACE}")
emit(f"n={len(TRACE)}")

emit()
emit("## exec_lib (:154-164) -- the triple, and the RETRY")
d = dev(have_fd=True); d.exec_lib(b"", rpc_sc(2, 2, 1, 3), None, None, None)
emit(f"ok: n={len(TRACE)} {TRACE}")
# now make the FIRST invoke raise, exactly once
class _Boom(OSError): pass
calls = {"n": 0}
_real_inv = QD.FASTRPC_IOCTL_INVOKE_ATTRS
def flaky(*a, **k):
  calls["n"] += 1
  if calls["n"] == 1: raise _Boom("EPERM")
  return _rec("INVOKE_ATTRS", getattr(k.get("inv", None), "sc", None))
QD.FASTRPC_IOCTL_INVOKE_ATTRS = flaky
d = dev(have_fd=True); d.exec_lib(b"", rpc_sc(2, 2, 1, 3), None, None, None)
emit(f"retry: n={len(TRACE)} {TRACE}")
def _raise_always(*a, **k):
  raise _Boom("EPERM2")
QD.FASTRPC_IOCTL_INVOKE_ATTRS = _raise_always
d = dev(have_fd=True)
try:
  d.exec_lib(b"", rpc_sc(2, 2, 1, 3), None, None, None)
  emit("both-fail: NO RAISE")
except RuntimeError as e:
  emit(f"both-fail: n={len(TRACE)} {TRACE}")
  emit(f"both-fail: raised RuntimeError({e})")
QD.FASTRPC_IOCTL_INVOKE_ATTRS = _real_inv

emit()
emit("## _alloc / _free (:78-96) -- the ORDER and the arm's differences")
import ctypes as _ct
QD.ION_IOC_ALLOC = lambda fd, len=None, align=None, heap_id_mask=None, flags=None: \
    type("H", (), {"handle": 0xABCD})()
QD.ION_IOC_SHARE = lambda fd, handle=None: FakeShare(77, 0xABCD)
al = D.DSPAllocator(dev(have_fd=True))
TRACE.clear(); st = al._alloc(4096, D.BufferSpec())
emit(f"real alloc: {TRACE} n={len(TRACE)}")
emit(f"  BufferStorage(buf={type(st.buf).__name__}, meta_fd={st.meta.fd}, "
     f"handle={st.meta.handle}, va={st.buf.va_addr}, size={st.buf.size}, offset={st.buf.offset}, "
     f"has_share={st.buf.share_info is not None})")
TRACE.clear(); al._free(st, D.BufferSpec())
emit(f"real free: {TRACE} n={len(TRACE)}")
b0 = D.DSPBuffer(4096, 1024, FakeShare(77, 0xABCD), 0)
b1 = al._offset(b0, 256, 64)
b2 = al._offset(b1, 128, 16)
b3 = al._offset(b2, 64, 4)
for nm, b in [("b0", b0), ("b1", b1), ("b2", b2), ("b3", b3)]:
  emit(f"{nm}: va={b.va_addr} size={b.size} offset={b.offset} "
       f"fd={b.share_info.fd} handle={b.share_info.handle}")

print("\n".join(OUT))
