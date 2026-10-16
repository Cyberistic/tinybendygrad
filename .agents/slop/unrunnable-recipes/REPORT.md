# CENSUS: UNRUNNABLE RECIPES in `.bend` files

**INSTRUMENT** `checks/unrunnable-recipes.py` (**594 lines**) · **TABLE** `checks/unrunnable-recipes.rows`
(**4 192 rows** + header, 11 columns) · **RUN** `.venv/bin/python checks/unrunnable-recipes.py` (42 s)
**NOTHING CALLS IT.** `grep -rln unrunnable-recipes` over `*.py *.sh *.md *.tsv *.json` names nothing
outside the file itself (measured 2026-10-16). **THIS IS A NOTE, NOT A GATE.**

---

## 1. THE DENOMINATOR, AND HOW THE POPULATION WAS FOUND

**Population = `os.walk`, not a list.** `walk_bend_files()` walks 15 declared top-level roots,
keeps the `.bend` suffix, skips 8 directory names (`.git __pycache__ references .venv node_modules .jj`).
`references/` is excluded because `.gitignore:2` holds it — it is 1 714 `.bend` files of third-party
Bend source, not this project's claim about itself. **Both numbers are printed on every run.**

| stratum | `.bend` files |
|---|---|
| `tinybendygrad/` (the port) | **134** |
| `.agents/` | 112 |
| `gates/` | 60 |
| `oracles/` | 16 |
| `checks/` | 4 |
| `runs/` | 3 |
| `examples/` | 1 |
| `langs/` | 1 |
| **TOTAL WALKED** | **331** |

| | port stratum (`tinybendygrad/`) | all strata |
|---|---|---|
| files | 134 | 331 |
| distinct `(file,line,token)` rows | 2 624 | 4 192 |
| files carrying ≥1 **recipe-position** row | **95** | 136 |
| rows in recipe position | 170 | — |
| files carrying ≥1 **unrunnable** recipe | **17** | 27 |
| unrunnable recipe rows (not negated) | **30** | 48 |

`RECIPE` is a **label applied after extraction, never a filter**: every unresolved token is printed
whether or not it earned the label, so a bad label cannot hide a row.

---

## 2. THE TABLE — 30 rows, 24 distinct paths, 17 port files

**READ THIS BEFORE THE TABLE: `tinybendygrad/mixin/rand.bend` IS NOT IN IT, BECAUSE IT WAS FIXED
WHILE THIS CENSUS RAN.** My first pass found `rand.bend:85-86` naming `$ORACLE_DIR/rd-gate.sh` and
`$ORACLE_DIR/rd-truth.py`, which is the instance the brief named. A concurrent unit replaced that
block between my runs: `rand.bend` now prints `.venv/bin/python gates/rand_census-gate.py` at line
95, **that gate exists (23 888 B, on disk, in HEAD)**, and the dead `$ORACLE_DIR` tokens survive only
as prose at line 97, where `$ORACLE_DIR` is followed by a backtick and not a `/`, so the extractor
emits no row for it at all. `gates/rand_census-gate.py` is now the 4th `.agents/slop`-free port gate
recipe; the census counted it `ON-DISK/TRACKED` at `rand.bend:95,105,120,1255`.

**SO THE 30 ROWS BELOW ARE A MOVING NUMBER, AND `rand.bend` IS THE PROOF: 32 ROWS IN 18 FILES WAS
THE COUNT 40 MINUTES AGO.** Every row below was re-verified against the committed
`checks/unrunnable-recipes.rows` and, for 10 of them, against the file itself by `sed`.

State key: **`WAS-OURS`** = not on disk, not in HEAD, **but `git log HEAD` touched it** (recoverable).
**`NEITHER`** = not on disk, not in HEAD, **not in our history at all**. **`UNRESOLVED-ENV`** = a
`$VAR/...` token whose variable has no assignment in the same file.

| file:line | named path | state |
|---|---|---|
| `tinybendygrad/mixin/creation.bend:123` | `$ORACLE_DIR/cr-gate.sh` | UNRESOLVED-ENV |
| `tinybendygrad/mixin/creation.bend:125` | `$ORACLE_DIR/cr-truth.py` | UNRESOLVED-ENV |
| `tinybendygrad/mixin/creation.bend:126` | `$ORACLE_DIR/cr-mutate.py` | UNRESOLVED-ENV |
| `tinybendygrad/mixin/creation.bend:129` | `$ORACLE_DIR/cr-truth.py` | UNRESOLVED-ENV |
| `tinybendygrad/mixin/reduce.bend:21` | `$TMP/mixin-reduce-gate.py` | UNRESOLVED-ENV |
| `tinybendygrad/codegen/late/linearizer.bend:150` | `tinybendygrad/codegen/late.bend` | WAS-OURS |
| `tinybendygrad/codegen/late/linearizer.bend:935` | `tinybendygrad/codegen/late.bend` | WAS-OURS |
| `tinybendygrad/codegen/decomp/transcendental_f32.bend:48` | `.agents/slop/tc-gen.py` | WAS-OURS |
| `tinybendygrad/engine/realize.bend:2052` | `.agents/slop/notes/rz-oracle.py` | WAS-OURS |
| `tinybendygrad/engine/worker.bend:606` | `.agents/slop/probe/mutate.py` | WAS-OURS |
| `tinybendygrad/helpers.bend:74` | `.agents/slop/nocolor-oracle.txt` | WAS-OURS |
| `tinybendygrad/nn/datasets.bend:43` | `.agents/slop/dst-oracle.py` | WAS-OURS |
| `tinybendygrad/nn/datasets.bend:429,430` | `.agents/slop/dk-mutate.py` | WAS-OURS |
| `tinybendygrad/renderer/ptx.bend:36` | `.agents/slop/ptx-s3-oracle.py` | WAS-OURS |
| `tinybendygrad/renderer/ptx.bend:1219` | `.agents/slop/ptx-s3-mutate.py` | WAS-OURS |
| `tinybendygrad/renderer/tc.bend:39` | `.agents/slop/tcptx-oracle.py` | WAS-OURS |
| `tinybendygrad/runtime/ops_bend.bend:2792` | `.agents/slop/bend_oracle.py` | WAS-OURS |
| `tinybendygrad/runtime/ops_bend.bend:2807` | `.agents/slop/bend_e2e.py` | WAS-OURS |
| `tinybendygrad/runtime/ops_disk.bend:2095-2097` | `.agents/slop/dk-mutate.py` | WAS-OURS |
| `tinybendygrad/runtime/ops_metal.bend:3718` | `.agents/slop/mt_constmap.py` | WAS-OURS |
| `tinybendygrad/runtime/ops_qcom.bend:158` | `.agents/slop/qc_oracle.py` | WAS-OURS |
| `tinybendygrad/runtime/ops_qcom.bend:159` | `.agents/slop/qc_stage3_oracle.py` | WAS-OURS |
| `tinybendygrad/runtime/ops_qcom.bend:160` | `.agents/slop/qc_cache_oracle.py` | WAS-OURS |
| `tinybendygrad/runtime/ops_qcom.bend:161` | `.agents/slop/qc_exec_oracle.py` | WAS-OURS |
| `tinybendygrad/runtime/support/autogen.bend:1099` | `.agents/slop/ag-oracle.py` | WAS-OURS |
| `tinybendygrad/tensor.bend:2806` | `.agents/slop/backward/bwd-mutate.sh` | **NEITHER** |
| `tinybendygrad/uop/ops.bend:3863` | `.agents/slop/notes/compiled-matcher-shape.bend` | WAS-OURS |
| `tinybendygrad/runtime/autogen/libclang.bend:6` | `.agents/slop/ag-emit.bin` | **RECIPE-PRODUCT** (see §4.10) |

By state (distinct paths): **19 WAS-OURS · 4 UNRESOLVED-ENV · 1 NEITHER**, plus **1 RECIPE-PRODUCT**
(`ag-emit.bin`, §4.10) which is deliberately counted separately rather than as a miss. **24 broken.**

**THE HEADLINE, MEASURED: 19 DISTINCT INSTRUMENTS UNDER `.agents/slop/` ARE CITED BY 14 SHIPPED PORT
FILES AS THINGS TO RUN, AND 18 OF THE 19 WERE DELETED FROM OUR OWN HISTORY.**

### 2a. The `$ORACLE_DIR` family is worse than "missing"

`$ORACLE_DIR` is **assigned nowhere in the tree** — not in `creation.bend`, not in `rand.bend`
(where it survives only as prose at `:97`), not in any `.md`/`.py`/`.sh`
(`grep -rn 'ORACLE_DIR=' --include=*.bend *.md *.py *.sh` → 0 hits). So the variable is unresolvable
in-file, which is the third state the brief asked for. **But the basenames were never at any path, on
any ref:**

```
$ for b in cr-gate.sh cr-truth.py cr-mutate.py rd-gate.sh rd-truth.py rd-mutate.py \
           mixin-reduce-gate.py; do printf '%s allRefs=%s\n' "$b" \
  "$(grep -c "/$b\$" /tmp/allhist.paths)"; done
cr-gate.sh allRefs=0      rd-gate.sh allRefs=0      rd-mutate.py allRefs=0
cr-truth.py allRefs=0     rd-truth.py allRefs=0     mixin-reduce-gate.py allRefs=0
cr-mutate.py allRefs=0
```

`/tmp/allhist.paths` is `git log --all --pretty=format: --name-only | sort -u` = **81 533 paths**,
of which **52 766 are under `.agents/slop/`**. So this is not a directory the sweep cannot see.
**THE CALLER'S VERIFICATION IS CONFIRMED AND STRENGTHENED: not merely absent, never committed.**
`creation.bend:126` says as much in its own prose — *"`$ORACLE_DIR` is outside the tree because the
brief makes `.agents/` append-only for this unit"* — which is a claim the file could not have made
honestly, because the files it names are in no tree this repository has ever had.

### 2b. `tinybendygrad/codegen/late.bend` — a deleted PORT file with a live oracle

`linearizer.bend:150` and `:935` both print
`diff <(python3 /tmp/opencode/late-oracle.py) <(./bin/bend tinybendygrad/codegen/late.bend)` as
**"the acceptance test"**. Three facts, each measured:

1. The file **does not exist**, and `codegen/late/` is a *directory* holding 5 `.bend` files.
2. It **was ours**: `git log --all --oneline -- 'tinybendygrad/codegen/late.bend'` = **170 commits**;
   `git show 2807aba5e^:tinybendygrad/codegen/late.bend | wc -l` = **3 507 lines**. Deleted by
   `2807aba5e` (2026-10-02), *"close 6 of the 10 remaining 1:1 violations, with byte-identical
   union proofs -- and the strongest evidence yet that a GREEN GATE proves nothing"*.
3. **`oracles/tinybendygrad_codegen_late.bend.rows` IS STILL IN HEAD** — 128 rows of expected output
   for a driver that has not existed since 2026-10-02. `checks/differ.py`'s `declared()` does **not**
   name it (176 names, checked), and the only things naming it are three `.agents/slop/` census
   artifacts. **An oracle for a deleted driver, committed, named by nothing.**

The second half of the recipe is equally dead: `/tmp/opencode/late-oracle.py` is outside the tree by
construction (the harness's own scratch dir), so **neither side of that `diff` exists.**

### 2c. `bwd-mutate.sh` — on a ref this branch never merged

`git log --all --format='%h %s' --name-status -- '.agents/slop/backward/bwd-mutate.sh'` shows `A` in
three commits and no `D`. `git merge-base --is-ancestor 5444ea42e HEAD` → **no**. So the file is
**not recoverable by `git show HEAD:path`**; it lives on an unmerged ref. This is why the census
separates `WAS-OURS` (HEAD-reachable) from `NEITHER` — and why the bulk `git log --all --diff-filter=D`
sweep must not be trusted (§4.8).

### 2d. Other strata

| stratum | rows | notes |
|---|---|---|
| `gates/` | 1 | `gates/ew-consts.bend:3` → `.agents/slop/ew-consts-gate.sh` (WAS-OURS) |
| `examples/` | 5 | `beautiful_mnist.bend:1112-1116`, all `$T/…` — a scratch dir, see §4.11 |
| `.agents/` | 12 | 7 of the 12 are `strays/` snapshots of the same port defects |
| `checks/`, `oracles/`, `runs/`, `langs/` | 0 | |

---

## 3. "EXISTS" vs "RUNS" — and the answer is that RUNS is rare

Every resolved path was asked whether its **basename appears on a NON-COMMENT line** anywhere in
7 608 text files. `code` = a program reads it; `declared-by:` = a **generator's own `declared()`**
names it; `prose` = only inside a comment. Prose-kind files (`.md .rows .tsv .txt .out .err .csv`)
are forced to prose — that is a claim about what a file *can do*, not a list of names.

| | rows |
|---|---|
| port, `code` | **2 022** |
| port, `declared-by:checks/differ.py` | 2 |
| port, `prose` | **2** |
| all strata, `code` | 3 171 |
| all strata, `declared-by` | 6 |
| all strata, `prose` | 8 |
| all strata, `-` (11 `AMBIGUOUS-SUFFIX` rows — two or more paths end in that name, so the root is unknown and the row is **not** counted as resolved) | 11 |

**IN THE PORT STRATUM, NOT ONE OF ITS OWN FILES IS "EXISTS, AND NOTHING EXECUTES IT."** The only two
`prose` rows are upstream fixtures in the gitignored clone:
`references/bend/tests/halt/threaded_state_after.bend` (`ops_bend.bend:925`) and
`references/bend/tests/parse/if_no_else.bend` (`autogen.bend:89`) — both verified by hand: no
non-comment mention anywhere outside `references/`.

**"EXISTS AND SOMETHING EXECUTES IT" IS NOT RARE HERE BECAUSE THE PORT IMPORTS ITSELF.** 2 022 of
2 026 resolved rows are `code`. **AND THE IMPORT POPULATION MEASURED ACROSS THE WHOLE PORT IS NOT
WHAT `AGENTS.md` SAYS IT IS.** `AGENTS.md` claims "every import under `tinybendygrad/` is `Base` or
another `.bend` file in this repo, which is the one grep worth keeping." The whole population, by
`grep -rhoE '^\s*import\s+"[^"]*"' tinybendygrad --include='*.bend'`:

| import | count |
|---|---|
| `import "../../../.agents/slop/clangshim/libclang-tramp.c"` | **325** |
| `import "../../../.agents/slop/clangshim/libclang-ffi.c"` | **10** |
| `import "./runtime/sz.c"` | 2 |
| `import "./runtime/sz.js"` | 2 |
| **any `.bend` file, anywhere in the port** | **0** |

plus 119 unquoted `import Base`. So **0 of the port's `.bend` files are imported by another `.bend`
file, 335 imports are `.c` files under `.agents/slop/`, and 4 are `.js`/`.c` under `runtime/`.** All
339 quoted ones resolve (`sz.c` 4 343 B, `sz.js` 950 B, both on disk and in HEAD — §4.1), so this is
a statement about the *shape* of the import population, not a defect row. **But the grep `AGENTS.md`
calls "the one grep worth keeping" cannot produce this table**, because it is shaped by the claim it
was written to support.

**THE 2 `declared-by` ROWS ARE THE ONES A LITERAL-SCAN READER GETS WRONG.**
`tinybendygrad/uop/ops.bend:1179` and `:4682` cite `runs/graphcmp/D/D1-graph-mselect.txt`. That file
is on disk (4 610 B), **not in HEAD**, and is in `checks/differ.py`'s `declared()` — which *derives*
its 176 names out of `corpus()`/`CONTROLS`/`PLANTS`/`STAB`, so **no filename literal appears in any
code line.** A reader that can only see literals calls it unread. MEASURED FALSE.

---

## 4. WHERE MY OWN EXTRACTOR WAS WRONG — TEN CAUSES, EACH WITH ITS NUMBER

Every number below is the difference between two runs of `checks/unrunnable-recipes.py`.

| # | cause | false rows written / true rows deleted | the repair |
|---|---|---|---|
| **1** | **No resolution relative to the containing file's directory.** `tinybendygrad/runtime/autogen/libclang.bend` has **335** `import "../../../.agents/slop/clangshim/libclang-{tramp,ffi}.c"` lines (325 + 10). Both `.c` files are on disk and in HEAD; a ROOT-relative-only resolve called **every one** dangling. | **338 false NEITHER** | try the file's own directory first |
| **2** | **Two resolution bases, because the port's source set is its own root.** `tinybendygrad/nn/__init__.bend` writing `mixin/op.bend` means `tinybendygrad/mixin/op.bend` — neither the file's directory nor the repo root. | **41 → 0** on `mixin/op.bend` | walk **every ancestor** of the file's directory |
| **3** | **The mirror root is not `tinygrad/`.** `tinybendygrad/runtime/support/usb.bend` writes `autogen/libusb.py` 23× and only `tinygrad/runtime/autogen/libusb.py` exists; the port's own mirror does **not**. | **46 false NEITHER** | index **every path SUFFIX**; `>1` match ⇒ `AMBIGUOUS-SUFFIX`, counted as unresolved, not resolved |
| **4** | **No right-hand boundary test.** `elementwise.bend:43` writes `(1/math.log(2))` and the expression was read as a path named `1/math.log`. | **11 false NEITHER** | a token glued to `(`/`[`/`.`/word on the right is a call or member access |
| **5** | **`TRAILING_PUNCT.match` instead of `.search`.** `match` anchors at position 0, so `[.,:;]+\Z` **could never fire**; `w64/cands/cand0.bend:1`'s `generated by checks/gen.sh. Do not hand-edit` stayed a path named `checks/gen.sh.` — and `checks/gen.sh` **exists**, 5 013 B, executable. | **7 + 2 rows survived a repair that did not repair** | `.search`, and strip only while `token[-2].isalnum()` — which is what keeps `gen.pyc` from becoming `gen.py` |
| **6** | **A pair-shorthand rule that matched dotfiles.** `\A[^/]*\.[A-Za-z0-9]+/` — `[^/]*` matches the EMPTY string, so `.agents/slop/dk-mutate.py`'s leading dot read as an extension and **every `.agents/` citation in the tree vanished.** `NEITHER` fell 886 → 220. | **666 TRUE ROWS DELETED** | `[^/.]` — a segment needs a first character before its dot |
| **7** | **A "never committed" claim from an empty file.** I built `/tmp/allhist.paths` inside a command that hit the 120 s timeout; the file was **0 lines**, and I then ran 21 `grep -qxF … /tmp/allhist.paths` checks against it and reported **`anyCommit=no` for all 21**. It was wrong for 20 of them — `tinybendygrad/codegen/late.bend` was in **170 commits**. | **21 wrong rows** | rebuild the file first, and assert it is non-empty before trusting it |
| **8** | **A bulk sweep used where a per-path query was needed.** `git log --all --diff-filter=D --name-only` (23 555 paths) does **not** list `tinybendygrad/codegen/late.bend`, while `git log --all --name-status -- <that path>` reports `D` for `2807aba5e`, which **is** an ancestor of HEAD. | one wrong "not deleted" | the census asks `git log HEAD -- <path>`-equivalent ONCE over 26 551 paths |
| **9** | **A member-access shape read as a path.** `realize.bend:1538`'s "uop/ops.ParamArg with 13 fields" became a file named `uop/ops.ParamArg`. | **1** | a final segment whose dot is followed by an UPPERCASE letter is an attribute |
| **10** | **A git revision read as a path.** `uop/ops.bend:1056`'s `6c3d401cf324:tinygrad/uop/ops.py` — the path is real, the revision is the part that may not be. | **3** rows | peel a leading `[0-9a-f]{7,40}:`; answer the revision separately with `git cat-file -t` ⇒ **`6c3d401cf324=commit`** |
| **11** | **Ellipses and globs counted as files.** `ops_cl.bend:7`'s `.../a.bend`, `ops_qcom.bend:69`'s `.../kgsl.py`, `tinygrad/runtime/autogen/*.py`. | 4 + 3 | `…`, `//`, `*`, `?` are families |
| **12** | **A reader index that can only see literals.** §3 — it called `D1-graph-mselect.txt` unread. | 2 false `prose` | ask every module that defines a **top-level** `def declared(` (discovered by walk, not typed) |
| **13** | **A `set`-iteration order in an output column.** The `note` column joins every path sharing a basename, and it joined them in `set` order. **The table was NOT byte-reproducible:** `1f83544…` at `PYTHONHASHSEED=1` vs `97a6135…` at `=2`, differing in **20 rows a reader cannot tell apart**. | 20 rows, per run | build both indexes over `sorted(disk)`; verified `seed1 == seed7 == random == 929af948…` after the fix |

### 4.12 And the output was not reproducible until I checked

Cause 13 is the one that would have made every number in this report unciteable. `checks/differ.py
repro` exists to prove one run is reproducible, and **my table failed that test** — not because the
census was wrong, but because a `note` column joined paths in `set` order and `PYTHONHASHSEED`
changes `set` order for strings. Two runs of the same tree gave different sha256s in 20 rows.
**An instrument whose output cannot be diffed against itself cannot be reviewed**, so it is fixed and
the fix is verified across `PYTHONHASHSEED=1`, `=7`, and `=random`: `929af948…` three times.

### 4.10 And the one class I had to ADD, because a wrong exclusion deletes a true row

Cause 6 is the general lesson and it is the opposite of the remembered-extension bug. A *truncated*
token writes a **false** row. A *wrong exclusion* writes **no** row at all, which is worse, because a
false row argues with you and a deleted row does not. **SO EVERY REJECTION RULE NOW TALLIES ITSELF**,
and the tally prints on every run:

```
REJECTED (each rule's OWN size -- an exclusion that cannot report its size can go blind):
   family-or-glob=50   git-revision=3   glued-right=13   member-access=1
   no-dotted-tail=9234   pair-shorthand=11
```

And the mirror of that: a recipe that **produces** its own target is not a dangling reference.
`libclang.bend:5-6` runs `./bin/bend .agents/slop/ag-emit.bend -o .agents/slop/ag-emit.bin` and then
`.agents/slop/ag-emit.bin > <this file>` — so the `.bin` is **absent on the first run by design**.
Without a `RECIPE-PRODUCT` class the census reported a build artifact as a hard miss. **40 rows.**

### 4.11 And the negation, because `./x.c` means two opposite things

`tinybendygrad/runtime/ops_rdma.bend:173` writes "the trace IS the record of the call.
`import "./x.c"`" — a citation. `ops_dsp.bend:132` writes "**No** `import "./x.c"`" — a claim that
the path is absent **by design**. Same token, opposite meaning, and the census would have called the
second a dangling reference. 13 rows carry `negated=yes` (11 in the port) and are reported separately
rather than dropped.

---

## 5. WHAT I DID NOT DO

1. **I did not edit one `.bend` file**, including `mixin/rand.bend`, which another unit owns.
2. **The 19 recoverable instruments need `git show <commit>:<path>` restored under `checks/` or
   `gates/artifacts/`-adjacent tracked paths, not under `.agents/slop/`.** AGENTS.md's own measurement
   is that `.agents/slop/` is pruned and `gates/artifacts/` is `.gitignore`d — a gate's required input
   belongs **beside the gate, in git**. 18 of the 19 are one command each. **I did not run it**: it is
   a mass restore and another unit is working the same area.
3. **`oracles/tinybendygrad_codegen_late.bend.rows`** (128 rows, in HEAD, oracle for a driver deleted
   at `2807aba5e`) is a finding, not a fix. **I did not delete it.**
4. **`gates/gates-pop.ledger.tsv` has NO ROW for this instrument and I did not add one.** Running
   `gates/gates-pop.py` to check reported `III NEW checks/unrunnable-recipes.py` and **rewrote the
   ledger in place**, absorbing another unit's uncommitted rows. I restored the other units' rows by
   re-running the generator and removed only my own line; the ledger's remaining 20-insert/1-change
   diff against HEAD is **theirs, not mine, and is uncommitted.**
5. **`gates/gates-pop.py`'s `HOMES` is `("checks", "gates")`**, so this census is inside its
   population and its `III NEW` verdict is the ledger row that is missing.
6. **The 11 port-stratum `OUTSIDE-TREE` rows** (`/tmp/py.txt` ×19 tree-wide, `/usr/lib/libobjc.dylib`,
   `-T/tmp/dsp_link.ld`) are labelled, not judged. **A `/tmp/` scratch target is not a defect**, and I
   did not want the census to invent one.
7. **I did not re-run `bend`.** Every claim here is a filesystem/git fact, so none of it needed a
   compile, and nothing in this report depends on the substrate.
8. **`no-dotted-tail=9234` is the largest rejection bucket and I did not analyse it.** Those are
   tokens with a `/` but no dotted final segment (`tinybendygrad/runtime`, `checks/gates`). They are
   not files, but **9 234 is a number I have not explained**, and an unexplained bucket that large is
   exactly where a tenth extractor defect is hiding.
9. **THE COUNT IS A MOVING NUMBER AND I CAUGHT IT MOVING.** `rand.bend` is absent from §2 because a
   concurrent unit replaced its `$ORACLE_DIR` recipe with `gates/rand_census-gate.py` mid-session;
   the census reads `rand.bend:85-86` as two `UNRESOLVED-ENV` rows on the first pass and as **zero**
   on the committed pass. **A census over a tree that other agents are writing reports a number with a
   timestamp on it or it reports nothing** — this is the same rule `AGENTS.md` records for `ruff`'s
   error count moving between four reads 193 s apart.