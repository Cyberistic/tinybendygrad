<!-- FROM: tinybendygrad/uop/ops.bend:4189 -->
# BLOCK:
# THE ENGINE FAMILY (`_m`). PARALLEL to the `pm_rewrite` family above; this
# one returns the REPLACEMENT NODE, not just the verdict. `pm_rewrite` is the
# scan and decides which rule WANTS the node; `pm_rewrite_m` is the scan and
# the rule body's answer, which is the new U32 (or `None{}` to mean "no
# rewrite, rebuild with rewritten srcs").
#
# WHY A PARALLEL FAMILY. `uop/spec.bend` is the only consumer of `pm_rewrite`
# and reads the Verdict. The codegen rewrite engine is a NEW consumer and
# reads `Maybe<&2, U32>`. The two families co-exist until spec.bend moves
# off Verdict (it won't, in this unit). Each rule's `_m` body takes
# `(ctx: CTX, ar: Arena, self: U32)` and returns `Maybe<&2, U32>`.
# `ctx` is a `List<&2, U32>` here, which is the wall-passing shape from
# `walk_rewrite`; the engine threads it through the dispatch so the rule body
# can read it. The codegen pipeline eventually passes a typed `CTX` record
# and the `List<&2, U32>` becomes the new record's first projection.
# the rule bodies. The default for every rule is "no rewrite" (`None{}`).
# The no-op `pm_rewrite_m` body for a SINK is `Some(self)` so the engine
# does not have to special-case SINK in the rebuild step.
# END BLOCK

# THE ENGINE FAMILY (`_m`). PARALLEL to the `pm_rewrite` family above; this
# one returns the REPLACEMENT NODE, not just the verdict. `pm_rewrite` is the
# scan and decides which rule WANTS the node; `pm_rewrite_m` is the scan and
# the rule body's answer, which is the new U32 (or `None{}` to mean "no
# rewrite, rebuild with rewritten srcs").
#
# WHY A PARALLEL FAMILY. `uop/spec.bend` is the only consumer of `pm_rewrite`
# and reads the Verdict. The codegen rewrite engine is a NEW consumer and
# reads `Maybe<&2, U32>`. The two families co-exist until spec.bend moves
# off Verdict (it won't, in this unit). Each rule's `_m` body takes
# `(ctx: CTX, ar: Arena, self: U32)` and returns `Maybe<&2, U32>`.
# `ctx` is a `List<&2, U32>` here, which is the wall-passing shape from
# `walk_rewrite`; the engine threads it through the dispatch so the rule body
# can read it. The codegen pipeline eventually passes a typed `CTX` record
# and the `List<&2, U32>` becomes the new record's first projection.
# the rule bodies. The default for every rule is "no rewrite" (`None{}`).
# The no-op `pm_rewrite_m` body for a SINK is `Some(self)` so the engine
# does not have to special-case SINK in the rebuild step.
