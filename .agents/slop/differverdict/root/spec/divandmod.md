# divandmod: FLOORDIV/FLOORMOD folding, and a brief that was wrong three ways

`divandmod.py` is 109 lines. Four of them are the matcher and eighty-nine are
`fold_divmod_general`. The file is `tinybendygrad/uop/divandmod.bend`.

The honest story of this unit is that **the brief's premises were wrong in three
places, all three measured before a line was written, and all three recorded in
the file header so nobody re-derives them.** Two of them decided whether the file
was possible at all.

## What we gain

- **The premise check is itself the deliverable.** There is no `divmod_legal`
  and no `fast_divmod` in this repo: `rg -n 'fast_divmod|divmod_legal'
  tinygrad/ test/` is empty. The magic-multiplier code is `fast_idiv`, in
  `tinygrad/codegen/decomp/op.py`, a different unit. The multiply-high question
  this file was meant to answer does not arise here.
- **There is no `graph_rewrite` in this file either.** `divandmod.py` builds a
  `PatternMatcher` and stops; `symbolic.py:7` is what imports it. So the
  "a rule RETURNS THE ARENA" engine shape from `spec/engine.md` does not apply
  to the table, and the file uses `uop/spec.bend`'s first-wins scan instead.
- **The engine shape's one surviving purchase is the accumulator.** `PatternMatcher.rewrite`
  returns the FIRST non-`None`, and these rules GROW the arena, so the answer is
  the arena *and* a node index *and* whether anything fired: `Hit{ar, i, on}`.
  A scan returning only a node index would throw the growth away.
- **A `Maybe` cannot be a field of a `Data` record** (`bend2-constraints` rule
  15), so the "did it fire" flag is a `U32`. The index is meaningless when it is
  0 — and 0 is the arena's reserved bottom node, so it cannot serve as the
  sentinel either.
- **The gate is a string, because a node is not a comparable value.** `out_r15`
  and `out_r16` are `CONST(-2)` and `SUB(CONST(-7),MUL(CONST(-2),CONST(4)))`;
  they are the FLOOR-semantics rows, and a truncating port prints 3 and -1.
  The printer prints CONST *values*, not just op names, so the floor/trunc
  distinction is visible in the gate at all.
- **The printer's depth is a parameter, not a bug.** A real recursive printer
  needs `print(node) -> srcs -> print`, which is mutual recursion and refused
  outright, and a fuel cannot rescue it because a binop spends one fuel on TWO
  self-calls (`bend2-constraints` rule 5). So depth is a parameter, and it is
  exactly as deep as the answers need.
- **`grown_r02=4` is a numeric witness for a claim about ambiguity.** Three rules
  claim one node and two answer differently; the file says so and pins the count.
- **55 gate rows, `nrules=3`, `rej0=2 rej1=2 rej2=0`, both lanes byte-identical,
  18 mutations measured.** The `rej` counts are there because a mis-spelled
  reject set is silent.

## The three arms that survived, and why each one

Of `fold_divmod_general`'s 89 lines, 60 are interval arithmetic over symbolic
UOps. Three arms survive, each for a stated reason:

- `divandmod.py:11` `if y.vmin==y.vmax==0: raise` — a CONST's `_min_max` IS
  `(val, val)` and a PARAM's IS `arg.vmin_vmax`, so BOTH cases are one `arg`
  read. Ported as a `Bool` because Bend has no `raise`; `zero_r04`/`zero_r11`/
  `zero_r23` are the rows.
- `divandmod.py:13` `(xdiv:=x//y).vmin == xdiv.vmax` — for two CONSTs `_min_max`
  is four identical `a//b`, so the test is ALWAYS true there and this arm is
  EXACT rather than conservative on CONST/CONST. Outside CONST/CONST it needs
  the range and is a TODO.
- `divandmod.py:15` `x.arg.multiple_of % y.val == 0` — NO RANGE AT ALL, a field
  read. Ported in full, and the DEFAULT is load-bearing: `UOp.variable`'s
  `multiple_of` defaults to 1 and `1 % 1 == 0`, so `FLOORMOD(param, CONST(1))`
  rewrites to `CONST(0)`. `r18` is that row.

## What it cost

- **`Ops.ADD` is commutative, so `UPat.cvar("c") + UPat.cvar("a")` is an
  `is_any` over BOTH ORDERS.** Both rules' numerators are a two-way
  disjunction; writing it as a conjunction drops `r01` and `r08` and typechecks.
  Exactly one alternative can match, so there is no store to disambiguate and
  **not one `U32.is_eq` identity check appears in this file.**
- **The reject sets are not empty.** Rules 0 and 1 reject on `[ADD, CONST]`;
  rule 2 rejects on `[]` because its `src` is `None`. `r22` is the row where a
  three-src FLOORDIV falls to rule 2, which is what Python does before its
  `x, y = d.src` raises.
- **No promotion CASTs.** Python's `UOp.__init__` runs `dtype_from_uop`, so
  `a*c` with a weakint `a` is `CAST(MUL(C(5),C(3)))`; `ops.bend`'s `UOp.new` is
  `UOp.make` and nothing else. The ALGEBRA is unchanged, the NODE COUNT is not,
  which is why no Python node count is a gate row and the `grown` rows are
  port-internal.
- **No sub canonicalisation and no constant folding.** `x - q*y` is
  `SUB(x, MUL(q,y))` here and `ADD(x, MUL(MUL(q,y), C(-1)))` in Python; `C(5)*C(3)`
  survives as a MUL here. So `r14`/`r16` are checked by VALUE, not by shape.
- **A non-int CONST is not a `vmin`.** `UPat.cvar` accepts a `CFloat`, so Python
  compares a float; `dm_val` reads `CInt` only, so rules 0 and 1 SKIP where
  Python rewrites. That is the `_min_max` PyConst wall at miniature size.
- **Two shared helpers in `helpers.bend` are wrong, and one of them was found
  here.** `floordiv_i32`/`floormod_i32` add one whenever the division is inexact
  and ignore `neg`: `6//4 == 2`, `10//3 == 4`, `1000//7 == 143`, `6%4 == -2`,
  where Python says 1, 3, 142, 2 — and a non-negative inexact division is the
  case this file is ALL about. `H.asr` is also broken (`shrn(v,31)` is the sign
  bit, so `H.asr(-1,1)` prints 2147483647 where the answer is 4294967295). Both
  are unused and untested upstream, which is why ten green rows elsewhere never
  saw them. Reported, not fixed: `helpers.bend` is another unit's.
- **The wall is one export.** `Word.mul` is the only widening multiply in Bend 2
  and `base.bend` does not export `Word`'s constructors, so a magic multiplier
  is a WALL for whoever takes `fast_idiv`, not a TODO: either `Word`/`WCon`
  become public, or the 64-bit product is four `U32` multiplies and a carry
  chain. `H.I64` has `i64_add`/`i64_sub`/`i64_cmp` and NOT `i64_mul`.

## The one wall, and it is not a bench limitation

`UOp._min_max` (ops.py:1104), which `fold.bend:2176` already records as the
biggest single piece left in that half of ops.py. `H.I64` has no `i64_mul`,
`i64_div` or `i64_mod`; the arms read `self.dtype.min`/`.max` at 64 bits
(`dtype.bend`, unimportable, and it is the C-effect seam) and one LOAD arm
decodes a `memoryview` of a BINARY blob.

A limit worth keeping: `dm_which.go` and `dm_cside.go` are the two halves of the
same mistake and the gate moves the SAME sixteen rows for either, because from
the outside "which side is the CONST" and "which side is the quotient" are one
question. That is a limitation of this gate, not a coincidence; fixing it needs
a fixture where the quotient is on src1 AND the CONST is also on src1.

## Not done

- `divandmod.py:13` the range half of "`x//y` being a point" outside CONST/CONST.
- `divandmod.py:13-15` a FLOAT CONST divisor (`_min_max` returns PyConst).
- `divandmod.py:17-19` `pop_const()` and `split_uop(Ops.ADD)` — expressible, but
  P3 for SCOPE, not impossibility; they land with line 23.
- `divandmod.py:23-25` `nested_div` — needs `divides` → `gcd` → a `Counter` fold.
- `divandmod.py:28-35` `remove_nested_mod` — `divides`, same wall.
- `divandmod.py:37-48` `fold_divmod_congruence` — the worst one: a cartesian
  product over per-term sign choices, then interval arithmetic over a symbolic
  SUM. Bend has no cartesian product and no `min` over three with a key.
- `divandmod.py:50-55` `gcd_with_remainder` — `math.gcd` over a variadic is
  expressible; `divides`, `simplify` and `new_x.vmin >= 0` are not.
- `divandmod.py:57-70` `nest_by_factor` — a set comprehension, then a RECURSIVE
  call to `fold_divmod_general` (mutual recursion, refused outright), then
  `backward_slice` twice. The largest single omission in the file.
- `divandmod.py:75-96` `divide_by_gcd` and `factor_remainder` — `gcd`,
  `const_factor`, `simplify`, `_min_max`.
- `divandmod.py:11` the `raise` itself. `dm_zero` reports the condition and the
  rows are the evidence; rendering the message is the caller's job.

`rg "TODO\(p3\)" tinybendygrad/uop/divandmod.bend` is the work queue: 10 markers.
`_min_max` alone unblocks five of them.