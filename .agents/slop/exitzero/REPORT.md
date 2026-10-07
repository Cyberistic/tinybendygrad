# EXIT-ZERO OVER AN UNMEASURED SUBSTRATE — `checks/substrate.py`

**HEADLINE. A gate printed `SUBSTRATE CLEAN … each judged by its OWN instrument` and exited 0
while a file was judged by NOTHING. The bug was in the shell (`oracle-check.sh:463-470`) AND the
port reproduced it faithfully — so the fix belongs in BOTH, and both now REFUSE (exit 3). On
today's tree the defect is LATENT (`tally["none"] == 0`), which is the more dangerous state: the
only witness to a dead `cc` for the sweep's whole life was a count in a summary line on a run
that said `CLEAN`.**

Nothing committed; nothing staged. Two files touched: `checks/substrate.py` (+62/−11) and the
frozen oracle `.agents/slop/substrate/oracle-check.sh` (+36/−10), re-frozen in `ORACLE_PIN`.
Python only; `bend` was run exactly twice (the `cc` context emit, both needed).

---

## 1. REPRODUCED, WITH THE EXACT STRINGS (artifacts `before-*.out`, `oracle-defect2.out`)

All runs via `.venv/bin/python checks/substrate.py`. `cc` is LIVE in this tree now
(`checks/c-context.bend` exists, landed by `ccdead2` `6139a16fd`), so the defect had to be
reached by a class the router cannot judge and by a PLANT.

**DEFECT 2 (live, no plant) — a `.py` has no instrument class:**

```
NO INSTRUMENT  checks/substrate.py  (884 lines)  :: no instrument exists for this file class -- **NOT JUDGED, AND NOT COLD**
ROUTE   bend=0  cc=0  node=0  no-instrument=1  (of 1 file(s))
NO INSTRUMENT: 1 of 1 file(s) were **NOT JUDGED** (no instrument exists, or it produced nothing).
SUBSTRATE CLEAN: 1 file(s), all non-empty, each judged by its OWN instrument, all cross-file names resolved (0 of 27 qualified refs checked; …)
rc=0
```

**DEFECT 1 (planted: `checks/c-context.bend` renamed aside → the `cc` lane is DEAD over `sz.c`):**

```
FULL:  NO INSTRUMENT  tinybendygrad/runtime/sz.c  (119 lines)  :: cc and a compiling bend C context are both required, and one is absent
       SUBSTRATE CLEAN: 1 file(s), … each judged by its OWN instrument …   rc=0
-n  :  SKIP-VERDICT tinybendygrad/runtime/sz.c  (119 lines, verdict suppressed by -n)
       NAMES CLEAN: 1 file(s), … **VERDICT NOT TAKEN** (-n).   rc=0
```

**REACHABILITY TODAY.** `--root tinybendygrad` (`-n`) reads
`ROUTE bend=0 cc=0 node=0 no-instrument=0 (of 140)` — but `-n` suppresses verdicts. The full
instrument over the only class that can go dead (the two `.c`) reads
`ROUTE bend=0 cc=2 node=0 no-instrument=0`, both `WARM`, rc=0 (`live-c.out`). `.bend`→`bin/bend`
exists, `.js/.mjs`→`node` exists, `UNJUDGED 0`, so **`tally["none"] == 0` on the sweep: the defect
is LATENT, not live.** Latent is more dangerous: a live defect is seen, a latent one re-arms the
day `cc`/`node`/`bend` or a probe goes missing, and until then the mechanism has no witness.

**THE SWEEP ITSELF CANNOT SHOW `CLEAN` TODAY** — the tree carries 3 other units' untracked probes
(`tinybendygrad/runtime/_p6.bend`, `test/_probe/v5.bend`, `uop/probe-mmcore.bend`), so the port
alarm makes it `SUBSTRATE NOT CLEAN` (rc 1). The `CLEAN`-over-nothing state is shown by the two
controlled invocations above instead.

---

## 2. THE SHELL IT WAS PORTED FROM — IT HAD THE BUG (read at `git show HEAD:`)

`oracle-check.sh:463-470` (pre-edit numbering, the brief's):

```sh
if [ "$n_none" -gt 0 ]; then
  print -r -- "NO INSTRUMENT: $n_none of $# file(s) were **NOT JUDGED** …"
  print -r -- "A FILE WITH NO INSTRUMENT IS NOT A PASS AND NOT A FAILURE. It is an unmeasured surface."
fi
if [ "$names_only" -eq 1 ]; then
  print -r -- "NAMES CLEAN: …"
else
  print -r -- "SUBSTRATE CLEAN: $# file(s), … each judged by its OWN instrument, …"
fi
```

`n_none` never reaches `fail` (the counter is incremented at `:200` and `:223`, and `fail` only at
`Missing/EMPTY/COLD/BAD/prov`). The block has **no trailing `exit`**, so the script's status is the
LAST `print`'s — 0. **Proved, not read**: `SUBSTRATE_REPO=$PWD zsh oracle-check.sh checks/substrate.py`
prints `NO INSTRUMENT …` then `SUBSTRATE CLEAN … each judged` and returns **rc=0**
(`oracle-defect2.out`). The shell's only exit-3 is the zero-argument refusal (`:267`).

**SO THE PORT IS FAITHFUL — IT MOVED THE BUG, IT DID NOT INHERIT IT.** The string
`tally["none"] > 0` entered `checks/substrate.py` at **`3f0e70ff1`** (`git log -S`), the
"PYTHON ONLY" port/cleanup commit; `ccdead2` (`6139a16fd`, and its recovery `813bbec3e`) REPORTED
it and deliberately left it. The distinction the brief asks for resolves to: **the fix goes in
TWO files**, and it now does.

---

## 3. PLANTED, AND THE FIX SHOWN (`verify.py`, `before-*.out` vs `after-*.out`)

`verify.py` is PYTHON ONLY, `bend`-free: it renames `checks/c-context.bend` aside, drives the real
gate, and restores in `finally`. 11/11 assertions OK:

| state | BEFORE | AFTER |
|---|---|---|
| `.py` (no instrument) | `SUBSTRATE CLEAN`, rc 0 | `SUBSTRATE REFUSED`, rc 3 |
| `sz.c`, probe GONE, FULL | `NO INSTRUMENT` + `SUBSTRATE CLEAN`, rc 0 | `NO INSTRUMENT` + `SUBSTRATE REFUSED`, rc 3 |
| `sz.c`, probe GONE, `-n` | `SKIP-VERDICT` + `NAMES CLEAN`, rc 0 | `NO INSTRUMENT` + `SUBSTRATE REFUSED`, rc 3 |
| live `.c` pair | `WARM`, `SUBSTRATE CLEAN`, rc 0 | unchanged, `no-instrument=0`, rc 0 |

The `-n` row is the `-n` fix proving itself: the dead lane is no longer hidden.

---

## 4. THE FIX LANDED — REFUSED (3), matching `gates/gatekit.py:40-70`

`run()` no longer falls through to `CLEAN` when `tally["none"] > 0`. It branches:

```
findings > 0                    -> SUBSTRATE NOT CLEAN      exit 1  (FAIL)
findings == 0, tally["none"] > 0 -> SUBSTRATE REFUSED        exit 3  (REFUSED)
otherwise                        -> SUBSTRATE CLEAN          exit 0  (PASS)
```

`PASS, FAIL, REFUSED, SKIP, DEAD = 0,1,3,4,5` (`gatekit.py:60`). An unjudged file is **not a
finding** — nothing measured, so nothing is WRONG — which is exactly REFUSED (3), not FAIL (1):
*"I could not judge this" is not "this is wrong."* No sixth verdict. Exit 3 already meant the
zero-argument refusal and `ORACLE DRIFT`, so this is one vocabulary.

The verdict text names the unmeasured and states the denominator:
`SUBSTRATE REFUSED: <judged> of <N> file(s) were judged and agreed; the rest were judged by
NOTHING, so this run did not judge the whole population and must not report agreement.`

The `why` for a dead `cc` context stays the ROUTED wording (no `-- **NOT JUDGED**` suffix) — the
shell's deliberate asymmetry, preserved.

**EVERY CALLER THAT READS `$?` (the brief's warning, answered):**

| caller | how it reads the gate | sees the new 3? |
|---|---|---|
| `checks/disarm.sh:27` | pipes to `grep`; `$?` is grep's | no; verdict-words only |
| `checks/demo.sh:30` | pipes to `grep`; `-n` over `.bend` (rc stays 0/1) | no |
| `checks/run-f64.sh:105`, `.agents/slop/f64/run-f64.sh:98` | bare run, `set -u` only (NOT `-e`); reads `head -1`, not `$?`; passes `.bend` | no |
| `.agents/slop/guardfix/disarm.sh:28,37` | pipes to `grep`; greps `NO INSTRUMENT`/`ROUTE` | no |
| `.agents/slop/substrate3/plant.py` | reads rc; `-n` over `.bend` fixtures → rc 0 | no |
| `.agents/slop/substrate/diff.py` | reads rc, compares oracle vs port | **yes — and it now AGREES** |
| `.agents/slop/shfinish/triage.py:9` | FREEZES `oracle-check.sh`'s hash | **yes — must move to the new pin** |
| `checks/substrate-check.sh`, `.agents/slop/substrate-check.sh` | `exec` shims | propagate 3 |

No live caller hands the gate a class that yields `none` (all pass `.bend`, or `bare.txt` which is
absent → `MISSING` → rc 1), so nothing breaks today. `triage.py` is the one instrument to update
alongside the oracle (see §6).

---

## 5. THE `-n` SHORT-CIRCUIT — DECISION: PRINT THE DEAD LANES, AND REFUSE

`-n` used to `SKIP-VERDICT` a routed file BEFORE the instrument was consulted, so the one mode
that costs nothing was the one that could not see the `cc` context dying — "the cheapest mode is
the least honest one." Decision, implemented in BOTH files:

- **The cheap precondition is checked BEFORE the `-n` skip.** `Ctx.ready()` (port) / `c_ready()`
  (oracle) tests `bend` + the two probe files, with no emit. A probe that is GONE now prints
  `NO INSTRUMENT` under `-n` instead of being skipped. (The expensive half — does the context
  COMPILE — is still `Ctx.ok()`/`c_context`, and is deliberately not paid on `-n`.)
- **`-n` still does not refuse a merely-suppressed verdict.** It reads `NAMES CLEAN … **VERDICT
  NOT TAKEN** (-n)`, which is already the honest label, and exits 0. It refuses (3) only when a
  file was truly unjudged. This keeps `.agents/slop/substrate3/plant.py`'s `-n` green-on-restore
  assertion true.

---

## 6. THE ORACLE — RE-FROZEN, AND WHY THE C-LANE HAD TO MOVE WITH IT

Fixing the oracle's `n_none` branch alone made `.agents/slop/substrate/diff.py` report a NEW
divergence: the oracle's `C_PROBE` pointed at `.agents/slop/guardfix/probe-c.bend`, which was
**never committed** and is GONE, so `c_ready()` was false and the oracle called `dtype.c` `NO
INSTRUMENT` where the port calls it `WARM`. The `ccdead2` commit had already re-pointed the PORT's
probe to the tracked `checks/c-context.bend`; the oracle had not. So the oracle's
`C_PROBE`/`C_PROBE_FOREIGN` were re-pointed to `checks/c-context.bend` / `tinybendygrad/runtime/sz.c`
too. **Result: `diff.py --sets names` and `--sets smoke` now diverge ONLY on the port's added
`COVERAGE` line** (the documented port-only change from `substrate3` `46b95c133`) — oracle-only
line list is EMPTY; before this session the smoke set additionally diverged on the dead C lane.
The fix strictly IMPROVED port↔oracle agreement.

`ORACLE_PIN` moved `6d1000712f0f…` → `3b2ad83f57d9…`, and the port confirms no `ORACLE DRIFT`
(rc 0 on a live `.c` pair). **This is one commit or it is a broken pin**: the oracle edit, the
probe re-point and this hash must land together, or the next restore-from-HEAD makes the gate
REFUSE (3) — loudly, the safe direction. `.agents/slop/shfinish/triage.py` freezes the same oracle
and must move to the new hash.

---

## 7. THE DENOMINATOR — how many gates can print CLEAN while something is UNMEASURED

Instrument: `.agents/slop/exitzero/census.py` (`census.out`). Population by DISCOVERY — the 116
files of `checks/*.py` + `gates/*.py` (doctrine 1; `envguard/scan.py`, unmodified, is the Class-A
oracle).

| class | mechanism | count |
|---|---|---|
| A — REFUSED-missing (envguard) | read under `runs/`/`artifacts/` with no `exists`/`try`/`require` | **11 raw lower bound**; **2 genuine** = `differ.py`'s two read helpers (`text()`, `one_line()`, callers guard) |
| B — `warm="report"` (gatekit) | a COLD driver is REPORTED and the lanes are still diffed → green over a cold substrate | **1** = `gates/beautiful-mnist-gate.py` |
| C — a check nobody has seen fire | not an AST property; one tabulated instance | **10 of 16** in `graphcmp-oracle.py` (`censusred/REPORT.md` §6) |
| D — this task | `checks/substrate.py` `tally["none"]>0` → CLEAN, rc 0 | **1, now CLOSED** |

**DISTINCT unmeasured-while-green paths (the two named lists combined):**
- strict (genuine A): `2 + 1 + 10 = 13`
- lower bound (raw A): `11 + 1 + 10 = 22`
- `+ 1` closed by this task → 14 / 23.

Caveats stated, not hidden: A is a LOWER bound (a path through a helper-returned `Name` is a
named miss); B's count is the one gate that ADOPTS the policy (`gatekit.py` is the plumbing); C is
history, not AST, so it is one measured file of a tree-wide class; the units differ (A/B are
files, C is checks-within-a-file), which is why both a strict and a bound reading are given.

---

## 8. FILES

- `checks/substrate.py` — the fix: `Ctx.ready()`, the pre-`-n` precondition, the REFUSED branch,
  the exit-status docstring, and the re-frozen `ORACLE_PIN` (+62/−11).
- `.agents/slop/substrate/oracle-check.sh` — the same fix in the shell, plus the C-probe
  re-point (+36/−10).
- `.agents/slop/exitzero/repro.py` — reproduces both defects; `before-*.out`.
- `.agents/slop/exitzero/verify.py` — the 11-assertion two-state check; `after-*.out`.
- `.agents/slop/exitzero/census.py` / `census.out` — the denominator.
- `.agents/slop/exitzero/{live-c,defect1-plant-full,defect1-plant-n,oracle-defect2}.out` — raw evidence.
