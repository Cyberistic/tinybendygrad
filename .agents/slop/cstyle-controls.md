# DELIVERABLE 3 — one control per shape, each shown ARMED and RED

`.agents/slop/cstyle-shapes-selftest.py`. `python3` → exit 0. Run twice, byte-identical
(md5 `809f93a715d5119297d568b0ce26369f` both runs).

**A gate never seen red is not known to work.** So each shape runs **three** lanes, not two, and the
ARMED lane is half the control.

## The control row names

| shape | control row name | note |
|---|---|---|
| F1 `name=value` | `ctl OPENCL sz1 k0` | spaces, no `=` |
| F2 `name = [v]   py=[w]` | `ctl OPENCL sz1 k0` | spaces, no `=` |
| F3 `name␣␣value` | `ctlf3` | **single token — F3 forbids spaces** |

The F3 name is a single token because `rebase-gate.py:row()`'s F3 arm returns `None` unless
`len(head.split()) == 1`. My first draft used the spacey name on all three shapes and **the F3
control reported `AGREE` over zero shared rows** — a false pass, indistinguishable from a working
control in the output. Two name-spaces, and `shared != 0` is now a precondition of every case.

## The three shapes, ARMED and RED

Reader under test: `rebase-gate.py:rows()`, called. Both lanes share the row name in every case.

### F1 — `name=value`

| lane | port | oracle | shared | disagree | |
|---|---|---|---|---|---|
| ARMED | `ctl OPENCL sz1 k0=half` | `ctl OPENCL sz1 k0=half` | 1 | 0 | AGREE — expected AGREE |
| **RED** | `ctl OPENCL sz1 k0=halG` | `ctl OPENCL sz1 k0=half` | 1 | 1 | **RED** — `ctl OPENCL sz1 k0`, port `halG` vs cpy `half` |

### F2 — `name = [v]   py=[w]`

| lane | port | oracle | shared | disagree | |
|---|---|---|---|---|---|
| ARMED | `… = [half]   py=[half]` | `… = [half]` | 1 | 0 | AGREE |
| **RED** | `… = [halG]   py=[half]` | `… = [half]` | 1 | 1 | **RED** — port `[halG]` vs cpy `[half]` |
| **DISARM** | `… = [half]   py=[halG]` | `… = [half]` | 1 | 0 | AGREE — **correct** |

**The DISARM lane is the one that was paid for once.** The plant is in the **non-compared** `py=`
column, and the reader compares `left`. It comes back AGREE, which is the *correct* answer and
proves the RED plant really landed in the column the gate looks at. A project control that came back
RED here would be disarmed in the other direction; a control with no such lane cannot tell the two
apart.

### F3 — `name␣␣value`

| lane | port | oracle | shared | disagree | |
|---|---|---|---|---|---|
| ARMED | `ctlf3  half` | `ctlf3  half` | 1 | 0 | AGREE |
| **RED** | `ctlf3  halG` | `ctlf3  half` | 1 | 1 | **RED** — port `halG` vs cpy `half` |

## And the real instrument, on a real row

Not only synthetic text — `cstyle-gate.py`'s own `judge()`, over the real capture pair, one
character of one real F2 row:

| lane | gated | agree | disagree | |
|---|---|---|---|---|
| clean | 221 | 221 | 0 | AGREE |
| **RED** — `uchar` → `ucHar` | 221 | 220 | **1** | **BROKEN** — `['tmap OPENCL']` |

`--plant "tmap OPENCL"` through `main()`: `gated 221   agree 220   disagree ['tmap OPENCL']`,
`BROKEN`, rc=1.

## Reader reach, measured over the three shapes

| shape | `cstyle rows_strict` (what `judge()` reads) | `rebase-gate rows()` |
|---|---|---|
| F1 | **no** | yes |
| F2 | yes | yes |
| F3 | **no** | yes |

**`cstyle-gate.py`'s `judge()` cannot read F1 or F3 at all** — `rows_strict` demands `" = ["` and a
closing `]`. It is not degraded on F3; it reads *zero* rows there, which its own GUARD 1 would refuse
as an empty lane. That is fine for this file (both lanes are F2 by construction) and it is the reason
the fix in deliverable 1 is a *parity* reader rather than a substitution: `judge()` cannot read what
`rows()` reads. `rows_strict` is left in place, documented, not deleted.

## What this control set does not cover

* The **6 excluded rows** (`buft METAL`, `idx BASE regadd`, `idx HIP regadd`, `under float`,
  `under signed char`, `under unsigned lon`). Excluded rows are not compared, so no plant can move
  them; a control that appeared to cover them would be disarmed by construction.
* The **13 oracle refusals** on stderr. A refusal maps to the port's `""` marker and the assertion
  is `unsilent_refusals`, which the file's own `--selftest` already drives both ways
  (`refusal` AGREE, `refusal+` BROKEN).
* **A lane whose row names differ between the two readers.** `kern CUDA  lb=1` vs `kern CUDA  lb`
  (8 of 227 names, from `cstyle.bend:1758` emitting `=` inside a row name) is a *disagreement of
  NAME SETS*, and no plant of a *value* can detect it. That is the gap the parity line in
  `cstyle-gate.py` now prints every run, and it is a live defect in the port's row shape.