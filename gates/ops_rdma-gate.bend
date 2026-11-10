# gates/ops_rdma-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_rdma.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/ops_rdma.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/device.bend as D
import ./../tinybendygrad/LAWS/spec.bend as S

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([nm, "=", P.ustr(xs)]))
def ring_elems_of(+recv: Bool) -> U32: U32.mul(P.RING_ENTRIES(), P.ring_elems.at(recv))

def cq_elems() -> U32: U32.mul(P.CQ_ENTRIES(), 32)

def psn_bytes() -> U32: P.seq_bytes()
def db_elems() -> U32: P.PAGE()

# `to_name("rdma", lo, hi, name)` -- the four parts joined with `_`, in THIS
# order. The order is the claim: `to_name("rdma", *pair, n)` at :84 and
# `to_name("rdma", *pair, name)` at :90 must produce the same string for the
# same buffer or no rule ever fires.
def tag_of(+lo: String, +hi: String, +name: String) -> String:
  String.concat(["rdma_", P.tname(lo), "_", P.tname(hi), "_", P.tname(name)])

# :24 `device_fini` -- `self.dev_impl.fini()`, and it is the LAST thing a device
# does. `RDMA_FINI_LAST` in the gate is the row that says so.
def iface.fini(+i: P.Iface) -> P.Iface: P.Iface.at(i, P.Tr.emit(P.CALL_FINI(), P.OBJ_NONE(), P.Iface.tr(i)))

# :69-71 as ONE def, so a version that called `super().__init__` first would move
# `rdma_init_order` and not just some later count.
def dev.init(+dev_name: String, +db_off: U32) -> P.Tr:
  P.Tr.emit(P.CALL_DEVICE(), D.dev_id(dev_name), P.Iface.tr(P.Iface.of(dev_name, D.dev_id(dev_name), db_off)))

# :31 the buffer's size: `mem.nbytes`, RAW. Not rounded, and the difference is
# the whole point.
def alloc.buf_size(+nbytes: U32) -> U32: nbytes

def alloc.of(+size: U32, t: P.Tr) -> P.Tr: P.alloc.mem(size, P.alloc.sysmem(size, t))

# :41 `_copyin` -- `unwrap(dest.host)[:len(src)] = src`. The LENGTH IS THE
# SOURCE'S, and the trace records it. There is no `synchronize` here, which is
# the difference from `HostAllocator._copyin` (device.py:322): the RDMA device's
# host copies are ordered by the queue, not by a device-wide barrier.
def alloc.copyin(+len: U32, t: P.Tr) -> P.Tr: P.Tr.emit(P.CALL_INS_WRITE(), len, t)

def db.of(+db_off: U32, t: P.Tr) -> P.Tr:
  P.Tr.emit(P.CALL_BAR_INFO(), P.VRAM_BAR(), P.Tr.emit(P.CALL_MAP_BAR(), P.db.off_down(db_off), t))

# the physical address the doorbell lives at: `bar_info(2)[0] + off`, with the
# SAME `off` the mapping used.
def db.paddr(+bar_base: U32, +db_off: U32) -> U32: U32.add(bar_base, P.db.off_down(db_off))

# :129 -- the address the instruction stream writes: the whole-page placeholder's
# address PLUS the low twelve bits. Two masks, opposite directions, same constant.
def db.addr(+page: U32, +db_off: U32) -> U32: U32.add(page, P.db.off_up(db_off))

def db.snooped() -> Bool: False{}


def map.key_guard(+key: U32, +t: P.Tr) -> P.Tr:
  Bool.pick(P.Tr, Bool.not(U32.is_zero(key)), t, P.Tr.refuse(P.REFUSE_NO_KEY(), t))

# :42-53 `_map` as ONE def, so a version that registered before checking the peer
# group would move `rdma_map_order` and not merely some later count. The
# alignment is computed ONCE and both the page guard and the page count read that
# same number: an `align` that disagreed with the `log_page` derived from it is
# the bug this shape exists to make impossible.
# THE guards are nested inside the call, not outside it, and that is the whole
# difference between a refusal and a warning. Python raises at :48 -- the `max()`
# -- BEFORE it reaches `register_mem` at :50, so a buffer with no usable page size
# is NEVER REGISTERED. With the guards outside the call the trace would read
# `REGISTER(0), REFUSE(log_page)`: the registration happened and THEN the refusal,
# which is the opposite of what the source does. MEASURED: with the guards
# outside, `rdma_map_odd_regs` was 1; nested inside, it is 0. That was a real port
# bug and the oracle found it.
def map.run(+has_iface: Bool, src_peer: U32, dev_peer: U32, +sys: Bool, +va: U32,
            +raw: List<&2, U32>, +translated: List<&2, U32>, +sizes: List<&2, U32>,
            mapping_size: U32, t: P.Tr) -> P.Tr:
  P.map.call(P.npages(sizes, P.log_page(P.align_or(va, P.map.paddrs(sys, raw, translated), sizes))),
           P.map.page_guard(P.has_page(P.align_or(va, P.map.paddrs(sys, raw, translated), sizes)),
                          P.map.guard2(P.map.peer_ok(has_iface, src_peer, dev_peer), t)))

# :52 `_offset` -- `return buf`, UNCHANGED. Not a missing `+ offset` and not a
# simplification: a NIC-addressed buffer has no GPU-visible offset arithmetic,
# because the offset that matters is inside the key. THIS IS THE NEGATIVE CASE the
# brief asked for and it is a pure one -- the trace for `_offset` is EMPTY, so
# `rdma_offset_n = 0` is the row, and an implementation that added the offset
# would print a different number in `rdma_offset_val` rather than a different
# trace. Contrast `ops_npy.bend`'s `npy.offset`, which IS `buf + offset`.
def alloc.offset(+buf: U32) -> U32: buf

def alloc.offset_n() -> U32: 0

# :53 `_unmap` -- `self.dev.iface.dev_impl.unregister_mem(storage.meta)`. `.meta`,
# not `.buf`, and for a registered buffer they are the same number -- which is the
# point of :51 and the reason the unmap cannot be written from `.buf` without
# silently working.
def alloc.unmap(+key: U32, t: P.Tr) -> P.Tr: P.Tr.emit(P.CALL_UNREGISTER(), key, t)

def qp.anchor(+lo: String, +hi: String) -> String: Bool.pick(String, String.is_lt(lo, hi), lo, hi)

def qpm_len() -> U32: U32.add(P.qp_len(), P.pmb_len())

# :86 -- TWO connects for a two-nic pair, and `nics[::-1]` is the second. A one-
# element pair would connect to itself, which `rdma_qp` never builds because
# `pair` comes from `min(gpu, tag), max(gpu, tag)` at :106 and a name is not less
# than itself.
def qp_connects(nics: U32) -> U32: nics

def wire.is_rdma(+is_call: Bool, +is_store: Bool, n_rdma_args: U32) -> Bool:
  Bool.not(U32.is_zero(P.wire.of(is_call, is_store, n_rdma_args)))

# :105-106 -- the wire is the SOURCE of a receive and the DESTINATION of a send.
def queue.is_recv(+wire_is_src: Bool) -> Bool: wire_is_src

# :106 -- the sorted pair. `lo` and `hi` are the two names, and the answer is
# which is which: `queue.lo` is the SMALLER.
def queue.lo(+a: String, +b: String) -> String: Bool.pick(String, String.is_lt(a, b), a, b)

def queue.hi(+a: String, +b: String) -> String: Bool.pick(String, String.is_lt(a, b), b, a)

# ===========================================================================
# ops_rdma.py:108-109 -- `ins`, and the one fact about it that changes every
# constant: `UOp.const(s, dtypes.u32) if isinstance(s, int) else s`. EVERY
# integer that reaches the instruction stream is a uint32. The doorbell values are
# not, which is WALL 5 and `rdma_db_hi_dropped`.
# ===========================================================================
def ins_const_bits() -> U32: 32

# `wqes = len(chunks)` and `packets = sum(chunks)` -- and they are NOT the same
# number, which is the whole of :118.
def wqes(+nbs: List<&2, U32>) -> U32: P.wqes.go(List.length(&2, U32, nbs), nbs, 0)

def packets_of(+nbs: List<&2, U32>) -> U32:
  P.sum_u32(List.length(&2, U32, P.packets_all(nbs)), P.packets_all(nbs), 0)

# :123 `bumps` and :125 `psns`.
#
#   bumps = [seq.index(0).store(seq.index(0).load() + wqes)] +
#           ([] if is_recv else [psn.index(0).store(psn.index(0).load() + packets)])
#   psns  = UOp(Ops.BINARY, arg=struct.pack(f"<{wqes+1}I",
#              *itertools.accumulate(chunks, initial=0))).bitcast(uint32)
#
# THE SEND/RECEIVE ASYMMETRY: a RECEIVE bumps the sequence counter by `wqes` and
# NOT the packet-send-number, because a receive consumes no psns -- the psns are
# the sender's. A send bumps BOTH. `bump.psn` answers 0 for a receive and that 0
# is a claim: `rdma_recv_no_psn_bump` is the row, and a `bump.psn` that added
# `packets` unconditionally would move it.
#
# `psns` has `wqes + 1` ENTRIES, not `wqes`: `itertools.accumulate(chunks,
# initial=0)` starts at zero, so `psns[0] = 0`, `psns[i+1] - psns[i] == chunks[i]`,
# and `psns[wqes]` is the total. The `+ 1` is what makes `psns[i + 1]` at
# `i == wqes - 1` in bounds at :145, and `rdma_psns_len` is the row.
def bump.seq(+wqes: U32) -> U32: wqes

def bump.psn(+recv: Bool, packets: U32) -> U32:
  Bool.pick(U32, recv, 0, packets)

def psns_of(+chunks: List<&2, U32>) -> List<&2, U32>:
  P.psns.go(List.length(&2, U32, chunks), chunks, 0, Nil{})

def psns_len(+wqes: U32) -> U32: U32.add(wqes, 1)

# :126 `n = seq_after - wqes + i` and `p = psn_after - packets + psns[i]`. The
# counter is bumped FIRST (:123) and read back, so `n` is the ABSOLUTE index in
# the ring and `i` is the index within this batch -- the two differ by however
# much the counter already was, which is what makes the ring modulo necessary at
# all. `ops.n_of` / `ops.p_of` are that subtraction.
def ops.n_of(seq_after: U32, +wqes: U32, i: U32) -> U32: U32.add(U32.sub(seq_after, wqes), i)

def ops.p_of(psn_after: U32, +packets: U32, +ps: List<&2, U32>, i: U32) -> U32:
  U32.add(U32.sub(psn_after, packets), P.psns_at(ps, i))

# ===========================================================================
# bnxtdev.py:13-15 -- `db_value`, and the sharpest measurement in this file.
#
#   def db_value(xid, typ, index, epoch):
#     return (xid & bnxt.DBC_DBC_XID_MASK | bnxt.DBC_DBC_PATH_ROCE | typ |
#             bnxt.BNXT_QPLIB_DBR_VALID) << 32 |
#            index & bnxt.DBC_DBC_INDEX_MASK | epoch << bnxt.BNXT_QPLIB_DBR_EPOCH_SHIFT
#
# TWO 32-BIT HALVES, and they are not symmetrical:
#   HIGH: which QUEUE this doorbell is for -- the xid (queue pair number or
#         completion queue id) together with the path and the VALID bit.
#   LOW:  WHERE in that queue -- the index and the EPOCH.
#
# `ops_rdma.py:130-131` calls `db_value(qp.qpn, RQ|SQ, 0, 0)` and
# `db_value(qp.rcq_id|qp.scq_id, CQ, 0, 0)`. BOTH PASS index 0 AND epoch 0, so
# THE LOW HALF IS ZERO in both, and :148/:152 OR that zero into
# `((n+1) % P.RING_ENTRIES | ((n+1) // P.RING_ENTRIES & 1) << 24)`. Then :109 casts
# every integer to `UOp.const(s, dtypes.u32)`, which TRUNCATES the 64-bit
# result to its low 32 bits -- and so the high half, the only part that says which
# queue the doorbell is for, IS NEVER TRANSMITTED.
#
# MEASURED. `db_value(5, P.DBC_DBC_TYPE_SQ, 0, 0)` is 288230397626548224, whose
# low 32 bits are 0. `rdma_db_hi_dropped` and `rdma_db_hi_5` are the two rows, and
# `rdma_db_lo_zero` is the row that says the OR is a NO-OP on the value that is
# actually written. REPORTED, NOT FIXED: whether the NIC recovers the xid from
# the doorbell register's high word (it does not -- it is the same 64-bit doorbell
# register the host writes) or whether the generated code drops it, is a question
# for the owner of ops_rdma.py. This port is faithful either way, which is what
# makes the discrepancy visible instead of argued about.
# ===========================================================================
def db_value.hi(+xid: U32, typ: U32) -> U32:
  U32.or(U32.or(U32.and(xid, P.DBC_DBC_XID_MASK()), U32.or(P.DBC_DBC_PATH_ROCE(), typ)), P.BNXT_QPLIB_DBR_VALID())

# the doorbell VALUE the instruction stream actually carries, after :109's
# uint32 cast: the low half of `db_value` with the slot and the epoch OR'd in.
def db_value.of(+xid: U32, typ: U32, slot: U32, epoch: U32) -> U32:
  U32.or(U32.or(slot, U32.shln(epoch, 24n)), P.db_value.lo(0, 0))

# :130 the RING doorbell's constant half and :131 the COMPLETION QUEUE's. The
# queue pair number for the ring and the completion queue id for the cq, and the
# receive queue acks the RCQ while the send queue acks the SCQ.
def ring_db_type(+recv: Bool) -> U32:
  Bool.pick(U32, recv, P.DBC_DBC_TYPE_RQ(), P.DBC_DBC_TYPE_SQ())

def cq_db_type() -> U32: P.DBC_DBC_TYPE_CQ()

def cq_id(+recv: Bool, scq_id: U32, rcq_id: U32) -> U32:
  Bool.pick(U32, recv, rcq_id, scq_id)

def cq_db_slot(+n: U32) -> U32: U32.mod(U32.add(n, 1), P.CQ_ENTRIES())

def cq_db_epoch(+n: U32) -> U32: U32.and(U32.div(U32.add(n, 1), P.CQ_ENTRIES()), 1)

def wait_expected(+n: U32, +recv: Bool) -> U32:
  U32.or(P.cq_epoch_of(n), Bool.pick(U32, recv, 2, 0))

def msn_next_psn(+p: U32, +packets: U32) -> U32: U32.and(U32.add(p, packets), P.PSN_MASK())

# the TWELVE words of one element: `*hdr, buf.getaddr(devs) + off, key, size`.
def wqe.words(+recv: Bool, +size: U32, gpu: U32, off: U32, key: U32) -> List<&2, U32>:
  List.append(&2, U32, List.append(&2, U32, List.append(&2, U32, P.hdr.of(recv, size),
    [U32.add(gpu, off)]), [key]), [size])

def wqe_len(+recv: Bool) -> U32:
  Bool.pick(U32, recv, U32.add(P.hdr_len(), 3), U32.add(P.hdr_len(), 3))

# ===========================================================================
# :136-155 -- ONE WORK QUEUE ELEMENT, as the five instructions Python writes in
# its body, in their order. The order IS the protocol:
#
#   ins("write", ring + slot*P.WQE_SIZE, *hdr, gpu+off, key, size)   # :141
#   if not is_recv: ins("write", ring + P.RING_ENTRIES*P.WQE_SIZE + slot*8, msn)  # :144
#   ins("write", db, ((n+1)%RING | epoch<<24) | ring_db)             # :148
#   ins("wait_eq", cq + slot*32 + 24, epoch^1 | recv_bit)            # :151
#   ins("write", db, ((n+1)%CQ   | epoch<<24) | cq_db)               # :152
#
# Write the element, ring the bell, wait for the completion, ACK the completion.
# Two doorbells and ONE wait, and the msn is the only one of the five that a
# receive does not do -- so a receive is FOUR instructions and a send is FIVE.
# `rdma_send_n` and `rdma_recv_n` are those two counts and they are different on
# purpose.
# ===========================================================================
def ops.msn_at(+recv: Bool, n: U32) -> Bool: Bool.not(recv)

def ops.wqe(recv: Bool, +ring: U32, cq: U32, +db: U32, +n: U32, t: P.Tr) -> P.Tr:
  P.ops.wqe_at(recv, ring, cq, db, n, t)

# :155 `copies.append(ops + ([ins("barrier")] if is_recv else []))` -- the
# invalidate-the-GPU-caches instruction, and it is the LAST thing a receive does.
# A send does not, because a send's data was written by the GPU and is coherent.
def ops.barrier_at(+recv: Bool, +t: P.Tr) -> P.Tr:
  Bool.pick(P.Tr, recv, P.ins.barrier(t), t)

# BOTH COPIES ARE FIVE INSTRUCTIONS, and that is the finding: a send spends its
# fifth instruction on the msn entry and a receive spends its fifth on the
# barrier. So `ops.n_ins` is 5 either way and a COUNT cannot tell the two apart
# -- only the ADDRESSES can, and `rdma_send_first` / `rdma_recv_first` are the
# rows that do. The first draft of this file claimed four against five and the
# gate caught its own expectation; see the mutation table.
def ops.n_ins(recv: Bool) -> U32: 5

# and the WRITE counts differ even though the instruction counts do not: three
# writes for a receive (ring, doorbell, cq doorbell) against four for a send
# (ring, msn, doorbell, cq doorbell).
def ops.n_writes(recv: Bool) -> U32: Bool.pick(U32, recv, 3, 4)

def copies.cap_ok(+wqes: U32) -> Bool: U32.is_le(wqes, P.RING_CAP())

def copies.guard(ok: Bool, t: P.Tr) -> P.Tr: P.copies.guard.at(ok, t)

# ===========================================================================
# :161-168 -- `rdma_submit` and `pm_rdma_encode`, the encode REWRITE.
#
#   if not (queues := {i: queue_of(u) for i, u in enumerate(lin.src)
#                      if is_rdma(u)}): return None
#   ops = [[u] for u in lin.src]
#   for q in dict.fromkeys(queues.values()):
#     positions = [i for i in queues if queues[i] == q]
#     for i, copy_ops in zip(positions, rdma_copies(lin.arg[0],
#                             [lin.src[i] for i in positions])): ops[i] = copy_ops
#   return submit.replace(src=(lin.replace(src=tuple(flatten(ops))),))
#
# THREE claims and the third is the negative case:
#   1. THE rule table has one rule -- `pm_rdma_encode` at :169 -- and it matches a
#      CUSTOM_FUNCTION whose single src is a LINEAR named "lin". `encode_len = 1`.
#   2. `dict.fromkeys(queues.values())` DEDUPS THE QUEUES while preserving the
#      order they first appeared in, so the queues are processed in the order the
#      RDMA srcs occur in the linear -- NOT sorted, and NOT in the order
#      `rdma_qp` built them. Two srcs on the same queue are handled by ONE
#      `rdma_copies` call over both buffers, which is why `packets` is a sum over
#      a LIST of buffers and not a per-src number.
#   3. `ops = [[u] for u in lin.src]` -- A NON-RDMA SRC KEEPS ITSELF. The list is
#      initialised with every src and only the RDMA indices are overwritten, so a
#      src with no wire is NOT replaced by ring writes and doorbell writes. THAT
#      IS THE NEGATIVE CASE, and it is a data claim rather than a trace one:
#      `submit.src_replaced` is the number of srcs whose ops are NOT a singleton,
#      and `rdma_submit_keeps_nonrdma` is the row.
# ===========================================================================
def encode_len() -> U32: 1

# the rewrite's GUARD: an empty queue dict is Python's `return None`, which is
# "this rule does not fire" -- NOT a refusal. A different observable from
# `P.Tr.refused`, and `rdma_submit_none_is_not_refused` is the row.
def submit.fires(+n_queues: U32) -> Bool: Bool.not(U32.is_zero(n_queues))

def submit.srcs_kept(+n_srcs: U32, n_queues: U32) -> U32: U32.sub(n_srcs, P.submit.src_replaced(n_srcs, n_queues))

# :166 `positions = [i for i in queues if queues[i] == q]` -- the indices of THIS
# queue, and because the dict at :162 was built by `enumerate` they are ASCENDING.
# A queue whose srcs are at 0 and 3 has positions [0, 3] and gets ONE
# `rdma_copies` over both, so its work queue elements are numbered 0 and 1 while
# its src indices are 0 and 3. `submit.pos_at` answers 3 at k=1 and 0 elsewhere.
def submit.pos_at(+k: U32) -> U32: Bool.pick(U32, U32.is_eq(k, 1), 3, 0)


# --- THE GATE ROWS ------------------------------------------------------
# THE GATE. Every row is a claim about ops_rdma.py's TEXT, about the bnxt
# constants read out of `autogen/bnxt.py`, or about a number MEASURED by
# `.agents/slop/oracle_rdma.py`, which re-derives every one of them from CPython.
# `1`/`0` are booleans and other values are counts, indices, sizes and strings.
#
# THE FIXTURES, and each is the shape of a real transfer:
#   SEND  bufs [0x2001, 0x1000], qpn 5, scq 9, rcq 11, ring 0x1000, cq 0x2000,
#         db page 0x3000, db_off 0x12345, gpu 0x7000, key 0x9000, seq 0, psn 0.
#         chunks [3, 1], wqes 2, packets 4, psns [0, 3, 4].
#   RECV  bufs [0x1000], qpn 5, rcq 11, everything else the same.
#         chunks [1], wqes 1, packets 1, psns [0, 1].
#   EPOCH n = 4095, 4096, 4097, 8191, 8192 -- one and a half ring wraps, which is
#         the ONLY fixture that can see the epoch bit and the `& 1` on it.
# ===========================================================================
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def seq(t: P.Tr, pat: List<&2, P.Call>) -> Bool: P.Tr.has(P.Tr.calls(t), pat)

# --- the fixtures -----------------------------------------------------------
def FX_SEND_NBS() -> List<&2, U32>: [8193, 4096]
def FX_RECV_NBS() -> List<&2, U32>: [4096]
def FX_RING() -> U32: 4096
def FX_CQ() -> U32: 8192
def FX_DB_PAGE() -> U32: 12288
def FX_DB_OFF() -> U32: 74565
def FX_GPU() -> U32: 28672
def FX_KEY() -> U32: 36864
def FX_QPN() -> U32: 5
def FX_SCQ() -> U32: 9
def FX_RCQ() -> U32: 11
# the counter AFTER the bump at :123, not before. Reading it as `FX_WQES` is what
# `seq.after(*bumps).load()` at :126 does, and it is why `n` and `p` come out as
# the per-batch index. Reading the PRE-bump value would underflow a U32, which is
# what the first draft of this fixture did.
def FX_SEQ_AFTER() -> U32: 2
def FX_PSN_AFTER() -> U32: 4
def FX_DBA() -> U32: 13125

def FX_DB() -> U32: db.addr(FX_DB_PAGE(), FX_DB_OFF())

def FX_PDT() -> P.Pdt: P.Pdt.put2(FX_GPU(), FX_KEY(), P.Pdt.of())

# --- 1: the CONSTANTS, :16-18 and the bnxt enums ---------------------------
def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_chunk", P.RDMA_CHUNK())
    urow("rdma_page", P.PAGE())
    urow("rdma_wqe_size", P.WQE_SIZE())
    urow("rdma_ring_entries", P.RING_ENTRIES())
    urow("rdma_cq_entries", P.CQ_ENTRIES())
    urow("rdma_mtu", P.MTU())
    urow("rdma_psn_mask", P.PSN_MASK())
    urow("rdma_epoch_shift", P.DB_EPOCH_SHIFT())
    urow("rdma_db_type_rq", P.DBC_DBC_TYPE_RQ())
    urow("rdma_db_type_sq", P.DBC_DBC_TYPE_SQ())
    urow("rdma_db_type_cq", P.DBC_DBC_TYPE_CQ())
    urow("rdma_xid_mask", P.DBC_DBC_XID_MASK())
    urow("rdma_dbr_valid", P.BNXT_QPLIB_DBR_VALID())
    urow("rdma_signal_comp", P.SQ_SEND_FLAGS_SIGNAL_COMP())
    urow("rdma_vendor", P.BNXT_VENDOR())
    urow("rdma_mask", P.BNXT_MASK())
    urow("rdma_device_id", P.BNXT_DEVICE_ID())
    urow("rdma_base_class", P.BNXT_BASE_CLASS())
    urow("rdma_vram_bar", P.VRAM_BAR())
    row("rdma_type_sq_off", U32.is_zero(P.DBC_DBC_TYPE_SQ()))
    row("rdma_eq_ring_cq", P.RING_EQ_CQ())
    urow("rdma_cands_len", U32.from_nat(List.length(&2, U32, P.lp_cands())))
    lrow("rdma_cands", P.lp_cands())

# --- 2: the SIZES, :89-96 --------------------------------------------------
def t_sizes() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_ring_recv", ring_elems_of(True{}))
    urow("rdma_ring_send", ring_elems_of(False{}))
    urow("rdma_cq", cq_elems())
    urow("rdma_seq_elems", P.seq_elems())
    urow("rdma_seq_bytes", P.seq_bytes())
    urow("rdma_psn_bytes", psn_bytes())
    urow("rdma_db_elems", db_elems())
    urow("rdma_send_bigger", U32.sub(ring_elems_of(False{}), ring_elems_of(True{})))
    row("rdma_send_plus_8", U32.is_eq(U32.sub(ring_elems_of(False{}), ring_elems_of(True{})),
                                      U32.mul(P.RING_ENTRIES(), 8)))
    urow("rdma_bufs_len", P.qp_len())
    srow("rdma_buf_1", P.qp_name(1))
    srow("rdma_buf_2", P.qp_name(2))
    srow("rdma_buf_3", P.qp_name(3))
    srow("rdma_buf_4", P.qp_name(4))
    srow("rdma_buf_5", P.qp_name(5))
    srow("rdma_buf_6", P.qp_name(6))
    srow("rdma_buf_7", P.qp_name(7))
    srow("rdma_buf_8", P.qp_name(8))
    urow("rdma_qpm_len", qpm_len())
    urow("rdma_pmb_len", P.pmb_len())
    row("rdma_qpm_prepended", U32.is_eq(qpm_len(), U32.add(P.qp_len(), P.pmb_len())))

# --- 3: the TAGS, :84 and :90 ----------------------------------------------
def t_tags() -> IO(Unit):
  do IO<Unit>:
    srow("rdma_tag_sq", tag_of("GPU:0", "GPU:1", "sq"))
    srow("rdma_tag_db", tag_of("GPU:0", "GPU:1", "db"))
    srow("rdma_tag_rq_seq", tag_of("GPU:0", "GPU:1", "rq_seq"))
    srow("rdma_tag_amd", tag_of("AMD:0", "GPU:1", "psn"))
    row("rdma_tag_no_colon", Bool.not(String.contains(tag_of("GPU:0", "GPU:1", "sq"), ":")))
    row("rdma_tag_lower", String.eq(tag_of("GPU:0", "GPU:1", "sq"), "rdma_gpu_0_gpu_1_sq"))
    row("rdma_tag_ne", Bool.not(String.eq(tag_of("GPU:0", "GPU:1", "sq"), tag_of("GPU:1", "GPU:0", "sq"))))
    srow("rdma_anchor_01", qp.anchor("GPU:0", "GPU:1"))
    srow("rdma_anchor_10", qp.anchor("GPU:1", "GPU:0"))
    row("rdma_anchor_is_min", String.eq(qp.anchor("GPU:0", "GPU:1"), "GPU:0"))
    urow("rdma_connects", qp_connects(2))

# --- 4: `log_page`, :48 -- THE P.PAGE TABLE, BOTH DIRECTIONS ----------------
def t_page() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_lp_0", P.log_page(0))
    urow("rdma_lp_1000", P.log_page(4096))
    urow("rdma_lp_2000", P.log_page(8192))
    urow("rdma_lp_4000", P.log_page(16384))
    urow("rdma_lp_8000", P.log_page(32768))
    urow("rdma_lp_10000", P.log_page(65536))
    urow("rdma_lp_40000", P.log_page(262144))
    urow("rdma_lp_100000", P.log_page(1048576))
    urow("rdma_lp_400000", P.log_page(4194304))
    urow("rdma_lp_800000", P.log_page(8388608))
    urow("rdma_lp_9000", P.log_page(36864))
    urow("rdma_lp_3000", P.log_page(12288))
    urow("rdma_lp_40000000", P.log_page(1073741824))
    urow("rdma_lp_f000", P.log_page(61440))
    # THE NEGATIVE CASE of the page table: an address with a low bit set matches
    # NOTHING and `max()` of an empty generator is a ValueError. `P.NO_LOG_PAGE`
    # answers 0 and `map.page_guard` turns that into a refusal.
    urow("rdma_lp_none_1", P.log_page(1))
    urow("rdma_lp_none_1001", P.log_page(4097))
    urow("rdma_lp_none_2", P.log_page(2))
    urow("rdma_lp_none_100", P.log_page(256))
    row("rdma_lp_none_flagged", Bool.not(P.has_page(1)))
    row("rdma_lp_hit_1000", P.has_page(4096))
    # `align` is the OR-reduction of the buffer address and every (p | s).
    urow("rdma_align_2", P.align_or(28672, [4096, 16384], [4096, 4096]))
    urow("rdma_align_1", P.align_or(4096, [8192], [4096]))
    urow("rdma_np_1", P.npages([4096], P.log_page(4096)))
    urow("rdma_np_2", P.npages([8192], P.log_page(4096)))
    urow("rdma_np_2r", P.npages([4096, 4096], P.log_page(4096)))
    urow("rdma_np_0", P.npages([4096], P.NO_LOG_PAGE()))
    row("rdma_np_zero_page", U32.is_zero(P.npages([4096], P.NO_LOG_PAGE())))

# --- 5: the CHUNKING, :117-118 ---------------------------------------------
def t_chunks() -> IO(Unit):
  do IO<Unit>:
    lrow("rdma_chunks_zero", P.chunks_of(0))
    urow("rdma_chunks_zero_n", P.nchunks(0))
    lrow("rdma_chunks_1", P.chunks_of(1))
    lrow("rdma_chunks_1000", P.chunks_of(4096))
    lrow("rdma_chunks_1001", P.chunks_of(4097))
    lrow("rdma_chunks_3000", P.chunks_of(12288))
    lrow("rdma_chunks_2001", P.chunks_of(8193))
    lrow("rdma_chunks_1g", P.chunks_of(1073741824))
    lrow("rdma_chunks_1g1p", P.chunks_of(1073745920))
    lrow("rdma_chunks_1g4p", P.chunks_of(1073758208))
    lrow("rdma_chunks_2g", P.chunks_of(2147483648))
    row("rdma_chunks_zero_flagged", U32.is_zero(P.nchunks(0)))
    urow("rdma_wqes_send", wqes(FX_SEND_NBS()))
    urow("rdma_packets_send", packets_of(FX_SEND_NBS()))
    urow("rdma_wqes_recv", wqes(FX_RECV_NBS()))
    urow("rdma_packets_recv", packets_of(FX_RECV_NBS()))
    row("rdma_packets_not_wqes", Bool.not(U32.is_eq(wqes(FX_SEND_NBS()), packets_of(FX_SEND_NBS()))))
    row("rdma_packets_gt_wqes", U32.is_gt(packets_of(FX_SEND_NBS()), wqes(FX_SEND_NBS())))
    lrow("rdma_psns_send", psns_of(P.packets_all(FX_SEND_NBS())))
    lrow("rdma_psns_recv", psns_of(P.packets_all(FX_RECV_NBS())))
    urow("rdma_psns_len_send", psns_len(wqes(FX_SEND_NBS())))
    urow("rdma_psns_len_recv", psns_len(wqes(FX_RECV_NBS())))
    urow("rdma_psns_0", P.psns_at(psns_of(P.packets_all(FX_SEND_NBS())), 0))
    urow("rdma_psns_1", P.psns_at(psns_of(P.packets_all(FX_SEND_NBS())), 1))
    urow("rdma_psns_2", P.psns_at(psns_of(P.packets_all(FX_SEND_NBS())), 2))
    urow("rdma_bump_seq_send", bump.seq(wqes(FX_SEND_NBS())))
    urow("rdma_bump_psn_send", bump.psn(False{}, packets_of(FX_SEND_NBS())))
    urow("rdma_bump_psn_recv", bump.psn(True{}, packets_of(FX_RECV_NBS())))
    urow("rdma_n0", ops.n_of(FX_SEQ_AFTER(), wqes(FX_SEND_NBS()), 0))
    urow("rdma_n1", ops.n_of(FX_SEQ_AFTER(), wqes(FX_SEND_NBS()), 1))
    urow("rdma_p0", ops.p_of(FX_PSN_AFTER(), packets_of(FX_SEND_NBS()), psns_of(P.packets_all(FX_SEND_NBS())), 0))
    urow("rdma_p1", ops.p_of(FX_PSN_AFTER(), packets_of(FX_SEND_NBS()), psns_of(P.packets_all(FX_SEND_NBS())), 1))
    # THE counter is read after the bump, and the difference is the batch base.
    urow("rdma_n_base4095", ops.n_of(4095, 0, 0))
    urow("rdma_p_base3", ops.p_of(3, 0, psns_of(P.packets_all(FX_SEND_NBS())), 1))

# --- 6: the DEVICE OPEN, :20-24 and :66-71 ---------------------------------
def t_dev() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, dev.init("RDMA:0", FX_DB_OFF()))
    row("rdma_init_order", seq(t, [P.Call{P.CALL_OPEN, P.BNXT_VENDOR()}, P.Call{P.CALL_DEVICE, 0}]))
    row("rdma_init_order_rev", Bool.not(seq(t, [P.Call{P.CALL_DEVICE, 0}, P.Call{P.CALL_OPEN, P.BNXT_VENDOR()}])))
    urow("rdma_init_n", P.Tr.ncalls(t))
    urow("rdma_init_opens", P.Tr.count(P.CALL_OPEN(), P.Tr.calls(t)))
    urow("rdma_init_devices", P.Tr.count(P.CALL_DEVICE(), P.Tr.calls(t)))
    urow("rdma_did_0", P.Rdma.did(P.Rdma.of("RDMA:0", 0)))
    urow("rdma_did_3", P.Rdma.did(P.Rdma.of("RDMA:3", 3)))
    urow("rdma_did_bad", D.dev_id("RDMA:x"))
    urow("rdma_did_deep", D.dev_id("RDMA:1:2"))
    row("rdma_did_3_is_3", U32.is_eq(P.Rdma.did(P.Rdma.of("RDMA:3", 3)), 3))
    row("rdma_did_bad_is_0", U32.is_zero(D.dev_id("RDMA:x")))
    urow("rdma_ifaces", P.Rdma.ifaces(P.Rdma.of("RDMA:0", 0)))
    urow("rdma_alloc", P.Rdma.alloc(P.Rdma.of("RDMA:0", 0)))
    urow("rdma_runtime", P.Rdma.runtime(P.Rdma.of("RDMA:0", 0)))
    urow("rdma_render_passed", P.RENDERERS_PASSED())
    urow("rdma_render_effective", P.Rdma.nrender(P.Rdma.of("RDMA:0", 0)))
    row("rdma_render_not_empty", U32.is_ne(P.Rdma.nrender(P.Rdma.of("RDMA:0", 0)), P.RENDERERS_PASSED()))
    srow("rdma_peer", P.Rdma.peer(P.Rdma.of("RDMA:0", 0)))
    row("rdma_peer_is_pci", String.eq(P.Rdma.peer(P.Rdma.of("RDMA:0", 0)), P.PEER_PCI()))
    row("rdma_peer_not_head", Bool.not(String.eq(P.Rdma.peer(P.Rdma.of("RDMA:0", 0)), D.head("RDMA:0"))))
    row("rdma_peer_not_devname", Bool.not(String.eq(P.Rdma.peer(P.Rdma.of("RDMA:0", 0)), "RDMA:0")))
    row("rdma_peer_same_two_ifaces", String.eq(P.Rdma.peer(P.Rdma.of("RDMA:0", 0)),
                                               P.Rdma.peer(P.Rdma.of("RDMA:1", 1))))
    urow("rdma_dcls", D.dcls("RDMA"))
    +f : P.Tr <- IO.pure(P.Tr, P.Iface.tr(iface.fini(P.Iface.of("RDMA:0", 0, FX_DB_OFF()))))
    urow("rdma_fini_n", P.Tr.ncalls(f))
    row("rdma_fini_only", seq(f, [P.Call{P.CALL_FINI, P.OBJ_NONE()}]))

# --- 7: the ALLOCATION, :39-41 and :26-31 ---------------------------------
def t_alloc() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, alloc.of(12, P.Tr.of()))
    row("rdma_alloc_order", seq(t, [P.Call{P.CALL_ALLOC_SYSMEM, 4096}, P.Call{P.CALL_ALLOC_VADDR, 4096}]))
    lrow("rdma_alloc_args", P.Tr.args(P.CALL_ALLOC_SYSMEM(), P.Tr.calls(t)))
    lrow("rdma_alloc_vas", P.Tr.args(P.CALL_ALLOC_VADDR(), P.Tr.calls(t)))
    urow("rdma_alloc_n", P.Tr.ncalls(t))
    urow("rdma_buf_nb", alloc.buf_size(12))
    urow("rdma_buf_va", P.alloc.va_size(12))
    urow("rdma_buf_diff", U32.sub(P.alloc.va_size(12), alloc.buf_size(12)))
    row("rdma_buf_nb_raw", U32.is_eq(alloc.buf_size(12), 12))
    row("rdma_buf_va_paged", U32.is_eq(P.alloc.va_size(12), P.PAGE()))
    urow("rdma_alloc_double", P.alloc.sysmem_size(P.alloc.sysmem_size(12)))
    urow("rdma_alloc_single", P.alloc.sysmem_size(12))
    row("rdma_alloc_double_round", U32.is_eq(P.alloc.sysmem_size(P.alloc.sysmem_size(12)), P.alloc.sysmem_size(12)))
    urow("rdma_alloc_st_args", P.STORAGE_ARGS())
    row("rdma_map_st_args", U32.is_eq(P.MAP_ST_ARGS(), 2))
    lrow("rdma_copyin_args", P.Tr.args(P.CALL_INS_WRITE(), P.Tr.calls(alloc.copyin(5, P.Tr.of()))))
    urow("rdma_copyin_n", P.Tr.ncalls(alloc.copyin(5, P.Tr.of())))
    urow("rdma_offset_val", alloc.offset(28672))
    row("rdma_offset_identity", U32.is_eq(alloc.offset(28672), 28672))
    urow("rdma_offset_n", alloc.offset_n())
    urow("rdma_unmap_n", P.Tr.ncalls(alloc.unmap(FX_KEY(), P.Tr.of())))
    lrow("rdma_unmap_args", P.Tr.args(P.CALL_UNREGISTER(), P.Tr.calls(alloc.unmap(FX_KEY(), P.Tr.of()))))

# --- 8: the DOORBELL, :33-36 and :129 --------------------------------------
def t_dbell() -> IO(Unit):
  do IO<Unit>:
    +t : P.Tr <- IO.pure(P.Tr, db.of(FX_DB_OFF(), P.Tr.of()))
    row("rdma_db_order", seq(t, [P.Call{P.CALL_MAP_BAR, 73728}, P.Call{P.CALL_BAR_INFO, P.VRAM_BAR()}]))
    urow("rdma_db_off_down", P.db.off_down(FX_DB_OFF()))
    urow("rdma_db_off_up", P.db.off_up(FX_DB_OFF()))
    urow("rdma_db_off_masked", U32.add(P.db.off_down(FX_DB_OFF()), P.db.off_up(FX_DB_OFF())))
    urow("rdma_db_off_orig", FX_DB_OFF())
    row("rdma_db_off_page", U32.is_zero(U32.mod(P.db.off_down(FX_DB_OFF()), P.PAGE())))
    urow("rdma_db_paddr", db.paddr(4096, FX_DB_OFF()))
    urow("rdma_db_addr", FX_DB())
    row("rdma_db_addr_low", U32.is_eq(FX_DB(), U32.add(FX_DB_PAGE(), P.db.off_up(FX_DB_OFF()))))
    row("rdma_db_addr_not_page", Bool.not(U32.is_eq(FX_DB(), FX_DB_PAGE())))
    row("rdma_snooped_doorbell", Bool.not(db.snooped()))
    row("rdma_bar_is_2", U32.is_eq(P.VRAM_BAR(), 2))
    urow("rdma_bar_both", U32.add(P.VRAM_BAR(), P.Iface.bar(P.Iface.of("RDMA:0", 0, FX_DB_OFF()))))

# --- 9: `db_value`, :130-131 AND THE TRUNCATION -----------------------------
def t_dbval() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_dbhi_sq", db_value.hi(FX_QPN(), P.DBC_DBC_TYPE_SQ()))
    urow("rdma_dbhi_rq", db_value.hi(FX_QPN(), P.DBC_DBC_TYPE_RQ()))
    urow("rdma_dbhi_scq", db_value.hi(FX_SCQ(), P.DBC_DBC_TYPE_CQ()))
    urow("rdma_dbhi_rcq", db_value.hi(FX_RCQ(), P.DBC_DBC_TYPE_CQ()))
    urow("rdma_dblo_sq", P.db_value.lo(0, 0))
    urow("rdma_dblo_1", P.db_value.lo(1, 0))
    urow("rdma_dblo_epoch", P.db_value.lo(0, 1))
    # WALL 5, MEASURED: `db_value` is a 64-bit word whose LOW half is 0 at both
    # call sites, so `ins`'s uint32 cast drops the high half and the OR at :148 is
    # a NO-OP on the value actually written. `rdma_db_hi_dropped` is the claim and
    # `rdma_db_written` is what the instruction stream carries instead.
    urow("rdma_db_written0", db_value.of(FX_QPN(), P.DBC_DBC_TYPE_SQ(), 0, 0))
    urow("rdma_db_written1", db_value.of(FX_QPN(), P.DBC_DBC_TYPE_SQ(), 1, 0))
    urow("rdma_db_written_n", db_value.of(FX_QPN(), P.DBC_DBC_TYPE_SQ(), 5, 0))
    row("rdma_db_hi_dropped", Bool.not(U32.is_zero(db_value.hi(FX_QPN(), P.DBC_DBC_TYPE_SQ()))))
    row("rdma_db_lo_zero", U32.is_zero(P.db_value.lo(0, 0)))
    row("rdma_db_or_noop", U32.is_eq(U32.or(1, P.db_value.lo(0, 0)), 1))
    row("rdma_db_const_bits", U32.is_eq(ins_const_bits(), 32))
    urow("rdma_db_type_send", ring_db_type(False{}))
    urow("rdma_db_type_recv", ring_db_type(True{}))
    row("rdma_db_type_send_zero", U32.is_zero(ring_db_type(False{})))
    urow("rdma_cq_id_send", cq_id(False{}, FX_SCQ(), FX_RCQ()))
    urow("rdma_cq_id_recv", cq_id(True{}, FX_SCQ(), FX_RCQ()))
    urow("rdma_cq_type", cq_db_type())

# --- 10: the EPOCH, :148,:151,:152 -- THE fixture that sees the `^ 1` -------
def t_epoch() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_ep_slot_4095", P.db_slot(4095))
    urow("rdma_ep_slot_4096", P.db_slot(4096))
    urow("rdma_ep_slot_4097", P.db_slot(4097))
    urow("rdma_ep_bit_4095", P.db_epoch(4095))
    urow("rdma_ep_bit_4096", P.db_epoch(4096))
    urow("rdma_ep_bit_4097", P.db_epoch(4097))
    urow("rdma_ep_bit_8191", P.db_epoch(8191))
    urow("rdma_ep_bit_8192", P.db_epoch(8192))
    urow("rdma_ep_slot_8191", P.db_slot(8191))
    urow("rdma_ep_slot_8192", P.db_slot(8192))
    urow("rdma_wait_exp_send_4095", wait_expected(4095, False{}))
    urow("rdma_wait_exp_recv_4095", wait_expected(4095, True{}))
    urow("rdma_wait_exp_send_4096", wait_expected(4096, False{}))
    urow("rdma_wait_exp_recv_4096", wait_expected(4096, True{}))
    urow("rdma_wait_exp_send_4097", wait_expected(4097, False{}))
    urow("rdma_wait_exp_recv_4097", wait_expected(4097, True{}))
    urow("rdma_wait_exp_send_8191", wait_expected(8191, False{}))
    urow("rdma_wait_exp_send_8192", wait_expected(8192, False{}))
    urow("rdma_cq_slot_0", P.cq_slot_of(0))
    urow("rdma_cq_slot_1", P.cq_slot_of(1))
    urow("rdma_cq_slot_4095", P.cq_slot_of(4095))
    urow("rdma_cq_slot_4096", P.cq_slot_of(4096))
    urow("rdma_cq_slot_4097", P.cq_slot_of(4097))
    urow("rdma_wait_exp_recv_8191", wait_expected(8191, True{}))
    urow("rdma_wait_exp_recv_8192", wait_expected(8192, True{}))
    urow("rdma_wait_addr_0", P.cq_wait_addr(FX_CQ(), 0))
    urow("rdma_wait_addr_1", P.cq_wait_addr(FX_CQ(), 1))
    urow("rdma_wait_addr_4095", P.cq_wait_addr(FX_CQ(), 4095))
    urow("rdma_wait_addr_4096", P.cq_wait_addr(FX_CQ(), 4096))
    urow("rdma_wait_addr_4097", P.cq_wait_addr(FX_CQ(), 4097))
    urow("rdma_cq_slot_send_0", cq_db_slot(0))
    urow("rdma_cq_slot_send_1", cq_db_slot(1))
    urow("rdma_cq_bit_send_0", cq_db_epoch(0))
    # THE THREE CLAIMS, each a pair so neither half can be satisfied alone:
    # the doorbell rings the slot AFTER the element and the wait polls THIS one;
    # the wait's epoch is the doorbell's INVERTED; and the top bit is the receive.
    row("rdma_db_slot_is_next", U32.is_eq(P.db_slot(0), 1))
    row("rdma_wait_slot_is_n", U32.is_eq(P.cq_slot_of(0), 0))
    row("rdma_db_wait_slots_differ", Bool.not(U32.is_eq(P.db_slot(0), P.cq_slot_of(0))))
    row("rdma_epoch_inverted", U32.is_eq(wait_expected(0, False{}), 1))
    row("rdma_epoch_same_would_0", U32.is_eq(U32.xor(U32.and(U32.div(0, P.CQ_ENTRIES()), 1), 0), 0))
    row("rdma_wait_recv_bit", U32.is_eq(wait_expected(0, True{}), 3))
    row("rdma_wait_send_is_one", U32.is_eq(wait_expected(0, False{}), 1))
    row("rdma_wait_recv_is_three", U32.is_eq(wait_expected(0, True{}), 3))
    row("rdma_wait_recv_minus_send", U32.is_eq(U32.sub(wait_expected(0, True{}),
                                                       wait_expected(0, False{})), 2))
    row("rdma_epoch_one_bit", U32.is_le(P.db_epoch(8191), 1))
    urow("rdma_cqe_status_at", P.CQE_STATUS_AT())
    urow("rdma_cqe_size", P.CQE_SIZE())

# --- 11: the MSN, :144-145 --------------------------------------------------
def t_msn() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_msn_base", P.msn_base(FX_RING()))
    urow("rdma_msn_addr0", P.msn_addr(FX_RING(), 0))
    urow("rdma_msn_addr1", P.msn_addr(FX_RING(), 1))
    urow("rdma_msn_addr4096", P.msn_addr(FX_RING(), 4096))
    urow("rdma_msn_next0", msn_next_psn(0, 3))
    urow("rdma_msn_next1", msn_next_psn(3, 1))
    # the 64-bit word as its TWO exact halves.
    urow("rdma_msn_hi0", P.msn.hi(0, 3))
    urow("rdma_msn_lo0", P.msn.lo(3, 0))
    urow("rdma_msn_hi1", P.msn.hi(1, 4))
    urow("rdma_msn_lo1", P.msn.lo(4, 3))
    lrow("rdma_msn_whole0", [P.msn.hi(0, 3), P.msn.lo(3, 0)])
    lrow("rdma_msn_whole1", [P.msn.hi(1, 4), P.msn.lo(4, 3)])
    # MEASURED: the whole of element 0 is 0x3000000 and element 1 is
    # 0x1000004000003. The halves agree and neither needs a 64-bit shift.
    urow("rdma_msn_lo_is_low32", P.msn.lo(3, 0))
    row("rdma_msn_hi_is_slot16", U32.is_eq(P.msn.hi(1, 4), 65536))
    urow("rdma_msn_slot_masked", P.msn.hi(4095, 0))
    row("rdma_msn_slot_16", U32.is_eq(P.msn.hi(1, 0), 65536))
    row("rdma_msn_slot_0", U32.is_zero(P.msn.hi(0, 0)))
    row("rdma_msn_psn24", U32.is_eq(P.msn.lo(0, 16777215), 16777215))
    row("rdma_msn_next_psn_per_packet", U32.is_eq(msn_next_psn(0, 3), 3))
    # THE MASK, and the two rows that make it observable. Every other fixture has
    # a psn below 0xffffff, so `& P.PSN_MASK` is vacuously true and dropping it
    # moved NOTHING -- the mutation table's M8 was a zero until these two existed.
    # `psn_next_psn(0xffffff, 2)` is the WRAP: 24 bits, so the answer is 1 and not
    # 0x1000001, and `P.msn.lo(0, 0x1000000)` is the field: 0 and not 0x1000000.
    urow("rdma_msn_next_wrap", msn_next_psn(16777215, 2))
    urow("rdma_msn_field_over24", P.msn.lo(0, 16777216))
    urow("rdma_msn_hi_over24", P.msn.hi(0, 16777216))
    row("rdma_msn_mask_wraps", U32.is_eq(msn_next_psn(16777215, 2), 1))
    row("rdma_msn_mask_field", U32.is_zero(P.msn.lo(0, 16777216)))
    row("rdma_msn_mask_hi", U32.is_zero(P.msn.hi(0, 16777216)))
    row("rdma_msn_mask_both", Bool.and(U32.is_zero(P.msn.lo(0, 16777216)), U32.is_zero(P.msn.hi(0, 16777216))))
    urow("rdma_msn_field", P.MSN_FIELD())
    row("rdma_msn_past_ring", U32.is_eq(P.msn_base(FX_RING()), U32.add(FX_RING(), 524288)))
    row("rdma_msn_recv_none", Bool.not(ops.msn_at(True{}, 0)))
    row("rdma_msn_send_yes", ops.msn_at(False{}, 0))

# --- 12: the HEADER, :140 ---------------------------------------------------
def t_hdr() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_hdr0_send", P.hdr0(False{}))
    urow("rdma_hdr0_recv", P.hdr0(True{}))
    urow("rdma_hdr2_send", P.hdr2(False{}, 8193))
    urow("rdma_hdr2_recv", P.hdr2(True{}, 8193))
    lrow("rdma_hdr_send", P.hdr.of(False{}, 8193))
    lrow("rdma_hdr_recv", P.hdr.of(True{}, 8193))
    lrow("rdma_hdr_send_0", P.hdr.of(False{}, 0))
    lrow("rdma_hdr_recv_0", P.hdr.of(True{}, 0))
    lrow("rdma_wqe_send", wqe.words(False{}, 8193, FX_GPU(), 0, FX_KEY()))
    lrow("rdma_wqe_recv", wqe.words(True{}, 4096, FX_GPU(), 0, FX_KEY()))
    urow("rdma_hdr_len", P.hdr_len())
    urow("rdma_wqe_len", wqe_len(False{}))
    urow("rdma_wqe_len_recv", wqe_len(True{}))
    # THE SIZE IS in the send header and not in the receive one -- the receive
    # pack's 29-byte pad runs over byte 8. And the size appears TWICE in a send.
    row("rdma_hdr_recv_size_zero", U32.is_zero(P.hdr2(True{}, 8193)))
    row("rdma_hdr_send_size", U32.is_eq(P.hdr2(False{}, 8193), 8193))
    row("rdma_hdr_kind_recv", U32.is_eq(U32.and(P.hdr0(True{}), 255), P.RECV_KIND()))
    row("rdma_hdr_kind_send", U32.is_zero(U32.and(P.hdr0(False{}), 255)))
    urow("rdma_hdr_flags_send", U32.and(U32.shrn(P.hdr0(False{}), 8n), 255))
    row("rdma_hdr_signal", U32.is_eq(U32.and(U32.shrn(P.hdr0(False{}), 8n), 255), P.SQ_SEND_FLAGS_SIGNAL_COMP()))
    row("rdma_hdr_type3", U32.is_eq(U32.shrn(P.hdr0(False{}), 16n), P.WQE_KIND()))
    row("rdma_hdr_flags_recv_zero", U32.is_zero(U32.and(U32.shrn(P.hdr0(True{}), 8n), 255)))
    row("rdma_wqe_size_twice", U32.is_eq(wqe_len(False{}), 11))
    row("rdma_wqe_both_11", U32.is_eq(wqe_len(True{}), 11))

# --- 13: the INSTRUCTION STREAM, :136-155 -- A WHOLE SEND COPY ------------
def t_ops() -> IO(Unit):
  do IO<Unit>:
    # a SEND copy: two work queue elements over two buffers, no barrier.
    +s0 : P.Tr <- IO.pure(P.Tr, ops.wqe(False{}, FX_RING(), FX_CQ(), FX_DB(), 0, P.Tr.of()))
    row("rdma_send_first", seq(s0, [P.Call{P.CALL_INS_WRITE, 4096}, P.Call{P.CALL_INS_WRITE, 528384},
                                   P.Call{P.CALL_INS_WRITE, FX_DB()}, P.Call{P.CALL_INS_WAIT, 8216},
                                   P.Call{P.CALL_INS_WRITE, FX_DB()}]))
    urow("rdma_send_n5", P.Tr.ncalls(s0))
    row("rdma_send_rev", Bool.not(seq(s0, [P.Call{P.CALL_INS_WRITE, 528384}, P.Call{P.CALL_INS_WRITE, 4096}])))
    row("rdma_send_no_barrier", Bool.not(seq(s0, [P.Call{P.CALL_INS_BARRIER, P.OBJ_NONE()}])))
    # a RECV copy: one element, no msn write, and a barrier at the end.
    +r0 : P.Tr <- IO.pure(P.Tr, ops.barrier_at(True{}, ops.wqe(True{}, FX_RING(), FX_CQ(), FX_DB(), 0, P.Tr.of())))
    row("rdma_recv_first", seq(r0, [P.Call{P.CALL_INS_WRITE, 4096}, P.Call{P.CALL_INS_WRITE, FX_DB()},
                                   P.Call{P.CALL_INS_WAIT, 8216}, P.Call{P.CALL_INS_WRITE, FX_DB()},
                                   P.Call{P.CALL_INS_BARRIER, P.OBJ_NONE()}]))
    urow("rdma_recv_n5", P.Tr.ncalls(r0))
    row("rdma_recv_no_msn", Bool.not(seq(r0, [P.Call{P.CALL_INS_WRITE, 528384}])))
    row("rdma_recv_barrier_last", seq(r0, [P.Call{P.CALL_INS_WRITE, FX_DB()}, P.Call{P.CALL_INS_BARRIER, P.OBJ_NONE()}]))
    row("rdma_recv_vs_send_same_n", U32.is_eq(P.Tr.ncalls(r0), P.Tr.ncalls(s0)))
    row("rdma_recv_vs_send_diff_addrs", Bool.not(P.u32_list_eq(P.Tr.args(P.CALL_INS_WRITE(), P.Tr.calls(s0)),
                                                              P.Tr.args(P.CALL_INS_WRITE(), P.Tr.calls(r0)))))
    urow("rdma_send_n_writes", ops.n_writes(False{}))
    urow("rdma_recv_n_writes", ops.n_writes(True{}))
    urow("rdma_n_ins_send", ops.n_ins(False{}))
    urow("rdma_n_ins_recv", ops.n_ins(True{}))
    # the SECOND element of the send fixture: the ring slot advances by P.WQE_SIZE
    # and the msn by 8, and the wait by 32.
    +s1 : P.Tr <- IO.pure(P.Tr, ops.wqe(False{}, FX_RING(), FX_CQ(), FX_DB(), 1, P.Tr.of()))
    lrow("rdma_send1_writes", P.Tr.args(P.CALL_INS_WRITE(), P.Tr.calls(s1)))
    lrow("rdma_send0_writes", P.Tr.args(P.CALL_INS_WRITE(), P.Tr.calls(s0)))
    lrow("rdma_send0_waits", P.Tr.args(P.CALL_INS_WAIT(), P.Tr.calls(s0)))
    lrow("rdma_send1_waits", P.Tr.args(P.CALL_INS_WAIT(), P.Tr.calls(s1)))
    row("rdma_two_doorbells_one_addr", P.u32_list_eq(P.Tr.args(P.CALL_INS_WRITE(), P.Tr.calls(s0)), [4096, 528384, FX_DB(), FX_DB()]))
    row("rdma_send_n4_writes", U32.is_eq(U32.from_nat(List.length(&2, U32, P.Tr.args(P.CALL_INS_WRITE(), P.Tr.calls(s0)))), 4))

# --- 14: the REGISTRATION and the ADDRESS TRANSLATION, :42-53 --------------
def t_map() -> IO(Unit):
  do IO<Unit>:
    +pdt : P.Pdt <- IO.pure(P.Pdt, P.Pdt.put2(FX_GPU(), FX_KEY(), P.Pdt.put2(12288, 24576, P.Pdt.of())))
    urow("rdma_pdt_len", P.Pdt.len(pdt))
    # BOTH DIRECTIONS. A table that only answered one of these could be two
    # independent tables instead of one translation.
    urow("rdma_key_of_7000", P.key_of(pdt, 28672))
    urow("rdma_key_of_3000", P.key_of(pdt, 12288))
    urow("rdma_key_of_0", P.key_of(pdt, 0))
    urow("rdma_key_of_ffff", P.key_of(pdt, 65535))
    urow("rdma_va_of_9000", P.va_of(pdt, 36864))
    urow("rdma_va_of_6000", P.va_of(pdt, 24576))
    urow("rdma_va_of_0", P.va_of(pdt, 0))
    urow("rdma_va_of_1", P.va_of(pdt, 1))
    row("rdma_pdt_roundtrip", U32.is_eq(P.va_of(pdt, P.key_of(pdt, 28672)), 28672))
    row("rdma_pdt_unregistered", U32.is_zero(P.key_of(pdt, 65535)))
    # :42-53, the good path: two 4 KiB regions, so TWO pages at log_page 12.
    +ok : P.Tr <- IO.pure(P.Tr, map.run(True{}, 1, 1, True{}, FX_GPU(), [4096, 16384], [4096, 16384], [4096, 4096], 8192, P.Tr.of()))
    urow("rdma_map_n", P.Tr.ncalls(ok))
    lrow("rdma_map_args", P.Tr.args(P.CALL_REGISTER(), P.Tr.calls(ok)))
    row("rdma_map_ok", seq(ok, [P.Call{P.CALL_REGISTER, 2}]))
    row("rdma_map_not_refused", Bool.not(P.Tr.refused(ok)))
    # THE PEER GUARD, :44 -- two conjuncts and BOTH fixtures, because a guard with
    # only the first conjunct still refuses both of these.
    +nif : P.Tr <- IO.pure(P.Tr, map.run(False{}, 1, 1, True{}, FX_GPU(), [4096], [4096], [4096], 4096, P.Tr.of()))
    +ngr : P.Tr <- IO.pure(P.Tr, map.run(True{}, 2, 1, True{}, FX_GPU(), [4096], [4096], [4096], 4096, P.Tr.of()))
    urow("rdma_map_noiface_n", P.Tr.ncalls(nif))
    urow("rdma_map_nopeer_n", P.Tr.ncalls(ngr))
    urow("rdma_map_noiface_regs", P.Tr.count(P.CALL_REGISTER(), P.Tr.calls(nif)))
    urow("rdma_map_nopeer_regs", P.Tr.count(P.CALL_REGISTER(), P.Tr.calls(ngr)))
    row("rdma_map_noiface_refused", P.Tr.refused(nif))
    row("rdma_map_nopeer_refused", P.Tr.refused(ngr))
    row("rdma_map_noiface_msg", String.eq(P.REFUSE_MAP_MSG(), "RDMA requires memory on its node"))
    row("rdma_peer_ok_both", P.map.peer_ok(True{}, 1, 1))
    row("rdma_peer_ok_noiface", Bool.not(P.map.peer_ok(False{}, 1, 1)))
    row("rdma_peer_ok_diff", Bool.not(P.map.peer_ok(True{}, 2, 1)))
    # THE P.PAGE-SIZE REFUSAL, :48 -- an odd address matches no candidate.
    +odd : P.Tr <- IO.pure(P.Tr, map.run(True{}, 1, 1, True{}, 1, [4096], [4096], [4096], 4096, P.Tr.of()))
    urow("rdma_map_odd_n", P.Tr.ncalls(odd))
    urow("rdma_map_odd_regs", P.Tr.count(P.CALL_REGISTER(), P.Tr.calls(odd)))
    row("rdma_map_odd_refused", P.Tr.refused(odd))
    # THE ASPACE BRANCH, :46 -- SYS keeps the mapping's own addresses.
    row("rdma_aspace_sys", U32.is_eq(P.ASPACE_SYS(), 1))
    lrow("rdma_paddrs_sys", P.map.paddrs(True{}, [4096], [8192]))
    lrow("rdma_paddrs_peer", P.map.paddrs(False{}, [4096], [8192]))

# --- 15: the MISSING KEY -- THE NEGATIVE CASE ----------------------------
def t_nokey() -> IO(Unit):
  do IO<Unit>:
    # :140 asks the DEVICE for the NIC-side address. A buffer that was never
    # registered has no key, and a work queue element carrying key 0 is a
    # transfer to nowhere the NIC will accept. `map.key_guard` refuses, and no
    # Python guard writes that down -- it is :140 read the other way round.
    +empty : P.Pdt <- IO.pure(P.Pdt, P.Pdt.of())
    urow("rdma_nokey_key", P.key_of(empty, FX_GPU()))
    urow("rdma_nokey_n", P.Tr.ncalls(map.key_guard(P.key_of(empty, FX_GPU()), P.Tr.of())))
    row("rdma_nokey_refused", P.Tr.refused(map.key_guard(P.key_of(empty, FX_GPU()), P.Tr.of())))
    row("rdma_nokey_passed", Bool.not(P.Tr.refused(map.key_guard(P.key_of(FX_PDT(), FX_GPU()), P.Tr.of()))))
    urow("rdma_nokey_written", P.Tr.count(P.CALL_INS_WRITE(), P.Tr.calls(P.Tr.refuse(P.REFUSE_NO_KEY(), P.Tr.of()))))
    urow("rdma_refuse_n_types", 4)
    urow("rdma_refuse_n_nested", 0)

# --- 16: the RING cap, :120 -- THE other negative case --------------------
def t_cap() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_cap", P.RING_CAP())
    urow("rdma_cap_eq_ring", P.RING_CAP())
    row("rdma_cap_ok_4096", copies.cap_ok(4096))
    row("rdma_cap_no_4097", Bool.not(copies.cap_ok(4097)))
    row("rdma_cap_ok_0", copies.cap_ok(0))
    +bad : P.Tr <- IO.pure(P.Tr, copies.guard(copies.cap_ok(4097), P.Tr.of()))
    urow("rdma_cap_refuse_n", P.Tr.ncalls(bad))
    urow("rdma_cap_refuse_regs", P.Tr.count(P.CALL_INS_WRITE(), P.Tr.calls(bad)))
    row("rdma_cap_refused", P.Tr.refused(bad))
    row("rdma_cap_refuse_order", seq(bad, [P.Call{P.CALL_REFUSE, P.REFUSE_RING_CAP()}]))
    row("rdma_cap_msg", String.eq(P.REFUSE_CAP_MSG(), "a batch posts at most a ring of wqes per pair"))
    urow("rdma_cap_no_ins", P.Tr.count(P.CALL_INS_WRITE(), P.Tr.calls(copies.guard(copies.cap_ok(4096), P.Tr.of()))))

# --- 17: `rdma_submit`, :161-169 -------------------------------------------
def t_submit() -> IO(Unit):
  do IO<Unit>:
    urow("rdma_encode_len", encode_len())
    row("rdma_submit_fires_2", submit.fires(2))
    row("rdma_submit_none_0", Bool.not(submit.fires(0)))
    # THE NEGATIVE CASE: a linear of FIVE srcs with TWO on an RDMA queue. The
    # three others keep THEMSELVES -- `ops = [[u] for u in lin.src]` -- and are
    # NOT replaced by ring writes and doorbell writes.
    urow("rdma_submit_srcs", 5)
    urow("rdma_submit_replaced", P.submit.src_replaced(5, 2))
    urow("rdma_submit_kept", submit.srcs_kept(5, 2))
    row("rdma_submit_keeps_nonrdma", U32.is_eq(submit.srcs_kept(5, 2), 3))
    row("rdma_submit_all_queues", U32.is_eq(submit.srcs_kept(5, 5), 0))
    # `positions` is ASCENDING because the dict at :162 was built by `enumerate`.
    urow("rdma_submit_pos0", submit.pos_at(0))
    urow("rdma_submit_pos1", submit.pos_at(1))
    row("rdma_submit_pos_asc", U32.is_lt(submit.pos_at(0), submit.pos_at(1)))
    # the wire tests, :99-101 -- TWO op tests and the first RDMA arg.
    urow("rdma_wire_cs", P.wire.of(True{}, True{}, 1))
    urow("rdma_wire_notcall", P.wire.of(False{}, True{}, 1))
    urow("rdma_wire_notstore", P.wire.of(True{}, False{}, 1))
    urow("rdma_wire_none", P.wire.of(True{}, True{}, 0))
    row("rdma_is_rdma_cs", wire.is_rdma(True{}, True{}, 1))
    row("rdma_is_rdma_notcall", Bool.not(wire.is_rdma(False{}, True{}, 1)))
    row("rdma_is_rdma_notstore", Bool.not(wire.is_rdma(True{}, False{}, 1)))
    row("rdma_is_rdma_none", Bool.not(wire.is_rdma(True{}, True{}, 0)))
    # :106 the SORTED pair and the recv flag.
    srow("rdma_queue_lo", queue.lo("GPU", "rdma_gpu_0_gpu_1_sq"))
    srow("rdma_queue_hi", queue.hi("GPU", "rdma_gpu_0_gpu_1_sq"))
    srow("rdma_queue_lo_rev", queue.lo("rdma_gpu_0_gpu_1_sq", "GPU"))
    row("rdma_queue_sorted", String.eq(queue.lo("GPU", "rdma_gpu_0_gpu_1_sq"), "GPU"))
    row("rdma_queue_sorted_rev", String.eq(queue.lo("rdma_gpu_0_gpu_1_sq", "GPU"), "GPU"))
    row("rdma_recv_is_src", queue.is_recv(True{}))
    row("rdma_send_not_src", Bool.not(queue.is_recv(False{})))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_sizes()
    c : Unit <- t_tags()
    +d : Unit <- t_page()
    e : Unit <- t_chunks()
    +f : Unit <- t_dev()
    +g : Unit <- t_alloc()
    +h : Unit <- t_dbell()
    i : Unit <- t_dbval()
    +j : Unit <- t_epoch()
    k : Unit <- t_msn()
    +l : Unit <- t_hdr()
    +m : Unit <- t_ops()
    +n : Unit <- t_map()
    o : Unit <- t_nokey()
    +p : Unit <- t_cap()
    q : Unit <- t_submit()
    IO.print("rdma-done=1")

# ===========================================================================
# THE MUTATION TABLE. Every number below is `.agents/slop/mutate.py`'s output,
# not an estimate. The harness applies one edit to a scratch copy, runs the
# INTERPRETED lane, and diffs the row NAMES; the useful column is "rows MOVED",
# because a mutation that moves nothing measures what this gate does NOT see.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | the candidate list is DESCENDING, so the fold's LAST match is the SMALLEST | 11 | :48's `max()` over an ASCENDING list. Eleven and not four because every `rdma_lp_*` row is a different alignment and a wrong `log_page` is a wrong page count, which is a wrong registration, which is a silently wrong transfer. |
# | M2 | `log_page` answers 12 when NOTHING matches -- no ValueError | 7 | `max()` of an EMPTY generator. It moves the four `rdma_lp_none_*` rows, `rdma_lp_none_flagged` and -- the two that matter -- `rdma_map_odd_refused` and `rdma_map_odd_regs`. The last is the refusal not firing, so the NESTING of the guard inside the call is what makes this mutation visible at the trace and not only in the table. |
# | M3 | `wait_expected` drops the `^ 1` epoch inversion | 14 | THE biggest in the file, and the one that would have shipped. :151's `(n // P.CQ_ENTRIES & 1 ^ 1)` -- and it moves EVERY `rdma_wait_exp_*` row, both send and receive, across one and a half ring wraps. A port that dropped the `^ 1` compiles, typechecks, passes every count, passes every address, and HANGS: nothing ever matches the completion entry. The EPOCH fixture is the only reason it is caught, and every one of its rows is a DIFFERENT `n` because a single wrap point cannot see an inversion. |
# | M4 | the doorbell rings slot `n` instead of `n + 1` | 7 | :148's `n + 1` against :151's `n`. It moves `rdma_db_slot_is_next`, `rdma_db_wait_slots_differ` and all five `rdma_ep_slot_*`. The doorbell and the wait must be ONE APART, and that is the ring protocol in one number. |
# | M5 | the epoch drops its `& 1` | 3 | that the epoch is a SINGLE BIT. Only `rdma_ep_bit_8191`, `rdma_ep_bit_8192` and `rdma_epoch_one_bit` move -- the two that need `n` past TWO wraps -- which is why the epoch fixture runs to 8192 and not to 4097. |
# | M6 | the receive bit is dropped from `wait_expected` | 8 | the `| (2 if is_recv else 0)`, so a receive and a send on one completion queue can no longer be told apart. It moves the receive rows and `rdma_wait_recv_minus_send`, and NOT the send rows: the two sides are separate claims and the receive fixture is what makes them so. |
# | M7 | the msn slot sits at bit 0 instead of bit 48 | 5 | :145's `<< 48`. `base.bend` has no 64-bit shift, so the port carries the word as two halves with the slot at hi32's bit 16; this mutation puts it at bit 0 of the LOW half and the five `rdma_msn_hi*`/`slot*` rows see it. |
# | M8 | the msn psn fields are unmasked (no `& 0xffffff`) | 3 | :145's `& 0xffffff`, and this was a ZERO until the fixture straddled 2^24. Every original psn is below `0xffffff`, so the mask is vacuously true and dropping it changed nothing. `rdma_msn_next_wrap` (`psn_next_psn(0xffffff, 2)` is 1, not `0x1000001`) and `rdma_msn_field_over24` / `rdma_msn_mask_field` / `rdma_msn_mask_hi` are the rows that exist only for it. This is the same lesson `device.bend`'s `tag_of` row teaches and it is worth writing down twice. |
# | M9 | the send ring drops the `+ 8` msn table | 3 | :92's `P.WQE_SIZE + 8`. The msn table lives at `ring + P.RING_ENTRIES * P.WQE_SIZE` (`:144`), so a send ring allocated without the `+ 8` overlaps its own last work queue element. `rdma_msn_past_ring` does NOT move, because it reads the ADDRESS and not the SIZE: the arithmetic is right and only the allocation is wrong, which is exactly the split. |
# | M10 | `bump.psn` adds `packets` on a RECEIVE too | 1 | :123's `([] if is_recv else [psn...])`. ONE row, and it is the whole send/receive asymmetry in the sequence counters: a receive consumes no packet-send-numbers because the psns are the SENDER's. A localised row, and it is localised on purpose. |
# | M11 | the receive header gets the size in word 2 as well | 4 | bnxtdev.py:19's 29-byte pad, which runs OVER the `I size` at byte 8. A receive's work queue element says nothing about its length in the header, and :141 supplies it as a separate word. `rdma_hdr_recv`, `rdma_hdr_recv_0`, `rdma_hdr_recv_size_zero` and `rdma_wqe_recv` move. |
# | M12 | `psns` drops the `initial=0` -- one entry short | 3 | :125's `itertools.accumulate(chunks, initial=0)`. It moves `rdma_psns_send`, `rdma_psns_recv` and `rdma_psns_2` -- and NOT `rdma_psns_len_send`/`rdma_psns_len_recv`, because those read `psns_len(wqes)` and not the list. That is the two-rows-one-claim shape: the COUNT and the CONTENTS are transcribed independently and can disagree. |
# | M13 | `chunks_of` reverses the chunk order | 2 | that `range(0, n, CHUNK)` walks ASCENDING. Only `rdma_chunks_1g1p` and `rdma_chunks_1g4p` move, because every other fixture is one chunk or two equal chunks: a buffer larger than `P.RDMA_CHUNK` is the ONLY thing that can see the order, and it takes two such rows to see both directions. |
# | M14 | `alloc.buf_size` rounds the BUFFER's size to a page too | 3 | :31's `Buffer(self.dev.device, mem.nbytes, dtypes.u8, …)` against :27's `round_up(mem.nbytes, 0x1000)`. The buffer's size is RAW and the virtual address is ROUNDED, and both are right. `rdma_buf_nb_raw` and `rdma_buf_diff` are the pair; a port that rounded both would under-report a 12-byte buffer as 4096 bytes of dtype. |
# | M15 | `db.off_down` keeps the low twelve bits -- the doorbell pages UP | 5 | :35's `& ~0xfff`. The mapping must start ON a page, and :36 then adds the SAME `off` to the bar base. All three spellings of the address -- `db.off_down`, `db.off_up`, `db.addr` -- depend on the mask going both ways, and `rdma_db_off_masked` is the row that says the two halves sum back to `db_off`. |
# | M16 | the page guard is OUTSIDE the register call -- a warning, not a refusal | 2 | THE nesting, and it is the whole claim that a refusal TRUNCATES. Python raises at :48 before it reaches `register_mem` at :50, so an unusable page size means the region is NEVER registered. With the guard outside the call the trace reads `REGISTER(0), REFUSE(log_page)` -- the registration happened and then the refusal, which is the opposite of what the source does. `rdma_map_odd_n` and `rdma_map_odd_regs` move. This was a real port bug and the CPython oracle found it, not the mutation table. |
# | M17 | `va_of` is the forward lookup too -- no reverse direction | 3 | :106's `min(gpu, wire.tag), max(gpu, wire.tag)` and :140's `getaddr(nic.device)`. The TRANSLATION TABLE has to answer in both directions and a table that answers only one is two tables. `rdma_va_of_9000`, `rdma_va_of_6000` and `rdma_pdt_roundtrip` move; the `key_of_*` rows do not, which is what makes the pair a pair. |
# | M18 | `_offset` adds the offset -- the HOST allocator's rule | 2 | :52's `return buf`. `ops_npy.bend`'s `npy.offset` is `buf + offset` and this is `buf`, and the two files' gates are the only thing in the tree that tells them apart. It moves `rdma_offset_val` and `rdma_offset_identity` and NOT `rdma_offset_n`, because the trace for `_offset` is empty either way. |
# | M19 | `submit.src_replaced` replaces EVERY src, RDMA or not | 3 | :164's `ops = [[u] for u in lin.src]`. THE negative case the brief asked for: a src with no RDMA wire keeps ITSELF and is not replaced by ring writes and doorbell writes. `rdma_submit_kept`, `rdma_submit_keeps_nonrdma` and `rdma_submit_all_queues` move. |
# | M20 | the qp buffer-name table is reversed against ops_rdma.py's order | 2 | :82-83's `("sq","rq","scq","rcq")` then `sq_seq, rq_seq, psn` then `db`. Only `rdma_buf_1` and `rdma_buf_8` move, because a reversal that swaps 1<->8 and 2<->7 etc. leaves the MIDDLE four correct: two rows and not one is the price of a fixture that reads only the ends, and `rdma_bufs_len` does not move at all. |
# | M21 | a comment-only edit | 0 -- THE CONTROL | a table with no row that CANNOT move is a table of coincidences. |
#
# M8 and M16 ARE THE INTERESTING ONES, and they are different kinds of finding.
# M16 is a PORT BUG the CPython oracle caught and no mutation would have: the two
# guards looked right and the nesting was wrong, so the port recorded a
# registration that Python never performs. M8 is a GATE bug the mutation table
# caught: the mask is in the source, the port, and the gate, and all three agree
# on every fixture because every fixture's psn fits in 24 bits.
#
# WHAT this gate still does not see, and it is a SHORT list, which is the point:
#
#   1. THE INSTRUCTION ARGUMENTS. `P.Tr` records the call and, for the twelve calls
#     that take a number, that number. The work queue element's ELEVEN payload
#     words, the msn value, the two doorbell values and the expected wait value
#     are all pure functions with their OWN rows -- `rdma_wqe_send`,
#     `rdma_msn_whole0/1`, `rdma_db_written*`, `rdma_wait_exp_*` -- but nothing
#     checks that the RIGHT one is passed to the RIGHT call. Mutating `ins.ring_db`
#     to write the msn address instead of the doorbell address moves NOTHING,
#     because both are one `P.CALL_INS_WRITE` with a different argument and no row
#     pairs an address with an instruction kind.
#   2. `db_value`'s HIGH HALF. WALL 5 is about the low half being transmitted
#     (`rdma_db_hi_dropped`, `rdma_db_lo_zero`, `rdma_db_or_noop`) and those rows
#     are exact. But `db_value.hi` is a pure function of `xid` and `typ` and
#     nothing ever CONSUMES it: if `P.BNXT_QPLIB_DBR_VALID` were wrong, only
#     `rdma_dbr_valid` and `rdma_dbhi_*` would move, and no transfer would change.
#   3. `hdr.of`'s WORDS 1 AND 3-7. They are zero in `struct.pack`'s output and
#     this port writes zero; a version that wrote garbage into the five padding
#     words would print the same `hdr0`/`hdr2` and only `rdma_hdr_send`/`recv`
#     could see it -- and they do, but only because they print all eight.
#   4. `get_call_arg_uops` and `unwrap_view`. WALL 4. The port reads `P.key_of(va)`
#     where Python calls the device, and the two agree because the device's answer
#     IS the key -- an assumption, and the only one in this file that is not a
#     transcription.
#   5. THE wire tag. REPORTED in the header and not fixed: on a graph that reached
#     `lower_call` with the wire already bufferized, `UOp.tag` is `None` and
#     `min(gpu, None)` raises. `rdma_queue_sorted` pins the sort with the tag
#     spelled as a string, which is the case the source unambiguously supports,
#     and `wire.tag` being `None` is not exercised because there is no RDMA
#     hardware here.
#   6. THE DRIVER. WALL 2. `BNXTDev`'s queue state, the `connect` handshake and
#     the firmware are all seam. `rdma_connects = 2` says the Python writes two
#     `connect` calls and nothing about whether either succeeds.
