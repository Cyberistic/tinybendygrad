# run34 — the first run over the 34-graph corpus, and the substrate that broke under it

**Reading taken 2026-10-06.** `bend` is the unit's own; no other `bend` was started. Nothing
committed, nothing `git add`ed. Owned files edited: `checks/differ.py` (`WANT` `:124`, `PINS`
`:228`). Not touched: `gates/`, `AGENTS.md`, `.agents/slop/graphcmp.{py,bend}`, `tinybendygrad/`.

---

## 1. The run's own entry point, the command, and the expected artifacts

`checks/differ.py run --help` reads only `usage: checks/differ.py run [-h]` — the choice of
artifacts is not a flag; it is the driver's fixed output contract. `checks/README.md` is the
inventory (it exists so this is not guessed). `run` prints one line (`wrote runs/graphcmp/D`) and
the artifacts ARE the output; `D0-run-summary.txt` is read first because it is the run's verdict.

| artifact (each also has a `.txt.err`, legitimately empty) | what |
|---|---|
| `D0-selfcheck.txt` | the differ's own selfcheck; must be `# SELFCHECK: OK` |
| `D1-graph-NAME.txt` | one `# VERDICT:` under one `# DENOMINATOR:` per graph |
| `D1-verdicts.txt` | every graph's verdict ASSERTED against `WANT` |
| `D2-canon-{py,bend}-NAME.txt` | the canonical row stream per side |
| `D2-cmp-NAME.txt`, `D2-bytediff.txt` | py vs bend byte for byte |
| `D3-control-NAME.txt` | each side against ITSELF |
| `D4-cross-range.txt` | one graph against a different graph |
| `D5-plant-NAME.txt` | 7 plants that must DISAGREE |
| `D6-NAME-{ordered,equiv}.txt` | one reordered fixture, two comparison rules |
| `D7-conf.txt` | 4 conflations |
| `D8-dbg-012.txt`, `D8-dbg-03.txt` | DEBUG-level comparison |
| `D9-stability-NAME-{a,b}.txt`, `D9-stability.txt` | 5 two-run pairs |
| `D10-zerorow-guard.txt` | the 0-row guard, fired on purpose |
| `D0-coverage-census.txt` | the both-sides coverage denominator, with its own `rc=` |
| `D8b-cpython-dbg1-reachability.txt`, `D0-ops-probe.txt` | CPython reachability / raw ops |
| `D0-run-summary.txt` | the run's verdict, one `key=value` per line |

Command actually run:

```
.venv/bin/python checks/bounded.py --seconds 3600 --mb 2048 -- .venv/bin/python checks/differ.py run
```

## 2. Verdict token and wall time

```
[bounded] WITHIN-LIMITS  rc=1  peak-RSS=771 MB (ceiling 2048)  294s
          :: .venv/bin/python checks/differ.py run  out=22B err=669B
```

Start `2026-10-06T12:32:55Z`, end `2026-10-06T12:37:53Z` (`298 s` wall; the guard's own bound was
`294 s`). **`WITHIN-LIMITS`, not `TIMED-OUT`** — the corpus is not too big to run; the whole run is
under 5 minutes. The child's `rc=1` is the driver's own refusal (`RUN INCOMPLETE` + `RUN WRONG`),
not the guard's.

## 3. Every row of `D0-run-summary.txt`, as READ

```
graphs=34              graphs-answered=20     graphs-unset=14     expect-moved=3
graphs-agree=28        graphs-disagree=5      byte-identical=28   not-comparable=0
stable-pairs=0 of 5    stable-failed=5 of 5   stable-differ=0 of 5 plants-disagree=0 of 7
cross=0 of 1           selfcheck=# SELFCHECK: OK  conflations=4 of 4  controls=0 of 5
oracle-selfcheck=      census-rc=rc=1          dev=CPU  lc_all=C  noopt=0  pythonhashseed=0
```

`graphs=34` is `len(corpus())`, read as asked-for (as designed). `dev=CPU`, `lc_all=C`,
`noopt=0`, `pythonhashseed=0` — the four precondition rows are present and match `ENV`.

## 4. The five DISAGREEING graphs (+ one FAILED), with the disagreeing row and both values

`graphs-disagree=5`: **`flip`, `mselect`, `stage`, `unshard`, `wmma`**. `graphs-agree=28`.
`getaddr` is the 34th: `D1-graph-getaddr.txt` is `rc=2` with **no `# VERDICT:` line** — a FAILED
graph, neither AGREE nor DISAGREE.

| graph | first row | py | bend | class |
|---|---|---|---|---|
| `flip` | 6 (`6c6,7`) | `FLIP … arg=n(b1,b0)` | `FLIP … arg=n(i1,i0)` + a `GROUP#7` | WRONG VALUE, arg |
| `mselect` | 9 (`9c9`) | `MSELECT … arg=i0` | `MSELECT … arg=y n(i0)` | WRONG VALUE, arg (int stored as ABlob) |
| `stage` | 8 (`8c8`) | `STAGE dtype=f32 shape=(l0:4,l0:3)` | `STAGE dtype=? shape=?` | fold has no STAGE arm |
| `unshard` | 8 (`8c8`) | `UNSHARD dtype=f32 shape=(l0:8,l0:3)` | `UNSHARD dtype=? shape=?` | fold has no UNSHARD arm |
| `wmma` | 11 (`11c11`) | `WMMA dtype=f32 shape=(l0:4,l0:3)` | `WMMA dtype=? shape=?` | fold has no WMMA arm |

`getaddr`: `D2-canon-bend-getaddr.txt` is a single `NOOP … BAD` row (the port's arena bottom, never
interned); `diff --graph getaddr` prints `# devices py=['sCPU'] bend=[] -- NOT WELL-POSED … exit 2`.

**`cdiv` and `late` are two of `expect-moved=3`; the third is `allred`.** `run.err` reads
`allred: VERDICT=AGREE EXPECTED=DISAGREE`, `cdiv: … AGREE EXPECTED=DISAGREE`,
`late: … AGREE EXPECTED=DISAGREE`. The old `WANT` reason for all three (the bend side emitted
matmul's graph) was fixed by `adevfix` + `armfour`; the run adjudicated it. **`allred`'s row-8
prediction in `disagree-gate.py` is FALSIFIED — `allred` AGREES now.**

## 5. `WANT` and `PINS` moved — `file:line`, old → new, GREEN/RED

`checks/differ.py` (`WANT` at `:124`, `PINS` at `:228`). Followed
`.agents/slop/wantwire/REPORT.md`: Phase 0 (`flip allred cdiv late`), Phase 1 (the armed),
Phase 2 (armfour's four, now armed). `WANT` 20 → **33** rows; `getaddr` deliberately stays UNSET.

### `WANT`

| file:line | row | old | new | why |
|---|---|---|---|---|
| `differ.py:161` | `allred` | `DISAGREE` | `AGREE` | measured `BYTE-IDENTICAL`; arm landed |
| | `cdiv` | `DISAGREE` | `AGREE` | ditto |
| | `late` | `DISAGREE` | `AGREE` | ditto |
| `differ.py:165` | `alu bit bw move where threefry mulacc` | *(absent → UNSET)* | `AGREE` | Phase 1, measured byte-identical |
| `differ.py:170` | `custom_function mstack` | *(absent)* | `AGREE` | armfour, measured |
| `differ.py:183` | `mselect stage unshard wmma` | *(absent)* | `DISAGREE` | **RECORDED, not deleted, not pinned AGREE** — each with a named cause |

`flip` stays `DISAGREE` (still disagrees). `getaddr` stays UNSET.

### `PINS`

| file:line | pin | old | new | GREEN/RED now | knows? |
|---|---|---|---|---|---|
| `differ.py:236` | `graphs` | `25` | **`34`** | **GREEN** (`34=34`) | KNOWN — function of `corpus()` |
| | `graphs-unset` | `5` | **`1`** | RED (`14 vs 1`, see §6) | KNOWN — `corpus() − len(WANT)` |
| | `graphs-answered` | `20` | **`33`** | RED (`20 vs 33`) | KNOWN |
| `differ.py:245` | `expect-moved` | `0` | `0` (unmoved) | RED (`3 vs 0`, see §6) | zero-tolerance invariant |
| `differ.py:248` | `graphs-agree` | `21` | **`28`** | **GREEN** (`28=28`) | UNKNOWABLE before the run — measured |
| | `byte-identical` | `21` | **`28`** | **GREEN** | UNKNOWABLE — measured |
| | `not-comparable` | `0` | `0` | GREEN | measured 0 |
| `differ.py:249` | `selfcheck` | `OK` | `OK` | GREEN | — |
| | `census-rc` | `rc=0` | **unmoved** | RED (`rc=1`) | **contaminated** (§6) |
| `differ.py:265` | `stable-pairs` | `5 of 5` | **unmoved** | RED (`0 of 5`) | **contaminated** |
| | `stable-failed` | `0 of 5` | **unmoved** | RED (`5 of 5`) | **contaminated** |
| | `stable-differ` | `0 of 5` | `0 of 5` | GREEN (coincidence) | — |
| `differ.py:266` | `plants-disagree` | `7 of 7` | **unmoved** | RED (`0 of 7`) | **contaminated** |
| | `cross` | `1 of 1` | **unmoved** | RED (`0 of 1`) | **contaminated** |
| | `controls` | `5 of 5` | **unmoved** | RED (`0 of 5`) | **contaminated** |
| `differ.py:267` | `conflations` | `4 of 4` | `4 of 4` | GREEN | — |
| | `oracle-selfcheck` | `OK` | **unmoved** | RED (empty) | **contaminated** |

**Which I did NOT move, and why.** `census-rc`, `stable-*`, `plants-*`, `cross`, `controls`,
`oracle-selfcheck` keep the last HEALTHY run's values. The port went into flux 10 s after the graph
phase ended (§6), so those steps are 0-row failures, not measurements. Pinning them to
`0 of 5`/`0 of 7`/`rc=1`/empty would make the health gate read a broken run as healthy — *"a gate
that exits 0 having measured nothing is worse than no gate."* They return to green on the next run
taken under a settled substrate.

## 6. THE FINDING — the instrument that was green and went RED

**The port was edited MID-RUN.** Artifact mtimes date every step; the port files date the break:

| step | artifact mtime | port edit mtime |
|---|---|---|
| graph `diff`/`emit` done (`D2-bytediff`) | `15:35:04` | — |
| `controls` (`D3-control-matmul`) | `15:35:10` | `render.bend`/`upat.bend` **`15:35:12`**, `ops.bend` **`15:35:24`**, `fold.bend` **`15:39:43`** |
| `cross` / `plants` / `stability` / `census` | `15:35:29 … 15:37:48` | (all after the edits) |

Every step from `control` onward fails with the same line in its `.err`:
`emit bend: 0 rows after 5 attempts -- a FAILURE, not a verdict … Location: argstr 410 / arg_repr 704`.
The tree is broken **right now**: `./bin/bend .agents/slop/graphcmp.bend --check-only`
prints `SOME PROOFS FAIL`, and `tinybendygrad/uop/fold.bend` alone fails to typecheck
(`expected : acc / observed : acc (consumed more than once)`). Another unit (`.agents/slop/foldgap/`)
is editing it. **A re-run now would be worse, which is why none was taken.**

So this run is TWO runs wearing one summary: a CLEAN graph phase (`D0-selfcheck` … `D2-bytediff`,
finished `15:35:04`) and a BROKEN port phase (`D3` onward). The pins in §5 move only the clean
half.

Consequences measured after the `WANT`/`PINS` edits:

| instrument | before run34 | after run34 | verdict |
|---|---|---|---|
| `checks/corpus-figure.py` (`DEV=CPU`) | rc **1**, 16 of 17 pins green, RED only `graphs` | rc **1**, **7 of 17** green | **went RED-harder** — the fresh run is red on 10 pins |
| `checks/disagree-gate.py` COVERAGE | **FAIL** | **ok** rc=0 | **GREEN** (the arms landed) |
| `checks/disagree-gate.py` CITATIONS | ok (`b4dc69094`) | **FAIL** — `graphcmp.bend:776/:1563` moved | **went RED** (another unit's +1 line in `graphcmp.bend`) |
| `checks/disagree-gate.py` PIN | FAIL (stale run) | **FAIL — CRASH** | `names.py` `ValueError: D1-graph-getaddr.txt: no VERDICT line` |
| `checks/disagree-gate.py` PLANT | (crashes with PIN) | **FAIL — CRASH** | same `getaddr` cause |

**The most valuable line: `checks/corpus-figure.py` went from 1 red pin to 10, and
`disagree-gate`'s CITATIONS lane went green → RED — and BOTH are the mid-run substrate break and
another unit's concurrent edit, NOT the corpus.** That is a corpus that learned something the hard
way: a 34-graph run is only a measurement if nothing is writing `tinybendygrad/` while it runs.

**The three "self-inflicted" reds** (`graphs-unset 14 vs 1`, `graphs-answered 20 vs 33`,
`expect-moved 3 vs 0`) are NOT a second break: the on-disk summary was written by the run under
the OLD `WANT` (20 rows), and I wired `WANT` to 33 rows after the fact. A clean re-run under the new
`WANT` reads `graphs-unset=1` (only `getaddr`), `graphs-answered=33`, `expect-moved=0`. **No re-run
was possible (§6), so the summary and the pins disagree on those three until one is.**

## 7. `declared()` — the population, MEASURED (not pasted)

```
.venv/bin/python -c "… import checks/differ.py …; print(len(m.declared()))"
declared(): 175        corpus(): 34        WANT: 33        .tmp names: []
```

- **`wantwire`'s `175 → 231 (+56)` is a miscount.** `declared()` reads `corpus()`, not `WANT`
  (`differ.py:277`), so wiring the 14 answers adds **zero** artifact names. 175 is already the
  34-corpus value: `13 literals + 34 D1-graph + 68 D2-canon + 34 D2-cmp + 5 D3 + 7 D5 + 4 D6 + 10 D9 = 175`.
- **`txtresidual`'s `.tmp.` change did not land in `checks/differ.py`.** `git status` shows it
  UNMODIFIED vs HEAD, `git diff --stat checks/differ.py` is empty, and the measured set contains
  **no `.tmp.` name**. `census.py` agrees: the run writes 136 per-graph names, `declared()` misses 0.

## 8. The plants (the fix that must turn a gate red on purpose)

The four `differ.py` precondition plants are not in this run's output (they are `differ.py plant`,
over a COPY, and need no `bend`). What IS load-bearing here is the plant this run *is*: **one
instrument that was green went RED** (§6) and the run's own `expect-moved` fired on three rows
(`allred cdiv late`) before the `WANT` fix — a table that was behind the port, caught by the
zero-tolerance pin and nothing else.

## What a clean re-run needs (for the next unit)

1. Wait for `ALL PROOFS CHECK` on `.agents/slop/graphcmp.bend` (currently `SOME PROOFS FAIL` —
   `tinybendygrad/uop/fold.bend` is mid-edit by `.agents/slop/foldgap/`).
2. Re-run `checks/differ.py run` (under `bounded.py --seconds 3600 --mb 2048`).
3. Expect `graphs=34 graphs-answered=33 graphs-unset=1 expect-moved=0 graphs-agree=28
   byte-identical=28`. If `foldgap` lands the STAGE/UNSHARD/WMMA arms, the three `DISAGREE` rows
   in `WANT` move to `AGREE` and `expect-moved` fires — by design.
4. `checks/disagree-gate.py`'s PIN lane needs `getaddr` to carry a `VERDICT:` line (or `names.py`
   to tolerate a verdict-less `D1-graph-*.txt`); it crashes today.
