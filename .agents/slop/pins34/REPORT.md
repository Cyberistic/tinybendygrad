# PINS34 — the rows of `D0-run-summary.txt`, and the denominators that cannot move

**SUBJECT.** `checks/differ.py`'s `PINS` table (`:248-294`) and the `write("D0-run-summary.txt", …)`
call that produces the rows it compares against (`:927-991`). Every claim below is measured from the
writer's own source by `ast.parse`, and every "what would it read if the subject grew" reading is
produced by **executing the writer's own helper functions** (`text`, `lines_with`, `anchored`,
`files_with`, `grep_line`, `first_line`, `last_line` — `:464-506` and `:1263-1268`) over a fixture
copy of the live artifacts. Nothing here is a re-implementation of a count and nothing is predicted.

| | |
|---|---|
| instrument | `.agents/slop/pins34/enumerate.py` (this directory), output captured in `enumerate.out` |
| writer read | `checks/differ.py`, blob `162ddf3332467e95cf645df7e97106c4d9b76706` |
| blob check | `git hash-object checks/differ.py` == `git rev-parse HEAD:checks/differ.py` == `162ddf33…` — the file measured is byte-identical to the one HEAD carries, at **all three** HEADs below |
| HEAD at start | `e92adbb5cc1023eb6e2b7e2801a0a7c5e5cd27de` (2026-10-18T18:45:45Z) |
| HEAD at end | `5f31663e48e7c6f57d309001d4b9861c4faeea45` (2026-10-18T18:55:03Z) — **HEAD moved TWICE under this session** (25 s in, and again at 18:55Z); `checks/differ.py`'s blob is `162ddf33…` at all three, which is why every measurement below is pinned to the blob and not to a HEAD |
| stamped | 2026-10-18T18:49:28Z (enumerated) / 2026-10-18T18:56:12Z (HEAD re-read) |
| run read | `runs/graphcmp/D/D0-run-summary.txt`, mtime 2026-10-18T21:22:18 local = 18:22:18Z, 25 keys |
| caveat | the index is ARMED: `git diff --cached --name-only` names **139** paths (138 at 18:54Z) against a 1 408-entry `git status --porcelain=v2`. "HEAD" therefore does not identify this tree; the blob hash above does. Every git read here was `env -u GIT_INDEX_FILE` and every other read was a file read. No git state was mutated, and nothing here was committed |
| not run | no `bend`, no `graphcmp`, nothing under `gates/`, no `checks/differ.py` execution, no `differ run/repro/plant`. `differ.py` was parsed, never imported. |

---

## 1. THE CONTROL — does the writer's key list equal the live file's key list?

**PASS, exactly, in both set and order.** Measured:

```
writer rows in source: 19 + 4 precondition + 2 substrate = 25
live keys:             25
same set:              True
same order:            True
only in writer:        none
only in live file:     none
starred rows:          ['precondition_rows()', 'substrate_rows(substrate_start, substrate_digest())']
```

19 keys are the `f"key={expr}"` literals inside the one `write(...)` list; 4 are
`precondition_rows()` (`dev` + `ROW_VALUES`, read off that function's own return statement, not
retyped); 2 are `substrate_rows(...)` (`SUBSTRATE_ROWS`). `PINS` names 17 of the 25 and **every one
of the 17 is a row the writer writes** (`pinned-but-unwritten: none`) — so no pin is DEAD on a
missing key. Eight rows are written and unpinned: `dev`, `graphs-disagree`, `graphs-refused`,
`lc_all`, `noopt`, `pythonhashseed`, `substrate-start`, `substrate-end`.

**A PRIOR UNIT'S NUMBER IS OFF BY ONE.** The brief records "7 of the 24 summary rows". Measured now:
**7 of 19 direct rows carry a code-resident denominator, and the file carries 25 keys, not 24** —
`graphs-refused` was added to the writer at 18:04Z today (`differ.py:961`, its own comment dates the
change). The 7 is right; the 24 is a stale denominator for the very claim this report is about.

`rows.rows` (this directory) lists all 25 rows with the same five fields; `diff` of its first column
against `cut -d= -f1` of the live summary is empty, 25/25.

---

## 2. CLASSIFICATION — every row, and where its denominator lives

Full table with evidence: **`rows.rows`** (TAB-separated). The four sources asked for, and which rows
carry each:

| denominator source | rows | count |
|---|---|---|
| **CODE-RESIDENT LITERAL** — `of N` typed inside the f-string | `stable-pairs` `stable-failed` `stable-differ` (`of 5`), `plants-disagree` (`of 7`), `cross` (`of 1`), `conflations` (`of 4`), `controls` (`of 5`) | **7** |
| **DERIVED-FROM-TREE-FILE** — `len(corpus())` → `graphcmp.GRAPHS` (`:89-111`, `:716`) | `graphs` | 1 |
| **MEASURED-FROM-THE-RUN** — numerator counted off artifacts; denominator is 1, the artifact | `graphs-answered` `graphs-unset` `expect-moved` `graphs-refused` `graphs-agree` `graphs-disagree` `byte-identical` `not-comparable` `selfcheck` `oracle-selfcheck` `census-rc` `substrate-start` `substrate-end`, plus `dev` (derived from the artifacts by `device_of_run()` and checked against them rather than pinned) | 14 |
| **PINNED-EXPECTATION** — the row's own string, or `ENV`, compared verbatim by `PINS` | `lc_all` `noopt` `pythonhashseed` (and every other row's pin, since `:1347` compares the whole `key=value` string for equality) | 3 direct |

Two facts about the comparison that the risk analysis rests on, both read from the source:

- `:1347` — `unhealthy()` compares `[f"{k}={v} (expected {PINS[k]})" for k, v in got.items() if k in PINS and v != PINS[k]]`.
  **Exact string equality on the whole row**, so the typed `of N` is part of the compared string and
  cannot be re-typed without the pin going red. That is fail-safe in one direction only.
- the numerator of each of the 7 is written differently, and the difference decides whether a growth
  is even *visible*:

| row | numerator | sees a new MEMBER? | sees a new FILE? |
|---|---|---|---|
| the `stable-*` trio | `anchored`/`lines_with` over `D9-stability.txt` | **yes** — the writer appends one line per `STAB` member (`:866-877`) | n/a (one file) |
| `plants-disagree` | `files_with('D5-plant-*.txt', …)` | yes | yes (glob) |
| `controls` | `files_with('D3-control-*.txt', …)` | yes | yes (glob) |
| `conflations` | `lines_with('D7-conf.txt', …)` | yes (same file) | n/a |
| `cross` | `lines_with('D4-cross-range.txt', …)` | yes (same file) | **NO — measured `seen only by: []`** |

---

## 3. THE 7 CODE-RESIDENT ROWS — measured

### 3a. What they read now, and whether the literal agrees with the writer's own declarations

Measured with the writer's helpers exec'd over a copy of the live artifacts. Every one of the seven
reproduces the live row **byte for byte**, and all seven match their pins today:

| row | measured now | live file | pin | pin matches |
|---|---|---|---|---|
| `stable-pairs` | `5 of 5` | `5 of 5` | `5 of 5` | yes |
| `stable-failed` | `0 of 5` | `0 of 5` | `0 of 5` | yes |
| `stable-differ` | `0 of 5` | `0 of 5` | `0 of 5` | yes |
| `plants-disagree` | `7 of 7` | `7 of 7` | `7 of 7` | yes |
| `cross` | `1 of 1` | `1 of 1` | `1 of 1` | yes |
| `conflations` | `4 of 4` | `4 of 4` | `4 of 4` | yes |
| `controls` | `5 of 5` | `5 of 5` | `5 of 5` | yes |

The literals are **correct today**, which is the trap: a correct constant looks exactly like a derived
one until the subject moves.

Population size as the writer's own declarations count it (structural, not `eval`):

```
len(STAB)=5   len(PLANTS)=7   len(CONTROLS)=5   run(...,'cross',...) call sites=1
literal 'of 5' vs len(STAB)=5 | 'of 7' vs len(PLANTS)=7 | 'of 5' vs len(CONTROLS)=5 | 'of 1' vs 1
conflations: NO differ.py declaration names this population at all
```

So **five of the seven rows duplicate a declaration that already exists in the same file** — the
three `stable-*` rows duplicate `len(STAB)`=5, `plants-disagree` duplicates `len(PLANTS)`=7,
`controls` duplicates `len(CONTROLS)`=5 — and **two (`of 1`, `of 4`) duplicate nothing**: `of 1`
corresponds to a single hardcoded `run(...)` call at `:849`, and `of 4` corresponds to nothing in
`differ.py`: the conflation population lives in `graphcmp.py`'s `cmd_conf`, which emits one
`# CONFLATION n VERDICT:` line per case and is not a list `differ.py` can read.

**AND `of 5` IS ONE CONSTANT DOING TWO UNRELATED JOBS.** The same typed `5` is simultaneously
`len(STAB)` and `len(CONTROLS)`, two populations with nothing in common. So growing either
population leaves a *correct-looking* `of 5` in the other three rows — a reader who finds `5 of 5`
green has no way to know which of the two questions it answers. That is one more reason the minimal
fix (`of {len(STAB)}` / `of {len(CONTROLS)}`) is worth more than the arithmetic it repairs.

### 3b. What each row would read if its subject grew by one

One new member per axis, appended to a fresh copy of the live artifacts, counted by the writer's own
predicate, compared to the writer's own pin with the writer's own `!=`. `FIRES` = the pin goes red;
`SILENT` = the pin stays green.

| row | +1 GOOD member (the one the row counts) | +1 BAD member (the one the row exists to catch) |
|---|---|---|
| `stable-pairs` | `6 of 5` → FIRES | differing pair → `5 of 5` → **SILENT**; 0-row pair → `5 of 5` → **SILENT** |
| `stable-failed` | identical or differing pair → `0 of 5` → SILENT | 0-row pair → `1 of 5` → FIRES |
| `stable-differ` | identical or 0-row pair → `0 of 5` → SILENT | differing pair → `1 of 5` → FIRES |
| `plants-disagree` | load-bearing plant (DISAGREES) → `8 of 7` → FIRES | **plant that AGREES → `7 of 7` → SILENT** |
| `cross` | second OK range in the same file → `2 of 1` → FIRES | failing range in the same file → `1 of 1` → **SILENT**; a failing range in a **new file** → `1 of 1` → **SILENT** and read by no row at all |
| `conflations` | fifth OK conflation → `5 of 4` → FIRES | fifth DISPUTED → `4 of 4` → **SILENT** |
| `controls` | sixth OK control → `6 of 5` → FIRES | **sixth FAILING control → `5 of 5` → SILENT** |

**The `stable-*` trio is the one axis where per-row silence is covered by siblings.** Measured as a
set of three pins:

```
+ stab-identical  trio reads {stable-pairs: 6 of 5, stable-failed: 0 of 5, stable-differ: 0 of 5} -> red on stable-pairs
+ stab-differ     trio reads {stable-pairs: 5 of 5, stable-failed: 0 of 5, stable-differ: 1 of 5} -> red on stable-differ
+ stab-0row       trio reads {stable-pairs: 5 of 5, stable-failed: 1 of 5, stable-differ: 0 of 5} -> red on stable-failed
```

Every growth variant is caught by exactly one member of the trio, because the three numerators
partition `D9-stability.txt` and the trio sums to `len(STAB)`.

### 3c. What the corpus-growth rows do (the ones that are NOT the subject)

Measured by supplying the writer's expressions with one more graph and one more `D1-graph-*.txt` /
`D2-bytediff.txt` line:

| corpus case | pins that go red | rows that moved |
|---|---|---|
| as published (the live run) | `graphs-agree`, `byte-identical`, `census-rc`, `oracle-selfcheck` | — |
| **+1 graph, agrees** | `graphs` (35), `graphs-answered` (35), + the 2 already red | `graphs-agree`→34, `byte-identical`→34 |
| +1 graph, disagrees | `graphs`, `graphs-answered`, `expect-moved`, `graphs-agree`, + the 2 already red | `graphs-agree`→33, `graphs-disagree`→1 |
| +1 graph, no expectation | `graphs`, `graphs-unset`, `graphs-agree`, `byte-identical`, + the 2 | `graphs-unset`→1, `graphs-answered`→34 |
| +1 graph, refused | `graphs`, `graphs-answered`, `graphs-agree`, `byte-identical`, + the 2 | `graphs-refused`→2 |

**So a corpus growth is caught — twice, by `graphs` and `graphs-answered`** — and the two "agreement"
pins go *green at exactly their pin value* (`34 == 34`) in the healthy-growth case. That is a
coincidence of arithmetic (33 + 1), not a defence: nothing about those two pins detects the growth,
they are simply out of range in the other direction. **No bare-count pin in this file is a
false-agreement risk, and every one of them fails SAFE** (a stale literal is red, not green).

---

## 4. THE FALSE-AGREEMENT LIST

Named, in the order of how badly they lie. "Sees the growth" means the numerator alone, before any
proposal.

| # | pin | the scenario that stays GREEN | how badly | sibling covers it? |
|---|---|---|---|---|
| 1 | **`cross` = `1 of 1`** | a second cross range, anywhere. Measured twice over: failing range appended to `D4-cross-range.txt` → `1 of 1` GREEN; a failing range in a **new** file `D4-cross-newsix.txt` → `1 of 1` GREEN **and read by no row in the file** (`seen only by: []`) | the row is 100% green over a wrong artifact set, and there is no second reader | **no** |
| 2 | **`plants-disagree` = `7 of 7`** | an 8th plant that AGREES → `7 of 7` GREEN. This is the exact defect the pin exists to catch — "a plant that agrees is a plant that is not load-bearing" (`differ.py:224`) — and adding one makes it invisible | the health claim about plants becomes false while reading true | **no** |
| 3 | **`controls` = `5 of 5`** | a 6th control that FAILS → `5 of 5` GREEN | "5 of 5 controls" becomes a claim about 5 of 6 | **no** |
| 4 | **`conflations` = `4 of 4`** | a 5th conflation that is DISPUTED → `4 of 4` GREEN | "all four conflations distinguished" is pinned as `4 of 4` while a fifth is not distinguished | **no** |
| 5 | `stable-pairs` = `5 of 5` | a 6th pair that DIFFERS or has a 0-row side → `5 of 5` GREEN | one row of the trio lies | yes — `stable-differ` / `stable-failed` red |
| 6 | `stable-failed` = `0 of 5` | a 6th pair of either other kind → `0 of 5` GREEN | one row of the trio lies | yes — `stable-pairs` / `stable-differ` red |
| 7 | `stable-differ` = `0 of 5` | a 6th pair of either other kind → `0 of 5` GREEN | one row of the trio lies | yes — `stable-pairs` / `stable-failed` red |

Rows 1-4 are the real defect: **a pin that reads OK while the subject had actually grown.** Rows 5-7
are a per-row defect with a set-level cover, and they should be fixed with the same one-token change
as 2 and 3, so nobody has to remember that they come as a set.

**AND THE RUN IS ALREADY RED, WHICH IS NOT THE SAME AS BROKEN.** `PINS` is **13 of 17** green against
the live summary: `graphs-agree` 33/34, `byte-identical` 33/34, `census-rc` rc=1/rc=0,
`oracle-selfcheck` `# ORACLE SELFCHECK: FAIL`/`# ORACLE SELFCHECK: OK`. All seven of the
code-resident pins are green — so the denominators that cannot move are currently the seven
*quietest* pins in the table, and the four red ones are red for reasons this report does not address.
(This report does not diagnose the four reds; it only measures which pins fire under a perturbation.)

---

## 5. PROPOSALS — minimal, per risky pin. NOT IMPLEMENTED.

Each is one expression inside the one `write(...)` list, uses a helper or a declaration that already
exists in the file, adds no row and no pin, and every denominator it derives is either **(a) the
generator's own declaration, loaded from the same module** or **(b) a measurement of the same
artifact the numerator reads** — so no proposal adds a hand list, which is `AGENTS.md` doctrine 1.

| # | pin | minimal change | why it is enough (measured) |
|---|---|---|---|
| 1 | `stable-pairs` | `:966` `of 5` → `of {len(STAB)}` | `STAB` is what `:862` iterates, so denominator and population are the same object. A 6th member makes the row `N of 6`: identical → `6 of 6` (green only if all six are), differing → `5 of 6` RED, 0-row → `5 of 6` RED. Silent-green becomes red in every direction |
| 2 | `stable-failed` | `:967` `of 5` → `of {len(STAB)}` | same token; a 0-row 6th member reads `1 of 6` instead of `1 of 5` — it already fires, and now the denominator stops lying about how many pairs exist |
| 3 | `stable-differ` | `:968` `of 5` → `of {len(STAB)}` | same token, same reason |
| 4 | `plants-disagree` | `:971` `of 7` → `of {len(PLANTS)}` | an 8th plant that agrees reads `7 of 8` RED — the non-load-bearing plant can no longer hide behind a constant |
| 5 | `controls` | `:975` `of 5` → `of {len(CONTROLS)}` | a 6th failing control reads `5 of 6` RED |
| 6 | `conflations` | `:974` derive it from the same artifact: `f"{lines_with('D7-conf.txt', 'VERDICT: OK')} of {anchored('D7-conf.txt', r'^# CONFLATION \d+ VERDICT:')}"` | `anchored` already exists (`:479`) and counts every case line whether OK or not, so the denominator cannot be wrong about the population. **Rejected alternative:** typing the count the oracle prints — that is a second declaration of a population in a second file, which is doctrine 1's original sin |
| 7 | `cross` | **two** changes, because the numerator is blind too. (a) declare `CROSS = ("range",)` beside `CONTROLS` and loop `for g in CROSS: run(f"D4-cross-{g}.txt", "cross", "--graph", g)` in place of `:849` — for `g="range"` that writes today's `D4-cross-range.txt`, so nothing about the current run changes; (b) `files_with('D4-cross-*.txt', 'CROSS VERDICT: OK') of {len(CROSS)}` | (b) alone is not enough and (a) alone is not enough: measured, a second member's artifact is read by **no row**. With both, a second range is counted whether it lives in a new file or the old one. Caveat: (a) also means a future member's name joins `LITERALS` (`:351`), which is the declaration living with its generator — the reason this is one declaration and not a second hand list |

**NOT PROPOSED, deliberately.** `graphs` / `graphs-answered` / `graphs-unset` / `expect-moved` /
`graphs-agree` / `byte-identical` / `not-comparable`: their numerators already move with reality and
their pin is a literal that a growth forces a human to re-take. That is the stated design
(`differ.py:283-290`, "a pin that is lower than its subject is not a stricter gate, it is a stale
one") and it fails safe. Changing them would be churn against a shape that is already correct.

**AND THE PINS THEMSELVES STILL NEED RE-TAKING BY HAND.** `:1347` compares the whole row string, so
`PINS['cross'] = "1 of 1"` will red the first time `CROSS` has two members — which is the correct
direction, and is why no proposal here touches `PINS`.

---

## 6. THE SECOND WITNESS CARRIES ITS OWN COPY OF EVERY LITERAL

`.agents/slop/pinindep/derive.py` re-derives `D0-run-summary.txt` from the artifacts and is the
control that is supposed to catch a transcription error in these rows. Measured by `ast`:

```
derive.py re-derives 18 named rows + precondition_rows(); writer writes 25
keys the writer writes and derive.py does not: ['graphs-refused']
`of N` literals re-typed in derive.py: ['of 5', 'of 5', 'of 5', 'of 7', 'of 1', 'of 4', 'of 5']
same multiset as the writer's: True -- writer {'of 5': 4, 'of 7': 1, 'of 1': 1, 'of 4': 1},
                               derive {'of 5': 4, 'of 7': 1, 'of 1': 1, 'of 4': 1}
derive.py docstring claims the live summary carries: ['24']  writer writes 25
```

Three facts, all measured:

1. **`derive.py` re-types all seven denominators** (`derive.py:78, 81, 84, 98, 99, 101, 102`). Its
   byte-identity self-check can therefore catch the two copies *diverging*, but it can never catch
   **both being stale together** — which is precisely the failure mode in §4. The control inherits the
   defect it exists to find.
2. **`derive.py` is already out of date**: it does not re-derive `graphs-refused`, added to the writer
   today, so its `live_only` arm must be firing today.
3. Its docstring's "the live summary carries 24" is 25. A count in a comment, with no instrument.

**Consequence for the proposals:** fixing `differ.py:966-975` alone leaves `derive.py` transcribing the
old literals and going red for the wrong reason. Whatever is done must be done to both, or `derive.py`
must stop carrying the strings at all (derive the denominator the same way, or read the writer's own
`f`-string). This is the one place where "minimal change" is not one edit.

`.agents/slop/pinindep/sens.py:111-117` is an existing instrument that already asks "is `of N` a
constant or a derived count?" for four of the seven. Measured caveat about it: for `cross` and
`conflations` it answers against `1` and `4` that **it typed itself** (`("cross", "of 1", 1)`), so for
those two it is a tautology — it can never disagree, which is the same shape as the second copy above.

---

## 7. WHAT THIS DOES NOT MEASURE (REFUSED, not guessed)

- **Whether `derive.py`'s `selfcheck()` is green right now.** It would require importing and executing
  `checks/differ.py` and `graphcmp.py`, which this brief forbids. Every `derive.py` claim above is
  `ast`-level and certain; its *runtime* state is **UNMEASURED**.
- **Whether a real run with 6 stability pairs / 8 plants would behave as the fixture predicts.** The
  growth readings are the writer's own counting predicates over synthetic artifacts — a computation
  over the code, not a `differ.py run`, and no `bend` was executed. Every row's "reads NOW" column was
  validated against the live file byte for byte, which is what makes the synthetic step trustworthy.
- **Why the live run is red on 4 pins** (`graphs-agree` 33, `byte-identical` 33, `census-rc` rc=1,
  `oracle-selfcheck` FAIL). Out of scope; recorded only so no reader mistakes "13 of 17 green" for a
  verdict about the port.
- **The other consumers** of this summary (`checks/corpus-figure.py:72`, `gates/retention-check.py`
  clause IV, `checks/disagree-gate.py:128`, `checks/env-precond.py` method B, `gates/corpusverdict-gate.py:67`,
  `gates/prose-census.py:314` parses `graphs-agree=(\d+)`). Whether any of them would notice a changed
  denominator is not measured. The one that matters most is named: **`gates/prose-census.py:314` reads
  `graphs-agree=(\d+)` out of this file**, which is a bare-count row and therefore unaffected by all
  seven proposals.

---

## 8. FILES

| file | what |
|---|---|
| `enumerate.py` | the instrument. `ast.parse` only; execs the writer's own `text`/`lines_with`/`anchored`/`files_with`/`grep_line`/`first_line`/`last_line` over a fixture copy. `differ.py` is never imported |
| `enumerate.out` | its captured output (132 lines) — every table in this report is a copy of a block here |
| `rows.rows` | 25 rows × 5 TAB-separated fields: `row`, `denominator_source`, `moves_with_reality`, `false_agreement_risk`, `evidence` |
| `fixture/` | **not present.** The readings are taken over a copy of `runs/graphcmp/D`, and that copy is 100 `.txt` artifacts — `checks/no-txt.py` counts owned `.txt`, so a left-behind fixture would be 100 new rows in a census this tree is trying to drive to zero. `build_fixture()` rebuilds it from the live artifacts at the start of every run and the instrument deletes it at the end |
| `REPORT.md` | this file |