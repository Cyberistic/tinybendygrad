You are one of Cyberistic's agents. He hates unclean code and hacks. He loves his documentations. LOCs IS a measure of quality, the LESS, the better.

General:

- You must use concise, clean code. No hacks should be used. If you need to write a paragraph-long comment to justify your code, you are doing it wrong. Find a better way.
- Security is above all. Always make it secure (typesafe, fail-safe, auth), then make it work and effectful (effectjs), then make it fast, then make it pretty.
- Shareable logic should be reused. Avoid copy-pasting code. Hoist up if it's needed elsewhere.
- Use Jiujitsu version control for all your code. Make sure to commit often and write meaningful commit messages. If you launch multiple agents, use jiujitsu workspaces to manage them. If you are unsure about how to use Jiujitsu, ask for help. You have access to the jj mcp.
- If you need to create Markdown files to track agent state, always place them under .agents/slop/
- If I ask you to use a repo as reference, and it isn't tiny, you must clone it into `references/` and use it as a reference. Add the repo to `.gitignore` and link it under `references/` in your README.
- Whenever you finish a task, make sure to tick it off in .agents/TODO.md, If the task is not in TODO.md, add it there and check it off. Keep a progress bar inside TODO.md for each category of tasks. If it's an implementation detail or a small task, do not add it to TODO.md. Only add tasks that are meaningful and require tracking.
- Add TODO comments in the code for any tasks that are not yet completed, so we can use `rg` to search for TODO comments later on.
- Update .agents/TOOLS.md with the tools or libraries you're using, it will act as a ledger and overview for the project.

Development:

- No external dependancies. 
- Always stay turing-incomplete. Any turing completeness must be approved first. 


When using bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible



The gates at the top of the tree, and what each one CLAIMS. Run `--help` before trusting one:

- `checks/differ.py run` / `repro` / `snap` — the `graphcmp` corpus: CPython-vs-port VERDICT and
  DENOMINATOR per graph, canonical byte identity, controls, cross, plants, conflations, the
  coverage census, and (repro) that one run is reproducible. Artifacts in `runs/graphcmp/D`,
  read `D0-run-summary.txt` first; `checks/README.md` names every file. `graphcmp-run.sh` /
  `graphcmp-repro.sh` are shims onto it, and the shell bodies are the oracle in
  `.agents/slop/diffpy/`.
- `e2e.sh` — the 8-stage end-to-end gate, green. Do not rewrite it to tidy it.
- `substrate-check.sh` — import-graph and cold-file sweep over the `.bend` tree.
- `gates/*.py` — per-def gates, and they are **Python, never shell**. `.agents/slop/` is being
  pruned, so nothing new goes there. A gate names its `.bend` driver and its CPython oracle,
  which stay in `.agents/slop/` beside every other oracle; its OUTPUT goes to
  `gates/artifacts/`. The shared plumbing is `gates/gatekit.py` and it holds nothing but the
  three lanes, the row counts and the diff — the rows, the divergences and the pins are the
  gate's own. `gates/README.md` records why the shell form is retired, with the four ways a
  shell gate failed here (`&&` masking a diff under `set -e`; an `EXIT` trap returning `rm`'s
  status; `<( )` not parsing under `sh`; `${=SUB}` never expanding and a hash guard comparing
  `""` to `""`).


When using Python:
- use uv and ty
- Run tests with `-n12` for speed (e.g. `python -m pytest test/null/test_dtype.py -x -q -n12`)
- Run `python -m mypy tinygrad/` to typecheck
- Run `python -m ruff check .` to lint
- Read `./tinygrad/viz/README.md` for profiling and debugging rewrite rules
- Do not do amend commits. Always do a new commit if a force push to origin would be required.
- tinygrad has user space PCI drivers for AMD and NVIDIA GPUs. Do not insert the unneeded kernel modules.


Testing:

- NEVER write unit tests after you write code.
- Highly prefer E2E tests as the sole testing mechanism. Use them to verify complex features work. At the end of E2E tests, produce a verifiable and repeatable artifact.
- If you must test a system in isolation, FIRST write all the ways it could fail, THEN write the code.
- Tautological tests considered harmful.
- Change-detector tests considered harmful.
- Do not create regression tests for bug fixes without a genuine gap in behavior testing.
- Inject time instead of sleeping: production code needing "now" takes it as a parameter, so tests pass a deterministic value instead of faking timers. 


Tinygrad Flags

Most important ones are DEBUG and VIZ. You can mock hardware with DEBUG.


### Core UX

| Flag                 | Default          | What it does                                                                        |
| -------------------- | ---------------- | ----------------------------------------------------------------------------------- |
| `DEV`                | `""` (auto)      | Backend selection, `DEV=AMD:LLVM:gfx950`, `DEV=USB+AMD`, etc. See docs/env_vars.md  |
| `DEBUG`              | 0                | 1=ops, 2=+mem/timings, 3=+applied opts, 4=+gen code, 5=+UOps, 6=+linearized, 7=+asm |
| `JIT`                | 1 (2 on OSX/x86) | 0=off, 1=on, 2=on but device graphs off                                             |
| `VIZ`                | 0                | 1=record rewrites and open the viz UI (implies PROFILE)                             |
| `PROFILE`            | VIZ              | 1=enable profiling infrastructure                                                   |
| `SPEC`               | 1                | UOp spec validation level after rewrites (CI uses SPEC=2)                           |
| `BEAM`               | 0                | Beam search iterations for kernel optimization                                      |
| `NOOPT`              | 0                | 1=disable all kernel optimizations                                                  |
| `DEFAULT_FLOAT`      | float32          | Default float dtype (HALF, BFLOAT16, FLOAT64)                                       |
| `TRAINING`           | 0                | 1=training mode (used via `Context(TRAINING=1)`)                                    |
| `IMAGE`              | 0                | 1=2d-specific (image) optimizations                                                 |
| `FLOAT16`            | 0                | 1=use float16 for images instead of float32                                         |
| `ALLOW_TF32`         | 0                | 1=allow TensorFloat-32 on Ampere+                                                   |
| `NO_COLOR`           | 0                | 1=disable colored output                                                            |
| `CPU_COUNT`          | host cores       | Threads for CPU kernel launches                                                     |
| `MAX_BUFFER_SIZE`    | 0 (lib default)  | Cap individual buffer size in bytes                                                 |
| `ALLOW_DEVICE_USAGE` | 1                | 0=forbid opening devices (used by viz server)                                       |

### Compiler & kernel search

| Flag | Default | What it does |
|---|---|---|
| `JITBEAM` | BEAM | Beam level for kernels compiled inside the JIT |
| `IGNORE_JIT_FIRST_BEAM` | 0 | Skip beam on first JIT compile |
| `PARALLEL` | cpu count | Worker processes for beam search |
| `BEAM_ESTIMATE` | 1 | 1=score candidates by estimated runtime, 0=real launches |
| `BEAM_UPCAST_MAX` | 256 | Max upcast amount in candidates |
| `BEAM_LOCAL_MAX` | 1024 | Max local size in candidates |
| `BEAM_UOPS_MAX` | 1500 | Max uops allowed in a candidate kernel |
| `BEAM_TIMEOUT_SEC` | — | Abort beam after N seconds |
| `BEAM_MIN_PROGRESS` | — | Minimum estimated-improvement rate to continue |
| `BEAM_MAX_TASKS_PER_CHILD` | — | Recycle beam worker processes |
| `BEAM_PADTO` | — | Allow PADTO optimization in beam |
| `BEAM_STRICT_MODE` | — | Stricter candidate acceptance |
| `BEAM_DEV_TIMEOUT` | — | Per-launch device timeout during beam |
| `BEAM_DEBUG` | 0 | Beam search trace |
| `BEAM_LOG_SURPASS_MAX` | 0 | Log when candidates exceed uops/upcast/compute limits |
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
| `DISABLE_FAST_IDIV` | 1 | 0=enable fast integer division (marked broken for some indexing) |
| `USE_ATOMICS` | 0 | 1=allow atomics for embedding backward |
| `FUSE_OPTIM` | 0 | 1=fuse optimizer apply into the compute graph |
| `MAX_KERNEL_BUFFERS` | 0 | >0=split kernels with more than N buffers |
| `MV` | 1 | 0=disable matrix-vector tensor-core opt |
| `MV_BLOCKSIZE` | — | MV opt: block size |
| `MV_THREADS_PER_ROW` | — | MV opt: threads per row |
| `MV_ROWS_PER_THREAD` | — | MV opt: rows per thread |
| `OCCUPANCY_FLOOR` | 4096 | Skip local-group candidates below this global size |
| `ALLOW_HALF8` | 0 | 1=allow 8-wide half loads in memory coalescing |
| `ALIGNED` | 1 | 0=disable aligned vector loads in cstyle renderers |
| `DMC` | 0 | 1=skip memory coalescing pass |
| `UPAT_COMPILE` | 1 | 0=interpreted (slow) pattern matcher instead of compiled |
| `EXPAND_SSA` | — | SSA expansion toggle (rarely used; dev knob) |

### Scheduler, JIT & graph

| Flag | Default | What it does |
|---|---|---|
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

### Debug, validation & dev infra

| Flag | Default | What it does |
|---|---|---|
| `CHECK_OOB` | 0 | 1=check out-of-bounds in the PYTHON backend (slow) |
| `VALIDATE_WITH_CPU` | 0 | 1=validate every kernel's output against CPU |
| `ASSERT_COMPILE` | 0 | 1=assert on any device compile (no-compile enforcement) |
| `TYPED` | 0 | 1=typeguard runtime type checking on import |
| `DEBUG_LINEARIZE` | 0 | Print linearizer decisions |
| `DEBUG_RANGEIFY` | 0 | Rangeify debug output |
| `DEBUG_GC` | 0 | GC debugging at exit |
| `DEBUGONNX` | 0 | ONNX parser debug |
| `ONNXLIMIT` | -1 | Parse only first N onnx nodes |
| `TRACE` | 0 | PYTHON backend: print every executed op |
| `PRINT_MATCH_STATS` | 0 | Print pattern-match counts per rewrite |
| `TRACK_MATCH_STATS` | 0 | Record per-rule match stats (pickle) |
| `CAPTURE_PROCESS_REPLAY` | 0 | Capture kernels for process-replay tests |
| `REWRITE_DATA` | — | Path to rewrites pickle for viz (`--rewrites-path`) |
| `PROFILE_DATA` | — | Path to profile pickle for viz |
| `BROWSER` | — | viz: auto-open browser at this host |
| `PORT` | 8000 | viz server port |
| `NOSKIP` | 0 | AMD sqtt: don't skip decode categories |
| `TEST_PICKLE` | 0 | Dev knob for pickle testing |
| `DEVICE_IN_FUNCTION_BUG` | 0 | Dev knob reproducing a device-in-function bug |

### Device & runtime (cross-backend)

| Flag | Default | What it does |
|---|---|---|
| `THREADS` | 1 | 0=single-threaded CPU renderers (llvmir/cstyle/x86) |
| `CC` | clang | C compiler for the CLANG backend |
| `LLVMOPT` | 1 | 0=disable LLVM optimization passes |
| `MM_DEBUG` | 0 | Memory-manager map/unmap trace |
| `GMMU` | 1 | 0=disable GPU MMU usage |
| `EMULATED_DTYPES` | "" | Dtypes to emulate (e.g. bfloat16) |
| `NULL_ALLOW_COPYOUT` | 0 | Allow copyout on the NULL device |
| `REMOTE` | "" | Comma-separated remote tinygpu PCIe devices |
| `APL_REMOTE_SOCK` | temp path | Socket path for remote device IPC |
| `REMOTE_TIMEOUT` | — | Remote device timeout |
| `VFIO` | 0 | 1=use VFIO for PCIe device access |
| `IOCTL` | 0 | 1=import the ioctl test harness (nv/amd/qcom/dsp) |
| `TINYFS_ENDPOINT` | localhost:6767 | tinyfs server address |
| `TINYFS_TIMEOUT` | 60 | tinyfs request timeout |
| `ASYNC_COPY_WORKERS` | 4 | tinyfs async copy pool size |
| `HCQ2` | — | Opt into the newer HCQ implementation paths |
| `HCQ_NUM_SDMA` | ≤8 | HCQ copy queue count |
| `HCQDEV_WAIT_TIMEOUT_MS` | 30000 | HCQ device wait timeout |
| `HCQ_VISIBLE_DEVICES` | — | Deprecated; errors with guidance |

### Backend-specific

| Flag | Default | What it does |
|---|---|---|
| `CUDA_PATH` | /usr/local/cuda | CUDA headers location |
| `NV_DEBUG` | 0 | NV driver debug (≥4 dumps register writes) |
| `PMA_BUFFER_SIZE` | 512 (MiB) | NV PMA buffer size |
| `ROCM_PATH` | — | ROCm installation path |
| `AMD_AQL` | — | AQL packet path for AMD |
| `AMD_DISABLE_SDMA` | 0 | 1=disable AMD SDMA copy engines |
| `AMD_SDMA_BIND` | 0 | 1=bind SDMA queues to devices |
| `AMD_KFD_QUEUE_PRIORITY` | — | KFD queue priority override |
| `WAVES_PER_SH` | — | AMD: force waves-per-SH in COMPUTE_RESOURCE_LIMITS |
| `SQTT_BUFFER_SIZE` | — | AMD thread-trace buffer size |
| `SQTT_EVENT` | -1 | AMD: record only this sqtt event id |
| `MAX_SQTT_PKTS` | — | Cap decoded sqtt packets |
| `PMC_COUNTERS` | — | AMD performance counters to enable |
| `AM_DEBUG` | 0 | am (bare-metal AMD) debug level |
| `AM_RESET` | — | am: reset device at init |
| `AM_POWER_LIMIT` | 0.0 | am: cap power (fraction) |
| `MOCKDSP` | 0 | 1=use the mock DSP device |
| `QCOM_PRIORITY` | 8 | QCOM KGSL context priority |
| `FIX_METAL_ICB` | — | Metal indirect-command-buffer workaround |
| `WEBGPU_BACKEND` | auto | WebGPU native backend (Metal, Vulkan, ...) |
| `MLX_IP` | 10.0.0.1 | mlx (RDMA NIC) device IP |
| `EMULATE` | — | Deprecated; errors and points at `DEV=PYTHON::` |

### Optimizer / training knobs

| Flag | Default | What it does |
|---|---|---|
| `SUM_DTYPE` | float32 | Accumulation dtype for sum reductions |
| `OPTIM_DTYPE` | float32 | Optimizer parameter dtype |
| `CONST_LR` | 0 | 1=scalar (unscheduled) learning rate |
| `BENCHMARK_LOG` | "" | llm: write benchmark events to this log |
| `OPENPILOT_HACKS` | 0 | Compatibility behaviors for openpilot models |
| `CAPTURING` | 1 | Internal: graph-capture state (dev knob) |
| `TRACEMETA` | 1 | Internal: include metadata in traces |