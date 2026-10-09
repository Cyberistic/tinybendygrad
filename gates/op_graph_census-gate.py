#!/usr/bin/env python3
"""op_graph_census-gate.py -- A GRAPH CENSUS over the GRAPH-BUILDING defs of
`tinybendygrad/nn/optim.bend`.

    .venv/bin/python gates/op_graph_census-gate.py

28 ROWS, THREE LANES, TWO DECLARED DIVERGENCES. This is the `optim.bend` peer of
`gates/tn_graph_census-gate.py` / `mo_*` / `ew_*` / `mx_*` / `cr_*` / `gr_*`: the whole
graph-building surface of the layer in one artifact. The layer's own `main` prints eleven rows
under `unverified_*` names and its own comment said "the ARENA PLUMBING is not finished"; THIS
drives each builder directly and pins the exact trees, so a fix turns the gate RED and forces
the pin to move. SIXTEEN of the eighteen original divergences are FIXED and deleted; the two
that remain are a FLOAT-PRECISION divergence and NOT a graph one (see below).

THE POPULATION IS DISCOVERED, AND THE RULE IS STATED HERE. The file has 176 defs:

    grep -o '^def [a-z]*[a-z_0-9]*' tinybendygrad/nn/optim.bend | sed 's/def //' \\
      | sed 's/[_.].*//' | sort | uniq -c    # 176 in 15 groups (op 107, t 23, st 10, ...)

A def is a ROW iff it BUILDS A GRAPH and MIRRORS A NAMED CPYTHON EXPRESSION -- the `op_*` /
`op_*.*` defs whose body reaches a node write (`T.tn_alu` / `T.tn_rop` / `T.tn_assign_store` /
`T.tn_const`), directly or through another such builder. That is 24 rows. The rest FALL OUT:
51 of the 107 `op_*` defs reach NO node write inside this file and are the READERS -- they
return a list/number/record (`op_filter`, `op_acc`, `op_last`, `op_pos`, `op_lr_ok`,
`op_param_dtype`, `op_lr_dtype`, `op_nop`, `op_zg`, `op_set_params`, `op_zero_grad`, `op_group`,
`op_grad_zero`, `op_sched`, `op_slice`, `op_ndim`, `op_axes`, `op_1mb`, `op_ar`, `op_with_arena`,
`op_last_ar`, plus their `.go`/`.of`/`.push` halves); and 69 non-`op_` defs are the fixtures,
printers and `main`. (`op_cast` is a row whose NODE is built in tensor.bend's `tn_cast`.) The
four VALUE rows (`params`/`bufs`/`acc`/`nop`) are the layer's own non-graph claims and are kept as
CONTROLS: they are the part of the file that was already correct.

THE PRINTER IS THE DEEP TOPOSORT PLUS EACH NODE'S ARG, AND THE ARG IS NOT DECORATION. `O.Rng.sig`
prints the count, the root op, the root nsrc and the SRC op sequence -- it does NOT print an ARG.
The layer's own guards compare against `CONST 1.0` where optim.py:115 says `0` (`op_cmplt1`,
optim.bend:801-802), and the two graphs are the SAME op sequence (`CONST/0 CMPLT/2`), so NO
op-level printer can see it. Every node therefore prints `<op>/<nsrc>:<arg>`.

THE TWO DIVERGENCES THAT REMAIN, AND WHY THEY ARE NOT A GRAPH DEFECT. Both are `op_1mb`
(`(1.0 - self.b1)` / `(1.0 - self.b2)`, optim.py:167-168), and both are a DOUBLE-vs-F32
arithmetic difference that Bend cannot close because it has no `f64`:

  `mstep` -- CPython's `1.0 - 0.9` is a DOUBLE subtraction, `0.09999999999999998`, whose f32
    image is `0x3DCCCCCD` (`f1036831949`). The port's `op_1mb` subtracts in f32:
    `1.0 - 0.9f = 0.100000024`, `0x3DCCCCD0` (`f1036831952`). The two graphs are otherwise
    IDENTICAL -- every op, every nsrc, every src order -- and only that CONST's bits differ.
  `vstep` -- the same with `0.999`: CPython `1.0 - 0.999` -> `f981668463` (`0x3A83126F`); the
    port `1.0 - 0.999f` -> `f981668352` (`0x3A831200`).

MEASURED 2026-10-09: no f32 `v` within +/-200000 ULP of the f32 literal gives the CPython bits
under `1.0 - v`, so this is not a rounding-mode choice -- the port's `b1` is f32 where CPython's
is a double. The `:arg` suffix is the instrument that shows it; `O.Rng.sig`'s op-level printer
cannot.

THE SIXTEEN THAT WERE FIXED, AND THE MECHANISM. All were measured, all are gone, and each was a
defect and not a carve-out:

  OP CHOICE, 2 rows (`apply`, `neg`):
    `apply` -- `_apply_update` is `t.detach() - up.to(t.device)` (optim.py:60). CPython's `sub`
      is `a.alu(Ops.ADD, -b)` (elementwise.py:103), i.e. `ADD(detach, MUL(up, CONST(-1)))`. The
      old `op_sub` built a bare `SUB`. THIS IS THE EXACT TRAP: an oracle that reached for
      `alu(Ops.SUB)` would have agreed with the port while BOTH were wrong. The oracle calls the
      operator.
    `neg` -- `-t` is `MUL(t, CONST(-1))` (`__neg__`, elementwise.py:261), 3 nodes. The old
      `op_neg` built `NEG`, 2 nodes.

  TENSOR.BEND'S EMPTY ARENA, 1 row (`cast`):
    `g.cast(t.dtype)` (optim.py:128) is a real node. `op_cast` delegated to `tn_cast.of`, whose
    `tn_cast.put.of`/`tn_cast.node` built into `O.Arena.empty()` (tensor.bend), so an identity
    cast answered `1 NOOP/0` where CPython answers the src `1 BUFFER/0`. `tn_cast` now takes the
    arena as a parameter and `tn_alu.put` wraps its `Found`.

  STALE-ARENA THREADING, 13 rows -- ONE MECHANISM, MEASURED, not 13 stories:
    A helper interned a CONST into `op_ar(x)` (GROWING that arena to a new value) and then built
    the consuming node into the SAME PRE-GROWTH arena, at the index the const took. The const was
    orphaned and the consuming node's `src[0]` was ITS OWN INDEX -- a SELF-LOOP, which made
    `toposort` answer `0`. THE FIX IS ONE SPELLING: every two-operand node MERGES its operands'
    arenas (`tn_binop`, which is `Arena.merge` -- CONTENT, not length) and every three-operand
    node is `tn_where`. The rows: `normsq where guard mulf prewd trust lars0 mom nesterov postwd
    mhat vhat lamb_up`. (`mstep`/`vstep` inherited the same self-loop and their GRAPH is fixed;
    only their `op_1mb` CONST is the float divergence above.)

  AND THE `1.0`-vs-`0` GUARD, which the op-level printer CANNOT see: `op_cmplt1` built
    `CMPLT(CONST 1.0, x)` where optim.py:115 says `0`, and the two graphs are the SAME op sequence
    (`CONST/0 CMPLT/2`). It is now `0.0`; `guard` and `where` are the rows and the `:arg` suffix
    reads `f0` on both sides.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP`
anywhere is an index read out of range and ALWAYS a defect. MEASURED 2026-10-09: ZERO rows print
one -- the four that used to (`cast`, `mstep`, `vstep`, `lamb_up`) are fixed -- and the
`no_noop_unpinned` check still asserts every NOOP row is a declared divergence, so a NOOP cannot
appear without being declared.

EXIT STATUS: 0 all three lanes identical after the pins · 1 a lane took the wrong row count, the
oracle failed, the compile failed, or the lanes disagree · 3 a precondition was absent · 5 `bend`
ran and emitted no rows. `SKIP` (4) is not produced.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROWS = (
    # the four VALUE rows -- the layer's own non-graph claims, the controls.
    "params", "bufs", "acc", "nop",
    # the graph rows, in file order.
    "detach", "apply", "square", "div", "sqrt", "recip", "neg", "sum", "normsq", "cast",
    "where", "guard", "mulf", "prewd", "trust", "lars0", "mom", "nesterov", "postwd",
    "mstep", "vstep", "mhat", "vhat", "lamb_up",
)

# (CPython's line, the port's line), pinned on both sides. THE SIXTEEN THAT WERE DEFECTS ARE
# GONE; these TWO are a float-precision divergence (a double `1.0 - b` against an f32 `1.0 - b`)
# and the pins LOCK both sides so the graphs cannot drift apart unnoticed.
DIVERGES = {
    # `(1.0 - self.b1)` -- optim.py:167. CPython subtracts in DOUBLE; the port in f32. The two
    # graphs are IDENTICAL except this one CONST's bits. See the module docstring.
    "mstep": ("mstep=7 CONST/0:f1063675494 BUFFER/0:- MUL/2:- CONST/0:f1036831949 BUFFER/0:- "
              "MUL/2:- ADD/2:- ",
              "mstep=7 CONST/0:f1063675494 BUFFER/0:- MUL/2:- CONST/0:f1036831952 BUFFER/0:- "
              "MUL/2:- ADD/2:- "),
    # `(1.0 - self.b2)` -- optim.py:168, the same divergence with 0.999.
    "vstep": ("vstep=8 CONST/0:f1065336439 BUFFER/0:- MUL/2:- CONST/0:f981668463 BUFFER/0:- "
              "MUL/2:- MUL/2:- ADD/2:- ",
              "vstep=8 CONST/0:f1065336439 BUFFER/0:- MUL/2:- CONST/0:f981668352 BUFFER/0:- "
              "MUL/2:- MUL/2:- ADD/2:- "),
}

GATE = Gate(
    "op_graph_census-gate",
    bend="op_graph_census.bend",
    oracle="op_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


def no_noop_unpinned() -> bool:
    """EVERY ROW THAT PRINTS A `NOOP` IS A DECLARED DEFECT.

    `NOOP` is the arena's bottom, so a `NOOP` is an index read out of range and ALWAYS a defect
    -- it can never be a carve-out. This reads the LANE'S OWN output (`gatekit` promotes `bd.out`
    on a PASS) and asserts the set of NOOP-bearing rows is a SUBSET of the pinned ones, so a
    NOOP cannot appear without being declared, and a fix that removes one without moving its pin
    fails the pin instead.
    """
    rows = {l.split("=", 1)[0] for l in (GATE.dir / "bd.out").read_text().splitlines()
            if "NOOP" in l}
    return rows <= set(DIVERGES)


if __name__ == "__main__":
    sys.exit(gate(GATE, "op_graph_census-gate: 28 rows, 3 lanes, 2 DECLARED divergences. The four "
                       "value rows and all 24 graph rows match CPython byte-for-byte EXCEPT the "
                       "`(1.0 - b)` CONST of `mstep`/`vstep`, a DOUBLE-vs-F32 difference Bend "
                       "cannot close (no f64). The 16 fixed rows were `apply`/`neg` (wrong op), "
                       "`cast` (empty arena) and 13 stale-arena self-loops",
                 checks=no_noop_unpinned))
