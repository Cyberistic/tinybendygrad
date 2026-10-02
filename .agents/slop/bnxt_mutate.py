"""bnxtdev.bend -- THE MUTATION HARNESS.

    python3 .agents/slop/bnxt_mutate.py            # all
    python3 .agents/slop/bnxt_mutate.py 5 12 20    # by number
    python3 .agents/slop/bnxt_mutate.py --list

One edit per mutation, applied to a SCRATCH COPY IN THE SAME DIRECTORY (a
`$TMPDIR` copy cannot resolve the relative imports and produced 22 phantom
blind spots in one unit), the INTERPRETED lane run, and the WHOLE `name=value`
LINES diffed against a baseline captured immediately before the run.

WHOLE LINES, NEVER ROW NAMES. A name-comparing harness reported 0 moved rows for
all 30 mutations in one unit and 0 for all 68 in another.

A mutation that moves NOTHING is a BLIND SPOT and is reported with a reason. It
is never closed with a row that encodes the bug. A mutation that does not
compile is reported as such and is NOT counted as a blind spot -- it is a
different measurement.
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(REPO, 'tinybendygrad/runtime/support/rdma/bnxtdev.bend')
BEND = os.path.join(REPO, 'bin/bend')

# (label, find, replace, what it is testing)
MUT = [
 ("M1", "Bool.pick(U32, Bool.not(queue), U32.or(paddr_lo, PTU_PTE_VALID()),\n"
        "    Bool.pick(U32, pbl.is_last(i, n),",
        "Bool.pick(U32, Bool.not(queue), U32.or(paddr_lo, PTU_PTE_LAST()),\n"
        "    Bool.pick(U32, pbl.is_last(i, n),",
        ":29 -- the VALID bit becomes LAST, so no entry is ever VALID"),
 ("M2", "U32.or(paddr_lo, U32.or(PTU_PTE_VALID(), PTU_PTE_NEXT_TO_LAST())),",
        "U32.or(paddr_lo, U32.or(PTU_PTE_VALID(), PTU_PTE_LAST())),",
        ":30 -- NEXT_TO_LAST goes on the LAST entry"),
 ("M3", "def pbl.is_last(i: U32, n: U32) -> Bool: U32.is_eq(i, U32.sub(n, 1))",
        "def pbl.is_last(i: U32, n: U32) -> Bool: U32.is_eq(i, U32.sub(n, 2))",
        ":30 -- the last index is n-2, so LAST and NEXT_TO_LAST collide"),
 ("M4", "def db.hi(+xid: U32, typ: U32) -> U32:\n"
        "  U32.or(U32.or(U32.and(xid, DBC_DBC_XID_MASK()), U32.or(DBC_DBC_PATH_ROCE(), typ)),\n"
        "         BNXT_QPLIB_DBR_VALID())",
        "def db.hi(+xid: U32, typ: U32) -> U32:\n"
        "  U32.or(U32.or(U32.and(xid, DBC_DBC_XID_MASK()), U32.or(DBC_DBC_PATH_ROCE(), typ)),\n"
        "         DBC_DBC_TYPE_CQ())",
        ":14 -- BNXT_QPLIB_DBR_VALID replaced by DBC_DBC_TYPE_CQ"),
 ("M5", "U32.shln(epoch, U32.to_nat(BNXT_QPLIB_DBR_EPOCH_SHIFT()))",
        "U32.shln(epoch, U32.to_nat(SQ_MSN_SEARCH_START_IDX_SFT()))",
        ":15 -- the epoch rides at bit 48 instead of bit 24"),
 ("M6", "def msn.hi(slot: U32, nxt: U32) -> U32:\n"
        "  U32.or(U32.shln(slot, U32.to_nat(MSN_SLOT_HI_AT())), U32.shrn(nxt, 8n))",
        "def msn.hi(slot: U32, nxt: U32) -> U32:\n"
        "  U32.or(U32.shln(slot, U32.to_nat(MSN_NEXT_AT())), U32.shrn(nxt, 8n))",
        ":24 -- the slot sits at hi32 bit 24, i.e. at word bit 56"),
 ("M7", "def msn.next_of(+psn: U32, size: U32) -> U32:\n  U32.and(U32.add(psn, msn.pkts(size)), MSN_MASK())",
        "def msn.next_of(+psn: U32, size: U32) -> U32:\n  U32.add(psn, msn.pkts(size))",
        ":22 -- `nxt`'s `& 0xffffff` is dropped"),
 ("M8", "  U32.max(1, ceildiv(size, MTU()))", "  U32.max(0, ceildiv(size, MTU()))",
        ":22 -- `max(1, ...)` becomes `max(0, ...)`: a zero-length send does not advance the psn"),
 ("M9", "  Bool.pick(U32, U32.is_eq(n, 1), 0,\n    Bool.pick(U32, U32.is_eq(pbl.table_pages(n), 1), 1,",
        "  Bool.pick(U32, U32.is_eq(n, 1), 1,\n    Bool.pick(U32, U32.is_eq(pbl.table_pages(n), 1), 1,",
        ":28 -- the one-page shortcut allocates instead of returning"),
 ("M10", "Bool.pick(U32, U32.is_le(pbl.table_pages(n), PBL_MAX_PAGES()), 2, PBL_REFUSED())",
         "Bool.pick(U32, U32.is_lt(pbl.table_pages(n), PBL_MAX_PAGES()), 2, PBL_REFUSED())",
         ":34 -- `<=` becomes `<`, so exactly 512 pages stops being legal"),
 ("M11", "    U32.add(size, U32.mul(U32.mod(i, q.slots(size, stride)), AUX_ENTRY())),\n"
         "    q.read_off(i, size, stride))",
         "    U32.add(size, U32.mul(U32.mod(i, q.slots(size, stride)), stride)),\n"
         "    q.read_off(i, size, stride))",
         ":44 -- the aux arm uses the RING stride, so the msn table overlaps the ring"),
 ("M12", "    U32.add(size, U32.mul(U32.mod(i, q.slots(size, stride)), AUX_ENTRY())),\n"
         "    q.read_off(i, size, stride))",
         "    U32.mul(U32.mod(i, q.slots(size, stride)), AUX_ENTRY()),\n"
         "    q.read_off(i, size, stride))",
         ":44 -- the aux base loses the `size +`, so the msn table is at offset 0"),
 ("M13", "def q.size_of(+stride: U32, entries: U32) -> U32: U32.mul(q.entries_of(stride, entries), stride)",
         "def q.size_of(+stride: U32, entries: U32) -> U32: U32.add(U32.mul(q.entries_of(stride, entries), stride), AUX_ENTRY())",
         ":49 -- RE-INTRODUCES THE BUG THE GATE CAUGHT: `size` grows by the aux term"),
 ("M14", "def q.pbl_pages_of(alloc_bytes: U32) -> U32: ceildiv(alloc_bytes, PAGE())",
         "def q.pbl_pages_of(alloc_bytes: U32) -> U32: q.entries_of(AUX_ENTRY(), alloc_bytes)",
         ":31 -- the PBL level is a function of the ENTRY count rather than the pages"),
 ("M15", "  Bool.pick(U32, U32.is_eq(typ, BS_TYPE15()), c0,\n    U32.max(mne, U32.add(sum_splits, bs.extra_of(typ))))",
         "  Bool.pick(U32, U32.is_eq(typ, BS_TYPE15()), c0,\n    U32.add(mne, U32.add(sum_splits, bs.extra_of(typ))))",
         ":96 -- `max` becomes `+`, so the firmware's floor is ignored"),
 ("M16", "  Bool.pick(U32, U32.is_eq(typ, BS_TYPE15()), c0,\n    U32.max(mne, U32.add(sum_splits, bs.extra_of(typ))))",
         "  U32.max(mne, U32.add(sum_splits, bs.extra_of(typ)))",
         ":96 -- type 15's `counts[0]` REUSE is dropped and it computes its own"),
 ("M17", "      Bool.pick(U32, Bool.and(Bool.not(found), bs.inst_bit(ibm, ix)), ix, best))",
         "      Bool.pick(U32, bs.inst_bit(ibm, ix), ix, best))",
         ":98 -- the fold keeps the LAST hit, so the HIGHEST bit answers"),
 ("M18", "def bs.inst_bit(ibm: U32, i: U32) -> Bool: U32.is_ne(U32.and(U32.shrn(ibm, U32.to_nat(i)), 1), 0)",
         "def bs.inst_bit(ibm: U32, i: U32) -> Bool: U32.is_ne(U32.and(U32.shrn(ibm, U32.to_nat(i)), 2), 0)",
         ":98 -- the bitmap is masked by 2, not 1"),
 ("M19", "  Bool.pick(U32, U32.is_ge(off, mem_bytes), 0, ceildiv(U32.sub(mem_bytes, off), entry_size))",
         "  Bool.pick(U32, U32.is_ge(off, mem_bytes), 0, ceildiv(mem_bytes, entry_size))",
         ":102 -- the sweep count ignores the offset"),
 ("M20", "def rcfw.nq_arm_index(read_idx: U32) -> U32: U32.and(read_idx, CREQ_CONS_MASK())",
         "def rcfw.nq_arm_index(read_idx: U32) -> U32: read_idx",
         ":153 -- the CREQ consumer index is unmasked, so it is 32 bits and not 8"),
 ("M21", "           U32.is_lt(ret_event, CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION()))",
         "           U32.is_le(ret_event, CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION()))",
         ":154 -- `<` becomes `<=`, so the threshold event itself becomes a skip"),
 ("M22", "  Bool.and(U32.is_ne(resp_len, 0), U32.is_eq(seq_id, want))",
         "  U32.is_eq(seq_id, want)",
         ":86 -- the wait's `resp_len` conjunct is dropped"),
 ("M23", "rcfw.first_flag(rcfw.prod_of(write_idx), first)",
         "rcfw.first_flag(write_idx, first)",
         ":136-138 -- the FIRST flag is applied to the UNMASKED write index"),
 ("M24", "  U32.or(U32.shln(level, U32.to_nat(CMDQ_REGISTER_MR_LVL_SFT())),",
         "  U32.or(U32.shln(level, 2n),",
         ":186 -- `level << 2` \"fixes\" the zero LVL_SFT into the page-size field"),
 ("M25", "def wqe.hdr2(+recv: Bool, size: U32) -> U32: Bool.pick(U32, recv, 0, size)",
         "def wqe.hdr2(+recv: Bool, +size: U32) -> U32: Bool.pick(U32, recv, size, size)",
         ":19 -- the RECEIVE header gets the size in word 2, which its 29-byte pad covers"),
 ("M26", "    U32.or(U32.shln(WQE_KIND(), 16n), U32.shln(SQ_SEND_FLAGS_SIGNAL_COMP(), 8n)))",
         "    U32.or(U32.shln(RECV_KIND(), 16n), U32.shln(SQ_SEND_FLAGS_SIGNAL_COMP(), 8n)))",
         ":18 -- the INVERTED reading ops_rdma.bend's COMMENT gives, applied to the SEND arm"),
 ("M27", "  Bool.not(U32.is_eq(U32.and(toggle, CQ_BASE_TOGGLE()), U32.and(U32.div(cons, CQ_ENTRIES()), 1)))",
         "  U32.is_eq(U32.and(toggle, CQ_BASE_TOGGLE()), U32.and(U32.div(cons, CQ_ENTRIES()), 1))",
         ":25 -- the toggle test is inverted, so a ready entry is never ready"),
 ("M28", "def hwrm.seq_of(seq: U32) -> U32: U32.and(U32.add(seq, 1), SEQ_MASK())",
         "def hwrm.seq_of(seq: U32) -> U32: U32.add(seq, 1)",
         ":78 -- the `& 0xffff` is dropped, so the sequence counter never wraps"),
 ("M29", "def db_at(db_off: U32) -> U32: U32.div(db_off, 8)",
         "def db_at(db_off: U32) -> U32: U32.div(db_off, 4)",
         ":66/:164 -- the byte offset is divided by 4, i.e. a 32-bit doorbell bar"),
 ("M30", "def rcfw.trig_at() -> U32: U32.div(U32.add(RCFW_COMM_BASE_OFFSET(), RCFW_COMM_TRIG_OFFSET()), 4)",
         "def rcfw.trig_at() -> U32: U32.div(U32.add(RCFW_COMM_BASE_OFFSET(), RCFW_PF_VF_COMM_PROD_OFFSET()), 4)",
         ":142/:143 -- the trigger dword shares the producer's dword"),
 ("M31", "def qp.newstate(state: U32, network_type: U32) -> U32: U32.or(state, network_type)",
         "def qp.newstate(state: U32, network_type: U32) -> U32: state",
         ":204 -- `state | network_type` becomes `state`"),
 ("M32", "def cmdq_lvl() -> U32: U32.shln(CMDQ_LVL(), U32.to_nat(CMDQ_INIT_CMDQ_SIZE_SFT()))",
         "def cmdq_lvl() -> U32: CMDQ_LVL()",
         ":116 -- the CMDQ_SIZE shift is dropped"),
 ("M33", "  U32.or(RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID(), RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID())",
         "  RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID()",
         ":172 -- the receive ring shares the COMPLETION ring's enable word"),
 ("M34", "def src_mac_h(lo32: U32, sh: Nat) -> U32: U32.and(U32.shrn(lo32, sh), 65535)",
         "def src_mac_h(lo32: U32, sh: Nat) -> U32: U32.shrn(lo32, sh)",
         ":72 -- the `>3H` halves are unmasked, so the low one is the whole low word"),
 ("M35", "def l2_filter_flags() -> U32: CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX()",
         "def l2_filter_flags() -> U32: CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR()",
         ":178 -- the PATH_RX flag word becomes an enables bit"),
 ("M36", "# THE PAGE TABLES. `build_pbl`, :27-37, and it is THE TABLE MOST",
         "# THE PAGE TABLES. `build_pbl`, :27-37.  <-- CONTROL: a comment-only edit",
         ":27 -- CONTROL. A table with no row that CANNOT move is a table of coincidences."),
]


def rows_of(out):
    d = {}
    for line in out.split('\n'):
        if '=' in line:
            k, v = line.split('=', 1)
            d.setdefault(k, set()).add(v)
        else:
            d.setdefault('#' + line, set())
    return d


def run(src):
    p = SRC + '.mut'
    with open(p, 'w') as f:
        f.write(src)
    try:
        r = subprocess.run([BEND, p], capture_output=True, text=True, cwd=REPO)
        return r.stdout + r.stderr
    finally:
        os.unlink(p)


def main():
    if '--list' in sys.argv:
        for i, (lab, _f, _r, what) in enumerate(MUT, start=1):
            print(f"{i:2d} {lab:5s} {what}")
        return
    src = open(SRC).read()
    base_out = run(src)
    if 'done=1' not in base_out:
        print("BASELINE DID NOT RUN:\n" + base_out[:800])
        return
    base = rows_of(base_out)
    n = len(base)
    want = [int(a) for a in sys.argv[1:] if a.isdigit()] or list(range(1, len(MUT) + 1))
    for i in want:
        lab, find, repl, what = MUT[i - 1]
        cnt = src.count(find)
        if cnt != 1:
            print(f"{lab:5s} SKIP  anchor appears {cnt}x, expected 1")
            continue
        out = run(src.replace(find, repl, 1))
        if 'done=1' not in out:
            why = [l for l in out.split('\n') if l.startswith('- expected') or l.startswith('- message')]
            print(f"{lab:5s} NOCOMPILE  {what}")
            print(f"        {' '.join(w.split(':', 1)[1].strip()[:70] for w in why)}")
            continue
        cur = rows_of(out)
        m = sorted(k for k in set(base) | set(cur) if base.get(k, set()) != cur.get(k, set()))
        print(f"{lab:5s} {len(m):3d}  {what}")
        print(f"       {', '.join(m[:12])}{' ...' if len(m) > 12 else ''}")
    print(f"\nbaseline: {n} rows, {len(base)} distinct names")


if __name__ == '__main__':
    main()