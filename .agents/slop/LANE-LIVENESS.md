# LANE-LIVENESS.md — every gated lane, and whether it RAN the port

**One question, asked of every lane in this tree: does the gate compare a LIVE run of the port
against a LIVE call of the oracle, or does it compare two RECORDED FILES?**

Nobody had tabulated this. It decides how much of this tree is evidence.

All numbers here were produced by **running** things, not by reading a filename:
* `.agents/slop/liveness/measure39.py` — runs both sides of all 39 `BASE_ORACLES` lanes and
  reports port rows / oracle rows / shared names / disagreeing names / byte-identity, using
  `rebase-gate.py`'s **own** `row()`/`rows()` imported, never forked.
  Raw output: `.agents/slop/liveness/measure39.txt`.
* The plant/disarm matrix (§4) was run in a **copy** of the tree at
  `$TMPDIR/opencode/liveness/repo` (tinybendygrad + tinygrad + bin + .venv + .agents/slop,
  minus `.agents/slop/xd1`). **The live tree was never patched from a harness.** The copy's
  `.venv` editable-install finder was repointed at the copy, because `oracle_py.resolve()`
  refuses to run when the interpreter resolves `tinygrad` to another tree — and it should.

---

## 1. THE TWO NUMBERS, SIDE BY SIDE

| | count |
|---|---|
| **Lanes `BASE_ORACLES` enumerates** (the number everyone quotes) | **39** |
| **Of those 39, lanes whose port side and oracle side are BOTH live, in separate processes** | **37** |
| Of those 39, lanes that are live but whose **value comparison is a tautological zero** (the two sides print byte-identical stdout, so `disagree` compares a string with itself) | **7** |
| Of those 39, lanes that compared **ZERO** rows on either side (dead by wiring, not by design of the port) | **2** — `uop/ops.bend`, `dtype.bend` |

**THE GAP, NAMED: 39 enumerated − 37 that RAN = 2 lanes that have never run the oracle.**
`uop/ops.bend`'s oracle has raised `NameError` on every invocation since it was wired, and
`dtype.bend`'s port lane prints zero rows with exit 1. Both are counted in the 39.

**AND THE SHARPER NUMBER, WHICH IS THE ONE THAT MATTERS: 37 − 7 = 30.**
Of the 37 lanes that genuinely ran both sides, **7 print byte-identical stdout**, so their
`disagree` count is 0 *by construction* and the only live signal on them is the **byte diff**
plus the name-set guards. **30 of the 39 are lanes whose row-value comparison can actually
fail.** That is the honest denominator, and it is 9 fewer than 39.

`disagree` is **not** a coverage statement. Denominators, measured:

| measure | value |
|---|---|
| lanes enumerated (`BASE_ORACLES`) | 39 |
| lanes live on both sides | 37 |
| …of those, byte-identical (tautological value comparison) | 7 |
| …of those, a real value comparison | **30** |
| shared row names summed over all 39 (measured, not quoted from comments) | **7,809** |
| shared row names summed over the 7 byte-identical lanes | **1,408** |
| shared row names summed over the 30 real-value lanes | **6,401** |
| lanes RED at the moment of measurement | **1** — `codegen/decomp/dtype.bend`, row `c7` |

---

## 2. TABLE A — the 39 `BASE_ORACLES` lanes

`port side` is `LIVE` for **every one of the 39** by construction: `rebase-gate.py:733`
(`./bin/bend <port>`) and `:738-743` (`-o <bin>` then execute the binary). `oracle side` is
`LIVE` whenever the oracle script itself ran and emitted rows. All lanes are **cross-process**
(`rebase-gate.py:769` `subprocess.run`), so none of them measures a cache.

`byte-identical` = `port stdout == oracle stdout`, measured.

| # | port / comparison site | port side | oracle side | same PROCESS? | byte-identical? | verdict can change if the port's output changes? | verdict |
|---|---|---|---|---|---|---|---|
| 1 | `runtime/support/hcq2.bend` · `rebase-gate.py:962` GUARD 4 | LIVE interp+native | LIVE `hcq2-oracle.py` | no | no | **YES** | LIVE-VS-LIVE (157 shared, 0 disagree) |
| 2 | `runtime/ops_rdma.bend` · GUARD 4 | LIVE | LIVE `oracle_rdma_gate.py` | no | no | **YES** | LIVE-VS-LIVE (389/389) |
| 3 | `runtime/ops_nv.bend` · GUARD 4 | LIVE | LIVE `nv-oracle.py` | no | no | **YES** | LIVE-VS-LIVE (543/543) |
| 4 | `runtime/ops_metal.bend` · GUARD 4 | LIVE | LIVE `mt_seam_rows.py` | no | no | **YES** | LIVE-VS-LIVE (14/14) |
| 5 | `uop/ops.bend` · GUARD 4 | LIVE (319 rows) | **DEAD** `rebase-oracle-ops.py` | — | — | **NO — the lane dies before comparing** | **STUBBED · CANNOT-BE-MADE-LIVE** |
| 6 | `uop/spec.bend` · GUARD 4 | LIVE | LIVE `rebase-oracle-spec.py` | no | no | YES | LIVE-VS-LIVE (11/11) |
| 7 | `codegen/opt/search.bend` · GUARD 4 | LIVE | LIVE `rebase-oracle-search.py` | no | no | YES | LIVE-VS-LIVE (10/10) |
| 8 | `runtime/support/usb.bend` · GUARD 4 | LIVE | LIVE `usb-oracle-run.py` | no | no | YES | LIVE-VS-LIVE (939/939) |
| 9 | `schedule/prepare.bend` · GUARD 4 | LIVE | LIVE `prepare-oracle.py` | no | no | YES | LIVE-VS-LIVE (321/321 of 2 521 oracle rows) |
| 10 | `renderer/ptx.bend` · GUARD 4 | LIVE | LIVE `ptx-s3-oracle.py` | no | **YES** | only via the BYTE DIFF | **TAUTOLOGICAL** (281/281) |
| 11 | `renderer/tc_ptx.bend` · GUARD 4 | LIVE | LIVE `tcptx-oracle.py stage2` | no | no | YES | LIVE-VS-LIVE (228/228) |
| 12 | `renderer/nir_llvmir.bend` · GUARD 4 | LIVE | LIVE `nl/nl-oracle.py` | no | **YES** | only via the BYTE DIFF | **TAUTOLOGICAL** (205/205) |
| 13 | `viz/serve.bend` · GUARD 4 | LIVE | LIVE `vz/viz_oracle.py` | no | **YES** | only via the BYTE DIFF | **TAUTOLOGICAL** (176/176) |
| 14 | `runtime/support/c.bend` · GUARD 4 | LIVE | LIVE `c-oracle.py` | no | **YES** | only via the BYTE DIFF | **TAUTOLOGICAL** (129/129) |
| 15 | `uop/fold.bend` · GUARD 4 | LIVE | LIVE `mm-lift-gate.py` | no | no | **YES — plant-proven, §4 lane D** | LIVE-VS-LIVE (126/126) |
| 16 | `runtime/support/elf.bend` · GUARD 4 | LIVE | LIVE `elf_rows.py` | no | no | YES | LIVE-VS-LIVE (353/353) |
| 17 | `renderer/amd/sqtt.bend` · GUARD 4 | LIVE | LIVE `sqtt_spec.py` | no | no | YES | LIVE-VS-LIVE (1 015/1 015) |
| 18 | `renderer/amd/generate.bend` · GUARD 4 | LIVE | LIVE `ga-oracle.py` | no | no | YES | LIVE-VS-LIVE (726/726) |
| 19 | `nn/onnx.bend` · GUARD 4 | LIVE | LIVE `onnx-gate.py` | no | **YES** | only via the BYTE DIFF | **TAUTOLOGICAL** (123/123) |
| 20 | `mixin/elementwise.bend` · GUARD 4 | LIVE | LIVE `ew-gate.py` | no | no | YES | LIVE-VS-LIVE (71/71) |
| 21 | `mixin/op.bend` · GUARD 4 | LIVE | LIVE `mixin-op-gate.py` | no | no | YES | LIVE-VS-LIVE (32/32) |
| 22 | `tensor.bend` · GUARD 4 | LIVE | LIVE `tensor-gate.py` | no | no | YES | LIVE-VS-LIVE (30/30) |
| 23 | `codegen/simplify.bend` · GUARD 4 | LIVE | LIVE `xd1/rw-oracle.py` | no | no | YES | LIVE-VS-LIVE (28/28) |
| 24 | `nn/__init__.bend` · GUARD 4 | LIVE | LIVE `nn-init-gate.py` | no | **YES** | only via the BYTE DIFF | **TAUTOLOGICAL** (24/24) |
| 25 | `codegen/gpudims.bend` · GUARD 4 | LIVE | LIVE `xd1/rw-gate-oracle.py` | no | no | YES | LIVE-VS-LIVE (24/24) |
| 26 | `runtime/ops_cpu.bend` · GUARD 4 | LIVE | LIVE `cpulink_oracle.py` | no | no | YES, but only on **3** rows | LIVE-VS-LIVE (3 shared of 20 oracle rows) |
| 27 | `runtime/ops_python.bend` · GUARD 4 | LIVE | LIVE `ops-python-render-oracle.py` | no | no | YES | LIVE-VS-LIVE (59/59) |
| 28 | `runtime/ops_amd.bend` · GUARD 4 | LIVE | LIVE `amd_oracle.py` | no | no | YES | LIVE-VS-LIVE (409/409) |
| 29 | `uop/render.bend` · GUARD 4 | LIVE | LIVE `xd1/render-gate-oracle.py --gate` | no | no | YES | LIVE-VS-LIVE (85/85) |
| 30 | `renderer/llvmir.bend` · GUARD 4 | LIVE | LIVE `llvmir-oracle.py` | no | **YES** | only via the BYTE DIFF | **TAUTOLOGICAL** (470/470) |
| 31 | `runtime/ops_qcom.bend` · GUARD 4 | LIVE | LIVE `qcom-oracle.py` | no | no | YES | LIVE-VS-LIVE (312/312) |
| 32 | `schedule/indexing.bend` · GUARD 4 | LIVE | LIVE `indexing-oracle.py` | no | no | YES | LIVE-VS-LIVE (104/104) |
| 33 | `codegen/decomp/dtype.bend` · GUARD 4 | LIVE | LIVE `dtype-oracle.py` | no | no | **YES — and it is RED right now** | LIVE-VS-LIVE · **BROKEN, 1 of 109, row `c7`** |
| 34 | `schedule/rangeify.bend` · GUARD 4 | LIVE | LIVE `rangeify-oracle.py` | no | no | YES | LIVE-VS-LIVE (31/31) |
| 35 | `engine/jit.bend` · GUARD 4 | LIVE | LIVE `jit-oracle.py` | no | no | YES | LIVE-VS-LIVE (18/18) |
| 36 | `runtime/ops_null.bend` · GUARD 4 | LIVE | LIVE `null-oracle.py` | no | no | YES | LIVE-VS-LIVE (7/7) |
| 37 | `device.bend` · GUARD 4 | LIVE | LIVE `device-oracle.py` | no | no | **YES — plant-proven, §4 lane A** | LIVE-VS-LIVE (23/23) |
| 38 | `dtype.bend` · GUARD 4 | **DEAD — 0 rows, rc=1** | LIVE but emits TSV, 0 rows | — | — | **NO — 0 rows on both sides** | **STUBBED · dead by wiring** |
| 39 | `renderer/cstyle.bend` · GUARD 4 | LIVE | LIVE `renderer_oracle.py cstyle-rows` | no | no | YES | LIVE-VS-LIVE (224 shared / 221 by `cstyle-gate.py`) |

### The three findings Table A produced that were not in any file

**(a) `rebase-oracle-ops.py` has never run. `uop/ops.bend`'s lane is dead.**
`.agents/slop/rebase-oracle-ops.py:54` calls `importlib.util.spec_from_file_location(...)`,
and the file imports only `os, pathlib, subprocess, sys` at lines 34-37. Measured:
`NameError: name 'importlib' is not defined`, rc=1, zero stdout lines. `rebase-gate.py` reaches
GUARD 3 (`rebase-gate.py:911`) and returns BROKEN "lane(s) failed to run: cpython:rebase-oracle-ops".
The lane is counted in the 39 and its `BASE_ORACLES` comment claims `62` shared rows.
**Obstacle: `.agents/slop/rebase-oracle-ops.py:54`.** One line: `import importlib`.

**(b) `dtype.bend`'s port lane prints ZERO rows and exits 1, today.**
`./bin/bend tinybendygrad/dtype.bend` → `rc=1`, `lines=0`,
stderr `SOME PROOFS FAIL / Error: 14 defs rely on unsafe or foreign code: - Dt.bf16 …`.
`agent-core.md` records "the file run itself exits 0"; **measured, it does not, for this file.**
Both sides of the lane print 0 rows, so the lane compares nothing. `BASE_ORACLES` marks this
entry "deliberately dead", which is true of the ORACLE (TSV) but does not account for the
port lane also being dead.

**(c) `codegen/decomp/dtype.bend` is RED, reproducibly, on exactly one row.**
Measured twice, ~1 minute apart, identical both times:
port `c7=refused:unported` · oracle `c7=F(2139095040)`. 1 of 109 shared names.
`rebase-gate.py`'s own header (`:948-953`) records that a live disagreement must never be
reported as unrecorded; it is not — GUARD 4 fires before the baseline shortcut. **This is the
gate working.** Reporting it because a red lane nobody names is the failure being hunted.

### The tautological set, and what it costs

Seven of the 37 live lanes print **byte-identical stdout** on both sides:

`renderer/ptx.bend` (281) · `renderer/nir_llvmir.bend` (205) · `viz/serve.bend` (176) ·
`runtime/support/c.bend` (129) · `nn/onnx.bend` (123) · `nn/__init__.bend` (24) ·
`renderer/llvmir.bend` (470)

**1 408 shared rows across seven lanes whose `disagree` count is 0 by construction.**
Only `renderer/llvmir.bend` says so in its own header (`llvmir-gate.py:24-32`, and it names the
byte diff as the real gate). **The other six do not say it anywhere.** A reader of
`rebase-gate.py`'s output sees `7 lanes, 0 disagreements` on those six and has been told nothing.

Verified for llvmir directly: `./bin/bend tinybendygrad/renderer/llvmir.bend` and
`llvmir-oracle.py` (default argv, which is what `BASE_ORACLES` passes) both print 472 lines with
sha256 `258d7de0cf72f6bfe2c869d7…`. **The rebase-gate lane for llvmir is tautological too** —
that was only ever stated inside `llvmir-gate.py`.

---

## 3. TABLE B — the standalone `*-gate.py` / `*_gate.py` / `*-selftest.py` scripts

47 scripts under `.agents/slop/` and `.agents/slop/*/` (excluding two vendored
`.agents/slop/xd1/{head,pin}/test/.../test_rewrite_bottom_up_gate.py`, which are upstream
tinygrad's own tests, not this project's gates).

Legend: **DRIVER** = a script that runs both sides and compares. **EMITTER** = prints rows for a
`diff`; a gate only if something drives it. **ARTEFACT** = not a program.

| script | port side | oracle side | same PROCESS? | byte-identical? | can the verdict change with the port's output? | verdict |
|---|---|---|---|---|---|---|
| `rebase-gate.py` | LIVE (`run_port:733,738-743`) | LIVE (`run_port:769`) | no | 7 of 39 lanes | YES | **LIVE-VS-LIVE · the tree's real instrument** |
| `cstyle-gate.py` | **LIVE** (`cstyle-gate.py:555`) | **LIVE** (`:559`) | no | no | **YES — plant-proven §4 lane C** | **LIVE-VS-LIVE** (221 gated) |
| `cstyle-gate.py` capture mode (`:554`) | **RECORDED** `Path(a.port_stdout).read_text()` | RECORDED | n/a | n/a | NO — it says so, twice, on stdout (`:552`, `:564`) | RECORDED-VS-RECORDED, self-labelled |
| `llvmir-gate.py` | **LIVE** (`:467`) | **LIVE** (`:469`) | no | **YES (md5 `74e3e832`)** | **YES — plant-proven §4 lane B**; `disagree` alone cannot | **TAUTOLOGICAL** · byte diff is the gate |
| `llvmir-gate-noguard.py` | as above | as above | no | as above | as above | TAUTOLOGICAL |
| `nv_nvdev_gate.py` | **LIVE** (interp + native) | **LIVE** `nv_nvdev_oracle.py` | no | lanes compared byte-for-byte | **YES — plant-proven §4 lane F** | **LIVE-VS-LIVE** (799 gate rows / 2 176 oracle) |
| `dsl_gate.py` | **LIVE** (`dsl_gate.py:53`) | **RECORDED** — `ORACLE = ROOT/".agents/slop/dsl_oracle.txt"` (`:24`), mtime **Oct 2 22:48** | n/a | no | **YES on the port side — plant-proven**; **NO on the oracle side, ever** | **LIVE-VS-RECORDED** |
| `dtype-gate.py` | **RECORDED** — reads `.agents/slop/dt-bend.txt` unless `--write` (`:66`) | **RECORDED** — `.agents/slop/dt-py.txt` | n/a | no (1 declared deviation) | **NO — plant-proven §4 lane G** | **RECORDED-VS-RECORDED · reports GREEN over a wrong port** |
| `amdev_gate.py` | EMITTER → `amdev_gate.txt` | EMITTER → `amdev_py.txt` | n/a | n/a | only if re-recorded | EMITTER |
| `amdev_check.py` | **RECORDED** `amdev_interp.txt` (Oct 2 13:51) | **RECORDED** `amdev_py.txt` (Oct 2 13:08) + `amdev_gate.txt` | n/a | no | **NO** — runs nothing at all | **RECORDED-VS-RECORDED** · port side 1 day stale |
| `e2e_mm_gate.py` | **RECORDED** `runs/e2e/e2e-mm-bend.txt` (argv, 434 B) | **RECORDED** `e2e-mm-oracle.json` + `e2e-mm-gpu.json` | n/a | n/a | **NO** — runs nothing | **RECORDED-VS-RECORDED** |
| `ga_gate.py` | **RECORDED** (`run.txt`, argv) | **RECORDED** `ga-oracle.txt` (`:54`) | n/a | no | only if re-recorded | RECORDED-VS-RECORDED (superseded: `BASE_ORACLES` #18 is live) |
| `opsbend_milestone_gate.py` | **RECORDED** (`rows.txt`, argv) | **RECORDED** `ops_bend-milestone-expected.txt` (`:27`) | n/a | no | **NO** | **RECORDED-VS-RECORDED** |
| `dsp2-gate.py` | **RECORDED** (argv[2]) | **RECORDED** (argv[1]) | n/a | no | only if re-recorded | RECORDED-VS-RECORDED |
| `rend_gate.py` | **RECORDED** (argv[1]) | **RECORDED** (argv[2]) | n/a | no | only if re-recorded | RECORDED-VS-RECORDED |
| `dup/dup-gate.py` | **RECORDED** (`--port PORT.txt`) | **RECORDED** (`--oracle ORACLE.txt`) | n/a | n/a | only if re-recorded | RECORDED-VS-RECORDED (a name-set guard over files) |
| `drift-gate.py` | interp LIVE (`:43`); native **CACHED** unless `-r` (`:54`) | **CACHED** unless `-r` (`:76`) | n/a | n/a | **only with `-r`** | **LIVE-VS-RECORDED by default** |
| `ansi_gate.py` | **LIVE** — `./bin/bend .agents/slop/ansi_probe.bend` (`:64`) | **LIVE** `ansi_oracle.py` (`:61`) | no | no | YES | LIVE-VS-LIVE |
| `cpulink_gate.py` | **LIVE** `ops_cpu.bend` | **LIVE** `cpulink_oracle.py` | no | no | YES (3 rows) | LIVE-VS-LIVE |
| `validate-gate.py` | **LIVE** | **LIVE** | no | no | YES | LIVE-VS-LIVE |
| `eq/nl-gate.py` | **LIVE** (`:429` fall-through) | **LIVE** | no | n/a | YES | LIVE-VS-LIVE |
| `eq/rn-gate.py` | **LIVE** (`:416`) | **LIVE** | no | n/a | YES | LIVE-VS-LIVE |
| `vz/vz_gate.py` | **LIVE** (`os.popen`/`os.system`) | **LIVE** `vz_oracle.py` | no | no | YES | LIVE-VS-LIVE · `--mutate` writes the port in place |
| `rebase-gate-selftest.py` | synthetic lanes + **two deliberately-dead REAL lanes** | — | — | — | n/a | selftest of the instrument |
| `cstyle-shapes-selftest.py` | RECORDED inputs | RECORDED | n/a | n/a | n/a | ARMED/RED control per row shape |
| `naming-gate-selftest.py`, `zero-selftest.py`, `mutanchor-writes-selftest.py` | — | — | — | — | n/a | instrument selftests |
| `naming-gate.py` | reads the port's `def` names | upstream tinygrad **LIVE** + `naming-gate-ledger` (RECORDED) | n/a | n/a | YES, on names not values | LIVE-VS-RECORDED (names only) |
| `mm-lift-gate.py` | EMITTER — but wired as `BASE_ORACLES` #15 | — | — | — | covered by `rebase-gate.py` | LIVE-VS-LIVE **through `rebase-gate.py` only** |
| `mm-gate.py`, `mm-bl-gate.py`, `mm-dt-gate.py`, `mm-walk-gate.py` | EMITTER | EMITTER | — | — | **NO automated driver exists** | **NOT A GATE · CANNOT-BE-MADE-LIVE** |
| `onnx-gate.py`, `ew-gate.py`, `mixin-op-gate.py`, `tensor-gate.py`, `nn-init-gate.py`, `oracle_rdma_gate.py` | EMITTER, but each is a `BASE_ORACLES` oracle | — | — | — | covered by `rebase-gate.py` | LIVE-VS-LIVE **through `rebase-gate.py` only** |
| `mixin-op-gate.sh`, `tensor-gate.sh`, `beautiful-mnist-gate.sh`, `debug-gate.sh`, `helpers-tc-gate.sh` | LIVE | LIVE | no (fresh process per level, by design) | no | YES | **LIVE-VS-LIVE · these are the drivers that make the emitters gates** |
| `beautiful-mnist-gate.py` | EMITTER | EMITTER | — | — | via `beautiful-mnist-gate.sh` | LIVE-VS-LIVE via the `.sh` |
| `state-gate.py`, `nn-gate.py` | EMITTER | EMITTER | — | — | **NO driver exists** | **NOT A GATE** |
| `dsp2-gate.py` (shape) | — | — | — | — | — | see above |
| `mm-dt-gate.py` | — | — | — | — | — | reads tinygrad from `TG_TREE` env, default `.` |
| **`nv_gate.py`** | **it WRITES the port.** `open(P,"w").write(src + GATE)` where `GATE = $TMPDIR/opencode/gate.bend` (`:8,19`) | — | — | — | **the gate body lives in a scratch dir** | **NOT A GATE · a mutator whose payload is in `$TMPDIR`** |
| **`tools/reorder-gate.py`** | **it REWRITES a `.bend`** (`open(path,'w')`, `:109`) | — | — | — | — | **NOT A GATE · a code-mover named `-gate`** |
| **`helpers-tc-gate.py`** | — | — | — | — | — | **NOT PYTHON. 199 lines of recorded `name=value` rows** (`trange_0_len=0`, `gc_bumped_ops=12`) — it is the *output* `helpers-tc-gate.sh` writes, because that script's output prefix is `GT=.agents/slop/helpers-tc-gate` and it writes `$GT.py`. A `.py` that is an artefact. |

---

## 4. THE PLANT / DISARM MATRIX — 6 lanes, plus one more because it is the sharpest

Method: mutate **a copy** of the port so its printed value changes, run the gate, restore.
Every plant is paired with a disarm (change something that cannot matter — an appended
comment) run on the same copy, because a red with no paired disarm proves nothing about where
the plant landed. **One of my own plants was vacuous and the gate correctly refused to move** —
reported below, because it is the trap this project keeps paying for.

| lane | PLANT (changes the port's output) | verdict moved? | DISARM | verdict moved? | ARMED? |
|---|---|---|---|---|---|
| **A · `device.bend` via `rebase-gate.py`** | `device.bend:348` `allowed`: `Bool.or(allow, …)` → `Bool.not(Bool.or(allow, …))` (copy) | **YES** — `AGREE-UNRECORDED` → `BROKEN`, `cause=DISAGREE [DEFECT]`, **9 of 110** shared names disagree, `allow_lower` `allow_py` `allow_disk` `allow_npy` `allow_metal` `allow_cpu` `allow_cpu_l` `allow_mixed` `allow_on` named | appended comment | **NO** — identical `AGREE-UNRECORDED`, 23 shared with CPython, 0 disagree | **ARMED** |
| **B · `renderer/llvmir.bend` via `llvmir-gate.py`** | `llvmir.bend:981` `r_lt("lt f32", S.single(), "float")` → `S.double()` | **YES** — port md5 `74e3e832`→`1bc05717`, `BYTE-IDENTICAL True`→`False`, `agree 470`→`469`, `disagree []`→`['lt f32']` | appended comment | **NO** — md5 `74e3e832`, `agree 470`, `disagree []` | **ARMED** (but see below) |
| **C · `renderer/cstyle.bend` via `cstyle-gate.py`** | `cstyle.bend:565` `type_map.base`: `Kv{"f32","float",` → `"flt"` | **YES** — `AGREE`→`BROKEN`, `agree 221`→`157`, **64 gated rows DISAGREE**, every one named | appended comment | **NO** — `agree 221`, `disagree []`, `AGREE` | **ARMED** |
| **D · `uop/fold.bend` via `rebase-gate.py`** | `fold.bend:3731` `mm.where`: lo bound `bnd.min` → `bnd.max` | **YES** — `UNCHANGED`→`BROKEN`, `cause=DISAGREE [DEFECT]`, **3 of 240** disagree, `lf_where1 lo` `lf_where2 lo` `lf_where3 lo` | appended comment | **NO** — `UNCHANGED`, 240 shared, 0 disagree | **ARMED** |
| **E · `renderer/amd/dsl.bend` via `dsl_gate.py`** | `dsl.bend:1734` `srow("names_count", nat_text(reg_names_n()))` → `"99"` | **YES** — `MISMATCH names_count / port 99 / oracle 32`; `mismatched 1503`→`1504` | appended comment | **NO** — `mismatched 1503` | **ARMED on the port, RECORDED on the oracle** |
| **F · `runtime/support/nv/nvdev.bend` via `nv_nvdev_gate.py`** | `nvdev.bend:1562` `nv_boot42_merext_lo` field index `0`→`1` (the exact transposition `b8897fd4` fixed) | **YES** — `DISAGREEMENTS 0`→`1`, `nv_boot42_merext_lo` named, `GATE PASS`→`GATE FAIL`, **rc 0→1** | appended comment | **NO** — `DISAGREEMENTS 0`, `GATE PASS`, rc=0 | **ARMED** |
| **G · `dtype.bend` via `dtype-gate.py`** (extra) | `dtype.bend:381` `i64_max_u case 32`: `H.i64_of_hi_lo(0, 4294967295)` → `(12345, 4294967295)` — a genuinely wrong answer | **NO — `14766 rows compared, 1 declared, 0 unexpected`, rc=0.** The live port lane now prints `u32 … 12345:4294967295` where the committed `dt-bend.txt` says `0:4294967295`, and the gate did not notice | appended comment | **NO** — same output | **DISARMED** |

### The plants that failed to move anything, and why

1. **My first plant on lane A was VACUOUS and the gate was right to ignore it.**
   I flipped `device_usage(False{}, "python:1")` → `device_usage(True{}, …)` at `device.bend:1326`.
   The port's stdout sha256 was **identical** before and after. `allowed(allow, ix) =
   Bool.or(allow, tag_of(head(ix)) != 0)` — and the second operand is already `True`, so
   `Bool.or(True, True)` and `Bool.or(False, True)` are the same answer. **The plant changed the
   source and not the output.** Had I read the unchanged verdict as "the gate is blind" I would
   have filed a false finding. This is `agent-core.md`'s "a memoized answer is measured by its
   cache" arriving as "an OR is not a function of its first argument".

2. **My first plant on lane E was a COMPILE ERROR, not a value change.**
   `nat_text(reg_names_n() + 1n)` is `write (a + b : Nat)` with no type annotation →
   `SOME PROOFS FAIL`, port prints 0 rows. `dsl_gate.py` reported
   `rows port=0 mismatched=1576` — red, but for the wrong reason. **`dsl_gate.py` has no
   zero-row guard**, so a dead port lane reads as "every single row mismatches". Red for the
   wrong reason is how a lane teaches a reader to ignore it. Re-run with a compiling value plant
   (lane E above) before trusting any `dsl_gate.py` number.

3. **Lane G did not move, and that is the finding.** See `CANNOT-BE-MADE-LIVE`.

### Lane B, read carefully: ARMED, and still tautological

The plant works: `disagree` went from a structural `[]` to a real `['lt f32']`, and the byte
diff opened. But the lane is currently **BROKEN for an unrelated reason** — one duplicated row
name `lt 1 ptr f32`, printed twice by *both* sides (the oracle's own source, `llvmir-oracle.py:647-648`).
So the plant moved the *counters*, not the *exit code*. The counters are the evidence; the
pre-existing DUPE is a separate defect that `llvmir-gate.py` reports correctly.

And a second, sharper thing fell out of lane B:

```
planted port row:   lt f32 = [double]   py=[float]
live oracle row:    lt f32 = [float]    py=[float]
STALE-LITERAL 0
```

**`STALE-LITERAL` is 0 while the port's own answer is wrong.** It compares the port's `py=`
*literal* against the oracle's *answer*; on this lane the literal is generated from the pin, so
it stays correct when the port's computation goes wrong. That is the documented intent
(`llvmir-gate.py:377-379`, `rebase-gate.py:425-435`) — but it means **`STALE-LITERAL` is not a
second reader of the port, and the `py=` column cannot see a wrong Bend value on any lane where
the literal was generated.** Only `cstyle-gate.py:421-425`'s STALE-LITERAL has a live `py=`
column to disagree with, because `renderer_oracle.py` prints the pin's reading into the row.

---

## 5. EVERY `CANNOT-BE-MADE-LIVE`, WITH THE OBSTACLE

| lane | obstacle | shortest honest path |
|---|---|---|
| `BASE_ORACLES` #5 `uop/ops.bend` | `.agents/slop/rebase-oracle-ops.py:54` uses `importlib` which is not imported (lines 34-37 import only `os, pathlib, subprocess, sys`) | add `import importlib`; the lane then runs and its claimed 62 shared rows become measurable |
| `BASE_ORACLES` #38 `dtype.bend` | port lane prints 0 rows, rc=1, `14 defs rely on unsafe or foreign code: Dt.bf16 …`; oracle `oracle/dtype_tables.py` emits TSV so `rows()` finds 0 | give the oracle a `name=value` row shape (it already prints the data) — then the port's zero rows become GUARD 2's real finding instead of a shared zero |
| `dtype-gate.py` (whole script) | `dtype-gate.py:66` runs the lanes only `if write or not (BEND_OUT and PY_OUT exist)`; both files are committed | always run both lanes and compare the fresh text; keep the committed files as a `--record` artefact |
| `dsl_gate.py` | `dsl_gate.py:24` `ORACLE = …/dsl_oracle.txt`; **and the recorded file is not reproducible** — `fixed_hilo=<…FixedBitField object at 0x10911a510>.hi,0` embeds a heap address, so re-recording it on any other process launch changes that row | run `dsl_oracle.py` as the lane; replace the `fixed_hilo` row with the field's VALUE, not its `repr` |
| `amdev_check.py` | `amdev_check.py:14-15` opens `amdev_interp.txt` / `amdev_py.txt` and runs nothing | make the check a driver: bend → temp, oracle → temp, then compare; the recorded dumps are 1+ day older than `amdev.bend` |
| `e2e_mm_gate.py` | `e2e_mm_gate.py:44-46, 246` reads `runs/e2e/e2e-mm-{oracle,gpu,bend}` | have the driver re-run the bend lane and re-run the oracle before comparing; `e2e-mm-bend.txt` is 434 bytes today |
| `opsbend_milestone_gate.py` | `opsbend_milestone_gate.py:27` `EXPECTED = …/ops_bend-milestone-expected.txt`; argv carries `rows.txt`, `PACKET.in`, `PACKET.out` | same: generate the three inputs in the run |
| `ga_gate.py`, `dsp2-gate.py`, `rend_gate.py`, `dup/dup-gate.py` | all take **file paths on argv**; none runs a lane | one wrapper that runs the lanes and calls the existing differ with temp paths — the differs are fine, the wiring is not |
| `drift-gate.py` (default invocation) | `drift-gate.py:54` and `:76` return `$TMPDIR/drift-gate-cache/*.txt` unless `-r` (`drift-gate.py:98`) | make `-r` the default, or key the cache on the port's sha256 so a stale entry cannot be read silently |
| `mm-gate.py`, `mm-bl-gate.py`, `mm-dt-gate.py`, `mm-walk-gate.py` | **no driver exists at all** — the docstrings are a manual `diff` recipe and there is no `mm-*-gate.sh` | one `sh` driver each, exactly as `mixin-op-gate.sh` already does for `mixin-op-gate.py` |
| `state-gate.py`, `nn-gate.py` | EMITTERs with no `.sh` and no `BASE_ORACLES` entry — the only recipe is a `diff` in the docstring | one `.sh` each |
| `nv_gate.py` | `nv_gate.py:8` `GATE = $TMPDIR/opencode/gate.bend`, `:19` appends it to `tinybendygrad/runtime/support/nv/nvdev.bend` | put the gate block in `.agents/slop/` (oracles live there, per `agent-core.md`) and make the script idempotent on a content hash rather than a sentinel row |
| `tools/reorder-gate.py` | it is a `.bend` **mutator** (`open(path,'w')`), not a comparison | rename it; a file called `-gate` that rewrites the port invites exactly this miscount |
| `helpers-tc-gate.py` | it is **not a program** — 199 lines of recorded rows, the *output* of `helpers-tc-gate.sh` (whose `GT=` prefix makes it write `$GT.py`) | point `helpers-tc-gate.sh`'s prefix at `.txt`; today a `.py` in the gate namespace is an artefact |
| `BASE_ORACLES` #26 `runtime/ops_cpu.bend` | not a liveness failure — a **denominator** failure: 3 shared of 20 oracle rows, and 17 of those are host `findlib_*` answers | already stated in the `BASE_ORACLES` comment; the honest number is 3 |

---

## 6. THE TWO NUMBERS, RESTATED AS THE GAP

```
39   lanes BASE_ORACLES enumerates            <- the number everyone quotes
37   of those, port side AND oracle side both LIVE, cross-process
 7   of those 37, port and oracle print BYTE-IDENTICAL stdout -> `disagree` cannot fail
30   of those 37, a row-value comparison that can actually fail
 1   lane RED at measurement time (codegen/decomp/dtype.bend, row c7)
 2   lanes that compared ZERO rows (uop/ops.bend, dtype.bend)
```

**39 − 37 = 2 lanes that have never run.**
**37 − 7 = 1 408 rows whose green is structural rather than earned.**

The claim "39 lanes are gated" is true as a statement about *wiring* and false as a statement
about *evidence*. The defensible statement today is:

> **30 of the 39 wired lanes compare a live bend run against a live CPython call over rows whose
> values can differ. Seven more run both sides and are green only because both sides print the
> same bytes. Two have never run.**

---

## 7. WHAT I DID NOT DO, AND WHY

* **No row parser was audited.** `rebase-gate.py:rows()` / `row()` are the reader unit's; I
  **imported** `row`/`rows` (`measure39.py`) instead of forking them. All the numbers above come
  from the shipped reader, so they cannot disagree with the gate by construction.
* **No `.bend` under `tinybendygrad/` was edited.** Every plant was applied to
  `$TMPDIR/opencode/liveness/repo/tinybendygrad/…` and restored from a pristine copy taken
  immediately before; the sha256 of every restored file is printed in the transcript.
* **Nothing committed.** Working copy only.
* `dtype.bend`'s 14 unfilled laws and the concurrent edits to `helpers.bend` recorded in
  `bend2-constraints.md` mean some row counts in Table A are **lower bounds**. Every
  `rebase-gate.py` run during §4 carried its own `STARVED` marker and says so.
* **The transcript of the six plant/disarm pairs is in
  `.agents/slop/liveness/plant-transcript.md`**, including every restored file's sha256.