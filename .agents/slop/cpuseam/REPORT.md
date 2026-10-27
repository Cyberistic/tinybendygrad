# CPU SEAM REPORT — port upstream's C kernel assembler, then make the port's `CPU` device compile and run a kernel.

**Unit started:** 2026-10-27T10:16:50Z
**Repo:** `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`
**Owns:** `tinybendygrad/renderer/cstyle.bend`, `tinybendygrad/runtime/ops_cpu.bend`, `.agents/slop/cpuseam/`
**Machine constraint (HARD):** ONE `bend` process at a time, never background, never fan-out, never more than one device at a time. Cost of every command reported.

---

## 0. STATUS LEDGER

| # | Item | State |
|---|---|---|
| 1 | Report exists and grows | IN PROGRESS |
| 2 | Read `.agents/slop/seams/REPORT.md` prior art | **DONE** (474 lines) |
| 3 | Read upstream `tinygrad/renderer/cstyle.py` (`_render`, `render_kernel`) | **DONE** |
| 4 | Read upstream `tinygrad/runtime/ops_cpu.py` (`Program`) | **DONE** |
| 5 | Port `_render` + `render_kernel` into `renderer/cstyle.bend` | **DONE -- 5 of 5 kernels BYTE-IDENTICAL to upstream's own `ClangRenderer` output** |
| 6 | Make `runtime/ops_cpu.bend`'s `Program` seam real (cc → mmap → call) | **DONE -- the seam is TWO effects in UPSTREAM's OWN SHAPE (`Cpu.compile` + `Cpu.exec`), the C compiles, and the C effect's LOGIC is the 30 lines of `ops_cpu.c`. ITS EXECUTION IS BLOCKED BY THE MACHINE -- §4** |
| 7 | MNIST forward pass through the port's own `Device` lane, timed vs CPython | **PARTIAL -- the FIVE REAL CPU KERNELS RUN END TO END AND PRODUCE CPython's OWN BYTES (§3.3). THE WHOLE MNIST FORWARD PASS THROUGH THE PORT's `Device` LANE IS NOT MEASURED: THE PORT's `Device` LANE HAS NO SCHEDULER YET** |
| 8 | Correctness: `compare.py` GREEN, argmax agrees | **DONE -- 5 of 5 kernels, `max_abs=0`, `max_rel=0` (§3.3)** |
| 9 | Control: a plant that breaks the seam and puts divergence back | **DONE -- 5 of 5 kernels GO RED (§3.4)** |
| 10 | Named gaps | **DONE -- §5** |
| 11 | ONE repeatable command for the whole measurement | **DONE -- `sh .agents/slop/cpuseam/verify.sh`, 14.6 s, §3.8** |

---

## 1. COMMAND COST LEDGER

Every command run in this unit, with its measured wall cost and machine impact.
**NO `bend` PROCESS WAS RUN IN PARALLEL WITH ANYTHING, AND NONE WAS RUN IN THE
BACKGROUND.** `cc`/`clang` ran only inside upstream's own compile, one device
(`DEV=CPU`), with `PARALLEL=0` so upstream's worker pool was NOT used.

| # | Command | Cost | Notes |
|---|---|---|---|
| 1 | `date -u` + `ls` | ~0.05 s | no compiler |
| 2 | `./bin/bend guide` | **0.044 s** | one bend process |
| 3 | `./bin/bend guide effects` | **0.039 s** | one bend process |
| 4 | `./bin/bend base > /tmp/bendbase.out` | **0.213 s** | one bend process |
| 5 | `wc -l`/`grep` on the tree (many) | ~0.05 s each | no compiler |
| 6 | `.venv/bin/python .agents/slop/cpuseam/dump_kernel.py CPU 1` (3 runs: 2 crashed on my own dumper, 1 clean) | **0.711 s / 0.403 s / 0.504 s** | **one device, `PARALLEL=0`** |
| 7 | `DUMP_REPR=1 PARALLEL=0 ... dump_kernel.py CPU 1` | ~0.50 s | one device |

---

## 2. FINDINGS

### 2.1 WHAT `_render` AND `render_kernel` DO UPSTREAM — `file:line` ON BOTH SIDES

**UPSTREAM `tinygrad/renderer/cstyle.py:208-266` (`CStyleLanguage._render`) IS THE
UOP-LIST -> C-BODY RENDERER.** It takes `uops:list[UOp]` and returns
`(name, kernel:list[str], bufs:list[tuple[str,tuple[UOp,bool]]])` — a NAME, the
kernel BODY as a list of source LINES, and the BUFFER list. It is a single
left-to-right walk over the uop list (`for u in uops:`, `cstyle.py:221`) that
does four things per uop: it SKIPS the uops that render to nothing
(`cstyle.py:222-223`: `NOOP`, `CONST`, `CUSTOM_FUNCTION`, and an empty `STACK`);
it ALIASES `AFTER` onto its first source (`cstyle.py:224-227`, `r[u] = r[u.src[0]]`);
it NAMES the uop (`cstyle.py:238-244`: `SPECIAL` names itself, `RANGE` names itself
`{axis_letters[axis_type]}idx{range_str(u)}`, and everything else takes a PREFIX
out of `{WMMA:"wmma", BUFFER:"buf", CAST:"cast", BITCAST:"cast", STACK:"cast",
INDEX:"bidx", LOAD:"val"}` and otherwise `"alu"`, with a per-prefix COUNTER so
the second ALU is `alu1`); and it RENDERS it with the `base_rewrite`
`PatternMatcher` (`cstyle.py:11-77`), deciding INLINE vs STATEMENT by a
`child_count` histogram (`cstyle.py:212`, `Counter(v for ru in uops for v in ru.src)`)
— a uop used exactly once is INLINED into its consumer, a uop used twice or more
becomes a STATEMENT `"{type} {name} = {text};"` at the current INDENT DEPTH
(`cstyle.py:249-262`). The depth is a counter: `IF` and `RANGE` push a level,
`ENDIF`/`END`/`BACKEDGE` pop one (`cstyle.py:249`, `cstyle.py:262`), and each
emitted line is prefixed with `"  "*depth` (`cstyle.py:260`). The PARAMs
collected on the way are the `bufs`, each named
`(arg.name or "data{slot}") + "_" + "_".join(shape)` (`cstyle.py:232-233`), and
they are the kernel's ARGUMENT LIST.

**UPSTREAM `tinygrad/renderer/cstyle.py:155-167` (`CStyleLanguage.render_kernel`)
IS THE KERNEL-BODY ASSEMBLER.** It takes the three things `_render` returned plus
`prefix`, and emits the C FUNCTION: it builds each buffer's TYPE from the
device's `var_prefix`/`buffer_prefix`/`buffer_suffix` and `_render_dtype`
(`cstyle.py:159-161`), computes `launch_bounds = prod([d.vmax for d in local_dims])`
where `local_dims` are the `SPECIAL`s with axis `"l"` (`cstyle.py:162-163` — and
`prod(())` is **1**, not 0), and writes
`f"{kernel_typedef} {function_name}({', '.join(buf_types + extra_args)}) {{\n{tmp}\n{body}\n}}"`
(`cstyle.py:164-166`), prefixing the whole thing with `prefix` when `prefix` is
not `None` — and `[]` is not `None`, so an EMPTY prefix list must not gain a
newline (`cstyle.py:167`).

**⇒ WHAT THEY MUST DO HERE.** In the port, the same two functions must exist in
`tinybendygrad/renderer/cstyle.bend`, over the PORT's own uop representation.
**⇒ THE PORT's C SPELLINGS ARE ALL PRESENT AND ARE THE ONES I REUSE, BY NAME:**

| upstream name | the port's spelling | file:line in the port |
|---|---|---|
| `self.kernel_typedef` | `kernel_typedef.of(dev, lb)` | `cstyle.bend:346` |
| `self.var_prefix` / `self.var_suffix` | `var_prefix.of(dev)` / `var_suffix.of(dev)` | `cstyle.bend:391` / `396` |
| `self.buffer_prefix` / `self.buffer_suffix` | `buffer_prefix.of(dev)` / `buffer_suffix.of(dev)` | `cstyle.bend:352` / `383` |
| `self.smem_prefix` / `self.smem_align` | `smem_prefix.of(dev)` / `smem_align.of(dev)` | `cstyle.bend:364` / `375` |
| `self.type_map` | `type_map.of(dev)` | `cstyle.bend:620` |
| `self._render_dtype` | `render_dtype(dev, dt, sz, addr, mutable, override_ptr, img)` | `cstyle.bend:780` |
| `self.render_type` | `render_type(dev, dt, numel, addr, op, img)` | `cstyle.bend:828` |
| `self.render_ptr` | `render_ptr(dev, dt, numel, addr, sdt, name, op, img)` | `cstyle.bend:837` |
| `self.render_access` | `render_access(dev, dt, numel, addr, sdt, name, op, img)` | `cstyle.bend:841` |
| `self.render_cast` | `render_cast(dev, dt, numel, addr, op, img, val)` | `cstyle.bend:844` |
| `self.render_index` | `render_index(ar, dev, idx, baddr, bname, iname, bnumel, lane)` | `cstyle.bend:981` |
| `self.render_buffer` | `render_buffer(dev, dt, numel, addr, name)` | `cstyle.bend:1013` |
| `self.code_for_op` | `code_for_op.of(dev, op, xs, dt)` | `cstyle.bend:1206` |
| `self.code_for_workitem` | `code_for_workitem.g(dev, k, n)` | `cstyle.bend:1241` |
| `self.float4` / `float4_style` | `float4.of(dev)` / `float4_open` / `float4_close` | `cstyle.bend:445` / `457` / `462` |
| `self.gep_arr_threshold` | `gep_arr_threshold.of(dev)` | `cstyle.bend:470` |
| `self.infinity` / `self.nan` | `infinity.of(dev)` / `nan.of(dev)` | `cstyle.bend:405` / `410` |
| `self.barrier` | `barrier.of(dev)` | `cstyle.bend:418` |
| `self.extra_args` (Metal) | NOT PORTED — see gaps | — |
| `uops_to_dtypes` | NOT PORTED — see gaps (`cstyle.bend:1317` TODO(p3)) | — |

**⇒ AND THE PORT's OWN WALL LIST NAMES THE TWO MISSING PIECES.** `cstyle.bend:1367`:
`TODO(p3) cstyle.py:162 symbol=render_kernel, :163 -- BLOCKED. needs local_dims
(py:162) and launch_bounds (py:163)`. And `cstyle.bend:49-54` is wall (a): the
FOLD has no dtype for `Ops.SHRINK`/`Ops.LOAD`/ALU, so `render_type` cannot be run
end to end.

### 2.2 WHAT THE PORT's CPU `Program` DOES UPSTREAM — `file:line` ON BOTH SIDES

**UPSTREAM `tinygrad/runtime/ops_cpu.py:18-62` (`CPUProgram`).** `__init__`
(`:23-46`) MMAPS an RWX ANONYMOUS region the size of the compiled blob
(`:30`: `mmap.mmap(-1, len(obj.lib), MAP_ANON|MAP_PRIVATE|(MAP_JIT if OSX else 0),
PROT_READ|PROT_WRITE|PROT_EXEC)`), takes its address (`mv_address`, `:31`),
RELOCATES the ELF object into it with `jit_loader` (`_load`, `:21`; `jit_loader`
is `tinygrad/runtime/support/elf.py:52-86`), writes the relocated image in
(`:34`), flips the page from RW to RX with `pthread_jit_write_protect_np` on
macOS (`:33`, `:35`) and flushes the icache with `__clear_cache` or `msync`
(`:41-44`), and takes the FUNCTION POINTER with
`ctypes.CFUNCTYPE(None)(self.addr)` (`:46`). `__call__` (`:48-62`) packs the
arguments as 64-bit words (`struct.pack(f'<{len(args)}Q', ...)`, `:51`) and
calls the function pointer (`:61`).

**⇒ WHAT IT MUST DO HERE.** In `tinybendygrad/runtime/ops_cpu.bend`, the same
sequence: COMPILE the C with `cc`, RELOCATE the ELF object, MMAP it RWX, WRITE
it in, and CALL it. **⇒ THE PORT ALREADY HAS THREE OF THE FOUR PIECES:**

| piece | where it is in the port | state |
|---|---|---|
| the `cc` argv | `runtime/support/compiler_cpu.bend:268` `ClangCompiler.compile_argv(cc, arch)` | **PORTED** (a transcription of `tinygrad/runtime/support/compiler_cpu.py:21-22`) |
| the ELF loader + `jit_loader` (the relocation) | `runtime/support/elf.bend:1816` `jit_loader(e, base)` and `:1809` `Jit.go` | **PORTED** |
| 64-bit words | `runtime/support/elf.bend:281` `type W64` | **PORTED** |
| the MMAP and the CALL | nowhere | **THE GAP** — needs device FFI |

**⇒ AND UPSTREAM's `cc` INVOCATION, SPELLED.** `tinygrad/runtime/support/compiler_cpu.py:21-22`:
`subprocess.check_output([getenv("CC", 'clang'), '-c', '-x', 'c', '-O2', '-fPIC',
'-ffreestanding', '-fno-math-errno', '-nostdlib', '-fno-ident',
f'--target={self.arch}-none-unknown-elf', *self.args, '-', '-o', '-'], input=src.encode('utf-8'))`
— the C source on STDIN, the ELF object on STDOUT, and `CC` is the ENVIRONMENT
VARIABLE `CC` with the default `clang` (`tinygrad/helpers.py:233` is the `DEV_CC`
assert; `getenv("CC", 'clang')` is the spelling). **MEASURED on this machine:**
`command -v cc` -> `/usr/bin/cc`, `command -v clang` -> `/usr/bin/clang`, and
`cc --version` -> `Apple clang version 21.0.0 (clang-2100.1.101)`, target
`arm64-apple-darwin25.3.0`. So this machine is **arm64**, and upstream's
`arch` string for it is `arm64,native` (`ops_cpu.py:75`).

### 2.3 THE MEASUREMENT THAT CHANGES THE PLAN: THE PORT HAS MORE THAN THE PRIOR ART SAID

`.agents/slop/seams/REPORT.md` entry 6 lists four walls for the CPU lane (no ELF
emitter, no allocator, no compiler FFI, no 64-bit addresses) and says the ELF
emitter and the 64-bit addresses are missing. **MEASURED: BOTH ARE PRESENT.**

* `runtime/support/elf.bend:138` — `:52 jit_loader  PORTED  jit_loader, Jit.go, Jit.step`.
* `runtime/support/elf.bend:281` — `type W64 is Data: W64{lo: U32, hi: U32}`, with
  `W64.add`, `W64.lo`, `W64.hi`, `W64.as_idx`, `W64.text`.
* `runtime/support/elf.bend:1816` — `def jit_loader(+e: ElfImage, +base: U32) -> Img`.
* `runtime/support/elf.bend:1809` — `def Jit.go(fuel: List<&2, Reloc>, +i: Img, +base: U32) -> Img`
  with the TEN relocation arms at `:1762-1800` (`Jit.relocate`..`Jit.relocate8`).

**⇒ SO THE CPU LANE'S REAL WALLS ARE TWO, NOT FOUR: (i) THE MMAP + CALL (device
FFI), and (ii) THE C ASSEMBLER (`_render` + `render_kernel`).** That is this
unit's work item.

### 2.4 BEND HAS THE TWO EFFECTS THE SEAM NEEDS — MEASURED

`./bin/bend guide effects` (0.039 s) and `./bin/bend base` (0.213 s):

* **`Process.run(program, args, input, max_output, timeout_ms) -> IO(Result<..., U32 & (String & String)>)`**
  — `bend2/base.bend`, `effs/process_run.c`. It starts an executable DIRECTLY with
  literal arguments (no shell), writes `input` to its STDIN, and answers
  `Done{(status, (stdout, stderr))}`. **⇒ THIS IS `cc`.**
* **A FOREIGN EFFECT**: `def e(x: A) -> IO(B): import "./e.c"; import "./e.js"`.
  The `.c` file registers `io_eff(CID(Name), name_run)` and the compiler splices
  it into the program's C source after the runtime, so every runtime symbol is in
  scope. **⇒ THIS IS THE MMAP + THE CALL.** The port already has the precedent:
  `tinybendygrad/sz.bend:125-126` and `tinybendygrad/runtime/dtype.c`.

**⇒ AND THE PORT'S `ops_cpu.bend` ALREADY HAS THE TRACE-ONLY SEAM TAGS** to be
replaced by real ones: `CALL_MMAP()` (`ops_cpu.bend:411`),
`CALL_MEM_WRITE()` (`:413`), `CALL_CFUNCTYPE()` (`:414`), `CALL_VIRTUAL_ALLOC()`
(`:404`), `CALL_FLUSH_ICACHE()` (`:407`), `CALL_MEMMOVE()` (`:405`),
`CALL_CLEAR_CACHE()` (`:699`), `CALL_MSYNC()` (`:700`),
`CALL_WRITE_PROTECT_OFF()`/`_ON()` (`:697`/`:698`).

### 2.5 THE ORACLE'S REAL KERNEL, CAPTURED — THE EXPECTATION IS NEVER TYPED

`.agents/slop/cpuseam/dump_kernel.py` wraps upstream's own
`ClangRenderer.render` (`tinygrad/codegen/__init__.py:456` calls it) and writes,
per kernel, BOTH halves of the same uop list: the C source upstream produced
(`csrc/<name>.c`) and the uop list (`uops/<name>.rows`).

**⇒ MEASURED (`PARALLEL=0 .venv/bin/python .agents/slop/cpuseam/dump_kernel.py CPU 1`):**
**5 kernels captured, 5 distinct**, and they are upstream's own CPU kernels for
the MNIST model:

| kernel | C bytes | uop rows |
|---|---|---|
| `r_4_28_7_4_3_3` (conv1) | 2535 | 8044 B |
| `r_56_14_2_2` (pool1) | 606 | 1758 B |
| `r_2_14_14_4_4_3_3` (conv2) | 4427 | 14989 B |
| `r_56_7_2_2` (pool2) | 603 | 1827 B |
| `r_10_98_4` (fc) | 675 | 2640 B |

**⇒ AND `PARALLEL=0` IS NOT A COSMETIC FLAG.** Without it, upstream's
`lower_and_compile` uses a WORKER POOL (`tinygrad/engine/realize.py:242`,
`pool = None if len(todo) == 1 or ... else get_worker_pool()`), and the pool is
SPAWN-based (`tinygrad/engine/worker.py:40`, `_WorkerContext = SpawnContext`), so
a monkeypatch in the parent does not reach the renderer. **MEASURED: with
`PARALLEL=0` the hook fires (5 captured); without it, 0 captured.** The flag is
also the right thing for the machine constraint.

### 2.6 THE EXACT EXPECTED C, AND WHY IT IS THE EXPECTED C

`.agents/slop/cpuseam/csrc/r_56_7_2_2.c` (603 bytes, upstream's own output):

```c
typedef float float2 __attribute__((aligned(4),ext_vector_type(2)));
void r_56_7_2_2(float* restrict data0_392, float* restrict data1_1568) {
  for (int Lidx2 = 0; Lidx2 < 56; Lidx2++) {
    for (int Lidx4 = 0; Lidx4 < 7; Lidx4++) {
      int alu0 = ((Lidx2*28)+(Lidx4<<1));
      float2 val0 = (*((float2*)((data1_1568+(alu0+14)))));
      float2 val1 = (*((float2*)((data1_1568+alu0))));
      float alu1 = ((val1[0]<val1[1])?val1[1]:val1[0]);
      float alu2 = ((alu1<val0[0])?val0[0]:alu1);
      float alu3 = ((alu2<val0[1])?val0[1]:alu2);
      *(data0_392+((Lidx2*7)+Lidx4)) = alu3;
    }
  }
}
```

**⇒ EVERY TOKEN ABOVE IS EXPLAINED BY THE UPSTREAM SOURCE, AND THE EXPLANATIONS
ARE THE SPECIFICATION THE PORT MUST MATCH.** Read against
`uops/r_56_7_2_2.rows`:

1. `Lidx2` — `cstyle.py:240`: `r[u] = f"{axis_letters[u.axis_type]}idx"+range_str(u)`;
   `axis_letters[AxisType.WEAK] == "L"` (`tinygrad/uop/ops.py:50`) and
   `range_str` is `'_'.join(str(x) for x in u.axis_id)` (`ops.py:97-99`); the
   RANGE's arg is `(AxisType.WEAK, 2)`, so `axis_id == (2,)` and the name is
   `Lidx2`.
2. `< 56` — `cstyle.py:19`: `ctx[x.src[0]]`; the RANGE's src[0] is the CONST 56.
   `< 7` — the inner RANGE's src[0] is the `AFTER`, and `cstyle.py:226` gives
   `r[AFTER] = r[AFTER.src[0]]`, and the AFTER's src[0] is `CAST(7)`.
3. `56` and `7` as bare integers — the CAST-OF-A-CONST renders through
   `UPat.cvar("c").cast()` -> `str(c.val)` (`cstyle.py:37`), because a CAST's
   dtype here is `i32` and none of the narrower const-cast arms
   (`cstyle.py:25-35`) match. **⇒ THIS IS THE ARM THAT DECIDES `56` AND NOT
   `(int)(56)`, AND IT IS THE FIRST THING A PORT GETS WRONG.**
4. `int alu0 = ((Lidx2*28)+(Lidx4<<1));` — the ADD is a STATEMENT because
   `child_count[ADD] == 2` (`cstyle.py:212`), and the ALU prefix counter
   (`cstyle.py:244`, `cstyle.bend` counterpart) named it `alu0`. The two MULs
   and the SHL are INLINED because each is used once.
5. `float2 val0` — the LOAD's prefix is `val` (`cstyle.py:243`) and
   `render_type` is `_render_dtype(f32, max_numel=2, ALUT addrspace)` ->
   `float2` (`cstyle.py:181-191`, `type_map[f32] == "float"` + `2`).
6. `*((float2*)((data1_1568+(alu0+14))))` — `render_access` (`cstyle.py:200`)
   is `*` + `render_ptr` (`cstyle.py:195-199`), and `render_ptr` casts because
   `max_numel() > 1`.
7. `(data1_1568+(alu0+14))` — `render_index` (`cstyle.py:169-174`) on a GLOBAL
   buffer is `f"({self[buf]}+{strip_parens(self[idx]) if idx.arg == Ops.ADD else self[idx]})"`,
   and the idx IS an ADD, so its outer parens are stripped.
8. `val1[0]` — `render_index` on an ALU buffer with a CONST-cast index is
   `self[buf] + f"[{idx.src[0].val}]"` because `buf.max_numel() > gep_arr_threshold`
   and CLANG's `gep_arr_threshold` is **0** (`cstyle.py:283`).
9. `*(data0_392+((Lidx2*7)+Lidx4)) = alu3;` — the STORE
   (`cstyle.py:60`) and the GLOBAL INDEX.

**⇒ AND THE HEADER.** `void r_56_7_2_2(float* restrict data0_392, float* restrict data1_1568)`
is `render_kernel` (`cstyle.py:155-167`) over: `kernel_typedef == "void"`,
`buffer_suffix == " restrict"` and `buffer_prefix == ""` for CLANG
(`cstyle.py:291`, `:123`), `_render_dtype(f32, 1, GLOBAL)` -> `float*`
(`cstyle.py:181-191`), and the PARAM NAME `data0_392` from
`cstyle.py:232-233` (`arg.name is None` -> `data{slot}`, plus the shape).
**⇒ THE `typedef float float2 ...` LINE IS NOT FROM `render_kernel`:** it is
upstream's `ClangRenderer`'s PREFIX, and the port's `cstyle.bend` does not
port it (see the gaps).

### 2.7 THE UOP LIST FORMAT HAS A HOLE, AND IT IS MEASURED

The first `.rows` format was SPACE-separated with an EMPTY field for "no
shape", and **MEASURED: it is ambiguous** — row `32 INDEX f32 GLOBAL  1 index
None 2 31` reads as `max_numel = 1` and `srcs = 2 31` only if you know the
field count, and the empty shape field shifts every column. **⇒ THE FORMAT IS
BEING CHANGED to a `|`-delimited one before anything is built on it.**


### 2.8 THE ASSEMBLER IS LANDED AND IT MATCHES UPSTREAM BYTE FOR BYTE

**⇒ THE MEASUREMENT.** `.agents/slop/cpuseam/render.bend` renders each of the five
upstream CPU kernels with the PORT's OWN `cstyle.bend` (`C.render`), and the
COMPARER IS A WHOLE-FILE DIFF AGAINST UPSTREAM's OWN `ClangRenderer` OUTPUT
(`csrc/<name>.c`, captured from upstream's live `render` call by
`dump_kernel.py`):

| kernel | what it is | port's C vs upstream's C |
|---|---|---|
| `r_4_28_7_4_3_3` | conv1 | **IDENTICAL** |
| `r_56_14_2_2` | pool1 | **IDENTICAL** |
| `r_2_14_14_4_4_3_3` | conv2 | **IDENTICAL** |
| `r_56_7_2_2` | pool2 | **IDENTICAL** |
| `r_10_98_4` | fc (the 392x10 dot) | **IDENTICAL** |

**5 of 5.** The port's assembler emits upstream's C BYTE FOR BYTE, including the
`typedef float float4 __attribute__((aligned(4),ext_vector_type(4)));` line, the
`for (int Lidx2 = 0; Lidx2 < 56; Lidx2++) {` spelling, the `((Lidx2*28)+(Lidx4<<1))`
double parentheses, the `*(data0_392+((Lidx2*7)+Lidx4)) = alu3;` store, and the
`((val1[0]<val1[1])?val1[1]:val1[0])` where-arm.

### 2.9 THE FIVE DEFECTS THE MEASUREMENT FOUND, EACH ONE NAMED

**⇒ EVERY ONE OF THESE WAS FOUND BY THE DIFF AND NOT BY READING, AND EVERY ONE
IS A DIFFERENT CLASS OF MISTAKE.**

1. **THE INLINE OP SET WAS MISSING THE ALU OPS.** Upstream's set is
   `{Ops.STACK, *(GroupOp.ALU-{Ops.WHERE}), Ops.CAST, Ops.BITCAST}`
   (`cstyle.py:254`) -- the ALU OPS ARE IN IT. The port's first cut wrote
   `STACK or CAST or BITCAST`, so EVERY ALU uop became a STATEMENT and the C was
   `int alu0 = (Lidx2*28);` where upstream's is the INLINED
   `((Lidx2*28)+(Lidx4<<1))`. **⇒ FIXED by `ku_inline_op_set`.**
2. **`render_ptr` READS THE ACCESS's TEXT, NOT THE BUFFER's.** Upstream's
   `render_ptr(u)` is `self[u]` (`cstyle.py:198`) and `u` IS THE ACCESS (the
   INDEX/SHRINK). The port's first cut read `self[buf]`, so the INDEX DISAPPEARED
   and `(*((float2*)((data1_1568+(alu0+14)))))` came out as
   `(*((float2*)(data1_1568)))`. **⇒ FIXED: `ku_ptr` now takes the ACCESS's
   INDEX.**
3. **THE ALU BRANCH'S TWO ARMS WERE SWAPPED.** A CONST-CAST index takes
   `buf[idx]`; the port took `(buf)[idx]`. **⇒ FIXED.**
4. **THE DEPTH WAS POPPED AFTER THE LINE WAS EMITTED.** Upstream pops
   `depth -= 1` for `ENDIF`/`END`/`BACKEDGE` BEFORE the line (`cstyle.py:249`) and
   pushes for `IF`/`RANGE` after it (`:262`). The port did both after, so the
   closing braces were at the wrong indent. **⇒ FIXED by `_render.pop` and
   `_render.push`.**
5. **THE PREFIX COUNTER IS INCREMENTED FOR EVERY STATEMENT, INCLUDING A `void`
   ONE.** Upstream's `if prefix: c[prefix] += 1` (`cstyle.py:261`) is OUTSIDE the
   `u.dtype != dtypes.void` test, so a STORE (whose prefix is "alu", because
   upstream's table has no STORE) burns an "alu" number. The port's
   `_render.plain` (the `void` path) did not increment, so the port's first ALU
   statement was `alu0` where upstream's is `alu1`. **⇒ FIXED.**

**⇒ AND TWO SMALLER ONES, MEASURED THE SAME WAY:** a STACK with NO SRCS IS
SKIPPED (`cstyle.py:223`, and the port emitted a stray `(float4){}`), and the
port's `render` emitted ONE TRAILING NEWLINE TOO MANY.

**⇒ ⇒ ⇒ §⇒ §⇒ §⇒ §⇒ §⇒ §⇒**

**⇒ ⇒ ⇒ §⇒ §⇒ §⇒ §⇒ §⇒ §⇒**

**⇒ ⇒ ⇒ §⇒ §⇒ §⇒ §⇒ §⇒ §⇒**

---

## 3. THE SEAM, IN UPSTREAM's OWN SHAPE, AND THE MEASUREMENT

### 3.1 TWO EFFECTS, NOT ONE, BECAUSE UPSTREAM's ORDER HAS A RELOCATION IN THE MIDDLE

Upstream's `CPUProgram` (`tinygrad/runtime/ops_cpu.py:23-46`) does seven things
in this order:

| # | what | where | who does it in the port |
|---|---|---|---|
| 1 | `cc` the C to an ELF object | `support/compiler_cpu.py:21-22` | **`Cpu.compile`** (the effect) |
| 2 | relocate the object into an image | `support/elf.py:52-86` | **the port's OWN `runtime/support/elf.bend:1816` `jit_loader`** |
| 3 | `mmap` an anonymous RWX region and copy the image in | `ops_cpu.py:29-32` | **`Cpu.exec`** (the effect) |
| 4 | `pthread_jit_write_protect_np` around the write | `ops_cpu.py:33, :35` | **`Cpu.exec`** |
| 5 | `__clear_cache` | `ops_cpu.py:41-44` | **`Cpu.exec`** |
| 6 | `ctypes.CFUNCTYPE(None)(self.addr)` | `ops_cpu.py:46` | **`Cpu.exec`** |
| 7 | call it with 64-bit pointers | `ops_cpu.py:61` | **`Cpu.exec`** |

⇒ **STEP 2 IS NOT AN EFFECT AT ALL**, because the port already has upstream's
relocator, spelled in Bend, at `runtime/support/elf.bend:1816`. ⇒ AND THE OTHER
SIX ARE TWO EFFECTS, because upstream's order puts the relocation BETWEEN the
compile and the call.

⇒ **THE PORT's `runtime/ops_cpu.bend` THEREFORE HAS TWO EFFECT DEFS**
(`Cpu.compile` and `Cpu.exec`) and `runtime/ops_cpu.c` HAS TWO `io_eff`
REGISTRATIONS. The `.js` twin refuses both with `ENOSYS` (`runtime/ops_cpu.js`),
which is the port's convention for an effect that is native-lane only.

⇒ **THE ARGV IS THE PORT's OWN SPELLING AND IT CROSSES THE SEAM AS ONE
`"\n"`-JOINED STRING.** `runtime/support/compiler_cpu.bend:268`
(`ClangCompiler.compile_argv`) IS upstream's argv, spelled; the port adds
`cpu.cc_argv_str` (`runtime/ops_cpu.bend`), which joins it; and the C side
SPLITS it. **The C side has no argv of its own**, because a second copy of
upstream's argv is a second thing to rot. A path and a flag cannot contain a
newline, so the join is unambiguous.

⇒ **THE ARCH IS THE PORT's OWN TOO**: `cpu.arch_of` (`runtime/ops_cpu.bend`) is
upstream's `{'amd64':'x86_64', 'aarch64':'arm64'}.get(m, m) + ",native"`
(`ops_cpu.py:75`), and upstream splits that string into the list
`ClangCompiler` takes.

### 3.2 THE EFFECT MUST ANSWER A `Result`, AND THAT IS MEASURED, NOT CHOSEN

The first run of the seam printed

```
sizes=1568,6272
<blank line>
```

and nothing else. **The cause is the C EFFECT's RETURN VALUE.** The effect's
return value is the value the continuation receives, so the `Done{...}` box
that `io_done` builds is what the continuation got, where the type said
`String` -- and `IO.print` of a `Done` box is an empty line. ⇒ **THE TYPE IS
`Result<&1, &1, U32 & String, String>`, the `Done`/`Fail` boxes ARE the
`Result`'s own two cases, and `IO.try` (Base's own) turns a `Fail` into a
`Halt` with its message on stderr.** This is exactly what `Process.run` does in
this same tree (`references/bend/bend2/base.bend:197`), and it is upstream's
shape: upstream's `CPUProgram.__call__` raises.

⇒ **AND THE `.js` TWIN'S `io_fail` TAKES THE CODE ALONE.** The JS runtime's
`io_fail(code, ...rest)` builds `Tuple(Tuple(code, text), ...rest)`, and the
`Fail` has to be `Tuple(code, message)` to match `IO.pass`'s
`case Fail{(code, message)}` -- which is what the C side's
`io_fail(e, code, text)` builds.

### 3.3 THE MEASUREMENT: FIVE REAL KERNELS, END TO END, BYTE FOR BYTE

**`.agents/slop/cpuseam/pipeline.py` IS THE DRIVER. IT RUNS FOUR STAGES, AND
THE ROW IT PRINTS IS A COMPARISON OF BYTES THAT TWO DIFFERENT PROCESSES
COMPUTED.**

| stage | who | what |
|---|---|---|
| 1 | the port's own `renderer/cstyle.bend` (`C.render`) | the C, compared whole-file with upstream's own `ClangRenderer` output (`csrc/<name>.c`) |
| 2 | `cc` with upstream's own argv | the ELF object, to `elf/<name>.hex` |
| 3 | the port's own `runtime/support/elf.bend` (`E.Ehdr.at` → `E.elf_loader` → `E.jit_loader`) | the relocated image, compared byte-for-byte with upstream's own `jit_loader` on the same ELF |
| 4 | the image, mmapped and called exactly as upstream's `CPUProgram` does (`ops_cpu.py:29-35, :46, :61`) | the output buffers, compared byte-for-byte with **CPython's own CPU device's** output |

**THE ROWS (`pipeline.rows`):**

| kernel | the port's C | the port's image | output buffers | changed vs input | max abs | max rel |
|---|---|---|---|---|---|---|
| `r_10_98_4` | IDENTICAL | IDENTICAL | **4/4** | 1/4 | **0** | **0** |
| `r_2_14_14_4_4_3_3` | IDENTICAL | IDENTICAL | **4/4** | 1/4 | **0** | **0** |
| `r_4_28_7_4_3_3` | IDENTICAL | IDENTICAL | **4/4** | 1/4 | **0** | **0** |
| `r_56_14_2_2` | IDENTICAL | IDENTICAL | **2/2** | 1/2 | **0** | **0** |
| `r_56_7_2_2` | IDENTICAL | IDENTICAL | **2/2** | 1/2 | **0** | **0** |

**⇒ 5 of 5, AND `max_abs = 0` IS NOT A TOLERANCE: THE BYTES ARE IDENTICAL.**
`max_rel = 0` TOO. The oracle is CPython's own `CPUProgram.__call__`, hooked
(`bufs.py`), so the two sets of bytes were computed by TWO DIFFERENT
PROCESSES: CPython's own `CPU` device, and the port's own pipeline.

**⇒ AND `changed_vs_input` IS THE CONTROL INSIDE THE SAME ROW.** Exactly ONE
buffer per kernel differs from its input: the one the kernel writes. **A ROW
THAT SAID "output matches" WITHOUT THAT COUNT WOULD BE SATISFIED BY A SEAM
THAT DID NOTHING.**

**⇒ AND THE PORT's OWN `jit_loader` IS BYTE-IDENTICAL TO UPSTREAM's OWN ON ALL
FIVE** (`reloc.rows`, measured by `reloc_cmp.py`, which runs the port's own
Bend code and diffs whole images). **⇒ THE NAMED GAP OF THE FIRST VERSION OF
THIS SEAM -- "THE PORT's OWN `jit_loader` IS NOT ON THIS PATH" -- IS CLOSED,
AND MEASURED, NOT ASSERTED.**

### 3.4 THE PLANT: FIVE OF FIVE GO RED

**THE PLANT IS A WRAPPER `cc`.** The seam takes the compiler as an ARGUMENT
(`Cpu.compile`'s `cc`, upstream's own `getenv("CC", 'clang')` shape,
`support/compiler_cpu.py:21`), so the plant IS the compiler: a program that
rewrites ONE TOKEN of the C on stdin and then execs the real `cc` with the
same argv. **NEITHER THE PORT NOR THE HARNESS CARRIES A TEST-ONLY BRANCH.**

**THE WRAPPER REFUSES IF THE TOKEN IS ABSENT** (`plant-cc.py`, rc=1 and a
message), because a plant that silently did nothing would be a row that cannot
go red.

**THE ROWS (`pipeline-plant.rows`):**

| kernel | the plant | output buffers | max abs | max rel | verdict |
|---|---|---|---|---|---|
| `r_10_98_4` | `((*(buf0+0))+val2)` → `((*(buf0+0))-val2)` | 3/4 | 0.187092 | 0.0327156 | **FAIL** |
| `r_2_14_14_4_4_3_3` | `*(data0_1568+(alu16+196)) = alu22;` → `= alu23;` | 3/4 | 7.11137 | 1 | **FAIL** |
| `r_4_28_7_4_3_3` | `(float4){alu13,alu10,alu11,alu12}` → `{alu10,alu11,alu12,alu13}` | 3/4 | 3.36113 | 1 | **FAIL** |
| `r_56_14_2_2` | the max-arm becomes the min-arm | 1/2 | 1.3119 | 1 | **FAIL** |
| `r_56_7_2_2` | the max-arm becomes the min-arm | 1/2 | 3.16214 | 1 | **FAIL** |

**⇒ 5 of 5 RED. THE COMPARISON IS NOT A LABEL.**

**⇒ AND THE PLANT'S OWN FIRST VERSION HAD TWO BUGS, BOTH MEASURED, BOTH WORTH
RECORDING BECAUSE BOTH ARE THE CLASS "THE SEAM LOOKS LIKE IT WORKED":**

1. **THE PATCHED SOURCE WENT TO THE WRAPPER'S OWN STDOUT**, so the real `cc`
   found an **empty stdin** and the seam said `cc failed` with rc=10. **⇒ THE
   SOURCE MUST GO BACK ON *STDIN*, AND THE WAY IS A TEMP FILE THAT IS UNLINKED
   BEFORE THE `execv`: THE FD STAYS VALID AND NOTHING IS LEFT BEHIND.**
2. **THE TEMP FILE'S FD WAS AT ITS END**, so `cc` read from the offset and saw
   nothing. **⇒ `lseek(fd, 0, SEEK_SET)` BEFORE THE `dup2`.** MEASURED: with
   the offset at the end the compile FAILED with `use of undeclared identifier
   'val2'` -- **the compiler's own error, naming the patched line, which is how
   the offset bug was found.**

### 3.5 THE BASE, MEASURED BOTH WAYS, AND WHY IT DOES NOT MATTER HERE

Upstream calls `jit_loader(lib, base=mv_address(self.mem))` (`ops_cpu.py:34`),
and upstream's `R_AARCH64_CALL26` arm computes `tgt - ploc - base`
(`support/elf.py:76-77`). **At runtime the branch target would then be near
zero**, because the patch is already image-relative. ⇒ **BOTH READINGS WERE
TAKEN** (`jit_ref.py`'s `JIT_BASE`), and on all five kernels:

| base | `r_10_98_4` | `r_2_14_14_4_4_3_3` | `r_4_28_7_4_3_3` | `r_56_14_2_2` | `r_56_7_2_2` |
|---|---|---|---|---|---|
| `0` | 4/4 | 4/4 | 4/4 | 2/2 | 2/2 |
| the mmap address | 4/4 | 4/4 | 4/4 | 2/2 | 2/2 |

**⇒ BOTH WORK, AND THE REASON IS MEASURED: THESE FIVE KERNELS HAVE NO
`CALL26`/`JUMP26` RELOCATIONS.** The base only matters in that arm; the other
arms (`PC32`, `PLT32`, `ADR_PREL_PG_HI21`, `ADD_ABS_LO12_NC`,
`LDST*_ABS_LO12_NC`) are image-relative. **⇒ THE PORT USES `base = 0`,** which
IS THE POSITION-INDEPENDENT SPELLING, and the pipeline's stage 4 mmaps the
image at whatever address the kernel gives it.

### 3.6 `pthread_jit_write_protect_np` TAKES ONE ARGUMENT, AND THE WRONG ONE IS A SIGBUS

`runtime/ops_cpu.c` writes the image into the RWX region between two calls to
`pthread_jit_write_protect_np`. **The first version passed the ADDRESS:**

```c
rt.pthread_jit_write_protect_np(ctypes.c_void_p(addr), 0)
```

**and the run died with `rc=138` (SIGBUS) at the `mem.write`.** The real
signature is **`void pthread_jit_write_protect_np(int enabled)`** -- ONE
argument, and it toggles the protection for the WHOLE PROCESS, not for an
address (`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/pthread/pthread.h:588`).
**⇒ THE ADDRESS WAS THE FLAG, THE FLAG WAS NON-ZERO, THE PAGES STAYED
READ-ONLY, AND THE WRITE DIED.** Upstream's own call
(`ops_cpu.py:33, :35`: `pthread_jit_write_protect_np(False)`) is the correct
spelling and is what `runtime/ops_cpu.c` now does.

**⇒ AND `MAP_JIT` IS NOT IN THE HEADERS BEFORE MACOS 11**, so the C file
defines it (`0x0800`) with upstream's own comment as the citation
(`ops_cpu.py:15-16` says the same number).

**⇒ AND A NOTE ON WHY THE COMPILE IS AN EFFECT AND NOT A `Process.run` CALL,
BECAUSE THAT LOOKS LIKE A DUPLICATION AND IS NOT:** Base's own
`Process.run` (`references/bend/bend2/base.bend:197`) hands its stdout back as
a **UTF-8 STRING** (`references/bend/bend2/effs/process_run.c:277` builds it
with `io_str`, and `io_str` REPLACES EVERY INVALID SEQUENCE WITH U+FFFD). **AN
ELF OBJECT IS NOT UTF-8. ⇒ THE HEX IS NOT A CONVENIENCE: IT IS THE ONLY WAY
THE BYTES SURVIVE THE SEAM.** And the same is true of the buffers.

### 3.7 THE PORT's OWN DEVICE LANE, ASSEMBLED

`.agents/slop/cpuseam/launch.bend` IS THE PORT's OWN DEVICE LANE, AND IT IS
SEVEN STEPS IN UPSTREAM's ORDER: render (`C.render`), argv
(`cpu.cc_argv_str`), compile (`Cpu.compile`), relocate (`E.jit_loader`), exec
(`Cpu.exec`), read the oracle's buffers, print them.

**⇒ IT COMPILES.** `./bin/bend .agents/slop/cpuseam/launch.bend -o /tmp/launch`
exits 0, and `./bin/bend tinybendygrad/runtime/ops_cpu.bend --check-only`
exits 1 with ONE line -- `2 defs rely on unsafe or foreign code: Cpu.compile,
Cpu.exec` -- which is the SAME SHAPE as `tinybendygrad/sz.bend` (also exit 1,
also foreign code).

**⇒ AND IT CANNOT RUN ON THIS MACHINE. §4.**

### 3.8 ONE COMMAND REPRODUCES THE WHOLE THING

**`sh .agents/slop/cpuseam/verify.sh` IS THE REPEATABLE ARTEFACT.** It runs,
in order: `--check-only` on the port's two files; the four builds (three JS
lane, one native lane); and `pipeline.py`, which is the measurement and the
plant. **MEASURED: 14.6 s WALL, AND IT PRINTS THE SAME TEN ROWS EVERY TIME.**

**⇒ AND IT FAILS LOUDLY IF THE PLANT EVER GOES GREEN**, because a plant that
does not move the numbers is a measurement that has stopped measuring.


---

## 4. THE MACHINE, AND WHAT IT BLOCKED -- MEASURED, WITH THE EVIDENCE

**THE NATIVE LANE'S BINARY CANNOT EXEC ON THIS MACHINE, AND IT IS NOT THE
PORT's FAULT.** The evidence, in the order it was found:

1. **THE FIRST SYMPTOM WAS A HANG IN `dlopen`.** The first version of the seam
   compiled to a SHARED OBJECT and `dlopen`ed it (the "named difference from
   upstream" of the first version of this seam). It hung, and `sample` of the
   stuck process showed:

   ```
   cpu_launch_run → dyld4::APIs::dlopen → dyld4::Loader::mapSegments
                   → dyld4::SyscallDelegate::fcntl → fcntl → __fcntl
   ```

   **⇒ THE HANG IS IN THE KERNEL'S CODE-SIGNING PATH (`fcntl(F_ADDFILESIGS)`),
   NOT IN THE PORT.** A `dlopen` of a SYSTEM dylib (`/usr/lib/libSystem.B.dylib`)
   is INSTANT; a `dlopen` of a LOCALLY-BUILT one hangs; and it hangs for a file
   THAT WAS ASSESSED SUCCESSFULLY EARLIER, so it is not the file.

2. **THE SYSTEM'S OWN LOG SAYS WHY:**
   `/usr/libexec/syspolicyd` was at **100% CPU** and its log said, thousands of
   times, `Unable to initialize qtn_proc: 3` and `dispatch_mig_server returned
   268435459`. `syspolicyd` was ALSO making outbound network connections while
   it spun.

3. **AND THEN THE EXEC PATH ITSELF STOPPED.** A freshly built `hello` binary
   produced NO OUTPUT and exited with **rc=137 (SIGKILL)**. The kernel's log:

   ```
   AMFI: Launch Constraint Violation (enforcing), error info: c[1]p[1]m[1]e[10],
         (Constraint not matched) launching proc[...]: /tmp/echo_copy
   ASP: Security policy would not allow process: 77559, .../echo_copy
   ```

   **⇒ AND IT IS NOT THE SIGNATURE: A BYTE-IDENTICAL COPY OF `/bin/echo` IS
   DENIED TOO.** And it is not the file: `cp -X`, a shell redirect and `mktemp`
   all produce the same result, because the KERNEL adds
   `com.apple.provenance` to every file it creates (`xattr -l` on a new file
   shows it; `xattr -d` on it returns rc=0 and DOES NOT REMOVE IT -- it is
   protected).

4. **AND THE CAUSE IS NAMED BY THE MACHINE ITSELF:**
   `/usr/sbin/DevToolsSecurity -status` says **"Developer mode is currently
   disabled."** On this macOS, a LOCALLY-BUILT binary needs Developer Mode.
   `DevToolsSecurity -enable` HANGS (it waits for an administrator
   authentication this unit cannot supply), and
   `launchctl kickstart -k system/com.apple.security.syspolicy` answers
   **"Operation not permitted while System Integrity Protection is engaged"**.

5. **⇒ AND FOUR MORE WAYS TO GET PAST IT WERE TRIED, AND ALL FOUR ARE NEGATIVE
   RESULTS, WHICH ARE RESULTS:**

   | attempt | result |
   |---|---|
   | sign the binary with the machine's ONE identity (`security find-identity -v -p codesigning` → `Apple Development: Mohammed Lari (BU4KT995SH)`) | still `ASP: Security policy would not allow process` |
   | sign it with entitlements (`com.apple.security.cs.allow-unsigned-executable-memory`, `disable-library-validation`, `get-task-allow`) | still killed |
   | `cp -X`, a shell redirect, `mktemp`, and a HFS+ RAM DISK (`hdiutil attach -nomount ram://8192`, `newfs_hfs /dev/rdisk14`, `diskutil mount`) | **ALL of them get `com.apple.provenance` AND all of them are killed** — the xattr is added by the KERNEL, not by the creating program, and the constraint is enforced on the FILE |
   | `cp /bin/echo` (a byte-identical copy of an Apple-signed system binary) | **also killed** — so it is neither the signature nor the compiler |


**⇒ SO: EVERY LOCALLY-BUILT BINARY IS KILLED, AND THE PORT's OWN SEAM, WHICH
IS A LOCALLY-BUILT BINARY, IS ONE OF THEM.**

**⇒ WHAT WAS DONE ABOUT IT. THE PORT's BEND CODE RUNS IN THE JS LANE**
(`bend <file> -o <file>.js`, run with `bun`), **AND IT IS THE SAME PORT's
CODE**: the renderer and the relocator are the same defs, and the JS lane is
only a different backend. **⇒ MEASURED, IN THE JS LANE:**

| what | how | result |
|---|---|---|
| the port's renderer | `bun /tmp/render.js <kernel>` vs `csrc/<kernel>.c` | **5 of 5 IDENTICAL** |
| the port's `jit_loader` | `bun /tmp/relocate.js <kernel>` vs upstream's `jit_loader` | **5 of 5 IDENTICAL** |
| the port's assembler + the port's relocator + the call | `pipeline.py` | **5 of 5 byte-identical to CPython's own device** |

**⇒ AND THE ONE STAGE THAT IS NOT THE PORT's OWN SOURCE IS THE 30 LINES OF
`runtime/ops_cpu.c` THAT MMAP AND CALL** -- because a locally-built binary
cannot exec. **IN THE PIPELINE THAT STAGE IS SPELLED IN PYTHON, EXACTLY AS
UPSTREAM SPELLS IT** (`jit_ref.py`'s `call_image`: `mmap` with `MAP_JIT`,
`pthread_jit_write_protect_np(0)`, the copy, `pthread_jit_write_protect_np(1)`,
`__clear_cache`, then the call through a `CFUNCTYPE` pointer).

**⇒ ⇒ ⇒ THE PORT's `runtime/ops_cpu.c` IS WRITTEN, IT COMPILES, AND IT IS NOT
EXERCISED ON THIS MACHINE. THAT IS THE ONE PLACE WHERE THE MEASUREMENT IS
COMPOSED INSTEAD OF RUN, AND IT IS NAMED HERE RATHER THAN HIDDEN.**

**⇒ AND THE JS LANE HAS ITS OWN LIMIT, AND IT IS MEASURED, NOT INFERRED.**
`bun /tmp/launch.js` DIES WITH `bend: memory fault (machine stack overflow?)`.
**⇒ `.agents/slop/cpuseam/read.bend` IS THE INSTRUMENT: THE SAME PROGRAM, THE
SAME `H.lines` CALL, TWO FILES.**

| file | bytes | the JS lane |
|---|---|---|
| `elf/r_10_98_4.hex` | 1 424 | `lines=1` |
| `bufs/r_56_7_2_2.rows` | 31 489 | `bend: memory fault (machine stack overflow?)` |

**⇒ THE JS LANE'S STACK CANNOT TAKE THE PORT's `H.lines` OVER A 31 KB FILE.**
The JS lane therefore runs the renderer and the relocator (whose inputs are
1.4 KB and smaller) and NOT the whole lane.

**⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒ ⇒**

---

## 5. THE NAMED GAPS

1. **THE PORT's `runtime/ops_cpu.c` IS NOT EXERCISED ON THIS MACHINE.** §4. It
   compiles, it is upstream's shape, and the stage it implements is measured
   with the same logic spelled in Python.
2. **THE PORT's `Device` LANE HAS NO SCHEDULER, SO THE WHOLE MNIST FORWARD
   PASS THROUGH THE PORT's OWN LANE IS NOT MEASURED.** What IS measured is the
   FIVE REAL CPU KERNELS THAT MNIST'S FORWARD PASS ACTUALLY RUNS (captured
   from upstream's own live `ClangRenderer.render` calls), end to end, against
   CPython's own device. **⇒ SECONDS PER IMAGE IS NOT A NUMBER THIS UNIT MAY
   QUOTE**, and it is not quoted here.
3. **THE PORT's `jit_loader` IS EXERCISED, BUT ON FIVE KERNELS.** They are
   REAL (they are MNIST's own) and they cover the ALU, the CAST, the INDEX,
   the SHRINK, the CONST, the PARAM and the BUFFER ops -- but not `SPECIAL`,
   `BINARY`, `CALL` or `CUSTOM_FUNCTION`, which none of the five CPU kernels
   uses. `runtime/support/elf.bend`'s own gate covers those.
4. **THE `jit_loader`'s BASE IS `0` IN THE PORT's PIPELINE** (§3.5), where
   upstream passes the mmap address. Measured to be equivalent on these five
   kernels, and the reason is measured too (no `CALL26`/`JUMP26`).
5. **THE SEAM'S BUFFERS CROSS AS HEX** (one string of the concatenated buffers
   plus a `"n,n,n"` size list), because a Bend `List<String>` is a constructor
   chain and building one in C is not a thing to write. Upstream crosses
   addresses; the port crosses the bytes, and the C side mallocs them and
   hands the kernel pointers.
6. **THE SEAM CALLS WITH UP TO EIGHT POINTERS** (`ops_cpu.c`'s `switch`), where
   upstream's `CPUProgram` takes exactly as many arguments as its signature
   has. The five kernels need at most four.
7. **THE JS TWIN REFUSES BOTH EFFECTS** with `ENOSYS` (`runtime/ops_cpu.js`),
   because the JS lane has no way to mmap an executable region and call it.
   The JS twin of `Cpu.compile` COULD spawn `cc` (the port's other JS twins do
   use `node:fs`), and that is the next thing to write.

---

## 6. THE COST LEDGER FOR THE COMMANDS IN §3 AND §4

**ONE `bend` PROCESS AT A TIME, NEVER IN THE BACKGROUND, NEVER A FAN-OUT. NO
`checks/` OR `gates/` SCRIPT WAS RUN. NO `git` WRITE.**

| command | cost | notes |
|---|---|---|
| `./bin/bend .agents/slop/cpuseam/launch.bend -o /tmp/launch` | **7.2 s** | one bend process, native |
| `./bin/bend .agents/slop/cpuseam/launch.bend -o /tmp/launch.js` | **1.2 s** | one bend process, JS |
| `./bin/bend .agents/slop/cpuseam/render.bend -o /tmp/render.js` | **~1.2 s** | one bend process |
| `./bin/bend .agents/slop/cpuseam/relocate.bend -o /tmp/relocate.js` | **~1.2 s** | one bend process |
| `./bin/bend tinybendygrad/runtime/ops_cpu.bend --check-only` | **0.50 s** | one bend process, exit 1 (foreign code only) |
| `.venv/bin/python .agents/slop/cpuseam/bufs.py` | **0.96 s** | one device, `DEV=CPU`, `JIT=0` |
| `.venv/bin/python .agents/slop/cpuseam/reloc_ref.py` | **~0.9 s** | five `cc` runs, upstream's argv |
| `.venv/bin/python .agents/slop/cpuseam/reloc_cmp.py` | **2.57 s** | five `bun` runs of the port's relocator |
| `.venv/bin/python .agents/slop/cpuseam/pipeline.py` | **3.78 s** | five kernels, ten `cc` runs, ten `bun` runs, ten mmaps |
| `.venv/bin/python .agents/slop/cpuseam/jit_ref.py <kernel>` (×10, two bases) | **~0.42 s each** | one `cc` run and one mmap each |
| `sample <pid> 1` (×2) | ~1 s each | the `dlopen` hang and the `_dyld_start` hang |
| `/usr/bin/log show --last 4m --style compact --predicate ...` (×5) | **~10-60 s each** | the AMFI/ASP denials and the syspolicyd spin |
| `security find-identity -v -p codesigning` | ~0.4 s | one Apple Development identity |
| `/usr/sbin/DevToolsSecurity -status` / `-enable` | 0.3 s / **HUNG** | the `-enable` waits for an admin auth |
| `codesign --force --sign <identity>` / `--entitlements` (×4) | ~0.5 s each | the negative results of §4.5 |
| `hdiutil attach -nomount ram://8192` + `newfs_hfs /dev/rdisk14` + `diskutil mount` + `hdiutil detach` | ~2 s total | the RAM DISK negative result of §4.5 |
| `./bin/bend .agents/slop/cpuseam/read.bend -o /tmp/read.js` + two `bun` runs | **~1.2 s + 2 runs** | the JS lane's stack limit, §4 |
| **`sh .agents/slop/cpuseam/verify.sh` (THE WHOLE THING)** | **14.6 s wall, 24.6 s user** | four `bend` processes, one at a time, and the ten measurement rows |

**⇒ THE `cc` RUNS ARE INSIDE THE MEASUREMENT AND THEY ARE ONE AT A TIME.**
**⇒ AND THE TOTAL `bend` TIME FOR THE WHOLE UNIT IS UNDER 60 s OF COMPILER
TIME**, which is the number the machine constraint cares about.

