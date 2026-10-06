# THE TABLE — every directory in this tree that something WRITES into, tracked or not

**Produced by a SCAN, not by a list.** `gates/gendirs.py` reads **every** `.py`/`.sh`/`.mjs`/`.js`
in the tree, finds every write-shaped call, and resolves each target through a constant-
propagation fixpoint seeded with the source file's own `__file__`. Then it asks `git` about every
directory the scan names. `.agents/slop/gendirs/properties.md` evaluates WHY a scan and not a
list, with the measurements; this file is the table.

**A POPULATION DEFINED BY A THREE-ITEM LIST CANNOT BE WRONG ABOUT A FOURTH ITEM BECAUSE IT NEVER
LOOKS AT ONE.**

```
python3 gates/gendirs.py            # the table
python3 gates/gendirs.py --json     # machine copy
python3 gates/gendirs.py --plant    # seven plants, synthetic trees only
```

## THE SCAN'S DENOMINATOR

| | n |
|---|---|
| source files present | **2,048** |
| source files read (`SKIP_TOP` = `.git, references, node_modules, .venv, __pycache__, bin`) | **1,560** |
| write sites resolved | **~810** |
| **distinct target directories** | **194** |
| of those, in the git index | **101** (1,220 index entries) |
| of those, indexed **and** `.gitignore`d | **0** (was 1: `checks/gen`) |

**THIS IS A LOWER BOUND AND IT IS PRINTED ON EVERY RUN.** `checks/gen/` is reached through
`bend -o` in a subprocess whose caller (`checks/abi4_gate.py:501`, `rc_of`) names no output path
at all. **THE WRITER IS NAMED BY A CALL AND THE TARGET BY A CONVENTION INSIDE ANOTHER PROGRAM**,
so no static scan closes the gap; closing it needs execution, and nothing here executes a gate
(`bend` peaks at 1,468 MB against a 2,048 MB ceiling with six units live).

## THE TABLE

`trk` = entries in the **git index**; `HEAD` = in the last commit; `ign` = a `.gitignore` rule
names it (`--no-index`); `empty` = index entries whose blob is git's EMPTY BLOB `e69de29`.

### The rows that matter — output directories of THIS project's instruments

| directory | written by | trk | HEAD | ign | empty | `retention-check` I–IV | `retention-check` V | `gates-pop` IV |
|---|---|---|---|---|---|---|---|---|
| `runs/graphcmp/D/` | `checks/differ.py` (module functions) | 0 | 0 | **yes** | 0 | **YES** | YES | YES |
| `gates/artifacts/<gate>/` (10–11 dirs) | `gates/gatekit.py:176-177` `Gate.__init__` | 0 | 0 | **yes** | 0 | **YES** | YES | YES |
| **`checks/gen/`** | **`checks/abi_gate.py:606,616` (`bend -o`)** | **0** | **0** | **yes** | **0** | **NO** | **YES** | **YES** |
| `checks/` (51 `rows-*.rows` + `check.out`) | `checks/census.py:64`, `checks/both-census.py`, `checks/hermetic-census.py` | 4 | 0 | `rows-*` **yes** | 4 | NO | census | YES |
| `checks/rows-*.rows` | same, `.rows` cache per `(graph, side)` | **0** | 0 | **yes** | 0 | NO | census | YES |
| `.agents/slop/w64/cands/` | `checks/gen.sh:41-56` (heredoc `cat >`) | 0 | 0 | no | 0 | NO | census | YES |
| `.agents/slop/lintable/` | `checks/lintable-gate.sh` | 0 | 0 | no | 0 | NO | census | YES |
| `.agents/slop/runs/e2e/` | `checks/e2e.sh` (`$RUN`) | 0 | 0 | no | 0 | NO | census | YES |
| `gates/oracles/` | `gates/oracles/*.sh` | 2 | 2 | no | 0 | NO | census | YES |
| `oracles/gateport/oracles/` | `oracles/gateport/oracles/*.sh` | 4 | 4 | no | 0 | NO | census | YES |
| `langs/out/` | `langs/verify.sh` | 0 | 0 | no | 0 | NO | census | YES |
| `.agents/slop/**` (~380 dirs) | `.agents/slop/**` gates | many | many | mixed | 8 | NO | census | YES |
| `tinygrad/`, `test/`, `extra/`, `examples/` | the vendored upstream tree | yes | yes | no | 2 | NO | census | YES |

**ROWS 4–11 ARE THE FINDING, AND ONLY ROWS 1–3 WERE VISIBLE TO ANYTHING.** `checks/gen/` is the
brief's subject; `checks/rows-*.rows` (51 files), `.agents/slop/w64/cands/`,
`.agents/slop/lintable/`, `.agents/slop/runs/e2e/`, `langs/out/` and `gates/oracles/` are the same
defect at the same shape and **were in no instrument's denominator.**

### THE LAST ROW IS WHY "WRITTEN INTO" IS NOT "GENERATED"

`tinygrad/` is written into by its own build and is **source**. So "something writes here" is a
**lower bound on "generated"**, and clause V prints the bound as a **CENSUS with a count, not a
verdict** — the same discipline `retention-check.py` already applies to `unregistered()` and the
same lesson `LIVE_UNITS` taught.

## WHAT CLAUSE V ACTUALLY FAILS ON, AND WHY IT NEEDS NO LIST

**A DIRECTORY THAT IS IN THE INDEX *AND* NAMED BY A `.gitignore` RULE.** That is the tree
contradicting itself in two of its own files: one declares the directory is generated output that
must not be tracked, the other tracks it. It is decidable from two git commands and **needs no
knowledge of which directories exist**, so it would have caught `runs/` and `gates/artifacts/`
before clause III's 219-entry red.

**MEASURED: it fired on `checks/gen` while that directory held 2 index entries, BOTH at git's
empty blob — a tracked PLACEHOLDER, not a tracked artifact. It reads 0/194 now, after §5.**

### AND THE FLAG THAT DECIDES IT IS A FINDING OF ITS OWN

```
$ git check-ignore -v -- checks/gen/              -> rc 1, no output
$ git check-ignore --no-index -v -- checks/gen/   -> .gitignore:153:checks/gen/
```

`git check-ignore` **without `--no-index` reports "not ignored" for every path that is IN THE
INDEX** — git's own documented default. **A GUARD WHOSE QUERY CANNOT SEE ITS OWN SUBJECT.** The
index and the ignore rules must be asked with *different* flags, or the instrument answers about
the complement of the population it reports on. `gates/gendirs.py:ignored()` passes `--no-index`.

## §5 WHAT A CLONE GOT FROM `checks/gen/`, AND WHAT WAS DONE ABOUT IT

| where | `probe.js` | `probe.gen.c` |
|---|---|---|
| **worktree** | 49,265 B / 1,415 lines | 219,258 B / 8,647 lines |
| **git index, as found** | `100644 e69de29…` **empty blob** | `100644 e69de29…` **empty blob** |
| **`HEAD`, as found** | **ABSENT** | **ABSENT** |
| `git check-ignore`, as found | **not ignored** | **not ignored** |

`e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` is `git hash-object -t blob /dev/null`.
**BOTH TRACKED ENTRIES WERE GIT'S EMPTY BLOB.**

### AND THE ANSWER IS WORSE THAN "TWO EMPTY FILES IN EVERY CLONE"

**A CLONE GOT *NOTHING*.** `git ls-tree -r HEAD -- checks/gen` exits 0 with **zero lines**: the
directory was not in `HEAD` at all. The two empty blobs were in the **working-copy index only**
(jj's `@`), never committed. So the brief's premise — "a clone gets two empty files named
`probe.js` and `probe.gen.c`" — is measurably wrong in the *safer* direction: a clone got **no
directory**, and the first thing that happens on any machine that checks out and runs is
`gendir.mkdir()`.

### THE 9 CITATIONS THAT DEPEND ON IT, MEASURED BOTH WAYS

`checks/abi.json` declares **9 `site` entries** whose `file` is `gen/probe.js` or
`gen/probe.gen.c` — ABI-1 (2), ABI-2 (4), ABI-4 (3) — across `c_backend` and `js_backend`.
Resolved exactly as `checks/abi_gate.py:520-560`'s `cite_ok` does:

| | citations resolved | STALE |
|---|---|---|
| **worktree (real bytes)** | **9 / 9** | **0** |
| **against git's empty blob** | **0 / 9** | **9** |

`checks/abi_gate.py:624` READS BOTH FILES BACK (`q = gendir / f.removeprefix("gen/")`) to check
those citations, and `checks/abi4_gate.py:501` shells out to `checks/abi_gate.py` and reads its
exit status. **SO THE GATE'S OWN POINTER CHECK WAS 9/9 STALE ON ANY CHECKOUT THAT HAD NOT RUN THE
GENERATOR FIRST — A GATE THAT DEPENDS ON A FILE THAT IS EMPTY IN EVERY CLONE.** Confirmed by the
tokens: `io_eff_rows[c].run(e, fs, w)` and `io_node(e, CID_TUPLE, a, b)` each match **1** line in
the real `probe.gen.c` and **0** in the empty one.

### WHAT WAS DONE, AND THE PRECEDENT

**UNTRACKED — following clause III's OWN precedent.** `.gitignore` gained `checks/gen/`,
`checks/rows-*.rows` and `checks/check.out`, beside the two rules clause III's 219-entry red
produced. MEASURED now: **0 index entries, 0 in `HEAD`, ignored, and both files still on disk with
their 268,523 bytes.** Nothing is lost — the two "tracked" entries were git's empty blob, which is
not an artifact but a placeholder tracked as if it were a file, and the real bytes are
regenerable by one `bend -o`.

**AND THE MECHANISM IS WORTH NAMING, BECAUSE THE BRIEF EXPECTED `git rm --cached`.** No index
command was run. The project commits with **jj**, and jj does not snapshot ignored paths into its
working-copy commit — so the ignore rule alone moved the files out of the index at the next
snapshot, exactly as it moved `runs/` and `gates/artifacts/` from 219 tracked generated files to
0. **`.gitignore` CANNOT UNTRECK UNDER GIT. IT CAN, UNDER JJ, BECAUSE JJ'S COMMITTED STATE IS THE
SNAPSHOT AND THE SNAPSHOT SKIPS IGNORED PATHS.** Measured, not assumed: `git ls-files -s
checks/gen/` returns nothing and `jj file list -r @ checks/gen` warns "No matching entries".

**THE DIRECTORY IS STILL THERE AND STILL GENERATED. IT IS JUST NO LONGER TRACKED, WHICH IS WHAT
CLAUSE III ASKED FOR IN THE FIRST PLACE.**