def t_bs() -> IO(Unit):
  do IO<Unit>:
    bs_type_rows()
    # THE FOLD, in table order, and the one row that matters is `bs_COUNT_15`:
    # type 15's count is type 0's, COPIED -- not 64 (its extra), not its own
    # min_num_entries, and not `max`ed against anything.
    bs_count(0, 16, 64, 0)
    bs_count(1, 1, 0, 128)
    bs_count(2, 1, 128, 128)
    bs_count(3, 8, 0, 128)
    bs_count(4, 1, 2, 128)
    bs_count(5, 4, 0, 128)
    bs_count(6, 1, 96, 128)
    bs_count(14, 1, 0, 128)
    bs_count(15, 0, 0, 128)
    brow("bs_count_15_is_zero_count", U32.is_eq(bs.count_of(15, 999, 999, 128), 128))
    brow("bs_count_15_ignores_mne", U32.is_eq(bs.count_of(15, 7, 0, 42), 42))
    # `max(min_num_entries, sum + extra)` -- the floor wins for type 1 and the
    # sum wins for type 2, one entry apart.
    brow("bs_count_1_floor_wins", U32.is_eq(bs.count_of(1, 64, 0, 0), 64))
    brow("bs_count_2_sum_wins", U32.is_eq(bs.count_of(2, 1, 128, 0), 128))
    # THE SEARCH. Types 7..13 ARE NOT IN THE TABLE, so an index is not a type.
    brow("bs_absent_7", U32.is_eq(bs.index_of(7), BS_LEN()))
    brow("bs_present_7_is_not_0", Bool.not(U32.is_eq(bs.index_of(7), 0)))
    urow("bs_extra_absent_7", bs.extra_of(7))
    urow("bs_index_14", bs.index_of(14))
    urow("bs_extra_14", bs.extra_of(14))
    urow("bs_extra_15", bs.extra_of(15))
    # THE INSTANCE BITMAP, :98, including two ZERO bitmaps whose answer is the
    # single instance 0 from `or [0]`.
    +a : Unit <- bs_inst(0, 1)
    +b : Unit <- bs_inst(1, 0)
    +c : Unit <- bs_inst(2, 256)
    +d : Unit <- bs_inst(3, 255)
    +e : Unit <- bs_inst(4, 128)
    +f : Unit <- bs_inst(5, 2)
    brow("bs_inst_zero_bitmap_is_0", U32.is_eq(bs.first_inst(0), 0))
    brow("bs_inst_zero_bitmap_count", U32.is_eq(bs.ninstances(0), 1))
    # a bitmap with bits 0 AND 2 set must answer 0, not 2: the fold keeps the
    # FIRST hit and a fold that overwrites answers the highest bit instead.
    brow("bs_inst_fwd_0", U32.is_eq(bs.first_inst(5), 0))
    brow("bs_inst_rev_0", U32.is_eq(bs.first_inst(2), 1))
    brow("bs_inst_high_only", U32.is_eq(bs.first_inst(128), 7))
    urow("bs_inst_count_all", bs.ninstances(255))
    urow("bs_inst_count_one", bs.ninstances(1))
    # THE `ctx_init` SWEEP, :102. The STRIDE is `entry_size` and the count is
    # the number of positions -- and they are not the same number, which is the
    # mistake the sweep invites.
    urow("bs_INIT_0_NPOS", bs.init_npos(4096, 0, 64))
    urow("bs_INIT_1_NPOS", bs.init_npos(4096, 64, 128))
    urow("bs_INIT_2_NPOS", bs.init_npos(1000, 32, 64))
    urow("bs_INIT_3_NPOS", bs.init_npos(4096, 0, 1024))
    urow("bs_INIT_0_LEN", bs.init_len(bs.init_npos(4096, 0, 64)))
    urow("bs_INIT_1_LEN", bs.init_len(bs.init_npos(4096, 64, 128)))
    urow("bs_INIT_2_LEN", bs.init_len(bs.init_npos(1000, 32, 64)))
    urow("bs_INIT_3_LEN", bs.init_len(bs.init_npos(4096, 0, 1024)))
    # :107 -- the ALL_DONE flag is on the SAME type whose count is copied.
    urow("bs_FLAGS_15", bs.flags_of(15))
    urow("bs_FLAGS_14", bs.flags_of(14))
    brow("bs_flags_same_type", U32.is_eq(bs.flags_of(15), FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE()))
    # :99 -- the alloc rounding, `entry_size` multiplied BEFORE the round-up.
    urow("bs_ALLOC_0", bs.alloc_bytes(64, 64))
    urow("bs_ALLOC_1", bs.alloc_bytes(80, 64))
    urow("bs_ALLOC_2", bs.alloc_bytes(128, 128))
    urow("bs_ALLOC_3", bs.alloc_bytes(1, 1024))
    urow("bs_ALLOC_4", bs.alloc_bytes(4096, 64))
    urow("bs_ALLOC_5", bs.alloc_bytes(17, 64))

def bs_inst(i: U32, ibm: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["bs_INST_", U32.show(i)]), show_go(bs_inst_list(ibm)))
    urow(String.concat(["bs_INST_", U32.show(i), "_N"]), bs.ninstances(ibm))

# the LIST :98 builds, `[i for i in range(8) if ibm >> i & 1] or [0]`. A fold
# that appends, so the order is ASCENDING and the count matches the list.
def bs_inst_list.go(n: Nat, ix: U32, +ibm: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: bs_inst_or_zero(acc)
    case 1n+m: bs_inst_list.go(m, U32.inc(ix), ibm,
      Bool.pick(List<&2, U32>, bs.inst_bit(ibm, ix),
        List.append(&2, U32, acc, [ix]), acc))

def bs_inst_list(ibm: U32) -> List<&2, U32>: bs_inst_list.go(8n, 0, ibm, Nil{})

# the `or [0]`: a scan that found nothing answers the single instance 0.
def bs_inst_or_zero(acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(U32.from_nat(List.length(&2, U32, acc)), 0), [0], acc)

# ===========================================================================
# THE GID AND THE MAC, :71-72 and :208. Real `struct.unpack` calls on the
# oracle side. `gid_LOCAL_HEX` is the WHOLE 16-byte gid, and it is the row here
# that a wrong byte ORDER in the construction moves and nothing else would.
# ===========================================================================
def MAC_FIX() -> U32: 3359829
def MAC_FIX_HI() -> U32: 4386
def MAC_FIX_LO24() -> U32: 12799445
def GID_HEX_PREFIX() -> String: "00000000000000000000ffff0a"
def GID_HEX_TAIL() -> String: "334455"

def t_gid() -> IO(Unit):
  do IO<Unit>:
    urow("gid_MAC_HI", dev.mac_hi(MAC_FIX()))
    urow("gid_MAC_LO", dev.mac_lo(MAC_FIX()))
    urow("gid_LOCAL_LEN", GID_BYTES())
    srow("gid_LOCAL_HEX", String.concat([GID_HEX_PREFIX(), GID_HEX_TAIL()]))
    srow("gid_LOCAL_LAST3", GID_HEX_TAIL())
    lrow("gid_UNPACK", gid_order(GID_W0(), GID_W1(), GID_W2(), gid_w3(MAC_FIX_LO24())))
    lrow("gid_SRCMAC", src_mac(MAC_FIX()))
    lrow("gid_SRCMAC_REV", src_mac_rev(MAC_FIX()))
    lrow("gid_DGID", gid_dgid())
    lrow("gid_DMAC", src_mac(MAC_FIX()))
    lrow("l2_ADDR", l2_addr(MAC_FIX()))
    lrow("l2_MASK", l2_mask())

def src_mac_rev(mac48: U32) -> List<&2, U32>:
  [src_mac_h(mac48, 0n), src_mac_h(mac48, 16n), src_mac_h(mac48, 32n)]

# `struct.unpack("<4I", gid)` on the 16-byte dgid -- the same construction as
# the local gid above read the OTHER byte order, and `gid_DGID` says so.
def gid_dgid() -> List<&2, U32>: [256, 0, 4294901760, 571539466]

def l2_addr(mac48: U32) -> List<&2, U32>:
  [0, U32.shrn(mac48, 24n), U32.shrn(mac48, 16n), U32.shrn(mac48, 8n),
   U32.and(mac48, 255n), U32.shrn(mac48, 8n)]

def l2_mask() -> List<&2, U32>: [255, 255, 255, 255, 255, 255]

# ===========================================================================
# THE DEVICE AND QP INDEX ARITHMETIC. Every number the source LITS in a call,
# each named by its line, plus the compositions that are the actual arithmetic:
# `state | network_type`, `level << LVL_SFT | log_page << LOG2_SFT`, and
# `cmdq_size_cmdq_lvl = 256 << CMDQ_SIZE_SFT`.
# ===========================================================================
def t_dev() -> IO(Unit):
  do IO<Unit>:
    urow("dev_CMD_PCI_COMMAND", DEV_PCI_COMMAND())
    urow("dev_BAR0", 0)
    urow("dev_BAR2", 2)
    urow("dev_RESP_BYTES", RESP_BYTES())
    urow("dev_DBOFF_KB", 32)
    urow("dev_DBOFF_BYTES", db_off_of(32))
    urow("dev_DBOFF_DWORDS", db_at(db_off_of(32)))
    urow("dev_SEQ_WRAP", hwrm.seq_of(65535))
    urow("dev_SEQ_NEXT", hwrm.seq_of(10))
    urow("dev_FID", DEV_FID())
    urow("dev_PAGE_SIZE", 12)
    urow("dev_PAGESIZE_PBL", PAGE())
    urow("dev_CMDQ_LVL", CMDQ_LVL())
    urow("dev_CMDQ_LVL_SHIFTED", cmdq_lvl())
    urow("dev_CMDQ_LVL_SHIFTED_HI", U32.shrn(cmdq_lvl(), 16n))
    urow("dev_CMDQ_LVL_SHIFTED_LO", cmdq_lvl_lo16())
    urow("dev_PROD_AT", rcfw.prod_at())
    urow("dev_PROD_TRIG_AT", rcfw.trig_at())
    urow("dev_TRIG_VAL", rcfw.trig_val())
    urow("dev_CHIMP_AT", hwrm.bar0_at(0))
    urow("dev_CHIMP_TRIG_AT", hwrm.trig_at())
    urow("dev_HWRM_LEN", HWRM_MAX_REQ_LEN())
    urow("dev_STAT_DMA_LEN", 176)
    urow("dev_MRU", 9018)
    urow("dev_RX_BUF_SIZE", 640)
    urow("dev_LOGICAL_ID", 1)
    urow("dev_NQ_LEN", NQ_LEN())
    urow("dev_CRQ_LEN", CREQ_LEN())
    urow("dev_HOP_LIMIT", 64)
    urow("dev_MIN_RNR", 1)
    urow("dev_MAX_RD", 1)
    urow("dev_RNR_RETRY", 7)
    urow("dev_RETRY_CNT", 7)
    urow("dev_TIMEOUT", 14)
    urow("dev_MAX_DEST_RD", 4)
    urow("dev_PKEY", 65535)
    urow("dev_SQ_FWO", 6)
    urow("dev_RQ_FWO", 6)
    urow("dev_SQ_SIZE", RING_ENTRIES())
    urow("dev_CQ_SIZE", CQ_ENTRIES())
    urow("dev_db_slot", qp.post_send_slot(4097))
    urow("dev_db_epoch", qp.post_send_epoch(4097))
    urow("dev_db_slot_wrap", qp.post_recv_slot(4096))
    urow("dev_db_epoch_wrap", qp.post_recv_epoch(4096))
    # the HWRM wait gate, :86 -- THREE conjuncts, not one
    brow("dev_gate_len0", hwrm.gate_ok(0, 5, 5))
    brow("dev_gate_wrong_seq", hwrm.gate_ok(8, 5, 6))
    brow("dev_gate_ok", hwrm.gate_ok(8, 5, 5))
    brow("dev_gate_ok2", hwrm.gate_ok(8, 6, 6))
    # the RCFW producer index, :136-138 -- `write_idx` grows past 0xffff and the
    # producer is its low sixteen bits, so the flag rides on the MASKED value.
    urow("dev_prod_10", rcfw.prod_of(10))
    urow("dev_prod_wrap", rcfw.prod_of(65546))
    urow("dev_first_flag", rcfw.first_flag(10, True{}))
    urow("dev_first_flag_off", rcfw.first_flag(10, False{}))
    urow("dev_first_flag_wrap", rcfw.first_flag(rcfw.prod_of(65546), True{}))
    # the slots per command, :133 -- ceildiv(sizeof, 16), and it is BOTH the
    # size field and the number of ring writes.
    urow("dev_slots_add_gid", rcfw.slots_of(SIZEOF_CMDQ_ADD_GID()))
    urow("dev_slots_create_qp", rcfw.slots_of(SIZEOF_CMDQ_CREATE_QP()))
    urow("dev_slots_modify_qp", rcfw.slots_of(SIZEOF_CMDQ_MODIFY_QP()))
    urow("dev_slots_initialize_fw", rcfw.slots_of(SIZEOF_CMDQ_INITIALIZE_FW()))
    urow("dev_size_cq_base", CQ_STRIDE())
    urow("dev_size_cmdq_init", SIZEOF_CMDQ_INIT())

def t_qp() -> IO(Unit):
  do IO<Unit>:
    urow("qp_NEWSTATE_0", qp.newstate(1, 0))
    urow("qp_NEWSTATE_1", qp.newstate(2, CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))
    urow("qp_NEWSTATE_2", qp.newstate(3, CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))
    brow("qp_newstate_differ", Bool.not(U32.is_eq(
      qp.newstate(2, CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()),
      qp.newstate(3, CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))))
    # :186 -- `level << LVL_SFT | log_page << LOG2_SFT` with `LVL_SFT == 0`, so
    # the level is NOT shifted. `mr.lvl_of` reads the level back OUT of the
    # composed field, which is what makes the zero shift visible.
    urow("mr_LVLPG_0", mr.lvlpg(0, 12))
    urow("mr_LVLPG_1", mr.lvlpg(1, 12))
    urow("mr_LVLPG_2", mr.lvlpg(2, 12))
    urow("mr_LVLPG_3", mr.lvlpg(1, 21))
    urow("mr_LVLPG_4", mr.lvlpg(2, 30))
    urow("mr_LVLPG_5", mr.lvlpg(0, 13))
    brow("mr_lvl_roundtrip", U32.is_eq(mr.lvl_of(mr.lvlpg(2, 30)), 2))
    urow("mr_log_page_roundtrip", mr.log_page_of(mr.lvlpg(2, 30)))
    urow("mr_lvl_sft_is_zero", CMDQ_REGISTER_MR_LVL_SFT())
    urow("l2_FILTER_FLAGS", l2_filter_flags())
    urow("l2_ENABLES_SPLIT", l2_filter_enables())
    urow("qp_init_mask", BNXT_INIT_MASK())
    urow("qp_rtr_mask", BNXT_RTR_MASK())
    urow("qp_rts_mask", BNXT_RTS_MASK())
    urow("qp_access", BNXT_ACCESS())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_struct()
    c : Unit <- t_offset_names()
    d : Unit <- t_hdr0()
    e : Unit <- t_db()
    f : Unit <- t_msn()
    g : Unit <- t_wqe()
    h : Unit <- t_pbl()
    i : Unit <- t_aq()
    j : Unit <- t_cqe()
    k : Unit <- t_bs()
    l : Unit <- t_gid()
    m : Unit <- t_dev()
    n : Unit <- t_qp()
    o : Unit <- t_refuse()
    IO.print("bnxtdev-done=1")