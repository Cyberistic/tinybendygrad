MNIST TRAINS IN THE BROWSER: one step replayed on the adapter leaves 47 of 47 TENSOR buffers BIT-EXACT

    node .agents/slop/browser/train-gate.mjs
    PASS -- one MNIST training step, replayed on the adapter, leaves 47 of 47
    TENSOR buffers (weights, gradients, moments) BIT-EXACT against CPython,
    180782 words compared

THE STEP IS CPYTHON's AND THE REPLAY IS THE BROWSER's, AND THE PAGE NEVER SEES
THE ORACLE. `trace_train.py` captures ONE training step (forward +
`sparse_categorical_crossentropy` + the gradients + the SGD update) out of
`tinygrad/engine/realize.py`'s `exec_kernel`: 90 launches, the WGSL
`tinygrad/renderer/wgsl.py` emitted for the SAME ast, the binding order, the
geometry, and every buffer's before/after contents. `train-gate.mjs` replays
those 90 launches on a real adapter (`apple/metal-3`, headless Chrome) and diffs
the result against `train-oracle.json`, which CPython wrote BEFORE any browser
ran.

⇒ AND THE FORWARD HALF WAS ALREADY BIT-EXACT, AND IS STILL VERIFIED TODAY:
`examples/webgpu/mnist` reads 17 launches and 10/10 logits exactly.

⇒ ⇒ ⇒ AND THE TRACER THAT PRODUCED BOTH WAS **STALE AND DEAD**, WHICH IS THE
REAL FINDING OF THIS SESSION: nothing read it, so nothing noticed.
`xd2/trace_forward.py` now raises `AttributeError: 'Buffer' object has no
attribute 'size'`. Per the tree's own rule (a script others execute is shared
state; write a NEW path), the fix is `.agents/slop/browser/trace_common.py`,
and it carries FOUR measured re-points plus one measured wall:

  Buffer.size -> Buffer.nbytes        (`device.py:116` sets only
                                       `device, nbytes, offset, base`)
  Buffer.dtype -> the CALL's uop        (`Buffer` has no dtype at all now)
  ProgramInfo.vals -> `kernel_params`   (the 2026-10-20 re-vendor dropped
                                       `vals`; upstream `a6addc2d4`)
  ProgramInfo.function_name -> `ast.arg.name`

**⇒ AND THE `vals` ONE WAS A MEASURED BUG AND NOT A MIGRATION**: dropping them
built bind groups with too few entries, so **every kernel taking a scalar did
not run and its output kept its fill** -- 26 of 50 buffers agreed and the rest
held `0` or `1.0f`.

**⇒ AND `DEV=CPU` BEFORE TINYGRAD IMPORTS IS LOAD-BEARING.** With no `DEV` the
default device on darwin is `METAL`, so the traced ast was a METAL kernel and
`to_program(..., WGSLRenderer)` died with `RuntimeError: long decomposition of
variable None unsupported`. **⇒ AND THE CAUSE WAS TWO u64 PARAMs NAMED `mtl_cb`
AND `mtl_enc`** (`runtime/ops_metal.py:104` mints exactly those for a command
buffer and an encoder) -- so the "u64 problem" was never WGSL's, it was a METAL
kernel handed to a WGSL renderer. **A DECOMPOSITION ERROR IS A SYMPTOM AND THE
PARAM NAMES WERE THE EVIDENCE.**

**⇒ AND `DMC=1` IS REQUIRED FOR THE BACKWARD PASS, MEASURED**: one of the 90
launches fails to render with `memory coalescing does not support gated
loads/stores`, and it is the cross-entropy kernel. `DMC` is tinygrad's own
switch ("1=skip memory coalescing pass"): `DMC=0` renders 89 of 90, `DMC=1`
renders 90 of 90. Honest rather than convenient -- the traced ast is the CPU's,
and the CPU does not coalesce either.

**⇒ AND THE SNAPSHOT FILTER WAS `f32` AND HAD TO BECOME `w32`.** MEASURED: the
training step's LABEL is an i32 buffer, so it was never uploaded, the
cross-entropy gate `-1 < label < 10` read a different element, and the loss came
back `0` where CPython had `2.7735066413879395`. **⇒ A FILTER THAT MEANS "32-BIT
WORDS" MUST NOT BE SPELLED "f32".**

**⇒ AND WEBGPU REFUSES TINYGRAD's OWN WGSL SHAPE, TWICE, AND BOTH ARE MEASURED
REFUSALS.** `error scopes` were absent from the first version of the page, so a
refused dispatch read as a number that never changed:
  * `Writable storage buffer binding aliasing found` -- tinygrad binds ONE buffer
    at several positions (`b10` at [0,1,2]) and declares all of them
    `var<storage,read_write>`. **⇒ FIXED BY COLLAPSING THE ALIAS TO ONE BINDING
    and rewriting the body to name the survivor**, which is also the only
    spelling that lets an in-place kernel read its own writes.
  * `The buffer type in the shader (ReadOnlyStorage) is not compatible with the
    type in the layout (Storage)` -- the layout and the shader are ONE decision,
    and a non-output binding is `var<storage,read>` + `read-only-storage`.

AND ONE THING IS NAMED AND NOT FIXED. The loss is a 1-word scalar and it
differs: the GPU reads `b23` as `2.0951609` where the kernel needs `1.5072439`,
and `b23`'s FINAL contents agree on both sides. **⇒ AND THIS GATE'S FIRST
EXPLANATION FOR IT WAS THE READ-SIDE COPY, AND THAT EXPLANATION IS RETRACTED
HERE BECAUSE MEASUREMENT DISPROVED IT: the copy was removed, the alias
collapsed, and the value did not move (1081917952 before and after).** ⇒ The
next instrument is a per-launch ladder on `b23`, which is what the forward
page's own `snapshot` mode exists for. **⇒ AND IT IS NOT A WEIGHT: all 47 tensor
buffers are bit-exact.**

ALSO IN THIS COMMIT, AND THEY ARE THE ANSWER TO "HOW FAR ARE WE", CORRECTED:
`.agents/slop/browser/arenas.bend` settles an inconsistency my own earlier
report left open, and it proves my own D2 attribution WRONG. The rangeified
graph is 22 nodes with `STORE(INDEX,REDUCE)`; the scheduled one is 10 nodes with
`STORE(INDEX,PARAM)` -- **and the two readings are CONSISTENT, in the same
arena, so the arithmetic is genuinely LOST.** `d1probe.bend` shows why:

    D1_a_store_before=STORE(INDEX,REDUCE)  store_after_replace=STORE(INDEX,PARAM)
    D1_b_call_before=CALL(STORE,PARAM)     call_after_replace=CALL(STORE,PARAM)

`replace` is CORRECT and only its SUBJECT was wrong. Upstream
(`__init__.py:68-71`) asserts `k.op is Ops.CALL` before it; Bend has no `raise`,
so the assert became nothing and the CALL-shadows rewrite ran on a STORE,
replacing its value with a buffer-uop. **⇒ SO D2 IS D1's CASCADE AND NOT A
`kuconv` FIELD BUG, AND FIXING `split_kernels` FIXES BOTH.**
