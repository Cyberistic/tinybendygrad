import io, re

# Emit the arithmetic row sections as ONE FLAT LIST LITERAL per section. The
# group helpers are expanded INLINE, so a section needs no accumulator, no
# right-nested chain, and no `List<&2, List<&2, String>>`: every row expression
# is written exactly once and reads top to bottom.

# helper -> (rows as functions of the fixture args)
EXPAND = {
    "wire_rows":    (["+nm", "+size"], ["u1(nm, usb_wire(size))"]),
    "split_rows":   (["+nm", "+nb", "+win"], [
        'u1(String.concat([nm, "_full"]), Split.full(usb_split(nb, win)))',
        'u1(String.concat([nm, "_tail"]), Split.tail(usb_split(nb, win)))',
        'u1(String.concat([nm, "_ranged"]), Split.ranged(usb_split(nb, win)))',
        'u1(String.concat([nm, "_nranges"]), Split.nranges(usb_split(nb, win)))']),
    "pcie_byte_rows": (["+nm", "+sz", "+off"], ['u1(String.concat([nm, "_byteen"]), pcie_byte_en(sz, off))']),
    "cfg_rows": (["+nm", "+hv", "+bus", "+dev", "+fn", "+ba"], [
        'u1(String.concat([nm, "_fmt"]), pcie_cfg_fmt(hv, bus))',
        'u1(String.concat([nm, "_addr"]), pcie_cfg_addr(bus, dev, fn, ba))',
        'b1(String.concat([nm, "_ok"]), pcie_cfg_addr_ok(ba, bus, dev, fn))']),
    "xdata_rows": (["+nm", "+len", "+i"], [
        'u1(String.concat([nm, "_nchunks"]), xdata_nchunks(len))',
        'u1(String.concat([nm, "_chunk_i"]), xdata_chunk_at(len, i))']),
    "scsi_rows": (["+nm", "+n", "+slot_start"], [
        'u1(String.concat([nm, "_pad"]), scsi_pad(n))',
        'u1(String.concat([nm, "_padded"]), scsi_padded(n))',
        'u1(String.concat([nm, "_wvalue"]), scsi_wvalue(n))',
        'u1(String.concat([nm, "_windex"]), scsi_windex(n, slot_start))']),
    "copyout_rows": (["+nm", "+size"], [
        'u1(String.concat([nm, "_first"]), copyout_first(size))',
        'u1(String.concat([nm, "_second"]), copyout_second(size))',
        'u1(String.concat([nm, "_wire"]), copyout_wire(size))']),
    "chunk_rows": (["+nm", "+half", "+wire"], [
        'u1(String.concat([nm, "_end"]), chunk_end(half))',
        'u1(String.concat([nm, "_off"]), chunk_off(half, wire))',
        'u1(String.concat([nm, "_sentinel_word"]), chunk_sentinel_word(half))',
        'u1(String.concat([nm, "_wvalue"]), chunk_wvalue(wire))',
        'u1(String.concat([nm, "_windex"]), chunk_windex(half, wire))']),
    "table_row_rows": (["+nm", "+k", "+r"], [
        'u1(String.concat([nm, "_addr"]), table_addr_word(k, r))',
        'u1(String.concat([nm, "_size"]), table_size_word(k, r))']),
    "mmio_rows": (["+nm", "+i", "+el", "+start", "+stop"], [
        'u1(String.concat([nm, "_int_off"]), off_of_index(i, el))',
        'u1(String.concat([nm, "_int_sz"]), off_of_index_sz(el))',
        'u1(String.concat([nm, "_slice_at"]), off_of_slice_at(start, el))',
        'u1(String.concat([nm, "_slice_sz"]), off_of_slice_sz(start, stop, el))']),
}

SECTIONS = [
    ("t_wire", "wire_rows", [
        ('"usb_wire_0"', "0"), ('"usb_wire_511"', "511"),
        ('"usb_wire_512"', "512"), ('"usb_wire_513"', "513"),
        ('"usb_wire_slot_m1"', "16383"), ('"usb_wire_slot"', "16384"),
        ('"usb_wire_slot_p1"', "16385"), ('"usb_wire_2slot_m1"', "32767"),
        ('"usb_wire_2slot"', "32768"), ('"usb_wire_chunk"', "CHUNK()"),
        ('"usb_wire_2chunk"', "U32.mul(2, CHUNK())")]),
    ("t_split", "split_rows", [
        ('"usb_split_empty"', "0, CHUNK()"), ('"usb_split_one_lt"', "1, CHUNK()"),
        ('"usb_split_full1"', "CHUNK(), CHUNK()"),
        ('"usb_split_full1_p1"', "U32.add(CHUNK(), 1), CHUNK()"),
        ('"usb_split_full2"', "U32.mul(2, CHUNK()), CHUNK()"),
        ('"usb_split_full2_p5"', "U32.add(U32.mul(2, CHUNK()), 5), CHUNK()"),
        ('"usb_split_win_1"', "4, 1"),
        ('"usb_split_win_2chunk"', "U32.mul(3, CHUNK()), U32.mul(2, CHUNK())"),
        ('"usb_split_copyin_2chunk"', "U32.mul(2, CHUNK()), usb_window(True{})"),
        ('"usb_split_copyout_2chunk"', "U32.mul(2, CHUNK()), usb_window(False{})")]),
    ("t_byteen", "pcie_byte_rows", [
        ('"usb_byteen_s1_o0"', "1n, 0"), ('"usb_byteen_s1_o3"', "1n, 3"),
        ('"usb_byteen_s2_o0"', "2n, 0"), ('"usb_byteen_s2_o3"', "2n, 3"),
        ('"usb_byteen_s3_o1"', "3n, 1"), ('"usb_byteen_s4_o0"', "4n, 0"),
        ('"usb_byteen_s4_o2"', "4n, 2"), ('"usb_byteen_s4_o3"', "4n, 3")]),
    ("t_cfg", "cfg_rows", [
        ('"usb_cfg_wr_b0"', "True{}, 0, 0, 0, 0"),
        ('"usb_cfg_rd_b0"', "False{}, 0, 0, 0, 0"),
        ('"usb_cfg_wr_b1"', "True{}, 1, 0, 0, 0"),
        ('"usb_cfg_rd_b1"', "False{}, 1, 0, 0, 0"),
        ('"usb_cfg_wr_b255_d31_f7_ba4095"', "True{}, 255, 31, 7, 4095"),
        ('"usb_cfg_rd_b255_d31_f7_ba4095"', "False{}, 255, 31, 7, 4095"),
        ('"usb_cfg_rd_b256"', "False{}, 256, 0, 0, 0"),
        ('"usb_cfg_rd_d32"', "False{}, 0, 32, 0, 0"),
        ('"usb_cfg_rd_f8"', "False{}, 0, 0, 8, 0"),
        ('"usb_cfg_rd_ba4096"', "False{}, 0, 0, 0, 4096")]),
    ("t_xdata", "xdata_rows", [
        ('"usb_xdata_0"', "0, 0"), ('"usb_xdata_1"', "1, 0"),
        ('"usb_xdata_254"', "254, 0"), ('"usb_xdata_255"', "255, 0"),
        ('"usb_xdata_256"', "256, 1"), ('"usb_xdata_510"', "510, 1"),
        ('"usb_xdata_511"', "511, 1"), ('"usb_xdata_512"', "512, 2"),
        ('"usb_xdata_slot_i64"', "16384, 64")]),
    ("t_scsi", "scsi_rows", [
        ('"usb_scsi_0"', "0, 0"), ('"usb_scsi_1"', "1, 0"),
        ('"usb_scsi_511"', "511, 0"), ('"usb_scsi_512"', "512, 0"),
        ('"usb_scsi_513"', "513, 0"), ('"usb_scsi_slot_m1"', "16383, 0"),
        ('"usb_scsi_slot"', "16384, 0"), ('"usb_scsi_slot_p1"', "16385, 0"),
        ('"usb_scsi_2slot"', "32768, 0"),
        ('"usb_scsi_slotstart_ff"', "512, 255"),
        ('"usb_scsi_slotstart_100"', "512, 256")]),
    ("t_copyout", "copyout_rows", [
        ('"usb_co_0"', "0"), ('"usb_co_511"', "511"), ('"usb_co_512"', "512"),
        ('"usb_co_chunk_m1"', "U32.sub(CHUNK(), 1)"), ('"usb_co_chunk"', "CHUNK()"),
        ('"usb_co_chunk_p1"', "U32.add(CHUNK(), 1)"),
        ('"usb_co_2chunk"', "U32.mul(2, CHUNK())")]),
    ("t_chunk", "chunk_rows", [
        ('"usb_chunk_h0_w512"', "0, usb_wire(512)"),
        ('"usb_chunk_h0_w2slot"', "0, usb_wire(32768)"),
        ('"usb_chunk_h1_w512"', "1, usb_wire(512)"),
        ('"usb_chunk_h1_w2slot"', "1, usb_wire(32768)"),
        ('"usb_chunk_h1_w2chunk"', "1, usb_wire(U32.mul(2, CHUNK()))")]),
    ("t_table", "table_row_rows", [
        ('"usb_tbl_k0r0"', "0, 0"), ('"usb_tbl_k0r1"', "0, 1"),
        ('"usb_tbl_k1r0"', "1, 0"), ('"usb_tbl_k3r2"', "3, 2")]),
    ("t_mmio", "mmio_rows", [
        ('"usb_mmio_idx0_el4"', "0, 4, 0, 1"),
        ('"usb_mmio_idx1_el4"', "1, 4, 0, 1"),
        ('"usb_mmio_idx7_el1"', "7, 1, 0, 1"),
        ('"usb_mmio_slice0_4_el4"', "0, 4, 0, 4"),
        ('"usb_mmio_slice2_9_el4"', "0, 4, 2, 9")]),
]

# FLAT sections: a literal list of rows, one per line where it is long.
FLAT = [
    ("t_window", [
        'u1("usb_half", HALF())', 'u1("usb_chunk", CHUNK())', 'u1("usb_slot", SLOT())',
        'u1("usb_sentinel_block", SENTINEL_BLOCK())', 'u1("usb_max_stream", USB_MAX_STREAM())',
        'u1("usb_host_size", USB_HOST_SIZE())', 'u1("usb_asm24_size", ASM24_SIZE())',
        'u1("usb_win_fence_lo", WIN_FENCE_LO())', 'u1("usb_win_fence_hi", WIN_FENCE_HI())',
        'u1("usb_win_cq_lo", WIN_CQ_LO())', 'u1("usb_win_cq_hi", WIN_CQ_HI())',
        'u1("usb_win_sram_lo", WIN_SRAM_LO())', 'u1("usb_win_sram_hi", WIN_SRAM_HI())',
        'b1("usb_sram_win_fits_asm24", sram_win_fits())',
        'u1("usb_link_bytes", LINK_BYTES())', 'u1("usb_link_words", LINK_WORDS())',
        'u1("usb_link_packed", LINK_PACKED())', 'u1("usb_stage_lo", STAGE_LO())',
        'u1("usb_stage_hi", STAGE_HI())', 'u1("usb_zeros_lo", ZEROS_LO())',
        'u1("usb_vram_words", VRAM_WORDS())', 'u1("usb_vram_bytes", VRAM_BYTES())',
        'u1("usb_go_word", GO_WORD())', 'u1("usb_scratch_word", SCRATCH_WORD())',
        'u1("usb_bulk_buf", BULK_BUF())', 'u1("usb_ctrl_buf", CTRL_BUF())',
        'u1("usb_table_row_bytes", TABLE_ROW_BYTES())', 'u1("usb_table_size_off", TABLE_SIZE_OFF())',
        'u1("usb_req_power", REQ_POWER())', 'u1("usb_req_f0", REQ_F0())',
        'u1("usb_req_f2", REQ_F2())', 'u1("usb_req_e4", REQ_E4())',
        'u1("usb_req_e5", REQ_E5())', 'u1("usb_mode_mask", MODE_MASK())',
        'u1("usb_cfg_fmt_rd", CFG_FMT_RD())', 'u1("usb_cfg_fmt_wr", CFG_FMT_WR())',
        'u1("usb_cfg_bus_shift", CFG_BUS_SHIFT())', 'u1("usb_cfg_dev_shift", CFG_DEV_SHIFT())',
        'u1("usb_cfg_fn_shift", CFG_FN_SHIFT())', 'u1("usb_cfg_ba_mask", CFG_BA_MASK())',
        'u1("usb_xdata_chunk", XDATA_CHUNK())', 'u1("usb_sram_align", SRAM_ALIGN())',
        'u1("usb_sram_slot", SRAM_SLOT())', 'u1("usb_drain_mod", DRAIN_MOD())',
        'u1("usb_stream_fmt_wr", STREAM_FMT_WR())', 'u1("usb_stream_fmt_rd", STREAM_FMT_RD())',
        'u1("usb_stream_byte_en", STREAM_BYTE_EN())', 'u1("usb_copyin_win", usb_window(True{}))',
        'u1("usb_copyout_win", usb_window(False{}))', 'u1("usb_remote_n", REMOTE_N())',
    ]),
    ("t_sentinel", [
        'u1("usb_sentinel_magic", SENTINEL_MAGIC())', 'u1("usb_sentinel_mask", SENTINEL_MASK())',
        'u1("usb_sentinel_0", usb_sentinel(0))', 'u1("usb_sentinel_1", usb_sentinel(1))',
        'u1("usb_sentinel_max24", usb_sentinel(16777215))',
        'u1("usb_sentinel_max24_p1", usb_sentinel(16777216))',
        'u1("usb_sentinel_allones", usb_sentinel(4294967295))',
        'b1("usb_sentinel_collide_24", sentinels_collide(0, 16777216))',
        'b1("usb_sentinel_collide_23", sentinels_collide(0, 8388608))',
        'b1("usb_sentinel_collide_adjacent", sentinels_collide(0, 1))',
    ]),
    ("t_pcie_read", [
        'u1("usb_pcie_mask_1", pcie_read_mask(1n))', 'u1("usb_pcie_mask_2", pcie_read_mask(2n))',
        'u1("usb_pcie_mask_3", pcie_read_mask(3n))',
        'u1("usb_pcie_mask_4", pcie_read_mask(4n))',
        'u1("usb_pcie_extract_allff_s4_o0", pcie_extract(4294967295, 4n, 0))',
        'u1("usb_pcie_extract_allff_s1_o0", pcie_extract(4294967295, 1n, 0))',
        'u1("usb_pcie_extract_deadbeef_s1_o0", pcie_extract(3735928559, 1n, 0))',
        'u1("usb_pcie_extract_deadbeef_s2_o1", pcie_extract(3735928559, 2n, 1))',
        'u1("usb_pcie_extract_deadbeef_s2_o2", pcie_extract(3735928559, 2n, 2))',
        'u1("usb_pcie_extract_deadbeef_s4_o3", pcie_extract(3735928559, 4n, 3))',
        'u1("usb_pcie_offset_0", pcie_offset(0))', 'u1("usb_pcie_offset_3", pcie_offset(3))',
        'u1("usb_pcie_offset_4", pcie_offset(4))', 'u1("usb_pcie_offset_allff", pcie_offset(4294967295))',
    ]),
    ("t_fastpath", [
        'u1("usb_fast_p1_mask", FAST_P1_MASK())', 'u1("usb_fast_p1_val", FAST_P1_VAL())',
        'u1("usb_fast_p2_mask", FAST_P2_MASK())', 'u1("usb_fast_p2_val", FAST_P2_VAL())',
        # DECIMAL IN THE ROW NAME TOO. Bend has no `0x` literal, and the oracle
        # names these rows with `str(hx)`, so a hex-spelled name would be a
        # permanent disagreement rather than a visible one.
        'b1("usb_nocompletion_64", pcie_no_completion(64))',
        'b1("usb_nocompletion_48", pcie_no_completion(48))',
        'b1("usb_nocompletion_68", pcie_no_completion(68))',
        'b1("usb_nocompletion_4", pcie_no_completion(4))',
        'b1("usb_nocompletion_76", pcie_no_completion(76))',
        'b1("usb_nocompletion_0", pcie_no_completion(0))',
        'b1("usb_nocompletion_32", pcie_no_completion(32))',
        'b1("usb_nocompletion_96", pcie_no_completion(96))',
    ]),
    ("t_stream", [
        'u1("usb_pcie_mem_nchunks_max", pcie_mem_nchunks(USB_MAX_STREAM()))',
        'u1("usb_pcie_mem_nchunks_max_p1", pcie_mem_nchunks(U32.add(USB_MAX_STREAM(), 1)))',
        'u1("usb_pcie_mem_nchunks_2max", pcie_mem_nchunks(U32.mul(2, USB_MAX_STREAM())))',
        'u1("usb_pcie_mem_nchunks_0", pcie_mem_nchunks(0))',
        'u1("usb_pcie_mem_dwords_0", pcie_mem_dwords(0))',
        'u1("usb_pcie_mem_dwords_4", pcie_mem_dwords(4))',
        'u1("usb_pcie_mem_dwords_5", pcie_mem_dwords(5))',
        'b1("usb_aligned4_0", aligned4(0))', 'b1("usb_aligned4_4", aligned4(4))',
        'b1("usb_aligned4_5", aligned4(5))', 'b1("usb_aligned4_1", aligned4(1))',
    ]),
    ("t_drained", [
        'b1("usb_drain_need_fence_eq", drained_step(7, 7))',
        'b1("usb_drain_need_fence_ahead1", drained_step(7, 6))',
        'b1("usb_drain_need_fence_ahead2", drained_step(7, 5))',
        'b1("usb_drain_need_fence_ahead3", drained_step(7, 4))',
        'b1("usb_drain_need_fence_1behind", drained_step(7, 8))',
        'b1("usb_drain_need_fence_2behind", drained_step(7, 9))',
        'b1("usb_drain_wrap_need1_fence3", drained_step(1, 3))',
        'b1("usb_drain_wrap_need0_fence0", drained_step(0, 0))',
        'b1("usb_drain_wrap_need0_fence255", drained_step(0, 255))',
        'b1("usb_drain_wrap_need0_fence254", drained_step(0, 254))',
        'b1("usb_drain_wrap_need255_fence0", drained_step(255, 0))',
        'b1("usb_drain_wrap_need2_fence0", drained_step(2, 0))',
    ]),
    ("t_remote", [
        's1("usb_remote_prefixes", remote_prefixes())',
        'b1("usb_remote_usb_host", is_remote_prefix("usb_host", "usb_host"))',
        'b1("usb_remote_usb_xfer0", is_remote_prefix("usb_xfer0", "usb_xfer"))',
        'b1("usb_remote_usb_xfer1", is_remote_prefix("usb_xfer1", "usb_xfer"))',
        'b1("usb_remote_put_value", is_remote_prefix("put_value", "put_value"))',
        'b1("usb_remote_cmdbuf_copy", is_remote_prefix("cmdbuf_copy", "cmdbuf_copy"))',
        'b1("usb_remote_kernargs", is_remote_prefix("kernargs", "usb_host"))',
        'b1("usb_remote_kernargs_xfer", is_remote_prefix("kernargs", "usb_xfer"))',
        'b1("usb_remote_kernargs_put_value", is_remote_prefix("kernargs", "put_value"))',
        'b1("usb_remote_kernargs_cmdbuf_copy", is_remote_prefix("kernargs", "cmdbuf_copy"))',
        'b1("usb_remote_usb_table", is_remote_prefix("usb_table", "usb_host"))',
        'b1("usb_remote_arg_cache", is_remote_prefix("usb_arg_cache", "usb_xfer"))',
        'b1("usb_remote_usb_hostx", is_remote_prefix("usb_hostx", "usb_host"))',
        'b1("usb_remote_xusb_host", is_remote_prefix("xusb_host", "usb_host"))',
    ]),
]


def split_top(a: str):
    """Split a fixture's arguments on TOP-LEVEL commas only: `4, 1` is two
    arguments and `U32.mul(2, CHUNK())` is one, and a naive `split(",")` turns
    the second into three fragments and leaves the file uncompilable."""
    out, depth, cur = [], 0, ""
    for ch in a:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def section_src(name, rows):
    out = [f"def {name}() -> IO(Unit):", "  IO.print(lines_of(["]
    for j, r in enumerate(rows):
        out.append("    " + r + ("," if j < len(rows) - 1 else ""))
    out.append("  ]))")
    return "\n".join(out)


parts = []
for name, fn, args in SECTIONS:
    names, exprs = EXPAND[fn]
    rows = []
    for nm, a in args:
        vals = [nm] + split_top(a)
        env = dict(zip([n.lstrip("+") for n in names], vals))
        # LONGEST NAME FIRST: `nm` must be replaced before `n`, or the `n` inside
        # it is gone and every row name in the section collapses to the first
        # fixture's. PER FIXTURE: the templates must not be rewritten in place or
        # the second fixture inherits the first one's names.
        tpl = list(EXPAND[fn][1])
        for k in sorted(env, key=len, reverse=True):
            tpl = [re.sub(r"\b" + k + r"\b", lambda _m, v=env[k]: v, e) for e in tpl]
        rows.extend(tpl)
    parts.append(section_src(name, rows))
    parts.append("")
for name, rows in FLAT:
    parts.append(section_src(name, rows))
    parts.append("")
io.open(".agents/slop/usb-arith-rows.bend.txt", "w").write("\n".join(parts))
print("sections:", len(SECTIONS) + len(FLAT), "rows:",
      sum(len(EXPAND[f][1]) * len(a) for _, f, a in SECTIONS) + sum(len(r) for _, r in FLAT))