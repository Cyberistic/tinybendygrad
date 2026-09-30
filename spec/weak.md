# weak: the dtype promotion table, and the wall under it

`weak.py` is 98 lines. The file is `tinybendygrad/uop/weak.bend`: **5 of 9 defs
and 3 of 8 rules.** That ratio is the whole story of this unit, and the gate
prints it as four COUNT rows so the shortfall is machine-visible rather than a
silent under-rewrite.

## What we gain

- **52 gate rows, every value read from a live tinygrad oracle** rather than from
  this port, and both lanes byte-identical.
- **The shortfall is four numbers, not a sentence.** `commit_len=2`,
  `lower_len=0`, `uncast_len=1`, `cast_len=0`, and `commit_total=False`,
  `lower_total=False`, `uncast_total=True`, `cast_total=False`. A reader does not
  have to trust the header: `lower_len=0` says `pm_lower_weak` is an EMPTY table.
- **A COUNT catches what a boolean cannot.** `sealed_count_n=6` and
  `weak_count_n=2` are there so that adding a sealed dtype moves a number. A
  boolean over the same set would have gone from True to False and said nothing
  about how far off it was.
- **`wk_dt` answers `void` for an unsettled node, and `void` is the right
  bottom.** It is dtype.bend's own "no dtype" and a LATTICE BOTTOM (an empty
  `promo_mask`), so a void in a `promo_dtype` poisons the meet rather than
  reading as something else. It is still not allowed to be OBSERVED: `wk_ready`
  refuses a node whose own dtype or any of its srcs' is unsettled, and the
  driver gates every rule on it once. Mutation 8 is that gate, measured: give
  `wk_dt` the wrong default and nothing moves.
- **`derived_dtypes` asks about a HYPOTHETICAL src list, and that turned out not
  to be a wall.** `uncast_const` and `lower_weak_node` both pass a rewritten list
  rather than `u.src`. The alternative — asking the fold about a node that does
  not exist — needs a scratch arena and a second Kahn worklist per query.
  Instead `fold.bend`'s `F.dt_shape` IS `dtype_from_uop` with its src half
  already factored out as `List<Derived>`, and `F.Derived` is `Data`, so a fold
  rebuilds one per hypothetical src. `hypo_weak=True` is the row.
- **The weak class test is a `match`, not a predicate.** `dtypes.weaks` is
  `(weakint, weakfloat)` and `spec.bend` already spells all seven `S.Cls`
  constructors, so `weak_cls` is two arms and a wildcard.
- **`wk_eq_dt` compares a class as a NUMBER**, so the whole dtype equality is one
  `U32.is_eq` per field rather than a comparison of eight.

## The one wall, and what it costs

`UOp._min_max` (ops.py:1104-1158). `commit_dtype` (mixin/dtype.py:16) is
`commit_int(vmin, vmax)` on a weakint node, and `vmin`/`vmax` ARE `_min_max`: 57
lines of interval arithmetic over `PyConst = int|float|bool|Invalid`, with
ADD/SUB/MUL/AND/OR/SHL/SHR/CMOD/CDIV/FLOORDIV/FLOORMOD/XOR arms, `math.trunc`,
`truncate` (dtype.py:297), `dtype.min`/`dtype.max` at 64 bits, and one LOAD arm
that decodes a `memoryview` of a BINARY blob by dtype.

It blocks six defs, and the file says so rather than approximating:
`cast_weak_srcs`, `_lower_weak_ops`, `absorb_weak_src`, `lower_weak_node`,
`cast_consts`, and the `commit_dtype` reads inside the rules.
`fold.bend:2176` already records it as "the biggest single piece left in that
half of ops.py" and names the missing helpers: `i64_mul`, `i64_div`, `i64_mod`,
an F32 min/max, a `PyConst` sum type, `truncate`, and the binary-blob decoder.

The SECOND, smaller wall is `DType.const` for float16, bfloat16 and the four
fp8s, whose `truncate` entry is `float_to_fp16` / `float_to_bf16` /
`fp8_to_float(float_to_fp8(x))` — the same C-effect seam dtype.bend documents.
`wk_sealed` names those four dtypes and `wk_blocked` turns "this rule wants a
sealed `dt.const`" into "no answer". That is `fold.bend`'s stated policy: the
fold reports the absence and the caller decides. `const_sealed`, `store_sealed`
and `store_sealed_pm` are the rows, and Python rewrites all three.

## Two dependencies that turned out to be nuisances, not blockers

- **`dtype.bend` is unreachable for ANY importer.** Its fp16 / bf16 / fp8 / i64 C
  effects make the checker print "14 defs rely on unsafe or foreign code" and
  exit 1 whatever the importer does — a two-line file that imports it and does
  nothing else prints the same fourteen lines. So `strong_dtype` and
  `weak_dtype` are RECONSTRUCTED here, five LOC each, under dtype.bend's own
  `Cls` arms, following the precedent `fold.bend:92-174` set when it hoisted
  `least_upper_dtype`. `DEFAULT_INT`/`DEFAULT_FLOAT` are helpers.bend's
  "int32"/"float32" and nothing in weak.py overrides them.

## What the mutation table says

Twelve real edits, each re-run, each "rows that moved" column MEASURED. **Five of
them move NOTHING** (3b, 3c, 4, 7, 8 — the table lists five; its prose
paragraph above says three, which is stale), and each is a statement about what
this gate can and cannot see:

- 3b `wk_keep` becomes LAST-WINS — nothing, and that is the measurement the
  header claims: `disjoint` says the two ported entries claim disjoint op sets.
- 3c the subset test `and` → `or` — nothing, because `rej_all_empty=True` says
  every reject set is empty.
- 4 `wk_fire` drops `pm_claimed` — nothing, and this is a THEOREM not a gap:
  `wk_keep` is first-wins, so a permissive gate changes the answer only when the
  intended rule would not have fired. `claimed_store_b` pins the predicate; what
  nothing here sees is its WIRING into `wk_fire`.
- 7 `uncast_const.bad` drops the `dts.result != u.dtype` test — nothing, and this
  is a real gap in the fixture set: on fixture C the hypothetical result equals
  `u.dtype` either way.
- 8 the `wk_dt` default — nothing, because `wk_ready` gates it.

Mutation 9 is the one worth reading twice: `wk_sealed`'s bfloat16 arm priority
13 → 12 moves `sealed_count` and `sealed_count_n` but NOT `sealed_half`, which
stays True because the float16 arm is still there. A priority flip that mostly
works is exactly what a boolean cannot see.

## Reported, not fixed

`ops.bend:1313 eq_cls.sel` has six arms for `S.Cls`'s seven constructors, so
`CWeakFloat` falls to `case _` and becomes `CFloat`. Measured:
`eq_dt(weakfloat, weakfloat)` is `False` while `eq_dt(weakint, weakint)` is
`True`. The damage is not cosmetic — `intern.find` compares with `eq_node`, so
two structurally identical `CAST(..., weakfloat)` nodes do NOT hash-cons and two
of them build FOUR arena nodes where two would do (the same with `half` builds
three). ops.bend is read-only to this port, so `wk_eq_dt` is a LOCAL COPY and the
def says so; when the one-line fix lands these two defs go away and `wk_eq_dt`
becomes `O.eq_dt`.

## Not done

`rg "TODO\(p3\)" tinybendygrad/uop/weak.bend` is the work queue: 18 markers.

- `weak.py:27` `cast_weak_srcs` — `weak_dtype` and the `least_upper_dtype`
  lattice ARE ported; the `dt` it computes is not. It is `pm_commit_weak`'s third
  rule and the only one of that table whose body is absent here.
- `weak.py:45` `_lower_weak_ops` — a module constant, 30 op literals, no value
  without the def.
- `weak.py:48` `absorb_weak_src` — `s.commit_dtype(dtypes.int)` on the
  weakint-over-a-bool-or-float arm.
- `weak.py:53` `lower_weak_node` — reads `commit_dtype`, `strong_dtype` (PORTED)
  and `dtype_from_uop` (PORTED as `wk_dtype_at`). Only the first is missing. It is
  `pm_lower_weak`'s fourth rule.
- `weak.py:92` `cast_consts` — `UOp.cconst(s.val, s.commit_dtype(dtypes.int))`.
  It is `pm_cast_const`'s only rule, which is why that table is EMPTY here.
- `weak.py:69` `pm_lower_weak` rule 0 — `buf.max_numel()` is
  `prod(to_max_shape(shape))` and `to_max_shape` is `int(x.vmax)`. The rest of
  the rule (`idx.cast`, `idx.valid`, the `UPat.var("gate").where(...)` pattern) is
  portable and is NOT the wall.
- `weak.py:73` rule 1 and `weak.py:75` rule 2 — two and one `commit_dtype` reads.
- `weak.py:98` `pm_cast_const` — the whole table.

Two divergences that are refusals rather than TODOs, because a rule or a row
already carries them: `DType.const` at float16 / bfloat16 / the four fp8s is
`None`, so `commit_srcs_at` and the STORE rule answer "no rewrite" where Python
rewrites; and `DType.const`'s int arm is `c_intN(x).value`, which RAISES on
overflow in Python while `wk_dt_const` is total — no row, because a value a weak
CONST can hold does not overflow a `U32`.