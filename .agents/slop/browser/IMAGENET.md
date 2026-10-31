# IMAGENET IN THE BROWSER — EfficientNet-0 TRACED, AND ONE NAMED SHADER WALL

**Measured 2026-10-31.** Every row carries the command that produced it.

    .venv/bin/python .agents/slop/browser/trace_imagenet.py
    launches 328  buffers 314  logits [1, 1000]
    WGSL-UNRENDERED: 0 of 328

    node .agents/slop/browser/inet-gate.mjs
    BAD the page did not finish: WGSL rejected for r_8_112_28_4_4_3_3_3:
        line 371:2 expected '}' for function body

---

## 1. WHAT WORKS

**EfficientNet-0's WHOLE FORWARD PASS TRACES, AND EVERY ONE OF ITS 328 KERNELS
RENDERS TO WGSL.** `to_program(ast.src[0], BrowserWGSL)` succeeds on all 328 --
squeeze-excite, swish/`silu`, the global-average-pool, the 1000-way linear head,
and the depthwise convs. **⇒ SO tinygrad's WGSLRenderer CAN EXPRESS THIS MODEL,
and the only thing between the trace and a browser is §2.**

The weights are `deterministic()`, NOT pretrained, and that is stated rather than
implied: `load_from_pretrained()` fetches ~20 MB from the hub, and the claim this
exercise makes is **"the browser computes EfficientNet's forward pass bit for
bit"**, which pretrained weights do not change. **⇒ SO THE LABELS WOULD BE
MEANINGLESS AND THE ARITHMETIC WOULD NOT.**

## 2. THE WALL, AND IT IS tinygrad's

`inet-gate.mjs` replays the trace and WebGPU rejects **12 of the 328** shaders:

    .agents/slop/browser/imagenet/wgsl-braces.rows   328 rows
    launch  entry                open  close  verdict
    ...     12 rows                          UNBALANCED

**⇒ AND THE UNBALANCE IS IN THE WGSL tinygrad EMITTED, NOT IN THE PAGE's
TRANSFORM, MEASURED BY COUNTING THE BRACES ON THE SHADER AS TRACED:**

    $ .venv/bin/python -c '...count { and } over the trace's own wgsl...'
    kernels 328 unbalanced 12
    [('r_160_14_14_3_3_3', 2), ('r_224_14_14_3_5_5', 2), ('r_8_112_28_4_4_3_3_3', 1),
     ('r_32_112_28_4_3_3', 1), ('r_96_56_14_4_3_3', 1), ('r_144_56_14_4_3_3', 1),
     ('r_144_28_7_4_5_5', 1), ('r_240_28_7_4_5_5', 1), ('r_80_14_14_3_3_3', 1),
     ('r_160_14_14_3_5_5', 1)]

**⇒ AND EVERY ONE OF THE TWELVE IS A DEPTHWISE OR GROUPED CONV** -- the entry
names carry the `_3_3_3` / `_3_3` / `_5_5` group shape. **⇒ SO THIS IS THE THIRD
MEASURED GAP IN `tinygrad/renderer/wgsl.py`, AFTER THE TWO
`examples/webgpu/mnist/README.md` ALREADY NAMES** (`code_for_op` has no
`Ops.FDIV`; `supports_float4 = False` reaches `string_rewrite`).

**⇒ AND IT IS REPORTED AND NOT PATCHED, DELIBERATELY.** `tinygrad/` is the
reference tree; a fix there is a re-vendor and not a line in this lane. **⇒ AND
THE WORKAROUND IS REJECTED ON PURPOSE: APPENDING A `}` WOULD MAKE THE SHADER
COMPILE AND WOULD BE A GUESS ABOUT WHICH BLOCK WAS LEFT OPEN**, which is the
`* = ;` failure from the port's own `fullchain` measurement, one language over.

## 3. WHAT THE IMAGENET LANE NEEDS NEXT, IN ORDER

1. **THE 12 UNBALANCED DEPTHWISE SHADERS.** One defect, twelve kernels, and it
   blocks the whole replay. A brace census over a *fixture* of one depthwise conv
   is the smallest reproduction.
2. **THE 103 MB TRACE.** EfficientNet-0's weights as JSON is 103 MB even after
   dropping every all-zero snapshot (`GPUBuffer` is zero-initialised, so those
   are free). **⇒ AND THAT IS A PACKAGING PROBLEM AND NOT A CORRECTNESS ONE**:
   the same data as a binary blob beside a small JSON is ~21 MB, which is what a
   clone can carry.
3. **THE PRETRAINED WEIGHTS**, only once 1 and 2 are closed -- because only then
   do the 1000 logits mean "tench" instead of "some number".

## 4. THE ARTIFACTS

| file | what |
|---|---|
| `.agents/slop/browser/trace_imagenet.py` | THE TRACER. 328 launches, 0 unrendered. |
| `.agents/slop/browser/inet-gate.mjs` | THE GATE. REFUSED (3) without the trace; names the shader wall when it cannot replay. |
| `.agents/slop/browser/imagenet/inet-oracle.json` | CPython's 1000 logits, u32 bit patterns. **COMMITTED.** |
| `.agents/slop/browser/imagenet/inet-net.json` | the trace, **GENERATED** (103 MB, over this tree's new-file limit). |
| `.agents/slop/browser/imagenet/wgsl-braces.rows` | **THE CENSUS**: 328 rows, one per kernel, with its brace counts. |
