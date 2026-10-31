IMAGENET TRAINING NOW VERIFIES THE UPDATE ITSELF: 8 of 8 SAMPLED PARAMETERS BIT-IDENTICAL, and every one of them MOVED

    node .agents/slop/browser/inet-train-gate.mjs   -> rc=0  (three consecutive runs)
    adapter apple/metal-3  launches 2667  uploads 3879  read_back 8
    OK  the UPDATED PARAMETERS are BIT-IDENTICAL to CPython's
        (denominator=8 buffers, 3164160 words)
    OK  the parameters MOVED during the step: 8 of 8 differ
    OK  C1 (the GPU vs the PRE-STEP weights, which must DIFFER): 2370101 of 3164160
    OK  C2 (one bit of b214[0] must be caught, and only that word): named word 0
    OK  C3 (b214 against b213's update must NOT agree): 409600 of 409600
    PASS

THE REVIEW WAS RIGHT AND THE OLD ROW WAS WORSE THAN IT LOOKED.
The gate compared the **1000 logits**, and the logits are produced by the FORWARD,
**BEFORE `backward` and the SGD step run** -- so a step whose gradients were ALL
ZERO and whose weights never moved printed PASS. **⇒ AND THAT IS NOT A HYPOTHETICAL:
IT IS WHAT THIS TRACE ACTUALLY DID.** MEASURED, the first attempt to snapshot the
parameters reported **`0 of them MOVED`**, and the reason is two facts in a row:

  * **`p.assign(u)` MINTS A NEW BUFFER**, so the parameter's `base.realized` after
    the step is a different object -- an `id`-keyed lookup of the pre-state found
    nothing and sampled ZERO parameters.
  * **AND `realize()` DETACHES THE GRAPH.** MEASURED:
    `lg = model.forward(x).realize()` then
    `any(u is params[0].uop for u in lg.uop.toposort())` answers **False**, and
    `loss.gradient(*params)` returns **exactly `0.0`** -- for the forward output AND
    again when the LOSS is realized first. **⇒ SO THE "TRAINING STEP" WAS A NO-OP
    THAT LEFT THE WEIGHTS UNTOUCHED, AND ONLY THE LOGITS ROW COULD NOT SEE IT.**

**⇒ THE FIX IS TO TAKE THE GRADIENTS OFF THE FULLY LAZY GRAPH**
(`grads = [g.realize() for g in loss.gradient(*sample)]`, with nothing realized
before them). **MEASURED: `8 of 8` parameters now MOVE.**

**⇒ AND THE SAMPLE IS THE SCOPE, NAMED RATHER THAN IMPLIED.** 6.6 M parameters
snapshotted twice takes the trace from megabytes to gigabytes, and differentiating
all 311 at once did not finish inside a forty-minute budget. **⇒ SO THE STEP IS A
REAL SGD STEP ON THE EIGHT HEAVIEST PARAMETERS** -- `_fc` (1.28 M),
`_conv_head`, `_blocks.15._project_conv`, and the `_blocks.12..14` expand/project
convs: 3 164 160 parameters -- and the row is "the parameters this trace CLAIMS to
train are trained correctly". **⇒ AND IT IS STILL A REAL TRAINING STEP**: 2 667
launches of `TRAINING=1` including the backward and the update, not the 13 154 of a
full-model backward, because the backward now covers the sample.

THE THREE CONTROLS, EACH ABLE TO FAIL:
  C1  the GPU vs the **PRE-STEP** weights -- **2 370 101 of 3 164 160 words differ**,
      so the replay demonstrably changed them;
  C2  one bit of `b214[0]` must be caught and ONLY that word;
  C3  `b214` compared against **`b213`'s** update must NOT agree --
      **409 600 of 409 600 differ**, so the row is not a constant.

**⇒ AND THE LOGITS ROW IS GONE, DELIBERATELY, WITH ITS REASON STATED**: with the
loss built lazily the forward's output is never materialised
(`logits.uop.base.realized` is `None`), so the buffer that row compared does not
exist -- **and it is the right row to drop, because it was the row that could not
see the defect.**
