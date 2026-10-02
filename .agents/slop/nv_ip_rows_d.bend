# ===========================================================================
# t_trace -- THE REQUEST TRACE FOR A FIXED REQUEST LIST.
#
# The seven requests are the ones `NV_GSP.init_sw` and `init_hw` actually issue,
# in the order it issues them: set_system_info, set_registry, alloc_memory,
# gsp_rm_alloc, gsp_rm_control, set_page_directory, unloading_guest_driver.
# ===========================================================================

def t_trace() -> IO(Unit):
  do IO<Unit>:
    t_trace_reqs()
    t_trace_elem()
    t_trace_wp()
    t_trace_rx()
    t_trace_handles()
    t_trace_seqs()
    t_trace_fsp()

# --- the seven requests, one row group each ------------------------------
def t_trace_reqs() -> IO(Unit):
  do IO<Unit>:
    t_req(0, 72, 928)
    t_req(1, 73, 82)
    t_req(2, 4, 64)
    t_req(3, 103, 32)
    t_req(4, 76, 24)
    t_req(5, 54, 48)
    t_req(6, 47, 8)

def t_req(+i: U32, +func: U32, +plen: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rp.record(func, plen, 0, tr.at(Tr.of(), i)))
    urow(String.concat(["ip_rp_", U32.show(i), "_func"]), Rq.func(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_plen"]), Rq.plen(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_length"]), rp.length(plen))
    urow(String.concat(["ip_rp_", U32.show(i), "_elem"]), Rq.elem(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_total"]), Rq.total(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_cksum"]), Rq.cksum(r))
    urow(String.concat(["ip_rp_", U32.show(i), "_seq0"]), i)
    urow(String.concat(["ip_rp_", U32.show(i), "_seq1"]), Rq.seq(r))
    t_req_order(i, r)
    t_req_words(i, func, plen)

# THE TWENTY U32 WORDS of `bytes(phdr) + header`, one row each. The folded
# checksum cannot see the hi/lo split -- `hi32(c) ^ lo32(c)` is symmetric, so
# swapping which word of a pair is `hi` leaves the answer alone, and a mutation
# that does that (`rp.pickw` with its arms exchanged) moves ZERO rows. These rows
# are what make it visible: they name the word at each index, so an exchanged
# pair moves twenty rows instead of none.
def t_req_words(+i: U32, +func: U32, +plen: U32) -> IO(Unit):
  do IO<Unit>:
    t_words(i, func, plen, List.range(U32.to_nat(rp.nwords())))

def t_words(+i: U32, +func: U32, +plen: U32, +ks: List<&2, Nat>) -> IO(Unit):
  match ks:
    case Nil{}: IO.pure(Unit, Unit{})
    case k <> r:
      do IO<Unit>:
        p : Unit <- urow(String.concat(["ip_rp_", U32.show(i), "_w", U32.show(U32.from_nat(k))]),
                         rp.word(U32.from_nat(k), func, plen, i))
        t_words(i, func, plen, r)

# `elemCount` is the ONLY place the 32-byte header shows up in the arithmetic, and
# for all seven requests it does not: they are small enough that `plen + 48` and
# `plen + 80` round to the same element count. The header matters only in the band
# `4096k - 79 <= plen <= 4096k - 49`, so 4016/4017 and 4047/4048 are the fixtures --
# and `ip_rp_elem_4017` is the row a port that dropped the header loses.
def t_trace_elem() -> IO(Unit):
  do IO<Unit>:
    t_elem(4016)
    t_elem(4017)
    t_elem(4047)
    t_elem(4048)
    t_elem(16336)
    t_elem(16337)

def t_elem(+plen: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rp.record(103, plen, 0, Tr.of()))
    urow(String.concat(["ip_rp_elem_", U32.show(plen)]), Rq.elem(r))

# `ip_tr_<i>_order` is the FIVE calls of :49-55 in order -- record, the two queue
# copies, the write pointer, the barrier, the doorbell. It is the row that says
# the doorbell comes AFTER the pointer store.
def t_req_order(+i: U32, +r: Rq) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["ip_tr_", U32.show(i), "_order"]), tr.show(Rq.tr(r)))
    urow(String.concat(["ip_tr_", U32.show(i), "_n"]), Tr.ncalls(Rq.tr(r)))

# --- the write pointer and the wrap, :48-51 -----------------------------
# The ring length is `msgSize*msgCount` and NOT the header's `size`, and on a real
# queue those differ by a page -- so the wrap boundary is a ROW, not a comment.
def t_trace_wp() -> IO(Unit):
  do IO<Unit>:
    urow("ip_rp_ring_len", rp.ring_len())
    row("ip_rp_ring_ne_size", U32.is_ne(rp.ring_len(), 262144))
    urow("ip_rp_msg_count", rp.msg_count())
    urow("ip_rp_entry_off", rp.entry_off())
    urow("ip_rp_maxpayload", rp.max_payload())
    t_wp(0)
    t_wp(1)
    t_wp(31)
    t_wp(62)
    t_wp(61)
    t_wp(63)

def t_wp(+wp: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rp.record(103, 32, 0, Tr.of.wp(wp)))
    srow(String.concat(["ip_rp_w", U32.show(wp), "_order"]), tr.show(Rq.tr(r)))
    urow(String.concat(["ip_rp_w", U32.show(wp), "_off"]), Rq.off(r))
    urow(String.concat(["ip_rp_w", U32.show(wp), "_first"]), Rq.first(r))
    urow(String.concat(["ip_rp_w", U32.show(wp), "_wraps"]), rp.wrapbit(Rq.total(r), wp))
    urow(String.concat(["ip_rp_w", U32.show(wp), "_wp"]), Rq.wp(r))

# --- :57-60 the CONTINUATION SPLIT, and :62-85 the response read ----------
# A payload of exactly `max_payload` is ONE record and one byte more is TWO.
def t_trace_rx() -> IO(Unit):
  do IO<Unit>:
    urow("ip_rp_cont_first_func", 72)
    urow("ip_rp_cont_func", rp.cont_func())
    t_cont(0)
    t_cont(1)
    t_cont(65455)
    t_cont(65456)
    t_cont(65457)
    t_cont(130912)
    t_cont(130913)
    urow("ip_rp_rx_off_hdr", 48)
    urow("ip_rp_rx_off_msg", 80)
    t_rx(0, 32)
    t_rx(0, 4096)
    t_rx(0, 4097)
    t_rx(5, 8192)
    t_rx(62, 32)
    t_rx(62, 16384)
    urow("ip_rp_result_ok", 0)
    urow("ip_rp_result_bad", 4294967295)
    urow("ip_rp_sig", rp.sig())
    urow("ip_rp_pending", rp.pending())
    urow("ip_rp_hdr_version", rp.hdr_version())
    urow("ip_rp_len_bias", 32)
    urow("ip_rp_err_lo", Cn.v(const_of("NV_VGPU_MSG_EVENT_OS_ERROR_LOG")))
    urow("ip_rp_err_hi", Cn.v(const_of("NV_VGPU_MSG_EVENT_MMU_FAULT_QUEUED")))
    t_err(4102)
    t_err(4101)
    t_err(4097)
    t_err(4)

def t_cont(+plen: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_rp_cont_", U32.show(plen), "_n"]), rp.cont_n(plen))

def t_rx(+rx: U32, +hlen: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["ip_rp_rx_", U32.show(rx), "_", U32.show(hlen), "_tag"]),
         rp.rx_tag(rx, hlen))
    urow(String.concat(["ip_rp_rx_", U32.show(rx), "_", U32.show(hlen), "_after"]), rp.rx_after(rx, hlen))
    urow(String.concat(["ip_rp_rx_", U32.show(rx), "_", U32.show(hlen), "_up"]), rp.rx_up(hlen))
    urow(String.concat(["ip_rp_rx_", U32.show(rx), "_", U32.show(hlen), "_elems"]), rp.rx_elems(hlen))

def t_err(+f: U32) -> IO(Unit):
  do IO<Unit>:
    row(String.concat(["ip_rp_iserr_", U32.show(f)]), rp.is_err(f))

# --- :348 the handle generator, :526-536 alloc, :594-599 pdir ------------
def t_trace_handles() -> IO(Unit):
  do IO<Unit>:
    urow("ip_rp_handle_first", hgen.first())
    urow("ip_rp_handle_n", hgen.n())
    urow("ip_rp_handle_7", hgen.nxt7())
    urow("ip_rp_am_hdr", 56)
    urow("ip_rp_am_pte", 8)
    urow("ip_rp_am_payload_1", am.plen(1))
    urow("ip_rp_am_payload_4", am.plen(4))
    t_alloc(0)
    t_alloc(4)

# `rpc_alloc_memory` is the ONE of the seven that is not a bare `send_rpc`: it
# mints a handle at :529, sends, and then WAITS at :535. The order row is what
# says the handle is minted before the send and that the wait is a call of its
# own -- and `ip_rp_am_0_order`'s seventh entry is that wait.
def t_alloc(+npages: U32) -> IO(Unit):
  do IO<Unit>:
    +r : Rq <- IO.pure(Rq, rpc.am2(1, 1, npages, Tr.of()))
    srow(String.concat(["ip_rp_am_", U32.show(npages), "_order"]), tr.show(Rq.tr(r)))
    urow(String.concat(["ip_rp_am_", U32.show(npages), "_plen"]), Rq.plen(r))
    urow(String.concat(["ip_rp_am_", U32.show(npages), "_elem"]), Rq.elem(r))
    urow(String.concat(["ip_rp_am_", U32.show(npages), "_n"]), Tr.ncalls(Rq.tr(r)))
    urow(String.concat(["ip_rp_am_", U32.show(npages), "_next"]), Tr.handle(Rq.tr(r)))
    urow("ip_rp_am_format", 6)
    urow("ip_rp_am_pteAdjust", 0)
    urow("ip_rp_am_idr", Cn.v(const_of("NV_VGPU_PTEDESC_IDR_NONE")))
    urow("ip_rp_page_size", 4096)
    row("ip_rp_page_ok", am.page_ok(4096))
    row("ip_rp_page_bad", am.page_ok(8192))
    row("ip_rp_pages_ok", am.pages_ok4(4096, 4096, 4096, 4096))
    row("ip_rp_pages_bad", am.pages_ok4(4096, 4096, 4096, 8192))
    urow("ip_rp_ra_hdr", 32)
    urow("ip_rp_rc_hdr", 24)
    urow("ip_rp_pd_hdr", 48)
    urow("ip_rp_pd_params", 32)
    urow("ip_rp_unload_hdr", 8)
    urow("ip_rp_ra_plen_0", rpc.ra_plen(0))
    urow("ip_rp_rc_plen_0", rpc.rc_plen(0))
    urow("ip_rp_flags0", 0)
    urow("ip_rp_cls_vaspace", Cn.v(const_of("FERMI_VASPACE_A")))
    urow("ip_rp_cls_device", Cn.v(const_of("NV01_DEVICE_0")))
    urow("ip_rp_cls_subdev", Cn.v(const_of("NV20_SUBDEVICE_0")))
    urow("ip_rp_cls_root", Cn.v(const_of("NV1_ROOT")))
    row("ip_rp_cls_root_is_0", U32.is_eq(Cn.v(const_of("NV1_ROOT")), 0))
    urow("ip_rp_pd_flags", 8)
    urow("ip_rp_pd_pasid", 4294967295)
    urow("ip_rp_pd_sub", 1)
    urow("ip_rp_pd_chid", 0)
    urow("ip_rp_si_mirror_base", 557056)
    urow("ip_rp_si_fmc_base", 598016)
    urow("ip_rp_si_mirror_size", 4096)
    urow("ip_rp_si_passthru", 1)
    urow("ip_rp_si_hdr", 928)
    urow("ip_rp_si_bar", 3)
    urow("ip_rp_si_cfg_vendor", 0)
    urow("ip_rp_si_cfg_subsys", 44)
    urow("ip_rp_si_cfg_rev", 8)

# --- :557 the runlist key and :590-591 the doorbell ----------------------
def t_trace_seqs() -> IO(Unit):
  do IO<Unit>:
    t_rl(0)
    t_rl(1)
    t_rl(4)
    t_rl(18)
    t_rl(19)
    t_rl(20)
    urow("ip_rp_runlist_miss", rpc.runlist_miss())
    t_tok("gb2", "GB202", 4660, 7)
    t_tok("ga10", "GA102", 4660, 7)
    t_tok("rl0", "GA102", 4660, 0)
    t_tok("rl31", "GB202", 4660, 31)
    urow("ip_rp_token_shift", 16)
    urow("ip_rp_token_bit30", 1073741824)
    row("ip_rp_chip_gb2", String.starts_with("GB202", "GB2"))
    row("ip_rp_chip_ga10", String.starts_with("GA102", "GB2"))
    t_fl()
    t_gsp()

def t_rl(+e: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_rp_runlist_key_", U32.show(e)]), rpc.runlist_key(e))

def t_tok(+tag: String, +chip: String, +tok: U32, +rl: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_rp_token_", tag]), door.token(tok, rl, chip))

# :186-210 and :236-265: the falcon register ORDER and its values.
def t_fl() -> IO(Unit):
  do IO<Unit>:
    srow("ip_fl_init_order", fl.order())
    urow("ip_fl_init_n", fl.order_n())
    urow("ip_fl_falcon", fl.falcon())
    urow("ip_fl_sec2", fl.sec2())
    urow("ip_fl_ctx_dma", fl.ctx_dma())
    urow("ip_fl_imem", fl.imem())
    urow("ip_fl_sec", fl.sec())
    urow("ip_fl_dmactl", fl.dmactl())
    urow("ip_fl_allow_phys_no_ctx", fl.allow_phys_no_ctx())
    urow("ip_fl_reset_engines", fl.reset_engines())
    urow("ip_fl_dma_chunk", fl.dma_chunk())
    urow("ip_fl_alias", fl.alias())
    urow("ip_fl_startcpu", fl.startcpu())
    urow("ip_fl_riscv_core1", fl.riscv_core1())
    urow("ip_fl_riscv_core0", fl.riscv_core0())
    t_chunks(0)
    t_chunks(1)
    t_chunks(255)
    t_chunks(256)
    t_chunks(257)
    t_chunks(512)
    t_chunks(4096)

def t_chunks(+size: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["ip_fl_dma_chunks_", U32.show(size)]), fl.chunks(size))

def t_gsp() -> IO(Unit):
  do IO<Unit>:
    srow("ip_gsp_init_order", gsp.init_order())
    urow("ip_gsp_init_n", gsp.init_n())
    urow("ip_gsp_priv_root", gsp.priv_root())

# --- :328-344 the FSP framing, in trace order ---------------------------
# EMEMC, one EMEMD per word, TAIL, HEAD -- and `QUEUE_TAIL` is
# `len(buf) - 4`, the padded total MINUS the last header word.
def t_trace_fsp() -> IO(Unit):
  do IO<Unit>:
    +t : Tr <- IO.pure(Tr, fsp.trace(fsp.nvmd_cot(), 82))
    srow("ip_fsp_tr_order", tr.show(t))
    urow("ip_fsp_tr_nwords", fsp.words(20, 82))
    urow("ip_fsp_tr_tot", fsp.tot(82))
    urow("ip_fsp_tr_tail_val", fsp.tail(82))
    urow("ip_fsp_tr_w0", fsp.w0())
    urow("ip_fsp_tr_w1", fsp.w1(fsp.nvmd_cot()))
    urow("ip_fsp_tr_nvmd_cot", fsp.nvmd_cot())
    urow("ip_fsp_tr_aincw1", fsp.aincw())
    urow("ip_fsp_tr_aincr0", fsp.aincr())
    urow("ip_fsp_tr_tail_off", fsp.tail_off())
    urow("ip_fsp_tr_head_off", fsp.head())
    +t2 : Tr <- IO.pure(Tr, fsp.trace(0, 82))
    srow("ip_fsp_tr_0_order", tr.show(t2))
    urow("ip_fsp_tr_0_nwords", fsp.words(0, 82))
    urow("ip_fsp_tr_0_tot", fsp.tot(82))
    urow("ip_fsp_tr_0_w0", fsp.w0())
    urow("ip_fsp_tr_0_w1", fsp.w1(0))