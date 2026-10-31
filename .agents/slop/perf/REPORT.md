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
