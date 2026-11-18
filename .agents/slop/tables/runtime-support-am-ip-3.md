<!-- FROM: tinybendygrad/runtime/support/am/ip.bend:3 -->
# BLOCK:
# WHAT SURVIVES THE CROSSING IS DATA: the REGISTER FIELD LISTS (every
# `.write(...)` / `.update(...)` names its bitfields, and the ORDER of those
# names is the register write -- so this gate is BY NAME and IN ORDER rather than
# by count), the STRUCT FIELD LISTS (`struct_psp_gfx_rb_frame` :707, the four
# `union_psp_gfx_commands` members :728-751), the SMU MESSAGE PROTOCOL (:264-273),
# the KIQ `flush_tlb` PM4 PACKET (:108-110), the PTE FLAG TABLES (:178-195), the
# DOORBELL ARITHMETIC (:354, :367, :570-571, :592), the VERSION LADDERS, and every
# REFUSAL as a TRUNCATION of the trace (:588 is the only `raise`).
# END BLOCK
