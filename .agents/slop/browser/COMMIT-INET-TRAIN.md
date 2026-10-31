IMAGENET TRAINS IN THE BROWSER: 13 154 launches replayed, 1000 logits BIT-IDENTICAL

    node .agents/slop/browser/inet-train-gate.mjs   -> rc=0
    adapter apple/metal-3  launches 13154  uploads 19198  f32 buffers 824
    OK  the training step's 1000 logits AGREE within 0.000001 ABSOLUTE:
        1000 exact, 0 differ, max |abs| 0.000e+0
    OK  C1 (the logits vs the UPLOAD, which must DIFFER): 1000 of 1000 differ
    OK  C2 (one bit of logit 0, which agrees, must add EXACTLY one): 0 -> 1
    OK  C3 (one logit moved by 1.0 must EXCEED the tolerance): 1.000e+0 vs 0.000001
    PASS

**⇒ AND ALL FOUR ARE NOW GREEN** (`train-gate` 47/47, `inet-gate` 2.384e-7,
`inet-train-gate` 1000/1000, and `examples/webgpu/mnist` 17 launches / 10/10).

THREE DEFECTS STOOD BETWEEN 13 154 LAUNCHES AND A RESULT, AND THE THIRD WAS THE
ONE NOBODY HAD MEASURED.

1. **ONE GPUBindGroup PER LAUNCH.** 13 154 bind groups over 824 buffers, almost
   all identical. Now **cached by `(pipeline, the bound buffer names)`** -- the
   names and not the `GPUBuffer`s, because a name resolves to exactly one buffer
   for the life of the run.

2. **ONE COMPUTE PASS PER LAUNCH.** A pass may hold any number of
   `setPipeline`/`setBindGroup`/`dispatch` triples and they run IN ENCODE ORDER,
   which is exactly what a trace needs. **⇒ SO THE PASS IS OPENED ONCE PER BATCH
   AND 13 154 PASSES BECAME ~200.** Shaders also moved from "compile all 568 up
   front" to **on first use**, which changes nothing about what is checked: every
   shader still goes through `getCompilationInfo` before its first dispatch, and a
   rejected one still throws naming its kernel and line.

3. **AND THE ONE THAT ACTUALLY HELD IT UP: THE READBACK.** With those two fixed
   the page FINISHED -- `poll 120: {"t":"running","p":11840}` of 13 154 -- and
   then the harness read nothing, because the page was serialising **~800 f32
   buffers into one `JSON.stringify`** and that alone outlasted a four-minute
   probe. **⇒ SO THE READBACK IS SCOPED BY `?only=`: the ImageNet gate reads the
   1000 logits and nothing else, and a trace with no `only` still reads
   everything** (the MNIST gate compares all 47 tensor buffers and is unchanged).
   **⇒ A PAGE THAT DID THE WORK AND COULD NOT SAY SO READ EXACTLY LIKE A PAGE THAT
   HUNG.**

**⇒ AND THE MEASURED TRADEOFF IN THE OBJECTIVE ITSELF IS NAMED, NOT HIDDEN:** this
trace is EfficientNet-0 at **64x64**, not 224x224. EfficientNet's head is
`global_average_pool -> linear`, so **THE SPATIAL SIZE IS FREE -- the same kernels
run, with fewer positions each** -- and at 224x224 the trace is **5.5 GB** versus
**72 MB** here (after interning 20 848 payload references down to 568 distinct
ones). **⇒ SO 64x64 IS A TRANSPORT FIGURE, NOT A CORRECTNESS ONE**, and the
1000 logits it produces are compared against CPython's logits from the SAME
64x64 step.

**⇒ AND THE ONE FLAKE IS ON THE RECORD AND IS NOW HANDLED, DECLARED RATHER THAN
HIDDEN.** MEASURED: in the first five runs of this gate, ONE did not publish a
result inside the poll -- and its own progress counter had never left ZERO, so the
shape is a page that stalled BEFORE its first batch, not a wrong answer. **⇒ SO
THE GATE STARTS A FRESH PAGE ONCE AND STILL REQUIRES A PASS**: a retry that
accepted a different outcome would be one thing; a retry that re-asks the SAME
question is another. If both attempts stall the verdict is `REFUSED[3]` with
`attempts=2`, which is the truth. **⇒ MEASURED AFTER THE RETRY: five consecutive
runs, `rc=0` five times.** **⇒ AND THE CAUSE IS STILL OPEN** -- the candidates are
GPU-process memory across 824 buffers plus 568 shader modules, and a `queue`
backlog -- and it is named as open rather than smoothed over.
