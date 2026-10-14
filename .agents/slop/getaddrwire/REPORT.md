# getaddrwire — `RUN INCOMPLETE` → `RUN COMPLETE` for `getaddr`: **BLOCKED, and the run is a SKIP**

Unit of 2026-10-07 00:22–00:44. Read with `.agents/slop/getaddrfix/` (whose report **does not exist**;
see §1) and `checks/differ.py`'s `WANT`/`PINS`.

## 0. The verdict, in one line

**The fix IS on disk, but it is an UNCOMMITTED, LIVE-EDITED working-tree change; `bend` was
contended for the entire session; and `graphcmp.bend` moved under me three times — so
`differ.py run` is SKIPPED and no `WANT`/`PINS` row is moved.** A row written without a run is
the "a graph that lands expecting nothing is a corpus that cannot fail" defect `wantwire` names.
`SKIP` is a verdict; this is that verdict, not a pass.

## 1. The `getaddrfix` unit left no report, and the fix was not committed by its own commit

- `.agents/slop/getaddrfix/` **does not exist** (`ls`, 00:22). `git log --all -- '.agents/slop/getaddrfix/'`
  → nothing. `git log --all --diff-filter=D -- '.agents/slop/getaddrfix/'` → nothing. The directory
  was never tracked and never on disk in any ref I can read.
- Commit `00b101574`'s message is **"reports: the five units that landed (getaddrfix, unshardfold,
  gitinput, prefixtxt, flipbool) plus their artifacts."** Its actual diff — `git show --stat 00b101574` —
  touches **4 files**, **none** a report and **none** `graphcmp.bend`:
  `.agents/slop/censusred/run.err`, `.agents/slop/censusred/run.out`,
  `gates/tn_sin_log2_exp2_rsqrt.bend`, `tinybendygrad/tensor.bend`.
  The other four report dirs **do exist** (`flipbool/ gitinput/ prefixtxt/ unshardfold/`); only
  `getaddrfix/` is missing. **A commit message is not a diff.** This is Doctrine 1's shape: a claim
  ("it landed") with no generator that can fail.

## 2. The fix was applied to the WORKING TREE mid-session, and it is still uncommitted

`checks/differ.py`'s own brief step was "confirm the fix is in the worktree". **At session start it
was NOT**; it appeared during the session. Measured timeline (each a `git status --porcelain` /
`sha256sum` / `sed` read of `.agents/slop/graphcmp.bend`):

| time     | `g_getaddr` arena arg | `sha256` (first 12) | `differ.py:1564`/`1571` = `def rows.pick3`? | source |
|----------|-----------------------|---------------------|-----------------------------------------------|--------|
| 00:22:xx | `ar` (BUGGY)          | (spot: `ar`)        | 1564 (cite green)                             | `git status … graphcmp.bend` = **empty** (matches HEAD) |
| 00:28:14 | `Found.ar(a0)` FIXED  | —                   | —                                             | `git diff` shows `+a1 = Found.ar(a0)` |
| 00:37:03 | `ar` (BUGGY again)    | —                   | 1571 = `Bool.pick(...)` (cite RED)            | `git diff --stat` = 1643 ins (index reset) |
| 00:39:18 | `Found.ar(a0)` FIXED  | `c11b6fb60375…`     | 1571 = `def rows.pick3` (cite green)          | `grep Found.ar(a0)` = 26 |
| 00:44:15 | `Found.ar(a0)` FIXED  | `c11b6fb60375…`     | 1571 = `def rows.pick3`                        | as above |

**The file is being written by more than one unit.** The current fix, verbatim (`graphcmp.bend:1349`):

```
def g_getaddr() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new(ar, O.OpsALLOC{}, Nil{}, O.AParam{alloc(0, 12)}, O.TNone{})
  # THE ARENA `UOp.new` RETURNED, NOT THE ONE IT WAS HANDED. Arena is immutable and
  # `UOp.new.of` returns `Found{made, ..}` -- the ALLOC lives in `Found.ar(a0)`, whose
  # index `Found.i(a0)` names it. Passing the PRE-`new` `ar` put `Found.i(a0)` past its
  # end, so `Arena.op` answered the arena BOTTOM (`BAD/NOOP`): peel said "not an ALLOC",
  # getaddr returned `self` unchanged, and the graph was one BAD row. Every other arm
  # threads `O.Found.ar(prev)`; this one was the exception.
  +a1 = O.Found.ar(a0)
  O.UOp.getaddr(O.Arena.budget(a1), a1, O.Found.i(a0), S.D1{0})
```

This matches the `getaddrfix` diagnosis in `00b101574`'s message and in my brief, AND the port
semantics I re-derived independently: `UOp.new.of` (`ops.bend:2657`) returns `Found{made, …}`, and
`Found.ar` (`ops.bend:2651`) is `made`; passing the pre-`new` `ar` names an index past `ar`'s end.
So the fix's CONTENT is right.

**But it is not committed, and `git HEAD` does not even carry the file at 00:39** —
`git cat-file -e HEAD:.agents/slop/graphcmp.bend` → *"exists on disk, but not in 'HEAD'"*, and
`git ls-tree HEAD .agents/slop/` lists no `graphcmp.bend`. `git status` flips between ` M` and
` A` across commands. **That is the jj index reset the brief warns about; do not read "tracked" or
"staged" as "committed".**

## 3. Step 1b — the tree COMPILES

One `--check-only` was taken **at a measured trough** (`bun … bend2/main.ts` count = 0, poll at
00:41:09), under the required watchdog:

```
$ .venv/bin/python checks/bounded.py --seconds 120 --mb 2048 -- \
      ./bin/bend .agents/slop/graphcmp.bend --check-only
ALL PROOFS CHECK
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=598 MB (ceiling 2048)  1s
```

**Verdict token `WITHIN-LIMITS`, rc=0, peak RSS 598 MB, wall 1 s.** The fixed harness type-checks.

## 4. Step 2 — `differ.py run` is SKIPPED: `bend` was contended and `graphcmp.bend` was in flux

The brief: *"if `bend` is held, SKIP and say so."* Measured:

- **Contention.** 8 polls at 10 s (00:35:53–00:37:12): compiler-proc count `0,1,0,1,3,0,3,1` —
  **non-zero in 6 of 8**; a second 12-poll run: `3,2,2,2,1,0` — non-zero in 11 of 12. Three
  distinct units were invoking the `bend` compiler (gates `tn_dunder_neg`/`tn_neg`/`ops-core`/
  `ew-consts`/`wk-cd`, `tinybendygrad/mixin/op.bend`, `examples/beautiful_mnist.bend`) plus a
  `bendwire/roundtrip.py` runtime session.
- **Flux.** `graphcmp.bend` was rewritten at **00:28:14, 00:37:03, 00:39:18** (3 edits in 11 min),
  including a revert and a re-apply of the fix itself. A 294 s `differ.py run` started in that
  window is exactly the `run34` failure: *"the port was edited MID-RUN … EVERY STEP FROM control
  ONWARD IS 'emit bend: 0 rows' — a compile break, not a measurement."*

**Therefore: no token, no wall time, no peak RSS for `differ.py run` — the run did not happen.**
The one token I do have (§3) is the compile check.

## 5. Step 3 — every `name=value` row of the on-disk `D0-run-summary.txt`, as READ

There is no NEW summary (no run). This is the **on-disk** file, `mtime 2026-10-06 15:47:32`, which the
`c64c59665` message already flags as predating the `WANT` wiring. Rows as read:

```
graphs=34
graphs-answered=33
graphs-unset=1
expect-moved=3
graphs-agree=31
graphs-disagree=2
byte-identical=31
not-comparable=0
stable-pairs=5 of 5
stable-failed=0 of 5
stable-differ=0 of 5
plants-disagree=7 of 7
cross=1 of 1
selfcheck=# SELFCHECK: OK
conflations=4 of 4
controls=5 of 5
oracle-selfcheck=# ORACLE SELFCHECK: FAIL
census-rc=rc=1
dev=CPU
lc_all=C
noopt=0
pythonhashseed=0
```

### Delta per pin (`checks/differ.py:233-273`), 14 GREEN / 3 RED

| status | key | pin | on disk | `checks/differ.py` |
|--------|-----|-----|---------|--------------------|
| GREEN | graphs | `34` | `34` | :241 |
| GREEN | graphs-unset | `1` | `1` | :241 |
| GREEN | graphs-answered | `33` | `33` | :241 |
| **RED** | **expect-moved** | `0` | `3` | :252 |
| GREEN | graphs-agree | `31` | `31` | :253 |
| GREEN | byte-identical | `31` | `31` | :253 |
| GREEN | not-comparable | `0` | `0` | :253 |
| GREEN | selfcheck | `# SELFCHECK: OK` | `# SELFCHECK: OK` | :254 |
| **RED** | **census-rc** | `rc=0` | `rc=1` | :254 |
| GREEN | stable-pairs | `5 of 5` | `5 of 5` | :270 |
| GREEN | stable-failed | `0 of 5` | `0 of 5` | :270 |
| GREEN | stable-differ | `0 of 5` | `0 of 5` | :270 |
| GREEN | plants-disagree | `7 of 7` | `7 of 7` | :271 |
| GREEN | cross | `1 of 1` | `1 of 1` | :271 |
| GREEN | controls | `5 of 5` | `5 of 5` | :271 |
| GREEN | conflations | `4 of 4` | `4 of 4` | :272 |
| **RED** | **oracle-selfcheck** | `# ORACLE SELFCHECK: OK` | `# ORACLE SELFCHECK: FAIL` | :272 |

**The three RED pins are the STALE SUMMARY, not a new regression** — `c64c59665` (2026-10-06)
already moved `WANT` for `mselect`/`stage`/`wmma` to `AGREE`, so `expect-moved` returns to 0 on the
next run, and `census-rc`/`oracle-selfcheck` are the in-flux run34 reading. I did **not** move them:
pinning a run I never took is the doctrine violation.

## 6. Steps 4 & 5 — NO `WANT` and NO `PINS` change, and why

- **`WANT` (`checks/differ.py:124-190`): unchanged.** `getaddr` stays ABSENT. Brief: *"ONLY if the
  run MEASURED it — do not write an expectation a run has not read."* No run ⇒ no row.
  `wantwire`'s rule stands: a graph that lands expecting nothing is a corpus that cannot fail.
- **`PINS` (`checks/differ.py:233-273`): unchanged.** No run ⇒ no measured values.
- **`graphs-disagree` IS NOT a `PINS` key.** The brief lists it among what to move; it exists only as
  a summary ROW (`checks/differ.py:592`) and in no pin. `len(PINS) = 17`, asserted against the on-disk
  summary above. **A pin that does not exist cannot be "moved".**

### What `getaddr` would do to the counts — PREDICTION, deliberately not written as a pin

If the fix holds and a run is taken: the bend side stops emitting the one-row `2:i1 4:NOOP … 3:BAD`
(bottom-arena) graph and emits the real 2-node `ALLOC + GETADDR` graph, so

- `graphs-unset` `1 → 0`, `graphs-answered` `33 → 34` (both functions of `corpus()` + the table);
- `getaddr` then lands as **either** `AGREE` (⇒ `graphs-agree` `31 → 32`, `byte-identical` `31 → 32`,
  `graphs-disagree` stays **2**) **or** `DISAGREE` (⇒ `graphs-disagree` `2 → 3`). Which one is a
  function of the PORT and can only be settled by a run.

**The fix touches only `g_getaddr`.** `flip` (row 6, `n(b1,b0)` vs `n(i1,i0)`, adjudicated PORT) and
`unshard` (row 8, fold refusal) are untouched by it, so **the 2 stay 2** unless the run finds a new
`getaddr` disagreement; they do **not** become 1.

## 7. Step 6 — `disagree-gate.py` (4 lanes) and `corpus-figure.py`, before and after

### `checks/disagree-gate.py --lane all` — reads `runs/graphcmp/D/`, runs no `bend`

- **Before** (last good, commit `c64c59665`): *"EVERY LANE OF disagree-gate IS NOW ok"* — 4/4 ok.
- **After, 00:37:06** — `rc=1`:
  ```
  ok    PIN
  FAIL  CITATIONS   .agents/slop/graphcmp.bend:1571 -- reads 'Bool.pick(...)' expected 'def rows.pick3'
  ok    COVERAGE ARTEFACTS
  ok    PLANT + DISARM
  ```
- **After, 00:41:xx and 00:44:xx** — `rc=0` again, 4/4 ok.

### THE INSTRUMENT THAT WAS GREEN AND WENT RED — `CITATIONS`

`checks/disagree-gate.py`'s `CITES` pins `(graphcmp.bend, 1564, "def rows.pick3")`. **The
`getaddrfix` fix added a 6-line comment + one `+a1` line at `g_getaddr` (`graphcmp.bend:1352-1358`),
which moved `def rows.pick3` from `:1564` to `:1571` (+7).** That is what turned `CITATIONS`
green→red at 00:37 — **the fix's own comment placement moved a line another instrument had cited.**
It went green again by 00:41 only because `graphcmp.bend` shifted again under concurrent writes;
`1564`/`1571` oscillated as the file was rewritten (§2). This is the same class AGENTS.md records:
*"a unit that changes WHERE its code goes to keep someone else's citation true is the inverse of the
fifteen line numbers this session has fixed."* **Reported, not fixed** — `graphcmp.bend` is
off-limits to this unit and currently single-writer-less.

### `checks/corpus-figure.py` (reads `runs/graphcmp/D/`; no `bend`)

| invocation | rc |
|------------|----|
| `… checks/corpus-figure.py` (DEV unset) | **1** |
| `DEV=CPU … checks/corpus-figure.py` | **1** |

Both print `RUN HEALTH : **FAILED** -- 14 of 17 pins green. RED: expect-moved=3; census-rc=rc=1;
oracle-selfcheck=FAIL`. **Unchanged before→after** and **not a verdict on the port**: it reads the
stale on-disk summary (§5). Note the `DEV=CPU` rc is normally 0; it is 1 here only because HEALTH
is read off the stale summary, and `14 of 17` matches the pin census in §5 exactly.

## 8. Leftovers and denominators

- **The leftover UNSET is `getaddr`** (`want/census.py`: corpus 34, `WANT` 33, UNCOMPARED 1
  `getaddr`, `declared()` misses 0 of 136 per-graph names, rc=0). It stays UNSET until a run reads it.
- **The other two disagreements are real and diagnosed** and untouched by this fix: `flip` (row 6,
  `arg`, BOTH — port types PERMUTE/FLIP as one int `ATuple`, `ops.py:428` refuses an int tuple) and
  `unshard` (row 8, `dtype`/`shape`, WRONG SHAPE PORT — `foldgap` REFUSED it because the fold needs
  `int(r.vmax+1)` and `dt_shape` gets no `BTable`). `disagree-gate` PIN reads `len(PIN)=2` and names
  both.
- **No `.txt` written**; this report is `.md`; no `bend` row count is quoted from a running job.

## 9. What would close this

1. Commit `graphcmp.bend` at `sha256 c11b6fb60375…` (or later) from **one** writer, ending the
   three-way edit.
2. Reconcile `checks/disagree-gate.py`'s `(graphcmp.bend, 1564, "def rows.pick3")` CITES to the
   post-fix line (currently `:1571`).
3. Take the run when `bend` is free and the substrate is settled:
   `checks/bounded.py --seconds N --mb 2048 -- .venv/bin/python checks/differ.py run`, read the
   TOKEN, then wire the measured `getaddr` `WANT` row and move `graphs-unset`/`graphs-answered`/
   `graphs-agree`/`byte-identical` (+`graphs-disagree` if `3`) and the two summary pins
   (`expect-moved`/`census-rc`/`oracle-selfcheck`) from THAT reading.

**No `git add`. No commit was made by this unit.**
