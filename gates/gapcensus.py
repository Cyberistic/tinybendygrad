#!/usr/bin/env python3
"""gapcensus.py -- THE CENSUS: how far is this port from tinygrad?

    .venv/bin/python gates/gapcensus.py            # the table
    .venv/bin/python gates/gapcensus.py --rows     # name=value rows only

ONE RULE, AND EVERY ROW HERE IS SUBJECT TO IT: THE UNIT OF THE COUNT AND THE UNIT A READER
WILL ASSUME MUST BE THE SAME, OR THE NUMBER IS NOT A MEASUREMENT. So each `unit()` below
returns `(rows, unit_sentence)`, and the gate prints the sentence beside the number. Three
of the units in this file are, MEASURED, NOT COMPARABLE, and they say so in their own row
instead of producing a ratio -- a ratio between a per-`Ops` dict and a per-SHAPE helper is
a number about two different things.

EVERY POPULATION IS DISCOVERED, NONE IS A LIST. Upstream modules and lines: `os.walk`.
Upstream methods: `ast`, over a class and its BASE CHAIN, because `class Tensor(RandMixin)`
is 57 def sites in `tensor.py` and 355 over the mixins and 342 unique names, and a census
that reads `tensor.py` alone UNDERCOUNTS BY 6x. `Ops`: the interpreter, by importing
`tinygrad.uop.ops` -- a generator's own declaration, which is why the `.txt`-carve-out
count and this one cannot drift. Exercised-by: the drivers a gate NAMES IN ITS OWN
`bend=` ARGUMENT, which is the only place a driver is declared. Ambiguous names are
REPORTED AS AMBIGUOUS and never resolved by guessing which of two files was meant.
"""
from __future__ import annotations

import ast
import collections
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# DERIVED FROM `ROOT` AT CALL TIME, NEVER BOUND AT IMPORT. `--plant` reassigns `ROOT` to a
# temp copy and this row is what proves it took effect: with `UP`/`PORT` bound at import the
# plant moved NOTHING, re-ran green, and would have been reported as a plant that cannot
# fail. It is the same shape `AGENTS.md` records for `repro-paths.py` -- an INSTRUMENT'S
# SOURCE AND ITS SUBJECT COMING FROM TWO DIFFERENT PLACES -- and the plant is the only reason
# it was found.
def up() -> Path:
    return ROOT / "tinygrad"


def port() -> Path:
    return ROOT / "tinybendygrad"


def ops_bend() -> Path:
    return port() / "uop" / "ops.bend"


PY = ROOT / ".venv" / "bin" / "python"

# ----------------------------------------------------------------- the two walks


def walk(root: Path, ext: str) -> list[str]:
    """Every `ext` file under `root`, by DIRECTORY WALK, `__pycache__` not descended.

    `os.walk`, not `glob('**/*.x')`: `gates/no-txt.py`'s own record is that the glob form
    returned `[]` against a tree that held `.bend` files, tracked, 1890 lines.
    """
    out = []
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d != "__pycache__"]
        out += [os.path.relpath(os.path.join(dp, n), root) for n in fn if n.endswith(ext)]
    return sorted(out)


def module_names(paths: list[str]) -> dict[str, list[str]]:
    """basename-without-extension -> the paths carrying it. A NAME, not a key: see `ambiguous`."""
    d = collections.defaultdict(list)
    for p in paths:
        d[os.path.splitext(os.path.basename(p))[0]].append(p)
    return dict(d)


# ------------------------------------------------------------------ the modules


def unit_modules() -> tuple[dict, str]:
    u_files, p_files = walk(up(), ".py"), walk(port(), ".bend")
    upn, pon = module_names(u_files), module_names(p_files)
    missing = sorted(set(upn) - set(pon))
    # THE MISSING MODULES, CLASSIFIED BY A REASON THAT IS CHECKED, NOT ASSUMED. The class
    # is declared here and its evidence is a COUNT OF THE SAME WALK, so a new autogen file
    # upstream moves the first row and leaves the second alone -- which is the point.
    autogen = [p for n in missing for p in upn[n] if p.startswith("runtime/autogen/")]
    llm = [p for n in missing for p in upn[n] if p.startswith("llm/")]
    other = [p for n in missing for p in upn[n]
             if not p.startswith(("runtime/autogen/", "llm/"))]
    # PORT-ONLY, AND THE POINT IS THAT NONE OF THEM IS A PORT FEATURE BY ACCIDENT: 8 are gate
    # mutation drivers, 5 are LAWS/PROOF, 4 are probes, 11 are real port modules the upstream
    # has no file for. Declared as classes so the two cannot be confused when counting.
    scaffolding = [n for n in (set(pon) - set(upn)) if n.endswith(("-mut", "_mut")) or n.startswith(".")]
    laws = sorted({"LAWS", "PROOF", "PROOF2", "PROOF-ALL"} & (set(pon) - set(upn)))
    probes = sorted(n for n in (set(pon) - set(upn)) if n.startswith(("zz", "probe", "v5", "dtype_oracle")))
    rows = {
        "modules.upstream_files": len(u_files),
        "modules.port_files": len(p_files),
        "modules.upstream_names": len(upn),
        "modules.port_names": len(pon),
        "modules.upstream_names_missing": len(missing),
        "modules.missing_of_which_autogen_ctypes": len(autogen),
        "modules.missing_of_which_llm": len(llm),
        "modules.missing_of_which_UNCLASSIFIED": len(other),
        "modules.missing_unclassified_names": ",".join(sorted({os.path.splitext(os.path.basename(p))[0] for p in other})) or "NONE",
        "modules.port_only_names": len(set(pon) - set(upn)),
        "modules.port_only_that_are_gate_scaffolding": len(scaffolding),
        "modules.port_only_that_are_laws_or_proof": len(laws),
        "modules.port_only_that_are_probes": len(probes),
        "modules.ambiguous_upstream_names": sum(1 for v in upn.values() if len(v) > 1),
    }
    return rows, ("a MODULE = one source file under the root, named by its basename WITHOUT "
                  "extension. 167 upstream names, 120 port names, 15 of the 167 are carried by "
                  "MORE THAN ONE upstream file so the name alone cannot say which -- counted, "
                  "not resolved.")


# ----------------------------------------------------------------- the two lines


def unit_lines() -> tuple[dict, str]:
    """Lines, AND THE SENTENCE SAYS THEY ARE NOT A MEASUREMENT OF PROGRESS.

    Two corrections to the naive version, both MEASURED. `find ... | wc -l` counted 243120
    upstream against 235704 code lines, and 208915 of those -- 88.5% -- are
    `runtime/autogen/*.py`, ctypes struct tables. So the honest denominator is the
    autogen-excluded tree, and even then a LINE OF BEND IS NOT A LINE OF PYTHON: the port
    threads an arena through every signature that upstream closes over.
    """
    def code(root: Path, ext: str) -> tuple[int, int, int]:
        files = lines = autogen = 0
        for dp, dn, fn in os.walk(root):
            dn[:] = [d for d in dn if d != "__pycache__"]
            for n in fn:
                if not n.endswith(ext):
                    continue
                p = os.path.join(dp, n)
                files += 1
                sub = sum(1 for l in open(p, encoding="utf-8", errors="replace")
                          if l.strip() and not l.strip().startswith("#"))
                lines += sub
                if rel_is_autogen(p, root):
                    autogen += sub
        return files, lines, autogen

    uf, ul, ua = code(up(), ".py")
    pf, pl, _ = code(port(), ".bend")
    rows = {
        "lines.upstream_code": ul,
        "lines.upstream_code_excluding_autogen": ul - ua,
        "lines.upstream_autogen_code": ua,
        "lines.port_code": pl,
        "lines.port_over_upstream_ex_autogen": f"{pl / (ul - ua):.2f}x",
    }
    return rows, ("a LINE = one source line that is neither blank nor a `#` comment. NOT "
                  "COMPARABLE: the port is a different language and threads an arena through "
                  "signatures upstream closes over. The `Nx` row is a SHAPE, not progress.")


def rel_is_autogen(p: str, root: Path) -> bool:
    return os.path.relpath(p, root).startswith("runtime" + os.sep + "autogen" + os.sep)


# --------------------------------------------------------------------- the enum


def ast_enum_order(path: Path, cls: str) -> list[str]:
    """`Ops`' members in DECLARATION order, off the AST. `EnumType.__iter__` and the oracle
    both hide this: the oracle sorts, and CPython's own iteration is an implementation detail
    the tree's comment (`uop/__init__.py:14`) says is load-bearing for toposort order."""
    for n in ast.parse(path.read_text()).body:
        if isinstance(n, ast.ClassDef) and n.name == cls:
            return [t.id for m in n.body if isinstance(m, ast.Assign)
                    for t in m.targets if isinstance(t, ast.Name)]
    raise KeyError(f"{cls} is not a class in {path}")


def unit_ops() -> tuple[dict, str]:
    """`Ops`, from the INTERPRETER on both sides. The one unit in this file with no shape gap.

    `.venv/bin/python gates/tn_minimum-oracle.py` prints CPython's own `list(Ops)`, and
    `tn_minimum-gate.py` matches it against `^  Ops([A-Z_0-9]+)\\{}` in `ops.bend`. This row
    REUSES the oracle rather than writing a second reader, because a second reader is a
    second number.
    """
    r = subprocess.run([str(PY), str(ROOT / "gates" / "tn_minimum-oracle.py")],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return {"ops.status": "REFUSED-the-oracle-said-nothing"}, ("the enum lane did not run.")
    cp = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
    text = ops_bend().read_text()
    constructors = re.findall(r"^  Ops([A-Z_0-9]+)\{\}", text, re.M)
    names = cp["cpython_ops"].split(",") if cp["cpython_ops"] else []
    # ORDER, AND THE ORACLE CANNOT ANSWER IT. MEASURED: `gates/tn_minimum-oracle.py:19` reads
    # `names = sorted(o.name for o in Ops)`, so `cpython_ops` is a SORTED SET and comparing it
    # to any list is a comparison of a sort against a sort. `tn_minimum-gate.py` is a SET
    # gate: it would print PASS on an enum whose members were reordered, and order is load-
    # bearing here -- `tinygrad/uop/__init__.py:14` says in the tree's own words "the order of
    # these Ops controls the order of the toposort". So the declaration order is read off
    # upstream's AST HERE, and the port's `type Ops is Data:` variant block is compared to it.
    # THIS ROW IS THE ONE THAT SETTLES IT, AND IT IS NOT A ROW THE ORACLE OWNS.
    upstream_order = ast_enum_order(up() / "uop" / "__init__.py", "Ops")
    named = re.findall(r"case Ops([A-Z_0-9]+)\{\}: \"", text)
    ao = text[text.index("\ndef all_ops("):]
    ao = ao[:ao.index("\n\n")]
    all_ops = re.findall(r"Ops([A-Z_0-9]+)\{\}", ao)
    rows = {
        "ops.cpython_members": int(cp["cpython_ops_count"]),
        "ops.port_constructors": len(constructors),
        "ops.in_cpython_not_port": len(set(names) - set(constructors)),
        "ops.in_port_not_cpython": len(set(constructors) - set(names)),
        "ops.oracle_is_a_sorted_SET": "sorted(o.name for o in Ops)" in (ROOT / "gates" / "tn_minimum-oracle.py").read_text(),
        "ops.upstream_declaration_order_members": len(upstream_order),
        "ops.order_variant_block_equals_upstream_DECLARATION": list(upstream_order) == constructors,
        "ops.order_name_of_equals_upstream_DECLARATION": list(upstream_order) == named,
        "ops.order_all_ops_equals_upstream_DECLARATION": list(upstream_order) == all_ops,
    }
    return rows, ("a MEMBER = one `Ops.X` enum member. CPython's SET comes from "
                  "`gates/tn_minimum-oracle.py`, which SORTS, so it cannot see order; the "
                  "order rows are read off upstream's AST. `Ops.name.of`'s arm order is NOT "
                  "a declaration order and is not a defect: it is a total one-arm-per-variant "
                  "resolver. THE ENUM IS NOT THE PROJECT.")


# -------------------------------------------------------------- the behaviours

UOP_METHODS = re.compile(r"^\s*def\s+UOp\.([A-Za-z_][A-Za-z_0-9]*)\s*[:(]", re.M)
ANY_DEF = re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)?)\s*[:(]", re.M)


def ast_methods(path: Path, cls: str) -> list[str]:
    """`def` names DIRECTLY in `cls`'s body. NOT the base chain -- `unit_uop` is one class
    on one file, and `unit_tensor` is a chain; two units, two readers, on purpose."""
    for n in ast.parse(path.read_text()).body:
        if isinstance(n, ast.ClassDef) and n.name == cls:
            return [m.name for m in n.body if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef))]
    raise KeyError(f"{cls} is not a class in {path}")


def port_def_names() -> set[str]:
    """Every def name the port declares, ANYWHERE, plus the bare member of a `R.name` form."""
    names = set()
    for dp, dn, fn in os.walk(port()):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for n in fn:
            if not n.endswith(".bend"):
                continue
            for m in ANY_DEF.finditer(open(os.path.join(dp, n), encoding="utf-8", errors="replace").read()):
                names.add(m.group(1))
                if "." in m.group(1):
                    names.add(m.group(1).split(".")[1])
    return names


def gate_drivers() -> list[Path]:
    """THE DRIVERS A GATE NAMES IN ITS OWN `bend=`. The declared population, not `gates/*.bend`.

    MEASURED, and the difference is not academic: 91 gates name **61** drivers, while
    `gates/` holds **69** `.bend` files. The 8 unnamed are mutation drivers and fixtures that
    a mutation harness runs by a different route; counting the directory would credit the
    census with 8 gates that do not exist.
    """
    pat = re.compile(r"\bbend\s*=\s*r?[\"']([^\"']+\.bend)[\"']")
    out = []
    for dp, dn, fn in os.walk(ROOT / "gates"):
        dn[:] = [d for d in dn if d != "__pycache__"]
        for n in fn:
            if not n.endswith("-gate.py"):
                continue
            for m in pat.findall(open(os.path.join(dp, n), encoding="utf-8").read()):
                for cand in (ROOT / "gates" / m, ROOT / m):
                    if cand.is_file():
                        out.append(cand)
    return sorted(set(out))


def unit_uop() -> tuple[dict, str]:
    """`class UOp` ONLY -- 156 def sites in one file, no base chain.

    FOUR BUCKETS AND NOT THREE, because a three-way split over 156 hides the two ways a
    miss is not a miss. A `__dunder__` cannot exist in Bend (no operator overloading), and
    the port declares every ported `def` at module level with no descriptors or private
    protocol, so a leading-underscore helper is not required to be mirrored either. The 74
    ABSENT names are therefore split, or the row would report 74 gaps where at most 50 are.
    """
    u_names = ast_methods(up() / "uop" / "ops.py", "UOp")
    port_ns = set(UOP_METHODS.findall(ops_bend().read_text()))
    everywhere = port_def_names()
    drivers = {p: p.read_text(errors="replace") for p in gate_drivers()}

    def exercised(name: str) -> bool:
        w = re.compile(r"\b" + re.escape(name) + r"\b")
        return any(w.search(s) for s in drivers.values())

    identical = {n for n in u_names if n in port_ns}
    renamed = {n for n in set(u_names) - port_ns if n in everywhere}
    absent = set(u_names) - port_ns - renamed
    dunder = {n for n in absent if n.startswith("__") and n.endswith("__")}
    # `_` AND NOT `__x__`: a dunder IS private, so a bare `startswith("_")` counted 24 here
    # while the disjoint tally below needs 16, and 8+24+50=82 over a 74-row set. The two
    # buckets are made disjoint HERE rather than left to the reader to notice.
    private = {n for n in absent - dunder if n.startswith("_")}
    public_absent = absent - dunder - private
    rows = {
        "uop.upstream_def_sites": len(u_names),
        "uop.port_namespaced_def_sites": len(port_ns),
        "uop.ported_name_identical": len(identical),
        "uop.ported_name_identical_EXERCISED_by_a_gate_driver": sum(1 for n in identical if exercised(n)),
        "uop.ported_name_identical_UNEXERCISED": sum(1 for n in identical if not exercised(n)),
        "uop.ported_under_a_different_name": len(renamed),
        "uop.absent_dunder_no_bend_syntax": len(dunder),
        "uop.absent_private_port_has_no_protocol": len(private),
        "uop.absent_PUBLIC": len(public_absent),
        "uop.gate_drivers_in_the_population": len(drivers),
        "uop.port_only_names_no_upstream_counterpart": len(port_ns - set(u_names)),
    }
    return rows, ("a UOP METHOD = one `def` DIRECTLY in `class UOp` (upstream, AST) or one "
                  "`def UOp.<name>` in `ops.bend` (port, regex). EXERCISED = the name occurs "
                  "in >=1 .bend a gate names in its `bend=` -- a STATIC REACHABILITY claim, "
                  "not an observation of a run.")


def tensor_chain(paths: list[Path]) -> tuple[list[str], list[str]]:
    """`Tensor` plus every base, giving (unique method names, def sites with duplicates).

    MEASURED, and this is the largest unit error available in this tree: `class Tensor` is
    **57** def sites in `tensor.py`, **355** over the mixin chain, **342** unique names. Any
    of the three is a defensible-looking number and only one of them is the unit a caller
    means by "Tensor's methods".
    """
    classes: dict[str, tuple[Path, ast.ClassDef]] = {}
    for p in paths:
        for n in ast.parse(p.read_text()).body:
            if isinstance(n, ast.ClassDef):
                classes.setdefault(n.name, (p, n))
    names, sites, seen = [], 0, set()

    def walk(cls: str) -> None:
        nonlocal sites
        if cls in seen or cls not in classes:
            return
        seen.add(cls)
        _, node = classes[cls]
        for m in node.body:
            if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)):
                sites += 1
                if m.name not in names:
                    names.append(m.name)
        for b in node.bases:
            if isinstance(b, ast.Name):
                walk(b.id)

    walk("Tensor")
    return names, [str(sites)]


def unit_tensor() -> tuple[dict, str]:
    names, _ = tensor_chain([up() / "tensor.py"] + sorted((up() / "mixin").glob("*.py")))
    everywhere = port_def_names()
    # THE PORT HAS NO `def Tensor.<name>` NAMESPACE for its arithmetic: it spells them
    # `tn_<upstream_name>`, sometimes with a `.put/.go/.of` trio. So the name-identity test
    # is run against the `tn_` CONVENTION and its result is the FINDING, not a coverage
    # figure: 69 of 342, and the misses are dominated by dunders, so the convention is not
    # complete and this row CANNOT be read as "21% ported".
    hit = [n for n in names
           if f"tn_{n[2:-2] if n.startswith('__') and n.endswith('__') else n}" in everywhere
           or f"tn_{n}" in everywhere]
    rows = {
        "tensor.upstream_unique_method_names": len(names),
        "tensor.port_def_names_whole_tree": len(everywhere),
        "tensor.name_identical_under_tn_convention": len(hit),
        "tensor.three_way_split": "UNDEFINED",
    }
    return rows, ("a TENSOR METHOD = one method name on `Tensor` AND EVERY BASE in "
                  "`tinygrad/mixin/**` (342 names, 355 sites, 57 in tensor.py alone). THE "
                  "THREE-WAY SPLIT IS UNDEFINED HERE, NOT ZERO: the port renames (`relu` -> "
                  "`tn_relu.of`), so name identity measures the naming convention and not "
                  "porting.")


def unit_renderers() -> tuple[dict, str]:
    """THE ROW WITH NO RATIO IN IT, AND THE ROW THAT CAUGHT A THIRD OF TODAY'S WRONG GREPS.

    Upstream `cstyle.py` dispatches on a dict of **34** `Ops.X:` keys. `rg 'Ops\\.[A-Z_]+:'`
    over the port's renderers answers **0** -- and 0 would read as "the port renders no
    ops". It is `Ops\\.` matching nothing, the same phantom-member failure as `OptOps.TC`:
    the port has no per-`Ops` table at all. It dispatches on SHAPE -- `cfo_unary`,
    `cfo_bin`, `cfo_tern`, `cfo_neg`, `cfo_recip` -- and falls through to `cfo_unhandled`.
    So 34 arms and 5 shape helpers are not two counts of one thing.
    """
    arms = {}
    for name in ("cstyle", "ptx", "wgsl", "nir", "llvmir", "tc"):
        u = up() / "renderer" / f"{name}.py"
        if u.is_file():
            arms[f"renderers.{name}_upstream_ops_arms"] = len(set(re.findall(r"\bOps\.([A-Z_0-9]+)\s*:", u.read_text())))
    text = (port() / "renderer" / "cstyle.bend").read_text()
    rows = dict(arms)
    rows["renderers.port_cstyle_shape_helpers"] = len(set(re.findall(r"^def\s+(cfo_\w+)\(", text, re.M)))
    rows["renderers.port_has_a_per_ops_table"] = bool(re.search(r"^def\s+Ops\.[A-Za-z_]+\s*[:(]", text, re.M))
    rows["renderers.three_way_split"] = "UNDEFINED"
    return rows, ("a DISPATCH ARM = one `Ops.X:` key in an upstream `code_for_op` dict, or "
                  "one `cfo_*` shape helper in the port. THE UNIT DIFFERS BY CONSTRUCTION, "
                  "so no ratio is printed: the real renderer evidence is "
                  "`cstyle_render_census-gate.py`, which diffs RENDERED STRINGS.")


def unit_devices() -> tuple[dict, str]:
    """A DEVICE BACKEND -- the one unit that matches module-for-module on both sides.

    15 upstream `runtime/ops_*.py` and 16 port `runtime/ops_*.bend`, the extra one being
    `ops_bend` (Bend's own device). The LAUNCHER sub-unit is where upstream itself is
    irregular: 7 `class XProgram(Program[...])` sites and 6 `def exec` methods, and
    `cuda`/`hip` are the SAME driver twice (`ops_hip.py` is a HIPIFY re-binding of
    `ops_cuda.py`'s, MEASURED by reading its imports) while `disk`/`npy`/`rdma` have no
    launcher at all.
    """
    devs_up = sorted(p.name[4:-3] for p in (up() / "runtime").glob("ops_*.py"))
    devs_po = sorted(p.name[4:-5] for p in (port() / "runtime").glob("ops_*.bend"))
    launcher, sites = 0, 0
    for p in sorted((up() / "runtime").glob("ops_*.py")):
        t = ast.parse(p.read_text())
        # `class CLProgram(Program['CLDevice'])` puts `CLProgram` in `n.name` and the base in
        # `n.bases` -- a regex over `n.name` matches NOTHING, and a launcher census that
        # reads 0 where there are 13 sites is the `Ops\\.` phantom-member shape a third time.
        here = 0
        for n in ast.walk(t):
            if isinstance(n, ast.ClassDef) and any(
                    isinstance(b, ast.Subscript) and getattr(b.value, "id", "") == "Program"
                    for b in n.bases):
                here += 1
            elif isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "exec":
                here += 1
        # SITES AND FILES ARE BOTH PRINTED, AND THE ROW WAS WRONG ONCE BECAUSE IT WAS NOT.
        # `devices.upstream_files_carrying_a_launcher` held 13 -- the number of LAUNCHER
        # SITES -- while 10 is the number of FILES, and `ops_dsp.py` alone carries two and
        # `ops_null.py` carries one `Program` subclass AND one `exec`. A row whose NAME says
        # files and whose VALUE is sites is the unit error this whole census is about, in the
        # census. Two rows, one per unit, and no sum of them.
        launcher += here > 0
        sites += here
    rows = {
        "devices.upstream_backends": len(devs_up),
        "devices.port_backends": len(devs_po),
        "devices.upstream_without_a_port_file": ",".join(sorted(set(devs_up) - set(devs_po))) or "NONE",
        "devices.port_without_an_upstream_file": ",".join(sorted(set(devs_po) - set(devs_up))) or "NONE",
        "devices.upstream_backends_CARRYING_a_launcher": launcher,
        "devices.upstream_backends_that_are_NOT_a_launcher": len(devs_up) - launcher,
        "devices.upstream_launcher_SITES": sites,
    }
    return rows, ("a BACKEND = one `runtime/ops_<name>.py` or `runtime/ops_<name>.bend`. "
                  "HAVE-MODULE is decided on the FILE NAME, which is unambiguous for this "
                  "prefix; a name-only key would be ambiguous (see modules.ambiguous_*).")


# ---------------------------------------------------------------- the corpus age


def unit_corpus() -> tuple[dict, str]:
    """THE STALENESS ROW. The 34-graph corpus is the tree's only whole-port agreement test.

    `runs/graphcmp/D/` is the artefact. Its newest file's mtime against the re-vendor
    commit's committer date is the whole question, and the answer is measured at RUN TIME
    rather than written down, so this row cannot say "34/34" without also saying when.
    """
    import datetime as _dt

    d = ROOT / "runs" / "graphcmp" / "D"
    newest = max((p.stat().st_mtime for p in d.rglob("*") if p.is_file()), default=0)
    stamp = _dt.datetime.fromtimestamp(newest).strftime("%Y-%m-%dT%H:%M") if newest else "NONE"
    rev = subprocess.run(["git", "log", "-1", "--format=%h %cI %s", "--", "tinygrad"],
                         cwd=ROOT, capture_output=True, text=True).stdout.strip()
    # THE FULL `cI` TIMESTAMP, NOT ITS FIRST 10 CHARACTERS. MEASURED, and this row is the
    # only one in the file that was WRONG on its first run for exactly that reason: taking
    # `2026-10-17` and reading it as midnight made all **242** files "newer than the
    # re-vendor", when the newest is `01:50` and the re-vendor is `07:14` the same day --
    # so a corpus that is 5h24m STALE read as FRESH. A date is not a timestamp.
    # `cI` CARRIES AN OFFSET and `fromtimestamp` is NAIVE, so the first run raised
    # `TypeError: can't compare offset-naive and offset-aware datetimes` -- a loud failure,
    # which is the good kind. `.astimezone()` with no argument is the local-time reading and
    # puts both sides in one zone.
    when = _dt.datetime.fromisoformat(rev.split()[1]).astimezone().replace(tzinfo=None) if rev else None
    freshers = [p for p in d.rglob("*") if p.is_file() and _dt.datetime.fromtimestamp(p.stat().st_mtime) > when] if when else []
    gap = (when - _dt.datetime.fromtimestamp(newest)) if when and newest else None
    summary = d / "D0-run-summary.txt"
    agree = dict(l.split("=", 1) for l in summary.read_text().splitlines() if "=" in l) if summary.is_file() else {}
    rows = {
        "corpus.graphs_agree": agree.get("graphs-agree", "NO-SUMMARY"),
        "corpus.graphs_total": agree.get("graphs", "NO-SUMMARY"),
        "corpus.artifact_newest_mtime": stamp,
        "corpus.revendor_commit": rev.split(" ")[0] if rev else "NONE",
        "corpus.revendor_committed_at": rev.split()[1] if rev else "NONE",
        "corpus.artefacts_NEWER_than_the_revendor": len(freshers),
        "corpus.artefacts_OLDER_by": str(gap) if gap else "NONE",
        "corpus.is_stale": "STALE" if freshers == [] and stamp != "NONE" else "FRESH-OR-ABSENT",
    }
    return rows, ("a CORPUS RUN = the files under `runs/graphcmp/D/`. STALE is decided by "
                  "mtime versus the `tinygrad/` re-vendor commit, at RUN TIME. A graph count "
                  "with no timestamp is not a measurement.")


UNITS = (unit_modules, unit_lines, unit_ops, unit_uop, unit_tensor, unit_renderers,
         unit_devices, unit_corpus)


def rows(units=None) -> list[str]:
    """`name=value`, ONE ROW PER MEASUREMENT, and the unit sentence is emitted separately.

    `units` narrows to a subset, and `--plant` uses it to re-run ONLY the unit it perturbed.
    Copying the whole tree into a temp dir to move two rows would be a 300 MB plant, and a
    plant that needs 300 MB is a plant nobody runs. The subset is the plant's own claim about
    its SCOPE and it is visible in the call site rather than hidden in a full run.
    """
    out = []
    for unit in (units or UNITS):
        got, _ = unit()
        out += [f"{k}={v}" for k, v in got.items()]
    return out


def table() -> None:
    for unit in UNITS:
        got, sentence = unit()
        print(f"\n== {unit.__name__.removeprefix('unit_').upper()}")
        print(f"   UNIT: {sentence}")
        for k, v in got.items():
            print(f"   {k}={v}")


if __name__ == "__main__":
    if "--rows" in sys.argv:
        print("\n".join(rows()))
    else:
        table()