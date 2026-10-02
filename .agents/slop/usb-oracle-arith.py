#!/usr/bin/env python3
"""CPython oracle for the ARITHMETIC rows of tinybendygrad/runtime/support/usb.bend.

Every expectation is the value of the EXPRESSION `usb.py` writes, evaluated with
Python operators -- `round_up`/`ceildiv` come from `tinygrad.helpers` rather than
being re-derived, because a re-derivation is how ops_rdma shipped `BNXT_VENDOR`
5356 where the header says 5348.

The format-string rows come from `struct.calcsize` and `struct.pack`, never from
a hand count. `<IIIBBB16s` is 31 bytes, not the 37 a reader gets by eye, and the
:89 CDB is the reason `usb.py:91` reads exactly 13 bytes back.
"""
import ctypes
import io
import os
import struct
import sys

sys.path.insert(0, ".")
from tinygrad.helpers import ceildiv, round_up  # noqa: E402

OUT = []


def u(nm, v):
    OUT.append(f"{nm}={v}")


_u = u

import importlib.util as _ilu
_spec = _ilu.spec_from_file_location(
    "usb_oracle_head", os.path.join(os.path.dirname(os.path.abspath(__file__)), "usb-oracle.py"))
_head = _ilu.module_from_spec(_spec)
_o = io.StringIO()
_saved = sys.stdout
sys.stdout = _o
try:
    _spec.loader.exec_module(_head)
finally:
    sys.stdout = _saved
_FIELDS = _head.FIELDS


def b(nm, v):
    OUT.append(f"{nm}={'True' if v else 'False'}")


def s(nm, v):
    OUT.append(f"{nm}={v}")


def u32(x: int) -> int:
    """The Bend port stores a C value in a U32; CPython's ints are unbounded."""
    return x & 0xFFFFFFFF


# --- the constants and the window ------------------------------------------
HALF, SENTINEL_BLOCK, SLOT = 0x40000, 512, 0x4000
USB_MAX_STREAM = 1 << 20
CHUNK = 0x40000 - 512
USB_HOST_SIZE = 32 + 2 * HALF + USB_MAX_STREAM
ASM24_SIZE = 0x85000
WIN_FENCE_LO, WIN_CQ_LO, WIN_SRAM_LO = 0x800, 0x100C, 0x5000
LINK_BYTES, LINK_PACKED = 24, 16
STAGE_LO, STAGE_HI = 32, 32 + 2 * HALF
VRAM_WORDS = 2
BULK_BUF, CTRL_BUF = 4 << 20, 0x1000
TABLE_ROW_BYTES, TABLE_SIZE_OFF = 16, 8
REQ_POWER, REQ_F0, REQ_F2, REQ_E4, REQ_E5 = 0xF3, 0xF0, 0xF2, 0xE4, 0xE5
MODE_MASK = 0x03
CFG_FMT_RD, CFG_FMT_WR = 0x4, 0x44
CFG_BUS_SHIFT, CFG_DEV_SHIFT, CFG_FN_SHIFT, CFG_BA_MASK = 24, 19, 16, 0xFFF
XDATA_CHUNK = 0xFF
SRAM_ALIGN, SRAM_SLOT = 512, 0x4000
STREAM_FMT_WR, STREAM_FMT_RD, STREAM_BYTE_EN = 0x60, 0x20, 0x0F
DRAIN_MOD = 0xFF
SENTINEL_MAGIC, SENTINEL_MASK = 0x51000000, 0xFFFFFF
FAST_P1_MASK, FAST_P1_VAL = 0b11011111, 0b01000000
FAST_P2_MASK, FAST_P2_VAL = 0b10111000, 0b00110000

u("usb_half", HALF)
u("usb_chunk", CHUNK)
u("usb_slot", SLOT)
u("usb_sentinel_block", SENTINEL_BLOCK)
u("usb_max_stream", USB_MAX_STREAM)
u("usb_host_size", USB_HOST_SIZE)
u("usb_asm24_size", ASM24_SIZE)
u("usb_win_fence_lo", WIN_FENCE_LO)
u("usb_win_fence_hi", WIN_FENCE_LO + 4)
u("usb_win_cq_lo", WIN_CQ_LO)
u("usb_win_cq_hi", WIN_CQ_LO + 4)
u("usb_win_sram_lo", WIN_SRAM_LO)
u("usb_win_sram_hi", WIN_SRAM_LO + 2 * HALF)
b("usb_sram_win_fits_asm24", WIN_SRAM_LO + 2 * HALF == ASM24_SIZE)
u("usb_link_bytes", LINK_BYTES)
u("usb_link_words", LINK_BYTES // 8)
u("usb_link_packed", LINK_PACKED)
u("usb_stage_lo", STAGE_LO)
u("usb_stage_hi", STAGE_HI)
u("usb_zeros_lo", STAGE_HI)
u("usb_vram_words", VRAM_WORDS)
u("usb_vram_bytes", VRAM_WORDS * 4)
u("usb_go_word", 0)
u("usb_scratch_word", 1)
u("usb_bulk_buf", BULK_BUF)
u("usb_ctrl_buf", CTRL_BUF)
u("usb_table_row_bytes", TABLE_ROW_BYTES)
u("usb_table_size_off", TABLE_SIZE_OFF)
u("usb_req_power", REQ_POWER)
u("usb_req_f0", REQ_F0)
u("usb_req_f2", REQ_F2)
u("usb_req_e4", REQ_E4)
u("usb_req_e5", REQ_E5)
u("usb_mode_mask", MODE_MASK)
u("usb_cfg_fmt_rd", CFG_FMT_RD)
u("usb_cfg_fmt_wr", CFG_FMT_WR)
u("usb_cfg_bus_shift", CFG_BUS_SHIFT)
u("usb_cfg_dev_shift", CFG_DEV_SHIFT)
u("usb_cfg_fn_shift", CFG_FN_SHIFT)
u("usb_cfg_ba_mask", CFG_BA_MASK)
u("usb_xdata_chunk", XDATA_CHUNK)
u("usb_sram_align", SRAM_ALIGN)
u("usb_sram_slot", SRAM_SLOT)
u("usb_drain_mod", DRAIN_MOD)
u("usb_stream_fmt_wr", STREAM_FMT_WR)
u("usb_stream_fmt_rd", STREAM_FMT_RD)
u("usb_stream_byte_en", STREAM_BYTE_EN)
u("usb_copyin_win", CHUNK)
u("usb_copyout_win", 2 * CHUNK)
u("usb_remote_n", 4)


# --- usb_wire :253 ----------------------------------------------------------
def usb_wire(size):
    return (size + 512 + SLOT - 1) // SLOT * SLOT


for nm, sz in [("0", 0), ("511", 511), ("512", 512), ("513", 513), ("slot_m1", SLOT - 1),
               ("slot", SLOT), ("slot_p1", SLOT + 1), ("2slot_m1", 2 * SLOT - 1),
               ("2slot", 2 * SLOT), ("chunk", CHUNK), ("2chunk", 2 * CHUNK)]:
    u(f"usb_wire_{nm}", usb_wire(sz))

# --- usb_sentinel :254 ------------------------------------------------------
def usb_sentinel(g):
    return u32((g & SENTINEL_MASK) | SENTINEL_MAGIC)


u("usb_sentinel_magic", SENTINEL_MAGIC)
u("usb_sentinel_mask", SENTINEL_MASK)
u("usb_sentinel_0", usb_sentinel(0))
u("usb_sentinel_1", usb_sentinel(1))
u("usb_sentinel_max24", usb_sentinel(0xFFFFFF))
u("usb_sentinel_max24_p1", usb_sentinel(0x1000000))
u("usb_sentinel_allones", usb_sentinel(0xFFFFFFFF))
b("usb_sentinel_collide_24", usb_sentinel(0) == usb_sentinel(0x1000000))
b("usb_sentinel_collide_23", usb_sentinel(0) == usb_sentinel(0x800000))
b("usb_sentinel_collide_adjacent", usb_sentinel(0) == usb_sentinel(1))


# --- usb_split :258 ---------------------------------------------------------
def usb_split(nbytes, win):
    full, tail = divmod(nbytes, win)
    ranged = full if full > 1 else 0
    return full, tail, ranged, int(full != 0) + int(tail != 0)


for nm, nb, win in [
    ("empty", 0, CHUNK), ("one_lt", 1, CHUNK), ("full1", CHUNK, CHUNK),
    ("full1_p1", CHUNK + 1, CHUNK), ("full2", 2 * CHUNK, CHUNK),
    ("full2_p5", 2 * CHUNK + 5, CHUNK), ("win_1", 4, 1),
    ("win_2chunk", 3 * CHUNK, 2 * CHUNK),
    ("copyin_2chunk", 2 * CHUNK, CHUNK), ("copyout_2chunk", 2 * CHUNK, 2 * CHUNK),
]:
    full, tail, ranged, nr = usb_split(nb, win)
    u(f"usb_split_{nm}_full", full)
    u(f"usb_split_{nm}_tail", tail)
    u(f"usb_split_{nm}_ranged", ranged)
    u(f"usb_split_{nm}_nranges", nr)


# --- pcie byte enables :118 -------------------------------------------------
def pcie_byte_en(size, offset):
    return u32(((1 << size) - 1) << offset)


for nm, sz, off in [("s1_o0", 1, 0), ("s1_o3", 1, 3), ("s2_o0", 2, 0), ("s2_o3", 2, 3),
                    ("s3_o1", 3, 1), ("s4_o0", 4, 0), ("s4_o2", 4, 2), ("s4_o3", 4, 3)]:
    u(f"usb_byteen_{nm}_byteen", pcie_byte_en(sz, off))


# --- the read mask and the extraction :135 ----------------------------------
def pcie_read_mask(size):
    """`1 << (8*size)` in a U32: size 4 asks for 1 << 32, which is 0 mod 2^32, and
    `0 - 1` is 4294967295. Evaluated with the mask, not by hand."""
    return u32(u32(1 << (8 * size)) - 1)


def pcie_extract(data, size, offset):
    return u32((u32(data) >> (8 * offset)) & pcie_read_mask(size))


for sz in (1, 2, 3, 4):
    u(f"usb_pcie_mask_{sz}", pcie_read_mask(sz))
for nm, d, sz, off in [("allff_s4_o0", 0xFFFFFFFF, 4, 0), ("allff_s1_o0", 0xFFFFFFFF, 1, 0),
                       ("deadbeef_s1_o0", 0xDEADBEEF, 1, 0), ("deadbeef_s2_o1", 0xDEADBEEF, 2, 1),
                       ("deadbeef_s2_o2", 0xDEADBEEF, 2, 2), ("deadbeef_s4_o3", 0xDEADBEEF, 4, 3)]:
    u(f"usb_pcie_extract_{nm}", pcie_extract(d, sz, off))
for nm, a in [("0", 0), ("3", 3), ("4", 4), ("allff", 0xFFFFFFFF)]:
    u(f"usb_pcie_offset_{nm}", a & 3)

# --- the fast paths :122 ----------------------------------------------------
u("usb_fast_p1_mask", FAST_P1_MASK)
u("usb_fast_p1_val", FAST_P1_VAL)
u("usb_fast_p2_mask", FAST_P2_MASK)
u("usb_fast_p2_val", FAST_P2_VAL)


def pcie_no_completion(fmt_type):
    return (fmt_type & FAST_P1_MASK) == FAST_P1_VAL or (fmt_type & FAST_P2_MASK) == FAST_P2_VAL


for hx in (0x40, 0x30, 0x44, 0x04, 0x4C, 0x00, 0x20, 0x60):
    b("usb_nocompletion_" + str(hx), pcie_no_completion(hx))

# --- pcie_cfg_req :138-140 --------------------------------------------------
def pcie_cfg_fmt(has_value, bus):
    return (CFG_FMT_WR if has_value else CFG_FMT_RD) | int(bus > 0)


def pcie_cfg_addr(bus, dev, fn, byte_addr):
    return u32((bus << 24) | (dev << 19) | (fn << 16) | (byte_addr & CFG_BA_MASK))


def pcie_cfg_addr_ok(byte_addr, bus, dev, fn):
    return byte_addr >> 12 == 0 and bus >> 8 == 0 and dev >> 5 == 0 and fn >> 3 == 0


for nm, hv, bus, dev, fn, ba in [
    ("wr_b0", True, 0, 0, 0, 0), ("rd_b0", False, 0, 0, 0, 0),
    ("wr_b1", True, 1, 0, 0, 0), ("rd_b1", False, 1, 0, 0, 0),
    ("wr_b255_d31_f7_ba4095", True, 255, 31, 7, 4095),
    ("rd_b255_d31_f7_ba4095", False, 255, 31, 7, 4095),
    ("rd_b256", False, 256, 0, 0, 0), ("rd_d32", False, 0, 32, 0, 0),
    ("rd_f8", False, 0, 0, 8, 0), ("rd_ba4096", False, 0, 0, 0, 4096),
]:
    u(f"usb_cfg_{nm}_fmt", pcie_cfg_fmt(hv, bus))
    u(f"usb_cfg_{nm}_addr", pcie_cfg_addr(bus, dev, fn, ba))
    b(f"usb_cfg_{nm}_ok", pcie_cfg_addr_ok(ba, bus, dev, fn))

# --- the chip XDATA read chunking :161 --------------------------------------
def xdata_nchunks(length):
    return len(range(0, length, XDATA_CHUNK))


def xdata_chunk_at(length, i):
    return min(XDATA_CHUNK, length - i * XDATA_CHUNK)


for nm, ln, i in [("0", 0, 0), ("1", 1, 0), ("254", 254, 0), ("255", 255, 0),
                  ("256", 256, 1), ("510", 510, 1), ("511", 511, 1), ("512", 512, 2),
                  ("slot_i64", SLOT, 64)]:
    u(f"usb_xdata_{nm}_nchunks", xdata_nchunks(ln))
    u(f"usb_xdata_{nm}_chunk_i", xdata_chunk_at(ln, i))

# --- scsi_write :172 --------------------------------------------------------
def scsi_padded(n):
    return round_up(n, SRAM_ALIGN)


for nm, n, slot_start in [
    ("0", 0, 0), ("1", 1, 0), ("511", 511, 0), ("512", 512, 0), ("513", 513, 0),
    ("slot_m1", SRAM_SLOT - 1, 0), ("slot", SRAM_SLOT, 0), ("slot_p1", SRAM_SLOT + 1, 0),
    ("2slot", 2 * SRAM_SLOT, 0), ("slotstart_ff", 512, 255), ("slotstart_100", 512, 256),
]:
    padded = scsi_padded(n)
    u(f"usb_scsi_{nm}_pad", padded - n)
    u(f"usb_scsi_{nm}_padded", padded)
    u(f"usb_scsi_{nm}_wvalue", padded // SRAM_ALIGN)
    u(f"usb_scsi_{nm}_windex", (slot_start & 0xFF) | (ceildiv(padded, SRAM_SLOT) << 8))

# --- pcie_mem_write / read :146-156 ----------------------------------------
for nm, nb in [("max", USB_MAX_STREAM), ("max_p1", USB_MAX_STREAM + 1),
               ("2max", 2 * USB_MAX_STREAM), ("0", 0)]:
    u(f"usb_pcie_mem_nchunks_{nm}", len(range(0, nb, USB_MAX_STREAM)))
for nm, nb in [("0", 0), ("4", 4), ("5", 5)]:
    u(f"usb_pcie_mem_dwords_{nm}", nb // 4)
for nm, nb in [("0", 0), ("4", 4), ("5", 5), ("1", 1)]:
    b(f"usb_aligned4_{nm}", nb % 4 == 0)

# --- copyout :374-375 -------------------------------------------------------
def copyout_first(size):
    return min(size, CHUNK)


def copyout_second(size):
    return max(size - CHUNK, 0)


def copyout_wire(size):
    return (size + (512 if copyout_second(size) > 0 else 0) + 511) // 512 * 512


for nm, size in [("0", 0), ("511", 511), ("512", 512), ("chunk_m1", CHUNK - 1),
                 ("chunk", CHUNK), ("chunk_p1", CHUNK + 1), ("2chunk", 2 * CHUNK)]:
    u(f"usb_co_{nm}_first", copyout_first(size))
    u(f"usb_co_{nm}_second", copyout_second(size))
    u(f"usb_co_{nm}_wire", copyout_wire(size))

# --- usb_chunk :336-348 -----------------------------------------------------
def chunk_end(half):
    return (half + 1) * HALF


for nm, half, wire in [
    ("h0_w512", 0, usb_wire(512)), ("h0_w2slot", 0, usb_wire(2 * SLOT)),
    ("h1_w512", 1, usb_wire(512)), ("h1_w2slot", 1, usb_wire(2 * SLOT)),
    ("h1_w2chunk", 1, usb_wire(2 * CHUNK)),
]:
    end = chunk_end(half)
    u(f"usb_chunk_{nm}_end", end)
    u(f"usb_chunk_{nm}_off", end - wire)
    u(f"usb_chunk_{nm}_sentinel_word", end // 4 - 1)
    u(f"usb_chunk_{nm}_wvalue", wire // SRAM_ALIGN)
    u(f"usb_chunk_{nm}_windex", ((end - wire) // SLOT) | (wire // SLOT << 8))

# --- the usb_table rows :321 -----------------------------------------------
for nm, k, r in [("k0r0", 0, 0), ("k0r1", 0, 1), ("k1r0", 1, 0), ("k3r2", 3, 2)]:
    u(f"usb_tbl_{nm}_addr", 16 * (k + r))
    u(f"usb_tbl_{nm}_size", 16 * (k + r) + 8)

# --- _off_from_index :180 ---------------------------------------------------
for nm, i, el, start, stop in [("idx0_el4", 0, 4, 0, 1), ("idx1_el4", 1, 4, 0, 1),
                               ("idx7_el1", 7, 1, 0, 1), ("slice0_4_el4", 0, 4, 0, 4),
                               ("slice2_9_el4", 0, 4, 2, 9)]:
    u(f"usb_mmio_{nm}_int_off", i * el)
    u(f"usb_mmio_{nm}_int_sz", el)
    u(f"usb_mmio_{nm}_slice_at", start * el)
    u(f"usb_mmio_{nm}_slice_sz", (stop - start) * el)

# --- usb_drained :334 -------------------------------------------------------
def drained_step(need, fence):
    return ((need - fence) & 0xFF) > 1


for nm, need, fence in [
    ("need_fence_eq", 7, 7), ("need_fence_ahead1", 7, 6), ("need_fence_ahead2", 7, 5),
    ("need_fence_ahead3", 7, 4), ("need_fence_1behind", 7, 8), ("need_fence_2behind", 7, 9),
    ("wrap_need1_fence3", 1, 3), ("wrap_need0_fence0", 0, 0), ("wrap_need0_fence255", 0, 255),
    ("wrap_need0_fence254", 0, 254), ("wrap_need255_fence0", 255, 0), ("wrap_need2_fence0", 2, 0),
    ("need300_fence44", 300, 44), ("need300_fence43", 300, 43),
]:
    b(f"usb_drain_{nm}", drained_step(need, fence))

# --- is_remote :387 ---------------------------------------------------------
s("usb_remote_prefixes", "usb_host usb_xfer put_value cmdbuf_copy")
for tag, pfx in [("usb_host", "usb_host"), ("usb_xfer0", "usb_xfer"), ("usb_xfer1", "usb_xfer"),
                 ("put_value", "put_value"), ("cmdbuf_copy", "cmdbuf_copy"),
                 ("usb_table", "usb_host"), ("arg_cache", "usb_xfer")]:
    b(f"usb_remote_{tag}", tag.startswith(pfx))
for pfx in ("usb_host", "usb_xfer", "put_value", "cmdbuf_copy"):
    b(f"usb_remote_kernargs_{pfx}", "kernargs".startswith(pfx))
b("usb_remote_usb_hostx", "usb_hostx".startswith("usb_host"))
b("usb_remote_xusb_host", "xusb_host".startswith("usb_host"))

# --- the enumeration selection :34 ----------------------------------------
def list_match(idVendor, idProduct, vendor, dev):
    return (idVendor, idProduct) == (vendor, dev)


for nm, iv, ip, ve, dv in [("exact", 0x1d6b, 0x0104, 0x1d6b, 0x0104),
                           ("vendor_only", 0x1d6b, 0x0104, 0x1d6b, 0x0105),
                           ("product_only", 0x1d6b, 0x0104, 0x04b4, 0x0104),
                           ("both_wrong", 0x1d6b, 0x0104, 0x04b4, 0x0131),
                           ("zero_zero", 0, 0, 0, 0),
                           ("ffff_ffff", 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF)]:
    b(f"usb_list_match_{nm}", list_match(iv, ip, ve, dv))
# and the two descriptor field ORDINALS, by NAME, from the live struct
_u("usb_list_ix_idvendor", _FIELDS["device_descriptor"].index("idVendor"))
_u("usb_list_ix_idproduct", _FIELDS["device_descriptor"].index("idProduct"))

sys.stdout.write("\n".join(OUT) + "\n")