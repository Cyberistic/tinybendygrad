# foldgap REPORT — the fold's `?` class: an arm that is MISSING, and an arm that is WRONG

Unit: `tinybendygrad/uop/fold.bend` (the dtype/shape ladder `dt_shape`). **STATIC-ONLY: I did
NOT run `bend`** (another unit holds it). Every claim below is a read of the source or of the
PIN, or a CPython measurement of `_broadcast_shape`; the `bend`-gated claims are named as such
in §7. No `git add`, no commit, no `@`. Files written: `tinybendygrad/uop/fold.bend`,
`.agents/slop/foldgap/{population.py,population.rows,population-before-edit.rows,wmma-broadcast.rows,fold.diff.out,fold.md5.txt,REPORT.md}`.

> **A CONCURRENT UNIT IS EDITING `fold.bend` LIVE.** While this report was written,
> `md5(fold.bend)` changed on nearly every read (≥6 distinct hashes in ~2 minutes); the body of
> `wmma_shapes.put` was rewritten (mine was one recursive `match ds` def; on disk it is now a
> two-pass `.fold`/`.go` of undetermined final shape). **So replace every line number below by
> the DEF NAME**: the file moves under both units. `git diff -- fold.bend` is snapshotted at
> `.agents/slop/foldgap/fold.diff.out` and the hash at `fold.md5.txt` (`03961da8…`). My two
> landings (`stage_ds`/`stage_shape`, and `wmma_ds.go` -> `wmma_shapes.of`) were present at
> every read; the exact `wmma_shapes.put` body is the OTHER unit's to settle — it is a rewrite
> of the same fix, and `wmma_shapes.of` + `wmma_ds.go` are the load-bearing pair either way.

## 1. The population, by DISCOVERY (doctrine 1)

`dt_shape` (`def dt_shape`, `fold.bend:2282` at HEAD) is a `match op` with one arm per
`Ops` member — the match is TOTAL (the closing `raise RuntimeError(f"no dtype for {op}...")` of
upstream is not reachable). `.agents/slop/foldgap/population.py` reads the enum's OWN
declaration (`ops.bend`, `type Op is Data:`) and `dt_shape`'s arms, and classifies each body.
It emits `.agents/slop/foldgap/population.rows` (before: `population-before-edit.rows`).

**The question is not "where is STAGE's arm". It is "how many members share its answer".**

| | BEFORE my edit | AFTER my edit |
|---|---|---|
| enum members (N) | **77** | 77 |
| arm present (M) | 77 (0 absent, 0 stray) | 77 |
| `derived` (a real `_ds` def) | 64 | 65 |
| `late()` (honest `void`+no-shape) | 11 | 11 |
| **bare `None{}` (K)** | **2 — STAGE, UNSHARD** | **1 — UNSHARD** |

The bare-`None{}` scan finds **2**. It is not the class. A third member has an arm that
EXISTS and computes the WRONG thing — `OpsWMMA` is `derived` by the scan and a `?` producer in
fact (§3). **A population by the body's SPELLING cannot see a wrong body; only reading it can.**

## 2. The upstream rule for each, from the PIN (`git show 'ad117c928^:tinygrad/uop/ops.py'`)

- **STAGE dtype** — `ops.py:147-152`: STAGE is in the pass-through group
  (`LOAD | UNSHARD | REDUCE | AFTER | RANGE | ... | STAGE | ...`), so `return src[0].dtype`.
  **DERIVABLE.**
- **STAGE shape** — `ops.py:378-380`:
  `return tuple([int(r.vmax+1) for r in self.src[1:]]) + self.src[0].shape`. The prepend is
  empty iff STAGE has no range srcs (the same-device `bufferize`, `ops.py:679`). With ranges,
  `r.vmax` is `_min_max(r) = (0, (r.src[0]-1).vmax)` (`ops.py:1147`). **DERIVABLE for the
  no-range case; the range case needs `_min_max`.**
- **WMMA dtype** — `ops.py:162-164`: `case Ops.WMMA: return src[2].dtype` (the accumulator).
  **DERIVABLE, and INDEPENDENT of shape.**
- **WMMA shape** — `ops.py:383-386`:
  `wmma_b = _broadcast_shape(self.src[0].shape[:-1], self.src[1].shape[:-1],
  self.src[2].shape[:-1]); return wmma_b + (self.src[2].shape[-1],)`. **DERIVABLE.**
- **UNSHARD dtype** — `ops.py:147-152` (UNSHARD is in the same pass-through group as STAGE):
  `return src[0].dtype`. **DERIVABLE.**
- **UNSHARD shape** — `ops.py:400-401` (`if len(self.src) == 0: return None`) then the movement
  arm `ops.py:432` `tuple(s*(int(self.src[1:][self.arg.index(a)].vmax)+1) ...)`. **Needs
  `_min_max` for every sharded axis.** (port's own note: `case O.OpsUNSHARD{}: None{}`, and
  `schedule/prepare.bend:781`/`:919`.)

`_min_max` itself IS ported (`fold.bend` DONE(p3) `ops.py:1104`; `UOp.vmax` over a `BTable`),
but `dt_shape` is handed no `BTable`, so the range/vmax half is not reachable from an arm —
that is the wall, not a missing implementation.

## 3. Which of the K is a PORT GAP vs an honest unknown

**K = 2, and BOTH are PORT GAPS; 0 are honest unknowns.** Their dtypes ARE derivable upstream
(`src[0].dtype`); the port simply has no arm. An **honest unknown in this tree is the `late()`
arm** — `void` with no shape, which is exactly upstream's `always void` + `late ops don't have
shape` — and there are 11 of those, none in K.

The third member of the class is **WMMA**, and it is a PORT GAP of a *different* spelling: the
arm exists but **broadcasts the FULL shapes where upstream broadcasts `shape[:-1]`**. MEASURED
(`.venv/bin/python`, `.agents/slop/foldgap/wmma-broadcast.rows`):

```
_broadcast_shape((4,4),(4,3),(4,3))  ->  RAISES IndexError
_broadcast_shape((4,),(4,),(4,))      ->  (4,)
```

The port's pre-edit `wmma_ds` (`fold.bend:1304` old) was
`wmma_ds.go(src_dt(2, ss), all_shapes(List.take(ss, 3n)), src_last(2, ss))` — `all_shapes` is
the FULL shapes — so for the normal WMMA where K != N it raised, `wmma_ds.of` returned `None`,
and the node read `?`/`?`. Upstream's `(4,) + (acc[-1]=3,)` = `(4,3)`. **This is the one
`?` the brief calls "one missing mechanism": it is not a missing arm, it is a full-shape
broadcast where the rule says `[:-1]`.**

## 4. The arms I LANDED, and the one I could not

**Landed (both fully derivable):**

1. **WMMA shape** — `wmma_ds.go` (≈1318) now wraps `wmma_shapes.of`, and `wmma_shapes.of`
   (≈1315) drops the last dim of each operand and carries the LONGEST DROPPED shape as
   `Shapes.m` (the broadcast walk right-aligns against `m`, so the pre-drop max would pad one
   dim too far). `wmma_shapes.put` (≈1294-1306, a concurrent rewrite) is the accumulator.
   WMMA dtype (`src[2].dtype`) was already read; the shape refusal was what took it away.
2. **STAGE** — `stage_ds`/`stage_shape` (≈1338-1348); the arm
   `case O.OpsSTAGE{}: stage_ds(ss)` (≈2473). dtype = `src_dt(0, ss)`; shape = `src[0]`'s
   when the tail is empty, else REFUSED (`dt_of(dt, None)` -> the whole node is `None` ->
   `?`). For `--graph stage` (`graphcmp.bend:1549`, one src, no ranges) this now answers
   `f32` + `(4,3)`.

**NOT landed, with the reason:**

- **STAGE with a range src** — the shape needs `int(r.vmax+1)`; `dt_shape` has no `BTable`.
  The whole node stays `?` `dt_of` refuses a `None` shape, and returning `DtShape{dt, None}`
  would CLAIM upstream's `_shape` is `None`, which is a **lie** (upstream answers a tuple) —
  the brief's own rule: a fabricated `Derived` is worse than a measured `?`.
- **UNSHARD** — dtype IS derivable (`src[0].dtype`) but the shape is the same vmax wall, and
  the fold answers dt+shape TOGETHER (`DtShape`), so a dtype-only answer is not expressible
  without the same lie. `dt_shape`'s `case O.OpsUNSHARD{}: None{}` stays; `schedule/prepare.bend:781`/`:919`
  ("no UNSHARD dtype rule") stay TRUE. This is the remaining member of K.

## 5. The ripple — every reader of the fold's answer for these ops

- `fold.bend` `derived` -> `derived.of` -> `dt_shape`; a `None` from `dt_shape` is
  `derived.put`'s `None`, so the node is absent from the `Table`.
- `fold.bend` `Kahn.settled` = `Table.len(tb) == Arena.next(ar)`. **ONE absent node makes
  the WHOLE graph `settled=False`**, which is why a single `?` unsettles a graph.
- `fold.bend` `fold.shape`, `fold.dt` — the two per-node readers; outer `None` -> `?` in the
  differ (`?` ledger), inner `None` -> `R`.
- `.agents/slop/graphcmp.bend:1640-1641` prints the probe header's `settled=`.
- `fold.bend:~5600` `mmk_sibling`/`mmkx_sibling_stage` and the harness
  `.agents/slop/mm-walk-gate.py:108` (`D = [("stage", UOp(Ops.STAGE, (c(0),)))]`): my STAGE
  arm makes that one-src STAGE **answer**, so `mmkx_sibling_stage` moves from `ABSENT` to an
  interval and that `D` entry (its DIVERGES block) must be re-baselined. **No active gate
  covers it** (`grep mmkx_ gates/ oracles/` = none; the oracle imports a `/private/tmp` path).
  I updated the two stale prose blocks in `fold.bend` (`:116-118`, `:~5542-5552`) and left the
  harness alone.
- `tinybendygrad/schedule/prepare.bend:781`/`:919` (UNSHARD gap) and
  `.agents/slop/beautiful-mnist-gate.py:224` (PERMUTE, untouched) are UNCHANGED.

**`graphcmp.py:2178` "NO LIVE FIXTURE ANY MORE" — it becomes TRUE after this change.**
armfour measured `stage` reading `?=0/2` on the live driver, so the sentence was **stale
FALSE at that run**: `stage` WAS a live `?` fixture. WMMA is a second. With §4 landed, both
`stage` and `wmma` settle, and `sym`/`loop`/`bw` already read `?=0`, so no corpus graph should
produce a `?` from these ops — the sentence is correct again. **Only a `bend` run confirms it.**

## 6. The denominator, as the deliverable

| | value |
|---|---|
| `Ops` members (the enum's own declaration) | **77** |
| members with an arm in `dt_shape` | 77 (0 absent, 0 stray) |
| members falling to the bare `None{}` — BEFORE | **2** (STAGE, UNSHARD) |
| members falling to the bare `None{}` — AFTER | **1** (UNSHARD) |
| of the BEFORE K: PORT GAPS | **2** (both dtypes derivable; STAGE's no-range case fully derivable) |
| of the BEFORE K: honest unknowns | **0** (the honest unknowns are the 11 `late()` ops, a different class) |
| members with a WRONG (non-`None`) arm found by reading | **1** (WMMA — full-shape broadcast) |
| **the class "fold answers `?` where upstream settles"** | **3 = {STAGE, UNSHARD, WMMA}** |

The scan for a bare `None{}` names 2. Reading the arms names 3. **The third was invisible to
the spelling and only visible to the rule** — doctrine 1 one level down: a population by the
body's text cannot see a body that is wrong.

## 7. What ONLY `bend` settles (and I could not run it)

1. That `fold.bend` **compiles** — the `+ss` reuse in `stage_shape`/`stage_ds`, the
   `match tail` on a PARAMETER (`stage_shape.of`), and the `Maybe.map(Shapes, Shapes, ...)` in
   `wmma_ds.go` are read, not type-checked. A call in scrutinee position is refused
   (`fold.bend`'s PERMUTE note: "a call in a scrutinee position"), which is why the tail is a
   parameter.
2. That `diff --graph stage` and `diff --graph wmma` return **AGREE**, and that
   `Kahn.settled` becomes True for both (a fold change is proven by the ROWS, BOTH sides).
3. That `--graph stage` reads `?=0` and `graphcmp.py:2178`'s sentence is TRUE (§5).
4. That `mmkx_sibling_stage` now answers, so `.agents/slop/mm-walk-gate.py`'s `D` block needs
   its one entry removed (a HARNESS change, not the port's).
5. Whether `unshard` (UNSHARD still `None{}`) lands DISAGREE on a fresh `differ.py run` — the
   sixth live `?` the class predicts, and the one the brief did not name.

Unsettled by these measurements: any of 1-5. Assertions to re-take, not facts.
