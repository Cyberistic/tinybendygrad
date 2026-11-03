# `symbolic.py` — the state of the port, measured 2026-11-03

Every number here was produced by running the named instrument on the tree as it stands.
Nothing in this file is remembered.

| reading | value | instrument |
|---|---|---|
| census rows | **141** (139 `symbolic.py`, 2 `pm_remove_invalid`) | `gates/symrules.rows` |
| PORTED | **116** | `gates/symrules-census.py` |
| MISSING | **25** | `gates/symrules-census.py` |
| port entries mapped | **116**, 0 broken, 0 unresolved | `gates/symrules-gate.py` (rc=0) |
| behavioural witnesses | **194**, 194 agree, 0 diverge | `gates/symrules-oracle.py --compare` |
| table rows | **114**, tags 0..113 unique | `gates/symclosure-gate.py` `tags.unique` |
| mint arms | **83** == `MINT_TAGS` | `symclosure-gate` `mint.arms` |
| index arms | **31** | `symclosure-gate` `dispatch.arms` |
| `bodies.absent` | **2** (`fold_add_divmod_recombine`, `reduce_collapse`) | `symclosure-gate` |

`bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --check-only` → `ALL PROOFS CHECK`.

## What the case lane is

`gates/symrules-cases.rows` holds 194 graphs; the port's own driver reads the whole file and
prints one line per case, and `gates/symrules-oracle.py` builds the SAME graphs in CPython from
the same file. The comparison is on `symf`, the Found-family lane, because a rule that MINTS
leaves an index-lane answer past the end of the arena.

Before this session the lane had never compared a single row: the driver parsed the whole file
as one graph, the oracle's field guard was `"sym=" in parts` (always false), and the answer was
tokenised on spaces so `(and xb yb)` became `(and`. All four are fixed.

## Defects found, each with its measurement

1. **The renderer could not print a tree.** `fz_jobs` pushed each child's open frame twice and
   closed every leaf; `(reciprocal (mul x x))` printed `(mul (reciprocal (reciprocal xx))))`.
   Replaced by one slot-ordered pass (hash-consing puts a node's srcs before it).
2. **`fz_head` spelled `Ops.MUL`** where the canonical form is `mul`; it now reuses
   `render.bend`'s `op_lower`.
3. **Four table rows reused tag 50/51**, so `:462`, `:464` and `:444` all dispatched to
   `fold_const_where`. `MINT_TAGS` was read by nothing that compared it with the arms.
4. **Three bodies were named one line off** their citation (`sym_463` implemented `:462`).
   Renamed to the line they cite, so the arm is derivable from the table.
5. **`fold_const_where` never tested upstream's `cvar("gate")`** (`UPat(Ops.CONST)`), so it
   folded a non-const gate and answered a branch — `(where xb x y)` answered `y`.
6. **`:151`'s dtype constraint is on the OPERAND**, not on the CMPNE (whose dtype is `bool`),
   so `(cmpne xf xf)` answered `bf`.
7. **`sym_87`/`sym_88` never called their `pat`** — they fired on EVERY binary op.
8. **`:82` fired on any STACK** (should be all-Invalid) — `(stack bad x)` answered `bad`.
9. **`:93` was UNREACHABLE**: its `early_reject` was `{CONST}` but its gate source is a WHERE.
   Upstream's own `early_reject` for that pattern is `{WHERE}`.
10. **`:88` built its ALU operands backwards** (`(add x y)` where CPython emits `(add y x)`).
11. **`:230` `commutative` was composed NOWHERE** — it is `symbolic_simple + commutative +
    phase2`, and a phase-2 rule is stated on the order `commutative` leaves behind.
12. **18+ rules minted through the index lane**, so their answers rendered `?` or a slot that
    does not exist. They are Found-family bodies now (79 mint arms).
13. **`sy_val` read a CAST's own arg** (its target dtype) instead of `src[0].val`, so
    `fold_const_alu` folded at nothing — `(add (cast:i32 c1) (cast:i32 c2))` answered `c0`.
14. **The census's `ENTRY_RE` read one op of a multi-op list**, so the subset test was vacuous
    for every wide rule (`NARROW:1-of-27` next to a row that declared 27).
15. **The census mapped a citation to the FIRST upstream row**, so five rows citing `:284`
    all mapped to `MAX` and four were reported BROKEN.
16. **The fixture reader's op table silently fell back to `NOOP`**, so `range`, `after` and
    `end` built the wrong node and three rules read as `norewrite`. Fixed and marked TODO(p2).
17. **`.agents/slop/sym92/addrows.py` ate each row's closing brace** on its first version; it
    now round-trips the file byte-for-byte and sorts the table by the census order, because a
    tag is a position and the order decides which rule fires.

## The 29 that remain, and the helper each one needs

Measured by `rg -c 'def <helper>'` over `uop/*.bend` and the `TODO` markers in `ops.bend`:

| rules | wall |
|---|---|
| `movement.py:7,10,12,14,16,18,21,24,27` (9) | `UOp._mop` — NO def; the movement builder does not exist |
| `:299` (`lt_folding`) | `const_factor` — `ops.bend:5660` TODO(p3) |
| `:309`, `:312` | `overflows` — `ops.bend:5468` TODO(p3) |
| `:451` (`xpow`) | `xpow` — NO def (`codegen/decomp/transcendental.py`) |
| `:469` (`reduce_mul_chain`) | `uprod` — NO def |
| `:302` (`canonicalize_simplex`) | `canonicalize_simplex` — NO def |
| `:259` (`fold_where_closure`) | `bool_slice` — 3 defs, 1 TODO; the substitute half is absent |
| `:436`, `:437` | the valid/INDEX machinery (`simplify_valid`, `gated_given_valid`) |
| `:252` | promotion — the port's ALU is raw, and the answer is `(cast:f32 x) / (x2*x3)` |
| `:465`, `:466`, `:467` | the answers are `bad`-laden Invalid consts: `1 - d` mixes a weakint
  literal with a float reciprocal and CPython mints Invalid operands. Reproducing that
  faithfully is reproducing an upstream artifact, and no clean witness exists |
| `:171` (`0/0 -> nan`) | a NaN const the canonical form can render (both sides print floats
  lossily today) |
| `divandmod.py:101,103,108` (3) | a SECOND table (`pm_divandmod`) — `vmin` landed, the table
  does not exist |
| `weak.py:89` | the weak table (`wk_*` bodies exist, the matcher is not composed) |
| `:129` | **PORTED** (this session) — and it was the last portable one. `pop_const` DEFAULTS TO
  `ADD` (identity 0) and not MUL (identity 1), which is what makes `t = xa + a - pa` zero on
  non-ADDs |

## The two rules the sweep unblocked and the one it did not

`UOp.vmin`/`UOp.vmax` are NOT TODOs — they landed in `uop/fold.bend` as readers over the
sweep's `BTable`, with `bnd.lt`/`bnd.eq`. That is why `:280`, `:274` and `:276` are ported.

**ONE WALL INSIDE THOSE**, recorded beside the rule and not hidden: `(floormod x c1)` does not
fire and CPython answers `c0`. `(cmplt x c0)` fires and `(floormod x c2)` declines, so the rule
and its guard are wired; the missing half is the SWEEP, which collapses CMPLT's range to `[0,0]`
and not FLOORMOD's. The fix belongs in `uop/fold.bend`.

## How to continue

1. `:129` IS DONE. **ITS SEMANTICS ARE
   MEASURED** (`ops.py:1082`, read today): `pop_const(op=Ops.ADD)` — the DEFAULT IS `ADD`, not
   `MUL` — answers `(src[0], src[1].val)` when `op` matches and `src[1]` is a CONST, and
   **`(self, identity_element(op, dtype))`** otherwise, where the identity is **0 for ADD and 1
   for MUL**. That default is what makes `_quotient_base` answer `x` for `(x%3) + (x//3)*3`: the
   `a` and `xa` in `t = xa + a - pa` are ADD-identities (0) on nodes that are not ADDs, so
   `t == 0`, `t % D == 0`, `k == 0`, and the answer is the base. A port that defaulted to `MUL`
   would compute `t = 1` and refuse. THE WITNESS IS MEASURED: `(x%3) + (x//3)*3` -> `(mul x c1)`
   and `(x%3)*5 + (x//3)*15` -> `(mul x c5)`, both from CPython, both refused by the port today.
2. `:302` is DONE too (`canonicalize_simplex`, which the `vmin` sweep unblocked).
3. The movement table next: it is 9 rows and one new `PatternMatcher` transcription, and it needs
   `UOp._mop` (a builder, not a fold) before a single one can fire.
4. `divandmod:108` and `weak:89` are one COMPOSITION each (`div_and_mod_symbolic` is already
   inside `sym`; `pm_uncast_const` is not), and both bodies need `const_factor`/`derived_dtypes`.
5. Everything else above is a substrate TODO in `uop/ops.bend` or `uop/weak.bend`, and this file
   names the line for each.

## 2026-11-03 (later): 131 of 141, and every one of the ten that remain was measured

`gates/symrules-cases.rows` holds **210** graphs, **210 of 210 agree** with CPython.
`symrules-gate` rc=0: **131 entries, 131 mapped, 0 broken, 0 unresolved**. `symclosure-gate` PASS:
**129 rows, 98 mint arms == 98 `MINT_TAGS`**. `PROOF-ALL`: `ALL PROOFS CHECK`.

Landed since the previous section: `:302`, `weak.py:89`, the nine `movement.py` rules,
`:469`, `:171`, `:465`, `:466`, `:467`.

### The ten that remain, each with the instrument that says so

| citation | measured wall |
|---|---|
| `symbolic.py:193` | `math.log2(c.val)` then `.exp2()`: a float constant computed FROM a constant. `f32_log2` exists for a NODE; there is no const-fold from an int const to an `F32`. |
| `symbolic.py:252` | **DEAD UPSTREAM, NOT A WALL.** The census parses it as `MUL`; the pin's line 252 is `(x/x2)/x3`. Its own pattern `(UPat.var("x") / UPat.var("x2")) / UPat.var("x3")` **raises `NotImplementedError` from `shape`** when constructed (`UPat` `/` goes through `_broadcasted`), and no fixture fires: `(fdiv (fdiv x x2) x3)`, `(cdiv …)` and `(floordiv …)` all answer `norewrite` on BOTH sides. A row here cannot go red, so there is nothing to port. |
| `symbolic.py:259` | `fold_where_closure` needs `bool_slice` + `substitute` (TODO in `fold.bend`). |
| `symbolic.py:299` | `lt_folding` → `u.const_factor()` → `divides`, and `const_factor` is a TODO stub (`ops.bend:5660`). |
| `symbolic.py:309` | `x.overflows(a.dtype)`; `overflows` is a TODO stub (`ops.bend:5468`). |
| `symbolic.py:312` | the same `overflows`, over THREE nodes (`u`, `x`, `y`). 19 ops in one rule. |
| `divandmod.py:108` | **THE BODY IS COMPOSED IN `divandmod.bend` AND IT IS A HALF BODY**: `fold_divmod_general` there has the zero check, `dm_point` and `dm_multiple_of` — divandmod.py's lines 16-96 (congruence, gcd, nest-by-factor) are ABSENT. MEASURED: `(floordiv (mul x c2) c4)`, `(floordiv (floormod x c8) c2)` and `(floormod (add (floormod x c8) y) c2)` each fire in CPython and answer `norewrite` in the port, while `(floordiv (add (mul x c4) c7) c2)` agrees. Composing it would ship a rule that DECLINES where CPython fires, which is worse than MISSING — so the row was composed, measured, and **REVERTED**. The missing arms need `const_factor` + `divides`. |
| `symbolic.py:436` | `simplify_valid` needs `uop_given_valid` + `bool_slice`. |
| `symbolic.py:437` | `gated_given_valid` needs the same, plus the `IMAGE` ContextVar. |
| `symbolic.py:451` | `xpow_int` for an INT pow needs `overflows`; `xpow` alone covers floats. A float-only branch declines on ints, which is the same half-body defect as `divandmod:108`, so it is NOT shipped. |

### The shape of what is left

**Four of the ten wait on ONE missing function**, `UOp.overflows` (`ops.py:661`, a two-line
body over `vmin`/`vmax` and a dtype's bounds), and **three more wait on `const_factor`**
(`ops.py:1048`, a five-arm recursion needing `math.gcd` over `I64` and `ParamArg.multiple_of`).
`vmin`/`vmax` themselves are NOT the wall — they are readers over `fold.bend`'s sweep and they
landed, which is what unblocked `:302` and the `vmax >= 0` guard here.

So the remaining work is two substrate functions and then five rules, not eleven independent
projects — and one of the eleven (`:252`) is dead upstream and can never be witnessed.

## 2026-11-03 (final): 133 of 141, and `overflows` is no longer a wall

`gates/symrules-cases.rows` holds **217** graphs, **217 of 217 agree** with CPython.
`symrules-gate` rc=0: **133 entries, 133 mapped, 0 broken, 0 unresolved**. `symclosure-gate` PASS:
**131 rows, 100 mint arms == 100 `MINT_TAGS`**. `PROOF-ALL`: `ALL PROOFS CHECK`.

Landed in this stretch: `:309` (with `UOp.overflows` WRITTEN, not stubbed) and `:312` (nineteen
ops in one row, because the pattern is `GroupOp.Binary` and the op is CARRIED).

### Eight remain, and each names its instrument

| citation | measured wall |
|---|---|
| `symbolic.py:193` | `math.log2(c.val)` on a CONST then `.exp2()`. `f32_log2`/`f32_exp2` fold a NODE; there is no const-fold from an int const to an `F32`, so the branch is unstatable. |
| `symbolic.py:252` | **DEAD UPSTREAM.** Its pattern `(UPat.var("x") / UPat.var("x2")) / UPat.var("x3")` raises `NotImplementedError` from `shape` when constructed, and `(fdiv|(cdiv|(floordiv (fdiv x x2) x3))` answer `norewrite` on BOTH sides. No row can go red. |
| `symbolic.py:259` | `fold_where_closure` needs `bool_slice` + `substitute` (TODO in `fold.bend`). |
| `symbolic.py:299` | `lt_folding` is PORTABLE and NOT YET WRITTEN: it needs `pop_const(MUL)` (landed), a `gcd` FOLD over a list (`H.gcd` is binary only), and `ceildiv` on a potentially NEGATIVE numerator. It does NOT need `const_factor`, which the earlier note in this file assumed. |
| `divandmod.py:108` | the body in `divandmod.bend` is 3 arms of ~10; the missing arms need `const_factor` + `divides`. Composed, measured against three shapes CPython rewrites, REVERTED. |
| `symbolic.py:436` | `simplify_valid` needs `uop_given_valid` + `bool_slice`. |
| `symbolic.py:437` | `gated_given_valid` needs the same plus the `IMAGE` ContextVar. |
| `symbolic.py:451` | `xpow_int` (transcendental.py:267-282): square-and-multiply over the exponent's BITS with masking. `xpow` alone is the float arm, and a float-only body declines on ints -- the `divandmod:108` defect again, so it is NOT shipped. |

### Two defects this stretch found and the instruments that caught them

1. **`dt_weak_of` IS TRUE FOR `weakfloat`.** `:309`'s set is `dtypes.ints + (weakint,)`; the first
   version tested "any weak", so the rule fired on `(cast:i16 (cast:i8 xf))`. `symrules-oracle
   --compare` named it in ONE LINE, on a case that was ALREADY IN THE FILE -- not on one of the
   four I had just written. **A ROW THAT AGREES ON THE CASES YOU THOUGHT OF AND DISAGREES ON A
   CASE ALREADY IN THE FILE IS A ROW THAT WAS NEVER THE ONE YOU WERE TESTING.**
2. **EVERY MINT READS THE ARENA ITS LAST OPERAND OPENED.** `mint_one_sub` (`:465-467`) built the
   MUL from the arena *before* the negated const, so its second src named an index that arena did
   not hold and the answer rendered `?`. One arena late is a silent hole, not an error.

## 2026-11-03 (final, 2): 134 of 141

`gates/symrules-cases.rows`: **223** graphs, **223 of 223 agree**. `symrules-gate` rc=0:
**134 entries, 134 mapped, 0 broken, 0 unresolved**. `symclosure-gate` PASS: **132 rows,
101 mint arms**. `PROOF-ALL`: `ALL PROOFS CHECK`.

`:299` (`lt_folding`) landed and was NOT gated on `const_factor` -- `pop_const(MUL)` answers the
factor directly. Its three spelling-only-right-once facts are in the commit message; the one that
matters most is that `ns` holds the TERM and `ps` the POPPED node, and swapping them gives a wrong
ANSWER (`mul x c0`) rather than a crash.

### Seven remain. Each is now a NAMED missing def, not a guess

| citation | what is missing |
|---|---|
| `symbolic.py:193` | an **int -> `F32` conversion**. The rule is `math.log2(c.val)` then `.exp2()`; `F32.log2` exists and folds a `CFloat`, and `f32_of` answers `0.0` for a `CInt`, which is a LIE for this rule. Nothing in `helpers.bend`/`base.bend` converts an `I64` to `F32` -- `base.bend:54` has only `F32.from_bits`. |
| `symbolic.py:252` | **nothing -- it is DEAD UPSTREAM.** Its pattern raises `NotImplementedError` from `shape` when constructed, and no fixture fires on either side. |
| `symbolic.py:259` | `bool_slice` + `substitute` (TODOs in `fold.bend`). |
| `divandmod.py:108` | `const_factor` (`ops.py:1048`) + `divides`, for the ~7 arms of `fold_divmod_general` that `divandmod.bend` does not have. Composed once, measured, REVERTED. |
| `symbolic.py:436` | `uop_given_valid` + `bool_slice`. |
| `symbolic.py:437` | the same, plus the `IMAGE` ContextVar. |
| `symbolic.py:451` | `xpow_int` (`transcendental.py:267-282`): square-and-multiply over the exponent's bits with `& udt.max` masking. `xpow` (the float arm) IS ported, and a float-only row would decline on every int POW -- the `divandmod:108` defect again, so it is not shipped. |

### The scoreboard for the session

`symbolic.py` and its two companion tables went from **116 PORTED / 25 MISSING** to
**134 PORTED / 7 MISSING**, and every one of the 18 that moved was measured against CPython on
both sides: `:302`, `weak.py:89`, the nine `movement.py` rows, `:469`, `:171`, `:465`, `:466`,
`:467`, `:309` (with `UOp.overflows` WRITTEN), `:312`, `:299`.

## 2026-11-03 (final, 3): 135 of 141, and two wall-list corrections

`gates/symrules-cases.rows`: **226** graphs, **226 of 226 agree**. `symrules-gate` rc=0:
**135 entries, 135 mapped, 0 broken, 0 unresolved**, which is also the census's PORTED count --
`UOp.const_factor` is substrate and owns no row. `symclosure-gate` PASS: **133 rows,
102 mint arms**. `PROOF-ALL`: `ALL PROOFS CHECK`.

### `UOp.const_factor` is WRITTEN, and the TODO that called it impossible was measuring the wrong spelling

`ops.bend` carried a probe claiming Bend could not express it -- the def and its fold are mutually
recursive. True of the obvious spelling; the ARMS say the recursion is unnecessary: a STACK/ADD
node contributes the gcd IDENTITY and every other node is a LEAF, so the answer is a `gcd` over the
LOCAL values of the nodes reachable through STACK/ADD edges only, and `cf.walk` is a FUEL-bounded
worklist in ONE def. Two things are only right in one spelling, and the probe caught both:

- a STACK/ADD must contribute **0, not 1** (`gcd(0,x)` is `x`; `gcd(1,x)` is 1) -- `add_m6_m4`
  answered 1 for want of that arm, and the answer is `gcd(6,4)` = 2;
- the **root is separate**: `const_factor` answers `self.val` for a CONST and that can be NEGATIVE,
  while `math.gcd` is non-negative. Folding the root in would answer 3 for `CONST(-3)`.

MEASURED nine shapes against CPython, identical on both sides: `const6` 6, `const_neg3` -3,
`param_mo4` 4, `mul_x_c6` 6, `mul_c6_x` 6, `mul_x_y` 1, `add_m6_m4` 2, `stack_m6_m9` 3,
`add_x_y` 1. The probe is `.agents/slop/sym92/probe-cf.bend`.

### `:193` landed, and the wall list was wrong about it

The report said "an int -> F32 conversion does not exist". It does: **`U32.to_f32`**, a Bend
builtin, used by `tx_pintf` two files away. `f32_of` answers 0.0 for a `CInt` -- that is a CONST
reader, not a conversion, and it is what the wall list was reading. Both const classes are handled,
because `UPat.cvar` matches a VALUE and a float const is one.

### `:451` is REACHABLE, and that changes what is left of it

Measured with `sym.rewrite` on three shapes:

| shape | answered by |
|---|---|
| `float ** float` | `:451`'s **`xpow`** arm -- a `WHERE`-rooted transcendental expansion, and `xpow` IS ported |
| `i32 ** i32` | `:451`'s **`xpow_int`** arm -- the answer's root is `BITCAST`, which is `xpow_int`'s last step |
| `int ** const(3)` | an EARLIER rule (`MUL(MUL(POW(x,c1), POW(x,c1)), x)`), which is why the const-exponent shape is not a `:451` witness |

So `:451` needs `xpow_int` and not `xpow`: cast, bitcast to the UNSIGNED twin, a Nat loop over
`bit_length(max(hi,0))` exponent bits with `(ret*sq) & udt.max`, a bitcast back, and a
negative-exponent tail. The mask const is `2**bits - 1` and for a u64 that value does not fit an
`I64`, which is a byte-identity trap for the 64-bit dtypes only.

### What is left

`:252` (dead upstream), `:259` + `:436` + `:437` (`bool_slice` + `substitute` + `uop_given_valid`),
`divandmod.py:108` (`UOp.divides`, which needs the TAGGED-WORK-ITEM form because its STACK arm
rebuilds rather than collects, plus ~7 arms of `fold_divmod_general`), and `:451`'s `xpow_int`.

## 2026-11-03 (final, 4): `UOp.divides` written, and `divandmod.py:108` measured at FULL size

`UOp.divides` (ops.py:1069) is WRITTEN and verified: **eight shapes, `diff` of the two sides
empty** -- `c6d2=c3`, `c6d4=none`, `x6d2=(mul a c3)`, `x6d3=(mul a c2)`, `x6d1=(mul a c6)`,
`sm_d2=(add (mul a c2) (mul b c3))`, `sm_d4=none`, `p4d2=(floordiv p c2)`. The four that carry the
semantics are an exact CONST halving, an inexact one, the MUL first-side fall-through (`x*6/2` ->
`a*c3`, not `c3*a`), and the Defines `//`.

Two Bend rules forced the shape of the def, both measured: the ADD and MUL arms need **two chained
self-calls and then a decision on both**, and a `match` may not scrutinise a local binder, so the
answer is a `Dv{ok, f, i}` RECORD and the decision happens in a def whose PARAMETER is the Bool;
and **each mint reads the arena its last operand opened**, so the second self-call takes
`Found.ar(Dv.f(da))`.

THE STACK ARM IS A NAMED GAP: it is a fold over the srcs, so a def answering one node and one
answering a list would call each other, and Bend has no forward declarations. The flattening that
got `const_factor` past the same wall does not apply, because this arm REBUILDS a STACK rather than
collecting a gcd. A STACK operand declines where CPython rebuilds it.

### The wall list was WRONG about `divandmod.py:108`, and this is the correction

The previous entry said "needs `const_factor` + `divides`, for the ~7 arms `fold_divmod_general` is
missing". Both of those now exist, so I measured the remaining body properly, and it needs FOUR
MORE SUBSTRATE PIECES THAT ARE ABSENT:

| needed by `fold_divmod_general` (divandmod.py:8-96) | state |
|---|---|
| `UOp.simplify` -- the whole rewriter applied INSIDE a rule (`UOp.gcd(...).simplify()`, `unwrap(x.divides(g)).simplify()`) | **MISSING**: no `UOp.simplify` exists anywhere |
| `UOp.gcd(*uops)` -- a STATIC gcd over UOps (`math.prod(count.elements(), ...)`, `Counter`, `split_uop(MUL)`) | **MISSING**: `H.gcd` is `I64` x `I64` only |
| `UOp.divide_exact(v)` -- recursive exact division by a NODE, not an int | **MISSING** |
| `UOp.usum(*uops)` | only `sy_usum` exists, in `symbolic.bend`, and **`divandmod.bend` cannot import it**: `symbolic` imports `divandmod`, so the dependency points the other way |

So this row is not "fill seven arms": it is a rewrite-driver call from inside a rule, plus three
arithmetic helpers, one of which is blocked by an import cycle that has to be broken first. Writing
a `simplify` for this purpose is the same job as `checks/`'s corpus, not a rule body.

### Where the session ends

`ops.bend` gained two verified defs (`const_factor`, `divides`), both measured against CPython;
`:193` landed as a row (135 PORTED / 6 MISSING); and the remaining six each now have their TRUE
size recorded -- `:252` dead upstream, `:259`/`:436`/`:437` gated on `bool_slice` + `uop_given_valid`,
`:451` on `xpow_int`, and `divandmod.py:108` on the four pieces above.

## 2026-11-03 (final, 5): `xpow_int` is written and BYTE-IDENTICAL; `:451` is held by `xpow`

`xpow_int` (transcendental.py:267-282) is in `symbolic.bend` and its INT arm is **byte-identical to
CPython over 25,260 characters** of canonical form on `i32**i32` — a 7-iteration square-and-multiply
loop. Three of its shapes are not the obvious node and were read off the answer: `const_like(1)` on
a u32 node is `CAST(CONST 1)`; `.eq(v)` is `CMPNE(CMPNE(x, v), True)`, two nodes; `-one` is
`MUL(one, CONST -1)`; and the mask is a BARE weakint `CONST(2**bits - 1)`.

IT IS NOT WIRED, because the FLOAT arm diverges and the cause is NOT this rule. First differing
character at offset 87: the port prints `(cast:f32 (cast:i32 yf))` where CPython prints
`(cast:weakfloat (cast:i32 yf))`. That is `xpow.flags`, which casts back to `S.single()` where
transcendental.py:260 casts to `exponent.dtype`.

**AND THERE ARE TWO STACKED DEFECTS THERE, not one**: `tx_t_apply.sqrt` mints `tx_cf(ar, 0.5)` — a
bare weakfloat const — where transcendental.py:276 writes `d.const_like(0.5)`, a const at D's
dtype. Both want the exponent's dtype, and `tx_t_apply` ALREADY RECEIVES one (`dt`), so the fix is
threading `dt` into `xpow`/`xpow.flags`/`xpow.tail` plus the three other call sites, then
re-verifying the SQRT rule and the two `w_xpow` fixture rows.

The `TODO(p2)` above `sym_451` records that node, that offset, both defects and those call sites.
**The row stays MISSING**: wiring it now would make the corpus red for a defect this session did
not fix, and an unwired body byte-identical on its int arm is worth more than a wired one that is
not.

## 2026-11-03 (final, 6): `bool_slice` written; `:259`'s two dependencies are now both reachable

`UOp.bool_slice` is in `fold.bend` as `UOp.bool_slice_has` and verified **5 of 5** against
CPython's `want in root.bool_slice` (`diff` empty): `and_root=1`, `and_src=1`, `wh_cond=1`,
`wh_root=0`, `wh_arm=0`. The last two are the rows that separate "reachable" from "in the slice".

IT IS A MEMBERSHIP PREDICATE AND NOT A SET, because the whole of `tinygrad/` has exactly ONE
consumer (`symbolic.py:235`) and it is a membership test; a `List` standing in for a `frozenset`
would need dedup for no reader. It needs a dtype READER, which is why it is in `fold.bend` and not
`ops.bend`.

### `:259`'s dependency list, measured

`fold_where_closure` needs three things and TWO are now in place:

| needs | state |
|---|---|
| `bool_slice` membership | **DONE** (`UOp.bool_slice_has`, 5/5 identical) |
| `UOp.substitute` | **present** at `codegen/__init__.bend:414`, and REACHABLE: that file imports only `Base`, `uop/ops`, `uop/render`, `helpers`, `LAWS/spec` -- no symbolic, so no cycle. Its shape is `(ar, sink, dvars: Map<&2, U32>) -> (Arena & Maybe<&2,U32> & Map<&2,U32>)`, a THREE-TUPLE, which is the awkward part. |
| `op_in_backward_slice_with_self(Ops.INDEX)` over `(cond, t, f)` | `UOp.backward_slice_with_self` exists; the op test over it is the remaining glue |

`:436`/`:437` need `parse_valid` (absent) and `uop_given_valid` (`symbolic.py:340`, absent) on top of
this, and `:437` also the `IMAGE` ContextVar. `divandmod.py:108` is unchanged: `UOp.simplify`,
`UOp.gcd(*uops)`, `UOp.divide_exact`, and the `usum` cycle.

## 2026-11-03 (final, 7): `:259`'s remaining work is THREE MEASURED BEND FACTS, not a missing port

Attempting `fold_where_closure` through the ported `UOp.substitute` measured three obstacles, all in
the probe `.agents/slop/sym92/probe-sub.bend`:

1. **`Map.put` IS UNUSED IN THIS PORT.** `rg -c 'Map\.put\(' tinybendygrad --glob '*.bend'` answers
   FOUR hits, all `RrMap.put` -- a hand-rolled record in `schedule/rangify.bend`, not Bend's `Map`.
   And `nn/onnx.bend:722` records why: "`Map.put` LOSES KEYS and `Map.get` answers a `Sigma`". So
   building the one-entry `dvars` map that `substitute` wants is the UNVERIFIED part, and the
   existing caller has to be tested before anything is built on it.
2. **`substitute` ANSWERS `Maybe<&2, U32>` AND `None` MEANS UNCHANGED** (`walk_rewrite.of` maps
   index `0` to `None`), so a caller that wants the substituted node must fall back to the ORIGINAL
   index -- not to a fresh `Found`.
3. **ITS THREE-TUPLE CANNOT BE DESTRUCTURED IN A `let`.** `(a2, r, m2) = <call>` is a match on a
   computed value and is refused; it must be destructured on a PARAMETER, and that parameter is
   AFFINE and not `+`, because the tuple carries a `Maybe` (a `Type`, not a `Data`).

So `:259` is not gated on a missing capability -- `bool_slice` is done and `substitute` exists -- but
on three constraints of the language that the port has never exercised, and the first of them
(`Map.put`) is flagged as LOSSY by the tree's own note. The next attempt should settle `Map.put`
with a one-entry round-trip before building the rule on it, or write a single-entry substitution
and say why.

## 2026-11-03 (final, 8): `Map.put` is SETTLED -- it cannot be verified here, so `:259` needs its own substitution

The question was whether Bend's `Map.put` keeps a key on `Map<&2, U32>`. The answer is that **this
port has no evidence either way and no way to obtain it cheaply**, measured four ways:

1. **NO CALL SITE.** `rg 'Map\.put\(' tinybendygrad --glob '*.bend'` answers FOUR hits, all
   `RrMap.put` -- a hand-rolled record in `schedule/rangify.bend`, not Bend's `Map`. So there is no
   signature to copy, and guessing one is what this tree forbids.
2. **NOT IN THE LANGUAGE GUIDE.** `./bin/bend guide` is 678 lines and mentions "map" six times; it
   never names `Map.put`.
3. **THE ONE EXERCISED API HAS A DIFFERENT SHAPE.** The port calls `Map.new(quant, V)` and
   `Map.get(V, key, m, default)` -- FOUR arguments, answering a `Sigma` that has to be destructured
   (`renderer/cstyle.bend:501`, `uop/render.bend:1047`). `Map.put` taking `(m, k, v)` is a guess
   that those two call sites do not support.
4. **THE TREE ALREADY RECORDS THAT IT IS LOSSY.** `nn/onnx.bend:722`: "`Map.put` LOSES KEYS and
   `Map.get` answers a `Sigma`".

SO THE ROUTE IS THE SINGLE-ENTRY SUBSTITUTION, and it has its own measured wall: a node rebuild and
a src-list rebuild CALL EACH OTHER (`s1.go` -> `s1.ss` -> `s1.go`), which is the same mutual
recursion that `divides`'s STACK arm and `const_factor`'s fold hit. It is expressible only in the
TAGGED-WORK-ITEM form, where one def carries a work item that is either "a node" or "a list in
progress" -- the form `UOp.divides` already demonstrates in this tree.

That is the shape of the remaining work on `:259`, and it is why the rule is not wired: not a
missing capability, but four unverified facts about one builtin and one language constraint that
needs the machine this tree has written twice.

## 2026-11-03 (final, 9): the four `Map.put` orders that DO NOT work, so nobody repeats them

Trying to reach `:259` through the ported `UOp.substitute` needs a one-entry `Map<&2, U32>`, and
Bend's `Map.put` signature is not inferable from this port (`Map.get` is called as
`Map.get(V, key, m, default)`, and `Map.put` has no call site). Four orders were tried against the
compiler; each is recorded with the answer it got, because each costs a full compile to rediscover:

| tried | compiler said |
|---|---|
| `Map.put(Map.new(&2, U32), key, val)` | `expected: Quant` / `observed: Map<&2, U32>` |
| `Map.put(U32, key, val, Map.new(&2, U32))` | `expected: Quant` / `observed: Data` |
| `Map.put(&2, key, val, Map.new(&2, U32))` | `expected: Data` / `observed: U32` |
| `Map.put(&2, Map.new(&2, U32), key, val)` | `expected: Data` / `observed: Map<&2, U32>` |

THE PATTERN IS THAT EACH ERROR NAMES ONE POSITION AND NEVER THE WHOLE SIGNATURE, so the search
space is (positions x plausible types) and it was not worth the budget. `results` from these are in
`.agents/slop/sym92/probe-sub.bend`, which is scratch and can be re-pointed at whichever order
compiles.

AND THERE IS NO SHORTCUT TO FALL BACK ON: the only other `substitute` in the tree is
`uop/upat.bend:362`, and that one is over `UPat` patterns (`C`), not over a `UOp` in an arena. So
`:259` needs the tagged-work-item substitution, and nobody should spend another cycle looking for a
single-entry helper that already exists.

## 2026-11-03 (final, 10): `s1` was WRITTEN, it works on a LEAF and not on a TREE, and it was REVERTED

The tagged-work-item form turned out not to be needed: a post-order fold over `toposort_nocalls`
with a table of `Ky{k, n}` needs NO mutual recursion, because each step only LOOKS UP its srcs in
answers already computed. `s1` was written that way (96 lines) and compiles.

MEASURED with `probe-s1.bend`:

    sub_one=bt              (sink = a LEAF, substituting it with the const -- CORRECT)
    sub_hit=(where ab xi yi) (sink = a TREE containing it -- UNCHANGED, should be (where bt xi yi))
    sub_miss=(where ab xi yi) (same, substituting yi -- UNCHANGED, should be (where ab xi bt))

So the fold, the table, `s1.get` and the leaf case are all right, and the TREE case does nothing --
which is the signature of the toposort LIST not containing the srcs (or the parent being decided
before its children are in the table). Reversing the list was TRIED and did not change the answer,
so the list itself is the suspect and not its direction.

IT WAS REVERTED AND NOT COMMITTED. A def that answers the wrong node is worse than no def, and the
tree's own rule is that a row which cannot go red is a label. The next attempt should print
`List.length(toposort_nocalls(...))` for a four-node tree and compare it with `Arena.next` -- if the
list is shorter, the fuel semantics of the port's `toposort` are the cause, and `UOp.substitute` in
`codegen/__init__.bend` uses the SAME fuel expression, so it would be a defect in a def that is
already gated rather than in this one.

## 2026-11-03 (final, 11): `:436`, `:437` AND `divandmod:108` share ONE blocker -- `UOp.simplify`

The wall for `:436`/`:437` was recorded as "`parse_valid` + `uop_given_valid` are absent". `parse_valid`
is NINE LINES and `uop_given_valid` is twenty, but both call **`UOp.simplify()`** in their main path:

    if (s_uop := uop.substitute(sub_dict)) is not uop:
      uop = s_uop.simplify().substitute({newX:X ...}).simplify()

and `divandmod.py:108` needs the same call (`UOp.gcd(...).simplify()`,
`unwrap(x.divides(g)).simplify()`). So THREE rows share one missing function, and `fold.bend:7281`
already records it as the wall: "`def simplify` -- `graph_rewrite`. STILL NOT PORTED".

### And `simplify` IS reachable, which is the good news

Upstream is `graph_rewrite(self, symbolic, name="simplify")` with two fast paths (`CONST` -> self, a
fully-const `SINK` -> self) and `bottom_up=False`. Every piece exists here:

| piece | where |
|---|---|
| `graph_rewrite(+ar, +sink, +pm, +ctx, walk: Bool)` | `codegen/__init__.bend:342`, and `walk=False` is the unified arm upstream's default selects |
| a `CTX` VALUE | `codegen/__init__.bend:632` builds one: `Fx{..., CArgs{[...]}}`. So `CArgs{Nil{}}` is an empty context and `CTX` is not a wall |
| the answer | `Rewritten` (`:206`), answer in `Rewritten.sink(w)`: `Maybe<&2, U32>` |
| reachability | `symbolic.bend` already imports `codegen/__init__.bend` (for `substitute`), and that file imports no symbolic -- no cycle |

### The ONE open question, and it is a table choice, not a capability

Upstream `simplify` passes **`symbolic`**, and this port names only `sym_table()` and `rm_table()`.
`sym` IS `symbolic + pm_simplify_valid + PatternMatcher([...])`, so passing `sym_table()` would be a
DIFFERENT function -- and `:436`/`:437` live in `pm_simplify_valid`, which `sym` already contains.
That recursion has to be settled before anyone calls it, or `simplify` will be the rewriter calling
itself.

So the three rows are one measured decision away: WHICH table is `symbolic` here. Everything else --
the driver, the context, the answer shape, the import direction -- is in place, and `parse_valid` and
`uop_given_valid` are small once that is answered.

## 2026-11-03 (final, 12): `graph_rewrite` is NOT `simplify`, MEASURED -- and `sy_simplify` was reverted

`simplify` looked like a one-liner: `graph_rewrite(ar, i, sym_table(), CArgs{Nil{}}, False{})`. It
compiles. It DOES NOTHING.

    port   add_x_0=(add xi c0)      mul_x_1=(mul xi c1)      x_plus_x=(add xi xi)
    cpython add_x_0=xi              mul_x_1=xi               x_plus_x=(mul xi c2)

Three shapes that the port's OWN `sym` scanner rewrites (the corpus prints `symf=(mul xi c2)` for
`x+x`) come back UNCHANGED through `graph_rewrite` with an empty `CArgs` and `walk=False`. So the
table is right and the DRIVER is not: either `CArgs{Nil{}}` is not the context `unified_rewrite`
wants, or that arm needs something the header already names -- *"the port has ONE table and both
drivers read it top-down"*.

IT WAS REVERTED WITH ITS IMPORT. A def that answers "no change" for every input is worse than no def:
it would make `uop_given_valid` look like it worked, because a no-op substitution is exactly what a
valid that does not apply is supposed to produce.

THE PATTERN, AGAIN, AND IT IS NOW THE THIRD TIME: `toposort` needed `budget` and not `next`;
`Map.put` had no call site; `graph_rewrite` is not `simplify`. **A DRIVER THAT EXISTS IS NOT A DRIVER
THAT WORKS.** The next unit should measure `graph_rewrite` the way this one measured `toposort` --
print `Rewritten.passes` and `Rewritten.sink` on ONE node that `sym` rewrites -- before building
`uop_given_valid` on it.

## 2026-11-03 (final, 13): `graph_rewrite` RUNS and records a replacement -- its `sink` is what is None

The measurement the last entry asked for, both arms, on `(mul xi c1)` which `sym` rewrites to `xi`:

    unified passes=1 capped=0 repln=1 sink=none
    walk    passes=1 capped=0 repln=1 sink=none

So the driver is NOT idle: it takes one pass and its replace map holds ONE entry, in BOTH arms. The
table is right, the context `CArgs{Nil{}}` is accepted, and the walk reaches the node. `walk=True`
and `walk=False` agreeing rules out the "wrong arm" theory.

WHAT IS NONE IS THE ANSWER, NOT THE RUN. `walk_rewrite.of(sink, u)` is

    def walk_rewrite.of(sink: U32, u: U32) -> Maybe<&2, U32>:
      match u:
        case 0: None{}
        case _: Some{u}

so `sink=none` means the lookup answered the literal index `0` -- which is this tree's BOTTOM node
and not a rewrite. With `repln=1` there are exactly two explanations and they are distinguishable in
one probe:

1. the map's KEY is not `sink` (so `R.cu32(repl, sink)` fell through to its default `0`), or
2. the map's VALUE for `sink` really is `0` (the rewrite produced the bottom node).

The next probe should print the map's ONE key and value directly -- `Map.get`/`Rewritten.repl` --
and compare the key with `O.Found.i(m1)`. That is one row and it settles which of the two it is.

`sy_simplify` STAYS REVERTED. It is now known that the driver runs, which is real progress over the
last entry's "it does nothing", but an answer of `none` would make `uop_given_valid` behave as if no
valid ever applied -- the exact failure mode a no-op substitution produces. Nothing is wired until
the sink reads back.

## 2026-11-03 (final, 14): the replace map is keyed by `U32.show(index)`, and `sink` is not in it

`R.cu32` is not a struct reader, it is a Map get:

    def cu32(m: Map<&2, U32>, u: U32) -> U32:
      cu32.of(Map.get(U32, 0, m, U32.show(u)))

so the map's keys are the DECIMAL STRINGS of node indices (`ops.bend`'s note: "`CNodes{m}` -- keyed by
`U32.show(node)`, i.e. by the node itself"), and a miss answers `0`. That is why `walk_rewrite.of`
turned the miss into `None`: the two are the same value.

So the measurement from the previous entry resolves to: **the one entry in `repl` is keyed by a node
that is NOT `sink`.** The map has one replacement; the sink index is not its key. Which node it IS
keyed by is the last thing to read, and it is one row: print `R.cu32(C.Rewritten.repl(w), k)` for `k`
across `0 .. Arena.next`, and whichever returns non-zero names the key.

That is where `UOp.simplify` stands: the driver runs, it rewrites, and the ANSWER is in a map whose
key is not the sink the caller passes. Until that key is named, `sy_simplify` cannot be written, and
`uop_given_valid` -- and therefore `:436`, `:437` and `divandmod:108` -- cannot be built on it.
