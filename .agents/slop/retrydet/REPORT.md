# retrydet — a retry that cannot tell a crash from an answer

**Unit:** `retrydet`. **Tree:** `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`.
**HEAD at every measurement below:** `c8d543324`, **2026-10-14T17:24:14Z**.
**Touched:** `.agents/slop/graphcmp.py` (edited), `.agents/slop/retrydet/` (new, untracked).
**Committed:** nothing. **Staged:** nothing. `git ls-tree -r HEAD` is the tree here; no `git add`
of any kind was run.

> **Observed live, worth reporting up:** `git diff --cached --name-only` (a READ-ONLY index
> read, run 2026-10-14T17:5xZ) names **2 paths** — `checks/cites-census.py` and
> `.agents/slop/precision/claims.rows`. **Neither is mine.** Something staged into git's index
> during this session; `checks/cites-census.py` is one of the two files another unit is editing
> per my brief. Nobody committed, so nothing is lost — but **a bare `git commit` by any unit from
> here would take another unit's staged work with it**, which is exactly the hazard AGENTS.md
> describes for `jj`'s colocated snapshots. **Whoever commits should use
> `GIT_INDEX_FILE=.git/agent-index` and name paths explicitly.** I did not touch either file.

## VERDICT: **PASS**

| check | token | how |
|---|---|---|
| `checks/no-txt.py` | `CLEAN` (rc 0) | run 2026-10-14T17:5xZ, after all three files were written |
| `ast.parse` on all three changed/added files | ok | `.venv/bin/python -c`, no execution |
| `graphcmp.py --help` | rc 0 | argparse only, no `bend` |
| `.venv/bin/python .agents/slop/retrydet/control.py` | `CONTROL: OK` | 10/10 rows, 3/3 mutants caught, 0.13 s, zero subprocesses |
| census instrument | rc 0 | 0.2 s, 36 rows |

`SKIP`, and this is the one thing I could not do: **no `bend` process was run.** The change is
therefore *not* end-to-end proven — see §6, which says so plainly rather than burying it.

---

## 0. HOW MY OWN MEASUREMENT WAS WRONG — five times, with the before-values

Sixteen instruments this session reported `0` or a clean number because they could not see.
This one did too, five times, and every one of the five would have reported a **clean zero**.

1. **The census died on its first file.** `census.py:93` read `c.func.attr` on a bare `run(...)`
   call and raised `AttributeError: 'Name' object has no attribute 'attr'`. It printed **0 rows**
   and a wrapper that swallowed the traceback would have reported *"the tree has 0 retry loops"*.
   This is the `DEAD` verdict in the five-verdict vocabulary: it ran and emitted nothing.
2. **The census was blind to its own subject.** Evidence was collected from `ast.Compare` nodes.
   `if not rows:` — which is **how the subject itself is written** — is
   `ast.UnaryOp(Not, Name)` under an `ast.If` and contains **no `Compare` at all**. The
   instrument could not see the exact class it was built for. Before-value: `empty=True` on
   **0** of 120 loops.
3. **The census had the polarity backwards.** It skipped every branch whose body *left* the
   loop, so `if rows: return rows, notes` — where the empty case is the **fall-through** — was
   scored `continues_on_empty=False`. Before-value: the subject scored `False` for the defect
   it *is*.
4. **The census could not see the FIX it existed to find.** With call resolution in place it
   still read `names_the_crash=False` on the fixed file, because the token lives in a module
   **constant**, one hop past the callee. Before-value, same instrument, same file,
   before-and-after: `False / False`. A census blind to its own remedy is doctrine 1's seventh
   member wearing a different hat.
5. **The census died twice more on its own output plumbing** — `ast.walk` handed the `ast.Pass`
   *class* (`'list' object has no attribute '_fields'`), then `comprehension.ifs` elements read
   as if they had `.test` (`'Call' object has no attribute 'test'`), then the `(text, leaves)`
   tuples passed to a function expecting text (`compile() arg 1 must be a string, bytes or AST
   object`). Each died having emitted **0 rows**.

The fix for all five was the same discipline the tree already names: the instrument reads what
the writer wrote — literals, callees, and **declared constants loaded from the module's own
assignment** — instead of re-typing the shape. Every failure above was an instrument that
**re-declared** a population instead of loading it.

**One more thing I got wrong, before I measured it:** I suppressed stderr on a census run
(`2>/dev/null`), got an empty file, and the JSON reader raised `JSONDecodeError`. The run was
`DEAD` and I had thrown away the reason. Receipt in the transcript above.

---

## 1. THE DISTINGUISHER — found by reading the PINNED COMPILER, not by provoking one

**I did not run `bend` and did not cause a stack overflow.** The answer is in
`references/bend` at **v2.0.37** (`git log -1` → `4ff8545 "Bend 2.0.37 (#1539)"`), and the
compiler ships its own regression for the failure:

| citation | what it says |
|---|---|
| `references/bend/bend2/comp.ts:159-167` | `ERRS` is the runtime fail-stop table; `ERRS[7]` is the literal `memory fault (machine stack overflow?)` |
| `references/bend/bend2/comp.ts:3415` | `#define ERR_DEEP 7` — the code that text is filed under |
| `references/bend/bend2/comp.ts:3642-3645` | `err_fail`: `fflush(stdout); fprintf(stderr, "bend: %s\n", msg); _exit(1)` |
| `references/bend/bend2/comp.ts:3649-3651` | `err_trap(int sig) { err_post(NULL, ERR_DEEP); }` — called from the SIGSEGV/SIGBUS the guarded mmap raises |
| `references/bend/bend2/comp.ts:6337` | the interpreter lane converts a host `RangeError` into the **same** `ERRS[7]` string |
| `references/bend/bend2/main.ts:971` | `book_err`'s `RangeError` arm: `"Error: the machine stack overflowed (a deep recursion, or a literal too large to expand)"` |
| `references/bend/bend2/main.ts:325-326` | `cli_file`'s catch: `cli_say(2, ...)` → **fd 2**, `process.exitCode = 1` |
| `references/bend/tests/io/stack_fault_trap.bend:59-60` | the compiler's own test expects `#\|bend: memory fault (machine stack overflow?)` and `#\|exit 1` |

**So: a machine-stack overflow is NOT a signal death and NOT an empty stream.**
`rc` is **1** — never `-11`, `139`, `-9`. Both lanes print a **named line on stderr** and exit 1.

### `rc` cannot tell them apart, and here is the tree's own proof

| shape | `rc` | stdout | who produces it |
|---|---|---|---|
| stack overflow | 1 | empty | `comp.ts:3644` |
| **file does not exist** | **1** | **empty** | `Error: - message : no such file: …` |
| **`SOME PROOFS FAIL`** | **1** | **empty** | a type error in the driver |
| **`--check-only` on a CLEAN file** | **1** | present | graphcmp.py header trap 6 |
| **a legitimate 0-row answer** | **0** | header only | the probe ran; the graph has no arena nodes |

The middle two rows are not theory. **`runs/graphcmp/D/D10-zerorow-guard.txt.err`** — a pinned,
measured artifact — reads:

```
emit bend: 0 rows after 5 attempts -- a FAILURE, not a verdict:
  bend attempt 1: 0 rows, rc=1, stderr tail: SOME PROOFS FAIL Error: - message : no such file: .agents/slop/graphcmp-empty.bend bend 2.0.35 is available: run bend update
  … attempts 2, 3, 4, 5: byte-identical …
```

**Five identical attempts of a 554 MB process, for a file that does not exist.**
`.agents/slop/midrun/REPORT.md:80-85` already names the consequence: *"The guard is currently
certifying a missing file."*

### And stderr's mere NON-EMPTINESS is worthless

The same transcript's stderr **tail is the update notice**: `bend 2.0.35 is available: run bend
update`. `references/bend/bend2/main.ts:187-213` (`check()`) prints that on **any** run, once a
day. So:

* ❌ `rc != 0` ⇒ crash — false for every row above but the first
* ❌ `not stdout` ⇒ crash — false for a legitimate 0-row answer
* ❌ `stderr != ""` ⇒ crash — false on essentially every run
* ✅ **a compiler-emitted string that appears only on this failure ⇒ crash**

**`checks/bounded.py:135-139` already says the exit status is not the gate**
(`NO-VERDICT`: *"That is either a failure that printed nothing or `bend`'s machine-stack
overflow … the two are indistinguishable from here"*). It is right that they are
indistinguishable *from the exit status* — and it stops one step short of naming the thing that
does distinguish them.

### Two witnesses that disagree, stated rather than reconciled

* `gates/gatekit.py:135` — *"bend's machine stack overflow answers no stdout **and no error at
  all**."*
* the pinned v2.0.37 source — it prints `bend: memory fault (machine stack overflow?)` on stderr.

I **cannot adjudicate this**, and the reason is a fact about the tree:
`references/bend` is a **depth-1 clone** (`git rev-list --count HEAD` = **1**), so what 2.0.34 /
2.0.35 printed is not checkable from here. What *is* checkable is the pin: **at v2.0.37 the
failure is loud**, and `gatekit.py:135`'s claim is stale for it. `gatekit.py`'s *code* — the
warm check's `if not said and not (out.stdout or "").strip(): continue` (`:324`) and `_lane`'s
`if _said(r.stderr): break` (`:370`) — keys on **silence**, so on this pin it retries a shape
the compiler now names. **Reported, not edited** (`gates/` is off-limits to this unit).

---

## 2. THE RULE — which branch retries, which returns

`classify(rc, out, err) -> (rows, header, verdict)`, four verdicts, one per attempt:

| verdict | condition | what the caller does |
|---|---|---|
| **`RETRY`** | stderr carries a compiler stack-overflow string | try again, up to `TRIES` |
| **`ANSWER`** | `rc == 0` and the probe **printed** | **return the rows** |
| **`EMPTY`** | `rc == 0` and printed nothing | **raise on attempt 1** — an answer must not be retried |
| **`BROKE`** | `rc != 0`, no stack-overflow string | **raise on attempt 1** — bend named it |
| *(timeout)* | `subprocess.TimeoutExpired` | **raise, never retried** |

**A crash may retry. An answer must not. And a named failure must not, either.**

Two tightenings beyond the crash/answer split, both required by "an answer must not be taken
from a failed run":

* **`rows and rc != 0` ⇒ `BROKE`.** A torn run's partial rows would otherwise become a byte
  mismatch reported as a **port bug**. `gates/gatekit.py:370` already requires `rc == 0` for
  this exact reason (`if r.returncode == 0 and len(_lines_text(r.stdout)) == self.rows`).
* **`ANSWER` is "printed", not "printed a `#` header".** `--bend-probe` can point `emit_bend`
  at any file, and a probe with rows and no header is still an answer. `graphcmp-empty.bend`
  prints nothing, so both readings agree on the case `D10` exists to test.

**The failure direction is the point.** A stale token — the compiler renames the string at the
next pin, which it demonstrably does (2.0.34 → 2.0.35 → 2.0.37, visible in the D10 transcript)
— degrades to `BROKE`: a **loud failure**, never a silent green. Measured by mutant M4 below.

---

## 3. THE NUMBERS

**Measured 1.29 s / 554 MB per emission, 44 s for 34 graphs, 182 s for `differ.py run`, at
v2.0.37 — CITED from the brief, NOT re-taken by this unit** (running it is forbidden here). The
arithmetic is printed by `control.py` from the constants, not from prose.

### `tries: 5 → 3`

| | tries = 5 (before) | tries = 3 (now) |
|---|---|---|
| P(all attempts hit the flake), p = 1/20 | 1/3 200 000 | **1/8 000** |
| P(≥1 of 34 graphs gives up) | ~0.001% | **0.42%** |
| expected attempts per graph | 1.0531 | 1.0525 (**+0.006%**) |
| worst case per graph | 9 000 s | **180 s** |
| worst case, 34 graphs | 306 000 s (**85 h**) | **6 120 s** |

Attempts 4 and 5 divide a 0.42% residual by ~400 and cost **2.4× the worst case**. 3 is the knee.

### `timeout: 1800 → 60`

60 s is **46× the 1.29 s mean** and **6.4× the old 2.0.34 mean** (318 s / 34 = 9.35 s). A graph
taking 46× the corpus mean is not slow, it is a different machine, and `TIMED-OUT` is the
truthful name for that. **A timeout raises and is not retried**, so a too-tight bound costs a
loud failure and never a wrong answer.

**No single graph can now cost thirty minutes: the bound is 180 s.** Corpus worst case drops
from **85 hours to 1 h 42 m**.

---

## 4. THE CHANGE

`.agents/slop/graphcmp.py`, `+170 −30`. Both lanes — `emit_bend` and `debug_run` — now go
through **one** `classify` and **one** `attempt_note`, so they cannot drift into disagreeing
about what a crash is. A duplicated hand-written rule per lane would guarantee the drift.

Also fixed in passing: `emit_bend` carried its `probe` docstring **twice** (a dead second string
expression); and `attempt_note` now records the whole stderr rather than its last 160 chars,
because the D10 transcript shows the tail is the update notice — **a tail can hide the only line
that says what went wrong**.

No consumer breaks: `0 rows after 5 attempts` appears in `checks/differ.py:271,279` and
`checks/corpus-figure.py:152` as **comments and docstrings**, not as assertions; nothing parses
`emit_bend`'s message. `checks/lintable-gate.sh:53` has its own `$tries`.

---

## 5. PROOF THAT DOES NOT RUN THE PORT

**`.agents/slop/retrydet/control.py`** — 0.13 s, **zero subprocesses**, `CONTROL: OK`.

```
# ROWS: 10 of 10 shapes get the verdict they cite
# MUTANT M1 retry-on-empty (the defect being fixed): caught on 4 row(s) [5, 6, 8, 9]
# MUTANT M2 retry-on-exit-status: caught on 4 row(s) [5, 6, 8, 9]
# MUTANT M3 token read off stdout: caught on 3 row(s) [3, 4, 8]
# MUTANT M4 the token table emptied: 2 row(s) degrade to BROKE [3, 4] -- loud, never green
# BOUND tries=3 timeout=60s -> 180s worst case per graph, 6120s for the 34-graph corpus;
#       was 5 x 1800 = 9000s per graph (2h) and 306000s for the corpus (85h)
# CONTROL: OK
```

The ten rows live in `graphcmp.CRASH_CONTROL` and are **read by `selfcheck`** — a command
`differ.py run` already executes and whose verdict it already pins
(`selfcheck=# SELFCHECK: OK` in `runs/graphcmp/D/D0-run-summary.txt`). So the classifier is
gated by machinery that is already wired and costs **no extra `bend` run**. Rows 6 and 8 are
quoted verbatim from the measured D10 artifact and from `main.ts`.

**The four mutants are why this is a control and not a tautology.** Each is a mistake this edit
could plausibly have shipped, and each is caught by reading rows. M1 is the defect being fixed;
M4 is the stale-pin case, and it is the one that matters most — it fails **red**.

---

## 6. WHAT I COULD **NOT** PROVE

**The change is not end-to-end proven.** I did not run `bend`, so I cannot show that a healthy
graph still yields `ANSWER` through the real `subprocess.run`. What I *can* show is that
`classify` reads every stream shape the pinned compiler can produce correctly, and that the
answer branch requires only what a healthy run already does (`rc == 0`, printed something).

**The next `differ.py run` is the test, and someone else is running it.** It will move these:

* `graphs-agree` / `byte-identical` **34 / 34** and `selfcheck=# SELFCHECK: OK` must not move.
  If they do, this change is wrong and the table above says which row to read first.
* `D10-zerorow-guard.txt.err` should stop saying `after 5 attempts` for a **missing file** and
  name the cause on attempt 1. **If it still says 5 attempts, the token is stale and the pin
  moved — which fails red, as designed.**

Untested-by-me risk, stated: requiring `rc == 0` for the answer branch could turn a currently
green run red **if** `graphcmp.bend`'s completed run ever exits non-zero. `main() -> IO(Unit)`
exits 0 (`main.ts:312`), and `gates/gatekit.py:370` already requires it, but I did not execute it.

---

## 7. THE CLASS — census by AST, with denominators

**Population: `git ls-tree -r HEAD --name-only` at `c8d543324`, 2026-10-14T17:24Z — 7 154 paths,
of which 1 777 are `.py`.** The tree, not the worktree: `runs/` is `.gitignore`d
(`.gitignore:179`) and `git ls-files --others --exclude-standard` cannot see ~1057 ignored
paths for every untracked one.

**Class: a `for … in range(<attempt counter>)` loop containing a `subprocess.*` spawn.** A
`while` is excluded and said so. A corpus sweep (`for g in GATES:`) is excluded — its branches
are about that gate, not about whether to try again.

| # | measure | value |
|---|---|---|
| 1 | attempt-counter loops that spawn a subprocess, tracked `.py` | **36**, in **27** files |
| 2 | branch on the child's **output** (loop body, local) | **18** |
| 3 | branch on the child's **exit status** (loop body, local) | **17** |
| 4 | **name the crash** — resolved: loop body ∪ one call level ∪ declared module constants | **3** |
| 5 | name it **locally** (literal inside the loop's own test) | **1** |
| 6 | `timeout=` literals over tracked `.py` | **125** call sites, 25 distinct values |
| 7 | of those, `timeout ≥ 1800` | **13 × 1800**, 14 × 3600, 1 × 30000 = **28** |

**The three members of the class that name the crash:**

| file:line | bound | how |
|---|---|---|
| `.agents/slop/ga_mutate.py:45` | `range(8)` | the literal, in the test. *"Bend 2.0.34's machine stack is NOT deterministic here … RETRY it."* |
| `.agents/slop/graphcmp.py:2067` | `range(1, tries+1)` | **this edit** — token in `STACK_OVERFLOW`, reached through `classify` |
| `.agents/slop/graphcmp.py:2895` | `range(1, tries+1)` | **this edit** — `debug_run`, same `classify` |

**Before/after, same instrument, same population, same tree** (`git show HEAD:…` vs the
worktree file):

```
HEAD (before)        line=1952  out=True   st=False  names-crash=False
HEAD (before)        line=2759  out=True   st=False  names-crash=False
WORKTREE (after)     line=2067  out=False  st=False  names-crash=True
WORKTREE (after)     line=2895  out=False  st=False  names-crash=True
```

**So: 3 of 36 retry loops in the tracked tree can tell a crash from an answer, and 2 of those 3
are this edit.** The other 33 cannot, and 18 of them branch on the child's *output* — the exact
shape of the defect.

**Two siblings already knowing the answer, cited rather than credited to me:**
`gates/gatekit.py:370` breaks out of a 25-try lane the moment `bend` **says** anything
(*"bend NAMED it, so it is not the flake and 24 more tries cannot help"*), and
`gates/gatekit.py:324` has the same idea for the warm check. Both key on **silence**, which
§1 shows is stale at this pin. **`gates/gatekit.py` is where the class should be fixed next** —
it is 25 attempts × an uncapped `subprocess.run` on a 1.4 GB process, across four gates
(`gatekit.py`, `amd_dsl_census-gate.py:1033`, `ops_python_census-gate.py:756`,
`wgsl_render_census-gate.py:1295`). **Reported, not edited: `gates/` is another unit's.**

**A second census with its own denominator:** the `timeout=` table (rows 6–7) is over **tracked
`.py` only** and is **not** a census of the retry class — it is a census of *how long the tree
lets a child run*. `1800` appears **13** times and `3600` **14**. That is a finding for whoever
owns the machine budget, not a claim about retries.

---

## 8. UNSETTLED

1. **The `1.29 s / 44 s / 182 s` figures are cited, not re-measured.** Running them is forbidden
   to this unit. Every number in §3 that derives from them inherits that.
2. **`references/bend` is a depth-1 clone.** Whether 2.0.34's stack overflow was silent — which
   is what `gates/gatekit.py:135` measured — is **not falsifiable from this tree**. A full clone
   would settle it; that costs network and disk, and the answer does not change §2.
3. **`CRASH_CONTROL` is checked by reading, so it cannot detect a compiler that stops printing
   the token.** That is the stale-pin case, and §2's answer is that it fails red. The next
   `differ.py run` is the detector.
4. **`gates/gatekit.py`'s silence-based retry is the largest remaining instance of the class**
   (25 attempts × 1.4 GB × 4 gates) and is untouched here.
