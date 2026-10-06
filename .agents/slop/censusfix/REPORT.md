# censusfix — an oracle patched to accept the flattened device tuple the port stopped emitting

Unit: `.agents/slop/graphcmp-oracle.py` + `.agents/slop/selfcheck/plants.py`. Read `AGENTS.md`.
**`bend` was NOT run** (another unit holds it), so the census reproduction replaces the bend side
with the py side (the `--row` path in `plants.py`); the tokens below are the census's own.
**I did NOT touch** `checks/`, `gates/`, `AGENTS.md`, `tinybendygrad/`, `runs/graphcmp/D/`,
`graphcmp.py`, or `graphcmp.bend`. **I did not commit or `git add`.**

**Files I edited (3):** `.agents/slop/graphcmp-oracle.py`, `.agents/slop/selfcheck/plants.py`,
`.agents/TOOLS.md` (the ledger rows the change invalidated).

---

## 1. It REPRODUCES. The tokens, before and after

`census()` over the current (`adevfix`) corpus, bend side replaced by py (`.venv/bin/python
.agents/slop/selfcheck/plants.py --row`; raw outputs in `before-row.out` / `after-row.out`):

| state | `allred` row (field: arg-atoms) | corpus-wide line | selfcheck | rc |
|---|---|---|---|---|
| BEFORE | `allred  9/9 ok 7 DNOSXabilnrs …` | `… an unmapped value: n)` | `# ORACLE SELFCHECK: FAIL` + `#   unmapped arg atom letters: n` | **1** |
| AFTER | `allred  9/9 ok 7 DNOSXabilrs …` | `… an unmapped value: none)` | `# ORACLE SELFCHECK: OK` | **0** |

The arg itself: `ALLREDUCE arg = al(OADD,n(sCPU,sCPU))` (`allred-arg.out`). The leaked letter is
`n`, the tuple opener, exactly as the brief predicted.

## 2. What `PAYLOAD_LAST_FIELD` did

`graphcmp-oracle.py:54` (BEFORE), `PAYLOAD_LAST_FIELD = ("al(",)", read by `atoms()` at `:91-95`:

```python
for p in PAYLOAD_LAST_FIELD:
    if arg.startswith(p):
        head, _, payload = arg.partition(",")
        lead = payload[:1]
        return _atoms(head) | ({lead} if lead.isalpha() else set())
```

For `al(`, it split at the FIRST `,` and kept only the field's first letter, DISCARDING everything
after it. It changed exactly one census decision: `tot_atoms` (the reached arg-atom letters), and
through it the `unknown = tot_atoms - ATOMS - COMPOSITE` check at `:283`/`:336-337` that drives
`# ORACLE SELFCHECK` and the exit code. It was written to hide the `C` leaked by the FLATTENED
`al(OADD,sCPU,CPU)`.

**The defect note it refers to** — the only `DEFECT 28` notes in `.agents/slop/` are the oracle's
own and two later citations; the note is in `.agents/slop/todo2/tasks.idx.tsv:1306`:

> **DEFECT 28 — a device NAME counted as an atom letter.** `al(OADD,sCPU,CPU)` is the arg of a …

and, restated with the measurement, `adevfix/REPORT.md:119`:

> `graphcmp-oracle.py:54` `PAYLOAD_LAST_FIELD = ("al(",)"` … `atoms("al(OADD,sCPU,CPU)") ==
> {"a","O","s"}` (the flatten the hack exists for) but `atoms("al(OADD,n(sCPU,sCPU))") ==
> `{"a","O","n"}` — and **`n` is neither an atom nor a composite prefix**.

## 3. Which side was wrong → DELETE the hack

**The census was right and the hack was wrong.** `n(` is the generic tuple opener `tup()` emits
(`graphcmp.py:383-384` `return "n(" + ",".join(xs) + ")"`), and the scan ALREADY reads it: `n` is
always followed by `(`, and the offset-0 rule requires the letter to be followed by alnum,
underscore, or end-of-string (`graphcmp-oracle.py:70-71`), so `n` is never counted. **The prefix
table does not need `n(`:** `G.COMPOSITE` is `("P(", "al(", "cF(", "cI(", "in(", "kI(", "pI(",
"rd(", "rg(", "wm(")` (`graphcmp.py:336`) and `G.ATOMS` has no `n` (`:324`) — and it does not need
it, because a tuple opener leaks nothing. Measured, `_atoms` (the scan, no form knowledge) over the
whole current corpus: `unknown` is **EMPTY**. So the fix is to delete `PAYLOAD_LAST_FIELD`, collapse
the `atoms`/`_atoms` pair into ONE scan, and replace the DEFECT-28 selfcheck block with assertions
for the two REAL device arms (`sCPU` and `n(sCPU,sCPU)`).

**A hack removed reveals its whole population, and here it is one letter.** The hack's population
was the flatten's `C` (absent from the corpus) and it additionally INTRODUCED `n`; without it,
nothing leaks. There is no second real unmapped atom behind it.

## 4. `plants.py` plant2 was guarding the HACK

Plant2's pre-fix beats asserted `hasattr(o, "PAYLOAD_LAST_FIELD")` and
`atoms("al(OADD,sCPU,CPU)") == {"a","O","s"}` — i.e. it PASSED only while the hack was present.
Measured on the pre-fix oracle: **plant2 GREEN**; on the fixed oracle with the old beats it would
be RED. So plant2 tested the hack, not the census. **A PLANT THAT GUARDS A HACK GUARDS THE WRONG
THING.**

Plant2 now tests the grammar: the nested `al(OADD,n(sCPU,sCPU))` reads `{a,O,s}` (the `n` is NOT an
atom), the 4-element tuple behaves the same, a BARE `al(OADD,CPU)` STILL counts `C`, the FLATTENED
`al(OADD,sCPU,CPU)` is now **REJECTED** (its `C` leaks), a plain `ParamArg` scan stays precise
(`{i,D,s,S,b}`, no longer a comparison-with-itself), and `C ∉ ATOMS`. Measured movement:

```
POST-FIX plant2 -> GREEN        PRE-FIX (git show HEAD:…, ORACLE_UNDER_TEST) plant2 -> RED
```

and `ORACLE_UNDER_TEST` on the pre-fix copy fails 4 of 6 beats (n counted, 4-tuple, flatten leak,
`C`-not-in-ATOMS); the two passes are the beats that were TRUE on both (bare `C`, ParamArg).

## 5. What MOVES

`checks/differ.py` `PINS` (**not edited**):

* `:234` `"census-rc": "rc=0"` — with the hack the run wrote `census-rc=rc=1`; after the fix the
  census returns **rc=0**. Pin goes RED → GREEN.
* `:242` `"oracle-selfcheck": "# ORACLE SELFCHECK: OK"` — with the hack `FAIL`; after **OK**.
  Pin goes RED → GREEN.

`checks/corpus-figure.py` (**not edited**): imports `differ.PINS` and compares all of them; its
`RUN HEALTH : OK` needs those two PINS green (they are again) **and** a re-taken
`runs/graphcmp/D/D0-run-summary.txt`.

`runs/graphcmp/D/` (**not edited**, committed artifact is from `12:50`, i.e. pre-`adevfix`):
`D0-coverage-census.txt:4` reads `allred 9/18 BAD … [PY-BEND OPs DIFFER …]`, `:57`
`# ORACLE SELFCHECK: OK`, `:32` `… an unmapped value: none`; `D0-run-summary.txt:18`
`census-rc=rc=0`, `:17` `oracle-selfcheck=# ORACLE SELFCHECK: OK`. That file was taken before the
`n(...)` normal form landed, so it cannot show the defect; a fresh run with `adevfix` + this fix
would read `allred 9/9` (py side MEASURED; bend lane **unmeasured** here), selfcheck OK, rc=0 —
but `graphs=25` vs the 34-graph corpus keeps `corpus-figure` at `RUN HEALTH : FAILED` until the run
is re-taken (adevfix §6).

## 6. Verdicts

* Fix VERIFIED statically + by the census (no `bend`): census `rc=0`, `ORACLE SELFCHECK: OK`,
  no `unmapped` line; all three plants PASS (see `plants-postfix.out`).
* The bend lane's `VERDICT: AGREE 9/9` on `allred` is **UNMEASURED** — `SKIP`/`DEAD`/`REFUSED` are
  not passes, and only `bend` settles it.
