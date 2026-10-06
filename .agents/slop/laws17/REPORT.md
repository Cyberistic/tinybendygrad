# laws17 — the proof backlog, by discovery, and the regression that made it look real

Measured 2026-10-06. Instrument: `.agents/slop/laws17/laws.py` (`.venv/bin/python`,
walks `tinybendygrad/**/*.bend`, follows the relative `import` graph). Every number
carries its denominator and the rule that produced it. No count is quoted from a job
that may still be running: each `bend` run is a finished `checks/bounded.py` line.

## 1. THE FINDING: the two numbers disagree, and they disagree about the BOOK

**By discovery, the aggregate book has 0 open laws of 34. `PROOF.bend --check-only`
reports 17. That is the finding: `PROOF.bend` is the SHAPE HALF, not the port's
backlog, and the 17 it counts are already proven in `PROOF2.bend`.**

The discovery rule is Bend's own (`bend.ts:3847`, `book.hols`): a law is open iff no
`def` of that name exists ANYWHERE IN THE BOOK (the import closure of the root file).
`laws.py` collects `^law  NAME:` and `^def ...NAME(` over the closure and matches by
the def's last dotted component.

| book (root) | open | filled | total |
|---|---:|---:|---:|
| `tinybendygrad/LAWS.bend` | 34 | 0 | 34 |
| `tinybendygrad/PROOF.bend` | **18** | 16 | 34 |
| `tinybendygrad/PROOF2.bend` | 16 | 18 | 34 |
| `tinybendygrad/LAWS/PROOF-ALL.bend` | **0** | 34 | 34 |

**Denominator: 34 laws** (`grep -c '^law ' LAWS.bend` = 34, measured). No file in the
tree declares a law outside `LAWS.bend` (discovery over all 138 `*.bend` files: the
only four books with a non-zero law total are the four rows above). `?TODO` holes in
the tree = **0**, so the entire TODO count of any book is laws-with-no-def.

`PROOF.bend --check-only` = **17 TODOs** and `LAWS.bend --check-only` = **34 TODOs**
(measured, both `WITHIN-LIMITS`, 31 MB). The two books never agree and never should:
`LAWS.bend` declares the laws and fills none; `PROOF.bend` fills the shape half only.
**A count from a half is not a backlog count, and `.agents/slop/portmarkers/REPORT.md`
read the half's number as the port's.** It also never mentions `PROOF2.bend`, which
`PROOF-ALL.bend` imports and which fills the other 18 (nine section-IV + nine
section-V, every one `{==}`).

## 2. THE REGRESSION: the "landed law" is a DUPLICATE, and it broke the gate

Commit `579f979b1` ("portmarkers: PROOF.bend 18 -> 17") added

```
def L.where_takes_the_second_operand_dtype(p, a, b):
  {==}
```

to `PROOF.bend` **where a def of that exact name already existed at
`PROOF2.bend:84` since `0104d757e`.** Bend requires a fresh name per book, so the
aggregate gate — the one file that imports BOTH halves — no longer builds:

| gate | before repair | after repair |
|---|---|---|
| `PROOF-ALL.bend --check-only` | **REFUSED** rc=1, `- expected : a fresh name (L is an import's alias)` / `observed 'L.where_takes_the_second_operand_dtype'`, no verdict | **`ALL PROOFS CHECK`** rc=0, stdout 58 B |
| `PROOF.bend --check-only` | 17 TODOs | 18 TODOs (the half, restored) |
| `LAWS.bend --check-only` | 34 TODOs | 34 TODOs (**unmoved**) |
| `PROOF2.bend --check-only` | 16 TODOs | 16 TODOs (the other half, unmoved) |

`PROOF-ALL.bend` before the repair printed **no TODO count and no `ALL PROOFS CHECK`**:
a REFUSED, not a pass and not a red verdict about any law. `.agents/TODO.md:637`
records this gate green at **0 TODOs**, and `.agents/slop/AUDIT-CAN-FAIL.md:14`
records `34/34 ALL PROOFS CHECK`; the duplicate is what removed that. The portmarkers
change traded a green aggregate for a cosmetic half-count.

## 3. THE REPAIR (6 deletions, `PROOF.bend` only)

Removed the out-of-scope duplicate. `PROOF.bend`'s own header (lines 5-6) scopes it to
`sections I, II, III, VI, VII and VIII`; `where_takes` is section V, which belongs to
`PROOF2.bend`. `git diff HEAD -- tinybendygrad/PROOF.bend` = `6 deletions(-)`; no other
tracked file changed (`git diff HEAD -- LAWS/spec.bend` empty after the plant revert).

## 4. CLASSIFICATION of the 17 laws open in the `PROOF.bend` closure

All 17 are **ALREADY PROVEN in `PROOF2.bend`** — 9 section IV (`neg_is_mul_by_minus_one`
… `mulacc_is_add_of_mul`) and 8 section V (`comparison_is_bool` … `detach_preserves_numel`).
Of the brief's four classes:

| class | count | why |
|---|---:|---|
| PROVABLE NOW | **0** | there is no def to write; each law's def exists |
| NEEDS A PORT | **0** | nothing names unported behaviour |
| REASONED | **0** | none is deliberately unfilled |
| UNCLASSIFIED | **0** | — |

The 17 are the half-boundary between two halves that `PROOF-ALL.bend` joins, not
work. **There is nothing to land.**

## 5. PLANTED: the law still bites after its def moved halves

Fault: `LAWS/spec.bend:806` `Sp.dtype(b)` -> `Sp.dtype(a)` (reverted after). Run on
`PROOF-ALL.bend`, so it is `PROOF2.bend`'s def that catches it:

```
SOME PROOFS FAIL
- expected : spec.Sp.dtype(a)
- observed : spec.Sp.dtype(b)
Location: L.where_takes_the_second_operand_dtype
```

The gate names the law and both terms — removing `PROOF.bend`'s duplicate left the law
guarded, not a comment.

## 6. BLAST RADIUS

- **1 of 138** `*.bend` files touched (`tinybendygrad/PROOF.bend`, 6 deletions) = **0.72%**.
- **34 of 34** laws proved in the aggregate book after the repair (`ALL PROOFS CHECK`).
- `tinybendygrad/helpers.bend`: **130719 bytes, 2843 lines, non-zero, unchanged** (no edit went near it).
- Only `LAWS/PROOF-ALL.bend` imports `PROOF.bend`, so the deletion's reach is exactly that one gate.

## Files

- `.agents/slop/laws17/laws.py` — the discovery instrument.
- `.agents/slop/laws17/books.tsv` — its census over all 138 files + the 4 gates.
- `.agents/slop/laws17/{proof,laws}.{before,after}.{out,err}` and `proof2.after.{out,err}` — the half-book tokens.
- `.agents/slop/laws17/proof-all.{err,after.out,final.out}` and `plant.err` — the aggregate.
- `tinybendygrad/PROOF.bend` — the repair (6 deletions).

Not committed (orchestrator commits by path).
