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
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import BEND, PY, Gate, gate

ROWS = (
    # the four VALUE rows -- the layer's own non-graph claims, the controls.
    "params", "bufs", "acc", "nop",
    # the graph rows, in file order.
    "detach", "apply", "square", "div", "sqrt", "recip", "neg", "sum", "normsq", "cast",
    "where", "guard", "mulf", "prewd", "trust", "lars0", "mom", "nesterov", "postwd",
    "mstep", "vstep", "mhat", "vhat", "lamb_up",
)

# THE DIVERGENCE POPULATION, DECLARED; THE CONTENT, PINNED BY PATH.
#
# THE SPLIT IS THE POINT AND IT IS NOT COSMETIC. These two rows are expected values -- whole lane
# lines, bit patterns and all -- and until now they were INLINE LITERALS IN THIS FILE, which means
# (a) a reviewer diffing this gate could not see a moved pin without reading 16 lines of wrapped
# string, and (b) `gates/assertlit-census.py`'s GATE arm counted them as 50 UNSOURCED tokens, the
# largest single gate in its table, because a `f1063675494` is a number no CPython expression
# spells. Moving the CONTENT to `gates/op_graph_census-pins.rows` does NOT make those numbers
# derived -- nothing can, they are what a divergence IS -- but it makes them a FILE, so the next
# refresh is a diff instead of a rewrite, which is the whole argument for a pins file.
#
# `decomp_graph_census-gate.py` and `crp_graph_census-gate.py` are the shapes copied: the gate
# declares WHICH rows diverge, `--refresh` is the ONLY writer of the content, and `_pins()` checks
# the two against each other rather than deriving one from the other. A row pinned and not declared
# is a pin nothing will exclude; a row declared and not pinned is an exclusion with no content.
DIVERGING = ("mstep", "vstep")

# `(1.0 - self.b1)` -- optim.py:167. CPython subtracts in DOUBLE; the port in f32. The two graphs
# are IDENTICAL except this one CONST's bits. `(1.0 - self.b2)` -- optim.py:168, the same with
# 0.999. See the module docstring for why neither is a graph defect.
WHY = {"mstep": "FLOAT-PRECISION, optim.py:167 `(1.0 - self.b1)`: CPython subtracts in DOUBLE, "
                 "the port in f32. Every op, arity and src order is identical",
       "vstep": "FLOAT-PRECISION, optim.py:168 `(1.0 - self.b2)`: the same with 0.999"}

PINS = Path(__file__).resolve().parent / "op_graph_census-pins.rows"


def _pins():
    """`(DIVERGES, why)` -- the pins LOADED BY PATH, against the declared population.

    A MISSING FILE IS REFUSED, NOT AN EMPTY DICT: `gates/decomp_graph_census-gate.py` records that
    its predecessor read `DIVERGES` out of `gates/artifacts/`, which `gatekit` EMPTIES before every
    run, and MEASURED it came back empty -- so the gate demanded all 28 rows agree and `gatekit`'s
    `bad = [...] [:2]` printed only the FIRST TWO of the disagreements. Twenty-eight rows live in
    git beside the gate, not in a directory a red run clears.
    """
    if not PINS.is_file():
        return None, (f"{PINS.name} is MISSING -- a gate's declared divergences must live in git, "
                      f"not in its own output directory. Run --refresh.")
    pins = {}
    for ln in PINS.read_text().splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        row, py, bd = ln.split("\t")
        pins[row] = (py, bd)
    if set(pins) != set(DIVERGING):
        extra, gone = sorted(set(pins) - set(DIVERGING)), sorted(set(DIVERGING) - set(pins))
        return None, (f"the pins file and the declared population disagree: pinned but not "
                      f"declared {extra}, declared but not pinned {gone}")
    return pins, ""


# `crp_graph_census-gate.py` names the second element `WHY` because it has no `WHY` of its own to
# shadow. This file DOES -- the per-row CLASS dictionary above -- and binding `_pins()`'s refusal
# string to it turned `WHY.get(r, '')` into `'str'.get(...)`. So the second element is `REFUSAL`
# here, and the collision is the reason rather than a preference.
DIVERGES, REFUSAL = _pins()

def refresh() -> int:
    """REWRITE `op_graph_census-pins.rows` FROM A FRESH PAIR OF LANES. Its only writer.

    **THE VALUES ARE MEASURED, NOT TRANSCRIBED, AND THAT IS THE WHOLE ARGUMENT FOR THE FILE.**
    A pins file somebody typed is a second copy of the answer with none of the derivation, and the
    brief's rule is explicit: do not create one whose values you derived yourself. So this runs
    both lanes and writes whatever DISAGREES. `--refresh` does not go through `Gate.run()` because
    a refresh is exactly what a run cannot do when the pins are wrong -- the point is to replace
    them.

    IT ALSO REFUSES TO PIN A ROW THAT IS NOT DECLARED. A `vstep` that stops diverging is a FIX, and
    pinning the new agreement would hide it behind a green run; `crp_graph_census-gate.py` records
    the same rule for its cleared `PROMOTION-FOLD` class ("a cleared defect that COMES BACK is a
    new finding and not a stale pin").
    """
    root = PINS.parent.parent
    py = subprocess.run([str(PY), str(root / "gates" / "op_graph_census-oracle.py")],
                        capture_output=True, text=True, cwd=root)
    bd = subprocess.run([str(BEND), str(root / "gates" / "op_graph_census.bend")],
                        capture_output=True, text=True, cwd=root)
    if py.returncode or bd.returncode:
        print(f"--refresh: a lane failed (py rc={py.returncode}, bd rc={bd.returncode}); nothing "
              f"written", file=sys.stderr)
        return 1
    got = {t: {l.split("=", 1)[0]: l for l in s.splitlines() if "=" in l}
           for t, s in (("py", py.stdout), ("bd", bd.stdout))}
    same = [r for r in ROWS if got["py"].get(r) == got["bd"].get(r)]
    rows = [r for r in ROWS if got["py"].get(r) != got["bd"].get(r)]
    undeclared = sorted(set(rows) - set(DIVERGING))
    if undeclared:
        print(f"--refresh: {len(rows)} rows disagree and {len(undeclared)} of them are NOT "
              f"declared: {undeclared}. Declare the class before refreshing, or a new difference "
              f"gets pinned as though it had always been expected", file=sys.stderr)
        return 1
    out = [
        "# op_graph_census-pins.rows -- GENERATED by `op_graph_census-gate.py --refresh`, which is",
        "# its ONLY writer. One TAB-separated TRIPLE per declared divergence:",
        "# `<row>\\t<CPython's line>\\t<the port's line>`.",
        "#",
        f"# {len(rows)} DIVERGENCES of {len(ROWS)} ROWS, {len(same)} OF WHICH AGREE EXACTLY. Both",
        "# sides are MEASURED from a fresh pair of lanes by the refresh that wrote this file;",
        "# nothing here is transcribed.",
        "#",
        "# THE VALUES ARE BIT PATTERNS AND NO CPYTHON EXPRESSION SPELLS THEM, which is what a",
        "# divergence IS: the two lanes differ in a float32 CONST's bits and the pin is the",
        "# disagreement, recorded so a fix has to move it deliberately. `gates/assertlit-census.py`",
        "# counts them as UNSOURCED, and that is the correct reading -- the file is where they can",
        "# be DIFFED.",
    ]
    for r in rows:
        out.append(f"# {r:<6} {WHY.get(r, '')}")
        out.append(f"{r}\t{got['py'][r]}\t{got['bd'][r]}")
    PINS.write_text("\n".join(out) + "\n")
    print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences, {len(same)} exact matches")
    return 0


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


# BOTH DISPATCHES ARE AT MODULE SCOPE AND BOTH ARE ABOVE `Gate(...)`, and that is not a style
# choice. `gatekit.Gate.__init__` CLEARS `gates/artifacts/op_graph_census-gate/` as it constructs
# (`gates/gatekit.py`: "A GATE CLEARS ITS OWN OUTPUT BEFORE ANY CHECK CAN FAIL, NOT AT THE TOP OF
# `run()`"), so a `--refresh` dispatched after the constructor would have its fresh lanes deleted
# by the gate it was refreshing -- and `refresh()` is DEFINED ABOVE this block for the same
# ordering reason. `decomp_graph_census-gate.py:494-503` has the identical shape and the identical
# reason, which is why this file copies it rather than inventing one.
if "--refresh" in sys.argv:
    sys.exit(refresh())
if DIVERGES is None:
    print(f"op_graph_census-gate: REFUSED, NOT A VERDICT: {REFUSAL}", file=sys.stderr)
    sys.exit(3)

GATE = Gate(
    "op_graph_census-gate",
    bend="op_graph_census.bend",
    oracle="op_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)


if __name__ == "__main__":
    sys.exit(gate(GATE, "op_graph_census-gate: 28 rows, 3 lanes, 2 DECLARED divergences. The four "
                       "value rows and all 24 graph rows match CPython byte-for-byte EXCEPT the "
                       "`(1.0 - b)` CONST of `mstep`/`vstep`, a DOUBLE-vs-F32 difference Bend "
                       "cannot close (no f64). The 16 fixed rows were `apply`/`neg` (wrong op), "
                       "`cast` (empty arena) and 13 stale-arena self-loops",
                 checks=no_noop_unpinned))
