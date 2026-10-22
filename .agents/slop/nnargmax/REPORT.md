# `nn/argmax.bend` -- THE RECIPE IS PORTED AND VERIFIED; THE GRAPH IS REFUSED, WITH THE MEASUREMENT

MEASURED 2026-10-22. The port file is `tinybendygrad/nn/argmax.bend`; the capability
probe is `.agents/slop/nnargmax/probe.bend`; the upstream contract is
`tinygrad/mixin/op.py:863-887`.

## WHAT IS BUILT AND VERIFIED

`nn/argmax.bend` implements upstream's recipe **on a list**:

```
m   = self.eq(self.max(axis=axis, keepdim=True))
idx = m * type(self).arange(self.shape[axis], 0, -1).reshape(...)
return (self.shape[axis] - idx.max(axis=axis, keepdim=keepdim)).cast(dtypes.int32)
```

`arange(n, 0, -1)` is `[n, n-1, ..., 1]`, so `idx[j]` is `n - j` where the value at `j`
IS a maximum and `0` where it is not. `idx.max` picks the LARGEST `n - j` among the
maxima, which is the SMALLEST `j` among them -- **the first occurrence**. **So the
tie-breaking rule is a CONSEQUENCE of the formula, not an assertion about it**, which is
why the tie rows can be *checked*.

Rows, run on the committed tree plus the `uop/weak.bend` fix:

```
argmax_unique got=1 want=1        argmax_tie3 got=0 want=0
argmax_tie2 got=1 want=1          argmax_tie_last got=0 want=0
argmax_neg got=1 want=1           argmax_zero got=2 want=2
```

`ALL PROOFS CHECK`.

**THE `want` VALUES ARE UPSTREAM'S, NOT THIS FILE'S OUTPUT.** The orchestrator
re-checked all six against CPython in `.venv` independently: **0 disagreements of 6**.

## WHY A LIST AND NOT A TENSOR

**The port builds UOp graphs and has no executor.** `uop/fold.bend` answers
dtype/shape/device/addr/base/ended and nothing else -- **there is no value fold in the
tree**, so a graph cannot be asked for its answer. What can be asked for an answer is the
recipe.

## THE GRAPH-LEVEL `argmax` IS REFUSED, WITH THE MEASUREMENT

`probe.bend` asks four questions. Measured 2026-10-22 on the committed tree:

| | question | answer |
|---|---|---|
| Q1 | does `nn_reduce` answer the keepdim MAX's shape? | **YES** (`1`) |
| Q2 | does the comparison broadcast a `[4]` against a `[1]`? | **YES** (`4`) |
| Q3 | does the bool dtype survive the comparison? | **YES** (`bool`) |
| **Q4** | **can the port produce an INDEX VECTOR along the axis?** | **NO** |

**Q4 IS ASKED TWICE** -- once through the fold and once through the movement walk --
because `examples/beautiful_mnist.bend` records that the two disagree on an
`arange`-rooted node. **They agree here: both read EMPTY.**

**So upstream's `Tensor.argmax` GRAPH is not buildable: its recipe needs `arange`, and
the port cannot produce one.** The missing capability is named: *a fold that answers the
shape of an index vector along an axis*. Three of the four steps work; the fourth is the
one upstream's recipe leans on.

## SCOPE, STATED SO NOBODY INVENTS A WIDER CLAIM

This is a **1-D F32 formula**. Upstream's `argmax` takes an axis and any dtype. A
generalisation is a widening of this file, not a new idea, and it is **not done here**.

## A NOTE ON `Bool.pick`

The port uses `Bool.pick` and not `match` on a computed value: `match` may not
scrutinise a call (Bend's rule 1). `tinybendygrad/uop/ops.bend:8951` was the tree's own
counter-example of what that costs -- a `match` on a call there poisoned **every** file
that imports `uop/ops.bend` (see `.agents/slop/idxrace/REPORT.md`'s sibling finding in
`.agents/TODO.md`).
