<!-- FROM: tinybendygrad/schedule/__init__.bend:2037 -->
# BLOCK:
# `apply_binds`'s THREE ARMS, AND `resolve_linear_call` ITSELF -- __init__.py:95-111.
#
#   linear = graph_rewrite(linear_call.body, pm_post_sched_cache,
#                          ctx=linear_call.src[1:], walk=True)
#   return linear.replace(src=tuple(apply_binds(si) for si in linear.src))
#
# THE last line is `replace` OVER `linear.src` AND not a second graph rewrite --
# `pm_resolve_linear_call` (the table that DOES apply this to a whole graph) belongs
# to `create_linear_with_vars`, one level up.  Reading the header instead of the body
# would have built a driver nobody asked for.
#
# ARM 1 IS refused and the reason is measured, NOT assumed: it recurses into
# `resolve_linear_call(si, binds)`, and this def already calls `sc_apply_binds`, so a
# faithful port is MUTUAL RECURSION between two defs -- which Bend does not have
# (its rule is defined-before-use, and the tree records the same limit where
# `Kahn.gather` threads an `ok` flag "because an early return from the middle of a
# self-call would need mutual recursion").  A `Some{}` here would be a WRONG ANSWER
# shaped like a success; `None{}` is a refusal the caller can see.
# `resolve_linear_call(si, binds)` -- THE RECURSION -- and the port answered
# `None{}` because upstream's shape is mutual recursion and Bend has none.
#
# THE machine below is a work item and a fuel, AND every one of its constraints was
# MEASURED IN A MINIMAL FILE FIRST:
#   1. `match` ON A COMPUTED VALUE IS REFUSED, even inside a self-recursive def
#      ("give it its own def"), and "its own def" reintroduces the forward
#      reference. SO EVERY SCRUTINEE IS A FIELD, decided in the ONE `match fuel w`.
#   2. THE FUEL IS THE FIRST ARGUMENT. Inside the Data the checker answers "a
#      decreasing self-call ... observed : w"; with `(fuel, w)` it is accepted.
#   3. `case 1n++k:` IS A COPYABLE SUCCESSOR BINDER, so one step can spend the fuel
#      on BOTH the nested call and the continuation.
#   4. `RJoin` IS THE TRICK: a non-tail self-call cannot be followed by another, so
#      arm 1's CONTINUATION is a work item carrying the nested result.
#   5. A DOWNSTREAM ITEM CARRIES `lin` AS A `U32`, NOT A `Maybe` -- reconstructing
#      `Some{lin}` and then passing it is what made a `Map` look linear.
# END BLOCK

# `apply_binds`'s THREE ARMS, AND `resolve_linear_call` ITSELF -- __init__.py:95-111.
#
#   linear = graph_rewrite(linear_call.body, pm_post_sched_cache,
#                          ctx=linear_call.src[1:], walk=True)
#   return linear.replace(src=tuple(apply_binds(si) for si in linear.src))
#
# THE last line is `replace` OVER `linear.src` AND not a second graph rewrite --
# `pm_resolve_linear_call` (the table that DOES apply this to a whole graph) belongs
# to `create_linear_with_vars`, one level up.  Reading the header instead of the body
# would have built a driver nobody asked for.
#
# ARM 1 IS refused and the reason is measured, NOT assumed: it recurses into
# `resolve_linear_call(si, binds)`, and this def already calls `sc_apply_binds`, so a
# faithful port is MUTUAL RECURSION between two defs -- which Bend does not have
# (its rule is defined-before-use, and the tree records the same limit where
# `Kahn.gather` threads an `ok` flag "because an early return from the middle of a
# self-call would need mutual recursion").  A `Some{}` here would be a WRONG ANSWER
# shaped like a success; `None{}` is a refusal the caller can see.
# `resolve_linear_call(si, binds)` -- THE RECURSION -- and the port answered
# `None{}` because upstream's shape is mutual recursion and Bend has none.
#
# THE machine below is a work item and a fuel, AND every one of its constraints was
# MEASURED IN A MINIMAL FILE FIRST:
#   1. `match` ON A COMPUTED VALUE IS REFUSED, even inside a self-recursive def
#      ("give it its own def"), and "its own def" reintroduces the forward
#      reference. SO EVERY SCRUTINEE IS A FIELD, decided in the ONE `match fuel w`.
#   2. THE FUEL IS THE FIRST ARGUMENT. Inside the Data the checker answers "a
#      decreasing self-call ... observed : w"; with `(fuel, w)` it is accepted.
#   3. `case 1n++k:` IS A COPYABLE SUCCESSOR BINDER, so one step can spend the fuel
#      on BOTH the nested call and the continuation.
#   4. `RJoin` IS THE TRICK: a non-tail self-call cannot be followed by another, so
#      arm 1's CONTINUATION is a work item carrying the nested result.
#   5. A DOWNSTREAM ITEM CARRIES `lin` AS A `U32`, NOT A `Maybe` -- reconstructing
#      `Some{lin}` and then passing it is what made a `Map` look linear.
