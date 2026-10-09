# whatisagate — WHAT A GATE IS, AND WHERE THE ROOT SET COMES FROM

**UNIT:** `whatisagate`. **TREE:** `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`,
read at commit-tree state `git ls-tree -r HEAD` = **6762 paths** (the census's own reading at
2026-10-06 was 6761; four units are live, so every denominator below carries the tree it was
taken on). **COMMITTED NOTHING. STAGED NOTHING.** Three files edited:
`gates/gates-pop.py`, `gates/indexread-gate.py`, `gates/gate-surface.py`.

**THE ANSWER IS NOT A REFUSAL, BUT IT IS NOT A CLEAN ONE EITHER, AND BOTH HALVES ARE BELOW.**
§1 is the criterion. §2 derives the root set from it and prices every disagreement with the
five hand lists. §3 is the one implementation, loaded by path. §4 is what remains undecided —
and it is a smaller question than the one `.agents/slop/UNIVERSE-CENSUS.md` left open, and it is
now a NUMBER rather than a disagreement between two lists.

---

## 1. THE CRITERION — one paragraph, applicable to a file nobody has seen

> **A file is a GATE of this repository iff the COMMIT TREE carries it (`git ls-tree -r HEAD` —
> never the index, which a reset empties, and never the working copy, which `chmod -R` and a
> stray write both move), AND running that file AS A PROGRAM performs its measurement — an
> `if __name__ == "__main__"` guard in Python, a shell file dispatching on `$0` or `exec`, an ES
> module that RUNS its top level under `node` rather than exporting it — AND it reports a verdict,
> meaning one of the five statuses `gates/gatekit.py` names, carrying a denominator.** The first
> two clauses are measured mechanically (`git ls-tree`, and `gates/gates-pop.py:entry_reason`,
> which is AST for Python and tokenizers for shell and JavaScript). The third is *declared* by the
> file and read off it; it is deliberately the only clause whose violation costs nothing, and
> `gates/gate-surface.py` is the instrument that charges for it. **The fourth clause — the one
> nobody had written down — is the ROOT CLAUSE: a gate home is a top-level directory of the
> commit tree holding, IN ITS OWN IMMEDIATE FILES, at least one tracked file that is an entry
> point and that NAMES A ROOT, REFUSES ON A WRONG ONE, AND RESOLVES ON-REPO.** Every conjunct of
> that is already measured in `gates-pop.py` (`entry_reason`, `ROOT_CONST`/`ROOT_INLINE`, `REFUSE`,
> `MARKER`, `resolve_root`), so the universe is declared by the subjects rather than transcribed:
> **the subjects declare the universe they live in, which is the only shape of population that
> cannot rot without something else rotting with it.** "Immediate files" is not a depth number but
> the coherence condition `_buckets` already imposes — it enumerates a home with `iterdir()` — so a
> witness three levels down would certify a home whose gates the population walk cannot reach: *a
> home that certifies itself and then contributes nothing*, which is `artefacts_ok()` one level up.

### The four named subjects, decided by that criterion

| file | tracked | entry point | in a derived home | verdict |
|---|---|---|---|---|
| `checks/nan_census.mjs` | yes | `js-main` | `checks/` **kept** | **GATE** |
| `checks/bend` | yes | `sh-dispatch` | `checks/` **kept** | **GATE** |
| `.agents/slop/capstream/refsplit.py` | yes | `py-main` | `.agents/` **rejected** | **NOT A GATE** |
| `tinybendygrad/uop/fold.bend` | yes | `None` | `tinybendygrad/` **rejected** | **NOT A GATE** |

Each answer, and **which clause decides it** — because the interesting fact is that the first two
clauses decide three of the four and the ROOT CLAUSE decides the third case alone:

* **`checks/nan_census.mjs` — IN.** JavaScript has no `__main__`, so the entry-point test is "the
  module RUNS rather than EXPORTS". A suffix set can never admit it (no `.py`) and a shebang test
  can never see it (no `#!`).
* **`checks/bend` — IN.** Tracked, `#!/bin/sh`, `exec`. A two-line launcher is a gate whose
  subject happens to be a compiler. **A BASENAME IS NOT A PATH** — `gate.txt` is four files — **AND
  A BASENAME CAN BE A PROGRAM**, which is why `suffix_of()` is hand-written and why no suffix test
  may decide membership.
* **`.agents/slop/capstream/refsplit.py` — OUT, and the root clause is the ONLY thing that can say
  so.** MEASURED: `entry_reason()` returns `py-main` for it. It is tracked, it has a `__main__`,
  and both membership clauses pass. What rejects it is that `.agents/`'s immediate row is
  **1 prefilter survivor of 5 files, and that survivor (`.agents/TODO.md`, which quotes `__main__`
  and `refuse(` in prose) resolves no root** — so `.agents` is not a home, and the file is three
  levels below any directory this tree puts a gate in. **Without the root clause this instrument
  has no answer for this file at all**, which is the entire reason the clause exists.
* **`tinybendygrad/uop/fold.bend` — OUT, twice over.** `entry_reason()` returns `None`: no entry
  guard, `import`ed by the `.bend` files that use it. And `tinybendygrad/` is rejected at
  `0 survivors of 11 immediate files`. It is the port's own source and the port is what is being
  MEASURED; running it would be the subject auditing itself.

---

## 2. THE DERIVED ROOT SET, AND EVERY DISAGREEMENT WITH THE FIVE HAND LISTS

**MEASURED on the live tree.** Candidates: the **14** top-level directories the commit tree shows
holding tracked paths. Derivation cost: **869 immediate files read**, 0.37 s user. **18 prefilter
survivors → 17 certified witnesses → 2 homes kept, 12 rejected.**

```
   ROOT SET, DERIVED FROM THE COMMIT TREE: 2 of 14 top-level directories qualify
     KEEP    checks           16 witness(es): checks/both-census.py
     KEEP    gates             1 witness(es): gates/gate-surface.py
     reject  .agents 1/5       -- no gate there names a root, refuses on a wrong one, and resolves on-repo
     reject  .github 0/0       docs 0/18      examples 0/38    extra 0/28      langs 0/5
     reject  oracles 0/329    spec 0/14       test 0/4        tinybendygrad 0/11
     reject  tinygrad 0/7     tools 0/1
```

### The five lists, and the one-line reason for each disagreement

| list | n | verbatim (measured by AST) | verdict vs the criterion | one-line reason |
|---|---|---|---|---|
| `gates/gates-pop.py:HOMES` | 2 | `("checks","gates")` | **AGREES, 2 of 2** | The old hand list was RIGHT; it was right by hand, which is the only thing that was wrong with it. |
| `gates/indexread-gate.py:ROOTS` | 3 | `("checks","gates",".agents/slop")` | **DISAGREES by 1** | Different question: *where are the SHIPPED INSTRUMENTS*, not *where are the gates*; `.agents/slop/**` holds most of the index-readers and **0 of its 3 certified root-asserting gates sits at depth 1 of any home**. |
| `checks/wallcheck.py:WALK_ROOTS` | 7 | `("tinybendygrad",".agents/slop","docs","checks","gates","AGENTS.md","README.md")` | **AGREES on 2; adds 5** | Different question: *what PROSE CLAIMS EXIST*; a gate home need not ship prose (`checks/` ships none about itself) and prose need not be a gate home (`README.md` is not a program). |
| `checks/repro-paths.py:REPORT_DIRS` | 5 | `(".agents/slop",".agents","checks","gates","")` | **DISAGREES by 2** (`.agents/slop`, `.agents`, `""`) | Different question: *where may a REPORT BE WRITTEN* — a write question, not a run question, which is why it admits the repo root itself. |
| `checks/sweep.py:RESIDUE_ROOTS` | 2 | `(".agents/slop","runs")` | **DISAGREES COMPLETELY** — names neither `checks` nor `gates` | Different question: *where does UN-GATED SCRATCH ACCUMULATE*; `runs/` is gitignored root output and is not a home by any criterion. |

**THE FINDING, AND IT IS NOT "THE LISTS DISAGREE".** Three of the five answer questions that have
nothing to do with each other, and **none of the five was wrong.** The census's phrasing — *"nothing
records that they are different questions"* — is the defect, and the fix is not a sixth list: it is
**one module that owns each question's derivation, names the question, and prints the rejected
candidates with their denominators.** §3.

### WHAT THE CRITERION SETTLES AND WHAT IT DOES NOT

* **Settled, with evidence:** `.agents/slop/` is **not** part of the gate-home universe. It is not
  a hole or a shrug — it is `1 survivor of 5` at depth 1, `3 of 3` certified gates at depth 4, and
  `0` gates at depth 1. `gates-pop`'s old `("checks","gates")` was **correct**.
* **Settled:** a vendored upstream directory is not a home for a *real* reason, not by name.
  `test/` holds **4** immediate files and **307** entry points across its 390 tracked ones, and
  **0** of them names a root or refuses on a wrong one. The third conjunct is a real property, which
  is why this derivation agrees with a hand list about `checks/` and disagrees with one about `test/`.
* **NOT settled — and this is the residue of the original REFUSAL:** whether a home should be
  **recursive**. The criterion says a home's gates must be reachable by the enumeration that will
  use the home (`_buckets` is `iterdir()`). That is coherence, and it is load-bearing: **MEASURED,
  the recursive rule admits `.agents` on 3 gates at depth 4 and then contributes
  `.agents/TODO.md` — a markdown file that `ast.parse`s — to the gate population.** So the honest
  statement is: `gate_homes()` answers "where are the gates this instrument enumerates", and a
  decision about recursive homes would change both the derivation and `_buckets` together. **That is
  a change to WHAT COUNTS, and the brief for this unit forbids it.** It is named here rather than
  taken.

---

## 3. THE IMPLEMENTATION — one definition, loaded by path, no second copy

### `gates/gates-pop.py` — the owner. Three new functions, one shared walker.

| function | what it derives | consumer |
|---|---|---|
| `_tree_paths(root)` | the candidate paths, `git ls-tree -r --name-only HEAD`, with a working-copy fallback for `--plant` synthetic trees. **The commit tree IS the prune**, which is why there is no `SKIP` list: `references/`, `.venv/`, `node_modules/`, `.agents/slop/opstree/`, `/runs/` are all `.gitignore`d and so are absent by construction. Prints which source it used. | both |
| `gate_homes(root)` | **`(homes, derivation)`** — the GATE-HOME question. | `gates-pop.py`, `gate-surface.py` |
| `scan_roots(root)` | the **COMMITTED-PYTHON** question — top-level dirs holding a tracked `.py`. | `indexread-gate.py` |
| `report_roots(derivation, indent)` | prints the derivation with every rejected candidate and its `survivors/files-read` denominator. | `gates-pop.py`, `gate-surface.py` |

`HOMES` is now `gate_homes(ROOT)[0]`, bound at the **bottom** of the module next to `FIXTURES`
(`gate_homes` reads `root_facts`; binding it near `LEDGER` raises `NameError` at import — measured,
same shape as `_init_fixtures`). `_buckets(root)` calls `_homes(root)` rather than the global, so
**a synthetic tree derives its own homes**. `_homes`/`_derivation` memoise **within one process
only** — nothing is written to disk, because `UNIVERSE-CENSUS.md`'s own finding is that
`gates-pop.ledger.tsv` is written at one line and read at another in the same process, and *a
ledger read and rewritten by its own reader is not a ledger*.

### `gates/indexread-gate.py` — the second copy is gone

`ROOTS = ("checks", "gates", ".agents/slop")` → `ROOTS = gates_pop().scan_roots(ROOT)`, loaded **by
path** with `importlib.util.spec_from_file_location`, refused (exit 3) if `gates-pop.py` is absent.
It deliberately does **not** read `gate_homes()`, and the reason is written on the line: **two
questions, two named populations, one module.** A second copy of a list is a contract with no
generator; a second copy of a *derivation* under a different name is a different question pretending
to be the same one. Every run prints both root sets side by side.

**AN OBSERVABLE CONSEQUENCE OF THE CHANGE, MEASURED:** the very instrument that catalogued these five
lists can no longer read two of them by AST —

```
HOMES      gates/gates-pop.py      = ?      # was a tuple, now `gate_homes(ROOT)[0]`: a CALL
ROOTS      gates/indexread-gate.py = ?      # was a tuple, now `_gpop.scan_roots(ROOT)`: a CALL
WALK_ROOTS checks/wallcheck.py     = ('tinybendygrad', '.agents/slop', 'docs', 'checks', 'gates', 'AGENTS.md', 'README.md')
```

`ast.literal_eval` fails on both, **because there is no longer a hand list to read.** The census's
own reader going quiet on two of its five subjects is the smallest possible proof that the thing it
was complaining about is gone.

### `gates/gate-surface.py` — `population()` untouched, as instructed

`gate-surface.py:277-280` still reads

```python
def population(root):
    """`(entries, libs)` from `gates-pop.discover()`. The ONLY definition of the population."""
    return gates_pop().discover(root)
```

**unchanged, character for character.** What counts as a gate is still `entry_reason()`; only where
the roots come from moved. Two additions: one `report_roots(...)` line beside the population count,
because `walk_control(root, gpop.HOMES)` is handed this very list as its parameter and **a control
fed the list it is about to check cannot disagree**; and `_tree()` now plants a **home witness**.

### THE FIXTURE REPAIR, AND IT WAS NOT OPTIONAL

Both plant suites build synthetic trees. Under a derived root set, a synthetic tree earns a home the
only way a real one does — by holding a gate that certifies it — so `_tree` writes `GOOD_ROOT`
(the file plant 5 already asserts is the clean fixed form: **one fixture, two jobs**) into each
home. **MEASURED consequence if this is left out: `gates/gate-surface.py --plant green` falls from
13/14 to 3/14, and every new failure reports `rc=2`** — the EMPTY-POPULATION refusal — because
`_buckets` enumerated two empty directories. An instrument refusing because its own fixture is
empty is not failing safely; it is failing loudly at the wrong subject. `gates-pop.py`'s plant 3
calls `_tree(r)` with **no** homes on purpose, which is how an empty population stays assertable.

---

## 4. VERDICTS — every number with its denominator and its scope

Five verdicts, `PASS 0 · FAIL 1 · REFUSED 3 · SKIP 4 · DEAD 5`. `SKIP`/`DEAD`/`REFUSED` are **not**
passes. A gate that exits 0 having measured nothing is worse than no gate, because it is trusted.

### The four verifications the brief named

| command | rc | token | scope / denominator |
|---|---|---|---|
| `gates/gate-surface.py --report` | **0** | `SHELL HALF: 18` | 150 entry points + 52 libs over the 2 derived homes; the 18 are `checks/`'s shell entries |
| `checks/no-txt.py` | **0** | `CLEAN` | every `.txt` the project owns, outside `differ.declared()` and 4 other declared exceptions |
| `checks/nl-gate.py` | **0** | `gated 205 agree 205 disagree []` | 205 lines, both lanes |
| `checks/nl-gate.py --selftest` | **3** | `REFUSED, NOT A VERDICT` | its control `checks/nl-port-post.txt` is absent from every commit — **refusal, not a pass** |

### The rest, run on the same tree state

| command | rc | verdict | denominator |
|---|---|---|---|
| `gates/gates-pop.py` | **0** | `OK` | 150 entry points, 46 name a root, 20 assert it, 0 resolve outside the repo; 281 generated dirs |
| `gates/gates-pop.py --plant` | **0** | `PLANTS: GREEN (10/10)` | 10 planted directions + 1 inertness assertion |
| `gates/gates-pop.py --ledger check` | **1** | `RED` | **PRE-EXISTING and unchanged by this unit**: 18 added / 0 gone / 1 changed, 132 → 150, from other units adding `checks/bend`, `checks/nan_census.mjs`, `gates/*-gate.py`. Measured RED at the same 150 before any edit. |
| `gates/indexread-gate.py` | **0** | `PASS: 68 offenders, all inside the pinned baseline` | **population 862 → 1706** (coverage *up*: 9 derived roots replace 3 hand-named), offenders 68 = baseline 68, NEW 0 |
| `gates/indexread-gate.py --strict` | **1** | `FAIL` | 68 offenders against the stronger claim — **red by design**; the default claim is GROWTH |
| `gates/gate-surface.py` (bare) | **1** | `RED` | 14 gates declare a surface, 21/42 verdicts reached, 16 unplanted, 4 UNOWNED, 10 RENAMED — the same surface census as before this change |
| `gates/gate-surface.py --plant green` | **1** | `PLANTS: RED (13/14)` | 13 pass, 1 fail. **6a fails and failed before this change**: forcing `_homes` to the OLD hand list `("checks","gates")` gives the **identical 13/14 with the identical 6a observation** (`counted=False`, `/bin/sh` resolved, `not_malformed=True`). 6a is not a root-set question. |
| `gates/gate-surface.py --plant red` | **1** | RED, charged | one synthetic gate with an UNPLANTED verdict. **Was `rc=2`** (empty-population refusal) before `_tree` planted its witness; `2` was the wrong direction and `1` is the one this plant exists to reach |
| `ruff check` on the three files | 1 | — | **finding counts identical to `git show HEAD:` for all three** (12 / 0 / 149); the per-rule distribution for `gates-pop.py` diffs empty. Zero lint findings added. |

### Cost

| | before | after |
|---|---|---|
| root derivation | 0 (a literal) | **869 immediate files, 0.37 s user**, memoised per process |
| `indexread-gate.py` wall clock | 0.65 s | 1.36 s (coverage 862 → 1706 files) |
| `gate-surface.py --report` | 25.9 s (`gates-pop` clause IV's 281 `git check-ignore` subprocesses dominate) | unchanged order; derivation adds ~0.4 s |
| LOC | `gates-pop.py` 1238 · `indexread-gate.py` 237 · `gate-surface.py` 898 | 1520 (**+282**) · 272 (**+35**) · 919 (**+21**) |

The +282 is **mostly the criterion paragraph itself**, which is the deliverable: the brief asked for
the criterion to be *written down*, not merely encoded. The executable part of the derivation is
`gate_homes` + `report_roots` + `scan_roots` + `_tree_paths` ≈ 90 lines.

---

## 5. WHAT WAS *NOT* DONE, AND WHY

* **`gate-surface.py:277-280` was not touched.** Not one character.
* **`checks/rows/**`, `tinybendygrad/**`, `gates/tn_*` were not read for modification and not
  modified.** `git ls-tree -r HEAD` was used for the TREE (the census names ten index traps this
  session); `git ls-files` was never used as a population; `git ls-files` appears in
  `indexread-gate.py` only as its own subject.
* **Nothing staged, nothing committed, no `git add -A`, no amend, no rebase, no force.**
* **The other three lists were not migrated.** `wallcheck.WALK_ROOTS`, `repro-paths.REPORT_DIRS`
  and `sweep.RESIDUE_ROOTS` are outside this unit's write scope and, on the evidence of §2, they
  answer different questions — migrating them to `scan_roots` would be a *category error*, not a
  refactor. **What they should each gain is a line naming their question**, which is the whole
  finding and costs one comment each.
* **The recursive-home question (§2, "NOT settled") is left to a human decision** because changing
  it changes what `_buckets` enumerates, and the brief forbids changing what counts as a gate.
  It is now a measured alternative (3 certified `.agents` gates at depth 4; `.agents/TODO.md`
  would enter the population) rather than an unexamined assumption.

## 6. THE ONE-LINE VERSION

**`HOMES` and `ROOTS` are no longer hand lists; both are derived by `gates/gates-pop.py` from the
commit tree, each answering its own NAMED question, and every candidate either derivation rejected
is printed with its own denominator — `2 of 14` gate homes (`checks` on 16 witnesses, `gates` on 1),
`9 of 14` committed-Python roots, `.agents` rejected at `1 survivor of 5` — which is why
`.agents/slop/` is *not* a gate home, and why `gates-pop`'s old two-item tuple was right while
`indexread-gate`'s three-item one was also right: they were never the same question.**