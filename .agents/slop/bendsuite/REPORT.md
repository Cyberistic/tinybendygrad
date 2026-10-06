# The first unbounded oracle for `Device['BEND']`

**Measured 2026-10-06, ~13:2x–14:5x, by a single `bend` unit, from
`/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`.**

Before this run, `DEV=BEND` appeared nowhere in the tree and `pytest` was not in `.venv`: every green
result was green on a **curated 25-graph corpus**. This report is the first time the port was asked
upstream's own questions.

## Verdict, in the five words

`test/null/` under `DEV=BEND` is **not a PASS and not a clean FAIL — it is a mix**:

| verdict | meaning here | count (denominator) |
|---|---|---|
| **PASS** | test ran under BEND, agreed | **946 / 1082** measured |
| **FAIL** | ran, wrong answer or wrong exception | **38 / 1082** (25 device-independent, **13 the port's**) |
| **DEAD** | could not import → emitted no tests | **11 files** (missing modules) |
| **SKIP** | the executor is too slow to reach them | **10 files, 349 collected** |
| **REFUSED** | the port's own dtype wall (`NotImplementedError`) | **13 tests** (subset of the 38 FAILs) |

And a headline: **`Device['BEND']` works.** 946 tests executed on it and agreed. The 0-of-232 kind of
disaster did **not** happen — this is a wiring-present, numerics-correct device with a **speed** wall.

---

## 1. What was installed, and how (reproducible)

`.venv` is Python 3.12.10 with **7 packages** and **no `pip` module**. Installed with `uv`:

```
uv pip install --python .venv/bin/python pytest
```

Resolved and installed **5 packages**:

```
+ iniconfig==2.3.0
+ packaging==26.3
+ pluggy==1.6.0
+ pygments==2.21.0
+ pytest==9.1.1
```

Network was used **only** for this. `numpy 2.5.3` was already present. `torch`, `z3`, `hypothesis`,
`tqdm`, `openai`, `jinja2` are **absent** — that is the source of every DEAD file below, and it is why
the denominator is 1431 and not larger.

## 2. The smallest self-contained upstream test, under `DEV=BEND`

```
DEV=BEND .venv/bin/python -m pytest test/null/test_dtype.py -q -p no:cacheprovider -rA
```

**10 collected · 9 passed · 1 failed · 0 errored · 0 skipped · 0 xfailed** (rc=1, 0.3 s).

The first and only failure, verbatim:

```
___________________________ TestEqStrDType.test_strs ___________________________

    def test_strs(self):
>     self.assertEqual(str(dtypes.float32), "dtypes.float")
E     AssertionError: 'dtypes.f32' != 'dtypes.float'
E     - dtypes.f32
E     ?         ^^
E     + dtypes.float
E     ?         ^^^^

test/null/test_dtype.py:7: AssertionError
```

**CONTROL, `DEV=CPU` on the same file: 10 collected · 9 passed · 1 failed · 0 errored · 0 skipped —
byte-identical failure.** So this is **not the port's**: it is an upstream test written against a
tinygrad whose `DType.name` was `"float"`; the vendored tree was renamed to `"f32"` (see the note in
`tinygrad/runtime/ops_bend.py:96-99`). The rename broke the test, on every device.

## 3. `test/null/` whole — it cannot be run whole under BEND, and why

The documented whole-suite sweep is unusable because **`conftest.py` installs a per-test wall-clock
watchdog** (`faulthandler.dump_traceback_later(int(os.getenv("TEST_TIMEOUT", 180)), exit=True)`) that
kills the **entire pytest process**, taking every test after it down. Under BEND one compute test
always exceeds it, so a whole-suite run reports nothing about the tests behind the first slow one.

The reason the first slow one is slow is measured, not guessed.

### The executor's cost (smallest reproduction, no tinygrad in the loop)

`tinygrad/runtime/ops_bend.py:executor()` compiles `tinybendygrad/runtime/ops_python.bend` **once** into
`~/Library/Caches/tinygrad/bend-executor-<hash>` (a 577,600-byte **Mach-O arm64**), then every kernel
launch is `subprocess.run([that binary, packet, gx, gy, gz, ...])`. Per-element cost, `/usr/bin/time -p`
on the saved packets:

| elements | user CPU |
|---|---|
| 16 | 2.82 s |
| 256 | 3.07 s |
| 4096 | 12.33 s |

Fit: **≈ 2.8 s fixed startup + ≈ 2.4 ms/element ⇒ ≈ 420 elements/second.** `Tensor.ones(256,256)`
(65,536 elements) is therefore **> 2.5 minutes of CPU for one kernel**, and `test_arange.py`'s
`test_tri_complexity` — a 256×256 `triu` — died against the 180 s watchdog exactly there.

Smallest reproduction (writes nothing outside `.agents/slop/bendsuite/`):

```
DEV=BEND .venv/bin/python -u .agents/slop/bendsuite/time_launch.py 64
#  [launch 0] executor 20.2s rc=0 nlines=19      # 4096-element fill
```

### Was `bend` invoked? Yes — once, to build the executor.

Pointing the cache at a fresh directory and running one trivial add:

```
XDG_CACHE_HOME=$PWD/.agents/slop/bendsuite/freshcache DEV=BEND .venv/bin/python -c \
  "from tinygrad import Tensor; print((Tensor([1.0,2.0])+Tensor([3.0,4.0])).tolist())"
```

produces `freshcache/tinygrad/bend-executor-970cbc1d5f288c9a` plus `freshcache/bun/@t@/*.pile`.
`bin/bend` is a shim → `bun references/bend/bend2/main.ts`. So the `bend` compiler is invoked **once per
`ops_python.bend` revision**; every launch after that runs the cached Mach-O directly. Across the entire
sweep, `bend` was invoked **zero further times**.

## 4. The per-file sweep (the real denominator)

Because one slow test kills a whole-file run, the suite was run **one file per pytest process**, bounded
at 90 s/file with `TEST_TIMEOUT=72`. The population is **discovered** (`os.walk test/null` for
`test_*.py`) — never a hand list. Driver: `.agents/slop/bendsuite/sweep.py`; raw output in
`.agents/slop/bendsuite/bend/*.out`; ledger `.agents/slop/bendsuite/sweep-bend.tsv`.

**83 files discovered · 1431 tests collected.**

| group | files | collected | passed | failed | errored | skipped | xfailed |
|---|---|---|---|---|---|---|---|
| **ran to completion** | **73** | **1082** | **946** | **38** | **30** | **70** | **9** |
| measured nothing | 10 | 349 | — | — | — | — | — |

Of the 1082 measured tests: 946 passed + 38 failed + **19 errored at runtime** + 70 skipped + 9 xfailed
= 1082. The other **11 errors are collection errors** (files that import a missing module, so 0 tests
were collected for them).

### Top three failure signatures by count (across all BEND output, `E`-lines, digits normalised)

| # | signature | count | whose |
|---|---|---|---|
| 1 | `ModuleNotFoundError: No module named 'openai'` | 12 | environment (device-independent) |
| 2 | `NotImplementedError: BEND v1 has no lane for dtypes.u8/u64/i64 (on PARAM/CAST/BITCAST)` | 15 (13 tests) | **the port's dtype wall** |
| 3 | `AttributeError: type object 'AxisType' has no attribute 'REDUCE'` | 9 | test/tree drift (device-independent) |

Runner-up device-independent drift: `AxisType.UNROLL` ×6, `'CustomFunction' object is not
subscriptable` ×6, `UOp.call() got an unexpected keyword argument 'ret_dtype'` ×2.

### The 10 files that measured nothing (a SKIP, not a zero)

| file | collected | why |
|---|---|---|
| test_assign.py | 5 | KILLED-BY-SWEEP (executor-bound) |
| test_linearizer.py | 9 | KILLED-BY-SWEEP (executor-bound) |
| test_schedule.py | 289 | KILLED-BY-SWEEP (executor-bound) |
| test_allreduce.py | 5 | faulthandler timeout |
| test_arange.py | 2 | faulthandler timeout |
| test_attention.py | 3 | faulthandler timeout |
| test_function.py | 8 | faulthandler timeout |
| test_real_world.py | 9 | faulthandler timeout |
| test_symbolic_tensor.py | 15 | faulthandler timeout |
| test_winograd.py | 4 | faulthandler timeout |
| **total** | **349** | |

A partial measurement of one of them, bounded explicitly: re-running `test_schedule.py` alone with a
600 s watchdog reached **74 / 289** (73 passed, 1 failed) and then hung on
`test_schedule.py:604 test_conv2d` — again a convolution, again the executor.

## 5. What the result IS

**`Device['BEND']` is working, and the failures it produces are refusals, not wrong answers.**

- **946 upstream tests pass on BEND.** Kernels execute and agree.
- **13 failing tests fail because the port refuses a dtype it does not implement.**
  `wire_dtype` (`ops_bend.py:99-101`) admits only `{int, uint, float, bool}` (i32/u32/f32/bool) and
  raises `NotImplementedError` otherwise. Every one of the 13 BEND-only failures is that raise, on
  `dtypes.u8` (10), `dtypes.u64` (3), `dtypes.i64` (2):
  `test_uops_stats.py::TestMemoryCount.{test_add,test_add_const,test_expanded,test_self_add,test_self_add_assign,test_self_add_transposed}`,
  `test_compile_failures.py::TestCompileFailures.{test_add_max_uchar,test_interpolate_atari}`,
  `test_mnist_dataset.py::TestDataset.test_dataset_is_realized`,
  `test_multitensor.py::TestMultiTensor.test_bn_ast_on_devices`,
  `test_transcendental.py::TestTranscendentalSchedule.test_transcendental_sin_fusion`,
  `test_uops.py::TestBitcastBufferView.test_render`,
  `test_uops.py::TestFastIdiv.test_fast_idiv_and_mod`.
  **No completed-file BEND-only failure is an `AssertionError`** — no silent wrong numerics were
  observed.
- **The 25 other failures, and all 30 errors, also fail under `DEV=CPU`** — they are missing modules
  (openai, jinja2, torch, z3, hypothesis, tqdm) and test/tree drift (`AxisType.REDUCE`/`UNROLL`,
  `CustomFunction` indexing, `UOp.call(ret_dtype=...)`, `hcq2.bufferize_cmdbuf`). **A test that fails on
  both devices has measured the test suite, not the port.**

**A 946-of-1082 that passes and a 13-refusal wall is a different country from 0-of-1431 that errors on
import.** The port is wired; its two limits are a **dtype wall** (u8/i64/u64) and an **executor that runs
at ~420 elements/second**, which makes the compute third of `test/null/` unreachable inside any sane
wall-clock bound.

## 6. Control: the same suite under `DEV=CPU`

```
DEV=CPU .venv/bin/python -m pytest test/null/ -q -p no:cacheprovider --continue-on-collection-errors -rfE
```

**1431 collected · 1294 passed · 28 failed · 74 skipped · 16 xfailed · 30 errors · 12 subtests passed in
190.45 s.** The 11 collection errors and the 19 `test_llm_server` setup errors are identical to BEND's.
Raw: `.agents/slop/bendsuite/null-cpu.out`.

## 7. Wall time, `bend` invocation, and tree writes

- **Wall time.** BEND per-file sweep: **969.1 s** summed across 83 files (plus a 1194 s
  `test_schedule` retry and a 181 s `test_arange` probe). CPU control: **190.45 s** for the whole suite.
  Wall times are **contaminated by concurrent load**: `uptime` read load averages of **35–54** from other
  units running on this machine throughout. **Pass/fail counts are unaffected; only the seconds are.**
- **`bend` invoked?** Yes, exactly once per `ops_python.bend` revision, to compile the executor (proved
  by the fresh-`XDG_CACHE_HOME` run in §3). Every kernel launch runs the cached Mach-O, not `bin/bend`.
- **Tree writes.** `git status` before vs after, excluding `.agents/slop/`: the only non-slop differences
  are three `tinybendygrad/*.bend` files that **other units committed** during the window and one
  `checks/substrate.py` **another unit** modified. **This unit wrote nothing outside
  `.agents/slop/bendsuite/`.** `runs/graphcmp/D/` is untouched (0 lines in `git status`), no
  `.pytest_cache` or `.hypothesis` was created, and no test artefact landed in `test/` or the root.

## 8. Reproduce

```
uv pip install --python .venv/bin/python pytest                    # §1
DEV=CPU .venv/bin/python -m pytest test/null/ -q -p no:cacheprovider \
    --continue-on-collection-errors -rfE                            # §6 control
.venv/bin/python .agents/slop/bendsuite/sweep.py BEND 90            # §4 per-file sweep
.venv/bin/python .agents/slop/bendsuite/analyze.py                 # §4 tallies + classification
.venv/bin/python .agents/slop/bendsuite/signatures.py              # §4 signature counts
DEV=BEND .venv/bin/python -u .agents/slop/bendsuite/time_launch.py 64   # §3 cost
```

Artifacts, all under `.agents/slop/bendsuite/`:
`REPORT.md` · `sweep.py` · `sweep-bend.tsv` · `sweep-bend.log` · `bend/*.out` (83) ·
`null-cpu.out` · `test_dtype-bend.out` / `.err` · `test_dtype-cpu.out` · `collect-bend.out` ·
`time_launch.py` · `analyze.py` · `signatures.py` · `pkt-{4,16,64}.in` · `git-status-before.rows`.

### One instrument defect in this run's own sweep (recorded, not hidden)

`sweep.py` reads only `e.stdout` when `subprocess.TimeoutExpired` fires, so the `faulthandler` traceback
(which conftest writes to a dup of fd 2) was dropped on the 3 `KILLED-BY-SWEEP` files; they are almost
certainly `FAULTHANDLER-TIMEOUT`s. Both verdicts mean **measured nothing**, so no count moved — but the
label on those three is the instrument's, not the port's.
