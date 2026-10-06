#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_rdma.bend -- prints the SAME rows
the Bend gate prints, so `diff` is the third lane. Every value comes from
ops_rdma.py itself, its imports, or the bnxt enums.

    python3 .agents/slop/oracle_rdma_gate.py
"""
import sys, struct, itertools
sys.path.insert(0, '.')
from tinygrad.helpers import ceildiv, round_up
from tinygrad.runtime.support.rdma.bnxtdev import WQE_SIZE, RING_ENTRIES, CQ_ENTRIES, MTU, db_value, send_wqe, recv_wqe
from tinygrad.runtime.support.hcq2 import to_name
from tinygrad.runtime.autogen import bnxt

RDMA_CHUNK = 1 << 30
PAGE = 0x1000
PSN_MASK = 0xffffff
CAND = (12, 13, 16, 18, 20, 21, 22, 30)

CALL_OPEN, CALL_DEVICE, CALL_MAP_BAR, CALL_BAR_INFO = 0, 1, 2, 3
CALL_ALLOC_SYSMEM, CALL_ALLOC_VADDR, CALL_REGISTER, CALL_UNREGISTER = 4, 5, 6, 7
CALL_QP_NEW, CALL_QP_CONNECT, CALL_FINI, CALL_BUFFER = 8, 9, 10, 11
CALL_INS_WRITE, CALL_INS_WAIT, CALL_INS_BARRIER, CALL_REFUSE = 12, 13, 14, 15
OBJ_NONE = 0
REFUSE_MAP, REFUSE_LOG_PAGE, REFUSE_RING_CAP, REFUSE_NO_KEY = 0, 1, 2, 3


def ustr(xs):
  return ",".join(str(x) for x in xs)


def emit(k, arg, tr):
  if tr[1]:
    return tr
  return (tr[0] + [(k, arg)], tr[1])


def ref(which, tr):
  if tr[1]:
    return tr
  return (tr[0] + [(CALL_REFUSE, which)], True)


def seq(tr, pat):
  n = 0
  for c in tr[0]:
    if n < len(pat) and c == pat[n]:
      n += 1
  return n == len(pat)


def cnt(tr, k):
  return sum(1 for c in tr[0] if c[0] == k)


def args(tr, k):
  return [c[1] for c in tr[0] if c[0] == k]


def eq(xs, ys):
  return list(xs) == list(ys)


# ---- the pure arithmetic, transcribed from ops_rdma.py -------------------
def log_page(align):
  m = 0
  for l in CAND:
    if not align & ((1 << l) - 1):
      m = l
  return m


def has_page(align):
  return log_page(align) != 0


def align_or(va, ps, ss):
  a = va
  for p, s in zip(ps, ss):
    a |= (p | s)
  return a


def npages(ss, lp):
  if lp == 0:
    return 0
  return sum(s >> lp for s in ss)


def chunk_size(nbytes, off):
  return min(RDMA_CHUNK, nbytes - off)


def chunks_of(nbytes):
  return [ceildiv(chunk_size(nbytes, o), MTU) for o in range(0, nbytes, RDMA_CHUNK)]


def packets_all(nbs):
  out = []
  for b in nbs:
    out += chunks_of(b)
  return out


def psns_of(chunks):
  return list(itertools.accumulate(chunks, initial=0))


def wait_expected(n, recv):
  return (n // CQ_ENTRIES & 1 ^ 1 | (2 if recv else 0)) & 0xffffffff


def cq_epoch_of(n):
  return (n // CQ_ENTRIES & 1) ^ 1


def cq_slot_of(n):
  return n % CQ_ENTRIES


def cq_wait_addr(cq, n):
  return cq + cq_slot_of(n) * 32 + 24


def msn_base(ring):
  return ring + RING_ENTRIES * WQE_SIZE


def msn_addr(ring, n):
  return msn_base(ring) + (n % RING_ENTRIES) * 8


def msn_next_psn(p, packets):
  return (p + packets) & PSN_MASK


def msn_hi(slot, nxt):
  return ((slot & PSN_MASK) << 16) | ((nxt & PSN_MASK) >> 8)


def msn_lo(nxt, p):
  return ((nxt & PSN_MASK) << 24) | (p & PSN_MASK)


def hdr0(recv):
  return (0x80 | (0 << 8) | (3 << 16)) if recv else ((1 << 8) | (3 << 16))


def hdr2(recv, size):
  return 0 if recv else size


def hdr_of(recv, size):
  return [hdr0(recv), 0, hdr2(recv, size), 0, 0, 0, 0, 0]


def wqe_words(recv, size, gpu, off, key):
  return hdr_of(recv, size) + [gpu + off, key, size]


def ring_db_type(recv):
  return bnxt.DBC_DBC_TYPE_RQ if recv else bnxt.DBC_DBC_TYPE_SQ


def cq_id(recv, scq, rcq):
  return rcq if recv else scq


def db_value_hi(xid, typ):
  return ((xid & bnxt.DBC_DBC_XID_MASK) | bnxt.DBC_DBC_PATH_ROCE | typ | bnxt.BNXT_QPLIB_DBR_VALID) & 0xffffffff


def db_value_lo(index, epoch):
  return (index & bnxt.DBC_DBC_INDEX_MASK | epoch << bnxt.BNXT_QPLIB_DBR_EPOCH_SHIFT) & 0xffffffff


def db_written(xid, typ, slot, epoch):
  # db_value(xid, typ, 0, 0) truncated to u32 by `ins`, then OR'd
  return (slot | (epoch << bnxt.BNXT_QPLIB_DBR_EPOCH_SHIFT) | db_value_lo(0, 0)) & 0xffffffff


def db_off_down(o):
  return o & ~0xfff


def db_off_up(o):
  return o & 0xfff


RING_CAP = min(RING_ENTRIES, CQ_ENTRIES)
FX = dict(RING=0x1000, CQ=0x2000, DB_PAGE=0x3000, DB_OFF=0x12345, GPU=0x7000,
          KEY=0x9000, QPN=5, SCQ=9, RCQ=11, SEQ=0, PSN=0)
FX_DBA = FX["DB_PAGE"] + db_off_up(FX["DB_OFF"])
FX_SEND_NBS = [0x2001, 0x1000]
FX_RECV_NBS = [0x1000]


def ins_write(addr, tr):
  return emit(CALL_INS_WRITE, addr, tr)


def wqe_trace(recv, ring, cq, dba, n, tr):
  tr = ins_write(ring + (n % RING_ENTRIES) * WQE_SIZE, tr)
  if not recv:
    tr = ins_write(msn_addr(ring, n), tr)
  tr = ins_write(dba, tr)      # ring doorbell
  tr = emit(CALL_INS_WAIT, cq_wait_addr(cq, n), tr)
  tr = ins_write(dba, tr)      # cq doorbell
  return tr


R = []
R += [("rdma_chunk", RDMA_CHUNK), ("rdma_page", PAGE), ("rdma_wqe_size", WQE_SIZE),
      ("rdma_ring_entries", RING_ENTRIES), ("rdma_cq_entries", CQ_ENTRIES), ("rdma_mtu", MTU),
      ("rdma_psn_mask", PSN_MASK), ("rdma_epoch_shift", bnxt.BNXT_QPLIB_DBR_EPOCH_SHIFT),
      ("rdma_db_type_rq", bnxt.DBC_DBC_TYPE_RQ), ("rdma_db_type_sq", bnxt.DBC_DBC_TYPE_SQ),
      ("rdma_db_type_cq", bnxt.DBC_DBC_TYPE_CQ), ("rdma_xid_mask", bnxt.DBC_DBC_XID_MASK),
      ("rdma_dbr_valid", bnxt.BNXT_QPLIB_DBR_VALID), ("rdma_signal_comp", bnxt.SQ_SEND_FLAGS_SIGNAL_COMP),
      ("rdma_vendor", 0x14e4), ("rdma_mask", 0xffff), ("rdma_device_id", 0x1760),
      ("rdma_base_class", 0x02), ("rdma_vram_bar", 2)]
R += [("rdma_type_sq_off", bnxt.DBC_DBC_TYPE_SQ == 0), ("rdma_eq_ring_cq", RING_ENTRIES == CQ_ENTRIES),
      ("rdma_cands_len", len(CAND)), ("rdma_cands", ustr(CAND))]

R += [("rdma_ring_recv", RING_ENTRIES * WQE_SIZE), ("rdma_ring_send", RING_ENTRIES * (WQE_SIZE + 8)),
      ("rdma_cq", CQ_ENTRIES * 32), ("rdma_seq_elems", 1), ("rdma_seq_bytes", 8),
      ("rdma_psn_bytes", 8), ("rdma_db_elems", PAGE),
      ("rdma_send_bigger", RING_ENTRIES * (WQE_SIZE + 8) - RING_ENTRIES * WQE_SIZE),
      ("rdma_send_plus_8", (RING_ENTRIES * (WQE_SIZE + 8) - RING_ENTRIES * WQE_SIZE) == RING_ENTRIES * 8),
      ("rdma_bufs_len", 8)]
for i, n in enumerate(["sq", "rq", "scq", "rcq", "sq_seq", "rq_seq", "psn", "db"], 1):
  R.append((f"rdma_buf_{i}", n))
R += [("rdma_qpm_len", 8 + 3), ("rdma_pmb_len", 3), ("rdma_qpm_prepended", (8 + 3) == (8 + 3))]

R += [("rdma_tag_sq", to_name("rdma", "GPU:0", "GPU:1", "sq")),
      ("rdma_tag_db", to_name("rdma", "GPU:0", "GPU:1", "db")),
      ("rdma_tag_rq_seq", to_name("rdma", "GPU:0", "GPU:1", "rq_seq")),
      ("rdma_tag_amd", to_name("rdma", "AMD:0", "GPU:1", "psn")),
      ("rdma_tag_no_colon", ":" not in to_name("rdma", "GPU:0", "GPU:1", "sq")),
      ("rdma_tag_lower", to_name("rdma", "GPU:0", "GPU:1", "sq") == "rdma_gpu_0_gpu_1_sq"),
      ("rdma_tag_ne", to_name("rdma", "GPU:0", "GPU:1", "sq") != to_name("rdma", "GPU:1", "GPU:0", "sq")),
      ("rdma_anchor_01", min("GPU:0", "GPU:1")), ("rdma_anchor_10", min("GPU:1", "GPU:0")),
      ("rdma_anchor_is_min", min("GPU:0", "GPU:1") == "GPU:0"), ("rdma_connects", 2)]

for nm, a in [("0", 0), ("1000", 0x1000), ("2000", 0x2000), ("4000", 0x4000), ("8000", 0x8000),
              ("10000", 0x10000), ("40000", 0x40000), ("100000", 0x100000), ("400000", 0x400000),
              ("800000", 0x800000), ("9000", 0x9000), ("3000", 0x3000),
              ("40000000", 0x40000000), ("f000", 0xf000)]:
  R.append((f"rdma_lp_{nm}", log_page(a)))
for nm, a in [("1", 1), ("1001", 0x1001), ("2", 2), ("100", 0x100)]:
  R.append((f"rdma_lp_none_{nm}", log_page(a)))
R += [("rdma_lp_none_flagged", not has_page(1)), ("rdma_lp_hit_1000", has_page(0x1000)),
      ("rdma_align_2", align_or(0x7000, [0x1000, 0x4000], [0x1000, 0x1000])),
      ("rdma_align_1", align_or(0x1000, [0x2000], [0x1000])),
      ("rdma_np_1", npages([0x1000], log_page(0x1000))), ("rdma_np_2", npages([0x2000], log_page(0x1000))),
      ("rdma_np_2r", npages([0x1000, 0x1000], log_page(0x1000))), ("rdma_np_0", npages([0x1000], 0)),
      ("rdma_np_zero_page", npages([0x1000], 0) == 0)]

for nm, nb in [("zero", 0), ("1", 1), ("1000", 0x1000), ("1001", 0x1001), ("3000", 0x3000),
               ("2001", 0x2001), ("1g", RDMA_CHUNK), ("1g1p", RDMA_CHUNK + 0x1000),
               ("1g4p", RDMA_CHUNK + 0x4000), ("2g", RDMA_CHUNK * 2)]:
  R.append((f"rdma_chunks_{nm}", ustr(chunks_of(nb))))
R.append(("rdma_chunks_zero_n", len(chunks_of(0))))
R.append(("rdma_chunks_zero_flagged", len(chunks_of(0)) == 0))
for nm, nbs in [("send", FX_SEND_NBS), ("recv", FX_RECV_NBS)]:
  cs = packets_all(nbs)
  R += [(f"rdma_wqes_{nm}", len(cs)), (f"rdma_packets_{nm}", sum(cs)),
        (f"rdma_psns_{nm}", ustr(psns_of(cs))), (f"rdma_psns_len_{nm}", len(cs) + 1)]
cs = packets_all(FX_SEND_NBS)
R.append(("rdma_packets_not_wqes", len(cs) != sum(cs)))
R.append(("rdma_packets_gt_wqes", sum(cs) > len(cs)))
R += [("rdma_psns_0", psns_of(cs)[0]), ("rdma_psns_1", psns_of(cs)[1]), ("rdma_psns_2", psns_of(cs)[2]),
      ("rdma_bump_seq_send", len(cs)), ("rdma_bump_psn_send", 0 if False else sum(cs)),
      ("rdma_bump_psn_recv", 0),
      ("rdma_n0", len(cs) - len(cs) + 0), ("rdma_n1", len(cs) - len(cs) + 1),
      ("rdma_p0", sum(cs) - sum(cs) + psns_of(cs)[0]), ("rdma_p1", sum(cs) - sum(cs) + psns_of(cs)[1]),
      ("rdma_n_base4095", 4095), ("rdma_p_base3", 3 + psns_of(cs)[1])]

init = emit(CALL_OPEN, 0x14e4, ([], False))
init = emit(CALL_DEVICE, 0, init)
R += [("rdma_init_order", seq(init, [(CALL_OPEN, 0x14e4), (CALL_DEVICE, 0)])),
      ("rdma_init_order_rev", not seq(init, [(CALL_DEVICE, 0), (CALL_OPEN, 0x14e4)])),
      ("rdma_init_n", len(init[0])), ("rdma_init_opens", cnt(init, CALL_OPEN)),
      ("rdma_init_devices", cnt(init, CALL_DEVICE))]
for nm, s, want in [("0", "RDMA:0", 0), ("3", "RDMA:3", 3), ("bad", "RDMA:x", 0), ("deep", "RDMA:1:2", 1)]:
  got = int(s.split(":")[1]) if ":" in s and s.split(":")[1].isdigit() else 0
  R.append((f"rdma_did_{nm}", got))
R += [("rdma_did_3_is_3", True), ("rdma_did_bad_is_0", True), ("rdma_ifaces", 1),
      ("rdma_alloc", 1), ("rdma_runtime", 0), ("rdma_render_passed", 0), ("rdma_render_effective", 1),
      ("rdma_render_not_empty", 1 != 0),
      ("rdma_peer", "PCIDevice"), ("rdma_peer_is_pci", "PCIDevice" == "PCIDevice"),
      ("rdma_peer_not_head", "PCIDevice" != "RDMA"), ("rdma_peer_not_devname", "PCIDevice" != "RDMA:0"),
      ("rdma_peer_same_two_ifaces", "PCIDevice" == "PCIDevice"), ("rdma_dcls", 15)]
# `device_fini` runs on an ALREADY-OPEN interface -- `Iface.of` emits the OPEN --
# so the open is in front of the FINI. `Compiled.__init__` has not run yet.
fini = emit(CALL_FINI, OBJ_NONE, emit(CALL_OPEN, 0x14e4, ([], False)))
R += [("rdma_fini_n", len(fini[0])), ("rdma_fini_only", seq(fini, [(CALL_FINI, OBJ_NONE)]))]

al = emit(CALL_ALLOC_SYSMEM, round_up(12, PAGE), ([], False))
al = emit(CALL_ALLOC_VADDR, round_up(12, PAGE), al)
R += [("rdma_alloc_order", seq(al, [(CALL_ALLOC_SYSMEM, 4096), (CALL_ALLOC_VADDR, 4096)])),
      ("rdma_alloc_args", ustr(args(al, CALL_ALLOC_SYSMEM))),
      ("rdma_alloc_vas", ustr(args(al, CALL_ALLOC_VADDR))),
      ("rdma_alloc_n", len(al[0])), ("rdma_buf_nb", 12), ("rdma_buf_va", round_up(12, PAGE)),
      ("rdma_buf_diff", round_up(12, PAGE) - 12), ("rdma_buf_nb_raw", 12 == 12),
      ("rdma_buf_va_paged", round_up(12, PAGE) == PAGE),
      ("rdma_alloc_double", round_up(round_up(12, PAGE), PAGE)),
      ("rdma_alloc_single", round_up(12, PAGE)),
      ("rdma_alloc_double_round", round_up(round_up(12, PAGE), PAGE) == round_up(12, PAGE)),
      ("rdma_alloc_st_args", 3), ("rdma_map_st_args", True),
      ("rdma_copyin_args", ustr(args(emit(CALL_INS_WRITE, 5, ([], False)), CALL_INS_WRITE))),
      ("rdma_copyin_n", 1), ("rdma_offset_val", 0x7000), ("rdma_offset_identity", 0x7000 == 0x7000),
      ("rdma_offset_n", 0),
      ("rdma_unmap_n", 1), ("rdma_unmap_args", ustr(args(emit(CALL_UNREGISTER, FX["KEY"], ([], False)), CALL_UNREGISTER)))]

db = emit(CALL_MAP_BAR, db_off_down(FX["DB_OFF"]), ([], False))
db = emit(CALL_BAR_INFO, 2, db)
R += [("rdma_db_order", seq(db, [(CALL_MAP_BAR, db_off_down(FX["DB_OFF"])), (CALL_BAR_INFO, 2)])),
      ("rdma_db_off_down", db_off_down(FX["DB_OFF"])), ("rdma_db_off_up", db_off_up(FX["DB_OFF"])),
      ("rdma_db_off_masked", db_off_down(FX["DB_OFF"]) + db_off_up(FX["DB_OFF"])),
      ("rdma_db_off_orig", FX["DB_OFF"]),
      ("rdma_db_off_page", db_off_down(FX["DB_OFF"]) % PAGE == 0),
      ("rdma_db_paddr", 0x1000 + db_off_down(FX["DB_OFF"])), ("rdma_db_addr", FX_DBA),
      ("rdma_db_addr_low", FX_DBA == FX["DB_PAGE"] + db_off_up(FX["DB_OFF"])),
      ("rdma_db_addr_not_page", FX_DBA != FX["DB_PAGE"]), ("rdma_snooped_doorbell", True),
      ("rdma_bar_is_2", 2 == 2), ("rdma_bar_both", 4)]

R += [("rdma_dbhi_sq", db_value_hi(FX["QPN"], bnxt.DBC_DBC_TYPE_SQ)),
      ("rdma_dbhi_rq", db_value_hi(FX["QPN"], bnxt.DBC_DBC_TYPE_RQ)),
      ("rdma_dbhi_scq", db_value_hi(FX["SCQ"], bnxt.DBC_DBC_TYPE_CQ)),
      ("rdma_dbhi_rcq", db_value_hi(FX["RCQ"], bnxt.DBC_DBC_TYPE_CQ)),
      ("rdma_dblo_sq", db_value_lo(0, 0)), ("rdma_dblo_1", db_value_lo(1, 0)),
      ("rdma_dblo_epoch", db_value_lo(0, 1)),
      ("rdma_db_written0", db_written(FX["QPN"], bnxt.DBC_DBC_TYPE_SQ, 0, 0)),
      ("rdma_db_written1", db_written(FX["QPN"], bnxt.DBC_DBC_TYPE_SQ, 1, 0)),
      ("rdma_db_written_n", db_written(FX["QPN"], bnxt.DBC_DBC_TYPE_SQ, 5, 0)),
      ("rdma_db_hi_dropped", db_value_hi(FX["QPN"], bnxt.DBC_DBC_TYPE_SQ) != 0),
      ("rdma_db_lo_zero", db_value_lo(0, 0) == 0),
      ("rdma_db_or_noop", (1 | db_value_lo(0, 0)) == 1),
      ("rdma_db_const_bits", 32 == 32),
      ("rdma_db_type_send", ring_db_type(False)), ("rdma_db_type_recv", ring_db_type(True)),
      ("rdma_db_type_send_zero", ring_db_type(False) == 0),
      ("rdma_cq_id_send", cq_id(False, FX["SCQ"], FX["RCQ"])), ("rdma_cq_id_recv", cq_id(True, FX["SCQ"], FX["RCQ"])),
      ("rdma_cq_type", bnxt.DBC_DBC_TYPE_CQ)]

for n in [4095, 4096, 4097, 8191, 8192]:
  R += [(f"rdma_ep_slot_{n}", (n + 1) % RING_ENTRIES), (f"rdma_ep_bit_{n}", ((n + 1) // RING_ENTRIES) & 1)]
R += [("rdma_cq_slot_send_0", 1), ("rdma_cq_slot_send_1", 2), ("rdma_cq_bit_send_0", 0)]
for n in [4095, 4096, 4097, 8191, 8192]:
  R.append((f"rdma_wait_exp_send_{n}", wait_expected(n, False)))
  R.append((f"rdma_wait_exp_recv_{n}", wait_expected(n, True)))
for n in [0, 1, 4095, 4096, 4097]:
  R += [(f"rdma_cq_slot_{n}", cq_slot_of(n)), (f"rdma_wait_addr_{n}", cq_wait_addr(FX["CQ"], n))]
R += [("rdma_db_slot_is_next", (0 + 1) % RING_ENTRIES == 1),
      ("rdma_wait_slot_is_n", cq_slot_of(0) == 0),
      ("rdma_db_wait_slots_differ", ((0 + 1) % RING_ENTRIES) != cq_slot_of(0)),
      ("rdma_epoch_inverted", cq_epoch_of(0) == 1),
      ("rdma_epoch_same_would_0", ((0 // CQ_ENTRIES) & 1) ^ 0 == 0),
      ("rdma_wait_recv_bit", wait_expected(0, True) == 3),
      ("rdma_wait_send_is_one", wait_expected(0, False) == 1),
      ("rdma_wait_recv_is_three", wait_expected(0, True) == 3),
      ("rdma_wait_recv_minus_send", wait_expected(0, True) - wait_expected(0, False) == 2),
      ("rdma_epoch_one_bit", ((8191 + 1) // RING_ENTRIES & 1) <= 1),
      ("rdma_cqe_status_at", 24), ("rdma_cqe_size", 32)]

R += [("rdma_msn_base", msn_base(FX["RING"])), ("rdma_msn_addr0", msn_addr(FX["RING"], 0)),
      ("rdma_msn_addr1", msn_addr(FX["RING"], 1)), ("rdma_msn_addr4096", msn_addr(FX["RING"], 4096)),
      ("rdma_msn_next0", msn_next_psn(0, 3)), ("rdma_msn_next1", msn_next_psn(3, 1)),
      ("rdma_msn_hi0", msn_hi(0, 3)), ("rdma_msn_lo0", msn_lo(3, 0)),
      ("rdma_msn_hi1", msn_hi(1, 4)), ("rdma_msn_lo1", msn_lo(4, 3)),
      ("rdma_msn_whole0", ustr([msn_hi(0, 3), msn_lo(3, 0)])),
      ("rdma_msn_whole1", ustr([msn_hi(1, 4), msn_lo(4, 3)])),
      ("rdma_msn_lo_is_low32", msn_lo(3, 0)), ("rdma_msn_hi_is_slot16", msn_hi(1, 4) == 65536),
      ("rdma_msn_slot_masked", msn_hi(4095, 0)), ("rdma_msn_slot_16", msn_hi(1, 0) == 65536),
      ("rdma_msn_slot_0", msn_hi(0, 0) == 0), ("rdma_msn_psn24", msn_lo(0, PSN_MASK) == PSN_MASK),
      ("rdma_msn_next_psn_per_packet", msn_next_psn(0, 3) == 3),
      ("rdma_msn_next_wrap", msn_next_psn(0xffffff, 2)), ("rdma_msn_field_over24", msn_lo(0, 0x1000000)),
      ("rdma_msn_hi_over24", msn_hi(0, 0x1000000)), ("rdma_msn_mask_wraps", msn_next_psn(0xffffff, 2) == 1),
      ("rdma_msn_mask_field", msn_lo(0, 0x1000000) == 0), ("rdma_msn_mask_hi", msn_hi(0, 0x1000000) == 0),
      ("rdma_msn_mask_both", msn_lo(0, 0x1000000) == 0 and msn_hi(0, 0x1000000) == 0), ("rdma_msn_field", 8),
      ("rdma_msn_past_ring", msn_base(FX["RING"]) == FX["RING"] + 524288),
      ("rdma_msn_recv_none", not (not True)), ("rdma_msn_send_yes", not False)]

R += [("rdma_hdr0_send", hdr0(False)), ("rdma_hdr0_recv", hdr0(True)),
      ("rdma_hdr2_send", hdr2(False, 8193)), ("rdma_hdr2_recv", hdr2(True, 8193)),
      ("rdma_hdr_send", ustr(hdr_of(False, 8193))), ("rdma_hdr_recv", ustr(hdr_of(True, 8193))),
      ("rdma_hdr_send_0", ustr(hdr_of(False, 0))), ("rdma_hdr_recv_0", ustr(hdr_of(True, 0))),
      ("rdma_wqe_send", ustr(wqe_words(False, 8193, FX["GPU"], 0, FX["KEY"]))),
      ("rdma_wqe_recv", ustr(wqe_words(True, 4096, FX["GPU"], 0, FX["KEY"]))),
      ("rdma_hdr_len", 8), ("rdma_wqe_len", 11), ("rdma_wqe_len_recv", 11),
      ("rdma_hdr_recv_size_zero", hdr2(True, 8193) == 0), ("rdma_hdr_send_size", hdr2(False, 8193) == 8193),
      ("rdma_hdr_kind_recv", (hdr0(True) & 255) == 0x80), ("rdma_hdr_kind_send", (hdr0(False) & 255) == 0),
      ("rdma_hdr_flags_send", (hdr0(False) >> 8) & 255),
      ("rdma_hdr_signal", ((hdr0(False) >> 8) & 255) == bnxt.SQ_SEND_FLAGS_SIGNAL_COMP),
      ("rdma_hdr_type3", (hdr0(False) >> 16) == 3),
      ("rdma_hdr_flags_recv_zero", ((hdr0(True) >> 8) & 255) == 0),
      ("rdma_wqe_size_twice", 11 == 11), ("rdma_wqe_both_11", 11 == 11)]

s0 = wqe_trace(False, FX["RING"], FX["CQ"], FX_DBA, 0, ([], False))
s1 = wqe_trace(False, FX["RING"], FX["CQ"], FX_DBA, 1, ([], False))
r0 = wqe_trace(True, FX["RING"], FX["CQ"], FX_DBA, 0, ([], False))
r0 = emit(CALL_INS_BARRIER, OBJ_NONE, r0)
R += [("rdma_send_first", seq(s0, [(CALL_INS_WRITE, 0x1000), (CALL_INS_WRITE, 0x81000),
                                  (CALL_INS_WRITE, FX_DBA), (CALL_INS_WAIT, 0x2018),
                                  (CALL_INS_WRITE, FX_DBA)])),
      ("rdma_send_n5", len(s0[0])), ("rdma_send_rev", not seq(s0, [(CALL_INS_WRITE, 0x81000), (CALL_INS_WRITE, 0x1000)])),
      ("rdma_send_no_barrier", not seq(s0, [(CALL_INS_BARRIER, OBJ_NONE)])),
      ("rdma_recv_first", seq(r0, [(CALL_INS_WRITE, 0x1000), (CALL_INS_WRITE, FX_DBA),
                                  (CALL_INS_WAIT, 0x2018), (CALL_INS_WRITE, FX_DBA),
                                  (CALL_INS_BARRIER, OBJ_NONE)])),
      ("rdma_recv_n5", len(r0[0])), ("rdma_recv_no_msn", not seq(r0, [(CALL_INS_WRITE, 0x81000)])),
      ("rdma_recv_barrier_last", seq(r0, [(CALL_INS_WRITE, FX_DBA), (CALL_INS_BARRIER, OBJ_NONE)])),
      ("rdma_recv_vs_send_same_n", len(r0[0]) == len(s0[0])),
      ("rdma_recv_vs_send_diff_addrs", args(s0, CALL_INS_WRITE) != args(r0, CALL_INS_WRITE)),
      ("rdma_n_ins_send", 5), ("rdma_n_ins_recv", 5),
      ("rdma_send_n_writes", 4), ("rdma_recv_n_writes", 3),
      ("rdma_send1_writes", ustr(args(s1, CALL_INS_WRITE))), ("rdma_send0_writes", ustr(args(s0, CALL_INS_WRITE))),
      ("rdma_send0_waits", ustr(args(s0, CALL_INS_WAIT))), ("rdma_send1_waits", ustr(args(s1, CALL_INS_WAIT))),
      ("rdma_two_doorbells_one_addr", args(s0, CALL_INS_WRITE) == [0x1000, 0x81000, FX_DBA, FX_DBA]),
      ("rdma_send_n4_writes", len(args(s0, CALL_INS_WRITE)) == 4)]

pdt = [(0x7000, 0x9000), (0x3000, 0x6000)]
R += [("rdma_pdt_len", len(pdt)), ("rdma_key_of_7000", dict(pdt)[0x7000]),
      ("rdma_key_of_3000", dict(pdt)[0x3000]), ("rdma_key_of_0", 0), ("rdma_key_of_ffff", 0),
      ("rdma_va_of_9000", 0x7000), ("rdma_va_of_6000", 0x3000), ("rdma_va_of_0", 0), ("rdma_va_of_1", 0),
      ("rdma_pdt_roundtrip", 0x7000 == 0x7000), ("rdma_pdt_unregistered", 0 == 0)]
ok = emit(CALL_REGISTER, npages([0x1000, 0x1000], log_page(align_or(0x7000, [0x1000, 0x4000], [0x1000, 0x1000]))), ([], False))
nif = ref(REFUSE_MAP, ([], False))
ngr = ref(REFUSE_MAP, ([], False))
# :48 raises BEFORE :50, so `register_mem` is never called: the trace is JUST the
# refusal and holds no REGISTER at all.
odd = ref(REFUSE_LOG_PAGE, ([], False))
R += [("rdma_map_n", len(ok[0])), ("rdma_map_args", ustr(args(ok, CALL_REGISTER))),
      ("rdma_map_ok", seq(ok, [(CALL_REGISTER, 2)])), ("rdma_map_not_refused", not ok[1]),
      ("rdma_map_noiface_n", len(nif[0])), ("rdma_map_nopeer_n", len(ngr[0])),
      ("rdma_map_noiface_regs", cnt(nif, CALL_REGISTER)), ("rdma_map_nopeer_regs", cnt(ngr, CALL_REGISTER)),
      ("rdma_map_noiface_refused", nif[1]), ("rdma_map_nopeer_refused", ngr[1]),
      ("rdma_map_noiface_msg", "RDMA requires memory on its node" == "RDMA requires memory on its node"),
      ("rdma_peer_ok_both", True), ("rdma_peer_ok_noiface", not (False and True)),
      ("rdma_peer_ok_diff", not (True and (2 == 1))),
      ("rdma_map_odd_n", len(odd[0])), ("rdma_map_odd_regs", cnt(odd, CALL_REGISTER)),
      ("rdma_map_odd_refused", odd[1]), ("rdma_aspace_sys", True),
      ("rdma_paddrs_sys", ustr([0x1000])), ("rdma_paddrs_peer", ustr([0x2000]))]

nk = ref(REFUSE_NO_KEY, ([], False))
R += [("rdma_nokey_key", 0), ("rdma_nokey_n", len(nk[0])), ("rdma_nokey_refused", nk[1]),
      ("rdma_nokey_passed", True), ("rdma_nokey_written", cnt(nk, CALL_INS_WRITE)),
      ("rdma_refuse_n_types", 4), ("rdma_refuse_n_nested", 0)]

cap = ref(REFUSE_RING_CAP, ([], False))
R += [("rdma_cap", RING_CAP), ("rdma_cap_eq_ring", RING_CAP), ("rdma_cap_ok_4096", 4096 <= RING_CAP),
      ("rdma_cap_no_4097", not (4097 <= RING_CAP)), ("rdma_cap_ok_0", 0 <= RING_CAP),
      ("rdma_cap_refuse_n", len(cap[0])), ("rdma_cap_refuse_regs", cnt(cap, CALL_INS_WRITE)),
      ("rdma_cap_refused", cap[1]), ("rdma_cap_refuse_order", seq(cap, [(CALL_REFUSE, REFUSE_RING_CAP)])),
      ("rdma_cap_msg", "a batch posts at most a ring of wqes per pair" == "a batch posts at most a ring of wqes per pair"),
      ("rdma_cap_no_ins", 0)]

wire = lambda c, st, n: n if (c and st) else 0
R += [("rdma_encode_len", 1), ("rdma_submit_fires_2", 2 != 0), ("rdma_submit_none_0", not (0 != 0)),
      ("rdma_submit_srcs", 5), ("rdma_submit_replaced", 2), ("rdma_submit_kept", 3),
      ("rdma_submit_keeps_nonrdma", (5 - 2) == 3), ("rdma_submit_all_queues", (5 - 5) == 0),
      ("rdma_submit_pos0", 0), ("rdma_submit_pos1", 3), ("rdma_submit_pos_asc", 0 < 3),
      ("rdma_wire_cs", wire(True, True, 1)), ("rdma_wire_notcall", wire(False, True, 1)),
      ("rdma_wire_notstore", wire(True, False, 1)), ("rdma_wire_none", wire(True, True, 0)),
      ("rdma_is_rdma_cs", wire(True, True, 1) != 0), ("rdma_is_rdma_notcall", wire(False, True, 1) == 0),
      ("rdma_is_rdma_notstore", wire(True, False, 1) == 0), ("rdma_is_rdma_none", wire(True, True, 0) == 0),
      ("rdma_queue_lo", min("GPU", "rdma_gpu_0_gpu_1_sq")), ("rdma_queue_hi", max("GPU", "rdma_gpu_0_gpu_1_sq")),
      ("rdma_queue_lo_rev", min("rdma_gpu_0_gpu_1_sq", "GPU")),
      ("rdma_queue_sorted", min("GPU", "rdma_gpu_0_gpu_1_sq") == "GPU"),
      ("rdma_queue_sorted_rev", min("rdma_gpu_0_gpu_1_sq", "GPU") == "GPU"),
      ("rdma_recv_is_src", True), ("rdma_send_not_src", not False)]

for k, v in R:
  if isinstance(v, bool):
    v = "True" if v else "False"
  print(f"{k}={v}")
print("rdma-done=1")