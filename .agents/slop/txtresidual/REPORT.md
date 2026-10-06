# The residual `.txt`: two forced plants and one deliberate 0-byte orphan get declarations; the fourth was a WRITER

**MEASURED 2026-10-06, this tree, `.venv/bin/python checks/no-txt.py`; `.venv/bin/python` throughout; no `bend` was started.**

## 0. Denominator, before -> after

| state | HARD | excused | rc | command |
|---|---:|---:|---:|---|
| plancarve's own reading | 3 | 139 | 1 | `.venv/bin/python checks/no-txt.py` |
| plancarve's FINAL reading (it says so) | 4 | 139 | 1 | same |
| **before** (my first read, 15:33) | **5** | 139 | 1 | same |
| **after** (this unit) | **0** | 175 | 0 | same |

`.venv/bin/python checks/txt-owners.py` -> **`0 .txt reported`**, rc 0; `--gate` -> `no generator writes a
reported .txt`, rc 0. The two instruments now hold **one** opinion (see §5).

## 1. The reconciliation: plancarve said 3, the file said 4, I read 5 — ALL THREE WERE RIGHT

**A count that two units disagree on is not arithmetic, it is a CLOCK.** The guard walks the live tree, so
its count is a function of what every other unit is writing at that instant. Measured by five consecutive
reads one second apart:

```
read 1 15:33:47   5 HARD   ... runs/graphcmp/D/.tmp.D1-graph-matmul.txt
read 3 15:33:48   5 HARD   ... runs/graphcmp/D/.tmp.D1-graph-matmul.txt
read 5 15:33:49   5 HARD   ... runs/graphcmp/D/.tmp.D1-graph-move.txt   <-- the NAME moved
```

The 5th file **changes name between reads** (`.tmp.D1-graph-matmul` -> `.tmp.D1-graph-move`). A `differ.py
run` was in flight: `differ.run()` writes each artifact to `.tmp.<name>` and `os.replace`s it
(`checks/differ.py:304`), so the walk catches a staging file for a microsecond per artifact. **So the stable
set is 4 and the 5th is a live writer's scratch:**

| # | path | bytes | who writes it | class |
|---|---|---:|---|---|
| 1 | `oracles/rows-bd.txt` | **0** | **nobody** (see §3) | deliberate orphan |
| 2 | `.agents/slop/figure2/plant/broken/runs/graphcmp/D/D0-run-summary.txt` | 386 | `.agents/slop/figure2/plant.py:40` | forced plant |
| 3 | `.agents/slop/figure2/plant/real/runs/graphcmp/D/D0-run-summary.txt` | 384 | `.agents/slop/figure2/plant.py:40` | forced plant |
| 4 | `.agents/slop/substrate/artifacts/smoke/diff.txt` | 355 | `.agents/slop/substrate/diff.py:198,228` | WRITER DEFECT |
| *(t) | `runs/graphcmp/D/.tmp.<declared>.txt` | — | `checks/differ.py:304` | concurrent-run staging |

**plancarve said 3 because 3 is what ITS change left** (24 -> 3); the 4th at its final read was the substrate
`diff.txt` (it says so, verbatim, in its §0: *"the fourth being `.agents/slop/substrate/artifacts/smoke/diff.txt`"*).
The brief's "4" is plancarve's 3 + substrate. My 5th is the differ staging file, which exists only while a run
is in flight. All three numbers are honest readings of a moving tree.

## 2. Each file, its GENERATOR, with `file:line`

- **figure2 plants** — `.agents/slop/figure2/plant.py:40`
  `(d / "D0-run-summary.txt").write_text(summary_text)`. The name is **structurally forced**:
  `checks/corpus-figure.py:182` reads `runs/graphcmp/D/D0-run-summary.txt` under its OWN root, and the plant
  root (`plant/{real,broken}/`) is a shadow copy of the repo layout. Renaming them stops the plant testing
  anything — plancarve's warning, confirmed.
- **substrate `diff.txt`** — `.agents/slop/substrate/diff.py:198` (VOID branch) and `:228` (main branch), read
  back at `:401` (`SEE diff.txt`). **It was regenerated at 15:23:27 today**, same mtime as its tracked siblings
  `oracle.out`/`python.out`/`oracle.norm` — a LIVE writer, not a frozen snapshot.
- **`oracles/rows-bd.txt`** — **NO GENERATOR** (see §3).
- **differ staging temp** — `checks/differ.py:304` `tmp = D / f".tmp.{out}"`; `out` is a `declared()` name, so
  the temp set is DERIVED from the declaration.

## 3. `oracles/rows-bd.txt`: 0 bytes, and NOBODY writes it

**Created by `07cb5a85a` ("portexec: THE PORT'S C RAN…", author `tinybendygrad@localhost`, Sun Oct 4) — the
LAST commit to touch it, and the only one.** `git cat-file -s HEAD:oracles/rows-bd.txt` = **0**; blob
`e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` (the empty blob). It is tracked.

**No live generator writes `oracles/rows-bd.txt`.** The only script that names the *path* is
`.agents/slop/txtexec/rename.py:15`, and it names it to say it did **not** move it. The name itself is
`checks/sb-gate.sh`'s row-dump published name (`:119 cat $D/rows-bd.raw > $D/rows-bd.txt`), but that gate writes
into a `mktemp` dir, never into `oracles/`. Its live counterpart is `oracles/schedule-bodies/rows-bd.rows`
(**1131 B**, tracked) and `oracles/rows-bd.err` (**267 B**, tracked).

**So this is a defect in its own right: a 0-byte placeholder nobody can re-derive, beside the 1131-byte file it
should have been.** It is kept (it is named in `AGENTS.md` and `checks/oracle-txt-census.py:17`, and a tracked
file is not deleted without a commit), and excused by a declaration that LAPSES on content (§4).

## 4. The carve-out, designed — three generator declarations + ONE writer fix

`AGENTS.md`: *"a population is (a) a GENERATOR'S OWN DECLARATION, LOADED BY PATH"*, and *"a second copy of the
list is a contract with no generator."* So each excused name is now asked of the code that PRODUCES it:

| generator's declaration (loaded by path) | declares | why it cannot go stale |
|---|---|---|
| `checks/differ.py:declared()` | graphcmp artifacts **+ their `.tmp.<name>` staging** | the staging name is `f".tmp.{out}"` over the SAME declaration (`:304`); a name that leaves `declared()` takes its temp with it |
| `.agents/slop/figure2/plant.py:declared()` | the two plant summaries | I added `ROOTS`/`SUMMARY_REL` **and made `make_root`/`main` USE them** (`:51,:74-75`); the writer and the declaration are one value |
| `.agents/slop/txtexec/rename.py:LEFT_EMPTY` | `oracles/rows-bd.txt` | honoured **only while the file is 0 bytes** (`no-txt.py:130`); it lapses the moment the file gains content |

- **`checks/txt-owners.py` now imports `no-txt.excused_names()`** (the union of all three), where it used to
  subtract only `graphcmp_artifacts()`. Before this it still printed 3 HARD while the guard said CLEAN — a second
  opinion about an exemption, which is the doctrine's named failure mode.

### The fourth file is a WRITER fix, not a carve-out — and that is the doctrine, not a shortcut

`substrate/artifacts/smoke/diff.txt` is live writer OUTPUT whose extension violates the table (`AGENTS.md`:
`.out`/`.err` captured streams). plancarve, §3, verbatim about the 20 e2e files — *"carving out the fixtures
would have produced 20 exemptions for a real defect"* — and it FIXED those writers rather than carving them. An
`artifacts/smoke/` snapshot already holds `oracle.out`, `python.out`, `oracle.norm`, `oracle.rc`; `diff.txt` is
the lone `.txt`. So:

```
.agents/slop/substrate/diff.py:198,228   diff.txt -> diff.out     (the writer)
.agents/slop/substrate/diff.py:401       "SEE diff.txt" -> diff.out
.agents/slop/substrate/SUBSTRATE.md:20,338
os.rename  artifacts/smoke/diff.txt -> diff.out   (tracked, 355 B, content unchanged)
```

**A carve-out for writer output would excuse a real extension defect; a writer fix removes it.** Three files
needed a declaration; the fourth needed a writer.

### Files changed

| file | change |
|---|---|
| `checks/no-txt.py` | `graphcmp_artifacts()` gains the derived `.tmp.` staging; new `plant_artifacts()`, `empty_remnants()`, `carveouts()`, `excused_names()`; `main()` prints each group; docstring updated |
| `checks/txt-owners.py` | `hard_set()` uses `nt.excused_names()` (was `nt.graphcmp_artifacts()`); docstring |
| `.agents/slop/figure2/plant.py` | `ROOTS`, `SUMMARY_REL`, `declared()`; `make_root`/`main` use them |
| `.agents/slop/txtexec/rename.py` | `LEFT_EMPTY` declaration |
| `.agents/slop/substrate/diff.py`, `SUBSTRATE.md` | writer fix `diff.txt` -> `diff.out` |
| `.agents/slop/substrate/artifacts/smoke/diff.txt` | renamed -> `diff.out` (content unchanged) |

## 5. The guard planted, FIVE states (`.agents/slop/txtresidual/probe.py`)

```
A fresh .txt (must be SEEN)                     rc=1  SEEN
B removed (must be silent)                      rc=0  silent
C orphan under runs/graphcmp/D (must be SEEN)   rc=1  SEEN   <- the carve-out is the SET, not the DIRECTORY
D empty but undeclared (.txt) (must be SEEN)    rc=1  SEEN   <- the 0-byte carve-out is the NAME, not the SHAPE
E declared remnant gains content (must be SEEN) rc=1  SEEN   <- the 0-byte excuse LAPSES on content
ZZ restored (must be CLEAN)                     rc=0  rows-bd bytes intact=True (blob e69de29b...)

VERDICT: FIVE STATES DISTINGUISHABLE
```

**The 4 excused files do NOT keep the guard red** (STATE ZZ rc=0 with them excused) **and the guard still sees
a NEW violation** (STATE A) — so it is a walk that discriminates, not a side-effect of what it excuses. State C
is the reason plancarve's own `declared()`-vs-directory distinction exists: an orphan under `runs/graphcmp/D/`
is still reported. State E is the "cannot go stale silently" property the brief demanded: the moment
`oracles/rows-bd.txt` stops being empty, it is HARD again.

## 6. What remains red, and it is not this rule

`checks/corpus-figure.py` on the REAL tree reports `RUN HEALTH: **FAILED** — graphs=25 but the corpus DECLARES
34`, so `figure2/plant.py` prints `PLANT: AMBIGUOUS -- FAIL`, rc=1. **That is pre-existing and environmental —
a `differ.py run` is mid-flight expanding the corpus — and not caused by this change** (it fails identically on
the real tree with no plant). The plant's own mechanics (build two roots, run the figure) run correctly.

`differ.declared()` is now **175** names, not the `139` `AGENTS.md` carries — the corpus grew to 34 graphs, and
the count is DERIVED, so it moved. The excused count follows it (175 or 176 depending on the live run).

## 7. Re-measure

```
.venv/bin/python checks/no-txt.py           # 0 HARD, rc 0  (175 graphcmp + 2 plant + 1 empty excused)
.venv/bin/python checks/txt-owners.py       # 0 reported, rc 0
.venv/bin/python checks/txt-owners.py --gate # rc 0
.venv/bin/python .agents/slop/txtresidual/probe.py  # FIVE STATES DISTINGUISHABLE, rc 0
```
