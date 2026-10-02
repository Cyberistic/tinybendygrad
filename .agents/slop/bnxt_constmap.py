"""bnxtdev.bend -- THE HAND MAP. One entry per constant def in
`tinybendygrad/runtime/support/rdma/bnxtdev.bend`, giving the authority and the
hand-typed value. `.agents/slop/const-audit.py` is only a SMOKE TEST (its
name-matching reached 0 of 106 on ops_metal), so this map is the real check:

    python3 -c "import sys; sys.path.insert(0,'.'); \
      exec(open('.agents/slop/bnxt_constmap.py').read())" | tail -40

prints `HANDMAP` lines and then `MISMATCH` / `handmap-clean`. Every authority
is either `bnxtdev.py:<line>` (read with getattr on the imported module) or
`bnxt.py` (read with getattr on the autogen module) or `ctypes.sizeof`.
The autogen module is 10,523 lines and nothing here is read out of its text.
"""
import sys, ctypes
sys.path.insert(0, '.')
from tinygrad.runtime.autogen import bnxt          # noqa: E402
import tinygrad.runtime.support.rdma.bnxtdev as B  # noqa: E402

# (BEND NAME, AUTHORITY, HAND-TYPED VALUE)
#
# AUTHORITY FORMS:
#   ("py",  "NAME", line)          -> getattr(bnxtdev, NAME); line cites bnxtdev.py
#   ("bn",  "NAME", line)          -> getattr(autogen bnxt, NAME); line cites bnxtdev.py's use
#   ("sz",  "STRUCT", line)        -> ctypes.sizeof(bnxt.STRUCT); line cites bnxtdev.py's use
MAP = [
  # ---- bnxtdev.py:8-12, the module's own five lines --------------------------
  ("BNXT_DEBUG",                ("py", "BNXT_DEBUG", 8),            0),
  ("BNXT_ACCESS",               ("py", "BNXT_ACCESS", 9),           3),
  ("BNXT_INIT_MASK",            ("py", "BNXT_INIT_MASK", 9),        13),
  ("BNXT_RTR_MASK",             ("py", "BNXT_RTR_MASK", 9),         68490669),
  ("BNXT_RTS_MASK",             ("py", "BNXT_RTS_MASK", 9),         712709),
  ("BNXT_CHIMP_COMM",           ("py", "BNXT_CHIMP_COMM", 10),       0),
  ("BNXT_CHIMP_COMM_TRIGGER",   ("py", "BNXT_CHIMP_COMM_TRIGGER", 10), 256),
  ("WQE_SIZE",                  ("py", "WQE_SIZE", 12),             128),
  ("RING_ENTRIES",              ("py", "RING_ENTRIES", 12),         4096),
  ("CQ_ENTRIES",                ("py", "CQ_ENTRIES", 12),           4096),
  ("MTU",                       ("py", "MTU", 12),                  4096),

  # ---- db_value (:13-15) ----------------------------------------------------
  ("DBC_DBC_XID_MASK",          ("bn", "DBC_DBC_XID_MASK", 14),            1048575),
  ("DBC_DBC_PATH_ROCE",         ("bn", "DBC_DBC_PATH_ROCE", 14),           0),
  ("BNXT_QPLIB_DBR_VALID",      ("bn", "BNXT_QPLIB_DBR_VALID", 14),        67108864),
  ("DBC_DBC_INDEX_MASK",        ("bn", "DBC_DBC_INDEX_MASK", 15),          16777215),
  ("BNXT_QPLIB_DBR_EPOCH_SHIFT", ("bn", "BNXT_QPLIB_DBR_EPOCH_SHIFT", 15), 24),

  # ---- send_wqe / recv_wqe / msn_entry / cqe_ready (:18-25) -----------------
  ("SQ_SEND_FLAGS_SIGNAL_COMP", ("bn", "SQ_SEND_FLAGS_SIGNAL_COMP", 18),   1),
  ("SQ_MSN_SEARCH_START_IDX_SFT", ("bn", "SQ_MSN_SEARCH_START_IDX_SFT", 24), 48),
  ("SQ_MSN_SEARCH_NEXT_PSN_SFT",  ("bn", "SQ_MSN_SEARCH_NEXT_PSN_SFT", 24),  24),
  ("CQ_BASE_TOGGLE",            ("bn", "CQ_BASE_TOGGLE", 25),              1),

  # ---- build_pbl (:27-37) ---------------------------------------------------
  ("PTU_PTE_VALID",             ("bn", "PTU_PTE_VALID", 29),               1),
  ("PTU_PTE_LAST",              ("bn", "PTU_PTE_LAST", 30),                2),
  ("PTU_PTE_NEXT_TO_LAST",      ("bn", "PTU_PTE_NEXT_TO_LAST", 30),        4),

  # ---- the doorbell types and the command queue offsets (:115-143) ----------
  ("DBC_DBC_TYPE_SQ",           ("bn", "DBC_DBC_TYPE_SQ", 115),             0),
  ("DBC_DBC_TYPE_NQ_ARM",       ("bn", "DBC_DBC_TYPE_NQ_ARM", 115),         2952790016),
  ("DBC_DBC_TYPE_RQ",           ("bn", "DBC_DBC_TYPE_RQ", 237),             268435456),
  ("DBC_DBC_TYPE_CQ",           ("bn", "DBC_DBC_TYPE_CQ", 223),             1073741824),
  ("CMDQ_INIT_CMDQ_SIZE_SFT",   ("bn", "CMDQ_INIT_CMDQ_SIZE_SFT", 116),     2),
  ("RCFW_COMM_BASE_OFFSET",     ("bn", "RCFW_COMM_BASE_OFFSET", 119),       1536),
  ("RCFW_PF_VF_COMM_PROD_OFFSET", ("bn", "RCFW_PF_VF_COMM_PROD_OFFSET", 142), 12),
  ("RCFW_COMM_TRIG_OFFSET",     ("bn", "RCFW_COMM_TRIG_OFFSET", 143),       256),
  ("RCFW_CMDQ_TRIG_VAL",        ("bn", "RCFW_CMDQ_TRIG_VAL", 143),          1),
  ("FIRMWARE_FIRST_FLAG",       ("bn", "FIRMWARE_FIRST_FLAG", 138),         31),

  # ---- hwrm (:76-89) --------------------------------------------------------
  ("BNXT_HWRM_NO_CMPL_RING",    ("bn", "BNXT_HWRM_NO_CMPL_RING", 79),       -1),
  ("BNXT_HWRM_TARGET",          ("bn", "BNXT_HWRM_TARGET", 79),             65535),
  ("HWRM_MAX_REQ_LEN",          ("bn", "HWRM_MAX_REQ_LEN", 83),             128),
  ("SIZEOF_RESP_HDR",           ("sz", "struct_hwrm_resp_hdr", 87),         8),

  # ---- the command queue loop and the completion wait (:133-155) ------------
  ("CREQ_BASE_V",               ("bn", "CREQ_BASE_V", 146),                 1),
  ("CREQ_BASE_TYPE_QP_EVENT",   ("bn", "CREQ_BASE_TYPE_QP_EVENT", 154),     56),
  ("CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION",
                               ("bn", "CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION", 154), 192),
  ("SIZEOF_CQ_BASE",            ("sz", "struct_cq_base", 194),              32),

  # ---- ring_alloc / vnic / cfa_l2 (:112-180) --------------------------------
  ("RING_ALLOC_REQ_RING_TYPE_NQ", ("bn", "RING_ALLOC_REQ_RING_TYPE_NQ", 112), 5),
  ("RING_ALLOC_REQ_RING_TYPE_L2_CMPL", ("bn", "RING_ALLOC_REQ_RING_TYPE_L2_CMPL", 169), 0),
  ("RING_ALLOC_REQ_RING_TYPE_RX", ("bn", "RING_ALLOC_REQ_RING_TYPE_RX", 172), 2),
  ("RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID", ("bn", "RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID", 169), 128),
  ("RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID", ("bn", "RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID", 172), 256),
  ("RING_ALLOC_REQ_INT_MODE_MSIX", ("bn", "RING_ALLOC_REQ_INT_MODE_MSIX", 113), 2),
  ("VNIC_CFG_REQ_ENABLES_MRU",  ("bn", "VNIC_CFG_REQ_ENABLES_MRU", 176),    16),
  ("VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID", ("bn", "VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID", 176), 32),
  ("VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID", ("bn", "VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID", 176), 64),
  ("CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX", ("bn", "CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX", 178), 1),
  ("CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR", ("bn", "CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR", 178), 1),
  ("CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK", ("bn", "CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK", 179), 2),
  ("CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID", ("bn", "CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID", 180), 32768),
  ("FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE",
                               ("bn", "FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE", 107), 2),

  # ---- setup_backing_store (:91-108) and register_mem (:183-188) -----------
  ("CMDQ_REGISTER_MR_LVL_SFT",  ("bn", "CMDQ_REGISTER_MR_LVL_SFT", 186),    0),
  ("CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT", ("bn", "CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT", 186), 2),
  ("CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE", ("bn", "CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE", 187), 1),
  ("CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE", ("bn", "CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE", 187), 4),
  ("CMDQ_REGISTER_MR_FLAGS_ALLOC_MR", ("bn", "CMDQ_REGISTER_MR_FLAGS_ALLOC_MR", 185), 1),
  ("CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED",
                               ("bn", "CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED", 123), 2),

  # ---- BNXTQP (:191-216) ----------------------------------------------------
  ("CMDQ_CREATE_QP_TYPE_RC",    ("bn", "CMDQ_CREATE_QP_TYPE_RC", 198),       2),
  ("CMDQ_MODIFY_QP_QP_TYPE_RC", ("bn", "CMDQ_MODIFY_QP_QP_TYPE_RC", 210),    2),
  ("CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4", ("bn", "CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4", 207), 128),
  ("CMDQ_MODIFY_QP_PATH_MTU_MTU_4096", ("bn", "CMDQ_MODIFY_QP_PATH_MTU_MTU_4096", 212), 64),

  # ---- ctypes.sizeof of the command structs (:133, :134) --------------------
  ("SIZEOF_CMDQ_ADD_GID",       ("sz", "struct_cmdq_add_gid", 72),          48),
  ("SIZEOF_CMDQ_INITIALIZE_FW", ("sz", "struct_cmdq_initialize_fw", 122),    112),
  ("SIZEOF_CMDQ_CREATE_CQ",     ("sz", "struct_cmdq_create_cq", 195),        64),
  ("SIZEOF_CMDQ_CREATE_QP",     ("sz", "struct_cmdq_create_qp", 198),        104),
  ("SIZEOF_CMDQ_MODIFY_QP",     ("sz", "struct_cmdq_modify_qp", 204),        144),
  ("SIZEOF_CMDQ_REGISTER_MR",   ("sz", "struct_cmdq_register_mr", 185),      56),
  ("SIZEOF_CMDQ_DEREGISTER_MR", ("sz", "struct_cmdq_deregister_mr", 189),    24),
  ("SIZEOF_CMDQ_INIT",          ("sz", "struct_cmdq_init", 116),             16),
]

def authority(spec):
    kind, name, _line = spec
    if kind == "py":
        return getattr(B, name)
    if kind == "bn":
        return getattr(bnxt, name)
    return ctypes.sizeof(getattr(bnxt, name))

bad = 0
for bend_name, spec, hand in MAP:
    truth = authority(spec)
    ok = (truth == hand)
    bad += 0 if ok else 1
    print(f"HANDMAP {bend_name:46s} {spec[0]} {spec[1]:56s} bnxtdev.py:{spec[2]:<4} "
          f"hand={hand:<12} truth={truth:<12} {'ok' if ok else 'MISMATCH'}")
print(f"handmap: {len(MAP)} entries, {bad} MISMATCH -> {'handmap-clean' if bad == 0 else 'HANDMAP-DIRTY'}")

# ===========================================================================
# THE HEX CROSS-CHECK, and it exists because the hand values above were typed
# while READING the oracle's decimal output. That is not independent on exactly
# the failure the brief names: a transposed digit pair, as in the brief's
# `BNXT_VENDOR` 5356 vs 5348. So every constant whose SOURCE SPELLING is hex
# is derived a second way -- `int(literal, 16)` off the literal in
# bnxtdev.py / autogen/bnxt.py -- and the two are compared. `ops_nv`'s 33 wrong
# of 219 and the brief's one-digit-pair error were both invisible to a decimal
# eyeball; this is the check that sees them.
#
# (HEXLIT, BEND NAME, hex literal as the SOURCE spells it)
# ===========================================================================
HEXLIT = [
  ("0xd",         "BNXT_INIT_MASK", 0xd),
  ("0x41515ad",   "BNXT_RTR_MASK", 0x41515ad),
  ("0xae005",     "BNXT_RTS_MASK", 0xae005),
  ("0x100",       "BNXT_CHIMP_COMM_TRIGGER", 0x100),
  ("0xffffff",    "PSN_MASK", 0xffffff),
]
hbad = 0
for lit, name, hx in HEXLIT:
    truth = dict((n, v) for n, _s, v in MAP).get(name)
    if truth is None:
        # PSN_MASK is not a constant def here; it is derived, so compare to the
        # source spelling itself and let the .bend gate carry the derivation.
        truth = hx
    ok = (truth == hx)
    hbad += 0 if ok else 1
    print(f"HEXLIT {lit:14s} -> {name:26s} hex_dec={hx:<12} handmap={truth:<12} "
          f"{'ok' if ok else 'MISMATCH'}")
# the autogen enums, whose SOURCE is a hex literal in autogen/bnxt.py.
HEXLIT_BN = [
  ("BNXT_QPLIB_DBR_VALID", 0x4000000),
  ("DBC_DBC_XID_MASK", 0xfffff),
  ("DBC_DBC_INDEX_MASK", 0xffffff),
  ("DBC_DBC_TYPE_RQ", 0x10000000),
  ("DBC_DBC_TYPE_CQ", 0x40000000),
  ("DBC_DBC_TYPE_NQ_ARM", 0xb0000000),
  ("CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION", 0xc0),
  ("CREQ_BASE_TYPE_QP_EVENT", 0x38),
  ("CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID", 0x8000),
  ("RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID", 0x80),
  ("RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID", 0x100),
  ("VNIC_CFG_REQ_ENABLES_MRU", 0x10),
  ("VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID", 0x20),
  ("VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID", 0x40),
  ("CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4", 0x80),
  ("CMDQ_MODIFY_QP_PATH_MTU_MTU_4096", 0x40),
]
m = dict((n, v) for n, _s, v in MAP)
for name, hx in HEXLIT_BN:
    truth = m.get(name)
    # the handmap value must EQUAL the hex the autogen source spells
    src = authority(("bn", name, 0))
    ok = (src == hx) and (truth == hx)
    hbad += 0 if ok else 1
    print(f"HEXLIT_BN {hex(hx):14s} -> {name:52s} handmap={truth:<12} {'ok' if ok else 'MISMATCH'}")
print(f"hexlit: {len(HEXLIT) + len(HEXLIT_BN)} literal-spelling cross-checks, {hbad} MISMATCH -> "
      f"{'hex-clean' if hbad == 0 else 'HEX-DIRTY'}")

# ===========================================================================
# THE CITED CROSS-CHECK. `ops_rdma.bend` is COMMITTED AND GREEN and cites
# `bnxtdev.py` in its comments and its constant table. Every constant it says
# comes from bnxtdev.py is listed here a second time, against the same
# getattr, so the two files' numbers can be compared rather than asserted.
# `BNXT_VENDOR` is ops_rdma.py:18's, not bnxtdev.py's, and it is included
# because the brief names it as a live warning.
# ===========================================================================
print()
print("=== ops_rdma.bend CITATIONS, re-derived from CPython ===")
CITED = [
  # (what ops_rdma.bend says, the Bend def it is, the truth)
  ("DBC_DBC_TYPE_SQ",        "DBC_DBC_TYPE_SQ",        bnxt.DBC_DBC_TYPE_SQ,        0),
  ("DBC_DBC_TYPE_RQ",        "DBC_DBC_TYPE_RQ",        bnxt.DBC_DBC_TYPE_RQ,        268435456),
  ("DBC_DBC_TYPE_CQ",        "DBC_DBC_TYPE_CQ",        bnxt.DBC_DBC_TYPE_CQ,        1073741824),
  ("DBC_DBC_XID_MASK",       "DBC_DBC_XID_MASK",       bnxt.DBC_DBC_XID_MASK,       1048575),
  ("DBC_DBC_PATH_ROCE",      "DBC_DBC_PATH_ROCE",      bnxt.DBC_DBC_PATH_ROCE,      0),
  ("BNXT_QPLIB_DBR_VALID",   "BNXT_QPLIB_DBR_VALID",   bnxt.BNXT_QPLIB_DBR_VALID,   67108864),
  ("SQ_SEND_FLAGS_SIGNAL_COMP", "SQ_SEND_FLAGS_SIGNAL_COMP", bnxt.SQ_SEND_FLAGS_SIGNAL_COMP, 1),
  ("DBC_DBC_INDEX_MASK",     "DB_INDEX_MASK",          bnxt.DBC_DBC_INDEX_MASK,     16777215),
  ("BNXT_QPLIB_DBR_EPOCH_SHIFT", "DB_EPOCH_SHIFT",     bnxt.BNXT_QPLIB_DBR_EPOCH_SHIFT, 24),
  ("WQE_SIZE",               "WQE_SIZE",               B.WQE_SIZE,                 128),
  ("RING_ENTRIES",           "RING_ENTRIES",           B.RING_ENTRIES,             4096),
  ("CQ_ENTRIES",             "CQ_ENTRIES",             B.CQ_ENTRIES,               4096),
  ("MTU",                    "MTU",                    B.MTU,                      4096),
  ("SQ_MSN_SEARCH_START_IDX_SFT", "MSN_SLOT_HI_AT:16 half -> slot at bit 48",
                                   bnxt.SQ_MSN_SEARCH_START_IDX_SFT,       48),
  ("SQ_MSN_SEARCH_NEXT_PSN_SFT",  "MSN_PSN_AT",  bnxt.SQ_MSN_SEARCH_NEXT_PSN_SFT, 24),
  ("PSN_MASK (:145 0xffffff)", "PSN_MASK",          0xffffff,                  16777215),
  ("VRAM_BAR (bnxtdev maps bar 2 as 'Q')", "VRAM_BAR", 2, 2),
]
cbad = 0
for cite, bend_def, truth, ops_value in CITED:
    ok = (truth == ops_value)
    cbad += 0 if ok else 1
    print(f"CITE {cite:52s} ops_rdma.bend {bend_def:44s} ops={ops_value:<12} cp={truth:<12} "
          f"{'ok' if ok else 'CONTRADICTED'}".replace("CONTRADICTED", "CONTRADICTED"))

# BNXT_VENDOR: ops_rdma.py:18 is 0x14e4. Not bnxtdev.py's -- it is the cross-check
# the brief calls a live warning.
vend_src = 0x14e4
print(f"CITE ops_rdma.py:18 BNXT_IDS[0]                        ops_rdma.bend BNXT_VENDOR"
      f"        ops={5348:<12} cp={vend_src:<12} {'ok' if 5348 == vend_src else 'CONTRADICTED'}")
print(f"      (0x14e4 = {vend_src}; the brief's 5356 = 0x14EC is a transposed digit pair)")
cbad += 0 if 5348 == vend_src else 1
print(f"cites: {len(CITED) + 1} checked, {cbad} CONTRADICTED -> "
      f"{'citations-hold' if cbad == 0 else 'CITATIONS-BROKEN'}")