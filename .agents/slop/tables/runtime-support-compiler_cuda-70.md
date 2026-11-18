<!-- FROM: tinybendygrad/runtime/support/compiler_cuda.bend:70 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :7   CUDA_PATH              PORTED `CUDA_PATH.default` (the parameter)
#   :8-9 root, osx_docker_cmd   PORTED `root` `osx_docker_cmd`
#   :11-14 _get_bytes           PORTED `_get_bytes.calls` `.calls_name` `.pick`
#   :16-19 nvrtc_check          PORTED `nvrtc_check.msg` `.kind`
#   :21-24 jitlink_check        PORTED `jitlink_check.msg` `.kind` `.result`
#   :26-36 pretty_ptx           PARTIAL `colored.*` `pretty_ptx.pat0..5`
#                                       `pretty_ptx.cls0..5` -- the SCAN is the wall
#   :38-44 cuda_disassemble     PORTED `cuda_disassemble.fname` `.ptxas` `.nvdisasm`
#                                       `.rstrip` `.keep` `.fail` `.fail2`
#   :46-54 NVRTCCompiler        PORTED `NVRTCCompiler.opts` `.opts_n` `.minimal`
#                                       `.key` `nvrtc_ge_12_4`
#   :55-62 NVRTCCompiler.compile PORTED `NVRTCCompiler.calls` `.calls_n` `.first`
#                                        `.last` `NVRTCCompiler.getter`
#   tinygrad/runtime/support/compiler_cuda.py:63 `disassemble` PORTED `NVRTCCompiler.dis_row` symbol=disassemble
#   :65-76 NVCCCompiler         PORTED `NVCCCompiler.mode` `.suffix` `.cmd`
#                                       `.join` `.keystr` `.key`
#   :78-84 PTXCompiler          PORTED `PTXCompiler.key` `PTXCompiler.ver`
#                                       `PTXCompiler.ge120` `.ge89` `.replace`
#   :86-99 NVPTXCompiler        PORTED `NVPTXCompiler.key` `.calls` `.calls_n`
#                                       `.arch_opt` `.input_kind`
# END BLOCK
