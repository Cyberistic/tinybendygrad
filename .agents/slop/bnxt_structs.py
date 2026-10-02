"""bnxtdev.bend -- STRUCT FIELD LIST probe, by name and in order.

The autogen structs are `c.record` opaque (`_fields_ == ('_mem_',)`), so plain
ctypes cannot see the names. `_real_fields_` CAN: it is what `register_fields`
installs. Everything below is read off the RUNTIME class, never out of the
source text, so a hand map can be diffed against it.
"""
import sys
sys.path.insert(0, '.')
import ctypes  # noqa: E402
from tinygrad.runtime.autogen import bnxt  # noqa: E402

WANTED = [
  "struct_hwrm_resp_hdr", "struct_cq_base", "struct_cmdq_init", "struct_cmdq_base",
  "struct_hwrm_ver_get_input", "struct_hwrm_ver_get_output",
  "struct_hwrm_func_reset_input", "struct_hwrm_func_reset_output",
  "struct_hwrm_func_qcaps_input", "struct_hwrm_func_qcaps_output",
  "struct_hwrm_func_drv_rgtr_input", "struct_hwrm_func_drv_rgtr_output",
  "struct_hwrm_func_qcfg_input", "struct_hwrm_func_qcfg_output",
  "struct_hwrm_func_backing_store_qcaps_v2_input", "struct_hwrm_func_backing_store_qcaps_v2_output",
  "struct_hwrm_func_backing_store_cfg_v2_input", "struct_hwrm_func_backing_store_cfg_v2_output",
  "struct_hwrm_ring_alloc_input", "struct_hwrm_ring_alloc_output",
  "struct_hwrm_stat_ctx_alloc_input", "struct_hwrm_stat_ctx_alloc_output",
  "struct_hwrm_vnic_alloc_input", "struct_hwrm_vnic_alloc_output",
  "struct_hwrm_vnic_cfg_input", "struct_hwrm_vnic_cfg_output",
  "struct_hwrm_cfa_l2_filter_alloc_input", "struct_hwrm_cfa_l2_filter_alloc_output",
  "struct_hwrm_func_drv_unrgtr_input", "struct_hwrm_func_drv_unrgtr_output",
  "struct_cmdq_initialize_fw", "struct_creq_initialize_fw_resp",
  "struct_cmdq_add_gid", "struct_creq_add_gid_resp",
  "struct_cmdq_create_cq", "struct_creq_create_cq_resp",
  "struct_cmdq_create_qp", "struct_creq_create_qp_resp",
  "struct_cmdq_modify_qp", "struct_creq_modify_qp_resp",
  "struct_cmdq_register_mr", "struct_creq_register_mr_resp",
  "struct_cmdq_deregister_mr", "struct_creq_deregister_mr_resp",
  "struct_creq_base_resp", "struct_cq_req",
]

print("=== FIELD LISTS, BY NAME, IN ORDER, WITH OFFSETS (read off _real_fields_) ===")
for n in WANTED:
    t = getattr(bnxt, n, None)
    if t is None:
        print(f"{n}: <ABSENT FROM autogen/bnxt.py>")
        continue
    lst = getattr(t, "_real_fields_", None)
    if not lst:
        print(f"{n}: <NO _real_fields_>")
        continue
    print(f"{n}: SIZE={t.SIZE} ctypes.sizeof={ctypes.sizeof(t)} nfields={len(lst)}")
    for fn, ft, fo in lst:
        print(f"    {fn:34s} {ft.__name__:16s} @{fo}")

print()
print("=== the ONE field offset the port reads by hand ===")
t = getattr(bnxt, "struct_cq_base")
for fn, ft, fo in t._real_fields_:
    if fn in ("cqe_type_toggle", "status"):
        print(f"  struct_cq_base.{fn} is byte {fo}, width {ctypes.sizeof(ft)}")
print("  bnxtdev.py:25 reads cqe[24]; bnxtdev.py:224 reads raw[25]")