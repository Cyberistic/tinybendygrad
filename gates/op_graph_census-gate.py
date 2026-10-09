#!/usr/bin/env python3
"""op_graph_census-gate.py -- A GRAPH CENSUS over the GRAPH-BUILDING defs of
`tinybendygrad/nn/optim.bend`.

    .venv/bin/python gates/op_graph_census-gate.py

28 ROWS, THREE LANES, EIGHTEEN DECLARED DIVERGENCES -- AND ALL EIGHTEEN ARE DEFECTS, NONE A
CARVE-OUT. This is the `optim.bend` peer of `gates/tn_graph_census-gate.py` / `mo_*` / `ew_*` /
`mx_*` / `cr_*` / `gr_*`: the whole graph-building surface of the layer in one artifact. The
layer's own `main` prints eleven rows under `unverified_*` names and its own comment says "the
ARENA PLUMBING is not finished"; THIS drives each builder directly and pins the exact trees, so
a fix turns the gate RED and forces the pin to move.

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

THE EIGHTEEN DIVERGENCES, CLASSIFIED. There are NO carve-outs: every one is a defect. They fall
into FOUR root causes, and the pin text is the measurement.

  OP CHOICE, 2 rows (`apply`, `neg`):
    `apply` -- `_apply_update` is `t.detach() - up.to(t.device)` (optim.py:60). CPython's `sub`
      is `a.alu(Ops.ADD, -b)` (mixin/elementwise.py:121-123), i.e. `ADD(detach, MUL(g, CONST(-1)))`.
      The port's `op_sub` (optim.bend:424-425) builds a bare `SUB`. THIS IS THE EXACT TRAP THE
      BRIEF NAMES: an oracle that reached for `alu(Ops.SUB)` would have agreed with the port while
      BOTH were wrong. The oracle calls the operator.
    `neg` -- `-t` is `MUL(t, CONST(-1))` (`__neg__`), 3 nodes. `op_neg` (optim.bend:708-712)
      builds `NEG`, 2 nodes.

  TENSOR.BEND'S EMPTY ARENA, 1 row (`cast`):
    `g.cast(t.dtype)` (optim.py:128) is a real node. `op_cast` (optim.bend:720-721) delegates to
    `tn_cast.of`, whose `tn_cast.put.of`/`tn_cast.node` build into `O.Arena.empty()`
    (tensor.bend:1260, :1265), so the returned Tensor's index is out of range in its own arena.
    The identity arm answers `1 NOOP/0` where CPython answers the src `1 BUFFER/0`.

  STALE-ARENA THREADING, 14 rows -- ONE MECHANISM, MEASURED, not 14 stories:
    A helper interns a CONST into `op_ar(x)` (GROWING that arena to a new value) and then builds
    the consuming node into the SAME PRE-GROWTH arena, at the index the const took. The const is
    orphaned and the consuming node's src[0] is ITS OWN INDEX -- a SELF-LOOP, which makes
    `toposort` exhaust its fuel with an empty cache and answer `0`. The rows:
      `normsq` -- `op_normsq` (optim.bend:762-763) passes `op_ar(a)` (pre-square) to `op_sum`.
      `where`  -- `op_where` (optim.bend:663-665) interns `1.0` then builds the WHERE in the
                  pre-growth arena.
      `guard`  -- `op_cmplt1` (optim.bend:801-802), the same, AND its constant is `1.0` where
                  optim.py:115 is `0`. THE CONSTANT IS A SECOND DEFECT THAT THE PRINTER CANNOT
                  SEE while the arena bug stands (the const never reaches the graph); the `:arg`
                  suffix is the instrument that will catch it the moment the arena is fixed.
      `mulf`   -- `op_mulf` (optim.bend:780-781) interns `v` into `op_ar(a)` then calls
                  `op_mul_l(const, a)`, which builds into `op_ar(a)` -- the pre-growth value.
      `prewd`, `postwd`, `mstep`, `vstep`, `mhat`, `vhat`, `trust` -- all reach `op_mulf` or
                  `op_where`, so they inherit it.
      `lars0`  -- `op_lars0` (optim.bend:1248-1249) passes `st_ar(s)` to `op_lr_mul` while the
                  `r` CONST was interned into a newer arena.
      `mom`, `nesterov` -- reach `op_mulf`.
      `lamb_up` -- reaches `op_mul_l` with an operand whose arena is newer than the target.

  THE FILE'S OWN COMMENT SAYS "the ARENA PLUMBING is not finished" AND THIS IS THAT, MEASURED:
  the precise mechanism is a SELF-LOOP from a pre-growth arena, not a "missing CONST" -- the
  CONST is built and then orphaned. A reviewer reading the file's comment would fix the wrong
  thing.

WHAT IT ASSERTS THAT NEEDS NO CPYTHON. `NOOP` IS THE BOTTOM (`Arena.bottom()`), so a `NOOP`
anywhere is an index read out of range and ALWAYS a defect. Four rows print one (`cast`,
`mstep`, `vstep`, `lamb_up`) and the `no_noop_unpinned` check asserts every NOOP row is in the
declared-divergence list -- so a NOOP cannot appear without being declared.

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

# (CPython's line, the port's line), pinned on both sides. EVERY entry is a DEFECT -- there is no
# carve-out in this gate -- and the pins LOCK the current wrong answer so a fix makes the gate RED.
DIVERGES = {
    "apply": ("apply=6 BUFFER/0:- DETACH/1:- BUFFER/0:- CONST/0:f3212836864 MUL/2:- ADD/2:- ",
              "apply=4 BUFFER/0:- DETACH/1:- BUFFER/0:- SUB/2:- "),
    "neg": ("neg=3 BUFFER/0:- CONST/0:f3212836864 MUL/2:- ",
            "neg=2 BUFFER/0:- NEG/1:- "),
    "normsq": ("normsq=4 BUFFER/0:- MUL/2:- REDUCE/1:- SQRT/1:- ",
               "normsq=0 "),
    "cast": ("cast=1 BUFFER/0:- ",
             "cast=1 NOOP/0:- "),
    "where": ("where=6 CONST/0:f0 BUFFER/0:- CMPLT/2:- BUFFER/0:- CONST/0:f1065353216 WHERE/3:- ",
              "where=0 "),
    "guard": ("guard=3 CONST/0:f0 BUFFER/0:- CMPLT/2:- ",
              "guard=0 "),
    "mulf": ("mulf=3 CONST/0:f1036831949 BUFFER/0:- MUL/2:- ",
             "mulf=0 "),
    "prewd": ("prewd=6 BUFFER/0:- CONST/0:f1036831949 BUFFER/0:- DETACH/1:- MUL/2:- ADD/2:- ",
              "prewd=1 BUFFER/0:- "),
    "trust": ("trust=21 CONST/0:f0 BUFFER/0:- DETACH/1:- MUL/2:- REDUCE/1:- SQRT/1:- CMPLT/2:- "
              "BUFFER/0:- MUL/2:- REDUCE/1:- SQRT/1:- CMPLT/2:- CONST/0:f981668463 MUL/2:- "
              "MUL/2:- ADD/2:- RECIPROCAL/1:- MUL/2:- CONST/0:f1065353216 WHERE/3:- WHERE/3:- ",
              "trust=0 "),
    "lars0": ("lars0=5 BUFFER/0:- CONST/0:f1065353216 MUL/2:- BUFFER/0:- MUL/2:- ",
              "lars0=1 BUFFER/0:- "),
    "mom": ("mom=7 BUFFER/0:- CONST/0:f1063675494 MUL/2:- BUFFER/0:- ADD/2:- STORE/2:- AFTER/2:- ",
            "mom=1 BUFFER/0:- "),
    "nesterov": ("nesterov=5 BUFFER/0:- CONST/0:f1063675494 BUFFER/0:- MUL/2:- ADD/2:- ",
                 "nesterov=1 BUFFER/0:- "),
    "postwd": ("postwd=8 BUFFER/0:- CONST/0:f1036831949 BUFFER/0:- MUL/2:- BUFFER/0:- "
               "DETACH/1:- MUL/2:- ADD/2:- ",
               "postwd=1 BUFFER/0:- "),
    "mstep": ("mstep=7 CONST/0:f1063675494 BUFFER/0:- MUL/2:- CONST/0:f1036831949 BUFFER/0:- "
              "MUL/2:- ADD/2:- ",
              "mstep=1 NOOP/0:- "),
    "vstep": ("vstep=8 CONST/0:f1065336439 BUFFER/0:- MUL/2:- CONST/0:f981668463 BUFFER/0:- "
              "MUL/2:- MUL/2:- ADD/2:- ",
              "vstep=1 NOOP/0:- "),
    "mhat": ("mhat=8 BUFFER/0:- CONST/0:f1065353216 BUFFER/0:- CONST/0:f3212836864 MUL/2:- "
             "ADD/2:- RECIPROCAL/1:- MUL/2:- ",
             "mhat=1 BUFFER/0:- "),
    "vhat": ("vhat=8 BUFFER/0:- CONST/0:f1065353216 BUFFER/0:- CONST/0:f3212836864 MUL/2:- "
             "ADD/2:- RECIPROCAL/1:- MUL/2:- ",
             "vhat=1 BUFFER/0:- "),
    "lamb_up": ("lamb_up=5 BUFFER/0:- CONST/0:f1065353216 MUL/2:- BUFFER/0:- MUL/2:- ",
                "lamb_up=1 NOOP/0:- "),
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
    sys.exit(gate(GATE, "op_graph_census-gate: 28 rows, 3 lanes, 18 DECLARED divergences -- the "
                       "four value rows and 6 of 24 graph rows (detach, square, div, sqrt, recip, "
                       "sum) match CPython byte-for-byte; the other 18 are DEFECTS with no "
                       "carve-out: `apply`/`neg` reach for the wrong op, `cast` builds in an empty "
                       "arena, and 15 rows inherit ONE stale-arena self-loop (`op_mulf`/`op_where`/"
                       "`op_cmplt1` intern a CONST and then build in the PRE-growth arena)",
                 checks=no_noop_unpinned))
