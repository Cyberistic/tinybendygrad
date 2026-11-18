import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/engine/realize.bend"

EDITS = [
  # ---- `_resolve` (57 lines) -> 33. THE UPSTREAM BODY, THE NESTED-MATCH FACT, THE FUEL FACT
  # AND THE MEASURED REFUTATION STAY; THE PROSE GOES.
  (1161, 1217, """# `_resolve` -- realize.py:128-131, as ONE self-recursive def with a NESTED `match`.
#
#     if b.op in (Ops.MSELECT, Ops.SHRINK, Ops.BITCAST):
#       return b.replace(src=(_resolve(b.src[0], inputs), *b.src[1:]))
#     if b.op is Ops.MSTACK:
#       return b.replace(src=tuple(_resolve(x, inputs) for x in b.src))
#     return inputs[b.arg.slot] if b.op is Ops.PARAM else b
#
# THE NESTED MATCH IS LOAD-BEARING and this is the first file in the port that needed it.
# Splitting the arm dispatch into a helper is MUTUAL RECURSION -- the helper must call `rz_res` to
# recurse and `rz_res` must call the helper to dispatch -- and Bend refuses that outright. Keeping
# the arm `match` INSIDE the fuel `match` leaves exactly ONE call site, so the only recursion left
# is the self-call. `uop/spec.bend`'s drivers never need this because they do not recurse into the
# arena.
#
# The fuel is a `Nat` and comes FIRST because a self-call reads its arguments LEFT TO RIGHT and
# stops at the first that shrinks, so the fuel is what makes the call decreasing and everything
# after it is free. `case 0n` answers the node UNCHANGED, so too small a fuel is a MISS and never
# a wrong value. `rz_res_fuel` is the exact bound and it is `Arena.budget`.
#
# ARM 1 (`Ops.MSTACK`) IS NOT PORTED, and the wall is the SAME mutual recursion one level up. The
# arm applies `_resolve` to EVERY src, so it needs a WALK over a list, and the walk calls
# `_resolve` on each element while `_resolve`'s MSTACK arm calls the walk. Two shapes were measured
# and both refused:
#
#   * a `rz_res.ms(todo, ...)` beside `rz_res` -- mutual recursion, refused;
#   * ONE def carrying `(fuel, pending, accumulator, arena, inputs)` -- a self-call must pass a
#     SUBTERM of its own parameter, and the pending list is REBUILT by the step rather than being
#     one, so the check refuses it too.
#
# one of those two refutations is now measured and is wrong, and the rule behind it is stated wrong:
# a self-call does not need a subterm of its own parameter, it needs one argument that shrinks, and
# it reads them left to right and stops at the first one, so the shrinking argument has to LEAD.
# `rz_prod.fold` and `ka_go` both put the list tail first and both are accepted; with the tail last
# they are refused with "expected a decreasing self-call". So the worklist shape the header
# guessed at -- a LIST TAIL -- is the right answer, and the "rebuilt rather than a subterm"
# objection does not apply to it.
#
# SO WHAT IS LEFT, and it is not the shape, is the ARENA. The walk has to call `rz_res` per src,
# `rz_res` GROWS the arena on a view arm, and each growth has to reach the next element and the
# answer -- which is the same defect just fixed in `rz_find` and `rz_beam_sink`, where a bare index
# was returned from an arena the caller did not hold. Here the accumulator is `rz_res`'s OWN
# parameter and a self-call may not rewrite an argument, so the queue needs its own record the way
# `RList` is its own record above. That, plus a fixture: `main_arena` has no MSTACK node, so the
# arm could not be ROWED without adding one, and adding one moves `arena_n` and every index after
# it. Not worth doing inside a fix for the Bool selectors.
#
# SO `rz_res` answers an MSTACK UNCHANGED and the gate row is `res_ms_same`: not a wrong value, a
# MISSING one. That direction is the safe one -- an unresolved MSTACK leaves the argument pointing
# at the node the caller already had -- and `res_ms_same` is what makes the omission VISIBLE
# instead of silent."""),
]

apply(F, EDITS)
