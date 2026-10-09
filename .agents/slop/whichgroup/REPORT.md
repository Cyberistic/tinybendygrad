# whichgroup — WHICH SIDE IS RIGHT ABOUT `flip`'s MISSING GROUP?

**UNIT:** `whichgroup` · **DATE:** 2026-10-09 (measurements 16:11Z–19:34+03) · **VERDICT: `PASS` (exit 0)**
**THE SHORT ANSWER: THE BEND FIXTURE IS WRONG. `graphcmp.bend:1355` FABRICATED A `GROUP` NODE
THAT UPSTREAM'S OWN CONSTRUCTOR NEVER BUILDS. THE PORT IS CORRECT AND WAS NOT TOUCHED.**
CORPUS: **33/34 → 34/34 BYTE-IDENTICAL**, 0 walls, population = `len(graphcmp.GRAPHS)` = **34**.

---

## 0. WHERE MY OWN MEASUREMENT WAS WRONG, AND THE BEFORE-VALUES

**Four errors, all mine, all before the verdict. The first two changed what I would have
concluded; the last two would have left a broken instrument behind in my own directory.**

**(a) I WOULD HAVE REPORTED A CORPUS STATE THAT IS NOT THE TREE'S.** I byte-diffed
`checks/rows-<graph>-<side>.rows` — 69 files, stable — and read **`BYTE-IDENTICAL: 20, differ: 48`
of 34 graphs**. That is not this tree. That cache is `checks/census.py:64`'s own, it predates
commit `73644b9c1`, and its `rows-flip-bend.rows` still carries the FLIP arg as **`n(i1,i0)`**, the
PRE-`ABoolList` rendering, while its `rows-allred-bend.rows` holds a 13-node graph against the py
side's 4. **The 33/34 I was briefed with is a generation too — and the OTHER one.** Two artifact
sets disagreed by a factor of five and I had to establish which was current before any of this
unit's work was worth anything.

**(b) THE POPULATION I WAS HANDED HAD NO STABLE DENOMINATOR.** `checks/rows/` read **68** files at
`2026-10-09T16:11Z`, then **58**, then **46**, then **40**, at 2 s intervals — *another unit is
deleting it while this one reads it.* A count over a directory someone else is emptying is a count
with a moving denominator, and the brief's "34 graphs × 2 lanes = 68" was a reading of a directory
that no longer held 68 files when I began. I snapshotted it (`.agents/slop/whichgroup/snap/`, 69
files) rather than re-reading it, and I re-took the count from the generator instead.

**(c) MY FIRST SRC-COUNT PROBE READ 0 SRCS FOR FOUR OF TWELVE `OpsGROUP` STATEMENTS — WRONG IN THE
DIRECTION THAT HIDES A FINDING.** It counted `O.Found.i(` only on the line carrying `OpsGROUP{}`.
Four statements **wrap onto a second line**. So `:822`, `:1232`, `:1253`, `:1319` all read `0` —
which would have made five of twelve look like single-src defects and pointed the fix at four
graphs that are correct. Corrected to read each statement until brackets **balance**: the true
count is **11 of 12 carry 2–8 srcs; exactly ONE carries 1.**

**(d) THAT SAME PROBE CRASHED** — `IndexError: list index out of range` — because it tracked
bracket depth as a *running delta over a concatenated statement*, which double-counts, and walked
off the end of the file. A probe that dies has measured nothing.

*(Minor, recorded because it is the same shape: my first attempt to read the rows used `cat -A`,
a GNU flag BSD `cat` rejects — `rc≠0`, `usage: cat [-belnstuv]`. And my first heredoc raced its own
`mkdir` because I issued the two tool calls in parallel.)*

**AND ONE CORRECTION TO THE BRIEF ITSELF, WHICH MATTERED:** the brief says the GROUP is hand-built
at `:791`, `:822`, `:910`. **Those three are `g_group`, `g_commute` and `g_sym` — every one of them
multi-src and every one of them correct. `flip`'s GROUP is at `:1355`.** A reader who followed the
brief's line numbers would have edited a graph that was never wrong.

---

## 1. IS `graphcmp.bend` A HARNESS OR THE PORT? — **A HARNESS. IT IS A FIXTURE.**

**The header says so at `.agents/slop/graphcmp.bend:19-21`** — *"IT IS A HARNESS, not a port. It
READS `tinybendygrad/uop/ops.bend` and `tinybendygrad/uop/fold.bend` and PRINTS. It adds nothing to
either and edits neither."* — **and I checked it rather than believing it**, because that is a
claim about the thing under test:

| test | reading |
|---|---|
| path | `.agents/slop/` — **outside** the port tree |
| every `tinybendygrad` mention (9) | an `import` path; `:33-37` |
| file-writing calls | **none** — no `write`, no `open(`, no `File.` |
| `O.UOp.new`/`O.UOp.const` sites | **349**, all in-memory arena construction |

**SO: EDITING IT IS A FIXTURE EDIT, NOT A PORT EDIT.** And this is corroborated by the tree's own
history — commit `73644b9c1` states it of this very graph: *"`graphcmp.bend` **BUILDS THE FLIP UOp BY
HAND** … **IT NEVER CALLS THE PORT's FLIP PATH**, WHICH IS WHY REPPOINTING ALL **FOUR** PORT
CONSTRUCTORS **COULD NOT** MOVE THIS ROW."* **The sibling unit's report was right, and its scope
was not.**

## 2. WHAT DOES THE `GROUP` AT `:1355` WRAP, AND WHY?

It wraps the **FLIP**, alone. `graphcmp.bend:1355` built `[FLIP]` → a GROUP over one src.

**Why it is there: it was inherited, and the inheritance is the defect.** `graphcmp.bend:1342-1347`
records that `flip` was **split out of `move`**: *"SO IT IS ITS OWN GRAPH AND NOT A FIFTH MEMBER OF
`move`. … `move`'s GROUP would have been reported as an unexplained one-sided node."* In `move`,
`UOp.group` has **four** srcs and upstream genuinely builds a GROUP. **The wrapper came across with
the split and did not survive the split's semantics — because a one-src `UOp.group` is not a GROUP
at all.** The docstring's own census said so and contradicted itself in the same two lines:
*"`ALLOC=1 CONST=2 FLIP=1 `**`GROUP=1`** `RESHAPE=1 STACK=1`"* sums to **7**, on a line headed
*"MEASURED at **6** nodes"*.

## 3. DOES CPYTHON'S `a.flip(0)` PRODUCE A GROUP? — **NO. AND THE BETTER QUESTION IS `UOp.group`.**

**Neither side prints `a.flip(0)`.** `graphcmp.py:1386` prints `UOp.group(a.flip(0).uop)`. So the
question that decides this is not about `flip` at all — it is about **`UOp.group` of ONE src**.

**FROM UPSTREAM SOURCE IN THIS TREE — `tinygrad/uop/ops.py:558-560`:**

```
558:  def group(*srcs:UOp|None, **kwargs):  # pylint: disable=no-self-argument
559:    if len(srcs) == 1 and isinstance(srcs[0], UOp): return srcs[0]
560:    return UOp(Ops.GROUP, src=tuple([x for x in srcs if x is not None]), **kwargs)
```

**`:559` IS AN IDENTITY SHORT-CIRCUIT. ONE SRC RETURNS THE SRC. NO NODE IS BUILT.**

**MEASURED, calling CPython (`.venv/bin/python`, `probe_group.py`, Q1–Q3):**

```
Q2  UOp.group(a.flip(0).uop) is the FLIP itself?  = True
    g.op = Ops.FLIP   |   Ops.GROUP node created? = False
Q3  G.emit_py('flip', None) -> 6 rows
    op census = {ALLOC:1, CONST:2, FLIP:1, RESHAPE:1, STACK:1}      GROUP rows = NONE
```

**SO THE PYTHON LANE'S 6 ROWS ARE CORRECT, AND THE PORT IS NOT MISSING ANYTHING.**
The bend lane's 7th row was not a port defect and never was.

**THE DECISIVE SHAPE — `probe_srccount.py`, all 12 `OpsGROUP` statements in `graphcmp.bend`:**

| line | graph | srcs | upstream builds a GROUP? |
|---|---|---:|---|
| 791 / 910 / 1173 / 1274 / 1410 / 1494 | group, sym, bw, where, threefry, cdiv | 2 | yes |
| 822 / 1232 | commute, alu | 6, 8 | yes |
| 1253 / 1319 / 1514 | bit, move, late | 4 | yes |
| **1355** | **flip** | **1** | **NO — identity** |

**11 of 12 hand-built GROUPs are nodes upstream builds. The single divergence in 34 graphs × 2
lanes is exactly the one place where the fixture models a call its own oracle collapses.**

## 4. VERDICT, THEN THE CHANGE

> ### `PASS` — **FIXTURE CORRECTION.** `.agents/slop/graphcmp.bend:1355` removed; the port untouched.

**WHICH QUESTION THIS IS — and it is NOT the route already refused.** That refusal was about
**forcing agreement** by repointing the port's four FLIP constructors so a hand-built `ATuple`
would *say what the oracle says* — editing the thing under test to match the ruler. **This is the
opposite, and the distinction is the whole answer:** here the oracle's **own source** says it never
builds the node, the **port is not edited at all**, and the evidence is `tinygrad/uop/ops.py:559` —
a line with nothing to do with the port. **Removing a node the oracle does not have is not making
the comparison agree; it is making the fixture stop asserting something false.** I did not edit
`tinybendygrad/`, `checks/`, or `gates/`.

**THE CHANGE — one statement, plus its census line:**

```
-  +fl = O.UOp.new(O.Found.ar(r43), O.OpsFLIP{}, [...], O.ABoolList{[True{}, False{}]}, O.TNone{})
-  O.UOp.new(O.Found.ar(fl), O.OpsGROUP{}, [O.Found.i(fl)], O.ANone{}, O.TNone{})
+  O.UOp.new(O.Found.ar(r43), O.OpsFLIP{}, [...], O.ABoolList{[True{}, False{}]}, O.TNone{})
```

**MEASURED BEFORE AND AFTER — same command, same guard, same session:**

| | bend rows | verdict token | peak RSS |
|---|---:|---|---:|
| BEFORE | **7** | `WITHIN-LIMITS` | 675 MB |
| AFTER | **6** | `WITHIN-LIMITS` | 645 MB |

`flip` py **6** vs bend **6**, **`cmp` byte-identical**. The FLIP row is **untouched** at `n(b1,b0)`.
`group` and `move` re-run after the edit: `WITHIN-LIMITS` — the edit broke nothing.

**THE INSTRUMENT WAS PROVEN TO MOVE, NOT ASSUMED TO.** I re-ran the same corpus census with the one
statement reverted, and restored by `cp` + sha256 (verified byte-identical, both
`2e180103…f065`):

| | graphs with both lanes | BYTE-IDENTICAL | differ |
|---|---:|---:|---|
| wrapper present | 34 of 34 | **33** | **1** → `['flip']` |
| wrapper removed | 34 of 34 | **34** | **0** |

## 5. VERIFICATION

```
checks/no-txt.py          rc=0   CLEAN: no .txt outside the two named exceptions
checks/nl-gate.py         rc=0   gated 205  agree 205  disagree []  AGREE
gates/gate-surface.py     rc=0   II SHELL HALF: 18 entry point(s)
corpus (fresh, this unit) 34 of 34 BYTE-IDENTICAL, differ 0, WALLS []
```

**THE BRIEF'S `33/34 → "still reads 33 identical of 34"` DOES NOT APPLY: I CHANGED THE FIXTURE, so
the new count is given above — 34 of 34.** Denominator and scope, in the same sentence as every
number: **34 of 34 graphs in `len(graphcmp.GRAPHS)` byte-identical between CPython and the Bend lane,
each lane emitted by its own process through `checks/bounded.py`, 0 walls.** All 68 lane-runs
returned a real verdict token; none was `SKIP` or `DEAD`. Memory: every `emit_bend` is a separate
`bend` process run **strictly sequentially** (in-flight RSS measured at 0 MB before the census),
peaks 645–680 MB against a 16 GB machine — so the sum precondition was never in question.
`graphcmp.bend` is **not** in `.agents/slop/peakrss/census.rows` (that census is over 138
`tinybendygrad/**` files); its imports measure `fold.bend` 484 MB and `ops.bend` 345 MB.

---

## 6. FOR OTHER UNITS — NOT MINE TO FIX

1. **`graphcmp.py:1357` carries the SAME stale census and I am forbidden to touch that file:**
   `"""`UOp.group(a.flip(0))` -- MEASURED at 6 nodes, census `ALLOC=1 CONST=2 FLIP=1
   `**`GROUP=1`** `RESHAPE=1 STACK=1`"""` — 7 categories on a line headed "6 nodes", naming a GROUP
   `ops.py:559` never builds. **`graphcmp.bend` now says `ALLOC=1 CONST=2 FLIP=1 RESHAPE=1
   STACK=1`; the two sides of one pair now disagree about what the census is.**
2. **`checks/census.py:64` reads a cache that is stale, and will keep reporting the old tree.**
   All **68 of 68** of its `checks/rows-<graph>-<side>.rows` slots hit (measured against
   `len(graphcmp.GRAPHS)` = 34), so a run today returns `CACHE` for every graph and reports the
   **pre-`ABoolList`** state. It never reads `checks/rows/` — that is a *published copy under a
   different name*, so the one artifact set a reader looks at is one the generator cannot see.
3. **`checks/rows/` was being deleted during this unit** (68 → 58 → 46 → 40). A fresh, correct
   68-row set is at `.agents/slop/whichgroup/rows/` if anything wants one.

## 7. ARTIFACTS (all under `.agents/slop/whichgroup/`)

`REPORT.md` · `probe_group.py` (upstream `UOp.group` + `emit_py`) · `probe_srccount.py`
(the 12 `OpsGROUP` src counts) · `corpus_fresh.py` (the 34-graph re-take) · `rows/` (68 fresh
lane files) · `snap/` (the 69 files as found) · `before-bend.{out,err}` ·
`after-bend.{out,err}` · `after-py.{out,err}` · `graphcmp.bend.FIXED` (sha `2e180103…`) ·
`no-txt.out` · `nl-gate.out` · `gate-surface.out`

**NOTHING COMMITTED. NOTHING STAGED BY ME.** I never ran `git add`.

**A READER MUST KNOW THIS, OR THEY WILL MISREAD THE INDEX:** `git diff --cached --stat` on this
tree reports **52 files staged** — `.agents/slop/META-VERDICT.md`, `.agents/slop/whatisagate/
REPORT.md`, `checks/*`, and so on. **None of them are mine.** MEASURED: `git diff --cached
--name-only | grep -E 'whichgroup|graphcmp\.bend'` returns **rc=1**, i.e. zero of my paths appear.
**That is colocated `jj` arming git's shared index** — the failure mode the brief names, where the
index is another unit's, so `git diff --cached` reporting a non-zero count here is a fact about
the workspace and not about this unit. Verified against `ls-tree`, not the index:
`.agents/slop/graphcmp.bend` is in `ls-tree` **1** and in the index **1** — same tracked blob, and
my edit is an unstaged working-copy change on top of it.

Likewise `git ls-files -m` under `tinybendygrad/ checks/ gates/` shows only other units'
concurrent work — 356 files, all under `gates/artifacts/`, which is where gate *output* lands and
which I never wrote to. **My writes are confined to `.agents/slop/whichgroup/` and to
`.agents/slop/graphcmp.bend`.**