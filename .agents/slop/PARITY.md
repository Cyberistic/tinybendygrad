# PARITY — where the port stands against tinygrad, measured

**THE GOAL IS 1:1 PARITY WITH `tinygrad/`, NOT SPEED.** This file records the three axes that make
"1:1" checkable, the exact command for each, and today's reading. Every number here was produced by
running the command beside it; re-run it rather than trusting this file.

Measured 2026-11-02. The corpus row was taken twice: once at `16a1fb5d5`, then RE-TAKEN at `78b204521`
after the file deletion below (which moves the substrate digest — `substrate-start`/`substrate-end` and
the live digest are what say so). Both runs agreed 38/38; the second is the one that stands, with
`substrate-start == substrate-end == live == 8e7ab117989c661ff9f6c390e631ec0d0b8d575d16985aeb07552385c5c71669`.

## 1. SOURCE AXIS — is the vendored `tinygrad/` pristine?

```bash
.venv/bin/python .agents/slop/upstream-delta.py
```

```
PIN      5c2bf39d6c4b  2026-10-20   230/230 vendored blobs match it
UPSTREAM 5c2bf39d6c4b  2026-10-20   BEHIND 0 commits, 0 files, 0 under tinygrad/
AT PIN                  230
RE-VENDORED               0
⚠ HAND EDITS              0   upstream HAS this path, our blob is at NO upstream commit
LOCAL-ONLY PATHS          0
PORT-RELEVANT CHANGED     0 of our ports have moved under us
```

**1:1 AT THE SOURCE LEVEL: no hand edits, no drift, no local-only paths.** Every one of the 230
vendored blobs equals the pin's blob.

## 2. SEMANTIC AXIS — does the port compute what tinygrad computes?

```bash
.venv/bin/python checks/bounded.py --mb 2500 --seconds 1800 -- .venv/bin/python checks/differ.py run
```

```
graphs=38  graphs-answered=38  graphs-agree=38  graphs-disagree=0
graphs-refused=0  byte-identical=38  plants-disagree 8 of 8
substrate-start == substrate-end      substrate-head=16a1fb5d51b289de86430cd406d27dde10419d4b
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=1118 MB   104s
```

**38 of 38 graphs agree BYTE-FOR-BYTE with CPython on the same graph**, no graph refused, the 8 plants
that must disagree do disagree (so the comparison can fail), and the run straddles no edit.

Two narrower lanes, both re-run today:

```
gates/ops_python_exec-gate.py   PASS -- 153 fixtures, 365 rows x 2 lanes, 0 unpinned, 0 pinned
gates/ops_bend_exec-e2e.py      7 match, 0 mismatch-or-refused
```

## 3. COMPILE AXIS — does every port file build?

```bash
.venv/bin/python checks/port-compile-gate.py
```

```
DENOMINATOR population=189  compiled=183  cold-by-design=6  findings=0  unmeasured=0
```

**0 findings.** It was 1: `tinybendygrad/runtime/zzprobe2.bend`, a tracked file whose own first line
read `# scratch probe -- DELETE.`, which no gate read and nothing imported, and which no longer compiled
(it had once — `gates/artifacts/specfix/port-compile.rows:132` records it as COMPILES). It was removed
and the four measured Bend rules in its header were moved to
`.agents/slop/notes/bend2-constraints.md` ("Recovered substrate rules") so no knowledge was lost.

## 4. COVERAGE — how many upstream modules have a port?

```bash
python3 - <<'PY'
import pathlib
u={p.relative_to('tinygrad').with_suffix('') for p in pathlib.Path('tinygrad').rglob('*.py') if '__pycache__' not in str(p)}
p={q.relative_to('tinybendygrad').with_suffix('') for q in pathlib.Path('tinybendygrad').rglob('*.bend')}
print(len(u), len(p), len(u-p), len(p-u))
PY
```

```
upstream .py 214    port .bend 190    no port 100    port-only 76
```

The 100, by bucket — **this is the whole of the coverage gap, and 93 of it is accounted for**:

| n | bucket | status |
|---|---|---|
| 88 | `runtime/autogen/` (`am` 19, `nv_regs` 15, `amd` 17, rest) | **documented OUT OF SCOPE** (`UPSTREAM-PIN.md:456`, `:233`) |
| 5 | `__init__.py` in `runtime/support/{am,nv,rdma}`, `renderer/{amd,isa}` | package markers; Bend has no such construct |
| 7 | **`llm/`** | **THE ONE REAL GAP** |

`tinybendygrad/llm/` currently holds only `ggml.bend` and `gguf.bend`. The 7 without a port are
`llm/__init__`, `llm/__main__`, `llm/cli`, `llm/kernels/__init__`, `llm/kernels/amd`, `llm/model`,
`llm/serve`. `UPSTREAM-PIN.md:233` lists `llm/`, `viz/`, the `isa` tables and `autogen/` as recorded in
`.agents/TODO.md` rather than ported — so `llm/` is a **known, declared gap, not an accident**.

The 76 port-only files are the port's own support modules (`base.bend`, `helpers.bend`, `LAWS/`,
`examples/`, and the extra split files the 1:1 file split produced).

## 5. WHAT "1:1" STILL DOES NOT COVER, STATED PLAINLY

- **`llm/` (7 modules)** — the only unported subsystem in scope. This is where parity work goes next.
- **1,049 `WALL` + 948 `TODO` markers across 154 `.bend` files** — the port's own record of places it
  refuses or has not ported something. Markers are CLAIMS, not measurements: `.agents/slop/WALLMAP.md`
  classified a Oct-7 population of 1,028 and found 97.8% of the claims still hold. That census is
  **stale at this HEAD** and is the natural next instrument to re-take.
- **`runtime/autogen/` (88 files)** — out of scope by declaration. If the owner ever wants it in scope,
  that is a SCOPE DECISION (`UPSTREAM-PIN.md`, Step 3), not an agent's call.

## 6. HOW TO RE-TAKE THIS FILE

Run §1–§4's commands; they are independent and each prints its own verdict token. **Do not copy these
numbers forward** — three of the four instruments read the working tree, and one of them (the corpus)
goes STALE the moment a `.bend` file changes, which `substrate-start`/`substrate-end` and the live
digest are what report.

## 7. THE WORK LIST TO CLOSE THE NON-`autogen` GAP (sized, not estimated)

Twelve files stand between the tree and 1:1 outside `runtime/autogen/`, and **nine of them carry no
semantics at all** — they are the `__init__` markers and stubs the tree's own convention already
prescribes (`tinybendygrad/engine/__init__.bend` is the precedent: six lines for a zero-line upstream).

**MEASURED 2026-11-03 AFTER LANDING THE MARKERS AND THE `amd` STUB: the non-`autogen` gap is FOUR
FILES, 1051 lines, all of them `llm/`.** Port `.bend` 190 -> 197, no-port 100 -> 92 (88 of those are
`autogen`). Seven files landed: `llm/__init__`, `llm/kernels/__init__`, `llm/kernels/amd` (the declared
stub), and the five `__init__` markers `renderer/{amd,isa}`, `runtime/support/{am,nv,rdma}`.

**AND TWO OF THOSE SEVEN ARE NOT EMPTY, WHICH THE FIRST DRAFT GOT WRONG.** `renderer/isa/__init__.py` is
50 lines defining the `Register` algebra and `renderer/amd/__init__.py` is 75 lines of AMD
instruction-format decoding; the generator wrote "Empty upstream (75 lines)" for both. Corrected by
reading them: `isa` is a REAL GAP (its `Register` appears in `x86.bend` only as `TODO(p3)` markers) and
`amd` is DECLARED OUT OF SCOPE (`TODO.md`, "Out of scope -- needs hardware we do not have", which names
`renderer/amd/` by path). Both files now state that instead of claiming emptiness.

| what remains | upstream lines | treatment |
|---|---|---|
| `llm/__main__.py` | 2 | trivial, and it waits on `cli`: it IS the `if __name__ == "__main__": main()` guard |
| `llm/cli.py` · `llm/model.py` · `llm/serve.py` | 223 · 650 · 176 | **the only real port work left** |

Landed this pass (7 files): the two `llm` markers, `llm/kernels/amd`'s declared stub, and the five
`__init__` markers. `renderer/isa/__init__` is recorded as a REAL GAP rather than a marker (see above).

Note the count: my §4 census reported `__init__` as 5 because it excluded `llm/` from that bucket; the
`__init__` total missing outside `autogen` is 7, plus `renderer/amd` which has 4 ports and no marker.

## 8. TWO GITIGNORED FILES INSIDE THE WALK THAT MUST **NOT** BE DELETED

`tinybendygrad/renderer/amd/dsl-mut.bend` and `dsl.bend.bak` are untracked (`.gitignore:36` `*mut.bend`,
`.gitignore:28` `*.bak`) and they sit inside the substrate walk, so the digest hashes them. **They are
not strays to sweep:** `gates/amd-mut-run.py:5` and `gates/amd_dsl_census-mutate.py:81` name
`dsl-mut.bend` as their mutation target — the copy that makes those gates able to FAIL — and
`checks/substrate.py:558` already records `*-mut.bend` and `dsl.bend.bak` as "owned by neither".
**Checked before touching; kept.** This is the file class `AGENTS.md` warns moves the digest, and the
answer here is that the tree already accounts for it.

## 9. THE EXECUTION LANE: A ONE-LINE DEFECT WAS HIDING A 168x GAP

**tinygrad's own CPU device runs this workload in 1.209 ms. Our BEND lane ran it in 228.46 ms --
189x slower.** That is not a floor, it was a bug: the compiled lane (`BEND_C=1`, which renders C with
the PORT's own `cstyle.bend` and calls `cc`) was DEAD.

```
AttributeError: 'BendDevice' object has no attribute 'remote'
  File "tinygrad/runtime/ops_cpu.py", line 26, in __init__
    if dev.remote is not None: ...
```

`CPUProgram.__init__` reads `dev.remote` **directly**, and `CPUDevice.__init__` (`ops_cpu.py:71`) is
what sets it. `BendDevice` handed `CPUProgram` to `Compiled.__init__` without setting it, so the
compiled branch raised on every launch and the device silently used the interpreter. **One line:
`self.remote = None` at the top of `BendDevice.__init__`, exactly as `CPUDevice` does.**

MEASURED AFTER THE FIX:

```
BEND (compiled, BEND_C=1)   1.36 ms       max|PYTHON-BEND| = 0.000e+00
BEND (interpreter)        228.46 ms
tinygrad CPU device         1.209 ms
```

**1:1 WITH TINYGRAD'S OWN CPU DEVICE TO WITHIN 12%, AND THE ANSWER IS BIT-EXACT (0.000e+00).** The
port's compiled lane is also certified independently by `.agents/slop/cpuseam/compare.py`: the C the
port renders with `cstyle.bend`, compiled with `cc`, reproduces CPython's numbers on all 5 kernels,
`max_abs=0 max_rel=0`, `fail=0`.

The interpreter lane is unchanged and still green (`ops_python_exec` 365 rows / 0 unpinned,
`ops_bend_exec-e2e` 7 match), so `BEND_C` remains the flag that selects a lane; **whether the compiled
lane should be the DEFAULT is a scope decision, not a bug fix** (`ops_bend.py`'s header: the interpreter
"IS this lane's definition").

## 10. THE DEFAULT LANE IS NOW THE COMPILED ONE, AND THE REMAINING GAP IS OUR OWN RENDERER

`BEND_C` defaults to **1** (`ops_bend.py`), so `DEV=BEND` means the compiled lane.

```
BEND (compiled, default)   1.21 ms      max|PYTHON-BEND| = 0.000e+00
PYTHON device            383.60 ms      316x
tinygrad CPU device         1.209 ms    <- the target; we are 1.21
BEND_C=0 (interpreter)    38.51 ms at 16x16, 1.85x vs PYTHON
```

**1:1 WITH TINYGRAD'S CPU DEVICE ON THIS WORKLOAD.** Both lanes agree with CPython exactly, so the flag
is a speed choice, not a correctness one.

**ONE INSTRUMENT HAD TO BE PINNED, AND IT IS RECORDED RATHER THAN HIDDEN.**
`gates/ops_bend_exec-e2e.py` measures the INTERPRETER: it captures the packet a `DEV='BEND'` run
produces and replays it through `OB.executor()`. With the compiled lane selected nothing is captured and
it read **`0 match, 7 mismatch-or-refused`**. It now pins `BEND_C=0` before importing `ops_bend`, on the
principle that a lane a gate does not measure must not be able to change its verdict; back to `7 match`.
`.agents/slop/perf/stepcensus.py` is pinned the same way — its input is the interpreter's packet.
The corpus is unaffected: `checks/differ.py` runs its oracle at `DEV=NULL` and drives the BEND side
through `bin/bend`.

**AND THE LANE STILL BORROWS TINYGRAD'S RENDERER.** The compiled lane hands `[ClangRenderer]` to
`Compiled`, i.e. it renders C with **tinygrad's** code, not with `tinybendygrad/renderer/cstyle.bend`.
The port's own renderer is proven equivalent — `.agents/slop/cpuseam/compare.py` renders with
`cstyle.bend`, compiles with `cc`, and matches CPython on all 5 kernels at `max_abs=0`, `fail=0` — but
nothing in the device path calls it.

### What wiring our own renderer requires, measured from the existing seam

`cpuseam/render.bend` does `import ./gen/<name>.bend as K` — **the uop list is compiled INTO a generated
Bend module**, one per kernel, produced by `dump_kernel.py` (uops -> `.rows`) then `gen_kus.py`
(`.rows` -> `gen/<name>.bend`), then `./bin/bend render.bend -o /tmp/render.js` and `bun /tmp/render.js
<name>`. So a live `Renderer.render(uops)` must, per kernel: format the uop list, emit a module, emit a
driver, build it, and return the C — with `tinygrad`'s program cache making that once per unique kernel.
A build is ~10-15 s on this machine. **That is the next build, and it is the only thing standing between
`DEV=BEND` and a fully self-contained 1:1 implementation.**

## 11. THE COMPILED LANE NOW RENDERS WITH THE PORT's OWN `cstyle.bend`

`BEND_C=1` (default) previously handed `[ClangRenderer]` to `Compiled`, i.e. it rendered C with
**tinygrad's** code. It now uses `PortRenderer(ClangRenderer)`, which overrides ONLY `render` -- the
target, the `Compiler` and the pattern matcher still come from `ClangRenderer`, because those are not
what the port ports. `BEND_PORT_C=0` selects tinygrad's renderer again.

**THE RENDERERS ARE BYTE-IDENTICAL ON A LIVE UOP LIST.** Measured on the 32x32 `(A@B)@C` kernel's own
634-uop list, captured from `ClangRenderer.render` and re-rendered by the port:

```
kernel 0: uops=634  ours=5251 B  theirs=5251 B  identical=True  render=1.2 s
```

`.agents/slop/cpuseam/portc.py` is the bridge. It does NOT re-type the format: it imports
`dump_kernel.dump_uops` and `gen_kus.one` -- the SAME two functions the fixtures use -- so a live render
and a fixture render cannot drift. `cstyle.bend`'s `C.render` takes a `KU` **Bend value, not text**, so
the uop list is transcribed to literals in a generated module, the module plus a driver are built with
`bend -o <js>`, and run with `bun`; the C is content-cached by sha256 of the rows. One build is
MEASURED 1.2 s and happens once per unique kernel.

A failure RAISES rather than falling back to tinygrad's renderer. **A silent fallback is exactly the bug
that hid a 168x-slower lane behind a dead branch for the whole of this session.**

MEASURED, `DEV=BEND` on the default path:

| | 32x32 | 16x16 |
|---|---|---|
| port renderer (default) | **1.22 ms** | 1.37 ms |
| `BEND_PORT_C=0` (tinygrad's) | — | 1.31 ms |
| agreement with CPython | `0.000e+00` | `0.000e+00` |
| tinygrad's own CPU device | 1.209 ms | — |

Gates: `ops_bend_exec-e2e` now measures BOTH lanes (see §12), `ops_python_exec` 365 rows x 2 lanes / 0
unpinned, `ALL PROOFS CHECK`.

**A CORRECTION TO THIS SECTION AS FIRST WRITTEN:** it said the substrate digest was "still `8e7ab117...`
so the corpus run remains CURRENT". That was true when measured and FALSE within the hour: another
unit's `.bend` edits moved the digest to `f98e515f...`, which is what `AGENTS.md` now records and what
the corpus was re-run at (`graphs-agree=38`, `substrate-head=f6921b283`). **A DIGEST TRANSCRIBED INTO
PROSE GOES STALE THE NEXT TIME ANYONE EDITS A `.bend` FILE.** Re-derive it
(`differ.substrate_digest()`) instead of quoting it.

## 12. `ops_bend_exec-e2e` MEASURES BOTH LANES, AND IT CAN GO RED ON EITHER

The gate pinned itself to the interpreter lane, which meant the DEFAULT lane -- the one every user gets
-- had no gate of its own. It now runs both, from ONE case list:

```
E2E_LANE=interpreter  BEND_C=0  captures the packet a DEV='BEND' run produces, replays it through the
                               port's executor binary, and REFUSES a case that rendered no packet
E2E_LANE=compiled     BEND_C=1  the default lane; renders C with the port's own cstyle.bend, so it
        BEND_PORT_C=1          produces no packet and the packet-rendered refusal does not apply
```

`BEND_C` is read by `ops_bend` at IMPORT time, so the parent spawns ITSELF with `E2E_LANE=compiled` for
the second lane and folds the child's exit status into its own.

```
# interpreter: 7 match, 0 mismatch-or-refused
# compiled:    7 match, 0 mismatch-or-refused
```

**AND THE FOLD IS PROVEN, NOT ASSERTED.** A plant that forces the CHILD to exit 1 makes the gate return
**rc=1** while both lanes still print `7 match` -- so the parent's verdict really does depend on the lane
it did not run itself. Without that fold the gate would have measured half of what it claims, which is
the same defect as a lane that silently falls back.

## 13. THE RENDERER IS NOW BYTE-IDENTICAL TO UPSTREAM ON EVERY KERNEL THE BATTERY REACHES

`.agents/slop/parity/opbattery.py` runs 31 small ops through the DEFAULT lane against **tinygrad's CPU
device** -- the target, not the PYTHON emulator. It found FOUR defects that the 7-case e2e gate could
not, because it reaches `exp`, `log2`, `sin`, reduces, casts and int ops:

| # | defect | upstream (`cstyle.py`) | port before |
|---|---|---|---|
| 1 | non-finite float const | `({render_cast(x, nan\|infinity\|-infinity)})` -> `((float)(__builtin_inff()))` | `inff` -- **UNDECLARED IDENTIFIER**, so `exp`/`log2`/`sin` did not compile |
| 2 | `CBool` const | `"1" if c.val else "0"` | `((_Bool)())` -- an **EMPTY expression**; the `boolean()` arm existed but was unreachable from `ku_const_int` |
| 3 | `u32` const | `{truncate[u32](val)}u` -> `4294967169u` | `-127u` (signed) |
| 4 | wide int const | 64 bits -> `4611686018427387903ul` | transcribed through `i64_of_i32` -> `-1ul` |

Two transcription bugs from the same pass: `"True"` contains an `e` and was read as a FLOAT
(`O.CFloat{True}`), and `-0.0` was transcribed as `(0.0-0.0 : F32)`, which is **+0.0**, losing the sign
upstream prints as `-0.0f`.

**MEASURED AFTER: 8 of 8 kernels render BYTE-IDENTICALLY to `ClangRenderer`** -- `exp`, `log2`, `sin`
(the largest at 15323 B), `sqrt`, `reciprocal`, `trunc`, `relu`, `maximum` -- and the battery is **31
match / 0 failed**.

**⇒ AND A CACHE NEARLY HID ALL OF IT.** `portc`'s key was the sha256 of the uop rows alone, so after
`cstyle.bend` was fixed for non-finite constants it returned the **PRE-FIX** C and the fix looked
inert; the same happened again after the `-0.0` fix. The key now covers the renderer sources AND the two
generators. **A CACHE THAT HIDES A FIX IS THE SAME DEFECT CLASS AS A GATE THAT CANNOT GO RED**, and it
cost two wrong conclusions in this session before it was fixed.

## 14. REAL PROGRAMS: 20 KERNELS, ALL BYTE-IDENTICAL — AND FOUR PROGRAMS THIS INSTRUMENT CANNOT SEE

`.agents/slop/parity/ksweep.py` runs 25 real programs (chained matmuls, conv2d, reduces, permute/reshape/
expand, slice/pad/cat, where/cmp, relu/abs/neg, the transcendentals, pow/maximum, half and bfloat16 casts,
int ops, bitops, argmax, embedding, cumsum, softmax, layernorm, threefry), captures EVERY kernel
`ClangRenderer` produced for each, and renders the same uop list through the port's `cstyle.bend`:

```
# programs that ran: 24; kernels captured: 20
# NO kernel (folded to nothing, or served from cache): 4 -- softmax, layernorm, threefry, argmax
# kernels: 20 byte-identical, 0 differ
```

**20 of 20 real kernels are BYTE-IDENTICAL to upstream.** That is the third surface this session has
measured, and the widest: 7 (e2e gate) -> 31 (op battery) -> 20 real kernels here.

**RESOLVED 2026-11-03: THE BLIND SPOT WAS TINYGRAD'S FORKED COMPILE WORKERS.** `realize.py:239` reads
`pool = None if len(todo) == 1 else get_worker_pool()`, and `get_worker_pool()` returns `None` only when
`PARALLEL == 0` (`engine/worker.py:43`). So a ONE-kernel program rendered in the parent and was captured,
while a THREE-kernel program (`softmax`) compiled in CHILDREN where no parent-side hook can see it —
`exec_kernel=3`, `render=0`, correct answer. `ksweep` now sets `PARALLEL=0`, and:

```
# programs that ran: 24; kernels captured: 30
# programs whose kernels were COMPARED: 24 of 24
# kernels: 30 byte-identical, 0 differ
```

**30 of 30 kernels, 24 of 24 programs, all byte-identical.** The superseded note is kept below, because
the five hypotheses it killed are the reason this took as long as it did.

**AND FOUR PROGRAMS' KERNELS WERE EXECUTED BUT NEVER RENDERED (superseded note, kept for the record).**
The instrument now counts BOTH sides, so the gap is a number rather than a note:

```
# EXECUTED-NOT-COMPARED (kernels ran, the C was never rendered here): 4
#     softmax(exec=3), layernorm(exec=3), threefry(exec=2), argmax(exec=2)
# programs whose kernels were COMPARED: 20 of 24
```

So the population is **20 kernels compared + 10 executed-but-not-compared**, and the coverage claim is
about the 20. MEASURED, to characterise the other 10: `exec_kernel` fires 3x for `softmax` and its CALL
carries a `CallInfo` with 3-5 srcs, while `ClangRenderer.render`, `Compiler.compile` AND `linearize` are
ALL silent -- so those kernels reach the device with their compiled form already attached. **WHICH PATH
ATTACHED IT WAS NOT ESTABLISHED.** Ruled out: the disk cache (`~/Library/Caches/tinygrad` cleared, 156 MB,
unchanged), `CACHELEVEL=0`, a fresh process with `softmax` as the FIRST op, and a broken hook (a control
`x*2` renders one kernel in the same context). Ruled in: something memoises at or above the CALL `UOp`.

**A blind spot that is counted is a coverage claim; one that is dropped is a slogan.** The remaining work
is to find that memo and either bypass it or hook it, so all 30 kernels are compared.

## 15. THE ksweep BLIND SPOT: WHAT THIS SESSION RULED OUT, AND THE EVIDENCE IT DID NOT RESOLVE

`PARITY.md` 14 records that 4 of 24 programs execute 10 kernels that `ksweep` never renders. An attempt
to find the memoisation at or above the CALL `UOp` produced the following, all MEASURED, and **did not
resolve it**. It is written down so the next attempt starts here instead of from the top.

**WHAT FIRES AND WHAT DOES NOT, for `x.softmax(axis=2)` on a (2,3,4) buffer:**

```
exec_kernel      3x        <- the kernels run and the answer is correct (5.6e-17 vs numpy)
ClangRenderer.render   silent
Compiler.compile       silent
linearize              silent
get_runtime           3x
```

**RULED OUT, each by a measurement:**
- the disk cache: `~/Library/Caches/tinygrad` (156 MB) deleted, behaviour unchanged;
- `CACHELEVEL=0`;
- the in-process program cache / a stale first result: `softmax` as the FIRST op in a fresh process is
  still silent;
- a broken hook: a control, `(x * 2).realize()`, renders exactly one kernel in the same context;
- the wrong renderer class: the CPU device's renderer IS `ClangRenderer`
  (`type(Device['CPU'].renderer)`), and patching all four of its renderers
  (`ClangRenderer`, `CPULLVMRenderer`, `LVPRenderer`, `X86Renderer`) still shows `mul` -> ClangRenderer
  and `softmax`/`argmax` -> NONE;
- the primitives: `max`, `exp`, `sum`, `div` each render ONE kernel, so `softmax`'s composites are not
  the cause;
- `linearize`: patching it in `tinygrad/codegen/late/linearizer.py` fires 0x even for `max`, which DID
  render -- so that is the wrong symbol (the name is imported into `tinygrad.codegen`, and patching a
  module attribute does not affect an already-imported reference). **This one is a mistake of mine, not a
  finding**, and it is recorded because it cost a cycle.

**WHAT THE EVIDENCE POINTS AT, AND WHY IT DID NOT SETTLE IT:** the CALL uop passed to `exec_kernel`
carries `src = [PROGRAM:ProgramInfo, ..., PARAM:ParamArg]`, and `UOp.to_elf` reads the ELF from
`self.src[3].arg` -- but for these kernels `src[3]` is a `BITCAST:DType`, not a buffer. So either this
tinygrad version's CALL shape is not what `to_elf` expects for the CPU device, or the compiled form is
attached somewhere that is neither `render` nor `compile` nor `linearize`. **Resolving it needs someone
who knows this tinygrad's codegen path; it is not a port defect and not a renderer defect.**

**WHAT TO DO NEXT, concretely:** hook `tinygrad.codegen.to_program` (the function that builds the CALL,
`tinygrad/codegen/__init__.py:515`), by the name `tinygrad.codegen` exports, not the module that defines
it -- and read `tinygrad/codegen/__init__.py:511`'s `to_program_key` first, because a key that is too
coarse would explain every observation above in one stroke.
