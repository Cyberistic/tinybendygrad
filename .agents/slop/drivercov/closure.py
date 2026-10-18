"""THE EXECUTION CLOSURE OF THE CORPUS RUN, DISCOVERED BY AST -- NOT BY A HAND LIST.

Doctrine 1: an instrument that cannot see its population cannot be wrong, because it cannot be
anything. So this walks the AST of the run's entry point and every file it can reach by
(a) an argv literal handed to `subprocess`, (b) an `importlib.util.spec_from_file_location`
path argument, (c) a local `import`/`from`, (d) a `runpy`/`exec` of a path, (e) a PATHLIT that
is a string literal naming a file in the repo.

It EXECUTES NOTHING. `ast.parse` only. No `bend`, no tinygrad import, no corpus loop.

WHAT THIS CANNOT SEE, STATED UP FRONT RATHER THAN DISCOVERED LATE:
  * a path assembled from pieces at runtime (`str(x) + "/y.py"`) -- reported as `DYNAMIC`, not
    silently dropped, so the population is `SEEN` and the misses are `UNKNOWN`.
  * a `sh -c "..."` string whose command is only visible in a shell file -- those shell files
    are themselves scanned.
  * THE COMPILER. `bin/bend` is a SHELL file; its target is not in its text as a repo path.
    `binbendscan` handles that separately.
"""
import ast, os, sys, json

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

def rel(p):
    try:
        return os.path.relpath(p, ROOT).replace(os.sep, "/")
    except ValueError:
        return p

def resolve(base_dir, lit):
    """A string literal -> a repo path, if it names one. `None` if it names no file."""
    if not isinstance(lit, str) or "\n" in lit:
        return None
    cands = [lit, os.path.join(base_dir, lit), os.path.join(ROOT, lit)]
    for c in cands:
        c = os.path.normpath(c)
        # `isfile`, not `exists`: `GCMP_REPO = "."` and `cwd=ROOT` both resolve to the repo ROOT,
        # and admitting the ROOT as a member of its own closure prints `.` as if it were an input.
        if c.startswith(ROOT) and os.path.isfile(c):
            return c
    return None

def consts(tree):
    """Module-level `NAME = "string"` bindings, so `[PY, GCMP, *args]` is readable.

    `differ.py:44` writes `PY, GCMP = ".venv/bin/python", ".agents/slop/graphcmp.py"`, so
    WITHOUT this the closure saw `bin/bend` (a literal argv) and MISSED the whole driver
    family. A closure instrument that only sees literals would have reported the truth as
    3 files and called it a result.
    """
    out = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        # `PY, GCMP = "a", "b"` puts a TUPLE in `targets[0]`, so an `isinstance(..., ast.Name)`
        # guard here silently drops every paired constant -- which is exactly how this
        # instrument first reported the closure as THREE FILES and missed the driver family.
        tgt = node.targets[0]
        names = ([tgt.id] if isinstance(tgt, ast.Name)
                 else [t.id for t in tgt.elts if isinstance(t, ast.Name)] if isinstance(tgt, ast.Tuple) else [])
        if not names:
            continue
        if isinstance(node.value, ast.Tuple):
            vals = [strlit(e) for e in node.value.elts]
            if all(v is not None for v in vals):
                out.update(dict(zip(names, vals)))
        elif isinstance(node.value, (ast.Constant, ast.BinOp, ast.Call)):
            # `BEND_DBG = SLOP / "graphcmp-dbg.bend"` is a PATH EXPRESSION, not a string literal,
            # and `probe = Path(".agents/slop/graphcmp-empty.bend")` is a CALL. Folding only
            # `ast.Constant` hid BOTH bend fixtures -- the second and third drivers of the run --
            # and reported a population with a hole in it. A constant folder that folds `"a"` and
            # not `ROOT / "a"` or `Path("a")` is not folding.
            v = strlit(node.value)
            if v is not None:
                out[names[0]] = v
    return out

def strlit(node, K=None):
    """The literal, if this node IS a string constant, a plain list/tuple of them, or a
    `*args` splat in a list (whose own elements are constants)."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name) and K and node.id in K:
        return K[node.id]
    if isinstance(node, (ast.List, ast.Tuple)):
        out = []
        for e in node.elts:
            if isinstance(e, ast.Starred):
                v = strlit(e.value, K)
                if v is None:
                    continue
                out += [v] if isinstance(v, str) else v
                continue
            v = strlit(e, K)
            if v is None:
                continue
            out.append(v)
        return out
    # `ROOT / "checks/devpin.py"` and `Path("gates/gatekit.py")`. WITHOUT this arm the closure
    # MISSES `devpin.py` and `gatekit.py` -- and `devpin.py` IS a declared substrate input, so an
    # instrument that cannot see it will report "uncovered" for a file the digest pins. Two
    # instruments disagreeing about one population is the finding; the fix is to see it, not to
    # pick the friendlier answer.
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        l, r = strlit(node.left, K), strlit(node.right, K)
        if l and r:
            return f"{l}/{r}"          # `REPO / "bin" / "bend"` folds to `bin/bend`, not to `bin`
        return r or l
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in ("Path", "pathlib") and node.args:
        return strlit(node.args[0], K)
    # `str(BEND_DBG)` -- graphcmp.py:3021 is `subprocess.run([str(BEND), str(BEND_DBG)], ...)`,
    # the ONE call that runs the SECOND bend driver. Unwrapping `str(...)` is what makes
    # `graphcmp-dbg.bend` a member of the population; without it the census would report the dbg
    # lane as unrun, which is the exact claim the dbg artifact `D8b-*` exists to support.
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "str" and node.args:
        return strlit(node.args[0], K)
    # `probe or BEND_PROBE`: the default of `a or b` is `b`, and that is the half that names a
    # file. Taking the LAST operand is the only reading that is a path rather than a variable.
    if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.Or) and node.values:
        return strlit(node.values[-1], K)
    return None

SUBPROC = {"run", "check_output", "check_call", "Popen", "call"}

def edges(path):
    """(kind, target_path_or_None, detail) for every way `path` can reach another repo file."""
    src = open(path, encoding="utf-8", errors="replace").read()
    try:
        tree = ast.parse(src, filename=path)
    except SyntaxError as e:
        return [("SYNTAXERROR", None, str(e))]
    out = []
    d = os.path.dirname(path)
    K = consts(tree)
    for node in ast.walk(tree):
        # (a) subprocess / runpy with a resolvable argv
        if isinstance(node, ast.Call):
            fn = node.func
            name = fn.attr if isinstance(fn, ast.Attribute) else (fn.id if isinstance(fn, ast.Name) else "")
            base = fn.value.id if isinstance(fn, ast.Attribute) and isinstance(fn.value, ast.Name) else ""
            if (base, name) in {("subprocess", m) for m in SUBPROC} or \
               name in {"run_path", "run_module"} and base == "runpy":
                argv = strlit(node.args[0], K) if node.args else None
                if isinstance(argv, list):
                    for a in argv:
                        t = resolve(d, a)
                        if t:
                            out.append(("SUBPROCESS", t, " ".join(a for a in argv if isinstance(a, str))[:160]))
                elif isinstance(argv, str):
                    out.append(("SUBPROCESS-DYNAMIC", None, argv[:160]))
            # (b) importlib.util.spec_from_file_location("name", PATH)
            if name == "spec_from_file_location" and len(node.args) >= 2:
                p = strlit(node.args[1], K)
                if isinstance(p, str):
                    t = resolve(d, p)
                    out.append(("IMPORTLIB", t, p) if t else ("IMPORTLIB-DYNAMIC", None, p))
        # (c) local import / from
        if isinstance(node, ast.Import):
            for a in node.names:
                out.append(("IMPORT", a.name, a.name))
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                out.append(("IMPORT", node.module, f"from {node.module}"))
            if node.level:  # relative: `from . import x` / `from .y import z`
                out.append(("RELIMPORT", "." * node.level + (node.module or ""), "." * node.level))
    # (f) CALLS TO THIS MODULE'S OWN FUNCTIONS with a resolvable path ARGUMENT. `differ.py`'s
    # `capture(out, ".agents/slop/graphcmp-oracle.py")` and `gc("emit", ...)` hand the driver
    # paths as ARGUMENTS, not as argv, so the subprocess rule alone sees only `bin/bend` and
    # reports a 3-file closure that runs 6 Python drivers. A closure that cannot see its own
    # helper calls is not a closure.
    local = {n.name for n in ast.walk(tree)
             if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in local:
            for a in list(node.args) + [k.value for k in node.keywords]:
                v = strlit(a, K)
                for lit in ([v] if isinstance(v, str) else (v or [])):
                    t = resolve(d, lit)
                    if t:
                        out.append(("LOCALCALL", t, f"{node.func.id}(...{lit}...)"))
    return out

#: OUTPUT TREES. An artifact a run WRITES is not an input it READS, and `capture("D0.txt", ...)`
#: resolves its first argument against a `runs/graphcmp/D/` left by a previous run -- so without
#: this the closure fills with the run's own leftovers and looks like a much bigger population
#: than it is. Classification by DIRECTORY SHAPE, which is a walk of the tree's own write sites.
OUTPUT_PREFIXES = ("runs/", "gates/artifacts/")

#: WHAT GETS PARSED. An ALLOWLIST, not a denylist: the first version denied `.bend`/`.js`/`.md`
#: and then handed `.venv/bin/python` to `ast.parse`, which raised `source code string cannot
#: contain null bytes`. A denylist is a guess about what is text; an allowlist is a claim about
#: what this instrument can read, and it fails on the UNKNOWN member rather than the known one.
TRAVERSABLE = (".py", ".sh")

def closure(roots):
    """BFS from roots over file-reachable edges only. Every reached file is REPORTED whatever its
    extension; only `.py`/`.sh` are PARSED (see `TRAVERSABLE`)."""
    seen, order, dyn = set(), [], []
    q = [os.path.normpath(r) for r in roots]
    while q:
        p = q.pop(0)
        rp = rel(p)
        if rp in seen:
            continue
        seen.add(rp)
        order.append(rp)
        if not os.path.isfile(p) or not p.endswith(TRAVERSABLE):
            continue
        for kind, tgt, detail in edges(p):
            if kind.endswith("DYNAMIC"):
                dyn.append((rp, kind, detail))
                continue
            if tgt and kind in ("SUBPROCESS", "IMPORTLIB", "LOCALCALL"):
                tr = rel(tgt)
                if tr.startswith(OUTPUT_PREFIXES):
                    continue
                q.append(tgt)
    return order, dyn

if __name__ == "__main__":
    roots = sys.argv[1:]
    order, dyn = closure(roots)
    print(json.dumps({"closure": order, "dynamic_sites": dyn}, indent=1))