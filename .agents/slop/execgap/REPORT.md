# EXECGAP — THE PORT's OWN RENDERED KERNEL, COMPILED AND RUN, WITH NO CPython IN THE LOOP

**Verdict token: `PASS`.** `execgate-gate.py` compares 7 measured rows against hand-derived pins
and all 7 agree; the three plants go RED; the lane itself runs under `checks/bounded.py` and
carries `WITHIN-LIMITS`.

**One command reproduces the whole thing, plants included:**

```
.venv/bin/python .agents/slop/execgap/execgate-gate.py --plants
```

`... execgate-gate.py` alone is the measurement (4.6 s); `--plants` adds three planted lanes
(18 s total). Both under `.agents/slop/execgap/`.

---

## 0. THE CLAIM, IN ONE PARAGRAPH AND WITH ITS BOUNDARY

A `bin/bend` process renders a kernel with the PORT's own `renderer/cstyle.bend`, emits the C,
writes it to `.agents/slop/execgap/out/k.c`, spawns `cc`, spawns the resulting binary, and prints
the binary's own stdout: **`out=7 2 5 4 7 4 1 2 2 4 3 1 6 2 3 4 0 5 0 4`**, which is the
`(4x3)@(3x5)` matmul those inputs demand and which was derived BY HAND in
`.agents/slop/execgap/expected.rows` before anything ran. **No CPython process produces a number
on this path, and none computes the expected value.** The two ends of the chain are the fixture
(the arena is hand-built — the port has no working scheduler, §6) and the driver (`main`, the
buffers and their data are the harness's, exactly as upstream's launcher is not its renderer).

---

## 1. THE PATH TAKEN, AND WHY THIS ONE

The brief's Path A, and the reason is that **the port's renderer is complete enough to be a
compiler and its runtime is not a runtime**: `runtime/ops_cpu.bend`'s own header says every seam
is a trace tag and nothing else. So the shortest honest path is the one that ends in a number and
crosses the fewest unimplemented seams:

```
graphcmp.bend:g_lin()          a scheduled (4,3)@(3,5) matmul, HAND-BUILT in the port's ops
  -> uop/fold.bend             the port's fold
  -> uop/ops.bend              the port's toposort_nocalls
  -> codegen/late/linearizer   the port's linearizer  (`linearize`)
  -> renderer/kuconv.bend      the port's UOp -> KU converter
  -> renderer/cstyle.bend      the port's renderer    (`_render`, `render_kernel`)
  -> THIS FILE                 the driver: `main`, three buffers, one printf
  -> Base's File.write         (all inside the same `bin/bend` process)
  -> Base's Process.run("cc")  -> cc_status=0
  -> Base's Process.run(bin)   -> run_status=0, and the numbers below are ITS stdout
```

**Path B (WebGPU) was not taken.** It needs a JS host, a WebGPU implementation in that host, and
`runtime/webgpu_call.mjs` is a *reference* implementation whose calls the port only *records*;
there is nothing in this tree that would make a shader actually dispatch, so the honest result
would have been "the port emits WGSL and a third-party host runs it" — a weaker claim than the one
above and a larger surface. The C route crosses a seam the port already owns and a launcher the
machine already has.

**The prior art was read before anything was built, and this lane is the missing END of it:**

| prior art | what it established | what it did NOT do |
|---|---|---|
| `.agents/slop/cpuseam/` | the port's render + ELF relocation + a call, on 5 real MNIST kernels, byte-identical to CPython's CPU device | the KU list came from **CPython's dump** (`gen_kus.py`); the call was spelled in Python (`jit_ref.py`), and it names the machine's block on `mmap`ing locally-built code |
| `.agents/slop/linrender/` | the port's own arena → fold → linearizer → kuconv → renderer produces the C for a scheduled matmul | **it never executed the C.** It compared TEXT with upstream's C |
| `.agents/slop/chain/` | program → engine → `schedule()` reaches the scheduler | `schedule()` answers **ZERO** kernels: `run_rangeify`'s apply half is not driven |

So the gap this lane closes is precisely "**the port's rendered text has never been a number, and
the number has never been checked against an expectation that no program computed**". Executing
the C is the part that was missing; and `Base` already had `Process.run`, which is the part that
made it possible in ONE language (§2).

---

## 2. INSIDE BEND, AND OUTSIDE IT — THE EXACT SPLIT

**MEASURED FIRST, BECAUSE THE WHOLE DESIGN DEPENDS ON IT: `bin/bend` CAN SPAWN A PROCESS AND WRITE
A FILE.** `.agents/slop/execgap/probe_io.bend`, output verbatim:

```
write=ok
cc_status=0
cc_out<>
cc_err<>
run_status=0
run_out<42>          # a C program this lane wrote, compiled and ran: 6*7
```

So **no step of this lane leaves Bend for a Python process.** The step that leaves the *Bend
runtime* — and it is a real boundary, named rather than hidden — is that `cc` and the binary are
**child processes**: Bend can start them and read their stdout, and it cannot link them. That is
`Base`'s `Process.run`, i.e. the same effect `gates/ops_bend-gate.bend` already uses, and the
cost is that the numbers cross as **text on a pipe**, not as memory.

**INSIDE THE PORT (shipped `.bend`, untouched by this unit):**

| step | file |
|---|---|
| the fixture's ops, the arena | `.agents/slop/graphcmp.bend` (`g_lin`) — port code, hand-built graph |
| the fold, the toposort, `vms` | `tinybendygrad/uop/fold.bend`, `tinybendygrad/uop/ops.bend` |
| the linearizer | `tinybendygrad/codegen/late/linearizer.bend` |
| UOp → KU | `tinybendygrad/renderer/kuconv.bend` |
| the C: typedef, signature, both loop heads, the three tap loads, the index arithmetic, the store, the braces | `tinybendygrad/renderer/cstyle.bend` (`_render`, `render_kernel_body`, `render_kernel`) |
| the file write, the compile, the launch, the stdout | `Base` (`File.open/write/close`, `Process.run`) |

**OUTSIDE THE PORT (this unit's):** the driver — `main`, the three arrays, the sentinel, the
counters and the `printf`s — and the gate. **THE PORT EMITS THE KERNEL; THE HARNESS EMITS THE
PROGRAM AROUND IT.** That is not a defect to be papered over: upstream draws the same line
(`CPUProgram.__call__` is the launcher and `CStyleLanguage.render` is not).

**AND ONE STEP THAT IS NEITHER, WHICH IS WHY THIS LANE IS NOT A `Device`:** `cc` here is a
**hosted** compile (`-O1`, default libc) because the driver needs `printf` and an entry point. The
port's own compiler lane is a different animal — `ClangCompiler.compile_fixed()` is
`-c -x c -O2 -fPIC -ffreestanding -fno-math-errno -nostdlib -fno-ident` with `- -o -`, i.e. a
**freestanding object to stdout** for in-process relocation, not an executable. Using it here would
be a category error, so the lane does not, and the port's `Cpu.compile`/`Cpu.exec` seam is
therefore NOT on this path (§6).

---

## 3. THE MEASURED NUMBERS

### 3.1 The kernel, exactly as the port rendered it (546 bytes, `out/k.c`)

```
void r_4_5_3(float* restrict data0_20, float* restrict data1_12, float* restrict data2_15) {
  for (int Lidx1 = 0; Lidx1 < 4; Lidx1++) {
    int alu0 = (Lidx1*3);
    float val0 = (*(data1_12+alu0));
    float val1 = (*(data1_12+(alu0+1)));
    float val2 = (*(data1_12+(alu0+2)));
    for (int Lidx2 = 0; Lidx2 < 5; Lidx2++) {
      float val3 = (*(data2_15+Lidx2));
      float val4 = (*(data2_15+(Lidx2+5)));
      float val5 = (*(data2_15+(Lidx2+10)));
      *(data0_20+((Lidx1*5)+Lidx2)) = ((val0*val3)+(val1*val4)+(val2*val5));
    }
  }
}
```

That is 50 KUs in (`n_ku=50`), one kernel out: two `RANGE`s, six `LOAD`s, one `STORE`, and
everything else INLINED into those — except the one intermediate the renderer keeps as a
statement, `int alu0 = (Lidx1*3)`, a MUL read by three loads, which `cstyle.py`'s `child_count`
rule makes a statement rather than an expression. **Every character of the kernel is the port's.**

### 3.2 The rows the gate compares (all AGREE)

```
mode             AGREE      real
sig              AGREE      r_4_5_3(data0_20,data1_12,data2_15)
in12             AGREE      1, 2, 3, 0, 1, 2, 3, 1, 0, 2, 0, 1
in15             AGREE      1, 0, 2, 0, 1, 0, 1, 0, 2, 0, 2, 0, 1, 0, 2
changed          AGREE      20
out              AGREE      7 2 5 4 7 4 1 2 2 4 3 1 6 2 3 4 0 5 0 4
wrote-every-cell AGREE      20
```

`out` is the matmul of the two printed input rows, derived by hand in `expected.rows`:

```
C[0] = 1*[1,0,2,0,1] + 2*[0,1,0,2,0] + 3*[2,0,1,0,2] = [7, 2, 5, 4, 7]
C[1] = 0*  .         + 1*[0,1,0,2,0] + 2*[2,0,1,0,2] = [4, 1, 2, 2, 4]
C[2] = 3*[1,0,2,0,1] + 1*[0,1,0,2,0] + 0*  .         = [3, 1, 6, 2, 3]
C[3] = 2*[1,0,2,0,1] + 0*  .         + 1*[2,0,1,0,2] = [4, 0, 5, 0, 4]
```

The inputs are chosen so the comparison can fail: **not rank-1, not symmetric, and the right
matrix is not its own transpose**, so an operand swap or a reversed index cannot land on the same
answer. Two cells are legitimately `0`, which is why the sentinel is `-99` and `changed` is a
control and not a comment.

### 3.3 Cost, token, and the compiler

| | |
|---|---|
| the lane | **5 s wall, peak RSS 2095 MB**, `[bounded] WITHIN-LIMITS` (ceiling 4000 MB) |
| the gate | 4.6 s without plants, **18 s** with all three |
| the compiler | `Apple clang version 21.0.0 (clang-2100.1.1.101)`, `arm64-apple-darwin25.3.0` |
| the compile | `cc -O1 -o .agents/slop/execgap/out/k.bin .agents/slop/execgap/out/k.c` → `cc_status=0` |
| the run | `out/k.bin` → `run_status=0` |

**AND THE PORT's C IS NOT BYTE-IDENTICAL TO UPSTREAM's C FOR THE SAME PROGRAM, MEASURED:**
`.agents/slop/linrender/lin_upstream_cpu.c` is 547 bytes to this one's 546 (upstream's file opens
with a blank line), and the remaining difference is a **permutation of the three tap names** —
upstream loads `val0=(alu0+1)`, `val1=(alu0+2)`, `val2=alu0`, `val3=Lidx2+10`, `val4=Lidx2`,
`val5=Lidx2` and stores `((val2*val5)+(val0*val4)+(val1*val3))`; the port loads them in index order
and stores `((val0*val3)+(val1*val4)+(val2*val5))`. **The three products and their summation order
are the same**, so the two kernels agree bit for bit on this data — but the report does not claim
byte identity, because there is none, and `linrender`'s own report had already named this as the
one remaining difference.

### 3.4 What the gate says when the lane cannot run — the `DEAD` row, measured twice

At 22:20 another unit had `tinybendygrad/codegen/kernel.bend` mid-edit (a forward reference:
`lr_dt.go` calling `lr_dt.in` before its def), and the lane printed **nothing**. The gate said:

```
DEAD -- the lane produced 0 row(s) and none of: mode, sig, c_len, ...
  the lane's stdout was:
<empty>
```

and exited **5**. **A run that produced no rows is not a pass**, and that property is now measured
rather than asserted. (It also means this lane is downstream of `codegen/kernel.bend` through
`linearizer.bend`; a break there is this lane's refusal, not its `FAIL`.)

**AND IT FIRED AGAIN ON THE FIRST RUN FROM A CLEAN STATE, WHICH FOUND A REAL DEFECT IN THE
HARNESS:** `rm -rf .agents/slop/execgap/out` and the lane died with `No such file or directory`,
because **`Base`'s `File.open` does not create parent directories** — and `out/` is not committed,
since its contents are build artefacts, so a fresh clone has no `out/` at all. The gate read 5
rows, saw `cc_status` missing, and said `DEAD` (5) instead of `PASS`. The fix is the harness's own
(`os.makedirs` in `run_gate`'s `run_lane`): **the harness owns its output directory; the lane writes
only the two files inside it.** Re-measured from a clean state afterwards: `PASS`, 10 rows.

---

## 4. THE MUTATIONS, AND WHICH ONE FIRED

Three plants, each a separate def in the lane, none reachable without naming it
(`plant=data`, `plant=swap`, `plant=nocall`). **They move the harness's side of the seam — the
inputs and the call site — not a shipped `.bend` file**, and §6 says why the source-level plant is
deferred rather than skipped-and-forgotten.

| plant | what it does | the answer | verdict |
|---|---|---|---|
| `plant=data` | ONE input cell: `B[0]` `1 -> 2` | `8 2 5 4 7 4 1 2 2 4 6 1 6 2 3 6 0 5 0 4` | **RED** |
| `plant=swap` | the kernel called with `(out, B, A)` | `1 4 5 0 5 2 3 1 0 2 1 4 5 0 5 4 6 2 0 4` | **RED** |
| `plant=nocall` | the kernel never called | `changed=0`, buffer still the sentinel | **RED** |

### 4.1 AND THE THIRD PLANT FOUND A REAL DEFECT — IN THE GATE'S OWN CONTROL

**MEASURED, first run of `--plants`, before the fix:**

```
plant=nocall STILL-GREEN  changed=20  out=99 99 99 99 99 99 99 99 99 99 99 99 ...
```

The driver initialised the output buffer with `SENT()` rendered as **`+99`** and compared against
`-99.0f`, so **every** cell counted as written and `changed` read 20 **for a kernel that did
nothing**. The control was a label. The fix is one def (`init_neg`) and the sign is now the point:
`AFTER` the fix the same plant reads `changed=0`, and the real lane still reads 20 **because the
kernel wrote every cell**, which is the only reading under which the number means anything.

**This is the case for plants in one paragraph:** the lane was green, the gate was green, and the
control that says "the kernel actually ran" was vacuous until a planted lane asked it a question it
could only answer wrongly.

### 4.2 WHAT NO PLANT HERE PROVES

**None of the three plants mutates the port's source**, so none of them proves the *renderer* is
load-bearing — they prove the *measurement* is. The port-level plant that is cheap and real is
`linrender`'s own found defect (feed `LT.linearize` a `Nil{}` vms table); it is `TODO(p3)` in the
lane because the tap ORDER may be semantically inert for this kernel (both orders sum the same
three products left to right), so it needs a kernel where order changes the bits — an accumulate
or a REDUCE, not a three-term dot.

---

## 5. THE ROWS, THE PIN, AND THE SHAPE OF THE GATE

- `expected.rows` is the ONLY place an expected number lives, and it carries its derivation as
  prose so it can be checked without running anything.
- The gate computes **nothing**: it compares row text. `norm()` folds whitespace and commas only —
  never value, never order.
- A missing pin is a `REFUSED`, not a default: a gate with a fallback expectation measures its
  fallback.
- A missing ROW is `DEAD` (5), a bound token that is not `WITHIN-LIMITS` is `REFUSED` (3), a
  disagreement is `FAIL` (1), and only "every row ran and agreed" is `PASS` (0).
- The lane never prints a verdict. It prints rows and the binary's stdout; the gate decides. **A
  lane that graded itself would be the corpus's own `D10` mistake in miniature.**

---

## 6. WHAT I COULD NOT DO, AND EVERY ONE OF THEM IS A `TODO(p3)` IN THE CODE

1. **THIS LANE DOES NOT SCHEDULE. THE REASON IS NO LONGER "THE STAGE IS NOT PORTED".** Its
   arena is `graphcmp.bend`'s hand-built `g_lin`, which already carries the six `LOAD` nodes
   (`:1193-1217`) that a real lowerer would have inserted. **CORRECTED 2026-11-19, MEASURED:**
   `rangeify.bend`'s `eng_stages()` still spells stage 1 as `Stg{0, Nil{}}`, but
   `rangify.bend`'s `rr_kernel_graph` IS the driver and `schedule()` on its output answers
   **1** kernel where the engine's output answers **0** (`.agents/slop/pipelinecensus/probe_kg.bend`).
   So the missing link is a WIRING LINE, and past it the next wall is `runtime/device.bend`'s
   `body_low` omitting `pm_add_loads`: the port's own scheduler's kernel renders **NO
   `LOAD` NODES** and `cc` refuses it with three `invalid operands to binary expression
   ('float *' and 'float *')` errors (`.agents/slop/pipelinecensus/execfull.bend`).
   **THE GAP IS TWO LINKS AND NEITHER IS A NEW ALGORITHM.**
2. **THE LAUNCH IS NOT THE PORT's OWN DEVICE LANE.** `cc` + `exec` here; `runtime/ops_cpu.bend`'s
   `Cpu.compile`/`Cpu.exec` is a freestanding object + relocation + in-process mmap-call, and it is
   not on this path. `.agents/slop/cpuseam/launch.bend` is the worked example of that route.
3. **ONE KERNEL, ONE DTYPE, ONE ADDRSPACE.** f32, `GLOBAL`, two RANGEs, LOAD/STORE/MUL/ADD. No
   `SPECIAL`, `BARRIER`, `CALL`, `CUSTOM_FUNCTION`, no `float4` vectorisation, no non-f32 dtype.
   Those arms are gated as TEXT (`gates/cstyle_render_census-gate.py`); nothing executes them.
4. **THE DRIVER IS THE HARNESS's**, so "the port ran a program" is not yet a sentence this tree can
   say — only "the port's kernel ran and computed X".
5. **NO PORT-SOURCE PLANT**, §4.2.
6. **NOTHING IS WIRED INTO `e2e.py` OR `gates/`.** This gate lives beside its lane under
   `.agents/slop/execgap/` and is reachable only by the one command in this report; an
   unreachable gate is the tree's own named hazard, and wiring it is a different unit's file.

---

## 7. FILES

| path | what it is |
|---|---|
| `.agents/slop/execgap/execgate.bend` | the lane: render → write → `cc` → run → rows; three plants |
| `.agents/slop/execgap/execgate-gate.py` | the gate: five verdicts, `--plants` |
| `.agents/slop/execgap/expected.rows` | the pins, with their hand derivation |
| `.agents/slop/execgap/probe_io.bend` | the measurement that `Base` has File + Process at all |
| `.agents/slop/execgap/probe_chain.bend` | the measurement that the fixture→KU chain imports and what it answers |
| `.agents/slop/execgap/out/k.c`, `out/k.bin` | the artefact of the last run, left where a reader can see it |
| `.agents/slop/execgap/lane.out`, `lane.err`, `gate-plants.out` | captured streams of the runs quoted above |
