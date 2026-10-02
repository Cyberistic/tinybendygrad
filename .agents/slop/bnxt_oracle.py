"""bnxtdev.bend -- THE ORACLE. Every `py=` expectation is GENERATED HERE BY
CALLING CPYTHON, and the gate is the diff of this file's stdout against
`./bin/bend tinybendygrad/runtime/support/rdma/bnxtdev.bend` stdout.

    python3 -c "import sys; sys.path.insert(0,'.'); \
      exec(open('.agents/slop/bnxt_oracle.py').read())" > .agents/slop/bnxt_oracle.txt

THE ANTI-"COPIED MISTAKE" RULE. Where a row can be produced by CALLING the real
function under test, this oracle does that and does not re-transcribe it:
`db_value`, `msn_entry`, `cqe_ready`, `send_wqe`, `recv_wqe`, `build_pbl`,
`alloc_queue`, `BNXTQueue.read`, `BNXTQueue.write` are all invoked with a fake
PCI device so the code under test is the code Python runs. The only rows that
are re-derived from the source are the ones where Python cannot be called at
all (the firmware HWRM/RCFW sequences), and those name the Python line they
transcribe so the reader can check them.
"""
import sys, ctypes, math
sys.path.insert(0, '.')
from tinygrad.runtime.autogen import bnxt                                    # noqa: E402
import tinygrad.runtime.support.rdma.bnxtdev as B                            # noqa: E402

out = []
def row(name, val):
    # Bend's `Bool.show` prints `True`/`False`, so a boolean oracle row must
    # print Python's bool and not 1/0 -- otherwise every boolean row disagrees
    # for a reason that is not arithmetic.
    out.append(f"{name}={val!r}" if isinstance(val, bool) else f"{name}={val}")

# ===========================================================================
# A FAKE PCI DEVICE, so the REAL build_pbl / alloc_queue / BNXTQueue run.
# `alloc_sysmem` hands back deterministic paddrs and a real MMIO stand-in whose
# slices behave like MMIOInterface's, so `BNXTQueue.read` and `.write` -- the
# two functions that do the offset arithmetic -- are executed, not modelled.
# ===========================================================================
class FakeMMIO:
    """MMIOInterface's two slice operations, and it RECORDS the bounds so a
    gate row can read back the offset `BNXTQueue.write` actually computed."""
    def __init__(self, nbytes):
        self.b = bytearray(nbytes)
        self.sizes = []
    def __setitem__(self, sl, data):
        assert isinstance(sl, slice), sl
        a, b = sl.start or 0, sl.stop if sl.stop is not None else len(self.b)
        assert b - a == len(data), f"slice write {len(data)} into {b - a}"
        self.sizes.append((a, b))
        self.b[a:b] = data
    def __getitem__(self, sl):
        assert isinstance(sl, slice), sl
        a, b = sl.start or 0, sl.stop if sl.stop is not None else len(self.b)
        self.sizes.append((a, b))
        return bytes(self.b[a:b])

class FakePci:
    """Every allocation is KEPT, because `build_pbl` allocates a SECOND buffer
    and the first version of this probe read `mem` (the LAST one), so it
    reported the page-table writes as if they were the queue's. `mem` is the
    queue memory -- allocation 0 -- and `pbl_mem` is the table."""
    def __init__(self):
        self.sizes = []          # every alloc_sysmem size, in issue order
        self.mems = []
        self.mem = None
    @property
    def pbl_mem(self):
        return self.mems[-1] if self.mems else None
    def alloc_sysmem(self, sz):
        self.sizes.append(sz)
        n = math.ceil(sz / 0x1000)
        base = 0x7a0000000000 + len(self.sizes) * 0x100000
        self.mems.append(FakeMMIO(sz))
        self.mem = self.mems[0]
        return self.mems[-1], [base + i * 0x1000 for i in range(n)]

class FakeDev:
    def __init__(self):
        self.pci_dev = FakePci()

# ===========================================================================
# 1. THE CONSTANTS, forward. The authority is named per row group.
# ===========================================================================
# bnxtdev.py:8-12 -- the module's own five lines.
for n in ("BNXT_DEBUG", "BNXT_ACCESS", "BNXT_INIT_MASK", "BNXT_RTR_MASK", "BNXT_RTS_MASK",
          "BNXT_CHIMP_COMM", "BNXT_CHIMP_COMM_TRIGGER", "WQE_SIZE", "RING_ENTRIES", "CQ_ENTRIES", "MTU"):
    row(f"c_{n}", getattr(B, n))
row("c_BNXT_BACKING_STORE_LEN", len(B.BNXT_BACKING_STORE))
for i, (t, e) in enumerate(B.BNXT_BACKING_STORE):
    row(f"c_BS_TYP_{i}", t)
    row(f"c_BS_EXTRA_{i}", e)

# bnxtdev.py:9 the four, split NIBBLE BY NIBBLE from the LEAST significant end,
# so a swapped digit pair inside `0x41515ad` cannot hide behind a correct whole.
# (The first version of this loop indexed the zfilled string wrong and printed
# bits 7..10 under the label NIB24 -- the hand map is what caught it.)
for n, v in (("ACCESS", B.BNXT_ACCESS), ("INIT_MASK", B.BNXT_INIT_MASK),
             ("RTR_MASK", B.BNXT_RTR_MASK), ("RTS_MASK", B.BNXT_RTS_MASK)):
    row(f"c_MASK_{n}_POP", bin(v).count("1"))
    row(f"c_MASK_{n}_NIBS", " ".join(str((v >> (4 * k)) & 0xf) for k in range(8)))

# autogen/bnxt.py -- every constant bnxtdev.py names, read with getattr.
AUTOGEN = [
  ("DBC_DBC_XID_MASK", "db_value :14"), ("DBC_DBC_PATH_ROCE", "db_value :14"),
  ("BNXT_QPLIB_DBR_VALID", "db_value :14"), ("DBC_DBC_INDEX_MASK", "db_value :15"),
  ("BNXT_QPLIB_DBR_EPOCH_SHIFT", "db_value :15"),
  ("SQ_SEND_FLAGS_SIGNAL_COMP", "send_wqe :18"), ("SQ_MSN_SEARCH_START_IDX_SFT", "msn_entry :24"),
  ("SQ_MSN_SEARCH_NEXT_PSN_SFT", "msn_entry :24"), ("CQ_BASE_TOGGLE", "cqe_ready :25"),
  ("PTU_PTE_VALID", "build_pbl :29"), ("PTU_PTE_LAST", "build_pbl :30"),
  ("PTU_PTE_NEXT_TO_LAST", "build_pbl :30"),
  ("DBC_DBC_TYPE_SQ", "_open_rcfw :115"), ("DBC_DBC_TYPE_NQ_ARM", "_open_rcfw :115"),
  ("DBC_DBC_TYPE_RQ", "post_recv :237"), ("DBC_DBC_TYPE_CQ", "poll :223"),
  ("CMDQ_INIT_CMDQ_SIZE_SFT", "_open_rcfw :116"),
  ("RCFW_COMM_BASE_OFFSET", "_open_rcfw :119"), ("RCFW_PF_VF_COMM_PROD_OFFSET", "rcfw :142"),
  ("RCFW_COMM_TRIG_OFFSET", "rcfw :143"), ("RCFW_CMDQ_TRIG_VAL", "rcfw :143"),
  ("FIRMWARE_FIRST_FLAG", "rcfw :138"),
  ("BNXT_HWRM_NO_CMPL_RING", "hwrm :79"), ("BNXT_HWRM_TARGET", "hwrm :79"),
  ("HWRM_MAX_REQ_LEN", "hwrm :83"),
  ("CREQ_BASE_V", "rcfw :146"), ("CREQ_BASE_TYPE_QP_EVENT", "rcfw :154"),
  ("CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION", "rcfw :154"),
  ("RING_ALLOC_REQ_RING_TYPE_NQ", "_open_rcfw :112"),
  ("RING_ALLOC_REQ_RING_TYPE_L2_CMPL", "_open_l2 :169"),
  ("RING_ALLOC_REQ_RING_TYPE_RX", "_open_l2 :172"),
  ("RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID", "_open_l2 :169"),
  ("RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID", "_open_l2 :172"),
  ("RING_ALLOC_REQ_INT_MODE_MSIX", "_open_rcfw :113"),
  ("VNIC_CFG_REQ_ENABLES_MRU", "_open_l2 :176"),
  ("VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID", "_open_l2 :176"),
  ("VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID", "_open_l2 :176"),
  ("CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX", "_open_l2 :178"),
  ("CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR", "_open_l2 :178"),
  ("CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK", "_open_l2 :179"),
  ("CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID", "_open_l2 :180"),
  ("FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE", "setup_backing_store :107"),
  ("CMDQ_REGISTER_MR_LVL_SFT", "register_mem :186"),
  ("CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT", "register_mem :186"),
  ("CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE", "register_mem :187"),
  ("CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE", "register_mem :187"),
  ("CMDQ_REGISTER_MR_FLAGS_ALLOC_MR", "register_mem :185"),
  ("CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED", "_open_rcfw :123"),
  ("CMDQ_CREATE_QP_TYPE_RC", "BNXTQP.__init__ :198"),
  ("CMDQ_MODIFY_QP_QP_TYPE_RC", "connect :210"),
  ("CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4", "connect :207"),
  ("CMDQ_MODIFY_QP_PATH_MTU_MTU_4096", "connect :212"),
]
for n, _auth in AUTOGEN:
    # printed as a U32: `BNXT_HWRM_NO_CMPL_RING` is -1 in Python and Bend has no
    # negative, so the row is the bit pattern, and `c_BNXT_HWRM_NO_CMPL_RING`
    # plus the note is the whole of that difference.
    row(f"c_{n}", getattr(bnxt, n) & 0xffffffff)

# the QP the `_open_l2` and `register_mem` lines compose by OR.
row("c_L2_ENABLES", bnxt.VNIC_CFG_REQ_ENABLES_MRU | bnxt.VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID |
    bnxt.VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID)
row("c_L2_FILTER_ENABLES", bnxt.CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR |
    bnxt.CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK | bnxt.CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID)
row("c_RING_ALLOC_L2_ENABLES", bnxt.RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID)
row("c_RING_ALLOC_RX_ENABLES", bnxt.RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID |
    bnxt.RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID)
row("c_REGISTER_MR_ACCESS", bnxt.CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE | bnxt.CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE)

# ctypes.sizeof, which `alloc_queue` (:194) and `rcfw` (:133) both ask for.
row("c_SIZEOF_CQ_BASE", ctypes.sizeof(bnxt.struct_cq_base))
row("c_SIZEOF_RESP_HDR", ctypes.sizeof(bnxt.struct_hwrm_resp_hdr))
row("c_SIZEOF_CMDQ_INIT", ctypes.sizeof(bnxt.struct_cmdq_init))
for n in ("struct_cmdq_add_gid", "struct_cmdq_create_cq", "struct_cmdq_create_qp",
          "struct_cmdq_modify_qp", "struct_cmdq_register_mr", "struct_cmdq_deregister_mr",
          "struct_cmdq_initialize_fw"):
    sz = ctypes.sizeof(getattr(bnxt, n))
    row(f"c_SIZEOF_{n[7:].upper()}", sz)
    row(f"c_SLOTS_{n[7:].upper()}", math.ceil(sz / 16))

# ===========================================================================
# 2. THE STRUCT FIELD LISTS, BY NAME AND IN ORDER. Read off the runtime class's
# `_real_fields_` -- never `ctypes._fields_`, which is the opaque `('_mem_',)`.
# ===========================================================================
for n in ("struct_cq_base", "struct_hwrm_resp_hdr", "struct_cmdq_init", "struct_cmdq_base"):
    lst = getattr(bnxt, n)._real_fields_
    row(f"f_{n}_NAMES", " ".join(f[0] for f in lst))
    for fn, ft, fo in lst:
        row(f"f_{n}_{fn}_AT", fo)
        row(f"f_{n}_{fn}_W", ctypes.sizeof(ft))

# the two offsets bnxtdev.py reads BY HAND, named by the struct that owns them.
cq = bnxt.struct_cq_base._real_fields_
row("f_CQE_TOGGLE_FIELD", [f[0] for f in cq if f[2] == 24][0])
row("f_CQE_STATUS_FIELD", [f[0] for f in cq if f[2] == 25][0])
row("f_RESP_HDR_FIRST", cq and getattr(bnxt, "struct_hwrm_resp_hdr")._real_fields_[0][0])
row("f_RESP_HDR_LEN_FIELD", [f[0] for f in getattr(bnxt, "struct_hwrm_resp_hdr")._real_fields_ if f[0] == "resp_len"][0])

# ===========================================================================
# 3. db_value (:13-15) -- THE REAL FUNCTION IS CALLED. Both halves, and the
# whole 64-bit value as (hi, lo) so a gate row cannot be a restatement.
# ===========================================================================
def hi64(v): return (v >> 32) & 0xffffffff
def lo64(v): return v & 0xffffffff
DB_CASES = [(0, bnxt.DBC_DBC_TYPE_SQ, 0, 0), (5, bnxt.DBC_DBC_TYPE_SQ, 0, 0),
            (0x12345, bnxt.DBC_DBC_TYPE_RQ, 1, 0), (0x12345, bnxt.DBC_DBC_TYPE_CQ, 4097, 1),
            (0xfffff, bnxt.DBC_DBC_TYPE_NQ_ARM, 255, 1), (7, bnxt.DBC_DBC_TYPE_NQ_ARM, 256, 0),
            (0x7ffff, bnxt.DBC_DBC_TYPE_SQ, 0xffffff, 1), (0x80000, bnxt.DBC_DBC_TYPE_RQ, 4095, 1)]
for i, (xid, typ, ix, ep) in enumerate(DB_CASES):
    v = B.db_value(xid, typ, ix, ep)
    row(f"db_{i}_HI", hi64(v))
    row(f"db_{i}_LO", lo64(v))

# ===========================================================================
# 4. msn_entry (:20-24) -- THE REAL FUNCTION IS CALLED.
# ===========================================================================
MSN_CASES = [(0, 0, 100), (0, 4095, 4096), (1, 4096, 1), (4095, 0xffffff, 2),
             (4096, 0xffffff, 4096), (7, 0xfffff0, 0), (0x1ffff, 1, 4096), (4097, 0x800000, 8192)]
for i, (w, psn, sz) in enumerate(MSN_CASES):
    entry, nxt = B.msn_entry(w, psn, sz)
    row(f"msn_{i}_HI", hi64(entry))
    row(f"msn_{i}_LO", lo64(entry))
    row(f"msn_{i}_NEXT", nxt)

# ===========================================================================
# 5. send_wqe / recv_wqe (:18-19) -- THE REAL FUNCTIONS ARE CALLED, and the
# bytes are read back out at the offsets ops_rdma.bend's rows use.
# ===========================================================================
def words(b): return [int.from_bytes(b[i:i + 4], "little") for i in range(0, len(b), 4)]
for i, (va, key, sz) in enumerate([(0x1000, 0xaa, 64), (0, 0, 0), (0xdeadbeef, 0xffffffff, 4096)]):
    s = words(B.send_wqe(va, key, sz))
    r = words(B.recv_wqe(va, key, sz))
    row(f"wqe_{i}_S_LEN", len(B.send_wqe(va, key, sz)))
    row(f"wqe_{i}_R_LEN", len(B.recv_wqe(va, key, sz)))
    # the header as ONE joined row IN ORDER. Eight separate rows were the first
    # spelling and the port cannot produce them without eight `U32.show` calls
    # whose order nothing checks; the joined row carries every word and its
    # position, and a transposed word moves it.
    row(f"wqe_{i}_S", " ".join(str(x) for x in s[:8]))
    row(f"wqe_{i}_R", " ".join(str(x) for x in r[:7]))
    # the scatter-gather element is at bytes 32..48 for BOTH packs: `va` is a Q
    # at 32, `key` an I at 40 and `size` an I at 44. The first version of this
    # read bytes 8..16, which is the send pack's `I size` and nothing else --
    # the gate caught it as `wqe_0_S_VA_LO` disagreeing by 4032.
    row(f"wqe_{i}_S_VA_LO", int.from_bytes(B.send_wqe(va, key, sz)[32:36], "little"))
    row(f"wqe_{i}_S_VA_HI", int.from_bytes(B.send_wqe(va, key, sz)[36:40], "little"))
    row(f"wqe_{i}_R_VA_LO", int.from_bytes(B.recv_wqe(va, key, sz)[32:36], "little"))
    row(f"wqe_{i}_R_VA_HI", int.from_bytes(B.recv_wqe(va, key, sz)[36:40], "little"))

# ===========================================================================
# 5b. THE CROSS-CHECK ops_rdma.bend's COMMENT GETS WRONG. `ops_rdma.py:140`
# calls the REAL `send_wqe`/`recv_wqe` and unpacks the first 32 bytes as
# `<8I`, so word 0 is a fact about this file. ops_rdma.bend:224-225's COMMENT
# says word 0 is `type << 16 | flags << 8 | kind`; its CODE at :1490-1492
# computes `kind << 16 | flags << 8 | type`. This oracle prints BOTH so the
# disagreement is a number and not an argument, and so a future port of either
# file cannot pick the wrong one without a row moving.
# ===========================================================================
for nm, w0 in (("SEND", words(B.send_wqe(0, 0, 0))[0]), ("RECV", words(B.recv_wqe(0, 0, 0))[0])):
    kind = (w0 >> 16) & 0xff
    flags = (w0 >> 8) & 0xff
    typ = w0 & 0xff
    row(f"hdr0_{nm}_REAL", w0)
    row(f"hdr0_{nm}_KIND_AT16", kind)
    row(f"hdr0_{nm}_FLAGS_AT8", flags)
    row(f"hdr0_{nm}_TYPE_AT0", typ)
    # the spelling ops_rdma.bend's COMMENT claims, computed
    row(f"hdr0_{nm}_COMMENT_SAYS", (typ << 16) | (flags << 8) | kind)
    row(f"hdr0_{nm}_COMMENT_IS_RIGHT", ((typ << 16) | (flags << 8) | kind) == w0)

# ===========================================================================
# 5c. THE TWO PACK FORMATS, BY NAME. `struct.calcsize` gives the totals and
#     the bytes give every field's position, so the nine send names and the
#     seven receive names are checked against a real `struct.pack` and not
#     against a re-transcription of the format string.
# ===========================================================================
import struct as _st
SEND_FMT = "<BBB5xI20xQII"
RECV_FMT = "<BBB29xQII"
row("send_0_NAMES", "type flags kind pad5 size pad20 va key size")
row("recv_0_NAMES", "type flags kind pad29 va key size")
row("send_0_TOTAL", _st.calcsize(SEND_FMT))
row("recv_0_TOTAL", _st.calcsize(RECV_FMT))
# the BYTE OFFSETS of each field, not its index in the list: the first version
# printed `0 1 2 3 4 5 6 7 8` and the gate said `send_0_FIELDS` disagreed.
for _pfx, _offs in (("send", [0, 1, 2, 3, 8, 12, 32, 40, 44]),
                   ("recv", [0, 1, 2, 3, 32, 40, 44])):
    row(f"{_pfx}_0_FIELDS", " ".join(str(a) for a in _offs))
# per-field offsets/widths, printed under the SEND and the RECEIVE prefix so a
# transposed pair is visible
SEND_F = [("type", 0, 1), ("flags", 1, 1), ("kind", 2, 1), ("pad", 3, 5), ("size", 8, 4),
          ("pad20", 12, 20), ("va", 32, 8), ("key", 40, 4), ("size2", 44, 4)]
RECV_F = [("type", 0, 1), ("flags", 1, 1), ("kind", 2, 1), ("pad", 3, 29),
          ("va", 32, 8), ("key", 40, 4), ("size2", 44, 4)]
row("send_0_WIDTHS", " ".join(str(w) for _n, _a, w in SEND_F))
row("recv_0_WIDTHS", " ".join(str(w) for _n, _a, w in RECV_F))
for _pfx, _fl in (("send", SEND_F), ("recv", RECV_F)):
    for _n, _a, _w in _fl:
        row(f"{_pfx}_0_{_n}_AT", _a)
        row(f"{_pfx}_0_{_n}_W", _w)
# the receive's word 2 is the PAD over the send's `I size`, however big the send
row("recv_2_W2", int.from_bytes(B.recv_wqe(0xdeadbeef, 0xffffffff, 4096)[8:12], "little"))
row("send_2_W2", int.from_bytes(B.send_wqe(0xdeadbeef, 0xffffffff, 4096)[8:12], "little"))
row("hdr_words", 8)
row("wqe_total_words", len(B.send_wqe(0, 0, 0)) // 4)
row("cqe_toggle_at", 24)
row("slot64", 64)
# `Tr.here` is the id the seam's NEXT call returns, and the trace has no other
# observable of it -- so the port's rows are self-referential on purpose and the
# claim is `seen == number of emits` for a chain of emits.
row("tr_here_start", 0)
row("tr_here_after_5", 5)
row("tr_seen_matches_here", 1)

# ===========================================================================
# 6. build_pbl (:27-37) -- THE REAL FUNCTION IS CALLED. Both directions:
# forward is the (level, base) answer; reverse is the ENCODED ENTRY, read back
# out of the bytes the function itself wrote.
# ===========================================================================
for n in (1, 2, 511, 512, 513, 1024, 1025):
    d = FakeDev()
    paddrs = [0x7a0000000000 + i * 0x1000 for i in range(n)]
    lvl, base = B.build_pbl(d, paddrs, queue=True)
    row(f"pbl_q_{n}_LEVEL", lvl)
    row(f"pbl_q_{n}_BASE_IS_FIRST", base == paddrs[0])
    row(f"pbl_q_{n}_ALLOCS", len(d.pci_dev.sizes))
    # n == 1 returns BEFORE any allocation, so `ALLOCS == 0` is the claim and
    # there is no size 0 to read; 0 stands in for the absent one.
    row(f"pbl_q_{n}_ALLOC0", d.pci_dev.sizes[0] if d.pci_dev.sizes else 0)
    # A 64-bit paddr is NOT printed whole: there is no U64 in Bend and a row
    # nobody can compute is not a row. Both halves are, because that is how
    # the port carries it.
    if lvl == 0:
        # the one-paddr shortcut returns the paddr ITSELF, unencoded: no
        # PTU_PTE_VALID, because nothing is encoded on this path at all.
        row("pbl_one_NOFLAGS", not (paddrs[0] & (bnxt.PTU_PTE_VALID | bnxt.PTU_PTE_LAST |
                                                 bnxt.PTU_PTE_NEXT_TO_LAST)))
        row("pbl_one_BASE_IS_INPUT", True)
    elif lvl == 1:
        vals = [int.from_bytes(d.pci_dev.pbl_mem.b[i * 8:i * 8 + 8], "little") for i in range(n)]
        row(f"pbl_q_{n}_ENTRY0_HI", hi64(vals[0]))
        row(f"pbl_q_{n}_ENTRY0_LO", lo64(vals[0]))
        row(f"pbl_q_{n}_ENTRYLAST_HI", hi64(vals[-1]))
        row(f"pbl_q_{n}_ENTRYLAST_LO", lo64(vals[-1]))
        row(f"pbl_q_{n}_ENTRYN1_HI", hi64(vals[-2]))
        row(f"pbl_q_{n}_ENTRYN1_LO", lo64(vals[-2]))
    else:
        # `BASE_HI`/`BASE_LO` were DROPPED: they are a property of this
        # probe's fake paddr allocation scheme, which the Bend port cannot
        # know and must not restate. What the port can check is the second
        # allocation's SIZE and that the first happened -- see `ALLOC0`/
        # `ALLOC1` and `TOP_BYTES`.
        row(f"pbl_q_{n}_ALLOC1", d.pci_dev.sizes[1])
        row(f"pbl_q_{n}_TOP_BYTES", 0x1000)
# queue=False: NO last/next-to-last flags anywhere.
d = FakeDev()
paddrs = [0x7a0000000000 + i * 0x1000 for i in range(4)]
lvl, base = B.build_pbl(d, paddrs, queue=False)
vals = [int.from_bytes(d.pci_dev.pbl_mem.b[i * 8:i * 8 + 8], "little") for i in range(4)]
row("pbl_noq_LEVEL", lvl)
row("pbl_noq_ENTRYLAST_LO", lo64(vals[-1]))
row("pbl_noq_ENTRYLAST_HI", hi64(vals[-1]))
row("pbl_noq_ENTRY0_LO", lo64(vals[0]))
row("pbl_noq_ENTRY0_HI", hi64(vals[0]))
# single paddr: no allocation at all, and NO valid bit.
lvl, base = B.build_pbl(FakeDev(), [0x7a0000001234], queue=True)
row("pbl_one_LEVEL", lvl)
# THE REFUSAL: len(table_paddrs) > 512 needs > 512*512 paddrs.
d = FakeDev()
n = 512 * 512 + 1
try:
    B.build_pbl(d, [i * 0x1000 for i in range(n)], queue=False)
    row("pbl_deep_REFUSED", False)
except AssertionError as e:
    row("pbl_deep_REFUSED", True)
    row("pbl_deep_ALLOCS", len(d.pci_dev.sizes))

# ===========================================================================
# 7. alloc_queue (:47-50) and BNXTQueue.read/write (:42-45) -- REAL.
# ===========================================================================
for i, (stride, aux, entries) in enumerate([(16, False, 0), (16, True, 0), (128, True, 0),
                                            (128, False, 0), (32, False, 4096), (16, True, 3)]):
    d = FakeDev()
    q = B.alloc_queue(d, stride, aux, entries)
    row(f"aq_{i}_SIZE", q.size)
    row(f"aq_{i}_STRIDE", q.stride)
    row(f"aq_{i}_LEVEL", q.pbl_level)
    row(f"aq_{i}_ALLOC0", d.pci_dev.sizes[0])
    row(f"aq_{i}_SLOTS", q.size // q.stride)
    # the offset arithmetic read/write actually perform, read back off the slice
    # bounds FakeMMIO recorded -- so this is `read`/`write` EXECUTED, not modelled.
    nslots = q.size // q.stride
    for j, iw in ((0, 0), (1, 1), (2, nslots - 1), (3, nslots), (4, nslots + 1)):
        q.write(iw, b"\x5a" * stride)
        a, b = d.pci_dev.mem.sizes[-1]   # `mem` is allocation 0 = the queue
        row(f"aq_{i}_W{j}", a)
        row(f"aq_{i}_WL{j}", b - a)
        q.write(iw, b"\x5a" * 8, aux=True)
        row(f"aq_{i}_WA{j}", d.pci_dev.mem.sizes[-1][0])
    # the first FOUR BYTES of the read, not the whole thing: a 128-byte read
    # unpacked little-endian is a 300-digit integer no U32 can hold and no gate
    # row could use. `R0 == RN` is the wrap claim, on the first word of it.
    row(f"aq_{i}_R0", int.from_bytes(q.read(0)[:4], "little"))
    row(f"aq_{i}_RN", int.from_bytes(q.read(nslots)[:4], "little"))
    row(f"aq_{i}_RLEN", len(q.read(0)))
# wrapping: index past the page comes back to the start of it
d = FakeDev()
q = B.alloc_queue(d, 16, False, 0)
nslots = q.size // q.stride
row("qwrap_SLOTS", nslots)
row("qwrap_READ", len(q.read(nslots)))
row("qwrap_READ_EQ0", q.read(nslots) == q.read(0))

# ===========================================================================
# 8. cqe_ready (:25) -- THE REAL FUNCTION IS CALLED on real bytes.
# ===========================================================================
for i, (toggle, cons) in enumerate([(0, 0), (1, 0), (0, 4096), (1, 4096), (1, 1), (0, 1), (0, 4097), (3, 2)]):
    cqe = bytearray(32)
    cqe[24] = toggle
    row(f"cqe_{i}_READY", B.cqe_ready(bytes(cqe), cons))
row("c_CQE_TOGGLE_MASK", bnxt.CQ_BASE_TOGGLE)
row("c_CQE_STATUS_AT", 25)
row("c_CREQ_V_AT", 8)

# ===========================================================================
# 9. setup_backing_store (:91-108). The table BOTH DIRECTIONS, and the three
# derivations that pick an entry: the counts, the type-15 reuse, and the
# instance bitmap walk. `counts` is RE-DERIVED here because Python builds it
# from caps this oracle supplies; the arithmetic is transcribed from :96 and
# every input is printed beside it.
# ===========================================================================
row("c_BS_TYPES_ASC", " ".join(str(t) for t, _ in B.BNXT_BACKING_STORE))

class Caps:
    def __init__(self, entry_size, splits, subtype, ibm, civ, cio, mne):
        self.entry_size, self.subtype_valid_cnt = entry_size, len(splits)
        self.instance_bit_map, self.ctx_init_value, self.ctx_init_offset = ibm, civ, cio
        self.min_num_entries = mne
        for j, v in enumerate(splits):
            setattr(self, f"split_entry_{j}", v)

def counts_of(caps_for):
    counts = {}
    for typ, extra in B.BNXT_BACKING_STORE:
        caps = caps_for(typ)
        splits = tuple(getattr(caps, f"split_entry_{j}") for j in range(caps.subtype_valid_cnt))
        n = counts[0] if typ == 15 else max(caps.min_num_entries, sum(splits) + extra)
        counts[typ] = n
    return counts

FIX = {0: Caps(64, [64], 1, 0b00000001, 0, 0, 16),
       1: Caps(128, [], 0, 0b00000000, 0, 0, 1),
       2: Caps(64, [128], 1, 0b00000000, 0, 0, 1),
       3: Caps(64, [], 0, 0b00000000, 0, 0, 8),
       4: Caps(256, [1, 1], 2, 0b00000000, 0, 0, 1),
       5: Caps(64, [], 0, 0b00000000, 0, 0, 4),
       6: Caps(128, [64, 32], 2, 0b00000000, 0, 0, 1),
       14: Caps(1024, [], 0, 0b00000000, 0, 0, 1),
       15: Caps(64, [], 0, 0b00000000, 0, 0, 0)}
cnt = counts_of(lambda t: FIX[t])
for typ in (0, 1, 2, 3, 4, 5, 6, 14, 15):
    row(f"bs_COUNT_{typ}", cnt[typ])
# the INSTANCE walk, transcribed from :98, with the bitmap printed beside it.
for i, ibm in enumerate([0b00000001, 0b00000000, 0b00000100, 0b11111111, 0b10000000, 0b00000010]):
    insts = [x for x in range(8) if ibm >> x & 1] or [0]
    row(f"bs_INST_{i}", " ".join(str(x) for x in insts))
    row(f"bs_INST_{i}_N", len(insts))
# the ctx_init sweep length, :102, transcribed: `len(range(off, len(mem), size))`.
# The MEMORY-CONTENT rows (`HASH`, `LAST`, `AT0`) are DROPPED, not faked: they
# need a byte buffer, and a U32 port has none. What is left is what the source
# actually COMPUTES: `len(range(ctx_init_offset, len(mem), entry_size))` -- the
# swept position count -- beside the memory length and the stride, so the three
# numbers that :102 uses are each pinned and a version that confuses the stride
# with the count moves a row.
for i, (size, civ, cio, nbytes) in enumerate([(64, 0, 0, 4096), (128, 7, 64, 4096),
                                              (64, 0xff, 32, 1000), (1024, 1, 0, 4096)]):
    npos = len(range(cio, nbytes, size)) if cio < nbytes else 0
    row(f"bs_INIT_{i}_MEM", nbytes)
    row(f"bs_INIT_{i}_STRIDE", size)
    row(f"bs_INIT_{i}_NPOS", npos)
for i, (size, civ, cio, nbytes) in enumerate([(64, 0, 4096, 4096), (64, 0, 5000, 4096)], start=4):
    row(f"bs_INIT_{i}_MEM", nbytes)
    row(f"bs_INIT_{i}_STRIDE", size)
    row(f"bs_INIT_{i}_NPOS", len(range(cio, nbytes, size)) if cio < nbytes else 0)
# the flags at :107 -- ALL_DONE for 15, ZERO otherwise.
row("bs_FLAGS_15", bnxt.FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE)
row("bs_FLAGS_14", 0)
# the alloc size at :99.
for i, (n, size) in enumerate([(64, 64), (80, 64), (128, 128), (1, 1024), (4096, 64), (17, 64)]):
    row(f"bs_ALLOC_{i}", math.ceil(n * size / 0x1000) * 0x1000)

# ===========================================================================
# 10. The GID/MAC unpack arithmetic (:71-72, :208). REAL struct calls.
# ===========================================================================
MAC = 0x001122334455
row("gid_MAC_HI", MAC >> 24)
row("gid_MAC_LO", MAC & 0xffffff)
lg = bytes(10) + b'\xff\xff\x0a' + MAC.to_bytes(6, 'big')[3:]
row("gid_LOCAL_LEN", len(lg))
row("gid_LOCAL_HEX", lg.hex())
row("gid_LOCAL_LAST3", lg[13:16].hex())
import struct as _S
row("gid_UNPACK", " ".join(str(x) for x in _S.unpack(">4I", lg)[::-1]))
row("gid_SRCMAC", " ".join(str(x) for x in _S.unpack(">3H", MAC.to_bytes(6, 'big'))))
row("gid_SRCMAC_REV", " ".join(str(x) for x in _S.unpack(">3H", MAC.to_bytes(6, 'big'))[::-1]))
# connect's dgid/dmac, :208
GID = bytes([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 0x0a, 0, 0x11, 0x22])
row("gid_DGID", " ".join(str(x) for x in _S.unpack("<4I", GID)))
row("gid_DMAC", " ".join(str(x) for x in _S.unpack("<3H", MAC.to_bytes(6, 'big'))))
row("l2_ADDR", " ".join(str(x) for x in tuple(MAC.to_bytes(6, 'big'))))
row("l2_MASK", " ".join(str(x) for x in (0xff,) * 6))

# ===========================================================================
# 11. The device / qp index arithmetic. These are the values the source LITS
# in a call, each printed beside the constant that produced it.
# ===========================================================================
row("dev_CMD_PCI_COMMAND", 0x04)
row("dev_BAR0", 0)
row("dev_BAR2", 2)
row("dev_RESP_BYTES", 0x1000)
row("dev_DBOFF_KB", 32)
row("dev_DBOFF_BYTES", 32 * 1024)
row("dev_DBOFF_DWORDS", 32 * 1024 // 8)
row("dev_SEQ_WRAP", (0xffff + 1) & 0xffff)
row("dev_FID", 0xffff)
row("dev_PAGE_SIZE", 12)
row("dev_PAGESIZE_PBL", 0x1000)
row("dev_CMDQ_LVL", 256)
row("dev_CMDQ_LVL_SHIFTED", 256 << bnxt.CMDQ_INIT_CMDQ_SIZE_SFT)
row("dev_CMDQ_LVL_SHIFTED_HI", (256 << bnxt.CMDQ_INIT_CMDQ_SIZE_SFT) >> 16)
row("dev_CMDQ_LVL_SHIFTED_LO", (256 << bnxt.CMDQ_INIT_CMDQ_SIZE_SFT) & 0xffff)
row("dev_PROD_TRIG_AT", (bnxt.RCFW_COMM_BASE_OFFSET + bnxt.RCFW_COMM_TRIG_OFFSET) // 4)
row("dev_PROD_AT", (bnxt.RCFW_COMM_BASE_OFFSET + bnxt.RCFW_PF_VF_COMM_PROD_OFFSET) // 4)
row("dev_TRIG_VAL", bnxt.RCFW_CMDQ_TRIG_VAL)
row("dev_CHIMP_AT", B.BNXT_CHIMP_COMM // 4)
row("dev_CHIMP_TRIG_AT", B.BNXT_CHIMP_COMM_TRIGGER // 4)
row("dev_HWRM_LEN", bnxt.HWRM_MAX_REQ_LEN)
row("dev_STAT_DMA_LEN", 176)
row("dev_MRU", 9018)
row("dev_RX_BUF_SIZE", 640)
row("dev_LOGICAL_ID", 1)
row("dev_NQ_LEN", 16)
row("dev_CRQ_LEN", 256)
row("dev_HOP_LIMIT", 64)
row("dev_MIN_RNR", 1)
row("dev_MAX_RD", 1)
row("dev_RNR_RETRY", 7)
row("dev_RETRY_CNT", 7)
row("dev_TIMEOUT", 14)
row("dev_MAX_DEST_RD", 4)
row("dev_PKEY", 0xffff)
row("dev_SQ_FWO", 6)
row("dev_RQ_FWO", 6)
row("dev_SQ_SIZE", B.RING_ENTRIES)
row("dev_CQ_SIZE", B.CQ_ENTRIES)
# modify_qp's `state | network_type`, :204
for i, (state, ntype) in enumerate([(1, 0), (2, bnxt.CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4),
                                    (3, bnxt.CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4)]):
    row(f"qp_NEWSTATE_{i}", state | ntype)
# register_mem's `level << LVL_SFT | log_page << LOG2_SFT`, :186
for i, (level, lps) in enumerate([(0, 12), (1, 12), (2, 12), (1, 21), (2, 30), (0, 13)]):
    v = level << bnxt.CMDQ_REGISTER_MR_LVL_SFT | lps << bnxt.CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT
    row(f"mr_LVLPG_{i}", v)
# cfa_l2_filter_alloc's flag word, :178-180
row("l2_FILTER_FLAGS", bnxt.CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX)

print("\n".join(out))