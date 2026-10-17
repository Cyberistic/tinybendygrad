#!/usr/bin/env python3
"""tnvalue-census -- DOES THE *VALUE* OF AN ORACLE'S FIXTURE REACH ITS ROWS?

    .venv/bin/python gates/tnvalue-census.py              # the table
    .venv/bin/python gates/tnvalue-census.py --plant      # self-test
    .venv/bin/python gates/tnvalue-census.py --rss        # peak RSS + wall only

`gates/oracleblind.rows` (COMMITTED, sha256 614ea700469eeea9...) read **28** oracles
`ALL VALID INPUTS AGREE`, and **23** of them are `tn_*`. `gates/tn_sqrt-oracle.py` returns the
SAME five rows for `arg=` 4, 5, 0 and -4 -- four inputs, one answer. This file asks the
question that census CANNOT: not "does perturbing a literal move a row" (VALID-DIFFERENT already
did `n -> n+1` and BOUNDARY did `n -> -n` and BOTH moved **0** rows), but **WHY**, and whether a
VALUE-DERIVED row is available.

THE POINT OF THE CLASSIFICATION. "0 rows moved" has TWO causes and they demand OPPOSITE answers:

  V-LADDER-SENSITIVE   some rung of the ladder moved a row. The asked property was TRUE only for
                the value the fixture happens to hold, or the row reads the value outright. Either
                way the fixture's value is an UNASSERTED PREMISE and a defect.
  V-LADDER-STABLE      NO RUNG moved a row -- AND THAT IS ALL IT SAYS. It does NOT say the
                property is value-invariant. It says four points on the integer line agreed, and
                `sqrt(CONST{4}).op is SQRT` and `sqrt(CONST{5}).op is SQRT` are BOTH correct
                CPython, so for most of these rows stability is the RIGHT answer and a value axis
                has nothing to add.

THE VERDICT NAMES ARE DELIBERATELY WEAK, AND MEASURED WHY. THE FIRST VERSION OF THIS FILE
CALLED THE STABLE VERDICT `V-INVARIANT`, AND ITS OWN PLANT REFUTED IT. `plant-invariant` asserts
that a row reading `c.arg == 1` moves when the payload is retyped -- but the ladder is
`v, v+1, 0, -v` = `4, 5, 0, -4`, and **1 IS NOT ONE OF THEM**, so the row did not move and the
instrument was RIGHT while the name was a lie. A value axis built from a FIXED LADDER has a
detection hole, and no amount of care at the call site fills it: the value a row is sensitive to
is not knowable without reading the row, and reading the row is what forbids printing the
argument. So the ladder is DECLARED in every row of the table and the verdict claims only what
four points can support.

THE SECOND HALF OF THE ANSWER IS THE DTYPE, MEASURED NOT ASSUMED. The int payload is not what
selects an arm; the DTYPE is. `Tensor(UOp(Ops.CONST, arg=4)).cast(dtypes.uint8).bitwise_not()`
emits `XOR` with `src[1].arg == 255`, and the same graph in `dtypes.int32` emits `src[1].arg ==
-1`. That 255 is a value DERIVED FROM CPYTHON'S OWN GRAPH, it is not the argument, and it is the
one value axis these oracles have that is reachable without printing the fixture back.

WHAT MAY NOT BE ADDED. A row that prints the ARGUMENT is not a value axis: it is `arg=4 -> arg=4`,
a tautology in the shape of a measurement, and `gates/tn_bitwise_not-oracle.py`'s own header names
the trap ("an oracle that reimplements the thing it is checking agrees with itself"). So this file
NEVER proposes `print(f"..._arg_is_{v}")`. The only admissible value row is one DERIVED FROM
CPYTHON'S OWN EXPRESSION -- read out of the graph CPython built, or out of `tinygrad`'s own
dispatch -- which is the shape of `gates/op_graph_census-oracle.py`'s repaired `Nzs` derivation.

THE POPULATION IS NOT A LIST. It is (a) every oracle `gates/gates-pop.py`'s `discover()` admits,
LOADED BY PATH -- the derivation this tree already owns -- INTERSECTED with (b) the oracles that
AST-CONTAIN a `UOp(... arg=<int literal>)` CONST payload, discovered by walking the tree, and the
verdict is read from `gates/oracleblind.rows`, ALSO LOADED BY PATH. No `tn_*` basename filter
decides membership: a name shape is not a population (`.agents/AGENTS.md` doctrine 1).
"""
from __future__ import annotations

import argparse
import builtins
import ast
import hashlib
import importlib.util
import json
import os
import resource
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
SCRATCH = HERE / "artifacts" / "tnvalue"
ROWS = HERE / "tnvalue.rows"
# NOT a `.py` literal, and that is the point -- see `oracle_path`. This file perturbs its parent's
# population if it so much as NAMES an oracle as a string constant, and `plant no-declaration`
# asserts the whole class over this file's own AST.
BLIND_STEM = "oracleblind-census"
BLIND = HERE / (BLIND_STEM.removesuffix("-census") + ".rows")

# The CONST payload is minted by `UOp(Ops.CONST, src=(), arg=<int>)`. That call's shape IS the
# population rule and it is a SEMANTIC one: a filename cannot express "the fixture payload".
CONST_CALLS = ("UOp", "uop", "UOp.__new__")


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def const_payload_sites(src: str) -> list[tuple[int, int, int]]:
    """`[(lineno, col_offset, value)]` -- every INT literal bound to `arg=` in a `UOp(...)` mint.

    RETURNED AS SOURCE OFFSETS, so the substitution below needs no re-derivation of them and
    cannot drift from this scan: a plant asserts the two agree.
    """
    tree = ast.parse(src)
    lines = src.splitlines(keepends=True)
    starts, at = [], 0
    for l in lines:
        starts.append(at)
        at += len(l)
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        name = fn.id if isinstance(fn, ast.Name) else getattr(fn, "attr", "")
        if name not in CONST_CALLS:
            continue
        if not (isinstance(node.func, ast.Name) or isinstance(node.func, ast.Attribute)):
            continue
        for kw in node.keywords:
            if kw.arg == "arg" and isinstance(kw.value, ast.Constant) \
                    and isinstance(kw.value.value, int) and not isinstance(kw.value.value, bool):
                n = kw.value
                out.append((starts[n.lineno - 1] + n.col_offset,
                            starts[n.lineno - 1] + n.end_col_offset, n.value))
    return sorted(out)


def substitute(src: str, sites, index: int, value: int) -> str:
    """One site's INT literal retyped. Textual, at the offsets `const_payload_sites` returned."""
    lo, hi, _ = sites[index]
    return src[:lo] + repr(value) + src[hi:]


def ladder(value: int) -> list[tuple[str, int]]:
    """`(label, value)` -- THE BRIEF'S FOUR, generalised, and DEGENERATE ON ZERO.

    Every rung is a VALID input of the same shape, so this is a value axis and not a garbage axis.
    DECLARED IN EVERY ROW OF THE TABLE, because `V-LADDER-STABLE` is only a claim about THESE FOUR
    and a verdict that does not say which four cannot be checked.

    **MEASURED DEFECT IN THE FIRST VERSION, AND IT IS THE CLASS THAT PRODUCES THE MOST FINDINGS
    HERE.** `v, v+1, 0, -v` is only four DISTINCT rungs when `v != 0, -1`. MEASURED on the
    population: `gates/cstyle_render_census-oracle.py` and `gates/realize_graph_census-oracle.py`
    each hold a payload site of **0**, so their declared ladder was `0, 1, 0, 0` -- **two**
    distinct rungs under a name that says four, and `V-LADDER-STABLE` over two points would have
    read as a claim over four. A ladder that silently loses rungs is `ptx.bend`'s alias defect
    again: the instrument reported a denominator it was not measuring. So the candidates are taken
    IN ORDER and the first four DISTINCT values win, and the labels are recomputed to match.
    """
    want = [("v", value), ("v+1", value + 1), ("zero", 0), ("neg", -value),
            ("v-1", value - 1), ("neg1", -value - 1), ("two", 2), ("neg2", -value - 2)]
    out, seen = [], set()
    for label, v in want:
        if v in seen:
            continue
        seen.add(v)
        out.append((label, v))
        if len(out) == 4:
            return out
    return out


def invoke(script: Path):
    try:
        r = subprocess.run([str(PY), str(script)], cwd=ROOT, capture_output=True,
                           text=True, timeout=240)
        return {"rc": r.returncode, "out": r.stdout, "err": r.stderr[-400:]}
    except subprocess.TimeoutExpired:
        return {"rc": None, "out": "", "err": "TIMEOUT>240s"}


def rows_of(out: str) -> dict:
    m = {}
    for l in out.split("\n"):
        l = l.strip()
        if not l:
            continue
        k, sep, v = l.partition("=")
        m[k] = v if sep else ""
    return m


ROW_CALLS = ("print", "row", "rowf")


def row_shapes(src: str) -> dict:
    """`{row name: (kind, value expression)}` -- `kind` is `CONSTANT` or `DERIVED`.

    **THE RUNTIME VALUE IS NOT THE EVIDENCE, AND THE FIRST VERSION OF THIS FUNCTION PROVED IT.**
    It read the printed `=1`, and `gates/tn_relu-oracle.py`'s `relu_has_three_srcs=1` is a REAL
    query -- `len(r.uop.src) == 3` -- so that column would have called a working row a constant and
    a census that cannot tell a derived row from a literal is the `gates/autogen-oracle.py` class
    one level down. So the test is on the AST of the row's VALUE EXPRESSION.

    **AND THE SECOND VERSION OF THE RULE WAS ALSO WRONG, IN THE OTHER DIRECTION.** "Any `Name`
    means derived" classified `int(1)` as DERIVED, because `int` is a `Name` -- so the column came
    out EMPTY on a population that holds **24** of these rows, and an instrument that reports zero
    where the answer is 24 is worse than one that reports 24 wrongly. The rule that is actually
    right: a row is `CONSTANT` iff its value expression contains **no `Attribute` and no
    `Subscript`**, and **every `Name` in it is a Python builtin**. `int(1)` consults nothing;
    `int(len(r.uop.src) == 3)` and `int(r.uop.op is Ops.SQRT)` both reach a UOp and are `DERIVED`;
    `int(len(...))` is `DERIVED` even though `len` is a builtin, which is why the attribute test is
    the load-bearing half and the builtin test is only there to let `int(` through.

    `CONSTANT` IS NOT A NEW VERDICT AND IS NOT A COMPARISON. It is the `DEAD` state of
    `.agents/AGENTS.md` doctrine 2 -- "it ran and emitted nothing" -- in its purest form here:
    `print(f"{name}={int(1)}")` runs, emits a well-formed row, and cannot fail. The 24 rows this
    finds are named in `gates/tn_bitwise_not-oracle.py`'s OWN header as the defect that unit
    already fixed on its own oracle ("THE FIRST VERSION OF THE LAST ROW WAS
    `print(f"...={int(1)}")` -- A CONSTANT. IT COULD NOT FAIL"), so the shape is KNOWN to be a
    defect and known to have been repaired once.
    """
    tree = ast.parse(src)
    out = {}
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and node.args):
            continue
        fn = node.func
        nm = fn.id if isinstance(fn, ast.Name) else getattr(fn, "attr", "")
        if nm not in ROW_CALLS:
            continue
        f = node.args[0]
        if not isinstance(f, ast.JoinedStr):
            continue
        name = "".join(v.value for v in f.values if isinstance(v, ast.Constant))
        # The literal part of `f"{row}={value}"` INCLUDES the `=`, so an unstripped key is
        # `"sqrt_is_reachable="` and every lookup by row name misses. Measured, not assumed: the
        # first version of `plant constant` raised `KeyError: 'is_reachable'`.
        name = name[:-1] if name.endswith("=") else name
        parts, derived = [], False
        for v in f.values:
            if not isinstance(v, ast.FormattedValue):
                continue
            expr = ast.unparse(v.value)
            parts.append(expr)
            reaches = [x for x in ast.walk(v.value)
                       if isinstance(x, (ast.Attribute, ast.Subscript))]
            unknown = [x.id for x in ast.walk(v.value)
                       if isinstance(x, ast.Name) and x.id not in dir(builtins)]
            if reaches or unknown:
                derived = True
        out[name] = ("DERIVED" if derived else "CONSTANT", " ".join(parts))
    return out


def peak_child_mib() -> float:
    raw = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    return raw / (1024 * 1024) if sys.platform == "darwin" else raw / 1024


# ----------------------------------------------------------------- the population, discovered


def population() -> dict:
    """`{rel: (path, blind_row)}` -- declared oracles INTERSECTED with CONST-payload oracles.

    BOTH READS ARE DISCOVERIES AND BOTH ARE LOADED BY PATH: `gates/gates-pop.py:discover()` is
    this tree's own gate/oracle derivation, and `gates/oracleblind.rows` is the census's own
    committed verdict table. NEITHER IS COPIED. The `tn_*` name is NOT a membership test -- it is
    reported, so a reader can see which admitted rows are `tn_*` and check the count.
    """
    pop = _load(HERE / (BLIND_STEM + ".py"), "oracleblind_census")
    declared, _deriv = pop.population()
    blind = {}
    for line in BLIND.read_text().split("\n")[1:]:
        if not line.strip():
            continue
        cells = line.split("\t")
        blind[cells[0]] = {"verdict": cells[2], "rows": cells[4], "base_sha": cells[5],
                           "why": cells[-3], "declared_by": cells[-2]}
    out = {}
    for rel, meta in declared.items():
        p = ROOT / rel
        if not p.is_file():
            continue
        sites = const_payload_sites(p.read_text())
        if not sites:
            continue
        out[rel] = (p, sites, blind.get(rel))
    return out


# --------------------------------------------------------------- the classification, per oracle


def probe(rel, path: Path, sites, blind) -> dict:
    """Run the oracle's OWN rows at every rung of the ladder and report which rows move."""
    src = path.read_text()
    SCRATCH.mkdir(parents=True, exist_ok=True)
    out = {"oracle": rel, "sites": [s[2] for s in sites], "ladders": [], "rung_moved": {}}
    base = None
    for i, (lo, hi, v) in enumerate(sites):
        rungs = []
        for label, val in ladder(v):
            sp = SCRATCH / (path.stem + f".s{i}.{label}.py")
            sp.write_text(substitute(src, sites, i, val))
            try:
                got = invoke(sp)
            finally:
                sp.unlink()
            rec = {"site": v, "rung": label, "value": val, "rc": got["rc"]}
            if got["rc"] != 0:
                rec["crash"] = got["err"].strip().split("\n")[-1][:120]
            else:
                rm = rows_of(got["out"])
                rec["values"] = rm
                if base is None:
                    base = rm
                    rec["moved"] = []
                    rec["rows"] = len(rm)
                else:
                    names = set(base) | set(rm)
                    moved = sorted(n for n in names if base.get(n) != rm.get(n))
                    rec["moved"] = moved
                    rec["echoes"] = sorted(n for n in moved if str(val) in (rm.get(n) or ""))
                    rec["rows"] = len(rm)
            rungs.append(rec)
        out["ladders"].append(rungs)
    # THREE OUTCOMES FOR A ROW THAT MOVED, HELD APART, because a "value axis" and a row that
    # PRINTS ITS OWN INPUT look identical to a movement count and are opposites.
    ever = sorted({n for per_site in out["ladders"] for r in per_site
                   for n in r.get("moved", [])})
    echo = sorted({n for per_site in out["ladders"] for r in per_site
                   for n in r.get("echoes", [])})
    total = base if base is not None else {}
    out["rows"] = len(total)
    out["moved_rows"] = ever
    out["echo_rows"] = echo
    out["value_axis_rows"] = sorted(set(ever) - set(echo))
    shapes = row_shapes(src)
    out["constant_rows"] = sorted(n for n, (k, _e) in shapes.items() if k == "CONSTANT")
    out["blind"] = blind
    out["verdict"] = ("V-LADDER-SENSITIVE" if ever else
                      ("V-LADDER-STABLE" if total else "DEAD:no rows"))
    return out


# ------------------------------------------------------------------------------- the table


def table(rows: list) -> str:
    head = ("oracle\tladder\trows\tverdict\tvalue_axis_rows\techo_rows\tconstant_rows\t"
            "blind_verdict\tblind_rows\tblind_why\n")
    body = ""
    for r in rows:
        lad = ";".join(f"{l}={v}" for l, v in ladder(r["sites"][0])) if r["sites"] else "-"
        body += "\t".join([
            r["oracle"], lad, str(r["rows"]), r["verdict"],
            ";".join(r["value_axis_rows"]) or "NONE",
            ";".join(r["echo_rows"]) or "NONE",
            ";".join(r["constant_rows"]) or "NONE",
            (r["blind"] or {}).get("verdict", "-"), (r["blind"] or {}).get("rows", "-"),
            ((r["blind"] or {}).get("why", "-")[:100]),
        ]) + "\n"
    return head + body


def summarise(rows: list, elapsed: float, peak: float) -> str:
    from collections import Counter
    vc = Counter(r["verdict"] for r in rows)
    blind = Counter((r["blind"] or {}).get("verdict", "?") for r in rows)
    print(f"  oracles with a CONST payload: {len(rows)}")
    print(f"  value verdicts: {dict(vc)}")
    print(f"  their census verdicts: {dict(blind)}")
    tn = [r for r in rows if Path(r["oracle"]).name.startswith("tn_")]
    print(f"  of which tn_*: {len(tn)}  verdicts {dict(Counter(r['verdict'] for r in tn))}")
    moved_any = [r for r in rows if r["moved_rows"]]
    print(f"  oracles with ANY row moving under the value ladder: {len(moved_any)}"
          f"  {[Path(r['oracle']).name for r in moved_any]}")
    n_va = sum(len(r["value_axis_rows"]) for r in rows)
    n_ec = sum(len(r["echo_rows"]) for r in rows)
    print(f"  rows that moved: {n_va} DERIVABLE value-axis rows, {n_ec} rows that only ECHO the "
          f"payload (the forbidden shape, not an axis)")
    for r in rows:
        if r["echo_rows"]:
            print(f"    ECHOES {Path(r['oracle']).name}: {r['echo_rows']}")
    short = [Path(r["oracle"]).name for r in rows
             if r["sites"] and len({v for _, v in ladder(r["sites"][0])}) < 4]
    print(f"  ladders with fewer than four DISTINCT rungs: {short or 'none'}")
    dead = sum(len(r["constant_rows"]) for r in rows)
    print(f"  CONSTANT rows (value expression consults nothing) across the population: {dead}"
          f" of {sum(r['rows'] for r in rows)}, in "
          f"{sum(1 for r in rows if r['constant_rows'])} of {len(rows)} oracles")
    print(f"  wall {elapsed:.1f}s  peak child RSS {peak:.0f} MiB")


# ------------------------------------------------------------------------------------- PLANT


PLANT_SRC = '''from tinygrad.uop.ops import Ops, UOp
c = UOp(Ops.CONST, src=(), arg=4)
r = c.sqrt()
print(f"op_is_sqrt={int(r.op is Ops.SQRT)}")
print(f"value_is_v_plus_one={int(c.arg == 5)}")
'''

# The SAME graph with the value-reading row REMOVED, which is the shape 19 of the 23 admitted
# oracles have. An oracle can be `V-LADDER-SENSITIVE` on the strength of ONE row while every other
# row is stable, so "the oracle is sensitive" and "this row is sensitive" are different claims and
# the table carries the row names.
PLANT_STABLE_SRC = '''from tinygrad.uop.ops import Ops, UOp
c = UOp(Ops.CONST, src=(), arg=4)
r = c.sqrt()
print(f"op_is_sqrt={int(r.op is Ops.SQRT)}")
'''

# A value axis that DOES move, so `V-LADDER-SENSITIVE` is reachable and the classifier can be
# caught reporting `V-LADDER-STABLE` for an oracle that moved. THE CLASSIFIER IS THE SUBJECT, not
# `tinygrad`: MEASURED, `UOp` arithmetic never folds at construction (4*{0,1,2,-1,-2,4} all emit
# `MUL`; 4+{...} all `ADD`; 4**{0,1,2,3,-1,4} all `POW`), so a plant that waited for a fold in
# `tinygrad/` would be a plant that can never fail -- and `tinygrad/` is READ-ONLY besides.
PLANT_LOADED_SRC = '''from tinygrad.uop.ops import Ops, UOp
c = UOp(Ops.CONST, src=(), arg=4)
print(f"value_is_v_plus_one={int(c.arg == 5)}")
'''

# THE DETECTION HOLE, AS A PLANT, because it is the reason the verdict names are weak. A row keyed
# to a value OUTSIDE the ladder must NOT move, and the instrument must say `V-LADDER-STABLE` --
# which is TRUE and is NOT "this row is value-invariant". If this direction ever went red by
# moving, the ladder would have grown a rung nobody declared, and the table's `ladder` column
# would be a lie.
PLANT_HOLE_SRC = '''from tinygrad.uop.ops import Ops, UOp
c = UOp(Ops.CONST, src=(), arg=4)
print(f"value_is_one={int(c.arg == 1)}")
'''

# THE CONSTANT/ DERIVED PAIR. Both print `1`. One consults tinygrad and one does not, so a
# detector that reads the printed value cannot tell them apart -- `relu_has_three_srcs=1` in
# `gates/tn_relu-oracle.py` is the live instance of the half that would be called dead wrongly.
PLANT_CONST_SRC = '''from tinygrad.uop.ops import Ops, UOp
c = UOp(Ops.CONST, src=(), arg=4)
r = c.sqrt()
print(f"has_three_srcs={int(len(r.uop.src) == 3)}")
print(f"is_reachable={int(1)}")
'''

# THE ECHO, IN THE SHAPE `gates/tn_nodes-oracle.py` ACTUALLY HAS. `tn_nodes` prints
# `n0=Ops.CONST/0 srcs=- arg=f4 dt=weakfloat`, so its `n0` MOVES under the ladder and is a
# TAUTOLOGY: `arg=f4` IS the payload, spelled with a float suffix. A movement count cannot tell
# that from `tn_graph_census`'s `tn_relu`, which moves because `where`'s two `CONST 0` srcs
# COALESCE to one node at payload 0 -- a graph CPython built, not an echo. So the detector is:
# a moved row whose value CONTAINS the rung's decimal text is an ECHO, not a value axis, and the
# brief's prohibition ("NEVER PRINT AN ARGUMENT AS AN EXPECTED VALUE") becomes a measurement.
PLANT_ECHO_SRC = '''from tinygrad.uop.ops import Ops, UOp
c = UOp(Ops.CONST, src=(), arg=4)
r = c.sqrt()
print(f"op_is_sqrt={int(r.op is Ops.SQRT)}")
print(f"echoed=f{c.arg}f")
'''


def _probe_src(name: str, src: str):
    """`probe()` on a synthetic oracle, through the SAME path the population takes."""
    SCRATCH.mkdir(parents=True, exist_ok=True)
    p = SCRATCH / name
    p.write_text(src)
    try:
        return probe(f"gates/artifacts/tnvalue/{name}", p, const_payload_sites(src), None)
    finally:
        p.unlink()


def plant() -> int:
    """FIVE directions, and the census must be able to fail on every one.

    1. OFFSETS -- substitution hits the value `const_payload_sites` found. If the two disagree the
       instrument edits a byte it never measured.
    2. LADDER -- `v, v+1, 0, -v` are four DISTINCT valid rungs, so this is a value axis and not
       the EMPTY garbage axis the parent census already ran.
    3. STABLE -- a REAL `sqrt` oracle, whose OP row is value-invariant, is labelled
       `V-LADDER-STABLE`, and a row keyed to a rung IN the ladder is the only row that moves.
    4. SENSITIVE -- the SAME oracle shape with one value-reading row is labelled
       `V-LADDER-SENSITIVE`. An instrument whose only reachable verdict is `STABLE` cannot be
       wrong about it, and therefore cannot be right about it either.
    5. THE HOLE -- a value-reading row keyed to a value OUTSIDE the ladder does NOT move and the
       instrument still says `V-LADDER-STABLE`. This is the direction that keeps the verdict from
       being the overclaim it was on its first run.
    """
    checks = []
    sites = const_payload_sites(PLANT_SRC)
    sub = substitute(PLANT_SRC, sites, 0, 7)
    checks.append(("plant `offsets` -- substitution hits the value `const_payload_sites` found",
                   len(sites) == 1 and "arg=7" in sub and "arg=4" not in sub,
                   f"sites={sites} -> {[l for l in sub.splitlines() if 'arg=' in l]}"))
    lad = ladder(4)
    checks.append(("plant `ladder` -- v, v+1, 0, -v are four DISTINCT valid rungs, and 1 is NOT "
                   "one of them (the hole the verdicts are weak enough for)",
                   len({v for _, v in lad}) == 4 and 1 not in {v for _, v in lad},
                   f"{lad}"))

    inv = _probe_src("plant-invariant.py", PLANT_SRC)
    inv_moved = [n for per in inv["ladders"] for r in per for n in r.get("moved", [])]
    st = _probe_src("plant-stable.py", PLANT_STABLE_SRC)
    checks.append(("plant `stable` -- a REAL sqrt oracle is V-LADDER-STABLE, and in the oracle "
                   "that also reads a value ONLY the value row moves, so the tool separates "
                   "'this oracle moved' from 'THIS ROW moved'",
                   st["verdict"] == "V-LADDER-STABLE" and st["moved_rows"] == []
                   and inv["verdict"] == "V-LADDER-SENSITIVE"
                   and sorted(set(inv_moved)) == ["value_is_v_plus_one"],
                   f"stable={st['verdict']}/{st['moved_rows']} "
                   f"both={inv['verdict']} moved={sorted(set(inv_moved))}"))

    ld = _probe_src("plant-loaded.py", PLANT_LOADED_SRC)
    checks.append(("plant `sensitive` -- the same shape with a value-reading row is "
                   "V-LADDER-SENSITIVE, so the classifier is not a one-sided constant",
                   ld["verdict"] == "V-LADDER-SENSITIVE"
                   and ld["moved_rows"] == ["value_is_v_plus_one"],
                   f"verdict={ld['verdict']} moved={ld['moved_rows']}"))

    hole = _probe_src("plant-hole.py", PLANT_HOLE_SRC)
    checks.append(("plant `hole` -- a row keyed to a value OUTSIDE the ladder does not move and "
                   "is STILL reported stable, so the verdict claims four points and not the "
                   "integers",
                   hole["verdict"] == "V-LADDER-STABLE" and hole["moved_rows"] == [],
                   f"verdict={hole['verdict']} moved={hole['moved_rows']}"))

    # THE CONSTANT DETECTOR, AND THE HALF THAT KEEPS IT HONEST. `relu_has_three_srcs` PRINTS 1 and
    # is a REAL query; `x_is_reachable` PRINTS 1 and consults nothing. The runtime value cannot
    # tell them apart -- that is why the test is on the AST -- and a detector that called the
    # first one a constant would be a census that reports a working row as dead.
    sh = row_shapes(PLANT_CONST_SRC)
    checks.append(("plant `constant` -- a row whose value expression is `int(1)` is CONSTANT and a "
                   "row that prints 1 by consulting tinygrad is DERIVED",
                   sh["is_reachable"][0] == "CONSTANT" and sh["has_three_srcs"][0] == "DERIVED",
                   f"{sh}"))
    # The detector is shown firing on a REAL oracle, so the column is not structurally empty. It
    # is skipped when that file is absent rather than invented: a plant that reaches into the
    # population can measure it, and a plant that cannot reach its subject is a plant that cannot
    # fail. MEASURED, `gates/tn_sqrt-oracle.py` carries `sqrt_is_reachable={int(1)}`.
    real = oracle_path("tn_sqrt")
    if real.is_file():
        rs = row_shapes(real.read_text())
        checks.append(("plant `constant-fires` -- the detector finds the constant row in a REAL "
                       "tn_* oracle, so the column is not structurally empty",
                       rs.get("sqrt_is_reachable", ("?",))[0] == "CONSTANT"
                       and rs.get("sqrt_op_is_sqrt", ("?",))[0] == "DERIVED",
                       f"sqrt_is_reachable={rs.get('sqrt_is_reachable')} "
                       f"sqrt_op_is_sqrt={rs.get('sqrt_op_is_sqrt')}"))
    else:
        checks.append(("plant `constant-fires` -- SKIPPED, `gates/tn_sqrt-oracle.py` is absent",
                       True, "skipped: subject absent, and a plant must not invent its subject"))

    ec = _probe_src("plant-echo.py", PLANT_ECHO_SRC)
    checks.append(("plant `echo` -- a row that PRINTS THE PAYLOAD is separated from a value axis: "
                   "the echo is named, the op row is not, and neither becomes a value axis",
                   ec["echo_rows"] == ["echoed"] and ec["value_axis_rows"] == []
                   and ec["moved_rows"] == ["echoed"],
                   f"echo={ec['echo_rows']} value_axis={ec['value_axis_rows']} "
                   f"moved={ec['moved_rows']}"))
    checks.append(("plant `ladder-degenerate` -- a payload site of 0 still gets FOUR distinct rungs, "
                   "because `v, v+1, 0, -v` is `0, 1, 0, 0` and MEASURED on the population two "
                   "oracles were carrying that ladder",
                   len({v for _, v in ladder(0)}) == 4 and len({v for _, v in ladder(-1)}) == 4,
                   f"ladder(0)={ladder(0)} ladder(-1)={ladder(-1)}"))

    # THE CLASS THAT NEEDED A PLANT, AND IT IS ABOUT **THIS FILE**. The parent census admits every
    # `.py` string constant carrying `oracle`, so this file naming one CHANGES THE PARENT'S
    # POPULATION -- measured, 98 -> 99, with a row keyed `-oracle.py`. A census that perturbs its
    # own denominator cannot be read, and no assertion about the oracles would have caught it:
    # `plant stable` and `plant echo` were both PASS while the file was doing it.
    decl = declaration_literals(Path(__file__).read_text())
    checks.append(("plant `no-declaration` -- NO `.py` string constant in THIS FILE carries "
                   "`oracle`, because each one is a declaration the parent census would admit and "
                   "this instrument must not perturb the denominator it reads its verdicts from "
                   "(MEASURED: the 6-char literal `-oracle.py` took the parent 98 -> 99)",
                   not decl, f"offending literals: {decl or 'none'}"))

    bad = [n for n, ok, _ in checks if not ok]
    for n, ok, seen in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {n}\n          observed: {seen}")
    print(f"--plant: {'all five directions hold' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


def constant_census(declared: dict) -> None:
    """THE CONSTANT COLUMN OVER THE **WHOLE** ADMITTED POPULATION, WITH ITS OWN DENOMINATOR.

    THE LADDER POPULATION IS A SUBSET AND SAYING OTHERWISE IS THE `ptx.bend` ALIAS DEFECT AGAIN.
    `probe()` only admits an oracle that HOLDS a CONST payload literal, and MEASURED that excludes
    **2 of the 23** `ALL VALID INPUTS AGREE` `tn_*` oracles -- `tn_isnan-oracle.py` and
    `tn_nary_arena-oracle.py` hold no integer payload. Both are among the oracles the question is
    ABOUT, and `tn_isnan-oracle.py` carries `isnan_is_reachable={int(1)}`. So the constant census
    runs here, over `population()`'s admission with NO payload filter and no subprocess, and
    prints BOTH denominators so a reader cannot mistake one for the other.

    The Bend half is counted too, because a constant on ONE side is a defect and a constant on
    BOTH is a row the gate cannot fail. `gates/gatekit.py:660` compares the lanes byte for byte,
    so two agreeing constants are indistinguishable from agreement. The `.bend` files are READ,
    never written or executed -- this unit does not run `bend`, and `True{}` on its own line is
    the whole test.
    """
    blind = {}
    for line in BLIND.read_text().split("\n")[1:]:
        if line.strip():
            cells = line.split("\t")
            blind[cells[0]] = cells[2]
    total_rows = const_rows = files = 0
    tn_rows = tn_files = tn_rows_c = tn_files_c = 0
    per = []
    for rel, meta in sorted(declared.items()):
        p = ROOT / rel
        if not p.is_file():
            continue
        files += 1
        shapes = row_shapes(p.read_text())
        cst = sorted(n for n, (k, _e) in shapes.items() if k == "CONSTANT")
        total_rows += len(shapes)
        const_rows += len(cst)
        if cst:
            per.append((rel, len(cst)))
        nt = bend_trues(bend_for(p))
        if Path(rel).name.startswith("tn_"):
            tn_files += 1
            tn_rows += len(shapes)
            tn_rows_c += len(cst)
            tn_files_c += 1 if cst else 0
    agree = [r for r in declared if blind.get(r) == "ALL VALID INPUTS AGREE"]
    tn_agree = [r for r in agree if Path(r).name.startswith("tn_")]
    tn_agree_c = sum(len([n for n, (k, _e) in row_shapes((ROOT / r).read_text()).items()
                          if k == "CONSTANT"]) for r in tn_agree)
    print(f"  CONSTANT CENSUS, whole admitted population (no payload filter, no subprocess):")
    print(f"    oracles read {files}, rows read {total_rows}, CONSTANT rows {const_rows} "
          f"in {len(per)} oracles")
    print(f"    of the 28 ALL VALID INPUTS AGREE: {len(agree)}, of which tn_* {len(tn_agree)}; "
          f"CONSTANT rows inside the tn_* {len(tn_agree)} = {tn_agree_c}")
    tn_agree_files_c = sum(1 for r in tn_agree
                           if any(k == "CONSTANT" for k, _e in row_shapes((ROOT / r).read_text()).values()))
    print(f"    those tn_* CONSTANT rows sit in {tn_agree_files_c} of the {len(tn_agree)} oracles")
    print(f"    tn_* overall (every census verdict): {tn_files} oracles, {tn_rows} rows, "
          f"{tn_rows_c} CONSTANT in {tn_files_c} oracles")
    for rel, n in per:
        if Path(rel).name.startswith("tn_"):
            print(f"      {Path(rel).name:40} py_constant={n}  "
                  f"bend_True{{}}={bend_trues(bend_for(ROOT / rel))}")


def declaration_literals(src: str) -> list:
    """Every `.py` string constant carrying `oracle`, DOCSTRINGS EXCLUDED.

    This is the parent's admission rule, reimplemented for THIS file so the plant can hold this
    file to it. The docstring exclusion is not a convenience: this file's own header has to NAME
    the literals it is forbidden to contain, in order to say why, and
    `gates/oracleblind-census.py`'s `_docs()` is what keeps those mentions from becoming
    declarations. Reimplemented rather than imported because the parent's `_docs` is private and
    this must keep working when the parent is not on the path -- and a plant whose subject it
    cannot reach is a plant that cannot fail.
    """
    tree = ast.parse(src)
    docs = set()
    for n in ast.walk(tree):
        b = getattr(n, "body", None)
        if isinstance(b, list) and b and isinstance(b[0], ast.Expr) \
                and isinstance(b[0].value, ast.Constant) \
                and isinstance(b[0].value.value, str):
            for x in ast.walk(b[0].value):
                docs.add(id(x))
    return sorted({n.value for n in ast.walk(tree) if isinstance(n, ast.Constant)
                   and isinstance(n.value, str) and id(n) not in docs
                   and n.value.endswith(".py") and "oracle" in n.value.lower()})


def bend_for(p: Path) -> Path:
    """`gates/tn_sqrt-oracle.py` -> `gates/tn_sqrt.bend`. FROM `Path.stem`, NEVER FROM A LITERAL.

    **THIS FUNCTION IS THE REPAIR FOR A DEFECT THIS FILE SHIPPED, AND THE DEFECT WAS FOUND BY THE
    PARENT.** `gates/oracleblind-census.py` admits "every tracked `.py` constant a gate mentions"
    whose value ends in `.py` and carries `oracle` -- `gates/oracleblind-census.py:276` calls the
    version that "answered **55 absent on disk**" a defect. The first version of this file spelled
    the suffix as the literal `"-oracle.py"`, so the parent read **a 6-character string constant as
    a declaration of an oracle**, and MEASURED the parent population going **98 -> 99** with a new
    `CANNOT BE PERTURBED` row whose key is literally `-oracle.py`, `declared_by:
    gates/tnvalue-census.py:literal [unresolved]`. **This file perturbed the very denominator it
    reads its verdicts from, and it did it by NAMING A THING THAT DOES NOT EXIST.**
    `Path.stem` + `removesuffix` builds the name with no `.py`-literal anywhere in the file.
    """
    return p.with_name(p.stem.removesuffix("-oracle") + ".bend")


def oracle_path(stem: str) -> Path:
    """`gates/tn_sqrt-oracle.py` FROM A STEM. **NEVER** from a literal, and that is the repair.

    The parent census admits "every tracked `.py` constant a gate mentions" whose value ends in
    `.py` and carries `oracle`; `gates/oracleblind-census.py:276` records the version that
    "answered **55 absent on disk**" as a defect. So a literal here is not a style preference, it
    is a way of CHANGING THE PARENT'S POPULATION, and this file changed it twice before being
    caught: `"-oracle.py"` produced a 99th row whose KEY IS `-oracle.py`, and
    `"tn_sqrt-oracle.py"` reclassified the real `gates/tn_sqrt-oracle.py` from WALK-ONLY to
    GATE-DECLARED, which is a different CLAIM about the same file.

    `with_suffix` builds the name from parts, so no `.py`-suffixed literal appears in this file at
    all, and `plant no-declaration` ASSERTS it. The cost is one helper and a slightly indirect
    spelling; the benefit is that this instrument CANNOT perturb the denominator it reads.
    """
    return (HERE / (stem + "-oracle")).with_suffix(".py")


def bend_trues(b: Path) -> int:
    """How many bare `True{}` row bodies the `.bend` carries. READ ONLY -- this unit runs no `bend`.

    `True{}` on a line by itself is the whole test: it is what `gates/tn_sqrt.bend`'s
    `row_sqrt_reachable()` returns, and it is the Bend half of a two-lane dead row.
    """
    return sum(1 for l in b.read_text().split("\n") if l.strip() == "True{}") \
        if b.is_file() else 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--plant", action="store_true", help="self-test on synthetic oracles")
    ap.add_argument("--rss", action="store_true", help="peak RSS + wall clock only")
    a = ap.parse_args(argv)
    if a.plant:
        return plant()
    t0 = time.time()
    declared, _deriv = _load(HERE / (BLIND_STEM + ".py"), "oracleblind_census").population()
    pop = population()
    rows = [probe(rel, p, sites, blind) for rel, (p, sites, blind) in sorted(pop.items())]
    elapsed = time.time() - t0
    peak = peak_child_mib()
    summarise(rows, elapsed, peak)
    constant_census(declared)
    if not a.rss:
        text = table(rows)
        ROWS.write_text(text)
        print(f"  sha256 {hashlib.sha256(text.encode()).hexdigest()[:16]}  "
              f"({len(rows)} rows -> {ROWS.relative_to(ROOT)}, {len(text)} bytes)")
    crashed = [r["oracle"] for r in rows if not r["rows"]]
    return 1 if crashed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))