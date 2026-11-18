<!-- FROM: tinybendygrad/codegen/opt/postrange.bend:551 -->
# BLOCK:
# `opt_ok` -- EVERY `check` in `apply_opt`'s SPLIT, PADTO and SWAP arms, plus
# `shift_to`'s first `check`, as one `Bool`. Python raises on the first failure,
# so the conjunct order below IS the order of the messages. `Bool.and` is not
# short-circuiting, so every conjunct is written to be total on its own.
#
# the two checks that are not here both need the ast and are wall #1:
#   * `smem_sz <= self.ren.shared_max` needs `self.reduceop.dtype.itemsize`.
#   * `reducers = [u for u in self.reduceops if rng in merge_dicts(...)]` needs
#     `UOp.ranges`. The CONDITION that reaches it (`new_type is UNROLL or
#     rng.axis_type is REDUCE`) IS here, and on every fixture below the
#     CONSEQUENT is vacuous: MEASURED on CPython, a LOCAL split of a REDUCE axis
#     on the 16x32 kernel SUCCEEDS, so `check(not any(...))` never fires and the
#     `reduces` conjunct is droppable. `ok_local_red` is that row.
# END BLOCK

# `opt_ok` -- EVERY `check` in `apply_opt`'s SPLIT, PADTO and SWAP arms, plus
# `shift_to`'s first `check`, as one `Bool`. Python raises on the first failure,
# so the conjunct order below IS the order of the messages. `Bool.and` is not
# short-circuiting, so every conjunct is written to be total on its own.
#
# the two checks that are not here both need the ast and are wall #1:
#   * `smem_sz <= self.ren.shared_max` needs `self.reduceop.dtype.itemsize`.
#   * `reducers = [u for u in self.reduceops if rng in merge_dicts(...)]` needs
#     `UOp.ranges`. The CONDITION that reaches it (`new_type is UNROLL or
#     rng.axis_type is REDUCE`) IS here, and on every fixture below the
#     CONSEQUENT is vacuous: MEASURED on CPython, a LOCAL split of a REDUCE axis
#     on the 16x32 kernel SUCCEEDS, so `check(not any(...))` never fires and the
#     `reduces` conjunct is droppable. `ok_local_red` is that row.
