# 03 — "60/60 fields agree"

**VERDICT: CAN-FAIL** for the comparison. **CANNOT-FAIL** for two components of
the printed header, and one hazard is **ARMED** with its detector **DEAD CODE**.

## Subject and instrument

- **Subject:** the PORT's schedule output for six specs — what
  `./bin/bend .agents/slop/sched-fixture.bend` prints, 10 fields × 6 specs.
- **Instrument:** `.agents/slop/sched-cmp.py`. Reproduced baseline, run twice:

```
# specs_attempted=6 specs_scheduled=6 fields_compared=60 fields_agree=60 fields_disagree=0 port_only=0
# denominator: 60 fields = 6 specs x 10 fields
```

## Plant 1 — the comparison CAN go red: **60 → 59**, rc=1

A copy of `sched-port.txt` with `matmul_ktop=5` → `9`:

```
# fields_compared=60 fields_agree=59 fields_disagree=1 port_only=0
DISAGREE matmul_ktop cpython=5 port=9
rc=1
```

## Plant 2 — the PORT ITSELF cannot move the number

`sched-cmp.py:101` is `open(os.path.join(HERE, "sched-port.txt"))`.
`port_rows()` **never runs the port.** It spawns no process and never touches
`tinybendygrad/`. The snapshot is produced by a *separate* command
(`sched-fixture.py:40`: `./bin/bend .agents/slop/sched-fixture.bend | tee sched-port.txt`).

Measured, in this order:

1. **Fidelity first.** A full `$TMPDIR` copy (`$TMPDIR/p2root/.agents/slop/` +
   `$TMPDIR/p2root/tinybendygrad/`, because the fixture's imports are
   `./../../tinybendygrad/...`; a *flat* copy cannot resolve them and prints
   `SOME PROOFS FAIL` with 0 rows — agent-core's `$TMPDIR` trap, hit and measured)
   produced output **byte-identical to the live `sched-port.txt`**. The snapshot
   is **fresh**: its sha256 of non-blank lines is
   `207ee494251e3dcde90ef2b03e5709899ff39604885b7bedad06b3beadd34817`, which is
   exactly the sha published in `sched-stage2.md`. **This is a real positive and
   it should be said plainly.**
2. **The plant.** `Lin.out` → `List.drop(&2, U32, out, 1n)` in the **copy** of
   `tinybendygrad/schedule/__init__.bend`. 60 rows still produced; content
   differs from clean.
3. **The question.** `sched-cmp.py`, run as committed from the live tree:

   ```
   # fields_compared=60 fields_agree=60 fields_disagree=0 port_only=0     rc=0
   ```

   **The port regression is invisible.** Feeding the planted snapshot in by hand
   gives `fields_agree=24 fields_disagree=36 rc=1` — so the comparator is not the
   problem; the *staleness window* is. **`60/60` cannot detect a port regression
   unless a human remembers to regenerate `sched-port.txt`. There is no freshness
   check.** This is the `schedule_cache` hazard in its purest form: a memoized
   value is measured by its cache, not by its code.

## Two literals in the number's own header are falsifiable

`sched-cmp.py:115` prints `specs_attempted=6 specs_scheduled=6` as **string
literals** inside the f-string; only `fields_compared`, `fields_agree`,
`fields_disagree` and `port_only` are computed. `sched-oracle.py:267` computes
the same pair for real (`specs_attempted={len(SPECS)} … scheduled_calls={…}`).

**Plant 3** — add a seventh spec (`("seventh", s_chain)`) to a copy of
`sched-oracle.py`'s `SPECS`, with its ten fields in the snapshot:

```
# specs_attempted=6 specs_scheduled=6 fields_compared=70 fields_agree=70 fields_disagree=0 port_only=0
# denominator: 70 fields = 6 specs x 11 fields
rc=0
```

**Seventy fields from seven specs; the header still says six, and the denominator
line prints `6 specs x 11 fields` — which is 66, not 70.** The per-spec width is
`n // 6`, integer division against a literal. So `specs_attempted=6` and
`specs_scheduled=6` are **CANNOT-FAIL**: they are literals, and a spec that fails
to schedule would not change them either — it would only shrink `fields_compared`.

## The hazard is ARMED and its detector is DEAD CODE

`sched-cmp.py:40`: `def dig(name): return DIG.get(name, 0)`. The module's own
docstring says: *"An op with no code becomes 0, on BOTH sides, so an op the port
has not ported shows as an agreement about the digit 0 — which is why the census
of uncoded ops is printed rather than left implicit."*

**That census is dead code.** `sched-cmp.py:132-136`:

```python
uncoded = collections.Counter()
for k, v in DIG.items():
    if v == 0:
        continue
```

`uncoded` is never written to and never printed. `DIG` has no zero-valued entries
(measured: `none`), so the loop is a no-op over 17 items. Nothing in the output
mentions "uncoded". **The docstring asserts a safety property that the code does
not implement.**

And the property is not hypothetical. Measured by walking
`sink.toposort()` for all six specs: **18 distinct op names, of which FOUR are
not in `DIG`** —

```
CMPLT x4, AND x4, CMPNE x2, WHERE x2        (12 nodes)
```

The packer is not injective over uncoded ops:

```
pack(['SHR','SHL'])   = 0
pack(['NOPE','WHAT']) = 0
pack([])              = 0        <- an EMPTY src sequence
pack(['CAST'])        = 17
```

**So a spec whose kernel srcs were all unported ops, and a spec with an empty src
list, pack to the same value, and `sched-cmp.py` would report AGREE on both.**

Measured honestly: **the hazard is ARMED but DORMANT in the packed slices.** The
three packed fields read only `k.src` (a kernel's direct srcs), `k.src[0].op.name`,
and the first STORE's value op; I checked each of those slices for all six specs
and **no uncoded op appears in any of them**. So no *currently reported* value is
wrong. But it becomes live the moment a spec puts a comparison op directly under
a kernel src, and the instrument that was written to say so is a loop that
discards its result.

This is agent-core's "three functions that were written, commented, and never
called", reproduced in the one component of this harness whose docstring claims
the check exists.

## The honest summary

| component | verdict |
|---|---|
| `fields_agree` / `fields_disagree` vs CPython | **CAN-FAIL** (plant 1: 60→59, rc=1) |
| the comparison itself, against a mutated port | **CAN-FAIL** (24/60 when the mutated snapshot is fed in) |
| sensitivity to a port edit *without* regenerating the snapshot | **CANNOT-FAIL** — reads a static file, spawns nothing |
| `specs_attempted=6`, `specs_scheduled=6` | **CANNOT-FAIL** — string literals; falsified to 70-from-7 |
| the `6 specs x N fields` denominator | **CANNOT-FAIL** — literal 6 and integer division |
| the "census of uncoded ops" the docstring promises | **CANNOT-FAIL** — dead loop; hazard ARMED (4 uncoded ops, 12 nodes) |

## Reproduce

```
env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/audit/sched-cmp-audit.py
env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/audit/sched-cmp-audit2.py
```

Plant 2 compiles `tinybendygrad/` twice in `$TMPDIR`; budget ~5 minutes.
The live tree is never written to.