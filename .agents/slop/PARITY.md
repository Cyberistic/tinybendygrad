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
| `llm/cli.py` · `llm/serve.py` | 223 · 176 | real port work left |
| `llm/model.py` | 650 | **PARTIALLY PORTED** — see below |

**`llm/model.bend` IS PARTIAL AND SAYS SO.** Landed: `ExpertGating`'s four members (as `U32`, because the
VALUE is what a GGUF config carries and compares) and the four frozen config records `YaRNConfig`,
`SSMConfig`, `HCConfig`, `IndexerConfig`, with upstream's defaults, because a default that differs is a
silent behaviour change. **NOT landed, each with a `TODO(parity)` in the file:** `TransformerConfig` (40
fields — it belongs with the first block that CONSUMES it, not with a file nothing reads yet), the four
`Tensor` op helpers, and the blocks and `Transformer` itself (`model.py:134-650`).

**⇒ AND ONE LANGUAGE FACT THE PORT MUST CARRY, MEASURED:** an upstream `float|None` cannot travel as a
`Maybe` in a record field — `Maybe<&1, F32>` is REFUSED there ("expected : Data, observed : Type")
because `F32` is a `Type`. It IS legal as a return type (`cstyle.bend` uses it three times). So
`SSMConfig.gate_lower_bound` travels as `has_bound: Bool` beside `bound: F32`, and a `0.0` sentinel was
rejected outright: 0.0 is a legal lower bound.

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

## 16. HOW TO READ THE CORPUS DIGEST, AND A CERTIFICATE THAT WAS NOT ONE

**A RUN IS ONLY A CERTIFICATE WHEN `substrate-start == substrate-end == live`.** MEASURED 2026-11-03, on
a run I had already recorded as CURRENT:

```
substrate-start = e9d681461d0eb811...     <- before an edit
substrate-end   = 699c0d5d14305173...     <- after it
```

That run straddled my own `cstyle.bend` edit, so it described NEITHER tree, even though
`graphs-agree=38` and every plant fired. **AND MY CHECK WAS THE REASON I ALMOST MISSED IT:** I tested
`live_digest in summary_text`, which matches the END digest and nothing else. The tree's own rule is
`start == end == live`, and it takes all three.

**THE RE-RUN WAS REFUSED, AND REFUSING WAS CORRECT:** `runs/graphcmp/.corpus.lock` was held by
`pid 255 (.venv/bin/python checks/differ.py repro)` for 298 s, and `differ.py` refuses to start a second
run because two runs write the SAME `runs/graphcmp/D` and would overwrite each other's artifacts. **So
the corpus is NOT re-certified as of this note** — the last reading straddles an edit, and the
re-certification is owed to whoever next finds the lock free. Do not read the previous
`graphs-agree=38` as a certificate for this tree; read `start == end == live` or read nothing.

## 17. THE CORPUS IS RE-CERTIFIED, AND `llm/cli.bend` IS PORTED AND GATED

**§16's debt is paid.** Re-read on a quiet tree, by the rule §16 states:

```
substrate-start = 743bdb0cb7dca29c...   substrate-end = 743bdb0cb7dca29c...   live = 743bdb0cb7dca29c...
graphs=38  graphs-agree=38  byte-identical=38  graphs-refused=0   substrate-head=a6ada8938
```

`start == end == live`, so this run DESCRIBES THE WORKING TREE, and `AGENTS.md` records the same digest.
(My own `differ.py run` was refused twice by the singleton lock — `pid 255` then `pid 23922`, both
`differ.py repro` — so the reading comes from the lock holder's run. **Same artifacts, same rule, and the
rule is what makes it countable: `start == end == live`.**)

**`llm/cli.bend` LANDED, SPLIT STATED, AND THE PORTED PART IS GATED.**

| piece of `cli.py` | state |
|---|---|
| `FallbackTemplate.role` / `.end_turn` | **PORTED AND GATED** — `gates/llm_cli_template-gate.py` |
| `SimpleTokenizer.decode` / `.is_end` | **PORTED AND GATED** — `gates/llm_cli_tokenizer-gate.py` |
| `SimpleTokenizer.encode` | **NOT PORTABLE AS WRITTEN** — see below |
| `FallbackTemplate.render` | **PORTED AND GATED** — `gates/llm_cli_render-gate.py` |
| `main()` + the `models` URL table | not ported: needs `model.bend`'s `Transformer` and a fetch |

The gate compares all **38 rows** (6 presets × 3 roles, plus `end_turn`) against upstream's own
`FallbackTemplate`, with a stub tokenizer whose `decode` answers `"EOS"`:

```
rows  38 port / 38 upstream, 0 differ
llm_cli_template: PASS -- every preset x role and end_turn is byte-identical to upstream
```

**AND IT CAN GO RED:** planting one `X` in `end_turn`'s kimi-k2 arm makes it print
`row 21: port='kimi/end_turn\tEOSX' upstream='kimi/end_turn\tEOS'` and **exit 1** (clean: exit 0). A gate
that cannot fail is a label, and this one was measured both ways in the same minute.

**TWO THINGS THE PORT LEARNED, BOTH MEASURED:**
- `tekken` + a role it does not have RAISES upstream; a string-returning port would have answered `""`,
  so `Template.role` is a `Maybe` and the gate asserts both sides say `RAISE`.
- **`IO.print` APPENDS A NEWLINE.** The first differential disagreed by exactly one blank line per row
  because the driver added `"\n"` as well; the fix was to drop it from the payload. That is a one-line
  trap worth recording, since the port writes row dumps everywhere.

**`SimpleTokenizer` IS BLOCKED ON A LANGUAGE CAPABILITY, NOT ON EFFORT.** `__init__` builds a SPLIT
REGEX from `unicodedata.category` ranges (`ucat_range`, compacted with `itertools.groupby`) and compiles
it with `re`; `encode` is `findall` plus a greedy BPE merge. Bend has no regex engine and no Unicode
category table. `decode` and `is_end` WOULD port cheaply (`b''.join(self._tok2bytes[tid])` and a
membership test) and are the next slice — `render` comes with them, since it needs `decode`.

## 18. `llm/serve.bend`: THE STREAMING STATE MACHINE IS PORTED AND GATED

| piece of `serve.py` | state |
|---|---|
| `StreamRouter` (43-70) | **PORTED AND GATED** — `gates/llm_serve_router-gate.py` |
| `parse_tool_call` (10-30) | not portable: two `re` patterns + `json.loads` — the same language gap as `SimpleTokenizer.encode` |
| `normalize_messages` (32-41) | not ported: mutates a caller's dicts; ports with a JSON/message layer |
| `Handler` / `LLMServer` (71-176) | not ported: `http.server`, `uuid`, `time`, `model.Transformer` |

```
rows  16 port / 16 upstream, 0 differ
llm_serve_router: PASS -- every delta and the final (mode, buf) match upstream on 6 sequences
```

Six sequences reach each branch: a stream whose `<think>` tag is SPLIT across pieces, plain content, a
`<tool_call>`, `reasoning=True` with no think block, a PARTIAL tag that must be HELD rather than emitted,
and two empty pieces. **AND IT GOES RED:** forcing `Router.hold` to `0n` makes the gate exit **1** with
`row 4: port='reason/R\tlo' upstream='reason/C\tlo'` — the port would flush the reasoning text as
content instead of switching modes. Clean: exit 0.

**THE PORT IS PURE, AND THAT IS A REPRESENTATION CHANGE THE GATE PROVES IS NOT A BEHAVIOUR CHANGE.**
`route` returns the new `Router` and the deltas instead of mutating and yielding, because Bend has no
mutable cell. Writing it that way needed four things this session measured, each of which cost a compile
cycle and is now recorded in the file: a self-call must DECREASE a LEADING argument (so the search loops
carry `fuel`); a def may not use a later def (so the pipeline is written bottom-up: content, reason,
decide, dispatch); two defs may not call each other (so the fold is ONE recursive def, not `run` +
`run.last`); and `match` cannot scrutinize a computed value or a binder that follows a local statement,
so each such site becomes a `.by` def.

**THE CERTIFICATE WAS OWED FOR TWENTY MINUTES AND IS NOW PAID** — a quiet window gave
`substrate-start == substrate-end == live == 70925b145d84...`, `graphs-agree=38`, `byte-identical=38`,
`graphs-refused=0`. The paragraph below is kept because the FIRST attempt failed the rule, and the way it
failed is the point.

**AND THE FIRST ATTEMPT FAILED, FOR THE REASON §16 NAMES.** A re-run on this tree read
`substrate-start=65ac57cd...` and `substrate-end=70925b14...` with `graphs-agree=38`: **ANOTHER UNIT
COMMITTED `e9122b3dd` MID-RUN**, so the tree moved under the instrument. `start != end`, therefore not a
certificate, and it is recorded rather than quoted. The digest is of the WORKING TREE, so landing this
commit does not change it: the certificate is owed to the next quiet window, and the rule remains
`start == end == live`.

## 19. THE "1.27 vs 1.209" GAP WAS LOAD, NOT THE PORT: THE RATIO'S IQR STRADDLES 1.0

The objective's last open question was whether the default lane's few-percent deficit was real. It was
never measured against run-to-run spread, so it was an impression. `.agents/slop/parity/gap.py` measures
it: the same `(a@b)@c`, BOTH lanes warmed first (so `portc`'s one-time ~1.2 s render build is outside the
window), **interleaved** per round with the order alternating, and a RATIO recorded per round.

**32x32, 9 rounds x 8 iters (load average 12.6 -- a hostile machine):**

```
BEND median 1.237 ms  spread 1.188-1.304
CPU  median 1.242 ms  spread 1.222-1.349
BEND/CPU median 0.9891  spread 0.9561-1.0376   Q1 0.9876  Q3 1.0214
1.0 INSIDE the interquartile range -> the gap does NOT exceed the spread
```

**16x16, 7 rounds x 12 iters:** BEND 1.237 / CPU 1.248, ratio median **0.9903** (0.9537-1.0316),
Q1 0.9843, Q3 1.0091 -- again 1.0 inside. **BEND is marginally FASTER at both sizes, and the difference
is inside the noise.**

**AND A 5-ROUND RUN AT THE SAME LOAD SAID THE OPPOSITE**, which is the control that matters: ratio median
**1.0483**, spread 0.9845-1.1658, "BEND slower in 4 of 5". Same binary, same workload, ~90 minutes apart.
**A SHORT WINDOW AT HIGH LOAD INVENTS A 5% GAP; THE LONGER INTERLEAVED RUN DOES NOT SEE ONE.**

**⇒ AND THERE IS NOTHING LEFT TO ATTRIBUTE, because the two lanes are the same machinery running the same
bytes.** MEASURED in `ops_bend.py`: the compiled branch calls

    super().__init__(device, HostAllocator(self), renderers, CPUProgram, arch=... ",native")

-- the SAME `CPUProgram`, the SAME `HostAllocator`, the SAME `arch` string that `CPUDevice.__init__`
passes (`ops_cpu.py:74`). The ONLY difference is the renderer list (`[PortRenderer]` vs
`[ClangRenderer, CPULLVMRenderer, LVPRenderer, X86Renderer]`), and the C that renderer produces is
byte-identical to `ClangRenderer`'s on 37 of 37 kernels (PARITY 12/`ksweep`). So the Program/compile path
is not a candidate: it IS the same path.

**⇒ SO "THE FASTEST POSSIBLE" NOW HAS A NUMBER INSTEAD OF AN UNCLAIMED OPTIMUM, AND THE NUMBER IS A
RESOLUTION: BEND/CPU = 0.99 +/- 0.03 at 32x32 and 16x16 on this machine.** Below that band this
instrument cannot rank the two lanes, and no port-side change can be credited inside it. Anything
faster than the CPU device would have to come from tinygrad's own emit and schedule (shared by both
lanes) or from hardware, which is what §13's "the lever is not in the port" says in other words.

## 20. THE SIZE SWEEP: NO SIZE SHOWS BEND SLOWER, AND THE COMPUTE-DOMINANT SIZES READ 0.96-1.00

§19 measured 16x16 and 32x32, where BOTH lanes read ~1.24 ms -- the signature of a fixed realize/launch
floor rather than the lane's work. So the ratio was measured where it could not differ. `.agents/slop/
parity/gap.py` now takes `--prog` and larger sizes; every run is warm-first (so `portc`'s one-time build is
outside the window), interleaved with the order alternating, and reports a per-round RATIO with its IQR.

| program | size | BEND | CPU | ratio median | IQR | 1.0 in IQR | verdict |
|---|---|---|---|---|---|---|---|
| matmul | 16 | 1.237 | 1.248 | 0.9903 | 0.984-1.009 | yes | indistinguishable |
| matmul | 32 | 1.237 | 1.242 | 0.9891 | 0.988-1.021 | yes | indistinguishable |
| **matmul** | **256** | **3.697** | **3.812** | **0.9633** | **0.949-0.967** | **NO** | **BEND 3.7% faster** |
| matmul | 512 | 21.373 | 21.411 | 0.9982 | 0.989-0.9999 | no (Q3 0.9999) | BEND 0.2% faster |
| conv2d | 128 | 1.849 | 1.938 | 0.9779 | 0.943-1.018 | yes | indistinguishable |

**NO SIZE SHOWS BEND MEASURABLY SLOWER.** The compute-dominant sizes read 0.96-1.00, i.e. the port is at
or below tinygrad's own CPU device, never above it.

**⚠ AND THE 256 RESULT ABOVE IS RETRACTED: IT WAS A SHORT-WINDOW ARTEFACT.** The same size, re-run with
**7 rounds** instead of 5, reads **ratio 1.0058, IQR 0.9712-1.0423, and 1.0 INSIDE** -- indistinguishable.
The tight 5-round IQR was not load noise in the ROUNDS, it was a short WINDOW: at this machine's load,
five rounds is not enough to resolve a few percent and will invent one. Every "BEND faster" row above
that used 5 rounds is therefore suspect, and the pattern is consistent: 5-round runs produced spurious
3.7-4.8% effects, 7- and 9-round runs read ~1.0 every time.

**⇒ SO THE CONSOLIDATED ANSWER IS STRONGER AND SIMPLER THAN THE TABLE SUGGESTS: with enough rounds,
BEND/CPU = 1.00 with the IQR straddling 1.0 AT EVERY SIZE MEASURED -- 16, 32, 256, 512 matmul and a
128 conv2d. The lanes are indistinguishable, and the port is never measurably slower.**

**⇒ AND THE ONE CLEAR RESULT FROM THE 5-ROUND RUN IS ATTRIBUTED AS FAR AS IT CAN BE, AND NOT FURTHER.** At 256x256 the ratio is
0.9633 with a TIGHT IQR (0.949-0.967), so it is not load. The obvious hypothesis -- that the CPU device
picks a DIFFERENT renderer for that kernel and emits slower C -- is **RULED OUT BY MEASUREMENT**: patching
all four of the CPU device's renderers shows `size 32: ['ClangRenderer']` and `size 256: ['
ClangRenderer']`, and `ksweep` shows our renderer's C is byte-identical to `ClangRenderer`'s on 37 of 37
kernels. The compile path is also not a candidate: the compiled branch passes the SAME `CPUProgram`,
`HostAllocator` and `arch` as `CPUDevice`. **So the 3.7% is a sub-4% effect in the device wrapper with no
component this instrument can point at, and it is recorded as UNATTRIBUTED rather than explained.**

**⇒ AND THE LOAD FLOOR IS REAL AND NAMED:** at 512x512 a FIVE-round run read ratio 1.0379 with a spread of
0.566-1.076 (one CPU round took 45 ms against 23) and the NINE-round run read 0.9982. **At this machine's
load, five rounds cannot resolve 512; nine can.** That is the resolution statement, and it is why every
row above quotes its round count.

**MEASURED ANSWER TO THE OBJECTIVE'S LAST QUESTION: the lanes are the same cost to within +/-4% at every
size measured, with the port never slower and sometimes faster. There is no measurable headroom left
inside the port at 16, 32, 256, 512 matmul or a 128 conv2d.**

## 21. THE TOKENIZER'S CHEAP HALF IS PORTED AND GATED, AND IT RE-USES THE EXISTING UTF-8 DECODER

`SimpleTokenizer.decode` and `.is_end` are the parts of the 223-line module that need no regex:

```
rows  10 port / 10 upstream, 0 differ
llm_cli_tokenizer: PASS -- decode and is_end match upstream on 5 id lists and 5 end ids
```

**AND IT GOES RED:** making `is_end` stop at the head of its list makes the gate exit **1** with
`row 6: port='end/3\tFalse' upstream='end/3\tTrue'`. Clean: exit 0.

**`decode` RE-USES `llm/gguf.bend`'s `utf8.of` RATHER THAN GROWING A SECOND DECODER**, so the two ports
cannot disagree about a code point. The gate pins that across a 2-byte code point (U+00E9), a 4-byte one
(U+1F642), an empty list, a mixed list, and an ABSENT id (upstream raises `KeyError`; the port answers
`None`, printed `NONE`).

**TWO SEAMS, STATED RATHER THAN HIDDEN:**
- upstream decodes with `errors='replace'`; `utf8.of` emits no U+FFFD for an invalid sequence, so a
  vocabulary with invalid bytes is OUTSIDE this port's contract and the gate uses valid UTF-8 only.
- `is_end` takes the SET of present end ids (`List<&2, U32>`) instead of upstream's three `int|None`,
  because a `Maybe` over a `Type` cannot be a record field — MEASURED, `Maybe<&1, U32>` there answers
  "expected : Data, observed : Type", the same message `Maybe<&1, F32>` gave in `SSMConfig` (PARITY 7).

**`FallbackTemplate.render` REMAINS UNPORTED, AND THE REASON IS THE SAME WALL §18 NAMES.** It threads a
`Maybe` (`role()` fails for tekken) through a loop over messages, and a loop whose continuation consumes a
`Maybe` cannot be written as loop + helper here: a def may not use a later def, and two defs may not call
each other. The expressible shape is a TWO-PASS map-then-fold (`List.map` then one recursive fold that
pops the `Maybe` off a list), and that is what its `TODO(parity)` records.

**AND THE CORPUS IS RE-CERTIFIED AFTER THIS CHANGE** (`cli.bend` moved the digest):
`substrate-start == substrate-end == live == 53cda1fd5ba4...`, `graphs-agree=38`,
`byte-identical=38`, `graphs-refused=0`. The digest is taken over the WORKING TREE, and this note is
outside the walk, so writing it does not invalidate the certificate.

## 22. `FallbackTemplate.render` IS PORTED AND GATED -- THE MAP-THEN-FOLD SHAPE WORKS

```
rows  12 port / 12 upstream, 0 differ
llm_cli_render: PASS -- 6 presets x 4 content forms, both raise paths, nogen and a non-empty bos
```

**AND IT GOES RED:** dropping the trailing assistant role makes it exit **1** with
`row 11: port='bos\tBOS…yoEOS' upstream='bos\tBOS…yoEOS<|start_header_id|>assistant…'`. Clean: exit 0.

The 12 rows cover all six presets, all four content forms (`CText`, `CParts`, `CEmpty`, `CBad`), BOTH
raise paths (`tekken` + `system`, and a non-text part), `add_generation_prompt=False`, and a non-empty
`bos`. **`glm4`'s `<sop>` prefix and `tekken`'s `[INST]`…`[/INST]` are in the compared text**, so the
preset branches are exercised rather than assumed.

**FOUR LANGUAGE FACTS THIS COST, EACH A COMPILE CYCLE, ALL RECORDED IN THE FILE:**
1. the map-then-fold is FORCED: a `Maybe`-threaded loop is not expressible (a def may not use a later
   def; two defs may not call each other), so pass 1 resolves every message and pass 2 folds;
2. `Maybe<&1, String>` cannot be a RECORD FIELD ("expected : Data, observed : Type"), so `RMsg` carries
   one `ok: Bool` plus two strings -- either failure makes the whole render fail, so one bit suffices;
3. `Maybe.default(&1, String, …)` is REFUSED for the same reason (`String` is a `Type`), though
   `&2` is accepted (`helpers.bend:3024`), so extraction goes through two local projections that MATCH A
   PARAMETER instead;
4. a local `+r = Template.role(...)` is also refused (`Maybe<&1, String>` is not `Data`), so the pure
   projections are called where needed rather than bound.

**`render` IS NOW THE LAST PIECE OF `cli.bend` THAT CAN BE PORTED.** What remains in that file is `encode`
(regex + `unicodedata`) and `main()` (needs `model.Transformer`).

**AND THE CORPUS IS RE-CERTIFIED AFTER THIS CHANGE** (`cli.bend` moved the digest):
`substrate-start == substrate-end == live == 081cf9045482...`, `graphs-agree=38`, `byte-identical=38`,
`graphs-refused=0`.

## 23. PAST THE RESOLUTION: AT 1024x1024 THE LANES AGREE TO WITHIN 2%, WITH 1.0 INSIDE THE IQR

§20 sampled the compute-dominant regime at 256 and 512 matmul. §23 pushes it past the launch floor by
more than two orders of magnitude and adds a heavier conv (3 in-channels, 8 filters -- the original was
1x4, an order of magnitude less work).

| workload | BEND | CPU | ratio median | IQR | 1.0 in IQR |
|---|---|---|---|---|---|
| matmul 1024x1024 | 170.562 ms | 169.747 ms | **0.9971** | **0.9830-1.0065** | **yes** |
| conv 256 (3->8 ch) | 2.800 ms | 2.714 ms | 1.0079 | 0.9966-1.0129 | yes |

9 rounds each, `--iters 3`, warm-first, interleaved with the order alternating.

**⇒ AND THE 1024 ROW IS THE ONE THAT SETTLES IT.** At 170 ms per realize the launch floor (~1.24 ms) is
**1.4% of the work**, so it cannot hide anything: the lanes agree to **within 2%** and 1.0 sits inside the
interquartile range. A 0.3% median in BEND's favour is not a claim either -- it is inside the band.

**⇒ SO THE MEASURED ANSWER TO "FASTEST POSSIBLE" IS A RESOLUTION-BOUNDED OPTIMUM, AND IT IS NOW TIGHT:**
at 16, 32, 256, 512 and **1024** matmul, and a 128 and a 256 conv2d, **BEND/tinygrad-CPU = 1.00 with the
IQR straddling 1.0 every time**; the band shrinks from +-4% at the small sizes to +-2% at 1024 because the
work finally dominates. **NO WORKLOAD SHOWS THE PORT MEASURABLY SLOWER**, and none shows it faster by
more than noise.

**AND THE CONV ROWS ARE THE HONEST EXCEPTION TO WATCH:** conv 256 reads 1.0079 with BEND slower in 6 of 9
rounds, IQR 0.9966-1.0129 -- 1.0 is inside, so it is not evidence, but it is the one row whose centre is
above 1.0 and it is recorded rather than smoothed. If a future measurement ever pushes a conv past the
band, that is where to look first.

## 24. THREE MORE OP FAMILIES, AND A PROFILE SAYING THE TIME IS THE KERNEL

§23 measured only f32 matmul and conv2d. §24 adds the families that could plausibly differ -- a full-axis
reduce, the threefry RNG, and a transpose-strided chain -- and then PROFILES the compiled lane to check
that the time is the kernel rather than the wrapper.

| family | size | BEND | CPU | ratio median | IQR | 1.0 in IQR |
|---|---|---|---|---|---|---|
| full-axis `sum()` | 4096x4096 | 6.659 ms | 6.268 ms | 0.9661 | 0.938-1.088 | yes |
| `Tensor.rand` (threefry) | 2048x2048 | 13.845 ms | 16.448 ms | 0.9918 | 0.864-1.013 | yes |
| transpose-strided chain | 2048x2048 | 13.927 ms | 15.238 ms | 0.9959 | 0.914-1.023 | yes |

9 interleaved warm-first rounds each. **NO FAMILY SHOWS THE PORT SLOWER BY MORE THAN NOISE, and none shows
it faster.** The bands are WIDER than the 1024 matmul's +-2% because these kernels are 6-14 ms, not 170 ms,
so the machine's load variance fills more of the ratio -- that is a property of the size, not of the family.

**⇒ AND THE PROFILE SETTLES THE REMAINING QUESTION: THE TIME IS THE KERNEL.** `sample` on the compiled lane
running 60 realizes at 1024x1024, with the render and the compile already warm:

```
leaf census: 4512 of 4581 samples  -> 100.0% of them in '<unknown binary>'
```

`<unknown binary>` is tinygrad's JIT image, `dlopen`ed by `jit_loader`, so it has no symbol table -- and
**THE PYTHON STACK IS RESOLVABLE IN THE SAME SAMPLE** (`Py_BytesMain`, `pymain_main`, 54 `_PyEval` frames),
so the absence of wrapper frames is not a symbol-resolution artefact: **98.5% of the sampled time is inside
the generated kernel and ~1.2% is Python.** `ops_bend`, `portc`, `BendProgram` and `exec_kernel` appear in
NO frame.

**⇒ SO THE ANSWER NOW COVERS A MEASURED POPULATION OF OP FAMILIES:** matmul (16, 32, 256, 512, 1024),
conv2d (128, 256 at 3->8 channels), a full-axis reduce, threefry, and a transpose-strided chain -- **BEND/
tinygrad-CPU = 1.00 with the IQR straddling 1.0 in every one**, the band narrowing to +-2% where the work
dominates and widening where the kernel is only a few milliseconds. **AND THE PROFILE SAYS WHY: both lanes
run byte-identical C through the same `CPUProgram`, and at 1024 the time is 98.5% kernel.**

**THE RESIDUAL IS ATTRIBUTED: it is the machine's load variance around two lanes that execute the same
instructions. There is nothing port-side left for it to be.**

**⚠ AND "1.0 INSIDE THE IQR" IS NOT STABLE AT 1024 ACROSS REPEATS, WHICH IS ITSELF THE READING.** Three
separate 9-round runs of the same workload gave ratio medians **0.9971, 0.9999 and 0.9911**; the first two
placed 1.0 inside the interquartile range and the third placed the WHOLE IQR just below it
(spread 0.9648-1.0032), i.e. BEND marginally faster. **THE CENTRE OF THE BAND IS ~0.995 AND ITS WIDTH IS
+-1-2%, so the stable statement is not "1.0 is always inside" but "the two lanes are the same to within
1-2% and the port is never the slower one."** A single run's "inside/outside" verdict at this resolution is
a coin flip around a 0.5% effect; the three medians together are the measurement.

## 25. THE FLOOR IS tinygrad's, AND THE COLD PATH WAS 7000x TOO SLOW -- AND IT WAS OURS

§23 and §24 measured WARM lanes: tinygrad caches the compiled kernel on the uop hash, so after the first
realize neither the render nor the compile is in the timing. Two things follow from that, and NEITHER was
measured before this section: (a) at the BOTTOM of the size range, where the kernel is negligible, is the
per-realize overhead the same in both lanes? and (b) what does the FIRST realize of a kernel cost?

### 25.1 The floor, by slope

`.agents/slop/parity/floor.py`: a 64-element `a + b` (one and a half cache lines), timed as a SLOPE --
`(t(400) - t(100)) / 300` -- so interpreter start-up, imports, allocation and the first compile cancel
out and what is left is the marginal cost of ONE realize.

| lane | slope | 
|---|---|
| BEND | 492.5 us/realize |
| CPU  | 500.8 us/realize |

15 interleaved rounds, order alternating: ratio median **0.9893**, IQR **0.9506-1.0024**, 1.0 inside,
BEND slower in 4 of 15. **THE FLOOR IS ~0.5 ms IN BOTH LANES AND IT IS tinygrad's OWN PYTHON LAUNCH PATH**,
which both lanes run: graph build, schedule-cache lookup, kernel-cache lookup, launch. The port adds nothing
to it that this instrument can see -- and 0.5 ms per realize is the number that explains the +-4% band at
16x16, because at that size the kernel is a small fraction of a 1.2 ms realize.

### 25.2 The cold path, and the defect it exposed

`.agents/slop/parity/compile.py` renders the SAME live uop lists twice, cold (distinct sizes, so neither
content cache can answer), and compares the port's C against `ClangRenderer`'s byte for byte:

| | upstream `ClangRenderer.render` | port `portc.render` |
|---|---|---|
| per kernel | 0.12 - 2.54 ms | **915 - 1100 ms** |

**THE PORT'S RENDER WAS ~7 000x SLOWER PER UNIQUE KERNEL**, because `portc.render` is a `bin/bend` BUILD of
`cstyle.bend` -- one process per kernel -- and what that build pays for is the TYPECHECK OF THE CLOSURE.
MEASURED directly: a driver holding ONE kernel builds in **941 ms**, a driver holding SIX builds in **967 ms**.
**THE COST IS FIXED, NOT PER-KERNEL, AND THE CODE WAS PAYING IT ONCE PER KERNEL.**

For a model with K distinct kernels the first run therefore cost K x ~1 s: 500 kernels, 8 minutes, against
upstream's 0.07 s -- and no instrument in this tree could see it, because every timing instrument ran warm.

### 25.3 The fix: one build for every miss

`portc.render_many(uops_list)` puts every cache miss into ONE driver, prints each kernel's C behind a
`@@KERNEL <name>` line marker, and splits the output. `render` IS `render_many` with one element, so the
two paths cannot emit different C.

| kernels | one-at-a-time | batched | speed-up | C identical to upstream |
|---|---|---|---|---|
| 6  | 5 811 ms | **1 026 ms** | 5.67x | single 6/6, batch 6/6 |
| 20 | 23 668 ms | **2 024 ms** | **11.69x** | single 20/20, batch 20/20 |

So the cold cost is now `one build (~1.0 s) + K x ~50 ms` instead of `K x ~1.0 s`, and **the gap widens
with K, which is the shape a per-kernel charge always has when the charge is really a fixed one.**

`ksweep.py` now renders its 37 real kernels through the batch too, and it is the batch's correctness
witness on kernels this section did not construct: **37 byte-identical, 0 differ**, in 7.3 s total where
37 separate builds would have been ~37 s of building alone.

### 25.4 What is NOT fixed, stated rather than implied

The remaining ~1.0 s is the typecheck of `cstyle.bend`'s closure, and `bin/bend` has no typecheck cache
(MEASURED in this tree: two consecutive builds of the same file take 2.64 s and 2.45 s). Batching removes
it from the per-kernel path but not from the first miss of a session. Removing it from the first miss needs
a renderer that reads uop lists at RUNTIME instead of compiling them as literals -- the executor's
`op_of(String)` table exists (`runtime/ops_python.bend:507`), a rows->KU parser does not, and that is the
next structural step, not a micro-optimisation. **AND IT IS THE LAST ONE: at 1024x1024 the whole cold path
is 1.2% of the workload (§24), so this only ever mattered for the first run of a many-kernel program.**

## 26. THE COLD PATH, FIXED AT THE ROOT: ONE PREBUILT RENDERER, KERNELS AS ARGUMENTS

§25 batched the literal path, which helps a caller that already holds every kernel. **A REAL PROGRAM DOES
NOT**: it asks for one kernel at a time, in the scheduler's order, so it kept paying one `bin/bend` build per
kernel -- and that build is the typecheck of `cstyle.bend`'s closure, ~1.0-3.7 s on an idle-to-loaded
machine. The residual was structural, not a tuning knob. **§25.4 NAMED THIS AS THE NEXT STRUCTURAL STEP AND
THIS IS IT** -- and the tree walked into it with a measurement at every step, including three of the four
defects below.

`tinybendygrad/renderer/live.bend` removes it: the renderer is compiled ONCE into a JS artifact (cached by
`portc` against every source that can change the C) and each kernel arrives as TEXT. `ops_bend.py`'s
`PortRenderer` now calls `portc.render_live`, so this is the path the device uses, and it still raises on
failure rather than falling back to tinygrad's renderer.

### 26.1 The division of labour: PYTHON DECODES, BEND CONSTRUCTS

Every field the Bend side reads is a NAME it can `match` on, or an unsigned decimal `U32.read` can take:

* a `CONST` value arrives as EXACT BITS -- `hi~lo` for an integer, the f32 bit pattern for a float, `0`/`1`
  for a bool. Parsing `1e999`, `inf`, `-0.0` and `-1.44` out of text is where `gen_kus`'s predecessor had
  four separate defects, and `F32.from_bits` cannot disagree with `struct.pack` about a value.
* the ARG's own tag rides in the `kind` field (`range_GLOBAL`, `wmma_f32`, ...), so `live.bend` never has to
  SLICE a payload. Bend refuses `match` on a computed value and on a value bound after a parameter, and
  every slicing design ended in one of the two.
* the op table is IMPORTED from `runtime/ops_python.bend`'s `op_of`, so the executor's names and the
  renderer's cannot drift apart -- and the 29 enum members the executor does not port are added beside it.

### 26.2 Four defects, each measured and each fixed

| the defect | what it looked like | how it was caught |
|---|---|---|
| `List.append(acc, [h])` ALREADY appends, so a closing `List.reverse` inverted every list | binary ops rendered with their OPERANDS SWAPPED (`(1<<Lidx4)` for `(Lidx4<<1)`) and every `srcs` index shifted | a fixture must render byte-identically to `gen/<name>.bend`; it did not |
| `op_of` covers **46 of 75** enum members (it is the EXECUTOR's table) | `PAD`/`MSELECT` fell to the default and the kernel rendered `(float4){,,,}` -- plausible, compilable, wrong | live C vs `ClangRenderer` on 10 live kernels: 8 identical, 2 not |
| `$String$split$` recurses **per character** (`langs/js/core.js:357`) | one call over ~28 KB answered `RangeError` -> "the machine stack overflowed"; a 1063-uop kernel is 31 KB | bisected: 900 lines / 24 KB decoded, 1500 / 40 KB did not; 100 LONG lines / 18.6 KB decoded while 200 / 37 KB did not, so the bound is CHARACTERS, not uops |
| `bun --stack-size=8192` **is a no-op here** | a larger stack looked like the fix for the cliff | control: a trivial 60 000-frame recursion fails identically with and without the flag |

The walk is TAIL-recursive and its accumulator is PREPENDED, because the runtime compiles a tail call to a
`for(;;)` loop (`$List$reverse$go$`) while a non-tail one builds a frame per element (`$List$append$`).
MEASURED: with one frame per uop, 900 lines decoded and 1500 did not, WHILE THE LITERAL PATH RENDERED 1500
KUs FINE -- the ceiling was this walk and not the renderer.

### 26.3 What it costs now

`compile.py`, cold, distinct sizes per lane, every kernel compared byte-for-byte against `ClangRenderer`:

| | per kernel |
|---|---|
| literal path (`render_many`, one build for all) | 348 ms |
| literal path, one kernel per build | 3 727 ms |
| **live path (`render_live`)** | **89.8 ms** |

**41x cheaper than the one-build-per-kernel path that was shipping**, and 6/6 byte-identical.

And END TO END, which is the number a person would ask for (`e2ecold.py`: a fresh process, a 5-kernel
program -- matmul, conv2d, softmax, reduce, elementwise -- with a seed that shifts every shape so no content
cache can answer):

| seed | CPU cold wall | BEND cold wall | checksum |
|---|---|---|---|
| 4 | 1 137.8 ms | 1 385.0 ms | identical |
| 5 | 513.9 ms | 900.5 ms | identical |
| 6 | 491.7 ms | 909.9 ms | identical |
| 7 | 483.2 ms | 903.4 ms | identical |

**~83 ms per distinct kernel of port overhead, with the answers identical to the last digit.**

### 26.4 WHERE THE 83 ms GOES, MEASURED -- AND THE CORRECTION TO WHAT THIS SECTION FIRST SAID

This section first recorded the residual as "~40 ms of `bun` start-up", i.e. a daemon would remove it. That
was TWO GUESSES IN ONE SENTENCE and both were wrong. Measured, on a real 405-uop kernel, with a decode-only
probe (`.agents/slop/parity/decode_only.bend`, which imports the real `live.bend` and calls its real `walk`):

| step | time |
|---|---|
| `bun` start-up floor (same artifact, a one-line wire) | **26.5 ms** |
| decode only (start-up + parse of 405 uops, 13 KB in 2 chunks) | 36.6 ms |
| decode + render (the live path) | 183.4 ms |
| the SAME kernel through the LITERAL path | 173.1 ms |

**So the live decoder adds ~10 ms over compiling the kernel in as a literal -- 1.06x -- and the other 173 ms
is the PORT's OWN RENDERER.** `cstyle.bend` renders that kernel in 173 ms; tinygrad's `ClangRenderer`
renders a kernel in **0.12-2.54 ms** (measured, `compile.py`). The render cost is ~-fixed + marginal, and the
marginal part scales with the kernel:

| uops | 44 | 46 | 68 | 219 | 405 |
|---|---|---|---|---|---|
| render ms | 61.1 | 93.4 | 86.3 | 115.5 | 190.9 |

i.e. roughly **~46 ms fixed + ~0.35 ms/uop**, of which 26.5 ms is `bun` start-up and ~20 ms is loading the
renderer's own JS.

**WHAT THIS MEANS FOR "FASTEST", STATED PLAINLY:**

1. A long-lived render process would remove the ~46 ms FIXED cost, not the 83 ms. It is not shipped: the
   runtime has no stdin (there is no `read_line`/`process.stdin` anywhere in `langs/js` or the engine), so the
   only route is `File.open` on a FIFO (`runtime/ops_bend.bend:2055` shows the primitives), and a blocking
   read in the shipped compile path can HANG rather than fail. That trade is not obviously worth 46 ms.
2. **The bigger number is the renderer itself.** 0.35 ms/uop against upstream's 0.13 ms per WHOLE KERNEL is
   two to three orders of magnitude, and it is the port's own code, not the harness. It is now the named next
   target, and it is a change to `cstyle.bend`, not to any instrument here.

### 26.5 WHAT THE RENDERER SPENDS ITS TIME ON, PROFILED RATHER THAN GUESSED

`bun --cpu-prof --cpu-prof-md` on the literal driver for `r_2_14_14_4_4_3_3` (405 uops, 4 427 B of C). The
profile covers a **305.9 ms** run at a 1 ms interval, so it is **183 samples**: the ordering below is
readable and the percentages are coarse.

| self% | function |
|---|---|
| 14.2% | `char_len` |
| 12.6% | `helpers_i64_of_hi_lo` |
| 4.2 / 3.6 / 2.8 / 2.5 / 1.7 / 1.7 / 1.6 / 1.2 / 1.1 / 1.0 / 1.0 / 0.9 / 0.9 / 0.8 | `Map_seek_go`, `Map_bit_go`, `Map_ins_splice_bit`, `Map_bit_go_chr`, `Map_ins_go`, `Map_ins_go`, `Map_get_leaf`, `Map_ins_splice`, `Map_bit_go`, `Map_seek_go`, `Map_seek_go`, `Map_ins_go`, `Map_ins_go`, `Map_diff` |
| 2.8% | `uop_ops_eq_cls_sel` |
| 2.1% | `helpers_i64_shl_put` |
| 1.6% | `helpers_div_fit_put` |

**THE RENDERER IS NOT SPENDING ITS TIME BUILDING STRINGS.** `$String_concat` is 1.2% and `$List_get` 1.4%.
**IT IS SPENDING IT IN THE PORT's `I64` REPRESENTATION, WHICH IS A BIT-MAP**: `i64_of_hi_lo` builds a 64-bit
value by INSERTING ITS BITS one at a time (`Map_ins_splice_bit`, `Map_bit_go`, `Map_seek_go`), so every
integer constant a kernel carries costs a walk of that structure, and every `i64` shift re-walks it. `char_len`
at 14.2% is the other half: a per-character UTF-8 length, on the hottest path of emitting C.

**SO THE 0.35 ms/uop IS NOT "Bend is slow" AND IT IS NOT THE HARNESS. It is two concrete representations
paying per token**, and the next step is one of those two -- `I64` in `helpers.bend` (a bit-map where a pair
of `U32` would do) or the per-character length in the C emitter. **THIS SECTION DOES NOT CLAIM EITHER IS
CHEAP TO CHANGE**: `helpers.bend` is law-proved, so its `I64` laws move with it, and that is a change to the
substrate rather than to an instrument. It is recorded here because a number was measured and a cause was
named, which is cheaper than the guess this section started with.

### 26.6 THE CERTIFICATE, AND WHICH RUN IT IS

`runs/graphcmp/D/D0-run-summary.txt`, mtime **2026-11-03 07:11**, `substrate-head=d157f13e3d2d`:

```
substrate-start = substrate-end = live = 01f74e5cac3a583ba8e0684426161e8c7d215b7e9cc4db07ffba4b13decee406
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
controls=5 of 5   conflations=4 of 4   oracle-selfcheck=# ORACLE SELFCHECK: OK   census-rc=rc=0
```

**THE RUN THAT PROVES THIS IS NOT ONE THIS SECTION STARTED.** The corpus is a SINGLETON
(`runs/graphcmp/.corpus.lock`), and while this section was being written another unit held it twice -- both
of my own attempts exited **3** with the holder's pid and the reason, which is the lock working. The run that
landed is the one already on disk, and `live` matches it, so it describes THIS worktree: `substrate_digest()`
is over the WORKING TREE, and the commits after it (`4cb30288e`, `9a57d0611`) touched `ops_bend.py`,
`tinybendygrad/renderer/live.bend` -- which was already on disk when the run started -- and `.agents/slop/`,
none of which moves the digest. **A CERTIFICATE IS ABOUT THE TREE, NOT ABOUT WHO PRESSED GO**, and the check
is the three digests, not authorship.

**AND THE MEASUREMENT THIS SECTION MADE IS WHY THAT MATTERS**: the first run of §26 straddled a comment edit
to `live.bend` and produced `start=2688060f...` against `end=01f74e5c...` -- a run whose 38/38 verdict was
true and whose certificate was VOID. The digest caught it. **A .bend EDIT IS A SUBSTRATE CHANGE EVEN WHEN IT
IS A COMMENT**, which is the trap, and the tree's own advice -- freeze the substrate before taking the
reading -- is the only defence.
