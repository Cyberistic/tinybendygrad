<!-- FROM: tinybendygrad/helpers.bend:633 -->
# BLOCK:
# `ShapeRes.of` is Python's `if not all_same(subs): raise; (len(subs),) +
# subs[0]`, so a sequence of scalars has shape (n,), not (), and an empty
# sequence has shape (0,). The all_same walk is ONE def carrying the state
# Python's generator carries: `ref` is the first non-() child's dims and `bad`
# is "a () met a non()". The child list is the FIRST argument so the recursion
# decreases structurally and the rest of the state is free.
#
# The three rules are Python's `all_same`:
#   all ()        -> (n,)            every child is a scalar
#   all equal d   -> (n,) + d        the homogeneous case
#   anything else -> SBad            Python's ValueError
#
# the first child sets the reference: a scalar leaves it None, a shape sets it
# END BLOCK

# `ShapeRes.of` is Python's `if not all_same(subs): raise; (len(subs),) +
# subs[0]`, so a sequence of scalars has shape (n,), not (), and an empty
# sequence has shape (0,). The all_same walk is ONE def carrying the state
# Python's generator carries: `ref` is the first non-() child's dims and `bad`
# is "a () met a non()". The child list is the FIRST argument so the recursion
# decreases structurally and the rest of the state is free.
#
# The three rules are Python's `all_same`:
#   all ()        -> (n,)            every child is a scalar
#   all equal d   -> (n,) + d        the homogeneous case
#   anything else -> SBad            Python's ValueError
#
# the first child sets the reference: a scalar leaves it None, a shape sets it
