# STAGE 1 — DOES THE PORT'S EMITTED C COMPILE AND RUN?

**REACHED: yes. `zsh .agents/slop/portexec/stage1.sh` → PASS, and 3/3 negative
controls turn it red.**

## THE EXACT KERNEL, taken from the port's OWN stdout

`./bin/bend tinybendygrad/renderer/cstyle.bend` prints **227 rows**. Row
`kern2 CLANG      ` is read out of the **port's own column** — the
`NAME = [...]` half — and the `py=[...]` half is never touched, because that half
is a transcription of CPython and comparing against it would be circular.

```c
                                      # 165 bytes, verbatim from the port
void E_4(float* restrict data0_4, float* restrict data1_4) {
  float4 val0 = (*((float4*)((data1_4+0))));
  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};
}
```

## THE EXACT INPUT, produced by calling CPython

`.venv/bin/python .agents/slop/portexec/oracle.py` — four f32 lanes, and the
words are printed as `u32` bit patterns so no printed-decimal rounding can be
mistaken for agreement:

| lane | f32 | u32 |
|---|---|---|
| 0 | `-2.0` | `3221225472` = `0xc0000000` |
| 1 | `+1.5` | `1069547520` = `0x3fc00000` |
| 2 | `+0.25` | `1048576000` = `0x3e800000` |
| 3 | `-0.75` | `3208642560` = `0xbf400000` |

## BOTH NUMBERS

```
STEP 0  oracle  numpy float32 arithmetic     : [3212836864, 0, 0, 0]
STEP 0  oracle  tinygrad DEV=CPU, real run    : [3212836864, 0, 0, 0]
STEP 5  port    cc-compiled, linked, executed : [3212836864, 0, 0, 0]
STEP 6  diff bytes                           : 0
```

Three independent answers agree, and only the third came from the port:
`0xbf800000` = `-1.0f`, which is `-2.0f + 1.0f`, and lanes 1–3 are zero because
`(float4){(val0[0]+1.0f)}` is a C compound literal with **one** initializer.

**THE SECOND CPython ANSWER IS A REAL EXECUTION, NOT ARITHMETIC.** `oracle.py`
hands the C text to tinygrad's own `Device["CPU"]`: `ClangCompiler.compile` →
ELF → `CPUProgram` → `mmap`/`ctypes.CFUNCTYPE` → call (`tinygrad/runtime/ops_cpu.py:29-72`).
So the reference is the same path `DEV=CPU` takes, not a second reading of the
port.

## THE FOUR STEPS, ATTRIBUTED

| step | what | result |
|---|---|---|
| `bend -o` | not used — Stage 1 runs the port's *interpreter*, so there is no `-o` step | n/a |
| `bend` (run) | `./bin/bend tinybendygrad/renderer/cstyle.bend` | 227 rows |
| `cc` | `cc -Wall -Werror -c stage1.c -o stage1.o` | ok, 1320-byte object, **zero warnings** |
| link | `cc stage1.o -o stage1.bin` | ok |
| run | `./stage1.bin`, **twice**, outputs `cmp`-identical | ok |

## NEGATIVE CONTROLS — the lane CAN fail

| plant | result |
|---|---|
| `val0[0]+1.0f` → `+2.0f` | **RED** at the word compare |
| `E_4(data0_4, data1_4)` → `E_4(data1_4, data0_4)` | **RED** at the word compare |
| the store line commented out | **RED at `cc`** — the compare was never reached, and this is labelled as such rather than counted as a compare that worked |

## WHAT IS THE PORT'S AND WHAT IS THE HARNESS'S

**PORT** — `render_kernel`'s **signature** (`void E_4(float* restrict data0_4,
float* restrict data1_4)`), the buftypes, the prefix/framing, verbatim.
**UPSTREAM'S OWN TEXT** — the `float4` typedef preamble, which is
`ClangRenderer.render_vector_prefix` (`tinygrad/renderer/cstyle.py:304-307`)
called from `oracle.py`, not typed here. `float4` in the body fixture does not
exist until a vector prefix has been declared.
**HARNESS** — `main()`, the buffers, the readback print, and the `extern`
prototype, which is obtained by **parsing** the port's own signature line out of
the row value.
**NEITHER SIDE GENERATED** — the two body lines. They are the gate's fixture
`g_kernel()` at `cstyle.bend:1879`, an **input** to `render_kernel`; upstream is
handed the same two lines (`renderer_oracle.py:508`).

**So Stage 1's claim, precisely: the port's SIGNATURE AND FRAMING are semantically
live C, not merely text-equal to CPython.** It does **not** claim the port
generated the arithmetic. The port has no `_render` at all — `cstyle.bend` has
`render_kernel`, `render_index`, `render_buffer`, `code_for_op`, `render_type`,
`render_ptr`, `render_cast` and nothing that walks a UOp list into lines.
