# The standing instruction in `uop/fold.bend` — STALE, corrected in place

Unit: owns `uop/fold.bend`. `helpers.bend` read only. Compiler Bend 2.0.34.
All bend runs under `checks/bounded.py --seconds 900 --mb 1024`, **one process at a time**.

## 1. The instruction, quoted

At the `THE _min_max ARITHMETIC CORE` banner, immediately above `def mm.u64.of`:

> **WHY IT IS HERE AND NOT IN helpers.bend.** `mixin/dtype.bend`'s header says the wall
> is that `i64_mul`, a shift, `i64_div` and `i64_mod` do not exist — and that div/mod DO
> exist in `tinybendygrad/dtype.bend` but as `IO(..)` effect seams, which a fold cannot
> call. This section is the same set of operations written PURE, which is the only shape
> `_min_max` can use. It is spelled under the same notice that `promo_mask`/`least_upper`
> carry ("THE LATTICE IS HOISTED"): **when helpers.bend grows them these defs go there and
> the callers do not change.**

**I re-derived the location. The handed citation `:2655` is the middle of the premise
clause; the standing instruction proper is `:2659`–`:2660`.** The `mm.u64.*` block the
instruction points at begins at `def mm.u64.of` — 26 lines below the quoted text, matching
the handed `:2681` to the line.

## 2. Verdict: STALE — 4 claims of 4 dead. Not one of the nine documentary ones.

Per the wallrule rule, a wall is a claim about a **tree**. So I re-derived every claim.

| # | Claim | Measured 2026-10-05 | |
|---|---|---|---|
| 1 | `i64_mul` does not exist in `helpers.bend` | `def i64_mul` — pure, over `u64_mul_parts` | **DEAD** |
| 2 | `i64_div` / `i64_mod` do not exist | both pure, beside the 64-step restoring divider | **DEAD** |
| 3 | a 64-bit **shift** does not exist | `def i64_shl` — and see below | **DEAD** |
| 4 | div/mod are only `IO(..)` seams in `dtype.bend`, unusable by a fold | `IO(` × **0**, `import "./runtime/dtype.*"` × **0**, `SOME PROOFS FAIL` × **0** | **DEAD** |

Claim 3 deserves its own line, because the premise I was handed said a runtime shift amount
*cannot* be a `Nat`. **It can, and this file proves it.** `bnd.pw2(+bits: U32)` — `bits` a
runtime parameter — calls `mm.u64.shl(0, 1, U32.to_nat(U32.sub(bits, 1)))`, whose parameter
is `+k: Nat`. `fold.bend` is `ALL PROOFS CHECK`. So the shift was never a *scope* difference
here at all; `i64_shl` was usable all along.

**Two facts make this the worst-placed copy of the wall, not the only one.**
`mixin/dtype.bend`'s header already says *"SO THE WALL IS NOT 'three helpers are missing',
which is what `uop/weak.bend` and `uop/fold.bend` BOTH RECORD"*, and `uop/weak.bend` says
*"all of which now exist"*. **Both other copies had already been corrected. This one had
not.** That is the whole failure mode named in my brief: the instruction lived where the
next reader would not look.

## 3. Does the trigger fire? Yes. And executing it is not what the instruction promised.

The trigger (*"when helpers.bend grows them"*) fired for all four. `mm.u64.*` is **not**
unreachable: **84 call sites in this file, 0 outside it** (29 `mm.u64.*` defs, 39 `bnd.*`
defs; 14 of those call sites are inside `bnd.*`, 55 are in `main`'s gate rows).

**The instruction's own promise was false, which is very likely why it was never executed.**
"the callers do not change": every one of those 84 sites needs a namespace qualifier,
because `H` is how this file reaches `helpers.bend`. The block already makes 95 `H.` calls;
a move is 84 more. Measured, not estimated.

**What executing it would actually change: nothing observable, and it is not a move.**
`helpers.bend` already owns the unsigned primitives this block reimplements — `i64_of_hi_lo`,
`u64_lt`, `u64_divmod`, `u64_mul_parts`. `mm.u64.mul` *is* `u64_mul_parts` **plus one
thing**: `mm.u64.of` answers `None`, and **that `None` is the unsigned overflow**, which
every caller turns into `PInf`/`NInf`. `i64_mul`/`u64_mul` **wrap** mod 2^64 and cannot
report it. So the contract differs and this is not duplicated logic.

**So the honest answer is the opposite direction**, and that is what I wrote: what
`helpers.bend` lacks is a **checked** unsigned 64-bit op (Maybe-on-overflow), not the
arithmetic. The recorded reopen condition is now that condition, with the old wall's
falsity kept in place.

## 4. `fold.bend:513`'s warrant: **WRONG**, and **the decision's answer changed**

The warrant cited a `helpers.bend` table entry — the textbook case of a false premise inside
a decision, which looks derived so nobody re-derives it.

> (`helpers.bend` has `i64_add` and `i64_sub` but **no `i64_mul` or `i64_div`**, and a dim is
> not a value this port needs 64-bit arithmetic for.)

`i64_add`/`i64_sub`: true. **`i64_mul`/`i64_div`/`i64_mod`: all present and pure. FALSE.**
So "a dim is not a value this port needs 64-bit arithmetic for" was resting on an inventory
that had gone stale.

**The decision's answer changed.** It rested entirely on its own second clause — *"a dim is
a non-negative count and an itemsize is 1, 2, 4 or 8, so the product fits a U32"* — because
the first clause was false. That clause is **also false past a threshold**.
`bitcast_dims.scale` truncates to U32 **twice**: `H.lo32(sint)` and `U32.mul`.

Oracle `.agents/slop/trigger/bc-oracle.py` calls the **real** `tinygrad` BITCAST arm through
`Tensor.bitcast` (`"unsupported size in bitcast"` is the proof it is that arm). Expectations
called, never typed. **324 rows: 172 agree, 80 DIFFER, 72 unbuildable.**

| band | agree | DIFFER |
|---|---|---|
| non-negative dims, `dim*inp < 2**32` | 120 | **0** |
| last in-window dim per `inp` | 34 | 14 |
| first out-of-window dim per `inp` | 18 | 30 |
| far past the window | 0 | 36 |
| negative dims | — | 72 unbuildable |
| **threshold band (one dim either side, per `inp`)** | **12** | **12 — EXPECTED 12** |

**THE ANSWER, restated: U32 is exact while `dim*inp < 2**32` and wraps silently above it —
no raise, no `None`, just `0`.** Largest exact dim is `2**32//inp - 1`: 4294967295 / 2147483647
/ 1073741823 / 536870911 at `inp` 1/2/4/8. At `dim = 2**32//inp` the port answers 0 where
CPython answers `2**32//out`. And **U32 is no longer forced either**, since `i64_mul` and
`i64_div` exist — so the fix is available, not hypothetical.

Negative dims are **not** part of the gap, and I checked rather than assumed: upstream
refuses to build one at all (`ValueError: shape can't contain negative numbers`), so
`H.lo32` of a negative is unreachable rather than wrong.

## 5. What I did

**Two comment edits in `uop/fold.bend` only. +64/−11, every added line a comment — verified
by grepping the diff for any non-comment addition, which returned nothing.**

1. The `:513` warrant replaced with: the two truncations named, the measured threshold, the
   falsity of the old entry, the restated answer, a REOPEN condition, and a
   `TODO(fold-bitcast-u32)` for the divergence itself.
2. The standing instruction **corrected in place, NOT deleted** — `helpers.bend`'s note above
   `i64_or` and `uop/weak.bend`'s header both point at it, so a deleted wall is a wall
   somebody re-derives.

**`helpers.bend` was NOT touched: 125,668 bytes before and after, checked after every step.**
It is the root of a 33-file closure and has been truncated to 0 bytes four times today.

## 6. Rows against rows expected

**334 rows before, 334 after, byte-identical** (whole `name=value` lines, not names) — the
control a comment-only edit must pass. `fold.bend` stayed `ALL PROOFS CHECK`, rc 0.

**Plant and disarm, both, and the second one is the finding:**

- **Plant A** — dropped the `u != 0` half of `mm.u64.join`'s overflow test. **3 rows moved,
  by name:** `lf_sat_mul`, `mm_mul_2p32sq`, `mm_mul_2p47sq`. The `mm.*` block is load-bearing
  and gated.
- **Plant B** — forced `bitcast_dims.put.of`'s divisor to `1`, so every bitcast answers
  `n` instead of `n/out` and the raise-guard always passes. **ZERO rows moved.**
  A blind spot with a reason, not a zero I have to explain away: `fold.bend`'s `main` has
  **no row naming `bitcast` at all** (0 of 334). That is why the fix is gated behind
  `TODO(fold-bitcast-u32)` rather than done — the gate half has to come first.
- **Both disarmed; final output identical to both the pre-edit baseline and the post-edit
  run**, so the disarming is proven by the same instrument that armed them.

## 7. Peak RSS (all runs bounded, `--mb 1024`, sequential)

`--check-only` 442 MB · plain run 821 / 847 / 833 / 727 / 695 MB. All `WITHIN-LIMITS`, rc 0,
~1 s. **No run was killed and none timed out. `helpers.bend` never compiled in this session.**

## 8. What I could not do

- **I did not execute the instruction** (did not move `mm.*` into `helpers.bend`), and I
  should not have: `helpers.bend` is root of a 33-file closure, was truncated to 0 bytes four
  times today, and my house rules admit it *only if the warrant fix demands it* — the warrant
  fix is entirely inside `fold.bend`. Section 3 measures what executing would change instead.
- **I did not fix the `bitcast_dims` divergence**, for the reason in §6: zero gate rows, so a
  fix would be unverifiable and untestable in place. Recorded as `TODO(fold-bitcast-u32)`.
- **Not mine, reported not touched:** `opspy/corpus.py:6` still says `61 of 77` while the
  script prints `53 of 77` — the third figure in the TODO.md entry I ticked, still open.