<!-- FROM: tinybendygrad/runtime/ops_nv.bend:3 -->
# BLOCK:
# WHAT IS PORTED, in upstream's own line numbers, and every `def` named
# here EXISTS in this file:
#
#   :559-611 (NVDevice)      :322-331 (NVAllocator)  :613-662 (fifos)
#   :688-697 (_ensure_has_local_memory)                :449-451 (alloc's page size)
#   :45 `nvm` word encoding  :31 `hilo`              :38 `nv_flags`
#   :99-225 the four queues' command vocabularies
#   :313-320 the program cache (the lookup is `pc.find`/`pc.same`, NOT a key reader)
#   :261-265 the reloc table both ways                  :230-305 image padding
#   :161-186 the launch path's graph-upload/launch trace and two refusals
#   :50-94 the QMD version/slot/grid layer              :43-45 the ioctl encoding
#   :699-715 the video-HW sizing                         :264-265 `to_name`
#   :811 `reg_ops`'s chunking   :793-816 the profiler register addresses
#   :35, :37-38 the error-string tables                  :664-665 the GPA-info fallback
#   :552 `MOCKIface`  :473 the selection rule  :357 the driver's version table
# END BLOCK
