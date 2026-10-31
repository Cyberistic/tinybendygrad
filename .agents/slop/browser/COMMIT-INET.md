IMAGENET: EfficientNet-0's 328 kernels ALL render to WGSL, and WebGPU refuses 12 of them for a tinygrad brace defect

    .venv/bin/python .agents/slop/browser/trace_imagenet.py
    launches 328  buffers 314  logits [1, 1000]
    WGSL-UNRENDERED: 0 of 328

SO tinygrad's WGSLRenderer CAN EXPRESS THIS MODEL -- squeeze-excite, swish, the
global-average-pool, the 1000-way head and the depthwise convs. The weights are
`deterministic()` and NOT pretrained, stated rather than implied:
`load_from_pretrained()` fetches ~20 MB and the claim here is "the browser
computes EfficientNet's forward pass bit for bit", which pretrained weights do
not change. THE LABELS WOULD BE MEANINGLESS AND THE ARITHMETIC WOULD NOT.

AND THE REPLAY IS BLOCKED BY 12 OF THE 328 SHADERS, ALL DEPTHWISE OR GROUPED
CONVS, AND THE UNBALANCE IS tinygrad's AND NOT THIS LANE's -- measured by
counting the braces on the WGSL AS TRACED, not after the page's transform:

    kernels 328 unbalanced 12
    [('r_160_14_14_3_3_3', 2), ('r_224_14_14_3_5_5', 2), ('r_8_112_28_4_4_3_3_3', 1), ...]

AND IT IS REPORTED AND NOT PATCHED. `tinygrad/` is the reference tree and a fix
there is a re-vendor. AND THE WORKAROUND IS REJECTED ON PURPOSE: APPENDING A `}`
WOULD COMPILE AND WOULD BE A GUESS ABOUT WHICH BLOCK WAS LEFT OPEN -- which is
the `* = ;` failure from the port's own `fullchain` measurement, one language
over. The census is committed as 328 rows in `imagenet/wgsl-braces.rows`, one
per kernel, so the 12 are NAMEABLE and not a count.

AND IT IS THE THIRD MEASURED GAP IN `renderer/wgsl.py`, after the two
`examples/webgpu/mnist/README.md` already records (no `Ops.FDIV`; the
`supports_float4` STACK crash).

THE FULL ACCOUNT, INCLUDING WHY THE 103 MB TRACE IS A PACKAGING PROBLEM AND NOT
A CORRECTNESS ONE, IS `.agents/slop/browser/IMAGENET.md`.
