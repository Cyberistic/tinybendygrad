# Pin vs xd1/head — wired-gate measurement

Measured 2026-10-03. Harness: `.agents/slop/pin-tree-oracle.py`. Snapshots: `runs/pin-tree-oracle/`. No port was edited. No live tree was patched.

The roster was **29** when the sweep started and **31** when it ended. Two gates were added by other units mid-run (`ops_python`, `ops_amd`); both were measured after they appeared. The brief said 28. The number below is the live `BASE_ORACLES` at the end of the sweep, not the brief's count.

**Decision input: 16 of 31 gates change verdict if every oracle is pointed at the pin `6c3d401cf324`.** Nine cannot run. Seven run and disagree with the port. In every disagreement the port matches the non-pin side.

## Trees, by blob, not by name

| tree | what it actually is |
|---|---|
| pin `6c3d401cf324` | `.agents/slop/xd1/pin` is this commit. `tinygrad/` **229/229 blobs, 0 differ**. |
| vendor `tinygrad/` | equals `origin/master`'s `tinygrad/` **230/230, 0 differ**. Differs from the pin on **25** files (the re-vendor list in `UPSTREAM-PIN.md`). |
| `xd1/head` | **not** a commit. `tinygrad/` vs `upstream/master` (`91b8cb5fa6c0`): **215 same, 14 differ**. |
| `opstree` | byte-identical to `xd1/head` (**229/229, 0 differ**). The ops and search oracles' default "upstream archive" is this snapshot, not current `upstream/master`. |

The 14 files where `xd1/head` ≠ `upstream/master`: `device.py`, `helpers.py`, `renderer/amd/generate.py`, `renderer/cstyle.py`, `runtime/ops_{amd,cuda,metal,null,nv,qcom,rdma}.py`, `runtime/support/hcq2.py`, `runtime/support/usb.py`, `uop/ops.py`.

### Claims re-checked by extract, then `wc`, then read

| file | pin | origin/master | upstream/master | xd1/head | vendor |
|---|---|---|---|---|---|
| `uop/render.py` blob | `9728ba6bf5` | `9728ba6bf5` | `dc14f26c72` | `dc14f26c72` | `9728ba6bf5` |
| bytes | 10808 | | 10577 | 10577 | 10808 |
| `AddrSpace` count | 2 | 2 | 0 | 0 | 2 |
| `axis_id[0]` count | 0 | 0 | 2 | 2 | 0 |
| `uop/ops.py` blob | `3ffac84bef97` | `2c686da7e21e` | `2c686da7e21e` | `6f7b9996431e` | `2c686da7e21e` |
| `CustomFunction` | 0 | 3 | 3 | 3 | 3 |
| `CallInfo` dtype clause | yes | no | no | no | no |

Pin is an ancestor of `upstream/master` (`git merge-base --is-ancestor` yes). Three commits after the pin touch `render.py` (`e78671eb6`, `78d482262`, `2394504c7`). So xd1/head's `render.py` does **not** predate `AddrSpace`. It equals current upstream, which deleted the import. "Matches neither the pin nor origin/master" is true. "Matches neither HEAD" is false if HEAD means `upstream/master`.

`xd1/head`'s `ops.py` (`6f7b9996431e`) matches **neither** the pin nor `upstream/master`, and it does have `CustomFunction` (3) and lacks the dtype clause. The checkout is inconsistent: `render.py` is upstream, `ops.py` is a third blob.

Claim "pin and origin agree on `render.py`, so pin and HEAD agree" is half true. Pin and origin agree (`9728ba6bf5`). Pin and upstream do not (`dc14f26c72`).

## How an oracle selects a tree

Measured, not read off a comment.

`.venv/bin/python` from `/tmp`, `env -u PYTHONPATH`, imports `tinygrad/__init__.py` in the repo. The editable finder is appended **after** `PathFinder` (`meta_path[4]`). So:

- no `sys.path` hit → editable fallback → vendor
- `sys.path.insert(0, <root>)` before the import → PathFinder wins → that root

System `python3` from `/tmp` raises `ModuleNotFoundError`. `sys.path[0]` is the **script directory**, not cwd. `rw-oracle.py` lives in `xd1/`, which has no `tinygrad` package, so a system-python run of it cannot import tinygrad at all. The sweep used `.venv/bin/python`, which is what `rebase-oracle-ops.py` hardcodes for its child and what the oracle docstrings name.

The gate (`rebase-gate.py` `run_port`) does `env=dict(os.environ, DEV="NULL")`. It does **not** set `PYTHONPATH` or `TG_TREE`. A caller's `PYTHONPATH` would contaminate it. This sweep unset both.

Forced runs install a `meta_path[0]` finder via `sitecustomize` so a child process is forced too. The finder wins over `--gate`'s own `sys.path.insert` of `xd1/head`. Proven by the plant below.

## Per-gate table

Verdict is GUARD 3, then 2, then 4, against the interpreted bend lane only (no baseline, no native). `AGREE` = exit 0, shared names, values match the port. `DISAGREE` = shared names, values differ. `BROKEN` = nonzero exit, zero `name=value` rows, or no shared name.

Natural tree is the tree the import log recorded when the oracle was run the way the gate runs it.

| port | oracle | natural tree | natural | pin | xd1/head | flips |
|---|---|---|---|---|---|---|
| `runtime/support/hcq2.bend` | `hcq2-oracle.py` | vendor | AGREE | BROKEN | AGREE | yes |
| `runtime/ops_rdma.bend` | `oracle_rdma_gate.py` | vendor | AGREE | AGREE | AGREE | |
| `runtime/ops_nv.bend` | `nv-oracle.py` | vendor | AGREE | BROKEN | AGREE | yes |
| `runtime/ops_metal.bend` | `mt_seam_rows.py` | vendor | AGREE | AGREE | AGREE | |
| `uop/ops.bend` | `rebase-oracle-ops.py` | **opstree** (= xd1/head) | AGREE | DISAGREE | AGREE | yes |
| `uop/spec.bend` | `rebase-oracle-spec.py` | vendor | AGREE | DISAGREE | AGREE | yes |
| `codegen/opt/search.bend` | `rebase-oracle-search.py` | child **opstree**, parent also vendor | AGREE | DISAGREE | AGREE | yes |
| `runtime/support/usb.bend` | `usb-oracle-run.py` | vendor | AGREE | AGREE | AGREE | |
| `schedule/prepare.bend` | `prepare-oracle.py` | vendor | AGREE | BROKEN | AGREE | yes |
| `renderer/ptx.bend` | `ptx-s3-oracle.py` | vendor | AGREE | BROKEN | AGREE | yes |
| `renderer/tc_ptx.bend` | `tcptx-oracle.py stage2` | vendor | AGREE | BROKEN | AGREE | yes |
| `renderer/nir_llvmir.bend` | `nl/nl-oracle.py` | vendor | AGREE | BROKEN | AGREE | yes |
| `viz/serve.bend` | `vz/viz_oracle.py` | vendor | AGREE | AGREE | AGREE | |
| `runtime/support/c.bend` | `c-oracle.py` | vendor | AGREE | AGREE | AGREE | |
| `uop/fold.bend` | `mm-lift-gate.py` | vendor | AGREE | BROKEN | AGREE | yes |
| `runtime/support/elf.bend` | `elf_rows.py` | vendor | AGREE | AGREE | AGREE | |
| `renderer/amd/sqtt.bend` | `sqtt_spec.py` | vendor | AGREE | AGREE | AGREE | |
| `renderer/amd/generate.bend` | `ga-oracle.py` | vendor | AGREE | AGREE | AGREE | |
| `nn/onnx.bend` | `onnx-gate.py` | vendor | AGREE | DISAGREE | AGREE | yes |
| `mixin/elementwise.bend` | `ew-gate.py` | vendor | AGREE | BROKEN | AGREE | yes |
| `mixin/op.bend` | `mixin-op-gate.py` | vendor | AGREE | DISAGREE | AGREE | yes |
| `tensor.bend` | `tensor-gate.py` | vendor | AGREE | AGREE | AGREE | |
| `codegen/simplify.bend` | `xd1/rw-oracle.py` | **vendor**, not xd1/head | AGREE | AGREE | AGREE | |
| `nn/__init__.bend` | `nn-init-gate.py` | vendor | AGREE | AGREE | AGREE | |
| `codegen/gpudims.bend` | `xd1/rw-gate-oracle.py` | **vendor**, not xd1/head | AGREE | DISAGREE | AGREE | yes |
| `runtime/ops_cpu.bend` | `cpulink_oracle.py` | vendor | AGREE | AGREE | AGREE | |
| `runtime/ops_python.bend` | `ops-python-render-oracle.py` | vendor | AGREE | AGREE | AGREE | |
| `runtime/ops_amd.bend` | `amd_oracle.py` | vendor | AGREE | BROKEN | AGREE | yes |
| `uop/render.bend` | `xd1/render-gate-oracle.py --gate` | **xd1/head** (the `--gate` insert) | AGREE | DISAGREE | AGREE | yes |
| `dtype.bend` | `oracle/dtype_tables.py` | vendor | BROKEN | BROKEN | BROKEN | no, reason changes |
| `renderer/cstyle.bend` | `renderer_oracle.py cstyle` | vendor | BROKEN | BROKEN | BROKEN | no, reason changes |

"24 other oracles use the pin vendor" is false. The pin vendor is not what they import. 27 import the working vendor, which is `origin/master`, 25 files past the pin. Two (`ops`, `search`'s child) import `opstree`, which is `xd1/head`. One (`render --gate`) inserts `xd1/head` itself. `simplify` and `gpudims` are wired to scripts under `xd1/` that do **not** insert a path and do **not** receive `PYTHONPATH` from the gate, so they import vendor.

`dtype` and `cstyle` stay BROKEN, but the failure changes. Natural/head: dtype prints TSV with no `=` (zero rows); cstyle prints 15 rows that share no name with the port's 225. Pin: both die on a missing dtype attribute before any row.

## Cannot run against the pin

All nine died inside the pin tree (import log says `pin`). Retried once; second attempt also 0 rows. Not a stack overflow.

| oracle | dies on |
|---|---|
| `hcq2-oracle.py:75` | `dtypes.u64` |
| `nv-oracle.py:149` | `dtypes.u64` |
| `prepare-oracle.py:23` | `dtypes.i32` |
| `ptx-s3-oracle.py:49` | `dtypes.f32` |
| `tcptx-oracle.py:187` | `dtypes.i8` |
| `nl/nl-oracle.py:31` | `dtypes.f16` |
| `mm-lift-gate.py:275` | `dtypes.i32` |
| `ew-gate.py:91` | `dtypes.i8` |
| `amd_oracle.py:830` | `dtypes.u8` |
| `dtype_tables.py:71` | `dtypes.f32` (already BROKEN on the other trees) |
| `renderer_oracle.py:91` | `dtypes.f32` (already BROKEN on the other trees) |

The pin's dtype names are the old ones (`float`, `int`, `half`, `char`). These oracles spell the post-pin names. There is no row diff to list: the pin side printed nothing.

## Rows that differ, pin vs xd1/head

Port column is the interpreted bend row. Where the port matches head, that is what was called, not a preference.

`elf_rows.py` differs on 14 names (`elf_built_{e,n}{32,64,a64}_reloc{s,_tgts}`). Two consecutive runs of the **same** tree, `env -u PYTHONPATH`, differ on exactly those 14 and on zero others. Not a tree difference. The 353 shared with the port agree on all three trees.

### `uop/ops.bend` — 13 gated, port matches head

| row | pin | xd1/head = port |
|---|---|---|
| `axc_LOOP` | `WHITE` | `red` |
| `axc_WEAK` | `WHITE` | `red` |
| `axid_twoid` | `(AxisType.LOOP,0)/len=2` | `(0,1)/len=2` |
| `axlt_gt` | `!TypeError` | `True` |
| `axlt_lt` | `!TypeError` | `False` |
| `axlt_revsorted` | `!TypeError` | `DEVICE,GLOBAL,LOCAL,WARP,WEAK,LOOP,UPCAST,PLACEHOLDER` |
| `axlt_sorted` | `!TypeError` | same string |
| `axt_twoid` | `int:1` | `LOOP` |
| `axv_LOCAL` | `4` | `3` |
| `axv_LOOP` | `10` | `6` |
| `axv_PLACEHOLDER` | `9` | `8` |
| `axv_WARP` | `3` | `4` |
| `eqax_diag` | `10` | `8` |

Ungated: `#rebase_inner` pin `inner_rows=85 filtered=23 kept=62` vs head `inner_rows=77 filtered=15 kept=62`.

### `uop/spec.bend` — 3 gated

| row | pin | xd1/head = port |
|---|---|---|
| `fu_len` | `71` | `70` |
| `te_len` | `56` | `55` |
| `tag_rej` | `0` | `1` |

Ungated: `#repro_four_src_reject` pin `LINEAR\|SINK\|SOURCE` vs head `BINARY\|LINEAR\|SINK\|SOURCE`. `#repro_tensor_own_n` pin `23` vs head `22`.

### `codegen/opt/search.bend` — 3 gated

| row | pin | xd1/head = port |
|---|---|---|
| `acts_n` | `269` | `209` |
| `acts_n_padto` | `276` | `216` |
| `acts_zero` | `28` | `18` |

Ungated: `zero_un9` pin `1` vs head `ABSENT`. `zero_red0` pin `0` vs head `ABSENT`. `#repro_split_UNROLL_top0` pin `group=10 amt0=10 axes=0\|1\|2\|3\|4\|5\|6\|7\|8\|9` vs head `AxisType.ABSENT`. `#repro_split_UNROLL_top1` pin `group=0 amt0=0 axes=-` vs head `AxisType.ABSENT`.

`#repro_vendored_import` under a **forced** run is not a vendor measurement: the force finder redirects that import too. The natural run, which is the gate's run, printed `OK:209`. The docstring that says the vendored `search.py` does not import is stale.

### `nn/onnx.bend` — 2 gated

| row | pin | xd1/head = port |
|---|---|---|
| `onnx_odt_dtbl` | `float,unsigned char,signed char,...` | `f32,u8,i8,u16,i16,i32,i64,bool,f16,f64,u32,u64,bf16` |
| `onnx_odt_hole_dts` | `-,float,-,-,-` | `-,f32,-,-,-` |

### `mixin/op.bend` — 5 gated

| row | pin | xd1/head = port |
|---|---|---|
| `sh_lse0` | `float` | `f32` |
| `sh_lse0kd` | `(1) float` | `(1) f32` |
| `sh_mean0` | `float` | `f32` |
| `sh_norm0` | `(2)(2) float` | `(2)(2) f32` |
| `sh_sum0kd` | `(1) float` | `(1) f32` |

### `codegen/gpudims.bend` — 15 gated, all 24 shared, port matches head

Natural (vendor) vs xd1/head: **0** mismatches. The flip is pin vs everything else.

| row | pin | xd1/head = port |
|---|---|---|
| `rs_len` | `!pm_range_to_special:ABSENT` | `2` |
| `rs_ownlen` | `!TypeError: unsupported operand type(s) for -: 'str' and 'int'` | `1` |
| `se_len` | `0` | `1` |
| `rs_arg_global` | `NONE` | `gidx0` |
| `rs_arg_local` | `NONE` | `lidx1` |
| `rs_claim_global` | `0` | `1` |
| `rs_claim_local` | `0` | `1` |
| `rs_idlast_global` | `AxisType.GLOBAL` | `0` |
| `rs_idlast_two` | `0` | `1` |
| `rs_name_global` | `gidxAxisType.GLOBAL` | `gidx0` |
| `rs_name_warp` | `lidxAxisType.WARP` | `lidx2` |
| `rs_op_global` | `NONE` | `Ops.SPECIAL` |
| `rs_rewrite_global` | `0` | `1` |
| `rs_rewrite_local` | `0` | `1` |
| `rs_tag_kept` | `None` | `rstag` |

`pm_range_to_special` does not exist at the pin. The port prints the head answers.

### `uop/render.bend` — 18 gated, all 85 shared, port matches head

| row | pin | xd1/head = port |
|---|---|---|
| `arg_repr ACALL2` | `CallInfo(..., dtype=dtypes.int)` | `CallInfo(None, 'f', False, False)` |
| `arg_repr ACALL3` | `CallInfo(..., dtype=dtypes.weakint)` | `CallInfo(None, None, False, False)` |
| `arg_repr ADt` | `dtypes.int` | `dtypes.i32` |
| `arg_repr AInk` | `('w', dtypes.float)` | `('w', dtypes.f32)` |
| `arg_repr AParam1` | `ParamArg(1, dtypes.float, ...)` | `ParamArg(1, dtypes.f32, ...)` |
| `arg_repr AParam2` | `ParamArg(2, dtypes.int, name='g')` | `ParamArg(2, dtypes.i32, name='g')` |
| `arg_repr AParam3` | `ParamArg(3, dtypes.float, ...)` | `ParamArg(3, dtypes.f32, ...)` |
| `arg_repr ARng` | `(0, AxisType.GLOBAL)` | `(AxisType.GLOBAL, 0)` |
| `dt_repr float` | `dtypes.float` | `dtypes.f32` |
| `dt_repr int32` | `dtypes.int` | `dtypes.i32` |
| `pyr_call_named` | `True` | `False` |
| `pyr_call_noop` | `True` | `False` |
| `pyrender cast` | `UOp.const(3).cast(dtypes.float)` | `UOp.const(3).cast(dtypes.f32)` |
| `pyrender cfn` | `arg='myfn'` | `arg=CustomFunction(name='myfn', dtype=dtypes.void)` |
| `pyrender flat2` | `UOp.range(4, AxisType.WEAK, 0, 1)` | `UOp(Ops.RANGE, (UOp.const(4),), (AxisType.WEAK, 0, 1))` |
| `pyrender flat3` | `UOp.range(4, AxisType.WEAK, 0, 1, 2)` | `UOp(Ops.RANGE, ..., (AxisType.WEAK, 0, 1, 2))` |
| `ast` | `UOp.new_buffer('CPU', 16, dtypes.int, 0)` | `UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device='CPU', image=(2, 2)))` |
| `c2` | `UOp.new_buffer(('CPU', 'METAL'), 4, dtypes.int, 0)` | `UOp(Ops.BUFFER, (c1,), ParamArg(0, dtypes.i32, 4, device=('CPU', 'METAL')))` |

Full strings are in `runs/pin-tree-oracle/oracle/tinybendygrad_uop_render__{pin,xd1head}__1.out`.

### `codegen/simplify.bend` — 18 differ, **0 gated**, verdict does not flip

Natural (vendor) equals xd1/head on all 18. The port's 28 shared names agree with both trees. The 18 are oracle rows the port does not print.

| row | pin | vendor = xd1/head |
|---|---|---|
| `gd_pinname` | `pm_add_gpudims:3` | `pm_add_gpudims:ABSENT` |
| `gd_headname` | `pm_group_gpudims:ABSENT` | `pm_group_gpudims:3` |
| `rs_len` | `pm_range_to_special:ABSENT` | `2` |
| `rs_tops` | `ABSENT` | `RANGE;END` |
| `rs_ownlen` | `!ABSENT` | `1` |
| `se_len` | `-1` | `1` |
| `se_tops` | `ABSENT` | `END` |
| `rs_global` | `!ABSENT` | `Ops.SPECIAL/gidx0` |
| `rs_global_2id` | `!ABSENT` | `Ops.SPECIAL/gidx1` |
| `rs_local` | `!ABSENT` | `Ops.SPECIAL/lidx1` |
| `rs_device` | `!ABSENT` | `NONE` |
| `rs_loop` | `!ABSENT` | `NONE` |
| `rs_warp` | `!ABSENT` | `NONE` |
| `rs_claim_global` | `!ABSENT` | `1` |
| `rs_claim_local` | `!ABSENT` | `1` |
| `rs_claim_device` | `!ABSENT` | `0` |
| `rs_claim_loop` | `!ABSENT` | `0` |
| `rs_claim_warp` | `!ABSENT` | `0` |

### `runtime/ops_python.bend` — 18 differ, **0 gated**, verdict does not flip

59 shared with the port agree on all three trees. Natural equals xd1/head on the 18. They are dtype-name spellings and two lengths, none of them a port row:

`pypp_b64_len` 1564 vs 1560. `pypp_pickle_len` 1172 vs 1170. `pysd_has_half` False vs True. `pywma_c0_dtype_in` `dtypes.float` vs `dtypes.f32`. `pywma_c1_dtype_in` `dtypes.half` vs `dtypes.f16`. Twelve `pyr_*_core_in` / `pysd_sorted` rows spelling `dtypes.half`/`float`/`char`/`bfloat16` at the pin and `dtypes.f16`/`f32`/`i8`/`bf16` at head.

### No pin-vs-head row diff, and no verdict flip

`ops_rdma`, `ops_metal`, `usb`, `viz/serve`, `support/c`, `sqtt`, `generate`, `tensor`, `nn/__init__`, `ops_cpu`. Plus `elf` once the 14 ASLR names are set aside.

## Recommendation

Do **not** standardise the gate suite on the pin.

The measurement: 16 of 31 verdicts move, all of them from AGREE to BROKEN or DISAGREE, and every disagreed row has the port on the non-pin side. Zero gates are AGREE on the pin and not AGREE on their current tree. The pin is the vendoring authority in `UPSTREAM-PIN.md`. It is not the tree these ports were checked against.

The tree the gates actually measure is the working vendor (`origin/master`) for 27 oracles, and the `xd1/head` snapshot for the three that select it (`ops` and `search` via `TG_TREE`→`opstree`, `render --gate` via an insert). `xd1/head` is not `upstream/master`. Pointing those three at current `upstream/master` was not this measurement; 14 files would change, including `ops.py`.

## What would have to change to adopt the pin

Not done. Listed so it is not done by accident.

1. Nine oracles (plus the two already-dead ones) name `dtypes.f32` / `i32` / `i8` / `u8` / `u64` / `f16`. Those attributes do not exist at the pin. Adopting the pin means rewriting each call site to the pin's names, or accepting BROKEN. The ports they gate already print the post-pin spellings, so an oracle rewrite alone does not make the gate AGREE — the port would still have to move, and this unit was told not to change ports.
2. Seven oracles run and disagree on the rows above. Adopting the pin means rewriting those port rows to the pin column, or leaving the oracle on its current tree. The rows are the whole cost: axis values and colours (`ops`), `fu_len`/`te_len`/`tag_rej` (`spec`), `acts_n` 269 vs 209 (`search`), the two onnx dtype tables, five `mixin/op` shape rows, fifteen `gpudims` `pm_range_to_special` rows, eighteen `render` rows (dtype clause, `CustomFunction`, range-arg order, `new_buffer` vs `Ops.BUFFER`).
3. `render-gate-oracle.py` lines 15–16 insert `xd1/head` when `--gate` is set. That insert is why the gate currently agrees. Pointing it at `xd1/pin` is the 18-row move in the table.
4. `ops-oracle.py:79` and `rebase-oracle-search.py:49` default `TG_TREE` to `opstree`. The gate does not override it. Changing the default to the pin is the ops and search rows above.
5. `rw-oracle.py` and `rw-gate-oracle.py` have no path insert. The gate does not set `PYTHONPATH`. They already import vendor. Forcing the pin does not flip `simplify`'s 28 gated rows; it does flip `gpudims`'s 15. A comment that says `PYTHONPATH=<tree>` is not what the gate runs.
6. Re-vendoring `tinygrad/` back to `6c3d401cf324` would move the 25 files that currently equal a post-pin commit. `UPSTREAM-PIN.md` says that movement is the batch working, in the other direction, and that the pin is not to be advanced while drift is open. Doing it in reverse is an owner decision, not an oracle flag.

## Control

`render-gate-oracle.py --gate`. Live `xd1/head` was not written (`=X ` absent after the plant).

| run | rows | vs |
|---|---|---|
| natural, twice, logger on | 85 vs 85, 0 changed | itself |
| natural vs forced onto an unmodified **copy** of xd1/head | 0 changed | the insert and the force finder read the same tree |
| `env -u PYTHONPATH` (no sitecustomize) vs the logged natural | 0 changed | the logger did not move a row |
| same check on `rebase-oracle-spec.py` | 16 vs 16, 0 changed | second oracle |
| forced onto a copy whose `pyrender` join was planted ` = ` → ` =X ` | **36 rows moved** | `ast`, `c2`–`c5`, and 30 `pyrender *` rows |

A gate that had never been seen to disagree with itself would not have been known to work. This one disagrees with a planted tree and agrees with itself.

`generate.bend`'s first bend run printed 0 rows; the second printed 233. The verdict uses 233. A 0-row result was not reported as a measurement.

## Outside this unit's files

- `BASE_ORACLES` grew during the sweep. `generate.bend` — ga-oracle wiring unit, constraints position 14489. `ops_python.bend` — ops-python render unit, `TODO.md` session 2026-10-03. `ops_amd.bend` — amd oracle unit, constraints position 14628. Not edited here.
- `TOOLS.md` says `xd1/head` is `git archive upstream/master`. Against current `upstream/master` that is false for 14 files. Owner: the xd1 unit that wrote that sentence. Not edited here except the ledger line below.
- `tinybendygrad/**`, `tinygrad/**`, `rebase-gate.py`, `tree-verdict.py`, `wire-*.py` were not edited.
