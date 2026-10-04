# env-flag semantic divergence -- findings, 2026-10-02

Owner: the env-flag audit unit. Files I edited: `tinybendygrad/helpers.bend` only.
Everything else is REPORTED with an owner named. No commit.

Reproduce the two measurements:

    uv run python .agents/slop/env-coercion-table.py > .agents/slop/env-coercion-table.txt
    uv run python .agents/slop/nocolor-oracle.py   > .agents/slop/nocolor-oracle.txt
    ./bin/bend .agents/slop/nocolor-probe.bend    > .agents/slop/nocolor-bend.txt
    uv run python .agents/slop/nocolor-diff.py

---

## 1. The count, first

| | |
| --- | --- |
| upstream `ContextVar` declarations | **61** (AST-counted; `helpers.py:236-290`, `device.py:18`, `uop/ops.py:1623-1624`, `hcq2.py:18`, `ops_nv.py:27`, `ops_amd.py:31-34`) |
| upstream bare `getenv("KEY", ...)` keys | **85** |
| distinct flags | **146** |
| flags the port reads | **4** (`NO_COLOR` `DEFAULT_FLOAT` `DEFAULT_INT` `SUM_DTYPE`) |
| of those, `ContextVar`s | **3** (`SUM_DTYPE` is a bare `getenv`, `dtype.py:223`) |
| flags named ANYWHERE outside a comment in the `.bend` tree | **15** |
| ... of which are real flag reads | **4** |
| ... of which are name COLLISIONS | **5** (`HALF`, `FLOAT16`, `DEV`, `TC`, `JIT`/`PROFILE`) |
| ... of which are walls with a `TODO(p3)` | **2** (`BNXT_DEBUG`, `OPTIM_DTYPE`) |
| **flags silently absent, no wall note, no read** | **131** |

`helpers.bend`'s comment claimed "~40 ContextVars". The real number is 61, so the
undercount is 21 and P6's scope as written is too small. Corrected in the file.

Of the 131 absent flags, most have a WALL NOTE naming them at the Python line
(`uop/ops.bend:1816` SPEC, `schedule/memory.bend:1515` NO_MEMORY_PLANNER,
`uop/fold.bend:850` DISALLOW_BROADCAST, `codegen/transcendental.bend:135`
TRANSCENDENTAL, `schedule/rangeify.bend:3104-3106` MAX_KERNEL_BUFFERS/VIZ/SPEC,
`mixin/rand.bend:172` TRAINING, `device.bend:325,717,778` ALLOW_DEVICE_USAGE /
MAX_BUFFER_SIZE / LRU, `codegen/opt/heuristic.bend:24-28` TC_MIN_GLOBALS,
`mixin/op.bend:414` SUM_DTYPE). Those are honest. The residue below is not.

---

## 2. DIVERGENCE SITES -- flag read by upstream, CONSTANT substituted by the port

Ordered by blast radius. "Verified" means measured against live CPython.

### D1. `tinybendygrad/helpers.bend:41-97` -- `no_color_of`, INVERTED. **MINE, FIXED.**

- flag: `NO_COLOR`, upstream `ContextVar("NO_COLOR", 0)` at `helpers.py:239`,
  consumed at `helpers.py:41` (`if NO_COLOR: return st`).
- port did: `no_color_of(v) = no_color_of.go(String.is_empty(v))`, i.e.
  `not String.is_empty(v)`, i.e. "any non-empty text switches colour off".
- upstream does: `bool(int(os.getenv("NO_COLOR", 0)))` -- the default is the `int` 0,
  so `getenv` coerces with **`int`**, not `bool`.
- diverges when: the value is any string `int()` reads as 0. MEASURED, 6 of them:
  `"0"`, `"00"`, `"-0"`, `"+0"`, `"0 "`, `" 0"` -- CPython leaves COLOUR ON, the
  port turned it OFF. Inverted, not merely absent. A second class: 12 strings CPython
  REFUSES (`"0x10"`, `"1.0"`, `"0.0"`, `".5"`, `"abc"`, `"false"`, `"True"`,
  `"no"`, `"off"`, `"nan"`, `"inf"`, `"1e3"`) make tinygrad unimportable, and the
  port answered True -- invented colour.
- before: **18 of 32 probes disagreed**. after: **0 disagree**, 18 exact, 13
  refusals-answered-False, 1 named boundary.
- the old comment asserted the OPPOSITE of the truth ("any text at all is truthy --
  NO_COLOR=0 does NOT switch colour off, and this reproduces that"). The conclusion
  was right by coincidence for `NO_COLOR=1` and wrong for `NO_COLOR=0`.

### D2. `tinybendygrad/mixin/dtype.bend:288` -- `DEFAULT_FLOAT` baked to float32. **OWNER: the mixin/dtype agent.**

```bend
case False{}: Some{strong_dtype(dt, di, S.single())}
```

- upstream `dtype.py:169-170`: `strong_dtype(dtype)` returns
  `dtypes.default_float` for `weakfloat`, and `dtypes.default_float` is
  `to_dtype(DEFAULT_FLOAT.value)`.
- `strong_dtype` in the port is ALREADY correct -- it takes `di` and `df` as
  parameters (`:252`, `:258`). Only the CALL SITE is wrong.
- **VERIFIED against live CPython**: `DEFAULT_FLOAT=float16` ->
  `strong_dtype(weakfloat)` is `dtypes.f16`; `=bfloat16` -> `bf16`; `=float64` ->
  `f64`. `least_upper_float(int16)` follows (`f16`/`bf16`/`f64`). The port answers
  `S.single()` in every case.
- the gate rows that pin it: `t_commit_weakfloat` (`:520`) and
  `t_commit_weakfloat_ignores_di` (`:523`). Mutation 4 in that file's table is
  literally "`strong_dtype`'s default_float is `half` not `single`" and moves exactly
  those two rows -- so the table already knows the value is a constant and calls it a
  mutation. **These two rows move together the day P6 lands.**
- fix shape: thread `df` the way `di` is threaded. `commit_dtype.of` already takes
  `di`; it needs the matching `df` parameter.

### D3. `tinybendygrad/runtime/support/hcq2.bend:282` -- `HCQ_CACHE_THRESH` baked to 64. **OWNER: the hcq2 agent.**

- upstream `hcq2.py:18` `ContextVar("HCQ_CACHE_THRESH", 64)`, consumed at
  `hcq2.py:535` as `use_rt = len(linear.src) < HCQ_CACHE_THRESH`.
- port: `def HCQ_CACHE_THRESH() -> U32: 64`, and `urow("hq2_cache_thresh",
  HCQ_CACHE_THRESH())` at `:1738` gates the constant.
- diverges when: `HCQ_CACHE_THRESH` is set to anything else. Every schedule with
  `len(linear.src) < thresh` flips between runtime-address patches and compile-time
  ones, which changes the cache key shape.
- second defect in the same three lines: the comment cites `:565` for the read; the
  read is at `:535`.

### D4. `tinybendygrad/runtime/support/system.bend:2221` -- `REMOTE_TIMEOUT` baked to 60. **OWNER: the system agent.**

- upstream `system.py:391` `socket.create_connection((host, port),
  timeout=getenv("REMOTE_TIMEOUT", 60))`.
- port: `def REMOTE_TIMEOUT() -> U32: 60`, gated by `urow("sy_remote_timeout",
  REMOTE_TIMEOUT())` at `:2966`.
- diverges when: `REMOTE_TIMEOUT` is set. A remote-device connect then gets a
  timeout the operator did not ask for.
- note the comment at `:2193` DOES quote the `getenv(...)` form, so the def's name
  is the only thing that hides it.

### D5. `tinybendygrad/runtime/support/rdma/bnxtdev.bend:222` -- `BNXT_DEBUG` baked to 0. **OWNER: the bnxtdev agent. Lower severity**: the read is a declared `TODO(p3)` at `:187`, so this def is the placeholder for it, and `urow("c_BNXT_DEBUG", BNXT_DEBUG())` at `:1430` gates the placeholder. Naming it here so it is not mistaken for a port.

### D6. `tinybendygrad/codegen/kernel.bend:795,798` -- the COUNT is right and the PROSE is wrong. **OWNER: the codegen/kernel agent.**

`cfg_len() -> 12` and `cfg_ctx_len() -> 14` are CORRECT (`codegen/__init__.py:509-511`
really is twelve flags and fourteen, and `*to_program_config, SPEC, DEBUG` is
fourteen). The header at `:773` says "ELEVEN ENV FLAGS" and `:786` says "THIRTEEN".
Separately, the twelve VALUES are a `# TODO(p3)` at `:792`, so the port's
`to_program_key` cannot distinguish two programs compiled under different flags --
a cache collision, invisible at default env.

---

## 3. FLAG-DERIVED GATE LITERALS -- the rows that all move at once when P6 lands

These are the rows that will move together on the day `Flags` grows. Naming them is
worth more than fixing them, because each is currently GREEN.

| row | file:line | encodes | flag |
| --- | --- | --- | --- |
| `commit_weakfloat` | `mixin/dtype.bend:520` | `S.single()` | `DEFAULT_FLOAT` |
| `commit_weakfloat_ignores_di` | `mixin/dtype.bend:523` | `S.single()` | `DEFAULT_FLOAT` |
| `hq2_cache_thresh` | `runtime/support/hcq2.bend:1738` | `64` | `HCQ_CACHE_THRESH` |
| `sy_remote_timeout` | `runtime/support/system.bend:2966` | `60` | `REMOTE_TIMEOUT` |
| `c_BNXT_DEBUG` | `runtime/support/rdma/bnxtdev.bend:1430` | `0` | `BNXT_DEBUG` |
| `amd_prof_slots_default` | `runtime/ops_amd.bend:1897` | `32` | `PROF_SLOTS` |
| `qc_flag_CONTEXT_PRIORITY_of_8` | `runtime/ops_qcom.bend:3471` | `8` | `QCOM_PRIORITY` |
| `red_c_on`/`_off`/`_a2`/`_a2f`/`_r2`/`_both` + `red_eq(red_mode(red_sel(red_sh1(256000), 4, red_c_on())), 0)` | `schedule/allreduce.bend:391-396,480` | `1,0,256000,0,True` | `RING`, `ALL2ALL`, `RING_ALLREDUCE_THRESHOLD`, `ALLREDUCE_NODE_NDEVS`, `ALLREDUCE_CAST` |
| `cfg_len`, `cfg_ctx_len` | `codegen/kernel.bend:795,798` | `12`, `14` | the twelve `to_program_config` flags (counts only) |
| `refused_parallel0` | `engine/worker.bend:623` | `PARALLEL == 0` | `PARALLEL` |
| (unnamed literal) | `engine/worker.bend:225` | `16` | `BEAM_MAX_TASKS_PER_CHILD` |
| `sd empty`, `sd emu long` | `renderer/__init__.bend:530-531` | `Nil{}`, `[S.int64()]` | `EMULATED_DTYPES` -- **this one is RIGHT**: `emu` is the parameter, so the two rows are two values of it |
| `op_lr_dtype(dflt)` | `nn/optim.bend:304,454` | parameterised, **but not gated** | `DEFAULT_FLOAT`, `OPTIM_DTYPE`, `CONST_LR` |
| `op_ok.tc(TC{any, sel, lvl, use}, ...)` | `codegen/opt/postrange.bend:868-888` | `TC{True{}, 0, 2, 1}` etc | `TC_SELECT` (-1), `TC_OPT` (0), `TC` (1) -- parameterised, so legitimate fixtures |
| `CFG{False{}, 1, 2, 256, 1024, 10, True{}}` | `codegen/opt/search.bend:171,174` | 256/1024/10 | `BEAM_UPCAST_MAX`, `BEAM_LOCAL_MAX`, `BEAM_TIMEOUT_SEC` -- parameterised, legitimate fixtures |

**`helpers.bend` has NO `main` and therefore NO gate at all.** So the file that owns
the flag machinery is the one file where a flag bug is completely ungated. That is
the gap I closed with `nocolor-probe.bend`.

No `py=` literal in any `.agents/slop/*oracle*.py` encodes a flag-controlled answer:
those oracles call CPython, and CPython reads the real environment, so a flag set in
the environment moves both sides together. The landmines are all in the `.bend`
`py=`/row literals listed above.

---

## 4. FALSE POSITIVES, and how they were filtered

The literal scan produced **396 candidate lines** (`.agents/slop/flag-literal-scan.txt`).
Every one was checked. Filtered:

1. **`HALF` in `runtime/support/usb.bend:535`** -- looked like a baked flag
   (`getenv("HALF", 262144)`) but `usb.py:208` is
   `HALF, CHUNK, SLOT = 0x40000, 0x40000 - 512, 0x4000`, a module CONSTANT. The
   `HALF` ENV flag is `llm/model.py:432`. Filtered by reading the Python line.
2. **`REDUCEOP_SPLIT_SIZE` -> `schedule/prepare.bend:365` `O.PMEntry{22, ...}`** --
   the 22 is a table INDEX, not the flag. And `sr_*` rows are not ported at all
   (`:933`). Filtered by reading the def.
3. **`SQTT_BUFFER_SIZE` (256) and `PMA_BUFFER_SIZE` (512) -> dozens of `ops_amd.bend`
   / `ops_nv.bend` / `ops_qcom.bend` register constants** -- 256 is `MEM_ALIGN_NEW`,
   512 is `M_SET_APPLICATION_ID`, 8 is `RM6_COMPUTE`, 32 is a wave size. All are
   hardware constants that happen to equal the flag's default. Filtered by name: the
   `def` names the register, not the flag.
4. **`AMD_KFD_QUEUE_PRIORITY` (7) -> `ops_amd.bend` `CALL_ALLOC`, `CKey`, `lru_take`
   rows** -- all unrelated uses of the number 7.
5. **`CACHELEVEL` (2) and `BEAM_LOCAL_MAX` (1024) -> 300+ lines across `device.bend`
   and `helpers.bend`** -- the number 2 is universal. This is why the literal scan
   skips defaults of 0 and 1 and why the two surviving hits were found by the
   `def <FLAG>()` shape instead.
6. **`FLOAT16` -> `nn/onnx.bend:337,391`** -- `FLOAT16 = 10` is the ONNX
   `TensorProto.DataType` enum member, not the flag. Filtered by name collision.
7. **`TC` -> `codegen/opt/postrange.bend:150`** -- a local `type TC is Data`, not the
   flag. `DEV` likewise.
8. **`PROFILE` -> `runtime/ops_cpu_null.bend:1939` `case 19: "PROFILE"`** -- a
   `PROFILE`-named operation in the null device's trace, not the flag.
9. **`PROF_SLOTS` (32) -> `ops_amd.bend`'s `prof_slot`/`sqtt_buf` rows** -- the count
   is a PARAMETER there (there are 32- and 4-slot rows side by side). Only
   `amd_prof_slots_default` at `:1897` pins the default as a bare literal. Kept, and
   the other 30 dropped.

**False-positive rate: 396 candidate lines -> 3 real substitution sites (D2/D3/D4),
plus D1 found by the `NO_COLOR` route rather than the literal scan. 99.2%.** The
reason the rate is that high is structural: a flag's default is a small integer and
small integers are everywhere, so the literal scan can only ever nominate; only
reading the Python line and the Bend def decides.

---

## 5. FILES FOUND WITH BUGS THAT I DID NOT EDIT

| file | what | owner |
| --- | --- | --- |
| `mixin/dtype.bend:288` | `DEFAULT_FLOAT` baked to `S.single()` (D2) | mixin/dtype agent |
| `mixin/dtype.bend:520,523` + mutation table row 4 | gate rows pin the baked value | mixin/dtype agent |
| `runtime/support/hcq2.bend:282`, `:280` | `HCQ_CACHE_THRESH` baked; comment cites the wrong Python line (D3) | hcq2 agent |
| `runtime/support/system.bend:2221` | `REMOTE_TIMEOUT` baked (D4) | system agent |
| `runtime/support/rdma/bnxtdev.bend:222` | `BNXT_DEBUG` placeholder baked (D5) | bnxtdev agent |
| `codegen/kernel.bend:773,786` | prose says ELEVEN/THIRTEEN, the rows say 12/14, and Python says 12/14 (D6) | codegen/kernel agent |
| `runtime/ops_amd.bend:1897` | `amd_prof_slots_default` pins `PROF_SLOTS`'s default | ops_amd agent |
| `runtime/ops_qcom.bend:3471` | `qc_flag_CONTEXT_PRIORITY_of_8` pins `QCOM_PRIORITY`'s default | ops_qcom agent |
| `helpers.bend:1480` (`IO.pure(Unit, Unit{})`) | unrelated, noted only because `helpers.bend` has no `main` | -- |

---

## 6. WHAT P6 NEEDS, GIVEN THE COERCION IS NOW PROVEN

`Flags` is a single record with `from_env` as the only seam, so P6 is mechanically
cheap. The three things it must get right, all measured:

1. **the coercion is `type(default)`, not `str`** (`helpers.py:162`). 51 of 61
   ContextVars have an `int` default. A port that stores the raw string and defers
   the `int` to a `Bool` will re-invert every one of them exactly as D1 did.
2. **`int()` REFUSES a bad value and tinygrad then does not import.** MEASURED:
   `DEBUG=true`, `NO_COLOR=`, `NO_COLOR=0.0`, `SPEC=1.5` all raise
   `ValueError: invalid literal for int() with base 10` at import. A total port must
   decide, and the only safe answer is the default (rule X).
3. **exactly three flags get the `bool` rule** -- `PMA`, `SQTT`, `PMC`, all
   `abs(VIZ.value) >= 2`. Everything else that "looks like a bool" is an `int`, and
   `int("0")` is False.

And the gate requirement that follows from D1: **every flag needs a gate row at a
NON-DEFAULT environment value.** A default-env gate cannot distinguish a correct
flag read from a baked default, and that is the whole failure mode.
