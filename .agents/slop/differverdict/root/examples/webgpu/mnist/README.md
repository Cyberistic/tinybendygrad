# examples/webgpu/mnist — `examples/beautiful_mnist.py` in a browser on WebGPU

The forward pass of [`examples/beautiful_mnist.py`](../../examples/beautiful_mnist.py)
— `Model.__call__` at py:19, under `TRAINING=0`, which is the path
`get_test_acc` (py:29-30) uses — executed by real WGSL kernels on a real WebGPU
adapter, checked bit-for-bit against CPython.

**Measured, on this machine:**

```
adapter: vendor=apple architecture=metal-3      (Chrome 154, --headless=new)
kernels: 17 launches, 201 ms, every one dispatched
logits:  10/10 bit-exact against CPython DEV=CPU
```

## What actually runs on the GPU

The kernels are **tinygrad's own**, not hand-written approximations.
`net.json` carries, for each of the 17 kernel launches CPython made, the WGSL that
`tinygrad/renderer/wgsl.py`'s `WGSLRenderer` emitted **from the same `Ops.PROGRAM`
the CPU executed**, plus the launch's binding order and dispatch geometry. The
entry names read as the model:

| launch | entry | layer |
| --- | --- | --- |
| 0-9 | `E_8_4`, `E`, `E_16_4` | `BatchNorm`'s `running_mean`/`running_var`/`num_batches_tracked` fills |
| 10 | `r_8_24_8_3_4_5_5` | `nn.Conv2d(1, 32, 5)` → `(1,32,24,24)` |
| 11 | `r_8_20_5_4_4_32_5_5` | `nn.Conv2d(32, 32, 5)` → `(1,32,20,20)` |
| 12 | `r_320_10_2_2` | `Tensor.max_pool2d` → `(1,32,10,10)` |
| 13 | `r_16_8_2_4_4_32_3_3` | `nn.Conv2d(32, 64, 3)` → `(1,64,8,8)` |
| 14 | `r_64_6_2_3_64_3_3` | `nn.Conv2d(64, 64, 3)` → `(1,64,6,6)` |
| 15 | `r_192_3_2_2` | `Tensor.max_pool2d` → `(1,64,3,3)` |
| 16 | `r_10_144_4` | `nn.Linear(576, 10)` → `(1,10)` |

`mnist-webgpu.js` contains no arithmetic. It decides only what CPython decides:
which buffer is bound where, and how big the grid is.

## Why it is a trace and not a re-implementation

`WebGpuDevice.__init__` needs the native Dawn binding, so the WebGPU device is
unreachable from CPython — but the **renderer** is not. codegen's `pm_to_program`
writes an `Ops.SOURCE` uop before anything is compiled, and
`tinygrad/engine/realize.py:160 exec_kernel` is the one place that knows every
launch's binding order, dispatch geometry and buffer contents. So
`.agents/slop/xd2/trace_forward.py` wraps `exec_kernel`, runs the model on
`DEV=CPU` for real, and captures both the numbers and the WGSL. The browser then
replays the launches.

## The gate, and what it does not claim

The harness diffs the whole 10-vector against `oracle.json` on disk — never
against the page's own output — and additionally prints a **per-launch ladder**
comparing every buffer after every launch, because "0/10 logits right" has
nowhere to start:

```
launch 10 r_8_24_8_3_4_5_5    1168/20048 elements differ, max 512 ulp / 8.94e-8 absolute
launch 11 r_8_20_5_4_4_32_5_5  3701/56992 elements differ, max 4158 ulp / 7.45e-8 absolute
launch 12 r_320_10_2_2         exact (16000 elements)
launch 13 r_16_8_2_4_4_32_3_3  618/25792 elements differ, max 320 ulp / 2.38e-7 absolute
launch 14 r_64_6_2_3_64_3_3   1485/43584 elements differ, max 87 ulp / 3.58e-7 absolute
launch 15 r_192_3_2_2          exact (2880 elements)
launch 16 r_10_144_4           exact (6356 elements)
```

So the honest claim is **not** "the GPU equals the CPU elementwise". It is:

- the **logits are bit-identical** (10/10), and
- both max-pools and the final `Linear` are bit-identical elementwise, while
- the four **convolutions** differ by at most **3.6e-7 absolute**.

The conv difference is f32 accumulation, and the ulp counts are large only because
those outputs are small numbers from sums of much larger ones — the absolute
figure is the one that means something. The CPU is compiled `-O2`
(`tinygrad/runtime/support/compiler_cpu.py:21`) with no `-ffp-contract=off`, so
clang may fuse a multiply-add that WGSL does not.

## Run it

```
# regenerate the trace and the oracle from CPython (needs .venv with numpy)
.venv/bin/python .agents/slop/xd2/trace_forward.py

# the gate: opens the page in Chrome, waits, diffs against oracle.json
node .agents/slop/xd2/e2e.mjs          # exit 0 = match

# or just look at it
node -e 'import("./.agents/slop/xd2/serve.mjs").then(async m => {
  const s = await m.serve("examples/webgpu/mnist"); console.log(s.url); })'
```

## What is NOT here, and why

- **Training.** `train_step` (py:23-27) needs `backward`
  (`tinygrad/mixin/gradient.py:20`), autograd, and the optimizer step. None of that
  is in the page, and none of it is claimed.
- **A general WebGPU device.** `mnist-webgpu.js` replays one captured trace.
  `tinybendygrad/runtime/ops_webgpu.bend` is where the call layer is being ported;
  this file is the smallest thing that makes the page real while that lands, and it
  should be replaced by it rather than grow.
- **Two `renderer/wgsl.py` defects**, worked around in `trace_forward.py`'s
  `MNISTWGSL` subclass and reported rather than patched (both files are read-only to
  this unit): `code_for_op` has no `Ops.FDIV`, and `supports_float4 = False` is read
  in only one place while a `float2`/`float4` STACK still reaches
  `CStyleLanguage.string_rewrite`, which crashes on `float4 = None`.
