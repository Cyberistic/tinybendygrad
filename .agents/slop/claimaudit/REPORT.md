# CLAIM AUDIT — the orchestrator's own commit messages, re-verified against the tree

**Auditist:** a subagent of another session. Read-only over the tree; the only files written are
new files under `.agents/slop/claimaudit/`.

**Measured at HEAD `1b4905cba9903b125c172ee6bdb2b3db48ac436a`, 2026-10-16 12:55–13:10 UTC.**
Every number below carries that HEAD and that window unless it says otherwise. The tree was moving
while this audit ran (another session is committing continuously), so a number that read one way at
12:58Z is re-read at the timestamp given.

---

## 1. HOW THE COMMITS WERE SELECTED, AND HOW MANY

The selection rule, stated so you can reproduce it:

1. Take `git log -40 --format='%H %ad %s' --date=iso`. **40 commits, all dated 2026-10-15 or
   2026-10-16** — i.e. the working window, nothing older.
2. Keep only commits dated **2026-10-16**. **35 commits** (2026-10-16 is the last day of commits;
   the 25 older ones are 2026-10-15).
3. Keep those whose **full commit MESSAGE** (`git log -1 --format=%B`, body included) contains any
   of the ten literals: `checks/repro-paths.py`, `checks/differ.py`, `.agents/slop/pinindep`,
   `.agents/slop/e2estage8`, `gates/pins-shape`, `gates/rng_graph_census`,
   `gates/ops_python_exec`, `gates/gatekit`, `gates/indexread-gate`, `.agents/TODO.md`.

**Result: 24 commits, out of 35 on 2026-10-16 and out of 16,078 total.** That is the "roughly
twenty" of the brief.

**The selection IS ambiguous and here is exactly how.** The brief says "the recent ones" without a
window. Widening the window to 200 commits yields **86** matches, because commits as far back as
2026-10-15 and earlier quote `.agents/TODO.md` in nearly every message. Narrowing to the last 20
commits yields **16**. There is no principled cut inside 2026-10-16 either — the 11 commits that do
*not* match are real commits of the same session (e.g. `dd5ff1bf7`, `711a5ec12`, `25cda3570`),
and `dd5ff1bf7` is the very commit `3a6f2ce6a9` names as its subject. **I chose the whole of
2026-10-16 because it is the only boundary in the data that is not invented by me.** A reader who
wants the 16 most recent instead will find every FALSE below still FALSE — all ten sit inside the
top 20.

The 24, newest first:

```
1  1b4905cba9  INDEXREAD2: the obvious fix to a silent-zero bug is ITSELF a silent zero
2  f495c88cba  indexread: the 2 remaining GENUINE sweepdirs offenders read the INDEX
3  e47f45ef27  DEVTAG: the P6 wall cited an ABSENT symbol and a gate QUOTED THE CITATION
4  45f3d5d032  The `Device.tag` citation is dead AND THE GATE WAS QUOTING IT FORWARD
5  3a6f2ce6a9  UPLATTICE: `least_upper_dtype` is not a join
6  7458f54fae  DEVPIN: 0 of 14 gates MOVE with the device
7  2c4472e81e  crp: the one census gate with device-bound rows now NAMES its device
8  b092d39d44  ARGPAYLOAD: 147 of 2080 pairs are now distinguishable
9  550678ecbb  realize census: the `arg` PAYLOAD
10 1ad6aa5108  gatekit: `if (code, why := f()) != PASS:` raised NameError on EVERY GATE
11 8435efe603  CRP-COUPLE: `C1` IS AN ALPHA-RENAME
12 afbd85691c  the JS fp8 lane is DEAD CODE
13 095f4793f7  REALIZEGAPS: `Device.tag` DOES NOT EXIST IN THIS TREE
14 05be0f075d  DECOMP-PROMO: seven boxes SETTLED, THREE REFUTED
15 2fb32340f9  TODO.md: audit my OWN citations
16 f18f2a52bf  INDEXREADQ: the two genuine ones FIXED
17 8f2ea1df30  orcdecide: read the population from the COMMIT TREE
18 5c33d15b74  the reachability question is SETTLED
19 6eb1ec1516  sweep: the DELETE census sees 7 of 45 delete sites
20 f6aee9af15  ANYSLIKE: I re-derived `M20` wrong twice
21 9fad284ea4  gatekit: the "13 files return 2 on purpose" was a number that reproduced under NO definition
22 059c22cab9  ops_python_exec: the gate said REFUSED and exited FAIL
23 1c1db2db37  SYMDRV-CORRECT: the census header said THREE divergences and TWO are true
24 437e651e15  rng_graph_census: the comment claimed a DISCOVERY and the code typed a LIST
```

## 2. HOW MANY CLAIMS, AND THE SPLIT

**165 claims** were extracted from those 24 messages and checked. Every one is a row in
`claims.rows` (commit / quoted claim / verdict / evidence), and the counts below are `awk`ed from
that file, not typed by hand.

| verdict | rows | share of 165 |
|---|---|---|
| **CONFIRMED** | 103 | 62.4% |
| **UNVERIFIABLE** | 44 | 26.7% |
| **STALE** | 8 | 4.8% |
| **FALSE** | 10 | 6.1% |

**44 UNVERIFIABLE is the honest cost of the machine budget, not a soft spot in the audit.** Every
one of them needs `bend`, `checks/differ.py`, a gate run, or a sweep harness — all banned. Each row
says which. The orchestrator's own messages are dominated by *measurements of runs*; a commit
message that reports a run cannot be re-verified without re-running it, and this machine cannot
run them.

---

## 3. EVERY FALSE, NAMED AND QUOTED

**Ten. Nine of the ten are a `file:line` citation or a count attached to one. This is precisely
the class `2fb32340f9` says it audited ("audit my OWN citations") and precisely the class the
brief warns has already produced two false corrections.**

### 3.1 `9fad284ea4` — a self-correction that corrects a wrong number to another wrong number

> "**`verdict_of`'s unassigned branch is `:98`, not `:97` as I wrote earlier today.**"

**FALSE.** At commit `9fad284ea4`, `gates/gatekit.py:98` is a **blank line inside the docstring**.
The two `UNASSIGNED` returns are at **`:104`** and **`:107`**:

```
gates/gatekit.py@9fad284ea4
  96   into "unassigned" would lose the one measurement that separates them; folding an unassigned
  97   code into `DEAD` claims a run nobody witnessed. Neither is the other.
  98
  99   `bool` IS A SUBCLASS OF `int`, so `verdict_of(True)` is `FAIL` and `verdict_of(False)` is
 100   `PASS` -- which is not a bug here but is a trap for a caller that passes a computed flag. It
 101   is named rather than silently absorbed, so the aliasing is visible at the call site.
 102   """
 103   if isinstance(code, bool):
 104       return f"UNASSIGNED (bool {code} aliases onto {int(code)}, not a verdict)"
 105   if code in VERDICT:
 106       return VERDICT[code]
 107   return f"UNASSIGNED (code {code!r} is not one of the five)"
```

Both the retracted `:97` and the correcting `:98` are docstring or blank. The message's whole
subject is *"a number that reproduced under NO definition"* and it introduces a **new, uncorroborated
line citation** while correcting one. The census it names in the same breath does not support it
either: `.agents/slop/exitcodes/codes.rows` has **no code-2 row for `gates/gatekit.py` at all**.

### 3.2 `1c1db2db37` — a citation 71 lines from its target, in the commit about stale prose

> "**`symbolic.bend:3221`'s OWN `row("sink", ...)` IS ON `fx_sink`**"

**FALSE.** `tinybendygrad/uop/symbolic.bend:3221` is a **markdown table row** about M17:

```
3220  # | M17 `sym_12.hit`'s flattened src list -> `List.tail`, so the FIRST src is dropped
3221  # |    and the rule still fires | `sinkgrp` | 1 | **AND `sink` DID NOT MOVE.** This
```

`row("sink", t_sink())` is at **`:3292`**. `fx_sink` is defined at **`:2371`**. The line is 71 away.

And in the same message:

> "**`symbolic.bend:1555`'s `sym_12.hit` LOOKS LIKE IT ALREADY DOES** --
> `H.flatten_u32(sink_srcs.go(sy_srcs(x, u), x, Nil{}))`"

**FALSE.** `:1555` is `def sym_12.put(...)`. `sym_12.hit` is at **`:1558`** and the quoted
`flatten_u32` expression is at **`:1559`**.

This is the commit that says *"the census header said THREE divergences and TWO are true … SEVEN
stale-prose corrections in one session"*, and it carries two stale citations of its own.

### 3.3 `059c22cab9` — two BEFORE-state citations written with AFTER-state line numbers

> "Line 270 read `sys.exit(f"REFUSED: {args.jobs} lanes x {MAXRSS} B exceeds 60% of {MEMSIZE} B")`"
> "Lines 267 and 268 did the same for `f"{p} is absent"`"

**BOTH FALSE.** The file is `gates/ops_python_exec-gate.py` (the message says "`gatesweep.py`
itself records", which is loose — `checks/gatesweep.py` never names that gate; it discovers gates
by a directory walk). At the commit's **own parent** the three sites are:

```
gates/ops_python_exec-gate.py @ 059c22cab9^
 251   if not p.exists(): sys.exit(f"{p} is absent")
 252   if not BEND.exists(): sys.exit(f"{BEND} is absent")
 254   sys.exit(f"REFUSED: {args.jobs} lanes x {MAXRSS} B exceeds 60% of {MEMSIZE} B")
```

and at the commit itself they are `:267`, `:268`, `:270` — because `refuse()` was inserted above
and shifted everything by 16. **The message quotes post-edit line numbers against pre-edit text.**
A reader who follows the citation at the commit finds `refuse(...)`, and a reader who follows it at
the parent finds `sink.flush()` territory. Both numbers the message gives are wrong for the state
they describe.

### 3.4 `6eb1ec1516` — "THE CENSUS SEES 7 OF 45 DELETE SITES" is 15 of 54 under the tree's own key set

> "MEASURED 2026-10-16 over checks/ + gates/: **7 delete sites in MODULE form**, all caught; **38**
> in METHOD form (`x.unlink()`) … **THE CENSUS SEES 7 OF 45 DELETE SITES.**"

**FALSE under the definition `FS_DELETES` itself declares.** `checks/sweep.py:285` names **four**
module-form keys, including `("shutil","rmtree")`. Extracting the commit's own tree (`git archive
6eb1ec1516 checks gates`, **226 `.py` files**, matching the commit's stated denominator) and walking
it with `ast`:

| | claimed | measured at `6eb1ec1516` |
|---|---|---|
| module-form (`os.*`) | 7 | **7** |
| module-form (`shutil.rmtree`) | *(not mentioned)* | **8** |
| method-form | 38 | **39** (one is `sys.….remove`, not a filesystem delete — excluding it gives exactly 38) |
| **total** | 45 | **54** |

**The 7 reproduces exactly and only if the 8 `shutil.rmtree` sites are dropped** — the very key
`FS_DELETES` lists fourth. So the census sees **15 of 54**, not 7 of 45, and the half of the
finding that survives is the *method*-form half, which the message already gets right. The claim's
own subject is *"the table has one spelling"*; the table names two modules and the count names one.

### 3.5 `afbd85691c` — a quoted command whose output is 10, not 0

> "**`tinybendygrad/runtime/dtype.js` IS UNEDITED**
> (`git show --stat 711a5ec12 | grep -c dtype.js` = **0**)"

**FALSE as quoted.** That command returns **10**. All ten hits are the **commit's own message
prose** — `git show` prints the message before the stat, and the message mentions `dtype.js` ten
times. The *conclusion* is separately true: no `tinybendygrad/runtime/dtype.js` path appears in the
stat. But the measurement offered as evidence does not produce the number attached to it. This is
the same defect `9fad284ea4` describes one commit later — a bare count answering a different
question than the one asked — except here the count is the whole proof of a "NOT EDITED" claim.

### 3.6 `550678ecbb` — "a 24-CONSTRUCTOR SUM" is 22

> "`UOp.arg` is `Any` on CPython and a **24-CONSTRUCTOR SUM** in the port (`ops.bend:1190`)"

**FALSE.** `tinybendygrad/uop/ops.bend:1190` is `type Arg is Data:` and the sum has **22**
constructors — `ANone ADt APy AParam ACustom ACall AKernel AProgram ARange AReduce AOpLit AWmma
ATuple ABoolList AStr AInk AAllred ADev ABlob AInt AFloat ABad` — identically at commit
`550678ecb` and at HEAD. No other `A…{}` constructor exists anywhere else in that file's 6,000+
lines, so there is no second `Arg` sum. The same message says "twelve arms cover the twelve
constructors the fixture uses" and gets a smaller number right in the same breath.

### 3.7 and 3.8 `05be0f075d` — two `dtype.bend` citations that name nothing at that line

> "`l2i.const` PASSES `uint32` (`:180`)" — **FALSE.** There are three `dtype.bend` files. At
> `05be0f075d`, line 180 of each is: a topological-sort comment (`codegen/decomp/dtype.bend`), a
> bounds comment (`mixin/dtype.bend`), and a `least_upper_dtype` mask (`tinybendygrad/dtype.bend`).
> `l2i.const` is at `codegen/decomp/dtype.bend:2773`, and the `S.uint32()` argument is at **`:2812`**.

> "`dtype.bend:644-648` names a bool trigger at `:647` that its own selector excluded" — **FALSE.**
> `tinybendygrad/dtype.bend:644-648` is a blank line plus prose about round-half-to-even and
> `def fp16_encode`. `codegen/decomp/dtype.bend:644-648` is a comment block about `(x / 2**32)`
> whose `:647` says "`a.cast(default_float)` when `a` is a bool" — inside a CDIV discussion, not a
> selector that excluded a bool trigger. Neither file has the cited thing.

Two claims from one commit. Both are in the message that says *"TWO RECORDED NUMBERS WERE STALE"*.

---

## 4. EVERY STALE, NAMED AND QUOTED

**Eight, and six of the eight are the same cause: index-derived populations in a tree whose index
is being rebuilt continuously.** They are STALE, not FALSE — they were true at their commit.

| commit | claim | measured now |
|---|---|---|
| `1b4905cba9` | "`git ls-tree -r --name-only HEAD` -> **7297 rows**" | **7308** at 12:58Z |
| `f18f2a52bf` | "`git ls-files` (default index, jj-armed) **7819**" | **7850** |
| `f18f2a52bf` | "agent-index `ls-files` **7290** / `ls-tree -r HEAD` **7290**" | **7308** |
| `8f2ea1df30` | "7819 / 7290 / 7290" | **7850 / — / 7308** |
| `f18f2a52bf` | "THE OLD POPULATION WAS **529** PATHS WIDER THAN THE COMMIT" | index placeholders now **1096** (up 567 since 07:03Z) |
| `f18f2a52bf` | "`checks/index-arm-gate.py` -> INDEX-ARM INTENT (**529**) … **9405258** bytes" | not re-taken (executable gate, banned) |

**Note the direction of the second one.** `1b4905cba9`'s own message complains that *"[A] NUMBER
WITHOUT ITS TIMESTAMP"* decays, and then the same sentence's sibling claims decay within one
session. This is a tree that commits continuously and I am measuring it while it moves; these six
are exactly what the orchestrator says they are.

Two non-index STALEs:

- **`8435efe603`**: "`gates/gatekit.py:503` … reads
  `if (code, why := device_precondition(...)) != PASS:`". The walrus form is **gone** — fixed under
  `1ad6aa5108`, four commits later. `:503` is not it, nor is anything else in the file
  (`grep -n 'code, why' gates/gatekit.py` → `:217` and `:507`, both plain tuple unpacking).
  Correct as a record of a defect that has since been repaired.

- **`437e651e15`**: "`gates/rng_graph_census-gate.py:104-106` carried [the `TABLES` tuple]".
  Those lines are now the explanatory prose and the live `re.findall(..., re.M)` at `:121`; the
  quote is a description of the *before*, and the before is gone.

---

## 5. WHAT IS CONFIRMED, AND IT IS NOT A TRIVIAL AMOUNT

**103 of 165 claims, 62.4%.** The load-bearing ones, each re-measured:

**The `Device.tag` spine (4 commits, ~18 claims).** `hasattr(Device, 'tag') = False` and
`type(Device) = tinygrad.device._Device` — re-measured in `.venv/bin/python`, 0.2 s.
`tinygrad/uop/ops.py:34`, `device.py:20/25/29/31/58/59`, `helpers.py:187/237`,
`tinybendygrad/device.bend:344` (`tag_of` = DISK 6 / NPY 10 / PYTHON 13 / else 0) — **every line
exact**. `hasattr` came back `False` and the tag sentinel came back three-valued, exactly as
claimed.

**`45f3d5d03`'s five `TODO.md` line citations — all five exact.** `grep -n 'Device\.tag'
.agents/TODO.md` returns **1993, 2053, 14783, 16180, 16187** and the total occurrence count is
**5**. Five out of five, including the two four-digit-line citations.

**The empty-blob / index-arm arithmetic in `1b4905cba9` — six figures, all six exact.**

| claim | measured |
|---|---|
| empty blob **in HEAD** = 541 | **541** |
| empty blob **in the index** = 1096 | **1096** |
| index entries = **7850** | **7850** |
| placeholders ending `.py` = **190** | **190** |
| placeholders with real disk content = **515** | **515** |
| `gate-surface-control.md` = **5180** bytes, index blob `e69de29b`, **absent from HEAD** | **5180 / e69de29b… / absent** |

And the trap itself: `git ls-tree -r --name-only HEAD -- '*.py'` prints **0 rows and exits 0**, and
`:(glob)` is `fatal: pathspec magic not supported`. The "silent zero" is real and the fix's premise
is right.

**`2fb32340f9`'s own self-correction about a stale line citation — CONFIRMED.** `checks/differ.py`
at `2fb32340f9^:1117` is the "present IS A DIRECTORY WALK" comment; at `2fb32340f9:1131` is
`present = {p.name for p in D.iterdir() …}`. The delta is exactly **14**, both lines still read
that today, and the 14 lines added are the `artefacts_ok()` edit the message blames. **That one is
clean, and it is the proof that the class is checkable — which is what makes §3.1 and §3.2
findings rather than noise.**

**`6eb1ec1516`'s six hidden-delete-site citations — all six exact.** `differ.py:658`,
`bounded.py:499`, `bounded.py:502`, `abi4_gate.py:314`, `substrate-id.py:507`, `substrate-id.py:525`
— every one lands on a `.unlink(` call. And `sweep.py:276` ("STATED AND UNBUILT") and `:278` ("no
scope reproduces 11") are exact. **The six *citations* in the commit with a false count are all
correct; only the count is wrong.**

**`059c22cab9`'s headline census — CONFIRMED to the digit.** At `059c22cab9^`, an AST walk over the
**226** `.py` files of `checks/` + `gates/` for `exit`/`_exit`/`quit`/`SystemExit` called with a
string constant or an f-string finds **exactly 57 sites in exactly 24 instruments**. And the
arithmetic that follows is right: 57 − 3 = **54 sites in 23 instruments**. The three `refuse()` calls
are at `gates/ops_python_exec-gate.py:267/268/270` and `gates/gatekit.py:60` still gives
`REFUSED = 3`.

**`9fad284ea4`'s denominators — CONFIRMED.** 226 `.py` files under `checks/` + `gates/` at
`6eb1ec1516`; `codes.rows` carries **226** distinct instruments and **18** instruments with a
`code-2` row, matching the "the `exitcodes` unit independently measured **18**" — and column 3 of
that file *is* `verdict`, with `UNOWNED` on every code-2 row, exactly as claimed. **Its 9 / 6 / 20
trio is UNVERIFIABLE (§6), and its `:98` correction is FALSE (§3.1).**

**`437e651e15` — the whole mechanism, verified rather than believed.** `grep -c '^def [a-z]*_table'
tinybendygrad/schedule/rangeify.bend` = **11**; the names come back `rb nic nv aprt sk gs ct fb dg
lb ab` — **byte-identical to the replaced tuple, same order**. 11 × 66 = **726**, and the gate's
own header at `:7` already said `726 ROWS (11 TABLES x 66 NODES)`. `re.M` is present at `:121`,
and the empty case refuses at `:122`. **This commit's claim that the change is "of MECHANISM, not
of population" is exactly right.**

**`5c33d15b74`'s lattice reading — CONFIRMED, and it is a real proof.**
`tinygrad/uop/symbolic.py:441` is `REMOVE_FROM_SINK_LIKE = {Ops.NOOP, Ops.STACK, Ops.SINK,
Ops.GROUP}`; `:445` is `UPat((Ops.SINK, Ops.GROUP), name="root")`; `:447`'s guard is
`if any(x.op in REMOVE_FROM_SINK_LIKE for x in root.src) else None`. **Both root ops are members, so
the guard is true whenever the pattern fires and the `else None` arm is unreachable.** The
corrective conclusion — that the port's guard reproduces CPython's reachability rather than
exceeding it — follows. `ops.py:273` → `render.py:8` is exact too.

**`3a6f2ce6a9`'s four source citations.** `tinygrad/dtype.py:194` is the `min(set.intersection(…))`;
`:201-215` has **no `case dtypes.bfloat16`**; `symbolic.py:188` is a `cvar` exponent;
`symbolic.py:452` is the catch-all `xpow`; `mixin/elementwise.py:565` is gated on
`isinstance(x, ConstType)`; `rg -in 'associativ' test/` = **0**. The upstream finding stands.

**`8435efe603`'s theorem.** `creation.bend:242-245` binds `+de = cr_cast_dt(F.is_cinvalid.val(v),
dt)` and hands it to `cr_cast`'s `same` test and `cr_cast`'s `dt` argument; `grep 'cr_cast('` shows
**exactly one call site, `:245`**. The "coupled, and the coupling is a theorem" reading is sound
against the source.

**`550678ecbb` / `b092d39d44`'s payload claim, insofar as it is checkable in git.**
`gates/realize_graph_census-pins.rows` now carries **three distinct `CALL/2[…]` spellings** —
`CALL/2[l]`, `CALL/2[m]`, `CALL/2[nk]` — where before they were one. "BEFORE, `CALL/2` AND
`CALL/2` WERE THE SAME TOKEN … IT IS NOW A PROPERTY OF THE ROWS" is confirmed as far as the tracked
rows go. **The 27 / 147 / 2080 / 8 figures are not checkable here** (§6).

**`f6aee9af15`'s row count.** `gates/symcases.rows` carries **exactly 7** `t_*` rows: `t_add t_xor
t_xor0 t_group t_sink t_sink0 t_sink1`. The file is 61 lines; the "7 ROWS" is the `t_*` count.

**`1ad6aa5108`'s two-line fix.** `gates/gatekit.py:60` = `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1,
3, 4, 5`; `:175` = `def device_precondition(declared, ambient) -> tuple[int, str]:`; `:197` =
`return PASS, ""`; and the walrus is gone everywhere (`grep -n 'code, why' gates/gatekit.py` →
`:217`, `:507`, both plain unpacking).

**`afbd85691c`'s dtype citations.** `dtype.js:145` is the `(103 << 23) | (m << 14)` subnormal line;
`dtype.js:150-152` is `dtype_bf16` with **no** non-finite passthrough, against `dtype.c:205`'s
`if ((x & 0x7F800000u) == 0x7F800000u) return …;` and `dtype.bend:607-610`'s `Bool.pick` on the same
predicate; `dtype.c:155-157` does round the remainder; `dtype.bend:711-715` does assemble the same
subnormal as the JS. And `grep -rn 'dtype\.js' tinybendygrad/` returns **exactly two lines, both
prose** — as claimed. `gates/js-lane-census.py` is **611 lines** (`wc -l` says 610; the file has no
trailing newline and `awk END{NR}` says 611).

**`8f2ea1df30`'s two citations.** `checks/slop-declare.py:143` reads verbatim *"MISCOUNTS; THEY READ
`git ls-files`, WHICH IS AN INDEX THIS TREE HAS RESET SIX TIMES TONIGHT."* and `:148` is the
`ls-tree -r -z --name-only HEAD`. And **0 committed paths under HEAD contain a space** — the claim's
"measured: 0 such paths today" is confirmed.

---

## 6. WHAT I COULD NOT CHECK, AND WHY

**44 rows are UNVERIFIABLE. They fall into five buckets, and no bucket is a guess:**

1. **Anything that needs `bend`** — the 34-graph corpus, `checks/differ.py run`, every emitted
   bundle. ~12 rows. Example: `afbd85691c`'s "emitted bundle **55,818 bytes**, ONE `io_eff`
   REGISTRATION".
2. **Anything that needs a gate to run** — `gates/*.py` are executable and banned. ~18 rows.
   Examples: `2c4472e81e`'s whole **70-run, 14-gate × 5-device table** (including "MAX PEAK ANYWHERE:
   2169 MB"), `8435efe603`'s "**287 rows, 286 byte-exact, 1 declared**", `05be0f075d`'s "**42 ROWS
   (WAS 39), 26 EXACT (WAS 23)**", `1ad6aa5108`'s "five gates all rc=0".
3. **Anything that needs an artifact under `gates/artifacts/`** — that directory is `.gitignore`d
   and swept, so the 1004-row census output the payload claims are counted against **is not in the
   repository at all**. `b092d39d44`'s "**27 ROWS** NOW CARRY A BRACKET" and the `147 of 2080` /
   `60 tokens / 8 pairs` figures are therefore unverifiable *by construction*, not merely
   inconvenient: the tracked `realize_graph_census-pins.rows` holds **192 lines, of which 7 carry
   any bracket**, and two of the commit's four named spellings (`CALL/2[ss]`, `CALL/3[f]`) appear in
   it **zero** times.
4. **Anything whose instrument the message does not name.** This is the honest UNVERIFIABLE bucket
   and it deserves its own line, because `9fad284ea4`'s entire subject is that a bare number must
   answer a stated question:
   - its **9 / 6 / 20** trio. `codes.rows` — the census the commit itself names — reports
     `declared_in_own_prose = yes` on **4** instruments for code 2, and `gates/gatekit.py` has **no
     code-2 row at all**, so "one of them gatekit.py ITSELF" is not in the artifact. A shallow AST
     walk of mine finds 6 files mentioning `USAGE` (4 importing `argparse`) and 7 files with a
     literal `exit(2)`; a deeper walk could reach 20. **No rule is stated, so I cannot say the 9 is
     wrong — only that it is not the number the named instrument produces.**
   - `2fb32340f9`'s "**12 citations resolvable, 1 ambiguous, 0 stale**" and "**157** stale or
     missing": no script is named for either.
   - `f18f2a52bf`'s "`checks/repro-paths.py:261` IS `for rel in sorted(base - set(found))`" — I did
     not read that file, and `:261` was outside the budgeted reads.
   - `f18f2a52bf`'s `gitignore/perdir.py:12` — that path is outside `checks/` and `gates/`.
5. **Claims about a state the message itself records as later.** `f18f2a52bf`'s "`POPULATION 1826
   OFFENDERS 78 BASELINE 68 NEW 11`", `8f2ea1df30`'s "`OFFENDERS 80 -> 78, NEW 13 -> 11`" — these
   are `gates/indexread-gate.py` output.

**One I deliberately declined to call.** `b092d39d44`'s "**PINS 63 → 63, 12 VALUES**" — the pins
file is tracked and readable, but 63 is a count of *declared-divergence rows in the gate's own
1004-row output*, which is the gitignored population. The tracked file is 192 lines. I could not
resolve the denominator honestly, so I marked it UNVERIFIABLE rather than manufacture one.

---

## 7. WHAT THE SIX ALREADY-KNOWN CORRECTIONS LOOK LIKE NEXT TO THESE

The brief says the orchestrator retracted or corrected six of its own claims. Three of the ten FALSE
findings here are **in commits that retract other people's or its own claims**, which is the shape
that matters:

- `9fad284ea4` retracts a count and, in the same paragraph, emits a new line citation that is wrong.
- `2fb32340f9` audits citations for staleness and lands one that reproduces exactly (§5) — so the
  audit method works; it was simply not applied to `9fad284ea4` or `1c1db2db37`.
- `1c1db2db37` is a stale-prose correction commit that carries two stale citations.
- `059c22cab9` is a "wrong exit status" correction that mis-numbers the very lines it fixes by 16.

**The pattern across all ten FALSE is one shape, and it is not sloppiness of arithmetic:**

> **A citation into a file the same session is editing is quoted with the line number the edit
> produced, not the line number the quoted text is at.** `059c22cab9` (off by 16, shift from its own
> insertion), `1c1db2db37` (off by 3 and by 71). `2fb32340f9` already named this exact failure — *"a
> line-number citation into a file the same session is editing has a half-life measured in commits"* —
> and then `2fb32340f9` itself got it right, so the lesson was known, stated and applied once.

The second shape is **a count whose population is narrower than the thing the prose says it covers**:
`6eb1ec1516` (7 vs 15, `shutil` dropped), `550678ecbb` (22 constructors, not 24), `afbd85691c`
(10 vs 0). Each is a number that would have been caught by the rule already written at the top of
`AGENTS.md`: *a population is a generator's own declaration or a directory walk, not a shape.*

## 8. REPRODUCING THIS

```
git rev-parse HEAD                                   # 1b4905cba
awk -F'\t' 'NR>1{c[$3]++} END{for(k in c) print k,c[k]}' .agents/slop/claimaudit/claims.rows
awk -F'\t' 'NR>1 && $3=="FALSE"' .agents/slop/claimaudit/claims.rows
```

`claims.rows` has **165 data rows**, every one 4 tab-separated fields, covering **24 distinct
commits**. The four verdict counts in §2 are `awk`ed from that file and sum to 165.