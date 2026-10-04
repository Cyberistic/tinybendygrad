# symbolic: 16 of 130 rewrite rules, and the 114 that are not

`symbolic.py` is 475 lines and this unit's honest answer is **that most of it is
a wall, not a port.** The file is `tinybendygrad/uop/symbolic.bend`. Writing
this walkthrough down is the gain: the unit's value is the inventory, and the
inventory is checkable.

## What we gain

- **The shortfall is arithmetic in the gate, not a claim.** `total_sym=127` is
  what symbolic.py's six own blocks imply (14 `pm_data_invalid` + 47
  `symbolic_simple` + 1 `commutative` + 47 `symbolic` + 2 `pm_simplify_valid` +
  14 `sym` + 2 `pm_clean_up_group_sink`). `len_sym=13` is what the table holds,
  `len_rm=2` is `pm_remove_invalid`, and `skip=114` is `total_sym - len_sym`. So
  `len_sym + skip == total_sym` and **the arithmetic of the port can be checked
  without reading a single rule body.**
- **30 gate rows, both lanes byte-identical.** `alu=0`, `inval_st=0`, `inval_n=0`
  and `cdiv_neg=0` are the four RED rows, and they are labelled RED in the header
  rather than being quietly expected to pass.
- **A rule is TWO defs, and the separation is what makes the affine arena safe.**
  `sym_N.pat` holds the pattern's own tests and is total and never grows the
  arena; `sym_N` is the body, called only when the pattern holds. Python's arena
  is a global cache and a discarded answer is garbage, so Python can call every
  rule body unconditionally; here a rule that does not match never touches the
  arena, and that is the invariant that makes the rest possible.
- **`ret is not uop` is ported and it is the whole of `x+0 -> x`, `x&0 -> 0` and
  `x>>0 -> x`** in one test. `selfadd=1` pins it: the answer IS the node.
- **A discarded node is a DEAD INDEX in a monotone arena**, which is "garbage in
  a global cache" with a name.
- **`rebind=1` / `rebind0=1` and `xorb=1` / `xorb0=1` are two-sided fixtures, and
  that is the only thing that can see an identity check.** Mutations M3 and M11
  drop the `(x // x)` and `(x^y)^y` rebind checks and move exactly the `…0` rows.
  A positive rebind row is worth nothing on its own; the negative side is the
  witness.
- **The name-rebind question had to be re-derived, and the notes were wrong.**
  `bend2-constraints.md` records ONE rebind in symbolic.py, at :180, and calls it
  safe because the two are `is_any` ALTERNATIVES. That is right and incomplete:
  `symbolic.py:123` `(x^y)^y` and `:124` `(x%y)%y` bind one name twice WITHIN A
  SINGLE SRC TUPLE and both are load-bearing. Every rule below that rebinds
  carries `U32.is_eq`, and the `is_any` case stays a disjunction because
  `is_any` copies the store per alternative, so an identity check there would turn
  a disjunction into a conjunction.
- **`M9` and `M10` are rows that exist ONLY for a mis-spelling**, and they were
  added after the mutation moved nothing without them. `rej` is a COUNT of
  non-empty reject sets, because an empty set and a wrongly-spelled set differ in
  exactly one place — the count. `bcast` is the only witness for a mis-spelled
  TAG. A row that cannot fail is not a row.
- **`M2` and `M5` moved nothing and both are reported as negatives rather than
  dropped.** `sy_novel` (`ret is not uop`) is load-bearing in tinygrad but no rule
  in this table returns its matched node, so the test has no witness here yet; and
  `rm_try`'s `and` is unreachable because `rm_table`'s two reject sets (`{CONST}`
  and `{}`) are violated by no fixture, which is a FIXTURE GAP rather than a
  property of the code.

## The three walls, measured rather than assumed

1. **`exec_alu` over a closed ALU tree: YES, for `U32` and `F32` only.** Overflow
   and sign semantics are right for the 32-bit widths. `U32.add/sub/mul` wrap mod
   2^32, which IS int32/uint32 wrap, and `U32.div(a,0) = 0` and
   `H.floordiv_i32(x,0) = 0` are the same number Python's `floordiv` is given by
   helpers.py:76, so the zero-divisor reading is right too. What it cannot do:
   weakint is MATHEMATICAL in tinygrad and the honest 64-bit carrier is `H.I64`,
   which has `i64_add`/`i64_sub`/`i64_cmp` and NOT `i64_mul`/`i64_div`/`i64_mod`;
   and `truncate` is a C-effect table for twelve widths that answer `None`.
   `alu_big=1` is that wall made into a row — it asserts the fold does NOT apply,
   rather than printing a wrapped 1. `alu_f32=1` is the float lane, and the two
   lanes cannot both pass by accident because `alu_big` is on the integer one.
2. **The operator layer.** Almost every rule body is an expression of UOp
   algebra (`x + c`, `x // c`, `x != 0`) and in Python those are
   `mixin/elementwise.py`'s `__add__`/`__floordiv__`/`__ne__`, each of which is
   `_broadcasted` — a dtype promotion — followed by `alu`. **That file is NOT
   PORTED**, so `sy_alu1/2/3` is the RAW `alu` and every rule body is the raw
   node. This is the single largest divergence and it is not hidden: a rule here is
   only faithful on a fixture whose src dtypes already agree, and `promo=1` is the
   row that counts the fixtures exercised under that restriction.
3. **`graph_rewrite` is not this file.** What is here is the part symbolic.py
   owns: the table, the first-wins fold over it, and the `ret is not uop` test.
   `sym_rewrite(fx, u) -> Maybe<&1, U32>` is `PatternMatcher.rewrite`; the
   fixpoint driver around it is P3.

## Reported, not fixed

`ops.py:1478`'s comment is wrong and it is load-bearing. Per the commit that
landed this unit, `early_reject` is the single-op ops of the pattern's FIRST src
ALTERNATIVE, all of its srcs — not of `src[0]` as the comment claims — and
`pm_remove_invalid.patterns[0][0].early_reject` is `{Ops.CONST}`. That changed
three reject sets here. (The correction is recorded in the commit rather than in
the file header, so it is not checkable from `symbolic.bend` alone.) What the
FILE does state, at line 103 and at line 1576, is the part that matters for
reading a verdict: `early_reject` is a NECESSARY CONDITION and not a veto, since
ops.py:1609 is `if not early_reject.issubset(ler): continue`, so the rule FIRES
when the op set IS a subset of the node's src ops.

Also reported: `helpers.bend`'s `floordiv_i32`/`floormod_i32` are wrong for a
non-negative inexact dividend, which is why `fdiv_i` is computed here from
`H.cdiv_i32_go` rather than read out of the shared helper.

## Not done

`rg "TODO\(p3\)" tinybendygrad/uop/symbolic.bend` is the work queue: 30 markers.
`skip=114` is the arithmetic and every one of the 114 is named there.

The commit that landed this unit splits the 114 by wall as **72 need
`UOp.vmin`/`vmax`**, **25 need `UOp.tuplize` plus `bool_slice`/`substitute`**,
**9 need `gcd` on I64**, and **8 need `UOp.ranges`**. That split is the commit's
arithmetic, not a gate row — the gate only carries `skip=114` and every one of the
114 is named individually below. What the FILE states, per wall:

- **`_min_max` (`vmin`/`vmax`) is the biggest single unlock, and it takes ALL 47 of
  the `symbolic` table** (:236-323): there is no sub-block of it answerable without
  one of `vmin`/`vmax`, `const_factor` → `gcd`, `tuplize`, `bool_slice`,
  `backward_slice` or `substitute`, which is why the block is 47 and not "most of
  it".
- **`tuplize` is blocked on a sort key, not on a sort.** The `commutative` table
  (:222-226) is `x.src[1].tuplize < x.src[0].tuplize`, and `tuplize` (ops.py:322) is
  a SORT KEY over `(op, src-tuple, arg)` where `arg` is a Python `Any` with
  eighteen shapes and no total order. The arena has an order for the first two and
  nothing for the third.
- **`gcd` on I64** — `const_factor` → `divides` → `gcd`, and `gcd` needs a
  `Counter` fold. This is what defers `lt_folding` (:203), `_quotient_base` (:31)
  and `fold_add_divmod_recombine` (:43), the last two being PORTED IN SHAPE and
  deferred on `divides` alone.
- **`UOp.ranges`** — the set algebra in `fold.bend`'s own TODO.
- Four are genuinely unavailable rather than behind a fold: `lift_reduce_gate`
  (:72, `_ranges` as a set union), the `commutative` sort key, the `AFTER` src
  expansion (:315-317, a `dedup` over a set), and `where_on_load` (:406-425,
  three P3 folds plus the set algebra).
- `:16` `simplify_pow` — TWO of its FIVE arms are ported; the half exponent needs
  an `F32 <-> I64` compare and `i64_div`.
- `:328-386` `parse_valid` / `uop_given_valid` / `_valid_priority` /
  `simplify_valid` — four functions, none answerable alone.
- `:390` `reduce_mul_chain`, `:400-403` `drop_and_clauses`, `:427`
  `gated_given_valid` (which also needs `IMAGE.value`, a process-wide mutable
  `ContextVar` Bend has no home for).
- `:452` `xpow` — `tinygrad/codegen/decomp/transcendental.py`, a foreign import,
  and owned by the transcendental unit.
- `:454-462` the four load/store folding rules — `UOp.index`, `UOp.valid`,
  `UOp.store`, `UOp.load`, which are `movement.bend`'s and `weak.bend`'s.
- `:463-468` three of the four reciprocal rules — the first IS ported (`sym_10`);
  the others are the same shape at `MUL(MUL,MUL)` and were left for budget.
- `:472-474` `-(x+y)` and `(x+y)*c -> x*c+y*c` — deferred for BUDGET, not a wall.
  The second is the one rule in the file whose answer DEPENDS on the missing
  promotion: it is `dtypes.weakint`-only for that reason.
- `:306-313` the long/cast folding rules — `S.Dt.min`/`S.Dt.max` ARE here;
  `_min_max` is not.
- `mixin/elementwise.py:50` `logical_not` — BORROWED, not this file's. Three of
  `pm_data_invalid`'s rules cannot be written without it; `sy_logical_not` here is
  the borrow.

`_min_max` first, then `gcd`/`const_factor`, then `tuplize`/`bool_slice`, is the
order the walls fall in.