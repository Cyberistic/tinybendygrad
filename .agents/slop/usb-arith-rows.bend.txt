def t_wire() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_wire_0", usb_wire(0)),
    u1("usb_wire_511", usb_wire(511)),
    u1("usb_wire_512", usb_wire(512)),
    u1("usb_wire_513", usb_wire(513)),
    u1("usb_wire_slot_m1", usb_wire(16383)),
    u1("usb_wire_slot", usb_wire(16384)),
    u1("usb_wire_slot_p1", usb_wire(16385)),
    u1("usb_wire_2slot_m1", usb_wire(32767)),
    u1("usb_wire_2slot", usb_wire(32768)),
    u1("usb_wire_chunk", usb_wire(CHUNK())),
    u1("usb_wire_2chunk", usb_wire(U32.mul(2, CHUNK())))
  ]))

def t_split() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_split_empty", "_full"]), Split.full(usb_split(0, CHUNK()))),
    u1(String.concat(["usb_split_empty", "_tail"]), Split.tail(usb_split(0, CHUNK()))),
    u1(String.concat(["usb_split_empty", "_ranged"]), Split.ranged(usb_split(0, CHUNK()))),
    u1(String.concat(["usb_split_empty", "_nranges"]), Split.nranges(usb_split(0, CHUNK()))),
    u1(String.concat(["usb_split_one_lt", "_full"]), Split.full(usb_split(1, CHUNK()))),
    u1(String.concat(["usb_split_one_lt", "_tail"]), Split.tail(usb_split(1, CHUNK()))),
    u1(String.concat(["usb_split_one_lt", "_ranged"]), Split.ranged(usb_split(1, CHUNK()))),
    u1(String.concat(["usb_split_one_lt", "_nranges"]), Split.nranges(usb_split(1, CHUNK()))),
    u1(String.concat(["usb_split_full1", "_full"]), Split.full(usb_split(CHUNK(), CHUNK()))),
    u1(String.concat(["usb_split_full1", "_tail"]), Split.tail(usb_split(CHUNK(), CHUNK()))),
    u1(String.concat(["usb_split_full1", "_ranged"]), Split.ranged(usb_split(CHUNK(), CHUNK()))),
    u1(String.concat(["usb_split_full1", "_nranges"]), Split.nranges(usb_split(CHUNK(), CHUNK()))),
    u1(String.concat(["usb_split_full1_p1", "_full"]), Split.full(usb_split(U32.add(CHUNK(), 1), CHUNK()))),
    u1(String.concat(["usb_split_full1_p1", "_tail"]), Split.tail(usb_split(U32.add(CHUNK(), 1), CHUNK()))),
    u1(String.concat(["usb_split_full1_p1", "_ranged"]), Split.ranged(usb_split(U32.add(CHUNK(), 1), CHUNK()))),
    u1(String.concat(["usb_split_full1_p1", "_nranges"]), Split.nranges(usb_split(U32.add(CHUNK(), 1), CHUNK()))),
    u1(String.concat(["usb_split_full2", "_full"]), Split.full(usb_split(U32.mul(2, CHUNK()), CHUNK()))),
    u1(String.concat(["usb_split_full2", "_tail"]), Split.tail(usb_split(U32.mul(2, CHUNK()), CHUNK()))),
    u1(String.concat(["usb_split_full2", "_ranged"]), Split.ranged(usb_split(U32.mul(2, CHUNK()), CHUNK()))),
    u1(String.concat(["usb_split_full2", "_nranges"]), Split.nranges(usb_split(U32.mul(2, CHUNK()), CHUNK()))),
    u1(String.concat(["usb_split_full2_p5", "_full"]), Split.full(usb_split(U32.add(U32.mul(2, CHUNK()), 5), CHUNK()))),
    u1(String.concat(["usb_split_full2_p5", "_tail"]), Split.tail(usb_split(U32.add(U32.mul(2, CHUNK()), 5), CHUNK()))),
    u1(String.concat(["usb_split_full2_p5", "_ranged"]), Split.ranged(usb_split(U32.add(U32.mul(2, CHUNK()), 5), CHUNK()))),
    u1(String.concat(["usb_split_full2_p5", "_nranges"]), Split.nranges(usb_split(U32.add(U32.mul(2, CHUNK()), 5), CHUNK()))),
    u1(String.concat(["usb_split_win_1", "_full"]), Split.full(usb_split(4, 1))),
    u1(String.concat(["usb_split_win_1", "_tail"]), Split.tail(usb_split(4, 1))),
    u1(String.concat(["usb_split_win_1", "_ranged"]), Split.ranged(usb_split(4, 1))),
    u1(String.concat(["usb_split_win_1", "_nranges"]), Split.nranges(usb_split(4, 1))),
    u1(String.concat(["usb_split_win_2chunk", "_full"]), Split.full(usb_split(U32.mul(3, CHUNK()), U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_split_win_2chunk", "_tail"]), Split.tail(usb_split(U32.mul(3, CHUNK()), U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_split_win_2chunk", "_ranged"]), Split.ranged(usb_split(U32.mul(3, CHUNK()), U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_split_win_2chunk", "_nranges"]), Split.nranges(usb_split(U32.mul(3, CHUNK()), U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_split_copyin_2chunk", "_full"]), Split.full(usb_split(U32.mul(2, CHUNK()), usb_window(True{})))),
    u1(String.concat(["usb_split_copyin_2chunk", "_tail"]), Split.tail(usb_split(U32.mul(2, CHUNK()), usb_window(True{})))),
    u1(String.concat(["usb_split_copyin_2chunk", "_ranged"]), Split.ranged(usb_split(U32.mul(2, CHUNK()), usb_window(True{})))),
    u1(String.concat(["usb_split_copyin_2chunk", "_nranges"]), Split.nranges(usb_split(U32.mul(2, CHUNK()), usb_window(True{})))),
    u1(String.concat(["usb_split_copyout_2chunk", "_full"]), Split.full(usb_split(U32.mul(2, CHUNK()), usb_window(False{})))),
    u1(String.concat(["usb_split_copyout_2chunk", "_tail"]), Split.tail(usb_split(U32.mul(2, CHUNK()), usb_window(False{})))),
    u1(String.concat(["usb_split_copyout_2chunk", "_ranged"]), Split.ranged(usb_split(U32.mul(2, CHUNK()), usb_window(False{})))),
    u1(String.concat(["usb_split_copyout_2chunk", "_nranges"]), Split.nranges(usb_split(U32.mul(2, CHUNK()), usb_window(False{}))))
  ]))

def t_byteen() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_byteen_s1_o0", "_byteen"]), pcie_byte_en(1n, 0)),
    u1(String.concat(["usb_byteen_s1_o3", "_byteen"]), pcie_byte_en(1n, 3)),
    u1(String.concat(["usb_byteen_s2_o0", "_byteen"]), pcie_byte_en(2n, 0)),
    u1(String.concat(["usb_byteen_s2_o3", "_byteen"]), pcie_byte_en(2n, 3)),
    u1(String.concat(["usb_byteen_s3_o1", "_byteen"]), pcie_byte_en(3n, 1)),
    u1(String.concat(["usb_byteen_s4_o0", "_byteen"]), pcie_byte_en(4n, 0)),
    u1(String.concat(["usb_byteen_s4_o2", "_byteen"]), pcie_byte_en(4n, 2)),
    u1(String.concat(["usb_byteen_s4_o3", "_byteen"]), pcie_byte_en(4n, 3))
  ]))

def t_cfg() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_cfg_wr_b0", "_fmt"]), pcie_cfg_fmt(True{}, 0)),
    u1(String.concat(["usb_cfg_wr_b0", "_addr"]), pcie_cfg_addr(0, 0, 0, 0)),
    b1(String.concat(["usb_cfg_wr_b0", "_ok"]), pcie_cfg_addr_ok(0, 0, 0, 0)),
    u1(String.concat(["usb_cfg_rd_b0", "_fmt"]), pcie_cfg_fmt(False{}, 0)),
    u1(String.concat(["usb_cfg_rd_b0", "_addr"]), pcie_cfg_addr(0, 0, 0, 0)),
    b1(String.concat(["usb_cfg_rd_b0", "_ok"]), pcie_cfg_addr_ok(0, 0, 0, 0)),
    u1(String.concat(["usb_cfg_wr_b1", "_fmt"]), pcie_cfg_fmt(True{}, 1)),
    u1(String.concat(["usb_cfg_wr_b1", "_addr"]), pcie_cfg_addr(1, 0, 0, 0)),
    b1(String.concat(["usb_cfg_wr_b1", "_ok"]), pcie_cfg_addr_ok(0, 1, 0, 0)),
    u1(String.concat(["usb_cfg_rd_b1", "_fmt"]), pcie_cfg_fmt(False{}, 1)),
    u1(String.concat(["usb_cfg_rd_b1", "_addr"]), pcie_cfg_addr(1, 0, 0, 0)),
    b1(String.concat(["usb_cfg_rd_b1", "_ok"]), pcie_cfg_addr_ok(0, 1, 0, 0)),
    u1(String.concat(["usb_cfg_wr_b255_d31_f7_ba4095", "_fmt"]), pcie_cfg_fmt(True{}, 255)),
    u1(String.concat(["usb_cfg_wr_b255_d31_f7_ba4095", "_addr"]), pcie_cfg_addr(255, 31, 7, 4095)),
    b1(String.concat(["usb_cfg_wr_b255_d31_f7_ba4095", "_ok"]), pcie_cfg_addr_ok(4095, 255, 31, 7)),
    u1(String.concat(["usb_cfg_rd_b255_d31_f7_ba4095", "_fmt"]), pcie_cfg_fmt(False{}, 255)),
    u1(String.concat(["usb_cfg_rd_b255_d31_f7_ba4095", "_addr"]), pcie_cfg_addr(255, 31, 7, 4095)),
    b1(String.concat(["usb_cfg_rd_b255_d31_f7_ba4095", "_ok"]), pcie_cfg_addr_ok(4095, 255, 31, 7)),
    u1(String.concat(["usb_cfg_rd_b256", "_fmt"]), pcie_cfg_fmt(False{}, 256)),
    u1(String.concat(["usb_cfg_rd_b256", "_addr"]), pcie_cfg_addr(256, 0, 0, 0)),
    b1(String.concat(["usb_cfg_rd_b256", "_ok"]), pcie_cfg_addr_ok(0, 256, 0, 0)),
    u1(String.concat(["usb_cfg_rd_d32", "_fmt"]), pcie_cfg_fmt(False{}, 0)),
    u1(String.concat(["usb_cfg_rd_d32", "_addr"]), pcie_cfg_addr(0, 32, 0, 0)),
    b1(String.concat(["usb_cfg_rd_d32", "_ok"]), pcie_cfg_addr_ok(0, 0, 32, 0)),
    u1(String.concat(["usb_cfg_rd_f8", "_fmt"]), pcie_cfg_fmt(False{}, 0)),
    u1(String.concat(["usb_cfg_rd_f8", "_addr"]), pcie_cfg_addr(0, 0, 8, 0)),
    b1(String.concat(["usb_cfg_rd_f8", "_ok"]), pcie_cfg_addr_ok(0, 0, 0, 8)),
    u1(String.concat(["usb_cfg_rd_ba4096", "_fmt"]), pcie_cfg_fmt(False{}, 0)),
    u1(String.concat(["usb_cfg_rd_ba4096", "_addr"]), pcie_cfg_addr(0, 0, 0, 4096)),
    b1(String.concat(["usb_cfg_rd_ba4096", "_ok"]), pcie_cfg_addr_ok(4096, 0, 0, 0))
  ]))

def t_xdata() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_xdata_0", "_nchunks"]), xdata_nchunks(0)),
    u1(String.concat(["usb_xdata_0", "_chunk_i"]), xdata_chunk_at(0, 0)),
    u1(String.concat(["usb_xdata_1", "_nchunks"]), xdata_nchunks(1)),
    u1(String.concat(["usb_xdata_1", "_chunk_i"]), xdata_chunk_at(1, 0)),
    u1(String.concat(["usb_xdata_254", "_nchunks"]), xdata_nchunks(254)),
    u1(String.concat(["usb_xdata_254", "_chunk_i"]), xdata_chunk_at(254, 0)),
    u1(String.concat(["usb_xdata_255", "_nchunks"]), xdata_nchunks(255)),
    u1(String.concat(["usb_xdata_255", "_chunk_i"]), xdata_chunk_at(255, 0)),
    u1(String.concat(["usb_xdata_256", "_nchunks"]), xdata_nchunks(256)),
    u1(String.concat(["usb_xdata_256", "_chunk_i"]), xdata_chunk_at(256, 1)),
    u1(String.concat(["usb_xdata_510", "_nchunks"]), xdata_nchunks(510)),
    u1(String.concat(["usb_xdata_510", "_chunk_i"]), xdata_chunk_at(510, 1)),
    u1(String.concat(["usb_xdata_511", "_nchunks"]), xdata_nchunks(511)),
    u1(String.concat(["usb_xdata_511", "_chunk_i"]), xdata_chunk_at(511, 1)),
    u1(String.concat(["usb_xdata_512", "_nchunks"]), xdata_nchunks(512)),
    u1(String.concat(["usb_xdata_512", "_chunk_i"]), xdata_chunk_at(512, 2)),
    u1(String.concat(["usb_xdata_slot_i64", "_nchunks"]), xdata_nchunks(16384)),
    u1(String.concat(["usb_xdata_slot_i64", "_chunk_i"]), xdata_chunk_at(16384, 64))
  ]))

def t_scsi() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_scsi_0", "_pad"]), scsi_pad(0)),
    u1(String.concat(["usb_scsi_0", "_padded"]), scsi_padded(0)),
    u1(String.concat(["usb_scsi_0", "_wvalue"]), scsi_wvalue(0)),
    u1(String.concat(["usb_scsi_0", "_windex"]), scsi_windex(0, 0)),
    u1(String.concat(["usb_scsi_1", "_pad"]), scsi_pad(1)),
    u1(String.concat(["usb_scsi_1", "_padded"]), scsi_padded(1)),
    u1(String.concat(["usb_scsi_1", "_wvalue"]), scsi_wvalue(1)),
    u1(String.concat(["usb_scsi_1", "_windex"]), scsi_windex(1, 0)),
    u1(String.concat(["usb_scsi_511", "_pad"]), scsi_pad(511)),
    u1(String.concat(["usb_scsi_511", "_padded"]), scsi_padded(511)),
    u1(String.concat(["usb_scsi_511", "_wvalue"]), scsi_wvalue(511)),
    u1(String.concat(["usb_scsi_511", "_windex"]), scsi_windex(511, 0)),
    u1(String.concat(["usb_scsi_512", "_pad"]), scsi_pad(512)),
    u1(String.concat(["usb_scsi_512", "_padded"]), scsi_padded(512)),
    u1(String.concat(["usb_scsi_512", "_wvalue"]), scsi_wvalue(512)),
    u1(String.concat(["usb_scsi_512", "_windex"]), scsi_windex(512, 0)),
    u1(String.concat(["usb_scsi_513", "_pad"]), scsi_pad(513)),
    u1(String.concat(["usb_scsi_513", "_padded"]), scsi_padded(513)),
    u1(String.concat(["usb_scsi_513", "_wvalue"]), scsi_wvalue(513)),
    u1(String.concat(["usb_scsi_513", "_windex"]), scsi_windex(513, 0)),
    u1(String.concat(["usb_scsi_slot_m1", "_pad"]), scsi_pad(16383)),
    u1(String.concat(["usb_scsi_slot_m1", "_padded"]), scsi_padded(16383)),
    u1(String.concat(["usb_scsi_slot_m1", "_wvalue"]), scsi_wvalue(16383)),
    u1(String.concat(["usb_scsi_slot_m1", "_windex"]), scsi_windex(16383, 0)),
    u1(String.concat(["usb_scsi_slot", "_pad"]), scsi_pad(16384)),
    u1(String.concat(["usb_scsi_slot", "_padded"]), scsi_padded(16384)),
    u1(String.concat(["usb_scsi_slot", "_wvalue"]), scsi_wvalue(16384)),
    u1(String.concat(["usb_scsi_slot", "_windex"]), scsi_windex(16384, 0)),
    u1(String.concat(["usb_scsi_slot_p1", "_pad"]), scsi_pad(16385)),
    u1(String.concat(["usb_scsi_slot_p1", "_padded"]), scsi_padded(16385)),
    u1(String.concat(["usb_scsi_slot_p1", "_wvalue"]), scsi_wvalue(16385)),
    u1(String.concat(["usb_scsi_slot_p1", "_windex"]), scsi_windex(16385, 0)),
    u1(String.concat(["usb_scsi_2slot", "_pad"]), scsi_pad(32768)),
    u1(String.concat(["usb_scsi_2slot", "_padded"]), scsi_padded(32768)),
    u1(String.concat(["usb_scsi_2slot", "_wvalue"]), scsi_wvalue(32768)),
    u1(String.concat(["usb_scsi_2slot", "_windex"]), scsi_windex(32768, 0)),
    u1(String.concat(["usb_scsi_slotstart_ff", "_pad"]), scsi_pad(512)),
    u1(String.concat(["usb_scsi_slotstart_ff", "_padded"]), scsi_padded(512)),
    u1(String.concat(["usb_scsi_slotstart_ff", "_wvalue"]), scsi_wvalue(512)),
    u1(String.concat(["usb_scsi_slotstart_ff", "_windex"]), scsi_windex(512, 255)),
    u1(String.concat(["usb_scsi_slotstart_100", "_pad"]), scsi_pad(512)),
    u1(String.concat(["usb_scsi_slotstart_100", "_padded"]), scsi_padded(512)),
    u1(String.concat(["usb_scsi_slotstart_100", "_wvalue"]), scsi_wvalue(512)),
    u1(String.concat(["usb_scsi_slotstart_100", "_windex"]), scsi_windex(512, 256))
  ]))

def t_copyout() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_co_0", "_first"]), copyout_first(0)),
    u1(String.concat(["usb_co_0", "_second"]), copyout_second(0)),
    u1(String.concat(["usb_co_0", "_wire"]), copyout_wire(0)),
    u1(String.concat(["usb_co_511", "_first"]), copyout_first(511)),
    u1(String.concat(["usb_co_511", "_second"]), copyout_second(511)),
    u1(String.concat(["usb_co_511", "_wire"]), copyout_wire(511)),
    u1(String.concat(["usb_co_512", "_first"]), copyout_first(512)),
    u1(String.concat(["usb_co_512", "_second"]), copyout_second(512)),
    u1(String.concat(["usb_co_512", "_wire"]), copyout_wire(512)),
    u1(String.concat(["usb_co_chunk_m1", "_first"]), copyout_first(U32.sub(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk_m1", "_second"]), copyout_second(U32.sub(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk_m1", "_wire"]), copyout_wire(U32.sub(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk", "_first"]), copyout_first(CHUNK())),
    u1(String.concat(["usb_co_chunk", "_second"]), copyout_second(CHUNK())),
    u1(String.concat(["usb_co_chunk", "_wire"]), copyout_wire(CHUNK())),
    u1(String.concat(["usb_co_chunk_p1", "_first"]), copyout_first(U32.add(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk_p1", "_second"]), copyout_second(U32.add(CHUNK(), 1))),
    u1(String.concat(["usb_co_chunk_p1", "_wire"]), copyout_wire(U32.add(CHUNK(), 1))),
    u1(String.concat(["usb_co_2chunk", "_first"]), copyout_first(U32.mul(2, CHUNK()))),
    u1(String.concat(["usb_co_2chunk", "_second"]), copyout_second(U32.mul(2, CHUNK()))),
    u1(String.concat(["usb_co_2chunk", "_wire"]), copyout_wire(U32.mul(2, CHUNK())))
  ]))

def t_chunk() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_chunk_h0_w512", "_end"]), chunk_end(0)),
    u1(String.concat(["usb_chunk_h0_w512", "_off"]), chunk_off(0, usb_wire(512))),
    u1(String.concat(["usb_chunk_h0_w512", "_sentinel_word"]), chunk_sentinel_word(0)),
    u1(String.concat(["usb_chunk_h0_w512", "_wvalue"]), chunk_wvalue(usb_wire(512))),
    u1(String.concat(["usb_chunk_h0_w512", "_windex"]), chunk_windex(0, usb_wire(512))),
    u1(String.concat(["usb_chunk_h0_w2slot", "_end"]), chunk_end(0)),
    u1(String.concat(["usb_chunk_h0_w2slot", "_off"]), chunk_off(0, usb_wire(32768))),
    u1(String.concat(["usb_chunk_h0_w2slot", "_sentinel_word"]), chunk_sentinel_word(0)),
    u1(String.concat(["usb_chunk_h0_w2slot", "_wvalue"]), chunk_wvalue(usb_wire(32768))),
    u1(String.concat(["usb_chunk_h0_w2slot", "_windex"]), chunk_windex(0, usb_wire(32768))),
    u1(String.concat(["usb_chunk_h1_w512", "_end"]), chunk_end(1)),
    u1(String.concat(["usb_chunk_h1_w512", "_off"]), chunk_off(1, usb_wire(512))),
    u1(String.concat(["usb_chunk_h1_w512", "_sentinel_word"]), chunk_sentinel_word(1)),
    u1(String.concat(["usb_chunk_h1_w512", "_wvalue"]), chunk_wvalue(usb_wire(512))),
    u1(String.concat(["usb_chunk_h1_w512", "_windex"]), chunk_windex(1, usb_wire(512))),
    u1(String.concat(["usb_chunk_h1_w2slot", "_end"]), chunk_end(1)),
    u1(String.concat(["usb_chunk_h1_w2slot", "_off"]), chunk_off(1, usb_wire(32768))),
    u1(String.concat(["usb_chunk_h1_w2slot", "_sentinel_word"]), chunk_sentinel_word(1)),
    u1(String.concat(["usb_chunk_h1_w2slot", "_wvalue"]), chunk_wvalue(usb_wire(32768))),
    u1(String.concat(["usb_chunk_h1_w2slot", "_windex"]), chunk_windex(1, usb_wire(32768))),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_end"]), chunk_end(1)),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_off"]), chunk_off(1, usb_wire(U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_sentinel_word"]), chunk_sentinel_word(1)),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_wvalue"]), chunk_wvalue(usb_wire(U32.mul(2, CHUNK())))),
    u1(String.concat(["usb_chunk_h1_w2chunk", "_windex"]), chunk_windex(1, usb_wire(U32.mul(2, CHUNK()))))
  ]))

def t_table() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_tbl_k0r0", "_addr"]), table_addr_word(0, 0)),
    u1(String.concat(["usb_tbl_k0r0", "_size"]), table_size_word(0, 0)),
    u1(String.concat(["usb_tbl_k0r1", "_addr"]), table_addr_word(0, 1)),
    u1(String.concat(["usb_tbl_k0r1", "_size"]), table_size_word(0, 1)),
    u1(String.concat(["usb_tbl_k1r0", "_addr"]), table_addr_word(1, 0)),
    u1(String.concat(["usb_tbl_k1r0", "_size"]), table_size_word(1, 0)),
    u1(String.concat(["usb_tbl_k3r2", "_addr"]), table_addr_word(3, 2)),
    u1(String.concat(["usb_tbl_k3r2", "_size"]), table_size_word(3, 2))
  ]))

def t_mmio() -> IO(Unit):
  IO.print(lines_of([
    u1(String.concat(["usb_mmio_idx0_el4", "_int_off"]), off_of_index(0, 4)),
    u1(String.concat(["usb_mmio_idx0_el4", "_int_sz"]), off_of_index_sz(4)),
    u1(String.concat(["usb_mmio_idx0_el4", "_slice_at"]), off_of_slice_at(0, 4)),
    u1(String.concat(["usb_mmio_idx0_el4", "_slice_sz"]), off_of_slice_sz(0, 1, 4)),
    u1(String.concat(["usb_mmio_idx1_el4", "_int_off"]), off_of_index(1, 4)),
    u1(String.concat(["usb_mmio_idx1_el4", "_int_sz"]), off_of_index_sz(4)),
    u1(String.concat(["usb_mmio_idx1_el4", "_slice_at"]), off_of_slice_at(0, 4)),
    u1(String.concat(["usb_mmio_idx1_el4", "_slice_sz"]), off_of_slice_sz(0, 1, 4)),
    u1(String.concat(["usb_mmio_idx7_el1", "_int_off"]), off_of_index(7, 1)),
    u1(String.concat(["usb_mmio_idx7_el1", "_int_sz"]), off_of_index_sz(1)),
    u1(String.concat(["usb_mmio_idx7_el1", "_slice_at"]), off_of_slice_at(0, 1)),
    u1(String.concat(["usb_mmio_idx7_el1", "_slice_sz"]), off_of_slice_sz(0, 1, 1)),
    u1(String.concat(["usb_mmio_slice0_4_el4", "_int_off"]), off_of_index(0, 4)),
    u1(String.concat(["usb_mmio_slice0_4_el4", "_int_sz"]), off_of_index_sz(4)),
    u1(String.concat(["usb_mmio_slice0_4_el4", "_slice_at"]), off_of_slice_at(0, 4)),
    u1(String.concat(["usb_mmio_slice0_4_el4", "_slice_sz"]), off_of_slice_sz(0, 4, 4)),
    u1(String.concat(["usb_mmio_slice2_9_el4", "_int_off"]), off_of_index(0, 4)),
    u1(String.concat(["usb_mmio_slice2_9_el4", "_int_sz"]), off_of_index_sz(4)),
    u1(String.concat(["usb_mmio_slice2_9_el4", "_slice_at"]), off_of_slice_at(2, 4)),
    u1(String.concat(["usb_mmio_slice2_9_el4", "_slice_sz"]), off_of_slice_sz(2, 9, 4))
  ]))

def t_window() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_half", HALF()),
    u1("usb_chunk", CHUNK()),
    u1("usb_slot", SLOT()),
    u1("usb_sentinel_block", SENTINEL_BLOCK()),
    u1("usb_max_stream", USB_MAX_STREAM()),
    u1("usb_host_size", USB_HOST_SIZE()),
    u1("usb_asm24_size", ASM24_SIZE()),
    u1("usb_win_fence_lo", WIN_FENCE_LO()),
    u1("usb_win_fence_hi", WIN_FENCE_HI()),
    u1("usb_win_cq_lo", WIN_CQ_LO()),
    u1("usb_win_cq_hi", WIN_CQ_HI()),
    u1("usb_win_sram_lo", WIN_SRAM_LO()),
    u1("usb_win_sram_hi", WIN_SRAM_HI()),
    b1("usb_sram_win_fits_asm24", sram_win_fits()),
    u1("usb_link_bytes", LINK_BYTES()),
    u1("usb_link_words", LINK_WORDS()),
    u1("usb_link_packed", LINK_PACKED()),
    u1("usb_stage_lo", STAGE_LO()),
    u1("usb_stage_hi", STAGE_HI()),
    u1("usb_zeros_lo", ZEROS_LO()),
    u1("usb_vram_words", VRAM_WORDS()),
    u1("usb_vram_bytes", VRAM_BYTES()),
    u1("usb_go_word", GO_WORD()),
    u1("usb_scratch_word", SCRATCH_WORD()),
    u1("usb_bulk_buf", BULK_BUF()),
    u1("usb_ctrl_buf", CTRL_BUF()),
    u1("usb_table_row_bytes", TABLE_ROW_BYTES()),
    u1("usb_table_size_off", TABLE_SIZE_OFF()),
    u1("usb_req_power", REQ_POWER()),
    u1("usb_req_f0", REQ_F0()),
    u1("usb_req_f2", REQ_F2()),
    u1("usb_req_e4", REQ_E4()),
    u1("usb_req_e5", REQ_E5()),
    u1("usb_mode_mask", MODE_MASK()),
    u1("usb_cfg_fmt_rd", CFG_FMT_RD()),
    u1("usb_cfg_fmt_wr", CFG_FMT_WR()),
    u1("usb_cfg_bus_shift", CFG_BUS_SHIFT()),
    u1("usb_cfg_dev_shift", CFG_DEV_SHIFT()),
    u1("usb_cfg_fn_shift", CFG_FN_SHIFT()),
    u1("usb_cfg_ba_mask", CFG_BA_MASK()),
    u1("usb_xdata_chunk", XDATA_CHUNK()),
    u1("usb_sram_align", SRAM_ALIGN()),
    u1("usb_sram_slot", SRAM_SLOT()),
    u1("usb_drain_mod", DRAIN_MOD()),
    u1("usb_stream_fmt_wr", STREAM_FMT_WR()),
    u1("usb_stream_fmt_rd", STREAM_FMT_RD()),
    u1("usb_stream_byte_en", STREAM_BYTE_EN()),
    u1("usb_copyin_win", usb_window(True{})),
    u1("usb_copyout_win", usb_window(False{})),
    u1("usb_remote_n", REMOTE_N())
  ]))

def t_sentinel() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_sentinel_magic", SENTINEL_MAGIC()),
    u1("usb_sentinel_mask", SENTINEL_MASK()),
    u1("usb_sentinel_0", usb_sentinel(0)),
    u1("usb_sentinel_1", usb_sentinel(1)),
    u1("usb_sentinel_max24", usb_sentinel(16777215)),
    u1("usb_sentinel_max24_p1", usb_sentinel(16777216)),
    u1("usb_sentinel_allones", usb_sentinel(4294967295)),
    b1("usb_sentinel_collide_24", sentinels_collide(0, 16777216)),
    b1("usb_sentinel_collide_23", sentinels_collide(0, 8388608)),
    b1("usb_sentinel_collide_adjacent", sentinels_collide(0, 1))
  ]))

def t_pcie_read() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_pcie_mask_1", pcie_read_mask(1n)),
    u1("usb_pcie_mask_2", pcie_read_mask(2n)),
    u1("usb_pcie_mask_3", pcie_read_mask(3n)),
    u1("usb_pcie_mask_4", pcie_read_mask(4n)),
    u1("usb_pcie_extract_allff_s4_o0", pcie_extract(4294967295, 4n, 0)),
    u1("usb_pcie_extract_allff_s1_o0", pcie_extract(4294967295, 1n, 0)),
    u1("usb_pcie_extract_deadbeef_s1_o0", pcie_extract(3735928559, 1n, 0)),
    u1("usb_pcie_extract_deadbeef_s2_o1", pcie_extract(3735928559, 2n, 1)),
    u1("usb_pcie_extract_deadbeef_s2_o2", pcie_extract(3735928559, 2n, 2)),
    u1("usb_pcie_extract_deadbeef_s4_o3", pcie_extract(3735928559, 4n, 3)),
    u1("usb_pcie_offset_0", pcie_offset(0)),
    u1("usb_pcie_offset_3", pcie_offset(3)),
    u1("usb_pcie_offset_4", pcie_offset(4)),
    u1("usb_pcie_offset_allff", pcie_offset(4294967295))
  ]))

def t_fastpath() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_fast_p1_mask", FAST_P1_MASK()),
    u1("usb_fast_p1_val", FAST_P1_VAL()),
    u1("usb_fast_p2_mask", FAST_P2_MASK()),
    u1("usb_fast_p2_val", FAST_P2_VAL()),
    # DECIMAL IN THE ROW NAME TOO. Bend has no `0x` literal, and the oracle
    # names these rows with `str(hx)`, so a hex-spelled name is a permanent
    # disagreement rather than a visible one.
    b1("usb_nocompletion_64", pcie_no_completion(64)),
    b1("usb_nocompletion_48", pcie_no_completion(48)),
    b1("usb_nocompletion_68", pcie_no_completion(68)),
    b1("usb_nocompletion_4", pcie_no_completion(4)),
    b1("usb_nocompletion_76", pcie_no_completion(76)),
    b1("usb_nocompletion_0", pcie_no_completion(0)),
    b1("usb_nocompletion_32", pcie_no_completion(32)),
    b1("usb_nocompletion_96", pcie_no_completion(96))
  ]))

def t_stream() -> IO(Unit):
  IO.print(lines_of([
    u1("usb_pcie_mem_nchunks_max", pcie_mem_nchunks(USB_MAX_STREAM())),
    u1("usb_pcie_mem_nchunks_max_p1", pcie_mem_nchunks(U32.add(USB_MAX_STREAM(), 1))),
    u1("usb_pcie_mem_nchunks_2max", pcie_mem_nchunks(U32.mul(2, USB_MAX_STREAM()))),
    u1("usb_pcie_mem_nchunks_0", pcie_mem_nchunks(0)),
    u1("usb_pcie_mem_dwords_0", pcie_mem_dwords(0)),
    u1("usb_pcie_mem_dwords_4", pcie_mem_dwords(4)),
    u1("usb_pcie_mem_dwords_5", pcie_mem_dwords(5)),
    b1("usb_aligned4_0", aligned4(0)),
    b1("usb_aligned4_4", aligned4(4)),
    b1("usb_aligned4_5", aligned4(5)),
    b1("usb_aligned4_1", aligned4(1))
  ]))

def t_drained() -> IO(Unit):
  IO.print(lines_of([
    b1("usb_drain_need_fence_eq", drained_step(7, 7)),
    b1("usb_drain_need_fence_ahead1", drained_step(7, 6)),
    b1("usb_drain_need_fence_ahead2", drained_step(7, 5)),
    b1("usb_drain_need_fence_ahead3", drained_step(7, 4)),
    b1("usb_drain_need_fence_1behind", drained_step(7, 8)),
    b1("usb_drain_need_fence_2behind", drained_step(7, 9)),
    b1("usb_drain_wrap_need1_fence3", drained_step(1, 3)),
    b1("usb_drain_wrap_need0_fence0", drained_step(0, 0)),
    b1("usb_drain_wrap_need0_fence255", drained_step(0, 255)),
    b1("usb_drain_wrap_need0_fence254", drained_step(0, 254)),
    b1("usb_drain_wrap_need255_fence0", drained_step(255, 0)),
    b1("usb_drain_wrap_need2_fence0", drained_step(2, 0)),
    # A `need` PAST the one-byte window is what the `& 0xff` exists for: 300
    # and 44 differ by 256, so the masked difference is 44 and the step is
    # True; 300 and 43 differ by 257, so it is 1 and is not `> 1`. One row
    # from its positive, and the only pair that can see it.
    b1("usb_drain_need300_fence44", drained_step(300, 44)),
    b1("usb_drain_need300_fence43", drained_step(300, 43))
  ]))

def t_remote() -> IO(Unit):
  IO.print(lines_of([
    s1("usb_remote_prefixes", remote_prefixes()),
    b1("usb_remote_usb_host", is_remote_prefix("usb_host", "usb_host")),
    b1("usb_remote_usb_xfer0", is_remote_prefix("usb_xfer0", "usb_xfer")),
    b1("usb_remote_usb_xfer1", is_remote_prefix("usb_xfer1", "usb_xfer")),
    b1("usb_remote_put_value", is_remote_prefix("put_value", "put_value")),
    b1("usb_remote_cmdbuf_copy", is_remote_prefix("cmdbuf_copy", "cmdbuf_copy")),
    b1("usb_remote_kernargs_usb_host", is_remote_prefix("kernargs", "usb_host")),
    b1("usb_remote_kernargs_usb_xfer", is_remote_prefix("kernargs", "usb_xfer")),
    b1("usb_remote_kernargs_put_value", is_remote_prefix("kernargs", "put_value")),
    b1("usb_remote_kernargs_cmdbuf_copy", is_remote_prefix("kernargs", "cmdbuf_copy")),
    b1("usb_remote_usb_table", is_remote_prefix("usb_table", "usb_host")),
    b1("usb_remote_arg_cache", is_remote_prefix("arg_cache", "usb_xfer")),
    b1("usb_remote_usb_hostx", is_remote_prefix("usb_hostx", "usb_host")),
    b1("usb_remote_xusb_host", is_remote_prefix("xusb_host", "usb_host"))
  ]))
