<!-- FROM: tinybendygrad/runtime/ops_qcom.bend:67 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF. The PORTED lines are what this file decides; the
# SEAM lines are what it names and does not do; the WALL lines are what Bend
# cannot express at all.
#
#   :19   `BUFTYPE_BUF`                  PORTED  the port's own buftype_names, both directions
#   :35-40 `_qreg_exec`/`qreg`           PORTED  the port's own mesa_of/qreg_of/is_reg_name
#   :35-40 `_qreg_exec`                  PORTED  the port's own qregs/qfields/qreg.of
#   tinygrad/runtime/ops_qcom.py:42   ctz                PORTED  `ctz` (see THE ctz PRECONDITION) symbol=ctz
#   :44-46 parity                        PORTED  `parity`
#   tinygrad/runtime/ops_qcom.py:48   pkt7_hdr          PORTED  `pkt7_hdr` symbol=pkt7_hdr
#   tinygrad/runtime/ops_qcom.py:50   pkt4_hdr          PORTED  `pkt4_hdr` symbol=pkt4_hdr
#   :52   `_read_lib`                    PORTED  the port's own read_lib/read_words
#   :62/:64 `cmd`/`reg` the word count   PORTED  the port's own qwords
#   :66-73 `_cache_flush`                PORTED  the port's own flush.of + `Tr`
#   :75   `memory_barrier`               PORTED  the port's own FLUSH_BARRIER
#   :79   the `gpu_id` signal guard      PORTED  the port's own rf.gpu_lt73 / RF_EVENT7
#   :122  the resources refusal          PORTED  the port's own rf.resources + `Tr.refuse`
#   :123  the dims refusal                PORTED  the port's own rf.dims + `Tr.refuse`
#   :119-196 exec                         PORTED  the port's own exec.of and its 27-call trace
#   tinygrad/runtime/ops_qcom.py:57 the ioctl command word  PORTED  `ioctl_cmd` symbol=qcom_submit
#   tinygrad/runtime/ops_qcom.py:206 `QCOMProgramData`    PORTED  `pd.parse_full`, `desc.*`, `const.*` symbol=QCOMProgramData
#   :225/:272 the two offset rules       PORTED  the port's own pd.nir_*/pd.cl_*
#   :232-237 the six derived sizes        PORTED  the port's own pd.*
#   :239-283 `_parse_lib`                 PORTED  the two binary walks
#   :285-288 `qcom_build_program`         PORTED  the port's own qcom.get/ce.find/ce.put
#   :289-297 `QCOMAllocator`              WALL 3  `:296 _offset` is device.bend's own
#   tinygrad/runtime/ops_qcom.py:298 `flag`              PORTED  `kgsl_flags`, both directions symbol=flag
#   :310-345 `QCOMDevice.__init__`        PARTIAL the flags and the gpu_id refusal
#   :310-345 the init SEQUENCE            WALL 4  the ioctls and mmap are seams
#   :339-342 `dummy`/`border_color`       PARTIAL the SIZES only, in the port's own FLUSH_*
#   :344-370 _gpu_alloc/_gpu_free        WALL 4  ioctls, mmap, memset, munmap
#   :354-362 `_gpu_map`                   WALL 4  the ioctl, the EFAULT arm
#   :371-376 `_wait_signal`               WALL 4  the timestamp ioctls
#   tinygrad/runtime/ops_qcom.py:378 _ensure_stack_size  WALL 3  it is `Buffer` and device.bend's
#   :384-386 `_at_profile_finalize`       WALL 4  sysfs
# END BLOCK
