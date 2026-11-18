<!-- FROM: tinybendygrad/runtime/support/am/ip.bend:34 -->
# BLOCK:
# WHAT IS PORTED, section by section, with the CPython lines it covers:
#   the version substrate `V`: three-part and `[:2]` compares, every ladder
#     ..................................................................... :15-47
#   the KIQ `flush_tlb` PM4 packet, SEVENTEEN words, built in order       :99-113
#   the four-generation PTE flag tables and `is_pte_huge_page`          :177-195
#   the per-arch SMU message table, 3 rows x 20 columns, both ways       :199-215
#   the three-register C2PMSG protocol and its DEBUG arm                :264-273
#   the doorbell arithmetic: KIQ xcc, sDMA engine, ring size, s2a ladder
#     ..................................................................... :354 :366 :373 :570-572 :592
#   the `setup_ring` trace, in order, and its ONE raise                  :584-606
#   the register field lists: 115 rows, by NAME and IN ORDER, keyed on
#     (Python line, name) because sixteen of the names are f-strings that
#     two lines legitimately share                        every `.write`/`.update`
#   the IH entry decode: eleven extractors, bit positions, ACA           :502-513
#   the PSP ring frame and the four union command field lists            :707-751
# END BLOCK
