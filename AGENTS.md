You are one of Cyberistic's agents. He hates unclean code and hacks. He loves his
documentations. LOC IS a measure of quality, the LESS, the better.

# HOW TO READ THIS FILE

Every line here is a **prescription**. Where a prescription can be measured it carries
`measure:` — the command and the token that must appear. **No prescription quotes a run.**
A run is a record of a tree that has since moved; the records are in
`.agents/slop/agend/` and in the artifacts they name.

The test is one line: if you cannot run something and read a token, you are not checking,
you are quoting. A governing document nobody checks against reality propagates into every
brief that cites it.

# GENERAL

- Concise, clean code. No hacks. If you need a paragraph-long comment to justify code,
  the code is wrong.
- **Security, then effect, then speed, then beauty.** Types and fail-safe defaults first.
- Shareable logic is reused. Hoist; never copy-paste.
- Version control is jj (`jj` MCP). Commit often, write meaningful messages, and use jj
  workspaces when you run several agents.
- Agent state Markdown lives under `.agents/slop/`. The plan for a piece of work is a
  checklist there, not prose in a report.
- A reference repo is cloned into `references/` and gitignored, and it is recorded in
  `.agents/TOOLS.md` — **not** in `README.md`. The README is off limits; this table is the
  ledger.
- **Tick work off in `.agents/TODO.md`.** If the task is not there and it is meaningful,
  add it with a `[###.....] n/m` bar. Implementation details do not go there.
- **A TODO comment for every unfinished task**, so `rg TODO` finds the work.
- `.agents/TOOLS.md` is the tool ledger: every tool, library and reference checkout, what
  it is pinned to, and why.

# DEVELOPMENT

- **No external dependencies in what the port ships.** The port imports `Base` and its own
  `.bend` files.
  `measure:` `rg -n '^\s*import' tinybendygrad --glob '*.bend'` — every line names `Base` or
  a sibling `.bend`.
  Tools installed to *check* the port are a different population: `ruff`, `mypy` and
  `pytest` are not in `.venv`, and `uv.lock` exists for upstream's Python.
- **No `.txt` files, ever.** `.rows` for expected values and row dumps, `.out`/`.err` for
  captured streams, `.tsv` for tabular, `.md` for prose.
  `measure:` `checks/no-txt.py` — read its HARD/EXCUSED rows, never a number you remember.
  A carve-out is a **generator's `declared()` loaded by path**, never a second copy of the
  list: `checks/no-txt.py` asks `differ.declared()`, and `checks/README.md` names the five
  generators it accommodates.
- **Stay Turing-incomplete.** Completeness requires approval first.

# THE BEND COMPILER

- The compiler is **`bin/bend`**, a gitignored shim onto `references/bend/bend2/main.ts`.
  There is no bare `bend` on `PATH`.
  `measure:` `ls -l bin/bend` — it exists; `command -v bend` failing proves nothing.
- `measure:` `bin/bend guide` — the language reference (rc=0).
- Laws live in `tinybendygrad/LAWS.bend`; the proof entry point is
  `tinybendygrad/LAWS/PROOF.bend`.
  `measure:` `bin/bend tinybendygrad/LAWS/PROOF.bend --check-only` — `ALL PROOFS CHECK`.
  One proof file, because Bend allows one `def` of a law's name per file.
- **Parallelise everything that is not a `bend` process.** For `bend`, the precondition is
  the **sum**, not the count: run two files concurrently only while the sum of their
  measured peak RSS is under 60% of `hw.memsize`.
  `measure:` the per-file peak RSS in `.agents/slop/peakrss/census.rows`, and
  `sysctl -n hw.memsize`. The population is bimodal; a remembered number is not a budget.
- **Read the verdict TOKEN** from `checks/bounded.py`, never the exit code:
  `KILLED-ON-MEMORY` / `TIMED-OUT` / `WITHIN-LIMITS`. It is a per-process watchdog, not a
  machine budget.

# THE GATES

Run `--help` before trusting a gate. The five verdicts, and their exits, are in
`gates/gatekit.py`.

- **`checks/differ.py run|repro|snap`** — the graphcmp corpus: the CPython-vs-port verdict
  per graph, canonical byte identity, controls, plants, conflation checks.
  `measure:` `head -3 runs/graphcmp/D/D0-run-summary.txt` and
  `cat runs/graphcmp/D/D1-verdicts.txt` (empty means every graph agrees).
  The oracle shell bodies are sha256-pinned in `differ.py`; the pin moves with a rename,
  in one commit, or not at all. `checks/README.md` names every artifact.
- **`gates/corpuswitness-gate.py`** — is the recorded verdict current and reproducible? It
  is seconds, and it is the only thing that may call a certificate established.
  `measure:` its `claim` row.
- **`checks/e2e.py` / `checks/e2e.sh`** — the end-to-end gate. Never run it on the real
  tree; stages 2-7 need `bend`, `node` and `cc`, so run it with nothing else compiling,
  under the RSS sum rule. A `SKIP` is not a `PASS`: the gate exits **4**, and that is the
  gate being honest. Do not rewrite it to tidy it.
- **`checks/substrate-check.sh`** — a shim onto `checks/substrate.py`: import graph and
  cold-file sweep over the `.bend` tree.
- **`gates/*.py`** — per-def gates. **Python, never shell.** A gate names its `.bend`
  driver and its CPython oracle; its output goes to `gates/artifacts/`.
  `measure:` `ls gates/*.py | wc -l` — if you quote a count, you must also say when you
  read it.
- **A gate's required input belongs beside the gate, in git** — never in `.agents/slop/`
  and never in `gates/artifacts/`, which is gitignored and is where runs write.
  A path inside a swept tree, or inside a gitignored output directory, is deletable while
  the gate still names it.
- **A gate that exits 0 having measured nothing is worse than no gate**, because it is
  trusted. Prefer `DEAD` to a zero.
- `gates/msgdiff-gate.py` checks a commit **message** against its own diff, and `REFUSED`
  (3) is not `FAIL`. `MESSAGE_DIFF_ACK=` records an explanation.

# GIT, AND THE INDEX

`jj` is colocated here, and **every `jj` command that snapshots stages the working copy
into git's index**. On this tree that is the standing hazard.

- **Stage by path. Never `git add -A`, and never `git add <dir>`** — a directory is not a
  path. An armed index turns either into other units' work inside your commit.
- Prefer **`git commit --only -m "msg" -- <path>`**: bounded by construction, no index
  seed, no window to lose. A **new** path needs `git add -- <path>` on the shared index
  first, then the `--only` form.
- `-m` goes **before** `--`; after it, `-m` is read as a pathspec and the commit silently
  does not happen.
- **Check `git show --stat` in the same command as the commit**, and run `git fsck
  --no-progress`. `--stat` answers "what changed"; `fsck` answers "is this commit
  malformed", and only the second blocks a push.
- **Never amend, never rebase.** Land a new commit. If someone else's commit reverted your
  bytes, re-land on top; never `reset` their commit.
- **`git status` is not a source of truth here.** 20k+ untracked paths under `.agents/slop/`
  are excluded locally; only tracked changes matter.

# THE TWO DOCTRINES

## 1. An instrument declares its population by discovery, or it is not a gate

A population is one of three things:

- **(a) a generator's own `declared()`, loaded by path** — e.g. `differ.declared()`, which
  `checks/no-txt.py` and `artefacts_ok()` both ask;
- **(b) a directory walk** — `os.walk` + `endswith`, because `glob('*.bend')` returns `[]`
  when `.bend` files are on disk;
- **(c) a regex over the tree's own write sites**, with the list admitted in a comment and a
  ledger so the edit is visible.

**A basename shape, a suffix set, and a hand list are not populations.** An instrument that
cannot see its population cannot be wrong, because it cannot be anything.
**Never list in this file what an instrument discovers.**

## 2. Five verdicts, and `DEAD` is the one nobody writes down

`PASS` every stage ran and agreed · `FAIL` it ran and got the wrong answer · `SKIP` it could
not run, so it measured nothing · `DEAD` it ran and emitted nothing · `REFUSED` a
precondition was absent.

- Exits are `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5` in `gates/gatekit.py`.
- **`SKIP` is not `PASS`**, and the exit status says so.
- **`DEAD` is not a zero and not a `PASS`.** "0 disagreements" over "0 comparisons" is
  indistinguishable from agreement.
- A shared exit number is not a shared vocabulary: shell gates and `gatekit` both exit 3
  for `REFUSED` and share no code.

# PYTHON

- `uv` and `ty` for packages and types.
- **Run Python through `.venv/bin/python`**, never bare `python`/`python3`: PATH's is 3.14
  with no `.pth`, `.venv` is 3.12 with the editable `tinygrad`, and a port oracle answers
  rows under one and `ModuleNotFoundError` under the other.
- `measure:` `.venv/bin/python -c 'import pytest, mypy'` — both are absent; install them
  with `uv` before using the commands below.
- Tests: `.venv/bin/python -m pytest test/null/test_dtype.py -x -q -n12`.
- Types: `.venv/bin/python -m mypy tinygrad/`.
- Lint: `ruff check .` (on PATH at `/opt/homebrew/bin/ruff`). The count is large and it
  moves while other units write; **quote it with a timestamp or not at all**.
- `./tinygrad/viz/README.md` explains profiling and rewrite rules.
- `ad117c928` is **ours**, not upstream: it re-vendored `tinygrad/` and broke a pin this
  tree cites. The pin is `ad117c928^`.
- tinygrad has userspace PCI drivers for AMD and NVIDIA. Do not insert kernel modules.

# TESTING

- **The harness that can fail comes first.** A test written after the code is a description
  of the code, not a check on it.
- **Prefer E2E**, and end it with a repeatable artifact.
- When testing a system in isolation, write down every way it can fail *before* the code.
- No tautological tests, no change-detector tests, and no regression test without a genuine
  gap in behaviour.
- **Inject time**; production code takes "now" as a parameter.
- **`test/` is upstream tinygrad's suite and is the oracle**, not our tests. It runs
  unchanged against the Bend build. A test that passes without exercising the Bend lanes is
  a change-detector.
- **Never quote a row count without the rule that produced it, and never from a job that may
  still be running.** Partial reads of in-flight runs have produced most of this project's
  false readings.

# WHAT A GOVERNING DOCUMENT MAY NOT CONTAIN

- A verdict. `gates/corpuswitness-gate.py` is the verdict; this file names it.
- A count without its command.
- A second copy of a list that a generator already owns.
- A number that a third party can move (a tag, a network answer, `~/.bend/check.json`).

# TINYGRAD FLAGS

The ones that matter are `DEBUG` and `VIZ`. `DEBUG` mocks hardware.

## Core UX

| Flag | Default | What it does |
| --- | --- | --- |
| `DEV` | `""` (auto) | Backend selection; `DEV=AMD:LLVM:gfx950`, `DEV=USB+AMD`. See `docs/env_vars.md` |
| `DEBUG` | 0 | 1=ops, 2=+mem/timings, 3=+applied opts, 4=+gen code, 5=+UOps, 6=+linearized, 7=+asm |
| `JIT` | 1 (2 on OSX/x86) | 0=off, 1=on, 2=on but device graphs off |
| `VIZ` | 0 | 1=record rewrites and open the viz UI (implies PROFILE) |
| `PROFILE` | VIZ | 1=enable profiling infrastructure |
| `SPEC` | 1 | UOp spec validation after rewrites. **Stay at 1.** `measure:` `checks/differ.py run` with `SPEC=2` and compare the reached-op census in `D0-ops-probe.txt`; do not remember a number. |
| `BEAM` | 0 | Beam search iterations for kernel optimization |
| `NOOPT` | 0 | 1=disable all kernel optimizations |
| `DEFAULT_FLOAT` | float32 | Default float dtype (HALF, BFLOAT16, FLOAT64) |
| `TRAINING` | 0 | 1=training mode (via `Context(TRAINING=1)`) |
| `IMAGE` | 0 | 1=2d-specific (image) optimizations |
| `FLOAT16` | 0 | 1=use float16 for images instead of float32 |
| `ALLOW_TF32` | 0 | 1=allow TensorFloat-32 on Ampere+ |
| `NO_COLOR` | 0 | 1=disable colored output |
| `CPU_COUNT` | host cores | Threads for CPU kernel launches |
| `MAX_BUFFER_SIZE` | 0 (lib default) | Cap individual buffer size in bytes |
| `ALLOW_DEVICE_USAGE` | 1 | 0=forbid opening devices (viz server) |

## Compiler & kernel search

| Flag | Default | What it does |
| --- | --- | --- |
| `JITBEAM` | BEAM | Beam level for kernels compiled inside the JIT |
| `IGNORE_JIT_FIRST_BEAM` | 0 | Skip beam on first JIT compile |
| `PARALLEL` | cpu count | Worker processes for beam search |
| `BEAM_ESTIMATE` | 1 | 1=score candidates by estimated runtime, 0=real launches |
| `BEAM_UPCAST_MAX` | 256 | Max upcast amount in candidates |
| `BEAM_LOCAL_MAX` | 1024 | Max local size in candidates |
| `BEAM_UOPS_MAX` | 3000 | Max uops allowed in a candidate kernel |
| `BEAM_TIMEOUT_SEC` | 10 | Abort beam after N seconds |
| `BEAM_MIN_PROGRESS` | 0.01 | Minimum estimated-improvement rate to continue |
| `BEAM_MAX_TASKS_PER_CHILD` | 16 | Recycle beam worker processes |
| `BEAM_PADTO` | 0 | Allow PADTO optimization in beam |
| `BEAM_STRICT_MODE` | 0 | Stricter candidate acceptance |
| `BEAM_DEV_TIMEOUT` | 1 | Per-launch device timeout during beam |
| `BEAM_DEBUG` | 0 | Beam search trace |
| `BEAM_LOG_SURPASS_MAX` | 0 | Log when candidates exceed limits |
| `IGNORE_BEAM_CACHE` | 0 | 1=ignore cached beam results |
| `CACHELEVEL` | 2 | Kernel cache level (0=no cache) |
| `CCACHE` | 1 | 0=disable the compiler cache |
| `SCACHE` | 1 | 0=disable the scheduler cache |
| `LRU` | 1 | 1=LRU eviction for the disk cache |
| `CACHEDB` | — | Disk cache database filename |
| `XDG_CACHE_HOME` | std | Base dir for the tinygrad cache |
| `DISABLE_HTTP_CACHE` | 0 | 1=never reuse `fetch()` downloads |
| `USE_TC` / `TC` | 1 | 0=disable tensor cores |
| `TC_SELECT` | -1 | Force a specific tensor-core candidate |
| `TC_OPT` | 0 | Tensor-core optimization level |
| `WINO` | 0 | 1=enable Winograd convolution |
| `TRANSCENDENTAL` | 1 | 1=force software transcendental decomposition |
| `NOLOCALS` | 0 | 1=disable local memory |
| `SPLIT_REDUCEOP` | 1 | 0=disable splitting large reduces into two kernels |
| `REDUCEOP_SPLIT_THRESHOLD` | 32768 | Min elements before reduce splitting applies |
| `REDUCEOP_SPLIT_SIZE` | 22 | Log2 cap on split reduce output size |
| `DISALLOW_BROADCAST` | 0 | 1=forbid broadcasting (catches hidden expands) |
| `DISABLE_FAST_IDIV` | 1 | 0=enable fast integer division |
| `USE_ATOMICS` | 0 | 1=allow atomics for embedding backward |
| `FUSE_OPTIM` | 0 | 1=fuse optimizer apply into the compute graph |
| `MAX_KERNEL_BUFFERS` | 0 | >0=split kernels with more than N buffers |
| `MV` | 1 | 0=disable matrix-vector tensor-core opt |
| `MV_BLOCKSIZE` | 4 | MV opt: block size |
| `MV_THREADS_PER_ROW` | 8 | MV opt: threads per row |
| `MV_ROWS_PER_THREAD` | 4 | MV opt: rows per thread |
| `OCCUPANCY_FLOOR` | 4096 | Skip local-group candidates below this global size |
| `ALLOW_HALF8` | 0 | 1=allow 8-wide half loads in memory coalescing |
| `ALIGNED` | 1 | 0=disable aligned vector loads in cstyle renderers |
| `DMC` | 0 | 1=skip memory coalescing pass |
| `UPAT_COMPILE` | 1 | 0=interpreted (slow) pattern matcher instead of compiled |
| `EXPAND_SSA` | 0 | SSA expansion toggle (dev knob) |

## Scheduler, JIT & graph

| Flag | Default | What it does |
| --- | --- | --- |
| `JIT_BATCH_SIZE` | 32 | Max kernels per JIT batch |
| `NO_MEMORY_PLANNER` | 0 | 1=disable buffer reuse by the memory planner |
| `PCONTIG` | 0 | 1=allow partial contiguous in rangeify |
| `DEBUG_RANGEIFY` | 0 | Rangeify debug output |
| `TUPLE_ORDER` | 1 | 1=tuplize linearizer sort order |
| `RING` | 1 | Ring allreduce: 0=off, 2=force |
| `ALL2ALL` | 0 | All-to-all allreduce: 1=on, 2=force |
| `ALLREDUCE_CAST` | 1 | 1=cast before allreduce |
| `RING_ALLREDUCE_THRESHOLD` | 256000 | Min elements to prefer ring/all2all for ndev>2 |
| `LATE_ALLREDUCE` | 1 | 0=do allreduce early instead |
| `GRAPH_ONE_KERNEL` | 0 | 1=allow single-kernel graph capture |
| `UNSAFE_ALLOW_JIT_BUFFER` | 0 | 1=allow capturing buffers during JIT (unsafe) |
| `REALIZE` | 0 | llm: realize weights at load |
| `HALF` | 1 | llm: cast loaded weights to float16 (0=keep dtype) |

## Debug, validation & dev infra

| Flag | Default | What it does |
| --- | --- | --- |
| `CHECK_OOB` | 0 | 1=check out-of-bounds in the PYTHON backend (slow) |
| `VALIDATE_WITH_CPU` | 0 | 1=validate every kernel's output against CPU |
| `ASSERT_COMPILE` | 0 | 1=assert on any device compile |
| `TYPED` | 0 | 1=typeguard runtime type checking on import |
| `DEBUG_LINEARIZE` | 0 | Print linearizer decisions |
| `DEBUG_GC` | 0 | GC debugging at exit |
| `DEBUGONNX` | 0 | ONNX parser debug |
| `ONNXLIMIT` | -1 | Parse only first N onnx nodes |
| `TRACE` | 0 | PYTHON backend: print every executed op |
| `PRINT_MATCH_STATS` | 0 | Print pattern-match counts per rewrite |
| `TRACK_MATCH_STATS` | 0 | Record per-rule match stats (pickle) |
| `CAPTURE_PROCESS_REPLAY` | 0 | Capture kernels for process-replay tests |
| `REWRITE_DATA` | — | Path to rewrites pickle for viz |
| `PROFILE_DATA` | — | Path to profile pickle for viz |
| `BROWSER` | — | viz: auto-open browser at this host |
| `PORT` | 8000 | viz server port |
| `NOSKIP` | 0 | AMD sqtt: don't skip decode categories |
| `TEST_PICKLE` | 0 | Dev knob for pickle testing |
| `DEVICE_IN_FUNCTION_BUG` | 0 | Dev knob reproducing a device-in-function bug |

## Device & runtime (cross-backend)

| Flag | Default | What it does |
| --- | --- | --- |
| `THREADS` | 1 | 0=single-threaded CPU renderers (llvmir/cstyle/x86) |
| `CC` | clang | C compiler for the CLANG backend |
| `LLVMOPT` | 1 | 0=disable LLVM optimization passes |
| `MM_DEBUG` | 0 | Memory-manager map/unmap trace |
| `GMMU` | 1 | 0=disable GPU MMU usage |
| `EMULATED_DTYPES` | "" | Dtypes to emulate (e.g. bfloat16) |
| `NULL_ALLOW_COPYOUT` | 0 | Allow copyout on the NULL device |
| `REMOTE` | "" | Comma-separated remote tinygpu PCIe devices |
| `APL_REMOTE_SOCK` | temp path | Socket path for remote device IPC |
| `REMOTE_TIMEOUT` | 60 | Remote device timeout |
| `VFIO` | 0 | 1=use VFIO for PCIe device access |
| `IOCTL` | 0 | 1=import the ioctl test harness (nv/amd/qcom/dsp) |
| `TINYFS_ENDPOINT` | localhost:6767 | tinyfs server address |
| `TINYFS_TIMEOUT` | 60 | tinyfs request timeout |
| `ASYNC_COPY_WORKERS` | 4 | tinyfs async copy pool size |
| `HCQ2` | 1 | Opt into the newer HCQ implementation paths |
| `HCQ_NUM_SDMA` | ≤8 | HCQ copy queue count |
| `HCQDEV_WAIT_TIMEOUT_MS` | 30000 | HCQ device wait timeout |
| `HCQ_VISIBLE_DEVICES` | — | Deprecated; errors with guidance |

## Backend-specific

| Flag | Default | What it does |
| --- | --- | --- |
| `CUDA_PATH` | /usr/local/cuda | CUDA headers location |
| `NV_DEBUG` | 0 | NV driver debug (≥4 dumps register writes) |
| `PMA_BUFFER_SIZE` | 512 (MiB) | NV PMA buffer size |
| `ROCM_PATH` | /opt/rocm | ROCm installation path |
| `AMD_AQL` | — | AQL packet path for AMD |
| `AMD_DISABLE_SDMA` | 0 | 1=disable AMD SDMA copy engines |
| `AMD_SDMA_BIND` | 0 | 1=bind SDMA queues to devices |
| `AMD_KFD_QUEUE_PRIORITY` | 7 | KFD queue priority override |
| `WAVES_PER_SH` | 0 | AMD: force waves-per-SH in COMPUTE_RESOURCE_LIMITS |
| `SQTT_BUFFER_SIZE` | 256 | AMD thread-trace buffer size |
| `SQTT_EVENT` | -1 | AMD: record only this sqtt event id |
| `MAX_SQTT_PKTS` | 50_000 | Cap decoded sqtt packets |
| `PMC_COUNTERS` | — | AMD performance counters to enable |
| `AM_DEBUG` | 0 | am (bare-metal AMD) debug level |
| `AM_RESET` | 0 | am: reset device at init |
| `AM_POWER_LIMIT` | 0.0 | am: cap power (fraction) |
| `MOCKDSP` | 0 | 1=use the mock DSP device |
| `QCOM_PRIORITY` | 8 | QCOM KGSL context priority |
| `FIX_METAL_ICB` | — | Metal indirect-command-buffer workaround |
| `WEBGPU_BACKEND` | auto | WebGPU native backend (Metal, Vulkan, ...) |
| `MLX_IP` | 10.0.0.1 | mlx (RDMA NIC) device IP |
| `EMULATE` | — | Deprecated; errors and points at `DEV=PYTHON::` |

## Optimizer / training knobs

| Flag | Default | What it does |
| --- | --- | --- |
| `SUM_DTYPE` | float32 | Accumulation dtype for sum reductions |
| `OPTIM_DTYPE` | float32 | Optimizer parameter dtype |
| `CONST_LR` | 0 | 1=scalar (unscheduled) learning rate |
| `BENCHMARK_LOG` | "" | llm: write benchmark events to this log |
| `OPENPILOT_HACKS` | 0 | Compatibility behaviors for openpilot models |
| `CAPTURING` | 1 | Internal: graph-capture state (dev knob) |
| `TRACEMETA` | 1 | Internal: include metadata in traces |
