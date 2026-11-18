<!-- FROM: tinybendygrad/runtime/support/rdma/bnxtdev.bend:42 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF. Line numbers are bnxtdev.py.
#
#   :8-12 the five constant lines   PORTED  every value, both directions
#   :11  `BNXT_BACKING_STORE`      PORTED  nine (type, extra) pairs, in order
#   :13  `db_value`                PORTED  `db.hi` / `db.lo`, and the whole
#                                              64-bit word as two halves
#   :18  `send_wqe`                PORTED  the 8 words, the pack format and
#                                              the field list by name
#   :19  `recv_wqe`                PORTED  the 7 words -- and the `I size` at
#                                              byte 8 that the receive pack's
#                                              29-byte pad runs OVER
#   :20  `msn_entry`               PORTED  `msn.of` / `msn.hi` / `msn.lo`
#   :22  `ceildiv(size, MTU)`      PORTED  `msn.pkts`
#   :24  the 48/24/24 msn word     PORTED  the same shift amount is MEASURED
#                                              from `SQ_MSN_SEARCH_START_IDX_SFT`
#   :25  `cqe_ready`               PORTED  `cqe.ready`, off `cqe_type_toggle`
#   :27  `build_pbl`               PORTED  `pbl.level_of` / `pbl.entry` /
#                                              `pbl.decode`, encode AND decode
#   tinygrad/runtime/support/rdma/bnxtdev.py:28 the one-paddr shortcut    PORTED  `pbl.level_of(1) == 0` -- upstream's `paddrs` symbol=build_pbl
#   :34  `assert len <= 512`       PORTED  the REFUSAL, a truncated trace
#   :42  `BNXTQueue.read`          PORTED  `q.read_off`, `q.read_len`
#   :44  `BNXTQueue.write`         PORTED  `q.write_off` -- and the `aux`
#                                              arm, which is a DIFFERENT base
#   :48  `entries or 0x1000//stride` PORTED `aq.entries_of`
#   :49  `(size:=entries*stride) + aux*entries*8` PORTED `aq.size_of`
#   :91  `setup_backing_store`     PORTED  `bs.fold` and its three derivations
#   :96  `counts[typ] = ...`       PORTED  `bs.count_of`, incl. the type-15
#                                              REUSE of `counts[0]`
#   :98  the instance bitmap walk  PORTED  `bs.instances`
#   :99  `ceildiv(n*size, 0x1000)*0x1000` PORTED `bs.alloc_bytes`
#   :100 the `ctx_init_value` sweep   PORTED  the port's own bs.init_npos / bs.init_stride
#   :107 the ALL_DONE `flags`         PORTED  the port's own bs.flags_of
#   :53  `BNXTDev.__init__`        PORTED  `dev.init`, the ordered trace
#   :56  the PCI_COMMAND write     PORTED  `pci.master_enable`
#   :57  `map_bar(0,'I')/(2,'Q')`  PORTED  `BAR0` / `BAR2`
#   :60  `hwrm("ver_get")`         PORTED  a WAIT, in `hwrm`
#   :62  `hwrm("func_reset")`      PORTED  the sequence counter, `hwrm.seq_of`
#   :64  `int.from_bytes(mac)`     PORTED  `dev.mac_of`, `dev.port_of`
#   :66  `db_off = kb * 1024`      PORTED  `dev.db_off_of` -- and it is a
#                                              BYTE offset divided by 8 for
#                                              the 64-bit doorbell bar
#   :71  `local_gid`               PORTED  `dev.local_gid`
#   :72  `>4I` reversed, `>3H`     PORTED  `dev.gid_words` / `dev.src_mac`
#   :76  `hwrm`                    PORTED  `hwrm`, in the trace
#   :78  `(seq+1) & 0xffff`        PORTED  `hwrm.seq_of`, with the wrap
#   :79  `cmpl_ring`/`target_id`   PORTED  `hwrm.header`
#   :81  the 0x1000-byte clear     PORTED  a WRITE, in the trace
#   tinygrad/runtime/support/rdma/bnxtdev.py:83 the word loop into bar0  PORTED  `hwrm.bar0_at` -- upstream's `bar0` symbol=hwrm
#   tinygrad/runtime/support/rdma/bnxtdev.py:84 the trigger dword         PORTED  `hwrm.trig_at` -- upstream's `bar0` symbol=hwrm
#   :86  `resp_len` / `seq_id`     PORTED  `hwrm.gate_ok`
#   :88  `assert error_code == 0`  PORTED  the REFUSAL
#   :110 `_open_rcfw`              PORTED  `dev.open_rcfw`, the ordered trace
#   :112 `ring_alloc` NQ           PORTED  `dev.ring_alloc`
#   :115 the NQ_ARM doorbell       PORTED  `dev.doorbell`
#   :116 `cmdq_size_cmdq_lvl`      PORTED  `dev.cmdq_lvl`
#   :121-123 `stat_ctx_alloc`      PORTED  `dev.open_rcfw`'s trace
#   :127 the notification NQ       PORTED  `dev.nq`, logical_id 1
#   :130 `rcfw`                    PORTED  `rcfw`, in the trace
#   :133 `ceildiv(sizeof(req_t),16)` PORTED `rcfw.slots_of`
#   :136-137 the producer index    PORTED  `rcfw.write_idx` / `rcfw.prod`
#   tinygrad/runtime/support/rdma/bnxtdev.py:138 the FIRMWARE_FIRST flag   PORTED  `rcfw.first_flag` -- upstream's `FIRMWARE_FIRST_FLAG` symbol=rcfw
#   :142-143 the prod/trig dwords  PORTED  `rcfw.prod_at` / `rcfw.trig_at`
#   :146 the CREQ valid test       PORTED  `creq.ready`
#   tinygrad/runtime/support/rdma/bnxtdev.py:153 the NQ_ARM consumer db    PORTED  `rcfw.nq_arm` -- upstream's `DBC_DBC_TYPE_NQ_ARM` symbol=rcfw
#   tinygrad/runtime/support/rdma/bnxtdev.py:154 the QP_EVENT filter       PORTED  `rcfw.is_final`, and its threshold -- upstream's `CREQ_BASE_TYPE_QP_EVENT` symbol=rcfw
#   :155 `assert ret.status == 0`  PORTED  the REFUSAL
#   :160 `fini`                    PORTED  `dev.fini`
#   :167 `_open_l2`                PORTED  `dev.open_l2`, the enable masks
#   :183 `register_mem`            PORTED  `dev.register_mem` -- the
#                                              `level << LVL_SFT | lps <<
#                                              LOG2_SFT` composition
#   :189 `unregister_mem`          PORTED  `dev.unregister_mem`
#   :191 `BNXTQP.__init__`         PORTED  `qp.new`, the four queues
#   :194 `sizeof(struct_cq_base)`  PORTED  `SIZEOF_CQ_BASE` -- so the CQ
#                                              stride is 32 and not 64
#   :198 `create_qp`               PORTED  `qp.create`
#   :201 `modify_qp(1, INIT_MASK)` PORTED  `qp.modify`
#   :203 `modify_qp`               PORTED  `qp.newstate` -- `state | ntype`
#   :206 `connect`                 PORTED  `qp.connect`, both transitions
#   :208 `struct.unpack` dgid/dmac PORTED  `qp.dgid` / `qp.dmac`
#   :219 `poll`                    PORTED  `qp.poll`, and its CQ doorbell
#   :224 `assert raw[25] == 0`     PORTED  the REFUSAL
#   :227 `post_send`               PORTED  `qp.post_send`, the ordered trace
#   :230 the aux msn write         PORTED  in the same trace
#   :232 the SQ doorbell           PORTED  in the same trace
#   :234 `post_recv`               PORTED  `qp.post_recv`
# END BLOCK
