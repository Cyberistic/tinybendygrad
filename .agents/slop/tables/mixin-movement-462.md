<!-- FROM: tinybendygrad/mixin/movement.bend:462 -->
# BLOCK:
# EVERY ELEMENT IS A CONST, and it is ONE walk rather than two, which is the whole
# of `as_shape`'s concrete arm. Python writes it as a generator with a conditional
# (`s.val if s.op is Ops.CONST else ssimplify(s)`), and the `else` is the symbolic
# wall; here the walk carries a `Bool` and the element contributes nothing when the
# `Bool` is false, so one pass answers BOTH "are they all concrete" and "what are
# their values" -- and the `Bool` is the accumulator because an early exit from the
# middle of a walk needs a def that calls back into the walk, which is mutual
# recursion and is refused.
#
# THE `Bool` IS FOLDED WITH `Bool.or` AND NOT `Bool.and`, and that is deliberate
# and is the row `mxm_sym_NONE` pins: `sofar` is "have we SEEN a non-CONST", so the
# walk's answer is `not sofar` at the end and the element contributes
# `not is_const`. Reading it as "all concrete so far" and conjoining would be the
# same computation, and it is the one that made the FALSE arm fire for a STACK of
# all CONSTs in an earlier revision of this file.
# THE ELEMENT, as a list, and it contributes NOTHING once `bad` is set: a STACK with
# one symbolic element has no concrete shape, and a partial answer would be a lie
# the fold cannot see.
# END BLOCK

# EVERY ELEMENT IS A CONST, and it is ONE walk rather than two, which is the whole
# of `as_shape`'s concrete arm. Python writes it as a generator with a conditional
# (`s.val if s.op is Ops.CONST else ssimplify(s)`), and the `else` is the symbolic
# wall; here the walk carries a `Bool` and the element contributes nothing when the
# `Bool` is false, so one pass answers BOTH "are they all concrete" and "what are
# their values" -- and the `Bool` is the accumulator because an early exit from the
# middle of a walk needs a def that calls back into the walk, which is mutual
# recursion and is refused.
#
# THE `Bool` IS FOLDED WITH `Bool.or` AND NOT `Bool.and`, and that is deliberate
# and is the row `mxm_sym_NONE` pins: `sofar` is "have we SEEN a non-CONST", so the
# walk's answer is `not sofar` at the end and the element contributes
# `not is_const`. Reading it as "all concrete so far" and conjoining would be the
# same computation, and it is the one that made the FALSE arm fire for a STACK of
# all CONSTs in an earlier revision of this file.
# THE ELEMENT, as a list, and it contributes NOTHING once `bad` is set: a STACK with
# one symbolic element has no concrete shape, and a partial answer would be a lie
# the fold cannot see.
