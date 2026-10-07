# CLAIM — unit `DENOM`, started 2026-10-04

## Files I own (I will not edit any other unit's files)

- `.agents/slop/denom/*`            (mine, exclusively)
- `.agents/slop/DENOMINATOR.md`     (mine, exclusively)

## CONTESTED — I claim these ONLY to read them, and only after the check below

- `.agents/slop/graphcmp.py`
- `.agents/slop/graphcmp.bend`
- `.agents/slop/graphcmp-oracle.py`

I have **not edited** any of the three. If a later graph needs them, I re-claim in this
file first (append-only) before touching anything.

## What I will not touch

`runtime/dtype.js`, `helpers.bend`, `dtype.bend`, `substrate-check.sh`, every other
`.bend`, `runtime/**`, `uop/**`, `helpers.bend`, `renderer/**`, `tinygrad/**`, `LAWS/**`,
`PROOF*.bend`, `rebase-gate.py`, `cstyle-gate.py`, `reader-*`, `e2e*`, `abi_gate.py`,
`jsfix_*`, another unit's slop tree. Scratch work in `$TMPDIR`. Oracles on disk, never in
`$TMPDIR`. **Nothing committed.**

## The question, in one line

For each of the 18 ops the differ does not reach: **can a graph emitter express it as a node
at all?** Decided by searching for *construction sites* in `tinygrad/`, not for the name.

## Rule prefix (fresh, mine)

All my new rules are prefixed `DENOM-` (e.g. `DENOM-1`, `DENOM-2`) so they cannot collide
with a sibling unit's numbering.

---

# RE-CLAIM, 2026-10-04, after the measurement phase — I AM NOW EDITING

Read-only use ended. md5 of the three contested files **at the moment I take the write
claim**, so a later collision has a baseline to diff against and cannot be silently
attributed to me:

```
c7096ee70cdfef447aec10cd784ef3ac  graphcmp.py        (matches hermetic/HERMETIC.md's
                                                  "graphcmp.py byte-unchanged (c7096...)")
9e5299b7c450c74325c1cc8cb530858f  graphcmp.bend
9f47db7830523b41068a1196808c118b  graphcmp-oracle.py
```

## WHAT I AM ADDING, and the exact shape of the edit

One new fixture, `g_allred`, in both files. Additive only — a `def`, one `GRAPHS` entry, one
dispatch arm. **I change no existing line of either file**, so a concurrent unit's work is
not touched and a revert is one deletion per file.

- `graphcmp.py`: `def g_allred()` beside `g_cdiv`, and `"allred": g_allred` in `GRAPHS`.
- `graphcmp.bend`: `def g_allred()` beside `g_flip`, and one `Bool.pick(... String.eq(name,
  "allred"), g_allred(), ...)` arm in the existing dispatch chain.

`g_allred` is chosen because it is the **cheapest possible proof that the denominator is
right**: 9 nodes, and it adds TWO of the 18 (`ALLREDUCE` and `COPY`), and every op it
contains is already in the corpus's reached-59 except those two — so the bend side needs no
arg constructor that `g_mselect`-style fixtures have not already forced. `program` also adds
two but is 51 nodes with a `ProgramInfo` arg; `patir` adds three but is UNEMITTABLE (see
`emittable.py`, `cshape` raises `AssertionError` on a shapeless `AND`).

**IF THIS FILE HAS MOVED WHEN YOU READ IT, DO NOT TRUST MY LINE NUMBERS — diff against the
md5s above.**
