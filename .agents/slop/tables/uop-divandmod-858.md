<!-- FROM: tinybendygrad/uop/divandmod.bend:858 -->
# BLOCK:
# NOT PORTED, one line each, with the WALL and the phase that owns it. The block
# is the same shape `ops.bend` and `fold.bend` use.
# TODO(p3) divandmod.py:13  symbol=fold_divmod_general  the RANGE HALF of `x//y` being a point -- PORTED for
#   CONST/CONST only, where `_min_max` (ops.py:1127) is four identical `a//b` and
#   the test is always true. Outside CONST/CONST it needs `_min_max`. THE `_min_max` WALL IS
#   MEASURED FALSE (2026-11-06): THE PORT HAS `F.UOp.vmin`/`F.UOp.vmax`
#   (`fold.bend:5344`/`5402`) and they match upstream's `_min_max` on all five measured cases
#   -- `x[0..10]`, `y[-5..5]`, `x*4[0..40]`, `x+y[-5..15]`, `x*4+8[8..48]` (PAIRED PROBES:
#   `.agents/slop/sym92/probe-vminmax.bend` AND `probe-vminmax.py`, AND THE TWO PRINT
#   BYTE-identical output). what is left is scope, not a wall: the port's bounds are a
#   `F.Bnd` (an interval with an infinity tag) rather than upstream's `PyConst`, so the
#   comparisons the arms need are over a `Maybe` bound and not over a constant.
# TODO(p3) divandmod.py:17-19 `# split uops for the rest of the processing` --
#   `x.pop_const()` and `split_uop(Ops.ADD)`, both op-shape walks over a fuel-bound
#   src list. Neither has a caller once line 23 is gone, so neither is written.
#   WALL: none -- these ARE expressible; they are P3 for SCOPE, not for
#   impossibility, and they land with line 23.
# TODO(p3) divandmod.py:13-15  symbol=fold_divmod_general  a FLOAT CONST -- `_min_max` returns PyConst and
#   `dm_val` reads `CInt` only, so rules 0 and 1 SKIP on a `CFloat` divisor where
#   Python rewrites. WALL: PyConst (float | bool | Invalid), P3.
#
#  Constant Denominator Rules  -- divandmod.py:21-70. These rules strictly
# require y to be a scalar constant > 0, and every one is behind a wall:
# TODO(p3) divandmod.py:23-25 `nested_div: (x%(k*c))//c -> (x//c)%k (requires k>0);
#   the mod case is handled by remove_nested_mod below` -- needs
#   `x.src[1].divides(c)`. THE WALL THIS NAMED IS MEASURED FALSE (2026-11-06): `divides` IS
#   not the blocker. the port's `UOp.divides` (`ops.bend:7656`) is a full recursion over
#   ADD/MUL/CONST carrying a `Dv` record, and it answers the same as upstream's on all four
#   MEASURED CASES -- `(x*4).divides(4)` IS `MUL(x, 1)`, `(x*4+8).divides(4)` IS
#   `ADD(MUL(x, 1), 2)`, AND `(x*6).divides(4)` AND `x.divides(4)` ARE BOTH `none` (PAIRED
#   probes: `.agents/slop/sym92/probe-divides.bend` and `probe-divides.py`). the old wall said
#   "`divides` needs `gcd` needs a `Counter` FOLD", but the file it named -- `ops.bend` -- has
#   that implementation already. what is left is scope, not a wall: the stack arm of
#   `divides` is not ported (seen at `ops.bend:7645`'s own NOTE), so a stack operand declines
#   WHERE UPSTREAM REBUILDS IT.
# TODO(p3) divandmod.py:27-35 `remove_nested_mod in sum: (a%4 + b)%2 -> (a+b)%2` --
#   `divides`, and the same measurement applies: the wall is gone and what is left is the
#   stack arm and the `usum` over the rewritten list.
# TODO(p3) divandmod.py:37  symbol=fold_divmod_general  `Shared decomposition for folding rules` and :41-48
#   `fold_divmod_congruence: fold if a is congruent to an expression whose range is
#   between 0 and c` -- the WORST one. `itertools.product` over per-term sign
#   choices (`try both signs of the remainder for a lone term ... otherwise pick
#   the smaller to keep the product over terms small`), then
#   `sum(r*v for r,v in zip(...)).vmin//c == rem.vmax//c`. It is interval
#   arithmetic over a symbolic SUM, so it needs `_min_max` on a node the fold has
#   never built, AND a cartesian product, AND `min(r, r-c, key=abs)`. WALL:
#   `_min_max`; the product is a fold over a `List<List<U32>>` and Bend has no
#   cartesian product and no `min` over three with a key function. P3.
# TODO(p3) divandmod.py:50-55  symbol=fold_divmod_general  `gcd_with_remainder: factor out common gcd from
#   numerator` -- `math.gcd(*factors, c)`, `divides`, `.simplify()` and
#   `new_x.vmin >= 0`. WALL: `gcd`, `_min_max`, `simplify`. `math.gcd` over a
#   VARIADIC fold is a fold over a list, which is expressible; the rest is not.
#   measured 2026-11-06: `divides` and `_min_max` are no longer walls (see the two pairs
#   above). `gcd` is half a wall: the port has `H.gcd` (`helpers.bend:2249`) for two I64s and
#   `UOp.const_factor` (`ops.bend:7545`) as a full gcd FOLD over the MUL factors, but not the
#   variadic `math.gcd(*factors, c)` over a list of factors -- which is a FOLD over a list and
#   THEREFORE EXPRESSIBLE. WHAT IS LEFT IS SCOPE.
# TODO(p3) divandmod.py:57-70 `nest_by_factor: x//c -> (x//f)//(c//f),
#   x%c -> (x//f%(c//f))*f + b where b=x%f` and `DIV identity holds for any
#   sign of x; MOD reconstruction needs x.vmin>=0` -- the set comprehension
#   `{abs(f) for u, f in zip(...) if ...}` is a set (an ORDERED fold with a dedup
#   step), then a RECURSIVE call to `fold_divmod_general(x//div)` (mutual
#   recursion, refused), then `backward_slice` twice for the `min(results, key=
#   len(slice))`. WALL: mutual recursion, `backward_slice` (a set walk,
#   uop/fold.bend:2167 symbol=marg_prod.step), and `_min_max`. P3, and the largest single omission here.
#
#  Variable Denominator / Fallback Rules  -- divandmod.py:72-96. These rules
# apply to variables OR constants that failed the checks above, and reconstruct all
# uops including const for these checks. Both are behind the same walls:
# TODO(p3) divandmod.py:77-81  symbol=fold_divmod_general  `divide_by_gcd: x//y -> (x//gcd)//(y//gcd)` and :83-96
#   `factor_remainder: (d*x+y)//d -> x+y//d` -- `UOp.gcd(*all_uops, y)`,
#   `.simplify()`, `divide_exact` (which needs `divides`), `const_factor` (a
#   `Counter` fold), `u.divides(c)*(c%y.val)` and `y.vmin<0` / `x.vmin<0`. WALL:
#   `gcd`, `const_factor`, `simplify`, `_min_max`. P3.
# TODO(p3) divandmod.py:11  symbol=fold_divmod_general  the `raise` itself -- Python's
#   `ZeroDivisionError(f"{'Division' if d.op is Ops.DIV else 'Mod'} by zero
#   trying to rewrite {x.alu(d.op, y)}")` needs a `raise` and an f-string over a
#   UOp. `dm_zero` REPORTS the condition and `zero_r04`/`zero_r11`/`zero_r23` are
#   the rows; rendering the message is the caller's job, exactly as `fold.bend`
#   does for `UOp.shape`'s `if (ret:=self._shape) is None: raise`. NO ACTION
#   beyond P3 at the call site.
#
# WHAT NEXT, in the order the walls fall.
#
# and this list was stale by two items and it was measured 2026-11-08. the items 1 and 2
# below are done and have been done:
#   * `_min_max` (ops.py:1104) IS `fold.bend:7306` ("DONE(p3) ops.py:1094 def _min_max"), AND
#     the header above already said "the `_min_max` wall is measured FALSE (2026-11-06)".
#   * `const_factor` IS `ops.bend:7545` (`def UOp.const_factor(fuel, ar, i) -> H.I64`) AND
#     `divides` IS `ops.bend:7656` (`def UOp.divides(fuel, ar, v, i) -> Dv`).
#
# SO THE TWO THAT REMAIN ARE:
#   1. `UOp.gcd` (ops.py:1073) AND `UOp.divide_exact` (ops.py:1079) -- AND THEY ARE ONE
#      shape, not two: both need a counter over node lists, and upstream's `UOp` is
#      HASHABLE BY IDENTITY (`ops.py:219-220`: `__hash__ = tuple.__hash__` AND
#      `__eq__` IS `self is other`), SO THE COUNTER's KEYS ARE NODES.
#      and the port has no integer-keyed map at all -- measured, `helpers.bend:494` says
#      "Bend's `Map` is string-keyed only, so the set is a linear scan", and the port has no
#      `HashMap` AND NO `HashSet`.
#      but the port has the honest spelling already, twice: `dedup_u32` (`helpers.bend:500`)
#      and `merge_dicts` (`helpers.bend:2412`) are both "a list of pairs with a linear scan",
#      so a counter over `U32` keys is a list of `(U32, Nat)` pairs and a FOLD -- and the
#      port's own `merge_dicts` NOTE says exactly that: "a list of pairs is the honest
#      representation". so the claim "the port has no multiset" is a claim about a
#      CONTAINER AND NOT ABOUT A CAPABILITY.
#   2. `simplify` / `ssimplify` (ops.py:513/520) IS WHAT `fold_divmod_general` LINE 78
#      calls on `UOp.gcd(...)`, and `ops.bend` records it as the largest single unlock in its
#      HALF TOO.
#
# and measured 2026-11-08: the missing row is not dead. `.agents/slop/sym92/
# deadrules-sweep.sh` READS `24 cases 23 agree 1 diverge` and the one divergence is
# `(x*y)/y`, whose upstream answer is `(div (mul c1 x) c1)` and whose rule is this one --
# measured by asking the matcher which pattern fired: pattern 117 is `UPat({DIV, MOD},
# dtype=weakint, name="d")` WITH `src=None`, AND ITS FUNCTION IS
# `tinygrad.uop.divandmod.fold_divmod_general`. SO THE PORT DECLINES A REWRITE UPSTREAM
# performs, on a graph as ordinary as `(x*y)/y` -- so this row is a real gap and not a
# COSMETIC ONE.
# and the arm that answers it is `divide_by_gcd` (line 66), because upstream's
# `UOp.gcd(x, y)` is `y` and not a constant 1 -- measured, `UOp.gcd(x, y)` answers the PARAM
# `y`.
#   4. Only after those three does `fold_divmod_congruence` become a question, and
#      only after THAT does the cartesian product need a shape.
#
# THE ROWS. Every one is a claim PYTHON FIXES: a table count, a reject-set length,
# a `vmin == vmax == 0` flag, a rewritten tree, an arena-growth count, or a
# fired/skipped flag. Nothing here restates the code.
# END BLOCK

# NOT PORTED, one line each, with the WALL and the phase that owns it. The block
# is the same shape `ops.bend` and `fold.bend` use.
# TODO(p3) divandmod.py:13  symbol=fold_divmod_general  the RANGE HALF of `x//y` being a point -- PORTED for
#   CONST/CONST only, where `_min_max` (ops.py:1127) is four identical `a//b` and
#   the test is always true. Outside CONST/CONST it needs `_min_max`. THE `_min_max` WALL IS
#   MEASURED FALSE (2026-11-06): THE PORT HAS `F.UOp.vmin`/`F.UOp.vmax`
#   (`fold.bend:5344`/`5402`) and they match upstream's `_min_max` on all five measured cases
#   -- `x[0..10]`, `y[-5..5]`, `x*4[0..40]`, `x+y[-5..15]`, `x*4+8[8..48]` (PAIRED PROBES:
#   `.agents/slop/sym92/probe-vminmax.bend` AND `probe-vminmax.py`, AND THE TWO PRINT
#   BYTE-identical output). what is left is scope, not a wall: the port's bounds are a
#   `F.Bnd` (an interval with an infinity tag) rather than upstream's `PyConst`, so the
#   comparisons the arms need are over a `Maybe` bound and not over a constant.
# TODO(p3) divandmod.py:17-19 `# split uops for the rest of the processing` --
#   `x.pop_const()` and `split_uop(Ops.ADD)`, both op-shape walks over a fuel-bound
#   src list. Neither has a caller once line 23 is gone, so neither is written.
#   WALL: none -- these ARE expressible; they are P3 for SCOPE, not for
#   impossibility, and they land with line 23.
# TODO(p3) divandmod.py:13-15  symbol=fold_divmod_general  a FLOAT CONST -- `_min_max` returns PyConst and
#   `dm_val` reads `CInt` only, so rules 0 and 1 SKIP on a `CFloat` divisor where
#   Python rewrites. WALL: PyConst (float | bool | Invalid), P3.
#
#  Constant Denominator Rules  -- divandmod.py:21-70. These rules strictly
# require y to be a scalar constant > 0, and every one is behind a wall:
# TODO(p3) divandmod.py:23-25 `nested_div: (x%(k*c))//c -> (x//c)%k (requires k>0);
#   the mod case is handled by remove_nested_mod below` -- needs
#   `x.src[1].divides(c)`. THE WALL THIS NAMED IS MEASURED FALSE (2026-11-06): `divides` IS
#   not the blocker. the port's `UOp.divides` (`ops.bend:7656`) is a full recursion over
#   ADD/MUL/CONST carrying a `Dv` record, and it answers the same as upstream's on all four
#   MEASURED CASES -- `(x*4).divides(4)` IS `MUL(x, 1)`, `(x*4+8).divides(4)` IS
#   `ADD(MUL(x, 1), 2)`, AND `(x*6).divides(4)` AND `x.divides(4)` ARE BOTH `none` (PAIRED
#   probes: `.agents/slop/sym92/probe-divides.bend` and `probe-divides.py`). the old wall said
#   "`divides` needs `gcd` needs a `Counter` FOLD", but the file it named -- `ops.bend` -- has
#   that implementation already. what is left is scope, not a wall: the stack arm of
#   `divides` is not ported (seen at `ops.bend:7645`'s own NOTE), so a stack operand declines
#   WHERE UPSTREAM REBUILDS IT.
# TODO(p3) divandmod.py:27-35 `remove_nested_mod in sum: (a%4 + b)%2 -> (a+b)%2` --
#   `divides`, and the same measurement applies: the wall is gone and what is left is the
#   stack arm and the `usum` over the rewritten list.
# TODO(p3) divandmod.py:37  symbol=fold_divmod_general  `Shared decomposition for folding rules` and :41-48
#   `fold_divmod_congruence: fold if a is congruent to an expression whose range is
#   between 0 and c` -- the WORST one. `itertools.product` over per-term sign
#   choices (`try both signs of the remainder for a lone term ... otherwise pick
#   the smaller to keep the product over terms small`), then
#   `sum(r*v for r,v in zip(...)).vmin//c == rem.vmax//c`. It is interval
#   arithmetic over a symbolic SUM, so it needs `_min_max` on a node the fold has
#   never built, AND a cartesian product, AND `min(r, r-c, key=abs)`. WALL:
#   `_min_max`; the product is a fold over a `List<List<U32>>` and Bend has no
#   cartesian product and no `min` over three with a key function. P3.
# TODO(p3) divandmod.py:50-55  symbol=fold_divmod_general  `gcd_with_remainder: factor out common gcd from
#   numerator` -- `math.gcd(*factors, c)`, `divides`, `.simplify()` and
#   `new_x.vmin >= 0`. WALL: `gcd`, `_min_max`, `simplify`. `math.gcd` over a
#   VARIADIC fold is a fold over a list, which is expressible; the rest is not.
#   measured 2026-11-06: `divides` and `_min_max` are no longer walls (see the two pairs
#   above). `gcd` is half a wall: the port has `H.gcd` (`helpers.bend:2249`) for two I64s and
#   `UOp.const_factor` (`ops.bend:7545`) as a full gcd FOLD over the MUL factors, but not the
#   variadic `math.gcd(*factors, c)` over a list of factors -- which is a FOLD over a list and
#   THEREFORE EXPRESSIBLE. WHAT IS LEFT IS SCOPE.
# TODO(p3) divandmod.py:57-70 `nest_by_factor: x//c -> (x//f)//(c//f),
#   x%c -> (x//f%(c//f))*f + b where b=x%f` and `DIV identity holds for any
#   sign of x; MOD reconstruction needs x.vmin>=0` -- the set comprehension
#   `{abs(f) for u, f in zip(...) if ...}` is a set (an ORDERED fold with a dedup
#   step), then a RECURSIVE call to `fold_divmod_general(x//div)` (mutual
#   recursion, refused), then `backward_slice` twice for the `min(results, key=
#   len(slice))`. WALL: mutual recursion, `backward_slice` (a set walk,
#   uop/fold.bend:2167 symbol=marg_prod.step), and `_min_max`. P3, and the largest single omission here.
#
#  Variable Denominator / Fallback Rules  -- divandmod.py:72-96. These rules
# apply to variables OR constants that failed the checks above, and reconstruct all
# uops including const for these checks. Both are behind the same walls:
# TODO(p3) divandmod.py:77-81  symbol=fold_divmod_general  `divide_by_gcd: x//y -> (x//gcd)//(y//gcd)` and :83-96
#   `factor_remainder: (d*x+y)//d -> x+y//d` -- `UOp.gcd(*all_uops, y)`,
#   `.simplify()`, `divide_exact` (which needs `divides`), `const_factor` (a
#   `Counter` fold), `u.divides(c)*(c%y.val)` and `y.vmin<0` / `x.vmin<0`. WALL:
#   `gcd`, `const_factor`, `simplify`, `_min_max`. P3.
# TODO(p3) divandmod.py:11  symbol=fold_divmod_general  the `raise` itself -- Python's
#   `ZeroDivisionError(f"{'Division' if d.op is Ops.DIV else 'Mod'} by zero
#   trying to rewrite {x.alu(d.op, y)}")` needs a `raise` and an f-string over a
#   UOp. `dm_zero` REPORTS the condition and `zero_r04`/`zero_r11`/`zero_r23` are
#   the rows; rendering the message is the caller's job, exactly as `fold.bend`
#   does for `UOp.shape`'s `if (ret:=self._shape) is None: raise`. NO ACTION
#   beyond P3 at the call site.
#
# WHAT NEXT, in the order the walls fall.
#
# and this list was stale by two items and it was measured 2026-11-08. the items 1 and 2
# below are done and have been done:
#   * `_min_max` (ops.py:1104) IS `fold.bend:7306` ("DONE(p3) ops.py:1094 def _min_max"), AND
#     the header above already said "the `_min_max` wall is measured FALSE (2026-11-06)".
#   * `const_factor` IS `ops.bend:7545` (`def UOp.const_factor(fuel, ar, i) -> H.I64`) AND
#     `divides` IS `ops.bend:7656` (`def UOp.divides(fuel, ar, v, i) -> Dv`).
#
# SO THE TWO THAT REMAIN ARE:
#   1. `UOp.gcd` (ops.py:1073) AND `UOp.divide_exact` (ops.py:1079) -- AND THEY ARE ONE
#      shape, not two: both need a counter over node lists, and upstream's `UOp` is
#      HASHABLE BY IDENTITY (`ops.py:219-220`: `__hash__ = tuple.__hash__` AND
#      `__eq__` IS `self is other`), SO THE COUNTER's KEYS ARE NODES.
#      and the port has no integer-keyed map at all -- measured, `helpers.bend:494` says
#      "Bend's `Map` is string-keyed only, so the set is a linear scan", and the port has no
#      `HashMap` AND NO `HashSet`.
#      but the port has the honest spelling already, twice: `dedup_u32` (`helpers.bend:500`)
#      and `merge_dicts` (`helpers.bend:2412`) are both "a list of pairs with a linear scan",
#      so a counter over `U32` keys is a list of `(U32, Nat)` pairs and a FOLD -- and the
#      port's own `merge_dicts` NOTE says exactly that: "a list of pairs is the honest
#      representation". so the claim "the port has no multiset" is a claim about a
#      CONTAINER AND NOT ABOUT A CAPABILITY.
#   2. `simplify` / `ssimplify` (ops.py:513/520) IS WHAT `fold_divmod_general` LINE 78
#      calls on `UOp.gcd(...)`, and `ops.bend` records it as the largest single unlock in its
#      HALF TOO.
#
# and measured 2026-11-08: the missing row is not dead. `.agents/slop/sym92/
# deadrules-sweep.sh` READS `24 cases 23 agree 1 diverge` and the one divergence is
# `(x*y)/y`, whose upstream answer is `(div (mul c1 x) c1)` and whose rule is this one --
# measured by asking the matcher which pattern fired: pattern 117 is `UPat({DIV, MOD},
# dtype=weakint, name="d")` WITH `src=None`, AND ITS FUNCTION IS
# `tinygrad.uop.divandmod.fold_divmod_general`. SO THE PORT DECLINES A REWRITE UPSTREAM
# performs, on a graph as ordinary as `(x*y)/y` -- so this row is a real gap and not a
# COSMETIC ONE.
# and the arm that answers it is `divide_by_gcd` (line 66), because upstream's
# `UOp.gcd(x, y)` is `y` and not a constant 1 -- measured, `UOp.gcd(x, y)` answers the PARAM
# `y`.
#   4. Only after those three does `fold_divmod_congruence` become a question, and
#      only after THAT does the cartesian product need a shape.
#
# THE ROWS. Every one is a claim PYTHON FIXES: a table count, a reject-set length,
# a `vmin == vmax == 0` flag, a rewritten tree, an arena-growth count, or a
# fired/skipped flag. Nothing here restates the code.
