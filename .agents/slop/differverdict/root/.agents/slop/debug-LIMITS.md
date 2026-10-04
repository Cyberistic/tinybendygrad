# debug-gate -- WHAT IT DOES NOT SHOW, and what it got wrong.

Every item here is MEASURED on this tree and every one is printed by the tool rather than
living only in this file: the per-level row counts are on every run, the digest's row count
is on the digest line, the upstream inventory is printed by `debug-gate.py --inventory` and
by `debug-gate.sh` itself, and the controls in `.agents/slop/debug-gate-control.py` are what
turn the new assertions red on demand. What this file adds is the reasoning, and the items
that CANNOT be printed.

Run: `sh .agents/slop/debug-gate.sh`
Controls: `.venv/bin/python .agents/slop/debug-gate-control.py`
Inventory: `.venv/bin/python .agents/slop/debug-gate.py --inventory`
Per-level reachability: `.venv/bin/python .agents/slop/debug-gate.py --probe-levels`

---

## 1. DEFECTS FOUND BY WRITING THIS, all in this gate's own machinery

These are not limits; they are bugs that existed while this file was being extended, and
they are listed because a coverage claim is only worth what the holes in it cost.

1. **THE LEVEL-INVARIANT DIGEST WAS VACUOUS AND THE GATE WAS GREEN THROUGH IT.**
   `INVARIANT_PREFIXES="gi_ mem_mb_ thr_ pin_ fires_ st_ok"` with
   `grep -E "^($INVARIANT_PREFIXES)"` reaches grep as `^(gi_ mem_mb_ thr_ ...)` -- SPACES
   inside the group -- and matches NOTHING. The digest was then the md5 of the empty string,
   `d41d8cd98f00b204e9800998ecf8427e`, at every level, so `distinct=1` and the guard
   reported agreement while comparing nothing. MEASURED: 55 of 89 rows are selected once the
   separator is `|`, and the real digest is `af36021d2ac482873fa39e55fb2aa17a`. **The fix is
   not the `|` so much as the ASSERTION** -- the selection now counts its own rows and exits
   2 below a floor, because a digest over nothing is STABLE, and stability is exactly what
   such a guard mistakes for agreement. This is `agent-core.md`'s "an all-empty block is a
   WALKER FAILURE" arriving in a gate that had never been red.
2. **A CHECK THAT READ A FILE A NARROWED RUN NEVER WROTE STILL PRODUCED A VERDICT.** The
   level-discrimination table reads `$GT.1.py`/`$GT.2.py` BY NAME; under
   `DEBUG_GATE_LEVELS=4` neither existed, `value_of` returned empty, and the run exited 1
   with all three lanes in agreement. Now inside the full-set guard.
3. **THE DIGEST GUARD WAS GATED BEHIND THE FULL NINE-LEVEL SET, so a control could not reach
   it.** `check_digests` is gated on the level COUNT (>= 2) instead, because "these rows do
   not differ between these levels" is a real claim at two levels and a tautology at one.
4. **`sh` is not bash.** `${got:-(nothing fires)}` is a PARSE ERROR under `#!/bin/sh`, and it
   fired at parse time -- after all nine levels had run and printed nine green lines. `sh -n`
   is worth its millisecond.
5. **THE PORT'S `pin_*` numbers were unreadable without `sys.settrace`.** `memory_plan_rewrite`
   returns a UOp, not a plan, so `first_appearance`, `nbytes`, `arena_sizes` and
   `total_memory` are frame locals (memory.py:31/42/45/53) and there is no return value to
   read. `.agents/slop/x86/x86-oracle.py:93-118` is the precedent; re-deriving the recipe
   would have been free to agree with a wrong port.
6. **14 `usites_*` ROWS WERE MANUFACTURED AND THEN REMOVED.** The upstream inventory was
   first emitted as compared rows. Both lanes compute it from the same grep over the same
   tree, so all 14 would have agreed, and the shared-row count would have risen 89 -> 103
   with 14 claims about nothing. **That is the `nv_query_litter` shape: two copies of one
   thing agreeing perfectly.** It is now a printed table, and the compared row count means
   one thing only -- claims about the port.

---

## 2. WHAT THE LEVEL ROWS DO NOT SHOW

### 2.1 THE HEADLINE: ZERO OF THE 17 NEW ROWS IS ABOUT ANYTHING A LEVEL 3..7 SITE PRINTS.

MEASURED, whole `name=value` lines, CPython lane, against level 0:

| level | rows differing from level 0 | of | which are NEW at this level |
|---|---|---|---|
| 1 | 3 | 89 | `mem_plan`, `mem_L1`, `thr_mem` |
| 2 | 12 | 89 | the 8 site rows + `env_ge1` + `env_ge2` + `env_value` |
| 3 | 13 | 89 | `env_ge3`, `env_value` |
| 4 | **14** | 89 | **`env_ge4`, `env_value`** |
| 5 | 15 | 89 | `env_ge5`, `env_value` |
| 6 | 16 | 89 | `env_ge6`, `env_value` |
| 7 | 17 | 89 | `env_ge7`, `env_value` |

**EACH NEW LEVEL ADDS EXACTLY TWO DIFFERING ROWS, AND BOTH ARE ABOUT THE GATE PREDICATE.**
So the 72 -> 89 growth decomposes as: 4 `env_ge4..7` (the predicate at the new thresholds),
5 `pin_*` (the memory-plan fixture, LEVEL-INVARIANT, so carrying no level information at
all), and 8 `fires_L0..7` (which of the seven **level-1 and level-2** sites fire at level L).
**NOT ONE OF THE 17 IS A ROW ABOUT A LEVEL 3, 4, 5, 6 OR 7 PRINT.** "0 disagreements at
level 7" is 89 rows agreeing, of which the level-7-specific content is one row about
`7 >= 7`.

### 2.2 THE PORT HAS NO SITE AT LEVELS 3, 4, 5, 6 OR 7. THAT IS THE COVERAGE FACT.

MEASURED by grepping `tinybendygrad/` for `H.debug_ge(_, N)` -- a grep, not a constant, so
adding a port site moves the number:

| threshold | port sites | upstream sites | of which print |
|---|---|---|---|
| 1 | 1 | 14 | 14 |
| 2 | 6 | 22 | 20 |
| 3 | **0** | 17 | 16 |
| 4 | **0** | 8 | 8 |
| 5 | **0** | 6 | 5 |
| 6 | **0** | 2 | 1 |
| 7 | **0** | 5 | 5 |
| total | **7** | **76** | **70** |

**7 of 76.** And the seven the gate DOES cover are 7 of the 22 at level 2 -- the other 15
at that level (`am/ip.py` x5, `nvdev.py`, `bnxtdev.py` x2, `codegen/decomp/dtype.py`,
`codegen/opt/search.py` x4, `engine/realize.py` x2, `function.py`) are ungated. A row at
level 3 or above therefore CANNOT be a disagreement about the port's code: there is no port
code at that level to disagree about.

### 2.3 LEVEL 3 WAS ALREADY A DECLARED ABSENCE AND THE OLD GATE DID NOT SAY SO.

`debug-gate.sh` ran a `DEBUG=3` lane before this change and reported it as coverage. It is
not: the port has 0 sites at threshold 3, and all 17 upstream level-3 sites print something
else. That lane establishes CUMULATIVITY (the level-2 sites still fire at 3) and nothing more.
It is now named as such on the run.

### 2.4 LEVEL 6 IS A LIMIT OF UPSTREAM, NOT OF THE PORT, AND IT CONTRADICTS THE BRIEF.

The brief's scale says `6 = + linearized`. **This tree has no `DEBUG >= 6` that prints a
linearized graph.** MEASURED: level 6 has 2 sites. `runtime/support/usb.py:25` sets
`LIBUSB_OPTION_LOG_LEVEL` -- a libusb option, not a print. `viz/cli.py:216` is a render
predicate reachable only from the `viz` CLI. And on a fixed end-to-end fixture, level 6 adds
**0 stdout lines over level 5** (28 at both). `schedule/__init__.py:141` prints the SCHEDULED
kernel COUNT at `DEBUG >= 3`, not a linearized graph, and nothing else in `tinygrad/` renders
a linearized graph under `DEBUG`. So a level-6 gate can only assert an absence, and it is an
absence upstream has too. **This is the one level where the port and upstream agree on
nothing being there, which is not coverage of level 6 -- it is coverage of level 6's
emptiness.**

### 2.5 LEVEL 5'S ABSENCE IS A GAP, NOT A STRUCTURAL IMPOSSIBILITY.

`codegen/__init__.py:274` is `print(pyrender(ast))` -- the UOp list, and the coordinator's
"level 5 = + UOps" is right about this tree. **The port HAS `pyrender`**:
`tinybendygrad/uop/render.bend:1886`. So level 5 is not unrepresentable; it is a two-line gate
away in `codegen/__init__.bend`, which has **zero** `debug_ge` sites today. Calling this a
structural absence would be wrong; it is unbuilt.

### 2.6 WHAT EACH LEVEL'S CONTENT IS, AND WHERE THE PORT STANDS ON IT.

* **level 4 -- GENERATED CODE.** `codegen/__init__.py:444` `print(ctx.asm_str(lst, ...))`,
  `:453` `print(src)`, `:462` `print(source.arg)`; plus `renderer/nir.py:234`,
  `codegen/opt/heuristic.py:107/134`, `codegen/opt/search.py:73`, `viz/cli.py:214`. 8 sites,
  all printing. MEASURED reachable end-to-end: level 4 adds the generated C
  (`void E_3(float* restrict data0_3, ...) { ... }`, 7 lines) to a fixed 2-tensor program.
  The port has no codegen print and no `asm_str`.
* **level 5 -- THE UOP LIST.** `codegen/__init__.py:274` plus `ops_cuda.py:119` (PTX),
  `usb.py:115`, `viz/cli.py:215/216`, and one non-printing (`ops_dsp.py:283`, a qemu
  `-strace` flag). MEASURED reachable: level 5 adds the `pyrender` block
  (`c0 = UOp(Ops.PARAM, (), ParamArg(0, dtypes.f32, 3, device='CPU'))` ... 8 lines).
* **level 7 -- DISASSEMBLY plus a BUFFER LEDGER.** `codegen/__init__.py:464`
  `ctx.compiler.disassemble(lib)`, `runtime/support/compiler_llvm.py:56`,
  `device.py:171/198` `buffer: allocate|deallocate N bytes on DEV`, `viz/cli.py:218`. 5
  sites, all printing. MEASURED reachable: level 7 adds 25 lines over level 6, including the
  full `objdump` disassembly of the kernel object.
  **The port's `device.bend` has NO `debug_ge` at all**, so the buffer ledger -- the only
  level-7 content this gate's own `st` lane incidentally stumbles into -- is ungated.

### 2.7 THE LEVEL-7 LANE IS WHERE A WRONG `KEEP` FILTER WOULD SHOW UP, AND THAT IS DELIBERATE.

At `DEBUG=7` the `st` lane's stdout contains REAL level-7 output -- `buffer: allocate 22
bytes on DISK:...` from `device.py:171`, plus `opened device`, `loading libc`, and the
`scheduled ... kernels` line from `schedule/__init__.py:141`. The oracle's `KEEP` filters are
PREFIXES of the very strings the gated sites produce, so a filter that stopped excluding
neighbour chatter at level 7 would print extra rows rather than hide any. That is why the
level sweep was extended instead of trusting the level-2 lane to generalise.

---

## 3. WHAT THE FIXTURES CANNOT SHOW

**`amdev.py` cannot be reached on this host.** MEASURED, `AMDev(0)` raises
`AttributeError: 'int' object has no attribute 'pcibus'`, so the oracle `exec`s the cited
source LINE with a stand-in `self`. Four of the seven rows are therefore evidence about a
SOURCE LINE and a gate, not about an AMD device. Nothing here has ever touched a GPU.

**`state.py:260` is exec'd-and-parsed, not run through a device.** The lane builds a real
on-disk pickle with three discarded pickles, the GLOBAL-opcode dict as the fourth and `ids`
as the fifth (state.py:283-290), so the dump is real; but the positive row comes from
`torch_load` and the four `am*` rows do not come from `torch_load` at all.

**`allreduce.py:16` is called with a hand-built 4-tuple `device`.** `handle_allreduce` is
invoked for real over a real `BUFFER` UOp, but no multi-GPU fabric is involved. The
256000-element threshold and the `ALL2ALL=2` override are both exercised; the RING path is
exercised as a NAME, not as eight real peers exchanging data.

**`mem_mb_*` is measured on multiples of 256 ONLY, and 76 integers in the first 40000 are
outside that population** where CPython's `f"{0.015:.2f}"` is `'0.01'` and half-even on the
rational is `'0.02'` -- because CPython formats the BINARY FLOAT. Those are excluded
deliberately and the exclusion is in `bend2-constraints.md`; putting them in the gate would
make it red for a documented narrowing.

**`gi_*` measures `getenv`'s coercion, not `int()`.** The value comes from the ENVIRONMENT
and the DEFAULT chooses the coercion (helpers.py:163), so each of the 19 texts needs its own
process. The negative-value narrowing (`int("-1")` is `-1` in CPython, a `U32` cannot hold a
negative, so the port answers the default) is invisible at every site because every threshold
is `DEBUG >= N` with `N >= 0` -- measured, `gi_m1_ge1..3` are 0 on both sides. **That is a
narrowing with three rows, not a proof the two agree on negative levels.**

---

## 4. THE TWO GUARDS COVER DIFFERENT FAILURES, AND NEITHER IS REDUNDANT

Both are exercised by `.agents/slop/debug-gate-control.py`, on a scratch copy, and both have
been seen firing:

* **the per-level three-lane diff** catches a row that is wrong at EVERY level. C8 doubles
  `pin_bufs` (5 -> 10): rc=1, names `pin_bufs`.
* **the level-invariant digest** catches a row that MOVES WITH THE LEVEL while both lanes
  agree -- i.e. the cross-level comparison would be comparing two different programs. C6
  plants `+ <the live DEBUG>` into `pin_bufs` on BOTH lanes: rc=**2**, not 1, and the
  message says so.

**The digest is BLIND to a constant wrong value** and that is by construction: a value wrong
at every level digests identically at every level. So "distinct=1" is a statement about
cross-level well-posedness and NOTHING about correctness. Correctness at one level is the
CPython diff's job, and the two are not substitutes.

**C6 needed four attempts and every failure is instructive**, so they are recorded at the
plant: a doubled value tests correctness not well-posedness; a one-lane plant is answered by
the per-level diff first; adding `+ DEBUG.value` to the oracle is a NO-OP because the oracle
reads that fixture in a child spawned at `DEBUG` unset **on purpose**; and the Bend bind was
at the top of a `def` body, which does not parse, so the lane printed ZERO rows and the
control could not tell "the guard stayed silent" from "nothing ran". **A PLANT THAT DOES NOT
COMPILE IS A LANE THAT PRINTS NOTHING, AND A LANE THAT PRINTS NOTHING IS A ZERO-ROW RESULT,
which is indistinguishable from NOT STARTED.** The control now asserts its planted runs
produced their rows.

---

## 5. WHAT A CLEAN RUN DOES AND DOES NOT ESTABLISH

A clean run establishes: on this tree, at each of nine levels, CPython's `tinygrad` and the
port's four `*_dbg` sites plus `helpers.bend`'s `getenv_int`/`debug_ge`/`gi_of_text` agree
on all **89** row names -- 89 x 9 levels x 3 lanes -- the row set is byte-identical across
lanes, all **8** site rows move from silent at 0 to firing at 7, the level-invariant digest
is `distinct=1` over all nine levels across **55** of the 89 rows, and the seven gated sites
fire at every level at or above their threshold and only there.

It does NOT establish: anything about levels 3, 4, 5, 6 or 7's CONTENT (2.1); that the port
has any site above threshold 2 (2.2); anything about the other 15 upstream level-2 sites, or
the 69 above them (2.2); that a linearized graph exists at level 6 in this tree, because it
does not (2.4); that level 5 is unrepresentable in the port, because `pyrender` is already
ported (2.5); anything about a real AMD, NV, CL or USB device (3); or that the digest says
anything about correctness (4).

**The gate is STANDALONE.** `rebase-gate.py` does not mention it, so no aggregate number has
ever included it and its green is invisible to every tally quoted. The measurements the
owning unit needs are in `.agents/slop/debug-roster-intersect.py`, including the blocker:
`run_port` sets `DEV="NULL"` for the oracle (rebase-gate.py:580) and nothing for the two bend
lanes, and the port has no argv read at all, so a roster-driven run would put the bend lanes
at `DEBUG`-unset and the oracle at its argv's level -- **three lanes at two different levels,
which is the one thing this gate was built to make impossible.**