# `checks/oracle-txt-census.py` — the census that read ABSENT as STALE

**Verdict: the CENSUS was wrong, not the plant.** It collapsed two verdicts into one: a reader whose
path is gone (`ABSENT`) was recorded as a reader whose input moved (`STALE`). The plant's failing
assertion, `plants.py:160-161`, is the conflation stated in one sentence — *"reader's path ABSENT
reads as STALE"* — and the assertion was FALSE only because the file it named **also had a live
reader**, so the census returned `LIVE`. `STALE` and `ABSENT` are now two verdicts, the plant is
green **by a true assertion**, and the pre-rename count moves from **30 STALE to 2 STALE + 28
ABSENT**.

---

## 1. Population, re-derived by walking `oracles/` (not by trusting a number)

Instrument: `os.walk` + `suffix` (`.agents/slop/oracletxt/population.out`).

| measure | value |
|---|---|
| files under `oracles/` | **358** |
| `.rows` | **277** |
| `.txt` | **1** — `oracles/rows-bd.txt`, 0 bytes, git-tracked |
| `.json` / `.bend` / `.err` / `.py` / `.md` / `.names` / `.tsv` / `.sh` | 20 / 16 / 12 / 7 / 5 / 5 / 4 / 4 |

**What the census reports NOW vs what is on disk.** `rglob("*.txt")` returns **1** (`.agents/slop/
oracletxt/census.out`). The census still describes a tree that exists — but a **remnant**: 258 of the
259 files it was built around were renamed to `.rows`/`.err`/`.md`/`.tsv`/`.bend` in `4d0a2b258`
(`notxt139`). **A census of a renamed set is a census of the past unless it says so, so the docstring
now says so** (lines 14-21): the 259-row reading is retained as history only, and the re-measurable
pre-rename split is `.agents/slop/oracletxt/shape_of_stale.py`.

## 2. The recorded failure — exactly which assertion, exactly what it asserts

`checks/oracle-txt-census.py`'s plant lives in `.agents/slop/oracles259/plants.py`. The failing
assertion is **`plants.py:160-161`**:

```
checks.append(report("plant2 beat 1: reader's path ABSENT reads as STALE",
                     seen[0] == "STALE", f"{key} -> {seen[0]}"))
```

with `key = "oracles/schedule-bodies/BEFORE-rows.txt"` (`plants.py:143`) and
`state()` (`plants.py:150-152`) reading the census's **collapsed file verdict**.

**Why it fails.** That file had *two* readers: `checks/sb-gate.sh` opens an ABSENT path
(`.agents/slop/schedule-bodies/BEFORE-rows.txt`) — and `.agents/slop/oracles259/ordering.py` opens
the file itself, LIVE. `census()` gave LIVE priority, so `state()` returned `LIVE`, not `STALE`.
Recorded in the repo's own artifact `txtexec/census-before.out:33`, which lists that path under
`LIVE 4 / 259`. (Earlier, `oracles259/census.out` — before `ordering.py` existed — shows it under
`STALE`; the scratch tool was added later and the tree moved under the plant.)

## 3. Decision: the CENSUS is wrong — it reads an ABSENT path as STALE

`census()` had this (`checks/oracle-txt-census.py:327-328`, pre-fix):

```python
            else:                       # reader's resolved path does NOT exist
                stale.append((reader, tok))     #  <-- named STALE
```

A reader whose path is simply **gone** is not a reader whose input **moved**. The join that finds the
reader is on the **basename**; a bare basename match is a *namesake*, not evidence of a move. The
file's own `--gate` mode already knew this — it looked for the surviving file — but the per-file
`census()` did not: **`STALE` was asserted from the reader's ABSENT path alone.** This is the
`stale71` distinction stated as a defect: *readers whose path is gone are not stale readers.*

## 4. The fix

**One definition (lines 279-291): `shared_tail(reader_path, file_path)`** — the trailing path
components the reader's gone path shares with the file, basename included. The read **MOVED** only if
more than the basename survived (`.agents/slop/schedule-bodies/BEFORE-rows.txt` was
`oracles/schedule-bodies/BEFORE-rows.txt`, so `schedule-bodies/BEFORE-rows.txt` is shared).

**The split (`census()`, lines 356-359):**

```python
            elif shared_tail(tok, rel) >= 2:
                stale.append((reader, tok))     # STALE: the sub-tree survived — the read MOVED
            else:
                absent.append((reader, tok))    # ABSENT: basename only — a namesake, not a move
```

Every row now carries `live`, `shadow`, `stale` **and** `absent`. `main()` prints both, computes
`NAMED BY NOTHING` over all four, and `--gate` now flags only the **moved** reads (the real hazard)
by reusing the same split rather than re-deriving a weaker basename rule. The census artifact moved
to `.agents/slop/oracletxt/census.json` — it no longer overwrites another unit's git-tracked file.

## 5. Re-run numbers, with denominators

**Current tree** (`.agents/slop/oracletxt/census.out`, census rc=0; `--gate` rc=0):

| measure | value |
|---|---|
| files found (`rglob("*.txt")` under `oracles/`) | **1 / 1** |
| classified by content (`shape()`) | **1 / 1** — `prose-in-txt` (`rows-bd.txt`, 0 B) |
| named by nothing | **0 / 1** |
| REACH | LIVE 0 · SHADOW 0 · **STALE 0** · **ABSENT 1** · NOTHING 0 |

Before the fix the same single file read `STALE 1 / 1`. It is a namesake of `rows-bd.txt` readers, not
a moved input — the one file the rename left behind was also the one the old census over-claimed.

**Pre-rename population, replayed from the committed 259-row `census.json`**
(`.agents/slop/oracletxt/shape_of_stale.py`, one `shared_tail`, imported by path):

| old (collapsed) | corrected |
|---|---|
| STALE **30 / 259** · LIVE 4 · NOTHING 225 | STALE **2** · ABSENT **28** · LIVE 4 · NOTHING 225 |
| 63 absent-path reader tokens | **6 moved** · **57 namesake** |

## 6. The plant — two states, distinguishable

`.agents/slop/oracletxt/plant.py` (rc=0, `plant.out`) runs on a **private `tempfile` tree**, never
into `oracles/` (a plant inside the population moves the answer it measures). Two plants:

- **PLANT 1 — SHAPE.** A rowdump at a no-hint name stays `rowdump`; rewrite the same name with source
  bytes and the verdict **moves** to `source-in-txt`; a crash dump at a rows-looking name is still
  `crash-dump-in-txt`.
- **PLANT 2 — REACH.** One file, one byte sequence, four beats — `STALE -> ABSENT -> SHADOW -> LIVE`
  — selected only by the **reader's path**. `STALE` (sub-tree survived) and `ABSENT` (basename only)
  are distinct states on the *same* file.

**It can go red.** `.agents/slop/oracletxt/selftest.py` (rc=0, `selftest.out`) injects the pre-fix
census (`shared_tail` always ≥ 2) and requires `plant_reach` to **FAIL** — beat 2 catches the
collapse — then runs an untouched census and requires **PASS**. It also runs `--gate` over a tree
whose only reader is a moved read and requires **rc=1**. Pre-fix red, fix green, gate fires: the
plant proves the distinction it exists for.

## Reproduction

```
.venv/bin/python checks/oracle-txt-census.py                       # 1 .txt; STALE 0, ABSENT 1
.venv/bin/python checks/oracle-txt-census.py --gate                # rc 0
.venv/bin/python .agents/slop/oracletxt/plant.py                   # ALL PLANTS PASS
.venv/bin/python .agents/slop/oracletxt/selftest.py                # red under pre-fix, green after
.venv/bin/python .agents/slop/oracletxt/shape_of_stale.py          # 30 -> 2 STALE + 28 ABSENT
```
