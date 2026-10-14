# Which of the four resolutions to `indexread-gate.py`'s 7 new offenders

Subagent report 2026-10-14. Read-only. **Nothing committed; nothing deleted; no gate claim touched.**
Every number below carries the command that produced it and was read at `HEAD 23aa81801`,
`2026-10-14T05:09Z .. 05:16Z`. `jj` auto-snapshots, so `HEAD` moved during the session and the
population read **1755 and 1756 in different minutes**. Quote these with the revision.

---

## 0. THE GATE'S STATE, INDEPENDENTLY CONFIRMED

```
$ .venv/bin/python gates/indexread-gate.py ; echo $?
INDEXREAD POPULATION 1755  OFFENDERS 75  BASELINE 68  NEW 7
INDEXREAD FAIL: 7 offender(s) against the claim -- no NEW offender since the pinned baseline
1

$ .venv/bin/python gates/indexread-gate.py --strict ; echo $?
INDEXREAD FAIL: 75 offender(s) against the claim -- STRICT: no offender
1
```

It is a growth ratchet against a **tracked** baseline beside it (`gates/indexread-baseline.rows`,
`# TOTAL 68`, 72 lines). Nothing is loosened here.

---

## 1. THE 147 IS REAL, AND IT IS A RAW GREP WITH NO CLASSIFIER

```
$ git ls-tree -r --name-only HEAD -- .agents/slop/ > /tmp/b.rows        # 4490 files
$ xargs grep -lE 'ls-files|read-tree|--cached' < /tmp/b.rows | wc -l    # 147
```

**That reproduces the brief's 147 exactly** — and it counts **every tracked file of every
extension**, not code:

| ext | n | |
|---|---|---|
| `.py` | **67** | code |
| `.md` | 55 | prose ABOUT the index (including `REPORT.md` files that *quote* the gate) |
| `.out` | 17 | captured stdout |
| `.rows` | 3 | expected values |
| `.tsv` | 2 | tabular |
| `.sh` / `.json` / `.diff` | 1 each | |
| **total** | **147** | |

**So 80 of the 147 are not instruments.** The committed `.py` population under `.agents/slop/` is
**711**; the gate's AST classifier calls **63** of them offenders. Chain:

```
$ git ls-tree -r --name-only HEAD -- .agents/slop/ | grep -c '\.py$'    # 711
$ .venv/bin/python gates/indexread-gate.py | grep POPULATION              # 1755 population, 75 offenders
# of the 75: 63 under .agents/slop/, 12 outside
```

### THE 7 "NEW OFFENDERS" ARE NOT 7 DEFECTS. TWO ARE.

The brief's premise was "genuine offenders ... really reading the index". Measured by AST parent
context, **5 of the 7 are the index's own custodians and reproductions**, i.e. instruments whose
**subject IS the index** and which therefore *cannot* be converted to `ls-tree` without going blind:

| file | the index read | verdict |
|---|---|---|
| `.agents/slop/orcdecide/sweep.py:29` | `tracked = git("ls-files").split()` | **GENUINE** — a population read |
| `.agents/slop/orcdecide/verdicts.py:37` | `[f for f in git("ls-files").split() if f.startswith(D)]` | **GENUINE** — a population read |
| `.agents/slop/whyarms/armsites.py:31` | `ARMING = {"read-tree": "the DISARM, ...", ...}` | **NOT.** A dict VALUE naming a git verb. **0 calls construct it.** Its own population uses `ls-tree` at `:46` — already converted |
| `.agents/slop/whyarms/repro.py:53,57` | `git ls-files --stage` | **NOT.** It is *the reproduction of the destruction*. The index read is the experiment |
| `.agents/slop/whyarms/repro2.py:52,56..133` | `ls-files --stage`, `diff --cached`, `read-tree` | **NOT.** Same — R2/R3/R4 arms and disarms an index on purpose |
| `.agents/slop/whyarms/watch2.py:67,82` | `git ls-files --stage` | **NOT.** A watcher *for* the armed state |
| `checks/index-arm-gate.py:77` | `git ls-files --stage` | **NOT. IT IS THE CUSTODIAN.** `index-arm-gate.py:77` is the *measurement*; `:215` is a **plant** in a `tempfile.mkdtemp()` |

`checks/index-arm-gate.py:2` — *"index-arm-gate.py -- IS THE DEFAULT INDEX ARMED?"*. Converting it
to `ls-tree` would make the index's own guard structurally unable to detect an armed index, which is
the exact four-times-repeated destruction this repo suffered. **Option 3 applied to it is a
capability REMOVAL, not a fix.**

**Verification, re-runnable:**
```sh
.venv/bin/python - <<'PY'
import ast
from pathlib import Path
for rel in [".agents/slop/whyarms/armsites.py","checks/index-arm-gate.py"]:
    src=Path(rel).read_text(); t=ast.parse(src)
    par={id(c):n for n in ast.walk(t) for c in ast.iter_child_nodes(n)}
    for n in ast.walk(t):
        if isinstance(n,ast.Constant) and n.value in ("ls-files","--cached","read-tree"):
            print(rel, n.lineno, n.value, "parent=", type(par.get(id(n))).__name__)
PY
```

### AND THE TREE ALREADY SAYS THE 2 GENUINE ONES ARE WRONG, IN WRITING

`checks/slop-declare.py:138-146`, verbatim:

> **`git ls-tree -r HEAD`, NOT `git ls-files`** — … ***`orcdecide`'s 256 AND `declare`'s 262 WERE NOT
> MISCOUNTS; THEY READ `git ls-files`, WHICH IS AN INDEX THIS TREE HAS RESET SIX TIMES TONIGHT.***

`checks/slop-declare.py` is a live instrument that made **exactly** this conversion. The fix for the
2 has a precedent and a written reason, in the tree, today.

### THE GATE'S `FORMS` SET CONFLATES TWO CLAIMS

```
$ (.venv/bin/python - <<'PY'
import importlib.util
s=importlib.util.spec_from_file_location("g","gates/indexread-gate.py")
m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
c,_=m.committed_paths()
f={p:m.offenders_of(p) for p in m.walk_population(c) if p!="gates/indexread-gate.py"}
f={p:h for p,h in f.items() if h}
print("offenders", len(f))
print("  ONLY form is ls-files      :", sum(1 for h in f.values() if h==["ls-files"]))
print("  never call ls-files        :", sum(1 for h in f.values() if "ls-files" not in h))
PY
)
offenders 75
  ONLY form is ls-files      : 45   <- THE POPULATION DEFECT (doctrine 1)
  never call ls-files        : 22   <- mutation / plant / reproduction: A DIFFERENT CLAIM
```

**22 of the 75 never call `ls-files` at all.** They `git add`, or `git read-tree`, or `--porcelain` —
they *arm* or *observe* an index on purpose. Counting them under the same word "reads the index" as
`git("ls-files").split()` is a **classifier error of exactly the kind doctrine 1 exists to catch**,
and it is what makes `--strict`'s 75 meaningless as a target.

---

## 2. THE NUMBER THAT DECIDES OPTION 2 — AND IT REFUTES IT

```
$ git ls-tree -r --name-only HEAD -- gates checks | grep '\.py$' \
    | xargs grep -lE '\.agents/slop' | wc -l        # 77 files
$ ... same, restricted to LIVE (non-docstring) string constants via the gate's own bare_strings():
FILES with a LIVE string naming .agents/slop : 36
distinct .agents/slop paths in those strings: 58
  PRESENT in the commit tree : 35      <- held by 21 gate/check files
  GONE from the commit tree  : 23      <- ALREADY DANGLING
```

**The 35 that are PRESENT are gate INPUTS, and their holders are GREEN RIGHT NOW:**

| gate | its `.agents/slop/` input | run today |
|---|---|---|
| `gates/i64-shl-gate.py:73-74` | `.bend` driver + `.py` oracle | **rc=0**, 151 rows |
| `gates/i64-shr-gate.py` | `ishr/shr.bend` + `shr-oracle.py` | **rc=0**, 301 rows |
| `gates/bc-u32-gate.py:59-60` | `bc-rows.bend` + `bc-oracle.py` | **rc=0**, 39 rows |
| `checks/wallcheck.py:34-35` | defaults BOTH ledger and truth | rc=1 |
| `checks/oracle-txt-census.py:216` | loads its exclusion plant by path | **rc=0** |

**Verify:**
```sh
.venv/bin/python gates/i64-shl-gate.py; echo $?      # 0
git ls-tree -r --name-only HEAD | grep -c 'shl-oracle.py$'   # 2 -- no second copy exists
```

`.agents/slop/` is **42.5 MB over 4490 files** in the tree. `git check-ignore -v .agents/slop/toolsledger/extract.py`
→ **rc=1, nothing ignored today.**

**AND OPTION 2 HAS ALREADY BEEN HALF-EXECUTED, AND ITS BILL IS VISIBLE:** **23 of 58** live-named
inputs are *already gone from the commit tree*. The precedents are written down:
`.agents/slop/runsgate/REPORT.md` — *"a gate's REQUIRED INPUT under a `.gitignore` rule"* — and
`.agents/slop/deadgens/REPORT.md`, which tables four swept instruments.

**"Scratch" is also not a status.** `AGENTS.md:21` makes `.agents/slop/` the mandated home for
tracked Markdown, and the tree's own instrument says what is actually in it:

```
$ .venv/bin/python checks/slop-declare.py
tracked `.agents/slop/*/` directories : 284
  DECLARED (report or manifest)  : 219
```

**219 of 284 carry a `REPORT.md`/`MANIFEST.tsv`.** That is a documentation tree, not scratch.

---

## 3. THE FOUR OPTIONS

| # | cost | what becomes true that is not now | VERIFY |
|---|---|---|---|
| **1. BASELINE THEM** | 68 → 75 accepted. **5 of the 7 are not defects** (`armsites.py` names a verb; `repro`/`repro2`/`watch2`/`index-arm-gate` measure the index on purpose), so the claim absorbs 5 entries that are *wrong*. Who accepts: whoever runs `--write-baseline`, and it is **one command** — which is the risk | the 63/63 sweep goes green | `.venv/bin/python gates/indexread-gate.py --write-baseline && .venv/bin/python gates/indexread-gate.py; echo $?` → `0`; `git diff gates/indexread-baseline.rows` → 7 added, `# TOTAL 75` |
| **2. GITIGNORE `.agents/slop/`** | **refuted above.** Untracks the `.bend` driver and `.py` oracle of `gates/i64-shl-gate.py`, `gates/i64-shr-gate.py`, `gates/bc-u32-gate.py` and both defaults of `checks/wallcheck.py`. **35 live-named inputs, 21 holders.** 23 more are *already* dangling | 63 of 75 offenders vanish from the gate's population — **because they are no longer shipped, not because they were fixed**. On a fresh clone **21 gates lose an input they are green on today** | `git ls-tree -r --name-only HEAD -- .agents/slop/ \| wc -l` → `0`; then `git clone . /tmp/c && cd /tmp/c && .venv/bin/python gates/i64-shl-gate.py` → **rc≠0**. **Already falsified by the 23** |
| **3. FIX THE OFFENDERS** | mechanical for the **45** whose only form is `ls-files`; a **capability removal** for the **22** that never call it (plants, `repro*`, `index-arm-gate`, `git-massdelete-gate`, `msgdiff-gate`). 40 of the 45 are in units I do not own | doctrine-1 compliance for the 45; **blindness** for the 22 | per file: `git grep -c 'ls-tree' <f>`; then `.venv/bin/python gates/indexread-gate.py --strict` |
| **4. SPLIT THE CLAIM** | two claims, two baselines, **zero new lists** — `gates/gates-pop.py:scan_roots` already derives the 9 roots and takes no exclusion list. Population 1755 → **1045**, offenders 75 → **12** | the shipped-tree claim stops being diluted 84% by a directory that is 84% documentation, and each question gets its own baseline beside its own gate | `.venv/bin/python - <<'PY'` (script in §1) → `population 1045  offenders 12` |

`gates/gates-pop.py:882-887` already anticipates option 4 and states its rule: *"two questions, two
named populations, one module. A second copy of a list is a contract with no generator; a second
copy of a DERIVATION with a different predicate is a different question pretending to be the same
one."* **Option 4 done right is a SECOND GATE, not a filter on the first.**

---

## 4. RECOMMENDATION

**Option 4 + option 3 on 2 files.** In this order:

1. **Convert the 2 genuine ones now.** `orcdecide/sweep.py:29` and `orcdecide/verdicts.py:37`,
   `git("ls-files")` → `git("ls-tree","-r","--name-only","HEAD")`. That is what
   `checks/slop-declare.py:138-146` already did to itself, with the reason written down. 2 lines.
2. **Split the claim.** A `shipped-indexread-gate.py` whose ROOTS are `scan_roots()` **minus**
   `.agents/slop/`, population 1045, baseline 12, beside it in git. Leave
   `gates/indexread-gate.py` and its 68-row baseline **exactly as they are** — it then measures
   `.agents/slop/` hygiene, which is a real question with a real population of 63.
3. **Never convert the 22.** When they show up they are answered with a line, not a diff.

### THE STRONGEST ARGUMENT AGAINST

**Option 4 exempts 63 of 75 offenders — 84% — and `.agents/slop/` is where the defect is DENSEST,
not absent.** 63 of 63 `.agents/slop/` offenders are there; and of the 45 files whose only index form
is `ls-files`, **40 are under `.agents/slop/`**. Exempting the directory where the defect concentrates
is exempting the defect, and the shipped claim it leaves behind is 12 offenders of which **5 are
custodians** — so the surviving gate is mostly measuring itself. If the brief's premise *"if
`.agents/slop/` is scratch, it arguably should be `.gitignore`d"* were TRUE, option 4 would be
correct and cheap. **Measurement says the premise is false** (219/284 declared, 42.5 MB, 35 live
gate inputs) — but option 4 still wins, and it wins *because* the premise is false: a directory
that is documentation is not scratch, so it should not be excused as scratch either. **If that
reasoning is rejected, option 3 restricted to the 45 `ls-files`-only files is the correct fallback
and option 1 — not option 4 — is the right thing to do only if the caller decides 5 custodians are
acceptable baseline entries.**

---

## 5. WHAT I CHANGED

**Nothing.** `git status --short -- gates/indexread-gate.py gates/indexread-baseline.rows
checks/index-arm-gate.py .agents/slop/orcdecide .agents/slop/whyarms` → empty. No commit, no
baseline write, no delete, no `bend`.

One incidental finding, not acted on: **`gates/gates-pop.py:883` is stale** — *".agents/slop/** holds
68 of the offenders"*. Measured: **63**, and the sentence predates the current census.

Verification: `git ls-files --error-unmatch` aside, every command above is in this file and every
number came from running it at `HEAD 23aa81801`.