# verdictcollide -- two owners, one integer, two names

**Unit:** `verdictcollide`. Python-only tooling. Nothing committed, nothing staged.
**Date of readings:** 2026-10-07. Every number below carries its denominator and scope in the same
sentence, because the two classes this file fixes were found by quoting bare counts.

---

## 0. THE FINDING, AS MEASURED

Two tables in this tree give the integer `4` two different names, and a third thing -- the runner
-- charges gates **by that integer**:

| code | `gates/gatekit.py` (the owner) | `checks/wallcheck.py` | agree? |
|---|---|---|---|
| 0 | `PASS` | `PASS` | yes |
| 1 | `FAIL` | `FAIL` | yes |
| 2 | **absent** | `USAGE` | **no -- owner has no name** |
| 3 | `REFUSED` | `REFUSED` | yes |
| 4 | `SKIP` | `NO-ROW` | **no -- two names, one code** |
| 5 | `DEAD` | `DEAD` | yes |

`gatekit.VERDICT` is `{0:'PASS', 1:'FAIL', 3:'REFUSED', 4:'SKIP', 5:'DEAD'}` (read by importing
`gates/gatekit.py` by path, never re-spelled). **`SKIP` and `NO-ROW` are not synonyms in this
project's doctrine**: `SKIP` is "it could not run, so it measured nothing"; `NO-ROW` is "it ran, and
the row it was asked for was not there". Collapsing them destroys the difference between *nothing to
grade* and *graded and found nothing*.

---

## 1. THE CENSUS, BY AST DISCOVERY

`.agents/slop/verdictcollide/census.py`. Output: `tables.rows` (27 lines), `gate-surface.out`.

- **Population:** `gates/gates-pop.py:discover()`, **loaded by path** -- not a hand list, not a
  basename shape, not a suffix set. **132 discovered entries, 39 modules** at the reading above.
- **Discovery:** `ast.parse` of the **module body**; every module-level `Assign`/`AnnAssign` to a
  name containing `VERDICT` whose value is a dict literal of `int -> str`, read with
  `ast.literal_eval`. A table built at run time is not discoverable by any static read and is
  **not counted** -- stated so the denominator means what it says.
- **The subject's table is IMPORTED BY PATH** (`sys.path.insert(0,"gates"); import gatekit`) and read
  as `gk.VERDICT` / `gk.PASS` / `gk.SKIP`. Never re-spelled. Re-spelling it had already produced
  two `TypeError`s in this tree.

**DENOMINATOR: 14 verdict tables in 132 discovered entries (39 modules).**

| question | answer | scope |
|---|---|---|
| how many tables declare code `4`? | **1 of 14** | the 14 AST-discovered tables |
| of those, how many call it the owner's `SKIP`? | **1 of 1** (after this fix; was **0 of 1**) | the 1 table declaring `4` |
| how many declare code `2`? | **4 of 14** | the 14 AST-discovered tables |

**The 8 remaining colliding tables** (each has ≥1 `RENAMED` code), 10 renamed codes total across 8
tables, all on codes `0` and `1`:

```
checks/dup-census.py      0:OK      owner PASS      checks/no-txt.py         0:CLEAN  owner PASS
checks/env-precond.py     0:OK      owner PASS      checks/no-txt.py         1:RED    owner FAIL
checks/hermetic-census.py 0:OK      owner PASS      checks/oracle_f64.py     0:OK     owner PASS
checks/nl-gate-noguard.py 0:AGREE   owner PASS      gates/gate-surface.py    0:OK     owner PASS
checks/nl-gate-noguard.py 1:BROKEN  owner FAIL      gates/gate-surface.py    1:RED    owner FAIL
```

**I did NOT rename these 9 tables' `0`/`1`.** They are all outside my declared scope, and unlike code
`4` none of them is a *disagreement about a verdict's meaning* -- `OK`/`RED`/`CLEAN`/`BROKEN`/
`AGREE` are per-gate display words for the same two codes, and no runner mis-reports them. The
difference matters and is the reason this is a finding rather than a mass rename: **code 4 had two
words that mean DIFFERENT THINGS** ("could not run" vs "ran and found nothing"), whereas code 0's
two words mean the same thing. I priced that in §5.

---

## 2. WHAT `.agents/slop/hooks/run.py` ACTUALLY DOES -- MEASURED, NOT READ

`run.py` is 208 lines and tracked. **It charges by integer, and this is the live coupling**:

- `:70` `PASS, FAIL, REFUSED, SKIP, DEAD = (_GK.PASS, _GK.FAIL, ...)` -- read from the owner.
- `:71` `charge = _GK.charge`.
- `:142` `return charge(r.returncode), head, ...` -- **the integer is the whole message**.

**The collision is LATENT for code `4`, LIVE for code `2`.** Measured:

- **Code 4 is unreachable under the runner.** The runner builds argv as `[python, path, *extra]` with
  `extra` being `()` (`:179`) or `("--report",)` (`:186`). It **never passes an id**. wallcheck's
  exit `4` requires `want` (a named id) and is only produced by `report()` when `want and not sel`.
  MEASURED: `wallcheck.py` with no argv returns **1**, and with `--report` returns **2** -- never 4.
  So no SKIP/NO-ROW disagreement reaches the runner today. **A SKIP is not a crash**: it is
  *latent*, not *absent*.
- **Code 2 is reachable and already happening.** `wallcheck.py --report` returns **2** because
  wallcheck has no `--report` flag and **argparse's own usage error exits 2**. The runner's
  `--report-gate=` path builds exactly that argv. MEASURED live:
  `run.py --run --only=wallcheck` charges wallcheck's no-arg run as **FAIL=1**. And `gatekit.charge(2)`
  is **REFUSED(3)**, which is a *correct* refusal -- but only because 2 is unassigned, not because
  anything agreed 2 means USAGE.

---

## 3. THE RESOLUTION: (b), and it is a RENAME, not a list entry

**I chose (b) `wallcheck` renames `4` to `SKIP`.** Option (a) -- teaching `gatekit` a sixth name --
was rejected on measurement:

- **A sixth verdict contradicts the owner.** `run.py:201` prints **"Do not add a sixth verdict."**
- **The count would not stay at six anyway.** `checks/env-precond.py` and `gates/gate-surface.py`
  both declare `2: "REFUSED"`, and `2` is **absent** from the owner's vocabulary while `REFUSED` is
  **already code 3**. Adding `NO-ROW` to the owner would leave code 2 with two live claimants and
  `REFUSED` meaning two different integers -- **worse than the 1-table defect I was sent to fix**.
- So the naming power belongs to the owner, and `wallcheck` was the only table exercising it.

**Implemented as a rename in `checks/wallcheck.py`:** the `VERDICTS` entry `4: "NO-ROW"` became
`4: "SKIP"`, and the printed sentence now says `SKIP, not CLEAN` while **keeping the distinction in
prose**, which is where it is actually readable:

```
NO ROW MATCHES ['NO-SUCH-ID'] -- SKIP, not CLEAN: a guard over an empty population has measured nothing.
```

**All six exits still reach their declared values** (MEASURED by RUNNING, after the rename):

```
[--selftest] rc=0   [--plant fail] rc=1   [--ledger /no/such/walls.tsv] rc=2
[--plant story] rc=3   [NO-SUCH-ID] rc=4   [--plant dead] rc=5
```

**No list was added anywhere.** The census reads the owner's table by import; `wallcheck`'s table is
a declaration that already existed. I added **zero** mapping rows to any file.

### The blind spot I also had to close: `gates/gate-surface.py` clause V

Clause V charged **UNOWNED** codes (`rc not in vocab`) and was **blind to a different NAME for a
known code** -- MEASURED before the fix: its output contained **5 UNOWNED lines and 0 occurrences of
`NO-ROW`**. A table that names a code the owner *does* have a name for, differently, is not
UNOWNED, so nothing fired. That is the exact shape of this defect, in the instrument built to find
it. I added the `RENAMED` branch (`gates/gate-surface.py:389-402`), which compares the **name**:

```
V EXIT CODES: 4 declared verdict code(s) that `gates/gatekit.py` has no name for, and 10
   declared code(s) the owner HAS a name for, under a different one.
```

**MEASURED: RENAMED charges went 0 -> 10, and the counter and print line were added together** --
adding the branch without declaring `renamed` would have been a `NameError`, i.e. the `DEAD` class
this report is about.

---

## 4. DECISION ON `2 USAGE` -- **do not assign it; it is LIVE and REFUSED is correct**

**This is the sharpest thing in the audit, and it argues against adding a name.**

- **4 of 14 tables declare `2`** (scoped to the 14 AST-discovered tables), and they **split 2/2**:
  `checks/dup-gate.py` and `checks/wallcheck.py` say `USAGE`; `checks/env-precond.py` and
  `gates/gate-surface.py` say **`REFUSED`**. So the tree has **two live claims on code 2** -- the
  opposite of the code-4 case, which had one dissenter against an owner.
- **`REFUSED` is already code 3** in the owner's vocabulary. Assigning `2 = REFUSED` would make one
  word mean two integers, which is strictly more dangerous than 2 having no name at all.
- **The hazard the brief names is real and I confirmed its direction.** Clause V reads
  *declarations*, so it finds `2` "declared and therefore fine" in the sense that a *declared* code
  looks intentional; the runner, which sees only `4`, must **guess**. A code **declared somewhere and
  unassigned elsewhere** is more dangerous than a code nobody declared -- and MEASURED, 2 is the
  **only** code in this population that is declared-but-unowned (4 of 14 tables, 4 UNOWNED charges).
- **It is LIVE, not latent**: `argparse` exits 2 on a usage error, and `run.py`'s `--report-gate=`
  path passes exactly such an argv. MEASURED: `wallcheck.py --report` -> rc 2 -> `charge(2)` =
  **REFUSED(3)**.

**Decision: leave `2` unowned.** `gatekit.charge(2)` already answers **REFUSED**, and REFUSED is
the correct doctrine for "a precondition was absent" -- the absent precondition here being a *valid
argv*. This is `verdict_of`'s existing, measured rationale, and inventing `USAGE = 2` would take a
code that is currently refused-by-correct-reason and make it *silently believed* by four tables that
do not agree on what it means. **I am not adding a name, and I am not renaming any of the four
`2`s -- they are outside my scope and they disagree with each other, so no single rename is correct.**

**The residual is reported, not hidden:** 4 UNOWNED charges remain in `gate-surface.out`. That is
data, and `--report` charges 0.

---

## 5. WHAT I GOT WRONG FIRST, AND THE BEFORE-VALUES KEPT

Four of my own errors, all found by measuring rather than reading. The rules require this first, and
three of the four are the *same classes* this report is about.

1. **`rc=$?` after a pipe to `tail` is `tail`'s status, not the gate's.** I read "all six plants
   return 4" and nearly built a whole report on it. **BEFORE-VALUES, kept:** all six plants return
   **0,1,2,3,4,5**. The "all return 4" reading was pure artifact.
2. **`$a` unquoted does not word-split in zsh.** My loop passed `--plant fail` as **one** argument,
   which `argparse` rejected -- producing the same fake 4. This has silently no-op'd twice in this
   session; here it manufactured a finding. Fixed with a `run()` function taking `"$@"`.
3. **My own census exited 1 while printing `PASS`, with `PASS` on stderr.** Cause:
   `vocab.get(0, 0)` indexed a **code->name** map by name and returned the **string** `'PASS'`, so
   `sys.exit('PASS')` printed it to stderr and exited **1**. Verified: `sys.exit('PASS')` -> rc 1,
   stderr `PASS`. **An inverted lookup on the owner's own table** -- the same mistake as the one I
   was sent to find. Fixed by reading `gk.PASS`/`gk.FAIL` **attributes**, which cannot invert.
4. **My `--check` was red at rest and could never pass.** I counted `MISSING` (a gate not declaring
   code 4/5) as a collision, so **14 of 14 tables collided**. A gate that can never be green teaches
   nothing. Fixed: `MISSING` is now `CANNOT-SAY`, reported as capability, never as disagreement.
   **This also means the "9 colliding tables" of §1 is a live count that moves as tables are added**,
   and the only stable number is the code-4 finding: **1 of 14 tables, 1 of 1 now agreeing.**

**Two commands I could not measure, and am not reporting as passes:**
- `gates/gate-surface.py` **without** `--report` **exceeded 120s** (it executes every plant). Its
  verdict is **NOT MEASURED**. I am not calling it red or green.
- `timeout` **does not exist on this macOS host**, so an earlier `timeout 180 gates/gate-surface.py`
  returned **no output and I initially read that as a silent pass**. It was `command not found`. An
  empty result from a missing tool is not a verdict.

---

## 6. VERIFICATION -- VERDICT TOKENS, AND THE BASELINE

| check | verdict token | note |
|---|---|---|
| `checks/cl-port-gate.py` | **PASS** (rc=0) | baseline preserved |
| `checks/nl-gate.py` | **AGREE 205/205** (rc=0) | baseline preserved |
| `checks/nl-gate-noguard.py` | **AGREE 205/205** (rc=0) | baseline preserved |
| wallcheck, 6 declared exits | **0,1,2,3,4,5 all reached** | unchanged by the rename |
| `census.py` | **PASS** (rc=0), stderr empty | after fixing bugs 3 and 4 |
| `gates/gate-surface.py --report` | **rc=0**, 7,123 bytes, stderr empty | redness is data |
| `gates/gate-surface.py` (no `--report`) | **NOT MEASURED** | exceeded 120s |
| `checks/no-txt.py` | **RED** (rc=1) | **NOT MINE -- see below** |

### `checks/no-txt.py` is red, and it is not my finding

**`checks/no-txt.py` exits 1 on 2 `.txt` files, both created 23:25 under
`.agents/slop/denominator/probe/checks/lanes/`** -- another agent's directory, outside my scope,
created **after** my last read of the baseline. MEASURED: my own files are only
`census.py`, `tables.rows`, `gate-surface.out` (all `.py`/`.rows`/`.out`). I did **not** delete
them, because deleting another agent's in-flight artifacts is exactly the `.agents/slop/` sweep that
`AGENTS.md` records as having destroyed instruments. **I report this rather than suppress it**, and
I make no claim that `no-txt` was green before my change -- I did not measure it before those files
existed.

### Also measured, and left alone

`checks/no-txt.py` prints a **carve-out failure**: `checks/dup-census.py`'s `SLOP` cache is
`NameError: name 'SLOP' is not defined` at read time, so its files are **reported** rather than
excused. `checks/dup-census.py` is outside my scope and another agent is editing `.agents/slop/`;
I report the defect and do not touch the file.

---

## 7. FILES TOUCHED -- ALL INSIDE SCOPE, NOTHING STAGED, NOTHING COMMITTED

- `checks/wallcheck.py` -- `4: "NO-ROW"` -> `4: "SKIP"`, plus the comment that records why.
- `gates/gate-surface.py` -- the `RENAMED` branch, its counter, and its print line.
- `.agents/slop/verdictcollide/census.py`, `tables.rows`, `gate-surface.out` -- new, under my unit dir.

**Not touched:** `gates/gatekit.py` (I did not need to change the owner's vocabulary -- that was
option (a), and §3 explains why it is rejected), `.agents/slop/hooks/run.py` (its `charge` was
already correct; the defect was upstream of it), and everything else in the tree.
`git status` shows `M checks/wallcheck.py`, `M gates/gate-surface.py`,
`?? .agents/slop/verdictcollide/` and **no staged changes**. I ran no `git add`, no amend, no rebase.

### Did the tree already own the answer?

**A fourth check does not exist.** `grep -rln` over `checks/`, `gates/` and `.agents/` for this
class (`verdictcollide`, `verdict collide`, `collision class`, `two owners`) returned **nothing**.
`gate-surface.py` clause V owned the *unowned-code* half and was blind to the *name* half, which is
what §3 fixes. So the census is new, and it is what found the 8 other renamed-code tables that
clause V now also charges.