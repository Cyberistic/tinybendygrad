<!-- FROM: tinybendygrad/runtime/ops_rdma.bend:1223 -->
# BLOCK:
# :140-141 -- THE work queue element, and the ADDRESS translation appears here.
#
#   hdr, key = struct.unpack("<8I", (recv_wqe if is_recv else send_wqe)(0, 0, size)[:32]), \
#             unwrap_view(buf)[0].getaddr(nic.device)
#   ops += [ins("write", ring_addr + (n % RING_ENTRIES) * WQE_SIZE,
#               *hdr, buf.getaddr(devs) + off, key.cast(uint32), size)]
#
# The element carries TWELVE u32 words: the EIGHT header words, then the GPU's own
# address plus the chunk offset, then the NIC's KEY for the same memory, then the
# size. BOTH addresses are there -- :46's branch and :50's registration are what
# make the second one mean anything -- and a work queue element whose key is 0 is
# a transfer to nowhere that the NIC will happily accept. So `ins.write` REFUSES
# when the key is missing: that is THE NEGATIVE CASE of this file, and it is not a
# guard Python writes down.
#
# The HEADER: `send_wqe(0, 0, size)` packs `"<BBB5xI20xQII"` and `recv_wqe` packs
# `"<BBB29xQII"`. Word 0 is `type << 16 | flags << 8 | kind`, and the size lands at
# byte 8 -- INSIDE the 32-byte header for a send (a 5-byte pad then `I size`) and
# INSIDE the 29-byte pad for a receive. So the send header's word 2 is the size and
# the receive header's word 2 is ZERO however big the transfer is. And the size
# appears TWICE in a send element, once in the header and once as the last word.
# `rdma_hdr_send` and `rdma_hdr_recv` are the two eight-word lists.
# END BLOCK

# :140-141 -- THE work queue element, and the ADDRESS translation appears here.
#
#   hdr, key = struct.unpack("<8I", (recv_wqe if is_recv else send_wqe)(0, 0, size)[:32]), \
#             unwrap_view(buf)[0].getaddr(nic.device)
#   ops += [ins("write", ring_addr + (n % RING_ENTRIES) * WQE_SIZE,
#               *hdr, buf.getaddr(devs) + off, key.cast(uint32), size)]
#
# The element carries TWELVE u32 words: the EIGHT header words, then the GPU's own
# address plus the chunk offset, then the NIC's KEY for the same memory, then the
# size. BOTH addresses are there -- :46's branch and :50's registration are what
# make the second one mean anything -- and a work queue element whose key is 0 is
# a transfer to nowhere that the NIC will happily accept. So `ins.write` REFUSES
# when the key is missing: that is THE NEGATIVE CASE of this file, and it is not a
# guard Python writes down.
#
# The HEADER: `send_wqe(0, 0, size)` packs `"<BBB5xI20xQII"` and `recv_wqe` packs
# `"<BBB29xQII"`. Word 0 is `type << 16 | flags << 8 | kind`, and the size lands at
# byte 8 -- INSIDE the 32-byte header for a send (a 5-byte pad then `I size`) and
# INSIDE the 29-byte pad for a receive. So the send header's word 2 is the size and
# the receive header's word 2 is ZERO however big the transfer is. And the size
# appears TWICE in a send element, once in the header and once as the last word.
# `rdma_hdr_send` and `rdma_hdr_recv` are the two eight-word lists.
