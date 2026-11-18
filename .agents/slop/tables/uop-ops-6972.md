<!-- FROM: tinybendygrad/uop/ops.bend:6972 -->
# BLOCK:
# `UOp.gcd` AND `UOp.divide_exact` -- ops.py:1073-1079.
#
# and both are built on the counter (above), and the counter is a list of pairs
# because the port has no integer-keyed map -- measured 2026-11-08, `helpers.bend:494`:
# "Bend's `Map` is string-keyed only, so the set is a linear scan".
#
# `UOp.gcd(*uops)` -- ops.py:1073:
#
#     terms, factors = zip(*[u.pop_const(Ops.MUL) for u in uops])
#     count = functools.reduce(operator.and_, [Counter(t.split_uop(Ops.MUL)) for t in terms])
#     if not count: factors = tuple(u.const_factor() for u in uops)
#     return math.prod(count.elements(), start=uops[0].const_like(math.gcd(*factors)))
#
# and the port's spelling follows it step for step, with three measured substitutions:
#
#   * `pop_const(Ops.MUL)` returns `(NODE, CONST)` upstream, and the port has only the
#     CONST half (`pop_const_val`/`pop_const_hits`). so the port spells the node half
#     DIRECTLY: A `MUL` WHOSE SECOND SRC IS A CONST IS `(src[0], that const)` AND ANYTHING
#     ELSE IS `(self, identity)`, AND `identity_element(MUL, dt)` IS 1 UPSTREAM
#     (`ops.py:81`: `{Ops.ADD:0, Ops.MUL:1, Ops.MAX:dt.min}[op]`).
#   * `const_like` is not ported (`ops.py:581`, a bare `TODO(p3)` with no wall named),
#     and the port's arena has no shape field -- so the shaped half cannot be spelled.
#     but measured 2026-11-07 on CPYTHON: for the `(x*y)/y` case, `x` is a variable and
#     has no shape, so `x.const_like(1)` takes the unshaped branch and is
#     `UOp.const(1, dtype)`. so the port spells the unshaped `const_like`, which is
#     `UOp.const(b, dt)`, and the shaped half is a separate matter.
#   * `math.gcd(*factors)` is a FOLD over a list of I64s, and the port has `H.gcd` for
#     TWO OF THEM (`helpers.bend:2249`) -- SO THE VARIADIC FORM IS A FOLD.
#
# and `Counter.elements()` -- which repeats each key by its count -- is the port's own
# `H.make_tuple_rep` (`helpers.bend:1282`: `make_tuple_rep(x, cnt) -> List<&2, U32>`), SO
# the product is a concatenation of those and not a hand-unrolled recursion.
#
# and every comparison is a parameter and not a computed value -- measured 2026-11-08:
# "a match cannot scrutinize a computed value: give it its own def" -- AND A `match` OVER A
# call is also a computed value, so the comparison is done in a helper and its result is
# PASSED IN.
#
# THE NODE HALF OF `pop_const(Ops.MUL)`.
# END BLOCK

# `UOp.gcd` AND `UOp.divide_exact` -- ops.py:1073-1079.
#
# and both are built on the counter (above), and the counter is a list of pairs
# because the port has no integer-keyed map -- measured 2026-11-08, `helpers.bend:494`:
# "Bend's `Map` is string-keyed only, so the set is a linear scan".
#
# `UOp.gcd(*uops)` -- ops.py:1073:
#
#     terms, factors = zip(*[u.pop_const(Ops.MUL) for u in uops])
#     count = functools.reduce(operator.and_, [Counter(t.split_uop(Ops.MUL)) for t in terms])
#     if not count: factors = tuple(u.const_factor() for u in uops)
#     return math.prod(count.elements(), start=uops[0].const_like(math.gcd(*factors)))
#
# and the port's spelling follows it step for step, with three measured substitutions:
#
#   * `pop_const(Ops.MUL)` returns `(NODE, CONST)` upstream, and the port has only the
#     CONST half (`pop_const_val`/`pop_const_hits`). so the port spells the node half
#     DIRECTLY: A `MUL` WHOSE SECOND SRC IS A CONST IS `(src[0], that const)` AND ANYTHING
#     ELSE IS `(self, identity)`, AND `identity_element(MUL, dt)` IS 1 UPSTREAM
#     (`ops.py:81`: `{Ops.ADD:0, Ops.MUL:1, Ops.MAX:dt.min}[op]`).
#   * `const_like` is not ported (`ops.py:581`, a bare `TODO(p3)` with no wall named),
#     and the port's arena has no shape field -- so the shaped half cannot be spelled.
#     but measured 2026-11-07 on CPYTHON: for the `(x*y)/y` case, `x` is a variable and
#     has no shape, so `x.const_like(1)` takes the unshaped branch and is
#     `UOp.const(1, dtype)`. so the port spells the unshaped `const_like`, which is
#     `UOp.const(b, dt)`, and the shaped half is a separate matter.
#   * `math.gcd(*factors)` is a FOLD over a list of I64s, and the port has `H.gcd` for
#     TWO OF THEM (`helpers.bend:2249`) -- SO THE VARIADIC FORM IS A FOLD.
#
# and `Counter.elements()` -- which repeats each key by its count -- is the port's own
# `H.make_tuple_rep` (`helpers.bend:1282`: `make_tuple_rep(x, cnt) -> List<&2, U32>`), SO
# the product is a concatenation of those and not a hand-unrolled recursion.
#
# and every comparison is a parameter and not a computed value -- measured 2026-11-08:
# "a match cannot scrutinize a computed value: give it its own def" -- AND A `match` OVER A
# call is also a computed value, so the comparison is done in a helper and its result is
# PASSED IN.
#
# THE NODE HALF OF `pop_const(Ops.MUL)`.
