# Which oracle is authoritative for `tinybendygrad/codegen/decomp/dtype.bend`

**Answer: `dd-oracle.py`. `dtype-oracle.py` should become a VIEW that prints the
denominator, and should never again be the thing a gate is wired to.**

Every number below is measured on the live tree with the pinned `.venv` interpreter
(3.12.10, `tinygrad` resolving to this repo's `tinygrad/__init__.py`), the port run
through `./bin/bend`, and all three lanes parsed with **rebase-gate.py's own `rows()`** —
loaded, not copied, because a second parser is a second opinion nobody checked and
`agent-core.md` records three false zeros from a parser that required `\s=\s` on lanes
that print `name=value`.

Reproduce: `.venv/bin/python .agents/slop/dd-truth.py --control`

---

## 1. The measurement, with its denominator

| lane | rows | shared with the port | disagreements |
|---|---|---|---|
| the port (`./bin/bend`) | **174** | — | — |
| `dd-oracle.py` | **416** | **174** | **19** |
| `dtype-oracle.py` | 356 (351 measured + 5 provenance labels) | **109** | **1** |

- `port ∩ dd-oracle = 174 = |port|`. **The port emits no row dd-oracle.py does not, and
  dd-oracle.py emits 242 rows the port does not.** The port's row set is a strict subset.
- `416 − 65 = 351`, and `dtype-oracle.py`'s printed names are **exactly** `dd-oracle.py`'s
  minus its 65-name `SKIP` set. Asserted by `dd-truth.py`, not assumed.
- So **172-vs-107 (now 174-vs-109) is entirely the `SKIP` set.** The two files do not test
  different things; one is the other with 65 rows deleted.

### The 242 rows only `dd-oracle.py` covers

`dd-oracle.py` prints 416 rows; the port emits 174. The 242 it covers and the port does not
are the whole of five families:

| family | rows | what it is |
|---|---|---|
| `f1..f4`, `g1..g7`, `h1..h4`, `k1..k3` + their `sig`/`n`/`k` | 71 + 36 + 44 | **`f2f` is not rowed at all.** dtype.py:101-125. 18 fixtures across fp8e4m3/fnuz/e5m2fnuz, f16/bf16/f32/f64, both directions, plus the three `NotImplementedError` refusals at dtype.py:125. |
| `fc1..fc8` + `sig`/`n`/`k` | 8 + 36 + 44 | **`f2f_clamp` is not rowed.** dtype.py:127-134. All 8 target dtypes × both source widths, plus the `sat=False` case. |
| `rn1..rn6` + `sig`/`n`/`k` | 6 + 36 + 44 | **`rne` is not rowed.** dtype.py:99. |
| `ri1..ri6` + `sig`/`n`/`k` | 6 + 36 + 44 | **`reindex` is not rowed.** dtype.py:14-18. |
| `df1..df5` + `sz`/`sig`/`n`/`k` | 5 + 5 + 36 + 44 | **`l2i_define` is not rowed.** dtype.py:83-86. |
| `c0..c7` | 8 | **`f2f_clamp`'s `mx`** — the value read back out of CPython's own graph. |
| `nlong*`, `nfloat*`, `ndtype*` (`=`, `r`, `o`) | 3 + 50 + 50 | the three **rule tables** (dtype.py:148, 181, 218) and their `early_reject` / matched-op sets. |
| `lgsp`, `lgtp` | 0 (now rowed) | were missing until this unit's fix — see §4. |

**`up`/`upp`/`upsig`/`upk` are in the port and agree** (`upsig` is in `SKIP` because it is
creation order).

**This is the bigger finding than the disagreement count.** 242 of 416 oracle rows have no
port row at all, and they are not random: they are `f2f`, `f2f_clamp`, `rne`, `reindex`,
`l2i_define` and the rule tables — i.e. **five of `dtype.py`'s ten public functions.** The
gate's 109-row denominator covers `l2i` and `unpack32` and nothing else.

---

## 2. Why 19 and not 1 — and why that is worse than "unchecked rows"

The 19 decompose exactly:

```
19 disagreements against dd-oracle.py
  1 gated by dtype-oracle.py   -> c7
 18 on rows dtype-oracle.py never prints
```

**And the 18 are not unchecked rows. They are rows the port emits with the WRONG value.**
`cvs()` intersects `set(port) & set(dd-oracle)`; all 19 names are in the port's 174. So for
`lgqk` the port prints a `k` row, `dd-oracle.py` measures it, the two differ, and the wired
lane never prints the name. The gate cannot go red on them because the name is not in its
lane — not because the row is absent from the port.

This is strictly worse than "unchecked". An unchecked row is a coverage gap and reports
itself as a denominator shortfall. **A suppressed disagreement is a known-wrong value that
the gate is structurally unable to see, and it reports itself as an agreement.**

### `SKIP` is not only creation-order rows

The previous `dtype-oracle.py` header said so. `dd-coverage.py` measures it:

- **57** of the 65 are creation-order rows (`sig` / `k` / `n` / `p`).
- **8 are BARE rows — the answer itself**: `lga`, `lgb`, `lge`, `lgq`, `lgr`, `lgs`, `lgt`,
  `lgu`. `lga` is `l2i(SHR, int, u32)`'s answer; `lgb` the zero-fill one; `lge` `MUL`;
  `lgq`/`lgr`/`lgs`/`lgt` the CDIV/CMOD ones. The old header admitted **one** of the eight
  (`lgu`). The other seven were silently classified as "creation-order".

`lgq`, `lgr`, `lgs`, `lgt` currently AGREE (they are bare, so `tree()`'s two levels match)
while their `k` and `sig` rows disagree. Suppressing a bare row that happens to agree today
is how a future regression in it stays invisible.

---

## 3. Does either oracle re-implement the port? **No — and this is measured, not read.**

`.agents/slop/dd-audit.py` wraps **every** entry point of `tinygrad.codegen.decomp.dtype`
with a counting proxy and *runs* both oracles:

| | `dd-oracle.py` | `dtype-oracle.py` |
|---|---|---|
| `l2i` calls | **1341** | **1341** |
| `f2f` / `f2f_clamp` / `rne` / `reindex` / `unpack32` / `l2i_define` | 18 / 26 / 16 / 6 / 3 / 5 | identical |
| rule tables read | 13 / 10 / 2 patterns | identical |
| own arithmetic on dtype.py's shapes (`2**e`, `max_exp`, `& 0xFFFF`, `>> 31`) | **0** | **0** |
| rows printed | 416 | 351 |

Neither hand-derives an expectation. **The header claim "nothing here is a reimplementation
of it" is true of both files.**

Two honest qualifications, both about `dd-oracle.py`:

1. **It projects, it does not reimplement.** Decision 1 monkeypatches `UOp.cast` and drops
   **281** promotion CASTS from the graph it reports, because `mixin/elementwise.py` is
   unported and the port's arena cannot contain them (measured by `dd-probe.py`, per-fixture,
   including 69 in `lgq` and 70 in `lgr`). Those are real CPython nodes, so `dd-oracle.py`'s
   rows are **CPython projected onto the port's buildable subset**. The projection is
   declared and justified, and it is the right call — but it means `dd-oracle.py` is *not*
   CPython verbatim either, and a reader deserves the number rather than the assurance.
2. **It does not mask the disagreement it is accused of masking.** With decision 1 disabled,
   `lg5`'s cone constants are `F(1333788672),F(0),C(0),C(-1)` — identical to the deleted
   view. The deletion removes 1 CAST elsewhere; the `F(1333788672)` CONST is tinygrad's own.
   So the `lg5k` disagreement is a **port** defect, not an artifact.

---

## 4. What was closed, and what was not

### Closed: `W2{ar, Cd.q0(c), 0}` — an arena index read as a value

`tinybendygrad/codegen/decomp/dtype.bend:1129-1130` (now `:1150-1153` after the comment
grew). `W2` is `{ar: O.Arena, lo: U32, hi: U32}` and **both `lo` and `hi` are arena
INDICES** — `W2.hi` is consumed by `l2i_shr`, `l2i_shl` and the final `WHERE` as
`Arena.op(ar, hi)`. Writing the literal `0` did not mean "high word is zero"; it meant
"high word is **arena slot 0**", and slot 0 is the arena's bottom node, whose label is
`NOOP`.

dtype.py:74 is `return r if op is Ops.CMOD else q`, and `q`/`r` are both `(z, z)`-shaped
2-tuples from dtype.py:62 — so the unsigned answer is `(q[0], q[1])` and `(r[0], r[1])`.

```python
    case True{}: W2{ar, Cd.q0(c), Cd.q1(c)}
    case False{}: W2{ar, Cd.r0(c), Cd.r1(c)}
```

This is the **fourth instance of the same species in this file**; the port's own comment at
`:1187-1192` already names it twice for `nr`/`nar`.

**Effect, measured:** `ALL PROOFS CHECK`; the port's row count went **172 → 174**
(`lgsp`, `lgtp` appeared — rows CPython emits that the port was silently not emitting, so
coverage rose and the denominator is honest); exactly **one** existing row moved
(`lgssig`, 10440 → 11016 chars); **nothing lost**.

**And it closed ZERO of the 18 disagreements.** Said plainly because that is the finding:
`lgtk` is still 3 constants against CPython's 66, and `lgtsig` still 57 cone nodes against
2184.

### Not closed, by family, with the CPython line

| # | rows | mechanism | which side is wrong |
|---|---|---|---|
| 1 | `c7` | declared refusal: port prints `refused:unported`, CPython `F(2139095040)` (f32 bits of `+inf`) | **neither — left alone as instructed.** dtype.py:131-134 |
| 2 | `lgu`, `lgun` | `l2i(CAST, f32→f32, a0, a1)` — dtype.py:35-38, the two-word float-source arm. Not ported. | **port.** dtype.py:35-38 |
| 3 | `lgqk`, `lgqn`, `lgqsig`, `lgrk`, `lgrsig`, `lgsk`, `lgsn`, `lgssig`, `lgtk`, `lgtsig` (10 of 18) | the 64-iteration restoring-division loop. CPython interleaves `C(i)` with `2**(i-32)` for i=63..33 (the `UOp.const(i, uint)` shift words of dtype.py:65 and the `shl(cond, i%32)` multipliers of dtype.py:68). The port emits one leading `C(64)` and then a bare run of powers of two — **it never emits the 31 `C(i)` shift words at all.** `lgt`'s cone is 57 nodes against CPython's 2184. | **port.** dtype.py:63-69 |
| 4 | `lg5k`, `lg5n`, `lg5sig` | dtype.py:33-34, `(uops[0] / 2**32)`. tinygrad rewrites `x / 2**32` as `x * RECIPROCAL(CONST_at_f32(2**32))` → **`F(1333788672)`** (0x4f800000 is exactly 2^32 in f32). The port builds the divisor at weakint/i64 → **`C(1:0)`**. One CONST/0 short in `lg5sig` follows. | **port.** dtype.py:34 |
| 5 | `lg1n`, `lg6n`, `lg9n` | `n` counts nodes interned during the fixture. Off by one in **three different directions** (+1, +1, +1 for the port against CPython's 10/4/17). `n` is a count, not an order, so these are real divergences. | **port.** dtype.py:41-49 |
| 6 | `lgvk`, `lgvsig`, `lgwsig` | three extra CONST/CAST nodes in the port's `l2i(CAST, uint→*)` cone | **port.** dtype.py:28-32 |

Rows 1-3 and 5 are unchanged by this unit's work. Rows 3 and 4 are the two families worth
opening next.

---

## 5. The control

Two, and both must be run by whoever adopts this.

**(a) The filter control — proves the number is a function of `SKIP`.**
`.agents/slop/dtype-oracle-MUTANT.py` is `dtype-oracle.py` with `SKIP` emptied and
**nothing else changed** (`diff` shows exactly that one block). `dd-truth.py --control`
runs it:

```
port vs MUTANT:  19 disagree of 174 shared
live filter   :   1 disagree of 109 shared
CONTROL PASSES: a filter that hides disagreements went red when it stopped hiding them
```

Without this, "1 disagreement" is compatible with "the filter works" and with "the filter
hides 18 defects", and nothing on the tree distinguishes them.

**(b) The port-edit control — proves the delta is mine and nothing else.**
`tinybendygrad/codegen/decomp/dtype.bend` was copied aside, the fix applied, the port run,
the file restored to its exact baseline hash, and the port run again:

```
reverted to baseline; hash 8886c0b7f862d57e13e11c52ee53f25a3305c839
diff port.BASELINE.txt port-revert.txt  ->  IDENTICAL
```

`ops.bend` is being edited by another agent and changed **three times** during this unit
(00:08:14 broke the typecheck with `match split_uop.sep.of(op, sep):` — a computed
scrutinee, which Bend 2.0.34 refuses — 00:09:42 restored it). Every number above was
re-measured after that settled; `dd-truth.py` refuses to report anything if the port lane
prints 0 rows, rather than printing a clean zero.

---

## 6. Recommendation to the gate's owner

`rebase-gate.py` / `rebase-gate-selftest.py` are another agent's files and were not edited.

1. **Re-wire `tinybendygrad/codegen/decomp/dtype.bend` from `dtype-oracle.py` to
   `dd-oracle.py`.** That is a one-line change in `ORACLE_CONFORMANCE` and it moves the
   lane from `1 of 109` to `19 of 174` — which is the truth. Expect it red.
2. **If a red gate on 16 unfixed rows is unacceptable right now, wire `dd-truth.py` as a
   second, diagnostic lane instead of `dtype-oracle.py`.** It reports both numbers and the
   decomposition, so "1 of 109" and "19 of 174" are visible in the same run.
3. **Whatever is wired, it must print the denominator.** `dtype-oracle.py` now emits five
   `dtype_oracle_*` provenance rows so its own output states `of=416`, `printed=351`,
   `suppressed=65`, `skip_names_unused=0` and
   `full_disagreements=19 (of which 18 are on rows this filter does not print)`. They are
   named so they cannot collide with a port row and so they can never be compared.
4. **Do not shrink `SKIP` to make the gate green.** Silencing a lane to keep a gate green
   is the failure this file exists to correct.