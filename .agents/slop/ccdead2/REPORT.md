# ccdead2 — the `cc` instrument was DEAD; it is now REVIVED, and the count is 2 FILES

Measured 2026-10-07 on `checks/substrate.py` at the working copy (`./bin/bend` → Bend 2.0.35,
`cc` = `/usr/bin/cc`, `node` = `/Users/cyberistic/.nub/node-shim/node`). Tree is edited
concurrently, so re-run before trusting any number here.

I read `.agents/slop/ccdead/` first (its two `.out` files are the only thing it left; both
`.err` are 0 bytes) and did **not** re-derive its measurement — I reproduced it once to
confirm the `-n` cell, then my job was to *finish* the report and land the fix.

---

## 1. The two `.c` files, `file:line`, and what the sweep prints

| path | lines | route | before | after |
|---|---|---|---|---|
| `tinybendygrad/runtime/dtype.c` | 328 | `cc -fsyntax-only + bend's C context` | `NO INSTRUMENT ... NOT JUDGED` | `WARM` |
| `tinybendygrad/runtime/sz.c` | 119 | `cc -fsyntax-only + bend's C context` | `NO INSTRUMENT ... NOT JUDGED` | `WARM` |

BEFORE (`.agents/slop/ccdead2/probe-absent.out`; same as `ccdead/two-c-headed.out`), un-`-n`:

```
NO INSTRUMENT  tinybendygrad/runtime/dtype.c  (328 lines)  :: cc and a compiling bend C context are both required, and one is absent
NO INSTRUMENT  tinybendygrad/runtime/sz.c  (119 lines)  :: cc and a compiling bend C context are both required, and one is absent
ROUTE   bend=0  cc=0  node=0  no-instrument=2  (of 2 file(s))
```

AFTER (`.agents/slop/ccdead2/two-c-fixed.out`), un-`-n`:

```
WARM        tinybendygrad/runtime/dtype.c  (328 lines)  [cc -fsyntax-only + bend's C context]
WARM        tinybendygrad/runtime/sz.c  (119 lines)  [cc -fsyntax-only + bend's C context]
ROUTE   bend=0  cc=2  node=0  no-instrument=0  (of 2 file(s))
```

AND THE `-n` CELL IS A TRAP, NOT THE SAME MEASUREMENT. `checks/substrate.py:437` short-circuits
`if opts.names_only and inst != "none"` **before** the context is ever built, so under `-n`
these two dead files print `SKIP-VERDICT` and the dead instrument is **invisible**:
`ROUTE ... no-instrument=0` (`ccdead/two-c.out:3`). `-n` cannot see a DEAD instrument, because a
DEAD instrument still has a *route*. The `NO INSTRUMENT = 2` came from the un-`-n` run.

## 2. WHAT THE COUNT COUNTS — 2 FILES, one instrument, one class, one cause

Read the code, not the label. `half1` (`checks/substrate.py:401+`) walks files and increments
`tally["none"]` **once per file**, at `:442` (route = `none`) and `:479` (route = `cc`/`node`/`bend`
but the instrument is absent / `Ctx.ok()` is False). `instrument_for` (`:386`) returns one of
`bend`/`cc`/`node`/`none` per file.

So `NO INSTRUMENT = 2` is **two FILES** that funnel into the single `none` bucket. Both are the
SAME class (`.c`), the SAME instrument (`cc`), and the SAME single cause: `Ctx.ok()` returned
False. It is **not** two instruments and **not** two classes. A `.c` instrument that judges 2
files and one that judged 300 would print the same `no-instrument=300` — the count is a cell over
files, and the instrument/class/cause must be read from the head lines, not the tally.

## 3. THE COUNT ALREADY NAMES THEM — and the same line the task pointed at

The sweep already prints, for each unjudged file, `NO INSTRUMENT  <path>  (<n> lines)  :: <why>`
(`checks/substrate.py:443` and `:482`), exactly the way `PORT ALARM 1` names `test/_probe/v5.bend`.
So the premise "a count of unjudged files that names none of them" is **FALSE in the un-`-n`
run** — the names are on lines 1–2 above. No one-line naming fix is needed; the names are already
there. Two *real* but separate defects remain, and I did NOT fix them because they are the
frozen shell oracle's own behaviour (`oracle-check.sh:463-470`) and the port must reproduce it
byte for byte:

- under `-n` the name is suppressed to `SKIP-VERDICT` (`:437`) — a DEAD instrument hides;
- with `tally["none"]>0`, `findings` stays 0, so the tail prints
  `SUBSTRATE CLEAN: ... each judged by its OWN instrument` and **exits 0** (`:846`, `:854`).
  A file with NO INSTRUMENT is *printed* as not-a-pass and *reported* as a pass. **KNOWN GAP,
  NAMED.**

## 4. HISTORY OF `C_PROBE` — NEVER COMMITTED, and its seam was RETIRED

`C_PROBE` was `.agents/slop/guardfix/probe-c.bend` (`substrate.py`, before this unit). Findings:

- **NONE in `git ls-files`.** `git log --all -- '.agents/slop/guardfix/probe-c.bend'` → empty.
- **NO BLOB in any ref.** `git rev-list --all --objects | grep -i probe-c` lists only
  `.agents/slop/probe-cc.bend`, `.agents/slop/probe-c/*.bend` (ten unrelated scratch probes) and
  `tinybendygrad/uop/zz-probe-c2d.bend` — never `guardfix/probe-c.bend`.
- **IT IS `GITIGNORE`d BY DESIGN.** `git check-ignore -v .agents/slop/guardfix/probe-c.bend` →
  `.gitignore:37:probe-*.bend`. So it was a scratch file that could NEVER be tracked; it vanished
  and git could not restore it. **This is NOT the 15th recovered instrument: it was NEVER written
  to git, which is a different finding from a deleted one.**
- **THE SEAM IT NAMED WAS RETIRED TOO.** `RESULTS.md:87` says the probe "reaches one `dtype.bend`
  seam so `bend -o` emits that runtime", and `C_PROBE_FOREIGN` was `runtime/dtype.c`. Commit
  `9e9aaac47` (2026-10-05 02:20) made `dtype.bend` `ALL PROOFS CHECK` by **removing its
  `import "./runtime/dtype.c"`**. `grep -rn 'import .*dtype\.c' tinybendygrad/` now finds only a
  comment in `mixin/dtype.bend:63`. **Nothing in the tree emits `dtype.c` any more**, so even a
  restored probe named against `dtype.c` could not have worked. `sz.bend` still reaches
  `runtime/sz.c` at `sz.bend:125,133`, which is why the marker moved to `sz.c`.

## 5. DECISION: WRITE (and repoint), LANDED

`RESTORE` was impossible (no blob). I judged `WRITE` worth it **only** because the seam still
exists through `sz.bend`, and I proved the probe moves before keeping it.

- **`checks/c-context.bend` (NEW, TRACKED path — does NOT match `probe-*.bend`).** A 26-line
  program (34 lines): two `Sz.*` foreign defs, each `import "../tinybendygrad/runtime/sz.c"`, and a `main`
  that calls one. `bend checks/c-context.bend -o gen.c` → rc 0, 82 489 B, marker present once,
  **peak RSS 115 MB / 1 s** (well inside the 2 048 MB ceiling and the sum-precondition).
- **`substrate.py`:** `C_PROBE = "checks/c-context.bend"`; `C_PROBE_FOREIGN =
  "tinybendygrad/runtime/sz.c"`. The preamble before the first foreign source is bend's generated
  C either way; the marker only says where the foreign block begins.
- **TWO LATENT BUGS IN THE NEVER-RUN `Ctx.ok` ARM, fixed:** `at.isdigit()` was called on an `int`
  (`at` comes from `next(..., 0)`) → replaced with `at < 2`; and `IF_OPEN`/`IF_CLOSE` were `str`
  regexes matched against the emit's `bytes` lines → made `bytes`. **The `Ctx` arm had never once
  run, so the Python's "reproduces the shell on EVERY input" claim was untested for `cc` until now.**

THE PROBE MOVES — three plants, all in `$TMPDIR`/`.agents/slop/ccdead2/`, tree never written:

| plant | must | got |
|---|---|---|
| a byte copy of `sz.c` | `WARM` | `WARM`, `ROUTE cc=1` (green not by accident via bend) |
| that copy + one bad line | `COLD` | `COLD :: broken.c:120: error: use of undeclared identifier 'this'` |
| `C_PROBE` absent | `NO INSTRUMENT` **by name** | `NO INSTRUMENT  tinybendygrad/runtime/sz.c :: ...`, `no-instrument=1` |

**STILL REQUIRED, AND I CANNOT DO IT: `checks/c-context.bend` MUST BE COMMITTED.** It is untracked
right now (`git status`: `A checks/c-context.bend`, index state under the `jj` server is not
trusted). An untracked probe is the same defect one boot later — the reason the last one died.

## 6. THE DENOMINATOR — instruments, reachable, dead, files unjudged

`instrument_for` declares exactly **3 instrument classes** (plus `none`) over `POP_SUFFIXES =
(".bend", ".c", ".js", ".mjs")`, `POP_ROOT = tinybendygrad`. Population measured by
`os.walk` (the walk, not a suffix filter): **140 files — 134 `.bend`, 2 `.c`, 3 `.js`, 1 `.mjs`**;
every one is a router class, so `UNJUDGED` (non-router) = 0.

| instrument | routes | files it JUDGES | reachable? | before | after |
|---|---|---|---|---|---|
| `bend --check-only` | `.bend` | **134** | yes (`./bin/bend` → bun + `references/bend`) | live | live |
| `cc -fsyntax-only + bend C context` | `.c` | **2** | probe present **and** compiling | **DEAD: 2 files** | **REACHABLE: 2 files** |
| `node --check` | `.js`/`.mjs` | **4** | yes (`node` on PATH) | live | live |

**DEAD count before this unit: 1 instrument, judging 2 of 140 files (1.4%) — and it was `cc`, the
one that exists precisely because these files are not Bend programs.** That is the whole
denominator: `NO INSTRUMENT = 2` was one cell, and the cell carried a *2-file* instrument, not a
300-file one. After the fix, 3 of 3 instruments are reachable and judge 140 of 140 files.

## 7. Files

- `checks/c-context.bend` — the landed probe (MUST BE COMMITTED).
- `checks/substrate.py` — `C_PROBE`/`C_PROBE_FOREIGN` repointed; `Ctx.ok` un-broken.
- `two-c-fixed.out` / `.err` — after: `WARM`, `cc=2`.
- `probe-absent.out` — after, probe removed: `NO INSTRUMENT = 2` by name, **rc 0** (the inherited lie).
- `two-c-fixed.err` — bounded records: emit 35 MB, context compile rc 0, both fragments rc 0.
