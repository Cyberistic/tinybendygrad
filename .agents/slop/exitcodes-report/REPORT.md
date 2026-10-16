# THE EXIT-CODE CENSUS — CAN A READER OF `$?` TELL WHICH VERDICT WAS MEANT?

`.venv/bin/python gates/exitcode-census-gate.py` · `--plant` · `--rows`
Fix landed: `gates/ops_python_exec-gate.py:113,115,204,286`
Every number below carries the run that took it. The population MOVES while other units write the
tree — `W` read 253 and then 254 inside this session — so quote a count with its command or not at
all. The two census columns this report quotes as final are the ones that did **not** move:
**50 `STR` sites over 23 files, and 5 `MAYBE-NONE` sites**, both taken from the same
`gates/artifacts/exitcode-census/rows.tsv`.

---

## 1. THE DENOMINATOR, AND HOW IT WAS DISCOVERED

**Four populations, all DISCOVERED, all printed on every run, none of them written down here.**

| | what | how | measured |
|---|---|---|---|
| **A** | `*-gate.py` under `gates/` | `checks/gatesweep.py:population()` — `os.walk`, `lstat`-regular, `__pycache__` not descended | **79** |
| **H** | the gate homes | `gates/gates-pop.py:gate_homes()` — measured, `COMMIT TREE (git ls-tree -r HEAD)` | **2** (`checks`, `gates`) |
| **B** | entry points in the homes | `gates/gates-pop.py:discover()` — AST `__main__` | **208** |
| **W** | **every `.py` under `H`** | `os.walk` over the derived homes, filtered on the extension | **253 → 254** ← **THE CENSUS SET** |

**171 → 172 files hold an exit site; 289 → 290 sites.** The arrow is not an estimate: the census was
re-run at the end of this session and `W` had grown by one file because another unit wrote one.
`W` is the census set and not `A` because an exit shape can live in a file no name shape calls a
gate: **175 of the 254 are invisible to `*-gate.py`.** `A` is 79 for the same reason — it read 76,
77 and 78 in three consecutive runs during this session. **That is the reason a census needs a
derivation and not a list.**

`H` is itself the tree's own measurement, so this file names no directory. `A`, `B` and `H` are
**loaded by path** (`importlib`), never re-implemented, and the vocabulary is
`gates/gate-surface.py:vocabulary()` reading `gates/gatekit.py`'s module-level unpack. **A second
copy of any of them is a mapping that can disagree with the first**, which is what
`gates/gate-surface.py:240-251` exists to stop.

---

## 2. THE TABLE — SHAPE × VERDICT × REACHABILITY

A **shape** is what the author handed the exit. `CHOSEN` is the line: a chosen number was picked by
a person; an unchosen one is picked by CPython from the value's **type**. Full table in
`gates/artifacts/exitcode-census/rows.tsv`, one row per site.

| shape | sites | code CPython produces | verdict a reader gets | **reaches `$?`?** |
|---|---|---|---|---|
| `INT` | 34 | the literal | the literal's verdict | **yes, always** |
| `NAME` | 3 | the module constant it reads (`FAIL`, …) | that constant's verdict | yes |
| `FOREIGN` | 153 | whatever the callee returns | not resolvable statically | delegated, not lost |
| `OTHER` | 39 | an expression over runtime data | not resolvable statically | delegated, not lost |
| `DELEGATED` | 5 | — | the callee's own site, already a row | counted once |
| **`STR`** | **50** | **`1`** | `FAIL` — **whether or not that is what was meant** | **no** |
| **`MAYBE-NONE`** | **5** | **`0`** | `PASS` — **on a path that never answered** | **no** |
| `BOOL` | **0** | `1` / `0` | `FAIL` / `PASS` by `True == 1` | no (none reach it today) |
| `NONE` | **0** | `0` | `PASS` | no (none reach it today) |

**55 of 289 sites (19%) carry a code CPython chose.** That is the headline and it is a count, not a
verdict about any one file.

### Every reachable shape, MEASURED under `.venv/bin/python` 3.12.10

| written | stderr | **rc** | verdict | the shape |
|---|---|---|---|---|
| `sys.exit("m")` | `m` | **1** | `FAIL` | `STR` |
| `sys.exit(f"x {y}")` | `x y` | **1** | `FAIL` | `STR` |
| `raise SystemExit("m")` | `m` | **1** | `FAIL` | `STR` |
| bare `exit("m")` / `quit("m")` | `m` | **1** | `FAIL` | `STR` |
| `sys.exit()` | — | **0** | **`PASS`** | `NONE` — **the most dangerous shape here** |
| `sys.exit(True)` | — | **1** | `FAIL` | `BOOL` |
| `sys.exit(False)` | — | **0** | **`PASS`** | `BOOL` |
| `sys.exit(3)` | — | 3 | `REFUSED` | `INT` |
| `sys.exit(5)` | — | 5 | `DEAD` | `INT` |
| `sys.exit(2)` | — | 2 | **UNASSIGNED** → `charge` bills `REFUSED` | `INT` |
| uncaught exception | traceback | **1** | `FAIL` to `$?`; **`DEAD` to a runner** | — |

**`sys.exit(2)` and `sys.exit(126/127)`: REACHABLE AND REPORTED, NOT FAILED.** `gates/gatekit.py:88-91`
already decides what an unassigned code means — "the absent precondition is a **DEFINITION**", so it
`REFUSE`s — and this gate reports that consensus rather than re-deciding it. Seven sites reach a
literal `2` (`checks/repair-dupes.py:99`, `gates/amd_dsl_census-mutate.py:139`,
`gates/beautiful-mnist-gate.py:89`, `gates/crp_graph_census-mutate.py:123`, `gates/gate-surface.py:221`,
`gates/linearizer_census-oracle.py:207`, `gates/mixin-op-gate.py:99`) and nine of the eighteen
instruments that can return one inherit it from `argparse`. `checks/wallcheck.py:692` and
`checks/dup-gate.py:362-370` both spell `2: "USAGE"`; `checks/env-precond.py:452` and
`gates/gate-surface.py:136` spell `2: "REFUSED"`. **That disagreement is pre-existing and untouched.**

---

## 3. EVERY GATE WHOSE EXIT CODE CAN CARRY A WRONG VERDICT

**55 sites over 40 files. Per-file rows: `gates/artifacts/exitcode-census/rows.tsv`.** The `STR`
sites are all identical in shape, so they are grouped by file with the count:

| file | `STR` | the sites |
|---|---|---|
| `checks/abi_gate.py` | 5 | 357, 376, 381, 395, 632 · `sys.exit(f"...")` |
| `checks/abi4_gate.py` | 4 | 298, 318, 327, 353 |
| `checks/gate.py` | 4 | 180, 203, 210, 217 |
| `checks/gate_norm.py` | 3 | 118, 123, 127 |
| `checks/jsfix_gate.py` | 5 | see the row file |
| `gates/ptx_render_census-mutate.py` | 3 | see the row file |
| `checks/al-verdict.py` · `cl-port-gate.py` · `corpus-figure.py` · `oracle_f64.py` | 2 each | see the row file |
| `gates/ops_python_census-oracle.py` · `crp_graph_census-oracle.py` · `ops_python_exec-gen.py` · `retention-check.py` · `tc_ptx_types-mutate.py` | 2 each | see the row file |
| `checks/dup-gate.py` · `gate_dtype.py` · `plant.py` · `residue.py` | 1 each | see the row file |
| `gates/crp_graph_census-mutate.py` · `gendirs.py` · `i64-shr-gate.py` · `ptx_render_census-gen.py` | 1 each | see the row file |
| **`gates/ops_python_exec-gate.py`** | **0 (was 4)** | **113, 115, 204, 286 — FIXED, §5** |

**50 sites over 23 files.**

**THE 5 `MAYBE-NONE` SITES, WHICH ARE WORSE, ALL BY HAND-READ:**

| site | what happens |
|---|---|
| **`gates/i64-shl-oracle.py:198`** `sys.exit(main())` | `main()`'s last statement is `print("\n".join(out))`, so it returns **`None`** and `sys.exit(None)` is **0**. |
| `gates/i64-shr-oracle.py:294` | the same shape |
| `gates/wgsl_render_census-gate`-adjacent `gates/wgsl_render_census-oracle.py:957` | the same shape |
| `gates/amd_dsl_census-oracle.py:1090` | the same shape |
| `gates/decomp_graph_census-mutate.py:314` `sys.exit(main(sys.argv[1:]))` | the same shape |

**AN ORACLE THAT EXITS 0 IS WHAT `gates/gatekit.py:444-448` WANTS** (`if r.returncode != 0: …
return False`), so these four are harmless *today* and **that is the finding**: `main()` falls off
its end **whether or not it asserted anything**. Delete the assertions in `gates/i64-shl-oracle.py`
and it still prints rows and still exits 0, and `Gate._oracle()` cannot see it. `gatekit`'s
`_warm()` already guards against exactly this on the *bend* side — `"the driver is 0 bytes, and an
empty file typechecks"` (`gates/gatekit.py:421-423`) — **and there is no such guard on the oracle
side.** That is the asymmetry, stated.

**THE TWO SHAPES THAT REACH NOBODY TODAY, AND THE MEASUREMENT THAT SAYS SO: `BOOL` 0, `NONE` 0.**
`sys.exit()` with no argument appears in **none** of the 253 files. Recorded because
`AGENTS.md`'s rule is that an unmeasured negative is not a fact until the instrument exists, and
this one exists now.

### THE SHELL, CENSUSED SEPARATELY — 19 files (17 `checks/*.sh`, 2 `gates/oracles/*.sh`)

| shape | measured | verdict |
|---|---|---|
| **`exit "msg"`** (an `sh` error: `exit: Illegal number: msg`) | **0 real sites.** 11 grep hits, **all 11 inside comments or prose** | negative result |
| `exit 3` | 24 sites | `REFUSED` — matches `gatekit` |
| `exit 2` | 14 sites | **UNASSIGNED** → `charge` bills `REFUSED` |
| `exit 1` | 15 sites | `FAIL` |
| `exit 5` / `exit 6` | **0 real sites.** Both grep hits are inside a *message string* in `checks/sb-gate.sh:124,125` | negative result |
| `exit $?` off a pipeline | **0** | negative result |
| `pipefail` declared | **2 of 19** (`checks/plant.sh`, `checks/run-all.sh`) | — |
| `gates/*.sh` | **0** | `gates/README.md`'s claim holds |

**AND THE SHELL'S ONE REAL FINDING: `checks/gate.sh:45-57` PRINTS `DIED` AND EXITS 2.**
Eight sites, all the same shape — a zero or short lane. **`DEAD` IS EXACTLY THAT**
(`gates/gatekit.py:60`, "it ran and emitted nothing"), `DEAD` HAS EXIT **5**, and `DIED` IS A WORD
BOUND TO NO CODE ANYWHERE. A reader gets **2**, which `gatekit.VERDICT` does not name and `charge`
bills `REFUSED`. **A DEAD LANE IS TALLIED AS A REFUSAL** — the same class as the confirmed defect,
in shell, on a different number. `gates/README.md` declares the shell form **retired**; this file
still carries it, and `gates/gatekit.py:59` still cites `checks/sb-gate.sh` as the owner of
`REFUSED = 3` while fourteen other refusals in the same directory say `2`.

### THE `raise` QUESTION, AND THE TREE'S OWN POSITION — MEASURED, NOT ASSUMED

An uncaught exception exits **1**, which is `FAIL`. **The tree's position is that a crash is `DEAD`
and that the mapping is the RUNNER's, not the gate's**, in two places:

- `checks/gatesweep.py:classify()` — `rc == 1 and TRACEBACK in text` → **`DEAD`, token `TRACEBACK`**.
- `.agents/slop/hooks/run.py:112` — `return DEAD, "crashed, not a verdict: " + head`.

**So a crash IS distinguishable — but only by a reader holding the captured stderr**, exactly like
a string exit is only readable by a reader holding the message. **THE EXIT CODE CARRIES NEITHER.**
A crash is a row here, not a verdict this gate hands out.

---

## 4. DOES ANY GATE'S OUTPUT CONTRADICT ITS OWN EXIT CODE?

**MEASURED TWO WAYS. THE ANSWER IS "NO" TWICE, AND BOTH NEGATIVES ARE THE POINT.**

**(a) STATIC, over all 289 sites, under `gates/runner.py`'s OWN rule.** `runner.SPOKEN` is
`\b(GREEN|RED|PASS|FAIL|REFUSED|DEAD|SKIP)\b`, filtered to names in
`gate_surface.vocabulary().values()`; `spoken_disagrees` fires when the spoken set differs from the
verdict. **MEASURED: 0 sites name a vocabulary state that the code they carry contradicts.**
**This is a negative result and it is reported as one** — not as "the tree is clean".

**(b) LIVE, four gates, the two cheapest plus the two the README prices.** Each run under
`checks/bounded.py` and read through `gatesweep.classify` + `runner.spoken_disagrees`:

| gate | rc | watchdog | `classify` | spoken names | `TOKEN-MISMATCH` |
|---|---|---|---|---|---|
| `gates/msgdiff-gate.py` | 0 | `WITHIN-LIMITS` | `PASS/PASS` | `PASS` | none |
| `gates/devtag-gate.py` | 0 | `WITHIN-LIMITS` | `PASS/PASS` | `PASS` | none |
| `gates/pins-shape-gate.py` | 1 | `WITHIN-LIMITS` | `FAIL/FAIL` | *(none)* | none |
| `gates/indexread-gate.py` | 1 | `WITHIN-LIMITS` | `FAIL/FAIL` | `FAIL` | none |

**CAN A READER SEE IT? YES, IN ALL FOUR — because `gates/gatekit.py:736-745`'s `main()` PRINTS
`verdict_of(code)` before returning it.** The verdict is on stdout *and* in `$?`, and they agree.
`gates/pins-shape-gate.py` prints no vocabulary name at all, and it still agrees, because it says
nothing that contradicts anything.

### AND THE HOLE THAT MATTERS MORE: `TOKEN-MISMATCH` CANNOT SEE THIS CLASS

**MEASURED: `runner.spoken_disagrees` fires on 0 of the 55 NOT-CHOSEN sites.** The reason is in
`gates/runner.py:316-320` — the rule needs `names` to be non-empty, and the messages at
`ops_python_exec-gate.py:113,115,204` are prose: `has no records`, `has no gx gy gz`,
`the oracle lane failed rc=…`. None of them contains a vocabulary NAME.

**A MESSAGE THAT NAMES NO STATE IS NOT A MESSAGE THAT AGREES.** The fifth precondition catches
`SAYS X, EXITS Y`; it cannot catch `SAYS NOTHING, EXITS 1`. Fixing `ops_python_exec-gate.py`
therefore does not stop the class from recurring — `gates/exitcode-census-gate.py` is what stops
it, because it grades the **shape** and not the sentence.

---

## 5. WHAT WAS FIXED, AND WHY IT IS NOT A WEAKENING

**`gates/ops_python_exec-gate.py:113,115,204,286` — `sys.exit(<string>)` → the file's own
`refuse()`, which prints `REFUSED, NOT A VERDICT` and exits `3`.** All four are exercised, not
asserted:

| site | BEFORE (`git show HEAD:`, the real input files) | AFTER |
|---|---|---|
| `:113` `fixtures()`, a file with no records | `SystemExit.code = '…/empty.rows has no records'` *(str)* → **rc 1** | `3` → **rc 3** |
| `:115` `fixtures()`, argv without gx gy gz | `SystemExit.code = 'f0: argv (1, 2) has no gx gy gz'` *(str)* → **rc 1** | `3` → **rc 3** |
| `:204` `lane_py()`, the oracle lane fails | `SystemExit.code = 'the oracle lane failed rc=9: boom'` *(str)* → **rc 1** | `3` → **rc 3** |
| `:286` `main()`, the executor is absent | `SystemExit.code = 'the executor … is absent'` *(str)* → **rc 1** | `3` → **rc 3** |

**WHY IT IS NOT A WEAKENING, AND THE EVIDENCE IS THE POINT:**

1. **The verdict was ALREADY WRITTEN DOWN IN THAT FILE.** `ops_python_exec-gate.py:46-49` says
   verbatim *"3 a precondition was absent (the fixture file, the executor, `bin/bend`)"* — **it
   names all four conditions**. **The code was contradicting its own header.** This change makes
   the exit agree with a contract the file already shipped.
2. **THE TREE'S OWN KERNEL SAYS SO.** `gates/gatekit.py:515-516`: *"CPython did not run, so
   nothing was compared"* → `return REFUSED`, which is `lane_py()` failing. `:295-296` of the gate
   itself grades `absent` `REFUSED` for the other three paths — **one file, one condition, two
   verdicts, was the defect.**
3. **NOTHING IS SKIPPED, RETRIED OR SWALLOWED.** 1 and 3 are both non-zero; `gates/runner.py` and
   `gatesweep.classify` both map 3 to `REFUSED`; `gatekit.charge(3) == 3`. What 3 buys is the
   ability to tell *"your inputs are absent"* from *"the executor and CPython disagree"*.
4. **NO VERDICT WAS COLLAPSED.** `DEAD` stays 5, `REFUSED` stays 3, `FAIL` stays 1. `--plant`
   asserts all five round-trip through `verdict_of` and asserts `SKIP != FAIL` and `REFUSED != FAIL`.
5. **NO `sys.exit(0)` WAS INTRODUCED.** `refuse()` has exactly one exit and it is `REFUSED`.
   `rg 'sys.exit\(0\)' gates/ops_python_exec-gate.py` → **0 hits.**
6. **THE HAPPY PATH STILL RUNS.** The probe executed `fixtures_hold`, `lane_py`, `population_hold`
   and `coverage_hold` against the real fixture file and the real generator: **all four `OK`**, before
   and after.

---

## 6. THE PLANT, AND THE PROOF IT GOES RED

`.venv/bin/python gates/exitcode-census-gate.py --plant` → **rc 0**, **22 shape cases + 4 decision
states + 5 verdict round-trips**, all through the **SHIPPED** `extract()`, `classify_site()`,
`decide()` and `gatekit.verdict_of`. **No walk, no subprocess, no `bend`, no live file.**

Every case asserts **four** things: the number of sites `extract()` found, the shape, the code
CPython produces from it, and whether that shape is `CHOSEN`. The `STR` rows assert `verdict == FAIL`
**and** `chosen is False` together — because `gatekit.verdict_of(1)` *is* `FAIL`, correctly, and the
defect is the **unchosenness**, not the number. A plant asserting only the shape would be green on
an instrument that had learned nothing.

**THE PLANT DRIVES THE DECISION, NOT A HELPER — MEASURED, and this is the property
`gates/runner.py:391` records its first plant lacked.** Three mutations, three reds:

| # | the mutation | the plant's reaction |
|---|---|---|
| **1** | `CHOSEN = CHOSEN \| {"STR"}` — declare a string exit a chosen number | **5 shape rows BAD** *and* `a tree holding a string exit FAILs → rc=0 PASS` **BAD** → `plant rc = 1` |
| **2** | `extract()` stops seeing `raise SystemExit` | `a callee's own exit is DELEGATED, once` → **BAD** → `plant rc = 1` |
| **3** | `returns_none()` always answers `False` | `sys.exit(f()) when f can return None` → **BAD** → `plant rc = 1` |

**Mutation 1 is the load-bearing one: it turned BOTH the classifier AND the verdict function red.
A plant that drove a helper would have stayed green on mutation 1 — which is exactly what
`gates/runner.py`'s first plant did when `preconditions`' branch was broken.**

**THE GATE'S OWN THREE STATES, each measured by running the tool:**

| state | how | rc |
|---|---|---|
| `FAIL` | the live tree — 55 sites whose code CPython chose | **1** |
| `REFUSED` | a tree whose `gate_homes()` derivation returns nothing, i.e. every synthetic tree tried | **3** |
| `PASS` | the plant's `a tree of chosen numbers PASSes` case, through `decide()` | **0** |

**AND `DEAD` IS NOT PRODUCED BY `decide()`, AND THIS FILE SAYS SO.** `decide()` has three branches;
`gatekit.DEAD` (5) is **not** one of them and cannot be, because a census that ran and found
nothing to report has run. **It is asserted in the plant instead** (`verdict_of` round-trips all
five) rather than faked with a fourth return path — *inventing* a `DEAD` here would be the
collapse `AGENTS.md` forbids.

---

## 7. FOUND AND NOT DONE

| what | why not |
|---|---|
| **The other 50 `STR` sites in 23 files** | Out of grant, and each needs the same 30-line argument this file's own header now carries. **Every one is a row in `rows.tsv`**, with the verdict each site means written down by hand in a later pass. |
| **`checks/gate.sh:45-57` prints `DIED` and exits 2** — a `DEAD` lane tallied as a `REFUSED` | `checks/` is out of grant. **`DIED` is bound to no code anywhere**, so fixing it means choosing 5 and saying so in a file whose README says the shell form is retired. **Whether to retire the file or renumber the exits is a decision, not a fix.** |
| **`2` means both `USAGE` and `REFUSED`** (`checks/wallcheck.py:692`, `checks/dup-gate.py:370` vs `checks/env-precond.py:452`, `gates/gate-surface.py:136`) | Out of grant, and `gatekit.verdict_of` already resolves the *reader*'s problem by naming an unassigned code `REFUSED`. The disagreement is between four owners' declarations, which is a decision. |
| **`gates/runner.py:304`'s `spoken_disagrees` has the hole §4 names** | `gates/runner.py` is out of grant. **A one-word fix exists** — treat a non-int exit as a claim — and it needs a runner, not a census. |
| **The 4 oracles whose `main()` falls off its end** | Each needs `return PASS` at the end. Trivially correct and still four files I was not given. **`gatekit._oracle()` is the guard that belongs, and `_warm()` already writes it for `bend`.** |
| **A `--root` flag** | Written, measured, **removed**. `gates/gates-pop.py:gate_homes()` certifies a home only through `_CERTIFY` (`pyproject.toml`, `__main__`), `_CERTIFY_OR` (`refuse(`, `exit 3`, …) and `root_facts`. **Four synthetic trees tried — bare, with `pyproject.toml`, with a root constant and a `refuse()`, and `git init`-ed — all four returned `homes = ()`.** A flag that refuses on every input is a flag nobody can act on. The synthetic input belongs in `--plant`, and that is where it is. |

---

## 8. WHAT THIS CENSUS CANNOT SEE

Same-module resolution only, depth 1. A name bound twice is read as both bindings; a call into
another module is `FOREIGN`; a value over runtime data is `OTHER`. **`MAYBE-NONE` is a LEXICAL
LOWER BOUND** over that same shallow resolution. Two false positives were found by running it and
are fixed in its favour of reporting them honestly rather than deleting the class:

- **`gates/msgdiff-gate.py:593` was flagged MAYBE-NONE on a bare `return` inside a CLOSURE `main`
  defines** — `ast.walk` descends into nested `def`s. `main` returns `PASS`/`REFUSED`/`SKIP`/`DEAD`
  and never `None`. Fixed by not descending.
- **`gates/msgdiff-gate.py` and `gates/git-massdelete-gate.py` were then flagged again** because
  `main`'s last statement is a `try:` whose every branch returns. Fixed by teaching `_terminates`
  about `try`/`with`/`if`.
- **`checks/vz_gate.py:249` was counted TWICE** — `sys.exit(verify())` over a `verify` that ends in
  `sys.exit(<str>)`, one `STR` defect at two rows. Fixed by `DELEGATED`, which is `CHOSEN` **because
  it is not a separate exit**.

**A SHALLOWER-THAN-CLAIMED LOOKUP IN A GATE IS A FALSE POSITIVE, AND A FALSE POSITIVE IN A CENSUS
IS THE SAME CLASS AS A FALSE NEGATIVE: BOTH ARE ROWS.** All three are in `--plant` now.