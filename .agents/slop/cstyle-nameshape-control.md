# DELIVERABLE 2 + 3 — the detector, and the control a value plant cannot fake

## What was there, and why it was not enough

`cstyle-gate.py` already printed name sets, and the brief asked me to check whether that was
enough. It was not, for three reasons, all MEASURED on this lane:

1. **It printed the delta and then said `AGREE`.** The pre-fix gate on the pre-rename pair:
   ```
   the SHARED reader (rebase-gate.py:rows()) over the SAME oracle stdout: 222 names --
     6 only it finds, 8 only rows_strict finds, 216 in common
   gated 221   agree 221   disagree []
   AGREE
   ```
   `rc=0`. The line above `AGREE` named all eight reshaping rows and the verdict did not move.
   A coverage delta that does not change the verdict is decoration.
2. **It covered ONE lane.** `rows_shipped` was applied to `o.stdout` only. The port lane was
   never put through the second reader, so a reshape present on one side and absent on the
   other could not be seen as what it is.
3. **It reported `6 only the shared reader finds` as if those six names EXIST.** They do not.
   `kern CUDA  lb` is a name **no producer printed** — it is the residue of two producers'
   names after `row()` cut them at `=`. A manufactured name reported as a found name is worse
   than a missing one, because it inflates the denominator of everything computed from it.

## The detector: `reshape()` — GUARD 0

`cstyle-gate.py:reshape(lane, text)` computes, per lane, from **`rows_strict` AND
`rebase-gate.py`'s own `row`/`rows`** (imported; `row_shipped` is `rebase-gate.row`, the
function `rows()` is built from — not a second copy of its rule):

| figure | meaning | denominator |
|---|---|---|
| `physical` | rows `row_strict` read | itself |
| `eq` | names containing `=` — the ROOT CAUSE | `physical` |
| `collided` | two physical names landed on one shipped key | `physical` |
| `unread` | `physical − len(shared)`: rows no name can reach | `physical` |
| `gate_only` | rows the shipped reader refuses **outright** | `physical` |
| `only_strict` / `only_shared` | the two readers' name sets, both directions | `physical` |

Any non-zero one is appended to `judge()`'s `bad`, **before** the value comparison, so a name
reshape is never reported as a value verdict. `report_reshape()` prints both lanes' counts
and the name-set verdict every run; `--names` dumps both full sets.

Two things I got wrong building it, recorded because both produced a **green** lane:

- **`reshape()` first ignored any row the shipped reader refused**, recording a key only when
  both readers read the line. So a row that reader cannot read *at all* was invisible — the
  strongest form of the defect. `--plant-shape` measured `eq=0 unreachable=0 AGREE` over it.
- **`plant_shape()` rebuilt the line from `rows_strict`'s value**, and `rows_strict` strips
  exactly one closing bracket, so on a port row the rebuilt line lost its final `]` and
  **failed `endswith("]")`**: the row became a shred and the lane went 227 → 226 for a reason
  that had nothing to do with the shape being planted. A control must not perturb the thing it
  is not measuring; it now keeps the tail verbatim and moves only the name prefix.

## The control, and why a value plant cannot fake it

**`--plant-shape OLD NEW` (repeatable) rewrites a row NAME on BOTH captured lanes.** Values
untouched.

The necessity is one sentence: a value plant is *invisible* to a name-set check and has to be.
`--plant ROW` appends `PLANTED` to a value; both lanes print the same bytes, so one value
disagrees and the name sets are untouched. The real defect is the opposite shape — the two
sides print **identical** bytes and the **comparable set** changes. A control that perturbs a
value cannot express it, and a check that a value plant can turn green is not testing it.

### The four lanes, all MEASURED, all in `--selftest`

Over a two-row synthetic probe (two rows because the collapse needs two names to land on one
key; MEASURED that Bend 2 rejects a second `do IO<Unit>:` block, so both rows come from one
`IO.print`):

```
  clean    -> AGREE   names eq=0 unreachable=0 disagree=[]
  value    -> BROKEN  names eq=0 unreachable=0 disagree=['st A']
  shape    -> BROKEN  names eq=2 unreachable=0 disagree=[]
  collide  -> BROKEN  names eq=2 unreachable=2 disagree=[]
SELFTEST OK: a planted VALUE leaves the name sets identical (so the name lane is not a value
check in disguise) and a planted NAME is BROKEN with every value agreeing
```

`value` is the falsification: `eq=0 unreachable=0` with the lane BROKEN on the value
comparison. `shape` and `collide` are BROKEN with `disagree=[]` — **every value agrees** —
and with **zero** ghost/stray lines, so `rows_strict` sees a perfect lane and only the
coverage delta fires. `collide` is `unreachable=2`, i.e. the loss is a *count of rows*.

### The real lane, before and after, over the same bytes

Pre-rename pair (both lanes, 8 `=` names, 2 unaddressable measurements per side). The
pre-rename captures are regenerated from the tree by **reversing the rename in the captured
bytes** (`re.sub(r'^(kern \S*? *lb) (\d+)( = \[)', r'\1=\2\3', …)`, 8 substitutions per
side), so the control is reproducible without a second live oracle:

```
jj file show -r @----- .agents/slop/cstyle-gate.py > pre/cstyle-gate.py   # 571 lines, no reshape
```

**`@-----`, not `@-`.** The coordinator committed while this unit ran, so `@-` moved and now
already contains the guard. First attempt at this control read `@-` and "got" a pre/post pair
where both sides were the NEW gate — which agreed on everything and proved nothing. `@-----`
is the 571-line blob, the last revision of `cstyle-gate.py` without `reshape`.

| gate | rc | verdict | gated / agree / disagree | ghost+stray |
|---|---|---|---|---|
| **pre-fix** (`@-----`, 571 lines) | **0** | **AGREE** | 221 / 221 / `[]` | 0 |
| **post-fix** | **1** | **BROKEN** | 221 / 221 / `[]` | 0 |
| post-fix, **post-rename** bytes | 0 | AGREE | 221 / 221 / `[]` | 0 |

`221 / 221 / []` in every row is the whole point: **the value verdict is identical and the
gate verdict changes.** And the pre-fix line immediately above `AGREE` names all eight rows:
`222 names -- 6 only it finds, 8 only rows_strict finds`. That is the control a value plant
cannot fake, failing before and passing after, on the tree's own lane rather than a synthetic
one. Captures: `cstyle-control-{prefix,postfix,clean}.txt`, `cstyle-capture-*.txt`.

Post-rename, live, twice, byte-identical:

```
lane    rows read  names (gate)  names (shipped)  `=`  unreachable  unreadable   name sets
port          227           227              227    0            0           0   IDENTICAL (227 shared)
oracle        224           224              224    0            0           0   IDENTICAL (224 shared)
gated 221   agree 221   disagree []
```

`AGREE`, `rc=0`, 6 declared exclusions, 0 stale literals, 13 named refusals — all unchanged by
the rename, which is the point: the rename moved **coverage**, not values.

## Why a rename and not a smarter split

`tcptx-oracle.py:386` already shows the cost of teaching a reader to cope. A boundary matcher
that splits on `=` will mis-split the name that contains one, so the two sides can be
internally consistent and still not address the same row. The name must be `=`-free, and the
check must be a **name-set** comparison, which is what `--plant-shape` proves.