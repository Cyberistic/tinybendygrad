<!-- FROM: tinybendygrad/runtime/ops_amd.bend:9 -->
# BLOCK:
# WHAT SURVIVES THE CROSSING is exactly what the other five backends also
# survive, which is why this file is worth the gate:
#
#   * the KERNEL ARGUMENT TRACE -- `kernargs` (tinygrad/runtime/ops_amd.py:374 symbol=kernargs) is `layout_args` then
#     `pack_args` over a list whose widths are `8` per global and `v.dtype.itemsize` per var.
#     That is upstream's `layout_args`/`pack_args` (tinygrad/runtime/support/hcq2.py:114-118 symbol=layout_args) -- the SAME
#     contract `ops_webgpu.bend`, `ops_cl.bend` and `ops_nv.bend` port. Getting it consistent across six files
#     matters more here than anywhere.
#   * the PROGRAM/PROGRAM-BUFFER CACHE KEYS and the one eviction policy
#     ops_amd.py has, which is `device.py:280`'s four conjuncts reached through
#     a `BufferSpec`. `BufferSpec(nolru=True)` on a program buffer and NOT on a
#     ring is the positive/negative pair, and it is real Python.
#   * `AMDProgramData`'s ELEVEN derived fields -- the bit positions in
#     `rsrc1`/`rsrc2`/`rsrc3`/`wave32` and the two `kernel_code_properties` bits.
#     A wrong entry here is a silently wrong kernel, which is the whole reason
#     this file exists.
#   * the WAVEFONT / OCCUPANCY tables: `se_cnt`, `cu_cnt`, `waves_per_cu`,
#     `wave_cnt`, `vgpr_size_per_cu`, `lds_size_per_cu`, `max_copy_size`, the
#     arch allow-list, and `tmpring_size`'s five-step ladder with its THREE
#     different `union_COMPUTE_TMPRING_SIZE*` bitfield records.
#   * the `import_module` LADDER and the four MODULE NAMES that `target[0]`
#     picks, both directions.
#   * the QUEUE TAG grammar (`to_name` + `rsplit('_', 2)` + the four-prefix
#     allow-list), both directions.
#   * every REFUSAL, as a TRUNCATION of the trace.
# END BLOCK
