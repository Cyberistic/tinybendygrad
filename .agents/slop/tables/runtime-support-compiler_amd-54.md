<!-- FROM: tinybendygrad/runtime/support/compiler_amd.bend:54 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :4-10  the comgr3 switch      PORTED  `Ad.version` `Ad.hip_lang` `Ad.hyp3`
#   :15-18 check()                PORTED  `c.msg`  (the refusal truncates `gd`)
#   :20-25 _get_comgr_data        PORTED  `gd.*` -- the FOUR-call order and the two
#                                        sizes; the calls themselves are the trace
#   :28-32 set_options()          PORTED  `sp.n` -- the option COUNT comgr is given
#   :35-38 the ISA name           PORTED  `h.isa`
#   :39    the logging flag       PORTED  `h.logging` (autogen value, declared)
#   :49-55 the `asm` branch       PORTED  `h.dataname` `h.asm_actions`
#   :56-70 the compile branch     PORTED  `h.options` `h.opt_n` `h.opt_codegen`
#                                        `h.compile_actions`
#   tinygrad/runtime/support/compiler_amd.py:52-68 the two refusals PORTED  `c.asm_fail` `c.compile_fail` -- upstream's `RuntimeError`
#   tinygrad/runtime/support/compiler_amd.py:55 upstream's `RuntimeError` (the assemble refusal)
#   tinygrad/runtime/support/compiler_amd.py:68 upstream's `RuntimeError` (the compile refusal)
#   tinygrad/runtime/support/compiler_amd.py:72-73 link PORTED  `h.opt_empty` `h.link_action` -- upstream's `set_options`
#   tinygrad/runtime/support/compiler_amd.py:72 upstream's `set_options` (the empty option string)
#   tinygrad/runtime/support/compiler_amd.py:73 upstream's
#                                     `AMD_COMGR_ACTION_LINK_RELOCATABLE_TO_EXECUTABLE`
#   tinygrad/runtime/support/compiler_amd.py:80-84 `HIPCompiler` PORTED  `C.hip_key`
#   :85-87 HIPCompiler.compile    PORTED  `C.is_asm` -- `split('\n',1)[0].strip()
#                                        == '.text'`, and the RuntimeError remap
#   :88    disassemble            PORTED  `C.dis_row` (the `amdgpu_disassemble` call)
#   tinygrad/runtime/support/compiler_amd.py:90-94 `HIPCCCompiler` PORTED  `C.hipcc_key` `C.join_extra`
#   tinygrad/runtime/support/compiler_amd.py:95-96 the NO_HIPCC short-cut PORTED  `C.short_circuit` -- upstream's `self.no_hipcc`
#   tinygrad/runtime/support/compiler_amd.py:96 upstream's `self.no_hipcc`
#   :97-98 the temp suffixes      PORTED  `C.suffixes`
#   tinygrad/runtime/support/compiler_amd.py:102 the ROCM default PORTED  `C.rocm_include` -- upstream's `ROCM_PATH`
#   tinygrad/runtime/support/compiler_amd.py:102 upstream's `ROCM_PATH`
#   :103-104 argv 1               PORTED  `C.argv1`  (element COUNT pinned)
#   :105-106 argv 2               PORTED  `C.argv2`  (element COUNT pinned)
# END BLOCK
