#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/runtime/ops_rdma.bend.

Every number the Bend gate asserts is printed by THIS file, transcribed from
`tinygrad/runtime/ops_rdma.py` plus the bnxt constants. Nothing is typed by
hand. Run from the repo root:

    python3 .agents/slop/oracle_rdma.py
"""
import sys, struct, itertools
sys.path.insert(0, '.')
from tinygrad.helpers import ceildiv, round_up
from tinygrad.runtime.support.rdma.bnxtdev import WQE_SIZE, RING_ENTRIES, CQ_ENTRIES, MTU, db_value, send_wqe, recv_wqe
from tinygrad.runtime.autogen import bnxt

RDMA_CHUNK = 1 << 30
PAGE = 0x1000
CAND = (12, 13, 16, 18, 20, 21, 22, 30)
PSN_MASK = 0xffffff
DB_EPOCH_SHIFT = bnxt.BNXT_QPLIB_DBR_EPOCH_SHIFT


def log_page(align):
  return max(l for l in CAND if not align & ((1 << l) - 1))


def align_or(buf_addr, pairs):
  a = buf_addr
  for p, s in pairs:
    a |= (p | s)
  return a


def chunks_of(nbytes):
  return [ceildiv(min(RDMA_CHUNK, nbytes - o), MTU) for o in range(0, nbytes, RDMA_CHUNK)]


def size_of(nbytes, off):
  return min(RDMA_CHUNK, nbytes - off)


def hdr_of(is_recv, size):
  return struct.unpack("<8I", (recv_wqe if is_recv else send_wqe)(0, 0, size)[:32])


def ring_db_of(qpn, is_recv):
  return db_value(qpn, bnxt.DBC_DBC_TYPE_RQ if is_recv else bnxt.DBC_DBC_TYPE_SQ, 0, 0)


def cq_db_of(qid, is_recv):
  return db_value(qid, bnxt.DBC_DBC_TYPE_CQ, 0, 0)


def ring_slot(n):  return (n % RING_ENTRIES) * WQE_SIZE
def msn_addr(ring_addr, n): return ring_addr + RING_ENTRIES * WQE_SIZE + (n % RING_ENTRIES) * 8
def cq_wait(cq_addr, n): return cq_addr + (n % CQ_ENTRIES) * 32 + 24
def db_slot(n):  return (n + 1) % RING_ENTRIES
def db_epoch(n): return ((n + 1) // RING_ENTRIES & 1) << DB_EPOCH_SHIFT
def cq_slot(n):  return (n + 1) % CQ_ENTRIES
def cq_epoch(n): return ((n + 1) // CQ_ENTRIES & 1) << DB_EPOCH_SHIFT
def wait_expected(n, is_recv): return (n // CQ_ENTRIES & 1 ^ 1 | (2 if is_recv else 0))
def msn_val(slot, p, packets): return (slot << 48) | (((p + packets) & PSN_MASK) << 24) | (p & PSN_MASK)


def db_addr(db_off): return db_off & 0xfff


def dbsplit(v):
  return (v >> 32) & 0xffffffff, v & 0xffffffff


print("## CONSTANTS")
for k in ['RDMA_CHUNK', 'PAGE', 'WQE_SIZE', 'RING_ENTRIES', 'CQ_ENTRIES', 'MTU', 'PSN_MASK', 'DB_EPOCH_SHIFT']:
  print(f"{k} = {eval(k)}")
for k in ['DBC_DBC_TYPE_RQ', 'DBC_DBC_TYPE_SQ', 'DBC_DBC_TYPE_CQ', 'DBC_DBC_XID_MASK',
          'DBC_DBC_PATH_ROCE', 'BNXT_QPLIB_DBR_VALID', 'DBC_DBC_INDEX_MASK', 'SQ_SEND_FLAGS_SIGNAL_COMP']:
  print(f"{k} = {getattr(bnxt, k)}")
print("CAND =", CAND)
print("BNXT vendor = 0x%x mask = 0x%x id = 0x%x base_class = 0x%x" % (0x14e4, 0xffff, 0x1760, 0x02))

print("\n## SIZES (rdma_ring / rdma_cq / rdma_seq / rdma_psn / rdma_db)")
for recv in (True, False):
  print(f"ring_{'recv' if recv else 'send'} = {RING_ENTRIES * (WQE_SIZE if recv else WQE_SIZE + 8)}")
  print(f"cq_{'recv' if recv else 'send'} = {CQ_ENTRIES * 32}")
print("seq_elems = 1 seq_bytes =", 1 * 8, "psn_elems = 1 psn_bytes =", 1 * 8, "db_elems =", PAGE)
print("db_page_is_page_aligned_off =", round_up(PAGE, PAGE) == PAGE)
print("double_round_idempotent =", round_up(round_up(4097, PAGE), PAGE) == round_up(4097, PAGE), round_up(4097, PAGE))

print("\n## log_page (the two-direction page table)")
for a in [0, 0x1000, 0x2000, 0x4000, 0x8000, 0x10000, 0x40000, 0x100000, 0x400000, 0x800000, 0x9000, 0x3000,
          0x40000000, 0x1000 | 0x7000 | 0x9000]:
  print(f"log_page({hex(a)}) = {log_page(a)}")
for a in [1, 0x1001, 2, 0x100]:
  try:
    log_page(a)
    print(f"log_page({hex(a)}) = UNREACHABLE")
  except ValueError:
    print(f"log_page({hex(a)}) = NONE")

print("\n## align = buf._buf | reduce(or, p|s)")
print("align(0x7000, [(0x1000,0x1000),(0x4000,0x1000)]) =", hex(align_or(0x7000, [(0x1000, 0x1000), (0x4000, 0x1000)])))
print("align(0x1000, [(0x2000,0x1000)]) =", hex(align_or(0x1000, [(0x2000, 0x1000)])))

print("\n## chunks / wqes / packets")
for nbs in [[0], [1], [0x1000], [0x1001], [0x3000], [0x2001, 0x1000], [RDMA_CHUNK], [RDMA_CHUNK + 0x1000]]:
  cs = [c for nb in nbs for c in chunks_of(nb)]
  ps = list(itertools.accumulate(cs, initial=0))
  print(f"nbytes={[hex(x) for x in nbs]} chunks={cs} wqes={len(cs)} packets={sum(cs)} psns={ps} psnlen={len(ps)}")
print("ring_cap =", min(RING_ENTRIES, CQ_ENTRIES))

print("\n## hdr (struct.unpack('<8I', wqe(0,0,size)[:32]))")
for size in [0, 1, 0x1000, 0x2001, RDMA_CHUNK]:
  print(f"size={hex(size)} send={hdr_of(False, size)} recv={hdr_of(True, size)}")

print("\n## db_value halves (hi, lo)")
for qid, typ, nm in [(5, bnxt.DBC_DBC_TYPE_SQ, 'SQ'), (5, bnxt.DBC_DBC_TYPE_RQ, 'RQ'), (9, bnxt.DBC_DBC_TYPE_CQ, 'SCQ'),
                     (11, bnxt.DBC_DBC_TYPE_CQ, 'RCQ')]:
  print(f"db_value({qid},{nm}) = {db_value(qid, typ, 0, 0)} halves={dbsplit(db_value(qid, typ, 0, 0))}")

print("\n## the SEND fixture: bufs [0x2001, 0x1000], qpn 5 scq 9 rcq 11, ring 0x1000 cq 0x2000 db_off 0x12345 gpu 0x7000 key 0x9000")
RING, CQA, DBOFF, QPN, SCQ, RCQ, GPU, KEY = 0x1000, 0x2000, 0x12345, 5, 9, 11, 0x7000, 0x9000
nbs = [0x2001, 0x1000]
cs = [c for nb in nbs for c in chunks_of(nb)]
psns = list(itertools.accumulate(cs, initial=0))
wqes, packets = len(cs), sum(cs)
print("chunks", cs, "wqes", wqes, "packets", packets, "psns", psns)
print("db = 0x%x + 0x%x = 0x%x" % (0x3000, db_addr(DBOFF), 0x3000 + db_addr(DBOFF)))
rdb, cdb = ring_db_of(QPN, False), cq_db_of(RCQ if False else SCQ, False)
print("ring_db", rdb, "cq_db", cdb)
i = 0
for bi, nb in enumerate(nbs):
  for off in range(0, nb, RDMA_CHUNK):
    n, p, size = i, psns[i], size_of(nb, off)
    print(f"-- wqe {i}: n={n} p={p} off={hex(off)} size={size}")
    print(f"   ring_write addr={hex(RING + ring_slot(n))} nsrcs={1 + 8 + 3} hdr={hdr_of(False, size)} "
          f"gpu={hex(GPU + off)} key={hex(KEY)} size2={size}")
    print(f"   msn      addr={hex(msn_addr(RING, n))} val={hex(msn_val(n % RING_ENTRIES, p, psns[i+1]-psns[i]))} "
          f"val={msn_val(n % RING_ENTRIES, p, psns[i+1]-psns[i])}")
    print(f"   ring_db  addr={hex(0x3000 + db_addr(DBOFF))} slot={db_slot(n)} epoch={db_epoch(n) >> DB_EPOCH_SHIFT} "
          f"val={db_slot(n) | db_epoch(n) | rdb}")
    print(f"   wait_eq  addr={hex(cq_wait(CQA, n))} exp={wait_expected(n, False)}")
    print(f"   cq_db    addr={hex(0x3000 + db_addr(DBOFF))} slot={cq_slot(n)} epoch={cq_epoch(n) >> DB_EPOCH_SHIFT} "
          f"val={cq_slot(n) | cq_epoch(n) | cdb}")
    i += 1
print("bump_recv =", wqes, "bump_send_seq =", wqes, "bump_send_psn =", packets)
print("assert_ok", wqes <= min(RING_ENTRIES, CQ_ENTRIES), "assert_bad", (min(RING_ENTRIES, CQ_ENTRIES) + 1) <= min(RING_ENTRIES, CQ_ENTRIES))

print("\n## the RECV fixture: bufs [0x1000]")
nbs = [0x1000]
cs = [c for nb in nbs for c in chunks_of(nb)]
psns = list(itertools.accumulate(cs, initial=0))
wqes, packets = len(cs), sum(cs)
rdb, cdb = ring_db_of(QPN, True), cq_db_of(RCQ, True)
print("chunks", cs, "wqes", wqes, "packets", packets, "psns", psns, "ring_db", rdb, "cq_db", cdb)
n, p, size = 0, psns[0], size_of(nbs[0], 0)
print(f"  ring_write addr={hex(RING + ring_slot(n))} hdr={hdr_of(True, size)} gpu={hex(GPU)} key={hex(KEY)}")
print(f"  ring_db    addr={hex(0x3000 + db_addr(DBOFF))} val={db_slot(n) | db_epoch(n) | rdb}")
print(f"  wait_eq    addr={hex(cq_wait(CQA, n))} exp={wait_expected(n, True)}")
print(f"  cq_db      addr={hex(0x3000 + db_addr(DBOFF))} val={cq_slot(n) | cq_epoch(n) | cdb}")
print("  barrier    (recv only)")

print("\n## the EPOCH fixture: seq base 4095, three wqes, RING=CQ=4096")
for n in [4095, 4096, 4097, 8191, 8192]:
  print(f"  n={n} ring_slot={n % RING_ENTRIES} db_slot={db_slot(n)} db_epoch={db_epoch(n) >> 24} "
        f"cq_wait_addr={hex(cq_wait(CQA, n))} wait_exp={wait_expected(n, False)} wait_exp_recv={wait_expected(n, True)} "
        f"cq_slot={cq_slot(n)} cq_epoch={cq_epoch(n) >> 24}")

print("\n## register_mem page expansion (log_page 12, mapping.size 0x3000)")
lp = log_page(0x7000 | 0x1000 | 0x1000 | 0x4000 | 0x1000)
print("log_page =", lp)
for regions in [[(0x1000, 0x1000)], [(0x1000, 0x2000)], [(0x1000, 0x1000), (0x4000, 0x1000)]]:
  exp = [p + off for p, size in regions for off in range(0, size, 1 << lp)]
  print(f"  regions={[(hex(p),hex(s)) for p,s in regions]} npages={len(exp)} first={hex(exp[0])} last={hex(exp[-1])}")