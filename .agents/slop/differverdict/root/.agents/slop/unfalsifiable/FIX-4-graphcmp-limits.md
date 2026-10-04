# Fix 4 — `graphcmp-LIMITS.md`'s own denominator, and the census's vocabulary

Harness: `graphcmp-opcensus-plant.py` in this directory. Transcript:
`graphcmp-opcensus-plant-RESULTS.txt` beside it.

## The denominator the file publishes about itself

`graphcmp-LIMITS.md` said:

```
(CROSSED THROUGH IN ROUND THREE, and these are the ten: NOOP, CALL, LINEAR, AFTER,
 END, IF, ENDIF, BACKEDGE, LOAD, STORE -- every one of them from `lin`/`loop`/`gate`)
```

Ten named, and `CMPLT` was not among them. **MEASURED, it is eleven.**

Which graphs reach each, asked **through the census itself** —
`census(G.emit_py(g, None))["ops"]`, the same call the oracle makes at
`graphcmp-oracle.py:108`:

```
NOOP ['loop']        CALL ['loop']      LINEAR ['gate']    AFTER ['loop']
END  ['gate','lin']  ENDIF ['gate']     BACKEDGE ['loop'] LOAD ['lin','loop']
STORE ['gate','lin','loop']             CMPLT ['gate','loop']
```

Eleven reached, ten named. The file was short by exactly the op `CMPLT`.

**Why through the census and not a second walk:** my first version of this harness
walked `sink.toposort(...)` itself. That is a *second reader* of the corpus, which is
the defect class this whole exercise is about — it is how `222`, and the 227/224/221
split, and the forked-reader counts all arose. The harness now calls the same function
the oracle calls, so the eleven is verified against the census rather than against me.

**The fix, and the guard.** The list now names eleven including `CMPLT`, and the file
says `eleven`. That is a prose edit, which fixes today's number and prevents nothing.
So the harness checks the file against itself on every run:

- the claimed count word is compared against the number of names beside it
  (`eleven` vs `11` → CONSISTENT; before the edit, `ten` vs `11` → INCONSISTENT);
- every named op is required to be an `Ops` member;
- any op reached by the corpus but absent from the list is printed as
  `REACHED BUT NOT NAMED`, which is the sentence that would have caught `CMPLT`.

Two of my own bugs here, both caught by the harness rather than by me, both the same
shape as the defect under repair:

- the name list was extracted with `\b[A-Z][A-Z_0-9]{2,}\b`, which needs three
  characters and **silently dropped `IF`**, reporting *nine* names for a list the file
  called ten. A verification harness that under-reports is worse than none.
- the earlier `emit_bend` monkeypatch patched a *second, separately loaded copy* of
  `graphcmp.py`, so the plant never ran and reported a green 34. The harness now
  imports `graphcmp` under the name the oracle itself imports, so there is one module.

## The vocabulary: `N of 77` accepted names outside `Ops`

`tot_ops` (`graphcmp-oracle.py:111`) is a `set[str]` of whatever `unchunks(ln)[1]`
yields, from **both** sides. Nothing asserted those names were members of `Ops`.

**The fix** (`graphcmp-oracle.py`, after the `NOT REACHED` line) computes
`known_ops = {o.name for o in G.Ops}`, and if `tot_ops - known_ops` is non-empty it
appends to `bad` — which the SELFCHECK prints and which sets rc=1 — and prints the
offending names on the census's own header line:

```
# OP NAMES ALL IN Ops: 34/34   (the census's vocabulary is verified against Ops, not assumed)
```

### PLANT — before / after

| | BEFORE | AFTER |
|---|---|---|
| `distinct ops` | 34 | **35** |
| vocabulary line | **(absent)** | `OP NAMES ALL IN Ops: 34/35   UNKNOWN: ['INVENTED']` |
| SELFCHECK | `OK` | **`FAIL`** |
| rc | **0** | **1** |
| the bad line | — | `the op census counted 1 name(s) that are NOT members of Ops, so '35 distinct ops' is not a count over the 77-op vocabulary: ['INVENTED']` |

### DISARM — nothing invented

`34 distinct ops`, `34/34`, `SELFCHECK OK`, rc=0, identical to the baseline on all
three of count, verdict and rc.

### How the planted line is built, and the two failures on the way

The wire is **length-prefixed** (`5:ALLOC`), not `key:value`.

1. First attempt: wrote `5:INVENTED`, keeping the old length. `unchunks` then read the
   next token as a length and raised `ValueError: invalid literal for int() ... 'TED 3'`
   — and because `emit_bend`'s own re-run guard swallowed the failure and reported the
   pre-plant count, **the plant read as a green 34**. The length had to be rewritten as
   `8:INVENTED`.
2. Second attempt: rewrote the id field as `i9999` without its length prefix, giving
   the same class of desync (`'999 8'`). Fixed to `5:i9999`.

Both times the count did not move, and both times the harness said so explicitly
rather than reporting agreement. The assertion `unchunks(out[-1])[1] == name` now runs
on every plant, so a line that does not parse is a loud failure, not a quiet 34.

### Why the plant is on the PY side, not the bend side

`emit_bend` spawns `./bin/bend` on `graphcmp.bend`, which imports
`tinybendygrad/uop/ops.bend`. **That file is mid-edit by the unit that owns it** and is
broken right now: its first line reads `set_end_none=Ops.AFTER(Ops.BUFFER Ops.STORE)`
rather than `ALL PROOFS CHECK`, so `graphcmp.bend` answers `SOME PROOFS FAIL / Error: -
expected : n` and `emit_bend` raises after its five attempts.

Planting `emit_py` — pure Python — measures my change independently of another unit's
mid-edit. Both sides feed the same `census()`, so the code path under test is the same
one a bend-side plant would take. Recorded as a wall, not edited around.

## Scope note

`.agents/slop/graphcmp-oracle.py` is not in the brief's "Yours" list. It is edited
anyway because the brief's Fix 4 says *"make the census reject a name it cannot
resolve"*, and the census lives there and nowhere else. The edit is three lines of
guard plus its comment, appended after the existing `NOT REACHED` line, and it changes
no number on a clean corpus (`34 distinct ops`, `43 of 77`, `SELFCHECK OK`, rc=0 — all
unchanged). It is not in the DO NOT TOUCH list. Flagging it explicitly rather than
quietly widening scope.