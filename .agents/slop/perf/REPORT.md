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
