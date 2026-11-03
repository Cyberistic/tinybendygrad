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

## 2026-11-03 (final, 15): `graph_rewrite` CANNOT apply `sym_table` -- the rule BODIES are not reachable from codegen

The one-row probe, `(mul xi c1)` which rewrites to `xi`:

    xi=1 c1=2 mul=3 n=4 n2=4
    repl: 0->0 1->1 2->0 3->0 4->0

So the replace map holds ONE entry and it is `1->1` -- `xi` mapping to ITSELF, an identity. `mul=3`,
the node the table should rewrite, is a MISS (`3->0`). `repln=1` was counting the identity entry, and
`walk_rewrite.of` turning the miss into `None` is now explained exactly.

**THE DRIVER RUNS, READS THE TABLE, AND NEVER APPLIES A BODY.** And it cannot: `O.PMEntry` carries the
tag, the ops and the reject set, but the BODY for each tag is dispatched by `sym_dispatch` -- which
lives in `symbolic.bend` -- and `codegen/__init__.bend` does not import symbolic (that is the
direction the dependency has: symbolic imports codegen, for `substitute`). So
`graph_rewrite(ar, i, sym_table(), ...)` is a table with no dispatcher: it can decide WHICH entries
match and has nothing to call when they do.

THAT SETTLES `UOp.simplify`, AND THE ANSWER IS THAT IT CANNOT BE BUILT WHERE I WAS TRYING. It must
live in `symbolic.bend` on top of the `Found`-threaded scanner that ALREADY works -- `sym_f` /
`sym_rewrite` -- iterated to a FIXPOINT, because `simplify` upstream is `graph_rewrite(self,
symbolic)` and `graph_rewrite`'s fixpoint is the `walk=False` arm. The pieces it needs are all here and
all in symbolic already: `sym_table()`, `sym_f`, `sy_novel` (which is the "did it change" test), and
`mint_ar`.

WHAT IS STILL OPEN: how many passes, and the `CONST`/`SINK` fast paths. Both are readable off
`ops.py:495-501`; neither needs codegen.

THIS IS THE END OF THE `graph_rewrite` ROAD, and it cost four turns to learn that the wall was never a
missing driver -- it was that the driver and the bodies live on opposite sides of an import edge that
this tree deliberately enforces.

## 2026-11-03 (final, 16): `uop_given_valid`'s TWO shapes, found the hard way and then reverted

Attempting `uop_given_valid` (the `try_simplex=False` half, which is all `:437` needs) produced two
findings and an incomplete def; the def was REVERTED unbuilt.

**1. THE UPSERT IS A CHAIN, NOT A RECURSION.** The `defaultdict`'s `bounds[expr][int(is_upper)] = c`
is a LAST-WINS upsert that writes ONE side and leaves the other. The obvious one-def version binds the
list TAIL twice (once in the replace branch, once in the recurse branch) and Bend refuses: `rest
(consumed more than once)`. The expressible shape is three defs that form a CHAIN and never a cycle:

    bd.get(bs, e) -> Maybe<&2, Bd>        find, no callback
    bd.rm (bs, e, acc)                    filter, no callback
    bd.mk2(m, bs, e, up, c)               calls bd.rm
    bd.add(bs, e, up, c) = bd.mk2(bd.get(bs, e), bs, e, up, c)

and **the order is not preserved, which is invisible**: the only thing order could change is the
`fake{i}` NUMBERING, and those names are substituted back out before the answer is returned.

**2. THE CANDIDATE LIST MUST BE A LIST OF PAIRS, AND THE FLATTENED FORM DOES NOT FOLD.** `(expr,
var)` pairs flattened to `[e0, v0, e1, v1, ...]` cannot be walked -- a list pattern binds ONE head and
a tail, and a nested match on the tail is a match on a local binder. A `Cd{e, v}` record makes it one
match again:

    def ugv.fwd(cs: List<&2, Cd>, +f: O.Found) -> O.Found:
      match cs:
        case Nil{}: f
        case +c <> rest: ugv.fwd(rest, s1.sub(O.Found.ar(f), O.Found.i(f), Cd.e(c), Cd.v(c)))

with `ugv.bwd` the same def with `Cd.e`/`Cd.v` swapped; then `simplify`, substitute back, `simplify`,
and answer the ORIGINAL when the index did not move (upstream's `is not uop` test).

That is the whole remaining shape of `:437`'s dependency, and it is written down rather than left in a
reverted buffer.

## 2026-11-03 (final, 17): `:436` AND `:437` ARE BLOCKED BY A CYCLE, AND IT IS BEND'S, NOT A MISSING HELPER

`uop_given_valid` was written -- 138 lines, the chain upsert and the `Cd{e,v}` pair list, compiling
FIRST TRY on the two shapes the previous entry derived -- and `sym_437` on top of it. Then the TABLE
refused it:

    observed : sym_437        (a filled definition ... live code cannot use it)

and the line numbers say why, exactly:

    5135  sym_451            <- a rule body
    5240  s1.sub             <- its helper, before the table
    5649  sym_table()
    5820  sym_dispatch.go
    6277  sym_dispatch_f     <- the minting dispatch: THIS references `sym_437`
    6314  sym_f              <- ... which is defined AFTER this, and CALLS it
    7966  sy_simplify        <- needs sym_f
    8169  sym_437            <- needs ugv -> sy_simplify

The chain is `sym_dispatch_f` -> `sym_437` -> `ugv` -> `sy_simplify` -> `sym_f` -> `sym_dispatch_f`.
**IT IS A CYCLE, AND IT IS NOT AN ORDERING MISTAKE**: `:437`'s body calls `simplify`, `simplify` is a
fixpoint of the whole table, and the table dispatches back to `:437`.

UPSTREAM ESCAPES IT WITH A LATE IMPORT, AND THE SOURCE SAYS SO:

    def simplify(self, tracked=False):
      # late import!
      from tinygrad.uop.symbolic import symbolic
      return graph_rewrite(self, symbolic, name="simplify")

That `# late import!` comment exists precisely to break this cycle, and a late import is the one thing
Bend cannot express: defs are resolved at compile time, there are no forward declarations, and a
cycle is refused rather than deferred.

SO `:436` AND `:437` ARE NOT PORTABLE AS RULE BODIES IN THIS FILE -- not for want of `parse_valid`
(landed, 4/4), `bool_slice` (landed, 5/5), `s1` (landed, 3/3) or `simplify` (landed, 4/4), but because
their body is the rewriter and the rewriter dispatches to them. `divandmod.py:108` shares it: its
`fold_divmod_general` calls `simplify` too, and its rules are reached from the same table.

THE THREE WAYS OUT, none of them small and all of them measurable:
1. a TWO-LEVEL dispatch -- an outer table for rules that may call the rewriter, taking the inner
   table as a PARAMETER, which is expressible because a parameter breaks the name cycle;
2. `simplify` as a FIXED-POINT THUNK defined before the bodies and given the table at the call site
   (same idea, threaded through every caller);
3. declaring the two rows UNPORTABLE-IN-THIS-LAYOUT with this cycle as the evidence, which is what
   this entry now does.

## 2026-11-03 (final, 18): I SHIPPED A BROKEN `symbolic.bend` AND A FALSE PORTED ROW, AND THE CHECK I RAN COULD NOT SEE IT

The previous commit (`f07c230e3`) left `symbolic.bend` NOT COMPILING and `gates/symrules.rows` with a
PORTED row for `:437` whose body no longer existed.

TWO MISTAKES, and the second is the dangerous one:

1. I reverted the `sym_437` BODY but not its ROW: `sym_table` still cited `symbolic.py:437` and
   `sym_dispatch` still called `sym_437`. A row that names a def nothing defines is exactly the
   "row that cannot go red" this tree forbids -- it READ as PORTED and the census counted it.
2. **I VERIFIED WITH THE WRONG INSTRUMENT.** The command that reported `ALL PROOFS CHECK` ran
   `tinybendygrad/LAWS/PROOF-ALL.bend`, and that aggregate does NOT compile `uop/symbolic.bend`.
   `symbolic.bend --check-only` says `SOME PROOFS FAIL / observed : sym_437`. A GREEN AGGREGATE OVER
   A FILE IT DOES NOT INCLUDE IS NOT A CHECK OF THAT FILE, and I had been using it as one all
   session.

REPAIRED: the row and its dispatch arm are gone, every tag above `120` is shifted down in `PMEntry`,
in the `case N:` arms AND in `MINT_TAGS()` -- the third list is the one the first attempt missed, and
`symclosure-gate` caught it at `mint=104 MINT_TAGS=105`. Verified after the repair:
`symbolic.bend --check-only` = ALL PROOFS CHECK; `symclosure-gate` PASS (104 == 104);
`symrules-gate` GREEN 137/137; `symrules-oracle --compare` **232 of 232 agree**; census 137 / 4.

THE RULE THIS TREE ALREADY HAD, WHICH I HAD BEEN READING AS A FORMALITY: verify the FILE, not an
aggregate that cites it. `checks/port-compile-gate.py` exists for exactly this and sweeps every file
one at a time.

## 19. The re-vendor swapped a PRIMITIVE, and the census could only see part of it

MEASURED 2026-11-04. `git diff 5c2bf39d6c4b..upstream/master -- tinygrad/mixin/elementwise.py`
flips BOTH comparison primitives:

    pin :  logical_not = cast(bool).ne(True)   -> CMPNE(x, True)
           ne = _binop(CMPNE) ; eq = ne().logical_not()
    HEAD:  logical_not = cast(bool).eq(False)  -> CMPEQ(x, False)
           eq = _binop(CMPEQ) ; ne = eq().logical_not()

Same NAMES, same MEANING, DIFFERENT NODES. `rg 'Ops\.CMPNE' tinygrad/uop/symbolic.py` answers
NOTHING at HEAD, so inside this lane `CMPNE` is a node nothing builds. The port had 42 `CMPNE`
sites. The census could only see the ones in a PATTERN (an op set is read off the source); the ones
that only MINT a node were invisible to it and wrong at runtime.

The shared mint was `mint_not`, and it was one line: `CMPNE(v, CONST True)` -> `CMPEQ(v, CONST False)`.

`ne(a, b)` is `CMPEQ(CAST(CMPEQ(a,b)), False)` -- TWO CMPEQ levels where the pin had one CMPNE. That
is why `:271` (`gate.where(x,0) != 0`) had to be re-ported as a two-level pattern AND a two-level
answer, and why `:155` (`x == x -> True`) replaced the pin's `x != x -> False` outright: `x != x`
now builds the same node as `logical_not(logical_not(x))`, which `:140` already owns.

## 20. What the census reads, and the leniency that let five false rows stand

`render()` marks an upstream row `PORTED` when ANY port entry mapped to that `(file, line)` has
`why == "OK"`. Six upstream rules share one line when a table entry is a comprehension (`:171` is
`for op in GroupOp.Associative`), so ONE correct port row at `:171` printed SIX `PORTED` rows --
five of which had no arm of their own. MEASURED before this turn: tags 95..99 were parked on the
pin's `:284` (a COMMENT at HEAD) and the six `:171` rows still read `PORTED` off tag 44 alone.
They now each carry a row (`MAX/OR/AND/ADD/MUL` + the missing `XOR`), tags 44 and 136 collapsed.

`symbolic.py:284` at the pin was that comprehension; at HEAD the comprehension is at `:171` and the
COMMENT took `:284`. **A comment is not a rule, and a citation that lands on one is invisible --
`verify()` calls it `CITATION-NOT-AN-UPSTREAM-RULE` and `render()` counts the row MISSING.**

## 21. TAG NUMBERING IS A DISPATCH KEY, NOT A LABEL

`symclosure-gate`'s `tags.unique` requires the table's tags to be `0..n-1`. That is not style: the
tag is the key `sym_mint_f` / `sym_dispatch.go` match on, so a HOLE is a key nothing can reach and a
DUPLICATE is a body reached by the wrong rule. Every row deletion therefore forces a renumbering
that moves the rows, both arm tables AND `MINT_TAGS` together. MEASURED this turn: `MINT_TAGS` had
been carrying NINE tags with no row, and was missing 48 (`sym_284`, which mints) -- the two errors
cancel in the COUNT and show up only as `mint=96 MINT_TAGS=104`.

A row's POSITION in the list is separate from its tag: `symrules-gate`'s `ORDER` check is a
SUBSEQUENCE test over upstream's composition order, so the six `:171` arms had to move under tag 44,
tag 47 above tag 45, and the two `:338` rows had to be adjacent -- with their old numbers until the
renumbering pass. Moving a row and moving its number are two different edits and doing one is a
half-repair that the gate names.

## 22. `fits` IS THE MISSING PRIMITIVE, and it blocks every guarded rule

`tinygrad/uop/symbolic.py:32`:

    def fits(x:UOp, v:PyConst) -> bool: return x.dtype not in dtypes.sints or x.dtype.min <= v <= x.dtype.max

It is called **12 times** in that file, and the port has NO equivalent: `rg 'def .*fits'` over
`tinybendygrad/uop/symbolic.bend` answers only `ci_fits`, which is the i32 LANE check in
`exec_alu`, not a dtype-range check. So `:316` (`x*-1 < c -> -c < x if fits(x, -c.vmin)`) is
blocked on a primitive, not on a line: **an unguarded `:316` would rewrite `x*-1 < c` where `-c`
overflows x's dtype, and a WRONG REWRITE IS WORSE THAN A MISSING ROW.**

The same hole is worth measuring across the other 11 sites before claiming any of them: a guard
dropped in translation is invisible to a census that compares OP SETS.

## 23. MEASURED STATE at `6a726a812`

`symrules-census.py --rows`: **135 rows -- 130 PORTED, 0 BROKEN, 5 MISSING** (was 121/1/13 at the
re-pin, 99 before that). `symrules-gate`: `port entries 130, mapped 130, broken 0, unresolved 0`,
**0 problems**, `ORDER` included.

MISSING, each named: `symbolic.py:316` (the `fits` wall above), `divandmod.py:103`
(`UOp.simplify`+`gcd`+`divide_exact` and the `usum` import cycle), `symbolic.py:450` / `:451`
(`simplify_valid`'s `# late import!`, still present at HEAD), `symbolic.py:476` (STORE with
where/invalid, needs the valid/INDEX machinery).

`symclosure-gate` still FAILs on `narrow.symbolic_202_ccast` and `bodies.absent`
(`fold_add_divmod_recombine`, `reduce_collapse`). Both PREDATE this turn and neither names a row
this work touched. **A GREEN `symrules-gate` IS NOT A GREEN CLOSURE GATE.**

`tinybendygrad/uop/symbolic.bend --check-only` = `ALL PROOFS CHECK`.

## 24. THE CYCLE I CALLED "GENUINE" IS A TABLE CHOICE, AND BEND'S REFUSAL IS AT NAME RESOLUTION

MEASURED 2026-11-04, and it CORRECTS section 16 of this report.

Section 16 said `:450`/`:451` are blocked because `simplify_valid -> uop_given_valid -> simplify ->
sym -> simplify_valid` is a genuine cycle and upstream escapes it with `# late import!`. **THE CHAIN
IS RIGHT AND THE CONCLUSION WAS WRONG, because `simplify()` does NOT re-enter `sym`:**

    tinygrad/uop/ops.py:490   # late import!
    tinygrad/uop/ops.py:491   from tinygrad.uop.symbolic import symbolic      <-- BASE table
    tinygrad/uop/ops.py:492   return graph_rewrite(self, symbolic, name="simplify")

and the two tables are DIFFERENT:

    symbolic.py:124  symbolic_simple = pm_data_invalid + PatternMatcher([...])
    symbolic.py:247  symbolic        = symbolic_simple + commutative + PatternMatcher([...])
    symbolic.py:448  pm_simplify_valid = PatternMatcher([...  :450, :451 ...])
    symbolic.py:463  sym             = symbolic + pm_simplify_valid + PatternMatcher([...])

`uop_given_valid` runs on `symbolic` -- WHICH EXCLUDES `pm_simplify_valid`. **So the rule that calls
`uop_given_valid` re-enters a table that does not contain that rule, and there is no cycle at
runtime at all.** The late import is there for MODULE-load order, not to defer the cycle; the cycle
is avoided by the table choice.

WHAT BEND ACTUALLY REFUSES, MEASURED with two throwaway files (`cycle-probe.bend`,
`cycle-probe2.bend`), the same three defs and nothing else:

    a -> b -> c -> a        "an unfilled law is a dead claim: live code cannot use it"
    b -> c -> a -> b        SAME, so it is not definition ORDER either

The refusal is at NAME RESOLUTION: a def cannot call one that is not yet filled, and a cycle can
never fill. It is not a termination check and no decreasing counter reaches it.

SO THE WALL IS REAL BUT ITS SHAPE IS WRONG IN THE RECORD: `:450`/`:451` are blocked because the
port's fixpoint folds over ONE table (`sym_rewrite(sym_table(), ...)`, `symbolic.bend:5992` and
`:6422`) and dispatches through ONE pair of tag functions, so a rule in that table that must
re-enter it is a NAME cycle whatever table it asks for -- the table is a VALUE and the dispatch is
the CALL GRAPH. Upstream separates the two by module-level name binding, which Bend does not have.

THE FIX, NAMED SO IT IS A DESIGN DECISION AND NOT A SURPRISE: the base lane needs its OWN dispatch
(`sym_dispatch_base` / `sym_mint_base`) over the base table, so `sym_450` has no static path back to
itself. That duplicates ~130 arms, and a duplicated dispatch is exactly the copy-paste this tree
refuses -- so it is a deliberate trade to be taken with the LOC cost written down, not smuggled in.
**The same reasoning covers `divandmod.py:103`, which needs the same base-lane re-entry; `:451` is
the second rule in the same table and shares the fix.**

GOOD NEWS, MEASURED, AND IT IS WHY THIS IS NOT A DEFECT IN THE PORT: the port has NO cycle today
because `:450`/`:451` are ABSENT. Absence is what makes the lane sound; adding them without the
base lane would turn a correct port into one that does not compile.

## 25. `divandmod.py:103` IS FOUR PRIMITIVES, THREE OF WHICH THE PORT HAS NEVER HAD

MEASURED 2026-11-04 on `fold_divmod_general`. The record said it "needs `UOp.simplify`, `UOp.gcd`
and `UOp.divide_exact` and the `usum` import cycle"; measured one at a time, the three primitives
are ABSENT, not merely unreachable:

    divandmod.py:9   x.pop_const()                        port: PRESENT
    divandmod.py:26  UOp.usum(*new_xs)                     port: NO `UOp.usum` (only `sy_usum`, symbolic.bend:557)
    divandmod.py:66  UOp.gcd(*all_uops, y).simplify()      port: NO `UOp.gcd`, and `.simplify()` is the wall in 24
    divandmod.py:68  x.divide_exact(gcd)                   port: NO `UOp.divide_exact`

and `UOp.gcd` is VARIADIC with a `simplify()` on its answer, so the row cannot be reached by adding
one helper: it needs a new variadic reduction, an exact-division helper, a `usum` that
`divandmod.bend` can call (which the `symbolic -> divandmod` import direction forbids), and the base
lane from section 24.

**THE POINT OF WRITING IT THIS WAY: "BLOCKED" IS A CLAIM AND IT SHOULD NAME WHAT IS MISSING.**
Three of the four are ABSENT primitives, which is a different and cheaper defect than a cycle --
they can be built and tested on their own, with CPython as the oracle, without touching the rewriter
at all. Only the fourth is the design decision.

STATE, FINAL FOR THIS SESSION: 135 census rows -- **132 PORTED, 0 BROKEN, 3 MISSING**
(121 / 1 / 13 at the start of the session). `symrules-gate`: `port entries 132, mapped 132,
broken 0, unresolved 0`, **0 problems**. `symclosure-gate`'s four structural rows green.
`symbolic.bend --check-only` = `ALL PROOFS CHECK`.

**A NOTE ON WHAT IS IN GIT HERE.** The `.py` halves of the four probe pairs ARE tracked; the
`.bend` halves are NOT, because `.gitignore:37` ignores `probe-*.bend`. That ignore rule predates
this session and is not mine to move, so the record says what it is rather than pretending
otherwise: the port half is reproducible from the case lists above and the CPython half that IS in
git, and `cycle-probe.bend`/`cycle-probe2.bend` ARE tracked because their names do not match the
rule. **A REPORT THAT CITES A PATH GIT DOES NOT OWN IS THE DEFECT THIS TREE NAMES IN ITS OWN
`TOOLS.md` LEDGER, SO IT IS NAMED HERE INSTEAD OF LEFT FOR A READER TO DISCOVER.**

## 26. OPEN: `sym_f` rewrites the `:171` node and `sy_simplify` does not

MEASURED 2026-11-04 with `.agents/slop/sym92/probe-171.bend` (int8 `x`, `(x+1)+2` and `(x+100)+100`,
each node rendered in ITS OWN arena). Every reading on one graph:

    sym_284.pat(ok)                                   True
    Maybe.is_some(sym_284.mk(ok))                     True
    assoc_op(Ops.ADD)                                 True
    sym_mint_f(46, ok)      -> (add x (add c1 c2))    REWRITES
    sym_rewrite_f(table, ok)-> (add x (add c1 c2))    REWRITES
    sym_f(ok)               -> (add x (add c1 c2))    REWRITES
    sy_simplify(ok)         -> (add (add c1 x) c2)    UNCHANGED

`sy_simp.n` is `8` iterations of `sy_simp.go(sym_f(F.folded(O.Found.ar(f)), O.Found.i(f)), f)` and
`go` adopts ANY `Some` (`case Some{+g}: g`), so a `sym_f` that answers `Some` on the same node must
be adopted on pass 1. It is not. **The two are therefore being asked about DIFFERENT NODES or
DIFFERENT FOLDS, and the surviving suspects are `F.folded(ar)` versus the probe's
`F.Folded{ar, F.UOp.fold(ar)}`.**

**ROOT-CAUSED ONE LEVEL FURTHER, AND IT IS AN OSCILLATION.** Walked pass by pass on the same node:

    sy_simp.n(1n)  -> (add x (add c1 c2))        REWRITTEN
    sy_simp.n(2n)  -> (add (add c1 x) c2)        ORIGINAL
    sy_simp.n(3n)  -> (add x (add c1 c2))        REWRITTEN
    sy_simp.n(4n)  -> (add (add c1 x) c2)        ORIGINAL

A PERIOD-2 CYCLE: one rule folds `(x+c1)+c2` into `x+(c1+c2)` and another unfolds it back, so the
answer `sy_simplify` returns depends only on the PARITY OF THE PASS BUDGET -- and the budget is
`8`, an even number, which is why the public entry shows the original. `sym_f` on the REWRITTEN node
answers the original (`B_step = (add (add c1 x) c2)`), so the reverting rule is reachable in one step.

THREE CANDIDATES ARE EXCLUDED, MEASURED on the rewritten node:

    sym_245.pat  False      (:253, the coefficient-sum fold)
    sym_284.pat  False      (:171, the two-stage fold that CREATED it)
    sym_271.pat  False      (:271, the gated-where rule)

so the reverting rule is none of the obvious three and the next step is a TAG SWEEP -- call
`sym_mint_f(tag, ...)` for every tag and name the first `Some`. **A SWEEP IS THE RIGHT INSTRUMENT
HERE AND A GUESS IS NOT: the tree's own doctrine is that an instrument declares its population by
discovery, and "which rule fires on this node" is exactly a population question.**

WHY THIS MATTERS BEYOND `:171`: `UOp.simplify` is the port's public simplifier and it is
`sy_simplify`, so ANY graph that reaches this pair of rules gets an answer chosen by pass parity. It
is a confluence defect, not a `:171` defect.

NOT ROOT-CAUSED FURTHER HERE, and deliberately not guessed at. What IS established: the six `:171` arms are
NOT dead -- `sym_f` reaches them -- so the five `PORTED` rows are honest. What is NOT established is
whether `UOp.simplify` (the port's public entry) applies them, and that is the question a `:171`
guard has to be tested through.

THE EARLIER `:171` GUARD ATTEMPT WAS THEREFORE MEASURING NOTHING, and its revert was correct: the
probe rendered `(mul c100 c2)` for a node built from `100` twice, i.e. a constant the graph did not
contain, which is the ARENA-ALIASING symptom this tree already names -- **every row must render in
the arena its node belongs to, and a row that renders another arena's index is not a measurement.**
Two of the readings in this section had exactly that defect before it was fixed.

CONSEQUENCE FOR THE GUARD WORK: `:253`'s guard (committed, `probe-253`) was verified through
`sy_simplify` on nodes rendered in their own arenas and it refuses correctly, so that one stands.
`fits` for `:171`, `:309`/`:311`, `:485`, `:255`/`:259`/`:261` and `:283` STAYS UNWRITTEN until this
discrepancy is settled, because a guard tested through a path that never reaches the rule proves
nothing in either direction.

## 27. OPEN: `:263` IS DEAD IN THE PORT -- `pat` says True and `mk` answers None

MEASURED 2026-11-04, `.agents/slop/sym92/probe-263.bend`, `(y + x) + x` with x,y int8, one arena per
case, every question asked of the SAME folded node:

    sym_251.pat(node)                          True
    sym_251(node)                              norewrite
    sym_mint_f(82, node)                       norewrite
    sy_simp.n(1n)  sy_simp.n(2n)  sy_simp.n(3n)  all unchanged

So the six `:263` arms do not fire, and the failure is in the BODY and not in the pattern, the
dispatch or the fixpoint -- **this is NOT the oscillation from section 26: pass 1 does not rewrite
either, so there is no parity to blame.**

`sym_251` is `sy_tri_f(pat, mk(mint_const_like(mint_ar(sy_ar(x)), x, sym_251.z(x, u), CInt 2), ...))`
and `mk` matches on `Maybe`: a `None` from `mint_const_like` makes the whole rule answer `None`. That
is the surviving suspect -- `mint_const_like.go` calls `sy_trunc(sy_dt1(x, u), v)` and answers `None`
when the truncation does.

**WHY THIS IS A ROW-LEVEL DEFECT THE CENSUS CANNOT SEE.** The `:263` row reads PORTED because the
port has an entry, the entry cites the line, and the op set matches -- and the rule has never fired.
**A PORTED ROW IS A CLAIM ABOUT A MAPPING; IT IS NOT A CLAIM THAT THE BODY RUNS**, and this tree's
own `DEAD IS NOT A ZERO` is the same sentence one level down.

NOT FIXED HERE. The next step is one call of `mint_const_like` on that exact node to see whether
`sy_trunc` refuses int8 `2` or whether the `Maybe` is being consumed twice, and the fix belongs
wherever that answers, not here.

THE SAME QUESTION NOW APPLIES TO EVERY ROW THIS SESSION DID NOT OPEN. `:171` was found dead in the
same way except that its `mk` was fine and the FIXPOINT was lying; `:263`'s `mk` is not fine. A
sweep that calls `pat`, then `mk`, then `sy_simp.n(1n)` on a fixture for every resposed row would
name every dead body at once, and that sweep is the instrument this lane is missing.

## 28. `:255` IS ALIVE; THE GUARD I WROTE SUPPRESSED IT (reverted)

MEASURED 2026-11-04, `.agents/slop/sym92/probe-255.bend`, `(y + x*c0) + x*c1` on int8:

    sym_246.pat(node)    True
    sym_246(node)        (add y (mul x (add c1 c2)))      the rule FIRES
    sy_simplify(node)    (add y (mul x (add c1 c2)))      and through the fixpoint

So `:255` is NOT dead -- unlike `:263`, which was -- and the "both rows unchanged" reading that
prompted the guard was the reading of a tree where MY GUARD was suppressing the rule. The guard is
reverted and the file is byte-identical to `ae3e3c91`.

**THIS IS THE SECOND TIME IN THIS SESSION THAT A GUARD I WROTE DELETED A WORKING RULE** (the first
was `:309`/`:311`, fixed by rebuilding the bounds table from the minted node's arena). Both times the
probe's two rows BOTH read "unchanged", and both times that is exactly what a correct guard looks
like -- which is why the PAIR has to be read as "one fires, one refuses" and never as "both agree".

WHY THE `:255` GUARD WAS WRONG, by inspection and not by another guess: the `no_overflow` half is the
`sym_248` machinery, which is known good (`:259`/`:261` verified with it), and the `fits` half reads
the minted SUM node's value through `sy_val` on a fold built from that node's own arena. That is the
same shape `:259`'s increment check uses... except `:259` reads the CONST it minted through
`mint_const_like` and this one reads an ALU node's `arg`, which is not a value at all. **`c0+c1` is
an ADD node, and `sy_val` on an ADD answers `None{}` -- so `vf` answered False for every graph.**
That is the bug, it is one line, and it is NOT fixed here because it was found at the end of the
session and a one-line fix at the end of a long session is how the two reverts above happened.

THE NEXT STEP IS NAMED AND SMALL: for `fits(x, c0.vmin+c1.vmin)` the two constants must be READ from
`cside` and ADDED, not read off the sum node -- `H.i64_add` of the two `CInt` payloads, then `fits`.

## 29. `:283`'s `no_overflow` CANNOT BE DECIDED BY A CONST-BRANCH FIXTURE

Attempted, measured, and REVERTED 2026-11-04; the file is byte-identical to `39312ed2`.

The guard is `no_overflow(m:=c.where(t+tt, f+ff))`, and `no_overflow(u)` is
`fits(u, u.vmin) and fits(u, u.vmax)` -- a statement about the WHERE's RANGE. The rule also requires
`t.op == tt.op == Ops.CONST` (or the `f` pair), so the natural fixture has CONST branches:

    c.where(100, 100) + c.where(101, 102)   ->  (where g (add c100 c101) (add c100 c102))

and the port FIRES on it. So did my guarded version, which is why it was reverted as unverified.

**AND THE FIXTURE CANNOT DISCRIMINATE, WHICH IS THE FINDING.** `t+tt` is `UOp.__add__` on two CONSTs,
and a CONST's value is truncated to its dtype AT CONSTRUCTION (`dtype.const` -> `truncate[self]`, the
table section 27 is about). So `100+101` becomes `CONST(-55, int8)` BEFORE the WHERE exists, the
WHERE's own range is `[-55, -55]`, and `fits` is TRUE on both sides of the guard. **A GUARD ABOUT A
RANGE NEEDS A FIXTURE WHOSE RANGE IS NOT ONE POINT, and a const pair collapses to one point by
construction.**

HOW TO TEST IT, named so the next pass does not rediscover this: one branch pair must be a PARAM with
a range wider than the dtype (`UOp.variable("x", -128, 127, dtype=int8)` gives `vmin/vmax` endpoints
that scale out of range), while the OTHER pair stays CONST so the rule's own `t.op == tt.op == CONST`
premise still holds.

THE THREE GUARDS THAT WERE REVERTED THIS SESSION ARE ALL THE SAME LESSON FROM THREE ANGLES: `:309`
suppressed a live rule until the bounds table was rebuilt, `:255` suppressed it because `sy_val` on a
sum is `None{}`, and `:283` could not be read at all because its fixture had one point of range.
**IN ALL THREE THE PROBE, NOT THE RULE, WAS THE THING THAT COULD NOT ANSWER.**
