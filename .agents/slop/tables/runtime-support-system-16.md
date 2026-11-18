<!-- FROM: tinybendygrad/runtime/support/system.bend:16 -->
# BLOCK:
# WHAT IS PORTED, DEF BY DEF. "FFI" means there is nothing to check: the call
# itself is the port's job and the Python line is the whole of it.
#
#   tinygrad/runtime/support/system.py:10-15 `filter_visible_devices` PORTED  `vis.*` -- the index-string parser
#   :17-47 FileIOInterface        FFI     open/close/ioctl/mmap/read/write.
#                                              :36's `-1` mmap sentinel and :42-47's
#                                              three statics are the trace
#   tinygrad/runtime/support/system.py:49-50 `MAP_FIXED` `MAP_LOCKED` PORTED  `MAP_*` -- both directions, per PLATFORM
#   tinygrad/runtime/support/system.py:52 `ipv4_to_gid` PORTED  `gid.*` -- 16 bytes of multicast group
#   :56-59 write_sysfs            PORTED  `sysfs.*` + `sysfs.wrote` -- the `sudo`
#                                               STRING
#   tinygrad/runtime/support/system.py:61-65 `atomic_lib` / libsys PORTED  `cap.*` -- the PLATFORM gate, which is
#                                               `cap.barrier_lib`'s `osx`
#   :67-70 pagemap                PORTED  `sys.pagemap`
#   :72-82 vfio                   PORTED  `pci.probe.vfio` -- its `except OSError:
#                                               None`
#   :84-87 reserve_va             PORTED  `sys.reserve_va` -- the CACHE negative case
#   tinygrad/runtime/support/system.py:88 `memory_barrier`  PORTED  `cap.barrier_lib` -- which library is
#                                               consulted
#   :91-92 lock_memory            PORTED  `sys.lock_memory` -- the refusal
#   tinygrad/runtime/support/system.py:93 `system_paddrs`   PARTIAL `paddr.*` -- the mask; the u64 read is FFI
#   :98-102 alloc_sysmem          PORTED  `sys.alloc_sysmem` -- the flag arithmetic
#   tinygrad/runtime/support/system.py:103 `pci_scan_bus`  PORTED  `scan.*` -- the mask filter + both id formats
#   :128-136 list_devices/probe   PORTED  `pci.probe.*`
#   :138-186 pci_setup_usb_bars   PORTED  `bars.*` -- THE HEADLINE. 7 ordered writes,
#                                               the REBAR control, the BAR sizing
#   :188-200 flock_acquire        WALL   the `fcntl.flock` call itself is the
#                                               seam; the two open-flag sets are
#                                               constants
#   :206-268 PCIDevice            PORTED  `pci.*` -- the sysfs path table, the open
#                                               flags, bar_info, read/write_config,
#                                               resize_bar, map_bar
#   :270-290 USBPCIDevice         PORTED  `usb.*` -- the constants and the DMA window
#   tinygrad/runtime/support/system.py:290 `PCIAllocationMeta` PORTED  `Meta.*` -- field order and names
#   tinygrad/runtime/support/system.py:292-352 `PCIIfaceBase` PORTED  `face.*` -- peer_group, is_bar_small, the
#                                               alloc size ladder, map()'s refusals
#   tinygrad/runtime/support/system.py:356-360 `RemoteCmd` PORTED  `Rcmd.*` -- 16 names, both directions,
#                                               REMOTE_REQ/REMOTE_RESP field order
#   tinygrad/runtime/support/system.py:362-380 `RemoteMMIOInterface` PORTED  `rmm.*` -- the element-size table
#   :385-452 RemotePCIDevice      PORTED  `rpc.*` -- the pad-to-3 rule, the REMOTE
#                                               parser, the socket-option table
#   :454   the MOCK swap          FFI     DEV.interface, a module rebind
# END BLOCK
