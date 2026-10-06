# bitcastrow — the `bitcast_dims` range fix, and the rows that can see it

`ONE JOB: a correct diagnosis in fold.bend was left unapplied because no row could see it.
Build the row, prove the diagnosis, then apply the fix.` — rows FIRST, then the fix.

## The finding that changed the answer

`bitcast_dims` truncated to U32 **three** times, not once, and the three have
**different** boundaries. `fold.bend`'s own comment named one:

| | where | bites from | named in the prior census? |
|---|---|---|---|
| **L1** | `H.lo32(i)` — the dim | `dim >= 2**32` | yes |
| **L2** | `U32.mul(i,inp)` — the product | `dim*inp >= 2**32` | yes |
| **L3** | `sint_of(q)` — the quotient | `dim*inp//out >= 2**31` | **NO** |

`fold.bend:511-512` said *"truncates to a U32 TWICE"* and named `H.lo32` and `U32.mul`.
It missed the third: `sint_of` is `H.i64_of_i32`, which **sign extends**, so every
quotient of `2**31` or more became a **negative dim**.

**L3 is inside the window the old comment called exact.** `dim=2**30, inp=2, out=1` has
`dim*inp == 2**31 < 2**32`, and answered `-2147483648` where CPython answers `2147483648`.

### And the previous census could not have seen it

`.agents/slop/trigger/bc-oracle.py` modelled the port's answer as a **Python int**:

```python
def port(dim, inp, out):
    i = dim & M32; n = (i * inp) & M32
    return (n % out != 0, n // out)          # <-- never goes through sint_of
```

So it never went through `i64_of_i32`'s sign extension. Its "the boundary band lands on
12 agree / 12 DIFFER exactly as predicted" was true **of its own model** and false **of
the port** — the `nv_query_litter` failure agent-core.md records, where a port and an
oracle both wrong is agreement rather than corroboration. **Its 80 divergent rows were
80 of a larger set.** Its `(raises, value)` shape also discards half the answer on a
refusal, which is the name-comparing harness this project has been bitten by twice.

## Why this universe and not the threshold that failed

A row at `2**32//inp` tests **one** of three defects. The bands are in
`table.py`; the derivation is:

| band | rows | what it pins |
|---|---|---|
| **A** | 9 | the interior — all agree, **two are refusals**, so `some_if` is pinned too. Without a band of agreement a universe of failures cannot tell a correct fix from one that refuses everything. |
| **B** | 8 | the `U32.mul` boundary, one step either side, per `inp`, `out=8` so L3 is slack. `dim*inp == 2**32` wraps to 0 — a **refusal** where CPython has a shape. |
| **C** | 6 | the `sint_of` boundary: `out=1`, `dim*inp == 2**31`. The band the prior census could not see. |
| **D** | 8 | the `H.lo32` boundary: `dim >= 2**32`. The `+8`/`+64` rows answer a **small positive** number where CPython has the full dim, so the failure does **not** look like a zero. |
| **E** | 2 | L1 and L3 composing. |
| **F** | 2 | `out == inp`, the `same` arm, which never reaches the arithmetic. |
| **G** | 4 | the **fix's own** window edge at `dim*inp == 2**63`. |

Every fixture is a **two-axis** shape `[1, dim]`, so a row carries the preserved prefix
*and* the scaled last dim; `drop_last` dropping the wrong axis moves every row.

## Discrimination

The standard: **a row that passes on the agreeing and fails on the disagreeing.**

```
PRE-FIX-vs-CPYTHON:  39 rows compared, 20 MOVED
POST-FIX-vs-CPYTHON: 39 rows compared,  2 MOVED
```

* **19 rows** agree on both sides — the interior and the refusals.
* **20 rows** failed before and are now either equal or pinned.
* **2 rows** still differ, and they are the *predicted* survivors, not surprises.

## Plants and disarms, by row NAME

Diffing whole `name=value` lines, as a **multiset** — `fold.bend` emits
`lf_sub_int32_-3_4` **twice** and a dict collapsed the pair, so the lane counted 333
for 334 rows.

```
PLANT-B  divisor -> 1        17 MOVED
PLANT-A  multiplicand -> 1   17 MOVED
PLANT-C  sign extension only 11 MOVED
DISARM                      0 MOVED
DISARM-2                    0 MOVED
```

Same count, different sets: A and B both move 17 and **share no band C**, and C moves
11 including all three `C_c_*_at` rows. That is the evidence the rows carry more than
one signal.

**Plant C's first attempt did not compile** (`H.i64_to_u32` does not exist) and the gate
went red with `bend produced no --check-only output in 25 tries (the stack flake)`. That
red was **a broken build, not a row movement** — the same shape as
`bounded.py` exit 3 being ambiguous. The plant was rewritten using names that exist.

## The fix

`tinybendygrad/uop/fold.bend:513-518` and `:555-558`. `i64_mul` / `i64_mod` / `i64_div`,
and `O.SI{quotient}` rather than `sint_of`. The stale warrant paragraph is **replaced**,
not annotated. The three changed defs are internal to `bitcast_dims`; `sint_of` has 29
other callers, untouched.

**The new window is `dim*inp < 2**63`, NOT `2**64`**, and that is `helpers.bend`'s own
divider rather than a caution: `i64_mul` wraps mod `2**64` and `i64_divmod` reads bit 63
of the dividend as a sign. **The fix moved the window; it did not abolish one**, so the
two rows at the edge are **pinned on both sides** in the gate, not excluded.

## The 334

`fold.bend`'s own rows, before and after the fix:

```
FOLD-334-after-fix: 334 rows compared, 0 MOVED
```

**Byte-identical.** `fold.bend --check-only` answers `ALL PROOFS CHECK`.

## Non-emptiness

Both the row and the harness are non-empty **by construction**:

* a row is `raise` or `[dim,...]` — the two are ONE string, so a row cannot pass on the
  flag while the value moved;
* `bc-diff.py` asserts both lanes are non-empty **before** any comparison, and
  `bc-u32-gate.py` refuses a lane that is all-refusals or all-shapes. Two empty dicts
  compare equal; that is the `${=SUB}` failure `gates/README.md` records.

## Files

| path | role |
|---|---|
| `gates/bc-u32-gate.py` | the gate — 39 rows, 3 lanes, 2 pinned divergences |
| `.agents/slop/bitcastrow/table.py` | the ONE fixture list + the port's semantics as code |
| `.agents/slop/bitcastrow/bc-gen.py` | emits BOTH lanes from the table |
| `.agents/slop/bitcastrow/bc-rows.bend` | generated port driver |
| `.agents/slop/bitcastrow/bc-oracle.py` | generated CPython oracle |
| `.agents/slop/bitcastrow/bc-diff.py` | whole-line multiset diff, named movers |

## Not settled

**A dim above `2**63/inp` is still wrong.** Closing it needs a **checked** product:
`i64_mul` wraps and cannot report the overflow. `mm.u64.mul`'s `None` is the only
overflow signal in this tree a caller can turn into a refusal, and today it is
`PInf`/`NInf`. This is not one line and it is not mine.

`tinybendygrad/uop/fold.bend:557-558`, `.agents/slop/bitcastrow/table.py` band G.

## Never committed

Per brief. The coordinator verifies and commits.