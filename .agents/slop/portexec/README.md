# `.agents/slop/portexec/` — THE PORT EXECUTING ITS OWN KERNEL

**This is the first time in this project that the port's output has been COMPILED
AND RUN rather than compared as text. Three stages, all green, all with negative
controls that turn them red.**

## THE THREE COMMANDS

```sh
zsh .agents/slop/portexec/stage1.sh                      # Stage 1  the port's C compiles and runs
zsh .agents/slop/portexec/run-kernel.sh stage2            # Stage 2  the same kernel, CALLED FROM BEND
zsh .agents/slop/portexec/run-kernel.sh mm                # Stage 3  the whole 8x8x8x8 matmul, from Bend
.venv/bin/python .agents/slop/portexec/census.py "$TMPDIR/portexec"   # the 227-row census
cc -O0 -Wall -Werror .agents/slop/portexec/addrprobe.c -o "$TMPDIR/addrprobe" && "$TMPDIR/addrprobe"
```

**`$1` is the MODE and `$2` is the WORK DIR, positionally.** Making the work dir configurable is
what caught a bug worth recording: `run-kernel.sh /some/dir` sets `MODE` to a path and exits 127
with no message. All three were verified green from three EMPTY work directories, each with its own
exit code read from the command and not from a pipe — `"$PY" gate.py | tee out` makes `$?` the
status of `tee`, which is the exact trap `e2e.sh:60` documents.

All three exit 0 on PASS and name which of the four steps broke otherwise.
Nothing in the live port tree is edited; every artefact lands in `$TMPDIR/portexec`.

## THE RESULTS

| | what | result |
|---|---|---|
| **Stage 1** | `kern2 CLANG`'s 165-byte C, `cc -Wall -Werror` (zero warnings), linked, run | port `[0xbf800000, 0, 0, 0]` = CPython, **diff 0 bytes**; 3/3 controls red |
| **Stage 2** | the same kernel called **from Bend** through the FFI, with its address as a `Nat` | `[3212836864, 0, 0, 0]`, **diff 0**; 3/3 controls red |
| **Stage 3** | `(A @ B) @ Cm`, kernel emitted by the port's own `render_kernel` with four buffers | **64/64 u32 words bit-identical to `e2e_mm.py`**, diff 0 bytes; 3/3 controls red |

Reports: `STAGE1.md`, `STAGE2.md`, `STAGE3.md`.

## THE ANSWER THAT MATTERS MOST — HOW MUCH IS TEXT

**`cstyle-gate.py:554` builds both lanes from
`subprocess.CompletedProcess([], 0, pathlib.Path(a.port_stdout).read_text(), "")`.
All 227 rows compare two RECORDED TEXTS. Measured by `census.py`, which writes
every row to its own file and hands it to `cc`:**

| | rows | share |
|---|---:|---:|
| total, from the port's own stdout | **227** | 100% |
| **TEXT ONLY** — a fragment: a type spelling, an ALU string, an index rendering, an option-table cell. Not a translation unit. | **216** | **95.2%** |
| C source (`void N(...)` + body) | 11 | 4.8% |
| …of those, `cc` on this machine **accepts** | **6** | **2.6%** |
| …of those, `cc` rejects | 5 | 2.2% |
| **EXECUTED, numbers compared against CPython** | **1** (`kern2 CLANG`) | **0.44%** |
| plus a kernel NOT among the 227 rows, emitted by the same `render_kernel` with 4 buffers, also executed | 1 | — |

**So: 2 of 227 rows have been executed. 225 are still text-only, and 216 of those
are not even compilable C.** The denominator matters more than the numerator
here: a "227/227 green" claim covers 2.6% compilable code, and this unit moved
0.44% of it from text to execution.

### WHY 5 OF THE 11 ARE REJECTED — two different reasons, both real

* **3 OpenCL rows** (`kern2 OPENCL`, `OPENCL f16`, `OPENCL pref2`):
  `unknown type name '__kernel'`. OpenCL headers are not on this machine.
* **2 ALU rows** (`kern2 BASE alu`, `kern2 CLANG alu`): `use of undeclared
  identifier 'data1_4'`. **This one is a finding, not a missing SDK.** Those rows
  pair an ALU-space *signature* (`const float alu0_1, const float alu1_1`) with
  the gate's `g_kernel()` *body*, which references `data1_4`/`data0_4`.
  `renderer_oracle.py:551-552` hands upstream the same mismatched pair, so **both
  lanes agree on a string no compiler has ever accepted.** The row is internally
  consistent and unfalsifiable by execution. Reported, not fixed — `cstyle.bend`
  and `renderer_oracle.py` are not this unit's to change, and the fixture belongs
  to whoever owns `g_kernel()`.

## WHAT IS STILL TEXT IN THE STAGES ABOVE

The kernel **bodies** are fixtures — `g_kernel()` at `cstyle.bend:1879` for
Stages 1–2, and the loop nest in `emit-mm.bend` for Stage 3. They are inputs to
`render_kernel` on both sides (`renderer_oracle.py:508`). What the port contributes
and what has now been proven live is the **signature, the buffer types, the
prefixes and the framing**.

**`cstyle.bend` has no `_render` at all.** Nothing in the port turns a UOp list
into lines. `cstyle.bend:49` names the wall: `Ops.SHRINK` has no dtype in
`fold.bend`, so `F.fold.dt` answers `None` and `render_type` — needed by every
emitted line — cannot be driven from a graph. **That wall is the boundary of this
unit's result, and it is `fold.bend`'s to move, not this file's.**

## FILES

| file | what |
|---|---|
| `oracle.py` | every expectation, by CALLING CPython: `ClangRenderer.render_kernel`, numpy f32, and tinygrad's real `Device["CPU"]` (ClangCompiler → ELF → CPUProgram → ctypes) |
| `exec_harness.py` | reads the port's own stdout, parses its signature, generates the driver |
| `gen_ffi.py` | generates `shim.c`, `kernel.c` and `run-kernel.bend`; the shim's ABI is parsed out of the port's text |
| `emit-mm.bend` | asks the port's `render_kernel` for a four-buffer matmul |
| `stage1.sh`, `run-kernel.sh` | the re-runnable lanes, with every step and every plant attributed |
| `census.py` | the 227-row text-vs-execution census above |
| `addrprobe.c` | the `Nat` pointer measurement, runnable on its own; two runs differ (ASLR) and every address is under 2^48 |

## TWO THINGS FOUND IN MY OWN HARNESS, BY NEGATIVE CONTROLS

1. **The Stage 2 lane was green through a SELF-ALIASED call.** `khi`/`klo` read a
   C static that `kmalloc` overwrites, and my generated program read `dst_hi`/
   `dst_lo` *after* the second allocation, so both buffer slots were the same
   pointer. A self-aliased call of a one-input kernel returns the correct answer
   by construction. Nothing on the PASS path could see it. `run-kernel.sh` STEP 5
   now asserts the buffer `Nat`s are **distinct**.
2. **Two "controls" were theorems.** Aliasing the two buffers of `kern2 CLANG`, in
   either direction, leaves the lane green — that kernel reads one buffer and its
   answer is a function of that one buffer. So does dropping input words 1–3, which
   it never reads. Reported as theorems in `STAGE2.md`, **not** counted towards the
   three controls. The matmul reads three buffers and has no such theorem.

## NEW MEASURED BEND RULES (bend 2.0.35)

* **`Nat` AND `U32` ARE BOTH LINEAR.** `def f(n: U32) -> U32: U32.add(n, n)` and
  `def f(n: Nat) -> Nat: Nat.add(n, Nat.add(n, n))` both fail with
  `observed : n (consumed more than once)`.
* **`+` GOES ON THE BINDER, NOT THE TYPE.** `def f(+n: U32) -> U32: U32.add(n, n)`
  compiles and prints 6. `+D` sets `D`'s leading quantities to `&2`. `+U32` as a
  *type* is `expected : a quantified datatype after +`.
* **`Nat.add`/`Nat.sub` take `n`-suffixed literals** and a bare `+` is refused
  (`a type for this operator (write (a + b : Nat))`).
* **`match` ON A `Nat` PARAMETER HAS NO `case 0` ARM** — `expected : a constructor
  of Nat`. Use a `List<&2, Nat>` of indices instead, which also keeps each index
  consumed exactly once.
* **`is` IS A KEYWORD** (`expected : a name (got the keyword 'is')`).
* A **self-call must pass the shrinking argument and leave the unchanged ones
  alone**, and the changing argument goes LAST (`generate.bend:2628` `gl.go`).
* `IO.pure(Unit, ())` is wrong; the port's spelling is `IO.pure(Unit, Unit{})`.
* `bend -o` **inlines** the imported `.c`, so a plant on `shim.c` after step 1 edits
  a file nothing reads. The controls that touch the shim **re-run step 1**.
