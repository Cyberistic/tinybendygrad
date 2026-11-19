# shaders/ — a fragment shader as a tensor program

**The claim: Shadertoy's expression vocabulary is expressible in this port's UOps without
extending the IR.** Not "a shader renders" — that is the runtime half and it is not here.

It is the smallest anti-aliased shape that uses the four things a Shadertoy author reaches
for and a tensor model does not have on the shelf:

| Shadertoy | here | why it is not free |
|---|---|---|
| `length(p)` | `sqrt(x*x + y*y)` | a tensor has no `vec2`, so `p` is **two buffers** |
| `fwidth(d)` | `pad` + `shrink` + `sub` + `abs` | screen-space derivatives are an *invocation-neighbourhood* notion and UOp has none |
| `smoothstep` | `clamp` composed from arithmetic | GLSL vocabulary, **absent from tinygrad**: `grep -c smoothstep tinygrad/` is 0 |
| `clamp(x,0,1)` | `max(x,0)` and `x - max(x-1,0)` | there is **no `Ops.MIN`**, upstream or here |

## Run it

```sh
.venv/bin/python shaders/shader-gate.py            # PASS / FAIL / DEAD / REFUSED
.venv/bin/python shaders/shader-gate.py --plant     # the gate must go RED
bin/bend shaders/shader-rows.bend                       # the port's graph, as rows
.venv/bin/python shaders/shader-oracle.py --values  # the formula, as numbers
```

`shader-gate.py` answers **two** questions and the exit status covers both:

* **graph parity** — 2 079 rows, the port's `bin/bend` against CPython's tinygrad, byte for
  byte after normalising one float spelling (the port prints the exact f32
  `9.999999747378752e-05`; CPython prints the shortest repr of the double `0.0001`).
* **is it a circle** — `centre=1.0000 corner=0.0000 partial=95`, then `VALUES OK`.
  `partial` is the count of pixels with an alpha strictly between 0 and 1: the
  anti-aliasing band. **It is the only number that sees `fwidth`**, because a shader that
  multiplies the derivative by zero still agrees with its own oracle. 95 of 256 at 16×16 is
  the *resolution*, not a defect: `fwidth = |dFdx| + |dFdy|` spans a band ≈ 4 px wide here
  and ≈ 1 px at 512².

`--plant` rewrites `SH_R()` in a **copy of `shader.bend`** so the *port's* graph moves, and
requires the diff to fire. Measured: `PLANT FIRED -- row 37`.

## Where the derivative comes from

A quad neighbour needs no new op:

```
right(d) = shrink(pad(d, +1 col), drop col 0)      # movement ops
dFdx(d)  = d - right(d)
fwidth   = abs(dFdx) + abs(dFdy)
```

**This is the result worth having.** In most systems autodiff is the hard half; here autodiff
is already done (32 rules, exercised by the corpus's `grad`/`gral` graphs) and the *screen-space*
derivative is the half that looks missing — and it is a movement op.

## The pipeline run: four links, and a measured negative

`shader-run.bend` takes the shader through the port's own compiler. **It runs and produces a
WRONG kernel** (`*(buf0+Lidx0) = 1`, one buffer instead of three), so it is a measured
negative and not a renderer. What it established on the way is worth more than the render:

| link | without it |
|---|---|
| `tn_assign_store` | a bare expression under a SINK schedules **nothing** — `kernels=0`, no error |
| `rr_kernel_graph` | `SCH.schedule` **is** `create_schedule`, which walks existing kernels and creates none |
| per-body `linearize` | it takes **one kernel**; given the `LINEAR` it renders `UNHANDLED(Ops.LINEAR)` |
| `vms` widths | `Nil{}` gives every node key 1, the sort collapses, and the body is **one op** |

**The kernel graph itself is right** — `eng_dump` shows `SINK(AFTER(INDEX, END(STORE, RANGE
×4)))` with the formula's `SQRT`, `RECIP`, `MAX` and both `PAD`s. So the loss is between
`create_schedule` and the CU list. `buf-schedules.bend` is the control: the same chain over
`a + b` on two `BUFFER`s answers `kernels=1` **and renders the add**, so the scheduler is not
simply broken — something about this graph (PAD/SHRINK, or two reads of one buffer) does not
survive.

**And a genuinely missing port.** An `ALLOC` has no realize-time rebind: `UOp.new_buffer` is
`TODO(p3)` in `ops.bend`, and upstream's `linear_with_vars` swaps `ALLOC` → `BUFFER` there.
That is why the runner takes `mxw_buf` (BUFFERs) and why a graph built the `Tensor.empty`
way — which is what the graph gate correctly builds, because CPython builds it — cannot be
scheduled at all.

## What this folder does not do

* **It does not execute.** The port builds and renders graphs; it makes no device call
  (`runtime/ops_cpu.bend`: "none of them is made"). Every number above is CPython's, except
  the row *structure*, which is the port's. Closing that is separate work.
* **It is not a rasterizer.** No geometry, no coverage, no perspective divide. A fragment
  shader's inputs are buffers, which is why the two coordinate grids are the inputs here.
* **`pad-arg-form.bend` is a measurement, not a gate.** It exists because this folder nearly
  wrote up a port defect that was its own bug: `mxw_pad` takes upstream's `(offset, END)`
  pairs, **not** after-amounts, so `[0,1]` gives a `?` dtype and `[16,17]` gives `f32`. Both
  readings are one line apart and the fold is right in both.

## Files

| file | what it is |
|---|---|
| `shader.bend` | the shader, built with the port's own Tensor API, printed as a preorder unfolding |
| `shader-oracle.py` | the same formula in CPython tinygrad — graph lane and value lane |
| `shader-gate.py` | the differ over both lanes, the five verdicts, and the plant |
| `pad-arg-form.bend` | the `pad` argument-form measurement quoted above |
