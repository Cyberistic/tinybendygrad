<!-- FROM: tinybendygrad/runtime/ops_rdma.bend:1136 -->
# BLOCK:
# :148,:152 -- THE DOORBELL RULE, and it is four arithmetic facts:
#
#   ((n + 1) % RING_ENTRIES | ((n + 1) // RING_ENTRIES & 1) << SHIFT) | ring_db
#
#   * the slot is `n + 1`, the slot AFTER the work queue element just written --
#     and :151 polls slot `n`. One step apart, and the two together are the ring
#     protocol.
#   * the epoch is `(n + 1) // RING_ENTRIES & 1`, a SINGLE BIT counting how many
#     times the index has wrapped the ring. `& 1` is what makes it one bit; the
#     gate's `rdma_epoch_*` fixture runs n across a wrap so a version that
#     dropped the `& 1` would print 2 instead of 0.
#   * the CQ doorbell is the SAME rule with `CQ_ENTRIES` -- and since
#     `RING_ENTRIES == CQ_ENTRIES == 4096` the two agree, which is a fact about
#     these numbers and not about the code. `rdma_eq_ring_cq` says so.
# END BLOCK

# :148,:152 -- THE DOORBELL RULE, and it is four arithmetic facts:
#
#   ((n + 1) % RING_ENTRIES | ((n + 1) // RING_ENTRIES & 1) << SHIFT) | ring_db
#
#   * the slot is `n + 1`, the slot AFTER the work queue element just written --
#     and :151 polls slot `n`. One step apart, and the two together are the ring
#     protocol.
#   * the epoch is `(n + 1) // RING_ENTRIES & 1`, a SINGLE BIT counting how many
#     times the index has wrapped the ring. `& 1` is what makes it one bit; the
#     gate's `rdma_epoch_*` fixture runs n across a wrap so a version that
#     dropped the `& 1` would print 2 instead of 0.
#   * the CQ doorbell is the SAME rule with `CQ_ENTRIES` -- and since
#     `RING_ENTRIES == CQ_ENTRIES == 4096` the two agree, which is a fact about
#     these numbers and not about the code. `rdma_eq_ring_cq` says so.
