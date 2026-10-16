# CLAIM AUDIT 2 — the 16 commits the first audit did not cover

**Auditist:** a subagent of another session. Read-only over every existing file; the only things written
are new files under `.agents/slop/claimaudit2/` (`REPORT.md`, `claims.rows`, and the 16 extracted
commit messages under `msg/`).

**Measured at HEAD `03500a26202aa8560adbab980f705ad9c0a7cbfb`, 2026-10-16 14:36–14:47 UTC.**
Every number below carries that HEAD. The tree was moving while this audit ran — see §1's drift note,
which is itself one of the four STALEs.

---

## 1. HOW I DREW THE BOUNDARY, AND HOW MANY COMMITS

The previous audit (`.agents/slop/claimaudit/REPORT.md`) states its own boundary twice, and both agree:
it measured at `1b4905cba9903b125c172ee6bdb2b3db48ac436a` (§6 of its report) and its covered list ends
at that same commit (`1b4905cba9`, item 1 of its 24).

So my subject is the complement, by commit range:

```
git rev-list --count 1b4905cba9903b125c172ee6bdb2b3db48ac436a..HEAD   ->  16
git merge-base --is-ancestor 1b4905cba… HEAD                          ->  ANCESTOR-YES
```

**16 commits, newest first:**

| # | sha | subject |
|---|---|---|
| 1 | `03500a26` | UNRUNNABLE: 331 `.bend` files, 4192 recipe rows, and 30 of them name something that IS GONE |
| 2 | `f15c78db` | census: the table was NOT byte-reproducible, and that is cause 13 |
| 3 | `ef63403` | census REPORT: drop 2 stale rows, and record that the count is a MOVING NUMBER |
| 4 | `9145300a0` | census of UNRUNNABLE RECIPES: 331 .bend files, 30 unrunnable recipes in 17 of them |
| 5 | `e486d3ec` | DEVTAG2: the `optim.bend` BLOCKER WAS NEVER REAL — the `Dn` arm is gateable in THREE TOKENS |
| 6 | `ed8c95f6` | RANDWRITE: every PINNED DIVERGENCE in this layer was GREEN on a port returning the WRONG NUMBER |
| 7 | `b86e3c25` | The four `Device.tag` citations are corrected AND ONE OF THEIR REASONS WAS MEASURED FALSE |
| 8 | `9b1be76b` | port the WRITE in `_next_counter`, and give the semantic half a row that can fail |
| 9 | `6a94279b` | NORUNNER: 164 gates, and a runner names 3 paths under `gates/`, NONE of which is a gate |
| 10 | `d8a9359c` | TODO.md: three FALSE line citations, found by the claim audit and verified before fixing |
| 11 | `f65d140a` | UNGATED3: three "ungated" layers, and TWO HAD A WORKING GATE THAT NOTHING WIRED |
| 12 | `0b1edd858` | census the three ungated layers: onnx, state, rand — and three findings |
| 13 | `e233811c` | two units: an adversarial re-audit of MY OWN commits finds 10 FALSE claims, 4 of them mine |
| 14 | `037d5d53` | L2I64: a pool FED BUT NEVER DRAINED, and the gate's own footer named THE WRONG BLOCKER |
| 15 | `63f78ad3` | scratch path list, not a record: the five paths and the evidence directory are named in the commit above |
| 16 | `f7a630962` | decomp_graph_census: lgz — a 64-BIT FLOAT TARGET THE TARGET POOL NEVER PRODUCED, AND IT REFUTES THIS GATE'S OWN FOOTER |

**The boundary is not ambiguous, and that is worth saying plainly** because the first audit had to say
the opposite. The first audit selected by a *keyword filter* over commit messages and said so (§1 of
its report: "There is no principled cut inside 2026-10-16 either"). I did not need a filter: the first
audit names the exact commit it stopped at, that commit is an ancestor of HEAD, and the range between
them is 16 commits with no judgment in it. I verified coverage mechanically: the set of shas in
`claims.rows` equals the set from `git log 1b4905cba..HEAD` — `diff` reports no missing and no extra.

**One caveat about "since that audit".** The first audit's own measured numbers carry its timestamp
(12:55–13:10Z) and several of its claims were index-derived. The commits it audited and the commits I
audit interleave in *no* way: its newest is the immediate parent of my oldest. So this is a clean
succession, not an overlap.

**Drift I measured inside my own window, which is why one of my four STALEs is a STALE.**
`ls gates/*.py` read **164** at `6a94279b` (by `git ls-tree`), **165** at 14:36Z, and **167** at
14:46Z — the same command, ten minutes, HEAD unmoved. The extra two are uncommitted files another
session is adding right now. The first audit's `f18f2a52bf` row warned that a number without its
timestamp decays; here it decayed twice inside ten minutes, which is a stronger statement than the
one it made.

---

## 2. HOW MANY CLAIMS, AND THE SPLIT

**218 claims** were extracted from those 16 messages and re-verified. Every one is a row in
`claims.rows` (commit / quoted claim / verdict / evidence), 4 tab-separated fields per row, and the
counts below are `awk`ed from that file, not typed.

| verdict | rows | share of 218 |
|---|---|---|
| **CONFIRMED** | 138 | 63.3% |
| **UNVERIFIABLE** | 54 | 24.8% |
| **FALSE** | 22 | 10.1% |
| **STALE** | 4 | 1.8% |
| | **218** | |

Per commit:

| commit | CONFIRMED | FALSE | STALE | UNVERIFIABLE |
|---|---|---|---|---|
| `03500a26` | 16 | 3 | – | 3 |
| `9145300a0` | 12 | 3 | – | 7 |
| `f7a630962` | 12 | 3 | – | 8 |
| `b86e3c25` | 12 | 3 | 1 | 3 |
| `0b1edd858` | 14 | 1 | 1 | 5 |
| `037d5d53` | 8 | 3 | – | 7 |
| `ed8c95f6` | 5 | 2 | – | 4 |
| `f65d140a` | 9 | 1 | 1 | 5 |
| `e486d3ec` | 5 | 1 | – | 1 |
| `e233811c` | 9 | 1 | – | 3 |
| `63f78ad3` | 0 | 1 | – | 0 |
| `6a94279b` | 4 | 0 | 1 | 1 |
| `9b1be76b` | 9 | 0 | – | 4 |
| `d8a9359c` | 6 | 0 | – | 1 |
| `ef63403` | 12 | 0 | – | 0 |
| `f15c78db` | 5 | 0 | – | 2 |

---

## 3. EVERY FALSE — 22, grouped by shape

Nine of the ten FALSE in the first audit were a `file:line` citation or a count attached to one.
**In this batch, 20 of the 22 are that same shape** — a number, a denominator, or a line number — and
they cluster into six mechanisms. The two that are not are both in §3.5, and they are claims about
what a file *names* rather than how many of something there are. The most
important thing I can say is that **four of the mechanisms are ones the first audit had already
named in prose, in a commit inside my own range** — see §7.

### 3.1 A BEFORE-state line number in a file the same commit edits — 4 FALSE

`b86e3c25` is a comment-correction commit that edits `tinybendygrad/schedule/memory.bend`
(`--stat`: `20 ++-`). It cites three lines of that file, and **all three line numbers are correct at
its own parent and wrong in the commit**:

```
schedule/memory.bend @ b86e3c25^                @ b86e3c25 / HEAD
  999: def disk() -> S.Dev: S.D1{1}          ->   1007
  1000: def mdev() -> S.Dev: S.Dn{[2, 3]}    ->   1008
  1002: def unpl() -> List<&2, U32>: [1, 4]   ->   1010
```

> **"`the only supplier of unpl in this tree is unpl() = [1, 4]` at `:1002`"** — **FALSE.** `:1002`
> is now `def mem_buf(+slot: U32, size: U32, dev: S.Dev) -> O.ParamArg:`.

> **"`disk() = S.D1{1}` (`:999`)"** — **FALSE.** `:999` is `  match w:`.

> **"`schedule/memory.bend:1000` already mints `S.Dn{[2, 3]}`"** — **FALSE.** That is `:1008` now.

> **`e486d3ec` (60 seconds later, same unit): "`memory.bend:1002 def unpl() = [1, 4]` IS A LITERAL
> BESIDE THE FIXTURES"** — **FALSE**, same off-by-8, same file.

Note the direction: these are **pre-edit** numbers in an **after-edit** tree, which is the mirror of
`059c22cab`'s defect in the first audit (post-edit numbers against pre-edit text). Both are the same
one shape: **a citation into a file the same session is editing, computed on one state and published
against another.**

There is a second, uncounted instance of the same drift still live in the tree: `validate.bend:2533`
records the disagreement by citing `schedule/memory.bend:999` for `disk() = S.D1{1}`, which was true
when written and is now `:1007`. Not a commit message, so not a row — but it is the same defect
propagating.

### 3.2 A census refuted by the row the same commit adds — 5 FALSE

The strongest finding in the batch, and the one I looked hardest at.

`f7a630962`'s central claim is that a 64-bit float target **never reached `l2i`**. The claim is
stated three times. It is measured against a table **in the same tree the commit creates**, and that
table contains the counterexample:

```
gates/decomp_graph_census.bend, def dc_l2i_pick  (31 arms; 30 at f7a630962^)
  138: case 4:  dc_l2i1("lg5", O.OpsCAST{}, S.int64(),  S.single(), 19n, 2)
  162: case 28: dc_l2i1("lgu", O.OpsCAST{}, S.single(), S.single(), 19n, 2)
  184: case 29: dc_l2i1("lgz", O.OpsCAST{}, S.double(), S.single(), 19n, 2)   <-- f64
```

> **`f7a630962`: "`dc_l2i_pick` fed `l2i` 30 `(op, dt, xdt)` cells"** — **FALSE**; 31 in this commit's
> own tree.

> **`f7a630962`: "MEASURED the TARGET multiset was `int32 19, int64 6, uint32 3, uint64 1,
> single 1` — **ZERO 64-BIT FLOATS**"** — **FALSE**; the multiset in the committed table is
> `int32 19, int64 6, uint64 1, uint32 3, single 1, **double 1**`.

> **`f7a630962`: "`double` … reached `l2i` from no row"** — **FALSE**; `lgz` *is* such a row.

> **`037d5d53` (the very next unit): "THE TARGET MULTISET OF THE **30** `dc_l2i_pick` ARMS …
> `<- ZERO 64-BIT FLOATS`"** — **FALSE**, same measurement, same tree.

> **`037d5d53`: "`double` … REACHED `l2i` FROM 0 OF 30 ROWS"** — **FALSE**, same counterexample.

**The charitable reading, which I record because it is real:** `lgz`'s *token* is a refusal
(`refused:unported`), so no f64 cell **builds**. Both commits say so elsewhere and are right about it.
But the sentences above are claims about a **count of rows** and about **what reached `l2i`** — and
`dc_l2i1` hands `lgz` to `l2i` unconditionally. A conclusion drawn from a table, where the table's own
newly added row is the counterexample, is a claim that can be had for free and was not taken.

The mechanism name is the first audit's: *a count whose population is narrower than the thing the prose
says it covers* — except here the population is not narrower, it is **one row short of the truth and
the missing row is the subject of the sentence**.

### 3.3 A declared constant, quoted with the wrong size — 2 FALSE (one claim, two commits)

> **`9145300a0` / `03500a26`: "os.walk over 15 declared roots, `.bend` suffix, **8 skip-dirs**"**

**FALSE, and this one is not a rounding error, it is a miscount of the file's own declaration.**
`checks/unrunnable-recipes.py:70-71` declares exactly **15** roots — correct — and `:72` declares

```python
SKIP_DIRS = frozenset({".git", "__pycache__", "references", ".venv", "node_modules", ".jj"})
```

which has **6** members, not 8. There is no second skip set anywhere in the file (three walk sites,
all reading `SKIP_DIRS`). The rest of the population claim is excellent: I re-walked with the
instrument's own constants and reproduced **331** total and all eight per-root numbers exactly. So the
headline is right and one word of its own definition is wrong, twice.

### 3.4 A numerator that includes a row from the wrong directory — 2 FALSE

> **`9145300a0` / `03500a26`: "19 distinct instruments under `.agents/slop/` are cited BY 14 SHIPPED
> PORT FILES … and 18 of the 19 were deleted from our own history"**

**FALSE.** Measured on the table, port stratum, `recipe=yes`, `state=WAS-OURS`: **19 distinct tokens**
— but only **18** of them are under `.agents/slop/`. The nineteenth is
`tinybendygrad/codegen/late.bend`, a **port file**, cited twice by `codegen/late/linearizer.bend`.

The "18 of the 19 were deleted" half is separately wrong: **all 19** carry the note *"deleted from our
history; `git log HEAD -- <path>` finds the commit"*. And the **14-file denominator is CONFIRMED** —
14 distinct port files cite those rows. So this is the same shape as the first audit's `550678ecbb`
(24 constructors, actually 22): the count is off by exactly the member that does not belong to the
population the sentence names.

### 3.5 A commit refuted by a file the same commit creates — 2 FALSE

> **`0b1edd858`: "no `gates/*onnx*` named it, nothing imported it"**
> **`f65d140a` (4 minutes later): "NO `gates/*onnx*` NAMED EITHER, NOTHING IMPORTED EITHER, NO LEDGER ROW"**

**FALSE — self-refuting inside the commit.** `0b1edd858` creates nine files, one of which is
`gates/onnx_census-gate.py`, and its **line 7** reads:

```
WHAT "UNGATED" MEASURED TO BE, WHICH IS NOT "NO GATE". `.agents/slop/onnx-gate.py` EXISTS
```

That line is present in the blob `0b1edd858` itself. So the sentence is contradicted by a file the
sentence's own commit adds, four minutes before `f65d140a` repeats it.

The substantive half holds: nothing *imports* the slop script. But the word chosen is **NAMED**, and a
docstring that names the path is a naming. This is the first audit's `afbd85691c` defect reproduced
exactly — *"a count answering a different question than the one asked"* — except here the question was
asked correctly and the answer was read off the wrong instrument.

The ledger half of the same sentence was **true at the commit** (the ledger held no census-gate rows
then) and is **STALE now** — `gates/gates-pop.ledger.tsv` carries rows for all three census gates and
for `devtag-gate.py`.

### 3.6 A sentence that contradicts its own arithmetic — 2 FALSE

> **`9145300a0`: "#6 … NEITHER fell 886 -> 220"** — **FALSE.** 886 − 220 = **666** rows fell.

> **`03500a26` (the same claim, restated): "#6 … DELETED 666 TRUE ROWS, INCLUDING 23 OF THE DANGLING
> INSTRUMENTS"** — **FALSE as published**, because it is the same claim with the contradiction removed
> but the *other* half still in the message. `9145300a0` says nothing fell; `03500a26` says 666 fell.
Both cannot be true of one extractor defect, and the two commits are 6 minutes apart in the same unit.

The underlying finding is real — a `\A[^/]*\.` rule matching the empty string against dotfiles is a
genuine bug — and the 23 dangling instruments is the part that matters. It is the *count* that is
self-refuting.

### 3.7 "WERE DELETED" against the evidence that says "never existed" — 1 FALSE

> **`ed8c95f6`: "`$ORACLE_DIR/{rd-gate.sh,rd-truth.py,rd-mutate.py}` — **ALL THREE ABSENT,
> `git log --all` EMPTY FOR EACH** — **WERE DELETED**"**

**FALSE.** `git log --all` empty for all three is the evidence that they were **never committed** —
which cannot have been undone by a deletion. Three sibling commits by the same unit say so in exactly
those words: `0b1edd858` *"none was ever committed"*, `f65d140a` *"NEITHER WAS EVER COMMITTED"*,
`9b1be76b` *"none was EVER COMMITTED"*. The parenthetical in `ed8c95f6` refutes its own verb.

The **absence is CONFIRMED** — all three are gone from disk and from every ref. What is FALSE is the
causal story: "deleted" implies a loss event, and the project's own governing argument is that a path
inside a swept tree is *deletable*, not deleted. The distinction is the whole point of the commit two
positions later.

### 3.8 A number attached to a filename that means something else — 1 FALSE

> **`ed8c95f6`: "THE FIRST PORT FIX IN THIS LAYER (`mixin/rand.bend`, 190 lines)"**

**FALSE.** `tinybendygrad/mixin/rand.bend` is **1325 lines** at `ed8c95f6` and at HEAD (1211 at its
parent). 190 is not any reading of that file's length. It **is** the diffstat line count of
`rand.bend` in `9b1be76b` (`190 +++++…`) — so the author had a real number and printed it next to a
filename where the honest reading is off by 1135×.

### 3.9 Two line numbers for a gate driver, both wrong — 1 FALSE

> **`037d5d53`: "`dc_l2i_pick` (`:126`) AND `dc_lc_pick` (`:205`) ARE TWO HAND-WRITTEN TABLES"**

**FALSE.** In `gates/decomp_graph_census.bend`, unchanged between this commit and HEAD:
`def dc_l2i_pick` is at **:132** and `def dc_lc_pick` at **:215**. `:126` is `+ga = D.fixtures()` and
`:205` is a comment about cone order. Off by 6 and by 10. The file was *not* edited by this commit —
so these are not the §3.1 shift shape; they are simply the wrong lines in an unedited file.

Its sibling citation in the same commit, `census.bend:181-182`, is **CONFIRMED** — the corrected
footer is verbatim at `gates/decomp_graph_census.bend:181-182`.

### 3.10 A restated denominator that disagrees with the audit it cites — 1 FALSE

> **`e233811c`: "The truth is **15 of 22** under FS_DELETES' own four keys: I DROPPED THE 8
> `shutil.rmtree` CALLS"**

**FALSE on the denominator.** The audit `e233811c` is summarising says **15 of 54**
(`claimaudit/REPORT.md` §3.4: module-form 7 + `shutil.rmtree` 8 = 15, method-form 39, total 54).

I re-took the numerator with an independent AST walk of `checks/` + `gates/` at HEAD under
`checks/sweep.py:284-285`'s four declared keys, and got **15 module-form** (`os.remove`, `os.rmdir`,
`os.unlink`, `shutil.rmtree` — all four keys represented) and **46 method-form**, 61 total. So the
numerator 15 reproduces exactly, and **no instrument available in this tree yields 22**.

The brief asked me to watch denominators specifically. This is the one place in 16 commits where a
denominator was carried across a summary and changed value in transit, and it changed by 32.

### 3.11 A claim about the commit above, checked against the commit above — 1 FALSE

> **`63f78ad3`: "scratch path list, not a record: **the five paths and the evidence directory are
> named in the commit above**"**

This commit's whole content is a deletion, and its diff is what makes the claim checkable:
`.agents/slop/l2ipool/msg.rows`, six lines —

```
gates/decomp_graph_census.bend
gates/decomp_graph_census-gate.py
gates/decomp_graph_census-oracle.py
gates/decomp_graph_census-mutate.py
gates/decomp_graph_census-pins.rows
.agents/slop/l2ipool
```

**FALSE.** In `f7a630962`'s message, `decomp_graph_census-pins.rows` appears **once** and `l2ipool`
appears **once**. The other four paths — `.bend`, `-gate.py`, `-oracle.py`, `-mutate.py` — appear
**zero** times each (`grep -cF`). The commit justifies removing the index by asserting the index is
redundant with the message above, and one sixth of it is.

---

## 4. EVERY STALE — 4

All four are true at the commit and false now, and **three of the four are index/tree-shaped** — the
same cause the first audit named for six of its eight.

| commit | claim | measured now |
|---|---|---|
| `6a94279b` | "`ls gates/*.py` = **164**" | **164** at the commit (`git ls-tree`); **165** at 14:36Z; **167** at 14:46Z. HEAD unmoved — the growth is uncommitted files. |
| `b86e3c25` | "`.agents/TODO.md` still carries **five** (`Device.tag`) citations, at 1993, 2053, 14783 … 16183 and 16190" | **six**. The five named lines are all still exact; `e486d3ec` added a sixth at `:16698`. |
| `f65d140a` | "`mixin/rand.bend:85-86` NAMES `$ORACLE_DIR/rd-gate.sh` AND `$ORACLE_DIR/rd-truth.py`" | `:85` is `#        binop here.)`, `:86` is a `TODO(p3)`. `9b1be76b` replaced the recipe 16 minutes later. |
| `0b1edd858` | same citation | same. |

The first two are **drift**, and the drift is measurable to the minute: `gates/*.py` grew by two in
ten minutes under an unmoved HEAD. That is a finding about the tree, not about the author, and I have
classified it as the brief instructs.

---

## 5. WHAT IS CONFIRMED, AND IT IS NOT A TRIVIAL AMOUNT

**138 of 218, 63.3%.** The load-bearing ones, each re-measured:

**The unrunnable-recipe census reproduces almost exactly, from its own committed table.** The
population walk reproduces to the digit: 331 files, and per-root
`tinybendygrad 134 · .agents 112 · gates 60 · oracles 16 · checks 4 · runs 3 · examples 1 · langs 1`.
4192 rows, 11 columns, 136 files carrying a recipe. Port stratum: 2624 rows, 95 files with a recipe,
170 recipe rows. Unrunnable, port: **30 rows / 24 distinct tokens / 17 files**. All strata: **48 rows
/ 27 files**. `RECIPE-PRODUCT` = 40 rows tree-wide. Per-state distinct port tokens: WAS-OURS 19,
UNRESOLVED-ENV 4, NEITHER 1, RECIPE-PRODUCT 1 — and 19+4+1+1 = **25**, which is exactly the "25
distinct paths" the commit reports. So `9145300a0`'s arithmetic is internally consistent; only its
"under `.agents/slop/`" qualifier is wrong.

**`f15c78db`'s headline hash is exact.** `sha256` of the committed table at HEAD is
`929af94897ca48d0e217361f76124bc836892c7ee3bc1615ca3ecbe0adc6b6a6` — the full 64-hex string the
message quotes. Both index builders read `for p in sorted(disk):`. And the *shape* of the repair is
confirmed too: between the pre-fix and post-fix blobs, **100 rows differ and every differing field is
column 9 (`note`)**, each note the same path multiset reordered. The exemplar
`oracles/dtype_oracle.bend:12 ../dtype.bend NEITHER` exists with exactly that three-path note in both
orders.

**`ef63403`'s corrections all hold**, including the one that matters most: `mixin/rand.bend` has
**zero** `UNRESOLVED-ENV` rows, and `rand.bend:97` really does have `$ORACLE_DIR` followed by a
backtick. The instrument is **594 lines** at that commit under `wc -l` (595 records; no trailing
newline). `libclang.bend` carries exactly **335** quoted `*.c` tokens. `AMBIGUOUS-SUFFIX` is
**11**. And `checks/unrunnable-recipes.rows` is byte-identical across `9145300a0` and `ef63403` —
"NO TABLE CHANGE" is literally true at the blob level.

**`d8a9359c` gets all three of its citations exactly right**, and they are the citations the first
audit got wrong: `symbolic.bend:1555` is `def sym_12.put`, `:1558` is `def sym_12.hit`, `:1559` holds
the `H.flatten_u32(...)` call; `:3221` is a markdown table row and `row("sink", t_sink())` is at
`:3292`, **3292 − 3221 = 71**; and `codegen/decomp/dtype.bend:664` holds exactly
`Bool.or(dd_is_bool(xdt), dd_is_uint(xdt))`.

**`6a94279b`'s runner census is right.** Every `gates/` path named by `bin/`, `checks/e2e.sh` and
`checks/differ.py`, deduped, is **three**: `gates/cstyle-live.rows`, `gates/gatekit.py`,
`gates/retention-check.py` — and none is a gate. `gates/README.md`'s header table has exactly **four**
shell-gate failures, and `grep -ic "by hand|manual|run each|no runner|invoked|called by"` returns **0**.

**`b86e3c25`'s mechanical half.** `realize_graph_census-pins.rows` md5 is `ebb4fd66a35a7ea1c5b049d54f1a035b`
— the exact value quoted. `device.bend` is byte-identical (not among its 5 changed files). `optim.bend`
is net +0 (1 insertion, 1 deletion). `ops.bend`'s `awk 'NR>868 && /Device\.tag/' | wc -l` is **0**,
and the whole file now holds **0** occurrences. All three "plausible candidate" lines
(`nl-gate.py:39-40`, `differ.py:188`, `realize_graph_census-gate.py:126`) are prose, exactly as claimed.
`e486d3ec`'s pins citation `:112` is the `name_18` triple, verbatim.

**`9b1be76b` / `ed8c95f6`'s static assertions.** `Gate(rows=55, compared=32)` is at
`rand_census-gate.py:259`. `rand.bend` has exactly **188** `^def` lines. The oracle header at
`9b1be76b^` really did read *"35 ROWS OUT OF THE 51 … THE OTHER SIXTEEN"*, and 35−32 = 3 and 19−16 = 3,
so "wrong by 3 in both numbers" is right. `tensor.py:236` is `def assign`, `:237` rebinds `self.uop`,
`:468/:469/:470` are the write and the two reads, in that order. `rand.bend:95` names the surviving
command, `:120` carries the new GATE STATUS line, and `:675/:678` carry the rewritten `TODO(p3)`.
`9b1be76b` touched exactly **3 files** and none of them is `tinygrad/`.

**`e233811c`'s restatements of the first audit all check out against it**, including `gatekit.py`
where it says `:107` is fixed: `:98` is blank, `:104` and `:107` are the two returns, exact. And
`"7 of 45"` appears **0** times in both `TODO.md` and `TOOLS.md`.

**`f7a630962`'s `dtype.py` citation is the best one in the batch.** `"both are dtype.py:35-38, one arm
at two target widths"` — `tinygrad/codegen/decomp/dtype.py:35-38` is exactly the single
`case Ops.CAST if dt in dtypes.floats:` arm whose `cdt = dt if dt == dtypes.float64 else
dtypes.float32` is the "two target widths". And the gate's own `:217` holds `UNBUILT = ("lgu", "lgz")`
while `:133` repeats the same citation. Line-precise, twice, in two files.

---

## 6. WHAT I COULD NOT CHECK, AND WHY

**54 rows are UNVERIFIABLE, 24.8%** — close to the first audit's 26.7%. They fall into six buckets,
none of which is a guess:

1. **Anything needing `bend`** — the decomp census lanes, `probe65.bend`, the `l2i` build/refuse
   answers, the emitted bundles. ~8 rows. Example: `f7a630962`'s *"all 20 cells REFUSE, none reaches
   `l2i_cast0` or `l2i_cast1`"* and the whole `sel == 1 / 0` reading.
2. **Anything needing a gate to run** — `gates/*.py` are executable and I did not execute any. ~28
   rows. Examples: `f65d140a`'s *"`nn/onnx` 167 ROWS, `nn/state` 85, `mixin/rand` 51 — ALL rc=0"*;
   `f7a630962`'s *"42 → 43 ROWS, 26 EXACT … rc=0"* and the whole A1–A14 mutation table;
   `b86e3c25`'s *"1004 rows, 941 match + 63 declared / 9 classes … 14.72 s … 1.31 GiB"*.
3. **Anything needing RSS** — `checks/bounded.py` is banned. ~3 rows: the three-message RSS spreads in
   `f7a630962` and `037d5d53`, and `9b1be76b`'s `1104.9 / 1159.3 / 1002.7 MB`.
4. **Anything needing a full-history walk** — `git log --all --name-only` over ~81k paths, which the
   author himself reports hitting a 120 s timeout. ~5 rows. `9145300a0`'s `81533` / `52766` pair and
   its "wrong for 20 of them" self-correction are unverifiable *because the author says his own
   instrument for them failed*. I did not reproduce the failure or paper over it.
5. **Anything whose instrument the message does not name** — the honest bucket. `e233811c`'s whole
   `onespelling` paragraph (307 sites, 100,951 literals, 254/27/26, the 728-vs-3510 anchor) names no
   path. `f7a630962`'s "cause 13 of 13 in the report" and `f65d140a`'s `C-BOOL (35/21/21)`.
6. **A denominator I could reproduce the numerator of but not the rule.** `9b1be76b`'s **87
   "whole-file declarations"** — `rand.bend` has 188 `^def` lines (CONFIRMED) and a loose top-level
   regex gives 201, so 87 is reachable under a rule I was not given and did not guess. Same for
   `d8a9359c`'s *"the TODO row ALREADY SAID 22 ARMS"*: the literal `22 ARMS` appears **0** times in
   `.agents/TODO.md` and I did not find the row being described, so I did not rule it false either.

**Two I deliberately declined to call.** `ef63403`'s *"32 rows in 18 files was the count ~40 minutes
ago"* — a self-description of a moving number whose earlier value is not recoverable from any
committed artifact. And `0b1edd858`'s *"the remaining 20-insert/1-change diff is theirs and stays
uncommitted"* — a statement about a working tree that has moved seven commits since.

---

## 7. THE RATE, COMPARED TO THE FIRST AUDIT — AND WHAT I THINK IT MEANS

**This batch: 22 FALSE of 218 = 10.1%.** First audit: 10 FALSE of 165 = **6.1%.**
**This batch's FALSE rate is roughly 1.7× the first's.** On a share-of-total basis: 10.1% vs 6.1%.

I do not think this means the author got worse. Three reasons, and one caveat.

**Reason 1 — the sample is different in kind, not in quality.** The first audit's 24 commits were
mostly *correction* commits (`INDEXREAD2`, `DEVTAG`, `UPLATTICE`, `CRP-COUPLE`, `SYMDRV-CORRECT`):
their job was to re-measure and re-state. This batch's 16 are mostly **census-instrument** commits —
`unrunnable-recipes`, `decomp_graph_census`, `rand_census`, `onnx/state/rand` censuses. A census
commit makes dozens of *enumerable* claims (counts, denominators, per-state breakdowns, file:line
citations into a data file), so the denominator of checkable claims per commit is far larger: **13.6
claims per commit here vs 6.9 before**. A higher hit count at a higher claim density is not the same
signal as a lower standard.

**Reason 2 — the same mechanisms, already named inside this range.** The first audit's §7 said the
pattern across all ten FALSE was *"a citation into a file the same session is editing is quoted with
the line number the edit produced, not the line number the quoted text is at"*. That sentence is
**still true of my findings** (§3.1, four rows) — and by the first audit's own account
`2fb32340f` had already written the rule down, in prose, in the message it audited. What I can add is
a **mechanism the first audit did not name**, and it is the one that produced the most damage:

> **A commit that publishes a census carries its own counterexample in the census.**
> `f7a630962` adds the `lgz` row, and then — in the same message, twice, and again 60 seconds later in
> the next unit's message — concludes that no such row reaches `l2i`. The finding did not need a
> citation, a denominator, or a second reading. It needed one `grep` against the file the commit had
> just written. **This is `6eb1ec151`'s "A FOOTER THAT EXPLAINS A ROW IS A CLAIM, AND THE ROWS ARE THE
> WITNESSES" (§3.2 of that message) applied to the message that wrote the row** — and the row was
> right there.

**Reason 3 — the self-audit machinery is real and it is finding things, in both directions.** `d8a9359c`
re-verified three of its own FALSE citations against the tree **before** re-numbering anything, and
got all three exactly right, including the 71-line offset it inherited from the first audit. `ef63403`
exists solely to retract two stale rows and to record that its own count is a moving number.
`e233811c` volunteered four of its own FALSE. `f15c78db` found that its own instrument was not
byte-reproducible and fixed it before anyone looked. **That is not what a session with a 10% false rate
looks like.** It is what a session that has learned to audit itself looks like, and the audits are
working: two of my four STALEs are the decay the author explicitly predicts.

**The caveat, and it is the honest one.** Three of my 22 FALSE are *counts* (skip-dirs 8-vs-6, 19
under `.slop/`, 15-of-22) and four are *line numbers in an edited file* — mechanical classes that a
single pre-commit grep would catch. **The two most expensive findings (§3.2 and §3.5) are both claims
that the tree, or the commit's own new file, contradicts outright.** Neither is arithmetic and neither
is a shifting line number. A pre-commit check of *counts against their own source* and of *claims about
what a commit names* would have caught 7 of the 22 with no analysis at all.

---

## 8. REPRODUCING THIS

```
git rev-parse HEAD                                            # 03500a26202aa8560adbab980f705ad9c0a7cbfb
git rev-list --count 1b4905cba9903b125c172ee6bdb2b3db48ac436a..HEAD   # 16
awk -F'\t' 'NR>1{c[$3]++} END{for(k in c) print k,c[k]}' .agents/slop/claimaudit2/claims.rows
awk -F'\t' 'NR>1 && $3=="FALSE"'  .agents/slop/claimaudit2/claims.rows
awk -F'\t' 'NR>1 && $3=="STALE"'  .agents/slop/claimaudit2/claims.rows
awk -F'\t' '{print NF}' .agents/slop/claimaudit2/claims.rows | sort -u   # 4
```

`claims.rows` has **218 data rows**, every one exactly 4 tab-separated fields, covering **16 distinct
commits**. The four verdict counts in §2 are `awk`ed from that file and sum to 218. The commit set in
`claims.rows` was `diff`ed against `git log 1b4905cba..HEAD` and matches exactly — no missing commit,
no invented one.