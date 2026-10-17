# axisflip -- `mxw_flip` was right on axis 0 and wrong on every other axis

`flip_01` was 28-vs-28 cut-relative and green while `mxw_dims_of` of the two results were
`(4,4,8,8)` and `(1,4,8,8)`. Owner: `tinybendygrad/mixin/movement.bend`'s `mxf_compose`. This
file records the before/after pair, because the BEFORE cannot be reproduced without reverting the
fix and the gate that certifies the axis did not exist.

## THE INSTRUMENT

`gates/mxgraph-fixture-rows.bend` -- written by the unit that made the first port, NOT mine, and
its `shape_*` rows are the same expressions on the same base as this fix's rows. Run under
`checks/bounded.py --mb 2048`, `DEV=CPU SPEC=1`, one `bend` at a time. Files:

| file | what |
| --- | --- |
| `rows-before.rows` | the port, pre-fix |
| `rows-after.rows` | the port, post-fix |
| `gate-before.out` | `groupflip-gate` PASS, pre-fix |
| `gate1.err` | `axisflip-gate` FAIL rc=1 -- `n=` was ABSOLUTE and the `ParamArg.size` BUFFER divergence put 10 against 9 on the base row |
| `gate2.out` | `axisflip-gate` PASS, post-cut |

## THE MEASUREMENT, AND IT IS THE WHOLE ARGUMENT

`mxw_base()` is `(1,4,8,8)`. `movement.py:256` makes `x = ret.transpose(0, axis)` and `:257-258`
read `crop` and `tail` from `x.shape[1:]` -- the shape minus the AXIS dim. `mxf_compose` read them
from `mxw_dims_of(ret)[1:]`, which drops dim 0 and KEEPS dim `axis`. The two agree iff
`shape[0] == shape[axis]`, and for `axis == 0` they are the same statement.

| row | base | before | after | CPython |
| --- | --- | --- | --- | --- |
| `shape_a0` | (1,4,8,8) | `1,4,8,8` | `1,4,8,8` | `1,4,8,8` |
| `shape_a1` | (1,4,8,8) | `4,4,8,8` | `1,4,8,8` | `1,4,8,8` |
| `shape_a2` | (1,4,8,8) | `8,4,8,8` | `1,4,8,8` | `1,4,8,8` |
| `shape_a3` | (1,4,8,8) | `8,4,8,8` | `1,4,8,8` | `1,4,8,8` |
| `shape_a01` | (1,4,8,8) | `4,4,8,8` | `1,4,8,8` | `1,4,8,8` |
| `shape_sym_a1_on_4444` | (4,4,4,4) | `4,4,4,4` | `4,4,4,4` | `4,4,4,4` |
| `shape_asym_a1_on_2448` | (2,4,4,8) | `4,4,4,8` | `2,4,4,8` | `2,4,4,8` |

Row 6 IS THE FINDING: the same call on a cube of 4s reads AGREE on both sides of the fix.

## THE ROWS THAT DID NOT MOVE, WHICH IS WHY THE GATE WAS GREEN

`ctl_a1` 33, `ctl_a1x2` 47, `ctl_a1x4` 75, `new_flip_0` 6, `new_flip_01` 33, `new_flip_noop` 6 and
`cut_flip01_above_base` 28 are BYTE-IDENTICAL in `rows-before.rows` and `rows-after.rows`, and
every one of them is `<n> Ops.<TOP>/<nsrc> <srcops>` or a count. So `gates/groupflip-gate.py`'s
eleven rows and `gates/mx_graph_census-gate.py`'s `flip_0`/`flip_01`/`flip_noop` could not have
seen this on ANY base. Two things had to change for a gate to see it, and only the second is a
code change:

1. a base where `shape[0] != shape[axis]` for the axes under test -- (4,4,4,4) is blind on every
   axis, and (1,4,8,8) has a SIZE-1 axis 0 that `movement.py:255`'s guard skips;
2. a row that carries a SIZE. `<OP>x<nsrc>[<src ops>]{order}` carries no RESHAPE target shape, no
   PAD offset and no SHRINK size, and the defect was a wrong size list.

`gates/axisflip-gate.py` is the two together, and its `axis1` row makes the blindness guard a
COMPARED row rather than a comment: a base that goes back to a cube turns that gate red with every
other row still green.

## THE TWO `old_flip_*` ROWS THAT DID MOVE, AND WHY

`old_flip_0` 69 -> 33 and `old_flip_01` 71 -> 47. Those pass the OLD FLAG VECTOR as an axis list
(`[1,0,0,0]`, `[1,1,0,0]`), so they flip axis 1 and then axis 0. Before the fix the axis-1 flip
returned a WRONG shape `(4,4,8,8)`, which made axis 0 non-unit, so the guard could not skip and
three more chains composed. After the fix the shape is right, axis 0 is size 1 again and the guard
skips. So the node count moved there -- but because a wrong shape changed a LATER DECISION, not
because the row could read a shape.