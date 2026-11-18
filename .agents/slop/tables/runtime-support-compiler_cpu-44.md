<!-- FROM: tinybendygrad/runtime/support/compiler_cpu.bend:44 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers. Def names are
# UPSTREAM names where upstream HAS one.
#
#   :7   the assert                PORTED `ClangCompiler.ge2` `ClangCompiler.msg`
#   tinygrad/runtime/support/compiler_cpu.py:8 the unpack    PORTED `ClangCompiler.arch_of` `.cpu_of` -- upstream's `arch` symbol=__init__
#                                          `.feats`
#   :10  the x86_64 arm            PORTED `ClangCompiler.x86_feat` `ClangCompiler.args`
#   :13  the arm64 arm             PORTED `ClangCompiler.arm64_feat` `ClangCompiler.args`
#   tinygrad/runtime/support/compiler_cpu.py:14 the riscv64 arm PORTED `ClangCompiler.riscv64_cpu` -- upstream's `riscv64` symbol=__init__
#                                          `ClangCompiler.args`
#   :15  the refusal               PORTED `ClangCompiler.supported` `ClangCompiler.unsupported`
#   :16  the cache key             PORTED `ClangCompiler.key`
#   :21-22 the spawn               PORTED `ClangCompiler.compile_argv` `.argv_n`
#   tinygrad/runtime/support/compiler_cpu.py:24 `disassemble`  PORTED `ClangCompiler.dis_row` symbol=disassemble
#   :28  X86Compiler.__init__      PORTED `X86Compiler.key`
#   :29  X86Compiler.compile       PORTED `X86Compiler.nibble` `X86Compiler.hex_ok`
#                                          `X86Compiler.hex_n` `X86Compiler.bad_pos`
#   :30  X86Compiler.disassemble   PORTED `X86Compiler.dis_row`
# END BLOCK
