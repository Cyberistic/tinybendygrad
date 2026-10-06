# Five New Graphs Report — 2026-10-06

## Summary

5 ops unexercised by the corpus → **5 authored (all 5 py-side reachable)**, 0 blocked.
All five produce the target op in the `emit --side py` normal form.
All five need a `graphcmp.bend` patch on the port side before they can enter the run corpus.

**Census change**: `61 of 77` → **66 of 77** (+5 ops, +0 new unexercised gaps).

---

## 1. The pattern — how a graph is declared

A fixture function is a **zero-argument function returning a `UOp`**.
It is registered in the `GRAPHS` dict (`.agents/slop/graphcmp.py:1471`):

```python
GRAPHS = {"matmul": g_matmul, ...}
```

The py side calls `base(graph)` → `GRAPHS[graph]()` once, caches in `_BASE`.
`emit_py` calls `base(graph)`, toposorts, and prints one normal-form row per node.

Key pattern details (measured, file:line):

| Rule | Location |
|---|---|
| A fixture imports dependencies INSIDE the function body | `g_matmul` at line 841 |
| A fixture uses the global `dtypes`, `Ops`, `UOp`, `UOp.group`, `Tensor`, `AxisType`, `ParamArg`, etc. from `load_tinygrad()` | `g_cast` at line 905, `g_bit` at line 1311 |
| `GroupOp` globals are injected in `load_tinygrad` at line 286-291 | — |
| A single-node graph can return the UOp directly (no GROUP) | `g_sink` line 879, `g_range` line 887 |
| Multi-return graphs use `UOp.group(gt1, gt2, ...)` to wrap multiple top-level nodes under one root | `g_alu` line 1298, `g_bit` line 1312 |
| The GRAPHS dict is at file line 1471 | — |
| The `carg` function handles op-specific arg shapes at line 478-563 | WMMA has its own arm at 491 |
| Generic args fall through to `_carg` at line 566 | THREEFRY/MULACC/GETADDR/UNSHARD all use this |

---

## 2. Reachability per op

### THREEFRY
- **Eager API**: `Tensor.threefry(seed)` → `self.alu(Ops.THREEFRY, seed)` (`elementwise.py:457-458`)
- **Decomposition**: `get_simplifying_rewrite_patterns` at `op.py:76-77` only fires during compilation, not in the eager graph
- **Device constraint**: None. Any renderer can carry THREEFRY (NullRenderer adds it explicitly at `ops_null.py:16`)
- **Multi-device**: None
- **Reachable from a graph: YES**

### MULACC
- **Late rewrite**: `get_late_rewrite_patterns` at `op.py:118-119` creates MULACC from `a*b + c` only when `Ops.MULACC in ops`
- **But hand-written**: `UOp(Ops.MULACC, src=(a, b, c))` — MULACC is in `GroupOp.Broadcastable` (via `Ternary`), so `dtype_from_uop` and `_shape` both handle it through the generic Broadcastable fallback (ops.py:193, 442)
- `python_alu` at ops.py:1431 has a lambda for evaluation
- **Device constraint**: None for hand-written graph
- **Multi-device**: None
- **Reachable from a graph: YES** (hand-written)

### GETADDR
- **Constructor**: `UOp.getaddr(device)` at `ops.py:841-844` wraps BUFFER/ALLOC/SHRINK/etc.
- **Spec**: `Irreducible` op, `dtype=uint64`, `shape=()` (ops.py:363)
- **Device constraint**: None for hand-written `UOp(Ops.GETADDR, src=(alloc,), arg="CPU")`
- **Multi-device**: None
- **Reachable from a graph: YES**

### UNSHARD
- **Constructor**: `UOp.unshard(axis, device_range)` at `ops.py:689-701`
- **Shape**: multiplied by shard count on the sharded axes (ops.py:430)
- **Spec check**: `spec.py:181-182` — `len(multi.src) == 1 + len(multi.arg)` and all ranges have weak dtypes
- **Device constraint**: None — if `device_range` is passed explicitly, the multi-device assertion is bypassed
- **Multi-device**: None as hand-written (uses an explicit DEVICE-axis range)
- **Reachable from a graph: YES** (hand-written with explicit range)

### WMMA
- **Constructor**: `UOp.wmma(a, b, acc, dims, threads)` at `ops.py:649-651`
- **Shape**: `_broadcast_shape(a.shape[:-1], b.shape[:-1], acc.shape[:-1]) + (acc.shape[-1],)` (ops.py:381-383)
  - Requires M==K for 2D tensors (batch dims must broadcast)
- **carg arm**: `carg` has a dedicated `if op is Ops.WMMA` at line 491-494 producing `wm(...)` form
- **Device constraint**: None for hand-written graph
- **Multi-device**: None
- **Reachable from a graph: YES** (hand-written with M=K)

### Summary table

| Op | Eager graph | Needs device | Needs multi-device | Authored |
|---|---|---|---|---|
| THREEFRY | `Tensor.threefry(seed)` | None | None | ✅ `g_threefry` |
| MULACC | Hand-write `UOp(Ops.MULACC, ...)` | None | None | ✅ `g_mulacc` |
| GETADDR | `UOp(Ops.GETADDR, src=(alloc,), ...)` | None | None | ✅ `g_getaddr` |
| UNSHARD | `UOp(Ops.UNSHARD, src=(val, range), ...)` | None | None | ✅ `g_unshard` |
| WMMA | `UOp(Ops.WMMA, src=(a,b,acc), ...)` | None | None | ✅ `g_wmma` |

**All five are reachable from a graph on `DEV=CPU` without any hardware.** None needs a real AMD/CUDA device, a second GPU, or any backend-specific flag.

---

## 3. Authored fixtures

All added to `.agents/slop/graphcmp.py` before `GRAPHS` dict, and registered in it.

| Graph | Fixture | Op | Py census | Nodes | Emit rc |
|---|---|---|---|---|---|
| `threefry` | `g_threefry` | THREEFRY | ALLOC=3, CONST=2, STACK=1, RESHAPE=3, THREEFRY=2, GROUP=1 | 12 | 0 |
| `mulacc` | `g_mulacc` | MULACC | ALLOC=3, CONST=2, STACK=1, RESHAPE=3, MULACC=1 | 10 | 0 |
| `getaddr` | `g_getaddr` | GETADDR | ALLOC=1, GETADDR=1 | 2 | 0 |
| `unshard` | `g_unshard` | UNSHARD | ALLOC=1, CONST=3, STACK=1, RESHAPE=1, RANGE=1, UNSHARD=1 | 8 | 0 |
| `wmma` | `g_wmma` | WMMA | ALLOC=3, CONST=2, STACK=2, RESHAPE=3, WMMA=1 | 11 | 0 |

Each verify line (`grep <op>` on emit output):

```
THREEFRY:  3:i11 8:THREEFRY 3:u64  11:(l0:4,l0:3)  2:i0 1:N 1:N 8:n(i5,i10)
MULACC:    3:i10 6:MULACC  3:f32  11:(l0:4,l0:3)  2:i0 1:N 1:N 11:n(i5,i7,i9)
GETADDR:   2:i2  7:GETADDR 3:u64   2:()            2:i0 1:N 4:sCPU 5:n(i1)
UNSHARD:   2:i8  7:UNSHARD 3:f32  11:(l0:8,l0:3)  2:i0 1:N 5:n(i0) 8:n(i5,i7)
WMMA:      3:i11 4:WMMA   3:f32  11:(l0:4,l0:3)  2:i0 1:N 27:wm(n(i3,i4,i4),Df32,i256,N) 12:n(i4,i8,i10)
```

---

## 4. What WANT would need per graph

The **py side** (CPython) works immediately — `emit_py` produces valid rows with the target op.
The **bend side** (port) does NOT know these graph names yet — `graphcmp.bend` silently falls back to matmul (producing MUL/REDUCE nodes instead of the new op).

For admission into the run corpus (`WANT`):

| Graph | Py emit | Bend needs | Expected verdict |
|---|---|---|---|
| `threefry` | ✅ 12 rows, THREEFRY seen | Pad `graphcmp.bend` with `g_threefry` and the UOp builders that produce `Ops.THREEFRY` | AGREE |
| `mulacc` | ✅ 10 rows, MULACC seen | Pad `graphcmp.bend` with `g_mulacc` producing `Ops.MULACC` | AGREE |
| `getaddr` | ✅ 2 rows, GETADDR seen | Pad `graphcmp.bend` with `g_getaddr` producing `Ops.GETADDR` | AGREE |
| `unshard` | ✅ 8 rows, UNSHARD seen | Pad `graphcmp.bend` with `g_unshard` producing `Ops.UNSHARD` | AGREE |
| `wmma` | ✅ 11 rows, WMMA seen | Pad `graphcmp.bend` with `g_wmma` producing `Ops.WMMA` with the `wm(..)` arg form | AGREE |

The `WANT` row for each would be `AGREE` (all control tests pass on the py side; the bend builder, once written, is expected to match).

---

## 5. Blocked ops — zero

No op is blocked. All five produce valid eager UOp graphs that the CPython-side emitter can render. The limiting factor is only the port's `graphcmp.bend` builder, which has not been patched for any of them. That is a port-side gap, not a graph-reachability gap.

---

## 6. Final tally

**Authored: 5** (`threefry`, `mulacc`, `getaddr`, `unshard`, `wmma`)
**Blocked: 0**

| Op | Fixture | Authorable? | Blocking thing |
|---|---|---|---|
| THREEFRY | `g_threefry` | ✅ | None |
| MULACC | `g_mulacc` | ✅ | None |
| GETADDR | `g_getaddr` | ✅ | None |
| UNSHARD | `g_unshard` | ✅ | None |
| WMMA | `g_wmma` | ✅ | None |

**The corpus CAN reach all five on this machine.** The port's `graphcmp.bend` needs 5 new builder arms, but no hardware, no device, and no multi-GPU setup is required. These are pure graph-pattern ops — they live in the eager IR and do not depend on any backend or runtime.