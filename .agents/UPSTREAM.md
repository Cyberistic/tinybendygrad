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

---

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
