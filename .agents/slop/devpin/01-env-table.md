# 01 — THE ENVIRONMENT-VAR TABLE: EVERY VARIABLE, AND WHETHER IT CAN MOVE A VERDICT

**147 flags, AST-counted off the tree, one subprocess each, two lanes. Reproduce:**

```
.venv/bin/python .agents/slop/devpin/envsweep.py
```

## THE TWO LANES, AND WHY ONE HASH WAS NOT ENOUGH

| lane | what it runs | what it hashes | question it answers |
|------|--------------|----------------|---------------------|
| **A** | in-process: `graphcmp.emit_py` over **all 25 graphs** (`hashall.py`) | sha256 over **row-shaped lines only** | *did the comparison's INPUT change?* |
| **B** | subprocess: `graphcmp.py emit --side py --graph lin`, **whole stdout** | byte count + a **non-row count** | *did the ARTIFACT change?* — this is byte-for-byte what `differ.py:452` writes into `D2-canon-py-lin.txt` |

**A SINGLE HASH CONFLATES THEM, AND I MEASURED THE CONFLATION RATHER THAN ASSUMING IT.**
My first sweep hashed lane B's whole stdout and reported `DEBUG=1`,
`DEBUG_LINEARIZE=1`, `DEBUG_RANGEIFY=1` as moving the rows. **They do not move a single
row.** They print to stdout, `differ.py:452` redirects the child's stdout straight into the
artifact, and the artifact therefore grows bytes that are not rows — which is still a
verdict-moving precondition (it breaks the byte-identity comparison) but is a **different
answer**, and naming it "the rows moved" would have been the `agree == total` error again.

Lane A cannot see contamination at all: `emit_py` **returns** the rows, so DEBUG's chatter
never enters it. MEASURED, `DEV=METAL DEBUG=1`:

```
4d950e585392… rows=311 nonrows=0        # the 311 real rows
opened device METAL from pid:88551      # ... printed by the subprocess, invisible to lane A
```

## RESULT — 8 of 147 CAN MOVE A VERDICT, 5 REFUSE, 128 CANNOT

### 8 MOVE — the only ones, and each with the evidence

| flag | lane A (inputs) | lane B (`D2-canon-py-lin.txt`) | measured effect |
|------|-----------------|-------------------------------|-----------------|
| **`DEV`** | **MOVES** `99bb94b1…`→`4d950e58…` rows 312→311 | **SAME** `2489B` | see §1 below — **the asymmetry is the whole finding** |
| **`IMAGE`** | MOVES `→8a36e849…` rows 312→**551** | MOVES `2489B`→`1619B`, rows 46→**29** | 2d-specific optimizations; **`lin` loses 17 rows** |
| **`NOOPT=1`** | MOVES `→2a13362a…` rows 312→311 | MOVES `2489B`→`2487B`, rows 46→**45** | kernel optimizations off — **this is the closest neighbour of the `lin` bug** |
| **`DEFAULT_FLOAT=bfloat16`** | MOVES `→001697ab…` rows 312→**433** | MOVES `2489B`→**8077B**, rows 46→**153** | every float dtype in the corpus becomes bfloat16; **the `lin` artifact triples** |
| `NO_COLOR=1` | MOVES `→609abc25…` | **SAME** | `graphcmp.py:2876-2878` already wraps the emit in `Context(NO_COLOR=1)`, so lane B is immune and lane A is not. **An already-fixed precondition still listed in the flag table.** |
| `DEBUG=1` | same | MOVES + `nonrows=1` | stdout contamination only |
| `DEBUG_RANGEIFY=1` | same | MOVES + `nonrows=13` | stdout contamination only |
| `MAX_BUFFER_SIZE=1` | same | MOVES + `nonrows=1` | stdout contamination only |

### 5 REFUSE — a flag that makes the side unbuildable is an answer, not a non-answer

| flag | measured failure |
|------|------------------|
| `DISALLOW_BROADCAST=1` | `RuntimeError: shape mismatch at Ops.MUL: [(4, 1, 3), (1, 5, 3)]` — the corpus itself stops being well-posed |
| `REWRITE_STACK_LIMIT=1` | `RuntimeError: infinite loop in graph_rewrite (stack too big)` |
| `SPEC=2` | crashes — **and AGENTS.md tells CI to run `SPEC=2`**, i.e. the corpus does not survive the flag the project itself recommends |
| `TEST_PICKLE=1` | `AttributeError: Can't get local object '…__wrapper'` |
| `REGEN=2` | `FileNotFoundError: llvm-config-20` |

### 128 CANNOT MOVE — measured inert, listed so the claim is checkable

`ALIGNED ALL2ALL ALLOW_DEVICE_USAGE ALLOW_HALF8 ALLOW_TF32 ALLREDUCE_CAST
ALLREDUCE_NODE_NDEVS AMD_AQL AMD_DISABLE_SDMA AMD_KFD_QUEUE_PRIORITY AM_DEBUG AM_POWER_LIMIT
AM_RESET ASSERT_COMPILE BEAM BEAM_DEBUG BEAM_DEV_TIMEOUT BEAM_ESTIMATE BEAM_LOCAL_MAX
BEAM_LOG_SURPASS_MAX BEAM_MAX_TASKS_PER_CHILD BEAM_MIN_PROGRESS BEAM_PADTO BEAM_STRICT_MODE
BEAM_TIMEOUT_SEC BEAM_UPCAST_MAX BEAM_UOPS_MAX BENCHMARK_LOG BNXT_DEBUG CACHEDB CACHELEVEL
CAPTURING CC CCACHE CHECK_OOB CONST_LR CUDA_PATH DEBUG_GC DEBUG_LINEARIZE DEFAULT_INT
DEVICE_IN_FUNCTION_BUG DISABLE_AMD_KERNELS DISABLE_FAST_IDIV DISABLE_HTTP_CACHE DMC EMULATE
EMULATED_DTYPES EXPAND_SSA FLOAT16 FUSE_OPTIM GMMU HALF HCQ2 HCQ_CACHE_THRESH HCQ_NUM_SDMA
HCQ_RUNTIME_DEV HCQ_VISIBLE_DEVICES IGNORE_BEAM_CACHE IGNORE_JIT_FIRST_BEAM IOCTL JIT JITBEAM
LATE_ALLREDUCE LLVMOPT LRU MAX_KERNEL_BUFFERS MAX_SQTT_PKTS MM_DEBUG MOCKDSP MV MV_BLOCKSIZE
MV_ROWS_PER_THREAD MV_THREADS_PER_ROW NOSKIP NO_HIPCC NO_MEMORY_PLANNER NULL_ALLOW_COPYOUT
NV_DEBUG OCCUPANCY_FLOOR ONNXLIMIT OPENPILOT_HACKS OPTIM_DTYPE PARALLEL PATH PMA PMA_BUFFER_SIZE
PMC PMC_COUNTERS PRINT_MATCH_STATS PROF_SLOTS PYTEST_XDIST_WORKER_COUNT QCOM_PRIORITY REALIZE
REDUCEOP_SPLIT_SIZE REDUCEOP_SPLIT_THRESHOLD REMOTE REMOTE_TIMEOUT RING
RING_ALLREDUCE_THRESHOLD ROCM_PATH SCACHE SPLIT_REDUCEOP SQTT SQTT_BUFFER_SIZE SQTT_EVENT
SQTT_ITRACE_SE_MASK SQTT_LIMIT_SE SQTT_SIMD_SEL SQTT_TOKEN_EXCLUDE SUM_DTYPE TC TC_MIN_GLOBALS
TC_OPT TC_SELECT TRACE TRACEMETA TRAINING TRANSCENDENTAL TUPLE_ORDER
UNSAFE_ALLOW_JIT_BUFFER UPAT_COMPILE USE_ATOMICS VALIDATE_WITH_CPU VFIO WAVES_PER_SH
WEBGPU_BACKEND WINO XDG_CACHE_HOME`

**SIX ARE EXCLUDED, EACH WITH ITS REASON, BECAUSE AN EXCLUSION NO CODE NAMES IS HOW A PIN
ROTS:** `VIZ` (opens a browser and a viz server), `PROFILE` (differ's dbg step sets DEBUG
explicitly with `--levels`), `BROWSER`/`PORT` (viz-only),
`CAPTURE_PROCESS_REPLAY` and `TRACK_MATCH_STATS` (write pickles to disk), `DEBUGONNX`
(parser-only, no ONNX in this corpus), `REWRITE_DATA`/`PROFILE_DATA` (viz path inputs).

**THE HEADLINE, AND IT CONTRADICTS THE PREMISE:** of the ~30 variables the job listed from
`AGENTS.md`, **only `DEFAULT_FLOAT`, `IMAGE`, `NOOPT`, `NO_COLOR`, `JIT`-family and `SPEC`
DO ANYTHING.** `BEAM`, `JIT`, `DEBUG`, `CPU_COUNT`, `MAX_BUFFER_SIZE`, `ALLOW_TF32`,
`TRANSCENDENTAL`, `CACHELEVEL`, `CCACHE`, `SCACHE`, `FLOAT16`, `WINO`, `USE_TC`,
`SPLIT_REDUCEOP`, `TRACEMETA`, `CACHELV`, `MAX_KERNEL_BUFFERS`, `MV`, `OCCUPANCY_FLOOR`,
`DISABLE_HTTP_CACHE` are **all measured inert on this corpus**. That is not because they are
harmless — it is because **the comparison only ever calls `schedule_linear` +
`full_rewrite_to_sink` on graphs it never realizes**, so the entire runtime/compiler flag
surface is downstream of a boundary this harness does not cross. **A PRECONDITION NOBODY
DECLARED IS A PRECONDITION NOBODY CAN AUDIT — BUT SO IS A FLAG LIST THAT ENUMERATES 147
NAMES AND MEASURES FIVE.**

## §1 THE ASYMMETRY THAT IS THE ACTUAL FINDING

**`DEV` MOVES LANE A AND NOT LANE B.** Not because the device does not matter — because
**`graphcmp.py:2853` `os.environ["DEV"] = a.dev` overwrites the ambient value inside every
subprocess the differ spawns, and `:2839` defaults `a.dev` to `"CPU"`.** So:

* `checks/differ.py` **IS** device-pinned, by an argument default in a file it does not own.
* `checks/corpus-figure.py:39-55` **IS NOT** — it imports `graphcmp.py` by path and calls
  `gc.load_tinygrad()` at `:51`, which never passes through `main()`, so `:2853` never runs.

```
$ for D in CPU NULL METAL PYTHON; do DEV=$D .venv/bin/python checks/corpus-figure.py; done
DEV=CPU     CPYTHON-SIDE UNION : 61 of 77
DEV=NULL    CPYTHON-SIDE UNION : 60 of 77
DEV=METAL   CPYTHON-SIDE UNION : 60 of 77
```

**SO THE PIN IS ALREADY THERE, IN ONE CONSUMER, AND NOT IN THE OTHER.** This is not a
missing precondition; it is a precondition that exists in one code path and not the next,
which is strictly harder to audit than one that exists nowhere.

## §2 THE FOUR SOURCES THE FLAG LIST IS BUILT FROM (none of them is `AGENTS.md`)

| source | count |
|--------|-------|
| every `ContextVar("KEY", …)` / bare `getenv("KEY", …)` / `os.environ["KEY"]` in `tinygrad/`, AST-counted | **147** |
| every key the **harness** writes: `differ.py`'s `ENV` + `graphcmp.py`'s `clean_env` | **1** — `DEV` |
| every **non-comment** `getenv` in the `.bend` tree — **what the PORT can read** | **4** — `NO_COLOR` `DEFAULT_FLOAT` `DEFAULT_INT` `SUM_DTYPE` (`tinybendygrad/helpers.bend:340-346`, `Flags.from_env`) |
| (the project already had this census: `.agents/slop/env-flag-divergence.md` §1 records 146 distinct flags, 4 read by the port, **131 silently absent from the port with no wall note**) | — |

**THE PORT READS FOUR FLAGS. THE PYTHON SIDE READS 147.** So the two sides of the
comparison do not share an environment contract at all, and no amount of pinning the *py*
side makes the pair symmetric. `.agents/slop/env-coercion-table.py` is the instrument that
regenerates the upstream half of this table; it is the ledger's own tool and it is not mine.
