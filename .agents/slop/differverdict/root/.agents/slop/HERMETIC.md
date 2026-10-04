# hermetic — the corpus's results must not depend on the process or on what ran before

2026-10-04. Nothing committed. `graphcmp.py` was CLAIMED on disk first
(`hermetic/CLAIM-graphcmp.md`) and is **byte-unchanged**: md5 `c7096ee70cdfef447aec10cd784ef3ac`
before and after. It needed no edit — see §3, where the briefed defect turned out not to exist.
`arith/`'s row cache is also byte-unchanged (md5 `c466049e…` `late`, `c37aa2bc…` `flip`); the
audit reads it and never writes it.

    hermetic/isolate.py          the mechanism: ONE graph, ONE side, in a fresh process
    hermetic/hermetic-census.py  the census. no cache on the verdict path. `--check`
    hermetic/audit-hermetic.py   a PLANT and a DISARM for each defect; rc 1 unless all pass
    hermetic/rows/               the published artifact, 48 row sets

    .venv/bin/python .agents/slop/hermetic/hermetic-census.py          # census, 23 s
    .venv/bin/python .agents/slop/hermetic/hermetic-census.py --check  # rc 3 if any artifact is stale
    .venv/bin/python .agents/slop/hermetic/audit-hermetic.py          # the six controls

## 1. THE SLOT LEAK — fresh process per graph, and WHY NOT A RESET

`UOp.unique_num` is a module-level `itertools.count(0)` (**`tinygrad/uop/ops.py:839`** — the
brief said 842, which is `getaddr`), `Tensor.empty` consumes one per call
(**`tinygrad/mixin/creation.py:41`**, via `new_buffer`, `ops.py:853`), and it reaches the row
stream at **`graphcmp.py:708`** (`u(pa.slot)`), the first of `ParamArg`'s thirteen fields.

MEASURED. `late` alone: slots `i0,i1`, md5 `16368f03`. After 8 predecessor graphs: `i13,i14`,
md5 `2990e301`. **Row count is 12 either way and the op census is identical**, which is exactly
why 59 read the same before and after.

**CHOSEN: a fresh process per graph.** A counter reset is *empirically* sufficient — measured,
all 24 graphs agree with a fresh process under a reset — and it is still the wrong choice,
because it is sufficient only if the set of interpreter globals reaching a row is exactly the
ones I enumerated. An enumeration fails by being incomplete, and incompleteness is invisible by
construction. A fresh process resets all of them without my naming them, so its soundness does
not rest on my bookkeeping. It costs **0.08 s per graph including the tinygrad import**
(measured), 24 graphs ≈ 2 s for the py side. The soundness is free here.

The bend side was **already** isolated — `emit_bend` runs one `bend` subprocess per graph
(`graphcmp.py:1828-1850`) — and MEASURED: arith's 24 bend row sets reproduce 24/24 while only
15 of its 24 py row sets do not. So only the py side leaked, and only the py side is re-parented.

**THE SOUNDNESS PREMISE, TESTED.** Fresh-process is only worth anything if it is *deterministic*,
or it trades one non-reproducibility for another. Two independent full census runs are
**byte-identical across all 48 row sets** (`diff -r` rc 0). Nothing in a row derives from `id()`:
`paramarg`'s field 11 is presence-only (`graphcmp.py:717`) and `trace_num` is never read
(`graphcmp.py:697`), which is why the buffer's process-dependent identity never reaches a row.

## 2. THE CACHE — no cache on the verdict path

`arith/both-census.py:39` read `rows-<graph>-<side>.txt` by default, and the file was stale.

**MEASURED, and it is 15 of 24, not one.** Against a fresh process, arith's published py row
sets disagree for `binblob bit buffer bw cast cdiv commute flip group late matmul move reduce
sym where` — every one with the **same row count**, differing only inside the `45:`/`46:` chunk,
the `ParamArg` record. The brief's `flip rows=7 vs rows=6` no longer holds (the cache reads 6);
what is there instead is a 15-of-24 byte corruption nobody could see. **The union stayed at 59
because `ops_of` reads field 1, the op, and the op census is invariant to `slot` — so the
agreement was luck, not verification.**

**CHOSEN: there is no cache on the verdict path at all.** `census()` always emits; the row sets
are a *published artifact* written from that emission; `--check` is the only reader and exits 3
naming every disagreement. "Default vs `--fresh`" is therefore not a comparison this file can
lose — no flag makes the default read a cache. Chosen over verify-on-read because
verify-on-read costs the same emit *plus* a comparison, i.e. it is this design plus a tamper
check that `--check` already does at zero emission cost. And it is the design that matches the
failure: the old cache was not *detected* wrong, it was *unobservable*, and the fix for
unobservable is structural, not louder.

## 3. `DEV` — THE BRIEFED DEFECT DOES NOT EXIST, AND THE WALL IS STILL TRUE

`graphcmp.py:2977` sets `DEV`, `:2978` calls `load_tinygrad()`. The assignment is **before** the
import, which is what has to happen. MEASURED: `--dev CPU` → `sCPU`, `--dev NULL` → `sNULL`,
`Device.DEFAULT == NULL`. The briefed `graphcmp.py:2769` is a **stale citation**: 2769 is now
`continue` in `split_debug`. It matches `.agents/slop/flip/graphcmp.py.BASELINE:2769` and
`arith/baseline/graphcmp.py.BASELINE:2769`, where `load_tinygrad()` is line **2770** — so even
against the baseline the order was correct. **The brief read a correct line as a wrong one.**

The wall itself (`REACH-ARITH.md` §5.3) is TRUE and reproduced: with no `DEV` in the env, a
source assignment *after* the import asking for `NULL` yields **`METAL`**. Two further modes,
both measured, both worse than the original:
- **inert, not an error** — with `DEV` already inherited, a late source assignment asking for
  `NULL` yields `CPU` *silently*. It reads as if it took effect. **This is why source order
  cannot be left to a reader's care.**
- **one graph is not a corpus** — every one of the 48 published row sets carries `sCPU` and no
  other `s*` token, checked per file rather than once.

**CHOSEN: no source assignment at all in the corpus path.** `isolate.emit` puts `DEV` in the
child's *environment at process birth* (`clean_env`, `graphcmp.py:1820`), so the child has no
line that could apply it late. Order becomes a property of the mechanism rather than a
convention. **§1's fix and §3's fix are the same fix.**

`audit_dev_sites()` scans every script that *assigns* `DEV` and reaches tinygrad: 37 scripts,
**0 offenders on the corpus path**. Off-path findings are reported with `file:line`, not gated,
because a gate that can never go green is a gate nobody reads.

## 4. THE CONTROLS — every plant fires, every disarm is green (`rc 0`)

| | plant | disarm |
|---|---|---|
| C1 | `late` alone `i0,i1`/md5 `16368f03` vs after 8 graphs `i13,i14`/md5 `2990e301` | emitted FIRST and LAST under `isolate`: both `16368f03`; and the parent's `unique_num` reads 0 then 1 — unreachable if any graph had been built there |
| C2 | arith's own artifact: rc 3, **15 named**; plus one flipped byte: rc 3 | same `--check` over the fresh artifact: rc 0; and the null is the **same file rewritten with identical bytes**: rc 0 — content is the comparison, mtime is not |
| C3 | asked `NULL`, applied after the import → `METAL`; and inert under an inherited `DEV` → `CPU`, silently | inherited at process birth → `NULL`; and all 48 row sets carry only `sCPU` |

**C1's DISARM is the condition that provably cannot trigger**, and reading the counter is itself
a trap: `unique_num` is a bare `itertools.count`, so reading it *consumes*. The start read
returning 0 proves nothing minted before it; the end read returning 1 proves nothing minted
in between, because the only consumer since is the start read. A reset could only re-establish
that number, never assert it.

**FOUR CONTROLS OF MY OWN WERE BROKEN BEFORE THEY PASSED, and each is a trap someone will hit:**

1. **C1's first plant was a tautology.** It compared `late` after `matmul` against `late` after
   `reduce,cast` and they came out byte-identical — because those two predecessor sets consume
   exactly **two slots each**, so `late` landed on `2/3` either way. A plant whose two spellings
   collide proves nothing; measuring per-set slot consumption is what exposed it. Same shape as
   the `flip` and `lin`/`loop` lessons.
2. **C3's first plant was the disarm.** One template with the `DEV` line substituted into the
   same slot for both runs, so both were EARLY and the "plant" reported the disarm's answer.
   Then the fixed plant reported `CPU` instead of `METAL` — because `clean_env` had already put
   `DEV` in the child env, making the late assignment inert. The plant needed an env with **no**
   `DEV`. Three bugs, one control.
3. **The counter check failed on a correct tree** (`0 -> 1`): the instrument consumed what it
   measured. Fixed as above; the fix is the measurement, not the expectation.
4. **`C3b` flagged 17 files, 16 of them false positives**: it matched `DEV` in any line
   containing `environ`, so upstream's own `tinygrad/device.py` (`DEV = ContextVar(…)`, or
   `os.getenv` at `:59`) counted as an *assignment*. **A read is not a write.** It also walked
   vendored trees (`xd1/*`, `opstree/*`). Now scoped: gate on the corpus path, report the rest.

One more, in my own readout: the slot display was a 2-char slice, so two-digit slots printed
`i1` for both — reading as a collision that is not there. Fixed to split the token.

## 5. STILL DISAGREES, WITH `file:line`

- **`.agents/slop/oracles/mm-range.py:12` and `:59` — a LIVE late-`DEV`.** `:12` imports tinygrad
  at module scope; `:59` sets `DEV='NULL'`; **MEASURED `Device.DEFAULT` is `METAL`**, and `:60`
  prints it. (It then dies at `:69` on `Tensor.floordiv`, separate rot.) Another unit's oracle:
  reported, **not fixed**, per `agent-core.md`.
- **`.agents/slop/oracles/mm-range.py`** and 7 vendored `tinygrad/device.py` /
  `xd1/*/external_test_train.py` sites are reported by `C3b` and do not gate. The `device.py`
  ones are upstream's own contract (`DEV = ContextVar`), not defects.
- **`arith/REACH-ARITH.md` §5 wall 6 cites `ops.py:842`**; the counter is at **`ops.py:839`**
  (842 is `getaddr`). The wall's substance is right and now measured; its line is not.
- **`arith/REACH-ARITH.md` §5 wall 3 cites `graphcmp.py:2769`** for the late-`DEV` site. It is
  **`:2977`**, and it is *before* the import — see §3.
- **`arith/both-census.py:39` is untouched** (another unit's tree) and still reads a stale cache
  by default. **Its 15 stale py row sets are still on disk.** `hermetic-census.py --check
  --out .agents/slop/arith` names every one and exits 3; deleting or re-publishing them is the
  owner's call, not mine.

## 6. DOES THE 59 SURVIVE

**Yes, re-measured under the new mechanism, three times:** 24 graphs, denominator **77**
(measured `len(list(Ops))`), reached PY **59**, reached BEND **59**, reached BOTH **59**,
`py-only []`, `bend-only []`, **0 walls**. 23.3 s. Two independent runs byte-identical.

**What the 59 is and is not.** It is *unchanged*, and that is the point: the leak never moved it,
so its stability is **not** evidence that the corpus was reproducible. It was not. 15 of its 24
inputs were bytes no fresh run could reproduce, and the number survived only because the census
reads the op, which the corruption does not touch. The 59 is now computed from rows that
reproduce byte-for-byte, which is a different and stronger claim than the same number before.