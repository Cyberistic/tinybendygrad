HOW FAR FROM MNIST AND IMAGENET IN THE BROWSER: one works TODAY, and the other two have NAMED walls

EVERY ROW BELOW CARRIES THE COMMAND THAT PRODUCED IT.

MNIST INFERENCE IN THE BROWSER **WORKS TODAY**. `examples/webgpu/mnist` on a
real adapter (`vendor=apple architecture=metal-3`, Chrome stable
`--headless=new`): **17 launches, 955.4 ms, logits 10/10 BIT-EXACT** against
CPython. Both max-pools and the final Linear are bit-identical elementwise; the
four convolutions differ by at most 3.6e-7 ABSOLUTE, which is f32 accumulation
order and not a defect (the CPU is `-O2` with no `-ffp-contract=off`).

AND THE PAGE IS A REPLAY OF A CAPTURED CPYTHON TRACE. `mnist-webgpu.js`
contains no arithmetic. So the browser runs the port's CALL LAYER and
tinygrad's SHADER, and CPYTHON did the SCHEDULING. That distinction IS the gap.

THE GAP, MEASURED AS A 0 -> 1. `realize.bend` reads `rz_lin_n=0`: the port's
own `schedule()` on the port's own sink answers ZERO kernels, because the
sink's AFTER carries a STORE and `_split_after` partitions an AFTER's srcs
into KERNELS and dependencies -- and a STORE IS NOT A KERNEL. Rangeifying the
sink turns that STORE into an `END`, and `sc_is_kernel` COUNTS `END`:

    bridge_lin_raw=0        <- the port's own sink, as-is
    bridge_lin_ranged=1     <- the SAME sink, through run_rangeify + the 6 stages

AND CPYTHON AGREES ON THE SAME PROGRAM: `py_lin_raw=0`, `py_lin_ranged=1`.
This is the first time the port's scheduler produces a kernel on the port's own
program, and the rangeify driver FIXED EARLIER THIS SESSION (`sink (consumed
more than once)` at `rr_run_rangeify`) is what closed it.

AND THE WHOLE CHAIN COMPOSES: schedule -> linearize -> kuconv -> render:

    chain_linear_n=10  chain_ku_n=10  chain_c_nbytes=198

AND IT RENDERS REAL C WITH REAL RANGE LOOPS, not `void test() { * = ; }` --
which is what the FIRST attempt produced, because it passed the kernel's two
DIRECT srcs to `linearize` and upstream's `linearize(sink)` toposorts
INTERNALLY (`linearizer.py:7`), so the port's caller OWES the toposort.

FOUR DEFECTS STAND BETWEEN 198 BYTES AND A MODEL, each visible in the C text
rather than inferred, against CPython's OWN 547-byte answer from its own
`do_to_program`:

  D1 `split_kernels` IS A STUB. `rangeify.bend:811`'s `sk_0` answers
     `M.Hop{ar, 0}` -- "no rewrite" -- where upstream (`rangeify.py:326-335`)
     builds `ret.sink(arg=KernelInfo()).call(...)`. AND THE PORT HAS `KernelInfo`
     ALREADY (`c2fbda4ca`), so this is a missing CALL, not a missing type. It is
     why CPython's root is `CALL` and the port's is `STORE`.
  D2 THE RANGE's CONST SRC IS NOT READ: `Lidx0 < ;` where CPython has `Lidx1 < 4`.
  D3 WEAK DTYPES ARE NOT LOWERED: `weakint` where CPython has `int`.
  D4 (follows D2/D3) the arithmetic is absent and the braces do not balance.

NOT CLAIMED: that the 198-byte kernel is CORRECT C. It is real C with an empty
trip count.

TRAINING: THE WALL IS ONE GREP. `compute_gradient` (69 `gr_*` rules) and
`tn_backward` all EXIST and NOTHING OUTSIDE `tensor.bend` CALLS IT. But
`.agents/TODO.md` records the fix that landed this session: `mixin/gradient.bend`
went **0/494 -> 174/495** and all 32 rules `gr_0..gr_31` are reached by two new
corpus graphs, and `gral` DISAGREED ON ITS FIRST RUN AND FOUND A REAL PORT
DEFECT (four WHERE nodes where CPython builds three).

IMAGENET: THREE WALLS. The model is a STUB (`resnet.bend`'s own header says so;
all 15 model files are), though the LAYERS landed. The loader is DONE (520
lines, a real `json.loads` replacement). The browser page is UPSTREAM's and
imports `../../net.js`, WHICH DOES NOT EXIST.

SO THE SHORTEST PATH TO A MODEL IN THE BROWSER THROUGH THE PORT IS: fix D2/D3,
render ONE MNIST kernel through the port's own `kuconv`+`render`, and dispatch
it -- because links 3-5 are already measured.

THE E2E GATE IS ALSO GREEN ON ALL SEVEN STAGES AS OF THIS SESSION (committed
earlier): `--- verdicts: 0 failed, 0 skipped ---`.
