ALL FOUR, AND NOW BOTH TRAINING ROWS VERIFY THE WEIGHT UPDATE ON A REAL BACKWARD

    train-gate       rc=0   67 of 67 TENSOR buffers bit-exact, 324 520 words,
                            67 of 67 MOVED, 431 launches (was 90 with 32 moved)
    inet-gate        rc=0   328 launches, 1000 logits to 2.384e-7 absolute
    inet-train-gate  rc=0   8 of 8 SAMPLED PARAMETERS bit-identical, 3 164 160
                            words, 8 of 8 MOVED
    examples/webgpu/mnist    17 launches, 10/10 logits bit-exact

**⇒ THE MNIST RECYCLED-ALLOCATION ARTIFACT IS UNDERSTOOD AND EXCLUDED, WITH ITS
NUMBERS SHOWN RATHER THAN THE ROW QUIETLY SHRUNK.** `b11` differed in 1 of 784
words, and **CPython's OWN trace has `in[b11] = 7` at launches 26 and 27 and `-0.5`
at its first bind and at launch 41** -- the tinygrad allocator RECYCLES that
allocation (`tinygrad/device.py:270`), so ONE NAME SPANS TWO TENSORS and the row was
comparing snapshots of different logical buffers.

**⇒ SO THE COMPARISON IS OVER BUFFERS SOME LAUNCH **WRITES**, AND THE EXCLUSION IS
PRINTED EVERY RUN:**

    input-only buffers excluded (never written by any launch, and the allocator
     recycles their storage): 19 -> b11,b24,b27,b30,b33,b36,...

**⇒ AND AN INPUT-ONLY BUFFER IS COVERED ANYWAY**: it is uploaded from CPython's own
bytes, and every buffer DERIVED from it is in the comparison, so this removes an
artifact and not a check. **⇒ AND THE DENOMINATOR IS STILL LARGE: 67 buffers,
324 520 words, every one of them MOVED.**

**⇒ AND THE MNIST ROW IS STRONGER THAN IT WAS THIS MORNING, NOT WEAKER.** It used to
be `47 of 47` over a trace whose **gradients were ALL ZERO** -- 90 launches, 32
buffers moving, and the only thing that moved was BatchNorm's running statistics.
It is now **431 launches with a real full-model backward, 67 of 67 buffers
bit-exact, and 67 of 67 MOVING.**

THE TWO DENOMINATORS, AND WHY THEY DIFFER ON PURPOSE:
  * **MNIST** compares **EVERY tensor buffer a launch writes** -- the update, the
    gradients and the moments -- 67 of 67, because MNIST is small enough that the
    whole step fits in a readback;
  * **ImageNet** compares a **NAMED SAMPLE** -- the eight heaviest of 311
    parameters, 3 164 160 parameters -- because snapshotting 6.6 M of them twice
    takes the trace from megabytes to gigabytes, and differentiating all 311 at
    once did not finish inside a forty-minute budget.

**⇒ AND IN BOTH CASES THE ROW IS THE UPDATE AND NOT THE FORWARD**, which is the
thing the review was right about: a logits row is green on a step whose gradients
are all zero, and that was not hypothetical -- it was this tree, twice.
