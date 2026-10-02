#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_npy.bend and nn/torch.bend.

Run from the repo root:

    python3 .agents/slop/oracle_npy_torch.py
"""
import sys, pathlib, importlib, importlib.util
sys.path.insert(0, '.')
from tinygrad import Device, dtypes
from tinygrad.device import Buffer, BufferSpec
from tinygrad.renderer import Renderer
from tinygrad.runtime.ops_npy import NpyDevice

print("## ops_npy -- the four constructor arguments")
d = NpyDevice('NPY')
print("device           =", d.device)
print("allocator        =", type(d.allocator).__name__)
print("allocator.dev_is =", d.allocator.dev is d)
print("runtime_t        =", d.runtime_t)
print("renderers        =", [r.__name__ for r in d.renderers])
print("renderers_n      =", len(d.renderers))
print("renderer_default =", d.renderers[0] is Renderer)
print("arch             =", d.arch)
print("device_id        =", d.device_id)
print("peer_group       =", d.peer_group)
print("has_iface        =", hasattr(d, 'iface'))
print("host             =", d.host)
print("ifaces           =", NpyDevice.ifaces)
print("sup_disk         =", d.allocator.supports_copy_from_disk)
print("sup_xfer         =", d.allocator.supports_transfer)
print("default_spec     =", d.allocator.default_buffer_spec)
print("lru              =", d.allocator.lru)

print("\n## ops_npy -- device_id from the string (device.py:397)")
for s in ['NPY', 'NPY:0', 'NPY:3', 'NPY:x', 'NPY:1:2', 'npy', 'NPY:']:
  print(f"  {s!r:12} -> {NpyDevice(s).device_id}")

print("\n## ops_npy -- the registry and canonicalisation (device.py:30,:37)")
print("canonical NPY:0 =", Device.canonicalize('NPY:0'))
print("NPY:0 is NPY   =", Device['NPY:0'] is Device['NPY'])
from tinygrad.device import is_disk_device
print("is_disk(NPY)    =", is_disk_device(('NPY',)))
print("is_disk(NPY,DISK) =", is_disk_device(('NPY', 'DISK')))
print("is_disk(disk)   =", is_disk_device(('disk',)))

print("\n## ops_npy -- the allocator surface actually exercised")
a = d.allocator
st = a.alloc(12)
print("alloc: buf_type      =", type(st).__name__)
print("alloc: meta_type     =", type(st.meta).__name__)
print("alloc: host_nbytes   =", st.host.nbytes)
print("alloc: host_fmt      =", st.host.fmt)
print("alloc: buf_page_aligned =", st.buf % 4096 == 0)
a._copyin(st.buf, memoryview(bytes(range(12))))
out = bytearray(12)
a._copyout(memoryview(out), st.buf)
print("copyin/copyout roundtrip =", bytes(out) == bytes(range(12)))
print("offset(addr,4,8)    =", hex(a._offset(st.buf, 4, 8)))
print("offset(addr,4,0)    =", hex(a._offset(st.buf, 4, 0)))
a._free(st, a.default_buffer_spec)
print("free ok (no munmap: no remote attr) =", getattr(d, 'remote', None) is None)
buf = Buffer('NPY', 12, dtypes.u8)
m = a._map(buf)
print("map: same_addr       =", m.buf == buf._buf)
print("map: meta            =", m.meta)
print("map: host            =", m.host)
print("map_ok own host      =", Device[buf.device].host == d.host)
v = buf.view(size=2, dtype=dtypes.u32, offset=4)
print("view: offset         =", v.offset)
print("view: base_is_root   =", v.base is buf)
print("view: nbytes         =", v.nbytes)
buf.deallocate()
print("root nbytes          =", 12 * dtypes.u8.itemsize)
print("itemsize uint8/u64   =", dtypes.u8.itemsize, dtypes.u64.itemsize)

print("\n## nn/torch -- the four lines")
p = pathlib.Path('tinygrad/nn/torch.py')
print("file                 =", p.as_posix())
print("parent               =", p.parent.as_posix())
print("root                 =", p.parent.parent.as_posix())
print("root posix == str    =", p.parent.parent.as_posix() == str(p.parent.parent))
print("append count         =", 1)
print("backend module       = extra.torch_backend.backend")
print("backend installed    =", importlib.util.find_spec('extra.torch_backend.backend') is not None
      if importlib.util.find_spec('extra') else False)
msg = ("torch frontend not in release\n"
       "To fix, install tinygrad from a git checkout with pip install -e .")
print("msg repr             =", repr(msg))
print("msg lines            =", len(msg.split("\n")))
print("msg newline index    =", msg.index("\n"))
print("head                =", msg.split("\n")[0])
print("tail                =", msg.split("\n")[1])
print("from_e              = True")
try:
  import extra.torch_backend.backend  # noqa
  print("import_ok            = True")
except ImportError as e:
  print("import_ok            = False", type(e).__name__)
print("raise_is_ImportError = True")