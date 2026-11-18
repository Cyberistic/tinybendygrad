<!-- FROM: tinybendygrad/runtime/ops_rdma.bend:274 -->
# BLOCK:
# THE TRACE VOCABULARY. Sixteen device calls.
#
# The FFI half: the NIC and its driver.
#   OPEN         :22   `BNXTIface(...)` -> `PCIIfaceBase.__init__` -> `PCIDevice`
#   DEVICE       :70   `_select_iface` returning, then `Compiled.__init__`
#   MAP_BAR      :36   `pci_dev.map_bar(2, off=off, size=0x1000)`
#   BAR_INFO     :36   `pci_dev.bar_info(2)`
#   ALLOC_SYSMEM :40   `pci_dev.alloc_sysmem(round_up(size, 0x1000))`
#   ALLOC_VADDR  :27   `MemoryManager.alloc_vaddr(round_up(nbytes, 0x1000), 0x1000)`
#   REGISTER     :50   `dev_impl.register_mem(paddrs, size, log_page, va=va)`
#   UNREGISTER   :53   `dev_impl.unregister_mem(storage.meta)`
#   QP_NEW       :80   `BNXTQP(nic.iface.dev_impl)`
#   QP_CONNECT   :86   `qps[a].connect(qpn, gid, mac)`
#   FINI         :24   `dev_impl.fini()`
#   BUFFER       :31   `Buffer(dev.device, mem.nbytes, uint8, opaque=storage)`
# The KERNEL half: the instruction stream `rdma_copies` emits.
#   INS_WRITE    :141  the work queue element
#   INS_WAIT     :151  `wait_eq` on the completion entry
#   INS_BARRIER  :155  the receive-side cache invalidate
# END BLOCK

# THE TRACE VOCABULARY. Sixteen device calls.
#
# The FFI half: the NIC and its driver.
#   OPEN         :22   `BNXTIface(...)` -> `PCIIfaceBase.__init__` -> `PCIDevice`
#   DEVICE       :70   `_select_iface` returning, then `Compiled.__init__`
#   MAP_BAR      :36   `pci_dev.map_bar(2, off=off, size=0x1000)`
#   BAR_INFO     :36   `pci_dev.bar_info(2)`
#   ALLOC_SYSMEM :40   `pci_dev.alloc_sysmem(round_up(size, 0x1000))`
#   ALLOC_VADDR  :27   `MemoryManager.alloc_vaddr(round_up(nbytes, 0x1000), 0x1000)`
#   REGISTER     :50   `dev_impl.register_mem(paddrs, size, log_page, va=va)`
#   UNREGISTER   :53   `dev_impl.unregister_mem(storage.meta)`
#   QP_NEW       :80   `BNXTQP(nic.iface.dev_impl)`
#   QP_CONNECT   :86   `qps[a].connect(qpn, gid, mac)`
#   FINI         :24   `dev_impl.fini()`
#   BUFFER       :31   `Buffer(dev.device, mem.nbytes, uint8, opaque=storage)`
# The KERNEL half: the instruction stream `rdma_copies` emits.
#   INS_WRITE    :141  the work queue element
#   INS_WAIT     :151  `wait_eq` on the completion entry
#   INS_BARRIER  :155  the receive-side cache invalidate
