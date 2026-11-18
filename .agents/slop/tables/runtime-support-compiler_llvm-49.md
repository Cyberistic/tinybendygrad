<!-- FROM: tinybendygrad/runtime/support/compiler_llvm.bend:49 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :6   cerr()                PORTED `cerr_depth` -- the pointer-to-pointer shape -- upstream builds the error pointer in `cerr`
#   :8-10 expect()             PORTED `expect.fails` `expect.ret_str` `expect.msg`
#   :14-15 the five inits      PORTED `LLVMCompiler.prefix` `.components`
#   :17  the triple map        PORTED `LLVMCompiler.triple` `.triple_ok`
#   tinygrad/runtime/support/compiler_llvm.py:18 `expect`   PORTED `LLVMCompiler.triple_ok` symbol=__init__
#   :20-21 the target machine  PORTED `LLVMCompiler.tm_processor` `.tm_feats`
#   :23-31 the pass options    PORTED `LLVMCompiler.passes` `.pbosets`
#   :34-35 the context         PORTED `LLVMCompiler.diags` `.append`
#   :36-43 the handler         PORTED `LLVMCompiler.append_diag`
#   :44  the cache key         PORTED `LLVMCompiler.key`
#   :46-48 __del__             PORTED `LLVMCompiler.del_calls` `.del_order`
#   :50-63 compile()           PORTED `LLVMCompiler.compile_calls` `.compile_order`
#                                       `.diag_join` `.obj_hex`
#   :66-74 CPULLVMCompiler     PORTED `CPULLVMCompiler.featstr` `.feat_native`
#                                       `.reserve_x18` `.feat_final`
#   :79-82 AMDLLVMCompiler     PORTED `AMDLLVMCompiler.reduce` `.tm_feats`
#   :83-87 the RuntimeError    PORTED `AMDLLVMCompiler.remap` `.remap_msg`
#                                       `.remap_kind`
#   tinygrad/runtime/support/compiler_llvm.py:76-88 `disassemble` PORTED `CPULLVMCompiler.dis_row` symbol=disassemble
#                                       `AMDLLVMCompiler.dis_row`
# END BLOCK
