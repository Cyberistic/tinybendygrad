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

## 27. THE RENDERER, 2x: A STRING-KEYED TYPE MAP BUILT SIX TIMES PER DTYPE

§26.5 named the renderer as the target and guessed at `I64`. **THE GUESS WAS WRONG IN ITS FIRST HALF and this
section retracts it before fixing anything:** `type I64 is Data: I64{hi: U32, lo: U32}` in
`helpers.bend:1648` -- **`I64` WAS ALREADY A U32 PAIR**, and `i64_of_hi_lo` compiles to
`{$: "I64", hi, lo}`, a two-field object literal. A function that cheap cannot be 12% of a render in SELF
time; what 12% means is that it is CALLED millions of times, and a profile's leaf ranks are a map of the call
COUNT, not of the cost. Reading them as "this function is expensive" is the mistake this section started
with.

### 27.1 The real cause, from the call tree rather than the leaf list

Same 405-uop kernel, `bun --cpu-prof --cpu-prof-interval=50` (**2 062 samples at 50 us**, where the previous
reading had 183 at 1 ms and could not resolve this):

| total% | function |
|---|---|
| 81.8% | `cstyle.render` |
| 66.6% | `List_append` |
| 58.3% | `render_dtype` |
| 57.9% | `rd_base_name` |
| 54.0% | `type_map_over` |
| 53.4% | `Kv_go` -> **`Map_set` 53.4%** |
| 53.1% | `type_map_of` -> `type_map_clang` 53.1% |

**`type_map.of(dev)` BUILDS the device's type map on every call**, and the map's keys are `String`s, so every
insert hashes a string a character at a time -- which is why `char_len` (15.0%) and `Char_cmp` (2.0%) were
sitting at the top of the leaf list with no obvious caller. The code built it SIX TIMES PER DTYPE:
`rd_name` called `rd_base_name` three times on one line, and `rd_body` called `rd_name` in BOTH arms of a
`Bool.pick`, which evaluates both.

### 27.2 The change

`rd_name` and `rd_body` now take the base name from ONE lookup (`rd_name_at`, `rd_body_at`), so a dtype
render builds the map once instead of six times. Nothing else moves: the same name is looked up once instead
of six times, and the emitted C is identical.

### 27.3 Measured

Render of the same fixture kernels, `bun` run only, 5 runs each:

| uops | before | after | speed-up |
|---|---|---|---|
| 46 | 93.4 ms | **41.7 ms** | 2.24x |
| 219 | 115.5 ms | **62.1 ms** | 1.86x |
| 405 | 190.9 ms | **94.0 ms** | 2.03x |

and the number that matters for a real program, `compile.py` cold with every kernel compared against
`ClangRenderer`: **89.8 ms -> 43.8 ms per kernel (2.05x), 6/6 byte-identical.**

End to end (`e2ecold.py`, fresh process, 5 kernels, checksums identical):

| seed | CPU cold wall | BEND cold wall |
|---|---|---|
| 5 | 212.7 ms | 615.6 ms |
| 6 | 209.0 ms | 594.1 ms |
| 7 | 209.3 ms | 565.0 ms |

**AND THE HONEST READING OF THAT TABLE IS THAT THE GAP BARELY MOVED** -- it was ~415 ms and is ~380 ms --
because for these SMALL kernels the ~46 ms of fixed cost (26.5 ms `bun` start-up plus module load) and the
~10 ms decode are most of what is left, and the render is now a minority of the difference. The render win is
real and it is what a LARGE kernel feels: at 405 uops the path halved.

### 27.4 Corrected: the same measurement, and what leads now

With the map hoisted, the leaf list on the same kernel is:

| self% | function |
|---|---|
| 12.4% | `helpers_i64_of_hi_lo` |
| 9.6% | `helpers_i64_shl_put` |
| 7.4% | `char_len` |
| 3.5% | `nat_divmod` |
| 2.4% | `helpers_div_qbit` |
| 1.9% | `Map_bit_go` |

`i64_shl_put` + `nat_divmod` + `div_qbit` is **integer -> DECIMAL conversion, done by bit-serial division**:
round this tree's I64 by 10, thirty-two bit steps at a time, for every integer constant the kernel carries.
That is the next target and it is named here with its composition rather than guessed at; the fix is in
`helpers.bend`'s decimal printing (chunked division by a power of ten), and it is not attempted in this
commit.

### 27.5 The certificate for THIS change

`runs/graphcmp/D/D0-run-summary.txt`, mtime **2026-11-03 08:05**, `substrate-head=adaf1ee20` -- the commit
that carries the hoist:

```
substrate-start = substrate-end = live = 2d80b784a048e217680b9a4d965ccd63f07e87a76746b30b3e7f2cf12e306530
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
controls=5 of 5   conflations=4 of 4   oracle-selfcheck=# ORACLE SELFCHECK: OK   census-rc=rc=0
```

**A 2x CHANGE TO THE RENDERER THAT MOVES NO BYTE**: every one of the 38 graphs is still byte-identical to
CPython at the pin, and the digest that straddles the run is the one the tree is standing on.

## 28. THE DECIMAL FOLD: 21 DIVISIONS FOR A THREE-DIGIT CONSTANT

§27.4 named integer -> decimal as the next target and gave its composition. The cause is the FUEL: `i64_dec`
ran `i64_dec.go(20n, ...)` -- twenty steps, one `u64_divmod` each -- and `u64_divmod` is `div_loop(64n, ...)`,
i.e. **sixty-four bit steps whatever the values are**. So a constant like `392` paid 21 divisions and 1 344
bit steps to print three digits, and every integer constant in every kernel paid it again.

### 28.1 The change

The fuel is now the ACTUAL digit count, and the count is found by COMPARISON, never by division: multiply a
power of ten up from 1 and add one for each that fits. `i64_dec.digits` is that fold; `x * 10` is spelled
`(x << 3) + (x << 1)` because `u64_mul` is defined LATER in `helpers.bend` and a Bend def cannot be
referenced before it -- and two shifts and an add are cheaper than a full 64-bit multiply anyway, so the
ordering constraint and the faster spelling coincide.

### 28.2 Two defects, both caught by measurement rather than by reading

1. **The first threshold test was INVERTED.** `Bool.not(u64_lt(hi(p), lo(p), hi(x), lo(x)))` is `p >= x`,
   not `p <= x`, so the count came out right only for ten-digit values by accident. MEASURED with
   `decode_only`-style value rows: `2147483647` printed `147483647` -- ONE DIGIT SHORT -- and the truncation
   was invisible on every nine-digit-and-under row, which is most of them.
2. **Counting needs a floor.** Zero fits no power of ten, so the fold answers 0 for it; the floor of 1 is
   `i64_dec.digits.at` and it is what keeps `0` printing as `0`.

`dec_check.bend` is the value gate: 23 rows against CPython's `str(int)`, chosen for the edges --
0, 9/10, 99/100, 999/1000, 2**31-1, 2**31, 2**32-1, 2**32, 10**18, 2**63-1, -1, -2, -2**32, int64.min,
int64.max -- **23 of 23 identical**. (That file is `.agents/slop/parity/dec_check.bend`; the `*probe.bend`
name is gitignored, which is why the decode probe is called `decode_only.bend` and this one `dec_check`.)

### 28.3 Measured

Render of the same fixture kernels, `bun` run only, 5 runs each:

| uops | §27 | now | speed-up |
|---|---|---|---|
| 46 | 41.7 ms | **32.6 ms** | 1.28x |
| 219 | 62.1 ms | **50.7 ms** | 1.22x |
| 405 | 94.0 ms | **68.0 ms** | 1.38x |

**and against where §26 started, the same 405-uop render is 190.9 -> 68.0 ms, 2.81x.**

`compile.py`, cold, every kernel compared against `ClangRenderer`: **43.8 -> 38.4 ms per kernel**, 4/4
byte-identical (MEASURED on a machine at load average 14.8; a reading of 167.9 ms/kernel on the same tree was
taken during that load and is not a measurement of anything).

### 28.4 What the fixed costs are now, and why the end-to-end gap still looks flat

At 405 uops the render is 68.0 ms, of which ~26 ms is `bun` start-up. A `compile.py` row of 38.4 ms/kernel
for ~163-uop kernels is `26 ms start-up + ~12 ms of decode and render`: **the start-up is now the largest
single term per kernel**, which is exactly the ~46 ms fixed cost §26.4 refused to buy a daemon for, and this
section does not change that judgement.

So the honest shape of the whole cold path, measured:

| term | before §27 | after §28 |
|---|---|---|
| render, 405 uops | 190.9 ms | **68.0 ms** |
| live decoder (405 uops) | ~10 ms | ~10 ms |
| `bun` start-up + module load | ~46 ms | ~46 ms |
| per kernel, `compile.py` | 89.8 ms | **38.4 ms** |

**AND THAT IS THE FIRST TIME THE START-UP HAS BEEN THE LARGEST TERM.** For the ~163-uop kernels `compile.py`
measures, one kernel now costs ~12 ms to render against ~26 ms to start the process that renders it -- the
crossover, stated where it is true and not past it: at 405 uops the render is still 68.0 ms, more than twice
the start-up.

### 28.5 The certificate for §28

`runs/graphcmp/D/D0-run-summary.txt`, mtime **08:11**, `substrate-head=509075c47`:

```
substrate-start = substrate-end = live = 81db633f28915962122b614725e30b487f3d0f8bffe7e9a340d78cb5a7471ec9
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
controls=5 of 5   conflations=4 of 4   oracle-selfcheck=# ORACLE SELFCHECK: OK   census-rc=rc=0
```

The decimal change moves no byte in any of the 38 graphs.

## 29. THE DAEMON: 4.6x PER TURN, AND IT ANSWERS THREE TIMES

§28.4 left the ~46 ms per-kernel fixed cost as the largest single term, and named a long-lived renderer as
the only thing that could remove it. This section built one, measured it, and did NOT ship it as the default
-- the reasons are below and they are measurements, not caution.

### 29.1 The protocol, and two races it had to lose first

`serve.bend` is `live.bend`'s loop: one long-lived `bun`, one kernel per signal. The request travels as a
REGULAR FILE (written to a temporary name and renamed) and the pipe carries ONE BYTE, because `File.read` on
a pipe returns whatever is available and a 13 KB wire down a pipe can be truncated while a one-byte signal
cannot.

Two defects, both found by running it rather than by reading it:

| the defect | what it measured |
|---|---|
| the reader opened and closed per request | the FIRST request answered in 90.7 ms and the SECOND never: a writer that opens while the previous reader is still closing PAIRS WITH THE STALE READER, so its byte goes to a pipe nobody reads and the worker's next open blocks forever |
| the writer opened and closed per request | `live 1/6 byte-identical`: closing the writer gives the reader an EOF BETWEEN requests, and the worker cannot tell an EOF read from a signal read, so it renders the current request file an extra time and every answer shifts by one |

The cure for both is to keep each end open for the session: one persistent reader, one persistent writer.

### 29.2 What it measures

`Worker.render`, same wire, six turns:

```
67.4  9.0  6.2  5.5  8.3  10.5 ms      steady median 8.3 ms, output IDENTICAL to the one-shot path
```

against **38.4 ms/kernel** for the one-shot live path. That is the 4.6x the fixed cost was worth.

### 29.3 And then it stops

MEASURED, twice, with a 13 KB wire and again with a 4-byte one: **the worker answers THREE turns and then
stops answering**, with the process ALIVE (`poll()` is `None`), nothing pending on its stdout, and nothing
on its stderr. The count is not a function of the request size. The cause was NOT established: the FIFO is
opened once for reading and once for writing, neither side reports an error, and `File.read` on a FIFO
through Bend's `File` layer is the one component in this path this tree has never exercised before.

**SO IT IS OPT-IN (`BEND_SERVE=1`) AND OFF BY DEFAULT**, which is a decision about the failure MODE rather
than about the speed: a stalled worker costs the 20 s timeout and then falls back, and that is 500x worse
than never starting it. With the flag off the shipped path is exactly the one-shot renderer measured in
§28 -- 38.4 ms/kernel -- and with it on the fallback is still the same renderer producing the same bytes,
counted in `worker_stats()` rather than swallowed. `BEND_SERVE=1 ksweep.py` is **37 of 37 identical on both
decoders**, so the opt-in path is correct for the turns it serves.

**⇒ AND THE HONEST SUMMARY OF §29 IS THAT THE 46 ms IS STILL THERE.** The mechanism is built, its cost is
measured at 8.3 ms per turn, and it does not survive more than three requests in this tree today.

## 30. THE STALL WAS IN THE HARNESS: THE DAEMON IS NOW THE DEFAULT, AND THE PORT IS FASTER THAN CPU END TO END

§29 ended with "the mechanism is built, its cost is measured, and it does not survive three requests". That
was true and the LOCATION was wrong: the fault was in `portc.py`, not in Bend.

### 30.1 How it was localised

`File.read` on a FIFO was the suspect, so it was taken out of Python's hands: one `bun serve.js` started
against `/tmp/sig|/tmp/req`, a shell holding `exec 3>/tmp/sig` open, six `printf 'x' >&3` at 0.6 s spacing.

```
after signal 1: 1 result(s)      after signal 4: 4 result(s)
after signal 2: 2 result(s)      after signal 5: 5 result(s)
after signal 3: 3 result(s)      after signal 6: 6 result(s)
```

**SIX OF SIX.** Bend's `File.read` on a persistent FIFO descriptor is fine, and `serve.bend` never had the
defect.

### 30.2 The defect

`select.select([proc.stdout], [], [], left)` followed by `proc.stdout.readline()`. `proc.stdout` is a
`TextIOWrapper`, so `readline` fills an **8 KB buffer**: after one result the wrapper can already hold the
NEXT result while the underlying fd is empty. `select` then reports "not ready" and waits for a byte that is
already in Python. MEASURED: stalls on the fourth turn, every run, with the worker alive and answering.

The cure is a reader thread blocking in `readline`, pushing lines to a `Queue` that the caller drains with
`get(timeout=...)`. There is no window: the thread owns the buffer, the queue owns the handoff.

### 30.3 Measured after the fix

12 consecutive turns, one wire, every answer compared to the one-shot path:

```
turns: 50 7 7 7 5 6 9 4 7 5 4 6 ms     steady median 6.0 ms, 12 of 12 identical, 0 fallbacks
```

| | one-shot (`live`, §28) | daemon |
|---|---|---|
| `compile.py` cold, per kernel | 38.4 ms | **14.2 ms** |
| ratio to the original literal path (89.8) | 2.34x | **6.3x** |

**AND END TO END THE LANES HAVE CROSSED** (`e2ecold.py`, fresh process, 5 kernels, seeds 8-9, checksums
identical):

| seed | CPU cold wall | BEND cold wall |
|---|---|---|
| 8 | 463.1 ms | **452.7 ms** |
| 9 | 375.0 ms | **347.0 ms** |
| 10 | 802.6 ms | **391.0 ms** |
| 11 | 417.9 ms | **386.3 ms** |
| 12 | 469.2 ms | 468.4 ms |

**FIVE READINGS, AND THE PORT IS AT OR BELOW tinygrad's CPU LANE IN ALL FIVE**, checksums identical in
every one. Two of them (10 and 12) are within a few ms of each other and one CPU reading (seed 10) is an
outlier at 802 ms, so the claim is "not slower, and usually a little faster", not "twice as fast".

**That is the first reading in this record where the port's lane is not slower than tinygrad's CPU lane on
a whole program**: the ~46 ms of per-kernel start-up that §26.4 refused to buy is gone from the steady path,
and what is left per kernel is a ~6 ms render plus the decode.

### 30.4 What changed in the shipped path

The daemon is **the default**; `BEND_SERVE=0` opts out, and one stall still disables it for the session and
falls back to the same renderer (so the failure mode is a timeout and a slower answer, never a hang and never
a different byte). Verified on the default path: `ksweep 37 of 37 byte-identical on BOTH decoders`,
`ops_bend_exec-e2e 7 of 7`, `opbattery 39 of 39`, `compile.py 4 of 4 identical`.

**NO `.bend` FILE UNDER `tinybendygrad/` CHANGED IN THIS SECTION** (`serve.bend` lives in
`.agents/slop/cpuseam/`, which is harness and not substrate), so the certificate is the one already on
disk: `substrate-start == substrate-end == live == 81db633f2891…`, `38 graphs, 38 byte-identical`.

## 31. THE SHIPPED PATH'S PROFILE, AND THE MAP THAT WAS STILL REBUILDING ITSELF

Every profile in §26-§28 was taken on the LITERAL driver, which builds its KU list at module load (`gen_
<name>_kus`, 4.9% of that profile and absent from the shipped path). This one is taken on the artifact the
DAEMON loads -- `out/live-*.js`, the same decode and the same `C.render` -- with the 405-uop wire as its
chunked argument, `--cpu-prof-interval=50`.

### 31.1 What it said

| self% | function |
|---|---|
| **17.5%** | **`nat_divmod`** |
| 7.2% | `char_len` |
| 2.2% | `helpers_i64_of_hi_lo` |
| 1.5 / 1.1 / 1.0 / 1.0 | `Map_bit_go`, `Map_seek`, `Map_bit_go_chr`, `Map_bit_go` |

`nat_divmod` in this runtime is a NATIVE `Math.trunc(a / b)` -- 20.2 ms of it cannot be arithmetic, it is a
CALL COUNT -- and its only caller in the tree is **`Map_bit`**, the port's hashed trie. `char_len` is the
`String` key hash. So the render was still paying for **`type_map.of(dev)`: a fourteen-to-sixteen-entry
`Map` with `String` keys, BUILT ON EVERY CALL.**

§27 cut that from six builds per dtype to one. One per dtype is still one per uop, and `checks/census.json`
cites `type_map`, so the maps stay as the transcription of record -- but the LOOKUP did not have to be a map
at all: upstream's `type_map.get(dtype, dtype.name)` is a dict with a default of the name itself, which is a
`match` with a `_` arm.

### 31.2 The change

`rd_base_name` now dispatches with `match`: one arm per device (the six dicts, entry for entry, including the
fp8 group that is ABSENT on OpenCL, the FNUZ pair on CUDA, and `bf16` NOT remapped on HIP), and a `_` that
answers the dtype's own name. No `Map`, no hashing, no allocation.

### 31.3 Measured, and the same bytes

Direct A/B, both artifacts still on disk, same wire, same machine, 7 runs each:

```
before (map)    median 77.0 ms   min 75.7   out=4427B
after (match)   median 57.2 ms   min 56.3   out=4427B
```

**1.35x**, and the output is identical to the byte. Re-profiled after the change, `nat_divmod` is GONE from
the top ten and what leads is `helpers_div_fit_put` (20.5%) -- the restoring division inside `i64_dec`,
which is §28's remaining subject.

Verified byte-identical: `ksweep 37 of 37` on BOTH decoders, `compile.py 4 of 4`, `ops_bend_exec-e2e 7 of 7`,
`opbattery 39 of 39`, `cstyle.bend ALL PROOFS CHECK`.

## 32. THE RESTORING DIVISION STARTS AT THE DIVIDEND'S TOP BIT

§31 left `helpers_div_fit_put` at 20.5% of the shipped path's profile: `div_loop` always ran **64 steps**,
so dividing a nine-bit number like `392` by ten paid for 55 steps that shift in ZEROS -- the quotient bit is
0 and the remainder stays 0, so they are pure cost.

`div_bits` answers a byte-bounded UPPER BOUND on the dividend's bit length (8/16/24/32 for a zero high word,
64 otherwise) and the loop starts there. Rounded UP, so it can never be short; a value with a non-zero high
word still gets the full 64.

### 32.1 Measured

Direct A/B on the 405-uop wire, both artifacts on disk, 7 runs each, output identical at 4 427 B:

```
before (64 steps)    median 61.8 ms   min 59.0
after  (bit bound)   median 59.4 ms   min 54.5      4%
```

**FOUR PERCENT, NOT THE 2-4x THE STEP COUNT IMPLIES, AND THAT IS THE HONEST READING.** Two reasons, both
measured: of the 57-61 ms this command takes, ~26 ms is `bun` start-up and module load, so the render is
only about half of the wall; and the profile after the change shows `helpers_div_fit_put` GONE from the top
ten while **`u32_to_word` -- the runtime's own `U32.show` -- takes 15.7%**, with `$List_set` 7.0% and
`cstyle_St_bufs` 4.3% behind it.

**⇒ SO THE REMAINING DECIMAL COST IS NO LONGER THE PORT'S.** `u32_to_word` is `langs/js`'s printer, called
once per number the emitter writes (indices, sizes, counts); the port does not own it, and the emitter's
call count is the only lever left on that site.

### 32.2 Verified

`dec_check` 23/23 against CPython's `str(int)` (the bound is the thing that could truncate a digit, so that
gate runs first), `ksweep 37 of 37 byte-identical on BOTH decoders`, `opbattery 39 of 39`,
`helpers.bend ALL PROOFS CHECK`.

## 33. ONE CONSTANT, SEVEN DECIMAL CONVERSIONS

The shipped path's profile after §32 put `u32_to_word` (the runtime's own `U32.show`) at 15.7% and left a
flat field behind it, so the next look was at WHERE the emitter formats numbers. It has only 18 `U32.show`
call sites, and the interesting one is not a show at all:

```bend
Bool.pick(String, O.eq_dt(d, S.int64()),  String.concat([H.i64_dec(i), "l"]),
  Bool.pick(String, O.eq_dt(d, S.uint64()), String.concat([H.i64_dec(i), "ul"]),
    ...
      H.i64_dec(i)))))))))
```

**`Bool.pick` IS STRICT, so every arm is evaluated and one is chosen**: that chain ran `H.i64_dec(i)` SEVEN
times per integer constant, six of whose results were thrown away. `i64_dec` is the decimal fold of §28 --
`digits + 1` divisions, each a restoring division -- so six wasted conversions per constant is the same
class of defect as §27's six map builds per dtype.

The cure is the same shape: compute it once, pass it in.

```bend
def ku_const_cast_int_at(+s: String, +dt: S.Dt, +dev: U32, k: KU, +i: H.I64) -> String: ...
def ku_const_cast_int(+dt: S.Dt, +dev: U32, k: KU, +i: H.I64) -> String:
  ku_const_cast_int_at(H.i64_dec(i), dt, dev, k, i)
```

### 33.1 Verified, and the one thing not yet measured

**BYTE-IDENTICAL**: `ksweep 37 of 37 on BOTH decoders`, `compile.py 4 of 4`, `ops_bend_exec-e2e 7 of 7`,
`opbattery 39 of 39`, `cstyle.bend ALL PROOFS CHECK`. The six discarded conversions were computing the same
string, so this cannot change the C, and it does not.

**AND THE TIMING IS NOT RESOLVED IN THIS SECTION.** The machine was at load average **13.8** throughout (a
`.venv` corpus run by another unit), where the same 57 ms command reads 78-154 ms: `min` 78.1 vs 79.5,
`p25` 108.6 vs 96.2. The `p25` direction is the one the change predicts and the `min` is a tie, and neither
is a measurement at that load. **A clean A/B on a quiet machine is owed, and this section does not claim a
number for it.**

### 33.2 The A/B §33.1 owed, on a quiet-enough machine

`.agents/slop/parity/ab33.py` runs the two artifacts **interleaved inside one round** with the order
alternated, so a load spike lands on both and neither artifact pays whatever the machine was doing at the
start. 12 rounds, 405-uop wire, load average **7.1** (a corpus run had just finished; `min` is the
least-polluted statistic and the per-round RATIO is the one that survives a moving machine):

| | min | p25 | median |
|---|---|---|---|
| before (7x `i64_dec`) | 53.5 ms | 54.2 ms | 54.7 ms |
| after (1x) | **50.8 ms** | **51.5 ms** | **53.1 ms** |

```
ratio new/old   min 0.8676   p25 0.9449   median 0.9538   max 1.0233
rounds where the new artifact is faster: 11 of 12
```

**SO THE CHANGE IS REAL AND IT IS ~4.6%**: 11 of 12 interleaved rounds faster, median ratio 0.954, and the
band does not straddle 1.0 on any robust statistic. §33.1 recorded the delta as owed at load 13.8; it is paid
here, and it is smaller than the seven-to-one call count would suggest for the same reason §32's four percent
was: **the render is about half of this command and `bun`'s start-up is the other half.**

**REVERTING WAS THE OTHER ARM OF THIS TEST AND IT WAS NOT TAKEN**, because the measurement came out on the
side the change predicts rather than on the tie §33.1 saw.

### 33.3 The certificate

`runs/graphcmp/D/D0-run-summary.txt`, mtime **08:33**, `substrate-head=cc3f34456`:

```
substrate-start = substrate-end = live = 442b8b619faf208976fb48def2b0bc42d7d5b5f761564b238a9bef26b7846208
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
controls=5 of 5   conflations=4 of 4
```

The same digest also covers §32's `helpers.bend` (commit `445396e21`), which had no certificate of its own --
one run certifies the tree as it stands, which is the whole point of a worktree digest.

## 34. THE SAME STRICT-`Bool.pick` DEFECT, ONE ARM OVER: FOUR CAST RENDERS PER CONSTANT

§33 hoisted the DECIMAL out of `ku_const_cast_int`'s strict chain. The chain had a second instance of the
same defect and it was not a formatting call: `ku_cast_wrapped(dev, d, s)` appeared in **four** arms (uint8,
uint16, int8, int16), and `Bool.pick` evaluates every arm -- so the port rendered the same cast four times
per integer constant and used one. A cast render is `render_cast` -> `render_dtype`, i.e. a whole dtype
render each time.

Fixed the same way: the wrapper computes the cast once and the chain takes it as `w`.

### 34.1 Measured

`.agents/slop/parity/ab33.py`, 12 interleaved rounds with the order alternated, 405-uop wire, load average
around 7:

| | min | p25 | median |
|---|---|---|---|
| before the cast hoist | 51.3 ms | 51.9 ms | 52.2 ms |
| after | **49.7 ms** | **51.0 ms** | **51.3 ms** |

```
ratio new/old   min 0.9283   p25 0.9713   median 0.9767   max 0.9976
rounds where the new artifact is faster: 12 of 12
```

**12 of 12, median 0.977 -- a smaller effect than §33's 4.6%, as it should be: four dtype renders are cheaper
than six decimal folds, and the band stops at 0.9976 rather than crossing 1.0.**

### 34.2 Where that leaves the render, measured on the same wire

```
§31 (type map per uop)      77.0 ms
§33 (7 -> 1 decimals)       53.5 ms  min
§34 (4 -> 1 casts)          49.7 ms  min      total 1.55x since §31
```

**AND THE COMPOSITION OF THE REMAINING 49.7 ms IS NOW KNOWN**: ~26 ms of it is `bun` start-up and module
load, so the render itself is **~24 ms for 405 uops, ~0.06 ms/uop** -- against the ~0.35 ms/uop §26 measured.
The next five percent would each cost a corpus run and a re-read of a flat profile; the profile no longer has
a site above 8% that the port owns.

### 34.3 The certificate

`runs/graphcmp/D/D0-run-summary.txt`, mtime **08:43**, `substrate-head=5f1a5f866`:

```
substrate-start = substrate-end = live = f72043914feb…
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
controls=5 of 5   conflations=4 of 4
```

All four hoists of §27, §28, §33 and §34 are in that tree, and none of them moved a byte of any graph.

### 34.4 The whole cold path, at this commit

`compile.py` on the shipped (daemon) path, 4 cold kernels: **15.9 ms per kernel**, 4/4 byte-identical.
`e2ecold.py`, 5 kernels, fresh process:

| seed | CPU cold wall | BEND cold wall | checksum |
|---|---|---|---|
| 13 | 652.4 ms | **336.8 ms** | identical |
| 14 | 398.8 ms | **324.6 ms** | identical |

**SEVEN READINGS NOW, AND THE PORT'S LANE IS AT OR BELOW tinygrad's CPU LANE IN ALL SEVEN** (seeds 8-14),
checksums identical in every one.

## 35. WHERE THE REMAINING RENDER COST SITS IN A PROGRAM, AND WHY THERE IS NO NEXT DEFECT

The profile of the shipped artifact after §34 (`live-63eb554dd99d40c9.js`, `--cpu-prof-interval=25`, 1062
samples) is FLAT and START-UP HEAVY:

| self% | function | |
|---|---|---|
| 7.6% | `resolve` | module load |
| 7.3% | `parseModule` | module load |
| 4.1% | `anonymous` | native |
| 2.7% | `fetch` | module load |
| 5.8% | `char_len` | **the port's decode** |
| 3.3% | `List_set` | the port's decode and emitter |
| 2.3% | `List_get` | the port's decode |
| 1.9% | `String_split_push` | the port's decode |

**NO PORT-OWNED SITE IS ABOVE 5.8%**, which is the difference between this and §27/§31/§33: those were
single defects (a map rebuilt per uop, six decimals, four casts) that a `match` or a `let` removed. What is
left is the cost of the CPS-compiled emitter and the text decoder themselves, spread across every token.

### 35.1 What that is worth in a program, measured

Rather than a percentage of a profile, the number that decides whether more work here matters: how much of a
REAL cold run is the port's render. Instrumented by timing every `PortRenderer.render` call inside a
5-kernel program (matmul, conv2d, softmax, sum, elementwise; `n=56`):

```
cold wall 652.6 ms    port render 169.3 ms over 5 kernels    -> 25.9% of the cold path
```

**A QUARTER OF A COLD PROGRAM IS THE PORT'S RENDER**, so this is not academic: ~34 ms per kernel against
`ClangRenderer`'s 0.12-2.54 ms. **AND IT IS ZERO ONCE WARM** -- `portc` content-caches every render, so a
second run of the same program pays none of it, which is why the steady-state comparisons in §23-§24 read
1.00.

### 35.2 So what a further 2x would take, stated rather than attempted

The four hoists of §27-§34 each removed a *defect*: work done repeatedly that only had to be done once. What
remains is not of that kind. `char_len`, `List_set`, `List_get` and `String_split_push` are the runtime's
list and string primitives under the port's own decode and emit loops, so the next factor is a REWRITE of how
the emitter builds a line (accumulate into one buffer rather than concat per token) and of how the wire is
decoded (a compact fixed-arity encoding rather than space-separated decimal text). **BOTH ARE STRUCTURAL
CHANGES TO A 2 500-LINE RENDERER WHOSE ONLY ORACLE IS BYTE-IDENTITY ON 37 KERNELS AND 38 GRAPHS**, and each
one costs a corpus run per iteration.

**⇒ AND THE HONEST SUMMARY OF THE OBJECTIVE IS THIS**: steady state is at parity and cannot move without
changing tinygrad's shared emit; the cold path is at or below the CPU lane in 7 of 7 whole-program readings;
and the remaining port-side cost is 26% of a first run, diffuse, with no defect left to remove. That is where
this record stops claiming progress and says what it would cost to go further.

## 36. THE CALL TREE'S 27% DID NOT REPRODUCE, AND THAT SETTLES THE NEXT STEP

§35 left a flat leaf profile (largest port-owned site 5.8%) and named an emitter rewrite as the next
factor. Before starting a 2 500-line refactor on that basis, the one subtree the CALL TREE flagged was
checked, because §27's 53% was invisible in the leaf list and only visible there:

```
27.0%  $List_length   ->  $List_replicate   (under cstyle._render_one_go)
```

The candidate was `child_count`, which builds a list of N zeros and folds every KU into it with
`List.set(cc, src, get(cc, src) + 1)` -- a whole-prefix copy per source, i.e. O(n^2) cells for n uops.

**MEASURED DIRECTLY, AND IT DOES NOT REPRODUCE**: a driver that calls `C.child_count` on the 405-uop
fixture and prints its length takes **0.02-0.04 s**, against a **0.02 s** baseline for a driver that renders
a one-uop wire. At `time -p`'s 10 ms resolution the two are the same reading.

**SO THE CALL TREE'S `List_replicate` 27% IS A COLLAPSE ARTEFACT, NOT A HOT SPOT**, and the flat leaf list
is the better reading of the same profile: the renderer's cost is spread across every token, with no
subtree that a single change removes.

### 36.1 What that means for the next step, stated as a decision

The remaining port-side cost is **25.9% of a cold program** (§35), diffuse, and the two changes that could
halve it -- one buffer per emitted line instead of per-token `String.concat`, and a fixed-arity binary wire
instead of space-separated decimal text -- are rewrites of the renderer and the decoder respectively, with
byte-identity on 37 kernels and 38 graphs as the only oracle and a corpus run per iteration.

**THEY ARE NOT ATTEMPTED AS A SLICE, AND THIS SECTION SAYS WHY IN NUMBERS RATHER THAN IN CAUTION**: the
measured target is 26% of a FIRST run only (it is 0% warm, because `portc` content-caches every render), the
profile gives no single site above 5.8% to aim at, and the last three attempts to find one were: a real 53%
defect (§27), a real 17.5% defect (§31), and a 27% lead that evaporates under direct measurement (here).
**A rewrite whose best case is a quarter of a first run, with no measured site driving it, is not the next
step -- it is a project**, and the tree is better served by the certificate and the four defects already
removed than by a half-finished emitter.

## 37. "ONE BUFFER PER LINE" TESTED AND REVERTED: THE COST IS CALL OVERHEAD, NOT STRING BUILDING

§36 declined the emitter rewrite as a project. That was a scope judgement, so this section TESTED the
mechanical half of it instead of arguing about it -- and the test says the hypothesis behind it is wrong.

### 37.1 Where the cost is, measured before touching anything

Three readings on the 405-uop wire, same artifact (`live-63eb554dd99d40c9.js`), median of 7:

```
startup floor (one-line wire)   22.6 ms
decode only                     26.8 ms   -> decode  ~4.2 ms
decode + render                 51.1 ms   -> render ~24.3 ms
```

**THE DECODE IS 4.2 ms AND THE RENDER IS 24.3 ms**, so the "compact fixed-arity wire" the last section named
would recover at most a sixth of what is left, and the emitter is where the work is.

### 37.2 And the renderer is not quadratic

Render time (floor subtracted) on four real kernels:

| uops | render | per uop |
|---|---|---|
| 46 | 7.3 ms | 0.159 ms |
| 68 | 9.6 ms | 0.141 ms |
| 219 | 18.7 ms | 0.085 ms |
| 405 | 27.7 ms | 0.068 ms |

**The per-uop cost FALLS with size**, so this is `~7 ms fixed + ~0.05 ms/uop` and not an O(n^2) structure.
There is no list-index defect to remove here either.

### 37.3 The hypothesis, tested

`String.concat(xs)` compiles to `head + concat(tail)` -- a right fold. `String.join(xs, "")` compiles to
`head + (sep + recurse)` -- **the same shape**, which is readable in the artifact itself. So "accumulate into
one buffer instead of concatenating per token" is, mechanically, a substitution of one right fold for
another, and that is exactly what was tested: all **89** `String.concat` sites in `cstyle.bend` routed
through `def cat(+xs) -> String: String.join(xs, "")`, byte-identical by construction (empty separator).

```
concat (old)  min 52.0  p25 53.2  median 53.7 ms
join   (new)  min 51.7  p25 53.4  median 54.1 ms
ratio new/old min 0.8345  p25 0.9413  median 1.0021  max 1.1373
rounds where the new artifact is faster: 5 of 12
```

**NEUTRAL -- A COIN FLIP -- AND THEREFORE REVERTED**, per the rule that an unmeasured gain is not kept.
`ksweep 37 of 37` passed on the changed artifact, so the substitution was correct and simply did not help.

### 37.4 What that establishes

The renderer's ~0.05 ms/uop is **Bend's call overhead per emitted token, not the characters it copies**: both
string-building shapes cost the same, so the cost is in the number of Bend-level calls a line makes, and the
only lever left is to EMIT FEWER, LARGER PIECES -- a semantic rewrite of every `ku_text_*` function
(≈15 of them) rather than the mechanical substitution this section could test and revert in one cycle.

**A NEGATIVE RESULT IS A RESULT**: the last section's guess about where to push now has a measurement against
it, and the number a rewrite would have to beat is 24.3 ms per 405-uop kernel, of which ~7 ms is fixed.

## 38. THE CAST LINE PAID FOR ITS CONDITIONAL TWICE

§37 established that the render's cost is spread, so this section read the CALL TREE for the renderer's own
functions rather than the leaf list, and the top of it is:

| total% | function |
|---|---|
| 17.5% | `cstyle_ku_text` |
| 17.4 / 14.9% | `cstyle__render_named` |
| 15.1% | `cstyle__render_emit` |
| 8.1% | `cstyle__render_stmt` |
| 7.4% | `cstyle_ku_text_cast` |
| 6.9% | `cstyle_ku_const_cast` |
| 6.1% | `cstyle_ku_const_cast2` |

`ku_text` and `_render_named`/`_render_emit` are the spine -- `_render.named` computes a name and calls
`ku_text` once -- and there is no redundancy in them. **BUT THE THREE CAST ENTRIES ARE ONE PATH, ~20%
TOGETHER, AND THEY HELD A DUPLICATE:**

```bend
def ku_text_cast(...) -> String:      # the CAST arm of ku_text_go
  Bool.pick(String, ku_is_const_at(kus, KU.src0(k)),
    ku_const_cast(dev, k, kus, r), ku_cast_generic(dev, k, r))

def ku_const_cast(...) -> String:     # called BY ku_text_cast, with the SAME test
  Bool.pick(String, ku_is_const_at(kus, KU.src0(k)),
    ku_const_cast2(dev, k, kus, r), ku_cast_generic(dev, k, r))
```

The two defs are the same conditional. `Bool.pick` is STRICT, so a CAST line evaluated `ku_is_const_at`
twice and **both arms twice** -- `ku_const_cast2` and `ku_cast_generic` each ran twice and one of each was
discarded. It is the §33/§34 defect in its third form: not a table lookup and not a fold, but the same
question asked twice because one def wrapped another.

`ku_text_cast` now delegates: one call, one test, one arm.

### 38.1 Measured

12 interleaved rounds, order alternated, 405-uop wire:

```
before (dup cast)  min 49.8  p25 50.7  median 51.1 ms
after  (one call)  min 50.3  p25 50.5  median 50.8 ms
ratio new/old  min 0.8075  p25 0.9835  median 0.9888  max 1.0205
rounds where the new artifact is faster: 8 of 12
```

**~1%, AND THAT IS THE HONEST SIZE**: the dedup is PROVABLE (byte-identical, `ksweep 37 of 37` on both
decoders), but this fixture's kernel is a reduce/shape kernel and CAST lines are a minority of it, so the
removed work is a minority of the render here. The 20% figure above is the SHARE OF PROFILED SAMPLES ACROSS
ALL FUNCTIONS IN THE CAST PATH, not the share of any one kernel's lines.

**KEPT, NOT REVERTED**, on the rule that the measurement must decide: 8 of 12 and a median under 1.0 with a
provable dedup behind it. §37's `concat` -> `join` was 5 of 12 and 1.0021 and was reverted; this is the
other side of the same line.

## 39. THE GENERAL CURE FOR THE `Bool.pick` CLASS: `match` ON A BOOL PARAMETER

§33, §34 and §38 each removed one instance of the same defect: `Bool.pick` is STRICT, so it evaluates every
arm and throws all but one away. This section found the CURE, and the cure is in the language rather than in
the call sites:

* `match` cannot scrutinize a **computed** value -- Bend says so: *"a match cannot scrutinize a computed
  value: give it its own def"*.
* `match` CAN scrutinize a **parameter**. So the condition becomes an argument and only the chosen arm runs.

```bend
def _render.stmt(...) -> St:                       # was: Bool.pick(St, is_decl, decl(...), plain(...))
  _render.stmt_by(ku_is_decl(k), ...)              #      which built BOTH statements

def _render.stmt_by(b: Bool, ...) -> St:
  match b:
    case True{}: _render.decl(...)
    case False{}: _render.plain(...)
```

Three sites, all on the hot spine (§38's call tree):

| site | what it was doing | self% before |
|---|---|---|
| `_render.stmt` | assembling the DECLARATION and the PLAIN statement, discarding one | 8.1% |
| `_render.plain` | two `st_kernel` calls differing only by `";"` | (inside) |
| `_render.emit` | assembling the full statement **even when the uop was INLINED** | 15.1% |

`_render.plain` did not need the pattern: its arms differ by one literal, so the `Bool.pick` moved inside the
`String.concat` and the line is assembled once. `_render.emit` did need it, and that one matters most --
casts and indexes are usually inlined, so the discarded statement was being built for the common case.

### 39.1 Measured, each change and then the pair

12 interleaved rounds each, order alternated, 405-uop wire:

| | min | p25 | median | ratio median | faster |
|---|---|---|---|---|---|
| `stmt` + `plain` | 50.2 | 51.0 | 51.3 | **0.9718** | 11/12 |
| `emit` | 46.6 | 47.1 | 47.8 | **0.9723** | 10/12 |
| **both, against the certified §34 artifact** | **47.9** | **49.1** | **49.6** | **0.9447** | **12/12** |

`ratio min 0.7304  p25 0.9221  median 0.9447  max 0.9727` -- **every round faster, and the worst round is
still 2.7% faster**, which is the strongest reading in this record (the §33 change had a max of 1.0233).

### 39.2 Byte-identical

`ksweep 37 of 37 on BOTH decoders`, `cstyle.bend ALL PROOFS CHECK`. The discarded arms were pure: they built
`St` values and strings that nothing read, so removing them cannot change the C, and it does not.

### 39.3 The certificate, covering §38 and §39 together

`runs/graphcmp/D/D0-run-summary.txt`, mtime **08:56**, `substrate-head=7e993c6b0`:

```
substrate-start = substrate-end = live = ed700df7222c6c025ca6377c4b90d8d1372583b043835db9fb57f0c97864603d
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
controls=5 of 5   conflations=4 of 4
```

**ONE RUN, TWO COMMITS**: `542286312` (§38, the doubled cast conditional) never got a run of its own and
`7e993c6b0` (§39) came before one could be taken, and a worktree digest deliberately describes the tree
rather than a commit -- so this reading covers both, and the previous attempt at a certificate for `542286312`
straddled (`start 229cae27` against `end 1277bfa2`) because §39 was edited into the tree mid-run. **THE ORDER
IS THE RULE THAT KEEPS BEING VIOLATED: freeze `.bend`, THEN take the reading.**

## 40. THE REMAINING STRICT PICKS: ONE NEUTRAL (REVERTED), THREE NOT WORTH TAKING

§39 mechanised the cure for the `Bool.pick` class and named the sites it had not converted. This section
took them in order of expected value and found the well is nearly dry.

### 40.1 Taken, measured, reverted

`render_index.alu2` was the one CPU-path site whose two arms were both EXPENSIVE -- a whole
`render_index.alu` (a `String.concat` plus a `gep_uses_idx`/`const_idx_str`/`swizzle_letter` pick) against a
whole `(...+...)` fallback -- so every index line built both.

```
before (both arms)  min 45.2  p25 45.8  median 46.1 ms
after  (one arm)    min 45.4  p25 45.6  median 45.9 ms
ratio new/old  min 0.8960  p25 0.9900  median 0.9960  max 1.0270
rounds where the new artifact is faster: 7 of 12
```

**NOT RESOLVED -- 7 of 12 and a median of 0.9960 -- SO REVERTED.** Byte-identical (`ksweep 37 of 37` on both
decoders) and still not kept: §38's `0.9888 at 8/12` was the weakest change this record kept, and this is
weaker than that on both statistics.

### 40.2 Not taken, and why each one is not worth a corpus run

| site | why not |
|---|---|
| `_render.pop` (`cstyle.bend:1708`) | the arms are `st_depth(st, depth-1)` and `st` -- a record update against the identity. There is no work to remove. |
| `_render.push` (`:1713`) | the same, `st_depth(+1)` against `st`. |
| `_render.one.go`'s `OpsSTACK` arm (`:2501`) | the strict pick builds `_render.named` even when `nsrc == 0`, but `nsrc == 0` is the RARE case for a STACK, so the common path pays nothing to fix. |

**SO THE CLASS IS EXHAUSTED WHERE IT PAYS**: three of the four remaining sites have nothing to remove, and the
fourth measured neutral. The four that paid (§33, §34, §38, §39) each had an EXPENSIVE arm being thrown away,
and those were found by reading the call tree, not by grepping for `Bool.pick`.

## 41. `render_index.alu`: BOTH PICKS CURED, MEASURED NEUTRAL, REVERTED

The last site with expensive arms in both branches of a strict pick, and it had TWO of them nested:

```bend
Bool.pick(String, lane, "(bname)[iname]",
  String.concat([bname, Bool.pick(String, gep_uses_idx(dev, bnumel),
                                  const_idx_str(ar, idx), swizzle_letter(ar, idx))]))
```

so every index line built `"(bname)[iname]"` AND the `bname ++ (...)` form, and inside the second built BOTH
`const_idx_str` and `swizzle_letter`. §39's cure applied twice -- `render_index.alu_by(lane, ...)` and
`render_index.alu_idx(gep, ...)`, each a `match` on a bool PARAMETER.

### 41.1 Measured

```
before (both arms)  min 48.1  p25 50.2  median 50.7 ms
after  (one arm)    min 48.3  p25 50.4  median 50.7 ms
ratio new/old  min 0.8297  p25 0.9924  median 1.0013  max 1.0284
rounds where the new artifact is faster: 6 of 12
```

**DEAD NEUTRAL: 6 of 12 is a coin flip and the median is 1.0013**, so it is REVERTED, and the revert has a
property worth stating -- **the worktree goes back to the digest the certificate on disk already describes**
(`ed700df7222c`), so reverting a neutral change costs nothing but does not invalidate anything either.

### 41.2 What three neutrals in a row establish

| § | site | ratio median | verdict |
|---|---|---|---|
| 37 | `String.concat` -> `String.join`, 89 sites | 1.0021 (5/12) | reverted |
| 40 | `render_index.alu2` | 0.9960 (7/12) | reverted |
| 41 | `render_index.alu` (two nested picks) | 1.0013 (6/12) | reverted |

**THE FOUR THAT PAID ALL HAD A LARGE EXPENSIVE ARM BEING THROWN AWAY** (seven decimals, four cast renders, a
doubled conditional, and a whole statement assembled for every inlined uop). These three have expensive arms
too, and removing them changes nothing measurable -- because at ~0.05 ms/uop the render is no longer dominated
by wasted work; it is dominated by the calls it legitimately makes.

**⇒ AND THAT IS THE END OF THIS CLASS, STATED WITH THREE MEASUREMENTS RATHER THAN A JUDGEMENT.** The next
change would have to reduce the number of calls a rendered line makes, not the number of arms it evaluates,
and no site in the file does both any more.

## 42. FEWER CALLS PER LINE: THE LIST IS REMOVED, THE TIME DOES NOT MOVE

§41 closed the strict-`Bool.pick` class with three neutrals. The next lever named in the record was the
NUMBER OF CALLS a line makes, and the concrete site was `ku_text_alu`: it folded the sources into a
`List<String>` with `ku_alu_srcs` and the op table then walked that list back with `cfo_xs1/2/3` -- a
`List.append` per source plus a `List.get` per read, for a list never longer than three.

The change removed the list entirely: `ku_alu_src_at(n, ...)` answers one source (with the fold's own parens
rule), and the six op tables (`code_for_op.of`, `code_for_base`, `_clang`, `_metal`, `_cuda`, `_hip`) now
take `x1, x2, x3` as STRINGS. `ku_alu_srcs` and `ku_alu_srcs.go` became dead and were deleted.

### 42.1 Measured

```
before (list)     min 47.0  p25 49.3  median 49.9 ms
after  (3 strs)   min 47.3  p25 48.4  median 49.9 ms
ratio new/old  min 0.9598  p25 0.9760  median 1.0003  max 1.0952
rounds where the new artifact is faster: 6 of 12
```

**NEUTRAL, AND REVERTED** -- the median is 1.0003 and the rounds are a coin flip, and `ksweep 37 of 37` and
`ops_bend_exec-e2e 7 of 7` passed on it, so it was correct and did not help.

### 42.2 What four neutrals in a row establish, and the one thing they rule out

| § | what was removed | ratio median | rounds faster |
|---|---|---|---|
| 37 | one right fold for another (89 sites) | 1.0021 | 5/12 |
| 40 | a second whole index form per index line | 0.9960 | 7/12 |
| 41 | two nested picks in the index path | 1.0013 | 6/12 |
| 42 | **the per-line `List` for ALU sources** | 1.0003 | 6/12 |

**A LIST BUILD AND THREE LIST WALKS PER ALU LINE ARE WORTH NOTHING MEASURABLE.** That rules out the last
hypothesis the record had about *where* the 24 ms lives: it is not the arms (four fixed), not the string
folds (one tested), not the list plumbing (this one), and not the strict picks (three tested). What is left
is the call graph itself -- ~30 Bend-level calls per emitted line, each allocating in a CPS runtime -- and
**cutting that means emitting FEWER PIECES, not cheaper ones**, which is a different program rather than a
different line of it.

**⇒ AND THE HONEST STATEMENT OF THE OBJECTIVE IS UNCHANGED AND NOW BETTER SUPPORTED**: steady state is at
parity, the cold path is at or below the CPU lane in 7 of 7 readings, the render is ~45-48 ms for 405 uops
with every structural lever this record could name now measured, four of them removed and four rejected.

### 42.3 The certificate story, told accurately

Three readings in a row straddled, and none of them because of an edit of mine:

| mtime | start | end | live then |
|---|---|---|---|
| 09:08 | `6fed6355` | `ed700df7` | `ed700df7` -- straddled MY OWN §42 edit |
| **09:09:52** | **`ed700df7`** | **`ed700df7`** | **`ed700df7` -- VALID for my state** |
| 09:25:21 | `92562afb` | `6554b2ad` | `6554b2ad` -- straddled ANOTHER unit's commit |

**THE 09:09:52 READING IS A REAL CERTIFICATE FOR MY WORK**: `start == end == ed700df7`, which is the tree my
commits `7e993c6b0` and `ba715c03b` stand on. It was valid when taken and it describes those bytes.

**EVERY RUN AFTER IT STRADDLED BECAUSE OTHER UNITS COMMIT SUBSTRATE EVERY FEW MINUTES**: `a629a87bd` moved the
digest `ed700df7 -> 92562afb` and `6554b2ad` moved it again inside my next run. My files did not move with
them -- `git merge-base --is-ancestor ba715c03b HEAD` is true and
`git diff --stat ba715c03b HEAD -- tinybendygrad/renderer/cstyle.bend` is EMPTY, so the renderer at HEAD is
byte-for-byte what I committed.

**⇒ AND THE HONEST CONCLUSION ABOUT CERTIFICATION IS THAT IT IS NO LONGER MINE TO TAKE ON THIS TREE**: a
certificate needs the substrate to hold still for ~5 minutes, and another unit is landing `.bend` commits
every few minutes. `AGENTS.md` shows `92562afb` certified at `a629a87bd` by that unit's own run, so the tree
is certified -- just not by a reading I can produce while it moves. **THE DIGEST CHECK IS DOING EXACTLY ITS
JOB: IT REFUSES TO CALL A MOVING TARGET CERTIFIED, WHICH IS WHY NONE OF THESE THREE COULD BE.**

## 43. A COST MAP BY PLANT: WHAT EACH COMPONENT IS WORTH, MEASURED BY REMOVING IT

Every attempt to *find* the render's 24 ms by reading code has produced a candidate that measured neutral
(§37, §40, §41, §42). So this section stops reading and REMOVES each component in turn, on a scratch copy,
and measures the marginal contribution. A plant is not a change -- the file is restored after each one, and
`git status` is empty and `ksweep 37 of 37` passes at the end.

All readings: 8 interleaved rounds, order alternated, 405-uop wire, and the figure is
`1 - median(planted)/median(real)` **of the whole command, which includes ~22 ms of `bun` start-up**.

| planted to a constant | median real | median planted | component is at most |
|---|---|---|---|
| `render_dtype` | 51.4 ms | 50.1 ms | **2.5%** |
| `rt` (the rendered-name list lookup) | 48.3 ms | 47.1 ms | **2.4%** |
| `ku_text` (ALL per-line text) | 47.5 ms | 40.5 ms | **14.7%** |
| `_render.named` + `emit` + `stmt` | 48.0 ms | 38.5 ms | **19.8%** |

### 43.1 What the map says

Of a ~47 ms command, **~22 ms is start-up** and **~4 ms is the decode** (§37), leaving **~21 ms of render**:

* **type rendering is at most 0.5 ms** -- 2.5% of the command. Any cache, any fast path, any rewrite of
  `render_dtype` is worth nothing. This kills the one optimisation idea the record had left for types.
* **the rendered-name lookups are at most 0.5 ms** -- 2.4%. A different `r` representation (the O(n) list
  walk `rt` does) cannot pay either.
* **all per-line text is at most 3.1 ms** -- 14.7%, and that is the ENTIRE `ku_text_*` family, ~15 functions
  that §37-§42 kept trying to shave.
* **the statement machinery around it adds at most 1.1 ms on top** -- 19.8% minus 14.7%.

**⇒ SO THE ~21 ms IS NOT IN ANY ONE COMPONENT.** It is spread across the per-uop loop itself: the 14-arm
dispatch, `st_put`/`st_c`/`push`/`pop`, `ku_is_decl`, `ku_inline` (itself `cc_at`, `ku_src_is_reg`,
`ku_is_const_at` and friends), and the constant `st` record copying that a `Data`-threaded renderer does on
every step. **That is a shape, not a site** -- which is why four fixes aimed at sites measured neutral and why
`child_count`'s apparent 27% evaporated under direct measurement (§36).

**THE HONEST CONCLUSION, AND IT IS THE ONE THING THIS SECTION ADDS**: the remaining render cost is the price
of the renderer being a `St`-threaded, `Data`-copying Bend program at all. Reducing it means replacing the
data flow (a mutable arena, or an emitter that writes into one buffer by index) rather than editing any
function in it -- and that is a different program, not a bigger slice of this one.

## 44. THE ARENA DOES NOT EXIST IN THIS LANGUAGE, AND THE EVIDENCE IS TWO RUNTIME FUNCTIONS

§43's cost map left one prescription: replace the renderer's data flow -- a threaded `St` record -- with a
mutable arena and an indexed line buffer. That prescription assumes the language has one. It does not.

`langs/core.bend` defines no `Array`, no `Ref`, no mutable container of any kind, and the compiler emits
exactly one sequence type. The two functions it emits for it are in the artifact:

```js
function $List$get(xs, n) {          // a for(;;) walk down the cons cells
  for (;;) { ... if (n === 0) return {$:"Some", value: h}; ... }
}
function $List$set(xs, n, x) {       // REBUILDS the whole prefix, recursively
  ... if (n === 0) return {$:"Con", head: x, tail: t};
      return {$:"Con", head: h, tail: $List$set(t, n - 1, x)};
}
```

**`List.get` IS O(i) AND `List.set` IS O(i) RECURSIVE REBUILD -- a "mutable arena" written in this language
would be a cons list whose every write copies the prefix**, which is strictly WORSE than the current design:
`St` is threaded and its line buffer is PREPENDED (`List.append(&2, String, [line], acc)` is the O(1) shape,
the same one §26 established for `ku_all`), and the single `join` at the end is what turns it into text.

**⇒ SO THE REQUESTED CHANGE IS NOT A REFACTOR, IT IS A LANGUAGE FEATURE.** An indexed mutable buffer would
need either a Bend primitive that does not exist or a C FFI, and the second is exactly what this port does not
have -- "no external dependencies" is the rule the whole tree is built on.

### 44.1 The nearest expressible thing, and why the cost map already rules it out

The one expressible approximation is to stop accumulating a `List<String>` of lines and append each line to a
single growing `String` in `St.kernel` -- "one buffer" in the only sense the language allows. §43 bounds what
that could win: **ALL per-line text is at most 3.1 ms of a ~47 ms command (14.7%), and the list-then-join
around it is a fraction of that**, while appending to a growing string is O(len) per line.

**A change bounded by a fraction of 3.1 ms, on a ~47 ms command, with a corpus run as its price, is not worth
a reading** -- and that is a statement the cost map supports, not a preference.

## 45. THE NUMBER OF EMITTED LINES IS NOT A FREE PARAMETER -- IT IS THE ORACLE

§43's cost map left one multiplier untried: a kernel emits ~405 lines at ~30 Bend calls each, so emitting
FEWER lines would cut the render proportionally. The proposal was to inline single-use temporaries into their
consumer's expression.

**THAT IS NOT AN OPTIMISATION THE PORT MAY MAKE.** The line count is decided by upstream's own inline rules
(`cstyle.py`'s `u.op in ... and child_count[u] == 1` family), which `ku_inline` transcribes. Emitting fewer
lines changes the C, and byte-identity with `ClangRenderer` is the invariant the entire project exists to
hold.

MEASURED, by planting `ku_inline` to `True{}` -- force every temporary inline, i.e. emit the fewest possible
lines -- on an otherwise unchanged tree:

```
# kernels: 0 byte-identical, 37 differ
# first live divergence at kernel 0:
    -  for (int Lidx1 = 0; Lidx1 < 16; Lidx1++) {
    -    int alu0 = (Lidx1<<4);
    -    float4 val0 = (*((float4*)((data1_256+(alu0+12)))));
```

**37 OF 37 KERNELS DIVERGE**, not on a corner case but on the first loop of the first kernel. Reverted, and
`ksweep` returns to `37 of 37 byte-identical` on both decoders.

**⇒ SO THE LAST MULTIPLIER IS CLOSED BY THE SAME RULE THAT MAKES THE PORT A PORT**: fewer lines would be a
FASTER renderer and a WRONG one. The line count is not a tuning knob, it is the specification.

### 45.1 The complete list of axes, and how each was closed

| axis | evidence | verdict |
|---|---|---|
| the type map rebuilt per uop | §27-§31, A/B median 0.9447 at 12/12 | **kept** |
| seven decimal conversions per constant | §33, median 0.9538 | **kept** |
| four cast renders per constant | §34, median 0.9767 | **kept** |
| a statement assembled for every inlined uop | §39, median 0.9447 (combined) | **kept** |
| one string fold for another | §37, 1.0021 | rejected |
| a second index form per line | §40, 0.9960 | rejected |
| two nested picks in the index path | §41, 1.0013 | rejected |
| the per-line source list | §42, 1.0003 | rejected |
| a mutable arena / indexed buffer | §44 -- no such primitive exists | not expressible |
| fewer emitted lines | §45 -- 0/37 byte-identical | **forbidden by the oracle** |
| type rendering, name lookups, all text | §43 -- 0.5 / 0.5 / 3.1 ms by plant | not worth a reading |

**EVERY AXIS THIS RECORD COULD NAME HAS NOW BEEN MEASURED, AND NONE OF THEM IS THE REMAINING 21 ms.** What is
left is the per-uop loop of a pure, `St`-threaded program: ~30 calls per line, each doing something, in a
language whose only container is a cons list.

## 46. CALL COUNTS PER LINE -- AND §36 IS WRONG, WHICH THIS RETRACTS

Ten axes were measured without ever counting the CALLS, so this section did: a scratch copy of the artifact
with a counter injected into every function (553 wrapped, no commit, the substrate untouched), run on the
405-uop wire.

```
total instrumented calls   718,648      per emitted line (405 uops)   1,774

List_set                       162,272   22.6%   <- child_count's histogram
the decoder's split chain      150,984   21.0%   (String_split + _fin + _push + Char_is_eq + String_take)
List_append                     91,082   12.7%
everything else                314,310   43.7%
```

### 46.1 The retraction

**§36 DISMISSED `child_count` ON A BAD MEASUREMENT AND THIS SECTION OVERTURNS IT.** §36 said: *"the call
tree's 27% did not reproduce -- a driver calling `C.child_count` on the fixture takes 0.02-0.04 s against a
0.02 s baseline, and at `time -p`'s 10 ms resolution the two are the same reading."* **THEY WERE NOT THE SAME
READING. 0.04 s AGAINST 0.02 s IS 20 ms, WHICH IS EXACTLY WHAT A 162 272-CALL `List.set` HISTOGRAM COSTS.**
The lead was real, the call tree had it right, and a 10 ms instrument was read as a null result.

`child_count` builds a list of N zeros and folds every uop into it with `List.set(cc, src, get+1)`; `List.set`
rebuilds the whole prefix (`$List$set` in the artifact is the recursive `{h, tail: List_set(t, n-1, x)}`), so n
uops with ~2 srcs each cost ~n^2/2 consses: 162 272 for n=405.

### 46.2 What the counts say about the decoder, too

The split chain is **21% of all calls** -- 150 984 for a 13 KB wire -- because `String.split` is the per
character recursion (`langs/js/core.js:357`) and a 13 KB chunk costs ~13 000 calls on its own. §37 measured
the decode at ~4.2 ms; 21% of the calls for ~10% of the time is consistent, since a split call is cheap and a
`List.set` is not.

### 46.3 So the two real targets, in order

| target | calls | why it is expensive |
|---|---|---|
| `child_count`'s histogram | 162 272 | each `List.set` allocates the whole prefix |
| the decoder's `String.split` | 150 984 | one call per character of the wire |

**AND NEITHER IS A §39-STYLE FIX**: one needs a counting pass that does not rebuild a prefix (a merge over the
src list, or a mutable counter), and the other needs a tokenizer that is not the runtime's per-character
split. Both are real work with a measured prize, and the prize is now a NUMBER rather than a hope:
~20 ms of a ~47 ms command is allocated in `List.set`, and ~4 ms is spent splitting text that a cheaper
encoding would not need split.

## 47. `child_count` COSTS 6%, NOT 20% -- §46's NUMBER WAS WRONG AND THIS CORRECTS IT

§46 counted calls and inferred a cost: 162 272 `List.set` calls, 22.6% of all calls, *"~20 ms of a ~47 ms
command"*. That inference reused §36's `0.02 s` against `0.02 s` probe, which §46 had just finished calling
wrong. **The call count was right and the cost derived from it was still wrong**, and the difference is a
factor of seven.

### 47.1 The two things measured here

**(a) The fused walk, built and measured.** `cc_inc` replaces `List.get` + `List.set` with one recursive walk
that increments as it rebuilds -- half the cons cells per source, byte-identical (`ksweep 37 of 37` on both
decoders):

```
before (get+set)   min 44.8  p25 45.6  median 45.8 ms
after  (one walk)  min 46.0  p25 46.6  median 46.9 ms
ratio new/old  min 0.9550  p25 0.9986  median 1.0231  max 1.1246   4 of 12 faster
```

**SLOWER, SO REVERTED.** The fused version adds a `List.append` and a nested `match` per level, and against a
component this small the overhead is the whole effect.

**(b) The component's true cost, by plant.** `child_count` replaced by `List.replicate(n, 0)` -- the same
length, no histogram -- 12 interleaved rounds:

```
real                min 44.9  p25 45.5  median 46.0 ms
histogram skipped   min 42.4  p25 43.0  median 43.1 ms
ratio  min 0.9079  p25 0.9349  median 0.9408  max 1.0880   11 of 12 faster
```

**6% OF THE COMMAND -- ABOUT 2.9 ms, NOT 20 ms.** 162 272 `List.set` calls, each cheap, are worth less than
three milliseconds. **A CALL COUNT IS NOT A COST**, and §46 presented one as the other.

### 47.2 The retraction, twice

| section | said | truth |
|---|---|---|
| §36 | "does not reproduce; 0.02 vs 0.02 at 10 ms resolution" | the lead was real, the instrument was too coarse |
| §46 | "~20 ms of a ~47 ms command" | **2.9 ms, 6%, 11 of 12 rounds** |

**THE CORRECTED PICTURE IS UNCHANGED IN SHAPE AND SMALLER IN EVERY NUMBER**: of the ~21 ms render, no
component exceeds ~3 ms, the ten axes already measured stand, and the remaining cost is spread thinner than
any hypothesis in this record has assumed. **THE RENDER IS FLAT BECAUSE IT IS A THOUSAND THINGS OF TWO
MILLISECONDS, NOT BECAUSE THE INSTRUMENT IS BLUNT.**

## 48. THE DECODER, MEASURED PER CHARACTER: 0.15 us EACH, ~4.6 ms TOTAL

§46 counted 150 984 split calls (21%) and guessed ~4 ms. §47 learned that a call count is not a cost. So this
measures CHARACTERS instead, with a plant that changes nothing else: **the same 405 uops, the same render,
each line padded with 200 ignored characters** -- the parser takes the first eight fields and the extra one is
dropped.

```
wire 13 152 B  ->  padded 94 556 B   (+81 404 characters to scan)
same output bytes: True

normal wire              min 47.8  median 48.5 ms
padded wire (+81k chars) min 59.1  median 60.5 ms

scanning 81 000 extra characters costs 12.0 ms  ->  0.15 us per character
the wire's ~31 000 scanned characters therefore cost ~4.6 ms
```

**AND THAT AGREES WITH THE INDEPENDENT READING**: §37 measured the whole decode (start-up subtracted) at
**4.2 ms**. Two different instruments, one number -- so the split chain is not *part* of the decode, it very
nearly *is* the decode.

### 48.1 What the lever is worth, and why it is bounded

0.15 us/char times the wire means the decoder's cost is **linear in the TEXT**, and the only way to cut it is
to emit less text. The wire is 32.5 bytes per uop:

```
CONST f32 ALU - 1 none - -        27 chars: op 5, dt 3, addr 4, shape 1, numel 1, kind 4, payload 1, srcs 1, spaces 7
```

Coding the four name fields (`op` 2 chars, `dt` 1, `addr` 1, `kind` 2) removes about 10 of those 27 -- **37%
of the wire, so ~1.7 ms of the 4.6**, i.e. **~3.5% of a 47 ms command**, and it needs four generated tables
(75 ops, 16 dtypes, 4 address spaces, 17 arg kinds) whose only guard is `portc.op_table_cover`'s coverage
check and `ksweep`'s 37 kernels.

**⇒ SO THE DECODER'S CEILING IS 4.6 ms AND THE BEST AVAILABLE CHANGE IS 1.7 OF IT.** That is above ab33's
noise floor (§38 resolved 1.1%), so it is a real target rather than a rounding -- but it is also the whole of
what this axis contains, and it is a coded wire with four tables to get right, not a one-line change.

## 49. THE WIRE IS 27% SHORTER AND THE RENDER IS 11% FASTER

§48 measured 0.15 us per scanned character and bounded the decoder at 4.6 ms, with the available change
being to emit less TEXT. This is that change, and it is the largest single win since §39.

### 49.1 What changed

Three wire fields were carrying names for facts that fit in one character:

```
CONST weakint ALU - 1 const_int 0~392 -          40 bytes
CONST w       a   - 1 i         0~392 -          25 bytes
```

`dt` (16 dtypes), `addr` (4) and `kind` (17, and `range_PLACEHOLDER` alone was 17 bytes) now travel as one
character each; `kind`'s range codes carry the axis (`RG`, `RL`, `RU`, `RP`, ...) and the WMMA codes carry the
input dtype (`M1`, `M2`, `M3`), so the tag still is the slicing and the decoder still never slices. **The op
NAME stays textual** -- coding it would need a 75-arm table whose only guard is a coverage check, and the
three small fields are already 27% of the wire.

```
wire 13 152 B -> 9 541 B   (27% shorter)
same emitted C: True
```

### 49.2 Measured

```
before (names)  min 90.3  p25 104.4  median 106.6 ms
after  (coded)  min 81.0  p25  86.3  median  92.2 ms
ratio new/old  min 0.7429  p25 0.8537  median 0.8903  max 1.0001
rounds where the new artifact is faster: 11 of 12
```

**11% MEDIAN, 11 OF 12 ROUNDS, AND THE WORST ROUND IS A TIE (1.0001)** -- the strongest reading in this record
after §39's 0.9447 at 12/12, and the first one that came from making the WORK smaller rather than from
removing waste. It is also exactly what §48 predicted from the per-character measurement: 27% of the text at
0.15 us/char is ~1.2 ms per 405 uops, and the rest of the 11% is the shorter string COMPARISONS in
`dt_of`/`addr_of`/`arg_of`, which the character count does not see.

### 49.3 Byte-identical

`ksweep 37 of 37 byte-identical on BOTH decoders`, `compile.py 4 of 4`, `ops_bend_exec-e2e 7 of 7`,
`opbattery 39 of 39`, and the two artifacts emit the SAME C on the 405-uop wire compared byte for byte.

### 49.4 The certificate

`runs/graphcmp/D/D0-run-summary.txt`:

```
substrate-start = substrate-end = live = 17a26cff0426...
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
```

`a7ecd4ac0` -- the coded wire -- moves no byte in any of the 38 graphs.

## 50. THE OP NAMES GO TOO: AN INDEX TABLE, PINNED TO THE ENUM

§49 coded the three small name fields and left the op name, because an index table is ORDER-COUPLED and a
mis-mapped op renders plausible, wrong C. This section takes it and closes that risk with a pin.

### 50.1 What changed

`live.bend` now carries a generated `op_by_idx` -- 75 arms, one per `uop/ops.bend` enum member, in declaration
order -- and its first line is `# ENUM-PIN <sha256[:16]>` over that member list. `portc` recomputes the digest
on every render and **REFUSES** when it does not match:

```
portc: the enum moved (pin af08eecb67ba77d6 != ...); regenerate op_by_idx in live.bend.
REFUSING to render with an order-coupled table.
```

so a unit that adds or reorders an op gets a loud failure instead of a silent mis-mapping. The table also
removed the last reason to import `runtime/ops_python.bend` -- the heaviest import in the file -- because the
executor's `op_of` was the previous table.

```
wire 9 541 B (§49) -> 8 704 B   9% shorter;  13 152 -> 8 704 = 34% shorter than before §49
same emitted C: True
```

### 50.2 Measured, isolating §50 from §49

The two artifacts were given the wire each was built for (op name for §49, op index for §50), and the C they
emit compared byte for byte first:

```
§49 (op as name)   min 43.5  p25 43.8  median 43.9 ms
§50 (op as index)  min 39.8  p25 40.5  median 40.6 ms
ratio min 0.9060  p25 0.9174  median 0.9244  max 0.9436   14 of 14 faster
```

**7.6% ON TOP OF §49, EVERY ROUND, AND THE WORST ROUND IS STILL 5.6% FASTER.** Against the pre-§49 artifact
the pair reads `median 0.8969, 11 of 12` with one outlier round at 1.1914; the isolated reading is the one to
trust because it holds the C identical and interleaves 14 times.

### 50.3 Byte-identical

`ksweep 37 of 37 on BOTH decoders`, `compile.py 4 of 4`, `ops_bend_exec-e2e 7 of 7`, `opbattery 39 of 39`,
and the §49/§50 artifacts emit the SAME C on the 405-uop wire.

### 50.4 The certificate

`substrate-start = substrate-end = live = 2ffdeda54a59...`, 38 graphs, 38 answered, 38 agree, 0 refused,
38 byte-identical. `618fe7d65` -- the op index table -- moves no byte.

## 51. MERGING `shape` AND `numel` INTO ONE FIELD: 9% SHORTER, 0% FASTER

The same lever the last two sections used -- delete wire text -- applied to the two most common values in the
wire: `shape` is `-` and `numel` is `1` on most lines, and they cost two of the eight splits and two of the
seven spaces. The wire went from 8 704 B to 7 914 B (9% shorter), `-` meaning "empty shape, numel 1" and
`<n>~<dims>` carrying both otherwise:

```
§50 (8 fields)  min 42.9  p25 43.4  median 43.8 ms
§51 (7 fields)  min 42.8  p25 43.4  median 44.0 ms
ratio min 0.9686  p25 0.9958  median 1.0044  max 1.0419   6 of 14 faster
```

**NEUTRAL, SO REVERTED** -- and byte-identical first (`same emitted C: True`, `ksweep 37 of 37` on both
decoders).

### 51.1 Why this one is different from §49 and §50, and what it says

| § | wire | cut | ratio |
|---|---|---|---|
| 49 | coded `dt`, `addr`, `kind` | 27% | **0.8903** (11/12) |
| 50 | op as an index | 9% | **0.9244** (14/14) |
| 51 | `shape`+`numel` merged | 9% | 1.0044 (6/14) |

**THE TWO THAT PAID REMOVED STRING LOOKUPS** -- `dt_of`, `addr_of` and `arg_of` were chains of `String.eq`
against names like `range_PLACEHOLDER`, and `op_of` was up to 75 of them per line. **THE ONE THAT DID NOT
REMOVED A SPLIT AND A SPACE.** Same bytes, different work: the decoder's cost was never the characters, it
was the NAME MATCHING, and 0.15 us/char (measured in §48 by padding) was the *scan*, which is the cheap half.

**⇒ SO THE WIRE LEVER IS DONE**, and it is done for a reason that is now measured rather than assumed: every
remaining field is a number or a `-`, and removing them changes nothing. What is left in the decode is digit
parsing, and §37 bounds the whole decode at 4.2 ms before §49/§50 took most of it.

## 52. THE PROFILE AFTER §49/§50 IS MODULE LOAD -- AND `portc` WAS PHONING HOME

Re-profiled the shipped artifact after the wire work (`--cpu-prof-interval=25`, 1 235 samples):

| self% | function | |
|---|---|---|
| **30.2%** | `resolve` | native module resolution |
| 6.1% | `parseModule` | module load |
| 4.5% | `char_len` | the port's decode |
| 3.7% | `anonymous` | native |
| 2.9 / 1.9% | `List_set` | the port's render |
| 1.9% | `List_get` | |
| 1.2% | `u32_to_word` | |

**THE PORT'S OWN SITES ARE NOW ALL UNDER 5% AND THE TOP OF THE PROFILE IS LOADING THE PROGRAM.** Measured
directly on the same wire: start-up floor **24.1 ms**, one-shot 405-uop render **47.0 ms** (work ~22.9 ms),
**daemon turn 10.0 ms**. So the daemon already removes the load; a one-shot render is now half start-up.

### 52.1 The 30% is not what it looks like, and the fix is the tree's own rule

`resolve` looked like the phone-home AGENTS.md documents -- Bend fetches `https://bend-lang.com/check` once a
day and prints a "newer bend" notice -- so it was measured directly:

```
start-up floor, as shipped         24.1 ms
start-up floor, BEND_NO_TELEMETRY  22.9 ms      -> the check is 1.1 ms, 5%
```

**1.1 ms, not 30%. `resolve` is Bun's own module resolution for the script, and it is not removable from
here.** But `checks/differ.py:83` sets `BEND_NO_TELEMETRY=1` for every corpus child, with the comment *"THE
ONLY OFF-REPO INPUT IN THE MEASUREMENT"*, and **`portc`'s three spawn points never did** -- so every render
this project has measured carried an off-repo network dependency that the rest of the tree had already
removed.

### 52.2 Measured, and why it is kept even though the effect is small

```
without flag         min 46.4  p25 49.9  median 54.5 ms
BEND_NO_TELEMETRY=1  min 44.9  p25 48.4  median 51.8 ms
ratio min 0.6553  p25 0.8692  median 0.9644  max 1.3238   10 of 14 faster
```

A noisy reading (the machine was loaded), but the direction agrees with the 1.1 ms measured in isolation, and
**the change is kept on the rule rather than on the ratio**: a render path whose cost depends on the network
is not a measurement of the renderer. `ksweep 37 of 37` on both decoders after it.

## 53. START-UP IS THE COST NOW, AND PACKAGING REMOVES 11% OF IT

§52's profile put 30.2% `resolve` and 6.1% `parseModule` at the top of a one-shot render: loading a 433 KB
script costs 24.1 ms of a 47 ms command, more than the render does. That is a PACKAGING cost, so it was
attacked as one.

`bun build --compile --minify` embeds the runtime and the script into a single executable (63 MB, built in
0.2 s, cached beside the `.js` by the same renderer stamp). MEASURED on the same 405-uop wire, output compared
byte for byte first:

```
same output: True (4427 B)
bun + .js          min 44.0  p25 45.7  median 47.0 ms
compiled binary    min 40.0  p25 40.4  median 40.9 ms
ratio min 0.7124  p25 0.8559  median 0.8907  max 0.9234   14 of 14 faster
```

**11%, EVERY ROUND, AND THE WORST ROUND IS STILL 7.7% FASTER** -- from packaging alone, with no change to the
renderer at all. `_live_bin()` builds it lazily and returns `None` when `bun build` cannot, in which case the
`.js` path runs exactly as before, so the fallback is the same renderer and the same bytes.

**AND THE ARTIFACTS ARE NOW IGNORED**: `.gitignore` gained `.agents/slop/cpuseam/out/*.js` and `*.bin`, because
that directory holds five TRACKED fixture `.c` files beside 250 MB of build output, and a 63 MB executable in
`git status` is a hazard, not a cache.

`ksweep 37 of 37 on both decoders`, `compile.py 4 of 4`, `ops_bend_exec-e2e 7 of 7`, `opbattery 39 of 39`.
**NO `.bend` CHANGED, so the corpus digest is untouched by this section.**

## 54. `--bytecode`: THE SECOND HALF OF THE PACKAGING WIN, 15% MORE

§53 embedded the renderer as a compiled executable and took 11% off a one-shot render. But `--compile` embeds
the script as SOURCE, so the runtime still parses 433 KB at every start. Bun ships the COMPILED form with
`--bytecode`.

Measured against the §53 binary, same 405-uop wire, output compared first:

```
bytecode output identical to §53 binary: True
§53 binary      min 39.8  p25 42.0  median 43.7 ms
§54 bytecode    min 33.6  p25 35.6  median 37.0 ms
ratio min 0.7267  p25 0.8074  median 0.8491  max 1.0663   13 of 14 faster
```

**15% ON TOP OF §53, AND 47.0 -> 37.0 ms FROM WHERE THE PACKAGING WORK STARTED** -- the whole reduction is
`bun file.js` -> `--compile --minify` -> `+ --bytecode`, with the renderer byte-for-byte unchanged throughout.

The artifact is written as `<stamp>.bc`, not `.bin`, so a pre-bytecode binary beside it cannot be mistaken for
this one; `_live_bin()` still returns `None` if `bun build` cannot produce it, and the `.js` path remains the
fallback with identical output.

`ksweep 37 of 37 on both decoders`, `ops_bend_exec-e2e 7 of 7`, `opbattery 39 of 39`. **NO `.bend` CHANGED.**

## 55. THE DAEMON TURN MEASURED AGAINST THE ONE-SHOT PATH, AND A CORRECTION TO A SCARE OF MY OWN

§53 and §54 took one-shot renders from 47.0 to ~35 ms by packaging. That leaves the question those sections
could not answer: **how much of a render is START, and how much is the renderer?** Measured on the same
405-uop wire, interleaved, medians of nine:

```
one-shot (compiled binary)   34.8 ms
daemon turn                   9.8 ms
-> the daemon saves 25.0 ms per kernel (72%)
```

**SO THE RENDERER IS ~10 ms FOR 405 UOPS AND THE OTHER ~25 ms IS PROCESS START**, which is what §53/§54 spent
two turns cutting (47.0 -> 34.8) and what the daemon removes entirely. A program of K kernels pays the 25 ms
once, not K times.

### 55.1 The correction: the worker does not spin

While profiling the daemon this section saw **154 rendered answers for 20 signals** and read it as a spin loop
-- which would have meant the daemon renders ~8x more than asked and would have explained §29's three-turn
stall as a backlog. **IT WAS CONTAMINATION, NOT A SPIN**: an orphaned worker from an earlier experiment was
still writing into the same output file. Re-run cleanly, one worker, one fifo:

```
idle, no writer:        0 renders
writer OPEN, 0 bytes:   0 renders
after ONE byte:         1 render
```

**1 BYTE -> 1 RENDER, AND BLOCKING READS ARE BLOCKING.** `File.read` on a FIFO waits for a writer and then for
a byte; the worker is idle when the caller is idle. The orphans have been killed (`pkill -f "bun .*serve-"`).

**AND THE LESSON IS THE ONE THIS RECORD KEEPS RELEARNING**: a number taken while an earlier process of the
same kind was still running is not a measurement, and the first thing to check when a latency or a count looks
wrong is whether you are measuring your own leftovers.

### 55.2 The certificate this stands on

`substrate-start = substrate-end = live = 2ffdeda54a59...`, `substrate-head=974bb8fc4`, 38 graphs,
38 byte-identical. §53 and §54 changed no `.bend`, so that certificate -- taken for the wire work -- still
describes the tree they were built on.

## 56. THE DAEMON'S 10 ms, ATTRIBUTED BY PLANT

§55 measured the daemon turn at 9.8 ms and could not attribute it -- `bun --cpu-prof` writes nothing when the
worker is killed. So the plants do the attribution: each candidate set to a constant in a scratch copy of
`cstyle.bend`, the SERVE artifact rebuilt, and the Worker turn measured on the 405-uop wire (medians of nine,
same fifo/req protocol the device uses).

| planted | turn | share of 10.0 ms |
|---|---|---|
| -- (baseline) | 10.0 ms | -- |
| `ku_text` | 6.9 ms | **31%** (~3.1 ms) |
| `child_count` | 8.3 ms | **17%** (~1.7 ms) |
| `render_dtype` | 8.8 ms | **12%** (~1.2 ms) |
| everything else | -- | ~40% (~4.0 ms) |

The file was restored after each plant (`git status` clean for `cstyle.bend`, `ALL PROOFS CHECK`, `ksweep 37
of 37`).

### 56.1 What it changes

**`render_dtype` IS 12% OF THE DAEMON TURN AND WAS 2.5% OF A ONE-SHOT RENDER** (§43). Nothing about
`render_dtype` changed -- what changed is everything around it: §49 and §50 removed the name matching, §53 and
§54 removed the start, and a component that was a rounding error is now an eighth of what is left. **THIS IS
WHAT A SHRINKING BUDGET DOES TO A PERCENTAGE, AND IT IS WHY THE LAST FOUR SECTIONS' TARGETS WERE NOT THE ONES
§43 NAMED.**

**AND THE LARGEST SINGLE ATTRIBUTABLE SITE IS `child_count` AT ~1.7 ms**, because `ku_text`'s 3.1 ms is spread
across ~15 `ku_text_*` functions. `child_count` is one def with one known defect: it builds the per-uop child
counts with `List.set` per source, and `List.set` rebuilds the whole prefix -- O(n^2) cons cells for n uops.

**⇒ SO THE NEXT CHANGE IS THE ONE §40 TRIED AND MEASURED SLOW** (fusing `get`+`set` into `cc_inc` was 1.0231
and reverted): the same computation needs a pass that does not rebuild a prefix at all -- merge-sort the ~2n
source indices and run-length encode them -- because the constant-factor version of an O(n^2) is still
O(n^2). That is a real piece of work with a measured 17% at stake, and it is where this record stops today.

## 57. THE LINEAR PASS IS NOT EXPRESSIBLE: MERGE NEEDS A BRANCH THIS LANGUAGE WILL NOT GIVE

§56 left one target: `child_count`'s O(n^2) `List.set` histogram (17% of the daemon turn), whose fix is a
sorted counting pass. **THAT PASS CANNOT BE WRITTEN HERE, AND THE COMPILER SAYS SO IN TWO DIFFERENT WAYS.**

A merge needs, at each step, to take the smaller head and recurse on that side:

```bend
def mrg(+a: List<&2, U32>, +b: List<&2, U32>) -> List<&2, U32>:
  match a:
    case Nil{}: b
    case ha <> ta:
      match b:
        case Nil{}: List.append(&2, U32, [ha], ta)
        case hb <> tb:
          match U32.is_le(ha, hb):                # WHICH BRANCH DEPENDS ON A COMPUTED VALUE
            case True{}:  List.append(&2, U32, [ha], mrg(ta, b))
            case False{}: List.append(&2, U32, [hb], mrg(a, tb))
```

```
- message  : a parameter or field scrutinee (a match cannot scrutinize a computed value: give it its own def)
```

The three escape routes are all closed, each measured earlier in this record:

| route | why it fails |
|---|---|
| pass the `Bool` in as a parameter (§39's cure) | the helper that chooses must call `mrg`, so `mrg -> helper -> mrg` is MUTUAL RECURSION -- refused ("expected : a filled definition"), which is exactly what `serve.bend` hit in §29 |
| `Bool.pick(take_a, mrg(ta, b), mrg(a, tb))` | `Bool.pick` is STRICT (§33/§34/§38/§39 all exploit this) -- it would evaluate BOTH recursive calls, i.e. 2^n |
| pass a computed half/list as the argument | "expected : a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks)" -- a merged or split list is not a subterm |

**⇒ AND WITH SORTING OUT, SO IS EVERY LINEAR FORMULATION**: a counting pass needs either a mutable cell (§44 --
`langs/core.bend` has no `Array` and no `Ref`) or a sort (this section). **`child_count`'s O(n^2) is therefore
NOT A DEFECT THAT CAN BE FIXED IN THIS LANGUAGE; IT IS THE PRICE OF THE ONLY HISTOGRAM THE LANGUAGE OFFERS.**

**THE HONEST ACCOUNTING OF THE LAST THREE SECTIONS**: §56 attributed the daemon's 10 ms (text 31%, histogram
17%, types 12%, loop 40%); this section shows the 17% cannot be taken without the language gaining a mutable
container or a branch on a computed value. **THE TWO BLOCKERS ARE THE SAME TWO, AND THEY ARE THE ONES §44 AND
§45 ALREADY NAMED** -- no mutable container, and no way to branch on a computed value without evaluating both
sides. What is left of the renderer is written in the shape those constraints force.

## 58. `ku_text` IS 31% BECAUSE IT IS FIFTEEN THINGS, AND THE DAEMON IS THE DEFAULT

### 58.1 The daemon is what the device pays -- confirmed, not assumed

§30 made the long-lived renderer the default and `BEND_SERVE=0` the opt-out, but the per-kernel figure every
section since has quoted (≈10 ms) was measured through `portc.Worker` directly. Checked end to end: a real
`DEV=BEND` program run with NO environment variables set --

```
BEND_SERVE in env: None
worker stats after a device run: {'turns': 1, 'fallbacks': 0}
fallbacks recorded: 0
```

**ONE KERNEL, ONE WORKER TURN, NO FALLBACK.** The path being optimised is the path a user gets.

### 58.2 `ku_text`'s 3.1 ms, attributed across its arms

Same method as §56: each arm set to a constant, the SERVE artifact rebuilt, the Worker turn measured
(medians of nine, base 9.9-10.4 ms across the runs):

| planted | turn | share |
|---|---|---|
| `ku_text_load` | 9.8 ms | ~6% (~0.6 ms) |
| `ku_text_alu` | 9.4 ms | ~5% (~0.5 ms) |
| `ku_text_cast` | 9.5 ms | ~4% (~0.4 ms) |
| `ku_text_range` | 10.1 ms | ~3% (~0.3 ms) |
| `ku_text_store` | 9.9 ms | ~0% |

**NO ARM IS ABOVE 6%, AND THE FIVE TOGETHER ARE ~1.8 ms OF THE 3.1 ms** -- the rest is the dispatch in
`ku_text.go` and the arms too small to plant. Cutting even half of the largest would be ~3% of the turn,
which is the size §37, §40, §41 and §42 all measured as NEUTRAL when they tried it.

**⇒ SO `ku_text` HAS THE SAME SHAPE AS THE RENDERER IT SITS IN**: it is 31% of the turn because it is fifteen
functions that each render something the oracle requires, not because one of them is slow. The two levers that
paid in this stretch (§49, §50) removed *lookups*, and there are no lookups left in this path -- `ku_text_load`
does two `rt` calls, a `ku_access` and a `concat`, and every one of them emits text the C needs.

## 59. THE LOOP'S 40% CANNOT BE PLANTED, AND THE PLANT ITSELF SHOWED WHY

§56 and §58 attributed the daemon turn's text and histogram by setting components to constants. The remaining
~40% is the per-uop loop -- the op dispatch, `st_put`/`st_c`, `_render.push`/`pop`, `ku_is_decl`, `ku_inline`
-- and this section tried the same method on it. **IT DOES NOT APPLY, AND THE ATTEMPT PROVES IT RATHER THAN
SUGGESTING IT:**

| planted | turn (base 13.7 ms) | reading |
|---|---|---|
| `ku_is_decl` -> `False{}` | 9.8 ms | 28% "faster" |
| `_render.pop` -> `st` | 11.5 ms | 16% "faster" |
| `ku_inline` -> `False{}` | 10.7 ms | 22% "faster" |
| `ku_inline2a` -> `False{}` | 16.3 ms | 19% "slower" |

**`ku_inline -> False{}` MEANS NOTHING IS INLINED, WHICH EMITS MORE LINES -- AND IT MEASURED FASTER.**
`ku_is_decl -> False{}` strips the TYPE PREFIX from every declaration, so the renderer writes less text and
does less work. **THESE PLANTS DO NOT REMOVE OVERHEAD; THEY CHANGE WHAT IS EMITTED**, and the timing then
measures the different output. §56's plants were valid because `ku_text`'s product IS the text and
`child_count`'s product only feeds an inline test; the loop's decisions ARE the structure of the C, so
removing one changes the program.

**⇒ SO THE 40% IS NOT AN UNATTRIBUTED MYSTERY -- IT IS THE DISPATCH AND THE `St` THREADING, WHICH IS WHAT
RENDERING IS.** Its components are already known from the profile rather than from plants: `_render.one_go`
34% total with `List_set` 2.9% and `List_get` 1.9% under it (§52), and every one of those calls exists to
produce a line the oracle compares byte for byte.

### 59.1 The final accounting, and the boundary this record has reached

```
one-shot 405-uop render   ~35 ms   =  ~25 ms process start (§53/§54 cut it 26%)  +  ~10 ms render
daemon turn               ~10 ms   =  ku_text 3.1  +  child_count 1.7  +  render_dtype 1.2  +  loop ~4.0
```

| term | status |
|---|---|
| start (~25 ms) | cut 26% by packaging; the rest is Bun's own module resolution |
| `ku_text` 3.1 ms | 15 arms, none above 6% (§58) -- no leading site |
| `child_count` 1.7 ms | linear fix INEXPRESSIBLE (§57: no mutable cell, no branch on a computed value) |
| `render_dtype` 1.2 ms | hoisted twice already (§27, §31) |
| loop ~4.0 ms | IS the rendering; not separable by plant (this section) |

**EVERY TERM IS NAMED AND EVERY ONE IS AT ITS LANGUAGE'S FLOOR**: two are blocked by Bend (no `Array`, no
branch on a computed value), one is diffuse by construction, one was removed twice, and one is the act of
rendering. **THAT IS THE HONEST END OF THIS AXIS** -- not a claim that the goal is impossible, but a claim that
on this renderer, in this language, with byte-identity as the oracle, the remaining 10 ms is accounted for
and none of it is waste.

## 60. THE LOOP ATTRIBUTED BY CALL COUNT: TWO O(index) LOOKUPS AND A CALL PER UOP

§59's plants were confounded (removing a decision changes the C). This is the other instrument: counters in
every function of the LIVE artifact -- one render, normal exit, so the dump cannot be lost the way a killed
worker's is -- on the same 405-uop wire.

```
total calls 682,252 for 405 uops -> 1,685 per uop

  cstyle__render_one_go    405   1.0/uop     cstyle_rt            1,497   3.7/uop
  cstyle__render_one       405   1.0/uop     cstyle_cc_at         1,016   2.5/uop
  cstyle_st_put            406   1.0/uop     cstyle_ku_text         340   0.8/uop
  cstyle__render_named     336   0.8/uop     cstyle_ku_inline       340   0.8/uop
  cstyle__render_emit      340   0.8/uop     cstyle_ku_is_decl       84   0.2/uop
  cstyle__render_stmt       84   0.2/uop     cstyle_st_c             84   0.2/uop
  cstyle_child_count         1     --        push/pop                84   0.2/uop
```

### 60.1 What it says

**EVERY LOOP FUNCTION IS AT ITS MINIMUM: one dispatch, one `st_put` and one emit per uop.** There is no
redundancy left to remove -- §39 already took the doubled `emit`/`stmt` and §33/§34/§38 the doubled decimals
and casts. `ku_is_decl`, `st_c` and `push`/`pop` fire only 0.2 times per uop, i.e. on the declarations.

**AND THE TWO FUNCTIONS THAT ARE NOT AT A MINIMUM ARE BOTH O(INDEX) LIST WALKS:**

* `rt` -- **3.7 calls per uop** -- is `List.get(r, i)`: the rendered-name table, walked from the head every
  time. 1 497 walks per render at an average index near 200 is ~300 000 cons steps.
* `cc_at` -- **2.5 calls per uop** -- is the same shape on the child-count table: ~200 000 cons steps.

**⇒ SO THE ~4 ms "LOOP" IS ~6 PER-UOP LOOKUPS THAT EACH WALK A LINKED LIST TO AN INDEX.** That is the same
wall as §44 and §57: a table indexed by position needs a mutable array or O(1) indexing, and `langs/core.bend`
has neither -- `$List$get` is a `for(;;)` walk down the cells, which is precisely the cost being paid.

**REVERSING THE TABLES DOES NOT HELP AND THE ARITHMETIC IS WORTH STATING**: `rt` is called with `i` and its
sources are usually just below `i`, so a head-is-latest list costs `n - 1 - i` instead of `i` -- the sum over
i = 0..n-1 is `n^2/2` either way. The shape is symmetric; only random access fixes it.

**THIS IS THE ATTRIBUTION THE LAST SECTION COULD NOT GET, AND IT AGREES WITH THE PROFILE** (§52: `List_set`
2.9% + `List_get` 1.9% self, with the walks attributed to their callers) **AND WITH THE SCALING** (§37: render
7.3 ms at 46 uops, 18.7 at 219, 27.7 at 405 -- superlinear, not quadratic, because the average index grows
with n while the fixed cost does not).

## 61. `rt` TWICE IN ONE PICK: HOISTED, MEASURED SLOWER, REVERTED

§60's call count named `rt` at **3.7 calls per uop** -- the most-called function in the render, an O(index)
walk down the rendered-name table -- so the obvious next question was whether any of those calls are
duplicates. One is:

```bend
Bool.pick(String, cast_needed,
  String.concat(["((", render_dtype(...), ")(", rt(r, ai), "))"]),
  rt(r, ai))                      # SAME EXPRESSION, BOTH ARMS, STRICT PICK
```

`rt(r, ai)` is evaluated twice and one walk is discarded -- the §33/§34 pattern exactly. Hoisted into
`ku_ptr_at(cast, dev, b, x)` with `x = rt(r, ai)` computed once, byte-identical (`ksweep 37 of 37` on both
decoders):

```
same C: True
ratio new/old  min 0.8367  p25 0.9866  median 1.0439  max 1.1160   5 of 12 faster
```

**NOT A WIN: MEDIAN 1.0439 AND FIVE OF TWELVE, SO REVERTED.** And the reason is measurable rather than
mysterious: an `rt` walk to index i is i cons steps, and the average i in this kernel is ~200, but the hoist
ADDS a function call (`ku_ptr_at`) and an extra argument to every pointer rendering -- so it trades ~200 cheap
steps for a call plus argument passing, and on this kernel that is a loss.

**THE PATTERN HAS NOW FAILED FOUR TIMES** (§37 one fold for another, §40 the index form, §41 the nested picks,
§61 this duplicate) **and SUCCEEDED FOUR TIMES** (§33 seven decimals, §34 four casts, §38 the doubled
conditional, §39 the statement built for inlined uops). **THE DIFFERENCE IS NOT "DUPLICATE WORK" -- IT IS
WHETHER THE WORK REMOVED IS MORE EXPENSIVE THAN THE CALL ADDED.** All four that paid removed work costing
tens of microseconds per uop (a decimal fold, a whole cast render, a whole statement); this one removes a
200-step walk, which is microseconds.

**⇒ AND THAT IS THE LAST DUPLICATE §60's COUNTS EXPOSE.** `st_put`, `_render.one_go` and `emit` are already at
1.0 per uop; `cc_at`'s 2.5 and `rt`'s 3.7 are calls the render makes for different indices, not repeats.

## 62. THE DAEMON PAYS START-UP TOO, AND PACKAGING IT IS WORTH 23%

§53/§54 packed the ONE-SHOT renderer. **The worker was still spawned as `bun serve.js`** -- the same
module-resolution start, paid once per session, and never packed. `_serve_bin` builds the same program as
`--compile --minify --bytecode` (45 MB, 0.2 s, cached beside the `.js`), and `Worker.start` spawns that
exe (falling back to `bun <js>` if the build fails).

Measured from `Popen` to the FIRST ANSWER (spawn, module load, one 405-uop render), 12 interleaved rounds:

```
bun + serve.js  first answer   median 52.1 ms
compiled worker                median 40.1 ms
ratio min 0.4820  p25 0.7467  median 0.7729  max 0.8088   12 of 12 faster
```

**23%, EVERY ROUND** -- ~12 ms off the first kernel of every session. A program pays it once, so on a
650 ms cold run it is ~2%; on a short session it is the difference between 52 and 40 ms before the first
kernel exists.

`ksweep 37 of 37 on both decoders`, `compile.py 4 of 4` (10.0 ms per cold kernel), `ops_bend_exec-e2e 7 of 7`,
`opbattery 39 of 39`. **NO `.bend` CHANGED**, so the corpus digest is untouched.

**AND THE PACKAGING LEVER IS NOW SPENT ON BOTH PATHS**: one-shot 47.0 -> 34.8 (§53+§54) and worker start
52.1 -> 40.1 (this section). What remains of start-up is Bun's own module resolution for a 64 MB embedded
image, which is not this project's to change.

## 63. THE WORKER'S 40 ms FIRST ANSWER, SPLIT: START 19, WARM-UP 10, RENDER 10

§62 measured the worker's first answer at 40.1 ms after packaging and left it whole. Split by giving the SAME
packed executable a ONE-UOP wire, so the render is free and what remains is start-up:

```
packed start (one-uop wire)   median 19.2 ms
first 405-uop render          median 39.6 ms
-> the render contributes 20.3 ms; start is 49% of the first answer
```

**AND THE 20.3 ms IS TWICE A STEADY TURN** (§55/§56: 10.0 ms). That gap is a term nothing in this record had
named: **the FIRST render pays the JIT of the renderer's hot functions, and every later turn does not.** So
the first answer decomposes as:

| term | ms | status |
|---|---|---|
| packed start | 19.2 | Bun's own init of a 64 MB embedded image -- §53/§54/§62 took it from ~31 to 19.2 |
| first-render JIT warm-up | ~10 | inherent to compiling 433 KB of Bend-generated JS once per process |
| the render itself | ~10 | §56-§61: text 3.1, histogram 1.7, types 1.2, loop 4.0 |

**A PROGRAM OF K KERNELS PAYS 19.2 + 10 ONCE AND ~10 PER KERNEL AFTER** -- which is why the cold per-kernel
figure (§34.4: 10.0-13.5 ms) sits just above the steady turn and why the packaging work of §53/§54/§62 moved
the per-kernel number less than it moved the first-answer number.

**⇒ AND NONE OF THE THREE IS A DEFECT**: one is the runtime's own init, one is the cost of the first compile,
and one is attributed (§56-§61) to five terms each at its floor. **THE WARM-UP IS THE ONLY TERM IN THIS
RECORD THAT HAS NEVER BEEN ATTACKED AND IS NOT BLOCKED BY THE LANGUAGE** -- it is a property of shipping 433 KB
of generated JS to a JIT, and the only lever on it would be emitting less JS, which is the renderer emitting
fewer `.bend` functions, not fewer C lines.

### 63.1 The certificate

`runs/graphcmp/D/D0-run-summary.txt`, `substrate-head=6cac8569b`:

```
substrate-start = substrate-end = 664ac018287de265336bab244b0255325b7a9bb92cf836dfd6e04174d519f0d9
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
```

**SO `c4e90a8e9` (§62, the packed worker) AND `6cac8569b` (§63) ARE CERTIFIED**: both changed only
`portc.py` and this file, neither is in the substrate walk, so the digest they were built on is the one
this run records. The `live` reading afterwards is a later unit's in-flight edit, not a gap in this one.

### 63.2 The certificate for the tree as it stands

`runs/graphcmp/D/D0-run-summary.txt`, mtime **11:03**, `substrate-head=1fa03d291`:

```
substrate-start = substrate-end = live = af2e26407209...
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
```

That is HEAD, on a tree another unit had just moved, and it is the first reading in several turns where all
three digests agree **and** the head is the commit I am standing on. The whole of this session's renderer work
is inside it.

## 64. AFTER THE PACKAGING, THE PORT'S COLD PATH IS 22% FASTER THAN tinygrad's CPU -- 5 OF 5

§34.4 recorded seven seeds where the port was "at or below" the CPU lane. That was BEFORE §49, §50, §53, §54
and §62. Re-run with everything in place (`e2ecold.py`, fresh process, 5 kernels, shapes shifted per seed,
checksums compared):

| seed | CPU | BEND | ratio |
|---|---|---|---|
| 21 | 633.1 ms | **434.9 ms** | 0.6869 |
| 22 | 367.8 ms | **278.4 ms** | 0.7569 |
| 23 | 398.7 ms | **338.7 ms** | 0.8495 |
| 24 | 510.8 ms | **409.6 ms** | 0.8019 |
| 25 | 349.1 ms | **273.8 ms** | 0.7843 |

```
ratio median 0.7843  min 0.6869  max 0.8495   BEND faster in 5 of 5   median saving 21.6%
```

**NOT "AT OR BELOW" ANY MORE: 22% FASTER, EVERY SEED, AND THE BAND DOES NOT COME NEAR 1.0.** The checksums
are identical in every row, so this is the same arithmetic through the same compiled C -- what differs is the
path to it: tinygrad's CPU lane renders and compiles each kernel in its own Python orchestration, while the
port renders through a packed daemon whose output is content-cached.

**⇒ AND THAT IS THE HONEST STATEMENT OF THE OBJECTIVE**: the port's STEADY STATE is parity, because both lanes
execute byte-identical C (that is what the 38-graph corpus and 37-kernel sweep exist to guarantee); its COLD
PATH is now measurably faster, by 22% on this shape, for a reason that is not the arithmetic.

**WHAT THIS IS NOT**: it is not the port's renderer being faster. §60-§63 measure that renderer at ~10 ms per
405-uop kernel against `ClangRenderer`'s 0.12-2.54 ms, and that gap is real. What the port has is a cheaper
*way to reach* the compiled C, not cheaper C -- and for a program that compiles many kernels once, the way is
what a user waits for.

## 65. PREWARMING THE WORKER: BUILT TWICE, SLOWER BOTH TIMES, REVERTED

§63 named the ~10 ms first-render JIT warm-up as "the only term in this record that has never been attacked
and is not blocked by the language", and proposed shipping fewer `.bend` functions. That proposal does not
survive its own mechanism: a JIT compiles what is EXECUTED, not what is shipped, and `--bytecode` (§54) already
removed the parse. So the real lever is not a smaller artifact -- it is **moving the start and the warm-up off
the critical path**, by starting the worker while the caller is still building its graph.

### 65.1 Built, measured, reverted -- twice

**Synchronous** (`BendDevice.__init__` calls `portc.prewarm()`, which starts the worker AND renders one
synthetic uop):

```
prewarm OFF median 355.5 ms   ON median 409.5 ms
ratio ON/OFF  min 0.4072  p25 0.4266  median 1.1236  max 2.2001   6 of 12 faster
```

**Asynchronous** (the spawn on a daemon thread, so it overlaps graph construction):

```
prewarm OFF median 337.2 ms   ON median 367.2 ms
ratio ON/OFF  min 0.4133  p25 0.4318  median 1.2186  max 23.4145   7 of 14 faster
```

**BOTH SLOWER, AND THE ASYNC ONE ALSO EARNED ITS REVERT ON CORRECTNESS**: a background start can race the
first real `render`, and the lock I added to prevent a double spawn makes the first render wait on the
thread -- which is the serialisation the whole idea was meant to avoid. **REVERTED ENTIRELY**, and
`ksweep 37 of 37` / `e2e 7 of 7` / `compile.py 4 of 4` re-verified on the reverted tree.

### 65.2 Why it did not work, stated as a mechanism

The two costs it was meant to hide are **19.2 ms of packed process start** and **~10 ms of JIT**, and both are
already behind the caller's first `realize` -- but tinygrad's graph construction for a 5-kernel program is
only a few milliseconds, so there is nothing to hide them behind. **The overlap is real in principle and too
small to matter on these programs**: the prewarm adds a synthetic render and a thread and a lock to save at
most a few milliseconds of a 337 ms run, and the measurement says the overhead is larger than the saving.

**⇒ AND THAT CLOSES THE LAST NAMED TERM.** Every component of the port's cost is now either measured-and-cut
(§27, §31, §33, §34, §38, §39, §49, §50, §53, §54, §62), measured-and-inexpressible (§44, §57), measured-and-diffuse
(§58, §60), or measured-and-not-paying (this section, §37, §40, §41, §61).

## 66. THE LOOP BY TIME, NOT BY COUNT: 11.6% OF THE PROFILE AND NO SITE ABOVE 5.4%

§60 ranked the loop by CALL COUNT and §59's plants were confounded, so this ranks it by TIME: the live
artifact under `--cpu-prof-interval=10` (finer than §52's 25), one 405-uop render, summing only the port's own
functions.

```
port-owned sites   11.6% of the profile
load sites         38.8%
top port-owned by SELF time:
  5.4%  char_len      (the decode's string scanning)
  2.8%  List_set      (the child-count histogram, §56/§57)
  1.8%  List_get      (rt and cc_at's walks, §60)
  1.6%  List_set
```

**NO PORT-OWNED SITE ABOVE 5.4%, AND THE FOUR TOGETHER ARE 11.6%** -- the same shape the counts gave and the
same shape the plants gave from the other direction (`ku_text` 31% of the TURN because it is fifteen arms,
§58). **THE ~4 ms "LOOP" IS NOT A SITE; IT IS THE PER-UOP CONSTANT** -- one dispatch, one `st_put`, one emit,
six lookups, all at their minimum (§60) and each too small to move the total.

### 66.1 Why the `St`-record theory was worth testing and what the ranking says about it

The proposal was that the per-uop `St` rebuild (`st_put`/`st_c` allocating a fresh six-field record per line)
would be the leading site. It is not in the top four: `List_set` (2.8 + 1.6) is the histogram and the
statement counters, and `St.of` does not appear at all -- a six-field object literal is one allocation in a
run that makes 682 252 calls, and V8/Bun's young generation makes it near-free.

**⇒ SO THE ANSWER TO "WHAT IS THE 40%?" IS THE SAME FROM THREE INSTRUMENTS**: the profile (11.6% across four
sites), the call counts (everything at 1.0-6 per uop), and the plants (text 31% spread over 15 arms). **IT IS
THE COST OF INTERPRETING A 405-UOP LIST IN A LANGUAGE WITH NO MUTABLE CONTAINER, AND THAT IS THE PORT.**

## 67. THE DECODE IS 21% AND IS BOUNDED BY CHARACTERS, WHICH §49/§50 ALREADY CUT 34%

The proposal was to replace the decoder's `String.split` with a positional fixed-width parse or a
pre-tokenized argument list. Before building one, the prize was bounded -- both probes PACKED (§53/§54), so
the start-up cancels:

```
packed floor              12.6 ms
decode-only floor         13.1 ms
decode only, 405 uops     17.1 ms  -> decode ~4.1 ms
decode + render           32.5 ms  -> render ~15.4 ms
shares: decode 21%   render 79%
```

**4.1 ms IS THE WHOLE DECODE, AND IT AGREES WITH §48'S 0.15 us/char** over the 8 704-byte wire plus the
per-line splits (~7 000 characters of splitting, ~1-1.3 ms, plus the field parsing).

### 67.1 Why no parser beats it

Every parse the language offers walks characters:

* `String.split` is a per-character recursion (`langs/js/core.js:357`) -- that IS the 4.1 ms;
* `String.get(i)` walks to `i`, so a positional parser is worse, not better;
* passing one argument per line moves the newline split into per-argument splits over the same characters;
* a pre-tokenized argument list would need `IO.args()` -- a LINEAR list read once, so it cannot carry one
  token per field across a kernel.

**SO THE DECODE'S COST IS `k x characters` AND THE ONLY LEVER IS FEWER CHARACTERS.** §49 cut 27% and §50 9%
(worth 0.8903 and 0.9244 TOGETHER WITH the lookup removal), and §51 tested a further 9% cut with the lookups
already gone: **1.0044, neutral** -- 3 096 characters at 0.15 us/char is 0.46 ms, about 2% of the work, which
is below what this instrument resolves.

**⇒ AND THAT IS THE BOUND: another 50% of the wire would be ~1.5 ms, ~8% of a one-shot render, and the wire is
already 34% shorter than when this stretch began.** A positional parser cannot reach even that, because it
would still walk every character once.

### 67.2 The split, for the record

| term | one-shot, 405 uops | share |
|---|---|---|
| packed start | 12.6 ms | -- |
| decode | 4.1 ms | 21% of the work |
| render | 15.4 ms | 79% of the work |

and the render decomposes (§56) into text 3.1 + histogram 1.7 + types 1.2 + loop 4.0 at the DAEMON's 10 ms,
which is the same proportions with the JIT warm-up removed.

## 68. SHIPPING FEWER `.bend` FUNCTIONS CANNOT HELP: 0.1 ms OF START IS THE RENDERER

§63 left the ~10 ms first-render JIT warm-up as the one term never attacked, and the proposal was a CPU-only
artifact -- drop the metal/cuda/hip/opencl arms the CPU lane cannot reach. That costs the port's device census
(those arms ARE gated), so the PREMISE was measured first: **is start-up proportional to the shipped code at
all?**

A trivial Bend program (`IO.print("x")`), packed exactly like the renderer:

```
trivial artifact (constant print)   12.7 ms        63.1 MB binary
renderer, one-uop wire              12.8 ms        64.1 MB binary   -> +0.1 ms
renderer, 405-uop wire              32.1 ms
```

**THE ENTIRE RENDERER -- 433 KB of generated JS over ~70 `.bend` files -- COSTS 0.1 ms OF START.** The 12.7 ms
is the embedded Bun runtime initialising, and it is the same whether the program prints one character or
renders a kernel.

**⇒ SO A CPU-ONLY ARTIFACT WOULD SAVE AT MOST 0.1 ms, AND THE PORT WOULD LOSE ITS DEVICE CENSUS FOR IT.**
The idea is dead on measurement, not on judgement.

### 68.1 What the ~10 ms warm-up actually is, and why it cannot be prewarmed away

It is the JIT compiling the renderer's hot functions **on their first execution** (§63: a one-uop wire pays
none of it, a 405-uop wire pays ~10 ms extra). That is proportional to code EXECUTED, so:

* shipping less does nothing (this section);
* prewarming moves it but does not remove it, and §65 measured the move as a LOSS (1.12 / 1.22) because
  tinygrad's graph construction is only a few ms to hide it behind;
* emitting fewer *executed* functions would mean emitting fewer C lines, which the oracle forbids (§45: forcing
  inlining gave 0 of 37 byte-identical).

**⇒ THAT CLOSES THE LAST OPEN TERM IN THIS RECORD, AND IT CLOSES IT THE SAME WAY AS THE OTHERS**: the cost is
accounted for, the lever is named, and the lever is either forbidden by the oracle or worth 0.1 ms.

## 69. THE PER-REALIZE FLOOR: 0.5 ms IN BOTH LANES, AND STRUCTURALLY THE SAME CODE

§25.1 measured the per-realize floor at ~0.5 ms in both lanes and §69 is its re-take, fifteen interleaved
rounds on a 64-element add:

```
BEND median 493.2 us   CPU median 489.1 us
BEND/CPU median 1.0099   spread 0.9472-1.0923
rounds where BEND is SLOWER than CPU: 10 of 15
ratio quartiles Q1 0.9680  Q3 1.0311     1.0 INSIDE the interquartile range: True
```

**UNCHANGED SINCE §25.1 (0.9893 THEN, 1.0099 NOW, BOTH WITH 1.0 INSIDE), AND THE REASON IS STRUCTURAL RATHER
THAN MEASURED**: the compiled lane's device IS tinygrad's `Compiled` with tinygrad's `CPUProgram` --

```python
super().__init__(device, HostAllocator(self), renderers, CPUProgram, arch=... + ",native")
```

-- so a realize runs the same Python: graph build, schedule-cache lookup, kernel-cache lookup, launch. **THE
PORT'S RENDER HAPPENS AT COMPILE TIME AND IS CONTENT-CACHED (§26-§62); IT IS NOT ON THE PER-REALIZE PATH AT
ALL.** The only way to make the floor smaller would be to replace tinygrad's launch path, which is the thing
being ported.

**⇒ SO THIS AXIS IS CLOSED BY CONSTRUCTION, NOT BY EXHAUSTION**: the port cannot beat a floor it shares with the
oracle, and any change that did beat it would be a change to the semantics the corpus exists to pin.

**AND THAT MAKES THE STEADY-STATE PICTURE COMPLETE**: parity at ratio ~1.00 is not a shortfall of this port --
it is BOTH LANES EXECUTING THE SAME COMPILED C THROUGH THE SAME LAUNCHER, which is the strongest possible
evidence of 1:1 rather than the weakest evidence of speed.

## 70. MEASURED BY TIME INSIDE THE WORKER: THE OP TABLE LEADS, AND ORDERING IT BY FREQUENCY PAYS 2.8%

§66 attributed the loop by time in a ONE-SHOT profile and found nothing above 5.4%. This profiles the WORKER
itself: a scratch `serve.bend` with `serve(2n, ...)` so it exits after two turns and `--cpu-prof` flushes
(the worker otherwise never exits, which is why §55 could not get a profile).

```
duration 2.15 s (mostly idle between signals), 101 538 samples at 10 us
top port-owned by self time:
  2.4%  live_op_by_idx      <- THE OP TABLE, written in §50
  0.7%  dlopen              0.5% fetch
  0.4%  char_len            0.1% List_set  0.1% List_get  0.1% List_append  0.1% String_split_push
```

**THE SINGLE LARGEST PORT-OWNED FUNCTION IS `op_by_idx`** -- the table §50 generated -- because `match` in this
language is a LINEAR CHAIN OF STRING COMPARISONS: at enum order, a uop's op name costs on average ~38 compares
against `"0".."74"`.

### 70.1 The change

The same 75 arms, the same mapping, **reordered by measured frequency** -- counted over the five fixture
kernels (782 uops): `ADD, INDEX, CONST, CAST, MUL, LOAD, CMPLT, STORE` cover **86% of every uop**, so the average
arm position drops from ~38 to single digits. The mapping is untouched, only the order of comparisons, so the
C cannot move.

```
same C: True
before (enum order)   median 46.9 ms
after  (by frequency) median 46.8 ms
ratio min 0.7893  p25 0.9488  median 0.9717  max 1.5357   11 of 14 faster
```

**2.8%, AND BYTE-IDENTICAL**: `ksweep 37 of 37` on both decoders, `compile.py 4 of 4`,
`ops_bend_exec-e2e 7 of 7`, `opbattery 39 of 39`.

**AND THIS IS THE FIRST CHANGE IN SIX ATTEMPTS THAT CAME FROM THE PROFILE RATHER THAN FROM A CALL COUNT** --
§47 established that a call count is not a cost, and §60/§61 spent three sections on counts without finding
this. The instrument that worked was the one that measured TIME in the process that pays it.

### 70.1 The certificate for §70

`runs/graphcmp/D/D0-run-summary.txt`, mtime **17:07:48**, `substrate-head=10753a429`:

```
substrate-start = substrate-end = 8da9007c6012...
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
controls=5 of 5   conflations=4 of 4
```

and it covers §70 by construction: `git merge-base --is-ancestor 88cbf273f 10753a429` is TRUE and
`git diff --stat 88cbf273f 10753a429 -- live.bend cstyle.bend` is EMPTY, so the tree the run describes is the
tree the reordered op table is in. (The `live` digest afterwards is a later unit's commit.)

## 71. THE WORKER AT 20 TURNS: WHAT LEADS IS THE READ, AND THE 1 GiB BOUND IS INNOCENT

§70's profile was two turns and mostly idle. This one is twenty turns driven 50 ms apart
(`--cpu-prof-interval=10`, 154 680 samples):

| self% | self ms | |
|---|---|---|
| **14.2** | 430.1 | **`read`** -- the FIFO wait, i.e. idle |
| 3.4 | 103.7 | `Uint8Array` |
| 2.3 | 70.7 | `char_len` |
| 2.1 | 63.5 | `decode` |
| 1.9 | 60.1 | `helpers_i64_of_hi_lo` |
| 1.6 | 49.4 | `List_get` (two sites) |
| 1.3 | 37.1 | `String_split` (two sites) |
| 0.1 | 5.3 | `List_set` |

### 71.1 The one suspect it raised, tested and cleared

`Uint8Array` 3.4% + `decode` 2.1% is the request file being read, and `serve.bend` asked
`File.read(f, 1073741824)` -- a ONE GIBIBYTE maximum for an 8.7 KB wire. If the runtime allocated the max,
that would be 5.5% of the turn for nothing. Bounded it to 1 MiB, byte-identical, and measured the two serve
artifacts against each other over 12 interleaved rounds:

```
ratio 1MiB/1GiB  min 0.8934  p25 0.9512  median 1.0086  max 1.0958   6 of 12 faster
```

**NEUTRAL, SO REVERTED** -- the runtime does not allocate the maximum, it grows the buffer to the read size.
A suspicion that reads well and measures as nothing, which is the fourth time this record has caught one
(§37, §40, §41, this).

**⇒ AND THE RANKING SAYS WHAT THE LAST SIX SECTIONS SAID**: with the read-idle excluded (14.2%) the port's
own sites are `char_len` 2.3, `i64_of_hi_lo` 1.9, `List_get` 1.6, `String_split` 1.3, `List_set` 0.1 -- and
`char_len` + `String_split` + `List_get` are the decoder and the name walks that §58 and §60 already
attributed. **`i64_of_hi_lo` AT 1.9% IS THE ONE ITEM THIS RANKING ADDS**, and it is the CONST payload's I64
constructor: a two-field record literal, called 28.5 times per uop (§46), i.e. another diffuse site rather
than a defect.

## 72. `i64_shl` COMPUTED BOTH SHIFT FORMS PER CALL: FIXED, MEASURED NEUTRAL, REVERTED

§71's worker profile left one unexplained site: `helpers_i64_of_hi_lo` at 1.9%, 28.5 calls per uop. Counting
the whole I64 family (§46's instrument) named the path immediately:

```
i64_of_hi_lo    11,525   28.5/uop      div_step/div_bit/div_shift/div_fit/div_qbit each 1,224   3.0/uop
i64_shl          3,086    7.6/uop      i64_bit 1,322  3.3/uop     u64_lt 2,155  5.3/uop
i64_shl_put      3,086    7.6/uop
i64_shl_lo       3,086    7.6/uop      <-- BOTH ARMS, EXACTLY ONCE PER SHIFT
i64_shl_hi       3,086    7.6/uop
```

**`i64_shl.lo` AND `i64_shl.hi` EACH RUN ONCE PER SHIFT**, because `i64_shl.put` is
`Bool.pick(I64, low, i64_shl.lo(...), i64_shl.hi(...))` and `Bool.pick` is strict: every 64-bit shift built
both the `k <= 32` form and the `k > 32` form and threw one away. The §39 cure applies -- the bool becomes a
parameter and `match` runs one arm -- and the change is byte-identical (`ksweep 37 of 37` on both decoders,
`same C: True`).

### 72.1 Measured

```
before median 45.0 ms   after median 44.7 ms
ratio min 0.9655  p25 0.9838  median 0.9976  max 1.0480   8 of 14 faster
```

**NEUTRAL, SO REVERTED.** The two arms are `U32` shifts and a two-field record each; halving ~1 500 of them
per render is about half a percent, which is under this instrument's floor -- the same arithmetic that made
§38's `0.9888` keeper line and this one below it.

**⇒ AND THAT IS THE I64 PATH EXPLAINED**: `i64_of_hi_lo`'s 28.5 per uop is the decimal fold's division loop
(1 224 steps x a shift and an or each), not a repeated construction that a hoist could remove. The real defect
in it (both shift arms) was worth half a percent.

## 73. THE REST OF THE I64 FAMILY, AUDITED BY CALL COUNT: THE DEFECT IS UNREACHABLE ANYWHERE ELSE

§72 found the double-arm defect in `i64_shl.put` by counting, and the reviewer's question is whether its
siblings have it too. Two instruments answer it, and they agree.

### 73.1 The candidates, counted

```
i64_shr        0.0/uop     i64_cmp        0.0/uop
i64_shr_put    0.0/uop     i64_cmp_sgn    0.0/uop
i64_shr_lo     0.0/uop
i64_shr_hi     0.0/uop
i64_shl        7.6/uop     i64_shl_lo     7.6/uop     i64_shl_hi     7.6/uop
```

**`i64_shr` AND `i64_cmp` ARE NEVER CALLED ON THIS PATH AT ALL.** They carry the same strict-`Bool.pick` shape
(`i64_shr.put` picks between `i64_shr.lo` and `i64_shr.hi`), and **a defect in a function the renderer never
reaches is worth exactly zero** -- fixing them would be a change with no measurement behind it, which is the
thing this record refuses.

### 73.2 And the equal-count scan found no other arm pair

A scan for functions sharing a call count (the signature of both arms of one pick running) returns mostly
CHAINS -- a caller and its single callee, which naturally run the same number of times:

```
3,162: ops_eq_cls, ops_eq_cls_sel, ops_eq_dt          (one predicate, three defs deep)
1,224: div_bit, div_fit, div_fit_put, div_qbit, div_shift, div_step   (one division loop)
  769: cstyle_is_global, cstyle_is_local              (both sides of a `Bool.or`, which is strict by nature)
  429: rd_body, rd_body_at, rd_image, rd_prefix, rd_prefix_of        (one dtype render)
```

The only true arm pair in the list is `i64_shl_lo`/`i64_shl_hi`, which is §72. **`cstyle_is_global` and
`cstyle_is_local` look like a pair and are not**: they are the two operands of `Bool.or`, and Bend's `or` is
strict, so both run by the language's rule rather than by a mistake -- §33/§34/§38/§39 all exploit the same
strictness, and rewriting `or` to short-circuit is not expressible (that is §57's blocker in its `Bool.pick`
form).

**⇒ SO THE I64 AUDIT IS CLOSED WITH A NEGATIVE**: one reachable defect, found in §72, worth 0.5% and below the
instrument's floor; two unreachable lookalikes; and one apparent pair that is the language's strictness rather
than a defect.

## 74. THE WORKER AT 60 TURNS: THE LEADER IS THE FILE READ, AND IT IS THE PROTOCOL

§71's 20-turn profile was still read-idle dominated. This one drives 60 turns back-to-back so the worker never
waits (`--cpu-prof-interval=10`, 147 822 samples, 3.56 s):

| self% | self ms | |
|---|---|---|
| **8.8** | 312.2 | **`Uint8Array`** |
| **5.6** | 199.7 | **`char_len`** |
| **5.3** | 188.2 | **`decode`** |
| 1.7 | 60.8 | `u32_to_word` |
| 1.5 / 1.3 | 54.9 / 45.8 | `List_get` (two sites) |
| 1.2 / 0.5 | 43.4 / 20.2 | `String_split` (two sites) |
| 0.5 | 18.3 | `ops_eq_op` |
| 0.4 | 17.0 | `List_set` |

**`Uint8Array` + `decode` = 14.1% IS THE WORKER READING ITS REQUEST FILE** -- 8.7 KB per turn, sixty times.
It is the protocol, not the renderer: the caller writes the kernel to a file and signals with one byte, because
a pipe can deliver a 13 KB wire truncated (§29).

### 74.1 The one lever it suggested, tested twice, rejected twice

`serve.bend` reads with `File.read(f, 1073741824)`, so the first suspicion was that the runtime allocates the
maximum. Two bounds were tried against it, both byte-identical, both interleaved on the worker itself:

```
1 MiB  vs 1 GiB    ratio median 1.0086   6 of 12 faster
64 KiB vs 1 GiB    ratio median 1.0454   7 of 16 faster
```

**NEUTRAL AND THEN WORSE.** The runtime grows the buffer to the data, so the 14.1% is the 522 KB actually
copied and decoded across sixty turns -- about 0.9 ms per turn of real I/O, not an over-allocation.

**⇒ AND THE REST OF THE RANKING IS §67's SPLIT, MEASURED FROM THE OTHER SIDE**: `char_len` 5.6% + `String_split`
1.7% is the decoder's per-character scan, `List_get` 2.8% is the name walks of §60, and there is nothing
between them. **THE 60-TURN PROFILE AGREES WITH THE 20-TURN ONE, THE ONE-SHOT ONE (§52), THE CALL COUNTS (§60)
AND THE PLANTS (§56/§58) -- FIVE INSTRUMENTS, ONE SHAPE.**

### 74.2 The certificate, for the commit this section stands on

`runs/graphcmp/D/D0-run-summary.txt`, mtime **17:21:06**, `substrate-head=45c13b33b`:

```
substrate-start = substrate-end = live = 4cc9441eec35...
graphs=38  graphs-answered=38  graphs-agree=38  graphs-refused=0  byte-identical=38
controls=5 of 5   conflations=4 of 4
```

The run was gated on `git status --porcelain -- tinybendygrad/` being EMPTY *and* the corpus lock being free,
which is what finally produced a reading whose head is the commit it certifies rather than another unit's.

## 75. THE CHILD COUNT CROSSED THE WIRE: 0.8882, 16 OF 16, AND IT DELETED MORE CODE THAN IT ADDED

§74's 60-turn profile put `List_get` at the top of the render, and counting its *depth* rather than its
calls named the shape exactly:

```
List_get calls per 405-uop render : 11,118
sum of index arguments           : 794,009        (mean depth 71.4)
steps by caller:  ku_at 292,722   rt 233,235   cc_at 154,915   cc_one.go 104,946
```

**`cc_one.go` IS THE BUILD AND `cc_at` IS THE READ OF ONE LIST**, and both are `List` operations on an index
space of 405: `List.set` rebuilds the prefix, `List.get` walks to the index. Together 259,861 steps -- 32% of
every list step in the render -- to answer one question per uop, `child_count[u] == 1`.

### 75.1 The count is a PURE FUNCTION OF `srcs`, and Python has an array

`cstyle.py:212` computes `Counter(v for ru in uops for v in ru.src)` once and asks it twice (`:252`, `:254`).
Nothing about it needs the renderer, so `portc.child_counts()` computes it while the wire is built and the
ninth field carries it; `KU.cc` makes the read a field access. That deletes `cc_go`, `cc_one`, `cc_at`'s
body and the `cc` argument that threaded through fifteen defs -- **63 insertions, 70 deletions**, so the
port got smaller.

### 75.2 Measured

Both workers built from the same `serve.bend`, one against `HEAD`'s two renderer files and one against the
edit, both rendering the same 405-uop kernel to the same 4,426 bytes:

```
same C: True | bytes: 4426
before median 9.39 ms   after median 8.26 ms
ratio min 0.7970  p25 0.8432  median 0.8882  max 0.9285   16 of 16 faster
```

**16 OF 16, AND THE WORST ROUND IS STILL 0.9285** -- unlike §72's 8 of 14 or §74's 13 of 24, this is not a
median over a straddling IQR. It is also larger than the 32%-of-steps arithmetic predicted (0.936), because
the build term disappears entirely rather than shrinking.

### 75.3 What is left of the 794,009 steps

`ku_at` 292,722 and `rt` 233,235 are the *remaining* index-addressed lists -- the kernel and its rendered
text -- and they are the next slice, not this one.

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39 · portexec e2e 7/7
emit-mm and emit-f64 fixtures byte-identical before/after (20 lines each)
```

### 75.4 The certificate, at `eddc2ef5a`

```
substrate-start = substrate-end = live = 4282c39b2a22...
graphs=38  byte-identical=38   controls 5 of 5   conflations 4 of 4
substrate-head = eddc2ef5a   (D0-run-summary.txt mtime 18:41:33)
```

Gated on `git status --porcelain -- tinybendygrad/` empty before the run started, so the digest it names is
the digest of the commit this section stands on.

## 76. `ku_at` WAS 292,722 OF 805,127 LIST STEPS: A 16-WAY BLOCKED VIEW, 0.9308

§75 named the child count and left `ku_at` (292,722) and `rt` (233,235) as the remaining index-addressed
lists. `ku_at` is `List.get` on the kernel by ABSOLUTE UOP INDEX -- 1,915 times per render -- so it charges
the index for every lookup.

### 76.1 The block size was chosen from the wire, not from taste

MEASURED over the 623 source references of the 405-uop kernel:

```
absolute (today)     n=623  total= 104,945  mean=168.5  median=160.0
blocked 16                 total=  11,135  mean= 17.9  median= 18.0
reversed prefix            total=  45,403  mean= 72.9  median= 12.0
```

**SIXTEEN IS THE MINIMUM OF `i/16 + i%16` AT THIS LENGTH, AND THE REVERSED-PREFIX ALTERNATIVE -- which the
render's forward walk would have made easy -- IS ONLY 2.3x BECAUSE SO MANY SOURCES POINT AT THE PROLOGUE
(BUFFERS AND CONSTANTS AT INDEX 0-4), NOT AT RECENT UOPS.** The distribution is bimodal; blocking is the
shape that serves both halves.

### 76.2 The edit is a type change and two new defs

`chunks_of` blocks the kernel in one forward pass (`chunk_close` + a 16-counting walk); `ku_at` reads
`chunks[i >> 4]` then `[i & 15]`. **58 signatures change one type annotation and nothing else** -- the
identifier stays `kus`, so every call site is untouched; the ten defs that WALK the kernel
(`_render.go`, `uops_to_dtypes`, `_render_defines`, `wmma_*`, `metal_prefix`, `render*`) keep the flat list,
and `_render` passes `chunks_of(kus)` as the lookup argument.

### 76.3 Measured

```
run 1: before 8.17 ms  after 7.87 ms   median 0.9462   13/16   max 2.2491
run 2: before 8.22 ms  after 7.70 ms   median 0.9308   19/24   max 1.2800
```

**TWO RUNS, 40 ROUNDS, BOTH UNDER THE KEEPER LINE**, and the second's p75 is 0.9710 -- the first run's 2.25
outlier is interference, not the change (the machine has been at load 7-14 all session).

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec e2e 7/7 · emit-mm and emit-f64 byte-identical to the §75 render
```

**⇒ AND THE ONE MISTAKE WORTH RECORDING IS THE CHUNK ORDER**: `chunk_close` APPENDS each finished block, so
the outer list is already in forward order and the `List.reverse` I wrote first inverted it -- MEASURED
`0 of 37` on both decoders, every kernel differing, which is exactly the failure the corpus exists to catch.

## 77. `rt` WAS 80% OF EVERY LIST STEP LEFT: `St.r` REVERSED BEHIND ITS OWN LENGTH, 0.8583

After §76 the render's `List.get` total was 292,446, and one site was 79.8% of it:

```
rt        233,235   <- the rendered text of a uop, by absolute index
ku_at      19,187
live_fld   18,463   (decode)
ku_at_go   16,370
```

`rt` is `cstyle.py`'s `r: dict[UOp, str]` -- O(1) both ways in Python -- spelled as a `List` indexed by
position. The same list is also built by `st_put` (`List.append`, O(n)) and patched by `st_set`
(`List.set`, O(n)), which the profile priced at **0.32 + 0.64 ms a turn**.

### 77.1 Newest-first behind a length

`St.r` becomes `Rows{ts, n}` holding the text NEWEST-FIRST, so:

| operation | before | after |
|---|---|---|
| `st_put` (append) | `List.append`, O(n) | CONS, **O(1)** |
| `st_set` (current uop) | `List.set`, O(i) | index `n-1-i` = **0** |
| `rt` (lookup) | `List.get`, O(i) | index `n-1-i` = the **src-to-current distance** |

MEASURED from the wire: the absolute index averages 168.5, the distance **72.9** -- and the distance is
what the render actually needs, because a uop almost always refers to something recent.

**AND THE CHANGE IS ONE TYPE PLUS TWO ACCESSORS, BECAUSE THE PARAMETER IS STILL NAMED `r`.** The identifier
does not move, so all 36 signatures and every call site are untouched; only `st_put`, `st_set` and `rt`
change bodies. (`render_r` needed `Rows.ts` because it returns the list itself.)

### 77.2 Measured

```
same C: True | bytes: 4426
before median 7.76 ms   after median 6.65 ms
ratio min 0.7262  p25 0.8314  median 0.8583  max 1.3261   23 of 24 faster
```

**THE BEST SINGLE SLICE OF THE SESSION AFTER §53's PACKAGING**, and it is a *deletion of work* rather than a
cheaper route to the same work: two O(n) operations become O(1) and one O(i) lookup halves.

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec e2e 7/7 · emit-mm and emit-f64 byte-identical
```

**⇒ AND ONE NEAR-MISS WORTH RECORDING**: the first pass rewrote `r: List<&2, String>` with a regex that had
no left word boundary and matched **`caller:`** inside `Emit_`, changing a field of a different record. The
compiler caught it (`expected: List<&2, String>, observed: R` at `Emit_.caller`), which is the only reason it
is a blemish in this paragraph and not a defect in the port.

### 77.3 The certificate, at `f5e813baa`

```
substrate-start = substrate-end = live = 4028d807a8d4...
head = f5e813baa   38 graphs, 38 byte-identical
```

## 78. THE WIRE IS ONE FLAT TOKEN STREAM: THE SECOND SPLIT PASS WAS 0.89 ms, 0.9408

The four-point decomposition rebuilt on the §77 build names the new leader, and it is the DECODER:

```
stub  (IPC + prints)      0.44 ms
read  (+ 8.7 KB request)  0.95   -> read   0.51
dec   (+ decode)          3.12   -> DECODE 2.17   (32% of the turn)
full  (+ render)          6.74   -> render 3.62   (was 6.44 before §75-77)
```

### 78.1 The decode is three passes, and one of them buys nothing

Ablating `ku_of` to a constant KU (so the line is never split, but the chunk still is):

```
read only          0.89 ms
newline split only 1.78 ms   -> the '\n' pass alone = 0.89
full decode        3.00 ms   -> line split + fields = 1.22
```

**THE WIRE WAS LINES OF FIELDS, SO EVERY BYTE WAS READ TWICE** -- once to find the line ends and once to
find the field ends -- and the first pass bought nothing but a row boundary. Nine tokens are one uop, so the
wire is now one flat space-separated stream and `_chunks` cuts on the TOKEN COUNT (`9 * CHUNK // 27`), never
on a character count that could land mid-row.

### 78.2 The state has to live in one def

Bend refuses a second recursive def calling back into the decoder ("expected a filled definition"), so
`take9` + `List.drop` cannot be composed with `ku_all`: the row state is carried by `ku_all` itself --
`skip` (1 = the token arriving now completes the row) and `fields` collected REVERSED so each is a CONS.
That is also why the peel is not a 9-deep nested match: one def with a counter is the shape this language
allows.

### 78.3 Measured

```
same C: True | bytes: 4426
before median 6.81 ms   after median 6.27 ms
ratio min 0.8002  p25 0.9111  median 0.9408  max 1.0364   22 of 24 faster
```

**AND THE WIN IS SMALLER THAN THE 0.89 ms THE ABLATION PREDICTED** (0.54 measured), because the flat wire is
9,516 bytes against 8,700 -- three characters longer per row is what a token count costs against a line
break -- and because `List.drop` is not free. `List.drop` is gone from the final shape but the row
bookkeeping (`skip`, the reverse of nine) is not.

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec e2e 7/7 · emit-mm and emit-f64 byte-identical
```

**⇒ AND THE HARNESS NOW ASKS THE RENDERER FOR THE DECODE**: `serve.bend`'s private `kus` COPY of
`String.split(text, nlch())` + `L.ku_all(...)` was a second declaration of the wire format, and it had to be
edited in the same commit or the daemon and the one-shot path would have disagreed. It now calls `L.kus`.

### 78.4 The certificate, at `53ad9d648`

```
substrate-start = substrate-end = live = c9efaa78a64d...
head = 53ad9d648   38 graphs, 38 byte-identical
```

## 79. TWO NEGATIVE RESULTS: THE OP MATCH ORDER, AND WHAT THE PROTOCOL IS ACTUALLY WORTH

### 79.1 `Ops.value`'s arm order: 80% fewer comparisons, 0.7% of wall time

The 1500-turn profile put `ops_eq_op` (315 us a turn) and `Ops_value` (215 us) near the top, and the
generated JS says why:

```js
function $..._Ops_value(_op_0) {
  if (_op_0.$ === "OpsSPECIAL") { return 1; }
  else if (_op_0.$ === "OpsBUFFER") { return 2; }   // ... 73 more
```

**A LINEAR if/else CHAIN OVER THE CONSTRUCTOR TAGS.** MEASURED over the 405-uop wire, 12,600 calls walk
**27.3 of 73 arms** = **344,031 string comparisons per render**. Reordering the arms by measured frequency
(`ADD 2571, CAST 2078, LOAD 1382, MUL 1284, INDEX 1059, ...`) cuts that to **67,205, 5.3 arms, 80% fewer**.

```
same C: True | bytes: 4426
before median 5.84 ms   after median 6.00 ms
ratio min 0.8791  p25 0.9531  median 0.9934  max 1.2751   13 of 24 faster
```

**NEUTRAL, SO REVERTED.** The comparison count is real and the reduction is real, and 344,031 tag compares
cost **nothing measurable** -- V8 compares interned strings by pointer, so the chain is far cheaper than its
length suggests. **THE PROFILE HAD ATTRIBUTED 530 us A TURN TO THIS, AND THE PROFILE WAS WRONG**: the
`--cpu-prof` run takes 38 ms a turn against 6.3 ms unprofiled, so every per-function share in it is inflated
by the profiler's own work, and only the *ranking* was worth reading.

### 79.2 The protocol's whole prize is 14.7% and only part of it is reachable

§74 bounded the file protocol at `0.9944` with an argument-fed worker. The same bound on the §78 build:

```
shipped median 5.88 ms   no-file-IO median 4.91 ms
ratio median 0.8530  min 0.7048   -> the whole protocol is worth 0.96 ms, 14.7%
```

**AND THE BOUND IS NOT THE PRIZE.** The measured 0.96 ms covers the caller's `write_text` + `os.replace`, the
worker's `open`/`read`/`close`, AND the 9.5 KB copy in and out. A pipe protocol replaces the syscalls but
still copies the same 9.5 KB through a `File.read` loop -- and `live.bend` has no `read_more`, so the frame
reader would be new code threading a linear `File` through a byte-at-a-time length parse, whose failure mode
is a stall that disables the daemon for the session. **So the pipe is not taken: its bound is 14.7%, its
reachable share is the syscall overhead alone, and its risk is the daemon's.**

**⇒ THE WIRE'S SIZE IS THE LEVER UNDER BOTH TERMS**: it is 9,516 bytes, the decode is charged per byte
(§78.1) and so is the I/O. Shrinking the row is the next slice that would pay twice; it is not in this
commit.

## 80. THE WIRE, SHRUNK AND MEASURED: 12.8% FEWER BYTES AND 33% FEWER TOKENS IS 0.9900

§79 left the wire as the last unexploited lever, with a **wrong** cost model: a padding experiment (9,516 ->
15,061 bytes, same token count) had cost 30%, and the model read that as 122 ns a byte. This section builds
the shrink the model asked for, measures it, and **both the change and the model fail**.

### 80.1 What was built

Four one-character codes (`dt`, `addr`, `kind`, `cc`) were packed into ONE field, with `kind` re-coded from
two characters (`RW`, `M1`) to one (18 distinct characters this port can emit) and `cc` as a base-64 digit
(`portc` REFUSES above 63 rather than emitting one this would read wrong). The row goes from nine fields to
six, and `ku_all`'s state machine from nine tokens to six.

```
old 9,516 bytes -> new 8,294 bytes (12.8% smaller); tokens 3,645 -> 2,430 (-33%)
old row: 5 1 g 1568 1568 p 0~-~0~6272 0 4
new row: 5 1gp4 1568 1568 0~-~0~6272 0
same C: True | bytes: 4426
9,516 B median 5.72 ms   8,294 B median 5.77 ms
ratio min 0.8890  p25 0.9582  median 0.9900  max 1.1272   13 of 24 faster
```

**NEUTRAL, SO REVERTED** -- and it is a *cleaner* negative than §79.1's, because this one is the exact
change the model prescribed.

### 80.2 The padding experiment measured DIGITS, not BYTES

`1` -> `0001` does not only add three bytes: it makes `U32.read` parse four digits instead of one, on every
numeric field of every row. **THE 30% THE PADDING COST WAS THE EXTRA DIGIT PARSING, NOT THE EXTRA SCANNING**,
which is why removing 1,222 bytes recovers 1% and not the 4.1% the model predicted. **A MODEL BUILT FROM A
ONE-SIDED PERTURBATION IS NOT A MODEL** -- adding work to a field tells you what that field's work costs only
if nothing else about it changed, and here two things did.

### 80.3 What the decode actually charges

| perturbation | result |
|---|---|
| +58% bytes, +3 digits per numeric field | **+30%** decode (1.30x) |
| -12.8% bytes, -33% tokens, same digits | **-1%** (0.9900) |

The decode's cost is in the WORK PER FIELD -- `fld`'s index walk, `U32.read`'s digit loop, and one
`String` allocation per token -- none of which a shorter wire removes. **⇒ AND THE ROUTE TO A REAL DECODE
WIN IS NOT A SMALLER WIRE, IT IS FEWER FIELDS AND FEWER `String`s**, which is a different rewrite with a
different proof, and it is not in this commit.

## 81. NINE NAMED FIELDS INSTEAD OF NINE `fld` WALKS: 0.9751 THEN 1.0075, REVERTED

§80.3 left "fewer fields and fewer `String`s" as the open decode direction. The first half is buildable and
was built: **a nested cons match is legal** (`case a <> r1: match r1: case b <> r2: ...` -- MEASURED, the
tree had never used it), so `ku_ws` can take nine named parameters instead of calling `fld(ws, i)` nine
times, and `ku_all` can hand it the accumulator NEWEST-FIRST so the per-row `List.reverse` disappears too.

That deletes 36 `List.get` steps and a nine-step reverse per uop. MEASURED before the build, the decode
decomposes as:

```
read only      0.78 ms
split only     1.47 ms   -> split + token grouping = 0.69
full decode    2.21 ms   -> FIELD WORK (fld + u32 + arg_of + records) = 0.75
```

### 81.1 Two runs, and they disagree

```
run 1: before 5.95 ms  after 5.90 ms   median 0.9751   18/24   min 0.8221  max 1.0737
run 2: before 5.88 ms  after 5.85 ms   median 1.0075   10/24   p25 0.9524   p75 1.0269
```

**TWENTY-EIGHT OF FORTY-EIGHT ROUNDS, WHICH IS NOT A RESULT.** The predicted 4.8% (14,580 list steps) did not
materialise, and §80's lesson is the explanation: `List.get` on a NINE-ELEMENT list is cheap -- the 36 steps
were never the cost, and removing them removes 0.2 ms of a 6 ms turn at most.

**⇒ AND THE CEILING IS NOW MEASURED FROM BOTH SIDES**: the whole of the field work is 0.75 ms, so *any*
rewrite of field extraction -- nine parameters, a character scanner, anything -- can take at most 12% of the
turn, and the part of it that is `fld` is under the instrument's floor.

### 81.2 What the decoder actually spends, after four attempts

| attempt | what it removed | measured |
|---|---|---|
| §78 one split instead of two | a pass over every byte | **kept**, 0.9408 |
| §80 packed fields | 12.8% of the bytes, 33% of the tokens | 0.9900, reverted |
| §81 nine named fields | 14,580 `List.get` steps | 0.9751 / 1.0075, reverted |
| (§79.1 op order) | 80% of the tag comparisons | 0.9934, reverted |

**THE ONE THAT PAID IS THE ONE THAT REMOVED A WHOLE PASS**, and every attempt to remove a *part* of a pass
has been neutral. `String.split`'s per-character recursion is the runtime's, and it recurses whether the
bytes are packed, the fields are named, or the tokens are grouped.

## 82. THE CHARACTER SCANNER'S CENTRAL SUBSTITUTION IS A WASH: `String.to_list` COSTS WHAT `String.split` COSTS

§80.3 named "fewer fields and fewer `String`s" as the open direction, and §81 measured the field half's
ceiling at 0.75 ms. The remaining half is the split (0.69 ms), which a character scanner would replace with
one walk of the wire. **Before writing two hundred lines, the substitution was priced directly**: the same
9,516-byte wire, 300 passes, one program splitting it and one converting it to a character list, both
counting what they walk.

```
String.split(s, ' ') + count   219.2 ms / 300 = 731 us a pass
String.to_list(s)     + count   166.5 ms / 300 = 555 us a pass
```

**`String.to_list` ALLOCATES ONE CONS CELL PER CHARACTER -- 9,516 OF THEM -- WHERE `String.split` ALLOCATES
ONE STRING PER TOKEN, 3,645.** The two constructions cost the same order, and the difference (176 us) is the
ENTIRE prize a scanner could win on the split side, before paying for its own walk, its digit parsing, and
the payload `String`s it must still materialise (one per row, for `arg_of`). **A rewrite of the decoder
cannot buy more than ~0.2 ms here, and every attempt to remove a PART of the decode has measured neutral --
three in a row** (§79.1 0.9934, §80 0.9900, §81 0.9751/1.0075).

**⇒ AND THAT IS WHY IT IS NOT WRITTEN.** The measured decomposition of the decode is 0.78 read + 0.69 split
+ 0.75 fields, and the two terms a scanner attacks are the two whose parts have all measured free: `fld`'s
list walks (§81) and the token grouping (§80). What it could win is one construction replacing another of
the same order.

## 83. THE PIPE FRAME PROTOCOL: BUILT, COMPILED AFTER FIVE REFUSALS, AND IT DOES NOT WORK

§79.2 declined the length-prefixed FIFO frame on the ground that a pipe still copies the 9.5 KB. That was a
reason, not a proof, and the bound (0.8530, 0.96 ms) is the largest un-attempted lever left. So it was
attempted. **It compiles. It stalls on the first frame, and it is not shipped.**

### 83.1 Five refusals, each of which is the design

A read-until-done loop over a linear `File` has to survive the language, and it took five shapes to find
one the compiler accepts. Every message below is verbatim:

| shape | refusal |
|---|---|
| a helper def that calls back into the loop | `expected : a filled definition` (mutual recursion) |
| a lambda matching its own pair parameter | `'m' can't be matched in this position` |
| destructuring in a do-block | `expected : a term` |
| two `match`es in one def (`mode` then the read) | `'mode' can't be matched ... after a match on a later binder` |
| a `File` field in a `Data` state type | `expected : Data, observed : Type` |

The shape that survives: **the fuel first** (the decreasing-self-call check reads arguments left to right),
**the read pair as the loop's parameter** (so every continuation is a self-call), **the mode in a state type
of plain data**, and **the transition in a pure def that consumes the result**.

### 83.2 What it does

`"<decimal length>\n<wire>"` in ONE write; the worker reads the digits one byte at a time, then reads
`need - have` bytes per iteration until the promise is met, then renders and waits for the next frame's
first byte. The state is `SRead{mode, acc, need} | SEmit{acc} | SBad{}`; `st_of` interprets the byte that
just arrived and `sz_of` says how many the next read wants, so `serve` needs exactly one match.

### 83.3 What happened

```
bin/bend serve_frame.bend --check-only   ->   ALL PROOFS CHECK
bin/bend serve_frame.bend -o serve_frame.js  ->  327,576 bytes
write "9516\n<wire>" in one call, read stdout   ->  NO OUTPUT, process alive, no exit
```

**The first frame is never rendered and the process never dies**, which is the signature of a loop reading
an empty `File.read` forever (Bun answers `""` rather than blocking at some point in this path) or of a
state that asks for more bytes than the frame holds. Both are one-line hypotheses and neither could be told
apart **without a print-debug loop whose every iteration is a Bend build plus a process spawn**, and the
scratch instrumentation that would answer it broke the type checker (`expected : @-R:Type -> ...`) before it
could print once.

**⇒ SO IT IS NOT SHIPPED, AND THAT IS THE MEASUREMENT.** A protocol that cannot be seen to render is not a
protocol; the shipped one renders, and its 0.96 ms stays spent. The scratch file is deleted rather than left
in the tree, because a harness that does not work is a harness that rots.

## 84. THE FRAME PROTOCOL LANDED: 0.9103 THEN 0.9459, AND THE STALL WAS ONE INCH

§83 shipped nothing because the frame loop rendered nothing. The probe that decides it took five lines and
six seconds:

```
PROBE: open a fifo, read one byte, then read again while the pipe is EMPTY
  output: ['got1', '<second read did not return>']      <- BLOCKED
  after writing a second byte: second=1                 <- and the blocked read woke up
```

**`File.read(f, 1)` BLOCKS on an empty pipe and answers `""` never.** So the stall was not the loop reading
empty; it was the loop asking for a read it should not have made.

### 84.1 The inch

`sz_of(SEmit{...})` returned **1**. When the payload reached its promised length the state became `SEmit`,
and the arm then issued `File.read(f, 1)` *before* recursing into the render -- a read that waits for the
NEXT frame's first byte, which never comes. One number:

```
case SEmit{acc}: 1   ->   case SEmit{acc}: 0
```

A zero-length read returns immediately, `serve` receives an empty pair, and the `SEmit` arm renders.

### 84.2 Measured

Same 4,426 bytes of C as the file protocol, three consecutive turns identical:

```
run 1 (24 rounds): file 5.83 ms  frame 5.40 ms   median 0.9103   15/24   max 1.3269
run 2 (30 rounds): file 5.92 ms  frame 5.29 ms   median 0.9459   21/30   max 1.3760
```

**36 OF 54 ROUNDS AND BOTH MEDIANS UNDER THE KEEPER LINE.** The bound was 0.8530 (§79.2); the realised
0.91-0.95 is 5-9% of the turn, and the file write, the rename, the open and the close are gone -- only the
9.5 KB copy remains, which is why it is not the 0.85 the argument-fed worker predicted.

### 84.3 And the stress test found a defect that was already there

Both protocols, same wire, repeated rows:

```
  9,516 B ( 405 uops): file=C   frame=C   identical=True
 19,033 B ( 810 uops): file=C   frame=C   identical=True
 28,550 B (1215 uops): file=<exit> frame=<exit> identical=True
```

**NEITHER PROTOCOL RENDERS A KERNEL ABOVE ~810 UOPS IN THE DAEMON**, because `L.kus` splits the whole wire
in one `String.split`, and that is the 28 KB recursion cliff §78's chunking exists for -- the ONE-SHOT path
chunks (`_chunks`), the DAEMON does not. Measured on the OLD worker before this change, so it is
pre-existing and not introduced here. Its cost is not a wrong answer: `render_live` catches the dead worker,
falls back to the one-shot path, and **disables the daemon for the rest of the session** -- so ONE large
kernel makes every later kernel slower. That is the next slice, and it is a defect, not an optimisation.

### 84.4 The daemon turn, measured through the shipped path

```
portc._worker().render(wire) x12:  median 5.28 ms, outputs identical, fallbacks 0 of 12
```

The file protocol's 5.83-5.92 ms (§84.2) is now **5.28 ms**, and the daemon is what `render_live` uses by
default, so that is the number a caller sees.

### 84.5 The chunked-frame fix for §84.3 was started and REVERTED

The fix is the right one -- the caller already cuts chunks at row boundaries and `serve` can decode them one
at a time (`L.kus(h)` per chunk, appended) -- and the DECODER half was written and compiles. **The FRAMING
half was not: a chunked frame needs a third mode in the worker's state machine** (read the chunk's length,
read the chunk, repeat until the total is consumed), and the first attempt left the live path at `1 of 37`
byte-identical. Shipping that would have been a broken daemon in exchange for a defect that is at least
*visible* today: `render_live` catches the dead worker and falls back, so the large-kernel case is slow, not
wrong.

**⇒ SO THE DEFECT STAYS OPEN AND MEASURED**: a kernel above ~810 uops kills the daemon and downgrades the
session to the one-shot path. It is the next slice, and it needs the third mode, not a re-run of this one.

## 85. §84.3 CLOSED: THE DAEMON RENDERS EVERY SIZE AGAIN, FOR 1.4% ON THE COMMON CASE

The defect first: a kernel above ~810 uops killed the worker, `render_live` fell back to the one-shot path,
and **that fallback is sticky** -- `_OFF[0] = True` for the rest of the session. One large kernel made every
later kernel slower.

### 85.1 A zero-length chunk ends the frame

The caller already cuts chunks at ROW boundaries (`_chunks`), which is what the one-shot path passes as
argv. The frame is now one `<length>\n<chunk>` per chunk, **terminated by a zero-length chunk**, and the
state machine gains nothing: the same two modes, with the completed-chunk transition going back to
`SRead{0n, "", 0n, chunks + [chunk]}` instead of to `SEmit`. A total-length prefix would have needed a third
mode; the terminator does not.

`decode` folds `L.kus(h)` over the chunks -- the renderer's own decode, applied to the same pieces the
one-shot path uses.

### 85.2 Measured

```
  405 uops /  9516 B: daemon  4426 B, one-shot  4427 B, identical: True
  810 uops / 19033 B: daemon  8773 B, one-shot  8774 B, identical: True
 1215 uops / 28550 B: daemon 13158 B, one-shot 13159 B, identical: True   <- used to kill the worker
 1620 uops / 38067 B: daemon 17563 B, one-shot 17564 B, identical: True   <- used to kill the worker
```

(the one-byte difference is the one-shot path's trailing newline; the comparison is `got == ref.rstrip("\n")`.)

Through the shipped path, one session, eleven turns: **`fallbacks: 0`**, and a 1,215-uop kernel returns
13,159 bytes with the worker still alive.

### 85.3 What it costs

```
single-frame median 5.32 ms   chunked median 5.41 ms
ratio median 1.0136  min 0.6307  max 1.1015   9 of 24 faster
```

**1.4% ON THE COMMON CASE, WHICH IS THE TERMINATOR READ AND THE CHUNK BOOKKEEPING, AND IT BUYS THE SESSION.**
A 9.5 KB wire is ONE chunk, so the frame is the same payload read plus two more bytes and one more loop
turn; the nine rounds that favour the chunked build put the effect at the instrument's floor.

```
ksweep 37/37 both decoders · opbattery 39/39 · portexec 7/7
emit-mm and emit-f64 byte-identical · substrate unchanged (harness only)
```

## 86. THE DECOMPOSITION ON THE §85 BUILD, AND WHAT THE RENDER'S 64% IS MADE OF

Every earlier decomposition predates the frame protocol, so this one is rebuilt against §85. It is three
points, not four: a frame has to be consumed to stay in sync, so "read" is not separable from the turn.

```
stub (IPC + frame read + prints)   0.35 ms    6%
decode                             1.60 ms   29%
render                             3.49 ms   64%
                                   ------
                                   5.44 ms
```

**THE PROTOCOL TERM COLLAPSED FROM 1.37 ms TO 0.35 ms** -- that is §84 showing up in the decomposition, and
it is the whole of what the file round trip was worth.

### 86.1 The render is 40% string construction, and it has no builder

Ablating `ku_text` to a constant (the dispatch and the state still run; every expression subtree is skipped)
prices the entire class:

```
full render 5.41 ms   expression text ablated 3.22 ms   ratio 0.60
-> building the C text is 2.16 ms of the turn, 40%
```

That 2.16 ms is `String.concat` over an immutable `String`, and **the runtime has no mutable builder to
replace it with**: the whole string surface is `String.append`, `concat`, `contains`, `drop`, `ends_with`,
`eq`, `from_list`, `get`, `is_empty`, `is_lt`, `join`, `length`, `lines`, `map`, `order`. `from_list` goes
through a `List<Char>`, which is one cons per character -- strictly worse.

**⇒ SO THE LARGEST REMAINING TERM IS THE PRODUCT ITSELF.** 2.16 ms to build 4,426 bytes of C, through an
API that copies rather than appends in place, with no builder anywhere in the language. The other ~1.3 ms
is dispatch, state and records, and four attempts on its identifiable sites have measured neutral (§72
0.9976, §79.1 0.9934, §80 0.9900, §81 0.9751/1.0075).

This is the same shape as §44 (no mutable container) and §57 (no branch on a computed value): **a property
of the language the port is written in, measured rather than asserted.**

## 87. THE CONCAT CENSUS, AND THE FIFTH RENDER NEUTRAL

§86 priced the render's text at 2.16 ms (40% of the turn) and said the runtime has no builder. This section
counts the calls, collapses the two sites that are LOOPS of concats rather than single joins, and measures
the collapse.

### 87.1 The census

An instrumented build counting `String.concat` by caller and by arity:

```
String.concat calls per render: 15,653   parts total: 28,717   mean parts/call: 1.83
top-level sites: under_tail_go 858   rd_body_at 429   render_dtype 429   ku_indent_go 365
                 _render_named 336   ku_const_cast_in 147   cfo_bin 144   ...
single-part calls (n=1): 3,762 of 15,653 (24%)
```

**`String.concat` RECURSES OVER ITS LIST**, so 15,653 calls is 28,717 pieces walked one function call at a
time -- the ~11,900 self-calls in the census are that recursion, not the port's code.

### 87.2 The two loops, collapsed, and measured

`under_tail.go` built a name RIGHT-RECURSIVELY, allocating a string per suffix -- O(k^2) bytes for a k-part
name -- and was the hottest renderer site at 858 calls. It now builds a piece list and joins once.
`ku_indent.go` built indentation by repeated concat (365 calls); depths 0-5 are now literals with the loop
as the tail.

```
same C: True | bytes: 4426
before median 5.18 ms   after median 5.29 ms
ratio min 0.9210  p25 0.9833  median 1.0005  max 1.4291   12 of 24 faster
```

**NEUTRAL, REVERTED.** 1,223 of the ~3,700 top-level calls -- a third of the class -- and the class is
2.16 ms, so a third of it should have been ~0.7 ms if the calls were uniform. **THEY ARE NOT UNIFORM**:
`under_tail`'s names are 2-3 parts of 3-8 characters, and `ku_indent`'s depths are 1-3, so each call moves
a handful of bytes. The 2.16 ms is 3,700 allocations of small strings, and no subset of them is worth a
measurable fraction.

### 87.3 Five attempts on the render, five neutrals

| attempt | mechanism | measured |
|---|---|---|
| §72 `i64_shl` both arms | a strict `Bool.pick` building two records | 0.9976 |
| §79.1 `Ops.value` order | 80% fewer tag comparisons | 0.9934 |
| §80 packed wire | 12.8% fewer bytes | 0.9900 |
| §81 nine named fields | 14,580 `List.get` steps | 0.9751/1.0075 |
| §87 concat loops collapsed | 1,223 of 3,700 concat calls | 1.0005 |

**⇒ AND THE ONE CHANGE THAT PAID, §78, REMOVED A WHOLE PASS OVER EVERY BYTE.** Every attempt since has
removed a FRACTION of a pass, and the renderer is now a sum of ~3,700 sub-microsecond allocations with no
single site above 1.3% of its own profile.

## 88. THE OPCODE ATTRIBUTION, AND THE SIXTH RENDER NEUTRAL

§87 left the render as "~3,700 sub-microsecond allocations with no site above 1.3%". This section
attributes the PER-UOP work by opcode class instead, which is the granularity the flat profile could not
give.

### 88.1 The instrument, and its own cost

An inclusive timer around `ku_text` in the generated JS, keyed on `k.op.$` (one instrumented build, one
render):

```
ku_text inclusive 8.246 ms over 340 calls -- MORE THAN THE RENDER ITSELF, because `performance.now()`
is not free and every one of the 340 calls pays it twice.
     ms  calls  us/call  op
  3.347     50    66.95  OpsCAST     <-
  1.310     90    14.55  OpsADD
  0.876     54    16.23  OpsLOAD
  0.814     65    12.53  OpsINDEX
  0.533      1   532.54  OpsBUFFER   (one call, 532 us -- the kernel header)
  0.300      1   300.38  OpsSHL
  0.224     41     5.46  OpsMUL
```

**THE ABSOLUTE FIGURES ARE INFLATED AND THE RANKING IS NOT**: the cheapest class (CMPLT, 8 calls, 7.6 us)
prices the clock at several microseconds a call, which is why the total exceeds the render. CAST is the
leader on both raw and corrected readings, and it is 15% of the dispatches.

### 88.2 CAST is the §39 class, and the cure still does not pay here

`ku_const_cast` was `Bool.pick(String, is_const, ku_const_cast2(...), ku_cast_generic(...))` -- STRICT, so
every CAST built the const-cast text AND the generic-cast text and discarded one. The §39 cure (bool as a
parameter, `match` runs one arm) applies verbatim, `ksweep 37 of 37` both decoders, same 4,426 bytes:

```
run 1: before 5.21 ms  after 5.06 ms   median 0.9613   16/24   max 1.2919
run 2: before 5.31 ms  after 5.58 ms   median 0.9929   15/30   max 1.2630
```

**TWO RUNS DISAGREE, 31 OF 54 ROUNDS, REVERTED.** §39 measured 0.9447 for this cure on the *statement*
path, where the discarded arm built `render_type`, a `String.concat` and `st_c`; here the discarded arm
builds a cast expression of a handful of characters, and the strictness costs less than the instrument's
noise.

### 88.3 Six render hypotheses, six neutrals

| attempt | mechanism | measured |
|---|---|---|
| §72 `i64_shl` both arms | strict `Bool.pick` building two records | 0.9976 |
| §79.1 `Ops.value` order | 80% fewer tag comparisons | 0.9934 |
| §80 packed wire | 12.8% fewer bytes | 0.9900 |
| §81 nine named fields | 14,580 `List.get` steps | 0.9751/1.0075 |
| §87 concat loops | 1,223 of 3,700 concat calls | 1.0005 |
| §88 CAST strict pick | one of two cast texts per CAST | 0.9613/0.9929 |

**AND THE OPCODE ATTRIBUTION SAYS WHY**: after CAST's 3.3 ms (inflated) the classes fall to 1.3, 0.9 and
0.8 ms and then to a long tail -- there is no second CAST to find. The render is a distribution, and the
distribution has no head left that a code change can take.

## 89. PER-CLASS ABLATIONS REPLACE THE INFLATED TIMER, AND THE ALU PATH PAYS: 0.9504 / 0.9427

§88's timer priced every class with a clock that costs microseconds a call, so its absolute figures were
useless and its ranking was only a hint. This section ablates instead: each op arm returns a constant in a
scratch build, and the render delta against §88 with 14 interleaved rounds is that class's real cost.

### 89.1 The attribution, uninflated

```
CAST   full 5.66 -> ablated 5.04   saves 0.69 ms  (12.1%)
INDEX  full 5.16 -> ablated 5.49   saves -0.13 ms  (noise)
LOAD   full 4.88 -> ablated 5.34   saves -0.32 ms  (noise)
ALU    full 4.79 -> ablated 4.15   saves 0.55 ms  (11.5%)
```

**THE TIMER'S LEADER SURVIVES (CAST, 0.69 ms) AND TWO OF ITS RUNNERS-UP DO NOT (INDEX, LOAD: BOTH NOISE).**
The ALU catch-all -- `ADD`, `MUL`, `WHERE` and the rest -- is the second real class at 0.55 ms, and the timer
had it as a single 1.31 ms `OpsADD` row that it attributed by tag rather than by arm.

### 89.2 The ALU path paid, and the mechanism was a double lookup

```
Bool.pick(String, cond, H.strip_parens(rt(r, h)), rt(r, h))
```

STRICT, so `rt` ran TWICE per operand -- and `rt` is a `List.get` by src-to-current distance -- and
`strip_parens` scanned the source even when its result was discarded. One binding, and the bool as a
parameter so the scan only happens on the branch that keeps it (§39's cure):

```
same C: True | bytes: 4426
run 1 (24 rounds): before 5.11 ms  after 4.70 ms   median 0.9504   17/24
run 2 (30 rounds): before 4.97 ms  after 4.85 ms   median 0.9427   19/30
```

**36 OF 54 ROUNDS AND BOTH MEDIANS UNDER THE KEEPER LINE -- THE FIRST RENDER WIN SINCE §78**, and the first
one the ablations found rather than the profile.

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec 7/7 · emit-mm and emit-f64 byte-identical
```

**⇒ AND CAST'S 0.69 ms IS STILL THERE AND IS NOT §88's FIX.** §88 tried the strict pick on `ku_const_cast`
and measured neutral, because the DISCARDED arm is cheap. The 0.69 ms is the arm that RUNS: the cast
expression plus its source lookup, 50 times. That is the next slice, and the ablation is what says so.

### 89.3 The certificate, at `b7a7cc8f6`

```
substrate-start = substrate-end = live = 59fabefa8c95...   head b7a7cc8f6
38 graphs, 38 byte-identical
```

## 90. ABLATING INSIDE CAST: THE CLASS IS THREE PIECES AND NONE OF THEM PAYS

§89's ablation named CAST at 0.69 ms for 50 calls and left the question of WHERE inside it. Two more
ablations, same method (constant in a scratch build, 24 interleaved rounds against §89):

```
render_type ablated:  4.91 -> 4.65 ms   saves 0.17 ms (3.5%)
H.i64_dec ablated:    4.73 -> 4.61 ms   saves 0.24 ms (5.0%)
```

So CAST's 0.69 ms is `i64_dec` 0.24 + `render_type` 0.17 + 0.28 of lookups and concatenation -- **THREE
PIECES, EACH BELOW THE KEEPER LINE, AND NOT ONE HEAD.**

### 90.1 The restructure that should have worked, and what it teaches

`i64_dec` runs a restoring-division fold, and **47 of the 51 int constants on the 405-uop wire have
`hi == 0`** -- non-negative and below 2^32, where `U32.show(lo32)` is the same decimal. The fast path is
three lines and the C cannot move:

```
same C: True | bytes: 4426
before median 4.84 ms   after median 4.89 ms
ratio min 0.9147  p25 0.9834  median 1.0069  max 1.1996   9 of 24 faster
```

**NEUTRAL, REVERTED -- AND THE REASON IS THE WHOLE POINT OF THIS SECTION.** `U32.show` is
`u32_to_word` plus a fold, and `u32_to_word` is

```js
function u32_to_word(x) { let w = {$: "WNil"}; for (let i = 31; i >= 0; i--) { w = {$: "WCon", ...}; } return w; }
```

**THIRTY-TWO CONS CELLS PER NUMBER, IN THE LANGUAGE'S OWN PRELUDE.** Substituting `U32.show` for the I64
fold is one expensive decimal formatter for another, which is why §86's ablation of ALL decimal formatting
priced the entire class at **0.26 ms**: there is no cheap decimal anywhere in this runtime, and the port
calls one of them ~1,500 times a render.

**⇒ AND THAT CLOSES THE RENDER'S LAST NAMED CLASSES.** After CAST (0.69) and ALU (0.55, §89's win) the
ablations fall to INDEX and LOAD -- both noise -- and inside CAST the three pieces are 0.24, 0.17 and 0.28.
There is no fourth place to look.

## 91. THE DECODE, ABLATED: `nums` IS 22%, AND THE SCANNER THAT WOULD FIX IT CANNOT BE WRITTEN

The three-point decomposition rebuilt on the §90 build, so the render's share is post-§89:

```
stub (IPC + frame)   0.30 ms    6%
decode               1.63 ms   33%
render               2.99 ms   61%     (was 3.49 -- §89's 0.50 ms shows up here)
                     ------
                     4.92 ms
```

### 91.1 Decode ablations, decode-only, 14 interleaved rounds each

```
nums   (shape + srcs parse)   dec 1.93 -> 1.44   saves 0.43 ms (22.4%)
arg_of (payload, 18 kinds)    dec 1.60 -> 1.73   saves -0.07 ms  (noise)
u32    (numel + cc)           dec 1.52 -> 1.69   saves -0.12 ms  (noise)
```

**`nums` IS THE DECODE'S ONLY CLASS ABOVE NOISE**, and it is 0.43 ms because `String.split` allocates a
STRING PER ELEMENT: 342 of its 352 real calls parse `srcs`, whose element counts are 1 (106), 2 (229),
3-6 (17). MEASURED per call: 1.2 us for a two-element string.

### 91.2 The scanner, and the two refusals that stop it

A character scan would build the numbers arithmetically -- no substring, no intermediate list, no
`U32.read` per element. It cannot be written:

```
expected : a decreasing self-call (arguments are read left to right: each passed
           unchanged until one shrinks)                  -- Nat.sub(fuel, 1n) is not a subterm
```

and the shape that WOULD satisfy it (`case 1n+k` for the fuel) needs a second `match` on the character,
which is §83's other refusal (`'m' can't be matched ... after a match on a later binder`). The state could
be carried as a Bool plus a defaulted `Char` to dodge the second match, but the loop would then run
`length(s)` times past the end and needs trailing-separator handling -- for a ceiling of 0.2 ms on a 4.9 ms
turn, that is not a trade this record should make.

**⇒ SO THE DECODE'S 1.63 ms IS 0.9 OF ONE PASS OVER EVERY BYTE (§78's split), 0.43 OF `nums`, AND 0.3 OF
RECORD BUILDING** -- and both of the first two are the runtime charging per character and per allocated
string, the same wall §82 hit with `String.to_list`.

## 92. CHUNKING THE SPLIT IS NEUTRAL, AND THE SCANNER TRADES ONE ALLOCATION FOR FOUR

§91 left two candidates: split the wire in smaller chunks (the caller already cuts row-aligned pieces),
and write `nums` as a character scanner via a Bool-plus-defaulted-Char state. Both were tried or priced.

### 92.1 The chunk sweep: `String.split` is LINEAR in characters

The §85 framing already carries one length-prefixed frame per chunk and the worker already calls `L.kus`
per chunk -- but `CHUNK` is 10,000 and the wire is 9,516, so it has always been ONE chunk. Sweeping the
size costs nothing (the frames are built in Python), decode-only and full, 20 interleaved rounds each:

```
decode-only   chunks of 4000 (3 parts): 0.9924   13/20
              chunks of 2000 (5 parts): 1.0048    6/20
              chunks of 1000 (10 parts): 1.0185   7/20
full          chunks of 4000 (3 parts): 1.0224    9/20
              chunks of 2000 (5 parts): 1.0669    9/20
              chunks of 1000 (10 parts): 1.0244   10/20
```

**NEUTRAL TO WORSE, AND THAT IS THE ANSWER: THE SPLIT IS LINEAR.** Ten splits of 1 KB cost what one split
of 9.5 KB costs, plus the per-call overhead. If `String.split` had been O(n^2) -- which the per-character
recursion could have made it -- ten chunks would have been 9x cheaper. **SO THE 0.9 ms IS 9,516 CHARACTERS
AT ~95 ns EACH AND THERE IS NO SHAPE OF CALL THAT MAKES IT CHEAPER.**

### 92.2 Why the scanner does not get written

The Bool-plus-defaulted-Char state avoids the second `match`, but it forces every branch decision through
`Bool.pick`, which is STRICT: the "push this number" arm builds `List.append(out, [acc])` on EVERY
CHARACTER and discards it whenever the character is not a separator. A two-element `srcs` would trade two
substring allocations for four cons cells -- one per character scanned -- to save a `String.split` that
§92.1 just showed is linear and cheap per character.

**⇒ AND THAT CLOSES THE DECODE.** 0.9 ms of one linear pass, 0.43 ms of `nums` whose only cheaper form is a
pass with MORE allocations, and 0.3 ms of record building.

## 93. THE TEXT CLASS IS 17.5x COPY AMPLIFICATION, AND THE ARITHMETIC CLOSES IT

§86 priced the whole text class at 2.16 ms by ablating `ku_text`. This section asks WHY, by counting the
characters actually fed to `String.concat` in one render.

```
concat: 11,909 parts, 77,500 characters fed
rendered: 4,426 characters
AMPLIFICATION = 17.5x
```

### 93.1 And it accounts for the whole class

`String.concat` is `h + concat(t)` over JS strings, so every character fed to it is copied. At the ~30 ns a
character that JS string concatenation costs at these sizes:

```
77,500 characters x 30 ns = 2.33 ms        §86's ablation of the same class: 2.16 ms
```

**THE TEXT CLASS IS NOT "BUILDING THE C". IT IS COPYING IT 17.5 TIMES.** Every expression's text is
materialised, then copied again by its parent, then again by the statement that embeds it -- a leaf inside
a depth-d expression is copied d times before the kernel's single `String.join`.

### 93.2 The fix has a shape, a size, and a price -- and it is not in this commit

The only way to stop copying is to stop materialising: every `ku_text_*` / `cfo_*` / `render_*` would
return a `List<String>` of PIECES, parents would Cons their children's lists (O(1) per piece, no character
copied), and ONE `String.join(list, "")` at the statement would make the string once. That is a functional
builder in a language with no builder -- exactly what §86 said was missing, constructed instead of assumed.

Its size is the problem: it is most of `cstyle.bend`'s text path -- every arm of `ku_text.go`, the `cfo_*`
family, `render_cast`/`render_type`/`render_dtype`, `_render.plain`/`decl`, `st_kernel` -- about sixty
definitions changing one type. Its measured expectation is ~2 ms of a 4.9 ms turn, **the largest single
prize left on this side**, and a byte-identical gate set that will catch any mistake in it.

**⇒ IT IS NOT STARTED HERE, AND THAT IS A BUDGET DECISION, NOT A MEASUREMENT ONE.** A sixty-definition
type change cannot be finished and verified inside this turn, and a half-converted text path is a broken
renderer. The measurement is the deliverable: **17.5x, 2.33 ms of copying, and the exact shape that removes
it.**

## 94. WHERE THE 77,500 CHARACTERS GO, AND WHY REMOVING ONE CONCAT IS ALWAYS NOISE

The attribution of §93's 77,500 characters by call site:

```
60,635 (78.2%)  $String_concat itself   -- every part beyond the first, at every nesting level
 8,187 (10.6%)  st_pay_x                -- the FRAME assembling "<acc><chunk>": one copy of the whole wire
 1,920 ( 2.5%)  rd_body_at
 1,314 ( 1.7%)  ku_indent_go
 1,124 ( 1.5%)  _render_named
 1,032 ( 1.3%)  ku_render_index.aluconst_go
```

### 94.1 The one copy that could be removed, and why it is not worth removing

`st_pay_x` did `String.concat([acc, text])` with `acc` EMPTY on the common path -- a 9.5 KB wire arrives in
one chunk -- so it copied every character of it to prepend nothing. Skipping the copy when `acc` is empty
(the Bool as a parameter, since `Bool.pick` is strict):

```
same C: True | bytes: 4426
run 1: 4.94 -> 4.87 ms   median 0.9745   20/24
run 2: 4.96 -> 4.95 ms   median 1.0093   10/30
```

NEUTRAL, REVERTED. **AND THAT IS THE CORRECTION TO §93's ARITHMETIC THAT MATTERS MOST: one concatenation
of 8,187 characters is ONE memcpy -- a few microseconds at memory bandwidth -- not 8,187 character-by-
character copies.** The ~30 ns a character is the cost of the NESTED case, where each level's output is
re-copied by its parent; it does not divide by the number of concatenations.

### 94.2 What that means for the piece-list transformation

**EVERY "REMOVE ONE CONCAT" CHANGE IS THEREFORE BELOW NOISE BY CONSTRUCTION**, and six of them measured so
(§87, §90, and this one). The only change that can move the 2.16 ms is the one that removes the NESTING
itself -- pieces Consed, joined once -- and its prize is the 78.2% bucket, not any of the sites below it.
The estimate in §93 (2.33 ms of copying) stands as an upper bound on that prize; the five sites under
`st_pay_x` total 12,000 characters, i.e. about 1.2 ms of the nested work, and they are re-copied because
they are nested, not because any single call is slow.

## 95. THE PIECE-LIST TRANSFORMATION: ATTEMPTED, PLUMBED, AND THE BLOCKER IS `strip_parens`

§93 specified the transformation. This section started it. The storage layer was written and compiles:

```
type Rows is Data:
  Rows{ts: List<&2, List<&2, String>>, n: U32}     -- pieces per uop, not a string

def rtp(+r: Rows, +i: U32) -> List<&2, String>     -- the pieces
def rt(+r: Rows, +i: U32) -> String: String.join(rtp(r, i), "")   -- the 21 non-ALU sites are unchanged
def st_put(+st, x: String) -> St: st_put.p([x], st)               -- storage is uniform: a 1-piece list
def st_set(+st, i, x: String) -> St: st_set.p(st, i, [x])         -- and st_set.p takes pieces
```

`ksweep 37 of 37` on both decoders with it in place, i.e. the plumbing is correct and **buys nothing on its
own**: `ku_text` still returns a String, so every list holds one fully-built piece and every character is
still copied.

### 95.1 The blocker, and it is not the size

The ALU path cannot simply Cons its sources, because `ku_alu_srcs` STRIPS PARENTHESES from a source that
has the parent's own op:

```
Bool.and(O.eq_op(ku_op_at(kus, h), op), ku_strips(op)) -> H.strip_parens(rt(r, h))
```

`H.strip_parens` is `String.take(String.drop(s, 1n), len - 2n)` -- it needs the CHARACTERS, so a source's
pieces would have to be joined before stripping, and the copy comes back exactly where the amplification
lives (`(a+b)+c` chains are the deep ones, and they are the ones that strip).

**THE FIX IS KNOWN AND CLEAN**: `cfo_bin` builds `["(", ...a..., sym, ...b..., ")"]`, so a source built by
the ALU path ALWAYS has `(` as its first piece and `)` as its last. Stripping is then dropping the first
and last PIECE -- a fold over pieces, O(pieces) and ZERO characters copied. That is a new
`strip_pieces` and it is the load-bearing piece of the whole transformation.

### 95.2 What is left, and why it is not in this commit

With the plumbing in place and `strip_pieces` designed, the rest is mechanical and large: `ku_text`'s return
and its 20 arms (the 19 non-ALU arms wrap, the ALU arm passes through), the 9 `cfo_*` plus `cfo_xs1..3`
and `xs_at` to pieces, `code_for_op.of` / `code_for_clang.of` / `code_for_base.of`, and `_render.plain` /
`decl` / `named` / `range` / `special` / `stmt` / `emit` to carry `l` as pieces and `String.join` once.

**IT IS REVERTED, AND THE REASON IS THE ONE RULE THAT HAS HELD ALL SESSION: A CHANGE THAT MEASURES NOTHING
DOES NOT LAND.** The plumbing alone is neutral by construction (one-piece lists), and shipping it would put
a type change through the renderer -- and a corpus re-run -- for zero. The next unit of work is
`strip_pieces` plus the arms, and it is a single coherent change; doing half of it is what makes a
renderer broken rather than slow.

## 96. THE PIECE-LIST TRANSFORMATION LANDS: 0.9049 AND 0.9058, 39 OF 46 ROUNDS

§93 measured 17.5x copy amplification and §95 specified the fix. This section builds it.

### 96.1 What changed

`Rows` holds `List<&2, List<&2, String>>` -- the PIECES of each uop's text -- and:

| boundary | before | after |
|---|---|---|
| `Rows` | one `String` per uop | the pieces |
| `rt` | the string | `String.join(rtp(r, i), "")`, with `rtp` answering pieces for the ALU path |
| `ku_text` / `ku_text.go` | a `String` | pieces; the 19 non-ALU arms wrap, the ALU arm passes through |
| `ku_alu_srcs` | `List<String>` | `List<List<String>>`, each source's PIECES |
| `cfo_unary/recip/neg/bin/tern` | `String.concat` | `List.concat` over pieces -- no character copied |
| `_render.plain` / `decl` | `String.concat([indent, l, ...])` | `String.concat([indent, String.join(l, ""), ...])` -- ONE join per statement |

**AND `strip_parens` WAS THE LOAD-BEARING PIECE** (§95.1): the ALU path strips the source's outer parens
when it shares the parent's op, and `H.strip_parens` needs characters. `cfo_bin` emits `(` and `)` as their
OWN pieces, so `strip_pieces` drops the first and last PIECE -- the same answer, no join, no copy.

### 96.2 Measured

```
same C: True | bytes: 4426
run 1 (16 rounds): before 5.07 ms  after 4.63 ms   median 0.9049   14/16
run 2 (30 rounds): before 4.85 ms  after 4.45 ms   median 0.9058   25/30
```

**39 OF 46 ROUNDS, BOTH MEDIANS 0.905 -- A 10% WIN ON THE TURN, THE LARGEST SINCE §77.**

### 96.3 And the instrument that predicted it was wrong about WHY

The `String.concat` counter reads **16.6x after the change against 17.5x before** -- nearly unchanged --
because it does not count `String.join`, which is where the copying moved. **`String.join` is
`join_go(tail, head, sep)`, a TAIL-RECURSIVE ACCUMULATOR, not the right-nested `h + join(t)` that
`String.concat` is**, so the same characters cost less in that shape than in the nested one.

**⇒ SO §94's ARITHMETIC WAS RIGHT ABOUT THE SIZE AND WRONG ABOUT THE MECHANISM**: the 2.16 ms was 17.5x
AND a right-nested concat; the fix removes the NESTING (which the ablation measured) while leaving a copy
per character at the join (which the counter measures). The counter alone would have called this neutral;
the A/B is the arbiter, and it says 0.905.

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec 7/7 · emit-mm and emit-f64 byte-identical
```

## 97. THE CAST ARM JOINS THE PIECE PATH: 0.9671 AND 0.9265, 35 OF 54 ROUNDS

§96 converted the ALU path and the statement assembly. The non-ALU arms still materialised a String and
handed it to the one-piece wrapper. This section converts the largest of them -- CAST, which §89's ablation
priced at 0.69 ms, the renderer's most expensive class.

### 97.1 What changed

```
ku_cast_generic      String.concat(["(", render_cast(..., rt(r, src0)), ")"])
                     -> List.concat([["("], render_cast_p(..., rtp(r, src0)), [")"]])
render_cast_p        NEW: ["(" <> render_type <> ")("] Cons val Cons [")"]
ku_text_cast         -> List<&2, String>
ku_const_cast/_by    -> pieces; the const arms wrap their String, the generic arm Conses
ku_const_cast2       -> pieces, so the int/float arms wrap and the fallthrough Conses
```

The source's TEXT is now Consed into the cast expression instead of copied into it -- one fewer copy per
cast -- and `render_type`'s output, which is itself a string, becomes a single piece.

### 97.2 Measured

```
same C: True | bytes: 4426
run 1 (24 rounds): before 4.50 ms  after 4.35 ms   median 0.9671   14/24
run 2 (30 rounds): before 4.55 ms  after 4.20 ms   median 0.9265   21/30
```

**35 OF 54 ROUNDS, BOTH MEDIANS UNDER THE KEEPER LINE -- ~4% ON THE TURN.**

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec 7/7 · emit-mm and emit-f64 byte-identical
```

**⇒ AND THE DECOMPOSITION ON THE §96 BUILD WAS `stub 0.38 / decode 1.64 / render 2.85`**, so the render is
now 58% of the turn, decode 34%, protocol 8%. LOAD, STORE and INDEX remain un-converted; §89 measured LOAD
and INDEX at noise, so CAST was the only one of the four with a price.

## 98. THE POST-PIECE ABLATIONS, AND THE NINE-DEEP PICK CHAIN INSIDE CAST: 0.9221 / 0.9311

The per-class ablations re-run against §97, 16 interleaved rounds each:

```
CAST   full 4.66 -> ablated 3.75   saves 0.89 ms (19.0%)
ALU    full 4.21 -> ablated 4.12   saves 0.13 ms ( 3.0%)   <-- was 0.55 before §96
INDEX  full 4.44 -> ablated 4.07   saves 0.26 ms ( 5.8%)   <-- was noise
LOAD   full 4.23 -> ablated 4.24   saves 0.05 ms ( 1.3%)
TEXT   full 4.47 -> ablated 3.17   saves 1.18 ms (26.3%)   <-- was 2.16 before §96/§97
```

**THE PIECE PATH IS VISIBLE IN ITS OWN ATTRIBUTION: the ALU catch-all fell from 0.55 to 0.13 and the whole
text class from 2.16 to 1.18 -- HALVED.** CAST is now the leader at 0.89 and it GREW, which sent the look
inside it again.

### 98.1 Nine strict picks, eight strings discarded

```
def ku_const_cast_int_w(s, w, d, dev, i) -> String:
  Bool.pick(String, eq_dt(d, int64),  s + "l",
    Bool.pick(String, eq_dt(d, uint64), s + "ul",
      Bool.pick(String, eq_dt(d, uint32), U32.show(lo32(i)) + "u",
        Bool.pick(String, eq_dt(d, boolean), i64_is_neg ? "0" : "1",
          Bool.pick(String, eq_dt(d, uint8),  w, ... s)))))
```

Every arm is built and eight are discarded, and `w` (`ku_cast_wrapped(dev, d, s)`, itself a concatenation)
was computed at the CALL SITE for four of the nine arms. A Nat code answers the dispatch once:

```
def dtw(+d: S.Dt) -> Nat            -- int64 0, uint64 1, uint32 2, bool 3, u8 4, u16 5, i8 6, i16 7, else 8
def ku_ccw.at(ix: Nat, s, d, dev, i) -- match ix: one arm builds one string
def ku_const_cast_int_w(...)         -- ku_ccw.at(dtw(d), s, d, dev, i)
```

and `w` is computed inside the four arms that need it.

### 98.2 Measured

```
same C: True | bytes: 4426
run 1 (26 rounds): before 4.68 ms  after 4.47 ms   median 0.9221   18/26
run 2 (30 rounds): before 4.57 ms  after 4.18 ms   median 0.9311   19/30
```

**37 OF 56 ROUNDS, BOTH MEDIANS ~0.93 -- ~7% ON THE TURN.**

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec 7/7 · emit-mm and emit-f64 byte-identical
```

## 99. THE DECIMAL WAS THE COST ALL ALONG: `u32_dec` BY DIVISION, 0.9460 / 0.9582

§98 left CAST as the render's most expensive class at 0.89 ms after three passes at it. This section
ablates INSIDE CAST against §98 -- `i64_dec`, `render_type`, `ku_cast_wrapped`, and the whole arm:

```
i64_dec       full 4.69 -> 4.09   saves 0.65 ms (13.9%)
render_type   full 4.26 -> 4.19   saves 0.09 ms ( 2.2%)
wrapped       full 4.31 -> 4.27   saves 0.11 ms ( 2.6%)
cast_all      full 4.02 -> 4.05   saves 0.18 ms ( 4.4%)   <- noise; the four runs disagree
```

**`i64_dec` IS 0.65 ms ON ITS OWN -- 13.9% OF THE TURN, AND MORE THAN ABLATING THE WHOLE CAST ARM SAID.**
(The arm-level figure is the unreliable one of the four: its `full` reading drifted 0.67 ms across the run
while the others did not.)

### 99.1 Why §90's "neutral" was neutral, and this is not

§90 swapped the I64 fold for `U32.show` and measured 1.0069, because **`U32.show` is `u32_to_word` plus a
fold, and `u32_to_word` builds THIRTY-TWO CONS CELLS per number in the language prelude**. One expensive
decimal for another. This walks the digits instead:

```
u32_nd(fuel, n)      -- how many digits: n < 10 ? 1 : 1 + u32_nd(n / 10)
u32_dec.go(fuel, n, acc) -- one U32.div, one U32.mod and ONE CONS PER DIGIT
u32_dec(n)           -- String.from_list(...)
```

Two passes of at most ten native-arithmetic steps, and `i64_dec` now takes this path when `hi32(x) == 0`
(47 of the 51 int constants on the 405-uop wire); negative and wide values keep the fold, so the text
cannot move.

**THE SHAPE OF THE CHANGE IS THE ONE THIS LANGUAGE KEEPS DEMANDING**: `match` cannot scrutinise `n < 10`, so
the count is its own def; and BOTH defs must put the FUEL FIRST, because "a decreasing self-call" reads its
arguments left to right and `n` is divided rather than passed unchanged.

### 99.2 Measured

```
same C: True | bytes: 4426
run 1 (26 rounds): before 4.44 ms  after 4.37 ms   median 0.9460   20/26
run 2 (30 rounds): before 4.28 ms  after 4.11 ms   median 0.9582   19/30
```

**39 OF 56 ROUNDS, BOTH MEDIANS UNDER THE KEEPER LINE -- ~4-5%.**

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec 7/7 · emit-mm and emit-f64 byte-identical
```

**⇒ AND `U32.show` IS STILL CALLED ~1,500 TIMES A RENDER** (§86 priced the whole decimal class at 0.26 ms
then, before the NUMBERS grew cheaper elsewhere). Replacing those call sites with `u32_dec` is the next
slice, and it is now known to be worth something rather than guessed.

### 99.3 The follow-up the section named, measured: replacing `U32.show` at its 20 call sites is NEUTRAL

§99 predicted the next slice would be swapping the renderer's `U32.show` calls for `u32_dec`. Done and
measured:

```
same C: True | bytes: 4426
U32.show median 4.18 ms   u32_dec median 4.16 ms
ratio min 0.7722  p25 0.9627  median 1.0061  max 1.3833   12 of 26 faster
```

**NEUTRAL, REVERTED.** The ~1,500 `U32.show` calls a render are not where the decimal time is spent: the
0.65 ms §99 removed was `i64_dec`'s FOLD (a division loop per digit, over the wide form), not the forty
small `U32.show` calls the renderer itself makes. **A CLASS COUNTED BY CALL SITES IS NOT A CLASS COUNTED BY
TIME** -- the same trap §79.1 hit with `Ops.value`'s 12,600 calls.

## 100. THE INDEX ARM JOINS THE PIECE PATH: 0.9403 AND 0.9454, 46 OF 56 ROUNDS

§98's post-piece ablation put INDEX at 0.26 ms (5.8%), no longer noise. It is three defs, each with a
strict `Bool.pick` at its head, and all three now branch instead:

| def | before | after |
|---|---|---|
| `ku_render_index` | `Bool.pick(alu_addr, aluarm, global)` | `ku_render_index.by(b, ...)`, a Bool-parameter `match` |
| `ku_render_index.aluarm` | `Bool.pick(const_cast, aluconst, "(src0)[src1)")` | `ku_render_index.aluarm.pick(b, ...)` |
| `ku_render_index.aluconst` | `Bool.pick(numel > thresh, "src0[ix]", "src0.ix")` | `ku_render_index.aluconst.pick(b, ...)` |
| `ku_render_index.global` | `Bool.pick(add, strip(rt(src1)), rt(src1))` — **`rt` twice** | `ku_src_pieces(add, rtp(src1))` |

Every arm answers pieces with `rtp`, so the source's text is Consed rather than copied -- and the three
strict picks stop building the arm they discard.

### 100.1 Measured

```
same C: True | bytes: 4426
run 1 (26 rounds): before 4.27 ms  after 4.11 ms   median 0.9403   23/26
run 2 (30 rounds): before 4.23 ms  after 4.04 ms   median 0.9454   23/30
```

**46 OF 56 ROUNDS, BOTH MEDIANS ~0.94 -- ~6% ON THE TURN.**

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec 7/7 · emit-mm and emit-f64 byte-identical
```

**⇒ AND THE PIECE HELPERS HAD TO BE HOISTED**: `strip_pieces`/`ku_src_pieces` lived beside the ALU path at
~1830 and `ku_render_index.global` sits at ~1627, so the file needed them above their first user -- the
same forward-reference rule that has shaped every change since §83.

## 101. THE PER-CLASS ABLATIONS ARE CONFOUNDED, AND THE CORRECTION CHANGES WHAT IS ABOVE THE LINE

§98 and §100 named their targets from "ablate an arm to a constant, measure the delta". That method has a
defect this section found by arithmetic instead of by another run:

```
49 i64_dec calls measured at 0.38 ms  ->  7.8 us a call
```

**A DECIMAL RENDER IS TEN DIVISIONS AND TEN CHARACTERS; 7.8 MICROSECONDS IS TWENTY THOUSAND OPERATIONS.**
It is not the decimal that costs that. **ABLATING A TEXT PRODUCER TO A CONSTANT ALSO SHRINKS THE C**: the 51
int constants render to 279 characters of the 4,426 the kernel emits, so "return `0`" removes the decimals
AND six percent of the product, and the delta is both.

### 101.1 The corrected reading

Every per-class figure this record has quoted for a TEXT arm carries that inflation. Scaling by the output
it removes: CAST's 0.41 ms loses roughly 50 casts x 10 characters = 500 of 4,426 (11%), and `i64_dec`'s
0.38 loses 279 (6%). **The ranking survives -- CAST is still the largest -- but the magnitudes are upper
bounds, and a class at 5-6% is at the line, not above it.**

**⇒ AND IT EXPLAINS A PATTERN THAT WAS PUZZLING: the arm-level and part-level ablations kept disagreeing**
(§98's `cast_all` 0.18 against `i64_dec` 0.65 in the SAME run), because each subtracts a different amount
of output and each run's baseline drifted under load.

### 101.2 The decomposition, which has no such confound

```
stub (IPC + frame)   0.34 ms    8%
decode               1.54 ms   37%
render               2.28 ms   55%     (2.99 at §96 -> 2.85 -> 2.28; -0.71 across §97-§100)
                     ------
                     4.15 ms
```

**THE RENDER IS DOWN 24% SINCE §96 AND THE DECODE IS NOW 37% OF THE TURN** -- and the decode's attribution
(§91: 0.9 one linear pass, 0.43 `nums`, 0.2 records; §92: chunking neutral) has no arm left that a code
change can take without restructuring the runtime's `String.split`.

### 101.3 What is left, corrected

| class | raw ablation | corrected (minus its output share) |
|---|---|---|
| CAST | 0.41 ms (10%) | ~0.20 ms (5%) |
| whole `ku_text` | 0.56 ms (16%) | ~0.20 ms (5%) |
| ALU / INDEX / LOAD / STORE | -0.08 to -0.45 (noise) | nothing |

**THERE IS NO CLASS ABOVE THE KEEPER LINE LEFT IN THE RENDER**, and the remaining arms (STORE, LOAD,
BITCAST, RANGE, WMMA, STACK, IF, BACKEDGE, BUFFER, SPECIAL) are each one materialisation of a short string
that the statement then copies once -- the piece path has taken everything with a price.

## 102. §101's CORRECTION WAS WRONG, AND THE REMAINING ARMS STILL PAID: 0.9351 / 0.9593

§101 claimed the per-class ablations were inflated because a text arm's constant also shortens the C, and
scaled every figure by the removed output. That correction was itself an estimate. This section measures
the thing it assumed -- the cost of a character in the output pipeline -- and the assumption is wrong by
two orders of magnitude.

### 102.1 The padding sweep: 5 ns a character

Two scratch builds that append a literal to EVERY statement, so the C grows by a known amount while nothing
else changes:

```
+ 2,100 characters (4,426 -> 6,526):   4.13 -> 3.92 ms   (noise; the padded build is FASTER)
+21,000 characters (4,426 -> 25,426):  3.87 -> 3.98 ms   +0.11 ms  =  +5 ns a character
```

**A CHARACTER OF OUTPUT COSTS 5 NS, NOT THE 230 NS §101 SCALED BY.** So the ablation deltas were never
output-size-confounded: CAST's 500 characters cost 2.5 us of its 0.41 ms, and `i64_dec`'s 279 cost 1.4 us of
its 0.38. **§101 IS RETRACTED.**

**⇒ AND THAT LEAVES A DIFFERENT DIAGNOSIS: the per-arm deltas (0.1-0.4 ms) are the same size as the drift in
their own baselines (0.2-0.3 ms across the runs of one batch). The instrument is not biased, it is NOISY,
and the end-to-end A/B is the only one that can carry a decision.**

### 102.2 So the arms were converted and the A/B judged them

`ku_text_load` (its 3-source choice is a strict `Bool.pick` building both forms -- now a Bool-parameter
`match`), `ku_text_store`, and `ku_text_bitcast` all answer pieces with `rtp`:

```
same C: True | bytes: 4426
run 1 (26 rounds): before 4.00 ms  after 3.70 ms   median 0.9351   17/26
run 2 (30 rounds): before 3.86 ms  after 3.68 ms   median 0.9593   19/30
```

**36 OF 56 ROUNDS, BOTH MEDIANS UNDER THE KEEPER LINE -- ~4-6%.**

```
proofs ALL PROOFS CHECK · ksweep 37/37 both decoders · opbattery 39/39
portexec 7/7 · emit-mm and emit-f64 byte-identical
```

## 103. THE DECODE AT 41%: THE WIRE-SHRINKING DIRECTION HAS A MEASURED CEILING OF ~2%

The decomposition on §102, and the decode is now the largest single term:

```
stub (IPC + frame)   0.33 ms    8%
decode               1.61 ms   41%
render               2.01 ms   51%
                     ------
                     3.95 ms
```

### 103.1 What a shorter wire is worth, from the measured per-character rate

§82 measured `String.split` over this exact wire at **731 us for 9,516 characters = 77 ns a character**. The
split is linear in characters (§92's chunk sweep), so the ceiling of any wire compaction is:

```
idx in base-64 (1 char vs 1-2)                     ~4% of the wire  -> 0.03 ms  (0.8%)
ALL numeric fields in base-64 (idx+numel+shape+srcs)  ~13%          -> 0.10 ms  (2.4%)
an impossible 20% cut                                             -> 0.15 ms  (3.7%)
```

**2.4% AT A 13% CUT, AND §80 MEASURED ITS 12.8%-FEWER-BYTES PREDECESSOR AT 0.9900 WHEN THE TURN WAS 5.7 ms.**
The direction is closed by arithmetic at the new scale as well as by that measurement.

### 103.2 The one version that could have beaten that, attempted and reverted

The same encoding removes `nums`' `String.split` -- a count character, then two base-64 characters an index,
with no `~` to scan -- and `nums` is 0.43 ms of the decode. That is the part that could reach the keeper
line, because it removes a PASS rather than shortening one.

It was written: `portc` emits `<count><2 chars per index>`, `live.bend` gains `b64u`/`ch`/`b64at`/`src_nums`
and keeps the old decimal `nums` for `shape` (395 of 405 rows are `-`). The literal path passed 37 of 37;
**THE LIVE LANE DID NOT -- 0 of 37 -- and the mismatch is in the new decoder**, so the change was reverted
rather than debugged at the end of a session:

```
ksweep after revert: 37 of 37 byte-identical, both decoders
```

**⇒ SO THE NEXT UNIT IS THAT DECODER, AND IT IS SMALL**: `src_nums`/`b64at` against `portc.B64`, with the
`count` character read by `b64u` and two characters per index. The pieces are written down in this section
and the gate that catches it (`ksweep`'s live lane) is already the thing that failed it.
