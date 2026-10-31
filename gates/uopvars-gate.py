#!/usr/bin/env python3
"""uopvars-gate.py -- THE GATE for `UOp.is_variable`, `UOp.unbound` and
`UOp.variables` (tinygrad/uop/ops.py:1009, :1027, :1037).

    .venv/bin/python gates/uopvars-gate.py

TWENTY ROWS, TWO LANES. These three names were WALL C of
`tinybendygrad/schedule/__init__.bend`'s deferral: `resolve_linear_call` stands
on `variables()`, which stands on `is_variable` and `unbound`, and none of the
three existed. A `variables()` that drops one of its two arms answers a
PLAUSIBLE parameter set and is wrong, so the rows are the only thing that can
make an arm visible.

WHAT THE ROWS ARE FOR, ONE BY ONE:

  iv_*  THE FOUR CONJUNCTS OF `is_variable`, one row each. `iv_alu_img` is the
        SHAPE conjunct: an image2d PARAM has a range and an ALU addrspace, so
        only the `_shape == ()` term answers False. `iv_alu_bound` is True, and
        that is the reason `unbound` exists as a separate def.
  ub_*  `unbound()` clears `val` and PRESERVES the name, and
        `ub_same_as_unbound` asks IDENTITY: upstream's `set` dedups a bound
        Variable against its unbound form only because hash-consing makes them
        the SAME node. A rebuild-by-fields that copies the values correctly is
        still wrong here, and only an identity row can see it.
  vs_*  THE TWO ARMS. `vs_dedup` is the PARAM arm's dedup (`v + v` is one
        parameter, not two). `vs_device` vs `vs_weak` is the RANGE arm: the
        SAME range and the SAME variable, differing only in the AXIS, answer 2
        and 1 -- so a port that minted `_device_num` for every axis, or for
        none, moves exactly one of them.
  vs_dev_*  the minted node ITSELF, not just its count: `_device_num`, range
        `0..7`, and reachable. THIS ROW IS WHERE THE GATE FOUND A REAL DEFECT
        IN THE PORT: `variables` mints through `UOp.new`, which APPENDS, and
        the first draft returned bare indices into an arena the caller never
        received. Every count was right and the node was unreachable.

A COUNT IS NOT A STRUCTURE. `vs_dev_count=1` held while the index was dangling,
which is why `vs_dev_vmax`/`vs_dev_name` read the node back through the arena
the ANSWER carries (`F.VarR.ar`) rather than the fixture's.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "iv_alu_range",
    "iv_alu_norange",
    "iv_global_range",
    "iv_alu_bound",
    "iv_variable",
    "iv_alu_img",
    "iv_not_param",
    "ub_val_none",
    "ub_name_kept",
    "ub_same_as_unbound",
    "vs_none",
    "vs_one",
    "vs_dedup",
    "vs_two",
    "vs_bound",
    "vs_device",
    "vs_weak",
    "vs_dev_count",
    "vs_dev_vmax",
    "vs_dev_name",
    "lb_k0_self",
    "lb_k1_moved",
    "lb_k1_unbound",
    "lb_k2_self",
    "lb_gone",
)

GATE = Gate(
    "uopvars-gate",
    bend="gates/uopvars.bend",
    oracle="gates/uopvars-oracle.py",
    rows=len(ROWS),
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(
        main(
            GATE,
            "uopvars-gate: 25 rows, 2 lanes -- `is_variable` (ops.py:1009), "
            "`unbound` (:1027) and `variables` (:1037), WALL C of "
            "`schedule/__init__.bend`'s deferral, AND `sc_linear_binds` "
            "(`__init__.py:104-106`), the CONSUMER that makes the first two "
            "live. The four conjuncts of `is_variable` are one row each, "
            "`ub_same_as_unbound` is an IDENTITY and not a field comparison, "
            "`vs_device` vs `vs_weak` is the RANGE arm's axis test, and "
            "`lb_k1_unbound` is the one row an `always return x` binds cannot pass",
        )
    )
