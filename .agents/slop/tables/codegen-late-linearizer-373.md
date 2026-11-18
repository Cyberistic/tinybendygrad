<!-- FROM: tinybendygrad/codegen/late/linearizer.bend:373 -->
# BLOCK:
# THE PRIORITY LADDER, linearizer.py:24-32. PORTED IN FULL, all eight arms.
#
# UPSTREAM'S FIVE COMMENTS ON IT ARE THE DOCSTRING OF THE WHOLE SCHEDULING
# DECISION, and they are kept because the numbers alone do not say why:
#
#   "get consumers and assign priorities" (14)
#   "NOTE: this requires the lst be locally toposorted" (15)
#       the priorities are assigned in a REVERSED toposort walk, so a node's
#       consumers are all known before it is numbered -- but that only works
#       if the list is toposorted to begin with.
#   "we place UOps with higher run_counts later" (19)
#       so the primary key is the RUN COUNT -- how many times the node's body
#       executes -- and a node that runs MORE is placed LATER. A node inside a
#       big loop is deferred; a node outside it is hoisted. That is the
#       "innermost last" shape of a generated kernel.
#   "simple priority override. this is all bottom up now, smaller numbers will
#    be closer to the top" (22)
#       the priority is an OVERRIDE on the run-count order, and it is read
#       bottom-up: a SMALLER priority number means CLOSER TO THE TOP. So the
#       negative numbers are the ones that get hoisted.
#   "the order and placement of these defines is important" (25)
#       and this is a warning about the ARM ORDER, not about the values: the
#       ladder is a `match` on the op and the arms are not interchangeable.
#       `PARAM` is first and it is the only one with an `extra`.
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
# AND THE THREE ARMS THAT CARRY THEIR OWN REASON INLINE -- upstream's own
# comments on the ladder's arms -- are the whole of what the numbers mean:
# "place loads early" (-1), "place stores late" (1), "placing RANGE is good"
# (5), and "placing loop exits is bad" (-5). A LOOP EXIT is bad because it
# ends a loop: hoisting it above the loop body would close the loop early.
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
# `# TODO(p3) linearizer.py:50  symbol=linearize  the DEBUG_LINEARIZE print reads `extra` -- the one
# place Python reads the field, and env-gated.`
#
# W4: the BUFFER/ALLOC arm's `u.addrspace == AddrSpace.LOCAL` is a PARAMETER. The
# arm is `lt_po.w1(local, is_bufalloc)`; `lt_po_glob`/`lt_po_loc` are the two rows.
# END BLOCK

# THE PRIORITY LADDER, linearizer.py:24-32. PORTED IN FULL, all eight arms.
#
# UPSTREAM'S FIVE COMMENTS ON IT ARE THE DOCSTRING OF THE WHOLE SCHEDULING
# DECISION, and they are kept because the numbers alone do not say why:
#
#   "get consumers and assign priorities" (14)
#   "NOTE: this requires the lst be locally toposorted" (15)
#       the priorities are assigned in a REVERSED toposort walk, so a node's
#       consumers are all known before it is numbered -- but that only works
#       if the list is toposorted to begin with.
#   "we place UOps with higher run_counts later" (19)
#       so the primary key is the RUN COUNT -- how many times the node's body
#       executes -- and a node that runs MORE is placed LATER. A node inside a
#       big loop is deferred; a node outside it is hoisted. That is the
#       "innermost last" shape of a generated kernel.
#   "simple priority override. this is all bottom up now, smaller numbers will
#    be closer to the top" (22)
#       the priority is an OVERRIDE on the run-count order, and it is read
#       bottom-up: a SMALLER priority number means CLOSER TO THE TOP. So the
#       negative numbers are the ones that get hoisted.
#   "the order and placement of these defines is important" (25)
#       and this is a warning about the ARM ORDER, not about the values: the
#       ladder is a `match` on the op and the arms are not interchangeable.
#       `PARAM` is first and it is the only one with an `extra`.
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
# AND THE THREE ARMS THAT CARRY THEIR OWN REASON INLINE -- upstream's own
# comments on the ladder's arms -- are the whole of what the numbers mean:
# "place loads early" (-1), "place stores late" (1), "placing RANGE is good"
# (5), and "placing loop exits is bad" (-5). A LOOP EXIT is bad because it
# ends a loop: hoisting it above the loop body would close the loop early.
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
# `# TODO(p3) linearizer.py:50  symbol=linearize  the DEBUG_LINEARIZE print reads `extra` -- the one
# place Python reads the field, and env-gated.`
#
# W4: the BUFFER/ALLOC arm's `u.addrspace == AddrSpace.LOCAL` is a PARAMETER. The
# arm is `lt_po.w1(local, is_bufalloc)`; `lt_po_glob`/`lt_po_loc` are the two rows.
