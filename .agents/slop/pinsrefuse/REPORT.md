# THE TWO REFUSALS, RE-EXAMINED

**HEAD `9c66365b7623813a843f36db145cd5d2df20245a`** (`gates/corpuswitness-gate.py: verdict.reported is derived, and it can go red`, 2026-10-20 23:47:27 +0300)
**measured 2026-10-20T20:48:51Z** (first pass 2026-10-20T20:41:54Z at HEAD `d9dcd0fe2ffb6559beb13e67f083021fa0a6748c`)
**loadavg 4.40 / 6.68 / 6.31** (under 12) · one process at a time · no `bend` run (see §4) · nothing committed.

VERDICT IN ONE LINE EACH:

| file | the brief's reason | still true? | the refusal | the recommended disposition |
|---|---|---|---|---|
| `gates/cstyle-live.rows` | the `227` is a line-count claim | **NO — THE REASON IS FALSE** | **STANDS, on a stronger reason** | **(b) change the consumer, then (a) land the header** |
| `gates/symcases.rows` | `discover()` cannot see the `.bend` reader | **NO — FIXED; THE FILE IS GREEN** | **GONE** | **NO ACTION** |

---

## 0. THE CONTROL FIRST, BECAUSE IT CHANGES THE FRAMING

### 0.1 IS THE GATE SAFE TO RUN? YES — READ ITS SOURCE FIRST, AS ASKED.

`gates/pins-shape-gate.py` was read END TO END (540 lines) before it was run. It **writes nothing**:

* `census()` — `print()` only (`:397-429`).
* `plant()` — every synthetic tree is a `tempfile.TemporaryDirectory()` (`:489`, `:506`, `:521`).
* `tracked()` — the only subprocess is `git ls-tree -r --name-only HEAD -- gates/` (`:311`), a **read of a commit tree object**, not of the index.
* **There is no `gates/artifacts/` write, and no write of any kind.** `grep -n 'open(\|write\|mkdir\|Path(' gates/pins-shape-gate.py` finds no write call.

So it was run, read-only, with the index disarmed: `env -u GIT_INDEX_FILE .venv/bin/python gates/pins-shape-gate.py`.
stdout → `.agents/slop/pinsrefuse/pins-shape-run.out` (HEAD `d9dcd0fe`), `…-run2.out` (HEAD `9c66365b`); stderr → `…-run.err` / `…-run2.err` (one `SyntaxWarning: invalid escape sequence '\`'`, from another gate's docstring, swallowed by `warnings.catch_warnings` at `:160`).

### 0.2 THE CONTROL RESULT — AND THE BRIEF'S "SAME 2 OFFENDERS" IS FALSE

The brief says: *"your re-measurement must find the SAME 2 offenders the gate reports now, and must not invent a third."*

**The gate does not report 2 offenders.** At HEAD `9c66365b` it reports:

```
POPULATION: 365 discovered entry point(s) + 78 lib(s) as owners, 38 checked-in .rows file(s) under gates/, 84 distinct .rows path(s) named by one of them
PINS-SHAPE: RED -- 24 finding(s)
```

**24 findings over 20 distinct `.rows` files** (at the earlier HEAD `d9dcd0fe`: 25 findings over the same 20 files — the one that moved is `vendordep-census.rows`, whose second finding disappeared because `gates/vendordep-census-plant.py` entered the owner pool between the two commits; see §0.4).

The 20 red files, named:

```
arenasrc_census.rows   citations-census-findings.rows   cstyle-live.rows   edge-cost.rows
edge-fixture.rows      edge-oracle-pin.rows             edge-trace.rows    falseclaim-plant.rows
falseclaim.rows        gapcensus-pins.rows              help-census.rows   nilsrc-census.rows
oracleblind.rows       prose-census.rows                revendor-struct.rows
runner-cost.rows       specreach-map.rows               tnvalue.rows       untested-pins.rows
vendordep-census.rows
```

**I invented no third offender.** The 19 files the brief did not name are named **by the gate itself**, in the run whose output is saved next to this report. The brief's two are a subset: **one still red, one green.**

### 0.3 THE TWO SUBJECT FILES, VERBATIM FROM THE RUN

```
  cstyle-live.rows                   rows=  227 cols= - owners=dup-gate.py,repair-dupes.py
  RED cstyle-live.rows: no header at all, so nobody declared who writes it -- but dup-gate.py,repair-dupes.py names it

  symcases.rows                      rows=    7 cols= - owners=sym_graph_census.bend
```

* `gates/cstyle-live.rows` — **still RED, one finding, check II only.** Check VI ("no gate source names this path") **PASSES**: it is named by `dup-gate.py` and `repair-dupes.py`.
* `gates/symcases.rows` — **GREEN.** It is in the population, it is named, and it is not among the 20 red files. **Its refusal is gone.**

Both are **stable across the two HEADs** I measured (`d9dcd0fe` → `9c66365b`): `symcases.rows` green at both, `cstyle-live.rows` red on check II only at both.

### 0.4 THREE INSTRUMENT LIMITS MEASURED IN THE OTHER 19 — NAMED, NOT COUNTED

These are not my subject, but they are the same class as the `symcases` one, and the next person will hit them.

1. **`namer()` requires the string to END with `.rows`** (`:164`, `n.value.endswith(".rows")`). A path on a **non-last line of a docstring** is invisible. MEASURED: `gates/specreach-compare.py:5` documents `--out gates/specreach-map.rows`, but that docstring's last line is prose, so `gates/specreach-map.rows` reports `owners=NONE` and is charged "no gate source names this path". **A FALSE CHARGE**, the same shape as the `symcases` one that was fixed.
2. **The owner pool is `entries + [p for p in libs if p.suffix == ".py"]`** (`:390`). `gates/vendordep-census-plant.py:25` names `gates/vendordep-census.rows` and `:50` writes it — but a `-plant.py` was not in the pool, so the file reported `owners=NONE`. Between HEAD `d9dcd0fe` and `9c66365b` another unit changed this and the false charge went away — **which is the measured proof that it was the pool, not the file.**
3. **`home.glob("*.bend")` (`:379`) is `gates/`-ONLY, and `pathlib.Path.glob` DOES match dot-prefixed names.** MEASURED: 69 `.bend` matched, including the mutation scratch `gates/.opseven-mut-723815.bend`, which is then counted in the printed "discovered entry point(s)". The gate's own `TEMP` convention (`:79`) excludes dot-prefixed `.rows`; nothing excludes dot-prefixed `.bend`. And the widening is narrower than the tree: **`tinybendygrad/runtime/support/autogen.bend` names `gates/oracleblind.rows` and lives outside `gates/`, so the gate cannot see it.**

---

## 1. `gates/cstyle-live.rows` — THE REASON WAS WRONG; THE REFUSAL IS STRONGER

### 1.1 THE CLAIMED REASON, AND THE MEASUREMENT THAT KILLS IT

The brief: *"`checks/dup-gate.py` publishes **`227 name(s) on the BEFORE side have no partner`** as a claim ABOUT ITS LINE COUNT, so adding a comment line there moves a number another gate reports."*

**It does not.** The line, `checks/dup-gate.py:321-322`:

```python
  print(f"RENAME     {len(pairs)} pair(s); "
        f"{len(set(na) - {y for _, y in pairs})} name(s) on the BEFORE side have no partner")
```

`na = Counter(r[0] for r in ra)` (`:297`) where `ra` is the list of rows **accepted by `ROW()`** — and `ROW` is `rebase-gate.py:row()`. That rule, at `.agents/slop/rebase-gate.py:443-455`:

```python
    if name.startswith("#"):
      # A `#name=value` LINE IS A COMMENT AND IS NOT A ROW …
      return None
```

**A `#` line is not a row.** So a comment header is invisible to the counter. The `227` is a count of **distinct row NAMES**; it equals the line count only because every line of this fixture happens to be a row.

**EXPERIMENT** (on a copy, `.agents/slop/pinsrefuse/with-header.rows` — 230 lines against the original's 228):

```
$ .venv/bin/python checks/dup-gate.py --compare .agents/slop/pinsrefuse/with-header.rows gates/cstyle-live.rows
ROWS       227 -> 227 lines; 227 -> 227 read; 227 -> 227 distinct names …
RENAME     0 pair(s); 227 name(s) on the BEFORE side have no partner
BYTES      sha256(nb) bc70e7ee3587 -> c44affd43136   CHANGED
```

**The `227` did not move.** The only thing that moved is `BYTES sha256(nb)` — and `c44affd43136` is published **nowhere**: `grep -rn 'c44affd43136' .` (excluding `references/`) returns **0 hits**.

### 1.2 THE REAL REASON, MEASURED — AND IT IS STRONGER

**The fixture is the verbatim stdout of a process, and its reader requires byte-identity.**

* `.agents/slop/f64/repair-dupes.py:100` — `same = GOOD.read_bytes() == r.stdout.encode()`, with `GOOD = pathlib.Path(__file__).resolve().parents[3] / "gates" / "cstyle-live.rows"` (`:48`).
* That reader is **tracked in git** — `git ls-tree -r --name-only HEAD -- .agents/slop/f64/` lists `repair-dupes.py` — and **LIVE**: `checks/run-f64.sh:73` sets `F64="$ROOT/.agents/slop/f64"`, and `checks/run-f64.sh:127` runs `"$PY" "$F64/repair-dupes.py" …`.
* `checks/run-f64.sh:132-138`: **any** non-zero rc → `*** REFUSED, EXIT 3: the port's own rows could not be reproduced, so NO number below would be a verdict about f64.` → `exit 3`.
* `repair-dupes.py:97-103`: `same` False → `sys.exit(2)`.

**SIMULATED** (the byte comparison, no `bend` needed):

```
current fixture bytes     : 46291
with-header fixture bytes : 46422
repair-dupes.py:100  same (current) : True  -> exit 0
repair-dupes.py:100  same (hdr)     : False -> exit 2  (rows DIFFER)
row count unchanged by the header    : 227 227
```

**So a `#` header does not move a published number — it makes e2e stage 7 refuse, forever, silently.** And there is **no writer**: `grep` for a write site tree-wide finds none; the file is the stdout of `./bin/bend tinybendygrad/renderer/cstyle.bend` at a past commit. `checks/repair-dupes.py:48` and `checks/.e2e-fixture/f64/repair-dupes.py:48` READ it; they do not write it. The gate's own finding is therefore **true**: "nobody can regenerate it" and "no header at all".

**A REFUSAL FOR THE WRONG REASON IS STILL A REFUSAL, AND IT WILL MISLEAD THE NEXT PERSON WHO LOOKS AT IT.** Believing the `227` reason sends the next agent to `dup-gate.py` to stop publishing a number — mutilating a *correct* instrument (the `RENAME` line is the multiset proof; `nl-gate.py`'s `--compare` is its model) to work around a defect in a *data file*.

### 1.3 THE SECOND HALF OF THE BRIEF'S REASON (the cold substrate)

`e2e.py` stage 7 is a SKIP-and-say-so stage (`checks/e2e.py:75-95`), and `checks/run-f64.sh:105-107` refuses when `substrate-check.sh` is not `WARM`. **I did not run it** — it compiles `bend`, and the substrate rule forbids a corpus-wide run. What I can state: there is **no `f64` artifact directory under `gates/artifacts/`**, and the on-disk e2e evidence (`.agents/slop/e2epy/artifacts/live.*.out`) has mtime **Oct 7**. So the "cannot be re-taken" half is **consistent with the tree** and I do not contradict it.

---

## 2. `gates/symcases.rows` — THE `.bend`-READER QUESTION

### 2.1 THE REFUSAL WAS TRUE, AND IT WAS AN INSTRUMENT DEFECT, AND IT IS FIXED

The brief: *"the gate's `discover()` finds gate entry points, so the file is NAMED BY NOTHING in the population the gate searches."* **That was true, and it was the gate's own tool limit, not a policy.** The gate says so itself, at `gates/pins-shape-gate.py:139-147`:

> `# gates/symcases.rows: no gate source names this path` WAS A **FALSE CHARGE**, MEASURED: `gates/sym_graph_census.bend:130` is `def CASES() -> String: "gates/symcases.rows"` and `:626` READS IT AT RUNTIME. `namer()` was `ast.parse`-only, so `if f.suffix != ".py": continue` COULD NOT SEE A `.bend` OWNER. **THAT IS A TOOL LIMIT AND NOT A POLICY**

and at `:360-365`:

> `discover()` IS A **TWO-VALUE CONTRACT** … **SO THE `.bend` POPULATION IS ADDED HERE AND NOT BY CHANGING `discover()`.** … A FIX THAT BREAKS A CALLER IS NOT A FIX; IT IS A TRADE.

**The fix landed, on both halves, and the file is GREEN:** `:150` admits `.bend` and `:170` scans them as **text** (doctrine 1 clause (c) — a driver's paths are literals, not computed); `:379` adds `sorted(home.glob("*.bend"))` to the entries **inside the gate**, not in `discover()` (`gates/gate-surface.py:280` unpacks `discover()` into `entries, libs`; a third return value raises `ValueError: too many values to unpack`).

The reader, re-measured today at **`gates/sym_graph_census.bend:157`** and **`:679`** (the line numbers moved from the `:130`/`:626` the gate's comment cites):

```
157: def CASES() -> String: "gates/symcases.rows"
679:     f : File <- IO.try(File, File.open(CASES(), "r"))
```

The file also already carries its own truthful declaration, `gates/symcases.rows:1`:

> `# GENERATED by hand -- this file is HAND-MAINTAINED and no gate, generator or flag writes it.`

**ANSWER TO "widen `discover()` or have the file declare itself?" — THEY ARE NOT ALTERNATIVES, AND BOTH ARE DONE.** The header answers check II (*who writes it*); the widened owner pool answers check VI (*who reads it*). **A file cannot declare its reader**, so check VI must be fixed on the instrument side, and it was — in the gate, not in `discover()`, for the caller-compatibility reason above. Git: `0bf516ed7` *"pins-shape's 'no gate source names this path' was a FALSE CHARGE, and the fix is `.bend` files read as TEXT"*, then `3173198bd` *"Two red gates, measured. One was mis-charged; the other's finding is a contradiction."*

### 2.2 IS THE `.bend` READER REACHABLE AT ALL? — NO, AND THAT CHANGES THE DISPOSITION

**The reader is never run by any automated instrument.** Five independent measurements:

1. **It says so.** `gates/sym_graph_census.bend:8` — *"There is no `gates/sym_graph_census-gate.py` and there is no committed oracle. **IT IS A PROBE, NOT A GATE.**"*
2. **Its only documented invocation is a human's.** `:5` — `bin/bend gates/sym_graph_census.bend`.
3. **It is not in the declared driver population.** `gates/gapcensus.py:257-268`, `gate_drivers()`: *"THE DRIVERS A GATE NAMES IN ITS OWN `bend=`. The declared population, not `gates/*.bend` … 91 gates name **61** drivers, while `gates/` holds **69** `.bend` files. The 8 unnamed are mutation drivers and fixtures … counting the directory would credit the census with 8 gates that do not exist."* MEASURED: `grep -rn 'bend=' --include='*.py' gates/ checks/ | grep -i sym` → **no gate declares it**.
4. **The compile census does not execute it.** `checks/compile-census.py` runs `bin/bend <file> --check-only` over every `.bend` outside `tinybendygrad/`; `references/bend/bend2/main.ts:39` — `["bend <file.bend> --check-only", "check the file and its imports; run nothing"]`. **`--check-only` runs nothing**, so `main()` and `File.open(CASES())` never execute.
5. **It is one of 7 `gates/*.bend` with no `-oracle.py` companion** (of 69): `arenasrc_rows`, `decomp-mut-driver`, `mxgraph-fixture-rows`, `paramarg_shape`, `ptx_render_census_axis`, **`sym_graph_census`**, `wk-f32`. Every census driver (`md`, `mo`, `gr`, `tn`, `rd`, `ew`, `cr`, `tc_`, `onnx`, `tn_nodes`) has one.

**I did NOT run it.** `gates/sym_graph_census.bend` imports `tinybendygrad/LAWS/spec.bend`, `helpers.bend`, `uop/ops.bend`, `uop/fold.bend`, `uop/symbolic.bend`; the frozen peak-RSS census puts `uop/symbolic` at **745 MB**, over this session's 200 MB command budget. **Reachability is therefore established STATICALLY, and I say so rather than implying I executed it.**

### 2.3 SO WHAT IS THE FILE? — A PROBE'S CORPUS, NOT A PINNED BASELINE

`gates/symcases.rows` is **read by a real driver**, so it is not a list and it is not the `agend`/`xd1/pin` class — the gate was right to stop charging it. But **no instrument that RUNS reads it**: the only runner is a human at a terminal. So it is a **probe corpus with no gate**, and the honest description of it is exactly what `gates/sym_graph_census.bend:8` already says.

**THE CORRECT DISPOSITION IS THEREFORE *NOT* "add a provenance header"** — that header **already exists**, is truthful (`hand`), and cost nothing. And it is not "widen `discover()`" — that is done too. **It is: no action on the refusal, and do not let the GREEN reading of the pins-shape gate be mistaken for "this file is a live input of a running instrument."** The gap that remains is real but belongs to a **different instrument**: *"is every `.bend` driver run by something?"* — and that question is already measured, by `gates/gapcensus.py`'s 8-unnamed-drivers gap, not by the pins-shape gate.

---

## 3. THE DISPOSITIONS, WITH COSTS

### 3.1 `gates/cstyle-live.rows` → **(b) change the consumer, THEN (a) land the header**

| option | cost |
|---|---|
| **(a) land the header** | **e2e stage 7 REFUSES FOREVER.** `repair-dupes.py` exits 2 (bytes differ) → `run-f64.sh` exits 3 → "no number below would be a verdict about f64", on every run, silently. The fixture's whole purpose — the *recorded good run* — is destroyed by a comment. |
| **(b) change the consumer** | `repair-dupes.py:100` compares **rows**, not **bytes**. The weakening is small and MEASURED: adding the header moves the row count 227→227 and every published name-count 227→227; only `BYTES sha256(nb)` moves, and that digest is published **nowhere** (0 hits). The one thing lost: a `#`-line difference between the port's stdout and the fixture would go unseen. The port's stdout rows are `name = [value]   py=[...]` and the fixture has **no `#` line today**, so the weakening is currently unobservable — and it is the *rows* that `repair-dupes.py`'s own docstring says the check is about ("the result must print **the same rows, byte for byte**"). |
| **(c) change `discover()`** | **NOT APPLICABLE and not wanted.** The owner is already found; the problem is not ownership, it is that there is no writer and the bytes are load-bearing. Widening `discover()` would break `gates/gate-surface.py:280`. |
| **(d) keep the refusal and record it** | Acceptable **only if the gate PRINTS THE REASON**, and the reason must be the byte-identity invariant, not the `227`. As it stands the gate prints *"no header at all, so nobody declared who writes it"* with no reason, so the next reader re-derives it — **this session re-derived it, and the brief had it WRONG.** |

**RECOMMENDED ORDER (the order is load-bearing):** **(b) first, then (a).** Change the consumer in one commit, land the header in the next. If (a) landed first, stage 7 is broken in the window between them and the breakage is a *refusal*, i.e. a silent absence of measurement.

**THE TRUTHFUL WRITER, WHEN (a) LANDS:** the gate's `WRITER` regex (`:71`) accepts a non-`.py` writer, and the "writer is not in the tree" charge at `:234` fires **only** for a `.py` writer. So `# GENERATED by ./bin/bend tinybendygrad/renderer/cstyle.bend` is accepted **and is the truth**: the file IS that command's stdout.

**IF (b) IS REFUSED**, then (d) — but as a **DISCOVERED** exemption, not a hand list: bind it to the **byte-identity READ SITE**, found by a regex over the tree's own read sites (doctrine 1 clause (c)). MEASURED today: the tree-wide sites of the shape `read_bytes() == … .encode()` that bind a `gates/*.rows` are `checks/repair-dupes.py:100`, `checks/.e2e-fixture/f64/repair-dupes.py:100`, `.agents/slop/f64/repair-dupes.py:100` — **three readers, ONE target**, `gates/cstyle-live.rows`. Delete `repair-dupes.py:100` and the exemption disappears. **THE PRIOR DRAFT OF THIS EXEMPTION SPREAD** — it collected every basename a reader mentions and MEASURED exempted **5** tables, because `pins-shape-gate.py`'s own `PLANTS` dict spells the comparison out in a comment. **AN EXEMPTION THAT SPREADS IS NOT AN EXEMPTION.**

### 3.2 `gates/symcases.rows` → **NO ACTION**

(a) is done (`:1`, `# GENERATED by hand`, truthful: 0 write sites tree-wide, and the file says so). (c) is done, in the gate rather than in `discover()`, for the caller-compatibility reason at `:360-365`. The refusal is **green**.

**The residual truth — "this file's reader is a probe that no instrument runs" — belongs in `gates/sym_graph_census.bend`'s own header, where it ALREADY IS (`:8`), and in the gap census that already measures the 8 undeclared drivers.** It does not belong in the pins-shape gate, whose check VI asks *"is a real file named"*, not *"is the reader reachable"* — and conflating the two would re-open the `agend`/`xd1/pin` blind spot this gate was built to close.

**ONE NARROW INSTRUMENT IMPROVEMENT IS WORTH MAKING** (not for these two files, for the next one): the owner pool's `.bend` half is `gates/`-only, so `tinybendygrad/runtime/support/autogen.bend`'s reference to `gates/oracleblind.rows` is invisible, and the glob matches dot-prefixed mutation scratch. A tree-wide `.bend` walk with the gate's own `TEMP` convention applied would close both. **That is a change to `gates/pins-shape-gate.py`, which this session may not make** — it is a recommendation, and it is NAMED so that whoever has the write access knows exactly where to look.

---

## 4. WHAT WAS RUN, AND WHAT WAS NOT

**RUN (safe, read-only, one process at a time):**
* `gates/pins-shape-gate.py` — read END-TO-END first, proven to write nothing, then run with `env -u GIT_INDEX_FILE`. rc=1. Output saved under this directory.
* `checks/dup-gate.py --compare` (×3: fixture-vs-fixture, with-header-vs-fixture, fixture-vs-`oracles/usb-oracle-BEFORE.rows`) — the `227` measurement and the header experiment.
* `git ls-tree` (read-only), `grep`/`find`/`sed` (read-only), one `.venv/bin/python -c` for the `pathlib.Path.glob` dotfile behaviour, and one inline script for the byte-comparison simulation.

**NOT RUN, AND WHY:**
* **No `bend` at all.** `gates/sym_graph_census.bend` was not executed (§2.2: `uop/symbolic` is 745 MB on the frozen peak-RSS census, over the 200 MB budget) and `repair-dupes.py` was not executed (it would need `bend` for the stdout side; the byte comparison was simulated instead). Reachability and the byte invariant are established **statically**, and this report says so rather than implying a run.
* **No `checks/e2e*`, no `checks/differ.py`, nothing under `gates/` except the one gate whose source was read first and proven write-free, no `checks/sweep.py`, no `checks/bounded.py`, no corpus-wide run, no pytest/mypy/ruff.**
* **No mutating git command, no commit, no reset, no rebase, no `git add`.** `env -u GIT_INDEX_FILE` on every git read. `git rev-parse HEAD` moved under me mid-session (`d9dcd0fe` → `9c66365b`) and **both readings are reported** rather than only the last.

## 5. FILES

* `.agents/slop/pinsrefuse/recheck.rows` — the two rows, TAB-separated, `file / refusal_reason_original / still_true_yes_no / recommended_disposition / evidence`.
* `.agents/slop/pinsrefuse/pins-shape-run.out` — the gate's stdout at HEAD `d9dcd0fe`.
* `.agents/slop/pinsrefuse/pins-shape-run2.out` — the gate's stdout at HEAD `9c66365b` (**the current one**).
* `.agents/slop/pinsrefuse/pins-shape-run.err`, `…-run2.err` — stderr (one `SyntaxWarning`).
* `.agents/slop/pinsrefuse/with-header.rows` — the experiment copy (230 lines: the original's 228 plus a 2-line `#` provenance header). **The byte-comparison subject.**
* `.agents/slop/pinsrefuse/red-files.rows` — the 20 red files, one per line.
