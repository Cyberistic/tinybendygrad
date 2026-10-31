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
