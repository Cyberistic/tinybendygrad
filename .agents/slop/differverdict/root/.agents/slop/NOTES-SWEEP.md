# NOTES-SWEEP — the notes' numbers, audited against runs

**One job, no code: the project's notes contained numbers that were true when written and
are false now. This is what was found, what was corrected, and what could not be
re-measured. Nothing committed.**

Full detail: **`.agents/slop/notes-sweep/01-GROUND-TRUTH.md`** (the measurements) and
**`02-FINDINGS.md`** (every stale claim, with its denominator).

## The measurement, first, because it is the only part that settles anything

```
graphs 24 | denom 77 (measured len(list(Ops))) | PY 59 | BEND 59 | BOTH 59
py-only [] | bend-only [] | WALLS [] | NOT REACHED 18 of 77
22 AGREE | 2 DISAGREE (lin, loop — forward-only on purpose)
.bend files: 137 total, 14 cold under --check-only, 123 warm
```

Instruments: `hermetic-census.py --no-publish` (rc=0, no writes), `graphcmp.py diff` once per
graph, `find | xargs -P 6 ./bin/bend --check-only`. **The brief's numbers are all confirmed
by run.** The `18 not reached` were derived here from the census's own op dicts and
`{o.name for o in list(Ops)}`, not transcribed.

## What was stale — 8 sites on the coverage number alone

`REACH.md`'s headline (22 graphs / 53 of 77 / NEITHER 24), its 24-name not-reached list, its
`53 of 77` emitter claim, and `graphcmp-LIMITS.md` §5's `34 of 77` + `REACHED (34)` table +
`NOT REACHED (43 of 77)`, its §0 current-state block, §3c, §8, and `TENSOR-SURFACE.md:206`
(which also cited the wrong line). **Every one now carries both values.**

## The two the brief flagged, confirmed and fixed

- **`flip` reads AGREE 6/6, not DISAGREE 6/7** — measured independently, and the AFTER block
  in `flip/FLIPR.md` is **still exactly right**. Five `6/7` sites marked.
- **`graphs-agree` is 22, not 14 and not 15** — **six** sites, not five.

## Three the brief did not flag

1. **A claim that INVERTED.** `graphcmp-LIMITS.md` §5 proves `CMPEQ` unreachable and says
   *"still 0. Reaching it needs a pattern-matched rewrite."* **Measured: `late` reaches it —
   commutative ops are now 8 of 8.** Every measurement in that paragraph is still true and
   the conclusion is false. The generalisable bit: *"I could not reach it" is not "it cannot
   be reached"*, and a paragraph of correct measurements got promoted into a false theorem.
2. **`arith/REACH-ARITH.md` §5 had FOUR of six citations wrong, not two.** `:2769`,
   `:1712-1717`, `:2869`, `ops.py:842`, plus `graphcmp.py:1686`/`:1703-1705` in wall 1.
   `:2769` is a `continue`; `:2869` is a conflation line; `ops.py:842` is `def getaddr`.
   **Every wall's substance is sound — only the pointers were fiction.** (Walls 2 and 4:
   verified exactly correct.)
3. **`graphcmp.bend` is generated and `g_flip` moved `:1274` → `:1289`.** `FLIPR.md` cited
   the old lines; `graphcmp.bend:1241-1242` now records the *corrected* census, i.e. the
   number being cited was already fixed underneath the citation. **Cite generated files by
   NAME.**

## Numerator right, denominator stale — the recurring shape

- `agent-core.md`: "**14 of the 136**" → **14 of the 137**, the other **123**. **The 14 cold
  files are exactly the same 14, member for member.**
- `SPELLING.md`: **678** `H.I64` uses ✅ held; **41** files → **39**; "40 defs" unverified.

## What could not be re-measured: 21 claims, marked STALE, none guessed

libclang `324`/`323`/`311` · `2,419 of 2,421` identifiers · `24,583` port defs · `t_` 1,813 ·
`cstyle.bend` 43+22 · `5,503` lines · the 22 phantom blind spots · 841 lines · `190+` rules ·
e2e stages · ABI-1..7 · `154/154` repro files · 189 nodes / 1134 field-records · the
float-CONST and `zip-truncated` counts · `40 i64_*` defs · the port's 77/77/0/0 enum ·
`dtype.c:205`/`dtype.js:136` (live unit's file) · `libclang.bend:95,98,101`.
**They are printed on every run of the checker and never counted as passes.**

## The checker, and its hit rate

`notes-sweep/staleness.py` — `--quiet`, `--measure`, `--falsify`.

**Hit rate: 11 re-measured claims, 0 stale after correction — and `--falsify` provably fires
(rc=2, one named row), so the `0` means "the notes now agree", not "the instrument cannot
notice".** An instrument that had only ever printed zero would not be evidence of anything,
which is why the perturbation exists.

## The one thing that needs an owner's hand

**`graphcmp-repro.sh` has three dead pins** — `graphs=16` (now 24), `graphs-agree=14`
(**now 22**), `byte-identical=14` (now 21) — so **the gate refuses a fully correct run and
retries, which is indistinguishable from a real reproducibility failure.** Gate script, out
of scope: **reported in three notes, not patched.** (I reverted an edit I made there.)

**The generalisable finding, and it is not about arithmetic: every claim with a
MACHINE-PRINTED denominator is current, and every number a human typed into prose has
aged.** `nodes=`, `ops-reached=`, `?=`, `commutative-ops=` — all correct on re-measurement;
the prose tables are what rotted. **That is an argument for printing the claim rather than
writing it down.**