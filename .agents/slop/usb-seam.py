#!/usr/bin/env python3
"""THE SEAM LIST for tinybendygrad/runtime/support/usb.bend.

EVERY LINE OF `usb.py` THAT IS NOT PORTED, with the reason. An honest "this is a
seam" is a complete result; what is NOT acceptable is a row that pretends to cover
one, and the only way to keep a hand-written list honest over a 473-line source is
to PRINT THE SOURCE TEXT FROM THE FILE, so a line that moves cannot silently keep
its old description.

The (line, why) pairs below are the only hand-written part. The middle column is
read out of `tinygrad/runtime/support/usb.py` at run time, so this table cannot
drift from the source and a wrong line number is visible on sight.

Read by `usb-build.py`, which splices it into the port's tail as a comment table.
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(os.path.dirname(ROOT), "tinygrad/runtime/support/usb.py")
LINES = io.open(SRC).read().split("\n")

CTYPES = "a ctypes object; the pointer IS the seam's"
UOPS = "a UOp construction (placeholder/cast/range); the arena owns it"
OPS = "a symbolic `Ops`-tagged match; it needs the graph"
FFI = "an FFI seam: a C pointer or a struct packing"
PY = "Python control flow with no gateable arithmetic"

# (line, why)
SEAMS = [
    (12, CTYPES + " -- `alloc_cbuffer` is a C array and a memoryview"),
    (16, "raises a Python exception and formats `libusb_strerror`; ported as "
         "`Tr.raise` and the `refused` flag, and the RAISE is a seam"),
    (40, "`itertools.count(1)`: an unbounded Python counter for `_tags`"),
    (41, CTYPES + " -- the 4 MiB bulk buffer's allocation"),
    (42, CTYPES + " -- the 0x1000 control buffer's allocation (the SIZE is ported)"),
    (47, CTYPES + " -- the 256-byte string buffer"),
    (48, CTYPES + " -- the `struct_libusb_device_descriptor` instance (the SIZE and "
                  "the field NAMES are ported)"),
    (51, "`bytes(_buf[:_ret]).decode('ascii', errors='replace')`: a byte slice and "
         "an ASCII decode; `product_ok` rows the two `startswith` tests, not this"),
    (52, "an `assert` on a decoded string; modelled as refusing at the string read"),
    (65, "an `assert` on a length; `usb_ctrl_*` rows the transfer, not the check"),
    (70, "an `assert` on a length; `usb_ctrl_*` rows the transfer, not the check"),
    (79, "an `assert` on `_transferred`; the transferred count is `libusb`'s"),
    (89, FFI + " -- `struct.pack('<IIIBBB16s', ...)` (the SIZE, 31, is ported)"),
    (91, FFI + " -- `struct.unpack('<IIIB', ...)` (the SIZE, 13, is ported)"),
    (99, "a device PROBE: `self.read(0xB450, 1)[0]` is a control transfer and the "
         "`ltssm != 0x78` branch is device state"),
    (102, "`raise RuntimeError` on a device state; the message formats a byte"),
    (104, "an FFI seam: `self.usb.control_write` carries a Python bool to `int`"),
    (110, FFI + " -- `struct.unpack_from('<I', data)`"),
    (114, "an `assert` with an f-string; `usb_pcie_size_ok` rows the predicate"),
    (115, "`if DEBUG >= 5: print(...)`: a host print"),
    (127, "`time.sleep(0.001)`: WALL-CLOCK TIME. Production code that needs 'now' "
          "takes it as a parameter, and this is a seam until it does"),
    (128, "the retry RECURSION with a counter; `usb_pcie_*` rows the arithmetic of "
          "one attempt, not the policy"),
    (129, "`raise RuntimeError` with an f-string"),
    (133, "`raise RuntimeError` with a nested f-string (the status MAP is ported)"),
    (138, "an `assert` with four bounds; `pcie_cfg_addr_ok` rows the predicate"),
    (146, "an `assert` with an f-string; `usb_aligned4_*` rows the predicate"),
    (154, "an `assert` with an f-string"),
    (168, PY + ": a `for off, val in enumerate(data)` per-byte loop"),
    (173, "an f-string index and `ceildiv`; `scsi_windex` rows the arithmetic"),
    (178, FFI + " -- `struct.calcsize(fmt)` on the caller's format string"),
    (181, "`index.stop or len(self)`: `len(self)` is the caller's buffer"),
    (187, "an `assert` with an f-string; `usb_aligned4_*` rows the predicate"),
    (190, FFI + " -- `int.from_bytes(data, 'little')`: a byte-order decode"),
    (194, FFI + " -- `struct.pack(self.fmt, data)` on the caller's format string"),
    (198, "an `assert` with an f-string"),
    (201, "a VIEW CONSTRUCTION: `USBMMIOInterface(...)` with a chain of defaults"),
    (213, UOPS + " -- `usb_host`'s placeholder, its `device=` and its `tag=`"),
    (214, UOPS + " -- `usb_link`'s bitcast (the 24 bytes are ported)"),
    (215, UOPS + " -- `usb_stage`'s slice (32 and 2*HALF are ported)"),
    (218, UOPS + " -- `usb_xfer`'s placeholder and its `tag=f'usb_xfer{half}'`"),
    (221, UOPS + " -- `usb_vram`'s placeholder"),
    (222, UOPS + " -- `usb_go`'s slice; the WORD INDEX 0 is ported"),
    (223, UOPS + " -- `usb_scratch`'s slice; the WORD INDEX 1 is ported"),
    (226, UOPS + " -- `usb_asm24`'s placeholder (0x85000 is ported)"),
    (227, UOPS + " -- `usb_fence`'s slice and bitcast (0x800/0x804 are ported)"),
    (228, UOPS + " -- `usb_cq`'s slice and bitcast (0x100c/0x1010 are ported)"),
    (229, UOPS + " -- `usb_sram`'s slice (0x5000 and 2*HALF are ported)"),
    (231, UOPS + " -- `usb_word`'s `cast`/`UOp.const` branch"),
    (233, UOPS + " -- `usb_stack`'s `max(1, len(vals))` SHAPE and its `AddrSpace.REG`"),
    (237, FFI + " -- `ccall(libusb_control_transfer, ...)`'s nine arguments and "
               "`.cast(dtypes.void)` (the ORDER is ported)"),
    (240, FFI + " -- `ccall(libusb_bulk_transfer, ...)`'s NULL `actual_length`"),
    (243, UOPS + " -- `usb_poke`'s `usb_stack(...).index(0)` (the ORDER is ported)"),
    (246, UOPS + " -- `usb_stream`'s header stack (the ORDER is ported)"),
    (247, UOPS + " -- `h.after(hdr)` and the endpoint `0x02 if write else 0x81`"),
    (252, "`all_devices_in(b.device, HCQ_DEVS - {'CPU'})`: a DEVICE SET question"),
    (255, OPS + " -- `is_staged` matches `Ops.CALL`/`Ops.STORE` and compares devices"),
    (264, UOPS + " -- `usb_ins`'s `Ops.INS` node and its `(name, dtypes.void)` arg"),
    (272, UOPS + " -- `vram.getaddr(dev)` and `i * win` on a UOp"),
    (281, UOPS + " -- `Ops.LINEAR` and its `.end(r)`"),
    (285, OPS + " -- `submit.without_after.src[0]`: a UOp-graph walk"),
    (290, "a `groupby` over a symbolic key (the RUN ORDER is ported)"),
    (295, OPS + " -- `usb_table`'s `lins[0].arg[0][0]` reach"),
    (299, "a generator zipped with `nums` (the ORDER is ported)"),
    (300, OPS + " -- `s.substitute` and `lin.replace(src=...)`"),
    (304, OPS + " -- `usb_link(...).after(...)`"),
    (308, OPS + " -- `s.replace(src=(*s.src, ...))`"),
    (309, OPS + " -- `pm_usb_batch`'s `PatternMatcher` and `UPat(Ops.SINK)`"),
    (315, UOPS + " -- `usb_table`'s placeholder and its `tag=`"),
    (318, "`unwrap_view(host)`: a view unwrapper"),
    (319, OPS + " -- `getaddr(to_tuple(dev)[0])`"),
    (322, OPS + " -- `patch(table, rows)` (the 16*(k+r) arithmetic is ported)"),
    (325, UOPS + " -- `UOp.range(Ops.NOOP, ...)` and `.backedge(loop, ...)`"),
    (328, "`events.backedge(loop, status.eq(0xff) & ...)` (the ORDER is ported)"),
    (334, "`read.backedge(loop, ...)` (the `(need - fence) & 0xff > 1` is ported)"),
    (337, OPS + " -- `table.index(2*i).load()`"),
    (339, UOPS + " -- `usb_xfer`'s and `usb_stage`'s placeholders"),
    (343, FFI + " -- `ccall(libc.memcpy, ...)` (the ORDER is ported)"),
    (344, OPS + " -- `.bitcast(dtypes.uint32).index(end // 4 - 1).store(...)`"),
    (349, FFI + " -- `functools.partial(cfield, ...)` (the three NAMES are ported)"),
    (352, FFI + " -- `ccall(libusb_submit_transfer, xfer.index(0))`"),
    (355, OPS + " -- `.index(UOp.const(0).valid(ret < 0)).store(...)`"),
    (361, "the unroll PREDICATE `n // 2 if n // 2 > 1 else 0` on a Python int"),
    (362, UOPS + " -- `UOp.range(pairs, ...)`"),
    (380, FFI + " -- `ccall(libusb_bulk_transfer, ...)` on the copyout path"),
    (381, FFI + " -- `ccall(libc.memcpy, ...)` of the FIRST half"),
    (382, FFI + " -- the SECOND half's `ccall(libc.memcpy, ...).cast(dtypes.void)`"),
    (387, "`p.op is Ops.PARAM and not is_host(p)` -- the `str(tag).startswith` half "
          "IS ported (`usb_remote_*`)"),
    (388, "`b.getaddr('CPU') + (idx * dt.itemsize)`: the `idx * el_sz` half IS ported"),
    (390, OPS + " -- `usb_deps` matches `Ops.AFTER`/`BITCAST`/`SHRINK`"),
    (392, OPS + " -- `idx is r` identity"),
    (393, OPS + " -- `idx.op is not Ops.ADD or r not in idx.src`"),
    (395, OPS + " -- `r not in base.ranges`"),
    (398, UOPS + " -- `usb_stack(ld.dtype)`"),
    (404, OPS + " -- `usb_store`'s `idx.op is Ops.STACK` arm"),
    (413, UOPS + " -- the kernargs cache's computed shape `int(idx.vmax - idx.vmin) + 1`"),
    (414, UOPS + " -- `Ops.BINARY` and `.bitcast(v.dtype)`"),
    (415, UOPS + " -- the cache probe's `UOp.range(...)`"),
    (427, "`usb_host(dst.device)[32 + 2*HALF:]` (the OFFSET is ported)"),
    (433, "a `Bool.where` on a symbolic condition (both ADDRESSES are ported)"),
    (435, UOPS + " -- `size.vmax > USB_MAX_STREAM` and the split `UOp.range`"),
    (437, "`s0 += off // v.dtype.itemsize`: a symbolic index rebind"),
    (441, OPS + " -- `pm_usb_lower`'s three `UPat`s and its `UPat(Ops.RANGE)`"),
    (443, OPS + " -- `idx.ranges or not is_remote(b)`"),
    (452, "a `Buffer(...)` allocation with `BufferSpec(nolru=True)`"),
    (453, FFI + " -- `ctypes.addressof(x.contents)` and `struct.pack('QQ', ...)` "
               "(the 16 bytes and the two words are ported)"),
    (457, FFI + " -- `libusb.libusb_alloc_transfer(0).contents` (the SIZE is ported)"),
    (458, "four field STORES through ctypes (the NAMES and their ORDINALS are ported)"),
    (459, "`Buffer(..., external_ptr=ctypes.addressof(t))`: a host allocation"),
    (463, "`b.host.view(fmt='B')[:8] = bytes(8)`: a host write"),
    (465, OPS + " -- `pm_usb_bufferize`'s five `UPat`s and its tag SET"),
    (473, "`if DEV.interface.startswith('MOCK'): from test.mockgpu.usb import ...`"),
]


def main():
    out = ["| usb.py | the source line | why it is not ported |",
           "| --- | --- | --- |"]
    for ln, why in SEAMS:
        if not 1 <= ln <= len(LINES):
            sys.exit(f"usb-seam.py: line {ln} is outside {SRC}")
        # The text is printed VERBATIM and its backticks are escaped, because a
        # truncated or re-spelled line is exactly the drift this script exists to
        # prevent.
        text = LINES[ln - 1].strip().replace("|", "\\|").replace("`", "\\`")
        out.append(f"| :{ln} | `{text}` | {why} |")
    sys.stdout.write("\n".join(out) + "\n")
    print(f"# usb-seam.py: {len(SEAMS)} unported lines", file=sys.stderr)


if __name__ == "__main__":
    main()
