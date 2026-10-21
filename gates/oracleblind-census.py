#!/usr/bin/env python3
"""oracleblind-census -- WHICH ORACLES CANNOT TELL A REAL INPUT FROM GARBAGE?

    .venv/bin/python gates/oracleblind-census.py              # the census
    .venv/bin/python gates/oracleblind-census.py --report     # census only, rc never charged
    .venv/bin/python gates/oracleblind-census.py --plant      # self-test on synthetic oracles
    .venv/bin/python gates/oracleblind-census.py --rss        # peak RSS + wall clock only

An oracle that answers the same for a REAL input and for GARBAGE is not an oracle; it is a
constant answering. `gates/autogen-oracle.py` is the measured instance -- all 51 rows
byte-identical for a real header and for `GARBAGE NOT C AT ALL`. It was NOT repaired, and that
was right: repairing it would mean INVENTING what it should catch. So this file MEASURES the
class and reports a FLOOR per oracle. "0 of 51 rows move under 3 perturbations" is a result;
"insensitive" is a label.

THE POPULATION IS DISCOVERED, TWICE, AND BOTH READS ARE COUNTED. (a) `gates/gates-pop.py`'s own
`discover()`, LOADED BY PATH -- the derivation the tree already owns (`gates/gate-surface.py:76`
says so) -- names the gate homes and entry points, and a gate's `Gate(oracle=...)` argument is
its OWN declaration of the CPython side. (b) A directory walk of each home for a file whose stem
carries `oracle`, which is a SHAPE and is therefore reported as a second CLASS rather than merged
in: an oracle no gate names is a denominator, not a verdict.

WHAT IS PERTURBED. An oracle's input is its own module-level LITERAL surface -- the fixture data
it binds to names, and the literals it passes at module scope. Sites are collected by AST and
EXCLUDED from three places, each exclusion a soundness requirement:

  1. any literal under `print(...)` / `stdout.write(...)` / `row(...)` -- perturbing it would
     rewrite the ANSWER, which is the one thing a perturbation must never do;
  2. any literal inside an f-string (`ast.JoinedStr`) -- the format text is output;
  3. the 0th positional argument of any call -- this tree's `(row_name, value)` convention puts
     the row name first, and a row name is not an input.

A literal the rules cannot reach is NOT perturbed, and it is COUNTED and printed. An oracle with
no reachable site is `IGNORES ITS INPUT` rather than a silent zero.

THE THIRD EXCLUSION, FOUND BY THE PLANT: A DOCSTRING IS PROSE, NOT A FIXTURE. `plant-nofix` came
back with **1** site and the plant went red -- the site was the module docstring, a string
`Expr` statement, and EMPTYING it changes a comment. `gates/oracle-census-gate.py` calls the
opposite rule for names ("a docstring is not a use", `_docstring_nodes`), and the two have to
agree or the same construct is a use in one instrument and a non-use in the other.

FOUR CLASSES, FOUR DIFFERENT QUESTIONS.

  CONTROL           the same source twice, in SEPARATE processes. Row count and token sequence
                    must be identical. Without this arm "0 rows moved" is unfalsifiable: a flaky
                    oracle and a constant oracle print the same thing.
  EMPTY             every reachable site emptied -- `[]`/`()`/`{}`/`set()`, `""`, `0`, `0.0`. The
                    GARBAGE class. An oracle that legitimately rejects it still MOVES, because
                    the row count is part of the answer.
  VALID-DIFFERENT   containers ROTATED by one: the same multiset in a different order, valid by
                    construction, so no value is invented. Integers `n -> n+1`, floats
                    `f -> f+1.0`. STRINGS ARE LEFT ALONE and counted -- the "other valid value"
                    of a dtype name is not knowable mechanically and inventing one is forbidden.
  BOUNDARY          containers reduced to their LAST element (the extreme case in the
                    magnitude-ordered fixtures this tree uses); numbers sign-flipped `n -> -n`.

THREE MOVEMENT MEASURES, because "moved" is three claims. `count` (row count changed),
`multiset` (the SET of `name=value` tokens changed -- a content change) and `order` (only the
sequence changed, which a rotation manufactures BY CONSTRUCTION and which is therefore reported
separately and never counted toward a floor).

THE FOUR VERDICTS. Two failures that are constantly conflated are held apart: an oracle that
IGNORES ITS INPUT never reads the fixture, and an oracle that READS it and answers the same
anyway is a constant property or a divergence. Conflating them reports blindness as divergence.

  SENSITIVE (floor)          some class moved `count` or `multiset`.
  IGNORES ITS INPUT          zero reachable sites in the oracle AND in any fixture module it
                             imports -- there is nothing to perturb and that is a measurement.
  ALL VALID INPUTS AGREE     sites exist, VALID-DIFFERENT moved neither count nor multiset.
  CANNOT BE PERTURBED (why)  it could not be run (rc / timeout / import failure), or every literal
                             it holds is on the excluded output side.

DETERMINISM IS ITS OWN COLUMN. An oracle that answers the same thing twice is a different defect
from one that answers differently, and the census reports both.

SCRATCH SPACE. Perturbed sources go under `gates/artifacts/sensitiv/`, which `.gitignore`d
already, and are unlinked per run. `__file__` is TEXTUALLY SUBSTITUTED for the original's
absolute path in every copy, so the seven oracles carrying a `__file__` derivation resolve
exactly as they do in the original -- `gates/i64-shl-oracle.py:62`'s
`Path(__file__).resolve().parent.parent / "checks" / "coindep.py"` and
`gates/wgsl_render_census-oracle.py:178`'s `__file__.rsplit("/gates/", 1)[0]` would both resolve
into `gates/artifacts/` from a relocated copy. The substitution is `(?<![\\w.])__file__`, so
`clang.__file__` is untouched, and the count of substitutions is reported per oracle.

THE PLANT builds FIVE synthetic oracles -- fixture-driven, constant-with-a-dead-fixture,
no-fixture-of-its-own, partly-crashing, and all-crashing -- and runs the whole machinery on each.
The last two exist because of a measured failure: a class whose run CRASHES must contribute
neither movement nor agreement, and 19 of 98 oracles were being reported as agreeing on the
strength of zero completed comparisons. A census that cannot go red on a constant-answering
oracle, and cannot distinguish "agreed" from "never ran", is the class of defect it exists to
measure.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import os
import importlib.util


import re
import resource
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
# `ast.parse` on OTHER instruments emits THEIR SyntaxWarnings onto OUR stderr, and `checks/no-txt.py:215`
# states the rule that makes that a defect: stdout is what callers parse (`oracle-census-gate.py`
# carries the same five lines and the same reason).
warnings.filterwarnings("ignore", category=SyntaxWarning)
ROOT = HERE.parent
PY = ROOT / ".venv" / "bin" / "python"
ART = HERE / "artifacts" / "sensitiv"
REPORT = HERE / "oracleblind.rows"

BUDGET = 240                       # seconds per invocation; a hang is a measurement, not a wait
KINDS = ("EMPTY", "VALID-DIFFERENT", "BOUNDARY")
OUT_RE = re.compile(r"(?<![\w.])__file__")
CONTAINERS = (ast.List, ast.Tuple, ast.Set, ast.Dict)
# THE KINDS A ROTATION MAY REORDER. A rotation is a "valid but different input" only when the
# container's elements are INTERCHANGEABLE. MEASURED, and this is the deepest false positive this
# file produced: `checks/render-gate-oracle.py:164` is `("cast", g_cast), ("add", g_add), ...` inside
# `for nm, f in (...)`, so VALID-DIFFERENT's rotation turned `("cast", g_cast)` into
# `(g_cast, "cast")` -- `nm` became a FUNCTION OBJECT and `f` a string. The oracle then took its
# exception path and printed **62 row NAMES containing a heap address** (`pyrender <function g_cast
# at 0x10ae2c680>`), which is why the table's sha MOVED under `PYTHONHASHSEED=3` while every other
# row held. That is not a different input; it is a re-binding, and it broke the only byte-identity
# this census claims. A container holding a literal AND a name/attribute/call is a BINDING, not a
# fixture, and rotation is refused for it.
ROTATABLE = (ast.Constant, ast.Tuple, ast.List, ast.Set, ast.Dict)
ENV_READERS = ()          # the gate files, set by `population()`; `gate_env_values` walks them
# CALLS WHOSE ARGUMENTS ARE OUTPUT. `print` is Python's; `row`/`rowf` are this tree's own row
# emitters. A literal under one is excluded because perturbing it rewrites the answer.
OUT_CALLS = frozenset({"print", "row", "rowf", "stdout.write", "stderr.write",
                       "sys.stdout.write", "sys.stderr.write"})


class PopulationUnavailable(RuntimeError):
    """The population could not be derived, so NO census was measured.

    NAMED, because the failure this replaces was a bare `ValueError: too many values to unpack
    (expected 3)` -- a traceback that names an ARITY and not a CONSEQUENCE, and the consequence is
    that `gates/oracleblind.rows` (and the `gates/tnvalue.rows` computed from it) keep the bytes
    of an EARLIER run with nothing in either file to say so. This exception is NOT caught here:
    it propagates, the traceback survives, and the process exits non-zero. A census that dies is
    DEAD (exit 5) and not a PASS, and the file it would have written is not written.
    """


# =============================================================== 1. THE POPULATION, DISCOVERED


def _gates_pop(path: Path = None):
    """`gates/gates-pop.py` LOADED BY PATH -- the derivation this tree already owns.

    `gates/gate-surface.py:76` says it: "the population is not a second list, it is
    `gates/gates-pop.py:discover()`, loaded by path". A second derivation with a different
    predicate is a different question pretending to be the same one.

    `path` exists for the PLANT, which plants a COPY whose `_buckets` returns three values and
    asserts that the producer exits NON-ZERO rather than writing a table from a broken population.
    """
    spec = importlib.util.spec_from_file_location("gates_pop", path or (HERE / "gates-pop.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _docs(tree):
    out = set()
    for n in ast.walk(tree):
        b = getattr(n, "body", None)
        if isinstance(b, list) and b and isinstance(b[0], ast.Expr) \
                and isinstance(b[0].value, ast.Constant) and isinstance(b[0].value.value, str):
            out.add(id(b[0].value))
    return out


def _resolve_gate_oracle(v, consts, assigns):
    """`Gate(oracle=...)`'s value, as a path. Resolves literals, module-level names, the
    `str(X)` wrapper and the `HERE / "name.py"` BinOp, and reports what it could NOT resolve
    instead of guessing.

    MEASURED, the three shapes that need it: `gates/linearizer_census-gate.py` and
    `gates/regalloc_census-gate.py` write `oracle=str(ORACLE)` with `ORACLE = HERE / "..."`, a
    BinOp no `literal_eval` can fold; `gates/onnx_census-gate.py` writes `oracle=ORACLE` with a
    bare string. The first version of this file reported all three as `@@UNRESOLVED@@` -- an
    unresolved declaration is a hole with a size, and reporting a hole while three live gates sit
    in it is exactly the `checks/census.py` shape `.agents/TODO.md` records (`pattern` held as an
    escaped regex, so `"pyproject\\.toml" in src` was a test no file could pass).
    """
    seen = 0
    while isinstance(v, (ast.Call, ast.Name, ast.BinOp)) and seen < 8:
        seen += 1
        if isinstance(v, ast.Call):
            if not v.args:
                return None
            v = v.args[0]
        elif isinstance(v, ast.Name):
            if v.id in consts:
                return consts[v.id].value              # `consts` maps string -> NODE
            v = assigns.get(v.id)
            if v is None:
                return None
        else:
            lits = [n.value for n in ast.walk(v)
                    if isinstance(n, ast.Constant) and isinstance(n.value, str)]
            return lits[-1] if len(lits) == 1 else None
    return v.value if isinstance(v, ast.Constant) and isinstance(v.value, str) else None


def _locate(lit, gate_file: Path):
    """`Gate(oracle=...)`'s two-base resolution, `gates/gatekit.py`'s `_resolve`, reimplemented.

    `gatekit.Gate._resolve` tries `HERE` then `ROOT` and returns `HERE / p` as the fallback. A
    census that resolved against the repo root alone reported **54 of 67 gate-declared oracles
    absent on disk**, because `gates/tn_sqrt-gate.py` writes `oracle="tn_sqrt-oracle.py"` -- a
    BARE name meaning a file beside the gate. The gate is the declaration, so the gate's own
    resolution rule is the one that reads it, and which base matched is returned with it.
    """
    q = Path(lit)
    if q.is_absolute():
        return (q, "absolute") if q.is_file() else (None, "absolute, absent")
    for base, tag in ((gate_file.parent, "beside-the-gate"), (ROOT, "repo-root")):
        if (base / q).exists():
            return (base / q, tag)
    return (None, "unresolved")


def population():
    """`(rows, derivation)` -- every oracle under a gate home, with the class that admitted it.

    TWO READS, KEPT APART. `gates/gates-pop.py` is imported BY PATH rather than reimplemented:
    `gates/gate-surface.py:76` -- "the population is not a second list, it is
    `gates/gates-pop.py:discover()`, loaded by path" -- and a second derivation with a different
    predicate is a different question pretending to be the same one.

    ONLY `.py` READERS ARE PARSED. The first version AST-parsed every reader and reported **8
    `SyntaxError` on `checks/*.sh`**, which is this file reporting its own blindness as the tree's
    unreadable gates: `gates/gates-pop.py:entry_reason` already classifies a shell gate by shebang,
    and a census that re-parses shell as Python has measured nothing. Shell readers are COUNTED in
    `readers_not_python` instead.

    THE ARITY IS NOT THIS FILE'S TO HOLD. MEASURED 2026-10-21: this file called the PRIVATE
    `gates_pop._buckets` and unpacked THREE values, and `gates/gates-pop.py` grew a FOURTH
    (`uncarried` -- the immediate files of the gate homes that the COMMIT TREE does not carry).
    Both this file and `gates/tnvalue-census.py` died with `ValueError: too many values to unpack
    (expected 3)`, and the `.rows` files they write kept the bytes of an EARLIER run with nothing
    to say so. So the public accessors are used -- `discover()` for the two buckets this file
    needs and `uncarried()` for the fourth -- and `gates-pop.py`'s own docstring says why they
    exist ("the third bucket leaves through `opaque()` instead of through this signature...
    AND THE FOURTH BUCKET LEAVES THE SAME WAY, FOR THE SAME REASON"). A caller that unpacks a
    private tuple has taken on a contract nobody published.
    """
    try:
        gates_pop = _gates_pop()
        homes = tuple(gates_pop._homes(ROOT))
        entries, libs = gates_pop.discover(ROOT)
        uncarried = gates_pop.uncarried(ROOT)
    except Exception as e:
        raise PopulationUnavailable(
            f"the gate population could not be derived: {type(e).__name__}: {e}. "
            f"{REPORT.relative_to(ROOT)} was NOT rewritten and still holds the bytes of an "
            f"earlier run.") from e
    readers = tuple(sorted(entries)) + tuple(sorted(libs))
    py_readers = [g for g in readers if g.suffix == ".py"]
    global ENV_READERS
    ENV_READERS = tuple(py_readers)

    named, unread, unresolved, absent_lits = {}, [], [], []
    for g in py_readers:
        try:
            tree = ast.parse(g.read_text(errors="replace"))
        except (OSError, SyntaxError) as e:
            unread.append(f"{g.relative_to(ROOT).as_posix()}: {type(e).__name__}")
            continue
        docs = _docs(tree)
        consts = {n.value: n for n in ast.walk(tree)
                  if isinstance(n, ast.Constant) and id(n) not in docs
                  and isinstance(n.value, str)}
        assigns = {t.id: n.value for n in tree.body if isinstance(n, ast.Assign)
                   for t in n.targets if isinstance(t, ast.Name)}
        # A `Gate(...)` INSIDE A PLANT IS NOT A DECLARATION. MEASURED: `gates/gatekit.py`'s
        # `device_plant` / `output_dir_plant` each build `Gate("plant-absent", oracle="unused.py")`,
        # so the first run admitted `unused.py` THREE TIMES and reported it absent on disk. A
        # synthetic fixture is a test of the plumbing; reading it as the population is the
        # `.agents/TODO.md` class -- the instrument naming a thing that exists only to be named.
        in_plant = {id(n) for f in ast.walk(tree)
                    if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))
                    and "plant" in f.name.lower() for n in ast.walk(f)}
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or id(node) in in_plant:
                continue
            fn = node.func
            if (fn.id if isinstance(fn, ast.Name) else getattr(fn, "attr", "")) != "Gate":
                continue
            for kw in node.keywords:
                if kw.arg != "oracle":
                    continue
                got = _resolve_gate_oracle(kw.value, consts, assigns)
                if got:
                    path, how = _locate(got, g)
                    rel = path.relative_to(ROOT).as_posix() if path else got
                    named.setdefault(rel, []).append(
                        f"{g.relative_to(ROOT).as_posix()}:Gate(oracle=) [{how}]")
                    if path is None:
                        absent_lits.append(f"{g.relative_to(ROOT).as_posix()}: {got}")
                else:
                    unresolved.append(f"{g.relative_to(ROOT).as_posix()}:{ast.unparse(kw.value)[:30]}")
        # GATES THAT DO NOT USE `gatekit` STILL NAME AN ORACLE BY LITERAL. `gates/tn_minimum-gate.py`
        # is the measured instance: no `Gate(...)` call, and its own header says the py lane "comes
        # from the interpreter via `tn_minimum-oracle.py`". THE NAME MUST CARRY `oracle`: the first
        # version admitted every tracked `.py` constant a gate mentions and answered **55 absent on
        # disk** -- `gatekit.py`, `coindep.py`, `checks/*.py` -- which is a gate naming its
        # collaborators, not naming oracles. Those are COUNTED in `dropped_literals`, not rows.
        for val in consts:
            if not val.endswith(".py") or "oracle" not in val.rsplit("/", 1)[-1].lower():
                continue
            path, how = _locate(val, g)
            rel = path.relative_to(ROOT).as_posix() if path else val
            named.setdefault(rel, []).append(f"{g.relative_to(ROOT).as_posix()}:literal [{how}]")

    # THE FOURTH BUCKET, USED AND NOT DROPPED. `gates-pop.py`'s own rule is "a gate is a file the
    # COMMIT TREE carries", and this census's SECOND read -- the directory walk -- is the one that
    # would otherwise admit a file the tree does NOT carry: another unit's in-flight scratch.
    # MEASURED 2026-10-21 on the live tree: **1 of the 90 walked oracles is
    # `checks/.tmp-tc_ptx_render-oracle.py`**, which `git ls-tree -r HEAD` does not name -- and a
    # census that admits it RUNS another unit's unvetted file as a subprocess and writes a row for
    # it into a committed table. So the walk is held to the SAME rule as the read that discovered
    # it, and the files it excludes are NAMED rather than dropped: a rule that excludes files
    # without naming them is the `artefacts_ok()` shape wearing a population.
    not_carried = {p.relative_to(ROOT).as_posix() for p, _reason in uncarried}
    walked, excluded = {}, []
    for home in homes:
        base = ROOT / home
        if base.is_dir():
            for p in sorted(base.iterdir()):
                if p.suffix != ".py" or "oracle" not in p.stem.lower():
                    continue
                rel = p.relative_to(ROOT).as_posix()
                if rel in not_carried:
                    excluded.append(rel)
                    continue
                if p.is_file():
                    walked[rel] = p

    rows = {}
    for rel in sorted(set(named) | set(walked)):
        p = ROOT / rel
        rows[rel] = {
            "class": "GATE-DECLARED" if rel in named else "WALK-ONLY",
            "declared_by": sorted(set(named.get(rel, []))),
            "exists": p.is_file(),
            "bytes": p.stat().st_size if p.is_file() else 0,
            "sha12": hashlib.sha256(p.read_bytes()).hexdigest()[:12] if p.is_file() else "",
        }
    return rows, {"homes": homes, "readers_read": len(py_readers),
                  "readers_not_python": len(readers) - len(py_readers),
                  "unreadable_readers": unread,
                  "walk_only": sum(1 for r in rows.values() if r["class"] == "WALK-ONLY"),
                  "not_carried": sorted(excluded),
                  "absent": sorted(r for r, v in rows.items() if not v["exists"]),
                  "unresolved_decl": sorted(unresolved),
                  "declared_but_unlocatable": sorted(absent_lits)}


# ================================================== 2. THE FIXTURE SURFACE OF ONE ORACLE (AST)


def _parents(tree):
    return {id(c): n for n in ast.walk(tree) for c in ast.iter_child_nodes(n)}


def _under_output(n, parents):
    """True when `n` is on the OUTPUT side: under an output call, or the 0th positional argument.

    THE 0th-POSITIONAL-ARGUMENT RULE IS A CONVENTION, AND IT IS STATED AS ONE.
    `gates/wk-cd-oracle.py:76` prints `f"{nm}={out...}"` and the tree's row helpers are
    `row(name, value)`, so the first argument of a call is a row NAME. Perturbing it would change
    a row's identity rather than the oracle's answer to a different input, and an instrument that
    counts that as sensitivity is measuring its own transformation. It does mean a fixture
    genuinely passed first to a builder call is left alone -- so the rule is reported per oracle
    as `unreachable` and never silently applied.
    """
    cur, hops = parents.get(id(n)), 0
    while cur is not None and hops < 400:
        if isinstance(cur, ast.JoinedStr) and isinstance(n, ast.Constant) \
                and n in cur.values:
            return True
        if isinstance(cur, ast.Call):
            fn = cur.func
            nm = fn.id if isinstance(fn, ast.Name) else getattr(fn, "attr", "")
            if nm in OUT_CALLS:
                return True
            if any(a is n and i == 0 for i, a in enumerate(cur.args)):
                return True
        cur, hops = parents.get(id(cur)), hops + 1
    return False


def _own_literal(n):
    """True when `n` is a literal THIS ORACLE could be reading rather than printing.

    BOOls ARE INCLUDED, and that is a fix against a measured blindness. `bool` was excluded as a
    flag, and `gates/tn_nary_arena-oracle.py:25-31` is
    `return Tensor(UOp(Ops.CONST, src=(), arg=True), device="PYTHON")` -- the flag IS the tensor
    value, and the file was reported `0 reachable sites`. Excluding a type from a surface because
    of how it is USED is a guess about the author's intent, which is the same move as excluding by
    filename; the replacement rule (`b -> not b`) is valid for a flag and for a value alike.
    """
    return isinstance(n, CONTAINERS) or (
        isinstance(n, ast.Constant) and isinstance(n.value, (int, float, str, bool)))


def surface(src):
    """`{label: [site nodes]}` plus the literals the exclusion rules could not reach.

    THE WHOLE MODULE IS SCANNED, NOT ONLY ITS TOP LEVEL, and that is a fix against a measured
    wrong reason. `gates/md_graph_census-oracle.py`, `mx_graph_census-oracle.py` and four siblings
    put their whole fixture in a module-level `print(f"...")` and were reported
    `IGNORES ITS INPUT / 0 reachable sites` -- which is THIS INSTRUMENT'S blindness wearing the
    oracle's name, and the brief's "a wrong reason is worse than no reason" applies to the
    instrument as much as to the tree.

    AN F-STRING IS SPLIT, NOT EXCLUDED. Excluding `ast.JoinedStr` outright protects the format
    TEXT and blinds the interpolated EXPRESSION, and in `mx_graph_census-oracle.py` the expression
    IS the fixture: `f"reshape_1_2_8_16={sig(base().reshape(1, 2, 8, 16))}"` -- the literals
    `(1, 2, 8, 16)` decide the answer and the row name merely spells them. So the rule is: a
    `Constant` that is a DIRECT child of a `JoinedStr` is output and is never perturbed; a
    literal inside a `FormattedValue` is input and is.
    """
    tree = ast.parse(src)
    parents = _parents(tree)
    docs = _docs(tree)
    sites, unreach = {}, []

    def in_fmt_text(n):
        return isinstance(parents.get(id(n)), ast.JoinedStr)

    def scan(node, label):
        """The OUTERMOST literal descendants of `node`, in source order, once each.

        The node ITSELF is a site when it is a literal, and the walk STOPS there. MEASURED, and it
        was this file's own defect: the first version seeded the worklist with
        `iter_child_nodes(node)` and so never tested `node`, which turned every container fixture
        into a bag of leaves. `VALUES = [7, 7]` came back as two `7` sites, and every class then
        rewrote them in place -- EMPTY produced `[0, 0]` instead of `[]`, VALID-DIFFERENT produced
        `[8, 8]` instead of the rotation `[7, 7]`, and BOUNDARY produced `[-7, -7]` instead of the
        last element `[7]`. **A container class applied to a container's elements is not the class;
        it is arithmetic on the fixture, and it made `plant-crash` report `SENSITIVE` where the
        two defined classes must agree.**
        """
        if _own_literal(node) and id(node) not in docs and not in_fmt_text(node) \
                and not _under_output(node, parents):
            # A `bool` IN CALL-SIGNATURE POSITION IS A FLAG, NOT A VALUE, AND IS EXCLUDED.
            # MEASURED TWICE, and both measurements were false positives this file reported as
            # sensitivity. `gates/tn_mul-oracle.py:51` is `r_rmul = d.mul(c, reverse=True)`;
            # VALID-DIFFERENT made it `reverse=False`, which does not change the FIXTURE, it changes
            # WHICH METHOD IS UNDER TEST -- and the census duly reported `floor=1 of 13` with
            # `rmul_srcs_are_x_and_self` the moved row. And with `bool` admitted at all,
            # `gates/oracle-census-gate.py`'s `subprocess.run(..., capture_output=True, text=True)`
            # had a plumbing flag flipped, the child inherited stdout, and 7364 paths came out.
            #
            # BOTH POSITIONS COUNT: `ast.keyword` for `f(flag=True)` AND `ast.arguments` for
            # `def f(flag=True)`. MEASURED, the first version covered only the former and plant 6
            # went red on a `def` default -- which is the same class of construct under a different
            # node type, and a rule that catches one spelling of a thing is a list of one.
            #
            # THE COST, STATED BECAUSE IT IS REAL: `gates/tn_nary_arena-oracle.py`'s
            # `UOp(Ops.CONST, src=(), arg=True)` IS a keyword-argument value AND IS the value under
            # test. It is excluded, so that file reports 0 sites and `CANNOT BE PERTURBED`, and the
            # exclusion is COUNTED in the `unreachable` column so the blind spot has a size rather
            # than being silent. The rule is positional, so it needs no list of flag names.
            if isinstance(node, ast.Constant) and isinstance(node.value, bool) \
                    and isinstance(parents.get(id(node)), (ast.keyword, ast.arguments)):
                unreach.append(f"bool keyword flag {ast.unparse(node)!r}")
                return
            sites.setdefault(label, []).append(node)
            return
        children = (ast.iter_child_nodes(node)
                    if not isinstance(node, ast.JoinedStr)
                    else (x for f in node.values for x in ast.iter_child_nodes(f)))
        for c in children:
            scan(c, label)

    for n in ast.walk(tree):
        if not isinstance(n, ast.stmt):
            continue
        # EVERY STATEMENT IS SCANNED, `def` INCLUDED, and that is a fix against a measured wrong
        # reason. `gates/md_graph_census-oracle.py`, `mx_graph_census-oracle.py` and four siblings
        # put their whole fixture in a module-level `print(f"...")` and were reported
        # `IGNORES ITS INPUT / 0 reachable sites` -- which is THIS INSTRUMENT'S blindness wearing
        # the oracle's name. MEASURED A SECOND TIME on plant 6: skipping `FunctionDef` also
        # excluded `def emit(flag=True)`'s default by ACCIDENT, so the boolean-keyword rule this
        # function documents was never the thing doing the work. A guard that is not the operative
        # one is a comment.
        target = n.value if isinstance(n, ast.Assign) else n
        if not isinstance(target, ast.AST):
            continue
        if isinstance(target, ast.Return):
            # A `return` carries no literal of its own; scanning it would only duplicate its
            # expression, which is already scanned where the expression is written.
            continue
        # THE LABEL IS THE BOUND NAME where there is one, because `dead_labels` joins on it.
        # `Assign@14` would have made every label unmatchable and the dead-label arm silently
        # vacuous -- the first version returned 0 findings for a fixture written and never
        # read, and reported it as `ALL VALID INPUTS AGREE` instead.
        label = next((t.id for t in getattr(n, "targets", [])
                      if isinstance(t, ast.Name)), f"{type(n).__name__}@{n.lineno}")
        if _own_literal(target) and id(target) not in docs and _under_output(target, parents):
            unreach.append(ast.unparse(target)[:48])
        scan(target, label)
    return sites, unreach


def fixture_fallback(src, oracle: Path):
    """The oracle's SIBLING fixture module when the oracle itself holds no literal.

    `gates/bc-u32-oracle.py` holds none: its fixture is `ROWS` in `bc_u32_table.py`, which it
    imports. Reporting "no reachable site" for it would report this instrument's blindness as the
    oracle's, so the fallback is mechanical -- a same-directory `.py` named by an `import` -- and
    the row records which module the surface came from.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return None
    for n in ast.walk(tree):
        mods = ([a.name for a in n.names] if isinstance(n, ast.Import)
                else [n.module] if isinstance(n, ast.ImportFrom) and n.module and not n.level
                else [])
        for m in mods:
            p = oracle.parent / f"{m.split('.')[0]}.py"
            if p.is_file() and p.resolve() != oracle.resolve():
                return p
    return None


# ============================================================ 3. THE PERTURBATION, AS TEXT


def _rot(items, kind):
    if kind == "EMPTY":
        return "[]"
    if kind == "VALID-DIFFERENT" and len(items) > 1:
        return "[" + ", ".join(items[1:] + items[:1]) + "]"
    if kind == "BOUNDARY" and items:
        return "[" + items[-1] + "]"
    return None


def _elts(node):
    if isinstance(node, ast.Dict):
        return [f"{ast.unparse(k)}: {ast.unparse(v)}" for k, v in zip(node.keys, node.values)
                if k is not None]
    return [ast.unparse(e) for e in node.elts]


def rotatable(site):
    """True when this container's elements are INTERCHANGEABLE, so a rotation reorders INPUT.

    A single `isinstance` over the DIRECT elements, and the shape matters: `checks/render-gate-oracle.py`
    failed on `("cast", g_cast)` -- a `Constant` beside an `Attribute` -- while the fixture containers
    that DO rotate (`wk-cd-oracle.py`'s `CASES`, a list of 4-tuples; `mx_graph_census-oracle.py`'s
    `reshape(1, 2, 8, 16)`, a tuple of numbers) are homogeneous and survive.
    """
    elts = [e for e in getattr(site, "elts", None) or [] if not isinstance(e, ast.Starred)]
    if isinstance(site, ast.Dict):
        elts = [k for k in site.keys if k is not None]
    return bool(elts) and all(isinstance(e, ROTATABLE) for e in elts) \
        and len({type(e) for e in elts}) == 1


def replacement(site, kind):
    """The replacement SOURCE TEXT for one site under one class. Returns None for "no-op".

    NEVER INVENTS A VALUE. A string has no mechanically knowable "other valid value", so it is
    left alone and the census counts the strings it left alone rather than pretending they were
    perturbed. A bool's other value is knowable (`not b`) and is used.
    """
    if isinstance(site, ast.Constant):
        v = site.value
        if isinstance(v, bool):
            return {"EMPTY": "False", "VALID-DIFFERENT": f"(not {v})",
                    "BOUNDARY": f"(not {v})"}[kind]
        if isinstance(v, str):
            return '""' if kind == "EMPTY" else None
        if isinstance(v, int):
            return {"EMPTY": "0", "VALID-DIFFERENT": f"({v} + 1)", "BOUNDARY": f"(-({v}))"}[kind]
        return {"EMPTY": "0.0", "VALID-DIFFERENT": f"({v!r} + 1.0)",
                "BOUNDARY": f"(-({v!r}))"}[kind]
    items = _elts(site)
    if kind in ("VALID-DIFFERENT", "BOUNDARY") and not rotatable(site):
        return None
    rot = _rot(items, kind)
    if rot is None:
        return None
    if isinstance(site, ast.List):
        return rot
    if isinstance(site, ast.Tuple):
        return "(" + rot[1:-1] + ("," if len(items) == 1 and kind == "BOUNDARY" else "") + ")"
    if isinstance(site, ast.Set):
        return "set()" if kind == "EMPTY" else ("{" + rot[1:-1] + "}" if rot != "[]" else "set()")
    if isinstance(site, ast.Dict):
        return "{}" if kind == "EMPTY" else ("{" + rot[1:-1] + "}" if rot != "[]" else "{}")
    return None


def perturb(src, path: Path, kind: str, sites):
    """`(text, n_applied, n_sites, n_str_untouched, n_file_sub)` or `None` when nothing applies."""
    starts, acc = [], 0
    for line in src.splitlines(keepends=True):
        starts.append(acc)
        acc += len(line)
    edits, n_str = [], 0
    for group in sites.values():
        for site in group:
            new = replacement(site, kind)
            if new is None:
                n_str += 1 if isinstance(site, ast.Constant) and isinstance(site.value, str) else 0
                continue
            a, b, c, d = site.lineno, site.col_offset, site.end_lineno, site.end_col_offset
            edits.append((starts[a - 1] + b, starts[c - 1] + d, new))
    if not edits:
        return None
    edits.sort()
    out, cursor, last = [], 0, -1
    for s0, e0, new in edits:
        if s0 < last:                       # a nested site the outermost scan already covered
            continue
        out.append(src[cursor:s0])
        out.append(new)
        cursor = last = e0
    out.append(src[cursor:])
    body = "".join(out)
    n_sub = len(OUT_RE.findall(body))
    return OUT_RE.sub(repr(str(path)), body), len(edits), sum(len(g) for g in sites.values()), \
        n_str, n_sub


# ================================================================ 4. RUNNING ONE ORACLE, ONCE


def invoke(script: Path, argv=(), env=None, seed=None):
    t0 = time.time()
    e = None if env is None else {**os.environ, **env}
    if seed:
        e = {**(e or os.environ), "PYTHONHASHSEED": seed}
    try:
        r = subprocess.run([str(PY), str(script), *argv], cwd=ROOT, capture_output=True,
                           text=True, timeout=BUDGET, env=e)
        return {"rc": r.returncode, "out": r.stdout, "err": r.stderr, "s": time.time() - t0}
    except subprocess.TimeoutExpired:
        return {"rc": None, "out": "", "err": f"TIMEOUT>{BUDGET}s", "s": time.time() - t0}


def lines(out):
    return [l.strip() for l in out.split("\n") if l.strip()]


def rowmap(out):
    """`{row name: the rest of the line}` -- the row IDENTITY, so movement is per row and not
    per line. Everything in this tree's oracles is `name=value`, and `autogen-oracle.py` prints
    `tmap 0 = int` with spaces, so the split is at the FIRST `=` and the name keeps its spaces."""
    m = {}
    for l in lines(out):
        k, sep, v = l.partition("=")
        m.setdefault(k if sep else l, []).append(v if sep else "")
    return {k: "|".join(sorted(v)) for k, v in m.items()}


def peak_child_mib():
    """Peak RSS of the heaviest child, in MiB.

    `ru_maxrss` is KILOBYTES on Linux and BYTES on macOS (`os.wait4`'s contract), so an
    unconditional `/1024` reads a macOS figure as GIBIBYTES -- the first run of this file printed
    `peak child RSS 71872 MiB`, which is 70 MiB said loudly. `sys.platform` decides, and the
    platform is named because a number with no unit is how the 797-in-AGENTS.md class starts.
    """
    raw = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    return raw / (1024 * 1024) if sys.platform == "darwin" else raw / 1024


def movement(base, got):
    """`(rows_moved, count_changed, multiset_changed, order_only)` -- "moved" is four claims.

    `rows_moved` is THE FLOOR: how many of the oracle's rows carry a different value, plus how
    many names appeared or vanished. That is the number the brief asks for ("0 of 51 rows move"),
    and it is not a boolean. `order_only` is reported because a VALID-DIFFERENT rotation
    MANUFACTURES an order change by construction, and an instrument that counted that as a
    sensitivity signal would be measuring its own transformation.
    """
    b, g = lines(base), lines(got)
    mb, mg = rowmap(base), rowmap(got)
    names = set(mb) | set(mg)
    moved = sum(1 for n in names if mb.get(n) != mg.get(n))
    return (moved, len(b) != len(g), sorted(b) != sorted(g),
            b != g and sorted(b) == sorted(g))


# ============================================================ 5. ONE ORACLE, END TO END


def argv_for(rel: str):
    """The argv this tree passes, MEASURED where it can be and DECLARED where it cannot.

    `gates/autogen-oracle.py:49` is `hdr = sys.argv[1]` and NO gate declares it, so there is no
    gate-supplied argv to copy. Its input is the header beside it, `gates/ag-fixture.h`, and the
    row records that the baseline was CHOSEN rather than discovered. Every other oracle runs with
    no argv, which is what `gatekit.Gate._oracle` does.
    """
    if Path(rel).name == "autogen-oracle.py":
        h = HERE / "ag-fixture.h"
        if h.is_file():
            return [str(h)], f"CHOSEN: gates/ag-fixture.h sha {hashlib.sha256(h.read_bytes()).hexdigest()[:12]}"
    return [], "gatekit.Gate._oracle passes no argv"


def argv_probe(rel: str):
    """A SECOND, DIFFERENT input for the `sys.argv` oracles -- the perturbation a file oracle gets.

    `gates/autogen-oracle.py` is the whole measured case: `sys.argv[1]` is its input, so the
    perturbation is a different FILE, not a different literal. Three are written beside the census
    and each is passed as argv[1]: EMPTY (0 bytes), GARBAGE (`GARBAGE NOT C AT ALL\n`), and a
    VALID-BUT-DIFFERENT header (a real C header with different struct members, generated from the
    oracle's own shape and not from any expected value).
    """
    src = (ROOT / rel).read_text(errors="replace")
    if not re.search(r"sys\.argv\s*\[\s*1\s*\]", src):
        return None
    ART.mkdir(parents=True, exist_ok=True)
    base = HERE / "ag-fixture.h"
    made = {}
    for tag, body in (("EMPTY", ""),
                      ("GARBAGE", "GARBAGE NOT C AT ALL\n"),
                      ("VALID-DIFFERENT",
                       (base.read_text(errors="replace") if base.is_file() else "")
                       + "\ntypedef struct { unsigned long long c_lo, c_hi; } "
                         "sensitiv_other_shape_t;\n")):
        p = ART / f"probe-{tag}.c"
        p.write_text(body)
        made[tag] = p
    return made


def probe_one(rel, row):
    """The `sys.argv` arm: same rows, three different input FILES.

    RUNS BEFORE THE VERDICT, because for `gates/autogen-oracle.py` it is the only surface there
    is -- `sys.argv[1]` IS its input, so the perturbation is a different FILE and not a different
    literal. An oracle that holds no literal site and moves nothing under a file perturbation is
    precisely the measured instance this census exists to take a floor of.
    """
    made = argv_probe(rel)
    if not made:
        return
    row["argv_probe"] = {}
    base = row["_base_tokens"]
    for tag, p in sorted(made.items()):
        # THE ORACLE IS THE SCRIPT AND THE PROBE IS `argv[1]`. MEASURED, and it invalidated the
        # whole arm: the first version called `invoke(p, argv=[str(p)])`, and `invoke` builds
        # `[PY, script, *argv]` -- so it ran `python gates/artifacts/sensitiv/probe-GARBAGE.c`,
        # i.e. it asked CPython to PARSE A C HEADER. Every probe returned rc=1 with 0 rows and the
        # census printed `EMPTY=103 GARBAGE=103 VALID-DIFFERENT=103` -- three identical numbers,
        # all of them the same failure. Run correctly (`python gates/autogen-oracle.py <probe>`) the
        # three probes answer 0, 53 and 74 rows.
        got = invoke(ROOT / rel, argv=[str(p)])
        moved, count, multi, _o = movement("\n".join(base), got["out"])
        row["argv_probe"][tag] = {"rc": got["rc"], "rows_moved": moved, "count": count,
                                  "multiset": multi, "bytes": p.stat().st_size}
        p.unlink()
    row["argv_probe"]["floor"] = min(
        [v["rows_moved"] for k, v in row["argv_probe"].items() if k != "floor"] or [0])


def dead_labels(src, sites):
    """Labels that are BOUND but never LOADED -- a fixture written and never read.

    THIS IS THE LINE THE BRIEF ASKS FOR, AND IT IS NOT THE SAME MEASUREMENT AS "0 rows moved". An
    oracle that writes `VALUES = [...]` at module scope and never names `VALUES` again provably
    ignores its input, and the proof is a `ast.Name(Load)` count of ZERO -- a line number, not an
    inference from a diff. An oracle that DOES load it and answers the same is a constant property
    or a divergence, and calling that blindness is the conflation this file exists to avoid.

    Only labels at or near module scope are checked, and only the oracle's OWN bindings: a
    fallback fixture module's labels are read by the oracle through the import, so their load
    count belongs to a different file and is reported there, not here.
    """
    tree = ast.parse(src)
    bound = {}
    for n in tree.body:
        if isinstance(n, ast.Assign):
            for t in n.targets:
                if isinstance(t, ast.Name) and not t.id.startswith(("@", "DIVERGES", "ROWS")):
                    bound.setdefault(t.id, n.lineno)
    loaded = {n.id for n in ast.walk(tree)
              if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}
    own = _own_labels(sites)
    return {k: v for k, v in sorted(bound.items()) if k in own and k not in loaded}


def _own_labels(sites):
    return {lab for lab in sites if lab.isidentifier()}


def env_keys_read(src):
    """`os.environ["K"]` / `os.getenv("K")` keys this oracle READS. A real, undeclared input.

    MEASURED, the two oracles that made this necessary: `gates/i64-shl-oracle.py:101` is
    `seed = int(os.environ["I64SHL_SEED"])` and `gates/i64-shr-oracle.py` the same under
    `I64SHR_SEED`. Running either with no environment answers `KeyError` -- so the first census
    reported both `CANNOT BE PERTURBED rc=1`, which is TRUE and useless: the precondition is
    written down in the gate that owns them (`gates/i64-shl-gate.py:54`,
    `os.environ["I64SHL_SEED"] = str(SEED)` with `SEED = 7`), and an instrument that stops at
    `KeyError` while the tree holds the value has measured its own ordering rather than the
    oracle. The gate is the declaration, so the gate supplies the value, and the SEED is then a
    VALID-DIFFERENT perturbation in its own right.
    """
    out = set()
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return out
    for n in ast.walk(tree):
        if isinstance(n, ast.Subscript) and isinstance(n.value, ast.Attribute) \
                and n.value.attr == "environ":
            if isinstance(n.slice, ast.Constant) and isinstance(n.slice.value, str):
                out.add(n.slice.value)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "getenv" \
                and n.args and isinstance(n.args[0], ast.Constant) \
                and isinstance(n.args[0].value, str):
            out.add(n.args[0].value)
    return out


def gate_env_values(readers, keys):
    """`{KEY: value}` for keys a gate reader ASSIGNS, from the gates' own AST.

    `os.environ["K"] = str(SEED)` is not `literal_eval`-able, so the assigned value is resolved
    through the module's own bindings: `SEED = 7` is a `Constant`, which is the whole chain. A key
    no reader assigns is reported UNSUPPLIED rather than defaulted, because supplying a value of
    my own choosing is inventing an expected value and the brief forbids it.
    """
    out = {}
    for g in readers:
        if g.suffix != ".py":
            continue
        try:
            tree = ast.parse(g.read_text(errors="replace"))
        except (OSError, SyntaxError):
            continue
        binds = {t.id: n.value for n in tree.body if isinstance(n, ast.Assign)
                 for t in n.targets if isinstance(t, ast.Name)}
        for n in ast.walk(tree):
            # `os.environ["K"] = v` puts the SUBSCRIPT IN `targets` and the value in `n.value`.
            # The first version of this function tested `n.value` -- which is `str(SEED)`, a Call
            # -- and so found ZERO assignments in `gates/i64-shl-gate.py` and reported
            # `I64SHL_SEED` unsupplied while the tree holds `SEED = 7` four lines above it. A
            # wrong side of an assignment is the brief's "a wrong reason is worse than no reason"
            # wearing a syntax error.
            if not (isinstance(n, ast.Assign) and n.targets
                    and isinstance(n.targets[0], ast.Subscript)
                    and isinstance(n.targets[0].value, ast.Attribute)
                    and n.targets[0].value.attr == "environ"
                    and isinstance(n.targets[0].slice, ast.Constant)
                    and n.targets[0].slice.value in keys):
                continue
            key = n.targets[0].slice.value
            v = n.value
            if isinstance(v, ast.Call) and v.args:
                v = v.args[0]
            if isinstance(v, ast.Name):
                v = binds.get(v.id)
            if isinstance(v, ast.Constant):
                out.setdefault(key, (str(v.value), f"{g.name}:{n.lineno}"))
    return out


def input_lives_in(src):
    """The `tinygrad.*` modules an oracle imports -- WHERE ITS INPUT LIVES when it has no fixture.

    The fourth verdict is `CANNOT BE PERTURBED (why)`, and for this shape "why" must name the
    thing that would decide it rather than shrug. `gates/tn_minimum-oracle.py` is the measured
    instance: it emits `sorted(o.name for o in Ops)` -- its input IS `tinygrad.uop.ops.Ops`, and
    the perturbation is an edit to `tinygrad/`, which the brief declares read-only. Calling that
    `IGNORES ITS INPUT` is the conflation the brief names in the other direction: it does the
    exact opposite of ignoring its input.
    """
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return ()
    mods = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            mods |= {a.name for a in n.names if a.name.split(".")[0] == "tinygrad"}
        if isinstance(n, ast.ImportFrom) and n.module and n.module.split(".")[0] == "tinygrad":
            mods.add(n.module)
    return tuple(sorted(mods))


def census_one(rel, meta):
    """One row. Never raises: a failure is a MEASUREMENT (`CANNOT BE PERTURBED`) with a reason."""
    p = ROOT / rel
    row = {"oracle": rel, "class": meta["class"], "bytes": meta["bytes"], "sha12": meta["sha12"],
           "declared_by": ";".join(meta["declared_by"][:3])}
    # THIS FILE IS IN ITS OWN POPULATION. `gates/oracleblind-census.py` carries `oracle` in its
    # stem, so the walk admits it -- and running a perturbed copy of a census CENSUS is unbounded
    # recursion, not a measurement. The exclusion is NAMED in the row rather than applied in the
    # walk, because a walk that silently drops a file is the class this instrument exists to end.
    if p.resolve() == Path(__file__).resolve():
        row.update(verdict="CANNOT BE PERTURBED",
                   why="SELF: this file; running a perturbed copy of a census is unbounded "
                       "recursion, not a measurement", rows=0, sites=0, deterministic=None)
        return row
    if not meta["exists"]:
        row.update(verdict="CANNOT BE PERTURBED", why="the declared path does not exist",
                   rows=0, sites=0, deterministic=None)
        return row
    src = p.read_text(errors="replace")
    argv, argv_note = argv_for(rel)
    row["argv"] = argv_note
    # THE ENVIRONMENT PRECONDITION, FROM THE ORACLE'S OWN CODE AND THE GATE'S OWN ASSIGNMENT.
    envkeys = env_keys_read(src)
    envvals = gate_env_values(ENV_READERS, envkeys) if envkeys else {}
    row["env"] = {k: v[0] for k, v in sorted(envvals.items())}
    missing_env = sorted(envkeys - set(envvals))
    env = {k: v[0] for k, v in envvals.items()}
    a, b = invoke(p, argv, env), invoke(p, argv, env)
    row["rc"] = a["rc"]
    row["seconds"] = round(a["s"], 1)
    row["rows"] = len(lines(a["out"]))
    # THE BASE OUTPUT'S SHA, so a reader can CHECK a claim of "two inputs agreed" from the table
    # instead of taking it: every perturbed run's output sha is printed beside it, and equality of
    # two shas IS the agreement. `gates/unrunnable-recipes.py` records the same defect this fixes
    # (a table whose sha moved between runs of one tree, 20 rows apart, `PYTHONHASHSEED` 1 vs 2).
    row["base_sha"] = hashlib.sha256(a["out"].encode()).hexdigest()[:12]
    row["deterministic"] = (a["out"] == b["out"])
    row["_base_tokens"] = lines(a["out"])
    if a["rc"] != 0 and (missing_env or not env):
        tail = (a["err"] or "").strip().splitlines()
        row.update(verdict="CANNOT BE PERTURBED",
                   why=(f"reads os.environ[{missing_env}] and NO GATE ASSIGNS IT -- the "
                        f"precondition is absent, which is REFUSED (3), not a verdict"
                        if missing_env else
                        f"rc={a['rc']}: {(tail[-1] if tail else 'no stderr')[:110]}"),
                   sites=0, err_head=(a["err"] or "").strip()[:200])
        return row
    try:
        sites, unreach = surface(src)
        owner = rel
        if not any(sites.values()):
            fb = fixture_fallback(src, p)
            if fb is not None:
                sites, unreach2 = surface(fb.read_text(errors="replace"))
                unreach += unreach2
                owner = fb.relative_to(ROOT).as_posix()
    except SyntaxError as e:
        row.update(verdict="CANNOT BE PERTURBED", why=f"SyntaxError: {e}", sites=0)
        return row
    row["surface_owner"] = owner
    row["sites"] = sum(len(g) for g in sites.values())
    row["unreachable_literals"] = len(unreach)
    row["unreachable_sample"] = "; ".join(sorted(set(unreach))[:4])[:180]
    row["kinds"] = {}
    for kind in KINDS:
        out = perturb(src, p, kind, sites)
        if out is None:
            row["kinds"][kind] = {"applied": 0, "note": "no site admits this class"}
            continue
        text, n_applied, n_sites, n_str, n_sub = out
        ART.mkdir(parents=True, exist_ok=True)
        sp = ART / f"{p.stem}.{kind}.py"
        sp.write_text(text)
        try:
            got = invoke(sp, argv, env)
            # THE SEED RE-RUN GOES HERE, INSIDE THE WINDOW WHERE THE FILE EXISTS. MEASURED, and it
            # marked **35 of 98 oracles SEED-UNSTABLE** including `gates/tn_sqrt-oracle.py`, whose
            # output I verified byte-identical at three seeds BY HAND: the first version ran the
            # re-run AFTER the `finally: sp.unlink()`, so `invoke` found no file and compared the
            # sha of an EMPTY string against a real one. A stability check run against a deleted
            # subject is worse than none -- it manufactures an instability.
            seed_stable = None
            if got["rc"] == a["rc"] and n_applied:
                again = invoke(sp, argv, env, seed="2")
                seed_stable = (hashlib.sha256(again["out"].encode()).hexdigest()[:12]
                               == hashlib.sha256(got["out"].encode()).hexdigest()[:12])
        finally:
            sp.unlink()
        c, m, o, oo = movement(a["out"], got["out"])
        row["kinds"][kind] = {"applied": n_applied, "of_sites": n_sites,
                          "strings_untouched": n_str, "file_sub": n_sub, "rc": got["rc"],
                          "rows_moved": c if got["rc"] == a["rc"] else None,
                          "count": m, "multiset": o, "order_only": oo,
                          "crashed": got["rc"] != a["rc"], "seed_stable": seed_stable,
                          "out_sha": hashlib.sha256(got["out"].encode()).hexdigest()[:12]}
    # A CRASH IS NOT MOVEMENT. MEASURED, and it is THIS FILE'S OWN DEFECT: with `bool` literals
    # admitted to the surface, `gates/oracle-census-gate.py`'s
    # `subprocess.run(..., capture_output=True, text=True)` had its flag flipped by
    # VALID-DIFFERENT, the child inherited stdout, the census printed **7364 paths** instead of
    # 0 rows, and the verdict came back `SENSITIVE floor=7364 of 0 rows`. That is not an oracle
    # reading its input; it is a perturbation that broke the ORACLE'S OWN PLUMBING. The brief's
    # "an oracle that legitimately rejects garbage still moves" is true of a rejection OF THE
    # DATA, and a run that cannot finish is indistinguishable from one without a semantic model of
    # the fixture. So a run whose exit status differs from the base's contributes NOTHING to the
    # floor and gets its own column: an over-claim is the same failure this census exists to end.
    moved = {k: v for k, v in row["kinds"].items() if v.get("rows_moved")}
    order_only = [k for k, v in row["kinds"].items() if v.get("order_only")]
    row["moved_by"] = sorted(moved)
    row["order_only_by"] = sorted(order_only)
    row["dead_labels"] = dead_labels(src, sites) if owner == rel else {}
    # THE ENVIRONMENT ARM. A numeric precondition is a numeric input, so `I64SHL_SEED=7` becomes
    # `8` -- the SAME `n -> n+1` rule VALID-DIFFERENT uses on a literal, applied to the process the
    # gate wrote. It is reported as its own class rather than folded into the literal classes
    # because it perturbs no source at all, and folding it would make a row of the table say
    # "EMPTY" for a run whose text was untouched.
    row["env_class"] = None
    if env and not missing_env:
        bumped = {}
        for k, v in env.items():
            try:
                bumped[k] = str(int(v) + 1)
            except ValueError:
                bumped[k] = v + "x"
        got = invoke(p, argv, bumped)
        c, m, o, _oo = movement(a["out"], got["out"])
        env_ok = got["rc"] == a["rc"]
        row["env_class"] = {"from": env, "to": bumped, "rc": got["rc"], "rows_moved": c,
                            "count": m, "multiset": o, "crashed": not env_ok}
    row["env_missing"] = missing_env
    probe_one(rel, row)          # the sys.argv arm runs BEFORE the verdict: for `autogen-oracle.py`
    ap = row.get("argv_probe") or {}                     # it is the ONLY surface there is
    ap_moved = [k for k, v in ap.items() if k != "floor" and v["rows_moved"] and v["rc"] == a["rc"]]
    row["argv_moved_by"] = sorted(ap_moved)
    env_moved = bool(row["env_class"] and row["env_class"]["rows_moved"]
                     and not row["env_class"]["crashed"])
    all_moved = sorted(set(row["moved_by"]) | set(ap_moved) | ({"ENV"} if env_moved else set()))
    floors = [v["rows_moved"] for v in moved.values()] + [ap[k]["rows_moved"] for k in ap_moved] \
        + ([row["env_class"]["rows_moved"]] if env_moved else [])
    row["floor"] = min(floors) if floors else row["rows"]
    row["crashed_by"] = sorted(k for k, v in row["kinds"].items() if v.get("crashed"))
    # THE DENOMINATOR OF THE DENOMINATOR, OVER **EVERY ARM**. `0 rows moved` over classes that all
    # CRASHED is 0 comparisons, and `0 disagreements over 0 comparisons is not agreement`
    # (`.agents/slop/rebase-gate-selftest.py:1168-1180`). MEASURED twice on this file. First: 19 of
    # 98 oracles were reported as agreeing on the strength of zero completed comparisons --
    # `gates/state_census-oracle.py`, 85 sites, 85 rows, 0 of 3 classes completing. Second, and the
    # worse one: the count covered only the LITERAL classes, so `gates/autogen-oracle.py` -- whose
    # three literal classes all crash -- came back `CANNOT BE PERTURBED` while its ARGV arm had
    # already measured **103 of 117 rows moving under three different input FILES**. A denominator
    # that omits the arm which found the answer is a denominator that hides the answer.
    row["comparisons"] = sum(1 for v in row["kinds"].values()
                             if v.get("applied") and not v.get("crashed")) + len(ap_moved) \
        + (1 if (row["env_class"] and not row["env_class"]["crashed"]) else 0)
    if a["rc"] != 0 and missing_env:  # an env precondition whose value no gate writes
        row.update(verdict="CANNOT BE PERTURBED",
                   why=f"reads os.environ[{missing_env}] and NO GATE ASSIGNS IT -- the "
                       f"precondition is absent, which is REFUSED (3), not a verdict")
    elif not row["sites"] and not ap:
        # NO SITE AND NO DEAD LABEL IS NOT BLINDNESS. An oracle with no fixture of its own, whose
        # input is `tinygrad`'s own code, cannot be perturbed without editing `tinygrad/` -- and
        # `IGNORES ITS INPUT` would say the opposite of what it does.
        where = ", ".join(input_lives_in(src)) or "nothing it imports"
        row.update(verdict="CANNOT BE PERTURBED",
                   why=f"no fixture of its own: 0 reachable literal sites and 0 bound-but-unloaded "
                       f"labels. Its input is {where}, and perturbing that means editing "
                       f"`tinygrad/`, which is read-only. WHAT WOULD DECIDE IT: an import shim "
                       f"that patches {where} before the oracle runs.")
    elif row["dead_labels"] and not all_moved:
        where = ", ".join(f"{owner}:{ln} {k} is bound and never loaded"
                          for k, ln in row["dead_labels"].items())
        row.update(verdict="IGNORES ITS INPUT", why=where)
    elif not row["comparisons"]:
        why_crash = ", ".join(f"{k}(rc={row['kinds'][k]['rc']})" for k in row["crashed_by"])
        row.update(verdict="CANNOT BE PERTURBED",
                   why=f"0 of {len(KINDS)} perturbation classes completed ({why_crash}) -- "
                       f"{row['sites']} sites, {row['rows']} rows, and 0 COMPARISONS, which is "
                       f"DEAD (gatekit exit 5), not agreement. WHAT WOULD DECIDE IT: a "
                       f"perturbation the fixture survives, or the crash's first traceback line.")
    elif not all_moved:
        row.update(verdict="ALL VALID INPUTS AGREE",
                   why=f"{row['sites']} sites in {owner}, every one loaded; 0 of {row['rows']} "
                       f"rows moved over {row['comparisons']} completed comparison(s)"
                       + (" + ENV" if env else "") + (" + ARGV" if ap else "")
                       + (f"; {len(row['crashed_by'])} class(es) CRASHED and were excluded"
                          if row["crashed_by"] else ""))
    else:
        row.update(verdict="SENSITIVE",
                   why=f"floor={row['floor']} of {row['rows']} rows; moved by {','.join(all_moved)}")
    return row


# ============================================================================= 6. THE TABLE


def table(rows):
    cols = ["oracle", "class", "verdict", "floor_of_rows", "rows", "base_sha", "sites",
            "unreachable", "deterministic", "rc", "EMPTY", "VALID-DIFFERENT", "BOUNDARY",
            "ENV", "ARGV", "crashed_by", "seed_stable", "comparisons", "dead_labels",
            "surface_owner", "why", "declared_by", "argv", "env"]
    out = ["\t".join(cols)]
    for r in sorted(rows, key=lambda r: r["oracle"]):
        def mv(k):
            v = r.get("kinds", {}).get(k)
            if v is None:
                return "-"
            if not v.get("applied"):
                return "no-site"
            if v.get("crashed"):
                return f"CRASH rc={v['rc']}"
            sha = v['out_sha'] if v.get("seed_stable") is not False else "SEED-UNSTABLE"
            flag = (f"{v['rows_moved']}@{sha}" + ("C" if v["count"] else "")
                    + ("M" if v["multiset"] else "") + ("o" if v["order_only"] else ""))
            return flag or "0"
        ap = r.get("argv_probe") or {}
        ec = r.get("env_class")
        out.append("\t".join([
            r["oracle"], r["class"], r["verdict"], str(r.get("floor", "")),
            str(r.get("rows", "")), r.get("base_sha", "-"), str(r.get("sites", "")),
            str(r.get("unreachable_literals", "")),
            str(r.get("deterministic")), str(r.get("rc", "")),
            mv("EMPTY"), mv("VALID-DIFFERENT"), mv("BOUNDARY"),
            (f"{ec['rows_moved']}@{ec['to']}" if ec and not ec.get("crashed")
             else (f"CRASH rc={ec['rc']}" if ec else "-")),
            ("/".join(f"{k}={v['rows_moved']}" + ("" if v["rc"] == r.get("rc") else f"!rc{v['rc']}")
                     for k, v in sorted(ap.items()) if k != "floor")
             if ap else "-"),
            ";".join(r.get("crashed_by") or []) or "-",
            (lambda ss: "ALL" if all(s is True for s in ss) else
             ("NONE" if all(s is None for s in ss) else
              ",".join(sorted({str(s) for s in ss}))))(
                 [v.get("seed_stable") for v in r.get("kinds", {}).values()
                  if v.get("applied") and not v.get("crashed")]),
            str(r.get("comparisons", "")),
            ";".join(f"{k}:{v}" for k, v in sorted((r.get("dead_labels") or {}).items())) or "-",
            r.get("surface_owner", "-"), r.get("why", "").replace("\t", " ")[:190],
            r.get("declared_by", "").replace("\t", " ")[:80],
            r.get("argv", "").replace("\t", " ")[:60],
            ",".join(f"{k}={v}" for k, v in sorted((r.get("env") or {}).items())) or "-"]))
    return "\n".join(out) + "\n"


def summarise(rows, d):
    v = {}
    for r in rows:
        v[r["verdict"]] = v.get(r["verdict"], 0) + 1
    print(f"  homes read          {','.join(d['homes'])}  "
          f"({d['readers_read']} .py reader(s) parsed, {d['readers_not_python']} non-.py "
          f"reader(s) NOT parsed by this instrument)")
    for u in d["unreadable_readers"]:
        print(f"    UNREADABLE {u}")
    print(f"  population          {len(rows)} oracle(s): "
          + " ".join(f"{k}={v[k]}" for k in sorted(v)))
    print(f"  walk-only           {d['walk_only']} (no gate names them -- a DENOMINATOR)")
    print(f"  not carried         {len(d['not_carried'])} (the COMMIT TREE does not carry them, so "
          f"they are not files of this repository)  {d['not_carried'][:4]}")
    print(f"  absent on disk      {len(d['absent'])}  {d['absent'][:4]}")
    print(f"  unresolved decl     {d['unresolved_decl'] or 'none'}")
    print(f"  unlocatable decl    {len(d['declared_but_unlocatable'])}  {d['declared_but_unlocatable'][:4]}")
    for k in sorted(v):
        print(f"    {k:24} {v[k]:3}")
    nondet = [r["oracle"] for r in rows if r.get("deterministic") is False]
    print(f"  nondeterministic     {len(nondet)}  {nondet}")
    print(f"  verdict table       {REPORT.relative_to(ROOT)}")


def verdict_of(rows):
    """The census is REPORTED and not charged. See `--report`; this returns the coverage check.

    THE ONLY ASSERTION IS COVERAGE: every row carries exactly one of the four verdicts, and the
    counts sum to the population. `0 disagreements over 0 comparisons is not agreement`
    (`.agents/slop/rebase-gate-selftest.py:1168-1180`), so the denominator is asserted, never
    inferred. An oracle the instrument cannot classify is a FAILURE OF THE INSTRUMENT.
    """
    known = {"SENSITIVE", "IGNORES ITS INPUT", "ALL VALID INPUTS AGREE", "CANNOT BE PERTURBED"}
    bad = [r["oracle"] for r in rows if r["verdict"] not in known]
    if not rows:
        return 5, "the population is empty"
    if bad:
        return 1, f"{len(bad)} row(s) carry no verdict: {bad[:4]}"
    return 0, (f"{len(rows)} oracles classified into {len(known)} verdicts, "
               + " ".join(f"{k}={sum(1 for r in rows if r['verdict'] == k)}"
                          for k in sorted(known)))


# ================================================================================== 7. PLANT


GOOD = '''#!/usr/bin/env python3
"""A synthetic oracle whose rows ARE a function of its fixture."""
VALUES = [1, 2, 4, 8]
for v in VALUES:
    print(f"v{v}={v * 2}")
'''

CONSTANT = '''#!/usr/bin/env python3
"""A synthetic oracle whose rows are a CONSTANT, whatever the fixture says."""
VALUES = [1, 2, 4, 8]
print("answer=42")
'''

NOFIX = '''#!/usr/bin/env python3
"""A synthetic oracle with no fixture at all -- the CANNOT-BE-PERTURBED arm."""
import tinygrad.uop.ops as m
print("answer=42")
print(f"members={len(list(m.Ops))}")
'''


FLAGOFF = '''#!/usr/bin/env python3
"""One class crashes (EMPTY indexes an empty list), the other two complete and AGREE.

    The two `7`s are equal on purpose: a rotation of `[7, 7]` is `[7, 7]` and its last element is
    `7`, so VALID-DIFFERENT and BOUNDARY are real perturbations that change nothing. This is the
    arm that a crash must NOT be allowed to steal: one completed, agreeing comparison is
    evidence, and hiding it behind the crash is how `state_census-oracle.py` lost 85 rows of
    denominator.
"""
VALUES = [7, 7]
print(f"answer={VALUES[0]}")
'''

ALLCRASH = '''#!/usr/bin/env python3
"""Base rc=0, and EVERY class raises -- 0 comparisons, which is DEAD and not agreement."""
TABLE = {3: "three"}
N = 3
print(f"answer={TABLE[N]}")
'''


BOOLS = '''#!/usr/bin/env python3
"""A fixture that IS a bool passed as a keyword argument -- the EXCLUDED case.

    `emit(flag=True)` must not be perturbed, because flipping it changes WHICH METHOD IS UNDER
    TEST (`gates/tn_mul-oracle.py:51`, `d.mul(c, reverse=True)`). The call is a STATEMENT, not
    inside an f-string, so the exclusion that fires is the keyword-argument one rather than the
    output-side one -- the first version of this plant put it inside `print(f"...")` and passed for
    the wrong reason, which is the `.agents/TODO.md` trap in a plant.
"""
VALUES = [1, 2]
def emit(flag=True):
    return len(VALUES) if flag else -1
r = emit(flag=True)
print(f"answer={r}")
'''


MIXED = '''#!/usr/bin/env python3
"""A container holding a LABEL and a CALLABLE is a BINDING, not a fixture -- and rotating it
   re-binds the program. `checks/render-gate-oracle.py:164` is the live instance and it is what
   moved this table's sha under a second PYTHONHASHSEED."""
VALUES = [1, 2]
BINDINGS = [("a", lambda: len(VALUES)), ("b", lambda: len(VALUES) + 1)]
print("".join(f"{n}={f()};\\n" for n, f in BINDINGS))
'''

# THE PLANT'S FIXTURES. THE ORACLE'S NAME IS A STEM, NEVER A LITERAL THAT ENDS IN `.py`: this file
# IS IN ITS OWN POPULATION, and its own admission rule ("every tracked `.py` constant a gate
# mentions whose value ends in `.py` and carries `oracle`") would turn a literal into a
# DECLARATION. `gates/tnvalue-census.py` records the trap by name: "this file perturbed the very
# denominator it reads its verdicts from, and it did it by NAMING A THING THAT DOES NOT EXIST". So
# the names are STEMS plus a suffix, and the census's own filename is `__file__`'s.
ORACLE_STEM = "fixture-oracle"
GATE_STEM = "fixture-gate"
WITNESS_STEM = "home-witness"

FIXTURE_GATE = '''#!/usr/bin/env python3
"""A synthetic gate that DECLARES an oracle -- the census's FIRST read, in miniature."""
ORACLE = "fixture-oracle.py"


def Gate(name, oracle=None):
    return (name, oracle)


def main():
    print(Gate("fixture", oracle=ORACLE))


if __name__ == "__main__":
    main()
'''


def plant_population() -> list:
    """Direction 8 -- THE POPULATION IS THE COMMIT TREE's, AND A BROKEN PRODUCER EXITS NON-ZERO.

    FOUR ARMS, ON COPIES, IN A SCRATCH TREE THAT IS NOT A REPOSITORY OF THIS ONE.
    `gates/gates-pop.py`'s `_tree_paths` records why the scratch tree is OUTSIDE: `git -C <dir>
    ls-tree` SEARCHES UPWARD, so a scratch tree inside this repository reads THIS repository's
    tree and the measurement is about a DIFFERENT TREE.

    8a CONTROL -- a tree with one CARRIED oracle: the census copy writes a table that HOLDS it,
        and the table DIFFERS from the stale bytes seeded before the run. The control is what
        makes 8b mean anything -- a census that admitted nothing would pass 8b too.
    8b PLANT -- the same tree plus an oracle the COMMIT TREE does NOT carry (it was written after
        the commit): the table must NOT hold it, and the run must NAME it. This is the arm the
        live tree has -- `checks/.tmp-tc_ptx_render-oracle.py` is another unit's in-flight scratch
        and the walk used to admit it.
    8c PLANT -- the same tree with a `gates-pop.py` whose `_buckets` returns THREE values: the
        producer must exit NON-ZERO, must NAME the reason, and must NOT rewrite its table. **A
        PRODUCER THAT DIES AND EXITS 0 IS THE WORSE SHAPE**: the file it writes stays at its old
        bytes and nothing says so.
    8d PLANT -- a tree with no gates at all: the census must SAY the population is empty, exit
        DEAD (5), and write no table at all.
    """
    gp = _gates_pop()
    checks = []
    oracle_rel = f"gates/{ORACLE_STEM}.py"
    late_rel = f"gates/late-{ORACLE_STEM}.py"
    census_name = Path(__file__).name
    env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}

    def build(root: Path, home: bool) -> Path:
        """A scratch tree with a COMMIT, so `carried` means something.

        The home is CERTIFIED by a witness and never by a list: `gates/gates-pop.py` derives the
        homes from the gates, so a synthetic tree earns a home the only way a real one does. The
        witness is `gates-pop.py`'s own `GOOD_ROOT`, LOADED FROM THAT MODULE -- a fixture retyped
        by hand agrees with the instrument by construction.
        """
        (root).mkdir(parents=True, exist_ok=True)
        (root / "pyproject.toml").write_text("[project]\nname='x'\n")
        if home:
            (root / "gates").mkdir(parents=True, exist_ok=True)
            (root / "gates" / f"{WITNESS_STEM}.py").write_text(gp.GOOD_ROOT)
            (root / "gates" / f"{GATE_STEM}.py").write_text(FIXTURE_GATE)
            (root / "gates" / f"{ORACLE_STEM}.py").write_text(GOOD)
        for cmd in (["init", "-q"], ["config", "user.email", "p@example"],
                    ["config", "user.name", "plant"]):
            subprocess.run(["git", "-C", str(root), *cmd], capture_output=True, text=True, env=env)
        subprocess.run(["git", "-C", str(root), "add", "-A"], capture_output=True, text=True, env=env)
        subprocess.run(["git", "-C", str(root), "commit", "-qm", "plant"],
                       capture_output=True, text=True, env=env)
        return root

    def install(root: Path) -> Path:
        """The census COPY and the population's own module, written AFTER the commit -- so the copy
        is not a file of the scratch repository and the population is the scratch tree's own.
        `gatekit.py` comes with them because `gates-pop.py` imports it BY PATH (`sys.path.insert(0,
        str(HERE))` then `from gatekit import REFUSED`), and the five verdicts are imported, never
        re-spelled."""
        (root / "gates").mkdir(parents=True, exist_ok=True)
        shutil.copy(HERE / census_name, root / "gates" / census_name)
        shutil.copy(HERE / "gates-pop.py", root / "gates" / "gates-pop.py")
        shutil.copy(HERE / "gatekit.py", root / "gates" / "gatekit.py")
        os.symlink(ROOT / ".venv", root / ".venv")
        return root / "gates" / census_name

    def run(root: Path):
        return subprocess.run([str(PY), str(root / "gates" / census_name)],
                              capture_output=True, text=True, timeout=900, env=env)

    with tempfile.TemporaryDirectory() as td:
        root = build(Path(td).resolve() / "tree", home=True)
        install(root)
        (root / "gates" / f"late-{ORACLE_STEM}.py").write_text(GOOD)   # AFTER the commit
        stale = "STALE ROWS FROM AN EARLIER RUN\n"
        table = root / "gates" / "oracleblind.rows"
        table.write_text(stale)
        r = run(root)
        out = r.stdout + r.stderr
        written = table.read_text() if table.is_file() else ""
        checks.append((
            "plant 8a -- a producer that RUNS writes a table that DIFFERS from the stale bytes, and "
            "it HOLDS the carried oracle (the CONTROL)",
            r.returncode == 0 and written != stale and oracle_rel in written,
            f"rc={r.returncode} differs={written != stale} holds={oracle_rel in written}"))
        checks.append((
            "plant 8b -- an oracle the COMMIT TREE does not carry is EXCLUDED from the table and "
            "NAMED by the run",
            late_rel not in written and late_rel in out,
            f"in_table={late_rel in written} named={late_rel in out}"))
        gp_copy = root / "gates" / "gates-pop.py"
        src = gp_copy.read_text()
        broken = src.replace("    return entries, libs, opaque, uncarried\n",
                             "    return entries, libs, opaque\n")
        gp_copy.write_text(broken)
        r2 = run(root)
        out2 = r2.stdout + r2.stderr
        after = table.read_text() if table.is_file() else ""
        checks.append((
            "plant 8c -- a producer whose ARITY is wrong exits NON-ZERO, NAMES the reason, and does "
            "NOT rewrite its table",
            broken != src and r2.returncode != 0 and "PopulationUnavailable" in out2
            and after == written,
            f"patched={broken != src} rc={r2.returncode} named={'PopulationUnavailable' in out2} "
            f"table_untouched={after == written}"))
        empty = build(Path(td).resolve() / "empty", home=False)
        install(empty)
        r3 = run(empty)
        out3 = r3.stdout + r3.stderr
        checks.append((
            "plant 8d -- a census that finds NOTHING says so, exits DEAD (5), and writes no table",
            r3.returncode == 5 and "the population is empty" in out3
            and not (empty / "gates" / "oracleblind.rows").exists(),
            f"rc={r3.returncode} says_empty={'the population is empty' in out3} "
            f"wrote={(empty / 'gates' / 'oracleblind.rows').exists()}"))
    return checks


def plant():
    """Three directions, and the census must be able to fail on the second one.

    1. A FIXTURE-DRIVEN oracle moves rows under all three classes -> `SENSITIVE`.
    2. A CONSTANT oracle with a fixture it never reads is red -> and the red must be a VERDICT, not
       an absence. This is the `gates/autogen-oracle.py` shape and the whole point.
    3. An oracle whose input is `tinygrad`'s OWN code and which holds no fixture -> `CANNOT BE
       PERTURBED`, NOT `IGNORES ITS INPUT`. The two are opposites and conflating them reports
       blindness as blindness' opposite. `gates/tn_minimum-oracle.py` is the live instance.
    Plus: the output side is NOT perturbable, asserted by 2 (if `answer=42` could be rewritten by
    a perturbation, 2 would report SENSITIVE for the wrong reason); and a CRASH does not count as
    movement, asserted by 4.
    4. A CRASH IS NOT A SENSITIVITY SIGNAL, AND NOT AN AGREEMENT EITHER. `plant-crash` flips a flag so
       one class raises: the verdict must not become SENSITIVE. `plant-allcrash` makes EVERY class
       raise, and the verdict must be `CANNOT BE PERTURBED`, because 0 completed comparisons is
       0 measurements -- this is the `0 disagreements over 0 comparisons` rule applied to this
       file's own output, and it was 19 of 98 oracles wrong before the guard existed.
    5. A `bool` KEYWORD ARGUMENT IS A FLAG, and `plant-boolkw` proves the census leaves it alone:
       `emit(flag=True)` must not be perturbed, because flipping it changes WHICH METHOD IS UNDER
       TEST. The cost -- a fixture that really is a keyword bool -- is counted in `unreachable`
       rather than hidden, and `gates/tn_nary_arena-oracle.py` is the live instance of the cost.
    6. THE POPULATION IS THE COMMIT TREE's, AND A BROKEN PRODUCER EXITS NON-ZERO -- `plant 8a-8d`,
       in `plant_population()`, on copies in a scratch tree.
    """
    ART.mkdir(parents=True, exist_ok=True)
    checks = []
    for want, src, tag in (("SENSITIVE", GOOD, "plant-good"),
                           ("IGNORES ITS INPUT", CONSTANT, "plant-constant"),
                           ("CANNOT BE PERTURBED", NOFIX, "plant-nofix"),
                           ("ALL VALID INPUTS AGREE", FLAGOFF, "plant-crash"),
                           ("CANNOT BE PERTURBED", ALLCRASH, "plant-allcrash")):
        sp = ART / f"{tag}.py"
        sp.write_text(src)
        try:
            r = census_one(f"gates/artifacts/sensitiv/{tag}.py",
                           {"class": "PLANT", "bytes": len(src), "sha12": "",
                            "declared_by": ["--plant"], "exists": True})
        finally:
            sp.unlink()
        got = r["verdict"]
        checks.append((f"plant `{tag}` -> {want}", got == want,
                       f"verdict={got} rows={r.get('rows')} sites={r.get('sites')} "
                       f"comparisons={r.get('comparisons')} moved={r.get('moved_by')} "
                       f"crashed={r.get('crashed_by')}"))
    # PLANT 6 asserts the SURFACE, not a verdict: `flag=True` must be EXCLUDED and COUNTED, and
    # `VALUES` must be a site. A verdict could be red for a reason that has nothing to do with the
    # exclusion, which is the `.agents/TODO.md` trap ("a fixture retyped by hand agrees with the
    # instrument by construction") in the direction of a plant that cannot fail.
    s6, u6 = surface(BOOLS)
    sites6 = {s for g in s6.values() for s in g}
    flagged = [s for s in sites6 if isinstance(s, ast.Constant) and isinstance(s.value, bool)]
    checks.append(("plant `plant-boolkw` -- a bool KEYWORD ARG is excluded AND counted, and the "
                   "sibling fixture is still a site",
                   not flagged and any("bool keyword flag" in u for u in u6) and len(sites6) >= 1,
                   f"bool sites={len(flagged)} unreachable_has_flag="
                   f"{any('bool keyword flag' in u for u in u6)} other_sites={len(sites6)}"))
    # PLANT 7 -- A HETEROGENEOUS CONTAINER IS NOT ROTATABLE. Asserted on the RULE, reached through
    # a snippet whose heterogeneous container is the OUTERMOST literal, because `surface` stops at
    # the outermost literal ancestor and the two earlier spellings of this plant could not reach
    # the inner `("a", <lambda>)` at all -- a plant that cannot reach its subject is a plant that
    # cannot fail.
    s7, _ = surface("TUPLE = (1, 'x')\nPLAIN = (1, 2, 3)\nMIXED = (1, [2], (3,))\n")
    b7 = [s for g in s7.values() for s in g]
    het = [s for s in b7 if isinstance(s, ast.Tuple) and not rotatable(s)]
    hom = [s for s in b7 if isinstance(s, ast.Tuple) and rotatable(s)]
    het_ok = bool(het) and all(replacement(s, "VALID-DIFFERENT") is None
                              and replacement(s, "BOUNDARY") is None for s in het)
    hom_ok = bool(hom) and all(replacement(s, "VALID-DIFFERENT") is not None for s in hom)
    checks.append(("plant `plant-mixed` -- a heterogeneous container is NOT rotatable and NOT "
                   "truncated, a homogeneous one still is",
                   het_ok and hom_ok,
                   f"heterogeneous={len(het)} refused={het_ok} homogeneous={len(hom)} "
                   f"rotated={hom_ok}"))
    checks += plant_population()
    bad = [n for n, ok, _ in checks if not ok]
    for n, ok, seen in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {n}\n          observed: {seen}")
    print(f"--plant: {'all eight directions hold' if not bad else 'FAILED: ' + '; '.join(bad)}")
    return 1 if bad else 0


# =================================================================================== 8. MAIN


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--report", action="store_true", help="census only, rc never charged")
    ap.add_argument("--plant", action="store_true", help="self-test on synthetic oracles")
    ap.add_argument("--rss", action="store_true", help="peak RSS + wall clock, census suppressed")
    ap.add_argument("--only", default=None, help="census one oracle by basename, for iteration")
    a = ap.parse_args(argv)
    if a.plant:
        return plant()

    t0 = time.time()
    try:
        rows, d = population()
    except PopulationUnavailable:
        # DEAD (5): THE RUNNER RAN AND EMITTED NOTHING. The traceback is PRINTED, not swallowed --
        # the exception carries the reason AND the consequence (which `.rows` file was not
        # rewritten), and the process exits non-zero. A producer that dies and exits 0 is the
        # worse shape, because the file it writes stays at its old bytes and nothing says so.
        traceback.print_exc()
        print("  DEAD (5): no census was measured and no table was written", file=sys.stderr)
        return 5
    if a.only:
        rows = {k: v for k, v in rows.items() if a.only in k}
    out = []
    for i, (rel, meta) in enumerate(sorted(rows.items()), 1):
        r = census_one(rel, meta)
        out.append(r)
        print(f"  [{i:3}/{len(rows)}] {r['verdict']:24} {rel}  "
              f"rows={r.get('rows')} sites={r.get('sites')} floor={r.get('floor')} "
              f"{r.get('seconds', 0)}s", file=sys.stderr, flush=True)
    elapsed = time.time() - t0
    peak = peak_child_mib()
    code, why = verdict_of(out)
    if a.rss:
        print(f"  oracles {len(out)}  wall {elapsed:.1f}s  peak child RSS {peak:.0f} MiB")
        return code
    summarise(out, d)
    text = table(out)
    if a.only:
        # `--only` MUST NOT WRITE `REPORT`. MEASURED: a seed-stability check ran
        # `--only wk-` three times and left `gates/oracleblind.rows` holding **4 lines** in place of
        # the population's **99**, with no error and no exit change. A filter that narrows the
        # answer and still overwrites the answer is a census that can be read wrong with no row to
        # notice, which is the whole defect this file exists to end. `--only` prints to stdout and
        # says the table was not written.
        print(text, end="")
        print(f"  --only {a.only}: {len(out)} row(s) to stdout; {REPORT.relative_to(ROOT)} NOT "
              f"written (a filtered run must not overwrite the population's table)", file=sys.stderr)
    else:
        if out:
            REPORT.write_text(text)
            print(f"  sha256 {hashlib.sha256(text.encode()).hexdigest()[:16]}  "
                  f"({len(out)} rows -> {REPORT.relative_to(ROOT)}, {len(text)} bytes)")
        else:
            # AN EMPTY POPULATION MUST NOT OVERWRITE A TABLE THAT MEASURED SOMETHING. `verdict_of`
            # answers DEAD (5) for it, and the file keeps the bytes of the last run that HAD a
            # population: a table of zero rows is indistinguishable from a table that was never
            # written, and the second is the one a reader would take for a fresh answer.
            print(f"  population is EMPTY: {REPORT.relative_to(ROOT)} NOT written; it still holds "
                  f"the bytes of an earlier run that measured something", file=sys.stderr)
    print(f"  wall {elapsed:.1f}s   peak child RSS {peak:.0f} MiB")
    print(f"  {why}")
    if a.report:
        print("  --report: rc never charged")
        return 0
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))