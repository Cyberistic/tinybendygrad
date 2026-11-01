# SPEED PARITY: THE THREE STAGES, MEASURED

**2026-10-31.** Every number carries the command that produced it.

`.venv/bin/python .agents/slop/perf/bench.py --iters N --size N --lanes CPU,PYTHON,METAL,BEND`
runs ONE program -- `(A @ B) @ C`, f32, the same arithmetic
`checks/.e2e-fixture/e2e_mm.py` uses -- on every lane that runs on this machine.

## 0. WHICH LANES EXIST HERE, MEASURED

    CPU      AVAILABLE  CPUDevice
    METAL    AVAILABLE  MetalDevice
    PYTHON   AVAILABLE  PythonDevice
    WEBGPU   UNAVAILABLE  failed to load library webgpu: try setting WEBGPU_PATH?
    BEND     AVAILABLE  BendDevice        (after `sys.modules['tinygrad.runtime.ops_bend'] = ops_bend`)

**⇒ AND THE FOUR LANES THE OBJECTIVE NAMES ARE NOT FOUR THINGS.** "python to X"
is CPython scheduling and rendering; "bend to X" is the port's. For WEBGPU the
Bend side has **no kernel-executing device at all** -- `runtime/ops_webgpu.bend`
is a TRACE port and `webgpu_call.js` drives a call sequence with **CPython-rendered
shaders**. For METAL the Bend side has **no device whatsoever**; `ops_metal.bend`
is a render/trace port. **⇒ SO STAGES 1 AND 2 ARE QUESTIONS ABOUT **EMITTED CODE**,
AND STAGE 3 IS THE ONLY ONE WITH TWO RUNNING DEVICES.**

## 1. PYTHON TO WEBGPU vs BEND TO WEBGPU — MET AT THE CODE LEVEL

    .venv/bin/python gates/wgsl_render_census-gate.py
    wgsl_render_census: PASS -- 227 rows x 3 lanes, 215 exact,
                        12 pinned lane divergences in 5 classes, 0 stale self-checks

**⇒ 215 OF 227 WGSL ROWS ARE BYTE-IDENTICAL BETWEEN CPython's `renderer/wgsl.py`
AND THE PORT's `renderer/wgsl.bend`.** A byte-identical shader compiled by the same
driver and dispatched with the same bindings runs at the same speed **by
construction** -- there is no second artifact to be slower. **⇒ SO THE ONLY PLACE
A SPEED DIFFERENCE COULD LIVE IS THE 12 DIVERGENCES, AND THEY ARE PINNED AND
CLASSIFIED, NOT UNKNOWN.**

## 2. PYTHON TO METAL vs BEND TO METAL — MET AT THE CODE LEVEL

    $ .venv/bin/python -c '...compare every kernel-text row in gates/cstyle-live.rows...'
    kern2 BASE         identical=True bytes=148
    kern2 CLANG        identical=True bytes=170
    kern2 METAL        identical=True bytes=444
    kern2 BASE  pref2  identical=True bytes=226
    kern2 BASE  pref0  identical=True bytes=150
    kern2 METAL pref2  identical=True bytes=444
    kern2 BASE  vol    identical=True bytes=157
    kern2 CLANG vol    identical=True bytes=179
    kern2 BASE  alu    identical=True bytes=156
    kern2 CLANG alu    identical=True bytes=160
    kern2 METAL alu    identical=True bytes=406
    --- 11/11 identical ---

**⇒ ALL ELEVEN KERNEL-TEXT ROWS ARE BYTE-IDENTICAL, INCLUDING ALL THREE METAL
ONES.** Same source, same compiler, same speed. **⇒ AND THE HONEST LIMIT IS NAMED:
THIS IS CODE PARITY, NOT EXECUTION-LANE PARITY**, because the port has no Metal
device to time.

## 3. PYTHON DEVICE vs BEND DEVICE — THE ONE REAL GAP

    $ .venv/bin/python .agents/slop/perf/bench.py --iters 2 --size 16 --lanes CPU,PYTHON,BEND
    CPU            1.36 ms/iter   max|diff vs CPU| 0.000e+00
    PYTHON       531.63 ms/iter   max|diff vs CPU| 8.941e-08
    BEND       30759.40 ms/iter   max|diff vs CPU| 8.941e-08

    relative to CPU:  CPU 1.00x   PYTHON 391.21x   BEND 22634.89x

**⇒ BEND IS 57.8x SLOWER THAN PYTHON ON THE SAME PROGRAM, AND IT IS BIT-EXACT TO
IT** (`8.941e-08` on both, against CPU).

### 3.1 WHERE THE 57.8x GOES, DECOMPOSED

    $ .venv/bin/python -c '...time a 3-element add and a 16x16 matmul on both...'
    fixed overhead, 3-element add:   BEND 2184.7 ms    PYTHON 0.6 ms
    16x16 matmul (1 launch):         BEND 15451.9 ms   PYTHON 270.8 ms

**⇒ SO OF A 15 452 ms LAUNCH, 2 185 ms IS FIXED** (the subprocess spawn and the hex
round trip `ops_bend.py`'s own header names) **and 5 540 ms IS THE 4 096 MACs AT
1.35 ms/MAC**. The fixed cost is 28% of one small launch and would vanish into a
bigger one; **⇒ THE INTERPRETER IS THE GAP, AND THE TARGET IS 41x, NOT 58x.**

### 3.2 THE COST IS ALLOCATION, NOT ARITHMETIC — PROFILED, NOT GUESSED

The Bend executor was captured on one 16x16 matmul packet (9 544 bytes, 3 buffers,
70 uop lines) and sampled with macOS `sample`:

    $ ~/Library/Caches/tinygrad/bend-executor-* /tmp/pkt/PACKET.in 1 1 1 &
    $ sample $PID 3 -file sample.txt
    Call graph:
      2333 Thread ... com.apple.main-thread
      + 2333 start
      +   2333 main
      +     2333 io_loop
      +       2333 io_step
      +         2333 corpus_eval
      +           2333 work_loop
      +             2216 WL_FID_Prog_step
      +             ! 1127 spin_85
      +             ! : 815 span_fade
      +             ! : | 217 term_drop
      +             ! 448 spin_85
      +             ! : 204 span_fade

**⇒ 2216 OF 2333 SAMPLES ARE INSIDE `Prog_step`, AND ALMOST ALL OF THOSE ARE IN
`spin_85` → `span_fade` → `term_drop`** — which are the runtime's REFERENCE-COUNT
machinery: spinning on a refcount, dropping a span of a block, dropping a term.
**⇒ THE INTERPRETER IS NOT SLOW AT ARITHMETIC; IT IS SLOW AT **ALLOCATING AND
FREEING ITS OWN STATE**.**

**⇒ AND THAT IS A STRUCTURAL FACT ABOUT THE LOOP, NOT A MICRO-OPTIMISATION.**
`Prog.step` CONSTRUCTS A NEW 17-FIELD RECORD PER UOP
(`ops_python.bend:2362`-ish, `Prog{us, vs, v0, ms, fs, mk, vals, pc, n, pv, gx, gy,
gz, cx, cy, cz, bad, dead}`), and the previous record is dropped — so every one of
the ~18 000 uop dispatches in a 16x16 matmul allocates a record, copies 17 fields,
and then runs the full recursive teardown of the old one.

**⇒ SO THE FIX IS THE ONE THE GUIDE ALREADY NAMES**: `Array<T>` is a `Type`, and
`a[i] <- v` "overwrites the slot and hands back the same array, **with no copy**".
**⇒ THE STATE MUST BECOME AN `Array` SO THE STEP MUTATES INSTEAD OF REBUILDING** —
not for O(1) indexing, which the micro-benchmark below shows is not the problem,
but to stop the allocation/teardown that the profile says is 98% of the time.

### 3.3 WHAT WAS RULED OUT, WITH THE MEASUREMENT THAT RULED IT OUT

* **O(n) `List.get`/`List.set` in `Mem`.** A micro-benchmark of 2 000 get+set over
  a `List<U32>` of 8 192 slots costs **~0.12 s of compute** (0.19 s minus the
  0.07 s compiler start), i.e. **~7 ns per list cell**. Scaling the arena 8x costs
  **1.7x**, not 8x, so the list scan is NOT the pathology.
  (`.agents/slop/perf/listvsarray.bend` is the fixture; `List.replicate` takes
  `(A, n, x)`, not a lifetime, and `Array<T>` is a `Type` so it is threaded
  linearly — both cost a compile to learn.)
* **The packet decoder.** `Prog.parse.go` folds over the lines once, and
  `Prog.hex.go` + `Prog.hex.app` walk the hex once with an explicit note that
  "`List.set` per byte would be quadratic" — it was already fixed.
* **The CPython side.** `encode` 0.8 ms, `decode` 0.2 ms, `unmarshal` 0.3 ms.
  **The subprocess's own runtime is 15 374.8 ms of 15 376 ms** — measured by
  wrapping `BendProgram.__call__`.

### 3.4 WHAT IS LEFT FOR STAGE 3, IN ORDER

1. **`Prog`'s mutable state becomes `Array`** so `Prog.step` mutates in place. The
   profile says this is where 98% is. The 153-fixture census
   (`gates/ops_python_exec-fixtures.rows`, 0 divergences today) is the gate that
   says bit-exactness survived.
2. **Then** the per-launch subprocess + hex (2 185 ms on a trivial kernel) — the
   remaining 28% of a small launch, and a persistent executor removes it.

---

# 4. STAGE 3, SECOND PASS: ONE FIX LANDED, THE ABLATIONS MISLED ME, AND I SAY SO

    .venv/bin/python .agents/slop/perf/bench.py --iters 3 --size 16 --lanes CPU,PYTHON,BEND
    CPU       1.33 ms/iter
    PYTHON  532.92 ms/iter
    BEND  29694.76 ms/iter      -> 55.7x slower   (was 57.8x)

    .venv/bin/python gates/ops_python_exec-gate.py
    ops_python_exec: PASS -- 153 fixtures, 365 rows x 2 lanes,
                     365 unpinned identical, 0 pinned

## 4.1 WHAT LANDED, AND IT IS SMALL

`Prog.at`, `Prog.vs1`, `Prog.ms1`, `Prog.mk1` and `Prog.live.at` each rebuilt the
18-field `Prog` record by calling **SEVENTEEN separate `Prog.x(p)` projections**,
and **each projection is its own `match` over the same record** -- so one
`Prog.next` (one per uop) paid 17 record traversals instead of 1. They are now a
single destructuring `match` each. **MEASURED: 30 806 -> 29 660 ms, 3.7%**, and the
153-fixture census is unchanged at **0 divergences**.

**⇒ 3.7% IS NOT PROGRESS TOWARD 55.7x AND IT IS NOT REPORTED AS SUCH.** It is a
real, bit-exact simplification that happens to be slightly faster.

## 4.2 THE ABLATIONS, AND WHY THEY MISLED ME — WRITTEN DOWN BECAUSE IT MATTERS

I ablated by replacing one def's body at a time and re-timing:

| ablation | ms | read as |
|---|---:|---|
| baseline | 15 385 | |
| `Prog.step` -> `Prog.next` only | **148** | the loop is 1%, the op handlers 99% |
| `Prog.alu` -> `Prog.next` | **2 211** | "the ALU is 86%" |
| `Prog.ld1` -> `Prog.next` | 2 128 | "loads are 86%" |
| `Prog.store` -> `Prog.next` | 2 189 | "stores are 86%" |
| `Prog.index` -> `Prog.next` | 14 444 | index is 6% |
| `Mem.byte` -> 0 | 14 410 | 6% |
| `Val.put` -> identity | 14 068 | 9% |
| `Prog.src` -> zero | 14 090 | 8% |

**⇒ THREE OF THOSE CANNOT ALL BE TRUE, AND I READ THEM AS IF THEY COULD.** `alu`,
`ld1` and `store` each "accounting for 86%" is arithmetically impossible; the
consistent explanation is that **`Prog.alu` is not "the arithmetic", it is the
SHARED EVALUATOR** that `ld1`, `store` and `index` also route through — so
disabling it stops the walk rather than removing one third of it. **⇒ AND I ACTED
ON THE MISREADING**: I landed fast paths for `MUL`/`ADD`/`SUB`/`MAX` in `alu2` and
for `MULACC` in `alu3`, measured **0%** for both, and **REVERTED THEM** rather
than leaving 40 lines of complexity that buy nothing.

**⇒ THE LESSON IS THE ONE THE TREE ALREADY CARRIES ABOUT MUTATION HARNESSES**: an
ablation that changes CONTROL FLOW is not a measurement of a cost, it is a
measurement of a different program. **A COST ATTRIBUTION NEEDS A SAMPLING
PROFILER WITH PER-SYMBOL LEAF COUNTS, NOT SUBTRACTION.**

## 4.3 WHAT IS ACTUALLY KNOWN, AND WHAT THE NEXT INSTRUMENT IS

Known, from `sample` (`.agents/slop/perf/bend-executor.sample.txt`): **2216 of 2333
samples are inside `WL_FID_Prog_step`, and its leaves are `spin_85`, `span_fade`
and `term_drop`** — the runtime's reference-count spin, span release and term
release. **And 14.7 s of the 14.9 s is USER CPU with 0.17 s of system**, so it is
not page faults or allocation of large blocks.

**⇒ THE NEXT INSTRUMENT IS A PER-SYMBOL LEAF CENSUS** — sum the SELF samples under
`Prog_step` by symbol rather than reading the call tree's nesting, which is what I
did and what produced the impossible 3x86%. Only then is "make `Prog` an `Array`"
justified or refuted; the guide's `a[i] <- v` ("overwrites the slot ... with no
copy") is the candidate, but **an unproven candidate is why 3.7% is all that
landed.**

### 4.4 THE PER-SYMBOL LEAF CENSUS §4.3 ASKED FOR, FROM THE SAME SAMPLE

`sample` writes a SELF-TIME table at the end of the file, and §4.2 did not read it.
**⇒ SO THE ATTRIBUTION WAS IN THE ARTIFACT ALL ALONG AND I READ THE CALL TREE
INSTEAD OF IT:**

    Sort by top of stack, same collapsed (when >= 5):
        __psynch_cvwait  (libsystem_kernel)            2333   <- the SAMPLER's own wait
        span_fade        (bend-executor)               1019   <- 44%
        term_drop        (bend-executor)                883   <- 38%
        spin_85          (bend-executor)                285   <- 12%
        OUTLINED_FUNCTION_12                            93
        spin_191                                         18
        WL_FID_run                                       12
        spin_82                                           7
        WL_FID_Prog_step                                  5

**⇒ `span_fade` (release a span of arena cells) + `term_drop` (release a term) =
1 902 OF 2 333 SAMPLES = 82%, AND WITH THE `spin_*` REFERENCE-COUNT SPINS IT IS
94%.** **⇒ THE INTERPRETER IS 94% MEMORY RELEASE.** It is not slow at arithmetic,
it is not slow at list scans, and it is not slow at decoding: it is slow at
**FREEING WHAT IT JUST ALLOCATED**, which is the functional-update churn
`Prog.step` creates and the one `Array<T>`'s `a[i] <- v` ("overwrites the slot ...
with no copy") exists to remove.

**⇒ SO THE `Array` REWRITE IS NOW JUSTIFIED BY A NUMBER AND NOT BY A HUNCH** — and
that is the difference between the 3.7% I landed and the fix that has not been
written. It has NOT been written: **§3's 55.7x stands, and this report does not
claim otherwise.**

**⇒ AND THE METHOD LESSON IS THE ONE WORTH KEEPING**: `sample` writes both a call
tree AND a self-time census, and reading only the tree produced three mutually
impossible "86%" readings from a table that said 82% in one line. **A PROFILE HAS
MORE THAN ONE VIEW AND THE CHEAPER ONE WAS THE RIGHT ONE.**

---

# 5. THE ABLATION THAT INVALIDATES ALL THE OTHER ABLATIONS

**`§4.2`'s ablations were already called misleading. They are worse than that: THE
CONTROL ITSELF WAS INVALID, AND IT IS THE ONE EVERY OTHER READING WAS DIVIDED BY.**

## 5.1 THE CONTROL

    $ # Prog.step -> Prog.next, i.e. "the loop with no op handling"
    ABLATED B: 148 ms

Read as "the loop is 148 ms of 15 385, so the op handlers are 99%".

**⇒ AND THAT IS NOT WHAT IT MEASURED.** With `Prog.step` replaced by `Prog.next`,
the pc ADVANCES EVERY STEP AND NEVER JUMPS -- `END` never returns to its RANGE and
`BACKEDGE` never loops. **⇒ SO THE WALK TERMINATES AFTER ~70 STEPS INSTEAD OF THE
18 000 A 16x16 MATMUL TAKES.** The 148 ms is a SEVENTY-STEP program; the 15 385 ms
is an eighteen-thousand-step one. **They are not the same denominator, and every
"X is Y% of the total" reading in §4.2 inherits the error.**

**⇒ AND THE SAME FAULT IS IN THE HANDLER ABLATIONS**: replacing `Prog.rng` or
`Prog.alu` with `Prog.next` also stops the walk from looping, which is why
`alu`, `ld1` and `store` EACH came out as "86%" -- **EACH OF THEM WAS MEASURED
AGAINST A PROGRAM THAT HAD STOPPED LOOPING.**

## 5.2 WHAT ACTUALLY HOLDS, AFTER THE SECOND ROUND

| what | ms | note |
|---|---:|---|
| baseline (projection fix) | 29 660 | `bench.py`, 2 iters |
| `Mem.byte` -> 0 | 14 410 | reads are fast; `List.get` does not allocate |
| `Mem.put` -> identity | 14 788 | **4%** -- the `ms` list copy on store is NOT the cost |
| `Val.put` -> identity | 14 068 | **9%** |
| `Prog.src` -> zero | 14 090 | **8%** |

**⇒ SO NONE OF THE FOUR BIG LIST OPERATIONS IS THE COST, AND THE `Array` REWRITE
OF `us`/`vs`/`ms` IS **NOT** JUSTIFIED BY THESE NUMBERS.** The remaining ~13 s is
inside the handlers' own bodies, and **the ONLY attribution that survives is the
one from `sample`'s self-time table: `span_fade` 1019 + `term_drop` 883 + `spin_*`
310 of 2333 samples = 94% in REFERENCE-COUNT RELEASE.** That table is a
measurement of the REAL program, not of an ablated one, and it is the only one in
this report that is.

**⇒ AND `span_fade`/`term_drop` RELEASE WHAT IS ALLOCATED — SO THE QUESTION IS
"WHAT ALLOCATES", AND THE ABLATIONS SAY IT IS NOT THE FOUR LIST OPERATIONS.** The
candidates left are the record rebuilds themselves (18 000 of them, each 18 fields
with 6 list pointers that are RC-incremented then RC-decremented) and `Elem`/`Uop`
construction inside the handlers.

## 5.3 WHAT I DID NOT DO, STATED PLAINLY

**The `Array` rewrite is NOT written, and this report no longer claims it is
justified.** Converting `us`/`vs`/`ms` to in-place `Array` state was the reviewer's
next step and §4.4's conclusion; §5.2 REFUTES that conclusion with four
measurements on the real program showing those four operations are 4-9% each.
**⇒ A REWRITE THAT REMOVES 4-9% OF THE COST CANNOT CLOSE A 55.6x GAP, AND STARTING
IT ON THE STRENGTH OF A NOTE I WROTE MYSELF WOULD HAVE BEEN THE SAME MISTAKE AS
§4.2, ONE LEVEL UP.**

**⇒ AND THE HONEST STATE OF THE GOAL IS UNCHANGED**: BEND is 55.6x slower than
PYTHON, one bit-exact 3.7% change has landed, and **every one of the three stages
is still unmet.**

---

# 6. SOURCE-ATTRIBUTED PROFILE, AND THE FIVE HYPOTHESES IT KILLED

**The reviewer asked for a symbolized profile. It is here, and it does not say what
I hoped.**

## 6.1 THE INSTRUMENT

    $ ./bin/bend tinybendygrad/runtime/ops_python.bend -o /tmp/exec.c   # 65 408 lines
    $ clang -O2 -g -o /tmp/exec_dbg /tmp/exec.c -lm
    $ /tmp/exec_dbg /tmp/pkt/PACKET.in 1 1 1 &                          # 15.61 s, 14.49 user
    $ sample $PID 4 -fullPaths -file /tmp/dbg.sample

**⇒ AND THE C IS THE COMPILER'S OWN OUTPUT**, so every symbol below is a Bend def
and not a guess: `executor.bend.c` and `executor-dbg.sample.txt` are committed
beside this report.

## 6.2 THE SELF-TIME CENSUS, WITH SYMBOLS

    Sort by top of stack, same collapsed:
        __psynch_cvwait        3096   <- the SAMPLER's own sleeping thread
        span_fade              1408   <- 48%
        term_drop              1145   <- 39%
        spin_85                 390   <- 13%
        OUTLINED_FUNCTION_12    109
        WL_FID_run               30
        WL_FID_Prog_step          8

**⇒ `span_fade` + `term_drop` + `spin_85` = 2 943 OF THE EXECUTOR's ~3 090 SAMPLES
= 95%, AND `Prog_step` ITSELF IS 8 SAMPLES.** The interpreter spends 95% of its
time in the runtime's REFERENCE-COUNT RELEASE, and 0.3% in its own dispatch.

## 6.3 FIVE HYPOTHESES THE GENERATED C KILLED

1. **"Every `Prog.step` allocates a task frame of 18 words."** The C does say
   `task_node(e, FID_Prog_step, ...)` + 18 `e.mem[...] = _pr_N` stores -- **BUT THE
   BRANCH IS `if (!DEVICE && !seq && fid_nofk(...))`, and `seq = stride == 0`
   (`:63498`).** Single-threaded, `stride == 0`, so `seq` is TRUE and **the frame
   is never allocated**. **⇒ DEAD.**
2. **"It is the worker pool contending on the allocator's bank lock."**
   `bank_push` does `LOCK(bank_lock)`, and `__psynch_cvwait` tops the table -- **but
   `--threads 1` changes nothing (14.76 s vs 14.71 s), and cvwait is the SAMPLER's
   own thread, which sleeps for the whole run and therefore tops every such
   table.** **⇒ DEAD, and the reading was noise.**
3. **"`heap_alloc` grows the arena."** `heap_alloc_miss` only falls back to
   `corpus_grow` when a bump fails; a 16x16 packet never exhausts it.
4. **"The four list operations."** Already refuted in §5.2: `Mem.put` 4%,
   `Mem.byte` 6%, `Val.put` 9%, `Prog.src` 8%.
5. **"`span_fade` walks a big list."** `span_fade` is O(n) over the span it fades,
   and the only big `List` in play is the memory arena (3 072 cells) -- **which is
   hypothesis 4 again, and hypothesis 4 is already refuted.**

## 6.4 WHAT IS LEFT, AND WHY I AM STOPPING HERE

**⇒ WHAT IS ESTABLISHED**: 95% of the executor's time is `term_drop`/`span_fade`/
`spin_85`, and it is NOT the record rebuild, NOT the four list operations, NOT a
task frame, NOT threading, and NOT the arena growing.

**⇒ WHAT I CANNOT DO WITH THE INSTRUMENTS I HAVE**: say WHICH allocation is being
released. `term_drop`/`span_fade` are the runtime's generic free path, and `sample`
attributes time to the FREE rather than to the allocation that made it necessary.
Finding it needs either an allocation-site profile (which Bend's runtime does not
expose) or an instrumented rebuild of the runtime -- **not another ablation, and
not another guess.**

**⇒ AND EIGHT ATTEMPTS HAVE PRODUCED 3.7%.** The honest summary of stage 3 is:
BEND is 55.6x slower than PYTHON, the cost is 95% reference-count release, and I
have not identified the allocation that requires it. **I am stopping rather than
landing a ninth speculative change.**

---

# 7. THE ALLOCATION, COUNTED — AND IT VINDICATES THE `Array` REWRITE I REFUTED IN §5.2

**The reviewer asked to instrument the allocation, not the free. Done: a counter
was compiled into a COPY of the compiler's own C (`ctr/exec_ctr.c`), and the tree
is untouched.**

    $ clang -O2 -o ctr/exec_ctr ctr/exec_ctr.c -lm
    $ ctr/exec_ctr /tmp/pkt/PACKET.in 1 1 1
    CTR bank_pop=1719 bank_push=210 heap_alloc=6011075 heap_free=6011075
        term_drop=2412939949 span_fade=1263244637 span_fade_terms=7914431233

## 7.1 PARSE OR RUN? — THE ZERO-GRID CONTROL

    $ ctr/exec_ctr /tmp/pkt/PACKET.in 0 0 0
    CTR heap_alloc=272720 term_drop=67908 span_fade_terms=116338
    real 0.01

**⇒ THE PACKET PARSE IS 0.01 s AND 67 908 `term_drop` CALLS.** So 2 412 939 949 -
67 908 ≈ **2.41 BILLION drops are the RUN LOOP**, and the parse is 0.07% of them.

## 7.2 AND 8x8 vs 16x16 SAYS IT IS NOT THE COMPUTE EITHER

    8x8 packet (3 362 B):  term_drop=1 301 499 820  span_fade_terms=4 276 184 334
    16x16 packet (9 544 B): term_drop=2 412 939 949  span_fade_terms=7 914 431 233

**1.85x for 4x the arena AND 8x the MACs.** Neither variable explains it alone --
which is the signature of `steps x arena`.

## 7.3 THE ARITHMETIC THAT NAMES IT

`Prog.load.put` builds the state as `List.replicate(Elem, Build.slot(b), zero)` for
`vs` and `Prog.bytes(...)` for `ms`. For this packet `ms` is **3 buffers x 1 024
bytes = 3 072** cells and `vs` is the slot count, **~70**.

**⇒ 2 412 939 949 / (3 072 + 70) = 767 000 STEPS.** And a 16x16 matmul is 4 096
MACs; at ~180 uops per MAC that is **737 000 steps. THE TWO NUMBERS AGREE.**

**⇒ SO EVERY ONE OF THE ~767 000 UOP STEPS DROPS AND REBUILDS THE 3 072-CELL
ARENA, AND `term_drop` IS CALLED ONCE PER CELL.** That is `steps x arena` -- 2.3
billion refcount calls at ~4 ns each = **9 s of the 15 s**, which matches §6's 95%
in `term_drop`/`span_fade`.

## 7.4 SO §5.2 WAS WRONG, AND I SAY WHICH PART

§5.2 concluded "`Mem.put` is 4%, so the `Array` rewrite removes 4-9% and cannot
close the gap". **⇒ THAT ABLATION REPLACED `Mem.put` WITH IDENTITY, WHICH MAKES
STORES NO-OPS -- IT CHANGED THE PROGRAM, AGAIN.** The counter does not change the
program: it says the arena is walked once per step, and a step that stores nothing
still walks it, which is exactly why the ablation under-reported.

**⇒ THE `Array` REWRITE IS CORRECT AND IS NOW JUSTIFIED BY A COUNT AND NOT BY A
HUNCH**: an `Array` field is a POINTER THAT MOVES, so dropping the record stops
walking 3 072 cells, and `a[i] <- v` rewrites the slot in place.

## 7.5 WHAT IS STILL NOT DONE

**The rewrite is not written.** It is a change to `Prog`'s type across ~12 reader
defs and 8 record constructions, and the only safety net is
`gates/ops_python_exec-gate.py` (153 fixtures, 0 divergences). **⇒ THE DIAGNOSIS IS
NOW SETTLED AND THE WORK IS NOT**, and stage 3's 55.6x stands until it is.

## 7.6 WHAT THE COUNTER CANNOT EXPLAIN — AND WHERE I STOP

**`heap_alloc` IS 6 011 075 AND `term_drop` IS 2 412 939 949.** That is **401
`term_drop` CALLS PER ALLOCATION**, and a correct refcount frees each allocation
exactly once. So the runtime is calling `term_drop` ~400x more often than the heap
says it should, which is the shape of a QUADRATIC in the RC accounting and not of
a hot loop.

**⇒ AND §7.3's `steps x arena` ARITHMETIC, WHILE IT LANDS ON 2.41e9 EXACTLY, IS
THEREFORE NOT PROOF** -- two independent quantities agreeing to three digits is
what coincidence looks like when both are built from 3 072. **THE FALSIFIABLE
STATEMENT THE COUNT SUPPORTS IS ONLY THIS: `term_drop` IS CALLED 401 TIMES PER
ALLOCATION, WHICH NO CORRECT REFCOUNT SHOULD DO.**

**⇒ AND ONE MORE CHANGE WAS TRIED AND DID NOT MOVE IT**: `Prog.at`/`vs1`/`ms1`/
`mk1`/`live.at` took `p` as a REUSABLE (`+`) parameter, and a hypothesis that this
forced a clone on every field bind was worth one word -- **MEASURED 29 683 ->
29 973 ms, i.e. NOTHING**, and the tight version is kept only because it is
semantically correct (each reads its 18 fields exactly once) and the census still
reads 153 fixtures / 0 divergences.

**⇒ SO NINE ATTEMPTS HAVE PRODUCED 3.7%, AND THE LAST FOUR MEASUREMENTS SAY THE
COST IS A REFCOUNT ACCOUNTING QUADRATIC INSIDE BEND'S RUNTIME** -- `term_drop`
called 401x per allocation, on a program whose parse is 0.01 s and whose
interpreter dispatch is 0.3% of samples. **THAT IS NOT SOMETHING I CAN FIX FROM
`ops_python.bend`**: it is in the compiler's own runtime (`term_drop`/`span_fade`/
`rfc_bump` in the emitted C), and the emitted C is regenerated from the compiler on
every build.

---

# 9. THE COST, FOUND: ONE O(pc) WALK PER STEP — 12.3x LANDED

**§6-§8 said the cost was "reference-count release" and could not name the allocation.
This section names it, with a counter that does not change the program, and lands the
fix.**

## 9.1 THE INSTRUMENT THAT WORKED: COUNT CALLS, DO NOT ABLATE

Every earlier instrument replaced a def body, which changes the program (§5, §7.4).
The one that worked counts calls inside a COPY of the compiler's own C
(`/tmp/exec4.c`, the same file `executor.bend.c` records), so the program is untouched:

    spin86_calls = 4 121 245      # the uop-table walker
    steps        = 4 000 000

**⇒ ONE WALK PER STEP, NOT SIX.** That single number explains four earlier results at
once: §5's ablation control (70 steps instead of 18 000), §7.4's `Mem.put` identity
(4%), and this session's two attempts below (0%), because none of them touched the
walk that runs once per step.

## 9.2 WHAT THE WALK IS

`spin_86` takes a list and an index, and per cons cell it does
`ctr_take(cons, 2)` **and** `ctr_take(uop, 11)`, then frees the record. So one lookup
costs **13 field copies per cell walked**, each an atomic refcount op. `Prog.step`
called `Uop.at(Prog.us(p), Prog.pc(p))`, and `pc` climbs 0 -> n, so the walk is
**O(pc) per step and O(n^2) per kernel**: on this 148-uop kernel, ~74 cells x 26
refcount ops = ~1 900 per step — against **1 979 measured faded terms per step** (§7).
The arithmetic closes to three digits.

## 9.3 TWO REFUTATIONS THAT POINTED AT IT

| change | measured |
|---|---|
| `Prog.alu.at` projects `p`/`u` ONCE instead of 17 times | 29 900 -> 29 900 ms (**0%**) |
| pre-resolve each src's SLOT at load (`Uop.sslot`), deleting 5 of 6 walks | 29 900 -> 33 154 ms (**0% per step**, +0.82 s at load) |

**⇒ AND BOTH ARE EXPLAINED BY §9.1**: `Prog.src` is not called per step on this kernel,
so removing its walks could not help; the per-step walk is `Prog.step`'s. Both changes
were reverted; the second was reverted for adding 0.82 s of load for nothing.

## 9.4 THE FIX

`Prog` gains one field, `un: List<&2, Uop>` — the uops from `pc` onward.

    Prog.next  takes the tail            O(1)     -- this is the hot path
    Prog.at    re-seeks with List.drop   O(target) -- a JUMP, once per loop iteration
    Prog.step  reads the head            O(1)     -- was O(pc)

**⇒ AND IT IS BIT-EXACT**: `ops_python_exec: PASS -- 153 fixtures, 365 rows x 2 lanes,
365 unpinned identical`, and the bench still reads the same `max|diff vs CPU| 8.941e-08`.

## 9.5 MEASURED

    .venv/bin/python .agents/slop/perf/bench.py --iters 2 --size 16 --lanes CPU,PYTHON,BEND
      CPU        1.38 ms/iter   max|diff vs CPU| 0.000e+00
      PYTHON   547.18 ms/iter   max|diff vs CPU| 8.941e-08
      BEND   2 426.89 ms/iter   max|diff vs CPU| 8.941e-08     (min 2 280.02)

    before this change:  BEND 29 900 ms/iter  ->  12.3x faster
    PYTHON/BEND: 56x -> 4.4x

**⇒ AND AT 32x32 IT IS 14.45x, WHICH NAMES THE NEXT ONE**: BEND 38 754.96 vs PYTHON
2 682 ms (`--iters 1 --size 32`; the ratios are 24 962x and 1 727x against a CPU of
1.553 ms). The gap GROWS with the program because the arena grows: `Mem.put` is
`List.set` and `Mem.byte` is `List.get`, both **O(byte address)**, and the address
scales with the buffer. `heap_alloc = 6 011 075` over 4 000 000 steps is that
allocation stream.

## 9.6 STATUS, NOTHING SOFTENED

| stage | state |
|---|---|
| 1. python->webgpu vs bend->webgpu | **never timed**: no CPython WEBGPU binding, no kernel-executing Bend WebGPU device |
| 2. python->metal vs bend->metal | **never timed**: no Bend Metal device at all |
| 3. PYTHON vs BEND (16x16) | **547.18 vs 2 426.89 ms — BEND is 4.4x SLOWER** |
| 3. PYTHON vs BEND (32x32) | **2 682 vs 38 754.96 ms — BEND is 14.45x SLOWER** |

**⇒ THE GOAL IS NOT MET AND IS NOT CLOSE ON THE BIGGER PROGRAM.** What is established:
the per-step cost is now the arena's O(address) list access plus the per-step record
rebuild, not the interpreter's dispatch; and the `Array` conversion of `ms` — the one
this report twice argued about — is the fix that §9.5's scaling points at.

---

# 10. THE ARENA, CHUNKED: 1.87x AT 16x16, 2.9x AT 32x32

## 10.1 THE MEASUREMENT THAT JUSTIFIED IT

Before the change, on the same binary with counters compiled into a COPY of the
compiler's own C:

    packet    steps    heap_alloc     term_drop     span_fade terms
    16x16     4.0M      6 011 615    144 100 967      227 599 233
    32x32    16.0M    117 081 988   2 623 935 890   5 497 119 626

**⇒ 19.5x the allocations for 4x the steps**, and the run went 1.6 s -> 18.2 s. The
cause is `Mem.put = List.set(ms, at, v)`: a store rebuilds every cons before its byte
address, and the address scales with the buffer. `Mem.byte = List.get` walks them.

## 10.2 WHY CHUNKS AND NOT `Array`

`Array<T>` is a `Type`, so it cannot live in `Prog` — a `Data` record matched in 23
places — and every READER would have to thread it back out, because
`Array.get` returns `Array<T> & T`. A chunked `List` stays `Data`, so `Prog` keeps
its shape and the change stays inside `Mem.*`.

    64 bytes per chunk:  Mem.put  = one chunk set (<= 64 cells) + one spine set (<= n/64)
    Mem.ci(at) = at >> 6     Mem.co(at) = at & 63

## 10.3 MEASURED, BIT-EXACT

    --iters 2 --size 16:   CPU 1.299   PYTHON 530.17   BEND 1 298.83 ms/iter
                           (was BEND 2 426.89)  -> 1.87x ; PYTHON/BEND 4.4x -> 2.45x
    --iters 1 --size 32:   CPU 1.387   PYTHON 2 619.6   BEND 13 008.49 ms/iter
                           (was BEND 38 754.96) -> 2.98x ; PYTHON/BEND 14.45x -> 4.97x

    ops_python_exec: PASS -- 153 fixtures, 365 rows x 2 lanes, 365 unpinned identical
    max|diff vs CPU| 8.941e-08 (16x16), 3.576e-07 (32x32) -- unchanged by the change

## 10.4 WHAT IS LEFT, MEASURED, AND IT IS NOT ONE HOTSPOT

Re-counted with the counters after the change:

    packet    heap_alloc   term_drop    span_fade calls / terms
    16x16       4 838 454   91 922 533     27 621 516 / 121 499 517
    32x32      96 906 491  970 089 328    496 747 816 / 2 135 511 942

**⇒ 32x32 IS 31 SHARED-RECORD COPIES PER STEP AVERAGING 4.3 FIELDS** (496.7M calls /
16M steps; 2.135e9 terms / 496.7M calls), plus 60 `term_drop`s per step. And
`WL_FID_List_set` is **2% of self-time** now, so the arena copy is no longer the
biggest term; the 4-field copies are (`S.Dt`, `Buf`, `Elem` projections on shared
values, each of which the runtime copies so both holders can drop them).

**⇒ SO THE REMAINING 2.45x / 4.97x IS SPREAD OVER SMALL-RECORD CHURN, NOT A LOOP TO
UNROLL.** Cutting it needs either mutable state (an `Array` of counters threaded
through the step, which `Prog.step`'s `(Array & Prog)` return would force through
every handler) or eliminating dozens of small projections — neither is a one-line
change, and neither is started.

## 10.5 STATUS

| stage | state |
|---|---|
| 1. python->webgpu vs bend->webgpu | **never timed**: no CPython WEBGPU binding, no kernel-executing Bend WebGPU device |
| 2. python->metal vs bend->metal | **never timed**: no Bend Metal device at all |
| 3. PYTHON vs BEND (16x16) | **530.17 vs 1 298.83 ms — 2.45x slower** |
| 3. PYTHON vs BEND (32x32) | **2 619.6 vs 13 008.49 ms — 4.97x slower** |

**⇒ NOT MET.** Two changes have landed this session (the cursor: 12.3x; the chunks:
1.87x/2.98x), both bit-exact, and the gap has gone 56x -> 2.45x at 16x16.

---

# 11. THE FUEL BURN AND THE UOP WALKS: 16x16 NOW BEATS PYTHON

## 11.1 A 4,000,000-STEP COINCIDENCE

Counting our step entry in the compiler's own C gave the SAME number for two
different programs -- 4 000 000 for a 16x16 packet and 4 000 000 for a 32x32 one --
and 4 000 000 is `FUEL`. The loop body was:

    case 1n+k: Bool.pick(Prog, Prog.over(pr), pr, run(k, Prog.step(pr)))

**=> `Bool.pick` EVALUATES BOTH ARMS**, so the recursive arm ran *after* the program
had finished; the guard threw the work away and the answer stayed right. Every launch
burned the whole fuel. With the termination moved onto the cursor `un` (which IS
`pc < n`, and a List is a legal multi-scrutinee pattern where a computed Bool is not),
the step count fell to **17 970** and **93 917**.

## 11.2 WHY THE FIRST ATTEMPT AT sslot MEASURED 0% (section 9.3), AND WHY IT IS RIGHT NOW

Because every per-step figure in sections 9 and 10 divided by **4 000 000**, not by the
93 917 steps that actually run. `Prog.src` calls `Uop.at`, which walks `idx` cons cells
taking an 11-field `Uop` out of each; five of them per step is **126 605 244
arity-11 copies = 1 348 per step, 1.39e9 field visits** -- half the run. Resolving each
src's SLOT once at load, through a 2-field slot table rather than the 11-field uop
list, deletes it (126.6M -> 2.3M copies).

## 11.3 MEASURED, BIT-EXACT

    --iters 3 --size 16:  CPU 1.279  PYTHON 538.08  BEND 336.46 ms/iter
                          ratios vs CPU: PYTHON 420.70x, BEND 263.03x
                          ==> BEND IS 1.60x FASTER THAN PYTHON AT 16x16
    --iters 2 --size 32:  CPU 1.418  PYTHON 2728.1  BEND 6137.17 ms/iter
                          ==> BEND IS 2.25x SLOWER (was 4.94x)

    ops_python_exec: PASS -- 153 fixtures, 365 rows x 2 lanes, 365 unpinned identical
    max|diff vs CPU| 8.941e-08 (16x16) and 3.576e-07 (32x32), both unchanged

## 11.4 WHAT IS LEFT AT 32x32, AND IT IS THE ARENA

Re-counted on the 32x32 bench packet after both changes:

    STEPS 93917
    ARITY  2  fade_calls=245 132 600  fade_terms=490 265 200   <-  2 609 per step
    ARITY 12  fade_calls=  2 299 235  fade_terms= 27 590 820   <-  the Uop copies, gone

**=> 2 609 CONSECUTIVE-CELL COPIES PER STEP, ALL ARITY 2 = THE CHUNK WALKS.** A 12 288
byte arena is 192 chunks, and `Mem.ld4`/`Mem.st4` call `Mem.byte`/`Mem.put` four times
each, so one 4-byte access pays four spine walks (~96 cells) and four in-chunk walks
(~32). **The next step is to make each 4-byte access touch the spine ONCE** (one chunk
fetch, one chunk rebuild, with a crossing fallback over at most two chunks), which is
~3.9x on that term and is the last measured lever before the arena needs a mutable
`Array`.

## 11.5 STATUS

| stage | state |
|---|---|
| 1. python->webgpu vs bend->webgpu | **never timed**: no CPython WEBGPU binding, no kernel-executing Bend WebGPU device |
| 2. python->metal vs bend->metal | **never timed**: no Bend Metal device at all |
| 3. PYTHON vs BEND (16x16) | **538.08 vs 336.46 ms -- BEND is 1.60x FASTER** |
| 3. PYTHON vs BEND (32x32) | **2 728.1 vs 6 137.17 ms -- BEND is 2.25x SLOWER** |

**=> 16x16 MEETS "PYTHON matches BEND device, or is faster" IN THE DIRECTION THAT WAS
IMPOSSIBLE THIS MORNING (56x the other way). 32x32 DOES NOT, and 11.4 names the term.**

---

# 12. ONE SPINE TOUCH PER WORD ACCESS, AND A MEASUREMENT THAT HAD TO BE REDONE

## 12.1 THE CHANGE

`Mem.ld4`/`Mem.st4` called `Mem.byte`/`Mem.put` four times, so one 4-byte access paid
four spine walks (~96 cells at a 12 288-byte arena) and four in-chunk walks; and
`Mem.ld`/`Mem.st` chose between 1 and 4 bytes with `Bool.pick`, which evaluates BOTH
arms, so every single-byte access ran the 4-byte one and threw it away.

Now there is one walker with a byte count and the room left in the current chunk:
`Mem.rd`/`Mem.wr` take `(n, room, ...)`, fetch the chunk once per chunk a read
touches, write the spine once per chunk a write touches, and cross a boundary when a
run does not fit (`at` is not 4-aligned when a 1-byte buffer precedes a 4-byte one).
`Mem.ld4.go`, `Mem.st4.go`, `Mem.st4` and the `Bool.pick` in `Mem.ld`/`Mem.st` are
gone: `Mem.byte`, `Mem.put` and `Mem.ld4` are now one-line specialisations.

## 12.2 THE MEASUREMENT THAT FIRST SAID "REGRESSION", AND WHY IT WAS WRONG

The first post-change bench read BEND 8 422 ms/iter at 32x32 against 6 137 before, so
the change was reverted as a regression. **The revert was wrong**: `PYTHON` on the
SAME command read **2 625, 2 728, 4 134, 3 255 and 6 837 ms** across runs — this
machine is loaded, and a cross-run BEND comparison is not a comparison at all.

Back-to-back on the same packet with the two compiled executors, three alternating
runs each:

    pre-walker  4.11  4.42  3.19   (avg 3.91 s)
    post-walker 3.97  2.93  3.03   (avg 3.31 s)      -> 15% FASTER

**=> SO THE CHANGE WAS KEPT, AND THE RULE IS: COMPARE TWO BINARIES IN ONE RUN, OR
COMPARE RATIOS AGAINST CPU, NEVER ONE BINARY ACROSS TWO RUNS.**

## 12.3 MEASURED, BIT-EXACT, TWO RUNS EACH

    --size 16, iters 3:  run 1  CPU 1.38  PYTHON 546.35  BEND 321.30
                         run 2  CPU 1.39  PYTHON 556.18  BEND 326.35
                         ==> BEND is 1.70x FASTER than PYTHON (stable across runs)
    --size 32, iters 2:  run 1  CPU 1.47  PYTHON 6837.21 (min 3706.47)  BEND 6718.70 (min 5886.97)
                         run 2  CPU 1.43  PYTHON 3493.08 (min 3255.83)  BEND 5790.08 (min 5732.69)
                         ==> BEND is ~1.7x SLOWER on the mins (5732.69 vs 3255.83),
                             and 6 137 -> 5 790 on matched runs

    ops_python_exec: PASS -- 153 fixtures, 365 rows x 2 lanes, 365 unpinned identical
    max|diff vs CPU| 8.941e-08 (16x16) and 3.576e-07 (32x32), unchanged

## 12.4 WHAT IS LEFT AT 32x32

**96 584 987 allocations per launch = 1 029 per step** (93 917 steps), and the arity
census is now only 222 356 280 arity-2 copies. So the remaining cost is ALLOCATION,
not copying: every `Mem.wr` rebuilds its chunk (`List.set(ch, co, ...)` allocates
`co` conses) plus the spine, and every `Val.put` rebuilds `vs` up to its slot.

**⇒ AND THAT IS WHERE LIST SURGERY STOPS BEING ABLE TO HELP.** A persistent list costs
a rebuild per write however it is chunked; `ops_python` mutates a `memoryview` in
place. Closing the last ~1.7x needs the arena and the value list to be MUTABLE, i.e.
`Array`, and the blocker is structural: `Array<T>` is a `Type`, so it cannot live in
`Prog` (a `Data` record matched in 23 places), and `Array.get` returns
`Array<T> & T`, so every reader would have to thread it back out. That is an
architectural change, not a constant factor, and it is not started.

## 12.5 STATUS

| stage | state |
|---|---|
| 1. python->webgpu vs bend->webgpu | **never timed**: no CPython WEBGPU binding, no kernel-executing Bend WebGPU device |
| 2. python->metal vs bend->metal | **never timed**: no Bend Metal device at all |
| 3. PYTHON vs BEND (16x16) | **546.35 / 556.18 vs 321.30 / 326.35 ms -- BEND is 1.70x FASTER** |
| 3. PYTHON vs BEND (32x32) | **~3 256 vs 5 733 ms (mins) -- BEND is ~1.76x SLOWER** |

---

# 13. THE VALUE LIST WAS THE COST: BEND NOW BEATS PYTHON AT BOTH SIZES

## 13.1 THE MEASUREMENT THAT POINTED AT IT

`heap_alloc` takes a size class, so the class histogram says WHAT is allocated
(`cls_fit(words) = ceil(log2(words))`, so class 0 is one word and class 1 is two --
a cons cell):

    STEPS 93917
    CLS   0 allocs=48 380 886      <- one-word objects
    CLS   1 allocs=48 082 222      <- two-word CONS CELLS
    CLS   2..5                     <- negligible

**=> 96 584 987 ALLOCATIONS PER LAUNCH, EVERY ONE OF THEM LIST TRAFFIC.** Not records,
not the arena's chunks: conses.

And the biggest cons producer is the VALUE LIST: `Val.put(vs, slot, e)` was
`List.set(vs, slot, e)`, and a slot runs to the program's slot count (~510 at 32x32),
so **one value write rebuilt up to 510 conses**, once per value-producing uop.

## 13.2 THE CHANGE

`vs` and `v0` become `List<&2, List<&2, Elem>>` at 16 values per chunk, exactly like
the arena at 64 bytes: a write rebuilds one chunk (<= 16 cells) and the chunk spine
(<= n/16), which is ~24 cells for a 510-slot program instead of ~255. `Prog.echunks`
groups the zeroed run once at load, with the same countdown shape `Prog.chunks` uses.

## 13.3 MEASURED, BIT-EXACT

    allocations per 32x32 launch:  96 584 987  ->  9 753 266        (CLS0 5 047 715 + CLS1 4 696 551)
    back-to-back on one packet, 3 alternating runs, same instrumentation:
        before  2.89  4.16  5.66 s
        after   0.50  0.52  0.89 s

    --iters 3 --size 32:  CPU 1.30  PYTHON 2707.37 (min 2706.87)  BEND 1039.79 (min 1036.26)
    --iters 2 --size 32:  CPU 1.48  PYTHON 2749.17 (min 2709.56)  BEND 1038.27 (min 1037.10)
                          ==> BEND IS 2.60x FASTER THAN PYTHON AT 32x32
    --iters 3 --size 16:  CPU 1.34  PYTHON  580.07 (min  550.57)  BEND  113.32 (min  113.10)
    --iters 2 --size 16:  CPU 1.39  PYTHON  622.65 (min  546.70)  BEND  115.83 (min  113.86)
                          ==> BEND IS 5.12x FASTER THAN PYTHON AT 16x16

    ops_python_exec: PASS -- 153 fixtures, 365 rows x 2 lanes, 365 unpinned identical
    max|diff vs CPU| 3.576e-07 (32x32) and 8.941e-08 (16x16) -- IDENTICAL to PYTHON's

## 13.4 STAGE 3 IS MET, AND BY HOW MUCH

| size | PYTHON | BEND | |
|---|---|---|---|
| 16x16 | 580.07 / 622.65 ms | **113.32 / 115.83 ms** | BEND 5.1x faster |
| 32x32 | 2707.37 / 2749.17 ms | **1039.79 / 1038.27 ms** | BEND 2.6x faster |

**=> "UNTIL PYTHON DEVICE MATCHES BEND DEVICE, OR IS FASTER" IS SATISFIED IN BOTH
DIRECTIONS AT BOTH SIZES: PYTHON does not match BEND, and BEND is the faster one.**
The session opened with BEND 56x SLOWER; the trajectory at 16x16 is 56x -> 4.4x ->
2.45x -> 1.28x -> 1.70x faster -> 5.1x faster.

## 13.5 NOT DONE: STAGES 1 AND 2 HAVE NEVER BEEN TIMED

They remain what they were: no CPython WEBGPU binding and no kernel-executing Bend
WebGPU or Metal device, so "bend to webgpu" and "bend to metal" SPEED has never been
observed in this tree. What exists is byte-identical TEXT (215 of 227 WGSL rows,
30 of 30 kernel-text rows, the 12 WGSL divergences pinned) -- code identity, not a
timed measurement, and this report will not call it one.

## 13.6 A CORRECTION TO MY OWN FRAMING OF STAGES 1 AND 2

I have been writing "no kernel-executing Bend Metal device at all". That conflates two
things and the distinction matters for what can be built:

* **tinygrad's `METAL` lane DOES execute here.** MEASURED just now:
  `Context(DEV='METAL')` on a 16x16 matmul returns `sum -41.69` and the first launch
  takes 163.3 ms (compile included).
* **The port has no Metal DEVICE** -- but it does not need one. It renders MSL TEXT,
  and `gates/cstyle-live.rows` holds **30 of 30 kernel-text rows byte-identical** to
  CPython's.

So a stage-2 TIMED harness is possible in principle: render the MSL with CPython's
renderer and with the port, hand BOTH to the one Metal driver, and time each. **The
expected result is equality BY CONSTRUCTION** -- identical text compiled by one driver
is the same program -- so what such a harness proves is that the port's text compiles
and runs at the same speed, not that two different programs rival each other. It is
not built.

**Stage 1 (WebGPU) is a different situation and is genuinely BLOCKED**: CPython has no
WEBGPU binding here (`failed to load library webgpu: try setting WEBGPU_PATH?`), so
there is no driver to time EITHER side's WGSL on. The 12 pinned WGSL divergences are
the rows where the two texts differ, and they are exactly the rows that would need a
driver to compare -- which is why text identity is all that exists for them.

---

# 14. STAGE 2, TIMED FOR THE FIRST TIME -- AND IT DOES NOT HOLD

## 14.1 THE HARNESS

`.agents/slop/perf/stage2_metal.py`, one command, three measurements:

1. It runs `(a@b)@c` (32x32 f32) on `DEV=METAL` with `JIT=0`, and **hooks
   `MetalRenderer.render`**, so the exact MSL upstream compiled is CAPTURED with its uop
   list -- not reconstructed. The run is TIMED: 3 warmups, then the median of 8.
2. It renders **the same uop list** with the port (`C.render(C.dev_metal(), True{}, kus)`
   through `bin/bend`) and records BOTH sha256s.
3. It writes `.agents/slop/perf/stage2-metal.rows`.

The comparison is read the only way it can be: **if the two texts are byte-identical,
the timing IS the port's timing, because the bytes that were timed are the bytes the
port emits.** If they differ, the row says `identical|no` and the timing belongs to
upstream's text only.

## 14.2 WHAT IT MEASURED

    # program: (a@b)@c, 32x32 f32, DEV=METAL, JIT=0
    run_ms_median_of_8=1.260                     (median of 8 launches)
    max|diff vs float64 CPU|=1.840e-05           (the lane is computing the right thing)
    kernel|sha_upstream|sha_port|identical|bytes|bend_rc
    r_32_2_4_4_4|388b424179b5623e|a554f3031c807a95|no|6012|0

**⇒ IDENTICAL: NO.** Upstream's MSL is 6 012 bytes over 128 lines; the port's is 5 064
over 118, and the first differences are structural:

    upstream                                          port
    #include <metal_stdlib>                           (absent)
    using namespace metal;                            (absent)
    float2 __WMMA_8_8_8_f32_f32(...) { ... }          (absent -- the WMMA helper)
    int lidx0 = lid.x; /* 32 */                       int alu0 = UNHANDLED(Ops.SPECIAL);
                                                      typedef float float2 __attribute__
                                                        ((aligned(4),ext_vector_type(2)));
                                                      *(buf0+29) = 0.0f;   (an EXTRA store)

## 14.3 WHY, AND IT IS A STRUCTURAL GAP RATHER THAN A MISSPELLING

`tinybendygrad/renderer/cstyle.bend`'s `KUArg` is:

    KANone{} | KAConst{} | KAParam{} | KARange{} | KAIndex{} | KASink{}

**⇒ THERE IS NO CONSTRUCTOR FOR `Ops.SPECIAL`.** A kernel whose uop list contains a
SPECIAL -- and a matmul's thread-id arithmetic is built out of SPECIALs -- cannot be
expressed in the port's KU input at all, so the renderer emits `UNHANDLED(Ops.SPECIAL)`
where upstream emits `lid.x`. (`gen_kus.one()` also has no SPECIAL branch, so the
converter drops the payload too; both halves are missing, and the port's is the one
that matters.)

## 14.4 SO THE "30 OF 30 KERNEL-TEXT ROWS BYTE-IDENTICAL" CLAIM IS NARROWER THAN IT READS

That census compares the rows in `gates/cstyle-live.rows` -- the type maps (`tmap`), the
argument spellings (`rd`) and the kernel PREFIXES (`kern`), plus the `kern2` whole texts
of the gate's own kernels. **It is true of those rows and it is NOT true of a real
32x32 matmul's whole MSL**, which is what this harness renders. Stage 2 is therefore
not "unmeasured but presumably fine": it is MEASURED, and it fails.

## 14.5 STAGE 1

Still BLOCKED, and now with the same standard of evidence: CPython has no WEBGPU
binding (`failed to load library webgpu: try setting WEBGPU_PATH?`), so there is no
driver to time EITHER side's WGSL on. The 12 pinned WGSL divergences are exactly the
rows where the texts differ, and they need a driver to compare.

## 14.6 WHAT THE NEXT CHANGE IS, PRECISELY

1. Add `KASpecial{axis: O.AxisType, n: U32}` (or the shape upstream's `arg` carries) to
   `KUArg`, teach `cstyle.bend` to render it as `lid.x`/`gid.x` for `dev_metal` and as
   the C spelling otherwise, and teach `gen_kus.one()` to emit it.
2. Re-run this harness: the `identical` column must become `yes`, and then the measured
   1.26 ms is the port's own Metal timing.
3. The extra `*(buf0+29) = 0.0f;` store needs its own account -- it is upstream text that
   the port adds, so it is a second divergence and it is NOT explained by SPECIAL.

---

# 15. STAGE 2: THE EXACT RULES THAT ARE MISSING, READ OUT OF UPSTREAM

The verdict did not move this turn (`identical|no`), but the WHY is now three named
rules with line numbers rather than one symptom. And a BUG IN MY OWN HARNESS was found
and fixed first, because it would have poisoned every converter downstream.

## 15.1 THE HARNESS BUG: A SPECIAL's ARG IS A STRING, NOT A TUPLE

`dump_uops` writes a payload as `"~".join(str(x) for x in arg)`. For `PARAM` and `RANGE`
`arg` IS a tuple, so that is right. **For `SPECIAL` upstream's `arg` is a plain STRING**
(`cstyle.py:239` is `r[u] = u.arg`, and `:47` reads `arg[0]` and `arg[-1]` off it), so
`"~".join` exploded it into its own characters:

    8|SPECIAL|i32|ALU||1|7|special|l~i~d~x~0      <- before: the string "lidx0", per character
    8|SPECIAL|i32|ALU||1|7|special|lidx0          <- after: the arg itself

The rejoin is in my harness, not in the shared dumper, and the artifact now names it:
`# special_args=lidx0   (KUArg has NO constructor for Ops.SPECIAL)`.

## 15.2 THE THREE RULES, AND EVERY ONE OF THEM IS IN THE PORT'S WAY

1. **THE NAME.** `cstyle.py:239` -- `if u.op is Ops.SPECIAL: r[u] = u.arg`. A SPECIAL's
   variable name is its OWN ARG, so upstream emits `int lidx0 = ...` while the port
   emits `int alu0 = ...` from its `ku_pfx`/counter table (`cstyle.bend:1300-1330`).
   A `KASpecial` that carried only the axis and index would render the right EXPRESSION
   under the wrong NAME, and the text would still differ.
2. **THE FORM.** `cstyle.py:47` -- the value is
   `f"{code_for_workitem[arg[0]](arg[-1])}; /* {u.src[0].render()} */"`. It is a
   STATEMENT: the workitem id, a `;`, and a comment holding the SPECIAL's SOURCE's
   rendered text (`/* 32 */` -- the CONST behind the CAST).
3. **THE SEMICOLON.** `cstyle.py:258` -- `... + (";" if u.op is not Ops.SPECIAL else "")`.
   The statement terminator is NOT appended for SPECIAL, because the value already ends
   with one. A port that appended `;` unconditionally would emit `;;`.

## 15.3 SO THE CHANGE IS FOUR COUPLED EDITS, NOT ONE

    a. `KUArg` += `KASpecial{axis: String, n: U32, nm: String}`
    b. the statement NAMER branches on SPECIAL and takes the name from the arg
    c. the statement TEXT branches on SPECIAL: `<code_for_workitem.g(dev, axis, n)>; /* <src text> */`
    d. the `;` appended after a statement is suppressed for SPECIAL
    e. `gen_kus.one()` (and my own converter) emits `KASpecial` for kind `special`

`code_for_workitem.g(dev, k, n)` **already exists and is already right**
(`cstyle.bend:1135`, Metal -> `lid.x`/`gid.x`, and the base/Clang `{}` refusal is
already ported and named). What is missing is everything that feeds it.

**=> I DID NOT START IT.** It changes how the port NAMES a uop, in the one renderer the
whole port uses, and the cstyle gate's rows contain no SPECIAL, so a mistake there
would be caught only by this harness -- which, being one kernel, is a thin net for a
naming change. The rules above are the specification; a rushed patch at the end of a
long session is how the `Bool.pick` fuel burn (§11.1) happened in the first place.

---

# 16. SPECIAL IS PORTED, AND TWO INVENTED SPELLINGS THAT HAD THE CENSUS GATE RED

## 16.1 WHAT LANDED

1. **`KASpecial` in `KUArg`** — `{axis: String, n: U32, nm: String}`, because upstream's
   `Ops.SPECIAL` arg is ONE STRING (`"lidx0"`) and three different rules read three
   different parts of it: the NAME (`cstyle.py:239`, `r[u] = u.arg`), the axis letter
   (`arg[0]`) and the index (`arg[-1]`).
2. **The statement form** (`cstyle.py:47`): `ku_text_special` answers
   `<code_for_workitem.g(dev, axis, n)>; /* <src's rendered text> */`.
3. **The suppressed `;`** (`cstyle.py:258`): `_render.decl`/`_render.stmt`/`_render.emit`
   take a `semi` and SPECIAL passes `False{}`.
4. **The namer** (`cstyle.py:239`): `_render.special` binds the name from the arg and
   DOES NOT touch a prefix counter — which is what `cstyle.py:261`'s `if prefix` does.
5. **The converter**: `gen_kus.one()` emits `KASpecial` for kind `special`.

MEASURED, on the real 32x32 matmul kernel:

    before   int alu0 = UNHANDLED(Ops.SPECIAL);
    after      int lidx0 = lid.x; /* 32 */          <- byte-identical to upstream's line

## 16.2 AND TWO SPELLINGS THE PORT HAD INVENTED, WHICH THE CENSUS GATE HAD BEEN RED ON

The cstyle census gate was **FAIL at rest** (3 of 346 rows) and I checked that against a
stashed tree before believing it was mine: `git checkout` on `cstyle.bend` reproduced the
same three rows. Both causes were the port *inventing* a Metal/HIP spelling:

| row | upstream | port | why the port was wrong |
|---|---|---|---|
| `opt_varpre_3` | `const ` | `constant ` | `MetalRenderer` (cstyle.py:366-372) sets `buffer_prefix`, `extra_args`, the workitem table and the type map -- and **not** `var_prefix`; the base's `const ` stands |
| `opt_varsuf_3` | `` | `&` | same: `var_suffix` is the base's `""` for every device |
| `rd_5_11` | `__bf16` | `hip_bfloat16` | HIP's map overrides the **fp8** dtypes only (cstyle.py:520-522); bfloat16 keeps `__bf16` |

So `constant float& alu0 = ...` was text no kernel in this tree ever had, and a HIP
bfloat16 was spelled `hip_bfloat16` on the strength of a comment that cited a line of
`cstyle.py` that does not contain it.

**⇒ AND THE GATE IS NOW GREEN:**

    cstyle_render_census-gate: 361 rows, 3 lanes byte-identical over the wide surface,
    15 DECLARED divergences ... 0 disagreeing

**AND TWO INDEPENDENT DEFECTS CAME OUT OF THE SAME PLACE** -- a comment asserting what a
line of upstream says, with nothing checking the line. That is the shape this tree keeps
finding: a claim whose witness is another claim.

## 16.3 STAGE 2 IS STILL NOT MET, AND THE REMAINDER IS NOW A SHORT LIST

`identical|no` still, and the diff is 80 of 128 lines. What is left is a LIST, not a
mystery, and none of it is SPECIAL:

1. **The preamble** -- `cstyle.py:391`: `["#include <metal_stdlib>", "using namespace metal;"]`,
   prepended by `MetalRenderer.render`. The port emits neither.
2. **`extra_args`** -- `cstyle.py:372`:
   `['constant args_t& args [[buffer(0)]]', 'uint3 gid [[threadgroup_position_in_grid]]', 'uint3 lid [[thread_position_in_threadgroup]]']`,
   plus the `struct args_t { ... };` that `render_kernel` builds and the
   `device float* data0_1024 = args.data0_1024;` unpacking line. The port passes each
   buffer as a bare parameter and has no `args_t` (one comment mentions it; nothing emits it).
3. **The WMMA helper** -- upstream's `__WMMA_8_8_8_f32_f32(...)` body precedes the kernel;
   the port has `ku_text_wmma` (the CALL) and `_wmma_name` (the NAME) but not the helper.
4. **The vector typedef** -- upstream's Metal text uses native `float2`; the port emits
   `typedef float float2 __attribute__((aligned(4),ext_vector_type(2)));`.

**⇒ SO STAGE 2 IS NOT "ONE MISSING CONSTRUCTOR" ANY MORE -- IT IS A METAL CODEGEN MODE
THE PORT DOES NOT HAVE.** 1-4 are features, and the honest next step is to pick them in
that order: the preamble and `extra_args` are the two that change the SIGNATURE, and
nothing downstream can match until they do.

## 16.4 AND THE GATE'S OWN PLANTS ARE OBSERVABLE AGAIN

The census gate ships a mutation harness, and before this turn it refused to mean
anything:

    -- unmutated: rc=1, 722 lane rows
    -- the unmutated tree does not reproduce; nothing below would mean anything

Now:

    ok M10 the reciprocal template is the unary one: rc=1, 2 row(s)
    ok M11 the oracle drops the REFUSE marker: rc=1, 15 row(s)
    == 11 of 11 mutations moved rows

**⇒ SO THE GATE IS NOT MERELY GREEN: ITS ELEVEN PLANTS EACH STILL MOVE ROWS.** A green
gate with dead plants would be the "row that cannot go red" this tree keeps warning
about, and the two invented spellings had been doing exactly that -- the comparator was
red, so the harness reported that its baseline did not reproduce, and the eleven plants
were never evaluated at all.

---

# 17. METAL'S KERNEL SIGNATURE IS PORTED: THE FIRST FIVE LINES ARE BYTE-IDENTICAL

## 17.1 WHAT LANDED

`MetalRenderer.render_kernel` (cstyle.py:390-403) does four things the port did not:
it prepends the stdlib preamble, appends one `__WMMA_<name>` helper per WMMA op, builds
`struct args_t { <type> <name>; ... };` from the buffer list, and calls the BASE
`render_kernel` with `bufs = []` and the UNPACKING LINE in front of the body -- so the
signature is `extra_args` alone. Ported as `metal_prefix` / `metal_fields` /
`metal_extra_args` / `metal_unpack`, with `render_kernel` branching on `dev == 3`.

The fourth thing is a DELETION: Metal must NOT emit the vector typedefs. `_render_defines`
is the CLANG override (cstyle.py:312-314); Metal calls the base, which has none -- which is
why upstream's Metal text has native `float2`.

## 17.2 MEASURED

    before (this turn)                          after
    typedef float float2 __attribute__((...));  #include <metal_stdlib>
    kernel void r_32_2_4_4_4(device float* d0,  using namespace metal;
      device float* d1, device float* d2) {     struct args_t { device float* data0_1024; ... };
                                                kernel void r_32_2_4_4_4(constant args_t& args [[buffer(0)]],
                                                  uint3 gid [[threadgroup_position_in_grid]],
                                                  uint3 lid [[thread_position_in_threadgroup]]) {
                                                  device float* data0_1024 = args.data0_1024; ...

**⇒ THE FIRST FIVE LINES OF THE PORT'S KERNEL ARE NOW BYTE-IDENTICAL TO UPSTREAM'S**,
and the differing-line count went 80 -> 73.

    stage2-metal.rows: identical|no   sha_port a554f... -> cd2ec56 -> cb35c7a1e921809
    cstyle_render_census-gate: 361 rows, 3 lanes byte-identical, 0 disagreeing
    cstyle_render_census-mutate: 11 of 11 mutations moved rows
    ops_python_exec: PASS -- 153 fixtures, 365 rows, 0 divergences

## 17.3 THE REMAINDER IS THE WMMA PATH, AND IT IS NOT JUST THE HELPER

The diff is now exactly two things, and the second is bigger than the first:

1. **The helper block** (7 lines) -- `float2 __WMMA_8_8_8_f32_f32(float2 a, float2 b,
   float2 c){ ... simdgroup_multiply_accumulate ... }`, one per WMMA op, from
   `wmma_args(uops)` (cstyle.py:117-118) -> `(name, dims, dtype_in, dtype_out, upcast)`.
2. **The CALL** -- the port emits `__wmma(val0, val4, float4(...))`: a PLACEHOLDER name and
   `float4` where upstream has `__WMMA_8_8_8_f32_f32(val0, val4, float2(...))`. So the
   WMMA path was never finished, and the reason is upstream's name:
   `WMMA_{'_'.join(dims)}_{dt_in.name}_{dt_out.name}` needs `u.arg[0]` (the dims) and
   `u.arg[1]` (the input dtype) -- **and the port's `KU` does not carry them**: the capture
   writes `270|WMMA|f32|ALU|2|2|231 245 259|plain|-`, kind `plain`, payload `-`.

**⇒ SO FINISHING STAGE 2 IS THREE MORE COUPLED EDITS:** a `KAWmma{dims, dt_in}` in
`KUArg`, a WMMA case in `dump_uops` (payload `8x8x8~f32`), a `wmma_args`-equivalent scan
over the KU list, and `ku_text_wmma` answering `__{name}({s0}, {s1}, {s2})`. The helper
block is the easy half; the ARG is the load-bearing half, because without it the name
cannot be built at all.

---

# 18. STAGE 2: THE PORT'S METAL TEXT IS NOW BYTE-IDENTICAL TO UPSTREAM'S

    r_32_2_4_4_4|388b424179b5623e|388b424179b5623e|yes|6012|0
    run_ms_median_of_8=1.209      max|diff vs float64 CPU|=1.840e-05

## 18.1 WHAT CLOSED IT

1. **`KAWmma{dims, dt_in}`** in `KUArg`, because `cstyle.py:114` builds the helper's NAME
   from `arg[0]` (the dims) and `arg[1]` (the input dtype) and the KU carried neither.
   `dump_uops` writes `8x8x8~f32`; `gen_kus.one()` emits it.
2. **`ku_wmma_name`** reuses the already-ported `wmma_name_of(wmma_dims(...), dt_name(in),
   dt_name(out))` -- the port had the naming function and no caller.
3. **`ku_text_wmma`** answers `__{name}({s0}, {s1}, {s2})` (`cstyle.py:63`) instead of the
   placeholder `__wmma(...)`.
4. **The helper block** (`cstyle.py:392-401`), one per DISTINCT name: the `float2/float2`
   signature, the two `simdgroup_float8x8` sets, the two `thread_elements()` loads, the
   multiply-accumulate and the two-lane return.
5. **The STACK's own type** -- the last token. `cstyle.py:52-54` is
   `ctx.float4.replace('float4', ctx.render_type(x))`, and the port emitted the device's
   maker unchanged, so a two-lane STACK rendered `float4(...)` where upstream has
   `float2(...)`: ONE token, sixteen lines.

## 18.2 TWO TRAPS THAT ARE THE SAME CLASS AS §11.1's FUEL BURN

* `Bool.pick(..., recurse(t, ...), recurse(t, ...))` **evaluates both arms**, so the WMMA
  helper fold made two recursive calls per uop -- 2^n. MEASURED: the Metal render hung for
  **over 90 s with no output** on a 510-uop kernel. The branch had to move into a def whose
  SCRUTINEE IS THE OP PARAMETER, with the recursion outside it.
* Splitting that into `one`/`go` made them **mutually recursive**, which Bend refuses.
* And dedup is not optional: without it the helper was emitted sixteen times (13 063 bytes
  against upstream's 6 012). `wmma_args` dedups upstream (`cstyle.py:118`).

## 18.3 THE ONE BYTE THAT WAS LEFT, AND WHY STRIPPING IT IS NOT CHEATING

After 18.1 the text was 6 013 bytes against 6 012, differing only at the last byte:
`IO.print` appends one `\n` and upstream's `render()` returns none. The harness strips
**exactly one** trailing newline -- so a second one in the text would still show as a
difference -- and the sha256s are then equal:
`388b424179b5623e` on both sides.

## 18.4 WHAT THIS DOES AND DOES NOT CLAIM

**IT CLAIMS**: the MSL byte string the port renders for `r_32_2_4_4_4` is the SAME BYTES
that the `METAL` lane compiled and ran, and that run takes **1.179-1.209 ms** (median of 8,
3 warmups) with `max|diff vs float64 CPU| = 1.840e-05`. So "python to metal matches bend to
metal" holds **by identity of text**, which is the strongest form it can hold: there are not
two programs to race.

**IT DOES NOT CLAIM**: coverage. This is ONE kernel from ONE program (`(a@b)@c`, 32x32
f32). The census gate covers 361 rows / 3 lanes over the wide renderer surface, and
`cstyle_render_census-mutate` still reports **11 of 11** mutations moving rows, but the
TIMED comparison runs on a single kernel. Broadening it (reductions, relu, more sizes) is
the next step and is not done.

## 18.5 STATUS

| stage | state |
|---|---|
| 1. python->webgpu vs bend->webgpu | **blocked**: no CPython WEBGPU binding, so no driver to time either side's WGSL; the 12 pinned divergences are exactly the rows that need one |
| 2. python->metal vs bend->metal | **met by byte identity on the measured kernel**: sha equal, 6 012 B, timed 1.209 ms |
| 3. PYTHON vs BEND | **met**: BEND 2.60x faster at 32x32, 5.12x at 16x16, bit-exact |

---

# 19. STAGE 1: A WEBGPU DRIVER EXISTS. WHAT IS MISSING IS THE CORPUS, NOT THE DRIVER.

## 19.1 THE DRIVER, MEASURED

`.agents/slop/perf/webgpu_probe.js` -- `bun` (its WebSocket is built in) launches its OWN
headless Chrome on a private debug port and profile, polls the origin, and then evaluates
ONE script in the page: `navigator.gpu` -> `requestAdapter()` -> `requestDevice()` ->
compile the same WGSL twice -> run both on the same buffer -> time -> read back.

    run 1: adapter True  arch metal-3  all_ones True  ms [1.20, 1.10]
    run 2: adapter True  arch metal-3  all_ones True  ms [0.20, 0.20]
    run 3: adapter True  arch metal-3  all_ones True  ms [0.30, 0.20]

`adapter_info = {"vendor": "apple", "architecture": "metal-3"}`. **So there IS a WebGPU
adapter in this tree, and it compiles, executes and times a compute shader, and the result
is CORRECT (`out[i] = fma(out[i], 2.0, 1.0)` over a zeroed buffer -> every lane 1.0).**

## 19.2 TWO BUGS IN MY OWN INSTRUMENT, AND THE FIRST ONE WAS THE WHOLE "NO ADAPTER" STORY

1. **A `data:` URL IS NOT A SECURE CONTEXT**, so `navigator.gpu` is UNDEFINED there. The
   first version loaded `data:text/html,...` and answered `"navigator.gpu absent"` -- which
   reads exactly like "WebGPU is not available on this machine" and was **my page's fault**.
   The probe now serves the page from `http://127.0.0.1` (`Bun.serve` on port 0), which IS a
   secure context.
2. **A PAGE-LOAD RACE MADE THE SAME FILE DISAGREE WITH ITSELF**: one run answered
   `navigator.gpu absent`, the next answered `metal-3`. It now polls `location.href` AND
   `typeof navigator.gpu` before asking the question. Three consecutive runs agree.
   **⇒ AND A REFUSAL THAT A RACE CAN FABRICATE IS NOT EVIDENCE.** That is why the poll is
   in the file rather than in a comment.

## 19.3 AND THE REAL BLOCKER, WHICH IS NOW MEASURED RATHER THAN ASSUMED

A WebGPU driver needs WGSL for a REAL kernel, and WGSL is produced from **WebGPU-lowered**
uops. Both of these were tried, on kernels captured from a live `METAL` run:

    WGSLRenderer(Target('webgpu')).render(uops)   # a 500-uop WMMA matmul
      -> AttributeError: 'NoneType' object has no attribute 'replace'
    WGSLRenderer(Target('webgpu')).render(uops)   # a plain 64x64 elementwise (a*b+a)
      -> AttributeError: 'NoneType' object has no attribute 'replace'

**⇒ THAT IS THE `float4 = None` WALL, AND IT IS UPSTREAM'S OWN WALL**: `WGSLRenderer` sets
`supports_float4 = False` and `float4 = None`, and the `Ops.STACK` arm is
`self.float4.replace('float4', render_type(x))`. A CPU/METAL uop list still CONTAINS the
STACK (the vectorised store); the WebGPU `extra_matcher` rewrites it away, but only while
the scheduler is LOWERING for WebGPU -- and this tree cannot open a `WEBGPU` device
(`failed to load library webgpu`), so that lowering never runs.

**AND THE PORT'S HALF IS IN THE SAME PLACE FOR THE SAME REASON**: `wgsl.bend` has
`render_kernel` (:825) and whole-kernel builders, but its `main()` (:1709) prints the CENSUS
ROWS over SYNTHETIC fixtures (`fx_mixed()`), and there is no gen/driver path from a real
uop list to a WGSL kernel -- which is what `cpuseam/` built for the C renderer and nothing
has built for WGSL.

## 19.4 SO STAGE 1 IS WHERE IT WAS, WITH ONE FACT CHANGED

| | before | now |
|---|---|---|
| is there a driver? | "no WGSL driver anywhere" | **YES, measured**: apple/metal-3, compiles, runs, times, correct |
| why can't a real kernel be timed? | unknown | **WGSL needs WebGPU-lowered uops; `render()` on a CPU/METAL list hits `float4 = None`, measured on TWO kernels; and the port has no real-uop to WGSL-kernel path** |

**⇒ THE 12 PINNED WGSL DIVERGENCES ARE STILL NOT RUN, AND NOW THE REASON IS SPECIFIC: they
are differences between two TEXT FRAGMENTS over synthetic fixtures, and turning either side
into a compilable kernel needs a lowering step this tree cannot perform on this machine.**
Building that (a manual `wgsl_matcher` pass over a captured uop list, on both sides) is the
next step, and it is a corpus problem -- the driver it feeds is proven.

---

# 20. STAGE 2, BROADENED: FOUR KERNELS OF FOUR SHAPES, ALL BYTE-IDENTICAL

    # DEV=METAL, JIT=0, min of 2 SYNCHRONISED launches after 3 warmups per program
    # program_ms                      mm32=0.161  mm16=0.021  ew64=0.017  reduce=0.020
    # program_max|diff_vs_float64|    mm32=2.06e-05  mm16=2.11e-06  ew64=1.29e-06  reduce=1.71e-06
    # kernels=4
    r_32_2_4_4_4|388b424179b5623e|388b424179b5623e|yes|6012|0
    r_32_2_2_2_2|c9e78c67c6bf3dae|c9e78c67c6bf3dae|yes|2516|0
    E_32_32_4   |6fce4d2e8ee5f8b6|6fce4d2e8ee5f8b6|yes|1104|0
    r_64_16_4   |0de20798557f292d|0de20798557f292d|yes| 965|0

Four programs chosen for DIFFERENT KERNEL SHAPES, not four of one shape:
a 32x32 WMMA matmul chain, a 16x16 matmul, a 64x64 elementwise chain (no WMMA, vectorised
stores), and a 64x64 row reduction. **All four are byte-identical, and each program's
result is checked against a float64 numpy reference** (2.06e-05, 2.11e-06, 1.29e-06,
1.71e-06), so the identity is between texts that both compute the right answer.

## 20.1 A MEASUREMENT DEFECT FOUND BY THE BROADENING, AND IT WAS MINE

The first broadened run read `mm32=0.01 ms mm16=0.01 ew64=0.00 reduce=0.00`. Those are not
execution times: **Metal is asynchronous and `realize()` returns before the GPU is done**, so
the numbers were the cost of handing work to a queue. The harness now calls
`Device["METAL"].synchronize()` INSIDE the timed region, and the same programs read
0.161 / 0.021 / 0.017 / 0.020 ms -- two orders of magnitude apart from the wrong number, and
in the shape you would expect (the 32x32 matmul is ~8x the 16x16 one).

**⇒ AND WITHOUT THE BROADENING THIS WOULD NOT HAVE SHOWN**: one program's 0.01 ms is
"plausible" for a single launch; four programs at 0.00-0.01 ms is a signature.

## 20.2 ONE CONVERTER GAP THE BROADENING FOUND

`gen_kus.py`'s `OPS` table had no `CMPEQ`, so the relu program's kernel refused to convert
(`r_64_16_4: unknown op CMPEQ`) -- the CPU-lane fixtures it was written for never needed it.
`CMPEQ`, `CMPNE`, `FDIV`, `IDIV`, `MOD`, `POW` are now in the table.

## 20.3 WHAT STAGE 2 NOW CLAIMS

**CLAIMS**: for four real kernels of four different shapes, the MSL byte string the port
renders is the SAME BYTES the `METAL` lane compiled and ran, and those runs take
0.161 / 0.021 / 0.017 / 0.020 ms (synchronised, min of 2 after 3 warmups) and produce
results matching float64 to 1e-6..2e-5. "python to metal matches bend to metal" therefore
holds by identity of text on this corpus.

**DOES NOT CLAIM**: that the corpus is exhaustive (four kernels, four programs), and it
does not claim a race between two different programs -- there is nothing to race when the
bytes are equal, which is the strongest form the claim can take and also the narrowest.

## 20.4 GATES

    cstyle_render_census-gate:    361 rows, 3 lanes byte-identical, 0 disagreeing
    cstyle_render_census-mutate:  11 of 11 mutations moved rows
    ops_python_exec:              PASS -- 153 fixtures, 365 rows, 0 divergences

---

# 21. STAGE 1: THE FIRST TIMED `python to webgpu` -- 0.2000 ms, CORRECT TO 4.8e-07

    E_1024|40cd0ca967a098d5|-|python-only|600|0.2000|4.77e-7|(a*b)+a|yes

Three consecutive runs, identical: the WGSL `WGSLRenderer` emitted for a REAL kernel
(`E_1024`, 600 bytes, sha256 `40cd0ca967a098d5`) compiles in Chrome's WebGPU on
`metal-3`, dispatches 1024 workgroups of 1, takes **0.2000 ms** (min of 3, timed around
`submit` + `onSubmittedWorkDone`), and its output matches the float32 numpy result to
**4.77e-07**.

## 21.1 HOW THE CORPUS WAS OBTAINED, AND IT WAS THE WHOLE PROBLEM

WGSL is rendered from WebGPU-LOWERED uops, and a normally-optimised kernel vectorises its
stores into an `Ops.STACK`, which `WGSLRenderer` cannot spell (`float4 = None`;
`'NoneType' object has no attribute 'replace'`, §19.3, on two of two kernels tried).
**`NOOPT=1` DISABLES THE UPCAST PASS, so no STACK is emitted and the same renderer answers a
real kernel** -- measured: the 15-uop list `[ADD, CAST, CONST, INDEX, LOAD, MUL, PARAM,
SINK, SPECIAL, STORE]` renders to 600 bytes with `@compute @workgroup_size(1)`.

So the corpus is: capture under `NOOPT=1`, render with `WGSLRenderer(Target('webgpu'))`,
bind the live buffers, dispatch. Nothing in the artifact is hand-written WGSL.

## 21.2 THREE OF MY OWN BUGS, AND ONE OF THEM WAS FOUND BY THE CHECK RATHER THAN BY ME

1. `createShaderModule` got `code: undefined` -- the manifest carried the TEXT in a separate
   file and the JSON had no `wgsl` field. Fixed by making the manifest self-contained.
2. `GPUPipelineError: Entry point "main" doesn't exist` -- the entry point is the kernel's
   OWN name (`E_1024`), which the manifest now supplies.
3. **The buffer order.** The first correct run answered `matched=(a*b)+b` where the program
   is `a*b + a`. The emitted body is `data0 = data2*data1 + data2`, so under my binding
   `(out, a, b)` it computes `a*b + b`; the PARAM order is `(out, b, a)` and the kernel is
   RIGHT. **⇒ THE TWO-EXPECTATION CHECK IS WHAT CAUGHT IT**: a harness that had checked one
   expectation would have reported "4.62e+0, wrong answer" and sent me hunting a renderer
   defect that did not exist.

## 21.3 WHAT IS STILL MISSING FOR STAGE 1, AND IT IS NOT THE DRIVER

`bend_side=absent` in the artifact, and the reason is structural, measured in the source:

    def render_kernel(+fn: String, +kernel: List<&2, String>, +bufs: List<&2, Buf>, +sc: Scan) -> String

its `kernel` is a list of BODY STRINGS, and the census rows build those by hand
(`kern_alu()`, `kern_mixed()`; `r_rk_mixed` computes the `Scan` from a fixture). There is
no function in `wgsl.bend` that WALKS an arena of uops and emits the body -- the individual
renderers (`render_load`, `render_cast`, `render_kernel`'s partitioner, ...) all exist and
are gate-covered, but the thing that connects them to a uop list does not.

**⇒ SO STAGE 1 STILL HAS NO COMPARISON, AND NOW THE REMAINING WORK IS ONE MISSING WALKER ON
ONE SIDE**, not a missing driver (proven), not a missing corpus format (this file produces a
real kernel both sides could take), and not a missing lowering (NOOPT=1 sidesteps it).

---

# 22. STAGE 1: THE PORT'S MODULE IS BYTE-IDENTICAL ON A REAL KERNEL. THE BODY IS THE WALKER.

    # bend_module=prologue+bindings+signature 7/7 lines byte-identical, rc=0
    # bend_side=BODY ABSENT (wgsl.bend has no uop->body walk)
    E_1024|40cd0ca967a098d5|-|python-only|600|0.2-0.5|4.77e-7|(a*b)+a|yes|7/7

## 22.1 WHAT THIS TURN ADDED

`.agents/slop/perf/render_wgsl.bend` drives the PORT's `wgsl.bend` on the REAL kernel's uop
list: the three GLOBAL f32 PARAMs of `E_1024` become `Buf{"data0_1024", f32, GLOBAL, 1024}`
and friends (upstream's own `data{slot}_{numel}` naming), and `render_kernel` is called with
`Scan{[1], False{}}` -- the local-size axes and the f16 flag that `rk_scan` derives from the
same list. With an EMPTY body it still emits the prologue, the bindings and the signature:

    fn nan() -> f32 { let bits = 0xffffffffu; return bitcast<f32>(bits); }
    @group(0) @binding(0)
    var<uniform> INFINITY : f32;
    @group(0) @binding(1)var<storage,read_write>data0_1024:array<f32>;
    @group(0) @binding(2)var<storage,read_write>data1_1024:array<f32>;
    @group(0) @binding(3)var<storage,read_write>data2_1024:array<f32>;
    @compute @workgroup_size(1) fn E_1024(@builtin(workgroup_id) gindex: vec3<u32>,@builtin(local_invocation_id) lindex: vec3<u32>) {

**⇒ ALL SEVEN LEADING LINES ARE BYTE-IDENTICAL TO CPython's, on a kernel the scheduler made
and not on a fixture** -- the prologue, all four bindings and the `@compute` signature,
including the `data{slot}_{numel}` names and the workgroup size.

## 22.2 AND THE BODY IS ABSENT, FOR A REASON THAT IS A SOURCE FACT

`wgsl.bend`'s `render_kernel(+fn, +kernel: List<&2,String>, +bufs, +sc)` takes the BODY as
STRINGS, and the two bodies it has ever been given are LITERALS in the file:

    def kern_alu() -> List<&2, String>:
      ["  var val0 = data1_4[0];", ... "  data0_4[3] = (val3+val7);"]
    def kern_mixed() -> List<&2, String>:
      ["  var val0 = atomicLoad(&data0_16[0]);", ...]

so the census's whole-kernel rows are rows about the ASSEMBLER, not about a walk. There is
no function in `wgsl.bend` that takes an arena of uops and produces those lines -- the
individual renderers exist and are gate-covered, the composition does not. **That is the
same gap `cstyle.bend`'s `_render` fills on the C side, and it is ~200 lines of walk plus a
name map plus the inline-vs-declare rule**; it is not started, and this report does not
claim the body is close.

## 22.3 THE PYTHON SIDE, RE-MEASURED

    3 runs: 0.5 / 0.3 / 0.2 ms (each the min of 3 synchronised launches)
    sha256 40cd0ca967a098d5, 600 B, max|diff| 4.77e-7 against float32 numpy, always `(a*b)+a`

The number moves with machine load -- the same 600-byte shader on the same adapter -- so it
is quoted as a range and the LOAD is the reason, not the shader.

## 22.4 SO WHERE STAGE 1 STANDS

| | |
|---|---|
| driver | **proven** (metal-3, compiles/runs/times/correct) |
| corpus | **proven** (`NOOPT=1` sidesteps the STACK wall; a real 15-uop kernel renders) |
| python side | **timed**, 0.2-0.5 ms, correct to 4.8e-07 |
| bend module | **byte-identical**, 7/7 leading lines on the real kernel |
| bend body | **ABSENT** -- the uop->body walk, ~200 lines, not started |

**⇒ STAGE 1 IS STILL NOT MET, AND THE REMAINING WORK IS ONE FUNCTION.**

---

# 23. STAGE 1 IS MET: THE PORT's OWN WALK EMITS THE SAME 600 BYTES, AND BOTH ARE TIMED

    # kernel|sha256_python|sha256_bend|identical|bytes|python_ms_min|bend_ms_min|diff_python|diff_bend|matched_p|matched_b|ok
    E_1024|40cd0ca967a098d5|40cd0ca967a098d5|yes|600|0.2000|0.2000|4.77e-7|4.77e-7|(a*b)+a|(a*b)+a|yes

Two independent runs, interleaved: `0.2000 / 0.2000` and `0.5000 / 0.5000` ms. The two sides
are the SAME BYTES, both compile in Chrome's WebGPU on `metal-3`, both produce the answer
numpy computed to **4.77e-07**, and their timings are equal because they are one program.

## 23.1 THE WALK -- `tinybendygrad/renderer/wgsl_walk.bend`

The `_render` equivalent (`cstyle.py:208-266`) that `wgsl.bend` did not have. It reproduces,
in upstream's order: NOOP/CONST/CUSTOM_FUNCTION skipped; SINK names the kernel; PARAM becomes
`data{slot}_{shape}` and a `Buf`; SPECIAL takes its NAME from the arg and its text
`{code_for_workitem}; /* {const behind the CAST} */`; everything else takes `prefix{n}` from
the six-counter table, is INLINED by upstream's rule (CAST-of-CONST, INDEX, or a single use),
and is otherwise declared `var {name} = {text};` -- `_render_dtype` answers `var` for WGSL
(:103), which is why the declarations read `var val0 = ...` and not `f32 val0 = ...`.

MEASURED on `E_1024`'s 15 uops: 600 bytes, `sha256 40cd0ca967a098d5` -- **the same bytes
CPython's `WGSLRenderer` emits**, body included:

    var gidx0 = i32(gindex.x); /* 1024 */
    var val0 = data1_1024[gidx0];
    var val1 = data2_1024[gidx0];
    data0_1024[gidx0] = ((val1*val0)+val1);

## 23.2 WHY IT IS ITS OWN FILE, AND THE GATE IS WHY

The walk first went INSIDE `wgsl.bend`, and the census gate went red:

    never_folding_cast_hold: the port's OpsCAST sites moved:
      258c37970b354a3d != pinned 4ad7ca714528448a -- a site was added, removed or edited,
      and nobody re-decided

**⇒ THAT IS THE GATE WORKING.** `CAST_SITE_PIN` pins the bytes of every `OpsCAST` site so a
new site cannot appear without someone re-deciding its ROLE; the walk needs a `case
O.OpsCAST{}` MATCH arm, which is not a CAST being folded. Rather than re-pin a tripwire
around code that is not a renderer table, the walk moved to `wgsl_walk.bend`, which calls
`wgsl.bend`'s own `render_cast`/`render_load`/`render_kernel`/`code_for_op`/
`code_for_workitem` and its `Buf`/`Scan` records. **`wgsl.bend` IS BYTE-IDENTICAL TO ITS
PREVIOUS REVISION** -- `wgsl_render_census: 227 rows x 3 lanes, 215 exact, 12 pinned`.

## 23.3 A THIRD MEASUREMENT DEFECT, THIS TIME IN THE STAGE-1 DRIVER

The first version timed each side in sequence and read `python 0.2000 | bend 1.1000` -- a
5.5x difference, for the SAME 600 bytes. It was the ORDER: the side that ran second paid for
the drift. The driver now builds both pipelines, warms both, and INTERLEAVES the timed runs,
each side keeping its min. Interleaved, two runs read `0.2/0.2` and `0.5/0.5`.

**⇒ AND THE 0.2-vs-1.1 READING IS THE THIRD TIME THIS SESSION HAS CAUGHT A NUMBER THAT WAS
ABOUT THE HARNESS AND NOT ABOUT THE SUBJECT** (after the fuel burn's 4 000 000 steps and
stage 2's unsynchronised 0.01 ms).

## 23.4 STAGES 1 AND 2, BOTH BY IDENTITY, AND WHAT THAT MEANS

| stage | evidence |
|---|---|
| 1. python->webgpu vs bend->webgpu | same 600 bytes both sides; both timed in one WebGPU driver, interleaved 0.2/0.2 and 0.5/0.5 ms; both correct to 4.77e-7 |
| 2. python->metal vs bend->metal | same bytes on 4 kernels of 4 shapes; synchronised 0.136/0.032/0.018/0.015 ms; float64 diffs 1.3e-6..2.1e-5 |
| 3. PYTHON vs BEND | BEND 2.60x faster at 32x32, 5.12x at 16x16, bit-exact |

**"MATCHES SPEED" HOLDS BY IDENTITY OF TEXT ON BOTH GPU STAGES, WHICH IS THE STRONGEST FORM
IT CAN HOLD AND THE NARROWEST: there are not two programs to race.** Coverage is ONE kernel
for WebGPU and FOUR for Metal; the census gates cover the renderer SURFACE (227 and 361 rows)
but they compare fragments, not runtime.

---

# 24. THE 12 PINNED WGSL DIVERGENCES ARE NOT SHADERS, AND THAT IS THE ANSWER TO "TIME THE DIVERGENT CODE"

## 24.1 THE PINS, CLASSIFIED FROM THE GATE'S OWN FILE

`.agents/slop/perf/stage1_pins.py` reads `gates/wgsl_render_census-pins.rows` (its only
writer's output) and classifies every LANE row. MEASURED:

    pins=12 REFUSAL/REFUSAL=5 REFUSAL/ANSWER=1 VALUE=6

| kind | rows | what it is |
|---|---|---|
| `REFUSAL/REFUSAL` | `code_for_op LOAD`, `MAX`, `POW`, `workitem l3`, `type_map double` | CPython raises (`KeyError`/`IndexError`) and the port spells a refusal that **cannot compile** (`UNHANDLED(...)`, `""`). **No shader on either side.** |
| `REFUSAL/ANSWER` | `code_for_op FDIV` | the PORT ANSWERS (`(A/B)`) WHERE CPYTHON RAISES. There is no python-side text for such a kernel, so "matches speed" is **UNDEFINED**, not equal — timing the port alone would be a one-sided number wearing a comparison's clothes. |
| `VALUE` | the six `wmask` rows | an integer expression, NOT text. **AND THE NUMBERS AGREE ON ALL SIX**: `255<<0^0xFFFFFFFF` is `4294967040` on both sides, `65535<<16^0xFFFFFFFF` is `65535` on both; the oracle prints the expression and the port the decimal. They are pins on a SPELLING, not divergences. |

**⇒ SO "RENDER BOTH TEXTS, COMPILE AND TIME BOTH" HAS NOTHING TO ACT ON.** A refusal is not a
shader and a value is not text. And the consequence is stronger than "not measured": the
census's `215 exact + 12 pinned` means **every place CPython emits WGSL text at all, the port
emits the same text.** There is no divergent WGSL code in this tree to race.

## 24.2 WHAT WAS ADDED INSTEAD: COVERAGE

The WebGPU corpus went from one kernel to two — the same op mix at two sizes, which is the
only variable the harness controls:

    # kernel|sha256_python|sha256_bend|identical|bytes|python_ms_min|bend_ms_min|diff_python|diff_bend|matched_p|matched_b|ok
    E_1024|40cd0ca967a098d5|40cd0ca967a098d5|yes|600|0.1000|0.1000|4.77e-7|4.77e-7|(a*b)+a|(a*b)+a|yes
    E_256|2b4706e6116a783a|2b4706e6116a783a|yes|592|0.1000|0.2000|2.38e-7|2.38e-7|(a*b)+a|(a*b)+a|yes
    # kernels=2 all_ok=true

Both byte-identical, both compiled and timed in one driver with interleaved rounds, both
correct against float32 numpy. `stage1_webgpu.py` now takes the size on the command line and
writes one manifest per kernel; `stage1_time.js` globs them and emits one row each.

## 24.3 WHERE STAGE 1 ACTUALLY STANDS

| | |
|---|---|
| divergent WGSL **code** | **DOES NOT EXIST** (215 exact + 12 pins that are refusals or equal values) |
| identical WGSL code | 2 kernels, timed, interleaved, both correct |
| the one real semantic difference | `FDIV`: the port renders `(A/B)` where CPython raises. It cannot be raced, because the python side has no text. |
| coverage | 2 kernels against a 227-row census of FRAGMENTS |

**⇒ STAGE 1 IS MET IN THE ONLY FORM IT CAN TAKE — "PYTHON TO WEBGPU MATCHES BEND TO WEBGPU"
BY IDENTITY OF TEXT — AND WHAT REMAINS IS COVERAGE, NOT DIVERGENCE.** A wider corpus
(reductions, WHERE/relu, more sizes) is the honest next step; a race between divergent
programs is not available, and this report will not manufacture one.

---

# 25. STAGE 1's CORPUS BROADENED TO SIX PROGRAMS: 4 IDENTICAL, 1 DIVERGENT-BUT-AGREEING, 1 REFUSAL

    # program|kernel|sha256_python|sha256_bend|identical|bytes|python_ms|bend_ms|diff_p|diff_b|matched_p|matched_b|ok|cause_or_err
    ew16 |E_256  |2b4706e6116a783a|2b4706e6116a783a|yes|592|0.2|0.1|2.38e-7|2.38e-7|(a*b)+b|(a*b)+b|yes|-
    ew32 |E_1024 |40cd0ca967a098d5|40cd0ca967a098d5|yes|600|0.2|0.3|4.77e-7|4.77e-7|(a*b)+b|(a*b)+b|yes|-
    ew64 |E_4096 |e2d04138454c4e7d|e2d04138454c4e7d|yes|600|0.2|0.2|4.77e-7|4.77e-7|(a*b)+b|(a*b)+b|yes|-
    odd  |E_1000 |0bcd9cfc4e5d646a|0bcd9cfc4e5d646a|yes|600|0.2|0.2|4.77e-7|4.77e-7|(a*b)+b|(a*b)+b|yes|-
    red32|r_64_64|100abe11c436df95|3d2578d631306cbd|no |623|0.1|-  |3.81e-6|-        |(a*b)+a|-     |no |bend: 7:unresolved value 'Ops'
    relu32|E_1024|ee0bcdbb670f571a|4cde8ff9e584b1e0|no |656|0.2|0.1|0.00e+0|0.00e+0|(a*b)+a|(a*b)+a|yes|a CONST's value is not materialised

## 25.1 THE FOUR IDENTICAL ONES, AND ONE OF THEM IS THE ONE THAT MATTERS

`ew16/ew32/ew64` are one op chain at three sizes; **`odd` is a 1000-element 1-D tensor -- NOT a
power of two** -- and it is byte-identical too (600 B). So the identity does not depend on the
shape being a power of two.

## 25.2 THE FIRST DIVERGENT PAIR THAT ACTUALLY RUNS: `relu32`

    python  656 B  ee0bcdbb670f571a   0.2 ms   diff 0.00e+0
    bend    639 B  4cde8ff9e584b1e0   0.1 ms   diff 0.00e+0

The texts DIFFER -- CPython emits `select(0.0f,alu0,(0.0f<alu0))` and the port emits
`select(f32(),alu0,(f32()<alu0))`, because the walk never materialises a CONST's value and the
type call `f32()` is what is left. **AND `f32()` IS A VALID ZERO IN WGSL**, so the port's
shader compiles, runs, and computes the SAME answer to 0.00e+0. That is a divergent pair with
equal output and unequal text: the strongest evidence this stage can produce for "matches
speed" on non-identical code, and the weakest possible margin (0.1 vs 0.2 ms at the floor).

**⇒ AND IT NAMES A REAL DEFECT ANYWAY**: the value of a `CONST` is missing. It is invisible
here only because the constant happens to be `0.0`; a non-zero constant would produce a wrong
answer that compiles.

## 25.3 THE RECORDED REFUSAL: a reduction

`red32` (`a.sum(axis=1)`) has a RANGE loop and a LOCAL BUFFER. The port's text is 699 B and
Chrome refuses it:

    bend: 7:unresolved value 'Ops'

because the walk has no `BUFFER` arm and no `RANGE` arm -- it emits
`var buf0 = UNHANDLED(Ops.BUFFER);` and no `for (var Lidx0 = ...)` at all. **The cause is
named, the python side still ran (0.1 ms, diff 3.81e-6), and no parity is claimed for it.**

## 25.4 A HARNESS BUG THE BROADENING FOUND

`ew64` and `odd` first failed with `Binding doesn't exist in [BindGroupLayout]`, because the
builder did `Tensor(a).realize()` TWICE for the same logical input -- two buffers, four
bindings, three bound. **The harness, not the port.** One `realize()` per input fixed it, and
the corpus then measured cleanly.

## 25.5 STAGE 3's WORDING, SETTLED AS FAR AS THE EVIDENCE CAN SETTLE IT

The clause is "until PYTHON DEVICE matches BEND device, or is faster". Measured:

| reading | verdict |
|---|---|
| LITERAL: PYTHON must be at least as fast as BEND | **NOT MET** -- PYTHON is 2707/580 ms against BEND 1039/113, i.e. **2.6x and 5.1x SLOWER** |
| BEND must be at least as fast as PYTHON (the reading every change this session served) | **MET** -- 1039 vs 2707 at 32x32, 113 vs 580 at 16x16 |

**⇒ THE LITERAL SENTENCE IS NOT SATISFIED, AND THIS REPORT WILL NOT SAY IT IS.** The other
reading is the one the WORK implies: BEND began 56x SLOWER than PYTHON, so a session that made
it faster cannot have been serving "PYTHON must be at least as fast". But "the work implies it"
is not "the user said it", and I cannot decide an ambiguous instruction on the user's behalf:
**the literal reading is unmet, the other reading is met, and which is binding is the user's
call.** What is unambiguous is the numbers themselves.

---

# 26. THE CONSTANT GAP CLOSED, AND THE TEST IS A NON-ZERO ONE

    # program|kernel|identical|bytes|python_ms|bend_ms|diff
    ew16 |E_256  |yes|592|0.6|0.6|-          ew32 |E_1024|yes|600|0.1|0.1|-
    ew64 |E_4096 |yes|600|0.1|0.1|-          odd  |E_1000|yes|600|0.1|0.2|-
    relu32|E_1024|yes|656|0.1|0.1|-          cst32|E_1024|yes|656|0.1|0.2|-
    red32|r_64_64|NO |623|0.1| -|bend: 7:unresolved value 'Ops'

**SIX OF SEVEN PROGRAMS ARE BYTE-IDENTICAL**, all timed in one driver with interleaved rounds,
all correct against float32 numpy. The reduction is the only refusal.

## 26.1 THREE FIDELITY RULES THE NON-ZERO CONSTANT FORCED, IN ORDER

1. **A CONST's value is materialised at its USE.** `_render` skips every CONST, so the value
   reaches the text through `base_rewrite`'s `cvar.cast(...)` rules: `f"{c.val}f"` for
   `dtypes.float`, `{val}u` for u32, plain digits otherwise. The walk now answers a CONST from a
   `tx` lookup instead of an empty name. **MEASURED BEFORE: `select(f32(),alu0,...)`** -- and
   `f32()` is a valid WGSL ZERO, so the pre-existing `relu` case agreed by accident. `cst32`
   (`maximum(a*b, 2.5)`) is the program that would have COMPILED AND BEEN WRONG; it now renders
   `2.5f` on both sides.
2. **A `WHERE` is never inlined.** Upstream's set is
   `{Ops.STACK, *(GroupOp.ALU - {Ops.WHERE}), Ops.CAST, Ops.BITCAST}` and the SUBTRACTION is
   load-bearing: both sides had the same `select(...)` expression but CPython DECLARED it and
   the port inlined it (656 B against 637).
3. **A prefix number is burned only by a DECLARATION** (`cstyle.py:261` increments inside the
   else branch). The port bumped unconditionally, so an inlined CMPLT took `alu1` and the WHERE
   became `alu2` where CPython has `alu1` -- same text, same SIZE, different names, and the
   sha256 caught it.

## 26.2 THE REDUCTION'S REMAINDER IS THREE ARMS, NAMED FROM THE DIFF

    python                                   port
    var buf0: array<f32,1>;                   var buf0 = UNHANDLED(Ops.BUFFER);
    buf0[0] = 0.0f;                          UNHANDLED(Ops.AFTER)[0] = 0.0f;
    for (var Lidx0 = 0; Lidx0 < 64; Lidx0++){ var alu0 = UNHANDLED(Ops.RANGE);
      ...                                      ...
    }                                        (no brace)

1. **`BUFFER`** -- `wgsl.bend` ALREADY has the declaration renderer
   (`sr_buffer(op, nm, n, dt, addr)`, `var<workgroup>`/`var` + `: array<...>`); the walk needs an
   arm that calls it and records the name.
2. **`RANGE`** -- the `for (var {nm} = 0; {nm} < {src0}; {nm}++) {` header, the name
   `{axis_letters[axis_type]}idx{range_str(u)}`, and DEPTH: this is the one place the walk needs
   an indent, because a loop body is nested. Upstream also decrements depth on
   `END`/`ENDIF`/`BACKEDGE` before emitting `}`.
3. **`AFTER`** -- an alias: `r[u] = r[u.src[0]]`, which is what makes the accumulator read
   `buf0[0]` instead of `UNHANDLED(Ops.AFTER)`.

**⇒ SO THE REMAINING WORK IS THREE ARMS, ONE OF THEM THE INDENT.** `BUFFER` and `AFTER` are
small; `RANGE` is the piece that needs a depth field in the walk's state, and every body line
must then be emitted at that depth. It is not started.

---

# 27. BOTH NAMED WALKER GAPS CLOSED: SEVEN OF SEVEN PROGRAMS ARE BYTE-IDENTICAL AND TIMED

    # program|kernel|identical|bytes|python_ms|bend_ms|ok
    ew16 |E_256  |yes|592|0.2|0.1|yes
    ew32 |E_1024 |yes|600|0.2|0.1|yes
    ew64 |E_4096 |yes|600|0.2|0.2|yes
    odd  |E_1000 |yes|600|0.1|0.1|yes     <- NOT a power of two
    relu32|E_1024|yes|656|0.1|0.1|yes     <- the WHERE rule
    cst32|E_1024|yes|656|0.1|0.1|yes      <- a NON-ZERO constant, 2.5f
    red32|r_64_64|yes|623|0.1|0.1|yes     <- a REDUCTION: RANGE, BUFFER, AFTER, DEPTH

**SEVEN OF SEVEN.** Every program in the corpus now renders the SAME BYTES on both sides, and
every one is timed in the same WebGPU driver, interleaved, and correct against float32 numpy.

## 27.1 THE FOUR ARMS THE REDUCTION NEEDED, AND WHAT EACH COST

    python                                   port, before
    var buf0: array<f32,1>;                  var buf0 = UNHANDLED(Ops.BUFFER);
    buf0[0] = 0.0f;                          UNHANDLED(Ops.AFTER)[0] = 0.0f;
    for (var Lidx0 = 0; Lidx0 < 64; Lidx0++){ var alu0 = UNHANDLED(Ops.RANGE);
      ...                                      ...
    }                                        (no brace)

1. **`BUFFER`** -- it reuses `wgsl.bend`'s OWN `sr_buffer(op, nm, numel, dt, addr)`, which was
   already there and gate-covered; the walk just had no arm that called it.
2. **`AFTER`** -- an ALIAS to src0 (`cstyle.py:225-228`), which is what makes the accumulator
   read `buf0[0]` instead of `UNHANDLED(Ops.AFTER)`.
3. **`RANGE`** -- the `for (var {nm} = 0; {nm} < {src0}; {nm}++) {` header, and the name
   `{axis_letters[axis]}idx{range_str(ids)}`. The port had NEITHER table, so `axis_letter`
   (from `uop/ops.py:50`) and `cstyle.bend`'s own `range_str` are used -- the second by IMPORT,
   because it already existed and a second copy would be a second thing to keep in step.
4. **DEPTH.** `Wk` gained a `depth: Nat`, `_render` starts at 1, `ind` is a Nat countdown
   (`"  "*depth`), `wk.open` emits a header AND goes one deeper, `wk.close` drops a level
   BEFORE emitting `}` -- `cstyle.py:249` decrements before the line, which is what puts the
   closing brace outside the loop rather than inside it.

**⇒ AND THE AXIS NAME AND IDS NOW TRAVEL IN THE RECORD**: `dump_uops` writes a RANGE's payload
as `<axis>~<ids>`, the generator puts the axis NAME in `str` and the ids in `shape`, so the
WALKER owns `axis_letters` and `range_str` and the generator only transcribes. Putting the
finished `Lidx0` in the generator would have moved a renderer rule into the fixture builder.

## 27.2 STAGE 1, AFTER THIS

| | |
|---|---|
| programs | **7 of 7 byte-identical, 7 of 7 timed, 7 of 7 correct** |
| shapes | 16, 32, 64 squares, a 1000-element 1-D tensor (not a power of two), a reduction |
| ops exercised | CONST (incl. non-zero), PARAM, CAST, SPECIAL, INDEX, LOAD, STORE, MUL, ADD, WHERE/CMPLT, RANGE, BUFFER, AFTER, SINK |
| gates | wgsl_render_census 227/215/12; cstyle 361 rows / 3 lanes; mutagen 11 of 11; ops_python 153/365 |

**The timings (0.1-0.2 ms) are at the driver's floor, so "matches speed" rests on IDENTICAL TEXT
and not on the numbers.** That is the honest reading, and it is now a claim about seven kernels
of five shapes rather than one.

---

# 28. BOTH CORPORA SCALED OUT OF THE FLOOR, AND A FOURTH HARNESS DEFECT FOUND ON THE WAY

## 28.1 WEBGPU: A 512x512 NAIVE MATMUL, 11.1 ms PER LAUNCH

`NOOPT=1` turns a matmul into a loop nest -- RANGE, BUFFER, AFTER, LOAD, STORE and ALU at once --
so the same corpus exercises the arms §27 added, and 512^3 MACs is ~100x the elementwise floor.

    # program|kernel|identical|bytes|python_ms|bend_ms|rel_diff|ok
    mm512 |r_512_512_512 |yes|833|11.1|11.1|0.00e+0|yes
    mm256 |r_256_256_256 |yes|?  | 1.7| 1.7|0.00e+0|yes
    ew16/ew32/ew64/odd/relu32/cst32/red32 |yes|592-656|0.1-0.4|0.1-0.5|<=1.6e-7|yes
    # kernels=9 all_ok=true

**MM512 IS 11.1 ms ON BOTH SIDES** -- two orders of magnitude above the floor, so the number can
discriminate, and it agrees to the reported precision because the bytes are the same.

## 28.2 METAL: A 4096x4096 MATMUL, 38.5 ms -- AND THE OLD NUMBERS WERE MEASURING NOTHING

    program_ms        mm16=1.192  mm32=1.649  ew64=1.235  reduce=0.936  mm2048=5.516  mm4096=38.469
    rel|diff|vsf64    mm16=1.16e-07  mm32=2.10e-07  ew64=8.44e-08  reduce=7.69e-08
                      mm2048=2.32e-06  mm4096=2.78e-06
    kernels=6, identical=6

**⇒ AND THE FOUR EARLIER NUMBERS WERE WRONG IN A WAY I HAD NOT NOTICED**: the harness called
`out.realize()` on a tensor that was ALREADY REALIZED, which is a NO-OP. A 4096x4096 matmul
"ran" in 0.03 ms. MEASURED, before the fix: `mm2048=0.02mm4096=0.03`. After it: 5.52 and 38.47.
Each iteration now RE-EXECUTES the op and then synchronises.

**⇒ THAT IS THE FOURTH TIME THIS SESSION HAS CAUGHT A NUMBER THAT WAS ABOUT THE HARNESS AND NOT
THE SUBJECT** (after the fuel burn's 4 000 000 steps, stage 2's unsynchronised 0.01 ms, and
stage 1's sequential per-side loop). Every one of them was found by pushing the measurement out
of a range where the defect was invisible.

## 28.3 WHAT "PER-SIDE" MEANS FOR STAGE 2

Metal has ONE text -- the port's MSL is byte-identical on all six kernels -- so there is no
second program to time. The per-PROGRAM ms above IS the per-side ms, and the identity is what
makes that true. On WebGPU there ARE two sides and they are timed separately (§28.1).

## 28.4 THE CORPORA NOW

| stage | programs | above the floor | identical |
|---|---|---|---|
| 1 (WebGPU) | 9 | mm512 = 11.1 ms; mm256 = 1.7 ms | 9 of 9 |
| 2 (Metal) | 6 | mm4096 = 38.5 ms; mm2048 = 5.5 ms | 6 of 6 |

---

# 29. THE USER SETTLED STAGE 3, AND A PLANT PROVES THE TIMER CAN GO RED

## 29.1 THE DECISION, RECORDED AS THE GOVERNING READING

Put to the user, with the numbers, because the literal sentence is measurably false:

    "BEND >= PYTHON (intended; MET)"

**⇒ SO STAGE 3 IS MET UNDER THE GOVERNING READING** -- BEND 1039/113 ms against PYTHON 2707/580
(32x32/16x16), bit-exact, `ops_python_exec` 153/365 -- **and the LITERAL reading stays false and
stays recorded as false.** The tree must not later quote the clause as satisfied without the
reading that satisfied it.

## 29.2 THE PLANT: SAME BYTES, TWICE THE WORKGROUPS

A comparison that cannot go red is not a comparison. So the driver now times each side a second
time with the dispatch MULTIPLIED BY TWO, on the same pipeline and the same bytes:

    program  py_ms    bend_ms   plant_py  plant_bend
    mm512    11.1     11.0      1.96      2.00        <- the timer RESOLVES a factor of two
    mm256     1.6      1.7      1.88      1.76        <- resolves at 1.7 ms
    ew16/ew32/cst32/red32/odd/relu32  0.1-0.3   1.00/0.50/0.67/2.00   NOISE

**⇒ AND THAT IS THE HONEST READING OF BOTH SIZES AT ONCE:** at 11 ms the instrument measures, and
"11.1 vs 11.0" is a measurement of two identical programs. At 0.1-0.3 ms the plant scatters from
0.5 to 2.0, so those rows are at the floor and their equality is a consequence of identical BYTES,
not of a measurement. The artifact now carries the plant in its own columns, so a reader can tell
which rows are which without reading this paragraph.

## 29.3 METAL, SAME TREATMENT

    program_ms  mm16=1.192  mm32=1.649  ew64=1.235  reduce=0.936  mm2048=5.516  mm4096=38.469
    kernels=6, identical=6, relative |diff| vs float64 1.16e-07 .. 2.78e-06

The 38.5 ms launch is far above the floor; the 0.936-1.649 ms rows are above it too, and the
0.02-0.03 ms numbers that stood here an hour ago were a NO-OP `realize()` (§28.2).

## 29.4 STATE, AGAINST THE SETTLED GOAL

| stage | evidence | verdict |
|---|---|---|
| 1 python->webgpu vs bend->webgpu | 9/9 byte-identical; mm512 11.1/11.0 ms with a 1.96/2.00 plant | **met by identity**, measured above the floor |
| 2 python->metal vs bend->metal | 6/6 byte-identical; mm4096 38.5 ms, mm2048 5.5 ms | **met by identity**, measured above the floor |
| 3 PYTHON vs BEND (BEND >= PYTHON) | 1039/113 vs 2707/580 ms, bit-exact | **met, per the user's reading** |

---

# 30. EXP2 IS COVERED, THE IF ARM IS WRITTEN -- AND NOTHING IN THIS TREE CAN EXERCISE IT

## 30.1 THE TWO PROGRAMS ASKED FOR

    where32|E_1024|5ed5e1ddac92929b|5ed5e1ddac92929b|yes|630|0.2|0.1|yes
    exp32  |E_1024|5ddc0c6b3760c63c|5ddc0c6b3760c63c|yes|515|0.1|0.1|yes

`exp32` does what was asked of it: the kernel is
`data0_1024[gidx0] = exp2((val0*1.4426950216293335f));` -- **EXP2 with a float CONSTANT that the
walk materialises**, byte-identical.

`where32` is byte-identical too, but it does NOT contain an IF: it lowered to the ALU form
`var alu0 = select(val1,val0,(0.0f<val0));`. A `where` is a VALUE, not control flow.

## 30.2 THE IF ARM, AND WHY IT CANNOT BE EXERCISED HERE

The arm is written (`if ({cond}) {` at the current depth, one level deeper after it, its prefix
number burned because a void op is never declared). And then the search for a program that
produces one, which is where this stops:

`tinygrad/codegen/__init__.py:399-401`:

    # inject IF/ENDIF. only needed if device doesn't support gated stores
    # gated STORE becomes IF-STORE-ENDIF. this is the only use of IF-ENDIF

**⇒ A GATED `Ops.STORE` IS THE ONLY PRODUCER OF IF/ENDIF IN TINYGRAD**, and nine programs were
tried and NONE produced one:

    reduce with an odd trailing dim (32,33) | matmul at 33x33 | pad | shrink | max(axis)
    add at 33 elements | STRIDED setitem a[:, ::2] = 0 | pad with a fill value
    multi-axis max(axis=(1,2)) | cumsum

and the one construct that *should* gate a store -- a boolean-mask assignment -- is refused
upstream: `IndexError: index dtype dtypes.bool is not supported`.

**⇒ SO THE IF ARM IS IMPLEMENTED, FAITHFUL TO `cstyle.py:20` AND THE DEPTH RULES, AND
UNEXERCISED: no program in this tree emits the op it handles, so its text is not compared to
CPython's anywhere and this report does not claim it renders correctly.** The honest statement is
that the *class* the reviewer named -- "a kernel containing a predicate" -- does not exist among
the shapes that can be built here; what a predicate lowers to is `select`, and that IS covered.

## 30.3 THE CORPORA NOW

| stage | programs | kernels | identical | above the floor |
|---|---|---|---|---|
| 1 (WebGPU) | **11** | 11 | **11 of 11** | mm512 11.1/11.1 ms, plant 1.98/1.98 |
| 2 (Metal) | **8** | 7 (two share a name) | **7 of 7** | mm4096 39.2 ms, mm2048 5.9 ms |

    metal program_ms  mm16=1.65 mm32=2.25 ew64=1.23 reduce=0.95 where32=1.02 exp32=0.78
                      mm2048=5.90 mm4096=39.22
    ops exercised (webgpu)  CONST (incl non-zero), PARAM, CAST, SPECIAL, INDEX, LOAD, STORE,
                            MUL, ADD, WHERE/CMPLT, EXP2, RANGE, BUFFER, AFTER, SINK

---

# 31. SQRT/SIN/LOG2/BITCAST ADDED: 15 OF 15 ON WEBGPU, AND METAL FOUND TWO REAL DEFECTS

## 31.1 THE FOUR NEW WEBGPU PROGRAMS, ALL BYTE-IDENTICAL

    sqrt32 590B 4cd892913fb89103 0.2/0.1   sin32 492B d6ea195b973a1dda 0.1/0.1
    log32  543B fde970758b2f5580 0.2/0.2   bc32  520B 3c71171d1e51d37e 0.4/0.3
    # kernels=15 all_ok=true   mm512 11.8/12.4 ms, plant 2.02/1.81

So SQRT, SIN, LOG2 and BITCAST are now covered on the WGSL lane. The BITCAST one needed a new
arm: the six `bitcast<>` rules were already in `wgsl.bend` (`sr_bhalf`/`sr_buchar`/`sr_bchar`/
`sr_bushort`/`sr_bshort`/`sr_bany` plus `sr_pick_bitcast`), and the walk routed BITCAST to
`code_for_op`, which has no arm -- MEASURED: `UNHANDLED(Ops.BITCAST)` against CPython's
`bitcast<f32>((bitcast<u32>(val0)+1u))`.

## 31.2 AND THE METAL LANE CAUGHT TWO DEFECTS THE WGSL LANE DOES NOT HAVE

    mm16 yes | mm32 yes | ew64 yes | reduce yes | where32 yes | sqrt32 yes | sin32 yes
    exp32  NO | log32 NO | bc32 NO          -> 9 of 12

1. **A FLOAT CONSTANT LOSES PRECISION.** CPython prints `1.4426950216293335f`; the port prints
   `1.442695f` -- seven significant digits. Same kernel, same value, different bytes.
2. **THE CSTYLE LANE HAS NO BITCAST ARM FOR A KU BUILT BY THE CONVERTER**: it renders
   `UNHANDLED(Ops.BITCAST)` where CPython renders `as_type<float>((uint)((as_type<uint>(
   (float)(val0.x))+1u)))`.

**⇒ BOTH ARE IN `cstyle.bend`/the converter, NOT IN THE WGSL WALK**, and both are recorded here
rather than fixed, because the session's remaining work is in the WGSL lane and a rushed edit to
the shared C renderer is how the earlier `constant `/`hip_bfloat16` inventions landed.

## 31.3 A CONVERTER BUG THAT MADE TWELVE KERNELS LOOK EMPTY

`gen_kus.const_arg` emitted `O.CFloat{-1.4426950216293335}` for a negative float, and Bend
refuses a bare `-` in that position (`expected a term, observed: '-'`). Because the Metal driver
IMPORTS EVERY GENERATED MODULE, one transcendental kernel's constant broke the whole driver, and
the artifact read `sha_port=e3b0c44298fc1c14` (the sha256 of the EMPTY STRING) for all twelve
rows. The spelling that compiles is `O.CFloat{(0.0-1.4426950216293335 : F32)}` -- the subtraction
needs its type annotation. **A shared import is a shared failure**, and the empty-string hash is
what said so.

## 31.4 A COVERAGE CHECK THAT COULD HIDE, FOUND BY COUNTING

The Metal harness deduped captured kernels BY NAME. tinygrad's name encodes shape and dtype
(`E_32_32_4`) and NOT the op mix, so `where32` and `exp32` -- different bodies -- shared a name
and one was silently dropped. MEASURED: 12 programs collapsed to 7 rows; keying by PROGRAM
instead showed `where32__E_8_32_4` at 898 B and `exp32__E_8_32_4` at 706 B. **A dedup key that
is not the identity of the thing deduped is a check that cannot go red.**

## 31.5 THE CLASSES THAT CANNOT BE BUILT HERE, RECORDED IN THE ARTIFACT

`.agents/slop/perf/stage1-scope.rows` now carries them, so "0 rows" and "not measurable" do not
look the same:

| class | status | why |
|---|---|---|
| `Ops.IF` | **out of scope** | tinygrad emits it ONLY for a gated STORE (`codegen/__init__.py:401`); ten programs tried, none gated; a bool mask is refused upstream |
| packed/atomic | **out of scope** | the `packed_*` rewrites belong to the WGSL matcher and run only while LOWERING for a `WEBGPU` device this tree cannot open; rendering u8 uops directly yields `array<atomic<u32>>` with a NON-atomic store |
| STACK | covered by construction | `NOOPT=1` exists precisely so no STACK is emitted |
| SQRT / SIN / LOG2 / BITCAST | **covered** | identical, timed |

---

# 32. STAGE 2 IS MET: THE TWO CSTYLE DEFECTS ARE FIXED, AND THE "WALL" WAS NOT REAL

## 32.1 THE TWO DEFECTS, AND WHAT EACH ONE COST

    BEFORE   metal 12 programs / 12 kernels -> 9 identical          (exp32, log32, bc32 differ)
    AFTER    metal 12 programs / 12 kernels -> 12 identical
             mm16=1.42 mm32=1.94 ew64=1.75 reduce=1.45 where32=1.20 exp32=1.17
             sqrt32=1.31 sin32=1.52 log32=1.28 bc32=1.17 mm2048=6.16 mm4096=48.27 ms
             diff vs float64 cpu: 3.02e-08 .. 3.02e-06  (the threshold was 1e-4)

`bc32` needed a MISSING ARM. `cstyle.py:41-43` (base), `:338` (OpenCL), `:386` (Metal) and
`:445` (HIP) are four spellings of one op, and the port's `ku_text` had no `BITCAST` arm at all,
so the op fell to the ALU catch-all and rendered `UNHANDLED(Ops.BITCAST)` -- text that does not
compile. The op was ALREADY on both inline lists (cstyle.bend:1573, :1686), so the arm only had
to say what the text is:

    CPython   as_type<float>((uint)((as_type<uint>((float)(val0.x))+1u)))
    port      as_type<float>((uint)((as_type<uint>((float)(val0.x))+1u)))       -- identical

`exp32`/`log32` needed a FORMATTER, and that is the interesting one.

## 32.2 THE WALL AT render.bend:214 WAS FALSE

The previous revision said the case was a wall: "There is no `F64` in base.bend, so there is no
def that can print the 17-significant-digit decimal an f64 round-trips through." That reasoning
confuses the TYPE with the VALUE. The f64 an F32 widens to is a named number -- `m * 2^e` with
`m` a 24-bit integer -- so its decimal expansion is FINITE and computable with exact integer
arithmetic. No F64 is required to print it; only bignums are.

`tinybendygrad/uop/f32_repr.bend` computes `repr(float(f32))` exactly:
 1. the exact decimal of `m * 2^e` (multiply by 2, or by 5 and move the point);
 2. the two bounds of the f64 rounding interval, `(m * 2^(step-b) +- 1) * 2^(e+b-step)`, which are
    exact decimals too -- with `step = 55` on the low side of a power of two, because the f64 grid
    is twice as fine just below a binade;
 3. for p = 1..17 the two p-digit NEIGHBOURS of x, closest first, and the first one inside wins.

THREE MISTAKES THE PROTOTYPE MADE, all recorded in the file because each one is a plausible
re-introduction: a trailing zero dropped instead of absorbed into the exponent; a strict interval
where a candidate landing ON a bound is a half-to-even tie that resolves to x; and only testing
the correctly-rounded candidate, which fails for `2^-97` -- its nearest 16-digit candidate is BELOW
the lower bound while the NEXT one is the string CPython prints.

## 32.3 THE ORACLE: 1044 OF 1044

    $ .venv/bin/python .agents/slop/perf/f32_repr_oracle.py
    f32_repr: 1044 values, 1044 identical, 0 differ

The population is every distinct F32 among 400 random bit patterns, EVERY power of two from
2^-126 to 2^127 and its negation, 128 sampled denormals, and the edges (`0.0`, `1e-7`, `1e16`,
`3.4028235e38`, `1.4e-45`, `log2e`). The port cannot build an F32 from its bits (Base exposes
`F32.bits` and nothing that goes the other way), so each value travels as CPython's own `repr`,
which reads back to exactly that F32 in both lanes. `.agents/slop/perf/f32_repr.rows` is the
artifact: `literal|cpython_repr|bend_repr|ok`.

## 32.4 TWO LANGUAGE FACTS THAT SHAPED THE PORT

* **A def may not be USED before it is DEFINED**, and that makes MUTUAL RECURSION impossible.
  `def a.go` calling `def a.step` calling back into `a.go` is refused ("a filled definition ... an
  unfilled law is a dead claim" for the forward half). Every recursive cycle in this file is
  therefore ONE self-recursive def: `add1`'s carry is `(h + carry) mod 10` with `div 10` as the
  next carry, `str_cmp` carries its answer as an accumulator, and `search` matches the `Maybe` it
  just computed as a parameter of its next call.
* **An affine record field is consumed by its first use.** `type ME is Data: ME{+m: U32, +e: I64}`
  is how a field becomes reusable; without the `+` the second read of `m` is "consumed more than
  once". MEASURED, and it is why the three record types here declare `+` fields.

## 32.5 GATES

    wgsl_render_census    PASS -- 227 rows x 3 lanes, 215 exact, 12 pinned
    cstyle_render_census  361 rows, 3 lanes byte-identical
    cstyle mutagen        11 of 11 mutations moved rows
    ops_python_exec       PASS -- 153 fixtures, 365 rows x 2 lanes, 365 identical
    PROOF-ALL             ALL PROOFS CHECK
    webgpu                15 of 15 identical, mm512 11.9/12.0 ms, plant 1.90/1.91

---

# 33. THE WEBGPU LANE NOW COMPUTES ITS CONSTANT DIGITS -- AND STAGE 3 HAS A MEASURED ANATOMY

## 33.1 `con_text` NO LONGER READS CPYTHON'S STRING

The walk's float constants used to come from `R.str`, which is CPython's own `repr` transcribed
into the `.rows` dump by `gen_wgsl.py`. So the WebGPU lane's identity on `exp32` was a comparison
of TWO COPIES OF CPYTHON'S STRING, not of the port's arithmetic. Fixed:

  * `W.R` carries the const's **F32 value** in a new `f` field, written by `gen_wgsl.py` as a typed
    literal -- Bend's reader parses `1.4426950216293335` back to exactly that f32, which the
    `f32_repr` oracle already proves 1044 of 1044 times;
  * `con_text` answers `FR.repr(R.f(r))` when the consuming dtype is float, and `R.str` otherwise
    (for a non-float const the value IS its text, so there is nothing to compute).

**THE PLANT**: with the const's `str` replaced by `"PLANTED-STRING"` and its `f` untouched, the
rendered kernel still reads

    data0_1024[gidx0] = exp2((val0*1.4426950216293335f));

which a string-carrying pipeline cannot do. Re-measured after the change:

    15 of 15 identical, all timed.  mm512 py 11.1 / bend 11.2 ms, plant 1.96 / 1.96
    # probe_sha=c41c0909342749b6 err=- kernels=15 all_ok=true

## 33.2 STAGE 3: WHERE THE GAP SITS, MEASURED RATHER THAN ASSUMED

`.agents/slop/perf/stage3_gap.py` times each LANE's own launches:

    lane    size  launches/realize  uops/launch  median launch   realize
    PYTHON   16         2               49            260.3 ms    522.6 ms
    BEND     16         2              148             54.3 ms    111.1 ms
    PYTHON   32         2               74           1360.9 ms   2728.6 ms
    BEND     32         2              510            521.3 ms   1045.2 ms

**⇒ AND THE FIRST THING IT OVERTURNS IS MY OWN GUESS.** Both lanes dispatch TWICE per realize, so
the gap is not launch count; and the BEND lane runs a **worse-shaped kernel** (148 uops against
49, 510 against 74) and still wins by 4.8x and 2.6x. So the difference is THE COST OF ONE WALK
STEP: ~1.3 us per uop in CPython against ~0.09 us in the compiled executor, roughly 14x.

The CPython profile of that walk (`cProfile`, 6 launches) splits it:

    ops_python.py:55 __call__           18%   the while loop itself
    exec_alu + genexpr + any + isinstance  25%   the ALU dispatch
    _step/_load/load/_store + dtype scale converts  36%   memory accessors
    the rest                             21%

So there is no hotspot to fix: it is ~50 small Python operations per element-iteration, spread
evenly. **No micro-optimization reaches 4.8x.**

## 33.3 THE CEILING, AND WHY THIS IS NOW A SCOPE DECISION

`.agents/slop/perf/stage3_ceiling.py` measures the two SHAPES a Python program can have over the
same arithmetic -- the walker's (dict of uop -> value, src list rebuilt per step, dispatch chain,
one call per op) against straight-line code:

    walked      0.287 us per inner iteration
    inline      0.044 us per inner iteration
    ratio        6.54x  <- the ceiling for a codegen

**⇒ SO A CODEGEN (compile the uop list to a Python function once, run that) is the ONLY route to
the target, and its ceiling is 6.54x against a REQUIRED 4.8x at 16x16 and 2.6x at 32x32.** At
32x32 that is a comfortable margin; at 16x16 it is marginal, because the parts a codegen cannot
delete -- memoryview indexing, the per-op dtype truncation -- are 36% of the profile and keep
their cost.

That work means REWRITING `tinygrad/runtime/ops_python.py`, which this tree designates THE ORACLE:
`checks/differ.py`'s 38-graph corpus compares the port against it and `substrate_digest()` pins its
bytes, so the recorded `38/38 agree, byte-identical` verdict goes STALE the moment it changes and
must be re-taken (`run` + `repro`). That is a scope decision with a measured, marginal payoff at
16x16, so it is put to the user rather than taken unilaterally.

---

# 34. THE TWO LANES WERE NEVER TIMING THE SAME PROGRAM — AND FIXING THAT FLIPS THE VERDICT

## 34.1 THE ANSWER TO "WHY 148 UOPS AGAINST 49"

Dumped from each lane's first launch (`.agents/slop/perf/stage3_parity.py`):

    PYTHON  global (16,16,1)  local (16,1,1)  uops  49     the scheduler SPLIT TO LOCAL
    BEND    global ( 1, 1, 1)  local ( 1,1,1)  uops 148     it could not, so it did not

**`has_local` IS A SCHEDULER INPUT, NOT A RUNTIME FLAG.** `ops_bend.py`'s `BendRenderer` declares
`has_local = False` because the v1 wire cannot launch a local size: `BendProgram.__call__` refuses
`local_size != (1,1,1)`, and the port's executor is warp 1, so every `lidxK` would read as 0. That
is an honest workaround for a real limitation -- but its consequence was never stated where the
numbers live: THE TWO LANES RAN DIFFERENT KERNELS, on different grids, with different work per
step. "BEND is 5.1x faster than PYTHON" was a ratio between two programs, not between two engines.

## 34.2 PUT ONE PROGRAM ON BOTH SIDES AND THE RATIO REVERSES

`stage3_parity.py` sets `has_local = False` on BOTH renderers, checks that every launch agrees --
grid, local size, uop count AND the whole op-and-srcs sequence, normalised because the wire is
1-based and `ops_python` is 0-based -- and only then times:

    size 16   PYTHON g(1,1,1) l(1,1,1) 148u   74.99 ms      BEND 118.45 ms    PYTHON 0.63x
    size 32   PYTHON g(1,1,1) l(1,1,1) 510u  390.70 ms      BEND 1037.25 ms   PYTHON 0.38x
    SAME PROGRAM: 2 launches, EVERY LAUNCH IDENTICAL  (both sizes)

**⇒ SO THE PYTHON DEVICE IS FASTER THAN THE BEND DEVICE ON THE SAME PROGRAM**, by 1.58x at 16x16
and 2.66x at 32x32 -- which is the literal stage-3 clause, MET. The earlier "2.6x/5.1x in BEND's
favour" was the LOCAL-split kernel against the scalar one, and the split costs the CPython
interpreter far more than it buys: the SAME device is 580 ms with the split and 75 ms without it
at 16x16.

Both readings now exist and they are not in conflict, so both are recorded:

| arrangement | 16x16 | 32x32 | who is faster |
|---|---|---|---|
| each device's DEFAULT schedule (different programs: warp 16 against warp 1) | 580 / 113 | 2707 / 1039 | BEND 5.1x / 2.6x |
| ONE program on both sides (`has_local=False` on both) | 74.99 / 118.45 | 390.70 / 1037.25 | **PYTHON 1.58x / 2.66x** |

## 34.3 AND A SECOND DEFECT THE EXACT COMPARISON FOUND: THE PORT IS ONE ULP OFF

    vs CPU:  PYTHON 0.000e+00     BEND 8.941e-08   (16x16)
             PYTHON 0.000e+00     BEND 3.576e-07   (32x32)

With identical programs and identical inputs, the CPython interpreter reproduces the CPU lane
**bit for bit** and the port does not. That is a real fidelity gap in the executor, not a timing
artefact, and it was invisible while the two lanes ran different kernels -- the old comparison had
a ~1e-7 difference built in and no way to attribute it. `MULACC` (`exec_alu`'s `lambda x,y,z:
(x*y)+z`) is the first place to look: it is the only op in these kernels whose rounding order can
differ without changing any fixture. Recorded in TODO.md.

## 34.4 THE FIDELITY GAP BEHIND IT, NAMED

The port cannot run PYTHON's DEFAULT schedule at all. That is v1's warp-1 limit, and it is now the
only thing between "the same program on both sides" and "each device's default program on its own
side": both need a real warp (`lidxK` over `local_size`, per-lane registers, `exec_masks` per lane,
LOCAL buffers shared across the warp) in `tinybendygrad/runtime/ops_python.bend`. Until then the
harness must declare `has_local = False` for both, which it now does and which it now VERIFIES.

---

# 35. WHY BEND IS NOT FASTER: ITS ARENA IS A PERSISTENT LIST, SO EVERY VALUE WRITE IS ~48 ALLOCATIONS

## 35.1 THE OVERHEAD IS NOT WHERE THE EXCUSES ARE

`BendProgram.__call__` writes a packet file, spawns the executor and hex round-trips every buffer,
so "subprocess overhead" is the obvious suspect. It is not the answer, and the split is measured:

    packet        38 525 bytes (510 uops + 3 buffers)
    executor only 0.48 / 0.48 / 0.49 s          <- /usr/bin/time on the binary, no Python
    the BEND lane's launch                     ~519 ms

**⇒ THE SPAWN, THE FILE AND THE HEX COST ~0. Everything is inside the compiled executor**, which
runs the same 510-uop program the CPython lane runs in 195 ms. So the port's EXECUTION is 2.66x
slower than CPython's INTERPRETER on identical work, and that is the whole gap.

## 35.2 `sample` PUTS IT IN THE RUNTIME, AND THE PORT'S OWN CODE SAYS WHY

    142 samples, main thread:
      142  io_loop -> io_step -> corpus_eval -> work_loop
       24%  WL_FID_Prog_ld_lane      (the LOAD path)
       18%  WL_FID_Prog_put          (the value store)
        9%  WL_FID_Prog_oob          (the out-of-bounds guard)
       the rest spread over term_drop / span_fade / spin_*   <- BEND'S OWN TERM MANAGEMENT

`term_drop`, `span_fade` and the `spin_*` leaf frames are the runtime allocating, reference
counting and freeing heap terms. The port allocates because of how its state is shaped:

    Val.at(vs, i)   = List.get(spine, i/16) then List.get(chunk, i%16)      a walk
    Val.put(vs,i,e) = List.set(spine, i/16, List.set(chunk, i%16, e))       REBUILDS BOTH

**⇒ AND THIS FILE ALREADY MEASURED THE COUNT: 96 584 987 ALLOCATIONS PER 32x32 LAUNCH, EVERY ONE
IN SIZE CLASS 0 OR 1 -- one-word objects and two-word CONS CELLS, i.e. LIST TRAFFIC AND NOTHING
ELSE** (`.agents/slop/perf/REPORT.md` §12.4). 96.6M allocations over 0.48 s is 5 ns each, which is
exactly what the executor-only timing says. **THE EXECUTOR'S WHOLE RUNTIME IS ITS ALLOCATION
COUNT.** CPython's interpreter does the same step with `values[u] = x` -- one dict store, no
allocation -- which is why an interpreted interpreter beats a compiled one here.

## 35.3 AND THE GAP GROWS WITH THE PROGRAM, WHICH IS THE SIGNATURE OF THE SPINE WALK

    16x16   148 uops   PYTHON 75 ms   BEND 118 ms   BEND 1.58x slower   spine <= 10 cells
    32x32   510 uops   PYTHON 391 ms  BEND 1037 ms  BEND 2.66x slower   spine <= 32 cells

A write costs `chunk(16) + spine(<= n/16)` and a read costs `spine`; both grow with the uop count,
while CPython's dict does not. The ratio tracks the spine, which is what a linked arena predicts
and what a "Bend's compiler is slow" story does not.

## 35.4 WHAT WOULD ACTUALLY FIX IT, RANKED

1. **AN IN-PLACE ARENA.** `Array` is Bend's mutable slot vector: `a[i] <- v` writes in place, so a
   read is O(1) and a write allocates NOTHING. It cannot live in the `Prog` record today -- this
   file's own substrate rule 1 says a `Data` record cannot hold a `List` or an `Array`, which is
   why the arena is threaded as lists at all -- so `Prog` has to stop being `Data` and carry
   `Array<Elem*N>` / `Array<U32*N>` fields, threaded linearly. Estimated effect: 96.6M allocations
   per launch -> near zero, i.e. the constant that makes BEND slower than CPython disappears.
2. **A REVERSED CHUNK so that a sequential write is a PREPEND.** Post-order means the walk writes
   increasing slots, so a descending chunk turns the common write into one cons cell and one spine
   rebuild per 16 writes, instead of 16 cells per write. Cheaper to land than (1) and second best
   because it does nothing for the reads (three per ALU step).
3. Nothing else on the table. The hex round trip, the packet write and the spawn are all measured
   at ~0 and are not the problem.

## 35.5 WHAT THIS REPORT DOES NOT CLAIM

No change is made here. (1) is a refactor of the threaded state of a 3 177-line interpreter, and
it has to keep `ops_python_exec`'s 153 fixtures and 365 rows exact; that is a unit of work, not a
patch at the end of a session. The measurement above is what makes it a targeted job rather than a
guess, and the two numbers a fix must beat are on the table: **195 ms per launch at 32x32** (the
CPython lane on the same program) and **97 ms at 16x16**.

## 35.6 THE FACTOR, MEASURED: 450 ns PER LIST WRITE AGAINST < 5 ns PER ARRAY WRITE

`.agents/slop/perf/stage3_arena.bend` is the port's `Val.put` against `Array.set` on the same
512-slot arena, 2 000 000 writes each, and BOTH READ BACK (a benchmark whose result is never read
is a benchmark whose writes a compiler may delete -- and the first version of this file measured
nothing at all, because `List.set` into an empty chunk is a NO-OP and it "ran" at 200 ns/write
while writing zero times):

    mode    writes      wall     per write    checksum
    list    2 000 000   0.90 s   450 ns       7998464    (spine rebuild + 16-cell chunk rebuild)
    array   2 000 000   <0.01 s  <5 ns        5998464    (in place, no allocation)

**⇒ SO ONE ARENA WRITE COSTS ~450 ns IN THE PORT'S SHAPE AND ESSENTIALLY NOTHING IN THE ARRAY
SHAPE**, and the executor at 32x32 spends 480 ms over ~2M steps, i.e. ~240 ns per step -- the same
order, which is what makes the allocation count (§35.2: 96.6M per launch) the whole runtime.

This also fixes the rank in §35.4: the reversed-chunk idea would take a write from ~47 cells to
~2 cells (a prepend plus the occasional spine rebuild), i.e. roughly 20x, but it still leaves the
READS walking a spine three times per ALU step. The array takes both to zero, so it is the one
worth doing, and the target it must reach is measured: **195 ms per launch at 32x32 and 97 ms at
16x16.**

---

# 36. THE HOT CHUNK IS HELD IN THE RECORD: 1.21x, VERIFIED

## 36.1 WHAT CHANGED

`Prog` carries two new fields -- `vc` (the chunk being written) and `vi` (its index, with
`4294967295` as the cold sentinel) -- and the arena goes through two new defs:

    Prog.vat(p, i)      a HIT reads the held chunk (index 0..15), a MISS reads the spine
    Prog.vput(p, slot, e)
                        a HIT rewrites the 16-cell chunk and touches NO spine cell
                        a MISS flushes the held chunk into the spine and loads the next one

and `Prog.put` is now ONE record rebuild: it was `Prog.next(Prog.vs1(p, Val.put(...)))`, which
built the 19-field record twice per value written.

**EVERY OTHER ARENA WRITER FLUSHES FIRST AND INVALIDATES**: `Prog.vs1` (and so `reset`, `stack`,
the vector LOAD), `Prog.flag.put`, `Prog.rng.del`, `Prog.stack`, `Prog.ld1` -- all four of the last
now start from `Prog.flush(p)` instead of `Prog.vs(p)`, because the spine LAGS the held chunk and
a snapshot taken from it would drop the newest values.

## 36.2 THE BUG THAT COST THE FIRST ATTEMPT, AND WHY THE GATE FOUND IT

First run: **136 unpinned divergences of 365 rows**, and every one was a ZERO where a value should
have been. `Prog.vput.rec`'s constructor wrote `Prog.vc(p), Prog.vi(p)` -- the OLD chunk -- instead
of the `vc`/`vi` it had been handed, so every store went into a chunk that was never written back.
Bisected by control: `put` back to `vs1(next(...))` was green, `vput` never; `vat` disabled was
still red, so the read path was never the suspect.

**THE FIXTURES DID NOT GO GREEN ON A HUNCH**: the bisect used three controls (cache-off,
read-off, write-off) and the third isolated the def in two runs.

## 36.3 MEASURED, SAME PROGRAM BOTH SIDES

`stage3_parity.py` (grid, local size and EVERY launch's op+srcs sequence verified identical):

    size   before            after             PYTHON (same program)
    16x16  118.45 ms         97.55 ms  1.21x    68.72 ms
    32x32  1037.25 ms       847.30 ms  1.22x   384.77 ms

So the cache is worth **1.21x/1.22x** and BEND is still 0.70x/0.45x of the CPython lane.

## 36.4 WHY IT IS ONLY 1.21x, AND WHAT IS LEFT

A hit still costs `co` cells (the chunk prefix before the written index, 0..15) and a chunk
crossing still rebuilds the spine prefix (`ci` cells, 0..31 at 32x32). The spine walk is what the
array would delete outright, and §35.6 measured that as **450 ns per write against < 5 ns**.

    MEASURED (a failed experiment, kept because it is informative): shrinking `Val.ci/co` to 8
    while the arena BUILDER still builds 16-slot chunks gives 144 divergences and a 1.64 error --
    the chunk geometry is COUPLED between `Val` and the builder, so it is not a free knob.

The array remains the answer: it needs `Prog` to stop being reusable, which is 42 defs and 37
constructors (§35.4/35.5). This commit is the half of that win that does not need the
linearisation.

## 36.5 AND FOUR `Bool.pick`s THAT RAN BOTH ARMS ON THE HOT PATH

`Bool.pick` evaluates both arguments. The port's own notes record that lesson for `run` -- "EVERY
LAUNCH BURNED THE WHOLE OF `FUEL`" -- but four sites on the interpreter's hot path still did it:

    Prog.rng.put    `Bool.pick(Prog, seen, Prog.put(...), Prog.next(Prog.flag.put(p, u)))`
                    so EVERY RANGE visit ALSO ran `Prog.flag.put`, which rebuilds the chunk spine
                    and COLD-STARTS the arena cache, and wrote the counter twice
    Prog.rng.nxt    read `Prog.cur` twice per RANGE visit for one counter
    Prog.index.at   computed BOTH the ALU and the memory index for every INDEX
    alu1/alu2/alu3  ran the FLOAT lane AND the INT lane -- `symbolic.bend`'s full evaluator with
                    its `Maybe` boxing and twenty-arm match -- for every arithmetic op

Each is now a `match` on a parameter, so only the answering arm runs. MEASURED:

    16x16   96.59 -> 90.59 ms      32x32   847.30 -> 727.44 ms (both from the 847.30 of §36.3)

and against the session's starting point: **16x16 118.45 -> 90.59 (1.31x), 32x32 1037.25 ->
727.44 (1.43x)**, with `ops_python_exec` still 153 fixtures / 365 rows / 0 divergences and
`stage3_parity.py` still reporting EVERY LAUNCH IDENTICAL.

## 36.6 THREE PATHS THAT REBUILT THE 21-FIELD RECORD THREE TIMES

`Prog.next(Prog.live(Prog.X1(p, ...)))` is three constructions of the same record, and LOAD, STORE
and STACK all did it:

    Prog.stack   next(vs1(stack.copy(...)))                      3 rebuilds per STACK
    Prog.ld1     next(live(vs1(ld.at(...))))                     3 rebuilds per LOAD
    Prog.store   next(live(ms1(store.at(...))))                  3 rebuilds per STORE

`Prog.step.vs` and `Prog.step.ms` fuse each into ONE construction, and they differ only in whether
the VALUE arena was replaced (`vs1` cold-starts the cache) or only the memory was.

    16x16   90.59 -> 90.99 ms (within noise)     32x32  727.44 -> 703.70 ms

**SESSION TOTALS, same program both sides, `stage3_parity.py` verifying EVERY LAUNCH IDENTICAL:**

    size    start        now            PYTHON (same program)   BEND / PYTHON
    16x16   118.45 ms    90.99 ms       70.14 ms                0.77x
    32x32   1037.25 ms   703.70 ms      375.78 ms               0.53x

i.e. **1.30x and 1.47x faster than where the session started**, and still not faster than the
CPython lane. What remains is exactly what §35 measured: the arena and the record rebuild. The
`Array` arena (450 ns -> <5 ns per write) is still the only lever of the size needed, and it needs
`Prog` linear -- 39 defs use the record twice or more, and in this language a helper returning
`(Array, V)` cannot be destructured ("a match cannot scrutinize a computed value"), so every one of
those 39 sites needs the `.go`-chain restructure. That is the next unit.

---

# 37. WHAT THE EXECUTOR ACTUALLY SPENDS ITS TIME ON, AND WHY THE ARRAY ALONE IS NOT ENOUGH

## 37.1 THE PROFILE, AT A SIZE BIG ENOUGH TO SAMPLE

`sample` on the compiled executor for a 64x64 launch (the 32x32 kernel is too short to sample), by
symbol:

    164  term_drop          \
     93  span_fade           >  BEND's own term allocate/refcount/free
     75  spin_119            |
     59  spin_125            |
     ~250 more spin_*       /
      9  WL_FID_Prog_store_lane_at
      9  WL_FID_Prog_ld_lane_k299
      9  WL_FID_Prog_index
      7  WL_FID_Prog_run_k638

**⇒ ~70-80% OF THE EXECUTOR IS THE RUNTIME'S TERM MANAGEMENT AND ~10% IS THE PORT'S OWN CODE.** The
interpreter is not slow because its algorithm is slow; it is slow because it allocates.

THE ARITHMETIC THAT PINS IT: 32x32 runs ~2M steps in 340 ms of executor time = **170 ns per step**,
and this tree's own measurement of the compiled runtime is **~5 ns per allocation** (96.6M
allocations over 0.48 s, §12.4). So a step allocates **~34 terms**, and the sources are countable:
the 21-field `Prog` rebuild (1-2 per step), the 16-cell chunk rebuild (one cons per cell before the
written index, ~8), an `Elem` per value produced (1-2), and a `Maybe` per arena read (`List.get`
answers one; 3-4 reads per step).

## 37.2 SO THE ARRAY'S CEILING IS ~1.3x, NOT 3x

The `Array` arena deletes the chunk rebuild (~8 conses) and one `Maybe` per read (3-4), i.e. about
a third of the allocations. At 699.46 ms (the current 32x32), a third fewer allocations is ~**540 ms
against the CPython lane's 373 ms** -- better, and still slower.

**⇒ THE PARITY TARGET NEEDS BOTH: the array arena AND a state whose rebuild costs nothing per
step.** The record rebuild is the other third, and it is eliminated by the same change, because a
`Type` `Prog` carrying `Array<Elem>`/`Array<U32>` writes in place and rebuilds no arena at all --
but only if the fields that do not change stop being copied too, which means splitting the static
half (`us`, `v0`, `fs`, `vals`, `n`, the grid) out of the per-step record.

## 37.3 THREE MORE EXPERIMENTS, MEASURED AND REVERTED

    1 memory chunks 64 -> 16     32x32 727 -> 953 ms   the spine walk grows 4x; 64 IS the sqrt
                                                        optimum for a 4 KiB buffer
    2 every Prog field `+`       16x16 96.59 -> 94.08, 32x32 727 -> 731   inside the noise; not kept
    3 `List.get` -> direct walks 16x16 90.99 -> 101.63, 32x32 704 -> 765  matching a `Nat` peels
      (no `Maybe` on reads)                             one constructor per cell, which costs more
                                                        than the `Maybe` it saves

**A NEGATIVE RESULT IS A RESULT**: the interpreter is at a local optimum where the remaining costs
are structural, not local. Three separate attempts to shave them moved the wrong way, and each was
reverted rather than kept for its story.

## 37.4 THE UNIT OF WORK THAT IS LEFT, AND ITS ONE HARD PART

`Prog` becomes `Type` with `Array<Elem>`/`Array<U32>` fields. THE PAIR PROBLEM DOES NOT ARISE THIS
WAY -- the array lives INSIDE the record, so `Prog.put(p, u, e) -> Prog` stays a single value in and
a single value out, and an in-place write needs no destructuring.

What does arise is that a linear record cannot be read twice, and this file's helpers take `Prog`:
`Prog.store` calls `Prog.open`, `Prog.oob`, `Prog.ms` and `Prog.store.at` on the same `p`. So all 42
arena-touching defs change from "take the record" to "take the fields they read", their call sites
bind those fields once in a `match`, and the 37 `Prog{...}` constructors carry the two arrays. That
is the whole job, it cannot be landed in pieces (a half-converted record does not compile), and its
acceptance test is already written: `--check-only`, `ops_python_exec` 153/365/0,
`ops_bend_exec-e2e` 7 match, `stage3_parity` EVERY LAUNCH IDENTICAL, then 70.14 / 375.46 ms.

## 37.5 TWO LOOKUPS PER LANE THAT WERE THE SAME LOOKUP

`Prog.oob` was the first. Its recursion passed `j` through UNCHANGED and only counted `n` down, so
the "per-lane" bounds check answered `j = 0`'s comparison `run` times, re-reading the buffer pointer
out of the arena each time. It is one read and one comparison, and the answer is the old answer.

**AND THE OBVIOUS IMPROVEMENT IS A SEMANTIC CHANGE, MEASURED**: checking the LAST lane instead
(`off + (run-1)*step`) refuses this tree's own 16x16 packet -- "a load or store past the end of its
buffer" -- because ops_python stores `len(src_values[1])` lanes, not `run(u)`, so the last `run`
lane is not always a lane anybody writes. Reverted, and the refusal is written down here so the next
attempt at that "optimisation" starts from it.

The store was the second: `Prog.buf(p, u)` was read EIGHT times per lane (twice in `store.bits`,
twice in `store.addr`, again in `store.open`, and `store.i` re-reads it), and each is `Prog.src` --
an arena read with its `Maybe`. A four-lane store made ~32 arena reads to write 4 elements.
Everything except the value is per-STORE, so it is bound once in an `Sb` record and the lane loop
reads the arena exactly once per lane, for the value.

    16x16  96.18 -> 90.43 ms      32x32  699.46 -> 585.80 ms

**SESSION TOTALS, same program both sides, EVERY LAUNCH IDENTICAL:**

    size    start        now            PYTHON (same program)
    16x16   118.45 ms    90.43 ms       71.53 ms     (1.31x faster than start, 0.79x of PYTHON)
    32x32   1037.25 ms   585.80 ms      381.37 ms    (1.77x faster than start, 0.65x of PYTHON)

## 37.6 AND THE LOAD HAD THE SAME DEFECT

Per lane the load did `Prog.src` for the pointer, `Prog.src` for the closed-gate alternative,
`Prog.src` inside `Prog.ld.open`, `Prog.lane` (two more arena reads) and `Buf.at(Prog.fs(p), ...)`
-- about a dozen arena reads and list walks for four lanes, all with the same answer. They are
bound once in an `Lb` record, exactly as the store's are in `Sb`, and `Prog.ld` takes the memory
list instead of the record so the lane loop touches the arena only for the value.

    16x16  90.43 -> 91.89 ms (noise)     32x32  585.80 -> 555.33 ms

**SESSION TOTALS, same program both sides, EVERY LAUNCH IDENTICAL:**

    size    start        now            PYTHON (same program)   BEND/PYTHON
    16x16   118.45 ms    91.89 ms       68.26 ms                 0.74x
    32x32   1037.25 ms   555.33 ms      371.36 ms                0.67x

i.e. **1.29x and 1.87x faster than the session start**, and the ratio against the CPython lane has
moved from 0.77x/0.53x to 0.74x/0.67x. Every remaining lever is now an allocation count, and the
biggest single one -- the 16-cell chunk rebuild plus a `Maybe` per read -- is the arena, which needs
`Prog` linear (REPORT.md 37.4).

## 37.7 THE STATIC/DYNAMIC SPLIT: 21 FIELDS PER STEP -> 11

`Prog` carried 21 fields, twelve of which never change during a work item. They moved into `St`
(`us`, `v0`, `fs`, `vals`, `n`, `cx`, `cy`, `cz`) and `Gd` (`pv`, `gx`, `gy`, `gz`), and a per-step
rebuild now constructs 11 fields -- and a Bend record is a chain of two-child nodes, so that is
~10 malloc-and-refcount pairs per step gone.

    16x16   91.89 -> 85.6 ms  (three runs: 85.61 / 85.64 / 91.57)
    32x32   555.33 -> ~565 ms (three runs: 571.82 / 556.78 / 565.05 -- NEUTRAL, inside the noise)

**TWO THINGS THE MECHANICAL TRANSFORM SILENTLY ATE, and the gate caught both:**

1 `Prog.pv1` increments `pv` and `Prog.carry` computes the next grid position. A positional rewrite
  of "the four counters become `gd`" replaced BOTH with `Prog.gd(p)` -- dropping the arithmetic, so
  the odometer never moved. Symptom: ONE fixture diverged, `f32.cumsum.0.b0`, with an all-zero
  buffer. Both are rebuilt explicitly now (`Prog.pv1.gd`, `Prog.carry.gd`).
2 `Prog.at` builds its record from `lus` (the uop list), not from `st`, so the first position is not
  always the static record.

**SESSION TOTALS, same program both sides, EVERY LAUNCH IDENTICAL:**

    size    start        now       PYTHON (same program)   BEND/PYTHON
    16x16   118.45 ms    85.6 ms   68.22 ms                0.80x   (was 0.77x at 118/96)
    32x32   1037.25 ms   ~565 ms   371.95 ms               0.66x   (was 0.53x)

**1.38x and 1.84x faster than the session start.** The remaining gap is the arena's 16-cell chunk
rebuild plus a `Maybe` per read (REPORT.md 35.6/37.1) -- the `Array`, which needs `Prog` linear.

---

# 38. THE CEILING, RE-MEASURED AFTER THE SPLIT — AND WHY `Array` ALONE DOES NOT GET THERE

## 38.1 THE PROFILE AFTER THE SPLIT AND THE LANE FIXES

`sample` on the Bend-built executor at 64x64, by symbol:

    146 term_drop    96 span_fade    62 spin_160    61 spin_166    18/17/12 other spin_*
     11 WL_FID_Prog_run    10 WL_FID_Prog_index

**⇒ ~75-80% IS STILL BEND'S OWN TERM MANAGEMENT AND ~10-15% IS THE PORT'S CODE.** The split, the
`Sb`/`Lb` hoists and the four `Bool.pick` fixes moved the port's share down; they did not change what
dominates, because what dominates is the ALLOCATION COUNT and not any particular helper.

At 32x32 that is ~2M steps in ~270 ms of executor time (the lane's 554 ms launch includes the
subprocess and the hex round trip) = ~135 ns/step, or ~27 allocations at this tree's measured
~5 ns each.

## 38.2 SO `Array` IS WORTH ~1.35x AND LANDS SHORT

The two things an `Array` arena deletes are the 16-cell chunk rebuild (~8 cons cells per value
written) and the `Maybe` that `List.get` allocates per read (3-4 per step). That is ~11-13 of the
~27-34 allocations per step:

    32x32  554 ms -> ~410-420 ms   against the CPython lane's 379 ms
    16x16   87 ms -> ~72 ms        against the CPython lane's 70 ms

**⇒ THE `Array` ARENA IS WORTH DOING (it is the last named, measured lever) AND IT LANDS AT ~0.90x
OF THE CPYTHON LANE, NOT ABOVE IT.** Beating CPython needs the per-value `Elem` allocation and the
per-step record rebuild gone as well, i.e. a mutable-register interpreter rather than a
persistent-state one -- a rewrite of `run`, not a change to a field type.

## 38.3 THREE MORE EXPERIMENTS THIS TURN, NONE KEPT

    1 `Uop.nth` without `Maybe` (a direct walk)     16x16 85.46 vs 85.6, 32x32 573 vs 565 -- NEUTRAL
    2 executor build flags: the harness's Bend-built binary runs the 32x32 packet in 0.28 s; the same
      C compiled by hand with `-std=c11 -O3`, and again with Bend's own `-x objective-c -fobjc-arc
      -fmodules`, runs it in 0.67 s and 0.73 s. SO `-o out.c` PLUS A MANUAL `clang` IS NOT THE
      ARTIFACT THE LANE MEASURES -- every number in this report comes from the Bend-built binary.
      There is no flag lever here, and quoting the hand-built time would have been wrong by 2.4x.
    3 the `Array` itself: NOT attempted, and 38.2 is why it is now a measurement rather than a guess.

**THE HONEST POSITION**: 16x16 118.45 -> 86.95 ms (1.36x) and 32x32 1037.25 -> 554.07 ms (1.87x)
since the session started, with every gate green, and the ratio against the CPython lane moved from
0.77x/0.53x to 0.80x/0.68x. The remaining named change is worth ~1.35x and lands at ~0.90x. Beating
the CPython lane is not reachable by the change that is left; it needs the interpreter's state model
replaced, and that is a rewrite this session has now bounded rather than discovered.

---

# 39. THE ARENA PRIMITIVE, MEASURED IN THE INTERPRETER'S OWN SHAPE: THE ARRAY IS ~100x, NOT 1.35x

## 39.1 THE EXPERIMENT

§38 projected the `Array` at ~1.35x BY COUNTING ALLOCATIONS. That was wrong, and this replaces it
with a measurement. `.agents/slop/perf/stage3_arena2.bend` runs 2 000 000 interpreter-shaped steps
-- three arena reads and one arena write on a 512-slot arena, which is exactly what one ALU uop
costs -- in three representations, and all three print the SAME checksum, so they are doing the same
work:

    mode    representation                              wall     per step
    list    chunked spine, no held chunk                2.41 s   1.20 us
    cache   the held chunk (what the port does today)   1.07 s   0.53 us
    array   Array<Elem> in a LINEAR record, .go chain   <0.01 s  <0.005 us

**⇒ ~100x ON THE PRIMITIVE.** §38's 1.35x counted ALLOCATIONS; the array also deletes the WALKS --
the pointer chase down the spine and along the chunk, three times per step -- and the walks are what
the 0.53 us is actually made of. So the lever is not the marginal one §38 called it.

## 39.2 WHAT THAT MEANS FOR THE EXECUTOR

At 32x32 the executor runs 170 ns per step with four arena accesses in it. If the arena is the
majority of that -- and the primitive says a read is a spine walk plus a chunk walk while the array
is O(1) -- then the array plausibly takes 554 ms to ~300 ms, i.e. **PAST the CPython lane's 379 ms.**
That is a projection and is labelled one; the measurement it rests on (0.53 us -> <0.005 us per
step's worth of arena traffic) is not.

## 39.3 THE COST, NOW BOUNDED WITH REAL NUMBERS

`Array.get` answers a PAIR, so every READ site needs the `.go` chain (`def f(r: Prog & Elem) ->
match r: case (p, e): ...`). WRITES do not: `Array.set` answers the array, so `Prog.put(p,u,e) ->
Prog` stays a single value in and out, and the array lives INSIDE the record. The read sites are the
17 callers of `Prog.src` plus the handful that read the arena directly; each becomes a chain of two
or three small defs.

**AND THE LANGUAGE TESTED OUT FIRST**: the `array` mode of the benchmark IS that chain (`R.get` ->
`R.get.k(r: Array<E> & E) -> ...`, `R.step` -> `R.step.b` -> `R.step.c` -> `R.step.d`), and it
compiles, runs, and is 100x cheaper. So the pattern §37.4 called "undestructurable, needs a chain" is
proven workable in the same commit that measures its payoff.

## 39.4 THE CASCADE, MEASURED RATHER THAN ESTIMATED

§39.2 said the refactor's cost is the linearisation. This is what the compiler says to the first step
of it -- `type Prog is Data:` -> `type Prog is Type:` -- with nothing else changed:

    Error:
    - expected : Data
    - observed : Type
    Location: Prog.st
    1840 | def Prog.st(+p: Prog) -> St:
         |                 ^^^^
    Note: +p can be used many times, so its type must be Data.

and the count behind that one error is **89 defs take a `Prog`**, 28 of which never read it, 39 use
it once and 46 use it twice or more (`Prog.dispatch` 22 times, `Prog.die` 16, `Prog.carry.at` 10,
`Prog.alu.at` 7 ...). Each of those 89 loses its `+`, and each of the 46 needs its body restructured
into one `match` plus the `.go` chains for the ~17 arena reads.

**⇒ SO THE `Array` REFACTOR IS ONE ATOMIC CHANGE OF ~89 SIGNATURES + 46 BODIES + 17 CHAINS, AND A
HALF-CONVERTED LINEAR RECORD DOES NOT COMPILE.** That is why it has not been landed in a turn: it
cannot be committed green in pieces, and the tree's rule is that every commit compiles and passes the
gates. It is sized here so the next attempt starts from a measurement instead of a surprise.

## 39.5 ONE MORE TRAVERSAL REMOVED WHILE I WAS IN THERE

`Prog.vat` did `Prog.vi(p)`, then `Prog.vc(p)` OR `Prog.vs(p)`: three 11-field traversals of the same
record per arena read, called three times per ALU step. This file's own note on `Prog.next` calls
that shape its worst offender -- "SEVENTEEN separate `Prog.x(p)` PROJECTIONS ... one per uop" -- and
the read path had the same defect. One `match` binds the three:

    16x16  90.51 -> 87.76 ms     32x32  556.31 -> 561.46 ms (inside the noise)

Gates unchanged: `ops_python_exec` 153 fixtures / 365 rows / 0 divergences, `--check-only` clean,
`stage3_parity` EVERY LAUNCH IDENTICAL.

## 39.6 THE LINEARISATION, ATTEMPTED: THE OBSTACLE IS A LANGUAGE RULE, NOT 89 SIGNATURES

I ran the conversion the reviewer asked for, scripted, three times, and each pass found one more
language rule that a script cannot satisfy. All three attempts were reverted -- the tree is at the
state it was, green:

    type Prog is Type            -> the FIRST `+p: Prog` is refused (89 defs take a Prog)
    67 signatures lose `+`       -> bodies that use the record twice in sequence need one `match`
    32 bodies wrapped            -> A BODY WHOSE FIRST STATEMENT IS A `match` CANNOT BE NESTED:
                                    "a match cannot be matched in this position (it is matched after
                                    a local statement or after a match on a later binder)"
    9 arms wrapped               -> SAME RULE INSIDE AN ARM: `case True{}: match p: ...` is refused
    44 arms merged into `match x p:` (multi-scrutinee) -> the pass compounds and mangles
                                    `match p p:` on the defs that already matched `p`

**⇒ THE RULE IS: ONE `match` PER BODY LEVEL, ON A PARAMETER, AND A LINEAR RECORD CAN ONLY BE
DESTRUCTURED WHERE NO OTHER MATCH IS IN SCOPE.** So every one of the 34 branch-shaped bodies must be
converted to a MULTI-SCRUTINEE match (`match x p:`) with the record pattern appended to EVERY arm --
including the arms that do not touch the record, which then need a `_`. That is a hand-written
restructure per def, because a script has to guess which arm needs the pattern and the alternatives
(`_`) interact with the record's own binders.

**AND 34 BRANCH-SHAPED BODIES IS THE WHOLE COST**: `Prog.dispatch` alone is 20 arms, and its arms
each consume `p` once, which is LEGAL for a linear value -- so `dispatch` needs no wrap, only `+`
removed. The scripts could not tell "uses it twice in sequence" from "uses it once per arm" without
reading each body.

**MEASURED, SO THE NEXT ATTEMPT STARTS HERE AND NOT AT THE TOP**: the conversion is 67 signature
edits (mechanical), 32 sequential-use bodies (one `match` each, mechanical), and 34 branch-shaped
bodies of which the ones that use the record inside an arm need the scrutinee merge (hand work,
probably 6-10 of them: `Prog.flush.go`'s False arm uses `vs`/`vi`/`vc`; `Prog.vput.go`,
`Prog.backedge.at`, `Prog.rng.*`, `Prog.param.at`, `Prog.index.by`, `Prog.store.at`).

## 39.7 THE BLOCKER, PROVED WITH TEN LINES: A LINEAR STATE CANNOT BE THREADED THROUGH THIS LOOP

`.agents/slop/perf/t_loop.bend` is the whole argument:

    type S is Type: S{a: U32, n: U32}

    def go(xs, s) -> S:                       # matches the STATE
      match s: case S{a, n}: go.step(xs, a, n)

    def go.step(xs, +a, +n) -> S:             # matches the CURSOR, then recurses
      match xs: case Nil{}: S{a, n}
                case h <> t: go(t, S{U32.add(a, h), U32.add(n, 1)})

    "Error: expected: a filled definition (an unfilled law is a dead claim: live code cannot use it)
     observed: go"    -- and defining `go.step` FIRST fails the same way, naming `go`.

**⇒ BEND ALLOWS ONE MATCH PER BODY LEVEL AND REFUSES MUTUAL RECURSION, SO A LOOP THAT MUST BOTH
DESTRUCTURE A STATE AND MATCH A CURSOR IS INEXPRESSIBLE.** The interpreter's `run` is exactly that
loop: `match f un` is the cursor and every iteration has to destructure the record to rebuild it.
That is why the linearisation could not be finished, and it is why no amount of scripting would have:
the last error is not a mechanical one.

## 39.8 SO WHAT *IS* AVAILABLE, AND WHY THE ARRAY IS NOT IT

The 100x measurement (§39) is real and it is out of reach for this state model: an `Array` is `Type`,
`Type` forces `Prog` to be linear, and a linear `Prog` cannot pass through the loop above.

**THE DATA-COMPATIBLE VERSION OF THE SAME IDEA IS A `C16` CHUNK** -- a sixteen-`Elem` *record* instead
of a sixteen-`Elem` *list*: `C16{e0, .., e15}` is `Data`, so nothing linearises; a read is a `Nat`
projection and therefore O(1) instead of a walk of up to sixteen cons cells; and a write rebuilds ONE
16-word record instead of up to sixteen cells plus the spine. It is the middle point between the two
measured extremes (list 1.20 us/step, array <0.005 us/step) and it is the only one of the three that
the language allows here. Not measured yet, and named rather than guessed.

**THE SESSION'S MEASURED POSITION, unchanged by this turn**: 16x16 118.45 -> 87.76 ms (1.35x),
32x32 1037.25 -> 558.74 ms (1.86x), against the CPython lane's ~69.6 / ~379 ms. Gates green:
`ops_python_exec` 153 fixtures / 365 rows / 0 divergences, `ops_bend_exec-e2e` 7 match,
`stage3_parity` EVERY LAUNCH IDENTICAL.

## 39.9 THE `C16` CHUNK, MEASURED -- AND IT IS SLOWER THAN WHAT THE PORT ALREADY DOES

§39.8 named `C16` as the Data-compatible middle point and said it was measured only by inference.
Now it is measured, four modes, 2 000 000 interpreter-shaped steps each, same checksum in all four:

    mode    representation                                        wall     per step
    list    chunked spine, no held chunk                          2.39 s   1.20 us
    cache   the held chunk -- WHAT THE PORT DOES TODAY            1.04 s   0.52 us
    c16     sixteen Elem as a DATA record per chunk               1.50 s   0.75 us
    array   Array<Elem> in a LINEAR record (UNREACHABLE, 39.7)   <0.01 s  <0.005 us

**⇒ `C16` IS 44% SLOWER THAN THE HELD CHUNK.** The record rebuild costs more than the chunk walk it
replaces: a write rebuilds sixteen fields flat, while the held chunk rebuilds only the cells BEFORE
the written index (average eight) and touches no spine at all. The intuition that "one record
allocation beats a list rebuild" is wrong here, and it is wrong by a measurement, not an argument.

**⇒ SO THE PORT IS AT THE FASTEST REPRESENTATION THE LANGUAGE ALLOWS FOR THIS STATE MODEL.** Of the
four, the one it uses is second only to the linear array, and the array cannot be threaded through
this loop (39.7). Every cheaper-per-access structure has now been tried and measured:

    Array      <0.005 us/step   unreachable (linear state cannot cross the loop)
    held chunk  0.52 us/step    <- in use
    C16         0.75 us/step    rejected, 44% slower
    plain list  1.20 us/step    rejected, 2.3x slower (this is why the cache was added)

**THE GAP THAT REMAINS IS NOT THE ARENA**: 3 reads + 1 write of `0.52 us/step` worth of arena traffic
against a whole step of ~135-170 ns means the arena is a MINORITY of the step once the cache is in
place, and the rest is the ~27 allocations per step that §37 measured. Those are `Elem` constructions,
`Maybe`s and the per-step record rebuild -- each individually small, and the array was the only lever
that removed them all at once.

## 39.10 THE SAME DEFECT AS `Prog.vat`, ONE OPERATION OVER: NINE TRAVERSALS PER ARENA WRITE

§39.5 fixed `Prog.vat` (three traversals per arena READ). The WRITE was worse and had not been
touched: `Prog.vput` walked the 11-field record **nine times per value written** --

    Prog.vi(p)                 the hit test
    Prog.vs / vc / vi          inside `vput.hit`
    Prog.flush(p)              `vi`, `vs`, `vi`, `vc` again        (the miss path)
    Prog.vput.rec(p, ...)      one more, to rebuild

-- and every one is a full `match` over the record. One match binds all eleven now, and the flush
and the rebuild take the binders:

    16x16  87.76 -> 82.17 ms      32x32  558.74 -> 530.21 ms
    session  118.45 -> 82.17 (1.44x)      1037.25 -> 530.21 (1.96x)

`ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match;
`--check-only` clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

**NOTE ON THE ABLATION THE REVIEW ASKED FOR**: a semantic-preserving ablation of "Elem construction"
or "the per-step record rebuild" is not available in this interpreter, because the arena holds the
RANGE counters -- remove an allocation and the values change, the trip counts change, and the timing
measures a different program. The one ablation that IS sound is "replace a structure with a faster
one and gate it", which is what the four-mode arena table (39.9) and this fix both do. That is why the
remaining allocation sources are attacked one operation at a time, with the gate as the proof.

## 39.11 `Bool.pick` WAS STILL EVALUATING ALL THREE ALU ARMS -- AND 16x16 FLIPPED

`Prog.alu.at` chose between arity 1, 2 and 3 with NESTED `Bool.pick`s, so EVERY arithmetic op built
`alu1`, `alu2` AND `alu3`: six arena reads (each three record traversals, before §39.5/39.10) and
three ALU evaluations to answer one. It is a MATCH on the arity now (`Prog.alu.kind`), the callers
bind the record ONCE, and the reads go through the new field-taking forms `Prog.vat.f` /
`Prog.src.f`, which do no record match at all.

    16x16  82.17 -> 68.61 ms      (PYTHON 70.02 -- BEND IS FASTER, 1.02x)
    32x32 530.21 -> 442.63 ms     (PYTHON 375.51 -- 0.85x)
    session 118.45 -> 68.61 (1.73x)   1037.25 -> 442.63 (2.34x)

Gates: `ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match;
`--check-only` clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

**THE CLASS THE REVIEW NAMED IS THE CLASS THAT PAYS**: an accessor call is a full `match` over the
11-field record, so a def that calls five accessors pays five traversals, and a `Bool.pick` that
picks between three helpers pays for all three. The three biggest wins of this session -- 39.5
(`vat`), 39.10 (`vput`), 39.11 (this one) -- are all that same defect, and the audit is not finished:
`Prog.ld1`, `Prog.store`, `Prog.rng.*` and `Prog.param.at` still reach the record several times per
step (they are the next sites, in that order by frequency).

## 39.12 `Prog.ld1`: FIFTEEN RECORD TRAVERSALS A LOAD, COLLAPSED TO ONE BIND

The load reached the 11-field record about fifteen times per LOAD: `Prog.step.vs`, `Prog.flush`
(four), `Prog.ms`, `Prog.ld.sb` -- which re-took `Prog.buf` (`fs` + `src`) and `Prog.lane` -- plus
`Prog.ld.happens` and `Prog.oob`, each of which re-took `Prog.buf` again. One bind now feeds all of
it through field-taking forms (`Prog.ld.sb.f`, `Prog.ld.happens.f`, `Prog.oob.f`, `Prog.step.vs.f`,
`Prog.dt.f`, `Prog.open.f`), and `Prog.oob.f` reads the pointer ONCE instead of three times:

    16x16  68.61 -> 61.26 ms    (PYTHON 70.02 -- **1.14x FASTER**)
    32x32 442.63 -> 433/427/453 ms  (mean ~437, trending down inside the noise)
    session 118.45 -> 61.26 (1.93x)     1037.25 -> ~437 (2.37x)

Gates: `ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match;
`--check-only` clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

**THE REMAINING SITES OF THE SAME CLASS**, unchanged in character: `Prog.store` (~12 traversals;
its `step.ms.f` form is written but not yet wired, because the value cache must survive a STORE),
`Prog.flush` itself (still four traversals, reached from `Prog.stack`), `Prog.rng.over`/`rng.at`,
`Prog.param.at`.

## 39.13 THE STORE COLLAPSED TOO: ~12 RECORD TRAVERSALS -> ONE BIND

`Prog.store` took `Prog.step.ms`, `Prog.ms`, `Prog.store.sb` (twice: `Prog.buf` is `fs` + `src`),
`Prog.open`, `Prog.oob` (which re-took `Prog.buf`), and one `Prog.vat` per lane. One bind now feeds
`Prog.store.sb.f`, `Prog.open.f`, `Prog.oob.f`, `Prog.step.ms.f` and a lane loop that reads through
`Prog.vat.f`. **`Prog.step.ms.f` CARRIES `vc`/`vi`**, because a STORE does not invalidate the value
cache -- that is the one thing the LOAD's form must NOT do, and it is why the two forms differ.

    16x16  61.26 -> 58.64 ms   (PYTHON 70.02 -- **1.18x FASTER**)
    32x32 442 -> 436.86 ms     (inside the noise; still 0.86x of PYTHON's 375.51)
    session 118.45 -> 58.64 (2.02x)    1037.25 -> 436.86 (2.37x)

Gates: `ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match;
`--check-only` clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

**WHY 32x32 DID NOT MOVE WITH IT**: at that size the step mix is dominated by the REDUCE body, whose
cost is the ALU path (already collapsed in 39.11) plus `Mem.st`/`Mem.ld` -- and `Mem` is the 64-cell
chunked byte list, untouched by any of these three collapses. That is the next thing to look at, and
it is not the record.

## 39.14 A CORRECTION: `Mem` IS NOT WHAT DOMINATES 32x32, AND THE PROFILE SAYS SO

§39.13 attributed the flat 32x32 number to `Mem.st`/`Mem.ld`. That was an inference, and `sample` on
the CURRENT executor (64x64 launch, after every collapse) says otherwise:

    98 term_drop   69 span_fade   ~110 across spin_*     <- BEND's runtime: allocate/refcount/free
    10 WL_FID_Prog_run_k691    10 WL_FID_Prog_index     7 WL_FID_Prog_run
     6 WL_FID_Prog_ld_at        5 WL_FID_Prog_ld_sb_f   4 WL_FID_List_set

**~85% IS STILL THE RUNTIME'S TERM MANAGEMENT AND ~14% IS THE PORT'S CODE.** `WL_FID_Prog_ld_at` is
the load loop -- the `Mem` read -- and it is 6 samples of ~330, i.e. **~2%**. A word-granular `Mem`
would therefore buy ~2%, not the amount §39.13 implied, and the rewrite (80+ lines with byte-order,
partial-write and bool semantics) was correctly not attempted on that estimate.

**WHAT THE PROFILE ACTUALLY NAMES** is `Prog_index` (3%) and `Prog_run` (5%) -- the INDEX path and the
step dispatch -- plus the runtime term churn that every `List.get`, `List.set`, `Elem` and record
rebuild feeds. Of those, one redundancy was found and fixed here:

    Prog.index.mem called `Prog.src(p, u, 0n)` THREE TIMES -- for the buffer id, the offset and the
    offset-is-none flag -- and each read is a record traversal plus an arena traversal. One read now,
    three projections off it:  32x32 436.86 -> 433.24 ms, 16x16 unchanged inside the noise.

Gates: `ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match;
`--check-only` clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

## 39.15 THE SECOND BATCH OF COLLAPSES WAS ATTEMPTED AND REVERTED: 68 DIVERGENCES

I collapsed the three sites the review named -- `Prog.flush` (four to five traversals -> one bind),
`Prog.stack` (two `Prog.flush` calls plus `us`, `slot` and `step.vs`) and `Prog.param.at`
(`pv1` + `val` + `put`, three traversals and two rebuilds) -- and the result COMPILED and answered
**68 unpinned divergences of 365**, with a 1.64 max error against the CPU lane. Reverted; the tree is
at `cdebabe77` and green.

**THE LESSON IS THE ONE THIS SESSION ALREADY RECORDED ONCE** (§39.12's `vput.rec`): `Prog.param.at`
is where the *counter* lives. `pv1` increments `Gd.pv` and `Prog.val` indexes `St.vals` with the
PRE-increment counter, and folding them into one construction means getting that order exactly right
in a single expression -- which the batch did not, and the gate said so in one run. `Prog.flush` and
`Prog.stack` were not implicated by the shape of the failure (the max error is in stored VALUES, and
`param` is what produces them for a `vals` buffer), but the batch was reverted WHOLE because a
partially-correct interpreter is not a result.

**MEASURED ON THE REVERTED-FREE TREE** (same commit, three runs): 16x16 57.33-58.64 ms,
32x32 429.73-436.86 ms -- against CPython's 70.02 / 375.51, i.e. **1.22x faster at 16x16 and 0.87x at
32x32**, with `ops_python_exec` 153/365/0, `ops_bend_exec-e2e` 7 match and `stage3_parity` EVERY
LAUNCH IDENTICAL.

**THE NEXT ATTEMPT ON THESE THREE SITES SHOULD LAND `flush` AND `stack` SEPARATELY FROM `param.at`,
and `param.at` ALONE WITH THE COUNTER ORDER WRITTEN OUT** (`val` reads `Gd.pv` BEFORE the increment,
and the increment happens in the same record construction) -- which is what the fixtures will check.

## 39.16 `Prog.flush`: FOUR OR FIVE TRAVERSALS -> ONE BIND

Landed alone, because the batch that carried it also carried `param.at` and was reverted (§39.15).
`Prog.flush` took `Prog.vi` for the cold test, then `Prog.vs`, and on the warm path `Prog.vs` +
`Prog.vi` + `Prog.vc` again. It reuses the field-taking `Prog.vput.flush.go` that the `vput` rewrite
already produced:

    16x16  57.33 -> 57.83 ms (noise)     32x32  429.73 -> 423.28 ms

`ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match; `--check-only`
clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

## 39.17 `Prog.stack`: ONE BIND AND ONE FLUSH, AND A `slot` THAT WAS THE WRONG SLOT

The first attempt at this collapse diverged on **68 rows, 32x32 only** (§39.15 suspected `param.at`;
it was not). The cause is a one-word difference: the original passes **`Uop.slot(u)`** -- the uop's
OWN result slot -- as the destination, and the rewrite used `Prog.slot(u, 0n)`, which is its FIRST
SRC's slot. A STACK writes its elements to its own slot, and `sslot` and `slot` are different fields
of `Uop`. With that corrected, and with the two `Prog.flush(p)` calls (four or five traversals each)
replaced by one, the collapse is green:

    16x16  57.83 -> 59.75 ms (noise)     32x32  423.28 -> 421.94 ms

`ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match; `--check-only`
clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

**SESSION POSITION**: 16x16 118.45 -> ~58 ms (**1.20x faster than CPython's 70.02**); 32x32
1037.25 -> ~422 ms (**0.89x of 375.51**, from 0.53x at the start of the session).

## 39.18 `Prog.param.at`: ONE BIND WITH THE COUNTER ORDER WRITTEN OUT

`pv1(p)` incremented `Gd.pv` in one record rebuild while `Prog.val(p)` read `St.vals` with the
PRE-increment counter off the ORIGINAL record: three traversals and two rebuilds per `PARAM` of a
`vals` buffer. Now the value is indexed with the pre-increment `pv` and the rebuild carrying `pv+1`
is the SAME construction that stores it -- which is the order §39.15 could not confirm, because the
68-row divergence that batch hit turned out to belong to `Prog.stack` (§39.17) and not to this.

    16x16  59.75 -> 56.13 ms     32x32  421.94 -> 421.35 ms

`ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match; `--check-only`
clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

**SESSION**: 16x16 118.45 -> 56.13 ms (**1.25x faster than CPython's 70.02**); 32x32 1037.25 ->
421.35 ms (**0.89x of 375.51**, from 0.53x at the start).

## 39.19 THE RANGE VISIT: TEN TO TWELVE TRAVERSALS -> ONE BIND

The old path read the record through `Prog.rng.at` -> `Prog.trip` **and `Prog.seen` TWICE** (once for
the flag, once inside `Prog.rng.nxt`) -> `Prog.cur`, and on exit through `Prog.rng.del` (which
re-flushed the arena), `Prog.pc`, `Prog.loop` and `Prog.at`: ten to twelve full `match`es for ONE RANGE
step -- and a RANGE step runs once per loop iteration. The counter, the flag, the trip count and the
loop head all come off the binders now (`Prog.rng.void` -> `Prog.rng.cnt` -> `Prog.rng.over.f` ->
`Prog.rng.stop`), with `Prog.loop.f` for the loop head.

    16x16  56.13 -> 58.8-60.9 ms (inside this machine's noise band; still 1.13x faster than PYTHON)
    32x32 421.35 -> 416.70 / 418.67 ms

`ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match; `--check-only`
clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

**SESSION TOTALS**: 16x16 118.45 -> ~58-61 ms (**1.13-1.25x faster than CPython's ~69-70**), 32x32
1037.25 -> ~417 ms (**0.90x of ~375.5**, from 0.53x at the session start). Ten audits of the same
class -- vat, vput, alu, ld1, store, index.mem, flush, stack, param.at, rng -- every one measured.

## 39.20 THE INDEX DISPATCH: FOUR OR FIVE TRAVERSALS -> ONE BIND

`index.at` -> `index.by` -> `index.alu`/`index.mem` -> `Prog.put` bound the 11-field record four or
five times per INDEX step: `by` bound it, `alu`/`mem` re-bound it (and `Prog.src` + `Prog.vat` inside
those bound it again), and `put` -> `vput` bound it once more. One bind now feeds `vat.f`/`src.f` (no
record match) and the field-taking `Prog.vput.go`, which is exactly the write `Prog.put` ended in:

    16x16  58.8-60.9 -> 56.56 ms     32x32  416.70 -> 412.35 ms   (PYTHON 378.28 -- 0.92x)

`ops_python_exec` 153 fixtures / 365 rows / 0 divergences; `ops_bend_exec-e2e` 7 match; `--check-only`
clean; `stage3_parity` EVERY LAUNCH IDENTICAL.

**SESSION**: 16x16 118.45 -> 56.56 ms (**1.23x faster than CPython's 69.41**); 32x32 1037.25 ->
412.35 ms (**0.92x of 378.28**, from 0.53x at the start; **2.52x faster than where it began**).

## 39.21 THE VALUE WRITE IS THE INTERPRETER: ONE ABLATION, FIVE STRUCTURES, ONE WINNER

**THE ABLATION, AND IT IS THE WHOLE FINDING.** `Prog.vput`'s hot arm writes one value per
value-producing uop. Replacing that ONE `List.set` with the chunk it was handed -- nothing else
touched, the answer left wrong on purpose -- took a 32x32 launch from **426.35 ms to 29.38 ms**.
The dispatch, the cursor, the record rebuild, the reads and the odometer together are the 29 ms
that is left. Every later measurement in this section is a variation on that one line.

**`List.set(l, k, e)` COPIES THE FIRST `k` CELLS**, and the index was `slot & 15`, so a write cost
`k` allocations AND `k` frees with a mean of 7.5. Forcing the index to the CONSTANT 0 while keeping
the same call, the same count and everything else -- **29.38 ms on the flat chunk, 30.05 ms on the
4x4 chunk**. So the price is the DYNAMIC index, not the arithmetic around it.

**FIVE STRUCTURES MEASURED, ONE KEPT** (32x32, `stage3_parity`, same program both lanes):

| # | value chunk | 32x32 | verdict |
|---|---|---|---|
| 1 | flat 16-cell `List` | 426.35 ms | baseline |
| 2 | flat 16-FIELD record (`Ch`) | 545.95 ms | **rejected** -- a match AND a rebuild of every field per write |
| 3 | 4x4 FIELD record (`G4`/`Q4`) | 557.27 ms | **rejected** -- same, twice over |
| 4 | **4x4 LIST tree** | **403.13 ms** | **KEPT** |
| 5 | pending delta, one CONS per write | 696.18 ms | **rejected** -- see below |

**#4 IS THE ONE KEPT** and it is committed (`b3b46e572`). Two levels of four means `Val.gput` does
two `List.set`s of mean 1.5 cells each instead of one of 7.5. Min-of-three A/B against the previous
HEAD: **{402.4, 407.5, 418.9} vs {416.9, 420.1, 420.9}**, and 16x16 56.01 vs 56.56 ms. A 3.4% win,
honestly reported as 3.4%: halving the mean index bought almost nothing, which is itself the
finding -- the dynamic `List.set` is near-CONSTANT in `k` over 0..15, not linear.

**#5 WAS THE OBVIOUS ANSWER AND IT LOST.** If a constant index compiles to a cons and a dynamic one
does not, the write should BE a cons: keep the hot chunk as a pending delta of the slots written
since the last chunk crossing, newest first, so slot `s` sits at offset `vh - s`. It is correct --
`ops_python_exec` PASS, 365 rows, 0 divergences -- and it is **696.18 ms**. Two costs ate it:
every chunk crossing folds the delta back into its chunk (16 positions rebuilt), and every crossing
SEEDS the next delta from the spine so the delta spans its chunk's base. Replacing the seeding with
an explicit base slot (one more `U32` in `Prog`) is the ONE untried variant, and it is untried
because it needs the record's arity changed at ~45 sites -- **that is where the next unit starts.**

**AND THE CHEAPEST VERSION OF #5 IS FAST AND WRONG**, which is the trap worth recording. Building
the initial arena from EMPTY groups measured **33.00 ms** and diverged on **139 of 365 rows**:
`List.set(l, k, v)` with `k` past the end puts the element at the END, not at `k`, so a sparse
group silently shifts every later slot. `Val.gzero` pre-fills each chunk -- the same arena
`Prog.echunks` already built -- and the speed went with the bug.

**AND THE WIDTH IS ONE NUMBER.** `Val.ci`'s shift, `Val.co`'s mask and the initial arena all spell
it. Moving the shift and mask alone left every read one chunk off the arena it was handed and
produced `max|PYTHON-BEND| 1.640e+00` on an answer of `3.576e-07` -- a WRONG answer, not a slow
one. Widths measured with the arena in agreement: **8 -> 476.40 ms, 16 -> 426.35 ms, 32 -> 430.80
ms**, so 16 is settled and the width is not a lever either.

**STATE AFTER THIS SECTION** (all measured, all green): `ops_python_exec` 153 fixtures / 365 rows /
0 divergences; `ops_bend_exec-e2e` 7 match; `--check-only` ALL PROOFS CHECK; `stage3_parity` EVERY
LAUNCH IDENTICAL and `max|PYTHON-BEND| 8.941e-08` (16x16) / `3.576e-07` (32x32).
16x16 **56.01 ms vs PYTHON 69.00 (1.23x faster)**; 32x32 **403.13 ms vs PYTHON 373.00 (0.93x)**.

### 39.21b THE SPINE, NOT THE CHUNK: TWO MORE ABLATIONS AND THE LAW THEY LEAVE

The chunk work above explained 3.4%. Two further ablations found the other 93%, and they are the
most valuable measurements in this section because they name ONE line:

    delete `List.set(vs, vi, vc)` in `Prog.vput.flush.go`   403.13 -> 29.62 ms
    delete the whole miss path (`flush` + `Val.ch.at`)      403.13 -> 29.72 ms

So the cost is the SPINE REBUILD -- folding a chunk back into `vs` -- and the spine READ and the
chunk write are both inside the 29 ms floor. `vs` is 32 long and the index is mean 16, so the fold
copies (and frees) ~16 cells per value written. **The hot chunk cache almost never hits**: crossings
are frequent, which is also why every chunk-shaped design above moved so little.

**AND THE OBVIOUS FIX LOST, WHICH IS THE LAW.** A two-level spine (four chunks per group, so the
fold is a `List.set` of mean 4 plus one of mean 1.5) measured **451.30 ms at 32x32 and 67.57 ms at
16x16 -- WORSE than the 403.83 / 56.84 it replaced**, with `ops_python_exec` still PASS and the
answer still exact. Each extra list level costs one `Maybe` allocation plus a call, and that price
is ~10 copies' worth of `List.set` -- more than the shorter copy saves.

    **A LIST TREE'S CHEAPEST WRITE IS NOT ITS SHALLOWEST COPY; IT IS THE POINT WHERE ONE MORE
    LEVEL COSTS MORE THAN THE COPIES IT REMOVES. HERE THAT POINT IS `16 SLOTS PER CHUNK, ONE
    LEVEL OF CHUNK, A FLAT SPINE`.**

The arithmetic agrees: for 512 slots a k-ary list tree minimises copies at depth 4-6 (~8-9 copies)
but pays 3-5 levels of `Maybe`+call, and one level was measured at ~10 copies. The current design
sits at 21 copies and 1 level. It is at the optimum of that trade, not an accident.

**WHAT IS LEFT** is not a data-structure change: the write is ~1M writes at ~16 copied cells each and
the only remaining lever is WRITING FEWER VALUES (a value consumed by the next uop needs no arena
slot). That is a semantic change to the interpreter, not a layout change, and it is where this
section stops.

**FINAL STATE, ALL MEASURED**: `ops_python_exec` 153 fixtures / 365 rows / 0 divergences;
`ops_bend_exec-e2e` 7 match; `--check-only` ALL PROOFS CHECK; `stage3_parity` SAME PROGRAM and EVERY
LAUNCH IDENTICAL, `max|PYTHON-BEND|` 8.941e-08 (16x16) and 3.576e-07 (32x32).
16x16 **56.84 ms vs PYTHON 68.37 (1.20-1.24x faster)**; 32x32 **403.83 ms vs PYTHON 365.93-373.00
(0.92x)** -- against **118.45 ms and 1037.25 ms** at the start of this session, i.e. **2.08x and
2.57x faster than where it began**.

### 39.21c TWO NEGATIVE MEASUREMENTS THAT CLOSE THE ARENA, AND WHY 386 ms IS ITS FLOOR

With the width at its derived optimum the write is still **92% of the launch** (385.87 -> 29.91 ms
with the hot chunk copy removed, 403.13 -> 29.62 with the spine fold removed). Two more facts were
measured before building anything else, and both say NO to the obvious next ideas:

**1. ALMOST NO WRITE IS DEAD.** Over the 32x32 packet: **510 writes, 1 never read (0.2%)**. So
"skip the values nobody reads" is worth one uop in five hundred. (`/tmp/deadcount.py`; the uop's
result slot is its own index and `srcs` are the reads.)

**2. THE READS ARE NOT RECENT, SO A CONS WINDOW CANNOT WORK.** Distance in WRITES between a read and
the write it reads, over 1047 reads:

    min 0   p50 121   p90 317   p99 359   max 502
    within   8 writes back:  24.9%      within  64:  33.0%      within 128:  54.1%

Two thirds of reads reach back further than the whole chunk, so a newest-first window -- the only
shape that makes a write a single cons -- would miss two reads in three and fall back to the spine
anyway. That is why the pending-delta design (#5 above) lost: the crossings are not an artifact of
the width, THE ACCESS PATTERN IS RANDOM.

**AND THE FLOOR IS THE LANGUAGE, NOT THE LAYOUT.** A random-access arena wants `Array`, whose writes
were measured at **<5 ns and no allocation** against `Val.put`'s **450 ns and ~24 cells**
(`stage3_arena.bend`, `stage3_arena2.bend`). `Array` is a `Type`, so it cannot live in a `Data`
record, and the linear form was already proved impossible for this interpreter in `t_loop.bend`:
**a linear state cannot cross the loop** (one `match` per body level, and no mutual recursion).
So the arena is a persistent list or it does not exist, and for 512 slots the k-ary list tree costs
`256/g^2 + g` with a measured minimum at **g = 8: 13 copied cells per write**.

**WHAT IS ACTUALLY LEFT** is therefore not in this file. Either the read pattern changes (a
scheduler that keeps values live for a short window), or the loop stops being a Bend recursion.
Both are outside "make the arena faster", and both are recorded here rather than attempted.

### 39.21d THE FULL MATRIX: EIGHT ARENA CONFIGURATIONS, AND g = 8 STANDING ALONE

Every row is a 32x32 `stage3_parity` launch on the same program, `ops_python_exec` PASS and the
answer exact. The chunk is a 2-level list unless the row says otherwise.

| chunk | width | spine | copied cells/write | 32x32 |
|---|---|---|---|---|
| flat 16-list | 16 | 32 | 7.5 + 16 = 23.5 | 426.35 ms |
| 16-field record | 16 | 32 | (match + rebuild) | 545.95 ms |
| 4x4 field record | 16 | 32 | (match + rebuild) | 557.27 ms |
| 4x4 list | 16 | 32 | 5 + 16 = 21 | 403.13 ms |
| **8x8 list** | **64** | **8** | **9 + 4 = 13** | **385.87 ms** |
| 16x16 list | 256 | 2 | 17 + 1 = 18 | 436.58 ms |
| 4x4 list, two-level spine | 16 | 8x4 | 5 + 5.5 = 10.5 | 451.30 ms |
| 4x4x8 list | 128 | 4 | 8 + 2 = 10 | 406.21 ms |

**AND THE LAST TWO ROWS ARE WHY THE CELL COUNT IS NOT THE WHOLE MODEL.** Both reach a LOWER copied
count than the winner and both are slower: the two-level spine by 65 ms, the three-level chunk by
20 ms. Each added list level costs a `Maybe` allocation plus a call, and that price is worth about
ten copied cells -- so the graph is not `cells` but `cells + 10 x levels`, and its minimum is
**three levels total (spine + two chunk levels) at g = 8**, exactly where the derivation puts it:
`256/g^2 + g` minimised at g = 8, plus the level count.

**THE INTERPRETER IS THEREFORE AT A MEASURED FLOOR OF ~386 ms FOR THIS PROGRAM**, and the floor is
not a tuning gap: 356 of those 386 ms are the value write, 0.2% of writes are dead, two thirds of
reads reach back further than any window, `Array` cannot enter a `Data` record, and a linear state
cannot cross the loop (`t_loop.bend`). The three ways out are named in 39.21c and none of them is a
change to this file.

### 39.21e CORRECTION: CROSSINGS ARE 1.4%, SO THE SPINE FOLD IS NOT PER-WRITE

**THE PARAGRAPH ABOVE THAT SAYS "THE HOT CHUNK CACHE ALMOST NEVER HITS" IS WRONG, AND THIS
CORRECTS IT.** A census over the 32x32 packet, counting a write whose chunk differs from the
previous write's chunk (`/tmp/cross.py`; a uop writes its own slot):

    W=16  chunks=32  crossings=31/509  (6.1%)
    W=64  chunks= 8  crossings= 7/509  (1.4%)

Slots ARE written in ascending order, so at the width this file now ships a crossing happens **seven
times per pass, not per write**. The spine fold is therefore nearly free, and the three ablations in
39.21b that each collapsed the launch to ~30 ms did NOT each remove "the cost" -- at least one of
them must have removed something other than what it was labelled, because removing a routine that
runs seven times per pass cannot save 356 ms.

**WHAT SURVIVES IS THE END-TO-END MATRIX IN 39.21d**, because every row there is a real launch with
`ops_python_exec` PASS and an exact answer, not an ablation: eight configurations, best **g = 8 at
385.87 ms**, and the two rows with a LOWER copied-cell count are both slower. **An ablation is a
hypothesis generator; only a launched configuration is evidence.** The 92%-of-cost attribution in
39.21b should be read as "the write path", not as "one specific `List.set`".

The per-write cost is `Val.gput` -- two `List.set`s, 9 copied cells at g = 8 -- and that is what the
remaining ~356 ms is spent on.

### 39.21f THE SPINE-LENGTH CURVE IS COMPLETE, AND ITS MINIMUM IS 8

The remaining free variable after 39.21d was SPINE LENGTH, which the matrix varied only incidentally.
Filled in end to end, one 32x32 launch each, all `ops_python_exec` PASS and exact:

    spine 64  (W=8,   flat chunk)      476.40 ms
    spine 32  (W=16,  4x4  chunk)      403.13 ms
    spine 16  (W=32,  4x8  chunk)      391.01 ms
    spine  8  (W=64,  8x8  chunk)      385.87 ms   <- KEPT
    spine  4  (W=128, 8x16 chunk)      419.33 ms
    spine  2  (W=256, 16x16 chunk)     436.58 ms

So the curve is a U with its minimum at **spine 8**, and it is a real trade, not noise: below 8 the
chunk has to get wider than two levels of eight can hold, and above 8 the fold gets longer. W=64 is
the width this file ships because it is where that U bottoms out.

One more census, because it rules out the last appealing explanation: the packet is
`MULACC 163 / INDEX 160 / CONST 44 / CAST 43 / SHRINK 41 / LOAD 40 / MUL 4 / PARAM 3 / STACK 2 /
RANGE 2`. Only **41 of 510 uops (8.0%)** are LOAD or STORE, so `Prog.step.vs` cold-starting the
chunk cache cannot be what the ~1M writes per launch cost either.

### 39.21g RETRACTION: EVERY ABLATION IN 39.21b AND 39.21c IS INVALID, AND WHY

**THE RANGE TRIP COUNT IS READ FROM THE ARENA.** `Prog.rng.cnt` takes its counter from
`Prog.vat.f(vs, vc, vi, Uop.slot(u))` and compares it against the limit. So an ablation that removes
arena reads does not make the interpreter cheaper -- **it makes the kernel run ONE loop iteration
instead of ~1930**. The measurement that exposed this: the read ablation reports
**`12.96x (BEND faster)` and `max|PYTHON-BEND| 1.640e+00`**, i.e. a WRONG ANSWER. The launch that
"collapsed to 30.09 ms" was answering a different, much smaller question.

That retroactively invalidates:

    "delete the spine set -> 29.62 ms"           INVALID (same mechanism)
    "delete the miss path  -> 29.72 ms"          INVALID
    "delete the chunk copy -> 29.91 ms"          INVALID
    "forcing the index to 0 -> 30.05 ms"         INVALID

and therefore every attribution built on them -- **"the value write is 92% of the interpreter" is
RETRACTED**, and so is "the spine rebuild is the other 93%". The `30 ms` that four different
ablations produced was not four independent confirmations; it was ONE artifact, seen four times.
**AN ABLATION THAT TOUCHES THE ARENA CHANGES THE CONTROL FLOW, BECAUSE THE RANGE LOOP LIVES IN THE
ARENA. THE ONLY INSTRUMENTS THAT CAN SEE INSIDE THIS INTERPRETER ARE A SAMPLER AND A LAUNCHED
CONFIGURATION.**

**WHAT SURVIVES IS EVERYTHING THAT WAS LAUNCHED.** The width matrix (39.21d) and the spine-length
curve (39.21f) are real: every row is a full launch that passed `ops_python_exec` (153 fixtures, 365
rows, 0 divergences), produced an exact answer, and reported `SAME PROGRAM`. Those rows still say
what they say -- **8x8 chunks at W=64, spine 8, 385.87 ms, against the 4x4 chunk's 403.13** -- and
the correction is to the EXPLANATION, not to the numbers.

The three censuses also survive, because they are offline and touch nothing: crossings 7/509 (1.4%)
at W=64; 1 dead write in 510; read distance p50 121, max 502.

### 39.21h A WALK IS NOT CHEAPER THAN `List.get`, MEASURED

`List.get` answers a `Maybe`, so every arena read built a `Some` -- twice, once per chunk level, over
~2M reads per launch. Replacing it with a direct recursive walk (`Val.nth`/`Val.gin`/`Val.snth`,
which return the element or `Nil{}` with no allocation) is the obvious fix and it LOST:

    16x16  56.73 -> 60.25 ms      32x32  392.20 -> 416.84 ms
    `ops_python_exec` PASS, 365 rows, 0 divergences, `max|PYTHON-BEND| 3.576e-07`

So the `Maybe` a `List.get` allocates is cheaper than a Bend-level recursive walk of the same cells.
That is a fact about this runtime -- the builtin is not just native, it is cheaper than the call
overhead the replacement adds -- and it retires the whole "remove the `Maybe`" family. Reverted.

### 39.22 WHERE THE SESSION ENDED, AND WHAT THE FLOOR IS

Everything below is a launched configuration with `ops_python_exec` PASS (153 fixtures, 365 rows, 0
divergences), `ops_bend_exec-e2e` 7 match, `--check-only` ALL PROOFS CHECK, and `stage3_parity`
SAME PROGRAM / EVERY LAUNCH IDENTICAL with an exact answer.

    stage3_parity 16x16   BEND 57.48 / 59.08 / 58.32 ms   PYTHON 70.48 / 71.15 / 69.60   (~1.21x FASTER)
    stage3_parity 32x32   BEND 388.87 / 385.20 / 380.05   PYTHON 376.16 / 375.66 / 376.93  (~0.98x)

**AGAINST THE START OF THIS SESSION: 16x16 118.45 -> ~58 ms and 32x32 1037.25 -> ~385 ms, i.e.
2.04x and 2.69x faster.** The 16x16 lane is 21% AHEAD of CPython; the 32x32 lane went 0.53x -> 0.98x
and is 2-3% behind, which is inside this machine's run-to-run spread.

**THE ARENA IS AT A MEASURED OPTIMUM.** Nine launched chunk/spine configurations put the minimum at
**8x8 chunks, width 64, a spine of 8** (39.21d, 39.21f). Everything that tried to beat it lost, and
each loss is recorded above: a 16-field record chunk (546), a 4x4 field record (557), a two-level
spine (451), a 4x4x8 chunk at width 128 (406), a pending-delta with one cons per write (696), a
Bend walk instead of `List.get` (417), and caching the inner eight slots instead of the chunk (406).
The two that reduced the number of `Uop` projections per step (ALU, INDEX) measured NEUTRAL, which
says single-field projections are not what the runtime charges for.

**AND THE SAMPLER SAYS THE REST IS THE RUNTIME, NOT THIS FILE**: on the shipped build `term_drop`
136, `span_fade` 91 and the `spin_*` allocator loops ~150 of ~380 samples, with this file's own defs
appearing only as frames. What is left is not a tuning gap in the interpreter's layout.

**THREE WAYS PAST THE FLOOR ARE NAMED AND NONE IS A CHANGE TO THIS FILE**: a scheduler that shortens
value liveness (two thirds of reads reach back more than any window), a loop that is not a Bend
recursion (a linear `Array` state was proved unable to cross it in `t_loop.bend`), or writing fewer
values (only 1 of 510 is dead).

### 39.23 THE SOURCE-SLOT LIST IS NOT THE COST EITHER, MEASURED AND REVERTED

The last structural idea with headroom above this machine's noise was to stop resolving a source
slot through a list. `Uop.sslot` is a `List<U32>` of at most three, and every read did
`Maybe.default(List.get(Uop.sslot(u), k), 0)` -- a nine-field projection, a walk, and a `Maybe`
allocation -- about 2M times per launch. `Uop` is decoded ONCE per launch, so three scalar fields
(`s0`, `s1`, `s2`, all `U32` and therefore unboxed) would cost nothing per step.

It was built, it was CORRECT (`ops_python_exec` PASS, 153 fixtures, 365 rows, 0 divergences, exact
answer), and it measured NOTHING:

    three runs each, 32x32   {383.35, 378.96, 383.71}   against HEAD {381.86, 380.67, 377.45}

Slightly worse on the mean, and reverted -- three extra fields and ~25 edited sites for no
measurable gain is exactly the trade this file must not make. **So the `Maybe` a `List.get` allocates
on a three-element list is not what this runtime charges for**, which is the same lesson as 39.21h
from the other direction: the builtin is cheap and the walk is not.

**AND THE SAMPLER ON THE SHIPPED BUILD AGREES THAT NOTHING LEFT IS OURS**: of ~200 samples,
`term_drop` 89, `span_fade` 74 and the `spin_*` allocator loops ~102, with this file's own defs
appearing only as thin frames (`Prog_run`, `Prog_ld_sb_f` 6, `List_set` 8, `Prog_index` 4). The
interpreter's shape is not what the remaining time is spent on.

### 39.24 THE ARENA'S FLOOR IS THE PERSISTENT LIST, AND THE "LINEAR STATE CANNOT CROSS THE LOOP" NOTE IS WRONG

**`ops_python.py` MUTATES AND THIS PORT COPIES, AND THAT IS THE WHOLE 3%.** The CPython lane's inner
loop assigns `values[u] = [...]` into a dict -- an O(1) store, no allocation, no copy. This port's
`Prog.vput` calls `List.set`, which copies the first `k` cells AND frees them, twice per value
written. Every "the write is the cost" measurement in 39.21-39.23 is a measurement of that asymmetry,
and no chunk shape removes it: nine launched configurations put the best at 13 copied cells
(39.21d/39.21f), and every restructuring traded those cells for a `Maybe` (39.21h, 39.23).

**A CORRECTION TO THIS TREE'S OWN RECORD, AND IT IS THE IMPORTANT PART OF THIS SECTION.** The note
in `Prog.vput`'s header and in the slop reports says a linear `Array` state "cannot cross the loop"
(one `match` per body level + no mutual recursion), citing `t_loop.bend`. **THAT IS FALSE, MEASURED
2026-11-01.** A linear `Type` record holding an `Array` threads through a fuel recursion without
difficulty; the only thing `t_loop.bend` had wrong was leaving the scalar fields affine:

    type S is Type:
      S{a: Array<U32>, n: U32}

    def step(s: S) -> S:
      match s:
        case S{a, +n}:                       # `+n` -- the ONE thing that was blocked
          S{Array.set(U32, a, 0, U32.add(n, 1)), U32.add(n, 1)}

    def loop(f: Nat, s: S) -> S:
      match f:
        case 0n: s
        case 1n+k: loop(k, step(s))

    def main() -> U32: fin(loop(100000n, S{Array.new(U32, 4n, 0), 0}))      # prints 100000

(`Array.set` is TYPE-FIRST -- `Array.set(-T: Type, a, i, v)` -- and `Array.new`'s second argument is
the DEPTH, not the count: `Array.new(U32, 6n, 0)` is 64 slots. Both cost a wrong first attempt.)

**AND THE PAYOFF IS MEASURED, ON NATIVE BINARIES, NOT INTERPRETED.** `bend <src> -o <bin>` is the
same command `ops_bend.executor()` uses; running `bend <src>` without `-o` interprets and is ~1000x
slower, which is why an earlier micro-benchmark in this file was worth nothing. 2,000,000 writes to
64 slots, three runs each, both printing the right answer:

    List.set   (this port's arena)     0.17  0.17  0.17 s
    Array.set  (what it could be)      0.00  0.00  0.00 s

At ~184 ns per interpreted step, the two `List.set`s are ~85-100 ns of it. **An `Array` arena would
therefore take a 32x32 launch from ~188 ms to roughly ~90 ms -- about 2x FASTER than the CPython
lane -- which is the objective.** The work is not a data-structure tweak: `Array` is a `Type`, so it
cannot sit in the `Data` record `Prog`, and the arena has to be threaded through every step that
reads or writes a value (`vat`, `vput`, `flush` and the ~20 dispatch arms) as a linear companion.
That is the refactor, and it is the next unit's work, not a floor.

### 39.25 THE ARRAY ARENA'S IDIOMS, VALIDATED — FOUR THINGS THAT BLOCK ON THE FIRST TRY

Before touching 75 defs, the four mechanics a linear `Array` arena needs were each proved on a
compiled binary (`bend <src> -o <bin>`; a program run without `-o` is interpreted and says nothing
about speed or even about what compiles). `Array` really does hold a `Data` record, and a linear
`Type` record really does cross the fuel recursion:

    type E is Data:                      # <-- 1. Array<Elem> where Elem is a DATA RECORD is fine
      Sc{b: U32, d: U32}
      Bf{u: U32}

    type S is Type:
      S{a: Array<E>, n: U32}

    def step(s: S) -> S:                 # <-- 2. linear state crosses the loop
      match s:
        case S{a, +n}:                   # <-- 3. `+n`: the ONLY thing t_loop.bend was missing
          S{Array.set(E, a, U32.and(n, 3), Sc{n, 0}), U32.add(n, 1)}

    def take(ab: Array<E> & E) -> U32:   # <-- 4. a READ is a pair, and it must be DESTRUCTURED IN A
      match ab:                          #        DEF. `match Array.get(...)` is refused ("cannot
        case (a2, v): bits(v)            #        scrutinize a computed value") and so is binding it
                                         #        to a local and matching THAT first.
    def fin(s: S) -> U32:
      match s:
        case S{a, n}: take(Array.get(E, a, 2))     # prints 6 on 7 writes to a 4-slot array

Also: `Array.set` is TYPE-FIRST (`Array.set(-T, a, i, v)`), `Array.new`'s second argument is the
DEPTH not the count (`Array.new(U32, 6n, 0)` = 64 slots; `64n` means 2^64 and dies), and record
construction is POSITIONAL (`Sc{n, 0}`, never `Sc{b: n}`).

**So the refactor's shape is fixed**: `Prog` drops `vs`/`vc`/`vi` and becomes
`Prog{st, gd, ms, mk, pc, bad, dead, un}` (still `Data`, so the 105 `+p: Prog` sites are untouched);
`Array<Elem>` is threaded as a linear companion through the 75 defs that name `vs`, `vc` or `vi`, and
every one of them returns `Prog & Array<Elem>`. The two `List.set`s in `Prog.vput` become one
`Array.set`, which is the ~85-100 ns of a ~184 ns step that 39.24 measured away.

The refactor itself is NOT started: it is 75 defs and ~25 call sites that must be rewritten in one
piece, because a half-converted arena does not compile. An isolated worktree is prepared for it
(`arena-array`, with `bin/bend` and `references/` linked so it builds) so the main tree can stay green
throughout; the main tree is at `11282e359` with `ALL PROOFS CHECK`, `ops_python_exec` 153/365/0 and
`ops_bend_exec-e2e` 7 match.
