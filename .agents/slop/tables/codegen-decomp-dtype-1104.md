<!-- FROM: tinybendygrad/codegen/decomp/dtype.bend:1104 -->
# BLOCK:
# ONE `.where` PAIR PER STEP, with every record and index passed as a `U32`, so
# nothing is read twice: `W2.ar`/`W2.lo`/`W2.hi` are three CALLS on one record and
# a `Found`'s `.ar`/`.i` are two, so every intermediate is destructured once.
#
# THE SHIFT AMOUNT IS `i % 32`, NOT `i`. dtype.py:68 writes
# `shl(cond.cast(dtypes.uint), i % 32)` and `shl` is transcendental.py:20,
# `x * 2y` -- so for `i = 63` the constant is `2**31` = `C(2147483648)` and NOT
# `2**63`, which `tx_powi(63)` builds as the 64-bit `C(2147483648:0)`. `U32.mod` is
# a machine word, so the reduction is exact and needs no special case.
#
# stale measurement in a comment is a measurement that gets cited. It claimed: "CPython's
# cone constants after the fixed six are `C(63), C(62), ..., C(2)` ... while the port
# printed `C(64)` and `C(2147483648)` there and NEVER PRODUCED A `2**31` AT ALL."
# Re-measured on the live tree, the port DOES print `2**31`. The port's `lgqk` is
#
#     C(0),C(1),C(32),C(1),C(31),C(-1),C(64),C(2147483648),C(1073741824),...
#
# and CPython's is
#
#     C(0),C(1),C(32),C(1),C(31),C(-1),C(63),C(62),C(61),C(60),...,C(33),
#     C(2147483648),C(30),C(1073741824),C(29),...
#
# So the real difference is not a missing power of two. It is that the port emits ONE
# leading word `C(64)` and then a RUN of powers of two, while CPython interleaves
# `C(i)` with `2(i-32)` for i = 63..33 -- the port never emits the 31 `UOp.const(i,
# dtypes.uint)` shift words of dtype.py:65 at all. Whether that is the TRUNCDIV loop or the
# `q` accumulator is not yet established; `lgtk` is still 3 constants against CPython's
# 66 and `lgtsig` 57 cone nodes against 2184, so the family is OPEN. `.agents/slop/
# dd-truth.py` is what prints both sequences side by side.
# END BLOCK

# ONE `.where` PAIR PER STEP, with every record and index passed as a `U32`, so
# nothing is read twice: `W2.ar`/`W2.lo`/`W2.hi` are three CALLS on one record and
# a `Found`'s `.ar`/`.i` are two, so every intermediate is destructured once.
#
# THE SHIFT AMOUNT IS `i % 32`, NOT `i`. dtype.py:68 writes
# `shl(cond.cast(dtypes.uint), i % 32)` and `shl` is transcendental.py:20,
# `x * 2y` -- so for `i = 63` the constant is `2**31` = `C(2147483648)` and NOT
# `2**63`, which `tx_powi(63)` builds as the 64-bit `C(2147483648:0)`. `U32.mod` is
# a machine word, so the reduction is exact and needs no special case.
#
# stale measurement in a comment is a measurement that gets cited. It claimed: "CPython's
# cone constants after the fixed six are `C(63), C(62), ..., C(2)` ... while the port
# printed `C(64)` and `C(2147483648)` there and NEVER PRODUCED A `2**31` AT ALL."
# Re-measured on the live tree, the port DOES print `2**31`. The port's `lgqk` is
#
#     C(0),C(1),C(32),C(1),C(31),C(-1),C(64),C(2147483648),C(1073741824),...
#
# and CPython's is
#
#     C(0),C(1),C(32),C(1),C(31),C(-1),C(63),C(62),C(61),C(60),...,C(33),
#     C(2147483648),C(30),C(1073741824),C(29),...
#
# So the real difference is not a missing power of two. It is that the port emits ONE
# leading word `C(64)` and then a RUN of powers of two, while CPython interleaves
# `C(i)` with `2(i-32)` for i = 63..33 -- the port never emits the 31 `UOp.const(i,
# dtypes.uint)` shift words of dtype.py:65 at all. Whether that is the TRUNCDIV loop or the
# `q` accumulator is not yet established; `lgtk` is still 3 constants against CPython's
# 66 and `lgtsig` 57 cone nodes against 2184, so the family is OPEN. `.agents/slop/
# dd-truth.py` is what prints both sequences side by side.
