<!-- FROM: tinybendygrad/runtime/support/compiler_qcom.bend:15 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF, with the CPython line it covers.
#
#   :8   _read_lib               PORTED  `q.read` `q.read_le` `q.read_be`
#   :12  the a630 assert         PORTED  `q.arch_ok` -- upstream's `arch` IS the
#                                        subject of the split
#   :13  chip_id = 0x6030001     PORTED  `q.chip_id` (0x6030001 = 100859905,
#                                        which fits a `U32` exactly)
#   :16  the cache key           PORTED  `q.key`
#   :17  the rootfs fetch        PARTIAL `q.root` -- the URL and the repo root;
#                                         `fetch(..., extract=True)` is WALL 1
#   :18  the qemu command        PORTED  `q.cmd_qemu` -- upstream's `qemu` IS
#                                         the command's head
#   :19-20 the docker command    PORTED  `q.cmd_docker` -- upstream's `docker` IS
#                                         the command's head; the whole four-line
#                                         f-string, with the `-v` mounts and the
#                                         two `-e` variables
#   :13  the platform gate       PORTED  `q.is_aarch64` -- upstream's `platform`
#                                         IS the gate's subject, and :13 (NOT
#                                         :21) IS where upstream tests it
#   :27-32 checked()             PORTED  `q.msg` `q.msg_with` `q.picks_exe` --
#                                         the handle-type test and the two
#                                         arms of the build log
#   :36  the nine-argument call -- upstream's `cl_compiler_compile_source` IS the
#                                         call: PORTED  `q.compile_args` -- chip,
#                                         mode, and the source-kind constant,
#                                         IN ORDER
#   :39  the link call -- upstream's `cl_compiler_link_program` IS the call --
#                                         PORTED  `q.link_args` -- and note the
#                                         last argument is the compile handle,
#                                         not NULL as in :36
#   :46  the disassemble slice -- upstream's `disas_adreno` IS the callee --
#                                         PORTED  `q.slice_off` `q.slice_end` -- THE
#                                         HEADLINE
# END BLOCK
