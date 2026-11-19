# PIPELINE CENSUS — Tensor → schedule → render → cc → numbers

**Verdict token: `REFUSED`.** The chain is implemented at EVERY link and is reachable from the
Tensor API at NO link: the first link is absent (`Tensor.realize`), the links after it are
implemented-but-unwired, and the one link that has been run end-to-end from the port's own
scheduler produces C that `cc` refuses. Nothing in this report is a claim about a label; every
row carries the command that produced it. Measured 2026-11-19, HEAD `425f7126a`.

## 0. THE ANSWER, IN ONE PARAGRAPH

**The first link that is genuinely absent is `Tensor.realize`** — `tensor.bend` has 358 defs and
none of them reaches a schedule: `Tensor.linear_with_vars` (`tensor.py:167`),
`Tensor.schedule_linear` (`:212`) and `Tensor.realize` (`:219`) are three `TODO(p3)` comments at
`tensor.bend:1748/1754/1759`, and that label is TRUE. **The first link after it that is genuinely
unwired is `rangeify.bend`'s stage 1** — NOT absent, as the tree says three times: `rangify.bend`'s
`rr_kernel_graph` implements it, and MEASURED it moves the port's kernel count **0 → 1** on the
port's own fixture. **The first link that is genuinely BROKEN is `runtime/device.bend`'s
`body_low`**, which runs four of upstream's lowerer passes and not the "add loads" pass, so the
port's own scheduler's kernel contains **zero `LOAD` nodes** and `cc` refuses it with three
`invalid operands to binary expression ('float *' and 'float *')` errors. Numbers ARE reached —
`execgap` prints the matmul from the port's rendered text — but only from a **hand-built** arena
that already carries the six `LOAD` nodes a real lowerer would insert.

## 1. THE CENSUS

One row per stage. `callers_shipped` counts callers under `tinybendygrad/`; a caller in `gates/`
is an instrument and a caller in `.agents/slop/<unit>/` is a lane, and neither ships. The
machine-readable rows (with `label_says` and `label_true`) are `census.rows`; the caller lists are
`callers.rows` (produced by `callers.py` over 589 live `.bend` files).

| # | stage | implementation | reachable from the Tensor API? | gate | rc | label claims | measured reality |
|---|---|---|---|---|---|---|---|
| 1 | Tensor API (ops → UOps) | `tensor.bend`, 2557 L, 358 defs | it is the entry | none | – | "the method surface, and the `realize` entry" | surface YES; **the `realize` entry does not exist** |
| 2 | Tensor → realize | **ABSENT**: `TODO(p3)` ×3 at `tensor.bend:1748/1754/1759` | **NO** | none | – | `TODO(p3) tensor.py:219 realize` | **TRUE — this is the first absent link** |
| 3 | realize → SINK | `schedule/realize.bend:459 rz_built`, 472 L | NO (fixture builder) | `realize-gate.bend` | 0 | "the port's own realize-to-sink driver" | TRUE; input is hand-built, and its own row says `rz_lin_n=0` |
| 4 | engine stages (7) | `rangeify.bend:2734 eng_stages`, 3136 L | NO | `rangeify-gate.bend` | 0 | "1 `run_rangeify` … **NOT PORTED**" | **FALSE** — implemented in `rangify.bend`, unwired here |
| 5 | `run_rangeify` | `rangify.bend:1653 rr_run_rangeify`, `:1661 rr_kernel_graph`, 1769 L | NO (0 shipped callers, 49 lane callers) | `rangify-gate.bend` | **1 REFUSED** | "the whole of the Device lane's last link" | exists and works; **no shipped caller; its gate does not compile** |
| 6 | `schedule()` → LINEAR | `schedule/__init__.bend:1295 schedule`, `:1288 lin_kernels`, 2149 L | NO (3 shipped callers, all inside the unwired lane) | `schedsched-gate.py` | **3 REFUSED** | "84 of 111 rows compared" | comparator **cannot run** (oracle raises a cycle); 0 kernels on the engine path, 1 on the rangeified root |
| 7 | lowerer: add loads | `codegen/kernel.bend:565 pm_add_loads`, 1557 L | **NO — 0 callers anywhere** | none | – | "24 `pm_add_loads` 2 of 2, PORTED" | TRUE as a rule; **no graph-level caller, and its absence is visible in the C** |
| 8 | kernel body → KU | `runtime/device.bend:378 body_kus`, 430 L | NO | none | – | "the port has **no DEF** that builds [a `List<KU>`] from the PORT's ARENA" | **FALSE — this def is that conversion** |
| 9 | lane entry | `runtime/device.bend:427 compile_sink` | **NO — 0 shipped callers** | none | – | "whoever produces it is the next unit" | FALSE — it is produced here; nothing calls it |
| 10 | linearizer | `codegen/late/linearizer.bend:762 linearize`, 1834 L | NO (1 shipped caller: `device.bend:383`) | `linearizer_census-gate.py` | **3 REFUSED** | "488 ported defs … ungated" | gated, and the oracle is stale (`ParamArg` 14 vs 13 args) |
| 11 | kuconv | `renderer/kuconv.bend:349 kuconv.convert`, 350 L | NO (1 shipped caller: `device.bend:384`) | none | – | none | works: it produced the KU list my render used |
| 12 | cstyle render | `renderer/cstyle.bend:2364 render`, 2384 L | YES (also from `llm/cli`, `renderer/live`, `uop/upat`) | `cstyle_render_census-gate.py` | **0 PASS** (425 rows) | "complete enough to be a compiler" | TRUE — but every fixture it renders already carries its LOADs |
| 13 | `cc` | `runtime/ops_cpu.bend:1035 Cpu.compile` | NO (1 shipped caller: `device.bend:151`) | none | – | "the port's `Cpu.compile` is that effect" | TRUE as a def; **no gate runs it** (execgap spawns a hosted `cc`) |
| 14 | run | `runtime/ops_cpu.bend:1039 Cpu.exec`, `device.bend:175 exec` | NO (1 shipped caller: `device.bend:177`) | none | – | "the port's `Cpu.exec` is that effect" | TRUE as a def; **no gate runs it** |
| 15 | numbers | `execgap` (fixture) + `pipelinecensus/execfull` (scheduler) | – | `execgate-gate.py` | **0 PASS** (10 rows, 3 plants RED) | "the binary's own stdout" | TRUE on the fixture path; the scheduler path stops at `cc` |

**The one sentence the table says:** every link from the SINK to the numbers has an
implementation, and every one of them is reachable only through `runtime/device.bend`'s
`compile_sink`, which has **0 shipped callers**.

## 2. DEFECTS, EACH WITH THE COMMAND THAT SHOWS IT

**D1 — THE FIRST ABSENT LINK: `Tensor.realize` DOES NOT EXIST.** Three `TODO(p3)`s, and the label
is true.
```
rg -n "def Tensor\.realize|def linear_with_vars|def schedule_linear" tinybendygrad/tensor.bend   # rc=1, no output
sed -n '1748,1762p' tinybendygrad/tensor.bend      # the three TODO(p3) comments
```

**D2 — `run_rangeify` IS IMPLEMENTED AND UNWIRED, NOT "NOT PORTED".** Three files say it is not
ported: `rangeify.bend:2700`, `chain/GAP.md`, `execgap/REPORT.md` §6. The measurement:
```
.venv/bin/python checks/bounded.py --mb 4000 -- ./bin/bend .agents/slop/pipelinecensus/probe_kg.bend
# kg_lin_n=1        <- rr_kernel_graph's root, through schedule()
# base_lin_n=0      <- the root the engine's stage list produces, through the same schedule()
```
The graph is real: `kg_dump` has `RANGE`, `INDEX`, `END`, `CALL`, `TRUNCMOD` — the ops
`.agents/slop/chain/GAP.md` records as absent (0 RANGE, 0 INDEX, 0 END, 0 CALL).

**D3 — THE FIRST BROKEN LINK: `body_low` OMITS `pm_add_loads`, SO THE RENDERED C DOES NOT
COMPILE.** Upstream runs that pass at `tinygrad/codegen/__init__.py:301`
(`symbolic_simple+pm_expand_broadcast+pm_add_loads`); the port runs four passes at
`runtime/device.bend:372-376` and not this one.
```
./bin/bend .agents/slop/pipelinecensus/probe_lin.bend        # lin=... INDEX[164,199] ... STORE[200,251]
                                                             # ZERO `LOAD[` in the whole linearized kernel
.venv/bin/python checks/bounded.py --mb 4000 -- ./bin/bend .agents/slop/pipelinecensus/execfull.bend
# cc_status=1
# error: invalid operands to binary expression ('float *' and 'float *')       x3, same line
#   *(data0_20+((cast0+(5*cast1))%20)) = (((data1_12+...) * (data2_15+...)) + ...)
```
The STORE is dereferenced correctly (`*(data0_20+…)`), so the deref exists: what is missing is the
`LOAD` node around each `INDEX` that feeds an elementwise op. **This is why `execgap` is green:**
its arena `graphcmp.bend:g_lin` hand-builds six `LOAD` nodes (`:1193-1217`) and skips the stage.

**D4 — `pm_add_loads` HAS ZERO CALLERS, AND ITS RULE IS ALREADY INCOMPLETE.** The only references
are its def, its comments, and `k_al` (a row helper).
```
.venv/bin/python .agents/slop/pipelinecensus/callers.py | grep add-loads      # callers_total=0
sed -n '527,536p' tinybendygrad/codegen/kernel.bend   # "TODO(p3) __init__.py:224 ... GroupOp.Elementwise"
```
So wiring it is not a one-liner: its first rule holds `{REDUCE, WMMA, STACK}` where upstream holds
`GroupOp.Elementwise|{WMMA,STACK}`, and applying the port's over-broad version would wrap `PARAM`s
in `LOAD`s. **REPORTED, NOT BUILT** (per the brief).

**D5 — `gates/rangify-gate.bend` DOES NOT COMPILE, SO THE PORT'S WHOLE `get_kernel_graph` HAS
NEVER BEEN COMPARED TO CPYTHON.** `rr_range_map` returns a PAIR (`(O.Arena & RrMap)`,
`rangify.bend:918`) and the gate binds it as an `RrMap` at 7 sites.
```
./bin/bend gates/rangify-gate.bend
# Error: expected : Data / observed : Type ... Location: rr_row_out
# Note: +m can be used many times, so its type must be Data.
```
Sites (7): `:31, :58, :89, :101, :117, :158, :197`, each `+m = P.rr_range_map(ar, tb, sink)`. The gate was
last green at `.agents/slop/rangify/rr_port.rows` (2026-10-28), which carries only `rr_realize`
and `rr_in` — **every newer row, including `rr_kg`, has never run.**

**D6 — THE SCHEDULER'S CPYTHON COMPARATOR IS REFUSED.** `gates/schedsched-gate.py` → rc=3.
```
.venv/bin/python gates/schedsched-oracle.py
# RuntimeError: cycle detected in assign graph   (tinygrad/schedule/__init__.py:78)
```
Its fixture builds a graph upstream rejects. The gate says `REFUSED` rather than `PASS` — that is
correct behaviour and a dead comparator.

**D7 — THE LINEARIZER'S CPYTHON COMPARATOR IS REFUSED, PINNED TO AN OLDER UPSTREAM.**
```
.venv/bin/python gates/linearizer_census-oracle.py
# TypeError: ParamArg.__init__() takes from 3 to 13 positional arguments but 14 were given
```

**D8 — FOUR `.bend` "GATES" CANNOT FAIL, BECAUSE NOTHING READS THEIR ROWS.** No `.py` gate, no
workflow and no document names them (the only hits are prose and their own files).
```
rg -l --hidden -g '!.git' "realize-gate|rangeify-gate|schedule-init-gate|linearizer-gate" .
# gates/*.bend themselves, plus prose in .agents/TODO.md and .agents/slop/loc/
```
Measured green and compared by nobody: `realize-gate` 8 rows, `rangeify-gate` 159 rows,
`schedule-init-gate` 135 rows, `linearizer-gate` 71 rows. **A row printer with no pin is a label.**

**D9 — THE LANE'S ENTRY HAS NO SHIPPED CALLER, AND THE LAUNCH IS NOT COMPOSED.** `compile_sink`
(`device.bend:427`) has 0 shipped callers (7 lane callers). `compile` (`:149`), `relocate` (`:162`)
and `exec` (`:175`) exist and **nothing composes them into a lane** — `compile_sink` stops at C
text, so `cc` and `run` are not merely uncalled, they are un-wired to each other.
`./bin/bend tinybendygrad/runtime/device.bend --check-only` → rc=1, `4 defs rely on unsafe or
foreign code` (a REFUSAL, not a FAIL: the module is `COLD-BY-DESIGN` in `checks/port-compile.rows`
and imports fine, which `probe_dev.bend` proves by rendering 665 bytes of C through it).

**D10 — A GITIGNORED MUTANT LIVES INSIDE THE SHIPPED TREE.**
`tinybendygrad/codegen/late/.linearizer-mut.bend` (81 KB, `.gitignore:36` `*mut.bend`) was counted
as THREE callers of `linearize` by my first census pass. It is invisible to `git status` and to any
gate that reads git, and it is the class `AGENTS.md` records as moving the substrate digest.
`callers.py` now excludes dotfiles and `*mut.bend`.

**D11 — THE BRIEF'S OWN CLAIM ABOUT THIS GATE IS FALSE.** "`gates/rangify-gate.bend` runs rc=0
emitting real kernel graphs" — measured rc=1 on a compile error (D5). The claim is stale in the
brief, not in the tree.

## 3. LABEL CORRECTIONS LANDED

Each is a comment-only edit; no behaviour changed; each file still type-checks.

| path:line | said | is true |
|---|---|---|
| `runtime/device.bend:4` | "EVERY STAGE … and NOTHING drives them"; "`grep Cpu.compile\|Cpu.exec` answers ONLY THE TWO definitions"; "a set of STAGES WITH NO LANE" | one def drives them (`compile_sink`) and nothing SHIPPED calls it; that grep answers 3 lines each (def + call); the lane is one def with no caller |
| `runtime/device.bend:11-20` | `schedule/__init__.bend:1124`, `:1125`, `cstyle:2257`, `ops_cpu:1546`, `:1582`, `elf:1796` | `:1295`, `:1292`, `:2364`, `:1035`, `:1039`, `:1720` |
| `runtime/device.bend:60-76` | "the port has no DEF that builds [a `List<KU>`] from the PORT's ARENA … the link is blocked by a named wall (`cstyle.bend:49-54`)" | `body_kus` (`:378`) IS that def; `cstyle.bend:49-54` is the `KU` record, the quoted text is gone, and the conversion renders C |
| `schedule/rangify.bend:5-9` | cites `rangeify.bend:2352` and quotes "NOT PORTED" as current | `:2700`, and records the measurement that the label is stale (0 → 1 kernels) |
| `.agents/slop/chain/chain.bend:1-18` | "**A NON-ZERO KERNEL COUNT**"; the plant "MUST MOVE" it; cites `:1139` | `ch_lin_n=0`, `ch_lin_n_plant=0`; the plant cannot bite below a zero; `:1295` |
| `.agents/slop/chain/GAP.md:1` | "stage 1 … IS NOT PORTED" | a correction block at the top: implemented in `rangify.bend`, unwired in `eng_stages()`; `0 → 1` measured |
| `.agents/slop/execgap/REPORT.md` §6.1 | "`rangeify.bend:2810` has `run_rangeify -- NOT PORTED` … THE MISSING LINK IS ONE STAGE" | stage is ported and unwired; the next wall is `pm_add_loads`, measured via `cc` |
| `.agents/slop/execgap/execgate.bend:268` | `TODO(p3) schedule/rangeify.bend:2810 … APPLY HALF is not driven` | `:2700`; ported and unwired; plus the `LOAD` defect named |

**NOT CORRECTED, ON PURPOSE:** `schedule/rangeify.bend:2700` still reads
`[Stg{0, Nil{}}, # 1 run_rangeify … NOT PORTED`. That file is **modified in the working tree by
another unit right now** (`git status --porcelain -- tinybendygrad/schedule/rangeify.bend` → ` M`,
a 36-line `ab_10` addition), so a `git commit --only -- <path>` would carry that unit's in-flight
work. **The correction to apply, once that file is quiet:**
```
-[Stg{0, Nil{}},         # 1  run_rangeify -- rangeify.py:344 -- NOT PORTED
+[Stg{0, Nil{}},         # 1  run_rangeify -- rangeify.py:344 -- NOT AN ENGINE TABLE: the
+                        #    driver is rangify.bend's rr_run_rangeify (:1653), which this
+                        #    list does not call; MEASURED, rr_kernel_graph + schedule() = 1
+                        #    kernel where this stage list alone = 0.
```

## 4. METHOD, AND WHAT I DID NOT DO

- **Callers**: `callers.py` walks 589 live `.bend` files (`tinybendygrad/`, `gates/`,
  `.agents/slop/<unit>/*.bend`) and excludes `#`-leading lines, because a name in a comment is a
  mention. It does NOT use `glob` (`AGENTS.md`: it answers `[]` with `.bend` on disk), and it
  excludes vendored port copies under `.agents/slop/*/tinybendygrad/` — MEASURED, without that
  rule `linearize` "had" 40+ callers and every one was a copy of itself.
- **Runs**: every `bin/bend` under `checks/bounded.py --mb 4000`; every verdict read off the
  `[bounded]` token (`WITHIN-LIMITS` in every case) and off the gate's own token, never the exit
  status alone.
- **Did not touch**: `shaders/`, `tinybendygrad/engine/**`, `tinybendygrad/tensor.bend`,
  `AGENTS.md`, or `gates/rangify-gate.bend` (D5 is a code fix, not a label — REPORTED).
- **Did not build**: `pm_add_loads`'s graph driver (D3/D4), `Tensor.realize` (D1), and the
  `eng_stages()` wiring (D2). The brief says REPORT them, and the orchestrator is wiring this
  path in parallel.

## 5. FILES

| path | what it is |
|---|---|
| `census.rows` | the 15 rows this report is built from, with `label_says`/`label_true` |
| `callers.rows` | the caller census (produced by `callers.py`), one row per stage, full caller lists |
| `callers.py` | the caller instrument: population by directory shape, comments excluded |
| `probe_kg.bend` | the decisive measurement: `rr_kernel_graph` → `schedule()` = 1 kernel, engine path = 0 |
| `probe_lin.bend` | the linearized kernel, node by node: **zero `LOAD`s** |
| `execfull.bend` | the port's own sink → rangify → schedule → `compile_sink` → C → `cc` → run (FAILS at `cc`) |
| `probe_dev.bend` | `compile_sink` reached from outside `device.bend`: 665 bytes of C, so the module imports |
| `raw-*.{out,err}` | the captured runs of every gate quoted above |
