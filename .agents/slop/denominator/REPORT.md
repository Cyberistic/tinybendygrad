# denominator — the zero-denominator class, and the one line that closes it

**HEAD at measurement:** `f7be40994`. **Method:** `.venv/bin/python` only, no `bend`, no commits,
no `git add`. Population by walk (`os.walk` + `.py`), per `AGENTS.md` doctrine 1.

---

## 1. THE DAMAGE — **NO DATA WAS LOST, AND THE TRAP IS STILL ARMED**

> **This is the most important line in the report and it is a NON-finding: the 797 KB census is
> intact and byte-identical to `HEAD`. Nothing was lost. But nothing was FIXED either.**

Measured, before and after every run in this report:

| witness | sha256 | bytes |
|---|---|---|
| `HEAD` blob `bda97b7c` (`git cat-file`) | `88cf4751cfd69184…` | 797,251 |
| worktree `checks/dup-census.json` | `88cf4751cfd69184…` | 797,251 |
| my backup `denominator/dup-census.json.BACKUP` | `88cf4751cfd69184…` | 797,251 |

**It was restored before I arrived, and I did not lose it.** But `checks/dup-census.py` still owns
the defect verbatim, and `checks/lanes/` — its entire population — **is not in git at all**:

```
$ git ls-tree -r HEAD --name-only | grep -c 'checks/lanes/'
0
```

So the trap is one restoration away. Today the only thing standing between the tree and a second
`[]` is that `.agents/slop/eq/eq-census2.py` happens to be absent, which trips `refuse()` at
`dup-census.py:74`. That is a **coincidence, not a guard** — a missing *file* is refusing the
gate for a reason unrelated to the missing *population*. Restore that one input (24,098 B,
recoverable from `371cc64c9^`, verified) and the gate goes straight through to the write.

### I REPRODUCED THE DESTRUCTION IN AN ISOLATED PROBE TREE

The real census was never at risk: I seeded the probe's copy from the worktree, built a wrapper
`.venv/bin/python` because `oracle_py.py:99` refuses an oracle whose `tinygrad` resolves outside
the sandbox tree, and ran the **unmodified** gate:

```
$ .venv/bin/python probe/checks/dup-census.py --all
rc=0                                   <-- GREEN OK
TOTAL over 0 lane texts of 0 ports
  DENOMINATOR: 0 of 0 lane texts carry at least one duplicate name …
census: 797251 B -> 2 B                <-- content: []
```

**rc 0, `0 of 0`, and 797,251 bytes replaced by `[]`.** Confirmed. The probe tree has been
stripped of its 30 MB `tinygrad` copy (it would have been counted by `unowned.py`); the restored
inputs and the scripts to rebuild it remain under `denominator/probe/`.

### WHY IT WAS SILENT — the file names its own defect in a comment

`dup-census.py:203-208`, verbatim:

> *"the first symptom is a census that reports ZERO rows … it is SILENT: every count is a real
> int and all of them are 0, and a census of 0 rows over 1 lane reads exactly like a clean lane."*

A comment describing the exact defect, on the file that has it, that did not prevent it. That is
the seventh member of `AGENTS.md`'s table — and the first one where the prose is *more* correct
than the code it describes.

---

## 2. THE POPULATION, BY DISCOVERY

**Scope, stated because `coindependent`'s 5 and `prune4`'s counts were both "correct for their
scope" and meaningless without it:** roots `checks/`, `gates/`; excluded `.agents/`,
`references/`, `node_modules/`, `.git/`, `.venv/`, `__pycache__`. **127 `.py` files walked.**

Three passes, because the first two were wrong and I have to say so.

| pass | instrument | yield | verdict |
|---|---|---|---|
| 1 | `scan.py` — count near a verdict token | **179 lines / 52 files** | **a NET, not a population** |
| 2 | `scan2.py` — population built ∧ count reaches a verdict | **30 files** | usable |
| 2b | `scan2.py`'s zero-guard classifier | **misclassified both ground-truth cases** | **discarded** |
| 3 | `scan3.py` — measured against the tree | **5 reachable, 1 really broken** | **this chose the tranche** |

**The classifier failed twice, in opposite directions, and I am reporting that rather than the
number it printed.** First version scored `if not (REPO/"pyproject.toml").is_file(): refuse()` as
a denominator guard — so it cleared `checks/dup-census.py`, the very gate this report is about.
I tightened it and it cleared **0 of 29**, because `dup-gate.py`'s `bad.append(…)` is a verdict
change it could not see. Validated against the two cases I know by hand:

```
checks/dup-census.py   want=NO   got=NO    OK  (empirically rc=0 over 0 of 0)
checks/dup-gate.py     want=yes  got=NO    *** MISCLASSIFIED ***
```

**A classifier that cannot classify the two instances a report is built from is not a census** —
it is doctrine 1's seventh entry again, wearing a different hat. So the tranche was chosen by
`scan3.py`, which asks the tree instead of the regex: for each candidate, resolve its literal
population source and **count what it actually yields today**.

### The named population: 5 candidates can go vacuously green, **1 really can**

| gate | state | why |
|---|---|---|
| **`checks/dup-census.py`** | **REACHABLE, VACUOUS** | **`checks/lanes/` absent → `0 of 0` → writes `[]` → rc 0. PROVEN.** |
| `checks/differ.py` | REACHABLE | only its `.tmp.*` / `D1-stability-*` scratch patterns. Its real population is `graphcmp.GRAPHS`, populated. |
| `checks/disagree-gate.py` | REACHABLE | `D1-graph-*.txt` on an absent runs tree — but **fails closed**: `set(one_sided) != SUBSTITUTION_ARTEFACTS` → empty ≠ declared → **red**, not green. |
| `gates/gates-pop.py` | REACHABLE | `gates/*.sh` = 0 with **62** `.py` beside it. **Genuine zero, and it is the finding.** |
| `gates/retention-check.py` | REACHABLE | `iterdir()` on a CLI-supplied directory — caller-declared, not swept. |

**So the answer to "how many?" is 1, and that is the answer the measurement gives, not the
answer I wanted.** I expected nine. `scan2.py` offered 30 candidates; five can reach an empty
population; one of those five turns a vacuous zero into a green verdict **and** destroys tracked
data. Reporting "30" or "5" would have been a count with no names, which is the defect.

---

## 3. THE FIX IS A SHARED ASSERTION — **(a)**, and here is the bill

**Chosen: (a) one helper, `checks/denominator.py`, loaded by path. 2 files touched.**

| option | files | why not |
|---|---|---|
| **(a) shared helper** | **2** | **chosen** |
| (b) lint flagging bare `len()` in a verdict | 1 + N fixes | flags the **symptom**; `dup-census.py`'s defect is `CACHE.glob()` over an absent dir, which contains no `len` in the offending line. A lint that misses the proven instance is decoration. |
| (c) per-gate | 30 | a second copy of a rule with no generator. `AGENTS.md`: *"a second copy is a contract with no generator and rots without anyone noticing."* |

`checks/coindep.py` states the precedent in its own header — *"This module is the
`gates/gendirs.py` fix — a single declaration, loaded by path"* — and `rebase-gate.py:162` is the
exact idiom used here (`sys.path.insert` + `import` for a same-dir helper). I used the house
idiom rather than `importlib`, because it is two lines instead of five and this project's own
`.agents/slop/rebase-gate.py` already does it.

**It is one assertion, split along the line where it actually bites** — and the split is what
keeps genuine zeros safe:

- **`enumerate_population(source, pattern, what)`** — for **inputs**. Refuses *only* when the
  source is not a readable directory, i.e. when **nothing was walked**. Never fires on a source
  that exists and is legitimately empty.
- **`require_denominator(found, what, source)`** — for **divisors only**. Refuses on **any**
  zero, because at a divisor `0 of 0` is an undefined ratio, not an answer.

---

## 4. THE TRANCHE — **1 GATE + 1 HELPER**, chosen by the measurement

`bendwire` landed three sites instead of thirty-seven: *"A REWRITE OF THE EXECUTOR CANNOT BE
BISECTED."* Same reason, and here the measurement is unusually decisive.

**Landed:** `checks/dup-census.py` — the only gate with a *demonstrated* zero denominator **and**
a tracked-artifact write. It is also the file that already documents the defect in a comment, so
the fix lands beside its own autopsy.

**Left, by name, with the reason:**

| left | reason |
|---|---|
| `checks/corpus-figure.py` | **the best next tranche.** `len(names)` at `:275-276` is a real divisor with **no floor** — `0 of 0 ops reached` would still `return 0` if `dev_ok and built == len(GRAPHS) and health_ok`. It is excluded from *this* tranche only because `scan3` measured `len(names) = 77`, so it is **not reachable today**. Fixing a reachable bug and an unreachable one in one change is not a tranche. |
| `checks/sweep.py:917`, `checks/slop-declare.py:278,301`, `checks/txt-owners.py:203`, `checks/coverage.py:121,123`, `checks/bounded.py:409`, `checks/devgate.py:522` | all carry the `WRITE` surface, but `scan3` measured their populations **populated**. No defect is demonstrated, so wiring them now is converting *on suspicion*, which is what the brief warns against. |
| `checks/differ.py`, `checks/disagree-gate.py`, `gates/gates-pop.py`, `gates/retention-check.py` | **already correct**, measured: fails closed, or the zero is genuine. Adding an assertion here would be a false positive. |

---

## 5. THE PLANT — and it denominates zero on purpose

Six tests, all against the probe tree, all re-runnable. `t1.err`, `t2.err`, `t3.out` retained.

| # | condition | verdict | census |
|---|---|---|---|
| **T1** | **PLANT: `checks/lanes/` ABSENT** — the vacuity | **rc=3 REFUSED**, `enumerate_population` | 797,251 B **intact** |
| **T2** | **PLANT: `checks/lanes/` PRESENT BUT EMPTY** — read it, found nothing | **rc=3 REFUSED**, `require_denominator` | 797,251 B **intact** |
| **T3** | populated with 2 lane texts | **rc=0**, prints `DENOMINATOR: 0 of 2` | rewritten, 2 lanes |
| **T4** | **genuine zero**: `enumerate_population(gates,"*.sh")` | **0 entries, NO refusal** | — |
| **T5** | the same 0 **at a divisor** | **rc=3 REFUSED** | — |
| **T6** | non-zero divisor (`62`) | returned 62, no refusal | — |

T1 and T2 are the plant: **the assertion catches the exact condition zerogate reported**, and the
second plant — an *existing but empty* source — is the one a single `enumerate_population` call
would have missed. Both refusals leave the census at 797,251 B. T3 shows the normal verdict
returns and the write happens.

**And note T3's own output:** `DUPLICATE NAMES: 0 over 0 rows`. That is a **numerator** zero over
a populated denominator, printed normally, untouched. The assertion is not a brake on small
numbers — it is a brake on undefined ones.

### WHAT A GENUINE ZERO LOOKS LIKE, AND HOW THE ASSERTION TELLS IT FROM A BROKEN ONE

This is the part that decides whether the fix survives the week.

A genuine zero has **a denominator that is independent of the count**. `gates/gates-pop.py`
enumerates `gates/*.sh` and finds **0**, beside **62** `.py`. So `0 of 62 shell gates remain` is a
*defined, true, meaningful* figure — the shell form really is retired. Its zero is a **numerator**
over a **declared** denominator.

`dup-census.py`'s zero has **no independent denominator at all**: `lanes` *is* the divisor
(`TOTAL over N lane texts`, `N of M`). Nothing else bounds it. A zero there means the gate
examined nothing, so the ratio is `0 of 0` and the two possible worlds — *"no duplicates exist"*
and *"no lanes were read"* — are **byte-identical in the output**.

**So the discriminator is not "is it zero". It is "is this zero divided by anything".** And that
is a property of the **call-site**, which is why the helper does not try to infer it:

- `enumerate_population` **never** judges the count — only whether the walk happened.
- `require_denominator` **always** judges it — because its callers have already declared, in
  code, that this number is a divisor.

**An assertion that cannot tell a genuine zero from a broken one is a gate with a false
positive, and a false positive gets deleted within a week — and then the gate is back to green
over nothing.** So I did not write one. I wrote two functions with different contracts, and the
genuine-zero case is the one that is *never refused by construction*.

**I am stating the residual risk rather than hiding it:** the call-site carries the judgement, so
a future caller can call `require_denominator` on a numerator and get a false positive. That is
real, and it is why the rule belongs in a helper with a 20-line docstring rather than in a lint
that fires without anyone reading. The mitigation is that each refusal **names what it refused
and why**, so a wrong call is one obvious diff away from being corrected — rather than a green
`OK` nobody ever looks at again.

---

## 6. IS A ZERO DENOMINATOR ALWAYS A DEFECT? — **NO, AND THAT IS THE WHOLE ANSWER**

Of the 5 reachable sites, measured:

- **1 is a defect**: `checks/dup-census.py`.
- **1 is a genuine zero and must never be flagged**: `gates/gates-pop.py`, `0 of 62`.
- **1 is fail-closed already**: `checks/disagree-gate.py` — empty ≠ declared → red.
- **2 are caller-declared or scratch**: `checks/differ.py`, `gates/retention-check.py`.

So **1 of 5**. A blanket "zero denominator is a defect" rule would have produced a false positive
on `gates-pop.py` and taught the tree that this assertion cries wolf.

`wantwire` made `UNSET` a refusal so a graph with no verdict could not read as an answer; `msgdiff`
refuses a claim it cannot judge. Both are right — and both are right *because their zero is a
denominator*, not because zero is always bad. `text-owners.py` reporting "0 files are unowned" is
a real, good result **provided its denominator is not 0** — it has one: it enumerated the files.

**The generalisable rule, and it is the one I would want read six months from now:**

> **A ZERO NUMERATOR IS A FINDING. A ZERO DENOMINATOR IS AN ABSENCE OF A FINDING. AND A GATE THAT
> CANNOT TELL WHICH ONE IT IS HOLDING HAS NO VERDICT TO REPORT.**

---

## 7. FILES

| path | what |
|---|---|
| `checks/denominator.py` | **NEW.** The shared assertion. 2 functions, 3 exits, no state. |
| `checks/dup-census.py` | 2 call sites + import. Working tree only — **not committed, not staged.** |
| `denominator/scan.py` `scan2.py` `scan3.py` | the three discovery passes, with the two failures recorded |
| `denominator/sites.tsv` `reach.tsv` `scope.rows` | the populations, by walk |
| `denominator/probe/` | the reproduction tree + restored inputs (`eq-census2.py` from `371cc64c9^`) |
| `denominator/dup-census.json.BACKUP` `HEAD.dup-census.json` | two independent 797,251 B witnesses of the intact census |

**Nothing was committed and nothing was staged.** `git ls-tree -r HEAD` was used throughout, never
`git ls-files` — and that mattered: `git diff checks/dup-census.py` compares worktree to **INDEX**
and reported a `VERDICTS = {0: "OK", 3: "REFUSED"}` block as mine. It is **another agent's
uncommitted change**. `git diff HEAD --` shows the truth: **my 23 insertions, 2 deletions**; the
`VERDICTS` block is not mine and a reviewer will see both in the same diff.

## 7b. ⚠ LIVE HAZARD FOUND WHILE VERIFYING — SOMEONE ELSE'S INDEX ENTRY IS AN **EMPTY** BLOB

I never ran `git add`. But `git status --porcelain` reports ` A checks/denominator.py`, and the
index says:

```
$ git ls-files --stage -- checks/denominator.py
100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0	checks/denominator.py
```

`e69de29b` is **the empty blob**. This is an intent-to-add (`git add -N`) entry recorded by
another agent's tooling while the file was being written — which is also why
`git diff --cached --name-only` reports **0** files and hides it.

**Why it matters:** a commit taken from that index lands `checks/denominator.py` as a **0-byte
file**, and then `dup-census.py` — which now imports it — dies with `ImportError` and a
traceback. That is rc 1 with no denominator, which is precisely the failure mode this report is
about, arriving by a different road.

**I did not touch it.** My brief forbids index operations, the index is shared and has reset
repeatedly tonight, and unstaging a path another agent may be mid-commit on is how work gets
lost. **Whoever commits next should run `git add checks/denominator.py` (or
`GIT_INDEX_FILE=.git/agent-index git add checks/denominator.py`) so the index carries the real
91 lines, not `e69de29b`.** Flagging rather than fixing, for the same reason `zerogate` reported
this class instead of quietly repairing it.

---

## 8. WHAT I DID NOT DO, AND THE ONE THING NEXT

- **Did not restore `.agents/slop/eq/eq-census2.py`** into the live tree. It is the input that
  arms the trap; restoring it into the tree under sweep while other units work is not my call.
  It was restored **only inside the probe tree**, which is what let me prove the damage without
  touching the census.
- **Did not wire the other 29 candidates.** §4 names each and says why.
- **Did not touch** `AGENTS.md`, `tinybendygrad/`, or any gate body beyond the two call sites.
- **Did not commit, stage, amend, rebase, force-push, or `git add`** anything.

**The one thing next:** `checks/corpus-figure.py:275-276`. `len(names)` is a divisor with no floor
and `0 of 0 ops reached` would still return 0. It is not reachable today (`len(names) = 77`), so
it is a **second tranche, not this one** — and it is the only site I would argue is worth the next
change on its own.