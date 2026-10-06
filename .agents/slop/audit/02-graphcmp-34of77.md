# 02 — "34 of 77 ops"

**VERDICT: CAN-FAIL** — the corpus plant moved it 34 → 23. **But the denominator
half is blind in two specific ways, and the oracle's own `rc` cannot see either.**

## Subject and instrument, stated separately

- **Subject:** which of tinygrad's 77 `Ops` the sixteen-graph corpus reaches.
- **Instrument:** `.agents/slop/graphcmp-oracle.py`'s `main()`, which prints
  `# TOTAL: 16 graphs, 189 nodes per side, 34 distinct ops: ...` and
  `# NOT REACHED (43 of 77): ...`.

The audit imports that live module by path and calls its **real** `main()`,
capturing stdout, so the number read here is the number it prints. No file under
`.agents/slop/` was edited; every case is an in-process monkeypatch restored in a
`finally`.

**The denominator is measured, not transcribed.** `len(list(Ops))` = **77**,
from `from tinygrad.uop.ops import Ops`, run twice: 77, 77.

## What the instrument actually read — read from source, not prose

`graphcmp-oracle.py`:

```
line 110   tot_ops |= py["ops"] | bd["ops"]     -> "34 distinct" is a UNION
line 111   tal.update(py["per_op"])            -> the per-op table is PY SIDE ONLY
line 112   tot_nodes += py["nodes"]            -> "189 nodes per side" is PY SIDE ONLY
line 178   NOT REACHED = len(list(Ops)) - len(tal)   -> "43 of 77" is PY SIDE ONLY
```

**The two halves of the printed ratio are built from different sides.** `34` is
`py ∪ bend`. `43` is `77 − |py ops|`. They agree here only because py and bend
happen to reach the same 34 ops — measured: `py_only == union`, i.e. every op
py reaches, bend reaches too. That is a fact about this corpus, not a property of
the instrument, and it is not asserted anywhere.

## Plants and disarm

| # | Plant | Printed number | Moved? |
|---|---|---|---|
| — | **BASELINE** | 16 graphs, 189 nodes/side, **34** distinct, 43 not reached, SELFCHECK **OK**, rc=0 | — |
| 1 | **SUBJECT:** drop `lin`, `loop`, `gate` from `G.GRAPHS` | 13 graphs, 104 nodes/side, **23** distinct, 54 not reached | **YES 34 → 23** |
| 2 | **PORT DEAD:** `emit_bend` returns `[]` for every graph | 16 graphs, **189 nodes per side**, **34** distinct, 43 not reached, SELFCHECK **OK**, rc=**0** | **NO** |
| 3 | **PORT INVENTS:** bend emits a well-formed wire line with op `INVENTED` | 16 graphs, 189 nodes/side, **35** distinct, 43 not reached, SELFCHECK **OK**, rc=0 | **YES 34 → 35** |
| D1 | **DISARM:** `emit_py` returns `[]` for every graph | 16 graphs, **0** nodes/side, **34** distinct, **77** not reached, SELFCHECK **OK**, rc=0 | NO (on `distinct`) |

Plant 1 is the required plant: the number is a fact about the corpus, and it
moves when the corpus changes.

### PLANT 2 — `34` and `189 nodes per side` both survive a completely dead port

With the bend side emitting **zero nodes for all sixteen graphs**, the oracle
prints `189 nodes per side`, `34 distinct ops`, `NOT REACHED (43 of 77)`, and
**`ORACLE SELFCHECK: OK` with rc=0**. `graphcmp-run.sh` step 11 records
`census-rc=rc=0` and its run summary reports it, so the orchestrator's rc channel
is green too.

Two reasons, both read from source:

1. **`tot_nodes += py["nodes"]` (line 112).** The words "per side" are a claim
   the code does not make. With one side dead the label reads `189` while the
   table beneath it reads `189/ 0  BAD`.
2. **`bad` is fed by exactly three assertions, all about `atoms()`**
   (`graphcmp-oracle.py:144,146,148`). The per-graph `PY-BEND OPs DIFFER` string
   is *printed* at line 118 and is **never appended to `bad`**. There is no
   assertion that `py["nodes"] == bd["nodes"]`.

This is exactly the brief's class, with a twist: the instrument is not lying,
it is printing a py-side quantity under a both-sides label, and its own exit
status does not carry the disagreement.

### PLANT 3 — the "of 77" set has no membership check

`34 → 35` with `INVENTED`, which is not a member of `Ops`. `tot_ops` is a
`set[str]` of whatever `unchunks(ln)[1]` yields; nothing asserts
`tot_ops <= {o.name for o in Ops}`, and SELFCHECK stays OK. So **"34 of 77" is a
union of two self-reported name sets with no ground-truth membership test.** On
this corpus it happens to be right because every name in it is real, but the
number cannot tell you that.

### DISARM 1 — `34` also survives a dead **py** side

`emit_py → []` leaves `34 distinct ops` standing (the bend union carries it) and
only moves the complement to `77 of 77`. Combined with PLANT 2: **the `34` is
robust to the death of either side of the instrument.** That is the property a
coverage number should *not* have if it is meant to say "the port has been
exercised across 34 ops".

## Two defects found in the published denominator

1. **`graphcmp-LIMITS.md:431-432` undercounts its own ops by one.** It says the
   ten ops "CROSSED THROUGH IN ROUND THREE" from `lin`/`loop`/`gate` are
   `NOOP, CALL, LINEAR, AFTER, END, IF, ENDIF, BACKEDGE, LOAD, STORE`. Measured
   by asking CPython which graphs reach each op:

   ```
   CMPLT   ['gate','loop']     IF      ['gate']      END    ['gate','lin']
   ENDIF   ['gate']            BACKEDGE['loop']      LOAD   ['lin','loop']
   STORE   ['gate','lin','loop'] CALL ['loop']       LINEAR ['gate']
   NOOP    ['loop']            AFTER   ['loop']
   ```

   **Eleven ops, not ten. `CMPLT` is missing from the list** — and PLANT 1
   measures the loss as exactly those eleven. The file that publishes the
   denominator miscounts it by one.

2. **"189 nodes per side" is a py-side count** (see PLANT 2). The committed
   artifact `runs/graphcmp/D/D0-coverage-census.txt` does read `189/189` for
   every graph, so the label is true *today*. It is true by luck, not by
   construction.

## What this number is and is not

- It **is** a real fact about the corpus, and it moves when the corpus moves.
- It is **not** a statement that the *port* reaches 34 ops: PLANT 2 shows the
  number survives the port emitting nothing.
- It is **not** gated on those names being `Ops` members.

## Reproduce

```
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python \
  checks/graphcmp-census-audit.py
```

Runs the oracle's real `main()` five times: baseline, three plants, one disarm.
Roughly 3 minutes.