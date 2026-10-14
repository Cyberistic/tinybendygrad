# `livenum` — the live-number population, by discovery, with its instrument and its pins

Unit `livenum`, 2026-10-07. **STATIC-ONLY: `bend` was NOT run.** Python only,
`.venv/bin/python`, no `.txt`, no commit, no `git add`, no `@`.
**Moment: `git rev-parse HEAD` = `3c4ceeea3e90d8ac3c8a9cfbedad51ea65343aaf`** (stable
all session). The surfaces are read from the **WORKING TREE**, so each reading
carries its file's mtime — the defect this unit exists to name.

Cites work: `.agents/slop/livenum/scan.py` (broad measure-claim scan),
`claims.py` (the named re-derivable counts), `named.py` (the value-join that FAILED
and is kept as evidence), `resolve.py` (working-tree citation resolver), `check.py`
(the location-pin checker), `live.py` (the deliverable table).

## 0. THE DELIVERABLE — how many live vs dated, and the one number that was wrong

Two populations, both **by discovery**, at different resolution:

| population | declared by | claims | LIVE | DATED |
|---|---|---:|---:|---:|
| broad measure claims | `scan.py`'s `BOUND` regex over the 3 surfaces | **1 452** | **1 128** | **324** |
| named re-derivable counts | `claims.py`'s `ANCHORS` (each names its instrument) | **88** | **48** | **40** |

Per surface (named): `AGENTS.md` **11 LIVE / 22 DATED**; `.agents/TOOLS.md`
**6 / 8**; `.agents/TODO.md` **31 / 10**. Broad: `AGENTS.md` 25/34,
`.agents/TOOLS.md` 113/70, `.agents/TODO.md` 990/220.

**The broad classifier over-counts LIVE and that is stated, not hidden.** A
reading is DATED only when its own ±2-line window carries a date, a clock, or a
past cue; a session-log line that restates a measurement without re-dating it reads
as LIVE. So `1 128` is an **upper bound on live candidates**, while the `48` named
occurrences are the actionable set: each names an instrument that can re-derive it.

**THE ONE NUMBER IN THE BRIEF THAT IS NOT IN THE TREE: the `41 %`.** Confirmed
absent again — `grep -rn '41 %\|41%' AGENTS.md .agents/TOOLS.md .agents/TODO.md`
returns nothing that is a measurement. `citeresolve` and `citetruth` each found the
same. A number in a brief is a number nobody can check.

**And the named stale list re-derived, at this moment:**

| claim | stated (live occurrence) | now | ONE-LINE COMMAND |
|---|---|---:|---|
| `no-txt.py` HARD | `550` (`AGENTS.md:41`, dated) | **0** | `.venv/bin/python checks/no-txt.py` |
| `no-txt.py` EXCUSED | `139` (`AGENTS.md:41,123`, dated) | **178** | same |
| `len(differ.declared())` | `139` (`AGENTS.md:96`) | **175** | `.venv/bin/python -c "…len(m.declared())"` |
| `TOOLS.md` present | `153` (`AGENTS.md:140`) | **164** | `.venv/bin/python .agents/slop/citeresolve/counts.py` |
| `TOOLS.md` gone | `180` (`AGENTS.md:140-141`) | **169** | same |
| gone under `.agents/slop/` | `96` (`AGENTS.md:141`) | **85** | same |
| `gates/*.py` | `21` (`AGENTS.md:131`) | **56** | `ls gates/*.py \| wc -l` |
| `checks/substrate.py` lines | `766`/`841` (`AGENTS.md:129`, dated) | **936** | `wc -l checks/substrate.py` |
| `*-mutate.py` survivors | `9 + 7` (`AGENTS.md:259`, dated) | **14** | `find .agents/slop -name '*-mutate.py' \| wc -l` |
| port `.bend` | `134` (`AGENTS.md:73`, dated) | **134** | `find tinybendygrad -name '*.bend' \| wc -l` |
| `TOOLS.md` paths | `333` (dated) | **333** | `counts.py` |

`134` and `333` still hold — the two the brief named as surviving, because they
were measured rather than asserted. **`gates/*.py` moved AGAIN under me, `54` →
`56`, between two readings minutes apart** — which is the whole argument for an
instrument and against a hand-copied number.

## 1. The population, and what declares it (Doctrine 1)

"The numbers in `AGENTS.md`" is **not** a population until something declares it.
Three declarations exist, all loaded by path:

* **`scan.py:BOUND`** — a regex over the tree's own write sites (the 3 surfaces)
  that binds a number to a unit noun (`files`, `lines`, `paths`, `.py`, …),
  a progress fraction `n/m`, or an `N of M` pair. This is the broad population.
* **`claims.py:ANCHORS`** — `(claim, current, pattern)` rows; each *pattern* is the
  claim's own prose anchor and each *current* is what `citeresolve/counts.py`
  computes. This is the named population, and it is a contract with a generator.
* **`citeresolve/counts.py`** — the existing generator that computes every value.

**A failed declaration is kept as evidence:** `named.py` joins counts to prose **by
bare value**, and a bare `0` or `14` is not a population — it matched ~150 unrelated
occurrences. That is Doctrine 1 reproduced one level down (a *value* is not a
population either), and the file stands as the measurement of why `claims.py` uses
structural anchors instead. **The instrument that cannot see its population cannot
be wrong, because it cannot be anything.**

## 2. The shape, PER NUMBER — not in general

A number in a **prose paragraph** and a number in a **dated reading** want different
answers, and `citeresolve` measured that editing `TOOLS.md` by 6 lines moved two
`AGENTS.md` cites by `+6` (it reverted its own fix: *"the fix manufactured the
defect"*). So the shape is chosen by kind:

| kind of number | shape | why |
|---|---|---|
| a **dated** reading (`550 HARD`, `766/841`, `9 + 7`, `134 @ 7f70b475`) | **(a) leave it; it is EVIDENCE** | it records what was true; a later measurement must not falsify it |
| a **live** named count with a re-derivation rule (`21 .py`, `153/180/96`, `139` declared, `403 remain`) | **(b) GENERATED into the file** | so it cannot rot — see §3 |
| a live number with **no** rule (`16/14 INSTRUMENTS`, `kind()` classifier counts) | **(c) cite the instrument, drop the number** | the two classifiers (`kind()`, `lostinst`) disagree and neither is `counts.py`'s rule |
| a **whole status block** (`TODO.md`'s `no-txt` header) | **(b) regenerate the block** | editing one number inside it makes a mixed-provenance line |

`AGENTS.md:22`'s `TOOLS.md:51-52` and `AGENTS.md:145`'s `TOOLS.md:645` are DRIFT
into `TOOLS.md` (`:65-66`, `:651`), reported by `citeresolve` for the AGENTS owner —
**not touched here** because they are citations, not counts, and re-pointing them is
authoring.

## 3. THE INSTRUMENT — `check.py`, and the declaration it reads

`check.py` is the `checks/disagree-gate.py` `(path, must_contain, why)` shape
`citeresolve` recommended, with the number optional: a `PIN` row is
`(file, line, regex-with-capture, counts.py key)`. The checker recomputes the value
from `counts.py` **and asserts the pinned line still carries it**:

* line MOVED → the regex misses → **FAIL (moved)** — loud, not a silent wrong answer;
* line holds an old value → **FAIL (stale)**;
* else **PASS**. `counts.py` unimportable → **REFUSED (3)**; no pins → **SKIP (4)**.

The population is `PIN`, a declaration in code, loaded by path. **Cost of the three
options:** an in-code `PIN` (chosen) is 6 rows and the smallest diff, but a
`(file, line)` pin rots when lines move — that is why it FAILS LOUDLY rather than
silently. A `MANIFEST.tsv` would separate data from code but adds a second file and
a parser. A marker in the prose itself (e.g. a `<!-- live:key -->` comment) makes
the number self-describing but edits the governing prose to instrument it, and
`AGENTS.md` is a document restated by other documents — one witness, not two.

MEASURED GREEN: `.venv/bin/python .agents/slop/livenum/check.py` → `pins=6 fails=0
PASS` (rc=0).

## 4. THE LANDINGS — 6 live numbers, line-count-neutral, with the reading

Every edit is **in-line**: no line added or removed, so no `file:<N>` cite can
shift. Line counts before and after: `AGENTS.md` **466**, `.agents/TOOLS.md`
**1548** (`wc -l`; untracked), `.agents/TODO.md` **13661**.

| file:line | was | now | method attached |
|---|---|---|---|
| `AGENTS.md:96` | `139` ×3 (`differ.declared()`) | **175** | `(2026-10-07; len(differ.declared()))` |
| `AGENTS.md:131` | `21 .py, 0 .sh` | **56 `.py`, 0 `.sh`** | `(measured 2026-10-07: … ls gates/*.py \| wc -l)` |
| `AGENTS.md:140` | `153 are present` | **164 are present** | `(2026-10-07)` |
| `AGENTS.md:141` | `180 are gone` / `96 of those` | **169** / **85** | same reading |
| `.agents/TODO.md:11` | `403 remain, 402 of them other units'` | **0 unexcused remain** | `(2026-10-07, checks/no-txt.py rc=0)` |

**LEFT ALONE as dated evidence: 40 named-anchor occurrences (and 324 broad).**
Counted by `claims.py`: `AGENTS.md` 22, `.agents/TOOLS.md` 8, `.agents/TODO.md` 10.
The load-bearing ones: `AGENTS.md:41,123` (`2026-10-06 13:00`, the `550 HARD / 139
EXCUSED` reading), `:129` (`766 @ 13:00, 841 @ 13:03`), `:259` (`survive at
2026-10-06 13:00`), `:10,178` (`333 paths … at 2026-10-06 13:00`), `:71` (`the 138
is the FROZEN … reading (2026-10-05 20:59)`), `:73` (`134 … as of
2026-10-06T12:19Z, HEAD 7f70b475`), `:9,211,297` (the 34-graph corpus readings).

**LEFT ALONE as live-but-correct:** `AGENTS.md:179` (`17 checks/*.sh`), `:114`
(`RETURNS 4`), `:240` (`93 lines`), `:253` (`8 files`), `.agents/TOOLS.md:12-13`
(`333/164/169/85`, landed by `citeresolve`; **not re-done**).

**REPORTED, NOT EDITED — one live number inside a dated block:** `AGENTS.md:47`,
`The 139 are excused by differ.declared()`. Its own line carries no date, but it
sits in the paragraph at `:40-49` headed *"as measured 2026-10-06 13:00"*, and
`:99` dates the same block. Editing it would falsify the dated reading it belongs
to, so it is left and named here. **A live number can live inside a dated
paragraph, and the paragraph wins.**

**REPORTED, NOT EDITED — the classifier counts:** `AGENTS.md:12,141` assert `16`
instruments (`kind()`'s count) and `14` by content (`lostinst`'s). `counts.py`'s
rule gives **6**. Three rules, three answers; replacing one with another would
conflate classifiers. Shape (c): the number should be dropped and the instrument
cited, which is a rewrite of the passage, not an in-place edit.

## 5. THE PIN — a citation to a live artifact is true and false in one paragraph

`D0-run-summary.txt` READ `FAIL` then `OK` four minutes apart (a live artifact). At
this reading (mtime **2026-10-07 05:45:17**) it reads `graphs=34`,
`oracle-selfcheck=# ORACLE SELFCHECK: OK` — i.e. OK **now**, which is a claim about
whatever the last runner wrote.

**Cited live artifacts in the 3 owned surfaces: 46 distinct paths** carry
`runs/` or `gates/artifacts/` or a generated-artifact name. By the mechanical
`<path>:<N>` rule in `scan.py` the count is **4 citations** —
`runs/graphcmp/D/D0-coverage-census.txt` ×3 and `runs/graphcmp/D/D1-graph-mselect.txt` ×1
— because most live artifacts are named **without a line number**.

The named live artifacts (the load-bearing ones): `runs/graphcmp/D/D0-run-summary.txt`,
`runs/graphcmp/D/D0-coverage-census.txt`, `runs/graphcmp/D/D0-ops-probe.txt`,
`runs/graphcmp/D/*.txt`, `runs/graphcmp/C*.txt`, `gates/artifacts/`,
`gates/artifacts/*/{bd,bn,py}.txt`, `runs/` as a directory, `oracle-selfcheck=…`.
**A citation to one of these is true and false in the same paragraph.** The fix is
to cite the **generator and `D0-run-summary.txt`'s mtime**, not the file's line:
`.venv/bin/python checks/differ.py run` produced the current one, and the summary's
own `oracle-selfcheck=` line is the datum.

## 6. THE PLANT — the check that is the whole deliverable

**Zero citations moved.** `resolve.py` reads the four surfaces from the working
tree and resolves every `<path>:<N>`; the before/after files are byte-identical.

| reading | surface set | citations | movement |
|---|---|---:|---|
| before edits | 4 surfaces | **2 459** | — |
| after edits | 4 surfaces | **2 459** | **0** (`diff` empty) |

sha256 before: `68e904dfd192a5a756e8fe7ed1fa0507ba542c3cdccad0c4ae1b76a32731e632`.

The line-count-neutral edit is the mechanism: a citation is `file:<N>`, so only a
line added or removed can move one, and none was. **`citeresolve` reverted its own
fix for exactly this — the fix manufactured the defect — so the edit shape is the
deliverable and the diff is its proof.**

**And the checker is falsifiable** (else it is trusted for nothing): planting the
old value `21` back onto pinned `AGENTS.md:131` gives
`FAIL AGENTS.md:131 gates/*.py: asserts 21, counts.py says 56`, rc=1; restoring the
exact bytes gives `pins=6 fails=0 PASS`, rc=0, and the file is **byte-identical to
its pre-plant self**.

## 7. Artifacts (all under `.agents/slop/livenum/`)

* `scan.py` / `nums.tsv` — the broad measure-claim scan (1 452 claims; LIVE/DATED).
* `claims.py` / `claims.tsv` — the named re-derivable counts, by anchor (88 hits).
* `named.py` — the value-join that failed, kept as the measurement of why.
* `live.py` / `live.rows` — every LIVE named occurrence, file:line, ONE-LINE command.
* `resolve.py` / `cites-before.tsv` / `cites-after.tsv` — 2 459 citations, 0 moved.
* `check.py` — the location-pin checker (`pins=6 fails=0 PASS`).
* `counts.rows` — `citeresolve/counts.py`'s reading at this HEAD, mtime-stamped.

The single generalisable finding: **a live number belongs in an instrument or in a
dated sentence, never asserted in prose — and a claim about a generated file must
carry the file's MTIME, because a citation to a live artifact is true and false in
the same paragraph.**
