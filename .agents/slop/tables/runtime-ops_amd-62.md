<!-- FROM: tinybendygrad/runtime/ops_amd.bend:62 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF. `amd:NN` is ops_amd.py.
#
#   :31-34   SQTT / PMC ContextVars            PORTED  the two default pairs
#   :36-41   the constants                     PORTED  all of them
#   :55      _queue_args                       PORTED  the four ring tags
#   :59      _dw                               PORTED  the 8-vs-4 width
#   :61-67   dispatch_packet                   PORTED  the SHAPE and the header
#   :99-101  set_grbm                          PORTED  the instance_val fold
#   :103-106 wait_reg_mem                      PORTED  the wrm_info_dw words
#   :108-121 acquire_mem                       PARTIAL the flag words, both arms
#   :123-140 release_mem                       PARTIAL the flag words, both arms
#   :142-146 memory_barrier                    PARTIAL the pf ladder
#   :148-150 spi_config                       PORTED  the six fields
#   :157-165 prof_start                        PARTIAL the slot, the log index
#   :172-175 prof_bump                         PORTED  the index arithmetic
#   :184-209 pmc_start                         PARTIAL the block-count table
#   :211-231 pmc_read                          PARTIAL the copy and the stride
#   :235-238 sqtt_userdata                     PARTIAL the pair loop
#   :240-243 sqtt_config                       PARTIAL the rt_freq arm
#   :245-261 sqtt_setup_exec                   PARTIAL the cu/se masks
#   :263-325 sqtt_start                        PARTIAL the per-target register
#                                                    arms, as TABLES
#   :328-357 sqtt_stop                         PARTIAL the status masks
#   :361-364 kernargs                          PORTED  THE ARGUMENT TRACE
#   :366-400 exec                              PARTIAL the register ORDER, the
#                                                    user_regs, dispatch_init
#   :402     wait                              PORTED  one pkt3
#   :404-407 timestamp                         PORTED  one pkt3
#   :409-412 signal                            PORTED  one pkt3, cache_flush
#   :414-418 submit                            PORTIAL the 4-dword ib blob
#   :420-428 push                              PORTIAL the ring/doorbell store
#   :437-443 close_run                         PORTED  the vendor ib packet
#   :445-447 AQLQueue.signal                   PORTED  the close_run then the
#                                                    release
#   :449-458 AQLQueue.exec                     PORTED  the dispatch packet append
#   :460-465 AQLQueue.submit                   PARTIAL the unit=64 doorbell_lag
#   :477-480 SDMAQueue.copy                    PORTIAL the per-chunk header
#   :482-486 SDMAQueue.wait                    PORTED  the func/op ladder
#   :488-490 SDMAQueue.timestamp               PORTED
#   :492-494 SDMAQueue.write                   PORTED
#   :496-498 SDMAQueue.signal                  PORTED  the gfx9 arm
#   :500-520 SDMAQueue.submit                  PARTIAL the wrap/zero tail
#   :522-523 amd_compute_queue                 PORTED  the is_aql dispatch
#   :525-530 AMDProgramData                    PORTED  the record
#   :533-540 amd_build_program                 PORTED  the cache key, both ways
#   :542-561 _amd_program_image                PARTIAL the eleven fields, the
#                                                    LDS refusal, the md5 slice
#   :563-572 AMDAllocator                      PORTED  the five methods
#   :574-577 AMDQueueDesc                      PORTED  the seven fields
#   :579-735 KFDIface                          WALL 1  /dev/kfd
#   :737-804 PCIIface                          WALL 2  PCI BAR + amdev
#   :806-833 USBAllocator / USBIface           WALL 3  USB3
#   :835     _mock                             PORTED  the name ladder
#   :838-840 the three class attributes        PORTED
#   :841-844 pm_encode                         WALL 4  the UOp matcher
#   :846     ifaces                            PORTED  the seven, in order
#   :848-850 device_props/is_am                PORTED
#   :852-920 __init__                          PORTED  the order, the derivations,
#                                                    the module ladders, the
#                                                    arch refusal
#   :922-941 create_queue                      PORTED  the specs, the sizes
#   :943-946 queue_buffer                      PORTED  the grammar, both ways
#   :948-959 compute_queue                     PORTED  the six sizes, the vgpr
#                                                    and lds tables
#   :961-971 has_copy_queue/sdma_queue         PARTIAL the disable, the memo
#   :973-987 tmpring_size                      PORTED  THE WHOLE LADDER
#   :989-999 scratch_buffer                    PORTED  the monotone max
#   :1001-1014 aql_scratch                     PARTIAL the rsrc dicts
#   :1016-1030 the four prof buffers           PORTED  their sizes and specs
#   :1032-1038 program_buffer                  PORTED  the memo and the spec
#   :1040-1048 sqtt_trace                      PORTED  the offset, the wptr, the
#                                                    gfx11 correction, the assert
#   :1055-1069 collect_prof                    PARTIAL the window and the kinds
#   :1071    on_device_hang                    WALL 5
# END BLOCK
