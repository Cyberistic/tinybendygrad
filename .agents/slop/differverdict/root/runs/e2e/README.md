# runs/e2e — the ONE computation this project proves, and the artifact for it

`(A @ B) @ C` for three 8×8 f32 matrices, **two kernel launches**, dispatched by
`tinybendygrad/runtime/webgpu_call.bend`'s own call layer onto a **real WebGPU
adapter**, and read back **bit for bit** against CPython tinygrad's answer on the
identical bytes.

```
./.agents/slop/e2e.sh          # one command; prints PASS or FAIL; exit 0 or 1
```

Read the files below without running anything and you can check every claim here.

---

## What actually executed

Measured on this machine, 2026-10-03:

| | |
|---|---|
| adapter | `vendor=apple architecture=metal-3` |
| chrome | stable, `--headless=new`, headless |
| kernels | **2 launches**, both `entry r_8_8_8`, `global_size (1,1,1)` |
| shaders | **tinygrad's own WGSL**, from `tinygrad/renderer/wgsl.py`'s `WGSLRenderer` on the same `ast` the CPU executed |
| WebGPU calls | **84 steps**, every one dispatched |
| buffers | 6 created (5 device + 1 staging), 3 written, 2 copies, 1 map |
| **answer** | **64/64 u32 words bit-identical to CPython** |

A matmul rather than a forward pass, and the reason is worth stating: the port has
no kernel executor. `exec` is the last wall in `uop/fold.bend` and no `.bend` in
the tree defines one. What the port *does* have, and what this exercises, is the
**device call layer** — `Cs.call`, `Cs.readable`, `Cs.read` — and a matmul is the
smallest program that makes that layer do arithmetic. A forward pass would need
`backward`, autograd and the optimizer step, none of which exist in Bend.

## Why two launches

The second launch's first input **is the first launch's output**. So the
intermediate had to be computed on the GPU. A one-launch program could be
satisfied by re-uploading every input, and an all-equal fixture cannot tell the
difference — `mm_e2e_writes=3` is the row that does: 3 is the number of buffers
**no earlier launch wrote**, counted from the trace.

## Why the input values are dyadic

**The claim is bit-exactness, and it is a theorem rather than a hope.** Every
matrix entry is a multiple of 2⁻⁶ with |entry| ≤ 2, so every product is a multiple
of 2⁻¹² with |product| ≤ 4, and every *partial* sum of the eight products is a
multiple of 2⁻¹² with |partial| ≤ 32 — at most 18 significand bits against f32's
24. No rounding ever occurs, so no association order and no multiply-add
contraction can change a bit.

That choice was forced by a measurement, not by taste. With `np.random.randn`
inputs the GPU and CPython disagreed by up to **2.86e-6 absolute**, and the cause
was measured rather than guessed:

- `tinygrad/runtime/support/compiler_cpu.py:21` compiles the generated C with
  `-O2` and **no** `-ffp-contract=off`. The LLVM IR for that exact kernel contains
  **57 `llvm.fmuladd`** at `-O2` and **0** with the flag added. The CPU contracts.
- The WGSL path (Tint → SPIR-V → MSL on this adapter) contracts too, differently.

**Neither side is the reference**, so no tolerance can settle it. `e2e/cc-no-fma.sh`
(a `CC` wrapper, no file edited) turns the contraction off on the CPU and the
residual difference *does not vanish* — which is what proved the second contraction.
The dyadic inputs remove the question instead of absorbing it into a number nobody
can audit.

## Why the answer is arithmetic and not data

`mm_e2e_in_bits_equal` reads an **uploaded matrix back off the GPU** and compares
it to the bytes that were written: **bit-identical**. Without that row a wrong
answer could be the data's fault, and nothing else tells the two apart.

## The files

| file | what it is |
|---|---|
| `e2e-mm-oracle.json` | the CPython call: two launches' WGSL, entry names, geometry, buffer ids, the upload words, and the answer's 64 u32 words |
| `e2e-mm-gpu.json` | the GPU call: adapter, the 84 performed op names, `cs_lens`, `out_u32`, `in_bytes`, and the raw constructor tags Bend emitted |
| `e2e-mm-bend.txt` | the **pure** port's own output — the program it built, with no GPU involved |
| `e2e-mm-gate.txt` | the 40 gate rows and the verdict |
| `e2e-mm-bend.err` | bend's stderr, kept because `--check-only` exits 1 on a clean file and the verdict is the FIRST LINE, never the status |
| `e2e-negctl.txt` | the negative control's whole output — three breaks, all caught |

Every expectation in the gate is computed from `e2e-mm-oracle.json`. Nothing is
transcribed — and that was learned the hard way: the gate's first version asserted
a hand-counted op multiset and four hand-counted buffer rows, and **all four were
wrong while the port was right**. They are now identities between two measured
counts (`PushScope == PopScope`, `Finish == Submit`, `MapAsync == 2 and
MappedRange == 1`, one object per launch), which cannot be satisfied by typing a
constant.

## The negative control

```
./.agents/slop/e2e_negctl.sh     # exit 0 only if all three breaks were caught
```

Everything is broken on a **copy** under `$TMPDIR` with the relative layout intact
(`.bend` imports are relative; a flat copy cannot resolve them). Measured:

| break | red on |
|---|---|
| one byte of an uploaded matrix | `mm_e2e_out_bits_equal=False`, `mm_e2e_in_bits_equal=False` |
| the second launch's binding order | `mm_e2e_l1_bg_bufs`, `mm_e2e_out_bits_equal=False`, and two power rows |
| **the port**: `Cs.caller` binding every `bufs` slot to id 0 | the walk stops; 19 rows red |

The third is the one that matters: the first two prove the harness listens, the
third proves it listens to the **port**. That mutation is the bug
`webgpu_call.bend`'s own header records as having once existed and as having been
invisible to every row in either file. Its output is `e2e-negctl.txt`.

## The power rows

An equality that cannot fail proves nothing. Six plausible wrong answers are
computed **by calling numpy on the oracle's own input words**, and each must be
far from the GPU's answer:

```
abad 24.34   atc 25.80   bada 22.45   ctb 30.03   self 22.84   zero 21.34
```

`abad` is "only the first launch ran"; `bada` is "the two reads bound the wrong
way round"; `self` is "the readback returned an untouched input". The right answer
is **0.0** away. Six orders of magnitude of headroom.

## Reproduce

```
./.agents/slop/e2e.sh                 # the gate
./.agents/slop/e2e_negctl.sh          # the negative control
.venv/bin/python .agents/slop/e2e_mm.py   # the oracle alone, no browser
./bin/bend .agents/slop/e2e_mm.bend        # the pure port alone, no GPU, no browser
node .agents/slop/e2e_gpu_probe.mjs        # is there a device that COMPUTES here
```

`e2e_gpu_probe.mjs` is deliberately separate and deliberately paranoid: it
dispatches a kernel and reads the answer back, because `requestAdapter()` resolving
is a **name**, not a computation. Its artifact is `.agents/slop/e2e-gpu-probe.txt`.
