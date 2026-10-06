# Four Remaining Ops Report — 2026-10-06 (`buffergraphs`)

## Summary

**4 ops remaining → 4 authored, 0 blocked. COVERAGE 66 of 70 → 70 of 70.** All four are
program nodes, not non-nodes: the denominator stays **70**, not 69 (evidence in §5).

| op | fixture | `emit --side py` line containing the op | rc |
|---|---|---|---|
| `CUSTOM_FUNCTION` | `g_custom_function` | `2:i6 15:CUSTOM_FUNCTION 4:void 1:R 2:i0 1:N 15:cF(smyfn,Dvoid) 5:n(i5)` | 0 |
| `MSELECT` | `g_mselect` | `2:i9 7:MSELECT 3:f32 11:(l0:4,l0:3) 2:i0 1:N 2:i0 5:n(i8)` | 0 |
| `MSTACK` | `g_mstack` | `2:i8 6:MSTACK 3:f32 11:(l0:4,l0:3) 2:i0 1:N 1:N 8:n(i5,i7)` | 0 |
| `STAGE` | `g_stage` | `2:i8 5:STAGE 3:f32 11:(l0:4,l0:3) 2:i0 1:N 1:N 5:n(i7)` | 0 |

Fixtures added to `.agents/slop/graphcmp.py` before `GRAPHS` and registered in it (diff: +57/−1).
**Not** added to `WANT` or `PINS` — see §4.

## 1. How upstream CREATES each (creation sites, measured)

| op | creation site (`file:line`) | arg shape | src shape |
|---|---|---|---|
| `CUSTOM_FUNCTION` | `tinygrad/uop/ops.py:1257-1259` (`UOp.custom_function`, staticmethod) | `CustomFunction(name: str, dtype: DType = dtypes.void)` (`ops.py:1393-1397`) | `*src` (any arity; `spec.py:111` allows any length) |
| `MSELECT` | `tinygrad/uop/ops.py:769` (`UOp.mselect`); also minted at `:762` inside `copy_to_device` when `arg` is given | `int` (the lane index) | `(self,)` — **must be tuple-device**, `spec.py:183` |
| `MSTACK` | `tinygrad/uop/ops.py:770` (`UOp.mstack`) | `None` | `(self,) + srcs` |
| `STAGE` | `tinygrad/uop/ops.py:676` (`UOp.bufferize`); tangent `tinygrad/mixin/elementwise.py:66` (`uop.alu(Ops.STAGE)`) | `None` (or a `ParamArg` opts when `bufferize(arg=...)`) | `(self,) + args` |

These sit in the enum's **section 6**, `# ** 6 -- ops that don't exist in programs **`
(`tinygrad/uop/__init__.py:85-98`), alongside `COPY`. **`COPY` is reached by `allred`, so the
section is not uniformly unreachable** — each was measured, not inherited.

## 2. Reachability findings

- **`CUSTOM_FUNCTION` needs a `CustomFunction` arg, and a `void` dtype gives no shape.** The
  arg is a dataclass (`name`, `dtype`), NOT the bare `str` the file's own header records at an
  older pin (`tinygrad/tensor.py:563` still spells one as `arg="encdec"`, which `carg`'s
  `cF(x.name,x.dtype)` arm would crash on). Reached via `UOp.custom_function("myfn", a)`;
  `dtype=void` → `_shape` is `None` (`ops.py:374`) → shape column `R`.
- **`MSELECT` needs a tuple-device src at spec level** (`spec.py:183`), which is why the
  fixture goes through `copy_to_device(("CPU","CPU"))` first — `copy_to_device` mints the
  DEVICE range (`ops.py:765`). No `arg` can be passed to `copy_to_device` directly because the
  source is single-device (`ops.py:761` asserts `self.device` is a tuple).
- **`MSTACK` is spec-legal over two single-device srcs** (`spec.py:184`); hand-written after the
  `MULACC`/`GETADDR` precedent.
- **`STAGE` has exactly one eager route.** `Tensor.contiguous()` (`elementwise.py:59-66`) mints
  `uop.alu(Ops.STAGE)` only when the value has **no buffer identity**; `Tensor.empty`'s ALLOC
  has one (`ops.py:954-959`), so `Tensor.empty(4,3).contiguous()` is a no-op and the fixture
  must take `+ 1` first. This is why it needs no ASSIGN/buffer context — the `+ 1` provides the
  non-buffer-identity value.
- All four carry device `sCPU`, which matters: the oracle hard-fails when the two sides open
  different devices (§5).

## 3. Before / after, measured

The coverage numerator is py-only (`graphcmp-oracle.py:303` `tal.update(py["per_op"])`), so the
before was measured both ways:

| measurement | instrument | result |
|---|---|---|
| before, py-only | `.agents/slop/buffergraphs/coverage-pyonly.py` | `66/70`, unexercised `['CUSTOM_FUNCTION','MSELECT','MSTACK','STAGE']` |
| after, py-only | same | `70/70`, unexercised `[]` |
| after, full oracle | `graphcmp-oracle.py` → `oracle-after.out` | `COVERAGE: 70 of 70 program ops === 70 of 77 enum members` |

**`ORACLE SELFCHECK: FAIL` (rc=1) after, with exactly two `bad` entries, both pre-existing and
neither mine:**

1. `getaddr: the two sides opened DIFFERENT devices -- py ['sCPU'] against bend []` — from the
   prior unit's `g_getaddr`, whose bend arm emits a single bottom node with no `ParamArg`.
2. `unmapped arg atom letters: B` — the port emits its arena-bottom arg as the literal `BAD`
   (`graphcmp.bend:457`), and `BAD` appears **only** in `getaddr`'s bend stream (the `?,BAD`
   live-ledger in the oracle table). No py-side arg anywhere carries `B` (measured with
   `find-bad.py B` → no output).

Both are `getaddr`-attributable. My four fixtures fall back to the matmul on the bend side
(`custom_function 6/18`, `mselect 9/18`, `mstack 8/18`, `stage 8/18` in `oracle-after.out`), so
they add **no new bend atom and no new device** — the SELFCHECK verdict is unchanged by this
edit. **The full before-oracle could not be completed: `graphcmp.bend` is currently mid-edit by
another unit (uncommitted `M` in git) and its bend probe fails to compile at `g_mulacc()`
(`emit bend: 0 rows after 5 attempts`). That is a port-side file I do not own and another unit
holds `bend` exclusively.**

## 4. Expected verdict once a bend arm exists

The py side emits clean rows and passes the control tests. The bend side **currently** falls
back to `g_matmul` for all four names (`graphcmp.bend:1363` default), so each currently carries
`DISAGREE`. Once `graphcmp.bend` has a builder per op — mirroring `g_custom_function` /
`g_mselect` / `g_mstack` / `g_stage` — each would carry **`AGREE`**.

**Not added to `WANT`/`PINS`.** A graph absent from `WANT` is `UNSET`, not agreed; `WANT` and
`checks/differ.py`'s corpus must not grow silently.

## 5. All four ARE program nodes — denominator stays 70

Section 6's title (`ops that don't exist in programs`) matches **none** of the oracle's
`NON_NODE_MARKERS` (`graphcmp-oracle.py:195`), so its members are not excluded by construction.
The independent proof is `COPY`: it lives in the **same section 6** (`__init__.py:91`) and is
already reached by `allred`, so a section-6 op can be a program node. The oracle's own three-way
partition confirms it — before: `AND 4 ARE PROGRAM OPS NO GRAPH DRIVES YET (unexercised):
CUSTOM_FUNCTION MSELECT MSTACK STAGE`. **The denominator is 70, not 69.**

## 6. Final tally

| op | fixture | authorable? | blocking thing | verdict once port arm exists |
|---|---|---|---|---|
| `CUSTOM_FUNCTION` | `g_custom_function` | ✅ | None | AGREE |
| `MSELECT` | `g_mselect` | ✅ | None | AGREE |
| `MSTACK` | `g_mstack` | ✅ | None | AGREE |
| `STAGE` | `g_stage` | ✅ | None | AGREE |

**4 ops → authored 4 · blocked 0 · COVERAGE 70 of 70.** No hardware, no device, no multi-GPU
setup. The only remaining gap is four port-side builder arms in `graphcmp.bend`, which another
unit owns.

### Artifacts (under `.agents/slop/buffergraphs/`)
`probe.py` (reach probe) · `emit-{custom_function,mselect,mstack,stage}.out` (emit transcripts) ·
`coverage-pyonly.py` (before/after py-only) · `find-bad.py` (atom attribution) ·
`oracle-before.py` (full before, blocked by bend) · `oracle-before.out` / `oracle-after.out`.
