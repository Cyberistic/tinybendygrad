# tc_ptx `types_pri`: `case _: ""` was not one bug, it was three, and two were silent

`gates/ptx_render_census-gate.py`'s author measured that `UOp.range(4,0)` (dtype `weakint`)
and `UOp(const(3.0), const(4.0))` (dtype `weakfloat`) reach `types_pri`'s `case _:` where
CPython raises `KeyError`, and that the port emits `%ridx_pred_0` and `%alu__0`. They filed
that as an EMPTY TYPE FIELD. Reading the code says it is worse and the report is what the
gate could not see.

## 1. WHAT CPYTHON ACTUALLY DOES (read, not inferred)

`ptx.py:156-161` -- three class-level DICTS. `types` has **twelve** keys. Measured:

```
$ .venv/bin/python -c "...; print([d.name for d in dtypes.all if d not in PTXRenderer.types])"
['fp8e4m3', 'fp8e5m2', 'fp8e4m3fnuz', 'fp8e5m2fnuz', 'bf16']
```

`dtypes.all` is 17 and does NOT contain `weakint`/`weakfloat` (`dtype.py:119,129` build them
outside `all`), so `types[weakint]` and `types[weakfloat]` raise as well --
`KeyError: dtypes.weakint`, MEASURED. **`pri` is not unique over the dtypes a kernel can
carry.** Grouped by priority, measured:

| pri | in `types` | MISSING |
|---|---|---|
| -1 | -- | `void` |
| 0 | `bool` | **`weakint`** |
| 9 | -- | **`weakfloat`** |
| 10 / 11 | -- | `fp8e4m3` / `fp8e4m3fnuz`, `fp8e5m2` / `fp8e5m2fnuz` |
| 13 | -- | `bf16` |

`types_pri`'s `case _: ""` therefore covered **six** dtypes, and the pri-keyed arms covered
**two it must not** (`void` and `weakint`, both pri 0, both sharing `bool`'s `"pred"`).

## 2. THE PORT'S THREE ANSWERS, MEASURED BEFORE THE FIX

`probe.bend` here, over the three tables:

```
bool       = [pred] [u8] [pred]  pri=0  bits=1
void       = [pred] [u8] [pred]  pri=0  bits=0        <-- wrong CONCRETE types
weakint    = [pred] [u8] [pred]  pri=0  bits=800      <-- wrong CONCRETE types
weakfloat  = []     []     []     pri=9  bits=800      <-- empty
fp8e4m3    = []     []     []     pri=10 bits=8
bf16       = []     []     []     pri=13 bits=16
```

**So the report was right about `weakfloat` and wrong about `weakint`, and the correction is
the finding.** `weakint` did not get an empty field -- it got `pred`, `u8` and `pred`: three
CONCRETE, COMPILABLE, SILENTLY WRONG types, one per table, reached down two different arms
(`types_pri`'s `case 0:` and `mem_types_pri`'s own `case 0: "u8"`). A `.reg .pred` for a
32-bit index is a kernel `ptxas` accepts and computes wrongly. `void` did the same thing.
That is `renderer/amd/dsl.bend`'s `U32.shln` shape exactly: a wrong value is SMALLER, not
ABSENT, and a diff does not see smaller.

## 3. WHICH OF THE THREE ANSWERS, AND WHY

* **(C) keep `""`, make the consumer refuse -- MEASURED IMPOSSIBLE, not merely awkward.**
  The consumer is `renderer/ptx.bend:300 pf.ty_of`, outside this unit's grant, and it
  *back-fills* rather than refuses: `Bool.pick(String, String.is_empty(ty), P.types_of(dt), ty)`
  resolves a `""` by asking `types_of` again, so a `""` passes straight through. Worse, a
  refuse-on-empty consumer is **blind to two thirds of the bug**: `weakint`'s answers are
  `pred`/`u8`/`pred`, none of them empty.
* **(A) refuse loudly via `Res{v, msg}`** changes `types_of`'s return type, and three
  consumers of it are outside this grant (`ptx.bend:300`, `ptx_render_census.bend`'s `tyo_`
  rows, and `Pr.text`). Breaking three contracts is a worse outcome than the bug.
* **(B) map the weak dtypes to the type they MEAN -- and it is CPython's own function.**
  `dtype.py:169-170`:

  ```python
  def strong_dtype(dtype): return {weakint: default_int, weakfloat: default_float}.get(dtype, dtype)
  ```

  Measured at the default settings: `i32`, `f32`. So the port answers `s32`/`f32`, and PTX
  admits no integer register narrower than 32 bits, so `s32` is the only legal `.reg` for a
  weak int and not a guess. `void`, the fp8s and bf16 have no such map -- `supported_dtypes`
  refuses them on PTX (the row is in the file) -- so they keep the refusal, which is LOUD.

  The one divergence from `strong_dtype`: CPython reads `DEFAULT_INT`/`DEFAULT_FLOAT` and
  `S.int32()`/`S.single()` are the defaults. The port's values are read OUT OF `types_pri`
  (`types_pri(pri(int32))`) so the map and the dict cannot drift.

## 4. BEFORE / AFTER

| | before | after | CPython |
|---|---|---|---|
| `types weakint` | `pred` | **`s32`** | `KeyError` |
| `types weakfloat` | `` | **`f32`** | `KeyError` |
| `types void` | `pred` | **`""`** (refusal) | `KeyError` |
| `mem_types weakint` | `u8` | **`s32`** | `KeyError` |
| `mem_types weakfloat` | `` | **`f32`** | `KeyError` |
| `mem_types void` | `u8` | **`""`** (refusal) | `KeyError` |
| `cast_types weakint` | `pred` | **`s32`** | `KeyError` |
| `cast_types weakfloat` | `` | **`f32`** | `KeyError` |
| `cast_types void` | `pred` | **`""`** (refusal) | `KeyError` |

Every one of the twelve keys and the two fp8/bf16 rows is byte-identical: the 334 rows
`tc_ptx.bend` already printed did not move, which is precisely the invisibility.

## 5. THE ROWS THAT CAN FAIL, AND THE MUTATIONS

`gates/tc_ptx_types-gate.py` -- **60 rows, 3 lanes, 24 pinned divergences, rc=0.**
Population DISCOVERED, not listed: `dtypes.all` (17) + `dtypes.weaks` (2) + `dtypes.void`
= 20, x 3 tables. The 24 divergences are *derived from CPython in the gate file itself* --
`PTXRenderer.types[strong_dtype(d)]`, `EMPTY` when that raises -- so **not one of the 24
pinned strings is written by hand**, and changing `DEFAULT_INT` or `strong_dtype` moves them.

| mutation | what | rows moved |
|---|---|---|
| M1 | `types_of` back to `types_pri(pri)` | 3 |
| M2 | `mem_types_of` back | 3 |
| M3 | `cast_types_of` back | 3 |
| **M4** | `w_int()` reads `uint32`'s entry, not `int32`'s | **3** |
| M5 | drop ONLY the `CVoid` arm from `types_of` | 1 |
| M6 | CONTROL: a comment-only edit | **0, as it must** |

M4 is the one that matters: the dispatch stays intact and only the ANSWER becomes a lie --
`weakint` gets `u32`, a real PTX type and a legal `.reg`. That is how a gate that refuses
empties is told apart from one that refuses concrete wrong types.

End-to-end, not just by row diff: reverting the three tables and running the gate gives
**rc=1** (`bd's types_void is not 'types_void=EMPTY'`); restoring gives **rc=0**.

## 6. THE SIBLING `case _:` ARMS

`grep -n 'case _:' tinybendygrad/renderer/tc_ptx.bend` -> 9 hits, 8 arms.
`types_pri`'s `case _: ""` is the miss marker `ifmiss` already models. The three tables'
`case _:` arms are fall-throughs to the dict. `mem_type`'s is CPython's own `else`. 
`px_pline`'s is a bounded 0..3 index.

**`op_asm`'s `case _: []` (line ~387) is the same class and is UNREACHABLE -- MEASURED: 21
arms for `asm_keys()`'s 21 members, and all five call sites pass a member or a literal
`OpsWHERE`.** No emitted line is affected today, so it is NAMED rather than changed -- a
refusal has no room in a `List<&2, String>`, and a twenty-second op would emit NOTHING where
CPython raises.

## 7. THE CONSEQUENCE FOR `gates/ptx_render_census` (NOT MINE -- FOR ITS OWNER)

`gates/ptx_render_census-pins.rows` pins the DEFECT as the expected answer. MEASURED against
a fresh `bin/bend gates/ptx_render_census.bend`: **5 of 579 pinned `bd` rows move, and all
five are the defect itself.**

| row | pinned | now |
|---|---|---|
| `tyo_0` | `pred` | `""` |
| `mto_0` | `u8` | `""` |
| `cto_0` | `pred` | `""` |
| `f31_weakint.r1` | `%ridx_pred_0` | `%ridx_s32_0` |
| `f32_weakfloat.r2` | `%alu__0` | `%alu_f32_0` |

`f33_bf16cast.r1=%cast__0` does NOT move -- bf16 still refuses, which is the half that was
already right. Updating those five pin values is the census owner's edit; this unit's grant
excludes `gates/ptx_render_census*`.

## 8. OTHER DIVERGENCES FOUND, NOT FIXED

* `LAWS/spec.bend:719` `void() = Dt{0, ...}` -- CPython's `dtypes.void.priority` is **-1**
  (MEASURED). In the port `void`, `bool` and `weakint` are all pri 0. The fix routes on
  `cls`, which is right in both; the priority divergence is in `spec.bend`, out of grant.
* `renderer/ptx.bend:300 pf.ty_of` back-fills `""` from `types_of`. Now that `types_of`
  refuses where CPython refuses, that consumer can no longer be told "empty means resolve me
  later" -- it is only safe because the refusal now means the same thing on both sides.

## 9. MEASUREMENTS

| run | rc | rows | s | peak RSS |
|---|---|---|---|---|
| `bin/bend tinybendygrad/renderer/tc_ptx.bend` (base) | 0 | 334 | 1.22 | 485 MB |
| same, after the fix | 0 | 334 | 0.61 | 512 MB |
| same, with the 9 rows | 0 | 343 | 0.99 | 474 MB |
| `gates/tc_ptx_types-gate.py` | 0 | 60 x 3 | 4.49 | 453 MB |
| `gates/tc_ptx_types-mutate.py` | 0 | 60 base | 5.38 | 439 MB |
| `bin/bend gates/ptx_render_census.bend` | 0 | 579 | 0.85 | 483 MB |

One `bend` at a time throughout; the peak figures are single-process maxima measured with
`/usr/bin/time -l`.