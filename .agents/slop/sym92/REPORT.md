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

## 30. THE CORPUS IS RED, AND IT IS NOT THIS LANE — measured across three versions

MEASURED 2026-11-04. `checks/differ.py run` on the tree says:

    graphs=38  agree=31  disagree=7  expect-moved=7  selfcheck=# SELFCHECK: FAIL
    disagreeing: binblob, bw, commute, flip, gral, matmul, reduce

`AGENTS.md` records a green 38/38 taken 2026-10-31. **THIS LANE DID NOT CAUSE IT**, and that is a
measurement and not a defence: the same run was taken three times with three different
`uop/symbolic.bend` versions and the count did not move.

    HEAD              1304e7b1    agree 31  disagree 7
    pre-`sy_trunc`    88d71f86    agree 31  disagree 7
    pre-session       45918bfa    agree 31  disagree 7

The last of the three is the file as it stood BEFORE this session's first commit, so the 7
disagreements were already there and belong to another unit's committed work. `reduce`'s row shows
`CONST 5/3`: the port emits THREE const nodes where CPython emits five, which is a folding difference
and not a symbolic-rule difference.

AND THE RUN IS NOT HEALTHY INDEPENDENTLY OF THAT: `not-comparable=38`, `byte-identical=0`, and
`selfcheck=# SELFCHECK: FAIL` with *"the `pI(` form is DEAD on both sides"* and *"the `params` plant
does not change the `pI(` row"*. That is the `prog` graph's `ProgramInfo` lane, which this session
never touched.

**SO THE GOVERNING LINE "the corpus is 38 of 38" IS A RECORD OF A RUN AND NOT A STANDING FACT, and
the DOSE OF STALENESS HAS A NAME THIS TIME: seven graphs, none of them a symbolic graph, plus a dead
`pI(` form on both sides.** Restoring 38/38 is somebody's next task and it is not a `symbolic.py`
task.

THE METHOD IS REUSABLE AND CHEAP: `git show <rev>:tinybendygrad/uop/symbolic.bend > /tmp/x`,
`cp` it in, run, `cp` back. Three runs, ~100 s each, and the answer is a count that either moves or
does not. **A CLAIM OF "NOT MINE" IS ONLY WORTH ANYTHING IF IT IS TAKEN THIS WAY.**

## 31. `sy_trunc`'s FLOAT half is the same defect, and here is the exact remainder

Section 27 widened `sy_trunc` for the INT widths. The FLOAT widths are still missing, and the whole
of what is left is measured here so the next pass does not re-derive it:

    tinygrad/dtype.py:293   truncate[float16]   = float_to_fp16                        <-- MISSING
                            truncate[bfloat16] = lambda x: float_to_bf16(float(x))     <-- MISSING
                            truncate[float]    = ctypes.c_float                        <-- present as `{14, 32, CFloat}`
                            truncate[double]   = ctypes.c_double == identity           <-- MISSING (arm absent)

and the port's own dtype table separates all four by `pri`, which is what an arm would match on:

    LAWS/spec.bend:739  half()      = Dt{12, 16, CFloat{}, "f16"}
    LAWS/spec.bend:740  bfloat16()  = Dt{13, 16, CFloat{}, "bf16"}
    LAWS/spec.bend:741  single()    = Dt{14, 32, CFloat{}, "f32"}
    LAWS/spec.bend:742  double()    = Dt{15, 64, CFloat{}, "f64"}

`bfloat16` and `half` share `bits=16` and `cls=CFloat`, so **(bits, cls) CANNOT tell them apart and
the arm must key on `pri`** -- which is the same thing the six existing arms do (`0`, `9`, `5`, `6`,
`14`), so this is the established shape and not a new hack.

THE ENCODERS ARE ALREADY IN THE TREE and `symbolic.bend` already imports the module they live in
(`import ./../dtype.bend as D`, line 181):

    dtype.bend:797  Dt.fp16(+x: F32) -> F32
    dtype.bend:1168 float_to_bf16(x: F32) -> F32

so the arms are `case S.Dt{12, 16, S.CFloat{}, _}: ... D.Dt.fp16(f)` and
`case S.Dt{13, 16, S.CFloat{}, _}: ... D.float_to_bf16(f)`, plus `{15, 64, CFloat}` as identity.

NOT DONE HERE, and the reason is a real edge case rather than fatigue: a float-dtype const can arrive
with an INT payload (`UOp.const(1, dtypes.float16)` goes through `dtype.const`'s float branch, which
converts first), so the arms need an int->float conversion before the encoder, and `O.CFloat{f}` is
the only float payload the port's `Const` has. **THAT CONVERSION IS THE UNMEASURED PART; the encoders
are not.**

## 32. THE FLOAT ARMS OF `sy_trunc` ARE UNVERIFIABLE, AND THAT IS A MEASUREMENT

Section 31 named the remainder. It was then ATTEMPTED, COMPILED, and REVERTED, because F32 values
cannot be observed anywhere in this port:

    F32.bits(f)      is an AXIOM with no body (helpers.bend:902 says so in words)
    H.f32_show(f)    does not reduce: a probe that prints it emits the CONSTRUCTOR TREE
                     (`SCon{'f', SCon{'1', ...}}`) instead of a string, so the term never normalises

MEASURED, both: a probe over `sy_trunc(half(), CFloat 1.1)` printed `SCon{...}` where the integer
probes print `"fits_1_2=(add ...)"`. **SO THE ANSWER OF AN ENCODER CANNOT BE READ BY ANY INSTRUMENT IN
THIS TREE, AND AN fp16 ROUNDING THAT CANNOT BE READ IS PRECISION CODE THAT CANNOT BE CHECKED.**

CPython's answers are recorded here so the next attempt has an oracle ready and does not have to
re-derive them (`float_to_fp16`/`float_to_bf16` applied at CONSTRUCTION, which is the part that
surprised me):

    UOp.const(1.1,   float16)  -> ConstFloat(1.099609375)     bits 0x3f8cc000
    UOp.const(70000, float16)  -> ConstFloat(inf)             bits 0x7f800000
    UOp.const(1.1,   bfloat16) -> bits 0x3f8d0000
    UOp.const(70000, bfloat16) -> bits 0x47890000

THE ENCODERS THEMSELVES ARE NOT THE PROBLEM: `dtype.bend:797 Dt.fp16` and `dtype.bend:1168
float_to_bf16` are in the tree and the whole file passes `ALL PROOFS CHECK`, and the `pri` mapping is
read straight off `LAWS/spec.bend:739-742`. What cannot be checked is the WIRING plus the INT-PAYLOAD
conversion, and a half-written arm is the "partial table reads as a refusal" defect of section 27 --
so the whole half stays out rather than half of it going in.

**THIS IS THE THIRD TIME THIS SESSION THAT THE HONEST ANSWER WAS "CANNOT VERIFY", AND EACH TIME THE
REASON WAS AN INSTRUMENT AND NOT THE CODE** (sections 28, 29, 32). The pattern is worth more than any
one guard: in this lane a change is only worth landing when a probe can read its answer back, and
three of the artefacts needed to read answers back are missing -- a bounds table that survives a
mint, an `F32` accessor, and a per-row `pat`/`mk` sweep.

## 33. `sy_trunc`'s INT half verified against `ctypes`, including the two's complement

MEASURED, `.agents/slop/sym92/probe-trunc-int.bend`, `i64_show` prints `hi:lo` so a negative value
cannot be mistaken for a positive one:

    S.int8()   200     -> 4294967295:4294967240   = -56     ctypes.c_int8(200).value   -56
    S.uint8()  200     -> 0:200                   = 200     ctypes.c_uint8(200).value  200
    S.int16()  70000   -> 0:4464                  = 4464    ctypes.c_int16(70000)      4464
    S.int8()   70000   -> 0:112                   = 112     ctypes.c_int8(70000)       112

FOUR OF FOUR, and the first row is the one that matters: `-56` is the SIGN-EXTENDED wrap, which is
what separates `ctypes.c_int8(x).value` from a mask. A mask would have answered `200`.

## 34. CORRECTION: THE BASE LANE IS TWO ARMS, NOT A HUNDRED AND THIRTY

Sections 24 and 30 said the last three rows need "~130 duplicated arms" because the dispatch is
static. **THAT COST ESTIMATE IS WRONG, AND THE ERROR WAS MINE: it assumed the BASE lane needed its own
COPY of the dispatch, which it does not -- the base dispatch ALREADY EXISTS.**

MEASURED, and this is the shape that works:

  * `sym_table()` stays the 130 base rows, and `sym_mint_f` / `sym_dispatch.go` keep dispatching them.
    **None of that changes.**
  * the two valid rules go in a SEPARATE `valid_table()` with their own tags;
  * a SEPARATE, TINY `sym_valid_f` dispatches ONLY those two tags (**two arms**);
  * the OUTER entry runs base fixpoint then a valid pass, to a fixpoint;
  * `sy_simplify` -- the one `uop_given_valid` calls -- stays the BASE fixpoint, which is EXACTLY what
    upstream does: `ops.py:492` re-enters `symbolic` (:247), not `sym` (:463).

The cycle then does not exist: `sym_450 -> ugv -> sy_simplify -> sym_f -> sym_mint_f -> (no valid
tags)`, and the only edge INTO `sym_450` comes from `sym_valid_f`, which the base lane never calls.
**THE FIX WAS NEVER "DUPLICATE 130 ARMS"; IT WAS "DO NOT PUT THE TWO RULES IN THE DISPATCH THAT THEY
MUST RE-ENTER".**

WHAT REMAINS IS THE BODY, NOT THE ARCHITECTURE: `uop_given_valid` (split on AND, `parse_valid` per
clause into a bounds map, substitute, re-`simplify`), `simplify_valid` (priority-sort the clauses and
join them with `uprod`), and `gated_given_valid` (a dtype check plus `cond.where(ugv(cond, x), i)`).
`sy_parse_valid` already exists, which is the hard half of `ugv`.

## 35. THE LAST BLOCKER FOR `:450`/`:451`/`divandmod:103` IS ONE TRUNCATED FUEL

With the architecture corrected in section 34, the remaining work is `uop_given_valid`'s BODY. Its
steps, one at a time, and what each costs:

    valid.split_uop(Ops.AND)          PRESENT  (UOp.split_uop, ops.bend:5169)
    parse_valid(stmt) -> (e, up, c)   PRESENT  (sy_parse_valid)
    cond.where(...)                   PRESENT  (mint_where / sy_where)
    a MULTI-ENTRY substitute          <-- THE BLOCKER
    .simplify()                       PRESENT  (sy_simplify, and section 34 says it must stay BASE)
    UOp.uprod(*ret)                   PRESENT  (the AND product)

MEASURED, `codegen/__init__.bend:414-415`:

    def UOp.substitute(+ar, +sink, +dvars: Map<&2, U32>) -> (...):
      walk_rewrite.put(sink, wr.go_sub(O.UOp.toposort_nocalls(U32.to_nat(O.Arena.next(ar)), ar, sink), ...))

`Arena.next(ar)` is THE LENGTH OF THE ARENA, used as a `Nat` fuel for a topological walk
(`ops.bend:1381`). `Arena.budget(+ar: O.Arena) -> Nat` (`ops.bend:3414`) is the sound fuel, and the
comment directly above this line says a previous audit already swept this file for exactly that
mistake -- **so this one call was MISSED BY THE SWEEP THAT WAS LOOKING FOR IT.** A `Nat` fuel equal to
the node COUNT truncates the walk on any graph with a diamond in it, which is every non-tree graph
`uop_given_valid` would be asked about.

AND THE SINGLE-ENTRY SOUND ONE ALREADY EXISTS: `s1` (`symbolic.bend:5536`) was written with
`Arena.budget` precisely because `Arena.next` truncated it, and it is verified 3 of 3. **So the fix is
known and the fix is not new work -- the multi-entry substitute needs `s1`'s fuel and `s1`'s shape
generalised to a map.**

NOT CHANGED HERE, and the reason is disclosure rather than fatigue: `UOp.substitute` is in
`codegen/`, not in this lane, the corpus is RED for reasons section 30 attributes elsewhere, so a
change here could neither be validated by the corpus nor blamed by it -- and `codegen`'s `Map` is
itself the "unverified in this port" component (`Map.put` has no call site and `nn/onnx.bend:722`
records it LOSING KEYS). **A FIX TO A TRUNCATED FUEL THAT RUNS THROUGH A MAP THAT LOSES KEYS IS TWO
DEFECTS, NOT ONE.**

THE THREE ROWS STAY MISSING, and the full chain is now short and measured: generalise `s1` to a map
with `Arena.budget` as fuel -> `uop_given_valid` -> `simplify_valid` and `gated_given_valid` in a
separate `valid_table` behind a two-arm `sym_valid_f` (section 34) -> and `divandmod.py:103` after
that, which additionally wants `UOp.gcd`, `UOp.divide_exact` and a `usum` it can reach.

## 36. ROWS 19 AND 20 ARE NOT GAPS IN THIS LANE, AND MEASURING THAT CHANGED THE ANSWER

Section 33/35 left rows 19 and 20 as "the blocker is absent, whether the BODY exists is a separate
question". MEASURED, and the answer is that they are **NOT GAPS IN THE SYMBOLIC LANE AT ALL**:

    upstream pm_drop_and_clauses   is composed by schedule/indexing.py:160
    upstream pm_move_where_on_load is composed by codegen/__init__.py:283

**NEITHER IS PART OF `sym`.** `sym = symbolic + pm_simplify_valid + PatternMatcher([...])`
(`symbolic.py:463`), and the census's upstream side is exactly `sym` plus `pm_remove_invalid` --
133 + 2 rows. The `drop_and_clauses` rule at `:414` has **NO CENSUS ROW** (measured: no sym row
between 412 and 418), because upstream never puts it in the table this lane ports.

SO "row 19 is DEFERRED" was the wrong question. The question is "does the port's
`schedule/indexing.bend` compose a `pm_drop_and_clauses`?", and the port's file at `:822` carries
upstream's own line as a COMMENT:

    #   return graph_rewrite(UOp.sink(*axes_out[::-1]), symbolic+..., name="reshape")

**THE PORT'S SCHEDULER LANE IS ITSELF BEHIND THREE NAMED WALLS** (`usum` is W3, the `%`//`//` arms
of `_min_max` are W2, `graph_rewrite` is W3), and upstream's line composes
`symbolic+pm_simplify_valid+pm_drop_and_clauses`. So the missing piece is a SCHEDULER-lane change
that needs a third matcher -- and a third matcher in THIS file would make its citation
UNRESOLVABLE, because the census pools a new table name against the SY rows and `drop_and_clauses`
is not one of them. **THE FIX BELONGS TO THE SCHEDULER LANE, NOT TO `symbolic.bend`, AND ADDING IT
HERE WOULD MAKE THE CENSUS RED.**

THE RANGE ALGEBRA IS NOT A BLOCKER, and the header's "blocker ABSENT" note was wrong about that:
`sym_90.any(ar, rt, SET, PROBES)` answers "is any probe in PROBES among SET's range heads", and
`drop_and_clauses`'s test -- `any(r in x.ranges for r in c.ranges)` -- is the SAME FUNCTION with `x`
as SET and `ranges(c)` as PROBES. MEASURED by reading the argument roles, not by name.

**SO ROWS 19 AND 20 LEAVE THIS LANE AS A NOTE, AND THE HEADER SAYS SO.**

## 37. THE CHAIN TO THE LAST THREE ROWS IS NOW FULLY SPECIFIED, AND IT IS FOUR STEPS

Sections 24, 33 and 35 said the three rows need a base lane and a substitute. MEASURED, step by
step, the chain is:

    1. `s1` -> a MULTI-ENTRY substitute.
       MEASURED: `s1.get` ALREADY scans a `List<&2, Ky>` -- the table IS the dict, and `Ky{k, n}` is
       the pair. `s1.sub(ar, sink, key, val)` takes ONE pair; generalising it to a list of pairs is
       the whole change. And `s1` REUSES THE SAME ARENA (`O.UOp.new(ar, ...)`), so a pre-minted
       value keeps its index -- which is what makes the values `ugv` needs (fake VARIABLES) usable.
       The SEMANTICS match upstream's dict: ugv's two dicts never have a value that is a key of the
       SAME dict (`{X:newX}` then `{newX:X}`), so simultaneous and sequential agree for this use.

    2. `ugv` -> `uop_given_valid`, using that multi-substitute and the port's `sy_parse_valid`
       (already present) and `sy_uprod`.

    3. `ugv`'s `.simplify()` -> the BASE fixpoint, not `sym_f`.
       MEASURED: `sym_f` is `sym_rewrite_f(sym_table(), x, u)`, so it CANNOT be the base one while
       the valid rows live in `sym_table`. Upstream's `ops.py:492` re-enters `symbolic` (:247), NOT
       `sym` (:463) -- so upstream's base fixpoint excludes `pm_simplify_valid`, and the port's must
       too. **THIS IS THE CYCLE, AND IT IS BROKEN BY TABLE SEPARATION (section 34): the valid rows go
       in their OWN table with their OWN two-arm dispatcher, and the base fixpoint never sees them.**

    4. `simplify_valid` and `gated_given_valid` -> the two new rows, in that table.

**SO THE THREE ROWS ARE NOT BLOCKED ON A SUBSTRATE. THEY ARE BLOCKED ON FOUR DEFS, AND THE FIRST OF
THE FOUR IS A SMALL GENERALISATION OF A FUNCTION THAT IS ALREADY THERE AND VERIFIED.** The record
previously said "needs a base lane" as if that were an architecture; it is a table split, and the
table split is two arms.

`divandmod.py:103` is separate: it needs `UOp.gcd` and `UOp.divide_exact` (both absent), and
`usum` -- which the port HAS as `sy_usum`, now with the bool arm fixed, but which `divandmod.bend`
cannot reach because `symbolic` imports `divandmod`.

## 38. THE ARCHITECTURE FOR THE LAST THREE ROWS, MEASURED END TO END

Section 34 said the base lane needs its own DISPATCH. MEASURED, the whole shape is now known and
**NONE of it needs a new fixpoint**:

    sym_mint_f      the MINT lane -- one arm per minting tag
    sym_dispatch.go the INDEX lane
    sym_dispatch_f  picks mint vs index by `MINT_TAGS()`
    sym_f           = sym_rewrite_f(sym_table(), x, u)
    sy_simplify     = sy_simp.n(8n, ...) -- 8 passes of sym_f

THE VALID RULES NEED FOUR THINGS AND NOTHING ELSE:

    (a) their own table, `valid_table()` -- so `sym_f` NEVER sees them;
    (b) their own arms in BOTH lanes (`sym_mint_f` and `sym_dispatch.go`);
    (c) `MINT_TAGS()` extended with their tags;
    (d) an OUTER entry that runs the base fixpoint and then the valid pass.

**AND THE CYCLE CANNOT FORM**, because `sym_f` walks `sym_table()` and the valid tags are not in it:
`ugv -> sy_simplify -> sym_f -> sym_table -> (no valid tags)`. So `ugv`'s `.simplify()` is the
port's EXISTING `sy_simplify`, unchanged, and **NO base-variant fixpoint is needed at all** -- which
is what upstream does too: `ops.py:492` re-enters `symbolic` (:247) and NOT `sym` (:463).

THE CENSUS NEEDS NO CHANGE: `verify()` pools `{"sym_table": rows, "rm_table": rm_rows}` and a table
name it does not know falls back to `rows` -- and `:450`/`:451` ARE sym rows (MEASURED), so a
`valid_table` resolves against the sym pool correctly.

SO THE REMAINING WORK IS: `ugv` (the bounds map, the fake variables, the two-phase substitute
through `s1.multi` -- WHICH NOW EXISTS), `simplify_valid`, `gated_given_valid`, the two table rows,
two arms in each lane, and the outer entry. **THAT IS FIVE DEFS AND TWO ROWS, AND THE FIRST OF THE
FIVE IS DONE (`s1.multi`).**

`divandmod.py:103` is separate: it needs `UOp.gcd` and `UOp.divide_exact` (both absent) and a
`usum` that `divandmod.bend` can reach (the port has `sy_usum`, now with its bool arm fixed, but
`symbolic` imports `divandmod`, so the direction is wrong).

## 39. `ugv`'s BOUNDS ARE FINITE IN THIS LANE, AND THAT REMOVES THE LAST DOUBT

Section 38 left `ugv`'s fake variables with a question: upstream's `UOp.variable(name, v0, v1, dtype)`
takes `PyConst` bounds, so upstream can make a fake variable with an INFINITE bound, and the port's
`UOp.variable(ar, nm, lo: H.I64, hi: H.I64, mo, dt)` cannot.

MEASURED, and the doubt is unfounded HERE: the port's `parse_valid` GATES ON THE DTYPE --

    pv.gate:  Bool.and(eq_op(op(ar, lt), OpsCMPLT{}),
                       S.Cls.is_int(S.Dt.cls(sy_dt1(folded(ar), src(ar, lt, 0)))))

so **an expr in a valid clause is always an INT**. An int node's `_min_max` is WRAPPED INTO ITS
DTYPE (`upstream: wrapped(self.dtype, ...)`), so its bounds are FINITE INTS. **THEREFORE EVERY FAKE
VARIABLE `ugv` NEEDS HAS FINITE I64 BOUNDS, AND `UOp.variable`'s I64 PAIR IS ENOUGH.**

That also fixes the bound TYPE question: upstream's bound is a `PyConst` and the port's const bound
is an `H.I64` (the port's `parse_valid` returns `Pv{ok, e, up, c}` with `c: H.I64`), so the port's
bound is an `I64` on both sides -- the const's own value, and the expr's `Bnd` CONVERTED (a
`BndInt{neg, mag}` is an I64 in two operations).

SO THE FOUR REMAINING DEFS ARE:

    ugv                the bounds map (expr -> (lo, hi)), the fake variables, the two-phase
                       substitute through `s1.multi` (DONE), and `.simplify()` = `sy_simplify`
                       (unchanged -- no base variant is needed, section 38)
    simplify_valid     priority-sort the clauses and join them with `uprod`
    gated_given_valid  the dtype checks plus `cond.where(ugv(cond, x, try_simplex=False), i)`
    the two TABLE ROWS + two arms in each lane + the outer entry

**AND NOTHING IN THAT LIST IS A SUBSTRATE WALL ANY MORE.** The walls were `vmin`/`vmax` (present),
`ranges` (present), `bool_slice` (present), `substitute` (present, and now MULTI-entry), `simplify`
(present, and the base fixpoint is not a cycle), and the fake variables (finite I64 bounds, present).

## 40. `uop_given_valid` IS DONE AND MEASURED AGAINST CPYTHON

`Ugv` is written, compiles, and ANSWER. The CPython half is `.agents/slop/sym92/probe-ugv.py` and
the port's half is `.agents/slop/sym92/probe-ugv.bend`; they print the same fields.

    field       CPython                     the port
    valid       (cmpeq (cmplt c5 x) bf)     CMPEQ
    pv.ok       true                        true
    pv.up       true                        true
    pv.c        5                           0:5          (the port's I64 is hi:lo)
    target      (add x y)                   ADD
    ugv         (add x y)                   ADD
    A target    (cmplt x c7)                CMPLT
    A ugv       bt                           bt            <- FIRES
    B target    (cmplt x c3)                CMPLT
    B ugv       (cmplt x c3)                CMPLT         <- REFUSES
    C pv.up     false                       false
    C pv.c      0                           0:0
    C target    (cmplt x c0)                CMPLT
    C ugv       bf                           bf            <- the LOWER-bound path

CASE A IS THE DISCRIMINATOR: `x < 7` given `x <= 5` is ALWAYS TRUE, so the answer is `bt`. A port
that no-ops answers `(CMPLT x c7)` and a port that substitutes without folding answers `x`. B AND C
ARE THE REFUSING HALF OF THE PAIR: B's bound does not decide the comparison and C's LOWER bound
decides it the other way.

### 40a. FOUR DEFECTS FOUND BY MEASURING, AND THE FIX FOR EACH

**1. `parse_valid`'s NEGATION SHAPE WAS THE PRE-RE-VENDOR ONE.** The port's `pv.neg.src` read
`CMPNE` with a const `1`. Upstream AT THE PIN (`f5ac54685074`, tinygrad/uop/symbolic.py:344) reads
`CMPEQ` with `src[1].val == 0`, because upstream HEAD's `logical_not` is `cast(bool).eq(False)`
(tinygrad/mixin/elementwise.py:57) and the port's own `sy_logical_not` still writes the OLD
`ne(True)` shape (tinybendygrad/uop/symbolic.bend:596-601). FIXED: `pv.neg.src` now reads `CMPEQ`
and a const `False`/`0`, and `pv` was re-pointed at upstream's two branches.

**2. THE CONST IS ON THE LEFT FOR `X <= c` AND ON THE RIGHT FOR `X >= c`.** MEASURED on CPython:
`x <= 5` is `CMPEQ(CMPLT(5, x), False)` and `x >= 5` is `CMPEQ(CMPLT(x, 5), False)`. Both are
`CMPEQ(CMPLT(...), False)`, so `neg` is True for BOTH, and the CONST-ON-LEFT branch returns
`is_upper = neg` while the other returns `is_upper = not neg`. The port's `pv.arm`/`pv.other` now
carry upstream's polarity exactly.

**3. `is_upper=True` IS THE UPPER BOUND, AND THE PORT HAD IT BACKWARDS.** Upstream's
`bounds[expr][int(is_upper)] = c` puts the `c` at index 1 when `is_upper`, and
`v0, v1 = (expr.vmin if v[0] is None else v[0], expr.vmax if v[1] is None else v[1])` reads index 1
as the UPPER bound. The port's `Ugv.set` and `Ugv.bound` had `up=True` writing and reading the
LOWER side. FIXED: `up=True` is now `hi` in both.

**4. `O.UOp.variable` RETURNS A NEW ARENA, AND THE INDEX IS LEGAL ONLY IN IT.** `O.UOp.new`
(`tinybendygrad/uop/ops.bend:2797`) returns `Found{made, i}` where `made` is the GROWN arena -- the
arena has no mutable store (`ops.bend:2802-2811`), so every mint is a new value. `Ugv.vars` was
reading `O.Found.i(v)` and throwing `O.Found.ar(v)` away, so the fake's index named NOTHING in the
arena the substitute walked. MEASURED: the fake's bounds read `none`, the forward simplify did not
fold, and the answer was `x` instead of `bt`. FIXED: `Ugv.vars` now returns `UgvVars{ar, cs}` and
`Ugv.go` walks `UgvVars.ar(vv)`.

**AND THE FORWARD SIMPLIFY MUST RUN IN THE SUBSTITUTED GRAPH'S ARENA.** `s1.multi` grows its own
arena, so `Ugv.go` passes `O.Found.ar(sub)` to the forward phase and not the arena the table was
built in. With the old arena the simplify saw the OLD graph.

### 40b. THE TWO BENDS THE PORT LEARNED, AND THEY ARE NOT ABOUT EFFECT

- `Maybe` IS A TYPE AND NOT A Data, so it CANNOT be a `+` binder. A `Maybe` answer crosses a
  boundary as a PLAIN parameter (consumed once) and the `match` is on the PARAMETER, because a
  `match` may not scrutinise a COMPUTED value.
- A `+` PARAMETER MAY BE READ ONCE. `neg` read twice in `pv.arm` is bound once with `+n = neg`.
- THERE IS NO FORWARD REFERENCE in Bend, so a mutually recursive pair is not writable. The
  probe's s-expression printer is therefore ONE LEVEL DEEP, and the port's own renderer lives in
  `gates/sym_graph_census.bend`.

## 41. `simplify_valid`, `gated_given_valid`, AND THE VALID LANE ARE DONE AND MEASURED

The census reads `134 entries, 134 mapped and CHECKED, 0 BROKEN` and ONE upstream rule is still
MISSING: `divandmod.py:103`.

    row  upstream          ops    table        tag   state
    120  symbolic.py:450   AND    valid_table   0    PORTED
    121  symbolic.py:451   WHERE  valid_table   1    PORTED

THE CPYTHON HALF IS `.agents/slop/sym92/probe-valid.py` AND THE PORT'S HALF IS `probe-valid.bend`,
AND THEY PRINT THE SAME FIELDS:

    field                    the port      CPython
    simplify_valid           none          none
    gated (weakint)          WHERE         where
    gated (int32)            none          none

THE REFUSING HALF IS `gated(int32)`: upstream's gate is `x.dtype is not dtypes.weakint`, so an
INT32 `x` REFUSES and a WEAKINT one FIRES. THE PORT DOES BOTH.

### 41a. `simplify_valid`'s COMPARISON IS AGAINST THE SORTED LIST

UPSTREAM REASSIGNS `valids` TWICE -- `valids = sorted(valids, ...)` and then
`for stmt in dedup(valids)` -- AND THE FINAL LINE COMPARES `ret != valids` AGAINST THE **SORTED**
LIST. THE PORT COMPARED AGAINST THE **UNSORTED** ONE, AND MEASURED: THE PORT ANSWERED A `CMPEQ`
WHERE CPYTHON ANSWERS `none`, BECAUSE THE SORT HAD PUT THE CLAUSES IN A DIFFERENT ORDER.

### 41b. THE VALID LANE IS A SEPARATE TABLE, AND THAT IS THE CYCLE BREAK

`pm_simplify_valid` IS A SEPARATE MATCHER UPSTREAM (`symbolic.py:448`) AND IS COMPOSED INTO `sym`
AS `symbolic+pm_simplify_valid+PatternMatcher([...])`. THE PORT'S `sym_table()` IS `symbolic`'s
TABLE, SO THE VALID RULES GET `valid_table()` AND THEIR OWN DISPATCHER, AND `sym_f` -- WHICH WALKS
`sym_table()` -- NEVER SEES THEM.

**THAT IS NOT COSMETICS. UPSTREAM'S `ops.py:492` RE-ENTERS `symbolic` (:247) AND NOT `sym` (:463),
SO A VALID RULE THAT CALLED `sym_f` WOULD CYCLE: `sym` INCLUDES THE VALID RULES AND THE VALID RULES
CALL `sym`.** THE SEPARATE TABLE IS WHAT BREAKS IT. `sym_all` IS THE OUTER ENTRY: THE BASE FIXPOINT
AND THEN THE VALID PASS, WHICH IS UPSTREAM'S ORDER.

BOTH VALID RULES MINT, SO THERE IS ONE DISPATCHER (`valid_dispatch_f`) AND NO `valid_dispatch.go`
AND NO `MINT_TAGS` FOR THE LANE -- EVERY ENTRY IN IT MINTS.

### 41c. THE DEF NAMES ARE `sv_450` AND `sv_451` AND NOT `sym_450`/`sym_451`

THE PORT'S `sym_451` IS THE `POW` RULE, AND IT CITED `symbolic.py:451` IN A RE-VENDORED UPSTREAM
WHERE `:451` WAS THE POW LINE. **AT THE PIN (`f5ac54685074`) `:451` IS
`invalid_gate, gated_given_valid` AND `:465` IS THE POW RULE.** THE NAMES ARE LABELS AND THE
CITATIONS ARE IN THE TABLE ENTRIES, SO THE COLLISION IS AVOIDED BY RENAMING AND NOT BY MOVING A
CITATION.

### 41d. THE `IMAGE.value` GATE IS NOT PORTED, AND IT IS RECORDED

UPSTREAM'S `gated_given_valid` HAS A SECOND GATE: `if IMAGE.value > 0 and
x.op_in_backward_slice_with_self(Ops.TRUNCDIV, Ops.TRUNCMOD, Ops.DIV, Ops.MOD): return None`.
**THE PORT HAS NO `IMAGE` FLAG** (MEASURED: `grep IMAGE` over `tinybendygrad/` NAMES NO FLAG
READER), AND THE GATE IS OFF IN EVERY CORPUS RUN, SO THE RULE IS THE SAME RULE WITHOUT IT. THE
GATE IS WRITTEN DOWN IN THE DEF'S OWN COMMENT AND NOT SILENTLY DROPPED.

### 41e. `gated_given_valid`'s `try_simplex=False` IS THE PORT'S `Ugv.go` ALREADY

UPSTREAM'S `uop_given_valid` HAS A `try_simplex` PARAMETER AND THE SIMPLEX BRANCH IS THE
`X0 + X1 + ... > 0` SPECIAL CASE, WHICH NEEDS `GroupOp.Irreducible`. THE PORT'S `Ugv` HAS NO
SIMPLEX ARM AND THE PORT'S `UOp.group` BUILDS A STACK, SO THE PORT'S `Ugv.go` IS
`try_simplex=False` ALREADY. THAT IS STATED IN THE DEF AND NOT LEFT TO BE GUESSED.

### 41f. THE COUNT ROWS MOVE, AND THEY MOVE TOGETHER

    upstream's `sym` is 133 rules
    the port's `sym_table` holds 130 and its `valid_table` holds 2
    so the port's own audit reads  len_sym=132  total_sym=133  skip=1

AND THE CENSUS'S ONE REMAINING MISSING ROW IS `divandmod.py:103` AND NOTHING ELSE. `t_len_sym`
COUNTS **BOTH** TABLES, BECAUSE UPSTREAM'S `sym` IS ONE COMPOSITION AND THE PORT'S TWO TABLES
ARE THAT COMPOSITION SPLIT IN TWO -- THE SPLIT IS WHAT BREAKS THE CYCLE AND IT MUST NOT CHANGE THE
COUNT.

## 42. THE CLOSURE GATE'S PINS AND ITS `MISSING` LIST WERE BOTH STALE

BOTH CHANGES ARE MEASUREMENTS AND NEITHER IS A RELAXATION.

**THE PINS ARE STALE.** THE GATE IMPORTS `tinygrad` FROM THE WORKING TREE AND MEASURES WHATEVER
IS VENDORED, AND THE PINS WERE TAKEN ON 2026-11-03, BEFORE THE RE-VENDOR TO `f5ac54685074`.
MEASURED AT THE PIN -- AND `tinygrad/uop/symbolic.py` IS BYTE-IDENTICAL TO `git show
f5ac54685074:tinygrad/uop/symbolic.py` (BOTH HASH `466a4f01d5185b6c`) -- `symbolic_simple` IS 74
RULES (PINNED 71) AND `symbolic` IS 119 (PINNED 122). **THE MOVE IS IN BOTH DIRECTIONS: A PIN THAT
ONLY EVER GROWS IS A PIN THAT WAS NEVER MEASURED.**

**`MISSING` IS TWO AND NOT FOUR.** `fold_const_where` LANDED AS `sy_fcw`
(`uop/symbolic.bend:6152`) AND `lift_reduce_gate` LANDED AS `sym_90` (`uop/symbolic.bend:6683`),
AND THE CENSUS AGREES: `:209` AND `:97` ARE PORTED. THE GATE'S OWN CHECK FIRES WHEN A
PINNED-ABSENT BODY LANDS, AND IT FIRED.

`fold_add_divmod_recombine` AND `reduce_collapse` ARE STILL ABSENT: `:135` IS PORTED ONLY BECAUSE
ITS RULE'S BODY IS THE ADD RULE AND NOT `fold_add_divmod_recombine` ITSELF, AND `reduce_collapse`
IS ROW 15 OF `codegen/simplify.bend`'S OWN INVENTORY ("WALL: UOp.variable + subs").

## 43. THE BEND SPELLINGS THIS LANE LEARNED, AND THEY ARE NOT ABOUT EFFECT

- `Maybe` IS A TYPE AND NOT A Data, so it CANNOT BE A `+` BINDER. IT CROSSES A BOUNDARY AS A
  PLAIN BINDING (CONSUMED ONCE), AND THE `match` IS ON THE PARAMETER, BECAUSE A `match` MAY NOT
  SCRUTINISE A COMPUTED VALUE.
- A `+` PARAMETER MAY BE READ ONCE. A VALUE READ TWICE IS BOUND ONCE (`+n = neg`), AND A RECORD
  READ TWICE IS DESTRUCTURED ONCE (`case SvP{ad, ab}`).
- THERE IS NO FORWARD REFERENCE, SO A MUTUALLY RECURSIVE PAIR IS NOT WRITABLE. THE IDENTITY TEST
  AND THE INSERTION SORT ARE THEREFORE ONE RECURSION WITH AN ACCUMULATOR.
- `List.append` PREPENDS ON A BORROWED LIST (MEASURED ELSEWHERE IN THIS TREE), SO THE INSERTION
  SORT'S `done` PREFIX IS BUILT WITH IT AND THE ORDER WAS VERIFIED BY THE PROBE, NOT ASSUMED.

## 44. THE LAST ROW, AND WHY CITING IT WOULD BE A FALSE `PORTED`

THE ONE REMAINING MISSING ROW IS `divandmod.py:103` -- UPSTREAM'S SLOW RULE,
`(UPat((Ops.DIV, Ops.MOD), dtypes.weakint, name="d"), lambda d: fold_divmod_general(d))`.
AND THE INVESTIGATION FOUND FOUR THINGS, IN ORDER OF HOW MUCH THEY CHANGE THE ANSWER.

### 44a. THE IMPORT DIRECTION IS FINE, AND THE SUMMARY'S CLAIM WAS MEASURED FALSE

THE SUMMARY SAID "THE `symbolic -> divandmod` IMPORT DIRECTION FORBIDS IT". **MEASURED: IT DOES
NOT.** `symbolic.bend` COMPILES WITH `import ./divandmod.bend as DM` ADDED ("ALL PROOFS CHECK"),
BECAUSE `divandmod.bend`'S TRANSITIVE IMPORTS (`helpers`, `LAWS/spec`, `ops`, `fold`,
`renderer/estimates`) NEVER REACH `symbolic.bend`. THE CONSTRAINT THAT IS REAL IS THE OTHER
ONE: `divandmod.bend` NEEDS `usum` AND `usum` IS IN `symbolic.bend`, SO `divandmod -> symbolic`
IS THE DIRECTION THAT IS FORBIDDEN -- **AND `divandmod.bend` USES NO `SY.`, SO IT DOES NOT NEED
`usum` AT ALL TODAY.**

### 44b. `divandmod.bend` IS AN ORPHAN, AND THAT IS WHY THE ROW IS MISSING

**NOTHING IMPORTS `tinybendygrad/uop/divandmod.bend`** (MEASURED: `grep -rn 'import.*divandmod'`
OVER `tinybendygrad/` AND `gates/` NAMES NOTHING). THE CENSUS READS `symbolic.bend`'S TABLE ONLY
(`gates/symrules-census.py:91`), AND `symbolic.bend` HAS ITS OWN COPIES OF THE TWO FAST RULES
(`dm_101` AT TAG 115 CITED `divandmod.py:96` AND `dm_103` AT TAG 116 CITED `divandmod.py:98`) AND
**NOT THE SLOW ONE**. SO THE ROW IS MISSING BECAUSE THE SLOW RULE IS IN A FILE NOBODY CALLS.

AND THE ORPHAN'S OWN TABLE CITES THE SLOW RULE `# 108` -- A **STALE CITATION**, BECAUSE AT THE
PIN (`f5ac54685074`) THE SLOW RULE IS AT `:103`.

### 44c. THE PORT'S STUB IS A FAITHFUL PORT ON 8 OF THE 9 FIXTURE ROOTS -- AND DIVERGES ON THE NINTH

`divandmod.bend`'s OWN 26-ROOT FIXTURE HAS NINE `fold_divmod_general` ROOTS (`r13`..`r21`), AND
`probe-dmfixture.bend`/`probe-dmfixture.py` ARE THE TWO HALVES OF THOSE NINE ROOTS.

**THE COMPARISON IS BY VALUE AND NOT BY SHAPE**, BECAUSE THE PORT AND UPSTREAM HAVE TWO
DOCUMENTED SHAPE DIVERGENCES (NO `SUB` CANONICALISATION AND NO CONSTANT FOLDING) AND THE PORT's
`r14` IS `SUB(6, MUL(1,4))` WHERE UPSTREAM'S IS `ADD(c6, MUL(MUL(c1,c4), n1))` -- **THE SAME
FUNCTION**. BOTH SIDES ARE EVALUATED OVER THREE SAMPLES, EACH FREE VARIABLE GETTING A DISTINCT
VALUE PER SAMPLE, SO TWO POLYNOMIALS THAT AGREE ON ONE POINT BUT NOT ON ANOTHER ARE CAUGHT.

    root  port          CPython       agree
    r13   [1, 1, 1]     [1, 1, 1]     YES
    r14   [2, 2, 2]     [2, 2, 2]     YES
    r15   [-2,-2,-2]    [-2,-2,-2]    YES
    r16   [1, 1, 1]     [1, 1, 1]     YES
    r17   [0, 0, 0]     none          PORT-ONLY
    r18   [0, 0, 0]     [0, 0, 0]     YES
    r19   none          none          BOTH-none
    r20   none          none          BOTH-none
    r21   none          none          BOTH-none

**THE `r17` DIVERGENCE IS THE PORT BEING MORE INFORMATIVE, NOT WRONG.** `r17` IS `pp % 4` WHERE
`pp` CARRIES `multiple_of=4`. **UPSTREAM's `ParamArg` HAS NO `multiple_of` FIELD AT ALL**
(MEASURED: `tinygrad/uop/ops.py:25-44` LISTS `slot`, `dtype`, `vmin_vmax`, `name`, `addrspace`,
`device`, `volatile`, `image`, `buffer`, `bind_on_realize`, `val`, `spec` -- AND NOT
`multiple_of`), AND `pp.divides(4)` IS `None` UPSTREAM. SO THE PORT'S REWRITE IS SOUND AND
UPSTREAM SIMPLY CANNOT KNOW IT. **BUT IT IS A DIVERGENCE, AND THE TWO LANES REWRITE DIFFERENT
NODE SETS.**

### 44d. AND THE CENSUS WOULD NOT SEE ANY OF IT

`gates/symrules-census.py`'s `verify()` MATCHES A PORT ENTRY TO AN UPSTREAM ROW BY **CITATION
AND OP SET** AND NOTHING ELSE. **SO CITING `divandmod.py:103` WITH OPS `{DIV, MOD}` MAKES THE ROW
GREEN WHATEVER THE BODY DOES** -- AND THE BODY IS A STUB COVERING TWO OF UPSTREAM'S NINE ARMS,
WITH A DIVERGENCE ON THE NINTH FIXTURE ROOT.

**THIS IS THE CLASS THE TREE NAMES: "OPS-STRING ALIGNMENT IS NOT SUFFICIENT: IT LEAVES ROWS
POINTING AT A RULE WHOSE OPS COINCIDE (PRODUCING FALSE `PORTED` ROWS)."** A CITATION IS A
POSITION, AND A POSITION IS NOT A BODY.

**SO THE ROW IS NOT LANDED, AND THE MEASUREMENT THAT SAYS WHY IS THE DELIVERABLE.**

## 45. THE BODY-VERIFICATION INSTRUMENT EXISTED HALF, AND IT HAS NOW RUN

`gates/symrules-oracle.py` IS THE BODY-VERIFICATION INSTRUMENT: IT BUILDS THE SAME GRAPHS IN
CPYTHON AND DIFFS THE ANSWERS. **IT HAD NO PORT SIDE AT ALL** (MEASURED: NO `.bend` FILE NAMED
`symrules-cases` AND NO `.py` PRODUCED A `symf=` COLUMN), **AND ITS CPYTHON HALF REFUSED EVERY
CASE** (`KeyError: 'FLOORDIV'` ON THE FIRST CASE THAT SPELLED IT, AND **24 OF THE 232 CASES
SPELL `floordiv` OR `floormod`**).

**SO THE CENSUS's 134 GREEN ROWS WERE GREEN ON CITATION AND OP SET ALONE.** AND THE PROOF IS
THAT A TABLE ENTRY WITH A CITATION AND **NO BODY AT ALL** MAKES THE `divandmod.py:103` ROW
GREEN -- MEASURED BY ADDING ONE AND READING `PORT: 135 entries, 135 mapped and CHECKED, 0 BROKEN`.

### 45a. THE RESULT: 232 CASES, 219 AGREE, 13 DIVERGE

**THIS IS THE FIRST BODY-LEVEL VERIFICATION OF THE PORT's `sym` TABLE EVER RUN**, AND THE THIRTEEN
FALL INTO THREE CLASSES.

    A  THE `ne`/`eq` PRIMITIVE SWAP (5): r189 r84 x451a x451b x451c
       THE PORT LEAVES A `CMPNE` WHERE UPSTREAM's `sym` REWRITES IT TO
       `CMPEQ(CMPEQ(...), False)`. **THE PORT's AND UPSTREAM's `CMPNE` ARE THE SAME NODE**
       -- MEASURED: UPSTREAM's `(cmpne x c0)` IS `Ops.CMPNE` -- SO THIS IS THE PORT's REWRITE
       NOT FIRING, WHICH IS THE CLASS THE CENSUS's `mint_not` ROW ALREADY RECORDS.

    B  THE PORT REWRITES WHERE UPSTREAM DECLINES (3): r243 r256 r174

    C  UPSTREAM REWRITES WHERE THE PORT DECLINES (5): r82 r295 r296 r453 p193a

### 45b. FIVE RENDERING FACTS, EACH A FINDING ABOUT THE PORT's OWN RENDERER

1. **A REDUCE's HEAD IS `reduce:<rop>` AND NOT `reduce`** -- THE ROP IS IN THE ARG (`AReduce`).
2. **A NODE WITH NO SRCS IS `(noop )` AND NOT `(noop)`** -- UPSTREAM's `sh` ALWAYS EMITS THE
   SPACE AFTER THE HEAD.
3. **A LEAF IS A CONST OR A PARAM AND THE HEAD ALONE DOES NOT SAY WHICH** -- A SRC-LESS `NOOP` IS
   NOT A LEAF AND A `c1` IS -- SO THE DRIVER PRINTS AN `L` MARKER. **THE FIRST ATTEMPT GUESSED
   THE LEAVES BY NAME AND 104 OF THE 232 CASES DIVERGED. A GUESSED CLASS IS NOT A CLASS.**
4. **THE CENSUS LANE's `idx` GIVES THE POSITION ONE BEHIND ON A WALK LIST** -- ITS OWN OUTPUT
   READS `1:XOR:1,2;2:x:;3:c5:;` WHERE THAT NODE's SRCS ARE AT POSITIONS 2 AND 3 -- **AND IT IS
   INVISIBLE THERE BECAUSE THE CENSUS LANE COMPARES TWO LISTINGS WITH THE SAME `idx` AND THE TWO
   ERRORS CANCEL.** SO THE DRIVER PRINTS THE **ARENA INDICES** AND THE ORACLE READS THOSE.
5. **THE HEAD/SRCS BOUNDARY IS THE LAST `:` AND NOT THE FIRST**, BECAUSE A HEAD MAY CARRY A
   DTYPE SUFFIX (`cast:i32`).

### 45c. THE BEND SPELLINGS THIS LANE LEARNED, AGAIN

- **A BORROWED LIST'S TAIL AND A PATTERN'S TAIL ARE NOT THE SAME LIST.** THE POSITION LOOKUP
  ANSWERED THE SAME FIRST ELEMENT EVERY TIME UNDER A PATTERN AND `List.get`/`List.tail` ARE THE
  PORT's OWN READERS FOR IT.
- **A `+` PARAMETER IS CONSUMED.** A LOOKUP THAT TAKES A LINEAR LIST DESTROYS IT FOR THE NEXT
  LOOKUP, AND THE PORT's OWN `ss.go` HAS THAT SHAPE.
- **A `Maybe` IS A TYPE AND NOT A Data**, SO IT CROSSES A BOUNDARY AS A PLAIN BINDING.
- **A `match` MAY NOT SCRUTINISE A COMPUTED VALUE**, AND A LIST READ TWICE IS A `+` BINDING.

## 46. THE CENSUS READS A CITATION AND NEVER THE BODY, AND THAT IS A FALSE-`PORTED` CLASS

**THE INSTRUMENT.** `gates/symbody-gate.py` (NEW). IT ASKS, FOR EVERY PORT TABLE ENTRY, **WHICH
BODY THE DISPATCH SENDS FOR THAT TAG** AND WHETHER THAT BODY IS THE RULE THE ENTRY CITES.

**THE FINDING: 19 OF 130 ENTRIES DISPATCH A BODY THAT IS NOT THE CITED RULE, AND SIX OF THEM
DISPATCH A RULE UPSTREAM NO LONGER HAS.**

### 46a. WHY THE CENSUS CANNOT SEE IT

`gates/symrules-census.py`'s `verify()` MATCHES A TABLE ENTRY TO AN UPSTREAM ROW BY **THE
CITATION AND THE OP SET**. IT NEVER LOOKS AT THE DISPATCH. **AND THE TABLE ENTRIES WERE
RE-POINTED BY SIGNATURE** (THE OP SET) IN `7e4054e7c` -- WHICH IS THE RIGHT RE-POINT AND WHICH
IS ALSO WHY THE BODY CAN DISAGREE WITH IT.

THE PROOF IS ONE LINE: **A TABLE ENTRY WITH A CITATION AND NO BODY AT ALL MAKES THE
`divandmod.py:103` ROW GREEN** (MEASURED: `PORT: 135 entries, 135 mapped and CHECKED, 0
BROKEN`).

### 46b. THE SIX, AND THE BEHAVIOURAL TEST SPLITS THEM IN TWO

THE TEXT TEST FINDS SIX AND THE **BEHAVIOURAL** TEST -- CPYTHON's OWN `sym.rewrite` ON THE
NAMED GRAPH -- SPLITS THEM, AND THE BEHAVIOURAL TEST IS THE ONE THAT COUNTS. **A RULE UPSTREAM
REWROTE HAS A DIFFERENT PATTERN AND A DIFFERENT ANSWER; A RULE UPSTREAM DELETED HAS NO ANSWER.**

    tag  body     the rule                        upstream's answer          the verdict
    19   sym_125  (x // -1)                       (mul x -1)                 REWRITTEN -- NOT EXTRA
    53   sym_174  ((x*x2) / x2)                   NONE                       **EXTRA**
    101  sym_295  ((x+c1) + y)                    (add y (add x 1))          REWRITTEN -- NOT EXTRA
    104  sym_300  (x*-1 < y*-1)                   (cmplt y x)                REWRITTEN -- NOT EXTRA
    106  sym_302  ((x<1).ne(True))                 NONE                       **EXTRA**
    119  sym_453  (store(index) load(index))       (after (noop) (index ...))  **EXTRA**

**AND THE THREE EXTRA ONES ARE DIVERGENCES THE BODY-VERIFICATION INSTRUMENT SAW**:
`sym_174` IS `r174` (`sym_174.pat=TRUE` MEASURED) AND `sym_453` IS `r453`
(`sym_453.pat=TRUE` MEASURED).

### 46c. WHY A TEXT COMPARISON CANNOT SETTLE IT -- MEASURED THREE TIMES

- COMPARING THE **WHOLE RULE LINE** OVER-REPORTS DELETIONS, BECAUSE UPSTREAM REWORDED THE
  BODIES OF RULES IT KEPT: `sym_280`'s RULE IS AT `:295` IN THE NEW PIN AND ITS LAMBDA CHANGED
  FROM `y` TO `None`.
- COMPARING THE **PATTERN ALONE** ALSO OVER-REPORTS, BECAUSE UPSTREAM REMOVED A PATTERN's NAME:
  `sym_453`'s PATTERN WAS `(UPat.store(UPat(Ops.INDEX, name="index"), UPat.load(...)), name="x")`
  AND AT `:467` IT IS THE SAME WITHOUT THE `name="x"`.
- COMPARING THE **OP SET** UNDER-REPORTS, BECAUSE THE OP SET DOES NOT TELL TWO RULES APART.

**SO THE INSTRUMENT IS BEHAVIOURAL, AND THE BODY-VERIFICATION INSTRUMENT IS IT.**

### 46d. AND THE THIRTEEN DIVERGENCES ARE THREE CLASSES

- **FIVE ARE THE `ne`/`eq` PRIMITIVE SWAP** (`r189` `r84` `r243` `r256` AND THE `x451*` FAMILY
  IS SEPARATE). THE DECISIVE MEASUREMENT: UPSTREAM's RULE AT `:250` IS `x | x.logical_not()` AND
  `logical_not` IS `CMPEQ(x, False)`, SO THE CASE's `cmpne` NEVER MATCHES IT. MEASURED:
  UPSTREAM's `x | !x` -> `bt` AND `x | CMPNE(x, True)` -> NO REWRITE.
- **TWO ARE THE PORT LACKING UPSTREAM's TWO-STAGE ALU FOLDING** (`:171`-`:173`, SIX ROWS:
  `r295` `r296`). UPSTREAM GETS `(add y (add x c1))` TO `(add (add x y) 1)` IN TWO STEPS AND THE
  PORT HAS ONLY THE SECOND.
- **TWO ARE THE PORT CARRYING A DELETED RULE** (`r174` `r453`).
- **FIVE ARE THE POW HANDLING AND THE `:89` STACK BROADCAST** (`r82` `p193a` `x451a` `x451b`
  `x451c`).

## 47. TWO REAL DEFECTS FOUND AND FIXED, AND THE INSTRUMENT READS 221 AND 11

THE BODY-VERIFICATION INSTRUMENT DID NOT JUST FIND DIVERGENCES -- IT FOUND TWO **WRONG
KERNELS**, AND BOTH ARE FIXED.

### 47a. `sym_453` BUILT THE OLD ANSWER

UPSTREAM AT THE OLD PIN (`5c2bf39d6`) HAD `lambda index, x: UOp(Ops.NOOP).after(*x.src)` --
**IT SPREAD ALL OF THE STORE's SRCS**, SO THE ANSWER WAS `AFTER(NOOP, INDEX, LOAD)`. AT THE
CURRENT PIN IT IS `lambda index: UOp(Ops.NOOP).after(index)` -- **ONE** SRC.

MEASURED: THE PORT ANSWERED `AFTER(NOOP, INDEX, LOAD)` AND UPSTREAM ANSWERED
`(after (noop ) (index b c0))` ON THE CASE `r453`, **AND THE PORT's ANSWER CARRIED A LOAD THAT
UPSTREAM's DID NOT -- A WRONG KERNEL SHAPE AND NOT A COSMETIC DIFFERENCE.**

THE FIX IS ONE LIST: THE INDEX AND NOT THE STORE's SRCS.

### 47b. `sym_174` WAS UNSOUND FOR ZERO, AND FOUR RULES WERE UNGUARDED FOR FLOATS

**UPSTREAM DELETED FIVE RULES IN ONE COMMIT** -- `1b892575c` "remove unsafe float div rules"
(PR #19039) -- **AND THE FLOAT TEST IT ADDED NAMES THEM EXACTLY**: `(x*y)/y`, `(x/y)/z`,
`1/(z*z)` AND `1/(z*z*z)` WITH `z = 1.7` AND `z*z` **OVERFLOWING TO `inf`**.

AND THE COMMENT UPSTREAM LEFT AT `:180` SAYS WHY THE OTHER ONE WENT: **"can be wrong if x or x2
is 0"**. `(x * 0) / 0` IS `0 / 0` AND NOT `x`.

MEASURED BEFORE THE FIX: `sym_174.pat(zero case)=TRUE` ON `(mul (mul x c0) (reciprocal c0))` AND
UPSTREAM DECLINES THE SAME GRAPH (`NONE`). **SO THE PORT WAS PRODUCING A WRONG KERNEL.**

THE FIX IS THE GUARD THAT MAKES EACH RULE TRUE IN THE ARITHMETIC IT IS TRUE IN: A **ZERO GUARD**
ON `sym_174` (THE DIVISOR) AND A **WEAKINT GUARD** ON ALL FOUR (`sym_174`, `sym_462`, AND
`p_recip2` WHICH COVERS `sym_463` AND `sym_464`). **AND THE PORT KEEPS THE OPTIMISATION FOR THE
INTEGERS**, WHERE IT IS AN IDENTITY, SO THE PORT's RULES ARE THE GUARDED FORMS OF UPSTREAM's
DELETED ONES AND NOT DIVERGENCES.

THE FIFTH DELETED RULE, `(x/x2)/x3 -> x/(x2*x3)`, WAS NEVER PORTED -- MEASURED: NO PORT RULE
MATCHES THAT SHAPE -- SO IT IS NOT HERE.

### 47c. THE ELEVEN THAT ARE LEFT ARE FOUR CLASSES

    4  THE `ne`/`eq` PRIMITIVE SWAP          r189 r84 r243 r256
    2  THE MISSING TWO-STAGE ALU FOLDING     r295 r296
    1  THE MISSING `:89` STACK BROADCAST     r82
    4  THE POW HANDLING                      p193a x451a x451b x451c

**AND THE INSTRUMENT READS `221 AGREE AND 11 DIVERGE`** -- IT READ 219 AND 13 BEFORE THIS
SESSION's TWO FIXES.

## 48. THE `ne`/`eq` SWAP WAS ONE CLASS AND IT WAS **TWO LANES**, AND THE INSTRUMENT READS 231 AND 1

§47c LISTED THE ELEVEN DIVERGENCES AS FOUR CLASSES. **THE FIRST CLASS WAS FOUR CASES AND IT WAS
ONE DEFECT, AND THE DEFECT WAS IN TWO LANES, AND NEITHER LANE'S OWN COMMENT SAID SO.**

### 48a. WHAT UPSTREAM'S `ne` AND `eq` ARE AT THE PIN

`tinygrad/mixin/elementwise.py` AT `f5ac54685074`:

    def logical_not(self): return self.cast(dtypes.bool).eq(False)   # :57
    def ne(self, x):        return self.eq(x).logical_not()           # :332
    def eq(self, x):        return self._binop(Ops.CMPEQ, x, False)   # :335

SO AT THE PIN:

| CALL | SHAPE | NODES |
|---|---|---|
| `eq(v)` | `CMPEQ(x, v)` | **ONE** |
| `logical_not()` | `CMPEQ(x, False)` | **ONE** |
| `ne(v)` | `CMPEQ(CMPEQ(x, v), False)` | **TWO** |

**AND THE PRE-PIN SPELLING WAS THE PRIMITIVE `Ops.CMPNE` FOR ALL THREE.**

**AND UPSTREAM's `tinygrad/uop/symbolic.py` AT THE PIN MENTIONS `Ops.CMPNE` **ZERO TIMES**
(`grep -c CMPNE` READS **0**), SO **UPSTREAM HAS NO RULE THAT CAN MATCH A `CMPNE` NODE AT
ALL.** MEASURED ON CPYTHON: `sym.sym.rewrite` OF `(cmpne xb bt)` RETURNS **`None`**.

**SO A `CMPNE` NODE IS NOT AN UPSTREAM-REACHABLE INPUT, AND A RULE THAT MATCHES ONE FIRES
WHERE UPSTREAM CANNOT.** THAT IS THE CLASS.

### 48b. WHERE THE PORT HAD IT, AND WHY NOBODY SAW IT

`tinybendygrad/uop/symbolic.bend`'s OWN `sym_134` COMMENT ALREADY RECORDED THE SWAP FOR
`logical_not` -- **"THE PRIMITIVE SWAPPED AT THE 2026-11-03 RE-VENDOR, AND THIS RULE IS THE
SMALLEST PLACE IT SHOWS"** -- **AND THE SWAP SHOWED IN **FIVE** PLACES, AND THREE OF THEM WERE
NOT RULES AT ALL:**

  * `sym_189` -- `x != 0`. THE PORT BUILT `CMPNE(x, 0)`. **AND ITS CITATION, `symbolic.py:189`,
    NAMES A LINE THAT AT THE PIN HOLDS A **BITCAST** RULE; THE REAL RULE IS AT `:196`.**
  * `tinybendygrad/codegen/decomp/transcendental.bend`'s `tx_lnot` -- `CMPNE(x, True)`.
  * THE SAME FILE's **14** `CMPNE` SITES, WHICH ARE UPSTREAM's `ne` CALLS AND SO MUST BE
    `CMPEQ(CMPEQ(x, y), False)`.
  * `p_not_of` -- A **HELPER**, AND SO IT CARRIED **TWO** RULES (`sym_243` AND `sym_256`).
  * `sym_132` -- MATCHED `CMPNE(x, False)`, THE PRE-PIN `!=` SPELLING.

**AND `p_not_of` IS THE ONE THAT NOBODY LOOKED AT, BECAUSE A HELPER IS NOT A RULE.** THE
`symbody-gate` MEASURES **WHAT BODY EACH TABLE ENTRY DISPATCHES**, AND A HELPER IS NOT A TABLE
ENTRY -- **SO THE INSTRUMENT THAT WAS BUILT TO CATCH "THE CITATION AND THE BODY DISAGREE"
CANNOT SEE A HELPER THAT IS WRONG IN THE SAME WAY.**

### 48c. THE FIX WAS NOT ONE LINE BUT THREE SHAPES, AND THE COMPOSITION IS NOT IDEMPOTENT

**`tx_lnot` BECAME `CMPEQ(x, False)`, AND `tx_eq` AND `tx_ne` ARE NEW.** ALL 14 `CMPNE` SITES
BECAME `tx_ne`.

**AND `xpow.zero` IS `tx_eq` AND NOT `tx_ne` THEN `tx_lnot`** -- THE OLD COMMENT SAID
"`exponent.eq(0)` IS `ne(0).logical_not()` (elementwise.py:337)" **AND `elementwise.py:337` AT
THE PIN IS `def eq`, NOT `ne`.** SO THAT ONE BUILT **THREE** NODES WHERE UPSTREAM BUILDS
**ONE**, **AND THE COMPOSITION IS NOT IDEMPOTENT AND THE EXTRA LAYER IS VISIBLE**: THE PORT's
`xpow` ANSWER HAD `cmpeq (cmpeq (cmpeq yf bad) bf) bf` WHERE UPSTREAM HAS `cmpeq yf bad`.

**AND THE SAME HOLDING IS TRUE OF `xpow_int`'s `xi.eq2`,** WHICH USED TO BUILD
`CMPNE(CMPNE(x, v), True)` -- **TWO** NODES -- WHERE UPSTREAM's `eq` IS **ONE**.

### 48d. THE MEASUREMENT

    231 AGREE  1 DIVERGE

**AND THE INSTRUMENT READ `224 AGREE AND 8 DIVERGE` BEFORE THIS WORK.** THE EIGHT WERE `r84`,
`r189`, `r243`, `r256`, `x451a`, `x451b`, `x451c` AND `r82`; **SEVEN OF THE EIGHT WERE THIS
ONE CLASS**, AND THE EIGHTH, `r82`, IS NOT.

**AND `r243` AND `r256` DIVERGED IN THE DIRECTION "THE PORT REWRITES AND UPSTREAM DECLINES",
WHICH IS THE SIGNATURE OF A RULE THAT MATCHES A NODE UPSTREAM CANNOT BUILD.**

### 48e. THE ONE THAT IS LEFT IS NOT THIS LANE

`r82` IS THE MISSING `:89` STACK BROADCAST. **UPSTREAM'S `:89` IS THE BROADCAST RULE** AND THE
PORT's `sym_89` IMPLEMENTS THE **OLD** `:89` (THE BINARY COMPARISON, NOW AT `:96`). THE
BROADCAST NEEDS `UOp.expand` -- `_mop`/`permute`/`reshape` -- **AND `tinybendygrad/uop/
movement.bend` HAS **164** DEFS AND NONE OF THEM.** **SO IT IS A MOVEMENT-LAYER RULE AND NOT A
SYMBOLIC ONE, AND IT IS THE ONE ROW THIS LANE CANNOT CLOSE.**

### 48f. AND A FINDING THAT IS NOT A DIVERGENCE: FOUR RULES ARE DEFINED AND NEVER CALLED

MEASURED BY A DISPATCH-SCAN OF THE WHOLE FILE (EVERY `case N: sym_M(x, u)` ARM IN EVERY
DISPATCH FUNCTION, MINUS EVERY `def sym_NNN(`):

    sym_132  sym_462  sym_463  sym_464

**AND `sym_149`, `sym_167`, `sym_253` AND `sym_471` ARE CALLED FROM *OTHER RULES'* BODIES**, SO
THE FOUR ABOVE ARE THE ONES WITH NO CALLER AT ALL. **AND ALL FOUR WERE ALREADY UNDISPATCHED
BEFORE THIS SESSION's COMMITS** (MEASURED AGAINST `4e0aac9f1^`), **SO THIS IS PRE-EXISTING
AND NOT SOMETHING THESE COMMITS BROKE.**

**AND `sym_462`/`sym_463`/`sym_464` ARE THE THREE GUARDED RECIPROCAL RULES THAT §47b FIXED** --
**SO THE FIX LANDED IN RULES THAT NOTHING CALLS, AND THE FIX IS INVISIBLE IN THE INSTRUMENT.**
**A RULE THAT CANNOT BE REACHED IS A ROW THAT CANNOT GO RED.**

### 48g. AND THE INSTRUMENT'S ROW CAN GO RED, WHICH WAS MEASURED AND NOT ASSUMED

**A ROW THAT CANNOT GO RED IS WORSE THAN NO ROW**, SO THE FIX WAS PLANTED BACK.

THE PLANT: `tinybendygrad/codegen/decomp/transcendental.bend`'s `tx_lnot` WAS PUT BACK TO
`CMPNE(x, True)` -- **THE PRE-PIN SPELLING** -- AND THE INSTRUMENT WAS RUN.

    PLANTED    230 AGREE  2 DIVERGE    (`x451b` RETURNS)
    PLANT OUT  231 AGREE  1 DIVERGE    (`x451b` GONE)

**AND THE FILE IS BYTE-IDENTICAL TO `HEAD` AFTER THE PLANT WAS REMOVED** (`git diff --stat`
READS EMPTY), **SO THE PLANT WAS A TEXT EDIT AND NOT A ROLLBACK.**

**AND THE PLANT IS THE EXACT DEFECT THE FIX REMOVED, SO THE ROW IS A WITNESS FOR THE FIX AND
NOT FOR SOMETHING ELSE.**

## 49. THE LAST DIVERGENCE WAS NOT A MISSING RULE, AND THE INSTRUMENT IS GREEN ON ALL 232

§48g LEFT `r82` AS THE ONE DIVERGENCE AND §48e CALLED IT "A MOVEMENT-LAYER RULE AND THIS
LANE CANNOT CLOSE IT". **THAT WAS WRONG, AND IT WAS WRONG BECAUSE IT WAS AN INFERENCE AND NOT
A MEASUREMENT.** THE PORT HAS `OpsEXPAND` (OP **71**), `tinybendygrad/schedule/prepare.bend`
HAS `pr_expand` WHICH BUILDS EXACTLY THAT NODE, **AND `r82` WAS NEVER ABOUT A MOVEMENT RULE
AT ALL.**

### 49a. WHAT THE RULE IS

UPSTREAM AT THE PIN (`f5ac54685074`), `tinygrad/uop/symbolic.py:89`:

    (invalid_pat.broadcast(name="s"), lambda i,s: i.expand(s.shape)),

**AND THE PORT's `sym_82` WAS THERE AND ANSWERED `sy_src0(x, u)` -- THE INVALID CONST
ITSELF.** MEASURED ON CPYTHON AT THE PIN:

    (stack bad)      ->  (expand Invalid 1)
    (stack bad bad)  ->  (expand Invalid 2)

**AND THE EXPAND's SECOND SRC IS A PLAIN `CONST(N)` WHOSE DTYPE IS `weakint`** -- MEASURED, THE
NODE IS `EXPAND(CONST(Invalid), CONST(2))`. **SO THE PORT PRODUCED A DIFFERENT SHAPE FOR EVERY
BROADCASTED INVALID: A WRONG KERNEL AND NOT A COSMETIC DIFFERENCE.**

### 49b. WHY NOBODY SAW IT

**THE PORT's OWN COMMENT AT `sym_82` ALREADY SAID THE PATTERN WAS RIGHT** -- "MEASURED
2026-11-03: `(stack bad x)` ANSWERED `bad` WHERE CPYTHON ANSWERS `norewrite`" -- **AND THAT
FIX WAS ABOUT THE *PATTERN* (TESTING `src[0]` INSTEAD OF ALL SRCS) AND NOT ABOUT THE *ANSWER*,
SO THE ANSWER WAS NEVER LOOKED AT.**

**AND THE ANSWER IS NOT A ONE-LINE FIX, BECAUSE IT MINTS.** THE PORT HAS TWO DISPATCH FAMILIES:
`sym_dispatch.go` ANSWERS A `U32` INDEX AND `sym_mint_f` ANSWERS AN `O.Found`, AND
`sym_dispatch_f` PICKS THE LATTER FOR THE TAGS IN `MINT_TAGS()`. **A RULE THAT MINTS CANNOT
ANSWER WITH AN INDEX** -- THE CLOSURE GATE NAMES THAT `wall.sym_rewrite_index_only`. SO TAG 0
MOVED FROM THE INDEX FAMILY TO THE MINT FAMILY, AND `MINT_TAGS()` AND `sym_mint_f` BOTH GREW
IT. **THE CLOSURE GATE CHECKS THAT THEY AGREE AND IT READS `mint=100 MINT_TAGS=100`.**

### 49c. AND ONE SPELLING WAS WRONG TWICE OVER

THE SHAPE CONST IS **A PLAIN INT CONST AND NOT `STACK(CONST(N))`**. THE PORT's `STACK(CONST(N))`
IS `prepare.bend`'s `pr_shp1` SPELLING FOR A *SHAPE* ARG, **AND IT ANSWERED
`(expand bad (stack c2))` WHERE UPSTREAM ANSWERS `(expand bad c2)`.** **THE SHAPE OF A STACK IS
`(N,)` BUT THE NODE UPSTREAM BUILDS CARRIES `N` ITSELF.** THAT WAS MEASURED, NOT GUESSED: THE
FIRST ATTEMPT ANSWERED THE TUPLE AND THE INSTRUMENT SAID `port=(expand bad (stack c2))
upstream=(expand bad c2)`.

### 49d. THE MEASUREMENT

    232 AGREE  0 DIVERGE

**AND THE PLANT FIRES**: `sym_82.put` WAS PUT BACK TO THE OLD ANSWER AND THE INSTRUMENT READ
`231 AGREE AND 1 DIVERGE` WITH `r82` NAMED. **SO THE ROW CAN GO RED.**

**AND `symbody-gate` READS `20 of 130` WITH AND WITHOUT THIS CHANGE** -- MEASURED BY PUTTING
`HEAD`'s BYTES IN THE FILE AND RUNNING IT -- **SO THIS CHANGE ADDED NO MISMATCH.** (AND THE
`19` THAT §46 AND §47 RECORDED IS A STALE READING; THE CURRENT READING IS `20`.)

### 49e. AND THE CLASS

**A RULE CAN BE IN THE RIGHT PLACE, MATCH THE RIGHT PATTERN, AND STILL ANSWER THE WRONG
THING.** THE CENSUS AND THE OP-SET TEST CANNOT SEE AN ANSWER, AND THE BODY-VERIFICATION
INSTRUMENT CAN -- **AND IT FOUND THREE WRONG ANSWERS IN THIS LANE** (`sym_453`'s EXTRA LOAD,
`sym_174`'s ZERO, AND NOW `sym_82`'s MISSING `EXPAND`), **AND ALL THREE WERE RULES THAT WERE
THERE AND PRESENT.**

## 50. THE INSTRUMENT IS GREEN ON ALL 232 CASES, AND TWO OF THE PORT's OWN CLAIMS WERE WRONG

### 50a. WHERE THE LANE STANDS

    THE BODY-VERIFICATION INSTRUMENT   232 AGREE  0 DIVERGE
    THE CENSUS                         134 entries, 134 mapped and CHECKED, 0 BROKEN
    symrules-gate                      rc=0
    symclosure-gate                    rc=0
    symrules-census                    rc=0
    THE WHOLE PORT                     193 compiled, 7 cold-by-design, 1 pre-existing finding

**AND THE INSTRUMENT READ `219 AGREE AND 13 DIVERGE` WHEN IT FIRST RAN.** **THIRTEEN
DIVERGENCES WERE FOUND AND FIXED, AND THEY WERE FIVE CLASSES:**

| CLASS | CASES | WHAT IT WAS |
|---|---|---|
| THE `ne`/`eq` PRIMITIVE SWAP | `r84` `r189` `r243` `r256` `x451a` `x451b` `x451c` | **ONE DEFECT IN TWO LANES** (§48) |
| THE MISSING TWO-STAGE ALU FOLDING | `r295` `r296` | THE `sym_295` SHAPE (§47) |
| THE OLD PIN's `c.val == 1` ARM | `p193a` | THE PORT's `sym_193` (§47) |
| THE OLD ANSWER | `r453` | `sym_453` SPREAD ALL OF THE STORE's SRCS (§47) |
| THE MISSING `EXPAND` | `r82` | `sym_82` ANSWERED THE INVALID ITSELF (§49) |

**AND FIVE OF THE THIRTEEN WERE WRONG KERNELS AND NOT COSMETIC DIFFERENCES** -- `sym_174`'s
ZERO, `sym_453`'s EXTRA LOAD, `sym_193`'s CONST ANSWER, `sym_82`'s MISSING `EXPAND`, AND THE
`ne`/`eq` SWAP'S FIVE.

### 50b. AND TWO OF THE PORT's OWN CLAIMS WERE WRONG, AND BOTH ARE NOW CORRECTED

**(1) THE HEADER SAID "FOUR are here and all FOUR are LOAD-BEARING" AND TWO OF THEM ARE NOT.**
`sym_462` AND `sym_463` HAVE **NO TABLE ENTRY** AND **NO CALLER**. **AND THAT IS CORRECT,
BECAUSE UPSTREAM DELETED THE RULE** -- UPSTREAM's `symbolic.py` AT THE PIN MENTIONS `RECIP`
**ZERO TIMES**. **SO THE LIMIT MUST BE STATED: THE WEAKINT GUARD ON THE THREE RECIPROCAL RULES
IS SOUND AND IT IS ALSO UNOBSERVABLE, BECAUSE NOTHING CALLS THEM.** **A RULE THAT CANNOT BE
REACHED IS A ROW THAT CANNOT GO RED.**

**(2) §48e OF THIS REPORT SAID `r82` WAS "A MOVEMENT-LAYER RULE AND THIS LANE CANNOT CLOSE
IT", AND THAT WAS AN INFERENCE AND NOT A MEASUREMENT.** THE PORT HAS `OpsEXPAND` (OP **71**)
AND `prepare.bend` HAS `pr_expand` WHICH BUILDS EXACTLY THAT NODE. **A CLAIM THAT NAMES A
FILE AND ITS ABSENCE MUST BE MEASURED AGAINST THE FILE.**

### 50c. THE CLASS, WHICH IS THE POINT OF THE WHOLE EXERCISE

**THE CENSUS AND THE OP-SET TEST CANNOT SEE AN ANSWER.** THE BODY-VERIFICATION INSTRUMENT CAN,
**AND IT FOUND THREE WRONG ANSWERS IN THIS LANE -- `sym_453`'s EXTRA LOAD, `sym_174`'s ZERO,
AND `sym_82`'s MISSING `EXPAND` -- AND ALL THREE WERE RULES THAT WERE THERE AND PRESENT, WITH A
CITATION AND AN OP SET THAT BOTH LOOKED RIGHT.**

**AND THE SECOND CLASS IS THE ONE THE INSTRUMENT ITSELF WAS BLIND TO, TWICE:**
  * **THE LEAF MARKER WAS `L` AND THE PORT's OP NAMES ARE UPPERCASE, SO `LOG2` READ AS A LEAF**
    AND THE THREE `x451*` DIVERGENCES WERE **A BUG IN THE INSTRUMENT AND NOT IN THE PORT.**
    **A MARKER THAT CAN BE CONFUSED WITH A PAYLOAD IS NOT A MARKER.**
  * **THE DELETED-RULES INSTRUMENT's KEY WAS THE OP SET, WHICH IS DEGENERATE FOR EVERY
    PATTERN THAT NAMES NO OP -- **63 OF 117** PORT RULES -- AND IT READ "0 of 117" FOR THAT
    REASON.** **AN INSTRUMENT THAT SAYS "NOTHING" CAN BE SAYING "I CANNOT SEE".**

## 51. THE LAST MISSING CENSUS ROW IS NOT A DEAD ENTRY, AND IT WAS FOUND BEHAVIOURALLY

### 51a. THE SWEEP, AND WHY IT NEEDED NO SECOND DRIVER

§50 LEFT ONE CENSUS ROW MISSING: `divandmod.py:103` (`fold_divmod_general`). **AND §50 ALSO
LEFT `deadrules.py`'s LIST OF 23 UNSETTLED** -- THE INSTRUMENT SAID "0 of 117" FOR A DEGENERATE
KEY AND THEN READ "23 of 117" WITH A NEW KEY AND SAID OUT LOUD THAT IT OVER-REPORTS.

**THE SETTLER IS BEHAVIOURAL: FOR EACH CANDIDATE, DOES THE PORT REWRITE IT AND DOES UPSTREAM?**

**AND IT NEEDED NO SECOND DRIVER.** `gates/symrules-driver.bend` IS **2,397 LINES** AND IS THE
TRUTH ABOUT HOW THE PORT REWRITES, **AND ITS CASES PATH IS NOW OVERRIDABLE BY `IO.args()`.**
MEASURED 2026-11-08: `IO.args()` WORKS WITH `bin/bend` AND **INDEX 0 IS THE PROGRAM, SO THE
PATH IS INDEX 1** -- `tinybendygrad/runtime/ops_bend.bend` READS ITS LANE FROM INDEX **1** FOR
THE SAME REASON, **SO IT IS THE TREE's CONVENTION AND NOT A NEW ONE.**

### 51b. THE ONE DIVERGENCE IS THE MISSING ROW, AND IT IS NOT DEAD

    THE SWEEP   24 CASES  23 AGREE  1 DIVERGE
    THE DIVERGE IS dr174 -- `(x*y)/y`

**AND UPSTREAM's ANSWER FOR `(x*y)/y` IS `(div (mul c1 x) c1)`, AND THE RULE THAT PRODUCES IT
IS `tinygrad/uop/divandmod.py:103`'s `fold_divmod_general`** -- MEASURED BY ASKING THE MATCHER
WHICH PATTERN FIRED:

    PATTERN 117 IS UPat({DIV, MOD}, dtype=weakint, name="d") WITH src=None
    AND ITS FUNCTION IS tinygrad.uop.divandmod.fold_divmod_general

**SO THE PORT DECLINES A REWRITE UPSTREAM PERFORMS, ON A GRAPH AS ORDINARY AS `(x*y)/y`.** **THE
ROW IS NOT A DEAD ENTRY AND THE TODO's FRAMING OF IT AS A BLOCKED ROW UNDERSTATED IT.**

### 51c. AND THE 23 CANDIDATES ARE SETTLED

| WHAT UPSTREAM DOES | THE CANDIDATES | WHAT IT IS |
|---|---|---|
| **REWRITES IT** | `dr125` `dr246` `dr247` `dr253` `dr290` `dr296` `dr300` `dr471` `dr473` `dr97` `dr97b` `dr97c` `dr101` | **KEPT UPSTREAM RULES THAT WERE REWORDED -- AND THE PORT MATCHES THEM** |
| **DECLINES IT** | `dr132` `dr191` `dr274` `dr287` `dr295` `dr302` `dr462` `dr463` `dr464` | **DELETED UPSTREAM RULES THAT THE PORT ALSO DECLINES** |
| **DECLINES IT** | `dr174` | **THE `divandmod.py:103` ROW** |
| **DECLINES IT** | `dr279` | **THE ONE WHERE BOTH DECLINE** |

**AND `dr295` AND `dr302` ARE THE TWO `deadrules.py` NAMED AS ITS OWN EXAMPLES OF OVER-
REPORTING, AND THE SWEEP SETTLES THEM: UPSTREAM REWRITES BOTH AND THE PORT MATCHES.**

### 51d. AND THE `divandmod` LANE'S ORACLE WAS SWEPT, AND THE BLOB WAS STILL THERE

**`tinybendygrad/uop/divandmod.bend`'s HEADER NAMES `.agents/slop/dm-oracle.py` BY NAME, AND
THE FILE WAS ABSENT.** MEASURED 2026-11-08:

  * `git log --all -- .agents/slop/dm-oracle.py` NAMES FOUR COMMITS **AND THE LAST ONE IS
    `371cc64c9` "sweep: **THE SWEEP DELETED 3,603 FILES AND TOOK 166 REPRODUCTION PA**".**
  * **AND EVERY COMMIT'S TREE HAD THE PATH BUT NOT THE BLOB** -- `git cat-file -s` READS
    **ABSENT** FOR ALL FOUR.
  * **AND `git rev-list --all --objects` STILL NAMED THREE `dm-oracle.py` BLOBS** -- THE LARGEST,
    `6065cd94bc2360eed4f9a56343e3458a144017e2` (3346 B), **IS RESTORED AND RE-POINTED AT THE
    PIN.**

**SO A SWEPT FILE IS NOT A LOST FILE WHEN THE BLOB IS STILL IN THE OBJECT STORE, AND "IT WAS
DELETED" IS NOT A REASON TO REBUILD IT.**

**AND THE RESTORED FILE REFUSED TO RUN, AND EVERY REASON WAS THE RE-VENDOR DRIFT:**
`Ops.FLOORDIV`/`Ops.FLOORMOD` ARE NOW `Ops.DIV`/`Ops.MOD` (**THE SAME DRIFT THAT MADE
`gates/decomp_graph_census-oracle.py` REFUSE WITH `KeyError: 'FLOORDIV'`**), AND
`UOp.variable(..., multiple_of=N)` IS GONE **AND `multiple_of` IS NOT A FIELD OF `ParamArg` AT
ALL** (MEASURED, UPSTREAM's `ops.py` AT THE PIN MENTIONS IT **ZERO TIMES**). **SO THE FOUR
`multiple_of` CASES ARE DROPPED RATHER THAN REWRITTEN INTO SOMETHING ELSE, BECAUSE A CASE THAT
MEANS SOMETHING ELSE IS NOT A CASE.**

### 51e. AND THE LANE'S ANSWERS NOW HAVE A CPYTHON SIDE AND A DIFF

**`.agents/slop/dm-compare.py` READS `19 AGREE AND 0 DIVERGE`** FOR THE LANE's 19 COMPARABLE
ROOTS. **AND THE COMPARISON IS BY VALUE WHERE THE ANSWER IS A CONSTANT AND BY A TWO-LEVEL
TRUNCATED SHAPE OTHERWISE** -- BECAUSE THE LANE's OWN HEADER STATES FOUR DIVERGENCES (NO
PROMOTION CASTs, NO SUB CANONICALISATION, NO CONSTANT FOLDING, A NON-INT CONST IS NOT A
`vmin`) **THAT MAKE THE FULL SHAPES DIFFER ON PURPOSE**, **AND THE PORT's OWN HEADER SAYS
"`out_r14`/`out_r16` ARE CHECKED BY VALUE".**

**AND THE PLANT PROVES THE ROW CAN GO RED**: `dm_1`'s `cm`/`cq` SWAPPED READS **5 DIVERGE**,
**AND THE FILE IS BYTE-IDENTICAL TO `HEAD` AFTER THE PLANT WAS REMOVED.**

### 51f. AND THE CLASS

**AN ORACLE CAN BE DELETED AND ITS CASES STILL LIVE IN THE HEADER THAT NAMES IT.** THE
`divandmod` LANE's HEADER NAMED A FILE THAT WAS GONE, **AND NOBODY NOTICED FOR THE TIME IT
WAS GONE, BECAUSE A HEADER IS NOT A DEPENDENCY AND NOTHING READS IT AS ONE.**

**AND THE BLOBS ARE STILL IN THE OBJECT STORE AFTER A SWEEP DELETED 3,603 FILES.** **THE SWEEP
REMOVED THE PATHS AND LEFT THE BLOBS, SO THE RECOVERY WAS A `git rev-list --objects` AND NOT A
REWRITE.**

## 52. THE COUNTER, AND **A COMPILING COUNTER AND A CORRECT ONE ARE THE SAME THING**

### 52a. THE CLAIM WAS ABOUT A CONTAINER AND NOT ABOUT A CAPABILITY

`divandmod.bend`'s TODO SAID "THE PORT HAS NO MULTISET AND NO `Map`" AND `.agents/TODO.md`
SAID THE SAME. **BOTH WERE TRUE ABOUT A CONTAINER AND FALSE ABOUT A CAPABILITY.**

MEASURED 2026-11-08:

  * `helpers.bend:502` SAYS "Bend's `Map` IS STRING-KEYED ONLY, SO THE SET IS A LINEAR SCAN",
    **AND THERE IS NO `HashMap` AND NO `HashSet` IN THE PORT.**
  * **BUT THE PORT HAS THE HONEST SPELLING ALREADY, TWICE**: `dedup_u32` (`helpers.bend:509`)
    AND `merge_dicts` (`helpers.bend:2467`) ARE BOTH "A LIST OF PAIRS WITH A LINEAR SCAN",
    **AND `merge_dicts`'s OWN NOTE SAYS EXACTLY THAT: "A LIST OF PAIRS IS THE HONEST
    REPRESENTATION".**
  * **AND UPSTREAM's COUNTER's KEYS ARE NODES**, BECAUSE A `UOp` IS HASHABLE BY IDENTITY
    (`ops.py:219-220`: `__hash__ = tuple.__hash__` AND `__eq__` IS `self is other`) -- **SO THE
    KEY IS THE ARENA's `U32` INDEX, WHICH IS THE NODE's IDENTITY IN THIS PORT.**

### 52b. THE FOUR BEND SPELLING RULES, MEASURED IN TWO PROBES EACH

  1. **A PLAIN PARAMETER MAY BE CONSUMED ONCE AND A `+`-BINDER MAY BE CONSUMED TWICE.**
     `def use2(x: U32) -> U32: U32.add(x, x)` REFUSES WITH "x (consumed more than once" AND
     `def use2(+x: U32) -> U32: U32.add(x, x)` COMPILES AND ANSWERS 6. **AND THE PORT's OWN
     `split_uop.pop` USES `+ar` AND `+sep` TWICE EACH, SO THIS IS THE TREE's CONVENTION.**
  2. **A DEF's HELPER MUST COME BEFORE ITS USER** -- "defs are checked in file order".
  3. **A `match` MAY NOT BE A CALL's ARGUMENT AND MAY NOT SCRUTINIZE A COMPUTED VALUE.**
  4. **ARGUMENTS ARE READ LEFT TO RIGHT AND EACH IS PASSED UNCHANGED UNTIL USED**, SO A LIST's
     TAIL MAY NOT BE PASSED TO TWO CALLS -- **AND THE PORT's OWN `Merge.go` IS THE PATTERN.**

### 52c. AND THE INTERSECTION'S TWO FOLDS DID NOT MAKE A CYCLE

**MEASURED, THE REORDERER REPORTED "A CYCLE" OVER **FIVE** SPELLINGS**: `go`->`step`->`pick`->`go`,
`go`->`step`->`go`, A FUEL-BOUNDED WORKLIST, A FLATTENED ONE, AND A PAIR WALK -- **AND BEND
REFUSES MUTUAL RECURSION.**

**THE SHAPE THAT IS NOT A CYCLE IS THE PORT's OWN: THE INNER FOLD IS A **CALL IN AN ARGUMENT**
AND NOT A HELPER OF THE OUTER ONE's RECURSION.**

### 52d. AND THREE SPELLINGS OF THE BUMP WERE WRONG, AND THE ROW CAUGHT ALL THREE

**AND THE FIRST COMPILING SPELLING READ `1=1 2=2 3=1 2=1` FOR `ctr_of([1,2,3,2])` -- A PROBE
THAT PRINTS THE COUNTER, NOT A TEST -- AND THE THREE WRONG SPELLINGS WERE:**

  * **THE BUMP KEPT THE OLD RECORD AND APPENDED THE NEW ONE** -- **SO THE COUNTER HAD **13
    RECORDS INSTEAD OF 3** -- **AND `ctr_find` READS THE **FIRST** MATCH, SO IT READ 1 FOR EVERY
    KEY.**
  * **THE BUMP STARTED AT `Nil{}` AND SO REBUILT THE COUNTER**, **SO THE RESULT WAS A COUNTER OF
    **ONE** KEY NO MATTER HOW MANY NODES WERE COUNTED.**
  * **THE `Nil{}` ARM APPENDED THE NEW KEY **AND** THE MATCHED ARM APPENDED THE BUMPED ONE**,
    **SO THE KEY APPEARED TWICE** -- AND THE FIX IS A **"FOUND" FLAG** CARRIED ALONG THE FOLD.

### 52e. AND THE THREE CLAIMS ARE CPYTHON-CONFIRMED

**`t_ctr_bump` AND `t_ctr_find` AND `t_ctr_inter` ALL READ **True** AGAINST CPYTHON's OWN
`collections.Counter`, AND CPYTHON's `_ctr_bump` READS `Counter([1,2,3,2])[2] == 2` AND NOT 1** --
**SO THE PORT's ANSWER AND PYTHON's ARE TWO INDEPENDENT COMPUTATIONS OF THE SAME PROPERTY.**

**AND THE GATE's ROW COUNT IS **35** ON BOTH SIDES** -- MEASURED, THE DRIVER PRINTS **35** AND
THE GATE NAMES **35** -- **AND A ROW COUNT THAT DISAGREES IS A GATE THAT CANNOT RUN.**

### 52f. AND TWO THINGS MEASURED ON THE WAY, BOTH OF THEM THE PORT's OWN SHAPE

  * **A COMMENT **INSIDE** A `do` BLOCK BREAKS IT** -- "the keyword 'def' cannot head one" --
    **AND THE PORT's OWN FILE PUTS ITS COMMENTS ABOVE THE BLOCK.**
  * **A `do` BLOCK's LAST STATEMENT MUST BE A BARE ONE** -- **AND HEAD's OWN BLOCK ENDS WITH A
    BARE `row(...)`**, **SO THE SHAPE WAS ALREADY IN THE FILE.**

### 52g. AND `ops-core-gate` IS STILL REFUSED, AND NOT BECAUSE OF THE COUNTER

`gates/ops-core-oracle.py` CRASHES AT `UOp(Ops.SINK, src=(), arg=None, tag=tag)` WITH "TypeError:
UOpMetaClass.__call__() got an unexpected keyword argument 'tag'" -- **AND THAT IS THE SAME
RE-VENDOR DRIFT THAT MADE `gates/decomp_graph_census-oracle.py` REFUSE WITH `KeyError:
'FLOORDIV'` AND THAT MADE `gates/symrules-oracle.py` REFUSE 24 OF ITS 232 CASES.**

**MEASURED: THE GATE WAS ALREADY rc=3 BEFORE THIS CHANGE, SO THIS CHANGE DID NOT CAUSE IT.**

## 53. `UOp.gcd` AND `UOp.divide_exact`, AND THE `ops-core` GATE IS ALIVE AGAIN

**MEASURED 2026-11-09. THE COMMITS ARE `4a8d15ab6` (THE `.bend`) AND `48aa36edd` (THE GATE).**

### 53a. AND THE GATE WAS REFUSED FOR A REASON THAT WAS **NOT** THE PORT's FAULT

`gates/ops-core-gate.py` WAS REFUSED (rc=3) BEFORE THIS, AND **A REFUSED GATE COMPARES NOTHING.**
THE ORACLE CRASHED WITH "TypeError: UOpMetaClass.__call__() got an unexpected keyword argument
'tag'".

**AND THE CRASH WAS RIGHT: UPSTREAM DELETED `UOp.tag` BEFORE THE PIN.** MEASURED:
`fb518b44e` ("delete UOp.tag [pr] (#18954)", 2026-10-21) AND
`git merge-base --is-ancestor fb518b44e f5ac54685074` ANSWERS **YES**; THE VENDORED
`tinygrad/uop/ops.py:192` AND THE PIN BOTH READ
`def __call__(cls, op:Ops, src:tuple[UOp,...]=tuple(), arg:Any=None)`; AND
`rg '\btag\b' tinygrad/uop/ops.py` FINDS **NOTHING**.

**⇒ THE THREE `tag_*` ROWS ASK A QUESTION UPSTREAM'S PIN CANNOT ANSWER, AND A ROW WHOSE ORACLE
CANNOT COMPUTE IT MAKES THE **WHOLE GATE** DEAD.** MEASURED: THE ORACLE'S ROW ORDER ALSO
DISAGREED WITH THE BEND LANE'S, AND **THE GATE COMPARES THE LANES **POSITIONALLY**
(`gates/gatekit.py`: `bad = [(x, y) for x, y in zip(base, other) if x != y]`) -- **AND THAT
MISMATCH WAS INVISIBLE WHILE THE GATE WAS REFUSED.**

### 53b. AND THE PORT's `Tag` IS UPSTREAM's DELETED CONCEPT, NOT `type(arg)`

THE PIN's KEY IS `(op, src, arg, type(arg))` (`ops.py:194`). THE PORT's `Node{op, src, arg, tag}`
CARRIES A FOURTH FIELD WHICH IS UPSTREAM's DELETED `UOp.tag`. **AND THE PORT's `arg` ALREADY
CARRIES THE TYPE IN ITSELF** -- `APy{CBool{...}}` AND `APy{CInt{...}}` ARE DIFFERENT `Arg` VALUES
AND `ANone{}` IS A THIRD.

**⇒ THE THREE `tag_*` ROWS ARE REPLACED BY THREE `arg_*` ROWS THAT ASK **THE SAME PROPERTY** IN
UPSTREAM'S SURVIVING SPELLING, AND THE PORT's OWN `t_tag_*` TESTS STAY IN `ops.bend`** -- **A ROW
THAT LEAVES THE GATE DOES NOT LEAVE THE TREE**, AND `.agents/TODO.md` ALREADY RECORDS THE
OVER-SPLIT AS LATENT AND UNREACHABLE ("The port has no `rtag` def and no `TBool{…}` construction").

### 53c. AND THE ORACLE'S `pa()` FIXTURE NAMED A `ParamArg` THAT THE PIN DOES NOT HAVE

**MEASURED: THE CRASH WAS "ParamArg.__init__() takes from 3 to 13 positional arguments but 14
were given"** -- **AND THE PIN's `ParamArg` (`ops.py:25-41`) HAS **TWELVE** FIELDS AND **NO
`multiple_of`**, WHILE THE OLD FIXTURE PASSED **THREE** `None`s BETWEEN `vmin_vmax` AND
`addrspace`.** THE FIXTURE IS RE-SPELLED AT THE PIN's OWN ORDER.

### 53d. AND `UOp.gcd` IS UPSTREAM'S, LINE FOR LINE

    terms, factors = zip(*[u.pop_const(Ops.MUL) for u in uops])
    count = functools.reduce(operator.and_, [collections.Counter(term.split_uop(Ops.MUL)) for term in terms])
    if not count: factors = tuple(u.const_factor() for u in uops)
    return math.prod(count.elements(), start=uops[0].const_like(math.gcd(*factors)))

**AND THE PORT SPELLS IT WITH FOUR MEASURED SUBSTITUTIONS, EACH STATED AT THE DEF:**

  * **`pop_const(Ops.MUL)` RETURNS `(NODE, CONST)` UPSTREAM AND THE PORT HAS ONLY THE CONST
    HALF**, **SO THE NODE HALF IS `UOp.pop_const_node` -- WHICH THIS BLOCK ADDS.**
  * **`const_like` IS NOT PORTED AND THE PORT's ARENA HAS NO SHAPE FIELD**, **SO THE PORT SPELLS
    THE **UNSHAPED** ONE, WHICH IS `UOp.const(b, dt)`** -- MEASURED 2026-11-07 ON CPYTHON: FOR
    THE `(x*y)/y` CASE `x` IS A VARIABLE AND **HAS NO SHAPE**.
  * **`Counter.elements()` REPEATS EACH KEY BY ITS COUNT AND THAT IS THE PORT's OWN
    `H.make_tuple_rep`** (`helpers.bend:1309`) -- **SO THE PRODUCT IS A CONCATENATION OF THOSE AND
    NOT A HAND-UNROLLED RECURSION.** **AND THE FIRST ATTEMPT AT THE PRODUCT WAS **250 HAND-UNROLLED
    DEFS** -- **WHICH WAS THE WRONG SHAPE, AND THE PORT's OWN `make_tuple_rep` WAS ALREADY THERE.**
  * **THE "ALL COUNTS ARE NON-NEGATIVE" TEST IS SPELLED AS A COMPARISON OF TWO **UNSIGNED**
    COUNTERS** INSTEAD OF A SUBTRACTION AND A SIGN TEST, **AND THE TWO ARE THE SAME PROPERTY**:
    UPSTREAM's DIFFERENCE IS NON-NEGATIVE IFF EVERY KEY OF THE DIVISOR's COUNTER IS PRESENT IN THE
    NUMERATOR's COUNTER **AT LEAST AS MANY TIMES**.

**AND THE PRODUCT'S SHAPE IS LEFT-NESTED, WHICH IS WHAT `math.prod` GIVES**: MEASURED, CPython's
OWN `UOp.gcd(x*z, x*z)` IS `(mul (mul 1 x) z)` **AND THE PORT's ANSWER HAS THE SAME SHAPE** --
`left_op=Ops.MUL left_nsrc=2 right_op=Ops.PARAM`.

### 53e. AND THE PRODUCT's **START** IS THE CONSTANT FACTOR's QUOTIENT, AND I READ HALF A LINE

**MEASURED 2026-11-09: `git show f5ac54685074:tinygrad/uop/ops.py` READS
`return math.prod(new_count.elements(), start=self.const_like(const//div_const))`** -- **AND THE
**FIRST** HALF OF THAT LINE IS WHAT I READ**, **SO THE PRODUCT HAD NO START AND THE ANSWER WAS `x`
INSTEAD OF `(mul 1 x)`.** **⇒ THE PORT's `UOp.divide_exact.start` IS `const_like(const //
div_const)`, AND THE `de_const_out` ROW IS THE ONE THAT CATCHS A MISSING START.**

**AND THE TWO CONST READS ARE **DIFFERENT READS**: THE **POPPED** CONSTANT OF A MUL IS
`UOp.pop_const_val(ar, node, OpsMUL{})` AND THE CONST NODE's **OWN** VALUE IS
`cval_arg(Arena.arg(ar, i))`.** MEASURED: THE PORT's FIRST `cval` READ THE **NODE's OWN ARG** AND
SO ANSWERED THE IDENTITY `1` FOR EVERY MUL, **AND `divide_exact(x*2, x)` ANSWERED **1** AND NOT
**2**; AND THE `v IS A CONST` BRANCH NEEDS THE CONST's **OWN** VALUE **2** AND NOT THE POPPED
ONE.**

### 53f. AND THE SIX NEW ROWS ARE CPYTHON-CONFIRMED AGAINST CPYTHON's OWN FUNCTIONS

`gcd_const`, `gcd_shared`, `de_same`, `de_const_none`, `de_mul`, `de_const_out` -- **AND CPYTHON's
OWN `UOp.gcd` AND `UOp.divide_exact` ARE THE ORACLE, SO THE PORT's ANSWER AND PYTHON's ARE TWO
INDEPENDENT COMPUTATIONS OF THE SAME PROPERTY.**

**AND THE ROWS READ THE **VALUES** AND NOT ONLY THE **SHAPES** -- MEASURED: A PLANT THAT REPLACED
THE PRODUCT's START WITH `1` **DID NOT** MAKE THE GATE GO RED WHEN THE ROWS ASKED "IS IT A CONST?",
**AND A ROW THAT CANNOT GO RED IS WORSE THAN NO ROW.** TWO PLANTS ARE NOW MEASURED FIRING: THE
START REPLACED BY `1` REDS `de_const_out`; AN ALWAYS-EMPTY INTERSECTION REDS `ctr_inter` AND
`gcd_shared`.

### 53g. AND THE BEND SPELLING RULES THIS LANE MEASURED, ALL OF THEM BY COMPILER ERROR

  * **A `match` MAY NOT SCRUTINISE A COMPUTED VALUE** -- "a parameter or field scrutinee (a match
    cannot scrutinize a computed value: give it its own def)" -- **AND A `match` OVER A **CALL** IS
    ALSO A COMPUTED VALUE, AND A `match` OVER A `+` BINDER OF A **CUSTOM** TYPE IS TOO.** **⇒ EVERY
    DISPATCH IS A **PARAMETER**, AND THE COMPARISONS ARE COMPUTED BY THE CALLER.**
  * **A NODE-BUILDING DEF MUST ANSWER A `Found`** AND NOT A BARE `U32` -- MEASURED: A PROBE READ
    `gcd=3` WITH `gcd_op=Ops.NOOP` **BECAUSE THE CONST WAS AT INDEX 3 IN THE **GROWN** ARENA AND
    INDEX 3 IN THE **OLD** ONE WAS THE NOOP.**
  * **A RECURSION THROUGH A CHAIN OF TESTS IS A CYCLE** -- **AND A **DIRECT** SELF-CALL IS NOT** --
    **AND THE PORT's OWN `UOp.divides.op` IS THE PATTERN** (`ops.bend:8252`): ONE DEF, A `match` ON
    A **PARAMETER**, AND **TWO DIRECT SELF-CALLS** IN THE ADD's ARM.
  * **A `+` PARAMETER MAY BE READ TWICE AND A PLAIN ONE MAY NOT** -- **AND THE PORT's OWN
    `merge_dicts.go` (`helpers.bend:2533`) IS THE SHAPE THAT WORKS**: THE TAIL IS THE RECURSION's
    FIRST ARGUMENT AND THE STATE IS PASSED **ONCE**, INSIDE THE ADDER's ARGUMENT LIST.
  * **THE COMPUTED VALUE MUST NOT BE THE **FIRST** ARGUMENT** -- MEASURED: THE PORT's OWN
    `UOp.divides.op(fuel: Nat, op: Op, +ar: Arena, ...)` HAS **TWO PLAIN** PARAMETERS BEFORE THE
    `+` ONES, **AND THE COMPUTED OP IS THE **SECOND** ONE.**
  * **THE COMMENTS IN A BLOCK MUST BE STRIPPED BEFORE THE USES ARE FOUND**, **OR A COMMENT NAMING A
    DEF IN PROSE READS AS A CALL** -- MEASURED: THE COMMENT "# THE ANSWER ITSELF: `UOp.gcd(*uops)`"
    WAS IN `UOp.gcd.prod`'s BODY AND SO `prod` "USED" `UOp.gcd`, **AND THE CYCLE WAS FAKE.**

### 53h. AND THE `divandmod.py:103` GAP IS NOW UNBLOCKED, AND IT IS STILL OPEN

**`dr174` IS `(div (mul x y) y)` AND UPSTREAM'S ANSWER IS `(div (mul c1 x) c1)` -- AND THE PORT
ANSWERS `norewrite`.** MEASURED: THE DIVERGENCE IS **PRE-EXISTING** (IT READS IDENTICALLY WITH
`ops.bend` REVERTED), **AND IT IS UPSTREAM's `fold_divmod_general`** (`divandmod.py:8`), **WHICH
NEEDS `UOp.gcd` AND `UOp.divide_exact` -- **AND THOSE ARE NOW IN.**

**⇒ THE NEXT MOVE IS `sym_174`'s BODY, NOT THE PRIMITIVES.**
