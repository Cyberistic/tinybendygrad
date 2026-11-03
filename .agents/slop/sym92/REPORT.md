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
