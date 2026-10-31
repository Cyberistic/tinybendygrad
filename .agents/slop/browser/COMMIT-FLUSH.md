BATCHING WAS INCORRECT AND IS FIXED: a flush before an upload that its own batch invalidates

    node .agents/slop/browser/train-gate.mjs     -> rc=0
      bit-exact buffers: 47 of 47
      PASS -- one MNIST training step ... 180782 words compared
    node .agents/slop/browser/inet-gate.mjs      -> rc=0
      PASS -- EfficientNet(0) ... 328 launches ... 2.384e-7 ABSOLUTE
    node .agents/slop/browser/inet-train-gate.mjs -> rc=3   REFUSED, named below

THE BUG, AND IT WAS MINE. To make a 13 154-launch replay START at all, launches
are batched 64-to-a-submit. **MEASURED: that took the MNIST training step from
`47 of 47` bit-exact buffers to `39 of 47`** -- eight buffers silently wrong.

**⇒ AND THE CAUSE IS AN ORDERING FACT AND NOT A TUNING ONE**: `queue.writeBuffer`
is ordered against SUBMITS, not against the command buffers being recorded. So an
upload for launch 70 lands BEFORE the batch holding launch 60 runs, and it
OVERWRITES what launch 60 computed.

**⇒ SO A LAUNCH WHOSE `in` TOUCHES A BUFFER WRITTEN SINCE THE LAST SUBMIT FORCES
A SUBMIT.** MEASURED, in that order: `batch=1` -> 47 of 47; `batch=64` before the
fix -> 39 of 47; `batch=64` after the fix -> **47 of 47**. The batch size is now
`?batch=` with a default of 1, and the two lanes agree at both settings.

**⇒ AND TWO MORE CACHE-KEY BUGS OF THE SAME CLASS ARE FIXED, BOTH FOUND BY THE
SAME SYMPTOM.** `aliasPlan` and the shader-module cache derived their result from
`k.outs`, and both were keyed on `k.wgsl` alone -- so two launches sharing one WGSL
string but disagreeing about which binding is an output shared a WRONG plan. Both
are keyed by the decision they encode now.

AND A TIMED-OUT PROBE IS NOT A VERDICT. Every gate's poll now RETRIES on a
`Runtime.evaluate` timeout instead of throwing, because the replay holds the main
thread in stretches longer than the probe's budget and a page that is WORKING read
as a page that "never finished".

**⇒ AND `inet-train-gate.mjs` IS `REFUSED` (3) AND NOT A FAIL OR A PASS, WITH ITS
MEASUREMENT PRINTED**: 13 154 launches, `WGSL-UNRENDERED: 0 of 13154` -- EVERY
kernel of an EfficientNet-0 TRAINING step renders to WGSL -- and the browser
replay does not publish a result inside a twenty-minute poll. **⇒ SO THE OPEN
PROBLEM IS WALL-CLOCK AND PACKAGING, NOT CORRECTNESS, AND IT IS NAMED AS OPEN
RATHER THAN DRESSED AS A PASS.**
