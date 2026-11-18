<!-- FROM: tinybendygrad/runtime/support/compiler_mesa.bend:19 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :9-12  rzalloc                 PARTIAL `ra.*` -- `sizeof` is autogen and the
#                                         kwargs are a ctypes `setattr` by name;
#                                         the ONE thing here that is this file's
#                                         own logic is the size arithmetic
#   :14-17 deserialize             PORTED  `de.*` -- base64 length + the
#                                         blob-reader length, which is what
#                                         `blob_reader_init` is handed
#   :20    LVPCompiler.__init__    PORTED  `lvp.archs` -- `arch.split(",")`
#   tinygrad/runtime/support/compiler_mesa.py:27-28 `struct_lp_type`'s four flags
#                                         PORTED  `lpt.*` -- floating/sign/width/length
#   :35    LP_JIT_RES_CONSTANTS    PORTED  `lpt.res` (autogen value, declared)
#   :51    cpu_objdump             PORTED  `dso.cmd` -- the argv `objdump -d <p>`
#   :56    warps_per_sm            PORTED  `w.*` -- THE TABLE. Five arch strings
#                                         answer 48 and EVERY other string
#                                         answers 64, including `sm_86x` and
#                                         `"SM_86"`, which is why the membership
#                                         test cannot be a prefix test
#   tinygrad/runtime/support/compiler_mesa.py:59 `struct_nv_device_info`'s `sm`
#                                         PORTED  `a3.*` -- the digits after `sm_`
#   :61    the NAK cache key       PORTED  `nak.key`
#   :75-80 NAKCompiler.disassemble PORTED  `nv.*` -- the temp path and the
#                                         `nvdisasm -b SM<n> <path>` command
#   :82-94 disas_adreno            PORTED  `da.*` -- `data64`, the `%04d [%08x_
#                                         %08x] ` line format, the decode-option
#                                         field ORDER and its four values
#   tinygrad/runtime/support/compiler_mesa.py:98 the a630 assert PORTED  `ir3.arch_ok` -- upstream's `a630` symbol=__init__
#   tinygrad/runtime/support/compiler_mesa.py:99 the dev id    PORTED  `ir3.gpu_id` `ir3.chip_id` -- upstream's `dev_id` symbol=__init__
#   :101   disable_cache=True      PORTED  `ir3.disable_cache`
#   :104   the IR3 cache key       PORTED  `ir3.key`
#   :119   the uav count           PORTED  `ir3.num_uavs` -- `num_ssbos + num_images`
#   tinygrad/runtime/support/compiler_mesa.py:118 the three-field store PORTED  `ir3.variant_fields` -- upstream's `const_state` symbol=compile
#   tinygrad/runtime/support/compiler_mesa.py:123 the four-way concat PORTED  `ir3.ret_parts` -- upstream's `info.size` symbol=compile
#                                         the fourth is `info.size`
#   :127-131 unpack_lib            PORTED  `ul.*` -- THE HEADLINE. Two successive
#                                         `sizeof` offsets and then a split at
#                                         `count * 4`
#   tinygrad/runtime/support/compiler_mesa.py:133 `disassemble` PORTED  `ir3.dis_row` symbol=disassemble
# END BLOCK
