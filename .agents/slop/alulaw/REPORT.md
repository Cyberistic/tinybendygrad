# alu-law-census — the ALU/dtype half's laws, and what they do NOT pin

Measured 2026-10-30. Instrument: `gates/alu-law-census-gate.py`
(`.venv/bin/python`, one `bend` process at a time, every case on a fresh copy of
`tinybendygrad/` in a private temp dir). Baseline:
`gates/alu-law-census.rows`, written only by `--refresh`.

## 0. THE BRIEF WAS STALE, AND THE TREE ALREADY SAID SO

The brief asked for nine ALU/dtype laws to be proved, and said
`PROOF.bend --check-only` reports `Error: 18 TODOs found.`

**Those 18 are a HALF-BOOK BOUNDARY, not a backlog**, and the tree had already
answered this on 2026-10-06 — commit `98721d492`, report
`.agents/slop/laws17/REPORT.md`:

| book (root) | open | filled | total |
|---|---:|---:|---:|
| `tinybendygrad/LAWS.bend` | 34 | 0 | 34 |
| `tinybendygrad/LAWS/PROOF-ALL.bend` | **0** | **34** | 34 |

Measured here, same numbers: `PROOF.bend` 18 TODOs, `PROOF2.bend` **16** TODOs,
`LAWS/PROOF-ALL.bend` **0** TODOs (`ALL PROOFS CHECK`, and the same under
`--verdict`, the proven kernel). `34 = 16 + 18`, and the 18 `PROOF.bend`
counts are **exactly** the 18 laws `PROOF2.bend` proves.

**All nine of the brief's laws, and all nine of its extras, were ALREADY
PROVEN** in `tinybendygrad/PROOF2.bend` (committed `813bbec3e`, i.e. long
before this unit started).

**AND THE PRIOR ATTEMPT AT THE COUNT WAS REVERTED.** `579f979b1` moved one
law's `def` into `PROOF.bend` to make the half-book count read 17; the
aggregate gate then REFUSED to build —

```
- expected : a fresh name (L is an import's alias)
- observed : 'L.where_takes_the_second_operand_dtype'
```

— no verdict at all. The repair was six deletions. `98721d492`'s own words:
**"A count from a half is not a backlog count"** and **"there is nothing to
land."**

**MEASURED HERE, THE SAME WALL.** A duplicate `def L.<name>` in the aggregate
book is refused with the same message. And `PROOF.bend` importing `PROOF2.bend`
DOES make `PROOF.bend --check-only` read 0 TODOs — measured — but it changes
the import graph `gates/verdict-lane-gate.py` discovers its population from,
and the tree's own record says gaming the half-book count is an anti-goal.
**NOT DONE, DELIBERATELY.**

## 1. WHAT THIS UNIT DID LAND: A GATE THAT ASKS WHETHER THE LAWS CAN FAIL

`gates/alu-law-census-gate.py`. The aggregate gate asks "are the laws true?";
this one asks **"can each law be false?"** — a law that cannot go red is a
label, not a law (`checks/differ.py`'s own plant 3).

**18 of 18 laws go RED, each naming itself.** One mutation per law, on the
law's own subject, found from the law's text:

- the 9 section-IV laws: break the `A.<fn>` the law is about;
- the 9 section-V laws: break the FOLD ARM the law reads the fold at.

## 2. FINDING ONE: THE MASK IS THE SAME TERM, SO FIVE LAWS CANNOT FAIL ON IT

`LAWS/alu.bend:29-33`:

```
def one() -> S.Sp:
  S.SpConst{S.SpInvalid{}, S.index()}

def zero() -> S.Sp:
  S.SpConst{S.SpInvalid{}, S.index()}
```

**`one()` and `zero()` are the SAME TERM.** MEASURED by the PROVEN kernel
(`bend --verdict` on a scratch law `one_is_zero: {A.one() == A.zero() : S.Sp}`)
— **`ALL PROOFS CHECK`**.

So `A.neg(a) == S.SpMul{a, A.one()}` and `A.neg(a) == S.SpMul{a, A.zero()}` are
the same statement, and the law's two sides name the SAME mask term: **no
change to the mask can break it.**

**FIVE LAWS ARE VACUOUS ON THEIR MASK**, and the gate names them:
`neg_is_mul_by_minus_one`, `cmp_ge_is_ne_of_cmp_lt`,
`cmp_le_is_ne_of_cmp_lt_swapped`, `cmp_eq_is_double_neg`, `not_is_ne_one`.

**AND THE VALUE IS NOT IN THE LANGUAGE.** `SpConst{v, dt}` carries the value in
`v: Sp`, and `one()` puts `S.SpInvalid{}` there — the spec's INVALID marker.
MEASURED: changing `one()`'s dtype to `boolean()`, and separately changing its
`v` to a `SpRange`, both leave **every law green**. The mask's identity, its
dtype and its value are all unpinned.

`LAWS/alu.bend:15-17` says the design out loud: the value "depends on the
dtype, so they are written here as `k`/`one`/`zero` and the dtype's bit pattern
is supplied at emit time by the C runtime." **So this is a PLACEHOLDER BY
DESIGN, not a typo** — and the honest reading is that these five laws pin the
STRUCTURE of the decomposition and say NOTHING about the mask. The laws'
names overclaim: `neg_is_mul_by_minus_one` cannot see the minus one.

**NOT A REGRESSION: the law's own subject still bites.** Breaking `A.neg` (making
it the identity) DOES redden `neg_is_mul_by_minus_one` — MEASURED, and the
tree's own `plant6_neg_identity` case agrees.

## 3. FINDING TWO: THIRTEEN ALU DTYPE ARMS ARE READ BY NO LAW

**MEASURED, ONE AT A TIME**: replacing each ALU op's dtype-fold arm
(`SpXor{a, b}: Sp.dtype(a)` -> `Some{boolean()}`, etc.) and re-running
`LAWS/PROOF-ALL.bend --check-only` leaves it **GREEN** for all thirteen.

| arm | read by |
|---|---|
| `SpRecip` `SpTrunc` `SpAdd` `SpMul` `SpMax` `SpMod` `SpIdiv` `SpXor` `SpOr` `SpAnd` `SpShr` `SpShl` `SpContiguousBackward` | **NO LAW** |
| `SpWhere` | `where_takes_the_second_operand_dtype` |
| `SpDetach` | `detach_preserves_dtype`, `detach_preserves_numel` |

**THE POSITIVE CONTROL IS MEASURED TOO**: breaking `SpDetach`'s dtype arm
reddens the gate naming `L.detach_preserves_dtype`, and breaking `SpWhere`'s
names `L.where_takes_the_second_operand_dtype`. So the arms that go red are
red because a law reads them, not because the fold is sensitive.

**THE CENSUS IS NOT "THE LAW NAMES THE OP".** `div_is_mul_by_recip` names
`SpRecip` in its right-hand side, and breaking `SpRecip`'s dtype arm does NOT
redden the gate — that law is about the STRUCTURE (`Mul(a, Recip(b))`) and
never reads the dtype. **MEASURED, and the gate's plant caught it**: the
first version of the census counted `SpRecip` as pinned, the plant's case 3
(`a PINNED arm must redden`) failed, and the census was corrected to ask
whether the law applies the FOLD **AT** that op.

**WHAT THIS COSTS.** tinyspec's dtype column gives every ALU op
`src[0].dtype` (`src[1].dtype` for Where). Thirteen of them have no law, so
the port may implement `SpXor`'s dtype as `src[1].dtype` and every law in the
book would still say `ALL PROOFS CHECK`.

## 4. THE GATE'S OWN CONTROL

`gates/alu-law-census-gate.py --plant` — four cases, all through the same
`check` the gate uses:

```
1 control          GREEN
2 neg mutated      RED  naming neg_is_mul_by_minus_one
3 pinned arm       RED  (SpWhere -> SOME PROOFS FAIL)
4 unpinned arm     GREEN  (SpRecip)
--plant: OK
```

Case 4 is the one that makes the gate's complaint falsifiable: if the gate
said "no law reads this arm" and breaking that arm DID redden the gate, the
gate would be wrong about its own population.

## 5. THE BASELINE, AND WHY THE GATE IS GREEN AT REST

A gate that is always red is not a gate (`checks/differ.py:814`). Both
findings are defects **that exist today**, so the gate compares the census
against `gates/alu-law-census.rows` and FAILS when the census gets WORSE.

**MEASURED IN BOTH DIRECTIONS:**

- a REGRESSION (a law stops reading an arm) -> **rc=1, `NOT OK: unpinned-arms:
  1 new -- SpWhere`**;
- an IMPROVEMENT (a law starts reading an arm) -> **rc=0** with
  `FIXED: unpinned-arms: 1 fixed -- SpContiguousBackward`;
- a broken tree -> **rc=3, REFUSED**, because the control copy is not green
  and every case below would be measuring the copy rather than the law.

**A HARNESS BUG WORTH RECORDING.** The first version of the reader did
`line.strip()`, which takes the trailing TAB of an EMPTY baseline row, so
`vacuous<TAB>` read as a bare `vacuous` and was skipped: an empty baseline
list became a MISSING KEY, and the census had nothing to compare against.
The reader now strips only the newline and the leading space.

## 6. THE TODO COUNT

| book | before | after |
|---|---:|---:|
| `tinybendygrad/PROOF.bend` | 18 | **18 (UNCHANGED, and unchanged on purpose)** |
| `tinybendygrad/PROOF2.bend` | 16 | 16 (untouched — a shared path) |
| `tinybendygrad/LAWS/PROOF-ALL.bend` | **0** | **0** |

**`PROOF.bend` is UNCHANGED.** This unit did not edit it: the 18 laws it
counts are proven in `PROOF2.bend`, and `LAWS.bend` and `PROOF2.bend` are
owned by others. The one change that WOULD have moved the number — making
`PROOF.bend` import `PROOF2.bend` — is a half-book boundary dressed as
progress, and the tree's own record says so.

## Files

- `gates/alu-law-census-gate.py` — the gate.
- `gates/alu-law-census.rows` — the declared census; `--refresh` is its only writer.
