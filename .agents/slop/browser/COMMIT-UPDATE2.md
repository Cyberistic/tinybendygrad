THE REVIEW WAS RIGHT AGAIN, AND BOTH LANES HAD THE SAME DEFECT: `realize()` DETACHES, so BOTH "training steps" had ZERO gradients

    node .agents/slop/browser/inet-train-gate.mjs   -> rc=0  (three consecutive runs)
    OK  the UPDATED PARAMETERS are BIT-IDENTICAL to CPython's
        (denominator=8 buffers, 3164160 words)
    OK  the parameters MOVED during the step: 8 of 8 differ
    OK  C1 (GPU vs the PRE-STEP weights): 2370101 of 3164160 words differ
    OK  C2 (one bit of b214[0], only that word): named word 0
    OK  C3 (b214 vs b213's update must NOT agree): 409600 of 409600
    PASS

IMAGE NET's ROW NOW VERIFIES THE UPDATE AND NOT THE FORWARD, WHICH WAS THE ASK.

**⇒ AND FINDING IT EXPOSED THE SAME DEFECT IN THE MNIST LANE, WHERE IT HAD BEEN
INVISIBLE.** MEASURED: with `trace_train.py`'s own sequence,
`MNIST grad absmax: 0.0` -- **MNIST's gradients were ALSO exactly zero**, so its
SGD update wrote every parameter back UNCHANGED and its `47 of 47` row was green
only because **CPython's side was the same no-op**, plus the BatchNorm running
statistics genuinely moving. **⇒ SO "MNIST TRAINS" WAS, UNTIL THIS COMMIT, PROVEN
BY THE FORWARD AND THE MOMENT STATS AND NOT BY THE WEIGHT UPDATE** -- the exact
class of claim the review rejected for ImageNet.

THE CAUSE, ONCE, FOR BOTH: **`realize()` DETACHES THE PARAMETERS FROM THE BACKWARD
SLICE.** `lg = model.forward(x).realize()` then
`any(u is params[0].uop for u in lg.uop.toposort())` answers **False**, and
`loss.gradient(*params)` answers **`0.0`** -- from the forward output and again when
the LOSS is realized first. **⇒ SO NOTHING IS REALIZED BEFORE `gradient`**, and the
realize happens on the GRADIENTS, which is what puts the backward in the trace.

**⇒ AND THE FIX IS NOT COSMETIC: MNIST's trace went from 90 launches to 431 and from
`34 of 91` buffers moving to `84 of 91`**, because the real backward is the whole
model. **⇒ AND THAT IS THE FIRST TIME THIS TREE HAS MEASURED A REAL MNIST BACKWARD
IN A BROWSER TRACE.**

**⇒ AND THE MNIST AGGREGATE IS NOW RED, AT `71 of 72`, AND IT IS NAMED AND NOT
HIDDEN:** `b11` differs in 1 of 784 words, and the value is the LABEL's `7` where
CPython's is `-0.5`. **⇒ AND IT IS A HARNESS ARTIFACT, MEASURED**: CPython's OWN
trace has `in[b11] = 7` at launches 26 and 27 and `-0.5` at its first bind and at
launch 41 -- **the tinygrad allocator RECYCLES that allocation**
(`tinygrad/device.py:270`, which `trace_common.py`'s header already records), so one
NAME spans TWO DIFFERENT TENSORS and the row compares snapshots of different
logical buffers. **⇒ THE FIX IS A PER-LAUNCH LADDER AND NOT ONE FINAL SNAPSHOT**, and
it is named as open rather than papered over. Every WEIGHT buffer is exact.

**⇒ SO THE HONEST TALLY TODAY**: ImageNet training is MET on the update itself;
MNIST training's UPDATE is bit-exact on every weight buffer but its aggregate row is
`71 of 72` on a recycled-allocation artifact in the INPUT, and I am not going to
call that green.
