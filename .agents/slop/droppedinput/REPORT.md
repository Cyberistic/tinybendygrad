# DROPPEDINPUT — a declaration that names two deleted files, a walk that dropped them, and a build that printed `froze 148` and exited 0

**UNIT:** droppedinput. **READING:** HEAD `a383cfa0b`, `.venv/bin/python` 3.12.10, 2026-10-07.
`snapshot.py` is **258 lines** after this work (227 before). Re-read with
`.venv/bin/python .agents/slop/droppedinput/census.py`.

**THE FIX IS LANDED AND MEASURED:** `--build` now prints **`froze 150 declared input(s) … 2 ABSENT
and NAMED in MANIFEST.tsv`**, names both paths, exits 0, and `--verify` re-reads the `ABSENT` rows.
It was `froze 148 input(s)`, no names, exit 0.

---

## 0. WHAT I CANNOT SEE, FIRST, UNREORDERED

**1. `snapshot.py` IS NOT IN `git`.** `git ls-tree -r HEAD --name-only | grep -c snapshot.py` → **0**.
My first census used a committed population (`git ls-tree`, the right primitive per `indextree`) and
reported **138 files** — and **could not see the file the whole brief is about.** The fix was to make
the population `os.walk` and the revision a *label* on each row. `census.py` now walks **868** files
(805 committed / 63 uncommitted). **A census whose population is a revision cannot see a file being
written, and this file is where two units' work is happening right now.**

**2. THE CENSUS FINDS A SHAPE, NOT A DEFECT.** It is AST over 868 files and it reports
*declaration + guard chain + no handling of the absent case*. It **cannot** know whether a dropped
member is a bug or a legitimate scope. I read all 26 sites; §3 carries the reading. **A shape count
quoted without a reading is a number you have to re-derive by hand**, which is what `indextree`'s
regex cost (183 where the truth was 61).

**3. FOUR FALSE POSITIVES, ALL MINE, ALL ON THE FILE I WAS FIXING.** Successive versions of the
classifier reported `snapshot.py`'s own `--declare` as a drop site three times, because they did not
know (a) an **inverted** guard `if not here:` *is* the absent branch, (b) a guard **bound to a name**
before the `if` that uses it, (c) a **conditional expression** `… if p.is_file() else "ABSENT"`,
which is `checks/differ.py:882`. Each version was strictly less wrong (7 → 5 → 3 offenders) and each
version was wrong **on the same file**. That is `indextree`'s regex error reproduced inside the census
of it, and it is the strongest argument in this report for the shape count being accompanied by a
reading.

**4. `snapshot.py` IS A PRECONDITION, NOT A GATE.** `quiesce` gives it `PASS` / `REFUSED` / `DEAD`
and **no `FAIL`, because nothing compares two answers.** So a dropped input was **never a verdict
here** — it was a **silent shortening of what the run measured.** A measurement of less than it claims
is the `DEAD` class without the token, and **that is worse than a gate lying, because a gate that
lies is at least a gate that ran.**

**5. NOTHING WAS COMMITTED, NOTHING STAGED.** No `git add`, no `jj`, no `@`. `.git/index` untouched
(`git ls-tree` only). No gate body, no `AGENTS.md`, no `tinybendygrad/`. No `bend` was run. The two
files I edited and the four I added are under `.agents/slop/quiesce/` and `.agents/slop/droppedinput/`.

---

## 1. BOTH HALVES, EXACTLY

### THE DECLARATION — `COPIES`, `snapshot.py:63-67` (was `:63-67`, unchanged)

```python
COPIES = ("bin", "checks/differ.py", "checks/devpin.py",
          ".agents/slop/graphcmp.py", ".agents/slop/graphcmp.bend",
          ".agents/slop/graphcmp-dbg.bend", ".agents/slop/graphcmp-empty.bend",
          ".agents/slop/graphcmp-oracle.py", ".agents/slop/graphcmp-dbg-oracle.py",
          ".agents/slop/graphcmp-p13-ops.py")
```

**10 members. Two are absent on disk** (`.agents/slop/graphcmp-dbg.bend`,
`.agents/slop/graphcmp-empty.bend`), deleted in sweep `371cc64c9`.
`--declare` names both and **exits 1** (measured, twice).

### THE WALK — `inputs()`, `snapshot.py:74-86` BEFORE this work

```python
for c in COPIES:
    p = ROOT / c
    if p.is_dir():
        files += [q for q in p.rglob("*") if q.is_file()]
    elif p.is_file():          # <-- THE LINE. There is no `else`.
        files.append(p)
```

### **THE LINE WHERE ONE STOPS BEING CONSIDERED: `elif` at the old `:85`.**

Not the `is_dir()` test. **The `elif`.** An absent path matches neither branch and leaves the loop
having produced **no row, no count, and no name.** `build()` (`:99`) iterates `inputs()`, so the drop
reaches `froze 148`, `MANIFEST.tsv`, and `--verify` without one of them noticing.

### **THE DOCSTRING AND ITS OWN BRANCH DISAGREE — AND YES, THIS IS A CLASS.** Third instance tonight
(`gates-pop.py`'s `os.lstat` claim, `device.bend`'s `Bool` list, this one). The old `:76-77`:

> *"A named path that is ABSENT is returned as well (by `--declare`), **never silently dropped** — a
> snapshot that freezes 9 of 10 inputs is a snapshot that passes on a coincidence."*

**The parenthetical is the whole tell: "(by `--declare`)" — the docstring names the ONE place the
property is true, in a sentence that claims it universally.** The author knew. The branch did not.
`gates-pop.py:327-330` claims `os.lstat` while `:338` calls `is_file()`; here the docstring claims a
property the branch contradicts. **Same shape: prose in the owner describing an instrument that is not
the one beside it.** It is a class because it has now been hit three times in one session by three
different files, and because the failure is *cheap to state and invisible to run*.

---

## 2. THE CLASS, BY DISCOVERY — **26 SITES, 3 THAT DROP, AND THEY ARE 3 DIFFERENT THINGS**

`census.py` walks every `.py` under `checks/ gates/ .agents/slop/` and finds, by AST: a module-level
`NAME = ( "str", … )` (**a declaration**) consumed by a `for`/comprehension whose guard chain tests
existence/type (**a walk**) with **neither a terminal `else` nor an inverted test** (**a silent drop**).

| | |
|---|---|
| population (`os.walk`, 3 roots) | **868** `.py` (805 committed / 63 uncommitted) |
| declaration + consumer sites | **26** |
| **of which the absent case is unhandled** | **3** |

**The class boundary, measured: 3 of 26 — and the 3 are NOT THE SAME DEFECT.**

| site | what is dropped | is it the same defect? |
|---|---|---|
| `.agents/slop/quiesce/snapshot.py` `COPIES` (pre-fix `:85`) | **a declared INPUT, from a freeze that claims to freeze the inputs** | **YES — this is it, and it is fixed** |
| `.agents/slop/flipthird/build.py:74`/`:76` | `OWNED` (5 members); `{p: hash for p in OWNED if os.path.exists(p)}` then **`say(f"owned: {len(OWNED)} files")`** | **YES — the same arithmetic.** Measured: it prints `len(OWNED)` = 5 and hashes `len(pristine)`. All 5 present today, so the gap is **latent**: delete one and it still prints 5 while hashing 4. **A count read off the DECLARATION beside a measurement read off the DISK.** |
| `.agents/slop/offrepo/callers.py:51` | `SEARCH_DIRS` (4 search ROOTS) missing from `roots` | **A RELATED SHAPE, NOT THE SAME DEFECT.** The `2 MB` cap skips ARE counted and printed (`SKIPPED`, and the comment says so); a missing ROOT is not named. But a search root that is absent means *there is nothing there*, not *an input was deleted*. **This is the `subtree` class: silent, not wrong.** |
| `.agents/slop/subtree/measure5.py:69` | `DEEPER` — `emit("INPUTS", rel, f"exists={p.is_file()} …")` then `p.read_text()` | **NOT A DROP.** The existence is **emitted** and the read then **raises**. Loud, not silent. **A near-miss of my classifier**, and reported as one. |

### **IS "SILENT BUT NEVER WRONG" ACCEPTABLE, OR THE SAME DEFECT IN A FRIENDLIER HAT?**

**Neither — and the honest answer is that "silent but never wrong" is not a property this tree can
verify.** `subtree` measured `|only-discover| = 0`: `discover()` is a strict subset of a recursive
walk, so it **can** be silent and **cannot** be wrong *today*. The mechanism it identified is the one
that matters here: **a silently-discarded entry and an unvisited one are the same observation, and
only the second is knowable.** `offrepo/callers.py` is that mechanism. `flipthird/build.py` is NOT —
it prints a count the measurement cannot contradict, which is `subtree`'s "a denominator defined by
the walk it audits is a restatement."

> **SO THE CLASS HAS A HARD EDGE AND IT IS NOT "SILENCE":**
> **A dropped member is tolerable exactly while the COUNT cannot be read off the wrong side.** The
> moment an instrument prints a number sourced from the declaration while its measurement is sourced
> from the disk, silence becomes a false claim. `snapshot.py` printed `froze 148` over **150**
> declared — that number was **false**, not merely incomplete.

### THE VOCABULARY — **THIS IS `UNJUDGED`. A FOURTH WORD WOULD BE A SECOND COPY OF A LIST.**

The tree already owns a word for *"nothing was measured here"* and it is **not** one of the five
exits. `checks/substrate.py:59`:

> *"A non-source file is printed `NO INSTRUMENT` and the **`UNJUDGED` line names how many discovered
> files were NOT judged**."*

and `:847` prints `UNJUDGED  N of M discovered file(s) are not a …`, and `substrate.py` **refuses with
exit 3** when anything is unjudged. That is precisely this state: a member of the discovered population
that no instrument judged.

| candidate | why not |
|---|---|
| **`NO ROW`** | `wallcheck.py:396` — *"NO ROW MATCHES … — REFUSED, not CLEAN: a guard over an empty set"*. **A row that a search produced and found none of.** Here the row was never produced. |
| **`UNTAKEN`** | `gate-surface.py:61` — *"the gate's rc-0 plant did not reach 0"*. **A measurement that was never taken.** `snapshot.py` took its measurement; it dropped a member from the result. Adjacent, and confusingly so. |
| **`UNJUDGED`** | **`checks/substrate.py` owns it, and its definition is exactly this**: a member of the declared population that no branch judged. `NO INSTRUMENT` is its per-file row. **USE THIS WORD. DO NOT INVENT A FOURTH.** |

**A fourth word would be a second copy of a list.** The tree already has this defect at
`declareverdict` §7.4 (a synonym table it refused to build) and `TOOLS.md` (333 paths, 169 gone).

---

## 3. THE THREE OPTIONS, AND WHAT A RUNNER IS CHARGED

The decisive constraint, from `hooks/run.py:116`:
`return (r.returncode if r.returncode in NAME else DEAD)` with `NAME = {0,1,3,4,5}` —
**anything outside the five becomes `DEAD`.**

| option | `build()` would return | a runner reads it as | it is told | cost |
|---|---|---|---|---|
| **(a) emit `ABSENT` as a VALUE** | **0** | `PASS` — and it is **correct**: the freeze succeeded, and it discloses 2 of 150 had no bytes | `froze 150 declared input(s); 2 ABSENT and NAMED`, each path on its own line, and the same two rows in `MANIFEST.tsv` | **one `else` and one `if` in `build()`** |
| (b) REFUSE | 3 | `REFUSED` — *"a precondition was absent"* | which two paths | **the build stops working FOREVER.** The two files are deleted in `371cc64c9` and `midrun` §1a already argued this: *"two declared inputs are absent from this tree right now … so the judge would be REFUSED FOREVER and would be ignored."* **A gate that can never pass is worse than no gate** — `AGENTS.md`, and `repropin` §4 reaching it independently. |
| (c) report the count mismatch | 0 or 1 | `PASS` or `FAIL` | `froze 148 of 150` | **A COUNT CANNOT NAME A PATH.** `substrate-id.py:196-200` states it: *"A count cannot name *which* bytes. Only a digest can."* And `148 of 150` still needs a reader to diff 150 paths by hand. |

> ### **(a) IS THE ANSWER — AND IT IS NOT A NEW ANSWER. IT IS THE ANSWER TWO OTHER INSTRUMENTS
> ### ALREADY GIVE.**
> `checks/differ.py:882` — `… hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "ABSENT"`
> `checks/substrate-id.py:131` — `h.update(b"ABSENT")`
>
> **`snapshot.py`'s walk was the only one of the three not using it.** Measured with `token.py`
> (AST, distinguishing an emitted `Constant` from a mention in prose). **Before, and after this fix:**
>
> | file | `ABSENT` occurrences | **EMITTED VALUES** (before → after) |
> |---|---|---|
> | `.agents/slop/quiesce/snapshot.py` | 2 → **9** | **0 → 2** (`:136` the `MANIFEST` row, `:157` the printed line) |
> | `checks/differ.py` | 9 | **1** (`:882`) |
> | `checks/substrate-id.py` | 7 | **1** (`:131`) |
>
> **The question "why does nothing emit it" has the answer measured: `snapshot.py` had no `ABSENT`
> value to emit.** Its two occurrences were `--declare`'s own print strings, and `build()` never
> called `--declare`. **Re-measured after the fix: 2 emitted values, and they are on the two paths
> that carry the fact.**

---

## 4. THE ONE THAT IS A GATE'S INPUT — **RESTORE IT, OR KEEP REFUSING?**

**The tree has taken BOTH and the third answer is now visible. Three absent declared inputs, by name:**

| # | path | read by | how the tree answered |
|---|---|---|---|
| 1 | `.agents/slop/graphcmp-empty.bend` | `checks/differ.py:593` (`--bend-probe` probe) | **`REFUSED`, exit 3, with the deletion named** — `601053dd2`. **This is the `D10-zerorow-guard.txt` read of `rc=1` off a `no such file`, replaced by a refusal that says which.** |
| 2 | `.agents/slop/graphcmp-dbg.bend` | `.agents/slop/graphcmp.py:274` `BEND_DBG` (`:2758`) | **silently dropped from the freeze** — the defect this unit fixed |
| 3 | `.agents/slop/diffpy/` (2 oracle scripts) | `checks/differ.py:61-64` `ORACLE_PIN`, read by `check_oracle` at `:78` | **hand-copied into the snapshot by `midrun` after the run DIED** — *"ORACLE DRIFT: diffpy/oracle-run.sh: MISSING"*. **Not a verdict; a crash.** |

**#3 IS NO LONGER ABSENT — MEASURED NOW:** both scripts are on disk and **both pins verify**:
`oracle-run.sh` `94e7108d428b` ✅ · `oracle-repro.sh` `a5d23505b3e9` ✅.

**#1 AND #2 ARE BOTH RECOVERABLE FROM GIT — MEASURED:**
`git rev-parse 371cc64c9^:.agents/slop/graphcmp-empty.bend` → blob `bdbc99e124bd`, **110 B**
`git rev-parse 371cc64c9^:.agents/slop/graphcmp-dbg.bend` → blob `57da4c37762333`, **10 151 B**

### **THE ANSWER IS `differ.py:593` — REFUSE. AND THE REASON IS NOT "THE FIXTURE IS MISSING".**

**The three units made three choices, and it IS the pattern, not the problem — because the choice is
a function of WHAT THE ABSENT PATH IS FOR, and two of the three units did not know that.**

> **AN ABSENT PATH IS A ROW IF THE INSTRUMENT IS COPYING A POPULATION, AND A REFUSAL IF THE INSTRUMENT
> IS MAKING A CLAIM THE PATH IS THE EVIDENCE FOR.**

- **`differ.py:593` → REFUSED.** The zerorow guard's *subject* is the probe. Without the probe the
  guard has no subject, and `D10` was certifying a missing file. **REFUSE is right.**
- **`snapshot.py` → `ABSENT` row.** The freeze's subject is *the tree*. The tree genuinely has no such
  file, and a freeze of a tree with a hole in it is a **faithful** freeze. **Refusing would make the
  freeze impossible exactly when the tree is abnormal — which is when you most need one.**
- **`diffpy/` → it was absent and a run CRASHED.** Neither row nor refusal: a traceback, which
  `hooks/run.py:113` classifies as `DEAD`. **The worst of the three, and the only one nobody chose.**

**So it is ONE ANSWER APPLIED BY ROLE, not one answer applied three times by hand.** The uniform
rule above produces `601053dd2`'s choice and `snapshot.py`'s from the same sentence, and it says the
`diffpy/` crash was **neither**.

**SHOULD THE FILE BE RESTORED?** **Not as the fix.** Both are recoverable, and restoring would delete
the measurement rather than make it — `differ.py:593`'s refusal is *correct today* and would become a
false claim the moment the file came back. **Restoration is a separate decision about whether the
zerorow guard is still wanted; this unit's answer is that the honest read is the one landed, and the
file's absence is now visible in the freeze, in the digest, and in `--declare` — three places.**

---

## 5. WHAT LANDED — BOTH DIRECTIONS PLANTED, WITH THE CONTROL THAT CAN BE FALSE

**`.agents/slop/quiesce/snapshot.py`, the whole change:**

1. **`inputs()`** — `elif p.is_file():` → **`else:`**, and the docstring rewritten to say what the
   branch now does instead of what it never did.
2. **`absent()`** — new, 3 lines. The declared members with no bytes, named.
3. **`build()`** — a member with no bytes gets an **`ABSENT`** row in `MANIFEST.tsv` and a printed
   line; the headline count is **declared**, not present.
4. **`verify()`** — an `ABSENT` row no longer crashes `sha()`; it prints `ABSENT` or **`APPEARED`**
   (and `APPEARED` counts as bad — the tree grew under the freeze).

**MEASURED, LIVE TREE, BOTH DIRECTIONS:**

```
$ .venv/bin/python .agents/slop/quiesce/snapshot.py --build DEST
froze 150 declared input(s) into DEST; 2 ABSENT and NAMED in MANIFEST.tsv
  ABSENT  .agents/slop/graphcmp-dbg.bend    declared, not on disk, NOT COPIED
  ABSENT  .agents/slop/graphcmp-empty.bend  declared, not on disk, NOT COPIED
rc=0

$ grep ABSENT DEST/MANIFEST.tsv
ABSENT	.agents/slop/graphcmp-dbg.bend
ABSENT	.agents/slop/graphcmp-empty.bend

$ .venv/bin/python .agents/slop/quiesce/snapshot.py --verify DEST
  ABSENT   .agents/slop/graphcmp-dbg.bend    declared, no bytes frozen
  ABSENT   .agents/slop/graphcmp-empty.bend  declared, no bytes frozen
VERIFY: OK -- 150 of 150 frozen inputs unchanged; 0 differ from the live tree
```

**`150`, not `148`. And both paths NAMED, in the manifest, in the headline, and in `--verify`.**

### THE PLANT — `.agents/slop/droppedinput/plant.py`, **11 of 11, rc=0**

The shipped `snapshot.py` is **loaded by path** with `ROOT` re-pointed at a temp tree; no live file is
touched; no `bend`.

| | assertion | got |
|---|---|---|
| **A** | a declared **PRESENT** path is a member | ✅ |
| **B** | a declared **ABSENT** path **is still a member** | ✅ |
| **B** | and `MANIFEST.tsv` carries the literal token `ABSENT` for it | ✅ `got='ABSENT'` |
| **B** | and the count includes it (3 copies + 1 port file = **4**) | ✅ `got=4` |
| **C CONTROL** | an **UNDECLARED** file on disk is **not** a member | ✅ `got=False` |
| **C CONTROL** | the port **walk** still discovers (`tinybendygrad/port.bend`) | ✅ |
| **D** | `--verify` on a manifest carrying `ABSENT` → rc **0**, no crash | ✅ |

> **C IS THE ASSERTION THAT CAN BE FALSE, AND IT IS WHY B IS A MEASUREMENT.** If `inputs()` had been
> "return everything under the tree", B would pass **and C would fail.** B alone is satisfiable by
> widening the population; B *with* C is satisfiable only by the declaration. `prune4`'s clause was
> vacuously true for 3 974 files — this one is false for every file that was not declared.

### AND THE FALSIFICATION — `.agents/slop/droppedinput/falsify.py`, rc=0

An assertion that cannot fail is not an assertion. The pre-fix branch is reconstructed from the line I
read before editing and loaded by path, and the same property is asked of both:

| member | shipped | pre-fix |
|---|---|---|
| declared **PRESENT** `kept.bend` | True | True |
| declared **ABSENT** `gone.bend` | **True** | **False** |
| **CONTROL** undeclared `undelared.py` | False | False |
| discovery `tinybendygrad/port.bend` | True | True |

**Exactly one row differs and it is the ABSENT one.** The first attempt at this harness also reverted
`build()` and produced `froze 0` — **a broken reconstruction, not evidence.** A falsification harness
that fabricates its own failure proves nothing; only `inputs()` membership is reverted, because that
is the property under test.

### THE REGRESSIONS THAT DID NOT MOVE

`.agents/slop/quiesce/freeze-check.py` → **FREEZE-CHECK: OK** rc=0 ·
`checks/substrate-id.py --plant` → **`PLANT: OK`**, all cases including `delete-cop` (which imports
`snapshot.inputs()` **by path** and therefore exercises the changed function against its own
expectations) · `snapshot.py --declare` → rc **1** with both names · `snapshot.py --plant` → **OK**.

**`checks/substrate-id.py`'s `population()` (`:105-113`) is now REDUNDANT** — it re-derives the absent
set because `inputs()` used to drop it. It still reports `inputs: 148, declared: 150`. **NOT FIXED:
it is a `checks/` file and this unit does not edit one it does not own.** Its redundancy is the
measurement that the fix worked: **two instruments derived the absence independently before; one walk
now carries it, and one consumer still does the old work.**

---

## 6. WHAT IS OWNED HERE

| path | what |
|---|---|
| `.agents/slop/quiesce/snapshot.py` | **EDITED** — the `else`, `absent()`, `build()`'s `ABSENT` row, `verify()`'s `ABSENT`/`APPEARED` row, two docstrings rewritten |
| `.agents/slop/droppedinput/census.py` | the class census (AST, `os.walk` population) → `census.rows` |
| `.agents/slop/droppedinput/census.rows` | 28 rows: 26 sites, each with its declaration, guard line, and verdict |
| `.agents/slop/droppedinput/twolists.py` | the two declarations of the same run, compared (`COPIES` 10 vs `SUBSTRATE_INPUTS` 8; intersection 7) |
| `.agents/slop/droppedinput/token.py` | **mention vs emission**, per occurrence, AST — §3's table |
| `.agents/slop/droppedinput/plant.py` | 11 assertions, both directions, **with the control that can be false** |
| `.agents/slop/droppedinput/falsify.py` | the pre-fix reconstruction; **exactly one row differs** |

**`.agents/slop/quiesce/snapshot.py` is NOT in git** (`ls-tree` → 0), which is why §0.1 exists and why
this fix is on disk only. **That is a finding about this unit's own work, not a caveat about it.**

## 7. THE RESIDUALS

1. **`flipthird/build.py` has the same arithmetic and is NOT FIXED** — it prints `len(OWNED)` over a
   population built from `os.path.exists`. Latent today (5 of 5 present); **a live false-count the
   moment one is deleted.** Another unit's file.
2. **`offrepo/callers.py` drops an absent `SEARCH_DIR` unnamed.** The 2 MB cap skips ARE counted and
   printed; the root is not. Related shape, benign today.
3. **`substrate-id.py`'s `population()` still re-derives the absent set.** Redundant now; harmless;
   `checks/` is not mine.
4. **`census.py` cannot see a guard reached through a FUNCTION CALL** — `if gone(p):` where
   `gone()` internally tests `is_file()`. No AST shape distinguishes that from any other predicate,
   so such a site is invisible and the census can only be a lower bound. **Not acted on, named.**
5. **`census.py` has 3 known blind spots** and each one produced a false positive on the file I was
   fixing: a guard bound to a name, a conditional *expression* rather than a statement, and a
   guard that is an attribute of a subscript. **A shape count with named gaps is a census with a
   denominator; it is not a verdict, and none of the 3 sites is acted on without reading it first.**
   The count went **23 → 7 → 5 → 3** as gaps were closed, and **every intermediate number was wrong
   on `snapshot.py` itself.**
5. **`snapshot.py`'s `TOOLING` still drops an absent toolchain entry** (`:129`). **This is a REAL
   THIRD INSTANCE IN THE FILE I JUST FIXED**, and I left it: an absent `TOOLING` dir means the
   snapshot cannot run, which is a different question from an absent input (the freeze is still
   faithful). **Named rather than silently left: that is the whole point of the vocabulary, and
   leaving it unnamed would repeat the defect I was sent here to remove.**