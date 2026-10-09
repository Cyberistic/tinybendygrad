#!/usr/bin/env python3
"""mo_graph_census-gate.py -- THE GRAPH CENSUS over the public `mo_*` layer.

    .venv/bin/python gates/mo_graph_census-gate.py

30 PUBLIC DEFS, 37 ROWS, THREE LANES, NO DECLARED DIVERGENCE.

THE POPULATION IS DISCOVERED, NOT REMEMBERED. Every `mo_*` name in the file is enumerated by

    grep -o '^def mo_[a-z_0-9]*' tinybendygrad/mixin/op.bend | sort -u    # 91 distinct names

(113 `def mo_*` lines, the extra 22 being the `.go`/`.at` sub-defs of a public def). Of those
91, a name is IN the population iff its body is the port of a CPython METHOD -- the recipes
`op.bend` ports from `tinygrad/mixin/op.py` plus the `reduce.py` / `elementwise.py` /
`movement.py` methods it HOISTS (its own header calls them hoists). That leaves 30:

    op.py        min, mean, var, var_mean, std, std_mean, normalize->mo_norm0, logsumexp,
                 _softmax->mo_softmax3, softmax, log_softmax, softmin              (12)
    reduce.py    max, sum, prod                                                    (3)
    elementwise  neg, logical_not->mo_notb, eq->mo_eqc, isfinite, isnan, exp, log,
                 reciprocal->mo_recip, _inverse->mo_inverse, sub, div, where        (12)
    movement.py  reshape, permute, squeeze                                         (3)

The other 61 names fall out as SUBSTRATE (`mo_bin`, `mo_promote`, `mo_alu2`, `mo_const_t`,
`mo_dims`, ...), PRINTERS (`mo_sig`, `mo_row`, `mo_shape`), FIXTURES (`mo_fx1d`, `mo_buf4`)
and CONSTANTS (`mo_log2e`, `mo_inf`, `mo_eps`). `mo_reduce`/`mo_bin` are `_reduce`/`_binop`
-- private, and reached only through a public method, so they are out by the same rule
`ew_graph_census` uses to drop `_broadcasted`.

TWO PRIVATE METHODS ARE IN, AND SAYING WHY IS THE POINT. `mo_inverse` is `_inverse`
(elementwise.py:391) and `mo_softmax3` is `_softmax` (op.py:657). Each has a FIXED body and
the port gives it its own def; `mixin-op-gate` already rows `_softmax`. The excluded private
pair takes the op as a PARAMETER (`_reduce(op, ...)`, `_binop(op, ...)`), so its effect is
visible only through a recipe and a standalone row would be a second reading of one graph.

WHAT IT ASSERTS. The port's toposort OP SEQUENCE against CPython's, for the method each def
mirrors. The printer is the port's OWN `M.mo_sig_t` (`op.bend:1146`) -- the deep toposort
sequence, bare op names -- and the oracle is the deep `sig()` the sibling `mixin-op-gate`
already uses, so a wrong node ANYWHERE in the graph moves a row and not only the root.

THE `permute0` DEFECT IS FIXED AND THE PIN IS GONE. The census used to pin `mo_permute.pick`
(`op.bend:667`) reading the arena BEFORE the build that grows it --
`T.tn_new(T.Tensor.ar(t), O.Found.i(T.tn_mop(...)))`, whose FIRST argument is read before the
PERMUTE is interned, so the returned Tensor named an index its own arena did not hold (the
`NOOP` bottom) and printed `permute0=1 NOOP/0` against CPython's
`5 BUFFER/0 CONST/0 STACK/2 RESHAPE/2 PERMUTE/1`. The fix binds the `Found` from `tn_mop` and
wraps it with `T.tn_alu.put` -- the one spelling that cannot name the wrong arena, and the same
shape the sibling `mo_reshape` (`op.bend:658`) already had. `mo_permute` has NO caller in the
tree (the movement wrapper is `mixin/movement.bend`'s `mxw_permute`), so the defect was LATENT;
it is fixed and `permute0` is now a COMPARED row.

EXIT STATUS: 0 all three lanes identical · 1 a lane took the wrong row count, the oracle failed,
the native compile failed, or the lanes disagree · 3 a precondition was absent (the output
directory, the substrate, or the oracle). `DEAD`/`SKIP` are `gatekit`'s 5/4 and this gate does
not produce them.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    # reduce.py
    "max0",
    "max0kd",
    "sum0",
    "sum0kd",
    "prod0",
    # elementwise.py -- unary
    "neg0",
    "notb0",
    "eqc0",
    "isfinite0",
    "isnan0",
    "exp0",
    "log0",
    "recip0",
    "inverse0",
    # elementwise.py -- binary
    "sub00",
    "div00",
    "where0",
    # movement.py
    "reshape0",
    "permute0",
    "squeeze0",
    # op.py
    "min0",
    "mean0",
    "var0",
    "std0",
    "varmean0_v",
    "varmean0_m",
    "stdmean0_s",
    "stdmean0_m",
    "norm0",
    "lse0",
    "lse0kd",
    "softmax0",
    "logsoftmax0",
    "softmin0",
    "softmax3_m",
    "softmax3_e",
    "softmax3_ss",
)

# No declared divergence: the `permute0` NOOP defect was fixed (see the module docstring), so
# every row is COMPARED.
DIVERGES = {}

GATE = Gate(
    "mo_graph_census-gate",
    bend="mo_graph_census.bend",
    oracle="mo_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "mo_graph_census-gate: 37 rows, 3 lanes, 30 public mo_* defs -- "
                        "all 37 op sequences match CPython byte-for-byte (the callerless "
                        "mo_permute NOOP defect is fixed and its pin dropped)"))
