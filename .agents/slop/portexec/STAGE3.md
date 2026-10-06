# STAGE 3 — THE WHOLE MATMUL THROUGH THE PORT

**REACHED: yes. `zsh .agents/slop/portexec/run-kernel.sh mm` → PASS,
`diff bytes: 0`, 64/64 u32 words, 3/3 negative controls red.**

## THE COMPLETION CRITERION

> the port's words match `.agents/slop/e2e_mm.py`'s CPython words bit for bit,
> through the port's own runtime

```
STEP 6  port   : 64 words, first 8 [1044381696, 1079115776, 1050148864, 3231514624,
                                      1088487424, 3221946368, 1048576000, 1091551232]
        CPython: 64 words, first 8 [1044381696, 1079115776, 1050148864, 3231514624,
                                      1088487424, 3221946368, 1048576000, 1091551232]
        equal  : True   diff bytes: 0   (64/64 words)
```

The expectation is **not** a numpy matmul I wrote. `oracle.py` reads
`runs/e2e/e2e-mm-oracle.json` — the file `e2e_mm.py` itself wrote — and takes
`mats.A`, `mats.B`, `mats.Cm` as the three 8×8 f32 inputs and `answer_u32` as the
64-word answer for `(A @ B) @ Cm`. If that record is absent the oracle sets
`mm_missing` and **refuses to substitute a matmul of its own**, because a
self-computed expectation would make the comparison against "e2e_mm.py's words" a
comparison against a different program.

## THE KERNEL IS EMITTED BY THE PORT

`.agents/slop/portexec/emit-mm.bend` imports
`tinybendygrad/renderer/cstyle.bend` and calls **`cstyle.bend:1643`'s
`render_kernel`** — the same def the 227-row gate calls — with **four** buffer
arguments instead of two. Its output, 520 bytes:

```c

void mm(float* restrict data0_4, float* restrict data1_4, float* restrict data2_4, float* restrict data3_4) {
  float tmp[64];
  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) {
      float s = 0.0f;
      for (int k = 0; k < 8; k++) { s += data1_4[i*8+k] * data2_4[k*8+j]; }
      tmp[i*8+j] = s;
    }
  }
  ...
```

`emit-mm.bend` declares **no `law` and no foreign effect**. It prints the text and
exits.

## THE FULL CHAIN, EACH STEP ATTRIBUTED

```
bend -o   run-kernel.bend -o run.c   159,801 bytes; shim INLINED at line 5650
cc        -Wall -Werror -c kernel.c  1,240-byte object, ZERO warnings   <- the PORT's C
cc        -c run.c                   109,560 bytes (bend's own runtime warns)
LINK      run.o kernel.o             ok
RUN       ./run.bin x2               64 WORD lines, cmp-identical
COMPARE   vs e2e_mm.py's record      0 diff bytes
```

Buffer `Nat`s printed by Bend, all under 2^51 and all **different from each
other** — the self-aliasing check:

```
KERNEL_NAT 4308376472   DST_NAT 4317115360   A_NAT 4317115616
B_NAT 4317115872        C_NAT 4317116128
```

Two runs gave `4335377304 / 4336759776 / 4336760032 / 4336760288 / 4336760544`.
Different — that is ASLR, and it is why no address is compared to a constant.

## WHAT IS THE PORT'S, PRECISELY

| part | who |
|---|---|
| `void mm(float* restrict data0_4, …, float* restrict data3_4)` | **PORT** — `kernel_typedef`, `buffer_suffix`, four `_render_dtype` calls, the `void` return, braces, framing |
| the two `tmp`/`s` loop nests and the eight-tap `s +=` | **FIXTURE** — literals in `emit-mm.bend`, exactly as `g_kernel()` at `cstyle.bend:1879` is a literal |
| the shim's `extern`, its function-pointer type, its call order | **PORT** — parsed out of the port's own text by `exec_harness.signature` |
| allocation, fill, launch, readback, printing | **BEND** |
| the loop indices `0n…63n` and the 192 input words | generated from CPython's JSON |

**`cstyle.bend` has no `_render`.** Nothing in the port turns a UOp list into
lines. `cstyle.bend:49` names the wall: `Ops.SHRINK` has no dtype in
`fold.bend`, so `F.fold.dt` answers `None` and `render_type` — which every emitted
line needs — cannot be driven from a graph. So Stage 3 is a statement about the
port's **kernel interface and signature assembly**, and about a matmul executing
on the machine, not a claim that the port scheduled one.

## NEGATIVE CONTROLS

| plant | result |
|---|---|
| the first dot's 8 taps → 7 | **RED** |
| the Bend program fills B into A's buffer | **RED** |
| the shim never calls the kernel | **RED** |

Unlike Stage 2, **no aliasing plant is a theorem here**: this kernel reads three
buffers, so the same slot-swapping plant does turn it red. The two plants that
were theorems for `kern2 CLANG` are documented as theorems in `STAGE2.md` and are
not counted towards these three.

## WHY THERE IS NO `-ffp-contract=off`

`e2e_mm.py` chose dyadic inputs so that no rounding ever occurs and no tolerance
can settle a contraction difference — that is the theorem at `e2e_mm.py:58-83`.
Its `answer_u32` is what tinygrad's own `DEV=CPU` produced on this tree, and the
port's kernel, compiled by `cc` with default flags, agrees with it on **all 64
words**. No tolerance was applied and none was needed.
