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

## The `remove_nested_mod` arm, and the differential gate that holds it

`divandmod.py:27-35` — `remove_nested_mod in sum: (a%4 + b)%2 -> (a+b)%2`. It
is the arm the whole unit's remaining work was waiting on, because it was the
one whose wall (`divides`) turned out to be measured false.

**The arm is four facts, and each is a separate def so a reader can see which
one is false:** `d` is a MOD; `y` is a CONST and its value is **positive**; each
term `u` of the sum is a MOD whose divisor **divides** `c`, and then the term
becomes its own **dividend**; and at least one term changed, or the arm does
not fire. The answer is `(usum(new_xs) + const) % y`, and the `+ const` is an
ADD of a ZERO CONST when `x` had no CONST part — upstream's
`identity_element(Ops.ADD, dt)` is `0` (`ops.py:57`), and the port keeps the
ADD so the tree matches.

**AND IT HAS A DIFFERENTIAL GATE AND A PLANT**, and the gate's design is the
`symrules` one: **one case file, two readers.**
`gates/divandmod-cases.rows` holds the graphs, the port's `.bend` driver reads
it, and `gates/divandmod-oracle.py` reads **the same file** and builds the same
graphs in CPython — so the port and the oracle cannot be measuring two
different graphs, which is the defect a hand-written pair of fixtures has by
construction. MEASURED 2026-11-24: **3 rows, 3 agree, 0 diverge**, and the
plant's four cases all pass.

**AND THE CASE IS A FIXED SHAPE AND NOT AN S-EXPRESSION, and the reason is a
Bend rule:** the first draft read an s-expression, and the port's parser needs
a frame stack, because `parse` and `close` need each other and **Bend refuses
mutual recursion** — the same wall this file's header names for
`nest_by_factor`. The fix was not a better parser; it was a case shape that
needs no parser.

**AND THE PLANT HAS FOUR CASES, AND TWO OF THE FIRST DRAFT's DID NOT FIRE —
and the reason is general: a plant that mutates a guard which is already
satisfied, or which is never reached, proves nothing.** The first broke
`divides` to "always divides" and the cases already divide. The second broke
the positive-divisor guard, and the `zero` row's `divides` on a zero divisor
never reaches it. The plant now breaks the `divides` guard the other way (the
arm never fires), the **zero-divisor check** (the port stops raising), and the
`usum` association (the sum's tree changes).

**AND THE CONST/CONST ARM IS NOT IN THE CASE FILE**, and the reason is
measured: upstream's `canonicalize` rewrites `SUB` into
`ADD(x, MUL(MUL(q,y),C(-1)))`, so the two trees differ while the values are
equal — and a row that compares trees on that arm is a row that can never pass.
**The existing gate already covers that arm by value** (`gates/divandmod-gate.bend`'s
`dmc.den` reads the folded tree's value), so the differential is about the
**new** arm.

## The `divide_by_gcd` arm, and its MOD half

`divandmod.py:72-77` — `divide_by_gcd: x//y -> (x//gcd)//(y//gcd)`. It is ONE
arm with TWO answer shapes, and the second is the one this file's TODO called
a wall:

```python
ret = unwrap(x.divide_exact(gcd)).alu(d.op, unwrap(y.divide_exact(gcd)))
return ret*gcd if d.op is Ops.MOD else ret
```

**AND THE TWO SHAPES ARE MEASURED ON CPYTHON AT THE PIN** — `MOD(0, 2x)`
answers `MUL(MOD(c0,MUL(x,c1)),c2)` and `DIV(0, 2x)` answers
`DIV(c0,MUL(x,c1))` — two different trees for the same gcd.

**AND THE ARM NEEDED NOTHING NEW.** `UOp.gcd` (`ops.bend:4513`),
`UOp.divide_exact` (`ops.bend:4490`) and `UOp.const_factor` (`ops.bend:3943`)
were all already in `ops.bend`. **AND `simplify()` IS NOT NEEDED**: upstream
calls `UOp.gcd(...).simplify()` and the port's `UOp.gcd` already answers
upstream's simplified form — measured, on `gcd(x, 2x)` upstream answers
`(x*1.expand((4,)))` and `simplify()` leaves it alone, and on `gcd(0, 2x)`
both answer `2`. **So the `simplify` wall is measured false for this arm, and
the `divide_by_gcd` wall was the `divides` one, which was also measured
false.**

**AND TWO THINGS WERE FOUND WHILE PORTING IT.**

**The port's own `symbolic.bend` had only the DIV half.** `dm_gcd_ret.put`
built `O.OpsDIV{}` unconditionally, so a MOD root was rewritten as a DIV.
That file is another lane's, and it is still there.

**And the two gcds differ in SHAPE on a term that is not a CONST.**
Upstream counts the **peeled** terms — `u.pop_const(Ops.MUL)` gives `2` for
`2x`, and `2.split_uop(MUL)` is `[2]` — so its counters for `2` and `2x` are
**disjoint** and it answers a **CONST**. The port's `UOp.gcd.terms` counts the
**unpeeled** term (`2x`), so its counters **overlap** and it answers a
**MUL**. So `(2 + 2x)` is not a differential row: the two would never
agree. The row is not in the case file, and the reason is written there.

**AND THE DIFFERENTIAL ROWS ARE GREEN.** `gates/divandmod-cases.rows` holds
`gcdmod_fires` and `gcddiv_fires`, and the plant's case 5 **deletes the
`ret*gcd` multiplication** and the lanes disagree — **so the MOD half is
load-bearing and not a variant of the DIV half.**

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
- `divandmod.py:23-25` `nested_div` — **DONE (2026-11-25), AND THE WALL WAS NOT
  THE ONE NAMED.** The named wall was "`divides` → `gcd` → a `Counter` fold", and
  `divides` (`ops.bend:4182`) and `gcd` (`ops.bend:4542`) ARE in the tree — but
  the arm needs `divides` **alone**: `k` is `x.src[1].divides(c)`, the INNER mod's
  divisor divided by the OUTER one, and it is a **CONST** quotient, so `k.vmin > 0`
  is a CONST's value and not a `vmin` fold.
  **AND THE ARM IS BEFORE `remove_nested_mod`** (`divandmod.py:23` vs `:26`) and
  the port's ladder keeps that order.
  **AND `k = 1` STILL FIRES**, because upstream's test is `k.vmin > 0` and
  `1 > 0` is true — measured 2026-11-25: upstream answers `MOD(DIV(x,c8),c1)`.
  The rows are `gates/divandmod-cases.rows`'s five `nd_*` rows, and the plant's
  case 10 proves the positive-quotient guard is load-bearing.
- `divandmod.py:28-35` `remove_nested_mod` — **DONE (2026-11-24), AND THE `divides`
  WALL WAS MEASURED FALSE.** `UOp.divides` (`ops.bend:4182`) HAS BEEN IN THE TREE
  SINCE 2026-11-06 AND IT ANSWERS UPSTREAM's SHAPE: A `Dv` WHOSE `ok` SAYS
  "DIVIDES" AND WHOSE `i` IS THE QUOTIENT NODE.  **SO THE ARM NEEDED `split_uop`,
  `divides` AND `usum`, AND THE PORT HAD THE FIRST TWO** — AND `usum` IS NOW IN
  `ops.bend` (`mixin/elementwise.py:40`), BECAUSE THE IMPORT DIRECTION FORBIDS
  `uop/` REACHING `schedule/`.
- `divandmod.py:42-49` `fold_divmod_congruence` — the worst one: a cartesian
  product over per-term sign choices, then interval arithmetic over a symbolic
  SUM. Bend has no cartesian product and no `min` over three with a key.
- `divandmod.py:51-65` `nest_by_factor` — a set comprehension, then a RECURSIVE
  call to `fold_divmod_general` (mutual recursion, refused outright), then
  `backward_slice` twice. The largest single omission in the file.

**AND THERE ARE TWO ARMS HERE AND NOT THREE.** Upstream's `divandmod.py` has
`fold_divmod_congruence` (`:42-49`) and `nest_by_factor` (`:51-65`) and **no**
`gcd_with_remainder`: the arm was removed upstream in `7711bbac7` ("merge to
fold_divmod_general", PR #13359) and this list still named it. **A work queue
that names work that is not there is a queue that counts wrong.**
- `divandmod.py:78-91` `factor_remainder` — **DONE (2026-11-25), AND THE WALL
  WAS NOT THE ONE NAMED.** The named wall was `const_like` (a TODO in
  `ops.bend`) and `new_x.vmin` over a sum; the port has `F.UOp.vmin` over a
  `BTable`, and `const_like` turned out not to be needed — **because the arm
  only fires with a VARIABLE divisor**, and a variable's `_shape` is `()`, so
  `x.const_like(0)` is a bare `CONST 0` and not an `EXPAND`.
  **AND THE VARIABLE IS NOT COSMETIC.** MEASURED 2026-11-25 on CPython at the
  pin: a CONST divisor puts the arm behind `divide_by_gcd`
  (`divandmod.py:72-76`), whose `gcd` is `UOp.gcd(...).simplify()` and, for a
  PARAM-bearing numerator, is an **`EXPAND`** and not a `CONST` — so upstream's
  guard `gcd.op is Ops.CONST and gcd.val==1` is **false**, the arm fires, and
  `unwrap(x.divide_exact(gcd))` **raises `AssertionError`**. Every
  CONST-divisor shape I built crashed upstream. Upstream's own test
  (`test/null/test_uop_symbolic.py:584`) uses `d = Variable("d", 1, 10)`.
  **AND TWO SUMS, NOT ONE**: upstream's `factor_remainder` uses PYTHON's
  builtin `sum` (`divandmod.py:89` and `:91`), which starts with the int `0`,
  while `remove_nested_mod` uses `UOp.usum` (`divandmod.py:33`), which starts
  with the first element. The port has both. The rows are
  `gates/divandmod-cases.rows`'s `fr_*` rows, and the plant's cases 6-8 prove
  the arm load-bearing.
  **AND THE ARM HAS A CONSTANT BRANCH (`divandmod.py:83-85`) AND IT IS
  REACHABLE, AND A CONST DIVISOR IS NOT THE SAME AS AN UNREACHABLE ONE.**
  `divide_by_gcd`'s guard is `gcd.op is Ops.CONST and gcd.val==1`, and the GCD is
  `uops[0].const_like(gcd)` (`ops.py:1037`) — so it is a **bare `CONST`** when
  `uops[0]`'s `_shape` is `()`, which is a **variable** derivation, and then the
  arm **is** reached. Measured 2026-11-25: `(6a+b)//4` answers
  `ADD(DIV(ADD(ADD(ADD(c0,MUL(MUL(a,c1),c2)),b),c0),c4),ADD(c0,MUL(MUL(a,c1),c1)))`.
  **AND THE PORT's ANSWER WAS A DEEP `ADD(c0, ADD(c0, ...))` NEST INSTEAD, AND
  THE CAUSE WAS NOT THE ARITHMETIC:** the `quo`/`rem` lists hold **indices**, an
  index is only meaningful in **its own arena**, and `UOp.divides` and `UOp.alu`
  **grow** the arena — so the `quo` term and the `rem` term were built in **two
  branches** of one arena and read each other's indices, and a stale arena reads
  the arena's **bottom NOOP node**. The fix is **one chain**: every node is built
  from the previous node's arena. The plant's case 12 proves it is load-bearing.
  **AND `UOp.divide_exact` HAD A REAL DEFECT AND IT IS FIXED.** Upstream's
  `new_count` is `Counter(num) - Counter(den)` (`ops.py:1044-1045`) and its test is
  `all(v>=0 for v in new_count.values())` (`ops.py:1046`), so a factor that is in
  the divisor and not in the numerator has a **negative** count and the answer is
  `None`. The port's MUL arm checked only the **other** half, so it answered
  `divide_exact(6x, y)` with a quotient where upstream answers `None`. The row is
  `gates/ops-core.bend`'s `de_den`, and it is load-bearing — measured: without
  the fix the gate disagrees on exactly that row.
- `divandmod.py:72-77` `divide_by_gcd` — **DONE (2026-11-24), AND BOTH HALVES**:
  upstream's arm is ONE arm with TWO answer shapes (`ret*gcd` for a MOD and
  `ret` for a DIV, `divandmod.py:76`), and `simplify` was not needed — the
  port's `UOp.gcd` already answers upstream's simplified form. **AND THE
  PORT's OWN `symbolic.bend` HAD ONLY THE DIV HALF** (`dm_gcd_ret.put` built
  `O.OpsDIV{}` unconditionally), **SO THE MOD HALF WAS MISSING THERE TOO —
  AND IT IS STILL THERE, AND IT IS ANOTHER LANE's FILE.**
- `divandmod.py:11` the `raise` itself. `dm_zero` reports the condition and the
  rows are the evidence; rendering the message is the caller's job.

`rg "TODO\(p3\)" tinybendygrad/uop/divandmod.bend` is the work queue: 10 markers.
`_min_max` alone unblocks five of them.