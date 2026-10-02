# UPSTREAM.md — defects in tinygrad (CPython), found by porting

**Append-only.** Add new defects at the end; never renumber or rewrite an existing entry
except to correct it, and say what corrected it.

## Why this file exists

Porting a file line by line against a live CPython oracle finds bugs in **both** sides.
Most of what looks like an upstream bug turns out to be the port being wrong — and the two
must never be confused, because **a port "fixed" to match an upstream bug is worse than a
red file**: it converts a loud failure into a silent wrong kernel, and it makes the gate
green over a defect.

So this ledger exists to keep the two apart:

- **The port is wrong** → fix the port. Ordinary work.
- **Upstream is wrong** → record it HERE, with a reproduction, and do not bend the port to
  match it.

A third category is just as important and just as often: **it looks wrong but is not.**
Those are recorded too, in the "not defects" section, because the cost of *re-investigating*
one of those is as high as the cost of missing a real one.

**A naming collision to be aware of.** `.agents/slop/notes/bend2-constraints.md` uses
"upstream" to mean *an earlier commit of this port* — e.g. its `dm_floordiv`/`H.asr` note is
about Bend helpers being wrong, not tinygrad. In THIS file, "upstream" always means
**tinygrad / CPython**.

---

## D1 — `rangeify.py:113`: `cast(UOp, ...)` is a no-op, and `int` has no `.eq`

**Status: CONFIRMED mechanism and reachability. NOT reproduced end-to-end** (see below.)

`tinygrad/schedule/rangeify.py:113`, inside `after_all_invalid`:

```python
and resolve(cast(UOp, prod(r.src[0] for r in s.ended_ranges)).eq(buf.numel()), False)
for s in after.src[1:])
```

When `s.ended_ranges` is empty, `prod(...)` is the **`int` 1**. `cast(UOp, 1)` returns the
bare `1` — verified, `cast` does no coercion here — and `int` has no `.eq`, so this raises
`AttributeError` **before `resolve` can supply its `False` default**. The annotation's
intent (coerce to a `UOp` so `.eq` exists) is not achieved.

**Reachability.** `tinygrad/uop/ops.py:472`:

```python
if self.op is Ops.END: return tuple(r for r in self.src[1:] if r.op is Ops.RANGE)
```

So an END whose `src[1:]` contains no RANGE has `ended_ranges == ()`. That is not
exotic — the comprehension *filters* non-RANGE entries, which means it already expects
`src[1:]` to sometimes hold non-RANGE nodes, and a multi-device END whose extra sources are
all non-RANGE lands exactly here.

**Verified here, precisely:** `cast(UOp, 1)` returns `1`; `hasattr(1, "eq")` is `False`;
`ops.py:472` filters rather than asserting. **Not verified:** a full triggering UOp graph.
Constructing one needs an END whose `src[0]` is a STORE with an invalid base, and that was
judged not worth hand-building for a ledger entry. **The reproduction below is the honest
shape of it and is known to need the STORE/invalid-base prefix to reach line 113.**

**Fix (upstream's to make, not ours):** give `prod` a non-empty seed, or compare without
`.eq`, e.g. `resolve(int(prod(...)) == buf.numel(), False)`.

**What the port does.** `tinybendygrad/schedule/rangeify.bend` reports this at its
`ct_7` wall rather than working around it, and `ct_7` is left walled on `_min_max`. The
port does **not** silently swallow it.

---

## D2 — `ops_bend.py`: the LOCAL param arm is unreachable, and `__init__` can hang

**Status: CONFIRMED by measurement, both parts.**

**D2a — `k:param:..:l` cannot be emitted, and the file says it can.** `ops_bend.py:112-113`
claims the `l` (LOCAL) arm is "spelled rather than refused", and `:36` lists `<g|l|r|a>` — but
the dict at `:116` has keys `GLOBAL` and `REG` only. A LOCAL param therefore raises
`KeyError: 'LOCAL'`. Measured by driving the function, not by reading it. Either the comment
and the `:36` grammar are aspirational, or a dict key is missing.

**D2b — `BendProgram.__init__`'s `:208` `while` has no termination guard.** A packet
containing a cycle hangs **CPython as well as the port**. This is why synthetic
"arm-reordering" fixtures hang and had to be dropped from the port's oracle: they hang the
authority too, so there is no answer to compare against.

Both were found by porting, and in both cases the port reports the divergence rather than
bending to match — see `runtime/ops_bend.bend`, which gates the `KeyError` and keeps 32 rows
red under a named wall.

---

## NOT defects — investigated, and it is important they are written down

Each of these looked like an upstream bug and is not. Recorded so nobody spends a turn on
them again.

**N1 — `device.py:366` `iter_sig` advances from the un-aligned offset.** NOT an upstream
defect. `yield (offset := round_up(offset, dt.itemsize)), dt` followed by
`offset += dt.itemsize` rebinds `offset` to the *rounded* value, so the next offset is
`round_up(off, k) + k`. The PORT read `off + k` and drifted. Our bug, fixed in `7f170f64`,
and it had been encoded in a committed gate row as if it were intentional.

**N2 — `ops_dsp.py`'s `ClangRenderer(Target("DSP", "CLANG", "hexagonv65,..."))` raises
`RuntimeError: unsupported arch`.** NOT a defect: it is *why* `DSPRenderer.__init__:18`
skips `super().__init__`. Gated as `dsp_no_super_init` in `ops_dsp.bend`.

**N3 — `ops_rdma.py:194`'s `sc=0x04020200` is not `rpc_sc(2, 2, 1, 0)`.** NOT a defect. They
differ by exactly the method byte; the literal is the greeting and rewriting it as an
`rpc_sc` call sends method 2 and the DSP never greets. Gated as `dsp_rpc_greet_*`-style rows.

**N4 — `range(0, n, 0)` raises in CPython.** NOT a defect; the PORT's comment claimed
otherwise and is what was wrong. Now an `assert` in `ops_disk.bend`'s oracle.

**N5 — `nv_query_litter` said 2 of `_query_gpu_info`'s five requests take the LITTER
fallback.** NOT an upstream defect: the truth is 3, at `{0, 1, 2}` (verified by evaluating
`ops_nv.py:664`'s own `getattr` chain against `nv_570`; resolved indices 20, 23, 32, 13,
12). The PORT and the ORACLE were both hand-written and both wrong. Our bug, twice.

**N6 — `runtime/support/am/amdev.bend`'s `AMDev.setup_ring`.** NOT an upstream defect and
not a missing feature. `ops_amd.bend` recorded a `setup_ring` TODO against `amdev.py`, but
`amdev.py` has no `setup_ring` at all — the ring arithmetic is `AM_SDMA`/`AM_GFX` in
`ip.py`. A mislabelled wall in our own committed file.

**N7 — `dm_floordiv` / `dm_floormod` / `H.asr` give wrong answers.** NOT upstream. These are
Bend helpers in our port, wrong on their own terms: `dm_floordiv` truncates toward zero and
ignores the sign (`6 // 4 == 2`, `10 // 3 == 4`, `1000 // 7 == 143` where Python says 1, 3,
142), and `H.asr(-1, 1) == 2147483647` where the answer is `4294967295` because `shrn(v,31)`
is the sign BIT, so `shrn(shrn(v,31), n)` is 0 for every `n >= 1`. Both are UNUSED and
UNTESTED in `helpers.bend`, which is why ten green rows in another unit never saw them.
The local fix and the removal condition are in `divandmod.bend` / `helpers.bend`.

**N8 — `runtime/support/hcq2.py`'s `encode_submit` → `encode_cmdbuf` rename, and
`ops_metal.py`'s rewrite onto it, are NOT defects.** NOT upstream, and specifically not a
regression: they are a deliberate restructure (the `HWQueue.encode` method, the
`uopfunc`-based `hcq_fence`/`mtl_run`, and `encode_cmdbuf(hq, lin=None, name=..., device=None)`
absorbing the old `bufferize_cmdbuf` + `encode_submit` pair). Our `hcq2.bend` and
`ops_metal.bend` describe the OLD shape, and their header line tables (`:479-481` for
`encode_submit`, `:455-477` for `bufferize_cmdbuf`) will need rewriting — that is drift
work, not a bug report. What IS worth knowing is that this rename is what makes `hcq2.py`
un-re-vendorable on its own; see `.agents/UPSTREAM-PIN.md`'s coupling note.

---

## D2 — `renderer/cstyle.py:191`: `_render_dtype` lost its `type_map` fallback and now raises `KeyError` for 18 of 102 dtype×renderer pairs

**Status: CONFIRMED mechanism, exhaustively enumerated. NOT reproduced on a real end-to-end
kernel** (see "Not verified" — and note that this cuts in upstream's favour: it may well be
an unreachable tightening.)

Found by the drift pass of 2026-10-02, while closing `UPSTREAM-PIN.md`'s work list. It is
two upstream commits acting together, and neither is wrong alone.

**Commit A — `dtype.py` changed every `DType.name` from the C spelling to the short form.**

```python
-  int8: Final[DType] = DType.new(1, 8, "signed char", 'b')
+  i8: Final[DType] = DType.new(1, 8, "i8", 'b')
...
-  float32: Final[DType] = DType.new(14, 32, "float", 'f')
+  f32: Final[DType] = DType.new(14, 32, "f32", 'f')
```

**Commit B — `cstyle.py` gave `CStyleLanguage` a fixed 14-entry `type_map` and dropped the
`.get(dtype, dtype.name)` fallback in `_render_dtype`.**

```python
-      return prefix + self.type_map.get(dtype, dtype.name).replace(" ", "_") + str(sz) + suffix
-    return prefix + self.type_map.get(dtype, dtype.name) + suffix
+      return prefix + self.type_map[dtype].replace(" ", "_") + str(sz) + suffix
+    return prefix + self.type_map[dtype] + suffix
```

The fallback was load-bearing for exactly the dtypes the new map omits. `type_map` covers
`void, bool, i8, u8, i16, u16, i32, u32, i64, u64, f16, bf16, f32, f64` and nothing else —
no `weakint`, no `weakfloat`, and **no fp8**. Before A, a missing entry answered
`dtype.name`, which for fp8 was the usable C-ish name `float8_e4m3`; after A the fallback
would answer the useless `fp8e4m3`, so B removed the fallback rather than carry a wrong
answer — and in doing so turned a silent-wrong into a loud crash for the dtypes that have no
entry at all.

**Reachability, enumerated exhaustively** (both trees extracted whole with `git archive`, so
this is upstream's code and not a partial re-vendor). Calling `_render_dtype(dt, 1, None)`
for all 17 `dtypes.all` × 6 renderers, at `87a4311b3`:

| renderer | dtypes that raise `KeyError` |
|---|---|
| `CStyleLanguage` (BASE) | `fp8e4m3`, `fp8e5m2`, `fp8e4m3fnuz`, `fp8e5m2fnuz` |
| `ClangRenderer` | the same four |
| `OpenCLRenderer` | the same four |
| `MetalRenderer` | the same four |
| `CUDARenderer` | `fp8e4m3fnuz`, `fp8e5m2fnuz` |
| `HIPRenderer` | `fp8e4m3fnuz`, `fp8e5m2fnuz` |

**18 of 102 combinations.** At the pin `6c3d401cf324`, all 102 return a string. `weakint`
and `weakfloat` are absent from every `type_map` too, but they are unreachable through
`_render_dtype` on a rangeified graph because the `UPat.cvar("c").cast()` rules consume
CONSTs first — EXCEPT on an un-rangeified graph, where `renderer-oracle.py`'s `f_range`
fixture has a `CAST(LOAD(f32) -> weakint)` node and dies with `KeyError: dtypes.weakint`.
That fixture is a synthetic graph, so it is evidence of the shape, not of a real kernel.

**Verified here, precisely:**
- `cstyle_oracle.py` against the **pin** tree: **210 rows, rc 0.**
- `cstyle_oracle.py` against **upstream** `87a4311b3`: **`KeyError: dtypes.fp8e4m3`, 0 rows,
  rc 1** — the unit's own oracle cannot produce a single row any more.
- The 18-cell table above, by direct `_render_dtype` calls.
- The `tmap` rows change **value** even where nothing raises: `type_map.get(dt, dt.name)`
  over `dtypes.all` answers `fp8e4m3,fp8e5m2,fp8e4m3fnuz,fp8e5m2fnuz` where the pin answers
  `float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz`, on all six renderers, and the
  two `fnuz` entries additionally change on CUDA and HIP. **That is 6 of our committed
  `tmap` rows whose expected values are now stale for a reason that is upstream's rename
  and not our bug** — they must be re-derived from the new oracle, not hand-edited.

**Not verified:** whether a real end-to-end kernel reaches any of the 18. Five real kernels
(`mul`, `sum`, `matmul`, `cast`, `stack`) render fine on upstream with `DEV=PYTHON`, and I
could not run an fp8 kernel because `tinygrad/runtime/ops_clang.py` is absent from both
trees in this checkout. So this is a **CONFIRMED defect in the function**, with reachability
from a real kernel unestablished. Given commit B's shape — deliberately dropping a fallback
whose answer had just become wrong — the charitable reading is "fp8 is not renderable on
these backends and now says so", which makes this a **missing error message on an
intentional restriction** rather than a crash bug. Either way it is upstream's to word.

**Fix (upstream's to make, not ours):** either add the four fp8 names to the base map (they
were the `.name` fallback values and some backend will need them), or make `_render_dtype`
raise a `KeyError` that names the dtype and the renderer, which it half does already.

**What the port does:** `renderer/cstyle.bend` does NOT bend. It keeps the pin's C spellings
(`signed char`, `float`, `__bf16`, …) because those are what a C backend wants, and its
`type_map` rows are the authority for the spelling rather than `dtype.name`. Its `tmap`
rows are **recorded as needing re-derivation**, not edited — see the drift report. The port
diverges from upstream on `dtype.name` deliberately: upstream's `DType.name` is now a dtype
IDENTIFIER (`f32`), and a C type name is a renderer concern, so the port's split (dtype name
vs renderer type_map) is the more defensible shape.

---

## Where upstream defects get integrated

`.agents/UPSTREAM.md` records what upstream got WRONG. `.agents/UPSTREAM-PIN.md` records how
far the port has drifted from upstream and the workflow for closing that gap. They are
different questions and both are needed: a defect is a bug to report, a drift is work to do.

If an upstream change looks like a bug, do NOT bend the port to match it -- put it here, and
say plainly in `.agents/TODO.md` that the port diverges from upstream on that line and why.

## Template for a new entry

```
## Dn — <file>:<line>: <one-line symptom>

**Status: CONFIRMED | MECHANISM-ONLY | SUSPECTED**

<the offending source, quoted>

<the mechanism: why it goes wrong, and which Python-level fact makes it wrong>

**Reachability.** <what input reaches it, with the code that establishes that>

**Verified here, precisely:** <the commands or facts actually checked>
**Not verified:** <what was not, and why that was acceptable>

**Fix (upstream's to make, not ours):** <the change, or why there isn't one>

**What the port does.** <whether the port bends to match it, and where it is recorded>
```

Rules: quote the source, do not paraphrase it. Separate what you verified from what you
inferred — every entry above does, and D1 is only "confirmed" for its mechanism. If a
suspected defect turns out not to be one, **move it to the "not defects" section and keep it
there**; that is the section that saves the most time.
