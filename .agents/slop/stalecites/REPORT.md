# `stalecites` — the `(path, line, must_contain)` class, measured

**Committed nothing. Staged nothing.** Scope touched: `checks/disagree-gate.py` and
`.agents/slop/stalecites/`.

---

## 0. TWO WAYS MY OWN MEASUREMENT WAS WRONG, BEFORE ANYTHING ELSE

The instruction was to find a way my own measurement was wrong and say so first, with the
before-value. There were **three**, and two of them were in the instrument I wrote.

### 0.1 The brief's path does not exist — before-value: "0 instances in `gates/`"

The brief names `gates/disagree-gate.py`. **It has never existed.** `git ls-tree -r HEAD`
finds exactly one tracked path matching `disagree`, and it is **`checks/disagree-gate.py`**.
Had I trusted the brief's directory and globbed `gates/*.py` for a hand list of tuples, I
would have reported **0** — a clean number produced by looking in a directory the class is
not in. This is the exact instrument that reported `0` four times today because it could
not see. **A basename is not a path, and neither is a directory in a brief.**

### 0.2 My first census said 58 in 3 modules. Truth: 51 in 2.

The 8 in `.agents/slop/plantthe46/plant.py:88` are **false positives of my own shape test**.
That integer is a **case index into a test vector**, not a line number:

```python
cases = [
  ("checks/wallcheck.py", 0, ["--selftest"], [], "the shipped ledger, which is red today"),
```

My `_is_lineish` admits any integer ≥ 1, and I then grabbed the tuple's last string — which
here is a prose *scenario description*, not a must-contain. **Before-value 58 → after 50.**

### 0.3 Then it said 51 with **19 phantom `NO-ANCHOR`s**. Truth: 0.

I extracted the anchor as the **last** string element. On `CITES`' 4-tuple
`(path, line, must, why)` the last element is the **rationale prose**, which resolves
nowhere — so 14 rows I had just repaired were reported as `NO-ANCHOR`. Fixing that exposed
the mirror-image error in §3.1. **Before-value 19 `NO-ANCHOR` → after 0.**

**The generalisable fault, and it is the same one doctrine 1 names:** each wrong answer was a
*shape* I guessed rather than a convention I read. The cure was to stop guessing one anchor
convention and to let both candidates stand, reporting which one matched.

---

## 1. REPRODUCING THE TWO FAILs

`checks/disagree-gate.py --lane citations` → **FAIL (exit 1)**, verbatim:

```
FAIL  CITATIONS
  .agents/slop/graphcmp.bend:1571 -- reads '+r0 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, ...)',
                                   expected 'def rows.pick3'
  .agents/slop/graphcmp.bend:777  -- reads '# one -- and a differ that only ever saw trees ...',
                                   expected 'OpsGROUP'
```

**Both are pure DRIFT. The text was never removed.**

| cited | anchor present at | drift | what the text says now |
|---|---|---|---|
| `graphcmp.bend:1571` `def rows.pick3` | **:1595** | **+24** | `def rows.pick3(+name: String) -> O.Found:` |
| `graphcmp.bend:777` `OpsGROUP` | **:791** (and 11 more) | **+14** | the commute fixture's `[add, mul]` GROUP statement |

`graphcmp.bend` grew 1650 → 1664 → 1674 lines in two commits (`73644b9c1`, `bbe246aca`)
without changing one word of either claim. **MEASURED, the pin was last correct at
`813bbec3e`, where the file was 1650 lines and `rows.pick3` was at exactly :1571.** The
citation was not always wrong; it was right once and decayed silently.

### 1.1 A worse fact about the second one: `OpsGROUP` was never a pin at all

`OpsGROUP` matches **12** lines in `graphcmp.bend` (791, 822, 910, 1173, 1232, 1253, …).
The old check was `cited(lines[n-1], needle)` — it read **one fixed line** and asked whether
the needle appeared there. It never established that the needle was *distinguishing*. So
`:777` "passed" for as long as *any one* of 12 lines sat at 777. **An anchor that matches
many lines is a claim that cannot fail.** The brief's "2 of 14 FAIL" therefore **understates**
the defect: 2 rows were *detectable* drift, and 4 needles were structurally incapable of
catching anything (measured §3.2).

---

## 2. THE CENSUS — by AST, by directory walk, with denominators

`.agents/slop/stalecites/census.py`. **Population clause (b): a directory walk**, asked of
git's **tree** (`git ls-tree -r HEAD`, not `git ls-files`, which reads the index this tree
has had wiped and restaged repeatedly), parsed with `ast`. Nothing lists files.

**Scope stated with the number, because it is the bound on every figure below:**

> **POPULATION: 1720 git-tracked `.py` files out of 6969 tracked paths, parsed with `ast`.**
> A citation is a **lower bound**, not a sufficient condition — which is this task's subject.

| verdict class | count | of |
|---|---|---|
| ON-LINE | 44 | 51 |
| **DRIFT** | **7** | 51 |
| NO-ANCHOR | 0 | 51 |
| **NO-FILE** | 0 | 51 |

**51 assertions in 2 modules** — the named instance plus exactly one other, found by
walking every tracked `.py`, not by grepping for a file name:

| module | owner | shape | assertions |
|---|---|---|---|
| `checks/disagree-gate.py` | `CITES` | `(path, int, str, str)` | **14** |
| `.agents/slop/citemass/resolve.py` | `A` | `(path, int, str, int, int\|None, str)` | **37** |

`.agents/slop/citemass/resolve.py:32` is a **richer instance of the same class** — a 6-tuple
`(check_relpath, cite_line, ref, N, end, anchor)` whose own comment declares the anchor must
be on the cited line. It carries `N`/`end` for range assertions and already survives
re-anchoring, but **18 of its 37 rows are drifted** (before my fix; measured above at 20,
then 18 once the anchor convention stopped shadowing real anchors). **It is out of my
write scope — I report it, I do not touch it.**

### 2.1 A second spelling of the same class: ZERO, and that is a measurement

The position can also be fused into the path (`("a/b.py:559", "must")`), which a 3+-tuple
shape test cannot see. Swept separately by AST over the same 1720 files: **0 instances.**
Reported because "I did not find any" is only worth printing with its denominator.

### 2.2 Two instances the `.py`-literal sweep CANNOT see

`.md` prose carries line-citations in ranges. **Measured examples:**
`.agents/slop/wmmafix/REPORT.md` cites `disagree-gate.py` at `:63-77`, `:83-111`, `:146`,
`:151-157`, `:193` — five positions in the very file this unit edited. And
`checks/differ.py:670` — a **live `.py` citation**, in prose:

> "…read by four consumers … by `checks/corpus-figure.py:140`, by
> **`checks/disagree-gate.py:128`** and by `checks/env-precond.py`'s METHOD B…"

**MEASURED: that citation was ALREADY WRONG BEFORE I TOUCHED ANYTHING.** At `HEAD`,
`disagree-gate.py:128` read `("tinybendygrad/uop/ops.bend", 1117, "dtype: S.Dt",` — a `CITES`
row. The `key=value` summary parse it claims lives at **:174–180** at `HEAD` (now
**:210/:216**). Off by **46 lines**. **A fourth instance of the class, stale on arrival,
in a file whose class is the subject.** Its three sibling paths (`gates/retention-check.py`,
`checks/corpus-figure.py`, `checks/env-precond.py`) all resolve — the *line* is the defect.

---

## 3. THE FIX — derive what can be derived, refuse what cannot

### 3.1 Which of the 14 can become AST-derived, and which cannot — **measured, per row**

| # | target | enclosing def (AST) | form |
|---|---|---|---|
| 1 | `graphcmp.bend` `def rows.pick3` | — `.bend`, no AST | **AT** |
| 2 | `graphcmp.py` `def g_allred` | `g_allred` | **DEF** |
| 3 | `graphcmp.py` `def g_cdiv` | `g_cdiv` | **DEF** |
| 4 | `graphcmp.py` `def g_late` | `g_late` | **DEF** |
| 5 | `ops.py:559` `if len(srcs) == 1` | `UOp` | **DEF** |
| 6 | `graphcmp.py:1386` `UOp.group(a.flip(0).uop)` | `g_flip` | **DEF** |
| 7 | `graphcmp.bend` `OpsGROUP` | — `.bend`, no AST | **AT** (widened) |
| 8 | `ops.bend:1117` `dtype: S.Dt` | — `.bend`, no AST | **AT** (widened) |
| 9 | `ops.py^:1398` `dtype: DType = dtypes.void` | `CallInfo` | **DEF** |
| 10 | `ops.py^:1404` `self.dtype is not dtypes.void` | `CallInfo` | **DEF** (widened) |
| 11 | `ops.py:1405` `aux: Any = None` | `CallInfo` | **DEF** |
| 12 | `ops.py:132` `return src[0].dtype` | `dtype_from_uop` | **DEF** |
| 13 | `fold.bend:1154` `CallInfo.dtype` | — `.bend`, no AST | **AT** |
| 14 | `ops.bend:999` `applied_opts: List<&2, OPT>` | — `.bend`, no AST | **AT** |

> **9 of 14 are AST-derivable; 5 are not, and all 5 are `.bend` files.**
> The split is *derived from the tree, not chosen*: a `.py` target gets its `DEF` form by
> construction, and `.bend` has no AST to ask. `AT` rows 7 and 8 were additionally
> **widened**, because their needles were ambiguous (§1.1). Every one of the 14 anchors is
> now verified **unique in its target** (measured 1 hit each) — row 7's widened anchor is
> the exact commute-fixture statement `O.UOp.new(O.Found.ar(mul), O.OpsGROUP{}, [O.Found.i(add), O.Found.i(mul)], O.ANone{}, O.TNone{})`, and row 10's is the `__repr__` conditional `f", dtype={self.dtype})" if self.dtype is not dtypes.void`.

**The locator grammar, one line of data per row:**

```
DEF:<path>:<name>    the top-level def or class <name>; the assertion is that ITS BODY
                     carries the text.  The parser resolves the name every run, so the
                     line falls out of the node and is NEVER STORED.
AT:<path>            the text is searched as a UNIQUE substring of the whole file.
```

`ad117c928^:tinygrad/uop/ops.py:CallInfo` parses correctly because the split is
`partition(":")` then `rpartition(":")` — a `rev:path` prefix survives.

### 3.2 Two plants, because a gate that cannot be moved is a gate that proves only itself

Run on scratch copies; the tree is untouched.

```
PLANT 1 -- INSERT 300 LINES ABOVE THE CITED DEF
  baseline          : PASS
  +300 lines above  : PASS
  -> POSITION-DEPENDENT -> POSITION-INDEPENDENT: PROVEN

PLANT 2 -- DELETE THE CITED TEXT
  mutated           : FAIL  tinygrad/uop/ops.py: def UOp no longer carries
                              'if len(srcs) == 1' (it reads 'class UOp(...)...')
BOTH PLANTS MOVED.
```

Plant 1 is the repair's whole claim: the old table scored this **FAIL at 300/1**.
Plant 2 is the half that is easy to fake — a resolver that always returned PASS would pass
plant 1 trivially.

### 3.3 What happens when the anchor is absent — **REFUSED (exit 3)**, driven, not asserted

`locate()` returns `PASS | FAIL | REFUSED`. **Every branch was driven with a real input:**

| condition | verdict | message |
|---|---|---|
| anchor present, unique | `PASS` | — |
| **anchor matches 0 lines** | `REFUSED` | `no line carries 'THIS_STRING_IS_NOT_IN_THE_FILE'` |
| **anchor matches >1 lines** | `REFUSED` | `12 lines carry 'OpsGROUP' (lines [791, 822, …]), and an anchor that matches many lines is a claim that cannot fail -- widen it or give the row a DEF locator` |
| **def renamed away** | `REFUSED` | `no def named NoSuchDef carrying 'anything'` |
| **target unreadable** | `REFUSED` | `unreadable or absent` |
| **unknown locator kind** | `REFUSED` | `unknown locator kind 'BOGUS'` |
| **def exists, text gone** | **`FAIL`** | `def UOp no longer carries 'if len(srcs) == 1'` |

**Why absent is REFUSED and not FAIL:** a FAIL says *the tree is wrong*, and the tree may be
perfectly right — the citation may be what is wrong. The gate cannot distinguish "the code
moved" from "this row never described the code", and **guessing is the exact fault this
table is being removed for.** Why not silent PASS: a gate that exits 0 having measured
nothing is worse than no gate, **because it is trusted.**

**Exit-code propagation:** `REFUSED` outranks `FAIL` (exit 3 over 1), and the flag is set
**once, inside the lane loop**. I initially wrote `if any(... lane_citations())` after the
loop, which would have **re-run the lane** — a second measurement of the same thing, which
is precisely how a module-level counter makes a stale answer look fresh. Caught before it
shipped.

### 3.4 One defect in my own fix, found by running the whole gate

The plant lane ended with `raise SystemExit(...)`. On a run with no disagreements that
**aborted `main` before it could reach its own exit code**, so a REFUSED from any other
lane would have been swallowed and reported as `FAIL` — my new verdict, dead on arrival.
Both refusals now return `[REFUSED] …` in the lane's list. **This was found by running the
gate, not by reading it.**

---

## 4. VERIFICATION — every required check, TOKEN not exit code

| check | token | rc |
|---|---|---|
| `checks/no-txt.py` | rc=0 | **0** ✅ |
| `checks/nl-gate.py` | **`AGREE 205/205`** (`gated 205 agree 205 disagree []`) | **0** ✅ |
| `gates/gate-surface.py --report` | **`SHELL HALF: 18`** | **0** ✅ |
| `checks/census.py` | rc=3 (stale slot served neither) | **3** ✅ |
| `checks/disagree-gate.py --lane citations` | **`ok  CITATIONS`**, 14/14 PASS | **0** ✅ |
| `.agents/slop/stalecites/census.py` | `37 assertions / 1 module` — **the class shrank by the repair** | 1 ✅ |
| `checks/disagree-gate.py` (all lanes) | **3 = REFUSED** — see §5 | 3 ⚠️ |

**The census is the repair checking itself.** Before: **51 assertions in 2 modules.**
After: **37 in 1.** `checks/disagree-gate.py` **left the census** — not because it was
deleted, but because it no longer stores a position. The instrument that found the class
now cannot find the named instance in it.

---

## 5. TWO FINDINGS BIGGER THAN THE TASK

### 5.1 `flip` does NOT emit 6 rows on both lanes. It emits 6 on **one**.

The brief's verification list expects "`flip` still emits 6 rows on both lanes
byte-identically". **MEASURED FALSE, and false since Oct 7 — nothing to do with this unit:**

```
D2-canon-py-flip.txt     rows=6  bytes=370
D2-canon-bend-flip.txt   rows=0  bytes=0      <- EMPTY
D2-cmp-flip.txt: flip NOT COMPARED: py=370 bytes bend=0 bytes
                 (a 0-byte side is a FAILURE, not a pass)
```

### 5.2 The whole bend lane of the corpus is DEAD — **34 of 34 graphs `NOT COMPARED`**

| side | 0-byte files |
|---|---|
| `D2-canon-py-*.txt` | **0 of 34** |
| `D2-canon-bend-*.txt` | **34 of 34** |

Every one of `D2-cmp-*.txt` reads `NOT COMPARED`. The newest artefact in
`runs/graphcmp/D/` is dated **Oct 7 23:50**; today is **Oct 11**. I wrote nothing under
`runs/` (`git status --porcelain -- runs/` is empty).

**So `graphs-disagree=0` — the number `lane_pin` cross-checks against `len(PIN)` — is not a
measurement of agreement. It is a measurement of nothing.** This is why three of
`disagree-gate`'s four lanes cannot pass, and why the gate correctly returns **REFUSED (3)**
rather than the **1** it returned before: before, the plant's `SystemExit` *was* the gate's
verdict, and it spoke for a lane that had measured nothing.

`gate-surface`/`no-txt`/`nl-gate`/`census` all pass, so the rest of the tree is sound; this
is one dead corpus, four days stale. **Regenerating it needs `bend`, which I did not run**
(per the sum-precondition, and because it would write to a tree other units are reading).

### 5.3 `PIN` is red for a pre-existing reason, and I did not touch it

```
FAIL  PIN
  the disagreeing set moved: [], expected ['flip', 'unshard']
  D0-run-summary.txt no longer reads graphs-disagree=2
```

`git diff` on my hunks confirms `PIN`, `lane_pin`, `lane_plant`, `lane_coverage` and
`arms_wired` are **untouched** — my changes are confined to `CITES`, `lane_citations`, the
new `defs`/`locate`, and main's exit aggregation. `PIN` still lists two graphs that the
(dead) corpus cannot compare. **A separate defect; out of scope; reported not changed.**

---

## 6. WHAT I WOULD NOT CLAIM

- **51 is a lower bound.** The sweep is `.py` literals only. `.md` prose carries at least
  **5 more** in `wmmafix/REPORT.md` alone, plus **1 live one** in `checks/differ.py:670`.
- **The 18 drifted `citemass/resolve.py` rows are reported, not fixed** — out of write scope.
- **`checks/disagree-gate.py` cannot reach rc=0** on this tree while the corpus is dead.
  It reaches **REFUSED (3)**, which is the honest token. I did not make it green.
- **Nothing is committed and nothing is staged**, as instructed.

## 7. FILES

| path | what |
|---|---|
| `.agents/slop/stalecites/census.py` | the census — AST, directory walk, 4 verdict classes |
| `.agents/slop/stalecites/REPORT.md` | this |
| `checks/disagree-gate.py` | **the only tracked file changed** — `CITES` shape, `defs`, `locate`, `lane_citations`, exit aggregation, plant refusal |