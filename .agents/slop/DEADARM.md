# DEADARM — what nothing in this tree can observe

Unit: dead-arm census, 2026-10-04. **Nothing committed. No `.bend` under `tinybendygrad/` was
edited; no `LAWS/**`, no `PROOF*.bend`, no `rebase-gate.py`, `cstyle-gate.py`, `graphcmp*`,
`reader-guard.py`, `reader-contracts.tsv`, and no other unit's `.agents/slop/` tree.** The files I
created are `.agents/slop/deadarm/**` and this one.

| what | where |
|---|---|
| the oracle-side census, generalised from `nvdup-deadarm.py` | `deadarm/deadarm.py` |
| its shard driver | `deadarm/sweep.sh` |
| the shard merge, with the denominator | `deadarm/deadarm-merge.py` |
| the port-side census (defs and arms) | `deadarm/bendarm.py` |
| the port-side merge, with the denominator | `deadarm/bendarm-merge.py` |
| raw output | `deadarm/shard-0.tsv` … `shard-9.tsv`, `deadarm/bendarm.tsv.gz` (12 MB gzipped to 1.4), `deadarm/bendarm-run.txt` |
| rules | `.agents/slop/notes/bend2-constraints.md`, appended as `DEAD-1` … `DEAD-9` |

---

## 0. THE LAW, AND WHY COUNTING ABSENCE IS THE ONLY WAY

> **D2 = a dead `try:` arm. IT COSTS 0 — and that is the point: A LINE THAT DOESN'T EXECUTE HAS NO
> OUTPUT LINE TO COUNT, SO IT IS INVISIBLE TO EVERY DUPLICATE INSTRUMENT IN THIS PROJECT, INCLUDING
> THE FIXER THAT WAS WRITTEN TO CLEAN UP AFTER EXACTLY THIS.**

The consequence, stated as a method: **you cannot find unobservable code by counting observable
code.** Every multiplicity census in this project counts emitted rows, so it is blind by
construction to anything that emits none. The census has to diff *emitting source lines* against
*lines a tracer saw execute* — the opposite direction.

**Complementarity with the wall census, as asked.** A unit is censusing 1,026 `TODO(p3)` markers
across 82 files. Those are **written-down** gaps. Dead arms are **unwritten** ones — nobody left a
note, which is exactly why no instrument reports them. Neither census answers the other's half: my
`deadarm.py` finds zero `TODO(p3)` markers (it is looking for dead *statements*) and the wall census
finds zero dead statements (it is looking for `TODO`s). **There is no overlap to deduplicate.**

---

## 1. THE TOOL, GENERALISED — `deadarm/deadarm.py`

`nvdup-deadarm.py` does this for one file with a **textual** selector, `^\s*row(`. That selector is
its own limit, stated and measured by its own `longhand` cell. The generalisation replaces the
selector with a **semantic** one and the population with the whole tree:

1. **`ast` finds the instrument's sink functions** — the functions that can put a line in the lane.
   Two mechanisms, because the tree uses both:
   * **direct**: the function reaches a write primitive (`print`, `.write`, `os.write`, …);
   * **indirect**: it mutates a module-level global that a direct writer later reads. This is the
     shape 70 of the instruments actually use — `nv-oracle.py:27-30` is `ROWS = []` /
     `def row(nm, v): ROWS.append((nm, str(v)))`, and the printing happens once, at the end of
     `main`. **A selector that stops at the first hop finds neither `row` (it does not print) nor
     `main` (it does not print), and reported a 337-emitting-line instrument as having 10 sites.**
     That was the first run of this file, and the DISARM cell caught it.
2. **`ast` maps every sink call site to the line of the innermost enclosing STATEMENT**, because
   `sys.settrace` line events are statement-granular: they fire on the statement's first line, so a
   `Call` node's own `lineno` is the wrong key the moment a call sits in a comprehension or spans
   lines.
3. **the instrument is copied into a `$TMPDIR` shadow of the repo and run there**, plain and then
   traced, in one child process. See §3 for why the shadow, and §4 for why a child process.
4. **the traced lane's stdout is compared with the instrument's own stdout.** A census whose traced
   lane prints something other than the instrument prints is measuring a different program — the
   `py=`-column plant shape (`NVDUP.md:110`). A mismatch is reported as `harness` and the cell is
   withheld.

### THE DENOMINATOR (the deliverable)

```
instruments EXAMINED (every .py under .agents/slop)      3230
with >= 1 emitting site                                 1721
TRACEABLE -- ran to completion AND emitted >=1 row       430
emitting sites inside those traceable instruments       9410
DEAD emitting lines                                    1129
   of which in a def the lane ENTERED                    874   <- the D2 class
   of which in a def it never entered                   255   <- either a dead helper
       or THIS CENSUS's no-argv blindness; never counted as D2
dead lines in                                           206 file(s)
duplicate names in the same traceable lanes              366   <- the OTHER census
shard partition: every instrument name appears exactly once   OK
```

The uncounted, with reasons, because a denominator without them is a boast:

```
crash 761   hang 164   harness 81   no-lane 253   no-sites 1495   unparsable 14
```

* `crash` — mostly a missing optional module (`torch` 44, `hexdump` 24, `PIL` 22, `z3` 16,
  `tqdm` 14) or an instrument that wants `argv` (`IndexError: list index out of range` 135,
  `SystemExit(1)` 41, `SystemExit(2)` 31).
* `hang` — 164 instruments exceeded the 45 s budget.
* `harness` — 81 lanes whose output is not reproducible under tracing.
* `no-lane` — ran, printed nothing. **This is the cell that stops the `Bool.pick` failure**: an
  instrument that emits nothing is NOT "all its sites dead", it is an instrument whose lane never
  produced output, and it is excluded from both the dead count and the denominator.
* `no-sites` — 1,495 files that emit nothing at all (mutators, table generators, `*_mutate.py`).

**The headline is `874 / 9410`, not `1129`.** §2 says why, and it is the most important number in
this file.

### 197 instruments carry at least one dead emitting line inside a def their lane entered

```
incalled  dead  instrument
      34    36  .agents/slop/codegen-init-measure.py
      31    31  .agents/slop/nv_order_census.py
      26    26  .agents/slop/wip/gate.py
      22    23  .agents/slop/opsbend_milestone_gate.py
      21    21  .agents/slop/kn-ops-mutate.py
      20    43  .agents/slop/cstyle-gate.py
      17    17  .agents/slop/prepare-oracle.py
      15    15  .agents/slop/x86/x86_oracle.py
      15    15  .agents/slop/x86/x86-oracle.py
      14    15  .agents/slop/nir/nir_mutate.py
      13    23  checks/nl-gate.py
      12    22  .agents/slop/llvmir-gate.py
      12    14  .agents/slop/nvdup/nvdup-fix-nv.py
```

---

## 2. THE SPLIT THAT DECIDES WHETHER THE HEADLINE MEANS ANYTHING

`cstyle-gate.py` reads **43** dead emitting lines. **20** of them are inside a def the no-argument
lane entered; 23 are inside defs it never entered. I read those 23 before believing them: they are
`print`s inside `selftest()`, `selftest_reshape()`, `report_reshape()`, the planted-`--capture`
diagnostics — **code that only runs when the gate is given `--selftest` or `--plant`**, which this
census does not pass.

> **A census that runs an instrument with NO ARGV reports every argument-gated print as dead code.
> That is the `Bool.pick` failure in a new costume, and it would have inflated this report's
> headline by 29%.** Hence two columns, and only the first is a claim about the tree.

So: **`874` is the number of dead emitting lines inside defs their lane entered.** It is an upper
bound on that class too — some are legitimately conditional diagnostics — and a *lower* bound on
total unobservability, because the 1,295 instruments this census could not run at all are not
counted at all.

---

## 3. `run-kernel.sh:22` — THE TOOL PROBLEM, GENERALISED

`.agents/slop/portexec/run-kernel.sh:22` is

```
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
```

hard-coded, so a lane cannot be run against a copy — **and that is why four plants would have been
vacuous.** `plant.py`'s assert-carrying rewrite of that one line is the model. Three consequences,
all built in:

1. **Every artefact lands in `$TMPDIR`.** Nothing in the live tree is written by either tool.
2. **A `$TMPDIR` SHADOW WITH THE REPO'S SHAPE, every file a symlink.** The first version copied
   each instrument to `$TMPDIR/tmpXXXX/<name>.py`, which is what `nvdup-deadarm.py` does — and
   **1,396 of 1,714 instruments with emitting sites came back `crash`**, most with a path in the
   message:

   ```
   FileNotFoundError: '.../tmp29vv0soh/tinybendygrad/codegen/kernel.bend'
   ```

   because an instrument that walks up from `__file__` finds a `$TMPDIR` directory holding none of
   the tree. **A census whose harness breaks the instrument reports a COVERAGE number as a DEADNESS
   number.** Measured on the three cells that decided it: `kn-ops-mutate.py` went `crash` → `lane`
   with **21 dead sites**; `elf_reloc_probe.py` `crash` → `lane` with 4; `dsp2-mutate.py` `crash` →
   `crash` (it wants argv, honestly). This is also the recorded "$TMPDIR scratch copy cannot resolve
   a relative import" wall, which cost one unit 22 phantom blind spots; the shadow is the fix, and
   the fix is *why* the plants work.
3. **The plants run against the shadow.** `bendarm.py --selftest` copies `tinybendygrad/` whole,
   plants into the copy, and never touches the live tree.

---

## 4. THE PORT SIDE — `deadarm/bendarm.py`

The oracle files are Python and traceable. **The port is Bend, and Bend has no tracer.** So the
trace is obtained from *the compiler*, not from instrumentation of the port.
`references/bend/bend2/comp.ts:3055` says, in its own comment:

> `// A def's JS name is its key between $s: each . a $, and any other non-word char a $ and its`
> `// three-digit code, so no two keys share one.`

So `def fold(...)` compiles to `function $fold$(...)` in the JS emitter's output — **one function
per def, with a reversible name.** `bend F.bend -o out.js` emits the whole program with `main`
wired to `io_exit`, and `bun out.js` prints the lane's rows in ~0.1 s against ~2.5 s for
`bend F.bend`. Measured on `renderer/cstyle.bend` (at 16:47, `sha256` recorded below): **227 rows
out of the JS build, byte-identical to the bend run's 227.**

The tool inserts `__hit("<full name>")` at the head of every emitted def and rewrites every
constructor test the emitter wrote:

```
_x.$ === "OpsADD"     ->     __arm("fold", "OpsADD", _x.$) === "OpsADD"
```

`__arm` returns its argument unchanged, so the comparison's value and every byte of the lane are
untouched — **which is the control asserted on every entry**: the instrumented lane's stdout must be
byte-identical to the plain lane's, and 88 entries passed that while 174 failed `bend -o` and were
dropped.

### The arm key is `(def, constructor)`, not a source line index

Two arms of one def cannot share a constructor, so `(def, tag)` **is** the arm's identity, and no
alignment between the emitted `if`s and the source `case`s has to be assumed. That matters, because
alignment is the assumption a source-level census would have quietly made.

Two kinds of absence, reported separately because they are different claims:

* **NOT-EMITTED** — `comp.ts:3374` roots the emitted book at `main`, so a def the emitter did not
  write is a def nothing in this entry's call graph can reach. Bend's own compiler says so, before
  any of my code runs.
* **NOT-ENTERED** — the def *was* emitted and the run never called it. That can only be a dynamic
  path (a `match` arm no fixture reaches, a fuel loop that stops early) and needs the trace.

### THE PORT-SIDE NUMBERS

```
BENDARM -- merged over 88 traced entries whose lane was byte-identical
           (110 entries built and ran in this run, 174 failed `bend -o`)

  defs in the tree (tinybendygrad/**/*.bend + slop's own probes)   42399
  defs inside >= 1 traced lane's import closure                   11213
  defs a traced lane REACHES                                      5121
  defs NO traced lane reaches                                      6092
     of which the file's OWN lane BUILT, so the claim is real       692   <- THE ANSWER
     of which the file's own lane FAILED `bend -o`, so UNKNOWN     5504   <- NOT a claim
     of which the file is not itself an entry at all                 12
  defs in NO traced lane's closure -- COVERAGE, not DEADNESS      31186
  dead-arm findings, summed over the entries                        731
  entries with >= 1 dead arm                                        61
```

**`692` defs are reached by no traced lane, and each one's own lane built.** Top files:

```
  tinybendygrad/sz.bend   (189)      tinybendygrad/runtime/support/objc.bend   (11)
  .agents/slop/ga-green-87.bend (129) tinybendygrad/runtime/support/c.bend     (10)
  .agents/slop/ag-emit.bend   (88)  tinybendygrad/runtime/support/compiler_mesa.bend (8)
  tinybendygrad/LAWS/spec.bend (58)  tinybendygrad/runtime/support/compiler_cpu.bend (7)
  .agents/slop/graphcmp.bend  (17)   tinybendygrad/runtime/support/compiler_cuda.bend (7)
  tinybendygrad/runtime/ops_cpu.bend (17)
  tinybendygrad/runtime/support/c.bend:292  def Field.entry
```

**`5,504` are NOT counted as dead.** Their files' own lanes failed `bend -o` in this run, and a
build failure is not a finding:

```
  multi.bend 694   elf_local.bend 548   amdev.bend 475   fold.bend 429   dtype.bend 381
  helpers.bend 336 op.bend 321          render.bend 302 realize.bend 280  memory.bend 263
```

The two largest groups in the unfiltered table — `schedule/multi.bend` (694) and
`support/am/amdev.bend` (475) — are **entirely** in that bucket. Reading them as "defs nothing
calls" would have been reporting a compile error as a result. `bendarm.py --entry <file>` on each,
once the build is green, turns them into claims or into coverage. This is `agent-core.md`'s
"if you hit a cold-compile failure naming a def that is not in your file, you have found another
agent mid-edit — say so and use a local reader rather than editing their file", applied to a number
instead of a run.

### The arm column is per-entry and is NOT merged, on purpose

A `case` arm dead in one entry can be taken in another. The negative set — the arms that *were*
taken — is not in the TSV, and inferring it would be exactly the inference this unit exists to
distrust. So: **731 dead-arm findings across 61 entries, each traceable to one entry's `file:line`,
and no tree-wide arm total claimed.**

Per-entry, the two headline files (measured 16:47, before `cstyle.bend` went unbuildable):

```
  cstyle.bend   emitted=450 entered=392 NOT-EMITTED=2074 NOT-ENTERED=0
                arms(source)=231  DEAD-ARM=75  unmeasured=149   byte-identical
  mixin/op.bend emitted=905 entered=669 NOT-EMITTED=2618 NOT-ENTERED=0
                arms(source)=59   DEAD-ARM=36  unmeasured=15    byte-identical
```

`arms(source)` counts the `case` arms written in the entry's own source and only in defs the lane
entered; `tags-seen` (not printed above) counts every distinct `(def, constructor)` including Base's
own, so it is routinely larger. `unmeasured` counts `case 0n:`, `case _:` and every other non-
constructor pattern, for which no `.$ === "Tag"` test exists — **they are counted, never dropped**,
because a census that quietly drops the arms it cannot see is the multiplicity census's mistake.

### THE `cstyle.bend:49` INSTANCE, CHASED

`renderer/cstyle.bend:49` records wall (a): *"`Ops.SHRINK` HAS NO DTYPE IN THE FOLD …
`render_type` needs a dtype on EVERY line, so `_render` cannot be run end to end until that arm
lands."* Two measurements, and one of them is about **observability rather than about SHRINK**:

1. **`def _render` DOES NOT EXIST in `renderer/cstyle.bend`.** Its renderers are `render_dtype`
   (`:773`), `render_dtype_legacy` (`:781`), `render_type` (`:821`), `render_ptr` (`:830`),
   `render_access` (`:834`), `render_cast` (`:837`), `render_index{,.alu,.alu2}` (`:940`, `:944`,
   `:955`), `render_buffer` (`:987`), `render_kernel` (`:1643`). `_render` appears 14 times in the
   file and **every one is inside a comment**. So the def the wall names has no body, and nothing in
   the tree can execute it.
2. **THE CSTYLE LANE NEVER REACHES THE FOLD AT ALL.** `cstyle.bend:81` is
   `import ./../uop/fold.bend as F`, and `F.` appears **once** in the file — in the comment at
   `:52`. Independently: of `fold.bend`'s defs, **zero** appear among the 450 the emitter wrote for
   the cstyle lane (`fold`, `promo_mask`, `dt_by_rank`, `least_upper.pick` — all absent). So the
   gap the wall describes lives in a file this lane does not touch, and **no row in the cstyle gate
   can observe it, in either direction**: the gate is 227 rows of string rendering driven by
   EXPLICIT derived values, which is why the file's own header says the gate "is built so that it is
   OBVIOUS this is why". The wall is honest and the gate is honest, and the gap between them is
   unobservable by construction.

---

## 5. WAS THE TOOL SHOWN TO FAIL ON A KNOWN-LIVE LINE? YES, TWICE, IN BOTH DIRECTIONS

The requirement is a check that can fail, demonstrated failing, plus a demonstration that the tool
does not call a live line dead. Both are in the code and both are printed.

### 5a. `deadarm.py --selftest` — 5 of 5 PASS, and the DISARM is measured, not typed

```
  nv-oracle.py:clean      sites=347 lane rows=547 DEAD=0 dup=0 ctl=same     <- the DISARM
  nv-oracle.py:dead       sites=349 lane rows=548 DEAD=1 dup=1 ctl=same
        DEAD SITE  line 1206  row("deadarm_plant_dead", "unreached")
  nv-oracle.py:live       sites=348 lane rows=548 DEAD=0 dup=1 ctl=same
  nv-oracle.py:dup        sites=348 lane rows=548 DEAD=0 dup=1 ctl=same
  nv-oracle.py:longhand   sites=348 lane rows=548 DEAD=0 dup=1 ctl=same

  [PASS] DISARM: the unplanted real file is censusable and has NO dead site: True
  [PASS] DEAD:   a row() in an unreachable try-arm IS seen (0 -> 1): True
  [PASS] LIVE:   a row() that DOES execute is not called dead (stays 0): True
  [PASS] DUP:    a duplicate is NOT a dead site -- site census stays, LINE census rises: True
  [PASS] LONGHAND: a row emitted by `print`, NOT by the writer fn, IS a site the semantic
         selector sees and nvdup's textual one could not: True
DEADARM SELFTEST OK
```

`LIVE` is the "known-live line" cell: a `row()` planted at module level **executes**, and the census
reports 0 dead. `DEAD` is the same shape one `try:` arm out: 0 → 1.

### 5b. THE TOOL REDISCOVERS THE FOUR KNOWN DEAD SITES, FROM A DIFFERENT SELECTOR AND A DIFFERENT HARNESS

```
$ .venv/bin/python .agents/slop/deadarm/deadarm.py --file .agents/slop/nvdup/nv-oracle-PREFIX.py
  nv-oracle-PREFIX.py  sites=361 lane rows=574 DEAD=4 dup=27 ctl=same
        DEAD SITE  line 1139  row("nv_smemcfg_too_big", "False")
        DEAD SITE  line 1146  row("nv_smemcfg_msg_big", "")
        DEAD SITE  line 1154  row("nv_reloc_msg_%d" % _t, "")
        DEAD SITE  line 1159  row("nv_reloc_bad_refused", "False")
RC=1
```

`NVDUP.md` §2 and `stage4-plants.md` §3 record exactly these four at exactly these lines. This tool
shares **no code** with `nvdup-deadarm.py` — different selector (semantic sink closure vs
`^\s*row(`), different population (`ast` over 3,230 files vs one file), different harness (child
process, shadow root, plain-vs-traced control). It reaches 361 sites where the textual selector
reaches 351, because it also sees the module-level printer. **Two instruments, one answer, four
sites.**

### 5c. `bendarm.py --selftest` — 6 of 6 PASS, with two plants, one per census

```
[selftest] DISARM first: the REAL entry, instrumented only by __hit()/__arm().
  op.bend            ok=True rows= 36 emitted=905 entered=669 NOT-EMITTED=2618 NOT-ENTERED=0 byte-identical
  PROBE   probe.bend          the unplanted probe: 2 called defs, 5 of its arms reachable
  probe.bend         ok=True rows=1 emitted=7 entered=7 NOT-EMITTED=0 NOT-ENTERED=0 DEAD-ARM=1 byte-identical
  PLANT   probe.planted.bend  two uncalled defs + one unbuilt `case Dead0{}` arm
  probe.planted.bend ok=True rows=1 emitted=9 entered=7 NOT-EMITTED=0 NOT-ENTERED=2 DEAD-ARM=2 byte-identical

  [PASS] DISARM: the real entry builds, prints rows, and its instrumented lane is BYTE-IDENTICAL …: True
  [PASS] DISARM: the real entry's own census is non-trivial -- it has constructor arms to miss: True
  [PASS] PLANT: the base probe has NO uncalled def and exactly ONE dead arm …: True
  [PASS] PLANT-DEF: two planted defs are EMITTED and NOT ENTERED -- emitted +2, not-entered 0 -> 2 …: True
  [PASS] PLANT-ARM: the dead arm is seen by the (def,tag) census and the lane's ROWS do not move …: True
  [PASS] PLANT-ARM: the dead arm is INVISIBLE to the def-level census …: True
BENDARM SELFTEST OK
```

The sixth cell is the "neither census substitutes for the other" claim, and it is the reason there
are two plants: `PLANT-DEF` moves the def census and **not** the arm census; `PLANT-ARM` moves the
arm census and **not** the def census; **both leave the lane's rows byte-identical**, which is the
whole of `D2` — the dead thing costs nothing to count.

---

## 6. THE TABLE — what is unobservable, ranked by what it costs

Ranked by consequence, and the last column is the deliverable. **"Nothing" is a real answer here
and it is the answer for most of this table**, because `D2` costs zero measurements: there is no
count of emitted names that could have reported its absence.

| # | `file:line` | what claims to exist | what would notice if it were wrong | would anything notice? |
|---|---|---|---|---|
| **T1** | `renderer/cstyle.bend:49` (wall (a)) + the absence of any `def _render` | `Ops.SHRINK` has no dtype in the fold, so the kernel body is still a fixture and `_render` cannot run end to end | a row that drives `render_type` from a real folded graph. **There is none: the cstyle lane emits 0 of the fold's defs and calls `F.` zero times** | **NOTHING.** The wall is a comment; the 227 rows are string rendering from explicit derived values by design; no lane reaches the fold, so no row can move in either direction |
| **T2** | `tinybendygrad/sz.bend` — 189 defs (`Row.name:65`, `Row.lines:69`, `Row.toks:73`, `Row.dl:77`, `Row.dt:81`, `is_docstring:149`, `op2eq:229`, `isdig.hex:267`, …) | a `sz.py` port with its own readers | `sz.bend`'s own lane, which **built and ran** and entered 1,101 of its 1,290 defs | **NOTHING for those 189.** The lane is byte-identical and green; no other lane reaches them either. `sz.bend`'s own text says its counts are lower bounds |
| **T3** | `lintable/lintable-oracle.py:96` — `row("rp_slot5_raises_py", 0)` | the *accepting* side of "CPython raises `KeyError: 5`" — i.e. that the call does **not** raise when it should not | `:98` emits `= 1` and the row dictionary at `:182` documents it as "CPython-side only: there is no port row, the port is total". The claim "**the port is total where Python is not**" is a real semantic difference | **NOTHING.** `:96` never executes — the raise is certain (`:88-89` says "measured, not assumed"). The lane carries only `=1`. The port's totality has **no** measurement of the accepting side |
| **T4** | `elf_reloc_probe.py:150` — `row(f"elf_rc_no_{nm}_ok", 1); row(f"elf_rc_no_{nm}_msg", "")` | that a patched relocation type is **not** refused — the positive case for `elf.py:81`'s `NotImplementedError` | the probe's own header (`:140-142`) asserts the raise is certain, so the `try:` succeeds never | **NOTHING today.** The lane carries only the `_ok=0` / `_msg=…` pair. If a future change made the patch *succeed*, new rows would appear and `rebase-gate.py`'s absolute row count would move — so the arm's *existence* is policed by accident, and its *value* is unverified |
| **T5** | `elf_reloc_probe.py:158` — `row("elf_rc_base_ok", 1)` / `_len` / `_words` | the unmodified baseline's **success** values: word count and the words themselves | `except Exception` at `:160` emits `_ok=0`, `_len=-1`, `_words=<type name>` — so the lane's baseline is a refusal report | **NOTHING.** The probe has no measurement of a successful baseline run, so "the baseline's words are right" is unmeasured. Note the wall: the lane's `_ok=0` is a *measurement*, so the refusal is witnessed; the success side is not |
| **T6** | `elf_reloc_probe.py:170` — `row(f"elf_rc_entry_at_{k}_ok", 1)` / `_len` / `_words` | that patching entry `k`'s type leaves a loadable object, for each `k` | `except Exception` at `:173` emits the zero/negative triple | **NOTHING**, per entry. The per-entry claim (`relocate` is applied per *relocation*, not per *section*) is proved entirely by the refusal side |
| **T7** | `kn-ops-mutate.py` — 21 dead emitting lines, all inside defs the lane entered (`:116-117`, `:122`, `:158-168`) | a mutation harness's baseline/oracle/failed-patch report | the harness's own three planted controls. Its mutants run; its *reporting* of them does not | **NOTHING for the report.** The mutants move rows (the harness is useful); the 21 lines that would have said *which* rows did not move never print, so "a mutation moved nothing" is invisible in its own log |
| **T8** | `cstyle-gate.py` — 43 dead lines, **20** inside entered defs (`:283`, `:287`, `:292`, `:483`, `:491`, `:494`, `:496`, …) | the coverage table and the `COVERAGE n/m` line | the gate's verdict. `:494-496` are the TOTAL and COVERAGE lines, i.e. **the gate's own coverage denominator** | **NOTHING** — and this is the sharpest one, because the dead lines ARE the coverage report. A gate that cannot print its coverage cannot be asked whether its coverage is complete. The other 23 are flag-gated and are my harness's blindness, not the tree's |
| **T9** | `codegen-init-measure.py` — 34 dead inside entered defs | a measurement harness's per-stage report | its own numbers | **NOTHING** for the 34 lines. Reported, not ranked higher, because a measurement script's *output formatting* costs less than a gate's *denominator* |
| **T10** | `uop/fold.bend` — 429 defs, and `runtime/support/am/amdev.bend` — 475, `schedule/multi.bend` — 694 | (not claimed) | their own lanes, which **failed `bend -o`** in this run | **NOT MEASURED, and deliberately not counted.** Reporting 1,598 defs as unreachable would have been reporting a concurrent agent's mid-edit compile error as a finding. `agent-core.md` names the symptom: a cold-compile failure naming a def not in your file means another unit is mid-edit |
| **T11** | 1,295 instruments with emitting sites that this census could not run (761 `crash`, 164 `hang`, 81 `harness`, 253 `no-lane`, 14 `unparsable`) | (not claimed) | nothing | **NOT MEASURED.** Most are mutators and one-shot probes wanting `argv`; some are missing `torch`/`PIL`/`z3`. Their dead arms, if any, are unmeasured — and `874` is therefore a **lower** bound on the oracle-side total |
| **T12** | `bendarm.py`'s arm census: 149 of `cstyle.bend`'s 231 source arms, 15 of `op.bend`'s 59 | constructor `case` arms | — | **NOT MEASURED.** `case 0n:`, `case _:` and every other non-constructor pattern compiles to no `.$ === "Tag"` test. Counted and printed as `unmeasured`, never dropped |

---

## 7. WALLS, `file:line`

Every one of these cost a run and each produced a plausible wrong answer first.

| | where |
|---|---|
| **A census that runs an instrument with NO ARGV reports every flag-gated print as dead.** `cstyle-gate.py` reads 43; 20 are real. The headline would have been inflated 29% | `deadarm.py`'s `dead_in_called` split; `cstyle-gate.py:283-292` |
| **`signal.alarm` + an in-process `settrace` SEGFAULTS.** 5 of 8 shards died rc 139: the alarm raises at an arbitrary bytecode boundary and these instruments are inside ctypes/numpy. A harness that segfaults reports nothing, so the cells were reported as `crash` — a WRONG answer rather than a missing one | `deadarm.py`, replaced by a child process the parent can SIGKILL |
| **Copying an instrument to `$TMPDIR/tmpXXXX/` breaks every script that resolves paths from `__file__`: 1,396 of 1,714 crashed.** `kn-ops-mutate.py` went `crash` → `lane` with **21 dead sites** the moment the shadow root landed | `deadarm.py:shadow_root` |
| **Comparing a MANGLED name against an UNMANGLED set reported all 2,302 def-sites of `cstyle.bend`'s own closure as NOT-EMITTED**, including `dev_base`, which the emitter demonstrably wrote. A wrong key is a tool that says everything is dead | `bendarm.py:census_entry` |
| **`bendarm-merge.py` keyed the tree `(file, line)` and compared it against the TSV's `(where, name)`** — the right shape, the wrong contents — so every membership test was False and it answered **"0 unreached defs of 10,870"**. Accepted because the number was small and plausible | `bendarm-merge.py` |
| **A newline in a TSV field.** A crash message carrying a compiler diagnostic wrote a MULTI-LINE row; **1,387 of 3,424 rows were malformed**, `csv.DictReader` produced `None`, and the merge reported a total over a corrupted table. Same species as the hand-typed `py=` column | `deadarm.py`'s `--report` |
| **`visit_Stmt` is not an `ast.NodeVisitor` hook.** The first selector fell back to `Call.lineno` and found 10 sites in a 337-site file | superseded by `_stmt_lines` |
| **A dup plant that invents its own name measures nothing** — the LINE census is a *multiplicity* census and a name of multiplicity 1 is not a duplicate. The right answer for the wrong reason, looking green | `deadarm.py:selftest` |
| **A `print` plant with a space before `=`**: the LINE census compared `"name "` with `"name"` and read 0. **A prefix is not a comparison** — the recorded `4 00004040` lesson, reached again from a different direction | `deadarm.py:selftest` |
| **`Bool.pick` CANNOT plant a dead arm's ARGUMENTS.** `base.bend:504` is `def Bool.pick(-A: Type, c: Bool, a: A, b: A) -> A: match c: …` and Bend's arguments are STRICT, so both arms are evaluated before `pick` chooses. The census read NOT-ENTERED 0 → 0 and the cell reported the failure instead of a green it did not earn | `references/bend/bend2/base.bend:504` |
| **`match True{}:` and `match deadarm_flag():` are REFUSED** — "an undestructured scrutinee", "a match cannot scrutinize a computed value: give it its own def". A dead arm has to hang off an existing `match` over a **parameter** | `references/bend/bend2/base.bend:504`, Bend's checker |
| **A forward reference is "an unfilled law"**, so `probe_unentered_of` must precede `probe_unentered` and `probe_of` must precede `probe_name`. Four probe builds failed on this in a row | `bendarm.py:PLANT_PROBE` |
| **`case _:` is a CATCH-ALL, not a constructor.** Classifying it as one put a `_` tag in the `(def, tag)` key space, and since `_` is unreachable by construction **every def with a catch-all read as carrying a dead arm** — the tool inventing a finding out of its own selector | `bendarm.py:ARMC` |
| **`subprocess.TimeoutExpired` was not caught**, and `.agents/slop/ga-ins-wip.bend`'s emitted JS never returns (a WIP probe with an unbounded fuel loop). The exception killed a 282-entry sweep at entry 63 **with no TSV written at all** | `ga-ins-wip.bend`; `bendarm.py:run_js` |
| **THE PLANTS' HOST IS BEING REWRITTEN.** Both cstyle plants fired at 16:47 (NOT-ENTERED 0 → 1, DEAD-ARM 75 → 76, 227 rows byte-identical), and by 17:37 `renderer/cstyle.bend` carried **FIVE copies of `def BArg.name`** (lines 159, 196, 233, 270, 307) and `bend -o` refused it with `duplicate declaration: BArg.name`. **A control whose host is being rewritten is not a control**, so the plants moved to a generated probe | `renderer/cstyle.bend:159,196,233,270,307` |
| **`tinybendygrad/uop/fold.bend` DOES NOT COMPILE RIGHT NOW**: `a declared constructor (unknown: ../helpers.I64)` at `fold.bend:2864`. Another unit is mid-edit on `helpers.bend`. Its 429 defs are in the NOT COUNTED bucket | `uop/fold.bend:2864` |
| **`tinybendygrad/schedule/multi.bend` and `runtime/support/am/amdev.bend` also failed `bend -o`**, and they are the two largest unreached groups (694 and 475). **The merge's `failed`/`built` split exists because of them** | `bendarm-run.txt` |
| **A `$TMPDIR` shadow must mirror `.agents/` and `tinybendygrad/` as real directories and everything else as symlinks.** Rebuilding it per instrument cost 4 s of a 4 s cell | `deadarm.py:_mirror` |
| **`bendarm.py`'s `tags-seen` counts Base's own `Nil`/`Some`/`Con` tests** and so is routinely larger than `arms(source)`. The first label printed them the other way round and read `arms 251/59` | `bendarm.py:_show` |
| **1,295 instruments of 1,721 could not be censused here**, so `874` is a LOWER bound on the oracle side and `6,092` is not the port-side answer either — `692` is, after the build-failure split | `deadarm-merge.py`'s stdout, `deadarm/bendarm-merged.txt` |

---

## 8. REPRODUCE

```
# oracle side -- the census, and the two selftests
.venv/bin/python .agents/slop/deadarm/deadarm.py --selftest                       # 5/5 PASS
.venv/bin/python .agents/slop/deadarm/deadarm.py --file .agents/slop/nvdup/nv-oracle-PREFIX.py   # rc 1, the 4 known sites
.venv/bin/python .agents/slop/deadarm/deadarm.py --file .agents/slop/lintable/lintable-oracle.py  # T3
DEADARM_TIMEOUT=45 zsh .agents/slop/deadarm/sweep.sh 10                            # 10 shards
.venv/bin/python .agents/slop/deadarm/deadarm-merge.py .agents/slop/deadarm        # the denominator

# port side
.venv/bin/python .agents/slop/deadarm/bendarm.py --selftest --entry tinybendygrad/mixin/op.bend   # 6/6 PASS
.venv/bin/python .agents/slop/deadarm/bendarm.py --report /tmp/bendarm.tsv        # the sweep
gunzip -c .agents/slop/deadarm/bendarm.tsv.gz > /tmp/bendarm.tsv
.venv/bin/python .agents/slop/deadarm/bendarm-merge.py /tmp/bendarm.tsv \
    .agents/slop/deadarm/bendarm-run.txt                                          # the denominator
.venv/bin/python .agents/slop/deadarm/bendarm.py --entry tinybendygrad/runtime/support/c.bend  # one lane
```

Nothing here writes inside the repo except this directory. `deadarm.py`'s shadow root lives at
`$TMPDIR/deadarm-shadow-<pid>/` and is removed by an `atexit` handler; `bendarm.py`'s `-o` targets,
instrumented copies and probe files all live inside a `TemporaryDirectory`.