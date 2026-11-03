# `symbolic.py` — the state of the port, measured 2026-11-03

Every number here was produced by running the named instrument on the tree as it stands.
Nothing in this file is remembered.

| reading | value | instrument |
|---|---|---|
| census rows | **141** (139 `symbolic.py`, 2 `pm_remove_invalid`) | `gates/symrules.rows` |
| PORTED | **114** | `gates/symrules-census.py` |
| MISSING | **27** | `gates/symrules-census.py` |
| port entries mapped | **114**, 0 broken, 0 unresolved | `gates/symrules-gate.py` (rc=0) |
| behavioural witnesses | **190**, 190 agree, 0 diverge | `gates/symrules-oracle.py --compare` |
| table rows | **112**, tags 0..111 unique | `gates/symclosure-gate.py` `tags.unique` |
| mint arms | **81** == `MINT_TAGS` | `symclosure-gate` `mint.arms` |
| index arms | **31** | `symclosure-gate` `dispatch.arms` |
| `bodies.absent` | **2** (`fold_add_divmod_recombine`, `reduce_collapse`) | `symclosure-gate` |

`bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --check-only` → `ALL PROOFS CHECK`.

## What the case lane is

`gates/symrules-cases.rows` holds 190 graphs; the port's own driver reads the whole file and
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
| `:129` (`fold_add_divmod_recombine`) | PORTABLE NOW — `split_uop`, `pop_const` and
  `backward_slice` all landed; it is a ~60-line fold over term pairs with `_quotient_base`, and
  it is one of the two `bodies.absent` |

## The two rules the sweep unblocked and the one it did not

`UOp.vmin`/`UOp.vmax` are NOT TODOs — they landed in `uop/fold.bend` as readers over the
sweep's `BTable`, with `bnd.lt`/`bnd.eq`. That is why `:280`, `:274` and `:276` are ported.

**ONE WALL INSIDE THOSE**, recorded beside the rule and not hidden: `(floormod x c1)` does not
fire and CPython answers `c0`. `(cmplt x c0)` fires and `(floormod x c2)` declines, so the rule
and its guard are wired; the missing half is the SWEEP, which collapses CMPLT's range to `[0,0]`
and not FLOORMOD's. The fix belongs in `uop/fold.bend`.

## How to continue

1. `:129` first — its helpers exist and it clears a `bodies.absent` row. **THE SEMANTICS ARE
   MEASURED** (`ops.py:1082`, read today): `pop_const(op=Ops.ADD)` — the DEFAULT IS `ADD`, not
   `MUL` — answers `(src[0], src[1].val)` when `op` matches and `src[1]` is a CONST, and
   **`(self, identity_element(op, dtype))`** otherwise, where the identity is **0 for ADD and 1
   for MUL**. That default is what makes `_quotient_base` answer `x` for `(x%3) + (x//3)*3`: the
   `a` and `xa` in `t = xa + a - pa` are ADD-identities (0) on nodes that are not ADDs, so
   `t == 0`, `t % D == 0`, `k == 0`, and the answer is the base. A port that defaulted to `MUL`
   would compute `t = 1` and refuse. THE WITNESS IS MEASURED: `(x%3) + (x//3)*3` -> `(mul x c1)`
   and `(x%3)*5 + (x//3)*15` -> `(mul x c5)`, both from CPython, both refused by the port today.
2. The movement table next: it is 9 rows and one new `PatternMatcher` transcription, and it needs
   `UOp._mop` (a builder, not a fold) before a single one can fire.
3. `divandmod` and `weak` are one table each, mirroring `rm_table`'s shape.
4. Everything else above is a substrate TODO in `uop/ops.bend`, and this file names the line.
