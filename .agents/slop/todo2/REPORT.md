# `.agents/TODO.md` — the state file no unit can safely edit

Subagent `todo2`, 2026-10-06. Instruments are Python under `.agents/slop/todo2/`
(`discover.py`, `index.py`, `bars.py`, `tick.py`). Every count below carries its denominator.
Nothing was ticked (see §8). The orchestrator commits by path; nothing here was `git add`ed.

## 0. Snapshot

Characterisation is of the file **as found**, `sha256 a66cb972697d…`, **13,477 lines /
992,659 B**. After the one change in §5 it is 13,640 lines; the change is a pure EOF append
so lines 1–13,477 are untouched (§7).

## 1. Characterisation BY DISCOVERY

Instrument: `discover.py` (walks the file; skips fenced code blocks when finding headings).

| quantity | value | denominator |
|---|---|---|
| bytes | 992,659 | file |
| lines | 13,477 | file |
| blank lines | 1,301 | of 13,477 |
| heading lines (`#`/`##`/`###`) | 266 | of 13,477 |
| — `#` | 1 | 266 |
| — `##` | 183 | 266 |
| — `###` | 82 | 266 |
| task items (`- [ ]`/`- [x]`/`- [~]`) | 1,317 | of 13,477 |
| — `[x]` done | 1,074 | 1,317 (81.55%) |
| — `[ ]` open | 239 | 1,317 |
| — `[~]` indeterminate | 4 | 1,317 |
| level≤2 sections | 184 | file |
| — carrying ≥1 task | 154 | 184 |
| level-3 subsections with tasks | 43 | 82 level-3 |

The file's own header (line 3) declares the convention: *"Progress bars are `[###.....] n/m`"*.

## 2. The `AGENTS.md` bar claim — VERIFIED

> `AGENTS.md`: `rg -c '[█▓▒░]' .agents/TODO.md` = **12 lines**

**TRUE at the snapshot: 12 lines, 191 bar glyphs.** But it is a weak instrument:

| bar convention | lines | of | where | who wrote it |
|---|---|---|---|---|
| block glyphs `[█▓▒░]` | 12 | 13,477 | 11 in session prose, 1 mid-sentence | hand-typed |
| ASCII `[#...]` | 62 | 13,477 | 18 in the header dashboard, 44 in prose | hand-typed |
| header dashboard category rows | 18 | 184 sections | lines 5–252, a fenced block | hand-typed |

**All 12 + 62 are hand-typed narrative, not one is computed from a checkbox.** The header
dashboard names ~20 workstreams (`no-txt`, `proofs`, `lane-liveness`, `dup-rows`, …) and none
of their bars is derived from the `- [ ]`/`- [x]` state — they disagree with the checkbox
counts (e.g. `mut-REQUEST [##########] 0` and `false-zeros [##########] 0`, both full bars over
zero counts). **`AGENTS.md` asks for "a progress bar … for each category"; the file has 184
sections and 0 computed bars.**

## 3. Duplication — the stated cause is REFUTED

| quantity | value | denominator |
|---|---|---|
| distinct lines (byte-exact) | 12,057 | 13,477 (10.5% repeated) |
| **those that are just blank lines** | 1,301 | 1,420 repeated instances |
| duplicated NON-BLANK lines | **120** | **12,176 non-blank (0.99%)** |
| distinct TASK texts (normalised) | **1,316** | **1,317 items** |
| duplicated task texts | **1** | 1,316 |
| task texts with CONFLICTING states | **0** | 1 duplicated |

The 10.5% headline is blank lines (1,301), `---` (40), and code fences (23+21). **The tasks
do not repeat: 1,316 of 1,317 texts are unique, the one duplicate carries the same state
(`[x]` twice, lines 8501/8633), 0 conflicts.** So *"a state file whose entries are duplicated
cannot be ticked safely"* is **not what is true of this file**. 13,477 lines is a **long
append-only history**, not a file repeating itself: 102 of 183 `##` sections are titled
`Session …` logs.

## 4. What actually blocks ticking — 303 pinned line-numbers

`.agents/TODO.md` is cited **by `file:line` from outside itself in 303 places**, and several of
those files are not mine to touch:

- `checks/differ.py:911` → `.agents/TODO.md:12108`
- `.agents/slop/sloptxt/readers.json` → 15+ refs (`:3769`, `:4618`, `:7565`, `:12805`, …)
- `.agents/slop/txt398/REPORT.md:99` → `:12051`; `.agents/slop/stale71/REPORT.md:134` → `:385`
- `.agents/slop/shadowtrees/REPORT.md:125,309` → `:3311`

**And at least one of them is ALREADY STALE, independent of me:** `checks/differ.py:911`
calls `:12108` "a ticked `- [x] Report.` box", but line 12108 is a `CS2-E` bullet about
`ClangRenderer` and **no ticked `Report.` box exists anywhere in the file** (`grep` rc=1).
Because my change is a pure EOF append, line 12108 is byte-identical to the found file: this
staleness predates the subagent.

And the reason units declined is **ownership, measured**: `.agents/slop/deadgens/REPORT.md:156`
— *"`.agents/TODO.md` not ticked. It is contended by seven running units and is not in my
ownership."* So: **one 977 KB file, 8 contending units, and 303 external `file:line` pins that
forbid moving lines.** That, not duplication, is the failure.

## 5. The one structure change: (b), a stable id per task

**Chosen: (b) — a stable, content-derived id per task, in a generated index.** Not (a), not (c).

- **(a) split by category is measured UNSAFE.** Splitting or reordering moves lines and
  invalidates the 303 external `TODO.md:NNNN` citations, at least one of which
  (`checks/differ.py:911`) lives in a file no unit here owns. The migration would itself be the
  multi-unit contention it is meant to remove.
- **(c) leave-and-document is refuted** by the same measurement: 303 pins + 8 contending units
  means the status quo is not safe.
- **(b) is additive and citation-safe.** `index.py` walks the file by discovery and emits
  `.agents/slop/todo2/tasks.idx.tsv`: **1,317 rows, 1,317 distinct ids, 0 collisions.** Id =
  `sha1(section-slug + NUL + normalised-text + NUL + occurrence)[:10]` — **stable across line
  moves**, so ticking is a lookup and a **single-line replace**, never a clobber of neighbours.

`tick.py` closes the loop: it resolves an id → `(section, text)`, re-reads the file, requires a
**unique** match, and replaces only that line. Demonstrated in dry-run (no write) on an open
task: `2db490851e  line 412: [ ] -> [x]`.

**Cost of (b), stated plainly:** the index is a generated artifact that must be **regenerated
after any edit** or it goes stale — it is a generator's declaration loaded by path (doctrine 1),
not a hand list, which is why it can be regenerated safely. And (b) removes **ambiguity**, not
the **read-modify-write race**: `tick.py` therefore also re-checks the file's sha between read
and write and aborts on a race (§7). What would have to be true for (a): every one of the 303
citations would need a stable anchor (or be repointed in one coordinated commit) including the
non-owned `checks/differ.py`.

## 6. Progress bars added — one per category, COMPUTED

`bars.py` computes one bar per level≤2 section from the checkbox counts and appends the
dashboard at EOF (append-only, §7). **Before → after:**

| measure | before | after | delta |
|---|---|---|---|
| block-glyph bar lines `[█▓▒░]` | 12 | **167** | +155 (1 OVERALL + 154 categories) |
| block-glyph glyphs | 191 | 1,741 | +1,550 (155 bars × 10) |
| hand-typed ASCII `[#...]` bar lines | 62 | 63 | +1 (one section is *titled* `Progress: [#########.] 9/10`) |
| lines | 13,477 | 13,640 | +163 |
| OVERALL | (none computed) | `████████░░ 1074/1317 81.5% (+4 [~])` | — |

Categories: **154 of 184** level≤2 sections carry tasks; each gets `done/total` and a percent.
The generated block is marked `<!-- GENERATED-PROGRESS-BARS … do not hand-edit -->` and is
**idempotent** (re-running regenerates it in place). `dashboard.md` holds the same block
standalone.

**A doctrine-1 instance the first draft committed and the fix caught.** A section is *titled*
`[x] **DEAD-ARM CENSUS …`; rendered as a `- ` bullet it became `- [x] **DEAD-ARM…`, which the
next run's own checkbox regex re-read as a task — the census moved **1,317 → 1,318** on
regeneration. The generator was changing the population it measures. Fixed by rendering
category rows with `•`, which the checkbox regex cannot match; the task count returned to
**1,317** and `index.py` to **1,317 ids / 0 collisions**. A generated artifact whose *output is
its own input* is the same disease as a hand list.

## 7. Concurrency — no race occurred, and no line shifted

Every write was preceded by a sha check. The chain is entirely mine:
`a66cb972… (found) → dd6d4317… (append) → 4c3b6e3f… → df71ed6a… → 3b4bd485… → 49287def… (final)`.
**No other writer appeared in any window**; if one had, `bars.py`/`tick.py` would have returned
code 2 and refused. The change is a **pure EOF append** (plus in-place regeneration of the
generated block only): lines 1–13,477 are byte-identical to the found file, so **all 303 pinned
citations still resolve**. Nothing else in `.agents/TODO.md` was edited.

## 8. Ticked off nothing

The instruction is a rule here, not a courtesy: an unchecked `[x]` that no instrument backs is
the same defect as an unmeasured line in `AGENTS.md`, and this file holds 1,074 `[x]` of them.
**I ticked none.** `tick.py` was run only as `--check` on a dry run to prove the mechanism; it
wrote nothing. No `[ ] → [x]` in the tree is mine.

## 9. Artifacts

| path | what |
|---|---|
| `.agents/slop/todo2/discover.py` / `discover.md` | characterisation, heading & state census, bar census, duplication, section rollup |
| `.agents/slop/todo2/index.py` / `dup.md` | duplicate-task census, citation census, id index generator |
| `.agents/slop/todo2/tasks.idx.tsv` | 1,317 stable ids → section/state/text |
| `.agents/slop/todo2/bars.py` / `dashboard.md` | computed per-category bars (generator + standalone copy) |
| `.agents/slop/todo2/tick.py` | id → unique-line replace, sha-raced |
| `.agents/slop/todo2/sections.tsv`, `subsections.tsv`, `collisions.out` | machine-readable rollups |
