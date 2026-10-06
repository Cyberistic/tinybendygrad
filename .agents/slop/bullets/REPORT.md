# REPORT — the governing document fails the test it sets itself

**Subject:** `AGENTS.md` (audited at `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`, 2026-10-06).
**Deliverables:** this file + `.agents/slop/bullets/REPLACEMENTS.md` (paste-ready OLD/NEW pairs).
**Instruments:** `.agents/slop/bullets/count.py` (primary), `altrule.py`, `dump_neither.py`.
Run with `.venv/bin/python`. No `bend` was run (owned by another unit). No commit; `AGENTS.md` not edited.

---

## 1. The population, re-derived by discovery

### The rule (declare it, do not list it)

```
TABLE     := a line whose first non-space char is '|'          -> EXCLUDED
BULLET    := a line matching ^( *)-  (top level or nested), tables excluded
BULLET BODY := the bullet's own line plus every following line that is non-blank,
               not itself a bullet start, and not a table line
measured(b)   := the literal token "measured" (case-insensitive) appears in b's body
instrument(b) := b's body matches (checks|gates)/[A-Za-z0-9_.-]+\.py
                 OR a file:line citation [A-Za-z0-9_./-]+\.[A-Za-z0-9]+:\d+
NEITHER(b)    := not measured(b) and not instrument(b)
```

This is a walk + two regexes over the tree's own text, not a hand list. **The rule excludes tables**, so
the two doctrines' comparison table (`|`-prefixed, L138–146) and the flag tables (L251–428) are outside the
population; no bullet lives inside a table.

### Counts

| # | quantity | value |
|---|---|---|
| a | file lines | **428** (`wc -l` says 427; the last line has no trailing newline) |
| b | bullet lines (`^- ` / `^  - `, tables excluded) | **38** |
| c | bullets naming `(checks\|gates)/*.py` or a `file:line` | **8** |
| d | bullets carrying `MEASURED` (case-insensitive) | **11** (uppercase-only: **6**) |
| e | bullets carrying **NEITHER** | **24** |

`c ∩ d = 5` (L20, L33, L53, L59, L115), so `|c ∪ d| = 14` and `38 − 14 = 24`, consistent.

Instrument bullets (L): `20, 33, 53, 59, 78, 97, 110, 115`.
Measured bullets (L): `20, 27, 33, 49, 53, 59, 115, 188, 196, 220, 233`.

### Did my rule reproduce `38 / 24 / 10 / 20`? Partly — and the split is where it differs.

- **bullets = 38: REPRODUCED.** The bullet population is rule-independent here; `^( *)- ` with tables
  excluded gives exactly 38.
- **instrument = 8, NOT 24.** The earlier count of **24** came from a *broader* notion of "instrument"
  (any named path/command). Even a generous backticked-form rule
  (`altrule.py`: any backticked filename ∪ path ∪ command) gives **22**, not 24, so the earlier 24 is not
  reproducible by any obvious sprite either; the earlier rule is not recoverable from the file. The task
  fixes the narrow definition (`(checks|gates)/*.py` or `file:line`), so the honest number is **8**.
- **measured = 11 (ci) / 6 (upper), NOT 10.** No token rule I can state yields 10; case-insensitive gives
  11 and uppercase-only gives 6.
- **neither = 24, NOT 20.** A direct consequence of the broader instrument rule above (4 bullets that name
  a non-`(checks|gates)` instrument were counted as "with instrument" earlier).

**A different rule giving a different number is a finding, not a disagreement** — and the finding is:
*yesterday's "24/10/20" was produced by a broad, unstated "instrument" rule; today's "8/11/24" is produced
by the task's narrow one.* Both are quoted with the rule that made them.

---

## 2. The 24 NEITHER bullets, each classified

Outcome classes: **MEASURED** (I ran a command; see `REPLACEMENTS.md`), **DELETABLE** (unfalsifiable
prescription — advice/taste/preference), **UNVERIFIABLE** (makes a tree claim I could not settle).

| L | first words | class | measurement / what is lost |
|---|---|---|---|
| 15 | "use concise, clean code. No hacks" | **DELETABLE** | Loses the style standard; not a tree claim. |
| 16 | "Security is above all… then effectful, fast, pretty" | **DELETABLE** | Loses a priority ordering; taste. |
| 17 | "Shareable logic should be reused" | **DELETABLE** | Loses the DRY reminder; taste. |
| 18 | "Use Jiujitsu version control…" | **DELETABLE** | Loses nothing — the same rule is in the harness instructions (another witness). |
| 19 | "Markdown agent state… under .agents/slop/" | **DELETABLE** | Loses nothing — restated in the harness instructions. |
| 21 | "tick it off in .agents/TODO.md… progress bar" | **MEASURED** | `.agents/TODO.md` = 13477 lines; 12 block-char progress lines. |
| 22 | "Add TODO comments… use `rg`" | **MEASURED** | `rg -l 'TODO' --glob '*.bend' .` = 94 files. |
| 23 | "Update .agents/TOOLS.md… ledger" | **MEASURED** | `.agents/TOOLS.md` = 1543 lines; 99 of 213 named paths gone. |
| 45 | "Always stay turing-incomplete" | **UNVERIFIABLE** | A real property of the port; I cannot settle it without a turing-completeness analysis. Not deletable on that basis. |
| 50 | "use `LAWS.bend`… path is `tinybendygrad/LAWS.bend`" | **MEASURED** | exists, 412 lines. (The `34 TODOs` number is bend-owned and was NOT re-run.) |
| 114 | "`substrate-check.sh` — import-graph sweep" | **MEASURED** | real path is `checks/substrate-check.sh`; bare name resolves to nothing. |
| 187 | "use uv and ty" | **MEASURED** | `uv`→`~/.local/bin/uv`, `ty`→`~/.local/bin/ty`. |
| 193 | "Run tests with `-n12`…" | **MEASURED** | rc=1, `No module named pytest`. |
| 194 | "Run `python -m mypy tinygrad/`" | **MEASURED** | rc=1, `No module named mypy`. |
| 195 | "Run `python -m ruff check .`" | **MEASURED** | `ruff check .` = 18752–18754 errors, rc=1 (moves). |
| 202 | "Read `./tinygrad/viz/README.md`" | **MEASURED** | exists, 93 lines. |
| 203 | "Do not do amend commits… do not REBASE" | **MEASURED** | body already carries `git log -1` / `merge-base` facts (a FALSE NEGATIVE of the token rule); all re-verified. |
| 215 | "tinygrad has user space PCI drivers…" | **DELETABLE** | Loses the "do not insert modules" warning; advice about upstream, not a claim about this tree. |
| 227 | "Highly prefer E2E tests…" | **DELETABLE** | Loses a preference; taste/process. |
| 228 | "FIRST write all the ways it could fail" | **DELETABLE** | Loses a process ordering rule. |
| 229 | "Tautological tests considered harmful." | **DELETABLE** | Loses a taste rule. |
| 230 | "Change-detector tests considered harmful." | **DELETABLE** | Loses a taste rule (the term is defined elsewhere). |
| 231 | "Do not create regression tests…" | **DELETABLE** | Loses a process rule. |
| 232 | "Inject time instead of sleeping…" | **DELETABLE** | Loses a design rule; not a tree claim. |

`AGENTS.md` is not edited here; the 11 MEASURED rows above are patched paste-ready in `REPLACEMENTS.md`.

---

## 3. Class counts with denominators

Population: **38 bullets** (`^( *)- `, tables excluded) · file **428** lines.

| class | count | denominator |
|---|---|---|
| WITH measurement (carries `MEASURED`) | **11** | of 38 |
| WITH instrument (`(checks\|gates)/*.py` or `file:line`) | **8** | of 38 |
| WITH NEITHER | **24** | of 38 |
| — of NEITHER: **MEASURED** (measurement supplied) | **11** | of 24 |
| — of NEITHER: **DELETABLE** | **12** | of 24 |
| — of NEITHER: **UNVERIFIABLE** | **1** | of 24 |

`11 + 12 + 1 = 24`. **Half the file's bullet prescriptions (24 of 38) fail the file's own test**, of which
almost half (11) are cheaply fixable with a number and half (12) are unfalsifiable advice.

**DELETABLE set (12):** L15, L16, L17, L18, L19, L215, L227, L228, L229, L230, L231, L232.
**UNVERIFIABLE set (1):** L45.

---

## 4. Findings beyond the count

1. **FALSIFIED — `ruff` is not 797.** `AGENTS.md` L196–199 says `ruff check .` "reports 797 errors".
   Measured today: **18752, rc=1**, then **18754** on an immediate re-run with no edit by me — the count
   **moves under concurrent units**. The `797` is stale; it lives in a bullet that *does* carry `MEASURED`,
   so it is outside this unit's patch scope but is a real defect. (`ruff --version` = 0.15.18, PATH only.)
2. **`substrate-check.sh` does not resolve.** L114 names it bare; there is no root file and
   `command -v` is absent. The real gate is `checks/substrate-check.sh` (46-line shim) →
   `.venv/bin/python checks/substrate.py` (765 lines). `.agents/slop/substrate-check.sh` is a differing
   27-line twin. Fixed in `REPLACEMENTS.md` #5.
3. **The flag table is 152 rows, not 146.** `len([l for l in lines if l.startswith("| \`")])` = **152**.
   Tables are out of scope (another unit's), but the stated row count is off by 6.
4. **The token rule has a FALSE NEGATIVE at L203.** That bullet carries full `git log`/`merge-base`
   measurements in its body and still lands in NEITHER, because it never spells `MEASURED` and its only
   citations (`:1398`, `:1404`) have no filename extension, so they miss the `file:line` regex. The narrow
   rule is the task's, but the rule is demonstrably blind here — the same failure mode the file's own
   doctrine 1 is about. Re-verified by hand and folded into `REPLACEMENTS.md` #11.
5. **`.agents/slop` file count is a moving target.** `find .agents/slop -type f | wc -l` read **3663**,
   then **3734** minutes later, with concurrent units active. Any count of `.agents/slop` must carry a
   timestamp — including the `2,353 of 4,455` in the doctrine table.
6. **L50's `34 TODOs` is not `rg`-verifiable.** `rg -c TODO tinybendygrad/LAWS.bend` = **1** and
   `tinybendygrad/PROOF.bend` = **0**; the `34`/`18` come from `bend --check-only`, which this unit was
   forbidden to run. The path and line count ARE measured and patched; the TODO number is left as the
   file already wrote it.
7. **L18 and L19 are redundant with the harness.** Both rules are also present in the injected harness
   instructions at the top of every session, so deleting them from `AGENTS.md` loses no coverage — the
   strongest possible case for the file's own "deleting it is cheaper than leaving it."

## 5. What I could not settle

- **L45 (turing-incompleteness)** — UNVERIFIABLE, not DELETABLE: it is a genuine, falsifiable property of
  the port, and I have no instrument for it. Left as-is.
- **The `34`/`18` TODO counts** in L50 / L53 — bend-owned; not re-run.
- **The earlier rule for `24/10/20`** — not recoverable from the file; reported as a difference, not a
  contradiction. My numbers stand on the rule printed in §1.
