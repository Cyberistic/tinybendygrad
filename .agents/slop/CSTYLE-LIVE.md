# CSTYLE-LIVE — `renderer/cstyle.bend`'s emitted C, compiled, run, and called from Bend

Unit: **cstyle-live**. Slot: take `render_kernel` from recorded text to a running kernel.
**Reached: Stage 4 of 4.** Nothing committed. `renderer/cstyle.bend` was **not edited** — its
sha256 is `07ae2766f891e9a85bed84c416bab21f9a17c143730aa26383d685998c97eb7f` before and after
this unit, and `.agents/slop/cstyle-gate.py` was **not** edited (only imported).

Reproduce EVERYTHING, from a clean `$TMPDIR`, with one command:

```
zsh .agents/slop/cstyle-live/run-all.sh
```

It snapshots the whole `tinybendygrad/` tree into `$TMPDIR`, asserts the snapshot's
`cstyle.bend` is byte-identical to the live one, copies in the single `.bend` this unit adds,
and runs Stage 0 (tree health) → Stage 1 → Stage 2 → Stage 3 → Stage 4. The stages are also
runnable alone (`stage1.sh`, `stage2.sh`, `stage3.sh`) once the snapshot exists.
Logs: `run-all.log`, `stage1.log`, `stage2.log`, `stage3.log`.

**Verified from a completely clean `$TMPDIR` at the end of the unit:** `STAGE 2: PASS`,
`STAGE 3: PASS`, byte-identity on both sides at sha256 `b5a0753d…`, and every Stage 1 and
Stage 4 number reproduced exactly. Bench: `bend 2.0.35` (re-measured today, not read off
`WALL 4`), Apple clang 17.0.0.

---

## 0. ONE CORRECTION TO THE SLOT'S PREMISE, MEASURED

The brief says `cstyle-gate.py:554` reads the port's stdout from a file, so the 222 rows
compare two recorded texts. **That is the CAPTURE path, and it is not the default.** Line
554-555 is one conditional:

```python
p = (subprocess.CompletedProcess([], 0, pathlib.Path(a.port_stdout).read_text(), "")
     if a.port_stdout else run(["./bin/bend", PORT]))
```

and with no `--port-stdout` the gate runs the port. Measured, just now, on this tree:

```
live port lane rc=0   live oracle lane rc=0
gated 221   agree 221   disagree []
STALE-LITERAL 0 port `py=` literal(s) disagree with the live call: []
AGREE
```

So the gate is **LIVE-vs-LIVE as text**: a live `bend` process against a live CPython process,
221/221 rows agreeing, 6 declared exclusions, 13 CPython refusals named on stderr.

**And the slot's real point survives that correction intact.** What no lane has ever done is
spend one of those strings on a compiler. Every row is a comparison on **newline-escaped
text** (`esc_row`, `cstyle.bend:1808` — its own comment: *"A ROW IS ONE LINE … a row whose text
contains a newline is invisible"*), so 227 measurements have been taken with the escape still
on. Nothing downstream has asked what the text looks like after the escape is undone, which is
the only form a compiler accepts. That is what this unit did.

---

## 1. STAGE 1 — DOES THE PORT'S EMITTED C COMPILE?

### 1a. The gate's own `kern2 CLANG` row: **NO**, and here is the error

`kern2 CLANG` is the row that is the port's `render_kernel` on the Clang device, the device
`ops_cpu.py` actually compiles. Its value, unescaped:

```c

void E_4(float* restrict data0_4, float* restrict data1_4) {
  float4 val0 = (*((float4*)((data1_4+0))));
  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f)};
}
```

Invocation (the flags are `ClangCompiler.compile`'s, `tinygrad/runtime/support/compiler_cpu.py:14-17`,
minus `-nostdlib`/`--target=…-none-unknown-elf`, which only matter for a kernel destined for
`mmap` + `dllopen` rather than for a host program):

```
$ cc -c -x c -O2 -fPIC -ffreestanding -fno-math-errno -fno-ident gate_kern2_clang.c -o gate_kern2_clang.o
```

**FAILS at step 2 (`cc`), 6 errors, first at `gate_kern2_clang.c:3:3`:**

```
gate_kern2_clang.c:3:3: error: use of undeclared identifier 'float4'; did you mean 'float'?
gate_kern2_clang.c:3:21: error: use of undeclared identifier 'float4'; did you mean 'float'?
gate_kern2_clang.c:3:28: error: expected expression
```

**WHICH OF THE FOUR STEPS BROKE: step 2, `cc`.** step 1 (`bend`) succeeded, step 3 (link) was
never reached, step 4 (run) was never reached.

### 1b. WHY — and it is a FIXTURE gap, not a port defect, and that is measured not argued

`float4` is not a C type. `ClangRenderer.float4 = "(float4)"` (`cstyle.py:279`) is a tinygrad
pseudo-type; the only thing that ever makes it real is `ClangRenderer._render_defines` →
`render_vector_prefix` (`cstyle.py:303-309`), i.e. the `vecs` field of the port's `Emit_`. The
gate's `kern2` fixture is `emit_min()` — an **empty** `vecs` (`cstyle.bend:282`) — with a body
that reads and writes a `float4`. So the row's text names a type its own fixture never defined.

The port models this correctly: `rk_wrap.of` (`cstyle.bend:1630-1633`) emits the prefix for
Clang only, and `Emit_.vecs` carries it. The *fixture* is what is missing.

### 1c. THE FIXTURE SUPPLIED — and the emitted text is now **byte-identical to CPython's**

`.agents/slop/cstyle-live/cstyle-oracle.py` captures, live with `CCACHE=0` (so `compile` really
is called — with the default warm diskcache `Compiler.compile_cached`, `device.py:339-344`,
never calls `compile` and my first run died on its own assertion guard, which is the guard
working), what tinygrad's CPU backend hands clang for `(a + 1.0)` over four contiguous f32:

```c
typedef float float4 __attribute__((aligned(16),ext_vector_type(4)));
void E_4(float* restrict data0_4, float* restrict data1_4) {
  float4 val0 = (*((float4*)((data1_4+0))));
  *((float4*)((data0_4+0))) = (float4){(val0[0]+1.0f),(val0[1]+1.0f),(val0[2]+1.0f),(val0[3]+1.0f)};
}
```

Feeding CPython's own two lines back in as the `vecs` prefix and the kernel body, the port
emits:

```
$ cc -c -x c -O2 -fPIC -ffreestanding -fno-math-errno -fno-ident live_clang_full.c -o live_clang_full.o
  step2 COMPILED ok (384 bytes of object)
$ diff cpython_real.c live_clang_full.c        # EMPTY
$ shasum -a 256 cpython_real.c live_clang_full.c
b5a0753d3581bea162a8cccfed4f9e1a2d6841feaab39c8ce773af72f744731d
b5a0753d3581bea162a8cccfed4f9e1a2d6841feaab39c8ce773af72f744731d
```

⚠ `cstyle-oracle.py` writes with `sys.stdout.write`, not `print`. `print` appends a newline and
the captured source already ends in one (`render_kernel` is `defines + "\n" + body + "\n" +
_entry`, `_entry` being `""`, `cstyle.py:313-315`), so `print` manufactured a second trailing
newline and the diff reported a missing newline **in the port**. MEASURED.

### 1d. THE BASE-DEVICE ROWS ALSO DO NOT COMPILE, and that is upstream's shape too

`live BASE full` — the same body on `CStyleLanguage` — fails identically at
`live_base_full.c:2:3`. Only `ClangRenderer` overrides `render_kernel` (`cstyle.py:313`); the
base never emits `_render_defines` at all. So the base cannot produce a compilable `float4`
kernel, and the port is right not to try.

**STAGE 1 VERDICT: the port's emitted C compiles once the one input the fixture withheld is
supplied, and what it then emits is byte-identical to the text CPython itself compiled and
ran. As the gate's own fixture stands, 0 of the 30 `kern2` rows compile — see §4.**

---

## 2. STAGE 2 — DOES IT RUN, AND DOES IT AGREE WITH CPython?

Kernel: the six-line `live_clang_full.c` above. Inputs on disk as raw float32 bytes, never
`printf`'d, so the comparison is over **bits** and endianness cannot silently matter. `out` is
pre-filled with the sentinel `-12345.0f`, which no lane of `in + 1.0f` can produce, so a kernel
that wrote nothing leaves a visibly-not-the-answer file rather than a zero-filled one.

Expectations come from **calling CPython**, never typed — `cstyle-numbers.py` runs tinygrad's
CPU backend, which emits C with `cstyle.py`, compiles it with clang, `mmap`s it and `CDLL`s it
(`tinygrad/runtime/ops_cpu.py:29-72`), and separately the `PYTHON` reference device and plain
float64 arithmetic.

```
=== fixture DISTINCT, input [1.0, 0.1, -2.5, 3.75] ===
  run1 sha256 a078895c70c39d3943510e0822b20347be0e0185dcbece4f363c91ab87e25291
  run2 sha256 a078895c70c39d3943510e0822b20347be0e0185dcbece4f363c91ab87e25291  (identical)
  run1 vs run2: 0 differing bytes
  CPU    00000040cdcc8c3f0000c0bf00009840  [2.0, 1.100000023841858, -1.5, 4.75]
  PYTHON 00000040cdcc8c3f0000c0bf00009840  [2.0, 1.100000023841858, -1.5, 4.75]
  f64    ...  1.1000000014901161, ...                     <- MUST differ, and does
  OK out_DISTINCT_1.bin: got 00000040cdcc8c3f0000c0bf00009840 … differing bytes: 0
  OK out_DISTINCT_2.bin: got 00000040cdcc8c3f0000c0bf00009840 … differing bytes: 0
```

Also run on `TIE` = `[1.0, 2.0, 3.0, 4.0]`, the exact program the text was captured from:
`0000004000004040000080400000a040` = `[2.0, 3.0, 4.0, 5.0]`, **0 differing bytes**, twice.

**THE DIFF AT STAGE 2 IS 0 BYTES, on 4 runs (2 fixtures × 2 processes), against an expectation
produced by a live CPython call.** Written down before the run, run twice, and:
`CPU == PYTHON` bit-for-bit while `f64` **differs** (`1.100000023841858` vs `1.1000000014901161`),
so the fixture is dtype-sensitive. Four DISTINCT inputs, so a lane-reversed kernel fails it.

**NEGATIVE CONTROL, and it is the part that makes the zero mean something:**

```
flipping one low bit of in[1] (0.1f becomes a different float32):
  MISMATCH out_bad.bin: got 00000040ddcc8c3f0000c0bf00009840 … differing bytes: 1
  control PASSED
```

**WHICH STEP BROKE: none.** All four steps green.

---

## 3. STAGE 3 — CALLING IT FROM BEND

`law` + `import "./shim3.c"` + `bend -o` + `cc`, all four steps named in `stage3.log`. The shim
carries the port's own emitted C **verbatim** and `stage3.sh` asserts it with `cmp` before
compiling, so every row below is a claim about a kernel the port rendered.

```
=== step1: bend stage3.bend -o stage3.c  (INLINES shim3.c) ===
  step1 ok, 142090 bytes emitted; the port's text is inside it 1 time(s)
=== step2+3: cc stage3.c -o stage3.out ===
  step2 compiled ok; step3 linked ok
=== step4 ===
  BEND_LIST_INDEX 0 nbytes 16
  C_MMAP_ADDR 4307140608
  BEND_FREE_NBYTES 16
  C_FREE_RETURNS_SAME_ADDRESS 4307140624
  ENTRY_NAT 4305799096
  BEND_LANE 0 1073741824
  BEND_LANE 1 1066192077
  BEND_LANE 2 3217031168
  BEND_LANE 3 1083703296
```

Verdict, on **Bend's own numbers**:

```
  bend    bit patterns: 1073741824 1066192077 3217031168 1083703296
  cpython bit patterns: 1073741824 1066192077 3217031168 1083703296
  MATCH -- all four lanes, bit for bit
```

**The kernel's entry point is carried as a `Nat`** (`ENTRY_NAT 4305799096`): Bend never names
`E_4`, it holds the address and hands it to `call_e4(entry, outp, inp)`, which casts it back to
`void (*)(float*, float*)`. `C_E4_ADDR` on stderr is an independent reading of the same value
in the same process.

⚠ The addresses in that transcript (`C_MMAP_ADDR`, `ENTRY_NAT`, `C_FREE_*`, every `C_ALLOC`) are
**ASLR-dependent and change every run** — two runs of the same binary printed different ones, and
an earlier version of `stage3.sh` compared whole stdout files and reported `run1 != run2` over
nothing but addresses. The four `BEND_LANE` lines are the claim and they are address-free.

### The allocator: ops_bend's, reused — and the one thing that could not be

`tinybendygrad/runtime/ops_bend.bend` is **imported**, and `Mem`, `Mem.of`, `Mem.base`,
`Mem.nbytes`, `first.of`, `raw_alloc` and `raw_free` are used as they are. `raw_free` really is
the no-op it documents, and that is now measured rather than quoted:
`BEND_FREE_NBYTES 16` after freeing, and `C_FREE_RETURNS_SAME_ADDRESS` answers the address it
was given.

What could not be imported is `raw_alloc`'s **backing store**, and the reason is printed rather
than asserted. `ops_bend.bend:1476`'s `raw_alloc` answers `Mem{base = Store.top(s), nbytes}`
where `Store.ms` is a `List<&2, U32>`, so `Mem.base` is an **index into a Bend list**; Bend
exposes no address for a `List` at all. Stage 3 prints both number spaces side by side:

```
BEND_LIST_INDEX 0 nbytes 16      <- ops_bend's allocator: index 0
C_MMAP_ADDR 4307140608           <- the C side: a real address
```

Same contract (one region, bump, never freed), different substrate — and that swap is the whole
difference between ops_bend's allocator, which executes a uop graph, and this one, whose bytes
are handed to a C function that needs an address. **This is the one addition and it is reported
as an addition, not smuggled in as reuse.**

### NEGATIVE CONTROL, strengthened

A control that only checked "the output moved" would pass on a kernel that moved it for the
wrong reason. So the perturbed run is compared against **CPython's perturbed answer**:

```
  bend, perturbed input : 1073741824 1073741824 3217031168 1083703296
  cpython, same input   : 1073741824 1073741824 3217031168 1083703296
  control PASSED: the perturbed run equals CPython's perturbed answer, so the MATCH above is a
  computation and not a coincidence.
```

**WHICH STEP BROKE: none.** All four steps green.

---

## 4. THE CONVERSION — evidence only; `.agents/slop/cstyle-gate.py` was NOT touched

`convert.py` walks all 227 rows with `cstyle-gate.py`'s **imported** `rows_strict`/`split_py`
(never a fork — that file's own docstring records a forked reader being wrong on 4 of 6 shapes),
unescapes each value, and puts every row through `cc -fsyntax-only`. Full per-row table:
`conversion.tsv`. Denominators, because a disagreement count is not a coverage statement:

```
rows EMITTED by the port                 227/227
  of which a TRANSLATION UNIT (is_tu)     29/227
  families of those                       ['hipockl', 'hipocml', 'kern', 'kern2']
rows that COMPILED (cc -fsyntax-only)     12/227
  by family  {'buf2': 5, 'cfo': 7}
  by device  {'BASE': 3, 'CLANG': 4, 'CUDA': 2, 'HIP': 1, 'METAL': 2}
rows that RAN                             0/12
rows that AGREED with CPython             0/227 as ROWS; 1/1 as a KERNEL
```

### The 30 `kern2` rows — the only family whose value is a whole kernel

| count | first error | rows |
|---|---|---|
| 8 | `use of undeclared identifier 'float4'` | `kern2 BASE{,alu,pref2,pref0,vol}`, `kern2 CLANG{,alu,vol}` |
| 10 | `expected identifier or '('` | all 10 `kern2 HIP*` — the text opens `extern "C"`, which is C++, and `-x c++` then gives `'amdgpu_flat_work_group_size' attribute only applies to kernel functions` |
| 6 | `unknown type name 'template'` | all 6 `kern2 CUDA*` |
| 3 | `unknown type name '__kernel'` | all 3 `kern2 OPENCL*` |
| 3 | `'metal_stdlib' file not found` | all 3 `kern2 METAL*` |
| **30** | | **0 compiled as emitted** |

The 8 `float4` rows are §1b's fixture gap. The other 22 are device dialects no host `cc` can
accept. **On all 30 the port is byte-for-byte with a live CPython call** — none of the 30 is in
the gate's 6-row exclusion set, so all 30 are gated, and the gate prints `agree 221 disagree []`
over its 221 gated rows. That is what makes the 22 "not compilable **here**" rather than
"wrong": the text is right and the toolchain is absent.

### So: which rows went from RECORDED to LIVE

**Exactly one row's defect is closed: `kern2 CLANG`.** Not by rewriting the row — the row is
untouched, and its value still does not compile, because that is what CPython emits for that
fixture. It went live as a **KERNEL**: `render_kernel(dev_clang(), "E_4", 1, bs, kernel, emit,
cdna4)`, called with the one argument the gate's fixture withholds, emits text that compiles,
links, runs, and agrees with tinygrad's own CPU backend bit for bit, twice, with a working
negative control, and is reachable **from Bend** with its entry point as a `Nat`.

**Everything else stayed recorded**, and for reasons that are structural rather than
disappointing:

- **219 of 227 are not translation units.** They are `_render_dtype` on one dtype, `code_for_op`
  on one op, `render_index` on one swizzle. A fragment cannot compile, so "compiled" would be a
  statement about the row's shape and not about the port. `convert.py` reports `is_tu` as its
  own column precisely so this is not folded in.
- **12 rows do compile** (5 `buf2` buffer declarations, 7 `cfo` expressions) and none of them ran:
  a `render_buffer` declaration has nothing to execute and a `(X/Y)` expression at file scope is
  a declaration-shaped accident. Reporting a 12/227 compile rate as a quality measure would be
  the "unexplained zero" this project keeps paying for in the other direction.
- **22 of the 30 `kern2` rows are Metal / CUDA / HIP / OpenCL** and cannot be compiled on this
  machine at all. Converting them needs those toolchains, which is a different unit's budget.

**What I did NOT do:** I did not edit `cstyle-gate.py`, I did not add a row to `cstyle.bend`,
and I did not decide what counts as LIVE-VS-LIVE. Another unit is censoring per lane and two
writers of one ledger collide silently. `conversion.tsv` is the evidence; the accounting is
yours.

---

## 5. CONCURRENT-AGENT OBSERVATION (not my bug, and it is a reproducibility hazard)

Mid-session the LIVE tree stopped compiling — `./bin/bend tinybendygrad/renderer/cstyle.bend`
gave **rc=1, zero rows**, twice in a row and identically:

```
- expected : a filled definition (an unfilled law is a dead claim: live code cannot use it)
- observed : i64_dec.go2
Location: i64_dec.go
2583 | def i64_dec.go(+acc: List<&2, String>, x: I64) -> List<&2, String>:
```

`i64_dec.go2` is **not in `cstyle.bend`** — it is in `tinybendygrad/helpers.bend`, which is on
the DO-NOT-TOUCH list and is another unit's. The same file later failed on
`'a decreasing self-call'` at `i64_dec.go:2596`. A `$TMPDIR` **whole-tree** snapshot taken
before that edit reproduced my capture byte-for-byte and stayed green throughout; a
single-file scratch copy would have resolved nothing and produced phantom rows, which is the
wall `agent-core.md` already records. By the end of the unit the live tree had recovered
(rc=0) and its output is `cmp`-identical to my snapshot.

**Snapshots used, named, so any number here is reproducible.** `run-all.sh` prints the live
tree's health and the snapshot's hashes on every run; the final clean run recorded
`helpers.bend` sha256 `edeea04a3131c5e0cc7adb2ae994c16d35c62c76f7575e90d72f910c19189a76` and
`cstyle.bend` sha256 `07ae2766f891e9a85bed84c416bab21f9a17c143730aa26383d685998c97eb7f`, the
latter asserted **IDENTICAL to the live one** — so the one file this unit's mandate covers was
provably untouched while six other units worked. Note `helpers.bend`'s hash MOVED twice during
the session (another unit) while the emitted kernel text stayed at `b5a0753d…` throughout,
which is the invariant that matters. No harness patched the live tree; the two `.bend` files
Stage 1 and Stage 3 add exist only inside the `$TMPDIR` copy, and `emit-real.bend` is kept at
`.agents/slop/cstyle-live/emit-real.bend` and copied in by `run-all.sh`.

---

## 6. THE RULES, appended as C-1 … C-8

At the END of `.agents/slop/notes/bend2-constraints.md`, nothing renumbered, cited by NAME.
Six of the eight are Bend facts that cost real time here and are not in any file I read; two
are about the escape that hid all of this.

### 6b. THE HARNESS'S OWN SIX BUGS — every one caught by a guard, none by a green result

Recorded because a harness that reports its own false positives as findings is worse than no
harness, and because the pattern recurs: **in every case the failure mode was a MISSING value
compared against something, and the report said "difference".**

| # | what it did | how it was caught | rule |
|---|---|---|---|
| 1 | `if stage2-io.py … \| sed; then` — a pipeline's status is `sed`'s, so `stage2-io.py` exiting 1 on MISMATCH was swallowed and the control printed `MISMATCH` on one line and `!! CONTROL FAILED` on the next | read the two lines against each other | take the status from the process, then print it |
| 2 | compared whole `stage3.out` stdout, which carries ASLR addresses, and reported `run1 != run2` | the four lanes were visibly identical one line above | compare the claim, not the file |
| 3 | `awk '$1==k'` with a **two-word** key `BEND_LANE 0`, so every lane read as the empty string and the negative control "passed" for the wrong reason | the empty lane list printed | an absent lane is a harness failure, and it says so |
| 4 | byte-identity block placed **above** the `unlive.py` calls that create the file, so `diff` said `No such file` and the script printed `DIFFER:` | `DIFFER:` with an empty diff body | a missing file is not a difference |
| 5 | the guard added to fix (4) tested `cpython_real.c` for non-emptiness **before** the command that creates it, so it refused to compare a file it had not made yet | it fired on a run where the oracle had worked minutes earlier | a guard that fires on its own harness reports nothing useful |
| 6 | `cp -R src "$W/tree/"` when `$W/tree` did not exist **renames** the directory to `tree`, so every downstream path was missing, the hashes printed empty, and the script reported "the snapshot DIFFERS from the live one — a concurrent agent is mid-edit" and exited 3 | a FALSE ALARM about the very file this unit owns | `mkdir -p` the destination, and check the files exist before hashing them |

Also measured and recorded in the harness rather than in a note, because both are ways a
zero is manufactured rather than found: `CCACHE=1` means `Compiler.compile_cached`
(`device.py:339-344`) never calls `compile`, so an oracle that spies on `compile` captures
nothing and reads as an empty capture; and `DEV=NULL` on this machine **opens** (it is an
amdgpu device, `ops_null.py`) and returns `[0.0, 0.0, 0.0, 0.0]` for this program with no error
at all, so had the emitted kernel also produced zeros it would have been reported as agreement.
`cstyle-numbers.py` uses `PYTHON` for the no-compiler reading and says why.

## 7. WHAT I WOULD DO NEXT, and the one thing that is worth arguing about

The honest headline is that **the gate's central lane was never about compilation and did not
claim to be** — but it also never noticed that it could not be, because 227 rows of escaped text
compile to nothing by construction. The one-line change with the most value is a *fixture*
change, not a renderer change: `emit_min()` should carry the `typedef float float4 …` line
whenever the body names `float4`, or the `kern2` fixture should use a scalar body. Then the
gate's own row is compilable as it stands and this whole report is a regression test instead of
a rescue. **That edit is in `renderer/cstyle.bend`, which is mine — but it changes the gate's
expectations, so I have not made it unilaterally and it needs the coordinator's call.**
---

## 8. THE FILES, all of them mine, none outside `.agents/slop/`

| file | what it is |
|---|---|
| `run-all.sh` | the one command. Snapshot + Stage 0 health + Stages 1-4. |
| `emit-real.bend` | calls `cstyle.bend`'s `render_kernel` three ways; copied into the snapshot, never into the tree. |
| `stage1.sh` / `stage1.log` | does the emitted text compile; byte-identity with CPython's own compiled source. |
| `stage2.sh` / `stage2.log`, `stage2-driver.c`, `stage2-io.py` | does it run and agree; the driver `#include`s the emitted text as its own translation unit. |
| `stage3.sh` / `stage3.log`, `stage3-shim.c`, `stage3.bend.tmpl` | the FFI chain, the shim carrying the port's text verbatim, and the Bend program. |
| `convert.py`, `conversion.tsv` | the per-row conversion inventory with the denominators. |
| `extract.py`, `unlive.py` | the two row readers. Both use `cstyle-gate.py`'s **imported** `rows_strict`/`split_py`; neither forks them. |
| `cstyle-oracle.py` | captures the C source tinygrad's CPU backend really compiles. |
| `cstyle-numbers.py` | CPython's numbers, three independent readings, for the same program. |
| `port.txt`, `port.err` | the port's 227 rows, captured from the snapshot. |

`renderer/cstyle.bend` is untouched. `renderer/cstyle.py` is untouched. `.agents/slop/cstyle-gate.py`
is untouched. **NOTHING IS COMMITTED.**
