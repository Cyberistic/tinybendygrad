# ADEV — the `COPY`/device normal form. Unit `ADEV`, 2026-10-04

**One decision: a device is `str | tuple[str, ...]` and BOTH arms must render. The port
already said so; the differ's text did not.** `graphcmp.py` + `graphcmp.bend`, three edits
plus two plants. Evidence: `.agents/slop/adev/probe.py` (run it), `.agents/slop/adev/recheck.py`
(`verdicts` / `blocked`). Claim + md5s: `.agents/slop/adev/CLAIM.md`. **Nothing committed.**

## 1. THE DECISION, AND THE UPSTREAM `file:line` THAT SETTLES IT

**A device PAIR is canonical. A flattened single device is not.** Not a preference — the
flatten is **not injective on a real domain**, and it erases a distinction upstream branches
on in four places.

| upstream | what it says |
|---|---|
| **`tinygrad/uop/ops.py:758`** | `def copy_to_device(self, device:str\|tuple[str, ...], arg=None)` |
| **`tinygrad/uop/ops.py:765`** | `return UOp(Ops.COPY, src=(inp, *UOp.device_range_src(device)), arg=device)` — **stored verbatim** |
| **`tinygrad/uop/ops.py:846-848`** | `device_range_src` = `(UOp.range(len(device), 0, AxisType.DEVICE),) if isinstance(device, tuple) else ()` |
| `tinygrad/uop/ops.py:677-679` | `allreduce(self, op, device:str\|tuple[str, ...])`, opening `assert isinstance(self.device, tuple)` |
| `tinygrad/uop/ops.py:701` | `unshard` asserts `isinstance(self.device, tuple)` again |
| `tinygrad/uop/spec.py:140` | `is_device(d) = isinstance(d,str) or (isinstance(d,tuple) and all strs)` |
| `tinygrad/uop/spec.py:30-34` | `valid_device_range`: a tuple needs 1 src, a str needs 0 |
| `tinygrad/uop/ops.py:33` | `ParamArg.device: str\|tuple[str, ...]\|None` |

**MEASURED, `probe.py` §3 — the flatten had two real collisions:**

```
                              pre-fix        post-fix
('CPU',)        vs 'CPU'      sCPU == sCPU   n(sCPU) != sCPU      <- isinstance(device, tuple)
('CPU,CPU',)    vs ('CPU','CPU')  sCPU,CPU == sCPU,CPU   n(sCPU,CPU) != n(sCPU,sCPU)
```

**MEASURED, `probe.py` §2 — and py's two spellings are ONE value:**
`c.arg == r.arg[1]` is `True`; both are `('CPU','CPU')`. So the two spellings cannot both
be right, and the graph is not the inconsistent party.

## 2. THE PREMISE WAS WRONG ABOUT THE PORT

**"`n(sCPU,sCPU)` has no port representation" is FALSE.** `LAWS/spec.bend:85` is
`type Dev is Data: D1{tag: U32} | Dn{tags: List<&2,U32>}` — the union, one variant — and
`uop/ops.bend:1070` `ADev{dev: S.Dev}` / `:1069` `AAllred{rop: Op, dev: S.Dev}` both hold it.
DENOM's own fixture already wrote `O.ADev{S.Dn{[0,0]}}`, and **it compiled and printed
before this unit touched anything.** The port was never the blocker; the differ's *text* was.
So **no `Arg` variant was added** — the third option in the brief, and the one that would
have been a hedge.

## 3. `g_allred`: BEFORE → AFTER, WITH ITS DENOMINATOR

Attribution by **real revert of the same tree** (`adev_revert.py`, restore md5-verified),
not by memory:

| | verdict | shared-cores | ONLY-PY | ONLY-BEND | nodes | field-records |
|---|---|---|---|---|---|---|
| **before** | **DISAGREE** | 7 | 2 | 2 | **9/9** | **54** |
| **after** | **AGREE** | 9 | 0 | 0 | **9/9** | **54** |

**The denominator did not move and the row count did not move** — 9/9 nodes, 54
field-records both ways. Only the verdict and the pairing moved. The rung-3.5 block is gone
entirely. The two rows that were unpaired:

```
                        before                                    after
COPY      py=n(sCPU,sCPU)        bend=ssCPU,sCPU      py=n(sCPU,sCPU)   bend=n(sCPU,sCPU)
ALLREDUCE py=al(OADD,sCPU,CPU)  bend=al(OADD,ssCPU,sCPU)  py=al(OADD,n(sCPU,sCPU))  bend=al(OADD,n(sCPU,sCPU))
```

**Corpus: 25 graphs re-measured individually — 23 `AGREE`, 2 `DISAGREE`** (`lin`, `loop`,
which disagree on purpose for named measured reasons). Before this unit: 22/3.
`selfcheck: OK`. `control: OK`. **`?=0` read 0 before AND after** — the `flip` pattern
reproduced on purpose; the verdict is the headline and `?=0` is not evidence in either
direction.

## 4. THE 13 — AND THE FRAMING NEEDS A CORRECTION

**They were never blocked on emittability.** DENOM §8 says "each measured emittable", and
that is right. Measured, `recheck.py blocked`:

```
emittable:      13 of 14    (the only NO is patir -- DENOM-3, the INSTRUMENT: cshape raises
                              AssertionError on a shapeless AND)
moved by ADEV-1: 1 of 14    (only `mselect`)
```

**So: 0 of the 13 became emittable, because all 13 already were — the fix touched a
renderer, not the ability to render. And the decision changed the arg text of exactly
1 of 14 candidates** (`mselect`: `COPY sCPU,CPU -> n(sCPU,sCPU)`). The rest have a `D1`
device, which renders identically under both. **`copy` reads `moved=NO` because DENOM's
measured recipe is `copy_to_device("CPU")` — a `str`.** The 13 were blocked *procedurally*:
with no settled spelling there was nothing to write a fixture down as.

**AND "13" DOES NOT MATCH §8's OWN LIST.** §8 says "the other 13 candidate graphs" and names
**twelve**. The 13th is `mulacc` (§3 "needs an NVIDIA device"; §8 "Did not touch MULACC's PTX
gate"). `patir` is the 15th of `emittable.py`'s `CANDS` and is blocked by the instrument.
A note's own count disagreeing with its own list is the `flip` stale-`7/7` shape.

## 5. IS PY'S INCONSISTENCY UPSTREAM'S OR THE DIFFER'S?

**The differ's — on BOTH sides. Upstream is answerable to neither spelling.**

* py `COPY` had no `carg` arm → fell to `_carg` → nested `n(..)`; py `ALLREDUCE` had one →
  the flattening `dev` → `sCPU,CPU`. Two spellings of one value, one graph, two nodes apart.
* bend's `devs` **double-prefixed**: `bstr(String.join(devs.go(..), ","))` where `go` already
  yields `dev1(t)` = `bstr(..)`. So `S.Dn{[0,0]}` printed **`ssCPU,sCPU`** — a **third**
  spelling, matching neither. This was not in the original report; it is why `ALLREDUCE`
  disagreed *independently* of `COPY`, and it is the same defect class: a second renderer
  for one value.

**The fix is one function per file, and on the py side it is a deletion.** `graphcmp.py`'s
`dev` existed only to flatten; with the flatten gone it is `_carg` on its whole declared
domain, so it is **deleted** and both call sites (`carg`'s `ALLREDUCE` arm, `paramarg`'s
device field) now say `_carg`. Removing the second renderer is the point.

## 6. PLANT AND DISARM — a paired experiment, not two edits

| | edit | verdict | cores | nodes | field-records |
|---|---|---|---|---|---|
| `--plant devpair` | `ALLREDUCE`'s device loses a member: `('CPU','CPU')` → `('CPU',)` | **DISAGREE**, names `arg` | 8/9 | 9/9 | 54 |
| `--plant devdisarm` | that same field **re-minted at the same value** (`tuple(list(..))`) | **AGREE** | 9/9 | 9/9 | 54 |

`devpair`: `py=al(OADD,n(sCPU))` vs `bend=al(OADD,n(sCPU,sCPU))`. The emitted py stream is
**byte-identical** for `devdisarm` and for no plant (`md5 90ec1dda…`, 577 bytes) and
**differs** for `devpair` (`2580f381…`, 572) — the precondition `plant_dsexpand` requires.
`probe.py` §5: the re-minted tuple is `is` the original node, because the ucache keys on
`(op, src, arg, tag, type(arg))` (`ops.py:201`).

**WHY `ALLREDUCE` AND NOT `COPY`: a spec, not convenience.** A device is *coupled* to a src
on a `COPY` — `spec.py:174-175` requires `valid_device_range(copy.arg, copy.src[1:])`, and
`spec.py:34` requires `int(rng.vmax)+1 == len(device)` — so collapsing the COPY's pair moves
the COPY's `arg` **and** its DEVICE RANGE's `vmax`. Two edits measures the sum.
`ALLREDUCE`'s device is checked by `spec.py:176-177` for `is_device` and nothing else: one
field, one node. **The trap this dodged is `js-repair-abi4`.**

**MY FIRST PLANT REPORTED AGREE, AND THAT IS THE FINDING.** `_rebuild_with` skips the root
by construction (`par[ast] = None`), and on `allred` the ALLREDUCE **is** the root, so the
replacement was a no-op. A plant that reports AGREE is not a plant. Corrected to direct
construction. Recorded because the next agent will reach for `_rebuild_with` on a root.

## 7. THE CLAIM I REFUSED TO MAKE

**This does not mean the corpus compares training graphs, and nothing here moves it.** `bw`
is the gradient of **one eager expression**; `schedule -> render -> compile` is still
**forward-only**; and `late` and `allred` are graphs the port **reproduces and does not
produce**. `g_allred`'s py side is `copy_to_device` + `allreduce` on a `Tensor` — an eager
call — and its port side is a 9-node arena fixture. **Reproducing a graph and producing it
are different claims, and a corpus of reproducible graphs looks identical to a corpus of
producible ones.** ADEV-1 moved one *spelling* of a value both printers already agreed on
upstream's type. It measures nothing about the emitter reaching `schedule -> render ->
compile` on its own.

I also did **not** claim this makes 4 more ops emittable. `CUSTOM`, `CUSTOMI` and
`PYLITERAL` are still gated by one `except` arm in `cshape` (DENOM-3), and `MULACC` still
needs an NVIDIA device.

## 8. RULES (`ADEV-`, fresh prefix)

* **ADEV-1. `S.Dev`'s two arms are two values. Never render a device tuple by flattening
  it.** MEASURED, the flatten collides on `('CPU',)` vs `'CPU'` and on `('CPU,CPU',)` vs
  `('CPU','CPU')`, and upstream branches on exactly that union at `ops.py:846`, `ops.py:679`,
  `ops.py:701`, `spec.py:30` and `spec.py:140`. `Dn` is the pair; `n(..)` is the value.
* **ADEV-2. A union rendered by TWO functions is a defect waiting for its second spelling.**
  `graphcmp.py` had `dev` and `_carg` for `str|tuple`, and bend had `devs` wrapping
  `bstr` around `dev1`'s already-`bstr`'d members — so one value had THREE spellings
  (`n(sCPU,sCPU)`, `sCPU,CPU`, `ssCPU,sCPU`) and a DISAGREE that named no culprit. When a
  value has a general grammar, the special renderer must **die**, not be retuned: `dev` is
  deleted, not rewritten.
* **ADEV-3. `_rebuild_with` cannot replace the ROOT, so a plant on a fixture whose root is
  the node you mean reports AGREE.** `par[ast] = None` then `fn(n) if (par.get(n) is not None
  and ...)`. On `allred` the ALLREDUCE is the root. A plant that reports AGREE is not a
  plant.
* **ADEV-4. "Blocked on a normal-form decision" is not "not emittable".** 13 of 14
  candidates were emittable before and after; the decision changed the arg text of 1. Measure
  `moved` (pre-fix renderer vs post-fix, per node) and not `emittable` when the question is
  what a decision *did*.
* **ADEV-5. A note's own count is not a vote.** `DENOMINATOR.md` §8 says "the other 13" and
  names twelve; the 13th is `mulacc`, and `patir` is a 15th. Same family as `flip`'s stale
  `7/7` and §5's "23 AGREE, 2 DISAGREE" against its own "the third `DISAGREE`" (22+3=25).
* **ADEV-6. If a fixture compiles and prints, the port represents the value.** `O.ADev{
  S.Dn{[0,0]}}` built and ran before this unit started. "No representation" should be checked
  against the port's constructors *before* it is written down as the cause of a DISAGREE.

## 9. WHAT I DID NOT DO

Did not add any of the 13 candidates (adding a graph is a separate action and the
normal form they were waiting on is now settled). Did not touch `uop/**`, `LAWS/**`, `base.bend`,
`dtype.bend`, `runtime/dtype.js`, or `.agents/slop/clangshim/**`. Did not widen `cshape`'s
`except` (DENOM-3's `CUSTOM`/`CUSTOMI`/`PYLITERAL` gate is still open and is one arm).
Did not touch `MULACC`'s PTX gate. **Did not commit.** `graphcmp-oracle.py` untouched
(md5 unchanged at `9f47db78…`).
