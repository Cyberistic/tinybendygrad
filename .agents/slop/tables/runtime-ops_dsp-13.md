<!-- FROM: tinybendygrad/runtime/ops_dsp.bend:13 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF.
#
#   :48  rpc_sc                 PORTED  `rpc_sc` + `sc_method/ins/outs/fds`
#   :49  rpc_prep_args          PORTED  `pra_len`, `pra_of` -- upstream builds the packed array in `rpc_prep_args`
#   :52  the fds array          PORTED  `fds_of` -- upstream builds the fd vector in `fds`
#   :53  the attrs array        PORTED  `attrs_of` -- upstream builds the attribute vector in `attrs`
#   :56    the pv/len fill      PORTED  `pra.put` -- the ZERO-LENGTH rule
#   :59  DSPProgram.__init__    PORTED  `prog.call`'s inputs (no state to keep)
#   :62  DSPProgram.__call__    PORTED  `prog.call`
#   :63    the buffer refusal   PORTED  `prog.too_many` + `Tr.refuse_now` -- upstream raises RuntimeError in `__call__`
#   :65-66  the three ins/outs  PORTED  `prog.nins`, `prog.nouts`, `prog.pra_lens`
#   :68  the size writes        PORTED  `vt_size_at`, `vt_size_byte` -- upstream packs each scalar with `struct.pack_into`
#   :68  the val writes         PORTED  `vt_val_offset`, `vt_hi_written` -- upstream packs each scalar with `struct.pack_into`
#   :69  the off_mv writes      PORTED  `off_nbytes` -- upstream fills the offset vector with `off_mv.cast`
#   :70  the exec_lib call      PORTED  `prog.exec_sc` -- upstream invokes the fastrpc ioctl in `__call__`
#   :71  the timer divide       PORTED  `prog.scale_micros` (the u64 read is WALL) -- upstream scales the timer in `__call__`
#   :73  DSPBuffer              PORTED  `DspBuf`, `buf.of`
#   :78  _alloc                 PORTED  `alloc.alloc` (MOCKDSP and real arms)
#   tinygrad/runtime/ops_dsp.py:79 the MOCKDSP arm    PORTED  `alloc.mock_flags` -- upstream's `MOCKDSP` arm symbol=_alloc
#   :81    the ION arm          PORTED  `ION_ALIGN`, `ion.aligned`
#   :83    the mmap + BufferStorage PORTED `alloc.alloc.real.go`
#   tinygrad/runtime/ops_dsp.py:87-91 `_free`       PORTED  `alloc.free_calls` symbol=_free
#   tinygrad/runtime/ops_dsp.py:93 `_as_buffer`     PORTED  `alloc.as_buffer_bytes` symbol=_as_buffer
#   tinygrad/runtime/ops_dsp.py:94 `_copyin`        PORTED  `alloc.copyin_bytes` symbol=_copyin
#   tinygrad/runtime/ops_dsp.py:95 `_copyout`       PORTED  `alloc.copyout_bytes` symbol=_copyout
#   :96  _offset                PORTED  `alloc.offset` -- offsets ACCUMULATE
#   :100 DSPCompiler.args       PORTED  `COMPILER_ARGS`, `compiler_args_first`
#   :104-105 the fifteen sections PORTED `link_section`, `link_sections` -- upstream lists the sections in `__init__`
#   :106 the ALIGN(4096) lines  PORTED  `link_line`, `link_line.go`
#   :108 the whole script       PORTED  `link_script` -- upstream writes the SECTIONS script in `__init__`
#   :111 the -T flag            PORTED  `compiler_args_has_T` -- upstream adds the link script flag in `self.args`
#   tinygrad/runtime/ops_dsp.py:113 the cachekey    PORTED  `compiler.cachekey_of` -- upstream's `compile_dsp` key symbol=__init__
#   tinygrad/runtime/ops_dsp.py:115 `__del__`        PORTED  `compiler.del_unlinks` symbol=__del__
#   :118 compile                WALL 1  the clang spawn + the .so read-back
#   :125 disassemble            WALL 1  cpu_objdump / llvm-objdump
#   tinygrad/runtime/ops_dsp.py:129 `DSPDevice.__init__` PORTED  `dev.is_mock` (the ONE branch, tinygrad/runtime/ops_dsp.py:129-139) symbol=__init__
#   :132 the ion_fd open        PORTED  `dev.open_ion`
#   tinygrad/runtime/ops_dsp.py:134-136 the shell buffer PORTED  `dev.shell_size`, `dev.shell_copy` -- upstream's `shell_buf` symbol=__init__
#   tinygrad/runtime/ops_dsp.py:135 `BufferSpec(nolru=True)` PORTED  `dev.shell_spec` -- the eviction NEGATIVE symbol=__init__
#   :141 open_lib               PORTED  `dev.open_lib`, `dev.open_lib_sc`
#   :143 the tinylib URL        PORTED  `OPEN_LIB_FP`, `open_lib_len` -- upstream builds the `tinylib` URL there
#   :145 the two outs           PORTED  `open_lib_out0`, `open_lib_out1` -- upstream allocates the two out views in `open_lib`
#   :147 the raise              PORTED  `open_lib_bad`, `open_lib_err` -- upstream raises RuntimeError in `open_lib`
#   tinygrad/runtime/ops_dsp.py:141-148 `open_lib`   PORTED  `dev.open_lib_handle` -- the handle answer symbol=open_lib
#   :150 close_lib              PORTED  `dev.close_lib`, `dev.close_lib_sc`
#   :154-164 exec_lib           PORTED  `dev.exec_lib` -- open/invoke/close, retry
#   :166-176 init_dsp           PORTED  `dev.init_dsp` -- seven ordered calls
#   :167-170 the stale-fd close PORTED  the `have_fd` arm -- upstream closes a stale fastrpc fd in `init_dsp`
#   :178 RPCListener.__init__   PORTED  the three initial values
#   :186-188 the request block  PORTED  `rpc.lens`, `RPC_MSG_BYTES`
#   :192 msg_send               PORTED  `rpc.msg_*_index` -- upstream writes the request header in `run`
#   :194 the greeting literal   PORTED  `RPC_GREET` -- upstream invokes `FASTRPC_IOCTL_INVOKE` with the greeting `sc` in `run` -- the literal is 0x04020200
#   :197 the sc field split     PORTED  `sc_ins`, `sc_outs` -- upstream splits the sc word in `run`
#   :199-210 the object walk    PARTIAL `rpc.obj_pad`, `rpc.obj_count` (WALL 3) -- upstream walks the object list in `run`
#   :213-238 the seven arms     PORTIAL `rpc.arm` + each arm's in/out counts
#   :221 the SEEK_SET assert    PORTED  `rpc.seek_ok`, `rpc.seek_err` -- upstream asserts `APPS_STD_SEEK_SET` in `run`
#   :239 the unknown-op raise   PORTED  `rpc.unknown_err`, `ARM_NONE` -- upstream raises `RuntimeError` on an unknown op in `run`
#   :243 mockdsp_boilerplate    PORTED  `mockdsp_boilerplate`
#   :253 MockDSPRenderer        PORTED  `mrender.*` -- upstream defines the mock renderer class `MockDSPRenderer`
#   :255 its defines            PORTED  by the omission (clang only)
#   :262 max_numel*itemsize     PORTED  `mrender.nbytes`
#   :264 the mmap2/read loop    PORTED  `mrender.mmap`
#   :266 the val read           PORTED  `mrender.val`
#   :268 the (void*) cast       PORTED  `mrender.arg_name` -- upstream casts the buffer argument in `_render_entry`
#   :270 the inscount write     PORTED  `mrender.finish`
#   :272 the output write       PORTED  `mrender.emit`
#   :276-292 MockDSPProgram     PORTED  `mprog.stdin_bytes`, `mprog.stdout_len`, -- upstream runs the mock program `MockDSPProgram`
#                                             `mprog.scale_ins`
# END BLOCK
