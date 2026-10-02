"""bnxtdev.bend -- constant probe. Every number here is READ OUT OF CPYTHON.

Run from the repo root:
  python3 -c "import sys; sys.path.insert(0,'.'); exec(open('.agents/slop/bnxt_probe.py').read())"

Nothing in this file is hand-typed: it getattr's the autogen module and the
port's own module, and prints both so a hand map can be diffed against them.
"""
import sys
sys.path.insert(0, '.')
from tinygrad.runtime.autogen import bnxt            # noqa: E402
import tinygrad.runtime.support.rdma.bnxtdev as B   # noqa: E402

print("=== bnxtdev.py module constants (the FOUR lines 8-12) ===")
for n in ("BNXT_DEBUG", "BNXT_ACCESS", "BNXT_INIT_MASK", "BNXT_RTR_MASK", "BNXT_RTS_MASK",
          "BNXT_CHIMP_COMM", "BNXT_CHIMP_COMM_TRIGGER", "WQE_SIZE", "RING_ENTRIES", "CQ_ENTRIES", "MTU"):
    print(f"{n} = {getattr(B, n)!r}  hex={getattr(B, n):#x}  dec={getattr(B, n)}")
print("BNXT_BACKING_STORE =", B.BNXT_BACKING_STORE)
print("BNXT_BACKING_STORE len =", len(B.BNXT_BACKING_STORE))
print("BNXT_BACKING_STORE types =", [t for t, _ in B.BNXT_BACKING_STORE])
print("BNXT_BACKING_STORE extra =", [e for _, e in B.BNXT_BACKING_STORE])
print("sum(extra) =", sum(e for _, e in B.BNXT_BACKING_STORE))

print()
print("=== the db_value / msn / cqe_ready constants (autogen/bnxt.py) ===")
for n in ("DBC_DBC_XID_MASK", "DBC_DBC_PATH_ROCE", "BNXT_QPLIB_DBR_VALID", "DBC_DBC_INDEX_MASK",
          "BNXT_QPLIB_DBR_EPOCH_SHIFT", "SQ_MSN_SEARCH_START_IDX_SFT", "SQ_MSN_SEARCH_NEXT_PSN_SFT",
          "SQ_SEND_FLAGS_SIGNAL_COMP", "CQ_BASE_TOGGLE",
          "PTU_PTE_VALID", "PTU_PTE_LAST", "PTU_PTE_NEXT_TO_LAST",
          "DBC_DBC_TYPE_SQ", "DBC_DBC_TYPE_RQ", "DBC_DBC_TYPE_CQ", "DBC_DBC_TYPE_NQ_ARM",
          "CREQ_BASE_V", "CREQ_BASE_TYPE_QP_EVENT", "CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION",
          "CMDQ_INIT_CMDQ_SIZE_SFT", "RCFW_COMM_BASE_OFFSET", "RCFW_PF_VF_COMM_PROD_OFFSET",
          "RCFW_COMM_TRIG_OFFSET", "RCFW_CMDQ_TRIG_VAL", "FIRMWARE_FIRST_FLAG",
          "BNXT_HWRM_NO_CMPL_RING", "BNXT_HWRM_TARGET", "HWRM_MAX_REQ_LEN",
          "CMDQ_REGISTER_MR_LVL_SFT", "CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT",
          "CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE", "CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE",
          "CMDQ_REGISTER_MR_FLAGS_ALLOC_MR", "CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED",
          "CMDQ_CREATE_QP_TYPE_RC", "CMDQ_MODIFY_QP_QP_TYPE_RC", "CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4",
          "CMDQ_MODIFY_QP_PATH_MTU_MTU_4096",
          "RING_ALLOC_REQ_RING_TYPE_NQ", "RING_ALLOC_REQ_RING_TYPE_L2_CMPL", "RING_ALLOC_REQ_RING_TYPE_RX",
          "RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID", "RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID",
          "RING_ALLOC_REQ_INT_MODE_MSIX",
          "VNIC_CFG_REQ_ENABLES_MRU", "VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID",
          "VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID",
          "CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX", "CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR",
          "CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK", "CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID",
          "FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE"):
    try:
        v = getattr(bnxt, n)
    except AttributeError as e:
        print(f"{n} = <MISSING> {e}")
        continue
    print(f"{n} = {v!r}  hex={v:#x}  dec={v}")

print()
print("=== struct sizes and field lists, in order, BY NAME ===")
import ctypes  # noqa: E402
for n in ("struct_cq_base", "struct_hwrm_resp_hdr", "struct_cmdq_init"):
    t = getattr(bnxt, n)
    names, align = [], 0
    for f in t._fields_:
        names.append(f[0])
        align = max(align, ctypes.sizeof(f[1]))
    print(f"{n}: sizeof={ctypes.sizeof(t)} align={align} fields={names}")

print()
print("=== every struct bnxtdev.py names, size + field list ===")
import re  # noqa: E402
src = open('tinygrad/runtime/support/rdma/bnxtdev.py').read()
named = sorted(set(re.findall(r'struct_(\w+)', src)))
print("named in bnxtdev.py:", named)
for stem in named:
    for suffix in ("_input", "_output", "_resp", "_cmd", ""):
        n = f"struct_{stem}{suffix}"
        t = getattr(bnxt, n, None)
        if t is None or not hasattr(t, "_fields_"):
            continue
        names = [f[0] for f in t._fields_]
        print(f"{n}: sizeof={ctypes.sizeof(t)} nfields={len(names)}")
        print(f"    {names}")
        break