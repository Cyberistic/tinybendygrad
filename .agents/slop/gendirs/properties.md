# IS THERE A TREE PROPERTY THAT SAYS "GENERATED"? — four candidates, each measured

**MEASURED 2026-10-06 on this tree.** The brief names four candidates and says *evaluate, do not
pick*. This file evaluates them and names the answer, which is **yes for one of them, no for
three, and the yes is a LOWER BOUND with a measured hole.**

The subject: `checks/gen/`, written by `checks/abi_gate.py:606` (`gendir.mkdir(exist_ok=True)`)
and `:616` (`subprocess.run([BEND, probe, "-o", str(gendir / f"probe.{ext}")])`), and invisible to
`gates/retention-check.py` (a TWO-ITEM `Output(...)` registry) and to `gates/gates-pop.py` (a
`HOMES = ("checks", "gates")` tuple).

## P1 — "the directory is `.gitignore`D"

**MEASURED, AND IT IS TRUE OF NOTHING.** `git check-ignore --no-index -q -- checks/gen/` → rc 1
before this unit's change; `git check-ignore -q -- checks/gen/` → rc 1 *even after*.

**AND THE MEASUREMENT ITSELF IS A FIFTH INSTANCE OF THE CLASS.** `git check-ignore` **without
`--no-index` reports "not ignored" for every path that is IN THE INDEX** — git documents this: a
tracked file is not considered ignored by default. So the "is it ignored?" half of a rule about
tracked generated directories **cannot see any member of the population it governs**, by
construction. MEASURED both ways:

```
$ git check-ignore -v -- checks/gen/              -> rc 1, no output
$ git check-ignore --no-index -v -- checks/gen/   -> .gitignore:153:checks/gen/
```

**A GUARD WHOSE QUERY CANNOT SEE ITS OWN SUBJECT.** `gates/gendirs.py:ignored()` passes
`--no-index` and says why in its docstring.

**VERDICT: the property is right and `checks/gen/` was wrongly UNIGNORED, so the defect was in
the TREE, not in the predicate.** Adding `checks/gen/` to a predicate would have been the fix
that reproduces the bug with more items. See `TABLE.md` §5 for what changed instead.

## P2 — "a gate writes into it" — **ADOPTED, AND IT IS THE ONE THAT WORKS**

Not as a list. `gates/gendirs.py` scans **every** `.py`/`.sh`/`.mjs`/`.js` in the tree for a
write-shaped call and resolves the target through a constant-propagation fixpoint seeded with the
source file's own `__file__`.

### IT TOOK FOUR WRITER SHAPES TO SEE `checks/gen/`, AND THREE OF THEM ARE MEASURED MISSES

| # | shape | example | found on version 1? |
|---|---|---|---|
| 1 | method, literal arg | `Path("out/x").write_text(s)` | yes |
| 2 | method, module constant | `D = ROOT/"runs/graphcmp/D"`; `D/"x"` | **no** — 1,209/1,690 unresolved |
| 3 | method, **no positional arg** | `gendir.mkdir(exist_ok=True)` | **no** — the dir is the RECEIVER |
| 4 | **compiler `-o` in a subprocess** | `subprocess.run([BEND, src, "-o", gendir/"probe.js"])` | **no** — nothing opens the file |

**Shape 4 IS `checks/gen/`.** `checks/abi_gate.py` never touches either output file; it NAMES it on
a `bend` command line. And six further fixes were each MEASURED before the scan could see it:

| fix | why it was needed, measured |
|---|---|
| `__file__` seeded with the source's absolute path | without it `HERE` never binds and the scan reports **zero** for `checks/gen/` |
| `expr(node.value, env)` — the env **passed in** | `expr(node.value)` built a fresh `{}`, so the fixpoint evaluated its own RHS against an EMPTY environment |
| `str(x)` unwrapped | `:616` writes the path as `str(gendir / f"probe.{ext}")`; a cast is not a path operation and a scanner that treats it as one never reaches the path |
| `.parent` **strips** a component | recursing into `.parent` binds `HERE` to the FILE, so `HERE/"gen"` → `…/abi_gate.py/gen`, which is not a directory — **the `artefacts_ok()` shape: a guard answering about a path that cannot be right** |
| `self.dir` is an **env key** | `gates/gatekit.py:176-177`: recursing reaches `Name('self')`, which binds nothing, so the directory TEN gates write into was invisible — which is why `retention-check.py` transcribes it by hand |
| `.parents[n]` evaluated with the **shape**, and `parents[n]` on a **prefix** | the two spellings differ by one and `name` is how `gates-pop.py` mis-measured a file; a runtime PARAMETER (`ART / name`) has no full value, so its DIRECTORY PREFIX is what survives — and that is the thing a list enumerates |
| out-of-repo tested on `rel`, **never** on `target.startswith("/")` | the fixpoint resolves to an absolute path, so an absolute filter discarded the subject. **A GUARD WHOSE FILTER IS SHAPED LIKE ITS SUBJECT EXCLUDES ITS SUBJECT** |
| `mkdir` names a DIRECTORY; `isdir` decides nothing | on a fresh tree `checks/gen` does not exist yet, so `isdir` bucketed `checks/gen` under **`checks`** — the subject reported as its own parent |
| `root` **resolved** before relativising | `tempfile` hands back `/var/…`, `resolve()` hands back `/private/var/…`, so **6 of 7 plants discovered NOTHING** while the live tree stayed green |

### THE ADMITTED LIMIT, MEASURED NOT ASSUMED

`checks/abi4_gate.py:501` runs `rc_of(REPO / g)`, and `rc_of` is
`subprocess.run([sys.executable, str(script), *args], cwd=REPO)` — **it names no output path at
all.** `checks/gen/` is written **two processes away**. So `discovered()` is a **LOWER BOUND**, and
both consumers print the coverage line (`1,553 of 2,041 source files read`) so the bound is
visible on every run.

**NO AMOUNT OF AST WORK CLOSES THIS: THE WRITER IS NAMED BY A CALL AND THE TARGET BY A CONVENTION
INSIDE ANOTHER PROGRAM.** Closing it needs EXECUTION, and nothing here executes a gate —
`bend` peaks at 1,468 MB against a 2,048 MB ceiling with six units live.

## P3 — "nobody cites it"

**REJECTED, AND THE BRIEF'S OWN EVIDENCE IS THE PROOF.** A citation index built from a tree that
contains the instrument has gone wrong three times here: `residue`'s own
`000-the-residue.md` named every row and became the citation that kept them all; `sweep.py`'s
`ORACLE` was a basename word-shape 670 of 675 files satisfied and no gate named;
`undeclared_gap`. And measured directly: `checks/gen/` is cited **9 times** by `checks/abi.json`
and read back by `checks/abi_gate.py:624`, so P3 classifies the subject as **NOT** generated.
**A POPULATION DEFINED BY WHAT IS ABSENT NAMES EVERY DIRECTORY IN THE TREE**, because a directory
nothing writes into is trivially uncited.

## P4 — "a `.gitignore` rule NAMES the directory"

**REJECTED AS A SEPARATE ANSWER: it is P1 restated.** The ignore file is a *declaration of intent
by someone*; it is already in the tree and already queryable (`--no-index`). Using it as the
population means the population is exactly what people remembered to write down — **the defect,
not the fix.** It is now P1's *remedy*, applied to the tree instead of to a predicate.

## THE ANSWER

**YES — P2, by scan, with a printed lower bound. NO LIST TO MAINTAIN, AND MEASURED: 194
directories from 1,553 source files, of which `checks/gen` is one and was invisible to both
instruments before.**

**AND A FOURTH FINDING THE CANDIDATES DID NOT ANTICIPATE.** "Is it ignored" and "is it indexed"
must be asked of *different* populations with *different* flags: the index for tracked-ness,
`--no-index` for ignore-ness. An instrument that asks both with the default flags **answers about
a population that is the complement of the one it reports on.**

## WHAT TWO INSTRUMENTS DO WITH ONE POPULATION

`gates/gendirs.py` is imported BY PATH by both `gates/retention-check.py` (clause V) and
`gates/gates-pop.py` (clause IV), and both print the same count. MEASURED: **194 and 194, they
agree.** Not because they were reconciled — because there is one function.

**THE SHARED FATE OF BOTH INSTRUMENTS SO FAR WAS THAT A DECLARATION DERIVED FROM THE TABLES IT
DESCRIBES CANNOT AUDIT THOSE TABLES, BECAUSE BOTH CHANGE TOGETHER — FOUR STATIC CHECKS FOUND ZERO
DRIFT WHILE RE-DERIVING FROM THE SAME TABLES.** One module, one population, two consumers: a
change moves both, so the pair can be checked against each other *and* against the tree.