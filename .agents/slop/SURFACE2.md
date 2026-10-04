# SURFACE2 -- which of the missing Tensor methods a RUNTIME DEVICE needs, and how many it now has

Rule prefix for this unit: **S2-**. Regenerate everything below:

```
.venv/bin/python .agents/slop/surface2/stage1-recensus.py      # the 57, from the AST
.venv/bin/python .agents/slop/surface2/stage2-sets.py          # the note's own list, counted
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python \
    .agents/slop/surface2/stage3-classify.py                   # 39 programs, 4 seams, instrumented
.venv/bin/python .agents/slop/surface2/stage4-bins.py          # the three bins
sh .agents/slop/tensor-gate.sh                                 # the gate, both lanes, vs CPython
sh .agents/slop/surface2/asparam-mutate.sh                     # what the new rows can fail on
```

## 1. THE COUNT, RE-MEASURED, AND THE NOTE WAS WRONG IN TWO PLACES

**Denominator 57** (`ast.parse` on `tinygrad/tensor.py`, `class Tensor`: 28 public, 8
private, 21 dunder). **Present 19 of 57 (33.3%). Missing 38 of 57.**

Before this unit: **18 of 57 (31.6%), missing 39.** The 19th is `as_param` (§3).

**Two defects in `TENSOR-SURFACE.md`, both found by re-measuring rather than reading.**

- **Its ABSENT list is 38 names long and it says 39.** `18 + 38 = 56`, not 57. The one
  member in neither list is **`__del__`** (`tensor.py:102`). `stage2-sets.py` prints it:
  `in AST, in NEITHER list: ['__del__']`. The count was right and the list was short, so
  every downstream count that read the *list* was one low.
- **It says `tensor.bend` is 1,584 lines. It is 1,771** (`wc -l`), and `backward` has
  moved: the note records `backward`'s zip as `TODO(p3)` at `:951` and the zip is **ported**
  (`tn_backward` :1040, `tn_bwd_gs`, `tn_bwd_pair`, gated by `bwd-oracle.py`, whose output
  is still byte-identical to its committed capture). `__init__`, `const`, `_apply_uop` and
  `assign` are still partial. So of the 18 the note listed, **`backward` is now whole up to
  its three named arms**, and the rest of the note's per-method state column has not been
  re-checked.

**Do not inherit either number.**

## 2. THE THREE BINS, AGAINST 38 — AND NOT BY NAME

**The criterion, stated once.** A missing method is **NEEDED TO BE A DEVICE** iff invoking
it (a) crosses one of the four device seams, or (b) returns the artifact a crossing
consumes. The four seams are instrumented, not inferred:

| seam | rebound |
|---|---|
| ALLOCATE | `Buffer.allocate` |
| LAUNCH | `run_linear` |
| READ BACK | `Buffer.as_memoryview` |
| MOVE | `UOp._mop` (diagnostic only -- **not** a bin criterion) |

**The measurement is a DELTA and the delta is the whole instrument.** A first pass counted
raw totals and reported `ALLOCATE` crossed for **all 39** -- because
`Tensor([1.0,2.0], device='PYTHON')` *is* an allocation. Every program is therefore two
phases (`fx()` prepares, `use(*args)` invokes the method) and the printed number is
`use - fx`. The table's first line is its own **negative control**: a program that builds
the fixture and calls nothing reads all-zero, and it prints `SEAMS ARE QUIET`. Without
that line the whole table is an assertion.

**MOVE is excluded from the criterion, and that is a measured correction.** A first pass
counted `_mop` calls and called it RESHAPE, which put `shard` in the device bin (its
`UNSHARD` is in `GroupOp.Movement`) and `__imatmul__` (which reshapes 4 *internal*
buffers). Neither is a reshape a caller performs through the method.

| bin | n | of 38 | members |
|---|---|---|---|
| **A -- NEEDED TO BE A DEVICE** | **9** | 24% | `linear_with_vars` `schedule_linear` `realize` `_data` `data` `tolist` `numpy` `from_blob` `_next_counter` |
| **B -- NEEDED TO BE USEFUL** | **11** | 29% | `call` `custom_kernel` `_buffer` `clone` `to` `to_` `shard` `shard_` `shard_like` `__setitem__` `decode_hevc_frame` |
| **C -- NOT A DEVICE CONCERN** | **18** | **47%** | `__del__` `__bool__` `__delitem__` `from_url` `manual_seed` `__eq__` and the **twelve** `__i*__` |

**Unmeasured bin members: none.** Every one of the 38 has a program that ran against
CPython at this revision, so no bin is an argument about a name.

### What each bin BLOCKS, which is the operation and not the name

**Bin A -- 9.** The operation each blocks, in the order a caller needs them:

- **LAUNCH** (5 of the 9): `realize` is the only method that *crosses* it
  (`ALLOCATE=1 LAUNCH=1`). `linear_with_vars` and `schedule_linear` cross nothing and
  return an `Ops.LINEAR` uop -- they **produce the artifact `realize` consumes**. Reading
  `realize` alone as "the launch" and putting the other two in bin B is the error this
  criterion exists to catch: with all three absent there is nothing to hand a device.
- **READ BACK** (4): `_data` `data` `tolist` `numpy`, each `READBACK=1`.
- **ALLOCATE from an external pointer** (1): `from_blob` (`ALLOCATE=1 LAUNCH=1`).
- **ALLOCATE for the RNG** (1): `_next_counter` (`ALLOCATE=2`).

**Bin B -- 11.** Each is zero-seam and each widens *what can be written*, not whether a
device can run. `_buffer` returns the **device handle** and all four bin-A readers are
written in terms of it -- one step from the seam, not on it. `clone` (a second buffer
without a copy), `to`/`to_` (migration; the same-device arm is the identity at
`tensor.py:357-358`), `shard`/`shard_`/`shard_like` (multi-device placement), `__setitem__`
(a write *through a view*; whole-tensor writes are already `assign`'s spine), `call` /
`custom_kernel` (custom ops), `decode_hevc_frame` (a codec).

**Bin C -- 18, and this is the valuable bin: it is how you learn the real denominator.**

- **Two are REFUSALS.** `__bool__` is `raise TypeError(...)` unconditionally;
  `__delitem__` is `raise TypeError("Tensor does not support deleting items")`.
- **Twelve are OPERATOR SUGAR.** Every `__i*__` is `self.assign(self.<op>(x))`, measured
  at 0 seams and **0 movement nodes** (except `__imatmul__`, 4 — all internal). `assign`
  *is* present. `__eq__` is one line over `self.eq(x)`.
- **Two are EXTERNAL SERVICES.** `from_url` is `urllib` + `Tensor(Path)`; `manual_seed`
  writes three class dicts whose only observable is `Tensor.rand(n).numpy()`.
- **One is a GC FINALIZER.** `__del__`.

**47% of the "missing surface" is not a device concern at all.**

## 3. WHAT I CLOSED, AND ITS ROWS

**One method closed: `as_param` (`tensor.py:153-154`). 18 -> 19 of 57.**

It is the only method in `tensor.bend`'s "DEVICE HALF" block that is buildable: the other
20 there need a `Buffer`, a `fetch`, or mutable class state. Upstream it is two lines, and
`UOp.param_like` (ops.py:1241) is three arms; this ports arm 3
(`UOp.param(slot, self.dtype, self._shape, self.device)`), whose three facts are read off
the **source's own `ParamArg`** rather than recomputed -- for BUFFER/ALLOC/PARAM, `_shape`
IS `ParamArg.size` and `dtype` IS `ParamArg.dtype` (ops.py:1018, and the fold's own answer
at `fold.bend:2222`). Arms 1 (an ALU scalar re-slot, which **clears** the bound value) and
2 (a sharded UNSHARD) stay TODO, and the def answers a `Maybe` for a source it declines.

**THREE facts on ONE line, because a signature cannot see an ARG.** Gate output:

```
tn_asparam=1 PARAM/0  tn_asparam_slot=3 tn_asparam_ne=True      BEND
tn_asparam=1 PARAM/0  tn_asparam_slot=3 tn_asparam_ne=True      CPython, CALLED
```

**`sh .agents/slop/tensor-gate.sh`: `--check-only` clean, interpreted == native byte
identical, and the diff against CPython reports nothing for the new line.** The full
tensor gate and `.agents/slop/backward/bwd-oracle.py` are both unchanged and green.

**The rows can fail, and the harness says WHICH fact moves** (`asparam-mutate.sh`, four
one-token edits, each applied/run/reverted):

| arm | edit | signature | `slot` | `ne` | verdict |
|---|---|---|---|---|---|
| A21 | drop the slot (`slot` -> `0`) | **UNCHANGED** | 3 -> 0 | T -> F | MOVED |
| A22 | forward the SOURCE's slot | **UNCHANGED** | 3 -> 0 | T -> F | MOVED |
| A23 | wrong op (`PARAM` -> `BUFFER`) | `PARAM/0` -> `BUFFER/0` | UNCHANGED | UNCHANGED | MOVED |
| A24 | no-op (control) | UNCHANGED | UNCHANGED | UNCHANGED | **NOTHING** |

A21 and A22 leave the signature **byte-identical** and A23 leaves the arg facts
**byte-identical**: no single mutation is caught by the signature alone, which is why the
row is three facts.

**Two methods I did NOT close, and why -- an ungated method is an assertion.**

- **`__bool__` and `__delitem__`**: both are refusals whose entire observable is an
  exception. A pure Bend def cannot raise (the file's own wall at `:331`), so the only
  expressible port is a def that traces nothing -- and a row over a def whose body is a
  literal asserts that a constant. **Not closed, deliberately.**
- **`manual_seed`**: ungateable *by nature*. It returns `None` on both lanes, and its only
  observable is `Tensor.rand(n).numpy()`, which needs RNG + `realize` + readback.

## 4. WHAT I FOUND IN UPSTREAM AND DID NOT FIX

**`Tensor.decode_hevc_frame` is inoperable in CPython at this revision.**
`tensor.py:563` passes `arg="encdec"`, a bare `str`, where `ops.py:1259` declares
`CustomFunction(name: str, dtype: DType = dtypes.void)`. So `dtype_from_uop` reaches
`arg.dtype` on a string and raises `AttributeError`, and **the graph it returns has no
readable shape** (`stage3-classify.txt` prints `holds=AFTER shape=<AttributeError>`). The
call itself succeeds -- nothing in its own path asks for the shape -- so this is a latent
break that only a reader hits. Reported, not fixed: `tinygrad/` is not mine.

## 5. THE HONEST DEVICE CLAIM, IN ONE SENTENCE

**The port is a device-shaped lazy graph builder that can allocate, reshape, launch and
read back through 9 ported methods and one I added, but its Tensor surface is 19 of 57 and
the gap is not uniform: 9 of the 38 are device-necessary, 11 widen what can be written, and
18 are not device concerns at all.**

## 6. THE CLAIM I REFUSE TO MAKE

**I will not write that the port is a device, and the bin table says why.**

- **`bw` is the gradient of one eager expression; the corpus is not a training-graph
  corpus.**
- **`schedule -> render -> compile` is forward-only.** `late` and `allred` are graphs the
  port **reproduces and does not produce** -- it writes the rewritten graph into its arena
  and does not implement `get_late_rewrite_patterns`. **Reproducing a graph and producing
  it are different claims**, and a corpus built of reproducible graphs can look identical
  to one built of producible ones.
- And the measurement above adds a fourth: **bin A is 9 of 38, and 4 of those 9 are the
  read-back side, 5 the launch side, and `realize` is the only one that crosses a seam at
  all.** A port whose *entire* device-necessary surface is a name whose invoke crosses one
  seam is not yet a device; it is a graph builder with one launch and four readers named.
  **The gap is in bin A**, and bin A is the smallest bin of the three.

## 7. FILES

| file | what |
|---|---|
| `.agents/slop/surface2/stage1-recensus.py` / `.txt` | the 57 from the AST, with kinds |
| `.agents/slop/surface2/stage2-sets.py` / `.txt` | the note's list counted: 38, and `__del__` |
| `.agents/slop/surface2/stage3-classify.py` / `.txt` | 39 programs, 4 seams, delta + control |
| `.agents/slop/surface2/stage4-bins.py` / `.txt` | the three bins, cross-checked per member |
| `.agents/slop/surface2/asparam-mutate.sh` / `asparam-mutations.txt` | A21-A24 |

Edited (both are `tensor.bend`'s own gate, and a closure without a row is an assertion):
`tinybendygrad/tensor.bend`, `.agents/slop/tensor-gate.py`. Nothing else was touched; no
commit was made.