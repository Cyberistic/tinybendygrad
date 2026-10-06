#!/usr/bin/env python3
"""ops-core-gate.py -- THE FIRST GATE FOR `tinybendygrad/uop/ops.bend`.

    .venv/bin/python gates/ops-core-gate.py

5 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- over the CONST-IDENTITY
claims that `ops.bend` already asserts in-file.

WHAT THIS IS FOR. `ops.bend` carries 55 `t_*` tests and, until this gate, no denominator at all:
each one was written, believed and unverified, which is the exact state the project rules call
unportable. Five of them are the CONST-identity cluster, and they are the five whose CPython
answers are already MEASURED in the port's own notes (`ops.bend:5044-5045`), so the oracle here
is a restatement of a measurement rather than a guess about what tinygrad would do.

THE FIVE CLAIMS, and the failure each one is shaped to catch:

    hashcons_same_index   the same key on an arena that already holds it returns the SAME node.
                          Catches a port that mints a duplicate instead of interning.
    zeros_differ          0.0 and -0.0 are DIFFERENT nodes. Identity is the BIT PATTERN, and
    nan_interns           two NaNs are ONE node. IEEE equality disagrees in BOTH directions, so
                          these two rows together are what makes `F32.bits` non-negotiable: a
                          port comparing `F32.is_eq` gets one of the two backwards. `decomp.bend`
                          may keep `is_eq`, because there it asks a different question.
    bool_vs_int_key       a bool const and an int const are different keys, which is what makes
                          `Cls` an explicit tag rather than a signedness flag.
    backedge_srcs         a BACKEDGE's src[0] is the node it was called on and src[1] the RANGE.

WHY FIVE OF FIFTY-FIVE. The rest of the 55 want `simplify` or arena machinery still behind its
own `TODO(p3)` markers. Gating a wall would make the denominator a claim about code that does not
exist yet. A gate over the finished subset can be trusted; a gate over everything cannot, and
trusting it is how gates rot.

GROWING IT. Every row here is a property CPython can be asked directly, so the next unit is: pick
the next cluster whose CPython statements are measurements rather than guesses, add the rows to
both lanes, and raise `rows`. The harness does not need to change for that, which is the point of
having it in `gates/` rather than in a scratch directory that a sweep can delete out from under a
gate that still names it.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

GATE = Gate(
    "ops-core-gate",
    bend="ops-core.bend",
    oracle="ops-core-oracle.py",
    rows=5,
    # The row NAMES are claims about WHICH property is being asked, not about its answer, so
    # they are pinned on both sides: a row renamed on one lane only would be a gate that had
    # stopped asking its question without saying so. The VALUES are diffed, not pinned -- the
    # value is the claim, and pinning it here as well would pin the answer twice over.
    pins=[
        ("py", "hashcons_same_index"),
        ("py", "zeros_differ"),
        ("py", "nan_interns"),
        ("py", "bool_vs_int_key"),
        ("py", "backedge_srcs"),
        ("bd", "hashcons_same_index"),
        ("bd", "zeros_differ"),
        ("bd", "nan_interns"),
        ("bd", "bool_vs_int_key"),
        ("bd", "backedge_srcs"),
    ],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "ops-core-gate: 5 rows, 3 lanes, ops.bend's CONST-identity claims "
                        "agree with CPython"))
