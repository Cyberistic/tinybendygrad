<!-- FROM: tinybendygrad/runtime/support/rdma/bnxtdev.bend:535 -->
# BLOCK:
# the page tables. `build_pbl`, :27-37, and it is the table most likely to
# CARRY A WRONG CONSTANT, because a wrong PTU_PTE_* flag is a page table the
# NIC walks off the end of and there is no Python exception to catch it.
#
#   def build_pbl(dev, paddrs, queue=False):
#     if len(paddrs) == 1: return 0, paddrs[0]
#     values = [p | PTU_PTE_VALID for p in paddrs]
#     if queue: values[-1] |= PTU_PTE_LAST; values[-2] |= PTU_PTE_NEXT_TO_LAST
#     table, table_paddrs = dev.pci_dev.alloc_sysmem(ceildiv(len(values),512)*0x1000)
#     table[:len(values)*8] = struct.pack(f"<{len(values)}Q", *values)
#     if len(table_paddrs) == 1: return 1, table_paddrs[0]
#     assert len(table_paddrs) <= 512, "a pbl has two levels"
#     top, top_paddrs = dev.pci_dev.alloc_sysmem(0x1000)
#     top[:len(table_paddrs)*8] = struct.pack(..., *(p|PTU_PTE_VALID for p in table_paddrs))
#     return 2, top_paddrs[0]
#
# FOUR FACTS, and each has a row:
#   1. ONE page short-circuits with NO ALLOCATION at all and NO VALID BIT.
#      `pbl_level_of(1) == 0` and `pbl_one_ALLOCS == 0`.
#   2. THE LEVEL IS A FUNCTION OF `ceildiv(n, 512)` ALONE -- the table's byte
#      count is a whole number of pages, so the number of pages holding the
#      table IS the page count of the allocation. 1 -> level 1, 2..512 ->
#      level 2, more -> the REFUSAL. `pbl_q_512_LEVEL == 1` and
#      `pbl_q_513_LEVEL == 2` sit ONE PAGE APART, which is the negative case.
#   3. the three flags land in the low 32 BITS. `PTU_PTE_VALID` is 1,
#      `PTU_PTE_LAST` is 2 and `PTU_PTE_NEXT_TO_LAST` is 4, so the high half
#      of every entry is the physical address's and NOTHING ELSE --
#      `pbl.entry_hi` is the IDENTITY and `pbl_hi_untouched` says so. This is
#      what makes WALL 2 cost nothing here.
#   4. `queue` adds two flags to two different entries, and the second-to-last
#      is the one that gets NEXT_TO_LAST -- the two are not the same entry and
#      `pbl_queue_two_entries` is the row that separates them.
# END BLOCK

# the page tables. `build_pbl`, :27-37, and it is the table most likely to
# CARRY A WRONG CONSTANT, because a wrong PTU_PTE_* flag is a page table the
# NIC walks off the end of and there is no Python exception to catch it.
#
#   def build_pbl(dev, paddrs, queue=False):
#     if len(paddrs) == 1: return 0, paddrs[0]
#     values = [p | PTU_PTE_VALID for p in paddrs]
#     if queue: values[-1] |= PTU_PTE_LAST; values[-2] |= PTU_PTE_NEXT_TO_LAST
#     table, table_paddrs = dev.pci_dev.alloc_sysmem(ceildiv(len(values),512)*0x1000)
#     table[:len(values)*8] = struct.pack(f"<{len(values)}Q", *values)
#     if len(table_paddrs) == 1: return 1, table_paddrs[0]
#     assert len(table_paddrs) <= 512, "a pbl has two levels"
#     top, top_paddrs = dev.pci_dev.alloc_sysmem(0x1000)
#     top[:len(table_paddrs)*8] = struct.pack(..., *(p|PTU_PTE_VALID for p in table_paddrs))
#     return 2, top_paddrs[0]
#
# FOUR FACTS, and each has a row:
#   1. ONE page short-circuits with NO ALLOCATION at all and NO VALID BIT.
#      `pbl_level_of(1) == 0` and `pbl_one_ALLOCS == 0`.
#   2. THE LEVEL IS A FUNCTION OF `ceildiv(n, 512)` ALONE -- the table's byte
#      count is a whole number of pages, so the number of pages holding the
#      table IS the page count of the allocation. 1 -> level 1, 2..512 ->
#      level 2, more -> the REFUSAL. `pbl_q_512_LEVEL == 1` and
#      `pbl_q_513_LEVEL == 2` sit ONE PAGE APART, which is the negative case.
#   3. the three flags land in the low 32 BITS. `PTU_PTE_VALID` is 1,
#      `PTU_PTE_LAST` is 2 and `PTU_PTE_NEXT_TO_LAST` is 4, so the high half
#      of every entry is the physical address's and NOTHING ELSE --
#      `pbl.entry_hi` is the IDENTITY and `pbl_hi_untouched` says so. This is
#      what makes WALL 2 cost nothing here.
#   4. `queue` adds two flags to two different entries, and the second-to-last
#      is the one that gets NEXT_TO_LAST -- the two are not the same entry and
#      `pbl_queue_two_entries` is the row that separates them.
