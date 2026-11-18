<!-- FROM: tinybendygrad/uop/ops.bend:6592 -->
# BLOCK:
# the counter -- `collections.Counter` over node lists, as a list of pairs.
#
# ops.py:1073-1079 -- `UOp.gcd` and `UOp.divide_exact`.
#
# and the port has no integer-keyed map. measured 2026-11-08: `helpers.bend:494` says
# "Bend's `Map` is string-keyed only, so the set is a linear scan", and there is no
# `HashMap` and no `HashSet` in the port. but the port has the honest spelling already,
# TWICE: `dedup_u32` (`helpers.bend:500`) AND `merge_dicts` (`helpers.bend:2412`) ARE BOTH "A
# list of pairs with a linear scan", and `merge_dicts`'s own NOTE says exactly that: "a list
# of pairs is the honest representation". so the claim "the port has no multiset" was a
# claim about a container and not about a capability.
#
# and upstream's counter's keys are nodes, because a `UOp` is hashable by identity
# (`ops.py:219-220`: `__hash__ = tuple.__hash__` AND `__eq__` IS `self is other`). SO THE
# key is the arena's `U32` INDEX -- which is the node's identity in this port.
#
# and the count is a `U32` and not a `Nat`: a count of occurrences is a `U32`, and
# `Nat`'s ARITHMETIC IS A PRELUDE-LEVEL DETAIL (`Nat.add`/`Nat.mul` IN bend2's `safe.ts`)
# that the port uses only for fuel. and a `U32` literal is a plain number
# (`bend.ts:70`: "U32 | NUMBER").
#
# the four spelling rules, all measured 2026-11-08 against bend2's compiler.
#
# 1. a plain parameter may be consumed once and a `+`-binder may be consumed twice. two
#    PROBES: `def use2(x: U32) -> U32: U32.add(x, x)` REFUSES WITH "x (consumed more than
#    once)" and `def use2(+x: U32) -> U32: U32.add(x, x)` compiles and answers 6. and the
#    port's own `split_uop.pop` uses `+ar` and `+sep` twice each, so this is the tree's
#    CONVENTION AND NOT A NEW ONE.
# 2. a DEF's helper must come before its user -- "defs are checked in file order, and an
#    unfilled law has none". so the order below is the dependency order and not the
#    READING ORDER.
# 3. a `match` heads a DEF body and not a term, and a `match` may not scrutinize a
#    COMPUTED VALUE -- "a match cannot scrutinize a computed value: give it its own def".
#    so every comparison is a parameter and every branch is a DEF.
# 4. arguments are read left to right and each is passed unchanged until used, so a list's
#    tail may not be passed to two calls. and the port's own `Merge.go` is the pattern
#    -- `ops.bend:2843`: `Merge.go(t, Found.ar(f), List.append(&2, U32, map, [Found.i(f)]))`
#    -- the tail is the recursion's first argument and the accumulator is the third.
#
# THE ALGORITHM, AND IT IS UPSTREAM's.
#
# `collections.Counter` OVER NODE LISTS: `Counter(term.split_uop(Ops.MUL))` COUNTS THE
# MUL-factors of a term, and `functools.reduce(operator.and_, ...)` intersects the counters,
# and `operator.and_` on two counters is "the keys in both, with the minimum count".
#
# so the counter is a list of `(KEY, COUNT)` pairs, the intersection is the keys of the first
# counter with the minimum count across all of them, and the product is a FOLD over the pairs
# WITH `count` COPIES OF THE KEY.
# END BLOCK

# the counter -- `collections.Counter` over node lists, as a list of pairs.
#
# ops.py:1073-1079 -- `UOp.gcd` and `UOp.divide_exact`.
#
# and the port has no integer-keyed map. measured 2026-11-08: `helpers.bend:494` says
# "Bend's `Map` is string-keyed only, so the set is a linear scan", and there is no
# `HashMap` and no `HashSet` in the port. but the port has the honest spelling already,
# TWICE: `dedup_u32` (`helpers.bend:500`) AND `merge_dicts` (`helpers.bend:2412`) ARE BOTH "A
# list of pairs with a linear scan", and `merge_dicts`'s own NOTE says exactly that: "a list
# of pairs is the honest representation". so the claim "the port has no multiset" was a
# claim about a container and not about a capability.
#
# and upstream's counter's keys are nodes, because a `UOp` is hashable by identity
# (`ops.py:219-220`: `__hash__ = tuple.__hash__` AND `__eq__` IS `self is other`). SO THE
# key is the arena's `U32` INDEX -- which is the node's identity in this port.
#
# and the count is a `U32` and not a `Nat`: a count of occurrences is a `U32`, and
# `Nat`'s ARITHMETIC IS A PRELUDE-LEVEL DETAIL (`Nat.add`/`Nat.mul` IN bend2's `safe.ts`)
# that the port uses only for fuel. and a `U32` literal is a plain number
# (`bend.ts:70`: "U32 | NUMBER").
#
# the four spelling rules, all measured 2026-11-08 against bend2's compiler.
#
# 1. a plain parameter may be consumed once and a `+`-binder may be consumed twice. two
#    PROBES: `def use2(x: U32) -> U32: U32.add(x, x)` REFUSES WITH "x (consumed more than
#    once)" and `def use2(+x: U32) -> U32: U32.add(x, x)` compiles and answers 6. and the
#    port's own `split_uop.pop` uses `+ar` and `+sep` twice each, so this is the tree's
#    CONVENTION AND NOT A NEW ONE.
# 2. a DEF's helper must come before its user -- "defs are checked in file order, and an
#    unfilled law has none". so the order below is the dependency order and not the
#    READING ORDER.
# 3. a `match` heads a DEF body and not a term, and a `match` may not scrutinize a
#    COMPUTED VALUE -- "a match cannot scrutinize a computed value: give it its own def".
#    so every comparison is a parameter and every branch is a DEF.
# 4. arguments are read left to right and each is passed unchanged until used, so a list's
#    tail may not be passed to two calls. and the port's own `Merge.go` is the pattern
#    -- `ops.bend:2843`: `Merge.go(t, Found.ar(f), List.append(&2, U32, map, [Found.i(f)]))`
#    -- the tail is the recursion's first argument and the accumulator is the third.
#
# THE ALGORITHM, AND IT IS UPSTREAM's.
#
# `collections.Counter` OVER NODE LISTS: `Counter(term.split_uop(Ops.MUL))` COUNTS THE
# MUL-factors of a term, and `functools.reduce(operator.and_, ...)` intersects the counters,
# and `operator.and_` on two counters is "the keys in both, with the minimum count".
#
# so the counter is a list of `(KEY, COUNT)` pairs, the intersection is the keys of the first
# counter with the minimum count across all of them, and the product is a FOLD over the pairs
# WITH `count` COPIES OF THE KEY.
