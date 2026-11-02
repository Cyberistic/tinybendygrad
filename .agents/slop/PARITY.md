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

| file(s) | upstream lines | treatment |
|---|---|---|
| `renderer/amd/__init__`, `renderer/isa/__init__`, `runtime/support/{am,nv,rdma}/__init__` | 0 each (5 files) | **marker-only** `.bend`, engine precedent |
| `llm/__init__`, `llm/kernels/__init__` | 0 each (2 files) | **marker-only** `.bend` |
| `llm/kernels/amd.py` | 811 | **documented not-ported stub** — the disposition `TODO.md:5187` already declares for it |
| `llm/__main__.py` | 1 | trivial: the `main()` guard |
| `llm/cli.py` · `llm/model.py` · `llm/serve.py` | 223 · 650 · 176 | **the only real port work left** |

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
