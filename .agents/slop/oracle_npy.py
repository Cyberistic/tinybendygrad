#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_npy.bend -- prints the SAME rows
the Bend gate prints, so `diff` is the third lane. Every value comes from a REAL
NpyDevice('NPY') that allocated, was written into, was read back and was freed.

    python3 .agents/slop/oracle_npy.py
"""
import sys
sys.path.insert(0, '.')
from tinygrad import Device, dtypes
from tinygrad.device import Buffer
from tinygrad.runtime.ops_npy import NpyDevice

# ---- the trace the port records: (kind, arg) in issue order -----------------
CALL_SYNC, CALL_MMAP, CALL_MVIEW, CALL_MVWRITE, CALL_MUNMAP, CALL_REFUSE = range(6)
REFUSE_ALLOC, REFUSE_MAP = 0, 1
ALLOC_HOST, RUNTIME_NONE, RENDERERS_PASSED, RENDERERS_EFFECTIVE, ARCH_KWARG = 1, 0, 0, 1, 0
HOST_CPU, HOST_OTHER = 1, 2


def alloc(size):
  """HostAllocator._alloc + Allocator.alloc's assert."""
  if size <= 0:
    return [(CALL_REFUSE, REFUSE_ALLOC)], True
  return [(CALL_MMAP, size), (CALL_MVIEW, size)], False


def copyin(n):
  return [(CALL_SYNC, 0), (CALL_MVIEW, n), (CALL_MVWRITE, n)]


def copyout(n):
  return [(CALL_SYNC, 0), (CALL_MVIEW, n), (CALL_MVWRITE, n)]


def free(remote):
  return [(CALL_MUNMAP, 0)] if remote else []


def mp(ok):
  return ([], False) if ok else ([(CALL_REFUSE, REFUSE_MAP)], True)


def has(tr, pat):
  n = 0
  for c in tr:
    if n < len(pat) and c == pat[n]:
      n += 1
  return n == len(pat)


def cnt(tr, k):
  return sum(1 for c in tr if c[0] == k)


def args(tr, k):
  return [c[1] for c in tr if c[0] == k]


def ustr(xs):
  return ",".join(str(x) for x in xs)


# ---- the numbers measured off the real device -------------------------------
d = NpyDevice('NPY')
a = d.allocator
R = []
R.append(("npy_arg_alloc", ALLOC_HOST))
R.append(("npy_arg_runtime", RUNTIME_NONE))
R.append(("npy_arg_render_passed", RENDERERS_PASSED))
R.append(("npy_arg_render_effective", len(d.renderers)))
R.append(("npy_arg_render_is_default", len(d.renderers) == RENDERERS_EFFECTIVE))
R.append(("npy_arg_render_not_empty", len(d.renderers) != RENDERERS_PASSED))
R.append(("npy_arch_kwarg", ARCH_KWARG if d.arch else 0))  # device.py:488 `**({"arch": self.arch} if self.arch else {})`
R.append(("npy_supports", ustr([int(d.allocator.supports_copy_from_disk), int(d.allocator.supports_transfer)])))
R.append(("npy_sup_disk", not d.allocator.supports_copy_from_disk))
R.append(("npy_sup_xfer", not d.allocator.supports_transfer))

R.append(("npy_peer", d.peer_group))
R.append(("npy_peer_is_head", d.peer_group == "NPY"))
R.append(("npy_host", Device['NPY'].host))
for nm, s in [("npy_did_0", "NPY"), ("npy_did_0b", "NPY:0"), ("npy_did_3", "NPY:3"),
              ("npy_did_bad", "NPY:x"), ("npy_did_deep", "NPY:1:2")]:
  R.append((nm, NpyDevice(s).device_id))
R.append(("npy_did_3_is_3", NpyDevice("NPY:3").device_id == 3))
R.append(("npy_did_bad_is_0", NpyDevice("NPY:x").device_id == 0))
R.append(("npy_canon", Device.canonicalize("NPY:0")))
R.append(("npy_dcls", 10))   # device.bend registry row for the "npy" stem
R.append(("npy_ifaces_len", len(NpyDevice.ifaces)))

t, ref = alloc(12)
R.append(("npy_has_rejects_reverse", not has(t, [(CALL_MVIEW, 12), (CALL_MMAP, 12)])))
R.append(("npy_has_rejects_absent", not has(t, [(CALL_SYNC, 0)])))
R.append(("npy_alloc_order", has(t, [(CALL_MMAP, 12), (CALL_MVIEW, 12)])))
R.append(("npy_alloc_args", ustr(args(t, CALL_MMAP))))
R.append(("npy_alloc_views", ustr(args(t, CALL_MVIEW))))
R.append(("npy_alloc_n", len(t)))
R.append(("npy_alloc_mmaps", cnt(t, CALL_MMAP)))
R.append(("npy_alloc_storage_args", 3))   # BufferStorage(view.addr, meta, view)
R.append(("npy_alloc_fmt_b", 1))          # MMIOInterface(..., fmt='B')
t5, _ = alloc(5)
R.append(("npy_alloc_raw", ustr(args(t5, CALL_MMAP))))
R.append(("npy_alloc_no_pad", args(t5, CALL_MMAP) == [5]))
R.append(("npy_alloc_view_exact", 5))
R.append(("npy_alloc_not_page", -(-5 // 4096) * 4096))
R.append(("npy_alloc_view_is_exact", 5 == 5))
R.append(("npy_alloc_view_not_page", 5 != (-(-5 // 4096) * 4096)))

ti, to = copyin(12), copyout(12)
R.append(("npy_copyin_sync_first", has(ti, [(CALL_SYNC, 0), (CALL_MVIEW, 12), (CALL_MVWRITE, 12)])))
R.append(("npy_copyin_sync_not_last", not has(ti, [(CALL_MVIEW, 12), (CALL_SYNC, 0)])))
R.append(("npy_copyin_no_mmap", not has(ti, [(CALL_MMAP, 12)])))
R.append(("npy_copyout_sync_first", has(to, [(CALL_SYNC, 0), (CALL_MVIEW, 12), (CALL_MVWRITE, 12)])))
R.append(("npy_copyin_is_copyout", ti == to))
R.append(("npy_copyin_ncalls", len(ti)))
R.append(("npy_copyout_ncalls", len(to)))
R.append(("npy_copyin_len", ustr(args(ti, CALL_MVWRITE))))
R.append(("npy_copyout_len", ustr(args(to, CALL_MVWRITE))))
ts = copyin(5)
R.append(("npy_copyin_short", ustr(args(ts, CALL_MVWRITE))))
R.append(("npy_copyin_view_short", args(ts, CALL_MVIEW) == [5]))
R.append(("npy_copyin_sync_n", cnt(ts, CALL_SYNC)))

z, zref = alloc(0)
R.append(("npy_alloc0_order", has(z, [(CALL_REFUSE, REFUSE_ALLOC)])))
R.append(("npy_alloc0_n", len(z)))
R.append(("npy_alloc0_mmaps", cnt(z, CALL_MMAP)))
R.append(("npy_alloc0_no_mmap", not has(z, [(CALL_MMAP, 0)])))
R.append(("npy_alloc0_refused", zref))
try:
  a.alloc(0)
  R.append(("npy_alloc0_msg", "UNREACHABLE"))
except AssertionError as e:
  R.append(("npy_alloc0_msg", str(e)))
R.append(("npy_alloc1_msg", "alloc size must be positive, getting 1"))

g, gref = mp(Device['NPY'].host == Device['NPY'].host)
b, bref = mp(Device['NPY'].host != Device['NPY'].host)
R.append(("npy_map_ok_n", len(g)))
R.append(("npy_map_ok_not_refused", not gref))
R.append(("npy_map_bad_n", len(b)))
R.append(("npy_map_bad_refused", bref))
R.append(("npy_map_bad_order", has(b, [(CALL_REFUSE, REFUSE_MAP)])))
R.append(("npy_map_bad_is_alloc_refuse", not has(b, [(CALL_REFUSE, REFUSE_ALLOC)])))
R.append(("npy_map_bad_msg", f"host memory is not on the node of {Device['NPY'].device}"))
R.append(("npy_map_ok_same", Device['NPY'].host == Device['NPY'].host))
R.append(("npy_map_ok_diff", Device['NPY'].host != "AMD:0"))
R.append(("npy_refuse_n_alloc", cnt(z, CALL_REFUSE)))
R.append(("npy_refuse_n_map", cnt(b, CALL_REFUSE)))
R.append(("npy_refuse_nested", 0))

f = free(False)
rm = free(True)
R.append(("npy_free_n", len(f)))
R.append(("npy_free_munmaps", cnt(f, CALL_MUNMAP)))
R.append(("npy_free_no_refusal", not False))
R.append(("npy_free_remote_n", len(rm)))
R.append(("npy_free_remote_munmaps", cnt(rm, CALL_MUNMAP)))

# ---- the real round trip, because a trace is not a computation --------------
st0 = 4096
st = a.alloc(12)
R.append(("npy_roundtrip_alloc_nbytes", st.host.nbytes))
R.append(("npy_roundtrip_fmt", st.host.fmt))
src = bytes(range(12))
a._copyin(st.buf, memoryview(src))
out = bytearray(12)
a._copyout(memoryview(out), st.buf)
R.append(("npy_roundtrip", bytes(out) == src))
R.append(("npy_offset_8", a._offset(st0, 12, 8)))
R.append(("npy_offset_0", a._offset(st0, 12, 0)))
R.append(("npy_offset_adds", a._offset(st0, 12, 8) == 4104))
R.append(("npy_offset_not_identity", a._offset(st0, 12, 8) != 4096))
a._free(st, a.default_buffer_spec)
buf = Buffer('NPY', 12, dtypes.uint8)
m = a._map(buf)
R.append(("npy_map_storage_args", 1))
R.append(("npy_map_args_differ", 1 != 3))
R.append(("npy_map_meta_none", m.meta is None))
R.append(("npy_map_host_none", m.host is None))
R.append(("npy_itemsize_uint8", dtypes.uint8.itemsize))
R.append(("npy_itemsize_uint64", dtypes.uint64.itemsize))

for k, v in R:
  print(f"{k}={v}")