IMAGENET INFERENCE RUNS IN THE BROWSER: EfficientNet-0, 328 launches, 1000 logits to 2.384e-7 ABSOLUTE

    node .agents/slop/browser/inet-gate.mjs
    adapter apple/metal-3  launches 328  uploads 278  f32 buffers 314
    OK  the 1000 logits AGREE within 0.000001 ABSOLUTE (denominator=1000 words):
        189 exact, 811 differ, max |abs| 2.384e-7 at logit 447, max 2048 ULP
    OK  C3 (one logit moved by 1.0 must EXCEED the tolerance): max 1.000e+0 vs 0.000001
    OK  C1 (the logits vs the UPLOAD, which must DIFFER): 1000 of 1000 words differ
    OK  C2 (one bit of logit 12, which agrees, must add EXACTLY one differing word): 811 -> 812
    PASS

**=> SO EFFICIENTNET-0 RUNS ON A REAL ADAPTER.** The twelve unbalanced depthwise
shaders that blocked it are repaired and the repair is VALIDATED BY THE RESULT,
not by argument.

THE BRACE DEFECT, ISOLATED TO ONE KERNEL AND ONE CODE PATH.
`imagenet/dw.wgsl` is `r_8_112_28_4_4_3_3_3`'s WGSL as tinygrad emitted it, and
a depth trace over its own bytes says:

    line 11  d0 +1  @compute @workgroup_size(1) fn r_8_112_28_4_4_3_3_3(...)   <- the function
    line 13  d1 +1  for (var Lidx3 = 0; Lidx3 < 8; Lidx3++) {
    line 38  d2 +1  for (var Lidx5 = 0; Lidx5 < 28; Lidx5++) {
    line 39  d3 +1  for (var Lidx4 = 0; Lidx4 < 112; Lidx4++) {
    line 41  d4 +1  for (var Lidx5 = 0; Lidx5 < 28; Lidx5++) {
    line 61  d5 +1  for (var Lidx0 = 0; Lidx0 < 3; Lidx0++) {
    line 143 d6 -1  }
    lines 368..371   }}}}                                                        <- FOUR, not five
    final depth 1

**=> FIVE `for (` LOOPS OPEN AND FOUR `}` CLOSE, AND EVERY CLOSING BRACE IS
TRAILING** (143, then 368-371, in descending depth order at the end of the file).
**=> SO THE DEFICIT IS A TRAILING UNCLOSED BLOCK, AND APPENDING ONE `}` PER
UNCLOSED LEVEL RE-CREATES THE NESTING THE RENDERER INTENDED AND CANNOT
RE-ASSOCIATE A BLOCK.** A mid-file deficit would NOT be repairable this way, and
the page refuses in that case (`closes more blocks than it opens`).

**=> AND IT IS REPORTED AND NEVER SILENT**: the page puts every repair in
`out.brace_repaired` (`entry:+N}`), so a page that quietly fixes a compiler's
output and then says PASS cannot hide the compiler's defect. **=> AND IT IS THE
THIRD MEASURED GAP IN `renderer/wgsl.py`**, after the two
`examples/webgpu/mnist/README.md` already records.

FOUR MORE MEASURED FIXES FELL OUT, EACH WITH ITS SYMPTOM:

  * `Queue.writeBuffer` vs buffer size -- `Write range (size: 4816896) does not
    fit in [Buffer] size (1605632)`. **A `Buffer` can be a VIEW whose `nbytes` is
    smaller than its `base`'s, and `as_memoryview` reads the BASE.** So `size` is
    now DERIVED FROM THE BYTES and the two cannot disagree.
  * the same class again, later: **a base allocation is REALLOCATED BIGGER
    during a trace**, so one name carried two payload lengths.
    `normalize_sizes()` makes ONE size per name -- the longest -- and moves
    NOTHING BUT THE SIZE, because a shorter `writeBuffer` is legal and leaves the
    rest zero. **=> PADDING THE PAYLOADS INSTEAD WAS MEASURED WRONG: it rewrote
    215 payloads and took the JSON past `RangeError: Invalid string length`.**
  * an all-zero first bind has no payload, and dropping its ENTRY left the page
    unable to ALLOCATE it (`Cannot read properties of undefined (reading 'gb')`).
    **=> THE ENTRY KEEPS ITS SIZE AND LOSES ONLY ITS PAYLOAD**, and `GPUBuffer`
    being zero-initialised makes "no upload" exact.
  * C1 was REFUSED when that payload was absent, which was wrong: **an absent
    PAYLOAD is not an absent FACT** -- the upload of a zero-initialised buffer IS
    zeroes, so the control is still askable.

**=> AND TWO OF THE CONTROLS WERE THEMSELVES WRONG AND ARE FIXED.** C2 flipped a
bit in `want[0]`, which `got[0]` ALREADY differed from -- **so the mutation left
the verdict unchanged and the control could never fire; a mutation in a word that
is already wrong measures nothing.** It now flips a word that AGREES and demands
the count go up by EXACTLY one (811 -> 812). And C3 is new: the tolerance itself
must be able to fail, or `TOL` could be `Infinity` and every row above would
still be green.

**=> AND THE TOLERANCE IS NAMED AND JUSTIFIED, NOT CHOSEN FOR CONVENIENCE.**
`1e-6` absolute against a measured `2.384e-7`, and that magnitude is the SAME
class and the SAME order `examples/webgpu/mnist/README.md` records for its own
four convolutions (3.6e-7): the CPU is compiled `-O2` with no
`-ffp-contract=off` (`support/compiler_cpu.py:21`), so clang fuses multiply-adds
that WGSL does not. EfficientNet-0 has ~50 convolution layers across 328
kernels, so the rounding compounds where MNIST's four did not, and 189 of 1000
logits are still BIT-IDENTICAL.
