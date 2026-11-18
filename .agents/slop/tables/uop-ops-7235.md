<!-- FROM: tinybendygrad/uop/ops.bend:7235 -->
# BLOCK:
# THE FOUR ARMS OF `divide_exact`, IN UPSTREAM's ORDER.
#
# and every comparison is a parameter and not a computed value -- measured 2026-11-08:
# "a match cannot scrutinize a computed value: give it its own def" -- AND A `match` OVER A
# call is also a computed value, so the op is read into a parameter first.
#
# and the answer is a `Dq` and not a `Maybe` -- and that is because the two srcs' answers
# must be bound and a `Maybe` is a TYPE and not a `Data`, and a `+` binder's TYPE
# MUST BE `Data` -- MEASURED 2026-11-08: "Note: +m can be used many times, so its type must be
# Data". and the port's own `UOp.divides.op` is the pattern that works (`ops.bend:7887`):
# one DEF, a `match` on the op, two direct self-calls bound with `+` in the ADD's arm, and
# the results combined by a helper. and a `Dq{ok: Bool, f: Found}` is exactly the port's own
# `Dv{ok: Bool, f: Found}` shape (`ops.bend:8050`) -- so the answer's TYPE is the port's own
# ANSWER TYPE AND NOT A NEW ONE.
#
# and `None{}` is upstream's `None`, which is the "we aren't sure" answer and not an
# ERROR -- AND IT IS THE `ok: False` HALF OF THE RECORD.
# the answer: the port's own `Dv` shape -- `ok` says whether it divides exactly and `f`
# IS THE QUOTIENT's NODE.
# END BLOCK

# THE FOUR ARMS OF `divide_exact`, IN UPSTREAM's ORDER.
#
# and every comparison is a parameter and not a computed value -- measured 2026-11-08:
# "a match cannot scrutinize a computed value: give it its own def" -- AND A `match` OVER A
# call is also a computed value, so the op is read into a parameter first.
#
# and the answer is a `Dq` and not a `Maybe` -- and that is because the two srcs' answers
# must be bound and a `Maybe` is a TYPE and not a `Data`, and a `+` binder's TYPE
# MUST BE `Data` -- MEASURED 2026-11-08: "Note: +m can be used many times, so its type must be
# Data". and the port's own `UOp.divides.op` is the pattern that works (`ops.bend:7887`):
# one DEF, a `match` on the op, two direct self-calls bound with `+` in the ADD's arm, and
# the results combined by a helper. and a `Dq{ok: Bool, f: Found}` is exactly the port's own
# `Dv{ok: Bool, f: Found}` shape (`ops.bend:8050`) -- so the answer's TYPE is the port's own
# ANSWER TYPE AND NOT A NEW ONE.
#
# and `None{}` is upstream's `None`, which is the "we aren't sure" answer and not an
# ERROR -- AND IT IS THE `ok: False` HALF OF THE RECORD.
# the answer: the port's own `Dv` shape -- `ok` says whether it divides exactly and `f`
# IS THE QUOTIENT's NODE.
