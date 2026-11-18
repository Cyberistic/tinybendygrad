<!-- FROM: tinybendygrad/engine/realize.bend:2241 -->
# BLOCK:
# THE ROWS THAT ARE NOT DIRECT CPYTHON NUMBERS, AND WHY:
#
#   * `*_len`, `gate_count`, `arena_n`  -- structural COUNTS, not values.
#   * `res_ms_same`                     -- the MSTACK WALL: this file answers an
#                                         MSTACK unchanged, so the row asserts the
#                                         omission rather than hiding it.
#   * `lin_len`, `lin_first`            -- the REWRITE's shape. CPython's fixture
#                                         inner LINEAR has TWO srcs, so flattening
#                                         gives `want_lin_nsrc = 3`; this fixture's
#                                         has one, so 2 is right HERE.
#   * `arg_len`                         -- `want_args_len = 1`, because the
#                                         oracle's call passes a BOUND variable.
#                                         This fixture's `callP` passes two UNBOUND
#                                         PARAMs, so 2 is right here; `arg_len_b` is
#                                         the row shaped like the oracle's and is 1.
#   * `oi_in_e`                         -- `want_oi_enc` is `((0,), ())`, because
#                                         the oracle's `encdec` call also carries a
#                                         bound variable and drops to one arg uop.
#                                         This fixture's does not.
#   * `beam_new`                        -- `want_beam_val = 3`; the port passes
#                                         `ctx = 7`, and the row is that the
#                                         rewritten sink's `KernelInfo.beam` IS the
#                                         ctx value.
#   * `lin_none`, `beam_skip`           -- spelled `9`, not `0`. Both are
#                                         `rewrite` answering `None`, which is
#                                         `VSkip`, which `show_v` spells `9`; the
#                                         oracle prints `want_lin_none = True` and
#                                         `want_beam_skip = True` for "is None".
#                                         The two rows were documented as `1` and
#                                         `0` here, which was a MISPELLING of the
#                                         same answer and is corrected above.
#
