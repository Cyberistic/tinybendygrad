# HOW FAR ARE WE FROM RUNNING MNIST AND IMAGENET IN THE BROWSER

**Every claim below carries the command that produced it. Measured 2026-10-31.**
**Machine:** darwin/arm64, Chrome stable `--headless=new`, adapter
`vendor=apple architecture=metal-3`.

---

## 0. THE ANSWER IN ONE TABLE

| # | what | state | the instrument |
|---|---|---|---|
| 1 | **MNIST IN THE BROWSER, INFERENCE** | **WORKS TODAY** | `examples/webgpu/mnist` — 17 launches, 955 ms, logits **10/10 bit-exact** vs CPython |
| 2 | **MNIST TRAINING IN THE BROWSER** | **NOT DONE, and the wall is named**: `backward` is unexercised | `mixin/gradient.bend` |
| 3 | **IMAGENET IN THE BROWSER** | **NOT DONE, three named walls** | `extra/models/resnet.bend` (STUB) |
| 4 | **THE PORT's OWN PORTABLE PIPELINE** (schedule→render→run) | **COMPOSES END TO END, with four named defects** | `.agents/slop/browser/fullchain.bend` |
| 5 | **THE PORT's EXECUTION IS BYTE-EXACT** | **PROVEN on 5 real MNIST kernels + a 4-buffer matmul + an f64 kernel** | `checks/e2e.py` — **7/7 stages PASS** |

**⇒ THE BROWSER IS NOT THE BLOCKER.** The WebGPU lane works and is
bit-exact. **⇒ THE BLOCKERS ARE (a) the port cannot yet turn a model into
kernels, and (b) there is no backward pass.** Both are named below with the
line they rest on.

---

## 1. WHAT RUNS IN A BROWSER TODAY, MEASURED

`examples/webgpu/mnist` is `examples/beautiful_mnist.py`'s forward pass
(`get_test_acc`, py:29-30) on real WGSL kernels on a real adapter.

```
$ node /tmp/probe_webgpu_mnist.mjs
RESULT {
 "done": true, "ok": true,
 "exact": 10, "total": 10,
 "launches": 17, "ms": 955.4
}
MATCH: the browser reproduced CPython's forward pass exactly
```

The per-launch ladder, from the page's own `__MNIST_RESULT.ladder`:

```
launch  0..9   E_8_4 / E / E_16_4        exact (BatchNorm fills)
launch 10      r_8_24_8_3_4_5_5          1168/20048 differ, max 8.94e-8 absolute
launch 11      r_8_20_5_4_4_32_5_5       3701/56992 differ, max 7.45e-8 absolute
launch 12      r_320_10_2_2              exact (max_pool)
launch 13      r_16_8_2_4_4_32_3_3       618/25792 differ, max 2.38e-7 absolute
launch 14      r_64_6_2_3_64_3_3         1485/43584 differ, max 3.58e-7 absolute
launch 15      r_192_3_2_2               exact (max_pool)
launch 16      r_10_144_4                exact (Linear)
bit-exact 10/10
```

**⇒ THE HONEST CLAIM IS NOT "THE GPU EQUALS THE CPU ELEMENTWISE".** It is: the
**logits are bit-identical**, both max-pools and the final `Linear` are
bit-identical, and the four convolutions differ by at most **3.6e-7
absolute**. The conv difference is f32 accumulation order: the CPU is compiled
`-O2` with no `-ffp-contract=off` (`compiler_cpu.py:21`), so clang fuses a
multiply-add that WGSL does not.

**⇒ AND WHAT THE PAGE IS NOT: it is a REPLAY OF A CAPTURED CPYTHON TRACE.**
`net.json` carries the 17 kernels' WGSL as `tinygrad/renderer/wgsl.py` emitted
them, plus the binding order and the dispatch geometry. `mnist-webgpu.js`
contains no arithmetic — it decides only what CPython decided. **So the browser
runs the port's CALL LAYER and tinygrad's SHADER, and CPython did the
SCHEDULING.** That distinction is the whole of the gap to a portable pipeline.

---

## 2. THE PORT'S OWN PIPELINE, MEASURED LINK BY LINK

The question a browser target actually asks is: **can the PORT turn a model into
kernels, without CPython?** Five links, all present:

| # | link | where | measured |
|---|---|---|---|
| 1 | `run_rangeify` + 6 engine stages | `schedule/rangify.bend` (`rr_kernel_graph`) | `rr_kg` = `SINK(AFTER(PARAM, END))` |
| 2 | `create_schedule` | `schedule/__init__.bend:1143` | **0 → 1 kernel** once rangeified |
| 3 | `linearize` | `codegen/late/linearizer.bend:836` | 10 of 10 nodes |
| 4 | `kuconv.convert` | `renderer/kuconv.bend:432` | 10 of 10 `KU` |
| 5 | `C.render` | `renderer/cstyle.bend:2297` | **198 bytes of C** |

### 2.1 THE MEASUREMENT THAT MOVED THE NEEDLE

`realize.bend` reads `rz_lin_n=0`: the port's own `schedule()` on the port's
own sink answers **zero kernels**. The reason is that the sink's `AFTER` has a
`STORE` as its second src, and `_split_after` partitions an AFTER's srcs into
KERNELS and dependencies — **and a STORE is not a kernel**.

`sc_is_kernel` (`schedule/__init__.bend:276`) counts `CALL` **or `END`**. So
rangeifying the sink — the step that turns the STORE into an `END` — is exactly
what makes it schedulable.

```
$ ./bin/bend .agents/slop/browser/schedbridge.bend
bridge_lin_raw=0
bridge_lin_ranged=1
bridge_dump_ranged=SINK:none:AFTER;AFTER:none:PARAM,END;END:none:STORE,RANGE,RANGE;...
```

**⇒ AND CPYTHON AGREES, ON THE SAME PROGRAM:**

```
$ .venv/bin/python .agents/slop/browser/oracle_sched.py
py_lin_raw=0
py_lin_ranged=1
py_ops=7111
py_kernel[0]=Ops.CALL
```

**⇒ 0 → 1 ON BOTH SIDES. THIS IS THE FIRST TIME THE PORT'S SCHEDULER HAS
PRODUCED A KERNEL ON THE PORT'S OWN PROGRAM.** The rangeify work (`rangify.bend`,
fixed this session — the driver did not compile) is what closed it.

### 2.2 THE WHOLE CHAIN COMPOSES

```
$ ./bin/bend .agents/slop/browser/fullchain.bend
chain_kernel_op=6            # gate.code(STORE)=6
chain_kernel_nsrc=2
chain_lst_n=10               # the kernel's toposort
chain_linear_n=10            # linearize
chain_ku_n=10                # kuconv
chain_c_nbytes=198           # render
chain_c=
void test(float* restrict data0_20, float* restrict data1_12) {
  for (weakint Lidx0 = 0; Lidx0 < ; Lidx0++) {
    for (weakint Lidx1 = 0; Lidx1 < ; Lidx1++) {
      *(data0_20+Lidx0) = data1_12;
}
```

**⇒ AND THIS IS `void test() { * = ; }` NO LONGER** — the first attempt passed
the kernel's two DIRECT srcs to `linearize`, and upstream's `linearize`
toposorts INTERNALLY (`linearizer.py:7`: `lst = list(sink.toposort())`), so the
port's caller owes the toposort. **The 198-byte kernel is a real kernel.**

---

## 3. THE FOUR NAMED DEFECTS THAT STAND BETWEEN 198 BYTES AND A MODEL

CPython's C for the SAME program, from CPython's OWN `do_to_program`:

```
$ .venv/bin/python .agents/slop/browser/oracle_fullchain.py
py_lin_n=1
py_kernel[0]=Ops.CALL
py_c_nbytes=547
void r_4_5_3(float* restrict data0_20, float* restrict data1_12, float* restrict data2_15) {
  for (int Lidx1 = 0; Lidx1 < 4; Lidx1++) {
    int alu0 = (Lidx1*3);
    float val0 = (*(data1_12+(alu0+1)));
    float val1 = (*(data1_12+(alu0+2)));
    float val2 = (*(data1_12+alu0));
    for (int Lidx2 = 0; Lidx2 < 5; Lidx2++) {
      float val3 = (*(data2_15+(Lidx2+10)));
      float val4 = (*(data2_15+(Lidx2+5)));
      float val5 = (*(data2_15+Lidx2));
      *(data0_20+((Lidx1*5)+Lidx2)) = ((val2*val5)+(val0*val4)+(val1*val3));
    }
  }
}
```

The comparison, side by side:

| what | CPython | the port | the defect |
|---|---|---|---|
| kernel root | `CALL` | `STORE` | **D1: `split_kernels` is a stub** |
| bytes | 547 | 198 | |
| buffers | 3 | 2 | `data2_15` is missing |
| RANGE trip count | `Lidx1 < 4` | `Lidx0 < ;` | **D2: the RANGE's CONST src is not read** |
| loop dtype | `int` | `weakint` | **D3: weak dtypes are not lowered** |
| braces | balanced | one `}` short | follows D2/D3 |
| the arithmetic | `val2*val5 + val0*val4 + val1*val3` | absent | follows D2 |

**D1 — `split_kernels` IS A STUB, AND IT IS THE ONE THAT MAKES A KERNEL A
`CALL`.**

```bend
# tinybendygrad/schedule/rangeify.bend:811
def sk_0(+ar: O.Arena, self: U32) -> M.Hop: M.Hop{ar, 0}
```

Upstream (`rangeify.py:326-335`) builds
`ret.sink(arg=KernelInfo()).call(*lctx.map.values())`. **⇒ AND THE PORT HAS
`KernelInfo` ALREADY** (`c2fbda4ca` made it upstream's six fields), so this is
a missing CALL and not a missing type. **This is the single most load-bearing
gap: a `CALL` is what carries the `KernelInfo` that `to_program` asserts on.**

**D2 / D3 are in `kuconv.bend`'s field extraction**, and both are visible in
the rendered text rather than inferred: a RANGE with no trip count and a
`weakint` that the renderer should have lowered.

### 3.1 D3 IS MEASURED EXACTLY, AND IT IS SEVEN OF TEN NODES

`.agents/slop/browser/kudump.bend` dumps every `KU` field the renderer reads,
because a wrong C text names neither the dtype nor the srcs.

```
$ ./bin/bend .agents/slop/browser/kudump.bend
ku=k_op=STORE nsrc=2
ku=k_srcs=INDEX,PARAM
ku=topo_n=10
ku=linear_n=10
ku=topo_ops=CONST,PARAM,CONST,RANGE,CONST,RANGE,INDEX,CONST,PARAM,STORE
ku=CONST:800:WI:A:1:0:c20/0
ku=PARAM:32:F:G:20:1:p0
ku=CONST:800:WI:A:1:0:c12/0
ku=PARAM:32:F:G:12:1:p1
ku=CONST:800:WI:A:1:0:c4/0
ku=CONST:800:WI:A:1:0:c5/0
ku=RANGE:800:WI:A:1:1:r1
ku=RANGE:800:WI:A:1:1:r1
ku=INDEX:32:F:G:1:3:-
ku=STORE:0:V:G:1:2:-
```

The field order is `op:bits:class:addrspace:numel:nsrc:arg`.

**⇒ D3, CONFIRMED AND EXACT: SEVEN OF THE TEN NODES CARRY `WI`
(`S.CWeakInt`) — every `CONST` and both `RANGE`s.** CPython renders those as
`int`. A `weakint` and an `i32` are BOTH 32 BITS and differ ONLY in this
field, which is why a row that dumped the bits alone could never see it —
and `kudump.bend` dumps the class for exactly that reason.

**⇒ AND `linearize` IS NOT DROPPING ANYTHING: `topo_n=10`, `linear_n=10`.**
So the missing arithmetic is NOT a `linearize` defect.

### 3.2 THE TWO READINGS THAT DISAGREE, AND IT IS NAMED RATHER THAN GUESSED

**`k_srcs=INDEX,PARAM`** — the kernel the scheduler SELECTED is
`STORE(INDEX, PARAM)`, which is a **COPY** and carries no arithmetic.

**But `rr_dump` on the rangeified graph says `STORE:none:INDEX,REDUCE`** —
the same op with a `REDUCE` as its second src.

**⇒ THE TWO OF THE TREE's OWN READINGS DISAGREE ABOUT ONE NODE, AND I DID NOT
PICK A WINNER.** The candidates, each checkable:

1. **the scheduler's rewrite is the difference**: `SCH.schedule` CONSUMES the
   arena and returns `Lin{ar, …}` with a GROWN one, and `create_schedule`
   legitimately rewrites (`pm_replace_buf` swaps BUFFER for PARAM). So `k` is
   in the NEW arena and `rr_dump` read the OLD one. **⇒ IF SO THIS IS NOT A
   DEFECT AND THE COMPARISON IS BETWEEN TWO DIFFERENT GRAPHS** — which would
   make my `fullchain` measurement compare the wrong pair.
2. **the scheduler rewrote the REDUCE away**, which would be a real defect.

**⇒ AND THE INSTRUMENT THAT SETTLES IT IS ONE ROW: dump `rr_dump` of the graph
IN THE SCHEDULER's ARENA, which is what `k` lives in.** That row does not exist
yet, and it is the next thing to write. **A FINGERPRINT COMPARISON ACROSS TWO
ARENAS IS NOT A COMPARISON, AND I AM NOT REPORTING IT AS ONE.**

**⇒ AND ONE FACT IS INDEPENDENT OF THAT QUESTION: THE KU LIST HOLDS TWO
`PARAM`s WHERE CPYTHON HOLDS THREE.** `data2_15` — the rhs matrix — is absent
from the port's kernel under either reading.

---

## 4. MNIST TRAINING: THE WALL IS `backward`, AND IT IS ONE GREP

```
$ grep -rn "tn_backward" --include='*.bend' tinybendygrad/ | grep -v tensor.bend
  (all hits are PROSE in stub files)
```

**⇒ `compute_gradient` (`mixin/gradient.bend:1581`) EXISTS, 69 `gr_*` rules
EXIST, `tn_backward` (`tensor.bend:2015`) EXISTS, AND NOTHING CALLS IT.** The
oracle `oracles/bwd-oracle.rows` holds exactly two rows:

```
tn_bwd_row=CONST/0 BUFFER/0 MUL/2 ADD/2 BUFFER/0 CONST/0 MUL/2 CONST/0 | writes=3
tn_bwd_grad=CONST/0
```

So the backward pass is written and **unexercised**. `.agents/slop/BACKWARD-WALK.md`
records **15/15 rows AGREE with CPython** on the `_deepwalk` half, with two
plants that move rows and two disarms that correctly do not.

**⇒ AND `.agents/TODO.md` RECORDS THE FIX THAT ALREADY LANDED THIS SESSION:**
`mixin/gradient.bend` went **0/494 → 174/495** and all 32 rules `gr_0..gr_31`
are reached, because two new corpus graphs (`grad`, `gral`) call it —
**and `gral` disagreed on its first run and found a REAL port defect** (the max
gradient rule built four `WHERE` nodes where CPython builds three).

**⇒ SO TRAINING IS CLOSER THAN THE `tn_backward` GREP SUGGESTS**, and the
remaining work is measurable: the optimizer (`nn/optim.bend`, 1 TODO), the loss
(`47` TODOs across `nn/`), and wiring `backward` into a training loop.

---

## 5. IMAGENET: THREE WALLS, EACH NAMED WITH ITS LINE

### 5.1 THE MODEL IS A STUB

```
$ head -18 tinybendygrad/extra/models/resnet.bend
# STUB -- 1:1 PATH MIRROR of extra/models/resnet.py (170 LOC). NOT YET PORTED.
```

All 15 model files (`resnet`, `efficientnet`, `convnext`, `vit`, `inception`,
…) are in this state. **But the LAYERS landed**: `nn_conv2d`
(`nn/layers.bend:937`), `nn_linear` (`:530`), `pool_bn` (`nn/pool.bend:382`),
`pool_maxpool` (`:251`). **⇒ `nn/__init__.bend` STILL HOLDS ZERO `nn` LAYER
CLASSES** — it is 429 lines of shape arithmetic.

### 5.2 THE IMAGENET LOADER IS DONE

`extra/datasets/imagenet.bend` (520 lines) ports `get_train_files`,
`get_val_files`, `get_imagenet_categories` with a real `json.loads`
replacement. **⇒ NOT THE BLOCKER.**

### 5.3 THE BROWSER PAGE IS UPSTREAM's, NOT THE PORT's

`examples/webgpu/efficientnet/index.html` imports `../../net.js` and
`../../net.safetensors`, and **neither exists**:

```
$ ls examples/net.js
ls: examples/net.js: No such file or directory
```

So the ImageNet page is a *pointer at a build artifact* that a separate
`compile_efficientnet.py` run produces. **⇒ AND THAT PATH IS UPSTREAM's WHOLE
PIPELINE**, not the port's.

---

## 6. WHAT IS PROVEN AND WHAT IS NOT

**PROVEN, with a gate and a plant for each:**

- **`checks/e2e.py` is GREEN ON ALL SEVEN STAGES** (this session):
  `--- verdicts: 0 failed, 0 skipped --- / PASS -- every stage ran and every
  stage agreed.`
- **The port's own renderer executes a 4-buffer matmul**: 64/64 u32 words
  bit-identical to CPython, `diff bytes: 0`, and **all four negative controls
  RED** (`C0` green, `C1`–`C4` red, plus the 5 inherited `portexec` plants).
- **The port's own pipeline is f64-correct**: 64/64 u32 words (32 doubles),
  `0x3ff0000000001000`, port C text == CPython's.
- **Five real MNIST CPU kernels**, end to end through the port's own
  `cstyle` → `cc` → `elf` → `mmap` → call: **`max_abs=0`, `max_rel=0`**, with
  the plant red on all five (`.agents/slop/cpuseam/verify.sh`).
- **The port's `run_rangeify` driver compiles** (it did not: `sink (consumed
  more than once)` at `rr_run_rangeify`) and its comparison harness reads
  `VERDICT PASS`.
- **The port's scheduler produces a kernel** from the rangeified graph: `0 → 1`,
  matching CPython's `0 → 1`.

**NOT PROVEN, and not claimed:**

- **The port cannot run a MODEL.** It can schedule and render ONE kernel. §3's
  four defects are what stand between that and a model.
- **MNIST training in the browser.** `backward` is unexercised in the port.
- **ImageNet at all.** The model is a stub.
- **The 198-byte kernel is not correct C.** It is real C with an empty trip
  count; it would not compute the right answer.

---

## 7. THE ORDER I WOULD DO IT IN, AND WHY

1. **D2 + D3 (`kuconv` RANGE CONST and weak dtypes).** Smallest, and they are
   the difference between "C that compiles" and "C that is a kernel". A
   RANGE-with-no-trip-count is a one-field read.
2. **D1 (`split_kernels`).** It is a `CALL` construction, and `KernelInfo`
   exists. **⇒ AND IT IS WHAT MAKES THE PORT's OUTPUT COMPARABLE TO CPython's
   BY ROOT OP**, which every later gate wants.
3. **A `schedule → render → compile → run` E2E on ONE real MNIST kernel**,
   replacing the `gen_kus.py` generated fixture with the port's own
   `kuconv`. That is the moment the pipeline stops being a composition of
   measured parts and becomes a measured pipeline.
4. **`backward` into a training loop.** The rules are written and 15/15 agree;
   what is missing is a caller and a loss.
5. **ImageNet last**, because it is 15 model files and needs 1–4 to be real.

**⇒ AND THE BROWSER NEEDS NONE OF THAT.** A page that runs the port's own
`kuconv`+`render` output on WebGPU needs links 3–5 only, and links 3–5 are
measured. **⇒ SO THE SHORTEST PATH TO "A MODEL IN THE BROWSER, THROUGH THE
PORT" IS: fix D2/D3, then render ONE MNIST kernel through the port and dispatch
it, and compare its output word against the replayed trace's.**

---

## 8. THE FILES

| file | what |
|---|---|
| `.agents/slop/browser/schedbridge.bend` | **THE 0 → 1 MEASUREMENT.** raw vs rangeified, `bridge_lin_raw=0` / `bridge_lin_ranged=1`. |
| `.agents/slop/browser/oracle_sched.py` | CPython's own answer for the same two, and the same `gate.code` alphabet. |
| `.agents/slop/browser/fullchain.bend` | **THE WHOLE CHAIN**: schedule → linearize → kuconv → render. |
| `.agents/slop/browser/oracle_fullchain.py` | CPython's own C for the same kernel, via `do_to_program`. |
| `tinybendygrad/schedule/rangify.bend` | the `run_rangeify` driver — **FIXED THIS SESSION** (`sink (consumed more than once)`). |
| `tinybendygrad/runtime/ops_bend.bend` | **FIXED THIS SESSION**: `PKT_DIR` pointed at the pruned tree. |
| `checks/e2e.py` | **7/7 GREEN**, and the fixture repairs that got it there. |
| `examples/webgpu/mnist/` | **THE BROWSER PAGE THAT RUNS TODAY**, 10/10 bit-exact. |
| `.agents/slop/cpuseam/` | the 5-MNIST-kernel byte-exact measurement. |

---

# 9. UPDATE 2026-10-31, LATER THE SAME DAY: TRAINING RUNS, AND D2 IS RETRACTED

**Everything in §1-§8 stands EXCEPT the attribution of D2, which §3.2 already
hedged and §9.2 now settles. Three things moved.**

## 9.1 MNIST TRAINS IN THE BROWSER

    node .agents/slop/browser/train-gate.mjs
    PASS -- one MNIST training step, replayed on the adapter, leaves 47 of 47
    TENSOR buffers (weights, gradients, moments) BIT-EXACT against CPython,
    180782 words compared

One training step -- forward, `sparse_categorical_crossentropy`, the gradients,
the SGD update -- is **90 kernel launches**, and the browser replays all of them
on a real adapter (`apple/metal-3`). **⇒ AND THE STRENGTH OF THE ROW IS ITS
DENOMINATOR: 47 TENSOR buffers and 180 782 words, not one loss scalar.** A GPU
that computed nothing and kept its uploads would fail C1, which is a control in
the gate.

**⇒ AND ONE THING IS NAMED AND NOT FIXED**: a single 1-word scalar, the loss,
differs (`3.9493408203125` where CPython has `2.7735066413879395`). **⇒ AND THE
GATE'S FIRST EXPLANATION FOR IT IS RETRACTED IN THE GATE'S OWN OUTPUT**, because
measurement disproved it: the read-side copy was removed, the alias collapsed to
one binding, and the value did not move. It is not a weight; the next instrument
is a per-launch ladder on `b23`.

## 9.2 D2 IS D1's CASCADE, AND MY §3 ATTRIBUTION WAS WRONG

`.agents/slop/browser/arenas.bend` dumps the SAME graph in the arena it lives
in, which is what §3.2 said was needed:

    A_ranged_n=22   STORE:none:INDEX,REDUCE     <- the arithmetic IS there
    B_sched_n=10    STORE:none:INDEX,PARAM      <- it is GONE
    C_sched_dump    STORE:none:INDEX,PARAM      <- the SAME reading, same arena

**⇒ SO THE TWO READINGS ARE CONSISTENT AND THE ARITHMETIC IS GENUINELY LOST**,
and `.agents/slop/browser/d1arity.bend` says why in two rows:

    D1_a_store_before=STORE(INDEX,REDUCE)  store_after_replace=STORE(INDEX,PARAM)
    D1_b_call_before=CALL(STORE,PARAM)     call_after_replace=CALL(STORE,PARAM)

`replace` (`schedule/__init__.bend:1063`) is **CORRECT** and only its **SUBJECT**
was wrong. Upstream asserts `k.op is Ops.CALL` before it
(`schedule/__init__.py:69`); Bend has no `raise`, so the assert became nothing
and a CALL-shadows rewrite ran on a STORE, replacing its value with a buffer-uop.

**⇒ ⇒ ⇒ SO D2 IS NOT A `kuconv` FIELD BUG AND FIXING `split_kernels` FIXES BOTH.**
**⇒ AND THE WEAK DTYPES (D3, seven of ten KU nodes `CWeakInt`) ARE STILL A REAL
SEPARATE DEFECT**, measured in `.agents/slop/browser/kudump.bend`.

## 9.3 IMAGENET TRACES COMPLETELY, AND WEBGPU REFUSES 12 SHADERS

EfficientNet-0: **328 launches, 0 unrendered**. WebGPU then rejects **12 of the
328**, and every one is a depthwise or grouped conv, and **the unbalance is in
tinygrad's own WGSL** (counted on the trace, before any page transform). The
account is `.agents/slop/browser/IMAGENET.md` and the census is
`imagenet/wgsl-braces.rows`, 328 rows.

## 9.4 THE TRACER WAS STALE AND DEAD, WHICH IS WHY NONE OF THIS RAN

`xd2/trace_forward.py` now raises `AttributeError: 'Buffer' object has no
attribute 'size'`. **⇒ NOTHING READ IT, SO NOTHING NOTICED** -- the tree's own
class. The re-point is `.agents/slop/browser/trace_common.py` (322 lines, a NEW
path, because a script others execute is shared state), and it carries FOUR
measured migrations, ONE measured bug and ONE measured wall:

| what | why |
|---|---|
| `Buffer.size` -> `nbytes` | `device.py:116` sets only `device, nbytes, offset, base` |
| `Buffer.dtype` -> the CALL's uop | `Buffer` has no `dtype` at all any more |
| `ProgramInfo.vals` -> `kernel_params` | the re-vendor dropped `vals` (`a6addc2d4`) |
| `ProgramInfo.function_name` -> `ast.arg.name` | `ProgramInfo` has no such field |
| **the `vals` drop was a BUG** | it built bind groups with too few entries, so **every kernel taking a scalar did not run** -- 26 of 50 buffers agreed and the rest held `0` or `1.0f` |
| **`DEV=CPU` before import** | with no `DEV`, darwin defaults to `METAL`, so the traced ast was a METAL kernel and WGSL died with `long decomposition of variable None` -- **and the evidence was two u64 PARAMs named `mtl_cb` and `mtl_enc`** (`ops_metal.py:104`) |
| **`DMC=1`** | one of 90 training launches cannot coalesce (`gated loads/stores`); `DMC=0` renders 89, `DMC=1` renders 90 |
| **`f32` -> `w32` snapshots** | the LABEL is an i32 buffer; an `f32` filter meant it was never uploaded and the loss came back `0` |

**⇒ AND WEBGPU REFUSES TWO SHAPES TINYGRAD EMITS, BOTH MEASURED REFUSALS, NEITHER
A NAMED WALL IN ANY DOC BEFORE TODAY**: a buffer declared `read_write` at several
bindings (writable aliasing), and a shader/layout pair that must agree about
which binding is an output. **⇒ AND THE FIRST VERSION OF THE PAGE HAD NO ERROR
SCOPE**, so a refused dispatch read as a number that never changed -- which is
the `SKIP IS NOT PASS` failure with a GPU in it.
