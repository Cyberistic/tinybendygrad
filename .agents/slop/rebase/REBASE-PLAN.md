# REBASE-PLAN.md — the executable sequence for closing upstream drift

Every verdict below is **measured**, not argued. Batches come from
`python3 .agents/slop/rebase-plan.py [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git]`; every "required / droppable" claim comes from
`.agents/slop/rebase-try.sh --shrink <id>`, which builds the batch in a throwaway tree and
drops one file at a time.

Window: pin `6c3d401cf324` → `upstream/master`. 46 changed files under `tinygrad/`.

> **⚠ PART OF B1 AND B2 IS ALREADY APPLIED — by accident, and the tree is broken.**
> Commit `d2cde2f2c` re-vendored `tinygrad/dtype.py` and `tinygrad/runtime/ops_null.py` to
> HEAD without the rest of their batches. `ops_null.py` at HEAD calls
> `UPat.custom_function`, which only HEAD `uop/ops.py` defines, so the working tree does
> not import:
>
> ```
> AttributeError: type object 'UPat' has no attribute 'custom_function'
>   tinygrad/runtime/ops_null.py:57, in NullDevice
> ```
>
> This plan was written while that was in effect. The batching below is what should have
> happened. Treat B1 as "17 files, of which `ops_null.py` is already applied and breaks
> the tree until the rest land", and B2 as "2 files, of which `dtype.py` is already
> applied". **Do not "fix" `ops_null.py` by editing it** — it is correct for HEAD and
> wrong only because its batch is missing.

## The order — 3 coupled batches, 20 independent singletons

| step | size | may run in parallel with |
|---|---|---|
| **B1** | **17 required** (21 static, 4 droppable) | B2, B3, any singleton |
| **B2** | **2 required** | B1, B3, any singleton |
| **B3** | **1 required** (`runtime/support/c.py`) | B1, B2, any singleton |
| S1..S20 | 20 singletons, one per file | everything else |

21 of the 46 changed files are `viz/`, unported renderers, or files with no `.bend` —
those are RE-BASE and need no step at all. The work is **3 + 20 steps in any order**, not
46 in one.

## B1 — 17 files, genuinely atomic

`--shrink 1`: **every one of these 17 is load-bearing.** The exact failure each produces:

```
  drop indexing.py    AttributeError: type object 'AxisType' has no attribute 'REDUCE'
  drop rangeify.py    TypeError: unsupported operand type(s) for +: 'AxisType' and 'int'
  drop ops.py         ImportError: cannot import name 'CustomFunction'
  drop spec.py        RUN-FAIL
  drop __init__.py    ImportError: cannot import name 'pm_add_gpudims'
  drop gpudims.py     ImportError: cannot import name 'pm_group_gpudims'
  drop heuristic.py   AttributeError: 'Scheduler' object has no attribute 'reduce_axes'
  drop postrange.py   ImportError: cannot import name 'axis_to_pos'
  drop hcq2.py        RUN-FAIL          drop device.py   ImportError: cfunc_buf
  drop realize.py     AttributeError: 'HCQInfo' object has no attribute 'inputs'
  drop ops_{cuda,metal,null,qcom,amd,nv}.py   ImportError: cannot import name 'encode_submit'
```

**4 droppable** — vendor these on their own, they are not part of the atomic unit:
`codegen/simplify.py`, `codegen/opt/search.py`, `llm/kernels/amd.py`,
`runtime/ops_rdma.py`.

Vendor order inside B1, dependency-first:

```
tinygrad/runtime/support/hcq2.py   tinygrad/codegen/opt/postrange.py
tinygrad/uop/ops.py                tinygrad/codegen/opt/heuristic.py
tinygrad/schedule/rangeify.py      tinygrad/schedule/indexing.py
tinygrad/device.py                 tinygrad/uop/spec.py
tinygrad/runtime/ops_{cuda,metal,null,qcom,amd,nv}.py
tinygrad/codegen/__init__.py       tinygrad/codegen/gpudims.py
tinygrad/engine/realize.py
```

## B2 — 2 files, atomic

`dtype.py` + `renderer/cstyle.py`. HEAD `cstyle.py` uses `dtypes.i8`; the pin's `dtype.py`
has no `i8` (793abbb16 renamed `int8` → `i8`, keeping `int8` as a legacy alias only).
Dropping `dtype.py` → `AttributeError: 'DTypes' object has no attribute 'i8'`.

## B3 — 1 file required, 2 droppable

`runtime/support/c.py`. `DLL._loaded_` is rebound from `set()` to `{}` (a dict), so
`ops_cpu.py`'s `DLL._loaded_.values()` raises `'set' object has no attribute 'values'`
against the pin's `c.py`. **`ops_cpu.py` and `ops_python.py` may vendor alone** — they are
the importers, and they need the *new* `c.py`, not the reverse.

This batch was **not** in the first cut of the analysis. It was found by running the probe
on every file, which is the argument for running the probe on every file.

## The 20 singletons — all measured OK alone

`codegen/simplify.py` `engine/jit.py` `llm/serve.py` `mixin/elementwise.py`
`mixin/gradient.py` `mixin/op.py` `nn/__init__.py` `nn/onnx.py` `renderer/amd/sqtt.py`
`renderer/llvmir.py` `renderer/ptx.py` `runtime/ops_python.py` `runtime/support/elf.py`
`runtime/support/usb.py` `schedule/__init__.py` `schedule/multi.py` `schedule/prepare.py`
`tensor.py` `uop/render.py` `uop/validate.py` `uop/weak.py`

Four of these are B1's droppable members (`simplify.py`, `opt/search.py`,
`llm/kernels/amd.py`, `ops_rdma.py`); the other sixteen are true singletons.

## Four coupling levels, and the measured failure each one is responsible for

| level | what moved | measured failure |
|---|---|---|
| **name** | `from x import n`, `n` added / removed / rebound | `ops.py` alone → `ImportError: axis_to_pos` |
| **attribute** | `Cls.member` added / removed | `cstyle.py` alone → `AttributeError: dtypes.i8` |
| **attribute rebind** | `Cls.member` bound to a different container | `ops_cpu.py` alone → `'set' has no 'values'` |
| **tuple payload** | `arg=(a,b)` → `arg=(b,a)` | `rangeify.py` → `x.arg[0] + 1` is `AxisType + int` |

A fifth, **signature**, is reported per batch rather than as an edge, because it only
couples a caller that is already in the batch: `heuristic.py` alone →
`Scheduler.axes_of() got an unexpected keyword argument 'reduce'`.

The tuple level is why **importing is not a test**: every `AxisType.REDUCE` use sits
inside a function body, so the tree imports cleanly and dies on the first kernel.
`rebase-try.sh` therefore runs import **and** a real compile **and** imports all seven
`ops_*` modules explicitly, because `DEV=NULL` loads only three of them.

## The negative control

`rebase-try.sh --solo <file>` vendors exactly one file and nothing else — which is what
`UPSTREAM-PIN.md` used to advise. It refutes that advice on demand:

```
ops.py          IMPORT-FAIL  ImportError: cannot import name 'axis_to_pos'
cstyle.py       IMPORT-FAIL  AttributeError: 'DTypes' object has no attribute 'i8'
hcq2.py         IMPORT-FAIL  AttributeError: type object 'UPat' has no attribute 'custom_function'
postrange.py    RUN-FAIL     AttributeError: 'Scheduler' object has no attribute 'reduce_axes'
heuristic.py    RUN-FAIL     TypeError: Scheduler.axes_of() got an unexpected keyword argument 'reduce'
dtype.py        RUN-FAIL
rangeify.py     RUN-FAIL
realize.py      IMPORT-FAIL  AttributeError: type object 'UPat' has no attribute 'custom_function'
ops_cpu.py      RUN-FAIL     AttributeError: 'set' object has no attribute 'values'
```

**10 of the files cannot be vendored alone.** Only 20 of 46 can.