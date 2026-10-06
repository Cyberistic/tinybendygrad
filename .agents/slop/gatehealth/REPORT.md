# Clause IV: eleven directories that can report health on none of themselves

Agent: gatehealth unit. Date: 2026-10-06. Instrument: `gates/retention-check.py`.
Evidence raw: `.agents/slop/gatehealth/` (`after-*.out`, `clauseI.rows`, `rc.rows`,
`clauseiv-nogate.py`, `experiment.py`).

> **The tree was being edited while this was measured.** A second unit was refactoring clause II in
> this same file (`.agents/slop/clauseII/`) and a third was running `gatekit` gates
> (`beautiful-mnist-gate` held `.tmp.` staging files mid-read). Every number below carries the state
> it was read in, and the clause-I "AFTER" is taken on a **static fixture**, not the live tree.

## 1. What "can report health" requires, exactly, and which 11 directories

"Can report health" is a single predicate: **the family's `Output` carries a non-`None` `healthy`
callable.** The branch is `gates/retention-check.py:520-524`:

```python
for o in res:
    dirs = o.dirs()
    if o.healthy is None:
        print(f"IV UNMEASURABLE {o.path}/: 0/{len(dirs)} dirs can report health -- {o.note}")
        continue
```

It is **a registry entry, not a file name and not a token**. There are two registered families
(`registry()`, `:342-359`); only the `graphcmp` one supplies a callable:

| family | `healthy` | reads |
|---|---|---|
| `runs/graphcmp/D/` | `lambda: differ.unhealthy() + differ.artefacts_ok()` (`:347-349`) | `D0-run-summary.txt` — `name=value` rows incl. `census-rc=rc=0` (`checks/differ.py:766-790`) — plus the artefact SHAPE over `differ.declared()` (`:793-825`) |
| `gates/artifacts/<gate>/` | `None` (`:350-358`) | — ; the note says why |

So what graphcmp has and the gate family lacks is **a persisted verdict the reader can parse**, not
a filename convention. `differ.unhealthy()` returns complaints (not a bool) so a stale pin is named;
the gate family has no such reader because there is nothing to read.

**The 11 directories are DISCOVERED, not listed** — doctrine 1, satisfied. `Output.dirs()`
(`:99-110`) does `sorted(p for p in root.iterdir() if p.is_dir())` for the `gates` family; there is
no number in the source. The printed `0/N` is `len(dirs)`. At 2026-10-06 13:2x that walk returned
**11**: `bc-u32-gate, beautiful-mnist-gate, ew-consts-gate, ew-explog-gate, i64-shl, i64-shr,
mixin-op-gate, ops-core-gate, wk-cd-gate, wk-eval-gate, wk-f32-gate`. (The docstrings said "8",
the epilog "8 + 1 = 9", the note "0 of 8" — all stale; fixed in this change.)

## 2. Do those 11 produce a healable artifact at all? No.

Read from the source and from disk:

- `gatekit`'s verdict is **an exit status**, printed and never written: `gates/gatekit.py:59` —
  `PASS, FAIL, REFUSED, SKIP, DEAD = 0,1,3,4,5`. There is no verdict file.
- A green run promotes exactly **seven fixed names** into the dir — `py.rows`, `bd.out`, `bn.out`,
  `py.cmp`, `bd.cmp`, `bn.cmp`, `gate.bin` — through one `_settle` (`gatekit.py:436-449`).
  MEASURED on the live tree (2026-10-06 13:2x, before the mid-run): 10 of 11 dirs held those 7
  names and `mixin-op-gate` held only `.tmp.bd.out` / `.tmp.py.rows` (a run in flight).
- Those are **lanes**: captured streams, expected rows, and the rows that survived the exclusion
  list. They are the *inputs to* the verdict, not the verdict. `bd.cmp == py.cmp` being equal is
  the claim; nothing on disk witnesses that it held, or whether the lane empty/one-line rule fired.

**What a gate leaves on disk is therefore not a health signal.** It is a health signal's *evidence*.
`UNMEASURABLE` is the truthful token.

## 3. Decision: **(b) DECLARE THE LIMIT** — and it is already the behavior.

Cited: clause IV's `continue` at `retention-check.py:524` leaves `red` untouched; the only `red`
in the clause is on the `FIRES` path (`:527`). **Clause IV never fails the check on an unmeasured
family.** Proven directly (`clauseiv-nogate.py`: drive `report()` with two families whose `healthy`
is `None` on an empty scratch dir, so I/II/III/V are green): **`report() returned 0`** while both
`IV UNMEASURABLE` lines printed.

**A false premise in the brief, measured.** The brief said *"rc=1 NOW COMES FROM HERE (`0/11 dirs
can report health`)"*. It does not. The `UNMEASURABLE` branch cannot set `red`. In the run taken
before this change, rc=1 came from **clause I** (`:435` `red |= bool(dirty)`, `dirty = 11`). In the
run after, clause I is green and rc=1 comes from **clause II** (`:410`, `bool(unmeasured)` — the
other unit's change; `checks/differ.py` has no class-scoped `run`). **Clause IV contributes 0 to rc
in both.** `gates/README.md` and clause II's own docstring independently call that state a REFUSAL,
not a pass, which is the right shape; it is simply not *this* clause's red.

**What would make (a) possible, and how much it would cover.** `gatekit` would have to *persist*
its verdict — one declared file per `Gate` dir (e.g. `verdict.rows` carrying the verdict token and
the lane row counts), added to `GATEKIT_OUTPUT`, paired with a `healthy()` like `differ.unhealthy()`.
That is `gatekit.py`'s change, **`gates/gatekit.py` is off-limits to this unit**, so (a) is not
reachable from this file. It would cover **all of them** — every directory under `gates/artifacts/`
is written by a `gatekit` `Gate` — i.e. the whole current 11, and every future one. So the honest
fork is: leave `UNMEASURABLE` until that file exists.

## 4. The one thing not done

No widening. `UNMEASURABLE` stays; the clause was **not** made green. The one change to clause I is
a *declared set* repair, not a health relaxation, and it was proven to still fire:

- `GATEKIT_OUTPUT` (`:86`) now derives from `gatekit`'s OWN lane constants (`LANE_ROWS`/`LANE_OUT`/
  `LANE_CMP`, `gatekit.py:68-70`) plus the one `gate.bin` literal (`gatekit.py:317`), imported at
  `:68`. The old transcription named `*.txt`/`*.sub`, which `gatekit` had stopped writing, so clause
  I named **every** gate-dir file residue.
- MEASURED on the static fixture `gates-syn` (`clauseI.rows`): BEFORE `0/11 clean, 11 with residue,
  66 residue files`; AFTER `11/11 clean, 0 residue`. **Plant:** drop one undeclared
  `stray.leftover` → `I RESIDUE ... 1 undeclared ['stray.leftover']` (`after-syn-plant.out`). The
  set still catches residue that is residue.

## 5. Clause IV's verdict BEFORE and AFTER, the counts, and rc

| read (2026-10-06) | clause IV, graphcmp | clause IV, gates | dirs looked at | measurable health | rc | rc source |
|---|---|---|---|---|---|---|
| BEFORE (live, before this change) | `IV OK` | `IV UNMEASURABLE … 0/11` | 12 (1+11) | **1** (graphcmp) | **1** | clause I (`11 residue`) |
| AFTER (live, after this change) | `IV OK` | `IV UNMEASURABLE … 0/11` | 12 (1+11) | **1** (graphcmp) | **1** | clause II (`differ UNMEASURED`) |
| AFTER (static `gates-syn`, clause I clean) | `IV OK` | `IV UNMEASURABLE … 0/11` | 12 | **1** | **1** | clause II |

Clause IV's token is **unchanged** — dishonest to claim otherwise; the honest result of (b) is that
the token stays `UNMEASURABLE`. What changed is that its printed note no longer hardcodes "8" and
now states that `UNMEASURABLE` is not a failure, and the stale denominators in the docstring,
`Output.dirs`, `registry` and `--help` epilog are corrected to the discovered count.

## 6. PLANT: break the one directory that reports health — `IV OK` → `IV FIRES` (two states)

Driver: `experiment.py`, which COPIES `runs/graphcmp/D/` to a transient fixture and points
`--dir graphcmp=…` at it, so the live `runs/graphcmp/D/` is untouched. The fixture holds 139 `.txt`
artifacts and is **derived on demand and deleted after the capture** — committing it would put 139
NEW `.txt` paths outside `differ.declared()`'s carve-out. Raw evidence is the `.out` captures below.

- **State 1, intact copy** (`graphcmp-ok`): `IV OK  …/graphcmp-ok/: 1 dir(s), last run healthy on
  its own measure`. Raw: `after-graphcmp-ok.out`.
- **State 2, one pinned row broken** (`graphcmp-broken`, `D0-run-summary.txt` rewritten to
  `graphs=25 / graphs-agree=0`): `IV FIRES  …/graphcmp-broken/: the directory exists and its last
  run was NOT healthy: 20 complaint(s)`, e.g. `graphs-agree=0 (expected 21)`, `graphs-unset ABSENT`.
  Raw: `after-graphcmp-broken.out`.

Two states, one variable, the token moves `OK` → `FIRES`. Clause IV measures.

## Summary of the one-line finding

Clause IV's `UNMEASURABLE` is a **REPORT, not a FAILURE** (`retention-check.py:524`), and it is
correct: `gatekit` prints its verdict and never writes it (`gatekit.py:59`), so none of the 11 gate
dirs can report health and all should say `UNMEASURABLE`. The rc=1 attributed to this line actually
came from clause I's stale declared set (`:435`), which this change repaired so clause I is now
`12/12 clean`; rc remains 1 only on clause II's honest `differ UNMEASURED` (`:410`).
