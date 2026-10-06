# `orcfix` — the dead name in the `skip` tuple, and the denominator behind it

Measured 2026-10-07, session `orcfix`, on a **moving tree** (parallel units were editing
`checks/e2e.py` and the `jj` index while this ran). Every number is quoted with what produced it.
Owned and touched: `checks/oracle-txt-census.py`'s `code_files()`, `.agents/slop/oracletxt/plant.py`,
`.agents/slop/skipexit/repro.py`'s declaration, and this directory. **No commit, no `@`.**
`checks/no-txt.py`, `gates/`, `AGENTS.md` were not touched.

---

## 0. THE BRIEF'S PREMISE IS FALSE ON THIS TREE — MEASURED FIRST

The brief says *"`oracles259/plants.py`: superseded → DELETED"*. **It is not deleted.**

```
$ ls -la .agents/slop/oracles259/plants.py
-rw-r--r--@ 1 cyberistic  staff  9989 Oct  6 16:56 …/oracles259/plants.py
$ git ls-files .agents/slop/oracles259/plants.py
.agents/slop/oracles259/plants.py                # tracked
$ git hash-object .agents/slop/oracles259/plants.py   ->  e6e31707bd5eaec79420f56cec6d183b32e713dc
$ git rev-parse HEAD:.agents/slop/oracles259/plants.py ->  e6e31707bd5eaec79420f56cec6d183b32e713dc
```

Byte-identical to `HEAD`, tracked, present. **The deletion the predecessor reported never landed**
— the `jj` server reset the working copy (the warning in `AGENTS.md` about a reset index is exactly
this), or the unit's `rm` was undone by the shared-index commit `00b101574`. So the hand-list entry
names a **live** file, not a dead one. Either way the entry is wrong: a hand list is not a
population (`AGENTS.md`, doctrine 1), whether or not its one extra name resolves.

**AND `prefixtxt/REPORT.md` DOES NOT EXIST.** The brief quotes it verbatim, but the directory holds
only `notxt.before.out`, `repro.before.err`, `repro.before.out`; no `REPORT.md` is on disk or in any
ref. Its denominator ("5 harnesses…") therefore **cannot be reproduced from the report**, and §3
re-derives what I can.

---

## 1. THE ORPHAN, QUOTED, AND WHAT THE TUPLES **IS**

`checks/oracle-txt-census.py:219`, before this unit:

```python
    me = os.path.relpath(os.path.abspath(__file__), ROOT)
    skip = (me, ".agents/slop/oracles259/plants.py")
    return [ROOT / r for r in out
            if pathlib.Path(r).suffix in GATE_CODE
            and not r.startswith(("references/", "tinygrad/", ".agents/slop/oracletxt/"))
            and r not in skip]
```

**It names TWO paths, not one**, and every name still exists:

| entry | is it a literal? | exists today? | role |
|---|---|---|---|
| `me` | **computed** (`os.path.abspath(__file__)`) | yes — the census itself | keep the census out of its own citation graph |
| `.agents/slop/oracles259/plants.py` | **a literal, typed** | **yes** (`e6e31707…`) | the superseded plant |

So the tuple is a **hand list of exactly one literal path** plus one computed value. The literal is
the entire hand list, its only entry is live (not dead), and — the decisive part — **`oracles259/`
is not excluded any other way**: the reader-path filter excludes `references/`, `tinygrad/` and
`.agents/slop/oracletxt/` by prefix, but **not** `.agents/slop/oracles259/`, so the literal is the
*only* thing keeping one file of that directory out of the reader set. `oracles259/othercopies.py`
is *not* listed and *is* a reader (it appears in the census's own ABSENT block for `rows-bd.txt`).
**A hand list that excludes one file of a directory and not its sibling is a hand list, not a rule.**

**What the literal actually does** (`.agents/slop/orcfix/skipdelta.py`): rebuilds `readers()` with
and without it. Removing it adds exactly one file (`oracles259/plants.py`) to the reader set, which
touches **10 basenames** — all of them fixture or gone paths (`zzz-census-plant-1.txt`,
`oracle-looking.txt`, …). **None is in the current population** (`rglob("*.txt")` over `oracles/`
finds **1**, `oracles/rows-bd.txt`), so the current census rows do **not** move:
`.agents/slop/orcfix/identity.py` reports `rows identical: True`, sha `8b2b2415c6dbc9d1` both ways.

---

## 2. DECISION: **REMOVE THE HAND LIST**, AND LOAD THE PLANT'S OWN DECLARATION

Two options were on the table (the brief's own): have the generator declare the population and load
it, or drop `skip` entirely. **Landed: both at once** — the literal goes, and the prefix copy goes
with it, replaced by a declaration **loaded by path from the generator**:

* `.agents/slop/oracletxt/plant.py` gained `excluded()`, derived from `__file__` (so moving the
  plant moves the exclusion — a second copy of the path is the exact fault `wantwire`'s `UNSET` and
  `nameshandlist`'s `SUBSTITUTED` were removed for):

```python
def excluded() -> frozenset[str]:
    """The reader-set exclusions THIS plant declares to the census, derived from `__file__`."""
    return frozenset({f"{HERE.relative_to(HERE.parents[2])}/"})
```

* `checks/oracle-txt-census.py` gained `plant_exclusions()` (a loader that **fails to nothing** —
  never a blanket exemption) and `code_files()` lost the tuple AND the hard-coded
  `.agents/slop/oracletxt/` prefix:

```python
    me = os.path.relpath(os.path.abspath(__file__), ROOT)
    excluded = ("references/", "tinygrad/", *plant_exclusions())
    return [ROOT / r for r in out
            if pathlib.Path(r).suffix in GATE_CODE
            and not r.startswith(excluded)
            and r != me]
```

**This removes a list rather than filling one.** `me` stays a computed scalar, not a tuple; the
literal is gone; the `.agents/slop/oracletxt/` prefix is no longer a second copy of the plant's own
location. The old literal's only real effect is that a superseded plant's fixture reads stop being
counted — and a read of a **gone** path is a `ABSENT` namesake the census already reports honestly
("it may never have named this file"), so excluding it was cosmetic even before the plant was
supposed to die.

**Verified after landing** (`grep -n skip checks/oracle-txt-census.py` → none):
`census.py` rc=0 (`NAMED BY NOTHING 0/1`), `--gate` rc=0, `oracletxt/plant.py` → `ALL PLANTS PASS`,
`oracletxt/selftest.py` → `PASS` (pre-fix red, fix green, gate rc=1), `shape_of_stale` unchanged
(2 STALE / 28 ABSENT / 4 LIVE-SHADOW).

---

## 3. THE DENOMINATOR — LANES, BY DISCOVERY (`os.walk`, never a list)

The brief's "5" comes from the absent report. I re-derived the population my own way, with a stated
definition, using `.agents/slop/orcfix/lanes.py`: **661 tracked `.py`/`.sh` harnesses under
`.agents/slop/**`; 37 harness→lane edges.** The definition:

> a **lane** is a `.py`/`.sh` a harness **spawns** whose target is a **frozen copy** (lives under a
> shadow dir: `prefix`/`frozen*`/`plant`/`broken`/`real`/`tree`/`old`/`new`) or an **oracle**; a lane
> **emits `.txt`** if the harness or the lane names a `.txt` as a **write** that lands in the repo;
> **declared** if every `.txt` it can write is in a generator's `declared()` loaded by path.

Hand-vetted from the 37 edges and by reading each harness — a lane runs when its shadow copy is
**executed**, not merely named:

| # | harness | lane it RUNS | emits `.txt` into repo? | declared? |
|---|---|---|---|---|
| 1 | `.agents/slop/skipexit/repro.py` | `prefix/checks/e2e.py` (frozen pre-fix) | **YES — 15, measured** | **NO → declared here (§4)** |
| 2 | `.agents/slop/e2epy/diff.py` | `oracle-e2e.sh` (frozen shell oracle) | no (oracle writes `.out`) | n/a |
| 3 | `.agents/slop/difftxt/oracle-probe.sh` + `diffpy/oracle-*.sh` | the frozen diffpy oracle | **YES** | **YES — `differ.declared()`** |
| 4 | `.agents/slop/figure2/plant.py` | `plant/{real,broken}/checks/corpus-figure.py` (shadow) | **YES** (2 summaries) | **YES — `figure2/plant.py:declared()`** |
| 5 | `.agents/slop/clearfix/clearfix-repro.py` | `frozen-prefix/<gate>.py` | no (writes its own `gk*-artifacts/`; frozen `gatekit` writes `.rows`/`.out`) | n/a |
| 6 | `.agents/slop/stalefix/stale-repro.py` | `gatekit-old.py` (frozen) | no (`SCRATCH` is under `/private/var/…`, **outside the repo**) | n/a |
| 7 | `.agents/slop/corpuswire2/plant.py` | shadow `corpus-figure.py` | no (`tempfile.TemporaryDirectory`) | n/a |
| 8 | `.agents/slop/e2esh/plant.py` | `e2epy/diff.py`, `checks/e2e.py` (live) | no | n/a |
| 9 | `.agents/slop/reprofix/plant.py` | `git show 46c52f30d^:…graphcmp-oracle.py` (pre-fix, piped) | no (stdout captured) | n/a |
| 10 | `.agents/slop/declared473/contract_test.py` | `figurefix/plant/plant.py` (mirrored) | no — `rmtree`s each case (`:47`,`:59`) | n/a |

**Denominator, measured: of the lane-running harnesses, 3 can write a `.txt`; 2 are declared already
(`diffpy` via `differ.declared()`, `figure2` via its own plant), and 1 was UNDECLARED —
`skipexit/repro.py`.** That is the brief's "third instance", and it is the one this unit lands.

**A LATENT EXTRA, REPORTED NOT LANDED.** `os.walk` also turns up `.agents/slop/figurefix/plant/plant.py`
(a shadow differ run from `declared473`), whose `SCRATCH` is **in-repo**
(`.agents/slop/figurefix/plant/scratch/`) and is **not cleaned at exit** (rmtree at start only, no
`finally`), so a direct run would leave `runs/graphcmp/D/*.txt` undeclared. It is **not a lane** (its
shadow is *copied into* the scratch, not executed as a frozen revision), its scratch does **not**
exist on disk now, and it belongs to another unit. Reported here rather than edited.

---

## 4. THE UNDECLARED `.txt` EMITTER, DECLARED — AND THE ONE-LINE WIRING

**MEASURED, the emitter is real.** Running the harness leaves the pre-fix lane's `.txt` in the repo
and turns `no-txt.py` red:

```
$ .venv/bin/python .agents/slop/skipexit/repro.py      # rc=0, 15 files created
$ find .agents/slop/e2epy/fixtures -name '*.txt' | wc -l
15
$ .venv/bin/python checks/no-txt.py
  15 .txt FILE(S). … (repro-{green,fail,skip}/runs/e2e/e2e-{f64,mm-bend,mm-gate,opsbend,port-mm}.txt)
```

The cause is a **rename drift**: `skipexit/prefix/checks/e2e.py` (frozen, `3ed5ab069^`) predates the
`.txt`→`.out` rename, so its five stage outputs are `.txt` while the live gate writes `.out` into the
**same** fixture. The frozen file cannot be edited (it is the pre-fix floor), so the harness declares.

**LANDED — `.agents/slop/skipexit/repro.py`:**

```python
STAGE_TXT = re.compile(r'RUN\s*/\s*"(e2e-[a-z0-9-]+\.txt)"')


def declared() -> frozenset[str]:
    """The `.txt` this harness's FROZEN pre-fix lane writes into `.agents/slop/e2epy/fixtures/`."""
    gate = (PREFIX_ROOT / "checks/e2e.py").read_text()
    names = sorted(set(STAGE_TXT.findall(gate)))
    roots = (plantlib.FX / f"repro-{n.lower()}" for n in COLUMNS)
    return frozenset(str((r / "runs/e2e" / n).relative_to(ROOT)) for r in roots for n in names)
```

**The names are DERIVED, not typed**: the frozen gate's own `RUN / "…txt"` write sites, crossed with
the fixture roots `diff.py` builds from `COLUMNS`. A name the gate stops writing stops being declared.
Measured: `declared()` returns **exactly 15**, byte-equal to the 15 the lane writes.

**THE ONE-LINE WIRING — this is what the orchestrator must add to `checks/no-txt.py`** (I may not
edit it; another unit owns it). Add a fourth carve-out alongside the three in `carveouts()`:

```python
def lane_artifacts() -> set[str]:
    """`.agents/slop/skipexit/repro.py`'s frozen pre-fix lane writes `.txt` into its fixture tree."""
    return set(load(".agents/slop/skipexit/repro.py", "skipexit_repro").declared())
```

and extend the tuple:

```python
    for label, fn in (("`checks/differ.py`'s graphcmp artifacts + `.tmp.` staging", graphcmp_artifacts),
                      ("`.agents/slop/figure2/plant.py`'s forced plant summaries", plant_artifacts),
                      ("`.agents/slop/txtexec/rename.py`'s deliberate 0-byte remnant", empty_remnants),
+                     ("`.agents/slop/skipexit/repro.py`'s frozen pre-fix lane", lane_artifacts)):
```

**WHAT BREAKS IF THE DECLARATION LAPSES:** nothing is exempted that no run puts there — the frozen
gate stops writing a name only when it (or the fixture roots) move, and then `no-txt.py` **reports
it**, which is the correct behaviour. The loader is `no-txt.py`'s existing `load()`, so a failure to
compute the set is **already** reported, never a blanket. And because only the **pre-fix** lane
writes `.txt` (the post-fix lane in the same fixture writes `.out`), the declaration cannot excuse a
`.txt` the post-fix run would never produce.

---

## 5. THE PLANT — TWO STATES (`orcfix/guard_plant.py`, `guard_plant.out`)

Running `skipexit/repro.py` is not usable right now: **a parallel unit edited `checks/e2e.py`
(mtime moved to `00:39:59` mid-session) and the post-fix lane no longer writes
`repro-*/runs/e2e/e2e-f64.out`, so the harness dies `FileNotFoundError` before the pre-fix lane leaves
anything.** So the plant materialises **exactly the 15 paths `declared()` derives** (the declaration
talking, not a typed list) and measures the guard:

| beat | state | result | want |
|---|---|---|---|
| 1 | fixtures clean | `no-txt.py` rc=**0** | 0 |
| 2 | the 15 declared lane outputs present, **UNWIRED** | `no-txt.py` rc=**1**, **names 15/15** | 1, all 15 |
| 3 | same tree, **WIRED** with `declared()` | rc=**0** | 0 |
| 4 | **FRESH undeclared** `tinybendygrad/orcfix-plant.txt`, wired | rc=**1**, **names it** | 1, True |
| 5 | everything removed | `no-txt.py` rc=**0** | 0 |

`VERDICT: PLANTS HOLD`. **Beat 4 is the point: a guard red for a reason it is excusing cannot see a
new violation — the wired guard is clean on the excused lane AND still sees a fresh `.txt`.** The
directory is left exactly as found (0 stray `.txt`).

---

## 6. `oracles259/` — **NOT EMPTY, AND NOT HOLDING A REPORT**

`AGENTS.md`: *"a prune that cannot say what it spared is a prune nobody can audit."* Here there was
no prune, so there is no audit:

| question | measured |
|---|---|
| is `oracles259/` an empty directory holding a report? | **NO** |
| how many files? | **21 tracked** (`basenames.rows`, `census.json`, `cited.py`, `classify.py`, `declared_join.py`, `manifest.py`, `MANIFEST.tsv`, `ordering.py`, `othercopies.py`, `paths.rows`, **`plants.py`**, …) |
| is there a `REPORT.md`? | **NO** — `ls oracles259/*.md` → no matches |
| does any report say the directory is retained? | **NO report about it exists in the directory.** `shadowcopies/REPORT.md:214` recommends *"retire `oracles259/plants.py`; do not repoint it"* and that is the only instruction; it was not executed. |
| is `plants.py` superseded? | **YES** — it **crashes today**: `FileNotFoundError: …/oracles/rows-cast-bend.txt` (one of 5 renamed literals, `shadowcopies/REPORT.md:169`). `.agents/slop/oracletxt/plant.py` covers its shape+reach assertions and `ALL PLANTS PASS`. |

**WHAT REMAINS, named:** the whole 21-file directory, `plants.py` included. **The directory is
retained, and no artifact says why** — the retention is an accident of a deletion that did not land,
not a decision. This unit neither deletes `plants.py` (not its grant; the predecessor's report is the
audit that recommended retirement) nor depends on it: with §2 landed, the census no longer names it,
and the plant's fate is now orthogonal to the gate.

---

## 7. ARTIFACTS IN THIS DIRECTORY

| file | what |
|---|---|
| `lanes.py` / `lanes.out` | the lane discovery (`os.walk`, 661 harnesses / 37 edges) |
| `skipdelta.py` | what the removed `skip` literal did (1 file, 10 basenames) |
| `identity.py` | census rows byte-identical before/after the removal (sha `8b2b2415c6dbc9d1`) |
| `guard_plant.py` / `guard_plant.out` | §5, the two-state plant (`PLANTS HOLD`) |
| `guardprobe.py` | the wired-guard simulation used before the atomic plant |
| `landed.diff` | **the uncommitted working-tree change to `checks/oracle-txt-census.py` and `.agents/slop/oracletxt/plant.py`** — verbatim, so a reset cannot lose it |
| `census-after.out`, `repro2.out/err` | the census re-run; the concurrent `repro.py` crash |

**A RESET HIT THIS UNIT MID-SESSION.** The `jj`/shared-index chaos `AGENTS.md` warns about reverted
`checks/oracle-txt-census.py` and `.agents/slop/oracletxt/plant.py` to `HEAD` **after** they were
edited and measured; the `skipexit/repro.py` declaration was absorbed by a parallel commit and
survived. The two working-tree edits were **re-applied and re-verified** (the run above), and their
diff is frozen in `landed.diff`. **They are NOT committed — the orchestrator commits.** If they are
found reverted again, `landed.diff` is the source.

