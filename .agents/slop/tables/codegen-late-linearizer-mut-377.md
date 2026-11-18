<!-- FROM: tinybendygrad/codegen/late/.linearizer-mut.bend:377 -->

# ===========================================================================
# THE PRIORITY LADDER, linearizer.py:24-32. PORTED IN FULL, all eight arms.
#
#     match u.op:
#       case Ops.PARAM: priority, extra = -20, u.arg.slot
#       case Ops.BUFFER | Ops.ALLOC: priority = -17 if u.addrspace == AddrSpace.LOCAL else -18
#       case Ops.LOAD: priority = -1    # place loads early
#       case Ops.STORE: priority = 1    # place stores late
#       case Ops.RANGE: priority = 5    # placing RANGE is good
#       case Ops.END | Ops.BACKEDGE: priority = -5     # placing loop exits is bad
#       case _: priority = 0            # everything else has priority 0
#
# EVERY PRIORITY IS NEGATIVE and Bend has no signed `U32`, so this returns
# `priority + 20`: the OFFSET, on 0..25, order-isomorphic to the priority. The
# `po=` column of every `lin_u<i>` row is that offset and not the priority.
#
# `extra` -- `u.arg.slot` for a PARAM, `None` for everything else -- is NOT a
# field here, and that is a claim rather than an omission: `extra` is only ever
# REACHED when `run_count` AND `priority` are equal, and priority -20 is the
# PARAM's alone, so any two entries that meet at `extra` are both PARAMs and both
# slots. Python would raise `TypeError` comparing `None` with an `int` if that
# were not true, and `lin_exmix=0` is the row that checks it on the fixture.
# `lin_exmix` COUNTS the pairs that tie on (run_count, priority) and disagree on
# whether `extra` is None -- so it is a gate, not a comment.
#
# `# TODO(p3) linearizer.py:50  the DEBUG_LINEARIZE print reads `extra` -- the one
# place Python reads the field, and env-gated.`
#
# W4: the BUFFER/ALLOC arm's `u.addrspace == AddrSpace.LOCAL` is a PARAMETER. The
# arm is `lt_po.w1(local, is_bufalloc)`; `lt_po_glob`/`lt_po_loc` are the two rows.
# ===========================================================================
# THE OP PREDICATES, LEAF FIRST. Seven arms of the ladder would be seven
# two-armed `match`es if each were written out, and each gets ITS OWN row (`po_*`)
# so that a mutation dropping one arm moves exactly that row -- the `k_alu_recip`
# lesson from kernel.bend's mutation table.
