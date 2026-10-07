# ONE POPULATION, SIX PROJECTIONS — AND ONE REAL DEFECT

`.agents/slop/onemodule/`, 2026-10-07T03:55–04:02Z. `git rev-parse --short HEAD` = `f7be40994`.
Committed nothing, ran no `git add`, started no `bend`. Owned and touched only this directory —
`checks/`, `gates/`, `AGENTS.md` and `tinybendygrad/` are unmodified by me. Instruments:
`probe.py` (all six re-measured in ONE process at ONE timestamp), `plant.py` (both plants),
`vocab-check.py` (the verdict-vocabulary census, `rc=1` RED at rest).
Artifacts: `probe.rows` (the per-file membership of all four file-set projections),
`plant.out` (both plants' deltas), `vocab.rows` (the vocabulary census).

**HEADLINE. THE SIX NUMBERS ARE NOT SIX OPINIONS. Five of them are ONE population asked five
ways and four are the same population under a different `walk` flag; the sixth (`pairs`) is a
different question entirely and `prune4`'s is a third. NO TWO OF THE SIX ARE CONTRADICTORY.
What the tree looks like is six opinions; what it is, measured, is one population with a
recursive-or-not flag on it and two instruments asking questions that are not about gates.**

**AND THE PLANT FINDS ONE REAL DEFECT, AND IT IS NOT A HAND LIST.** Dropping one new gate into a
scratch copy moves all five gate-counting projections by exactly +1 — including the two that were
reported as disagreeing by 2 — with **no list edited**. Dropping the same gate one directory
DEEP moves only the recursive ones: **`discover()` does not move at all.** That is the finding.
`discover()` is not wrong; it is correct about a **flat** tree, and it is blind to
`gates/oracles/` for the same reason it is blind to `checks/gen/`.

---

## 0. WHAT CANNOT BE UNIFIED — STATED FIRST, AS ASKED

**Two of the six must not be merged with the other four, and merging them would be the second
copy in a new coat.** Names first, so the rest of this report can be short:

| instrument | population | merge with the gate census? |
|---|---|---|
| **`pairs`** `.agents/slop/pairs/census.py` | **string-lists shared by ≥2 `.py` files in the WHOLE TREE** | **NO — different question.** It asks *which facts are stated twice*. A gates-only census would answer "which gates exist", which is not what it is for, and `pairs`' own instrument says the scope out loud. Its 126 vs 5 gap against `coindependent` is **scope, not disagreement**: `coindependent` is scoped to `checks/`+`gates/`, `pairs` is not. |
| **`prune4`** `.agents/slop/prune4/census.py` | **directory disk usage + git tracked/untracked status under `.agents/slop/`** | **NO — not about gates at all.** It asks *what occupies space*. It appeared in this brief only because its `git ls-files` reader is the trap; §6. |

**The remaining four — `discover()`, `gate-surface`, `coindependent/vocab.py`, `zerogate/derive.py`
— ARE ONE POPULATION, and they are already one module.** `gate-surface` and `hooks` *call*
`discover()`; `zerogate` *calls* `vocab.scan()`. Measured:

```
zerogate/derive.py:56   return [r for r in vocab.scan() if ...]      <- COWORKER'S GENERATOR
gate-surface.py:105     return gates_pop().discover(root)             <- SHARED POPULATION
```

**So "six instruments hold six lists" is FALSE, and it was false before this report: four of them
hold two generators, by path, and were constructed that way on purpose.** The brief's framing —
*"this is `gendirs.py`'s fault, six times over"* — is the one part of it the measurement refuses.
`gendirs.py` is not being ignored; it is being *obeyed*, and the obedience is measurable.

---

## 1. THE SIX NUMBERS, RE-MEASURED AT ONE INSTANT — AND WHICH ARE THE SAME POPULATION

`probe.py` loads each instrument by path and runs all six in one process, because the six figures
in the brief were taken at six different times on a tree four units were writing to, and **a
SCOPE difference and a MOVEMENT difference are indistinguishable across six timestamps.** One
timestamp:

```
projection                          files  entries  scope
discover() [gates-pop]                145      119  iterdir over ('checks','gates') ('.py','.sh')
gate-surface                          145      119  discover() + os.walk CONTROL=147
coindependent/vocab.py                147      121  os.walk RECURSIVE over ('checks','gates')
zerogate/derive.py                         -      121  re-asks vocab.scan()
pairs/census.py                    126 lists      -  WHOLE TREE string-lists: 126 walk / 109 tracked
prune4/census.py                         -        -  git ls-files: agent-index=1579 default=1553
```

### THE ANSWER TO QUESTION 1, AS A TABLE OF PAIRS

| pair | same population? | verdict |
|---|---|---|
| `discover()` ↔ `gate-surface` | **IDENTICAL — provably** | `probe.py` asserts `discover() == gate-surface: True` on the file SETS, not the counts. They cannot disagree: one calls the other. **The 114-vs-114 agreement the brief reports is not an agreement, it is a tautology** — which is what `gendirs.py` was for, working. |
| `discover()` ↔ `coindependent/vocab.py` | **SAME population, DIFFERENT `walk` flag** | 145 vs 147 files. **The whole difference is 2 files**, and the set decomposition names them (§2). |
| `discover()` ↔ `zerogate/derive.py` | **NOT a pair at all** | `zerogate` *is* `vocab.scan()`. Same 121. It is a consumer of a generator, not a second witness. |
| `discover()` ↔ `surface`'s `walk_control` | **SAME population, one labelled CONTROL** | `gate-surface.py:108` walks recursively **and prints the number beside the population precisely so the difference is visible rather than dissolved.** It is a deliberate second opinion *inside* one instrument, which is the opposite of a second list. |
| `discover()` ↔ `pairs` | **DIFFERENT QUESTION** | gate entry points vs shared string-lists, whole-tree. `pairs`' own output says *"both are correct for their scope and the number is meaningless without it"* — **that sentence is the correct reconciliation and it is already written down.** |
| any ↔ `prune4` | **DIFFERENT QUESTION** | git state, not gates. §6. |

**THE CONTRADICTION FINDING IS: THERE IS NONE.** Say it plainly, because the honest answer is the
deliverable. **The tree does not have six opinions about how many gates it has. It has ONE
population, asked by four instruments that share two generators, plus two instruments that are
answering other questions.** The "113 / 114 / 115 / 111 / 5" spread in the brief is:

```
  119  discover(), gate-surface      one module, one function, called twice
  121  coindependent, zerogate       one module, one function, called twice
  ----  the 2 between them are a RECURSION FLAG, not an opinion          (see below)
  126  pairs                         a different question (shared string-lists, whole tree)
  ---  prune4                        a different question (git state)
```

**So the fix is NOT consolidation — it is LABELING.** Every one of these six numbers is correct
for a scope, and the scope is printed by four of the six instruments and written down by `pairs`
and by `gate-surface.py:108`'s own docstring. **A number without its scope is a number nobody can
reconcile, and `pairs` named that exact defect first.**

---

## 2. THE SHARED POPULATION, DESCRIBED BY DISCOVERY — AND WHAT IT CANNOT SEE

**The population is `gates/gates-pop.py:discover()`.** Not because it is the oldest or the
biggest, but because **two of the six instruments already call it**, and because it is the only
one whose *membership predicate* is a rule rather than a walk:

```python
gates/gates-pop.py:311  def discover(root):
gates/gates-pop.py:320      for home in HOMES:          # <- a 2-tuple. THE LIST THAT REMAINS
gates/gates-pop.py:324          for p in sorted(h.iterdir()):     # <- NOT rglob. NOT os.walk
gates/gates-pop.py:327              (entries if entry_reason(p) in ("py-main","sh-dispatch","sh-selfref")
```

**`iterdir()` IS THE WHOLE FINDING, AND IT IS MEASURED BOTH WAYS.** From `probe.py`:

```
discover() vs walk_control : |D-S|=0 only-discover, |W-S|=2 only-walk
    ONLY-WALK      gates/oracles/beautiful-mnist-oracle.sh
    ONLY-WALK      gates/oracles/mixin-op-oracle.sh
discover() vs coindependent walk: |D-C|=0 only-discover, |C-D|=2 only-walk
    ONLY-WALKCI    gates/oracles/beautiful-mnist-oracle.sh
    ONLY-WALKCI    gates/oracles/mixin-op-oracle.sh
```

**`|D-S| = 0` IN BOTH ROWS IS THE MORE INTERESTING HALF, AND IT IS THE ONE NOBODY QUOTED:**
`discover()` sees NOTHING the recursive walks miss. It is a strict SUBSET — so it cannot be
"wrong about a file that exists", it can only be silent about one. **Both comparisons name the
SAME TWO FILES. The "113 vs 114" and the "111 vs 113" and the "5 vs 111" gaps are not three
disagreements; they are one `iterdir()` read three times.**

And the two are not marginal. `gates/oracles/beautiful-mnist-oracle.sh` is a **three-lane gate
that runs CPython and both `bend` lanes and diffs them** — one of the oldest gates in the tree,
and `gates-oracles/` is invisible to the population every runner would walk. Measured
`entry_reason` on both: `{'sh-selfref': 2}` — **they are ENTRY POINTS by `discover()`'s own rule.
They are not libs, not fixtures, not dead weight. They are gates that the census cannot see.**

**A SHARED POPULATION THAT IS BLIND TO A SUBDIRECTORY IS NOT A POPULATION — IT IS A LIST WITH A
RECURSIVE OPTION.** And the blind spot is not the 2 files, it is `HOMES = ("checks", "gates")`:
a **third gate home requires editing line 95**, which `gates-pop.py:90-94` admits in the clearest
words in the tree (*"this is the one universe this file names by hand, and clause I says so out
loud rather than pretending discovery reaches the whole repo"*). **`checks/gen/` — written by
`checks/abi_gate.py:616` through `bend -o`, invisible to both instruments — is the same defect
one level down, and `gates/gendirs.py` was built precisely to close it for OUTPUT while leaving
it wide open for GATES.**

---

## 3. DOES THE NEW GATE APPEAR IN EVERY PROJECTION? — THE PLANT, AND IT IS THE WHOLE TASK

`plant.py`. A scratch copy (`shutil.copytree(..., symlinks=True)`, because `bin/bend` is a
symlink and `discover()`'s own docstring says an existence test that follows symlinks certifies
a link target as a tree file), `git init` + one commit, then two plants. Full output: `plant.out`.

### PLANT 1 — `gates/zz-plant-probe.py`, at the TOP LEVEL of a gate home

```
discover         entries=119, files=145, in_plant=False  ->  entries=120, files=146, in_plant=True   YES
surface          entries=119, files=145, in_plant=False  ->  entries=120, files=146, in_plant=True   YES
coindependent    entries=121, files=147, in_plant=False  ->  entries=122, files=148, in_plant=True   YES
zerogate         entries=121, in_plant=False             ->  entries=122, in_plant=True              YES
```

**EVERY PROJECTION THAT ANSWERS "IS THIS A GATE" MOVES BY EXACTLY +1, AND NO LIST WAS EDITED.**
**The property `gendirs.py` was built for — *"a change to it moves both"* — HOLDS, and it holds
for all four gate projections.** **This is the answer to the brief's central worry, and it is the
opposite of the worry:** a shared population that required six lists to be updated when a gate
landed would be six copies with one name, and **measured, it requires none.**

### PLANT 2 — `gates/oracles/zz-plant-deep.sh`, ONE DIRECTORY DEEP

```
discover         entries=119, files=145  ->  entries=119, files=145, in_plant=False   ** DID NOT MOVE **
surface          entries=119, walk=147    ->  entries=119, walk=148                   (control moved only)
coindependent    entries=121, files=147  ->  entries=122, files=148, in_plant=True    MOVED
zerogate         entries=121             ->  entries=122, in_plant=True               MOVED
```

**`discover()` IS THE ONLY PROJECTION THAT DOES NOT MOVE, AND IT IS THE ONE THE OTHER THREE
CALL.** **A SHARED POPULATION THAT IS BLIND TO A SUBDIRECTORY IS NOT A POPULATION, IT IS A LIST
WITH A RECURSIVE OPTION.** `gate-surface` here is the interesting case and the instrument is
**HONEST ABOUT IT**: its population (`entries`, `files`) did not move; only its labelled `walk`
CONTROL did, and `gate-surface.py:108` says in its own docstring that the control *"is never used
to decide membership; two instruments holding two lists have no authority over each other, and
this is the SECOND one deliberately, so the difference is visible."* **That is the correct shape
and it is already in the code.** The defect is not `gate-surface`'s; it is `discover()`'s.

---

## 4. WHO OWNS WHAT — THE VERDICT VOCABULARY IS **NOT** THE SAME SUBJECT AS THE POPULATION

The brief asks whether three owners is right or whether the vocabulary and the declaration have
been split. **Measured: they are three subjects, the split is correct, and the third owner is
the one that has drifted.**

| owner | subject | correct? |
|---|---|---|
| `gates/gates-pop.py:discover()` | **the population** (which files are gates) | yes, with the `iterdir()` hole |
| `gates/gatekit.py:60-61` | **the verdict vocabulary** (`PASS,FAIL,REFUSED,SKIP,DEAD = 0,1,3,4,5`) | yes |
| `gates/gate-surface.py` | **the declaration mechanism** (how a gate states its verdicts, and how they are planted) | yes |

**A MODULE THAT OWNS A POPULATION AND ANOTHER THAT OWNS THE VOCABULARY OF JUDGING IT ARE
DIFFERENT JOBS, AND COLLAPSING THEM BECAUSE THEY ARE BOTH "GATE INFRASTRUCTURE" IS THE FAILURE
THIS PROJECT KEEPS MAKING ONE LEVEL UP.** `discover()` answers *what exists*; `gatekit` answers
*what a verdict means*; `gate-surface` answers *how a gate declares and how that claim is tested*.
Merging them would put the population and its judging vocabulary in one file, and then a change to
the walk would move the vocabulary — **exactly the "a change to it moves both" property, which is
the POINT when there is one fact, and the BUG when there are two.**

### 4a. AND MEASURED: THE VOCABULARY HAS **FOUR** SPELLINGS, IN AGREEMENT

The brief assumes one owner. **There are four copies of the five exits, and none of them reads
`gatekit`:**

| file | the constant |
|---|---|
| `gates/gatekit.py:60` | `PASS, FAIL, REFUSED, SKIP, DEAD = (0, 1, 3, 4, 5)` — **the owner** |
| `gates/git-massdelete-gate.py` | `PASS, FAIL, REFUSED, SKIP, DEAD = (0, 1, 3, 4, 5)` |
| `checks/git-index-guard.py` | `PASS, FAIL, REFUSED, DEAD = (0, 1, 3, 5)` — **four, no `SKIP`** |
| `checks/substrate-id.py` | `PASS, FAIL, REFUSED, DEAD = (0, 1, 3, 5)` — **four, no `SKIP`** |
| `.agents/slop/coindependent/vocab.py:17` | `EXITWORDS = {"PASS":0,"FAIL":1,"REFUSED":3,"SKIP":4,"DEAD":5}` — the same five, re-spelled |

`gatekit.VERDICT == {int(c): t for t, c in vocab.EXITWORDS.items()}` → **`True` today.** They
agree. **They also agree by hand, four times, with nothing comparing them** — which is precisely
the shape `checks/coindep.py` was built to close for the ABI fence, applied here to the verdict
vocabulary. `checks/coindep.py`'s own docstring names the criterion: *"agreement-by-two-copies is
a rubber stamp: a shared OMISSION is invisible to both."* **A sixth verdict would be invisible to
all four.** Two of them have already silently dropped `SKIP` — and `AGENTS.md` doctrine 2 says
`SKIP` **is one of the five**, and `SKIP IS NOT PASS`.

### 4b. AND MEASURED: A **SIXTH EXIT CODE** — THE REAL DEFECT IN THE VOCABULARY

**`gates/gate-surface.py` refuses with `2`, and `gatekit` spells `REFUSED` as `3`.**

```
gates/gate-surface.py:131  """exit 2 = REFUSED, and NOT a verdict. `checks/abi_gate.py`'s rule..."""
```
```
MEASURED, on a scratch copy with `tinybendygrad/` removed:
  == REFUSED, NOT A VERDICT: the repo root is not here: tinybendygrad is absent
  RC=2
```
**`2` IS NOT IN THE FIVE-VERDICT VOCABULARY AT ALL — AND IT IS NOT ONE GATE. `vocab-check.py`
finds FIVE gates declaring exit `2`, and `gate-surface.py` is only the loudest of them:**

```
outside-the-five checks/dup-gate.py                           [2]
outside-the-five checks/env-precond.py                        [2]
outside-the-five checks/wallcheck.py                          [2]
outside-the-five gates/.ab-a.py                               [2]
outside-the-five gates/gate-surface.py                        [2]
```

**THE TREE HAS TWO REFUSAL CODES.** `gatekit` says `3`; these five say `2`. **A runner
that maps rc→verdict through `gatekit.VERDICT` reads `2` as UNKNOWN, and
`.agents/slop/hooks/run.py:116` does exactly that: `return (r.returncode if r.returncode in NAME
else DEAD)`, with `NAME = {0,1,3,4,5}` at `:56`.** **So all five are scored `DEAD` by the tree's
own runner when they refuse** — and `DEAD` means *"it ran and emitted nothing"*, which is the
opposite of a refusal, whose whole content is *"a precondition was absent, so I measured nothing,
do not trust me"*. **A refusal scored `DEAD` is indistinguishable from a crash in every count
that reads the code.** `gate-surface.py` is the instrument whose entire subject is
*"a gate that exits 0 having measured nothing is worse than no gate"*, and **it cannot report its
own precondition-absent state in its own vocabulary.**

**`vocab-check.py` MAKES ALL OF §4 A NUMBER EVERY RUN** (exit 0/1/2, `--report` never charges),
and it is **red at rest — which is the correct current verdict, not a defect to hide.** Its own
first two versions were wrong in a way worth recording: it compared a **code** against a set of
**names** and reported all 15 declarations as "outside the five", because every code happened to
also compare cleanly against the name set. **A COMPARISON THAT CANNOT FAIL LOOKS EXACTLY LIKE A
COMPARISON THAT FOUND NOTHING** — `gates-pop.py:code_of`'s own lesson, and the third time I have
tripped it in this unit. The key direction is now *derived* (`CODES = set(gk.VERDICT)`) rather
than retyped, so it cannot invert again, and the `refuse()` placed before any measurement caught
the `gk.VERDICT` inversion at exit 2 — which is what a refusal is for.

---

## 5. WHAT I LANDED, AND WHY IT IS NOT A CONSOLIDATING MODULE

**I LANDED NO CONSOLIDATING MODULE. That is the finding, and it is the same move `zerogate` made —
which its own report calls rare and correct.** What I landed instead is `vocab-check.py`, which
**checks a fact that was previously a session finding and is now a number every run**, and which
owns no population, no vocabulary, and no declaration.

The brief asks for a consolidating module "only if it removes a hand list without creating a new
subject". **Measured against that test:**

1. **There is no hand list to remove among the six.** Plant 1 moved all four gate projections
   with zero edits. The consolidation `gendirs.py` already performed is holding.
2. **The three owners are three subjects** (§4). Merging them creates a fourth thing whose job is
   to own three things — which is the defect one level up, not a fix for it.
3. **`pairs` and `prune4` must not be merged into anything** (§0).
4. **`vocab-check.py` is the smallest thing that removes a hand list**, and it removes three:
   it makes the copies *comparable to their owner* instead of comparable to each other. **It adds
   no subject** — it asks "does `gatekit`'s vocabulary have exactly one owner?", which is a
   question about `gatekit`, not a fourth kind of gate infrastructure.

**WHAT I LANDED — three files, none of which is a population:**

| file | subject | owns a population? |
|---|---|---|
| `.agents/slop/onemodule/probe.py` | **the six projections, side by side, at one timestamp** | no — it asks each of six for its own |
| `.agents/slop/onemodule/plant.py` | **the plant: does a new gate move every projection?** | no — it creates the tree state and asks |
| `.agents/slop/onemodule/vocab-check.py` | **is there ONE verdict vocabulary, and do the copies agree with it?** | yes — of the copies, by `os.walk`, never by name |

**None of the three is a shared gate population, and that is deliberate: a module that owns a
population, one that owns a vocabulary, and one that owns a declaration are three subjects, and
§4 measured that adding a fourth owner makes the disagreement worse, not better.**

**What the tree needs instead is a SCOPE TOKEN on each number, not a shared module.** Six
instruments, six scopes, one per line:

```
119  gates-only, FLAT (iterdir)     discover() == gate-surface
121  gates-only, RECURSIVE         vocab.scan() == zerogate
126  whole tree, shared string-lists, os.walk   pairs
---  git index state               prune4
```

`gate-surface.py:108` already prints its control beside its population; `pairs/census.py` already
prints whole-tree beside tracked; `probe.py` already prints all six beside each other. **THE
INSTRUMENTS ARE NOT MISSING A SHARED MODULE. THEY ARE MISSING THE FOUR-TOKEN LABEL.**

### 5a. THE ONE DEFECT THAT *DOES* WANT A FIX — AND IT IS NOT A NEW MODULE

`discover()`'s `iterdir()` → `rglob()`, or a walk. That is **a one-token change to a line that
already exists**, and it moves `discover()` from 119 to 121 and closes `|D-W| = 2`. **It is not
mine to make** (the brief forbids touching existing instruments), and it is not neutral: it would
make the two `gates/oracles/*.sh` gates *visible to every runner*, which is the point and also the
reason it deserves its own unit's judgement.

**AND `HOMES` IS THE LIST THAT SURVIVES ANY WALK FIX.** Line 95 is a 2-tuple. A third gate home is
an edit to that line, and the ledger diff is the only thing that would show it. **`discover()`
being made recursive would fix the SUBDIRECTORY hole and leave the THIRD-HOME hole exactly where
it is**, which is why the brief's "a shared population that is blind to a subdirectory is not a
population" is the smaller half of the sentence.

---

## 6. THE `prune4` TRAP — SAME FAULT, DIFFERENT HAT, AND IT IS THE INDEX

`prune4`'s `orcdecide` read **2** tracked where there are **thousands**, because it asked
`git ls-files`. **Planted and measured, the trap is a POPULATION THAT IS NOT THE TREE:**

```
prune4's POPULATION, PLANTED TWICE:
  on disk, NOT staged : in_plant_index=False, ls_files_index=93
  on disk, STAGED     : in_plant_index=True,  ls_files_index=94
```

**A gate that exists on disk and is not `git add`-ed is INVISIBLE to `git ls-files`.** That is
not a bug in `prune4` — its question is *what is tracked*, and the answer is correct. **The trap
is that a tracking census was READ AS A TREE CENSUS**, and `AGENTS.md` says the index has reset
6+ times for exactly this reason.

**AND YES — THIS IS WHY `surface` AND `hooks` AGREE WHERE `coindependent` DID NOT. BUT NOT FOR
THE REASON THE BRIEF GIVES, AND THE CORRECTION MATTERS:**

> *"if the shared population is derived from `discover()` and `discover()` reads `iterdir()` ON
> THE WORKTREE, then it is reading THE INDEX-FREE TREE and is IMMUNE"*

**Half true, and the half that is false is the half carrying the conclusion.** `discover()` *is*
index-free — `Path.iterdir()` touches no git data, so it **cannot** be the `prune4` trap. **But
`surface` and `hooks` did not start agreeing because they are index-free; they agree because they
CALL THE SAME FUNCTION.** `gate-surface.py:105` is `return gates_pop().discover(root)` and
`hooks/run.py` loads the same module by path. **Two instruments that call one function cannot
disagree, and that has nothing to do with the index.** Meanwhile the instruments that DID disagree
with each other — `coindependent` at 121 and `discover()` at 119 — **are both index-free, and they
disagree by exactly 2, because of `iterdir()`.** So the index is exonerated and `iterdir()` is
convicted, and the brief has them the wrong way round.

**ONE MORE MEASUREMENT, because `git ls-files` was compared to the wrong baseline.** On this tree,
twice, ten minutes apart:

```
03:56Z   GIT_INDEX_FILE=.git/agent-index git ls-files '*.py'  ->  1579
         plain                            git ls-files '*.py'  ->  1553      DIFFERENCE 26
04:0xZ   GIT_INDEX_FILE=.git/agent-index git ls-files '*.py'  ->  1594
         plain                            git ls-files '*.py'  ->  1665      DIFFERENCE 71
```

**TWO READERS OF THE SAME TREE, THE SAME SECOND, DISAGREE BY 26 FILES AND THEN BY 71 — AND THE
GAP GREW WHILE I WATCHED.** `AGENTS.md` prescribes `git ls-tree -r HEAD` and `NEVER git ls-files`
and gives the reason ("the index has reset 6+ times"); this is that reason, measured, and **the gap
is not a constant, it is a live disagreement between two index readers that moves.** Measured
against `ls-tree`, the third reader, both indexes are also wrong in *different directions*:
`ls-tree -r HEAD | grep '\.py$'` = **1594**, `ls-files '*.py'` = **1594** with the agent index and
**1665** without it — **so the default index carries 71 files `HEAD` does not and the agent index
carries none.**

**AND THE CONSEQUENCE FOR THE WHOLE CLASS, STATED PLAINLY: `git ls-files` answers "what has been
STAGED", which is a question about the git PROCESS, not about the tree. `prune4` used it as a
tree census. A gate that exists, runs, and is not yet `git add`-ed is INVISIBLE to it.**

---

## 7. WHAT I COULD NOT MEASURE, NAMED

- **Whether `HOMES` should be recursive.** I did not make the change (out of scope) and the two
  `gates/oracles/*.sh` gates were **not executed** — one runs `bend`, and no `bend` was started.
  My claim that they are entry points is `entry_reason()`'s verdict (`sh-selfref`), **a source
  reading, not a reached exit.** Under doctrine 2 that is a DECLARATION and I am labelling it so.
- **`checks/gen/` visibility.** `gendirs.py` closes the OUTPUT hole; whether `discover()` should
  count `checks/gen/*.c|*.js` as gates is a question nobody has asked, and I did not answer it.
- **The `to_tally` filter in `hooks/run.py`.** `run.py` filters to 13-of-114 gates that declare a
  `VERDICTS` mapping. **That is a declaration-mechanism question, not a population question**, and
  I measured the population, not the filter.
- **`pairs`' 126 vs `coindependent`'s 5.** Both correct, different scopes; I did **not** re-derive
  the five named pairs, that is `coindependent`'s table and it is not in dispute here.
- **The tree MOVED while this ran, and it moved a lot.** `probe.py` reported **141 files / 117
  entries at 03:56Z** and **145 / 119 at 04:02Z** and **146 / 120 on the final `plant.py` run** —
  **+5 files and +3 entry points by other units in under ten minutes**, and the two
  `gates/oracles/*.sh` files are unchanged across all three readings, so **the 2-file `iterdir()`
  delta is stable while the absolute totals are not.** Every absolute number above carries its
  04:0xZ stamp for that reason, and **the per-file columns in `probe.rows` are the truth here, not
  the totals** — which is the same reason `AGENTS.md` says never to quote a row count without the
  rule that produced it.
- **My own three instruments were each wrong once, and all three faults are recorded above**
  because they are the class this unit is about: `probe.py`'s `pairs` row printed `files=0`
  because of a `len(p['whole_tree'] and ... and [])` I wrote by hand (§1's table, corrected in
  the code to print the two numbers it means); `plant.py` bound `OM_ROOT` to the temp dir instead
  of the tree and scored six instruments `rc=1` as "did not move", which **is the DEAD-is-not-a-
  zero failure reproduced inside the instrument measuring it**; and `vocab-check.py` compared a
  code against a name set (§4b). **Three of three, and all three were caught by re-running, not by
  reading.** That is the argument for the plant in `AGENTS.md`'s testing rules — *the harness you
  write is the one that can fail* — and it is why `plant.py` and `probe.py` re-run each other's
  numbers rather than asserting them.

---

## 8. THE ONE-LINE ANSWER TO EACH QUESTION ASKED

1. **Which pairs are the same population?** `discover`≡`gate-surface` (provably — one calls the
   other); `coindependent`≡`zerogate` (one calls the other); `discover`≡`walk_control` (same
   files, `iterdir` vs walk). **Which are different questions?** `pairs`, `prune4`.
   **Which are contradictory? NONE.** One population, four projections, two other questions.
2. **The shared population, by discovery:** `gates/gates-pop.py:discover()` — `iterdir()` over a
   2-tuple `HOMES`, entries by AST. **It cannot see `gates/oracles/` (2 real gates, both entry
   points) or a third gate home.** A list with a recursive option.
3. **Population / vocabulary / declaration are THREE subjects and the split is right.** Four
   spellings of the five exits exist, all agreeing today, two of them already missing `SKIP`;
   and `gate-surface.py` refuses with **2**, which is not in the vocabulary at all.
4. **No consolidating module.** There is no hand list to remove — the plant moved everything with
   zero edits. **The missing thing is a SCOPE TOKEN per number, not a shared module.**
5. **The plant, run:** all four gate projections move +1 at top level, **zero lists edited**;
   at depth, `discover()` alone does not move. Both in `plant.out`.
6. **The `prune4` trap is the INDEX, planted and measured: a file on disk is invisible to
   `git ls-files` until `git add`.** And the brief's causal claim is **backwards**: `surface` and
   `hooks` agree because they **call one function**, not because they are index-free — and the
   two instruments that genuinely disagree are **both** index-free.
7. **`pairs` and `prune4` are legitimately separate and must not be unified.** Stated first,
   above.