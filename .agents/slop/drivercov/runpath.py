"""THE CENSUS, AND THE TWO DELIVERABLES' NUMBERS.

DOES NOT RE-DERIVE THE POPULATION: it imports `checks/differ.py` and asks for
`substrate_entries()`, so "in_digest" is the GENERATOR'S OWN ANSWER and not a second walk.

DOES NOT EXECUTE ANYTHING: `ast.parse` only. No `bend`, no `tinygrad` import, no corpus loop.

TWO CLOSURES, because ONE ANSWER IS NOT ENOUGH:
  * `RUN_PATH`  -- file-reachable starting at `cmd_run` and following INTRA-FILE local calls.
    This is what `substrate_digest()`'s bracket (`:695` start, `:991` end) is about, because
    that bracket is taken inside `cmd_run`.
  * `CLI`       -- file-reachable from the file as a whole, i.e. `plant`/`repro`/`snap` too.
    `gates/gatekit.py` and `checks/runs-artifacts.py` live ONLY in this one, and reporting them
    as uncovered drivers would be a false positive: they are not run by `differ.py run`.
"""
import ast, os, sys, json, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "checks"))
import closure as C  # noqa: E402
import differ      # noqa: E402


def funcs_of(path):
    t = ast.parse(open(path, encoding="utf-8", errors="replace").read(), filename=path)
    return {n.name: n for n in ast.walk(t) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}


def calls_in(fn):
    """Names called anywhere inside `fn`'s own body (transitively through its nested defs is NOT
    done: `run()` -> `capture()` is one hop, and one hop is the shape that matters here)."""
    out = set()
    for n in ast.walk(fn):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
            out.add(n.func.id)
    return out


def run_path(root_file, entry="cmd_run"):
    """BFS over (file, function) pairs. A FILE edge leaves the function scope; a CALL edge
    narrows it. This is what separates `cmd_run` from `cmd_snap`."""
    import queue
    q = queue.deque([(C.rel(root_file), entry)])
    seen, edges = set(), []
    while q:
        relf, fn = q.popleft()
        if (relf, fn) in seen:
            continue
        seen.add((relf, fn))
        path = os.path.join(ROOT, relf)
        if not os.path.isfile(path) or not path.endswith(C.TRAVERSABLE):
            continue
        fs = funcs_of(path)
        node = fs.get(fn)
        if node is None:
            continue
        # file-leaving edges from this function's subtree
        for sub in ast.walk(node):
            if isinstance(sub, ast.Call):
                name = sub.func.attr if isinstance(sub.func, ast.Attribute) else (
                    sub.func.id if isinstance(sub.func, ast.Name) else "")
                base = sub.func.value.id if isinstance(sub.func, ast.Attribute) and isinstance(sub.func.value, ast.Name) else ""
                if (base, name) in {("subprocess", m) for m in C.SUBPROC} or \
                   (base == "runpy" and name in {"run_path", "run_module"}):
                    K = C.consts(ast.parse(open(path, encoding="utf-8", errors="replace").read()))
                    argv = C.strlit(sub.args[0], K) if sub.args else None
                    lits = [argv] if isinstance(argv, str) else (argv or [])
                    for lit in lits:
                        t = C.resolve(os.path.dirname(path), lit)
                        if t:
                            tr = C.rel(t)
                            if tr.startswith(C.OUTPUT_PREFIXES):
                                continue
                            edges.append((relf, fn, "SUBPROCESS", tr, " ".join(lits)[:120]))
                            q.append((tr, None))
                elif name == "spec_from_file_location":
                    # args[0] is the MODULE NAME and args[1] is the PATH. Reading args[0] here is
                    # what made `checks/devpin.py` -- a DECLARED substrate input -- invisible to
                    # the run-path walk, and an instrument that cannot see a pinned file will
                    # report it as uncovered.
                    K = C.consts(ast.parse(open(path, encoding="utf-8", errors="replace").read()))
                    p = C.strlit(sub.args[1], K) if len(sub.args) >= 2 else None
                    t = C.resolve(os.path.dirname(path), p) if isinstance(p, str) else None
                    if t and not C.rel(t).startswith(C.OUTPUT_PREFIXES):
                        edges.append((relf, fn, "IMPORTLIB", C.rel(t), str(p)))
                        q.append((C.rel(t), None))
                elif name in fs and name != fn:
                    edges.append((relf, fn, "CALL", f"{relf}::{name}", fn))
                    q.append((relf, name))
        # ARGUMENT-LEVEL file edges, at the CALL SITE. `capture("D0-...txt", ".../graphcmp-oracle.py")`
        # hands the driver path as an ARGUMENT and `capture`'s own body runs
        # `subprocess.run([PY, script])` where `script` is a PARAMETER -- so the argv rule alone
        # resolves to `.venv/bin/python` and the four oracles vanish. A path can be named at a
        # call site as well as in a command line; an instrument that reads only one of the two
        # reports a population smaller than the run's.
        K = C.consts(ast.parse(open(path, encoding="utf-8", errors="replace").read()))
        for sub in ast.walk(node):
            if not (isinstance(sub, ast.Call)
                    and isinstance(sub.func, ast.Name) and sub.func.id in fs):
                continue
            for a in list(sub.args) + [k.value for k in sub.keywords]:
                v = C.strlit(a, K)
                for lit in ([v] if isinstance(v, str) else (v or [])):
                    # PATH SHAPE, required for an ARGUMENT edge. `run(..., "emit", "--side",
                    # "bend", ...)` passes the SIDE NAME `"bend"`, and `checks/bend` IS A REAL
                    # 153-BYTE FILE -- so without this the closure invents an eighth driver that
                    # nothing runs. A bare token is a token; a path has a separator or an
                    # extension. This is the basename-shape trap, met in the argument position.
                    if "/" not in lit and "." not in lit:
                        continue
                    t = C.resolve(os.path.dirname(path), lit)
                    if t and not C.rel(t).startswith(C.OUTPUT_PREFIXES):
                        edges.append((relf, fn, "ARGFILE", C.rel(t), f"{sub.func.id}(...{lit}...)"))
                        q.append((C.rel(t), None))
    return edges


def subproc_inventory(relf):
    """EVERY `subprocess.run` argv in a file, with the ENCLOSING FUNCTION and line.

    Needed because the file-level closure cannot say WHICH graphcmp.py subcommand reaches a
    given bend file, and a census that cannot say that has to choose between over- and
    under-reporting. This prints the table and lets the reachability be READ, not guessed.
    """
    path = os.path.join(ROOT, relf)
    src = open(path, encoding="utf-8", errors="replace").read()
    t = ast.parse(src, filename=path)
    K = C.consts(t)
    fns = sorted((n for n in ast.walk(t) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))),
                 key=lambda n: n.lineno)
    rows = []
    for sub in ast.walk(t):
        if not (isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute)
                and isinstance(sub.func.value, ast.Name) and sub.func.value.id == "subprocess"):
            continue
        if sub.func.attr not in C.SUBPROC:
            continue
        argv = C.strlit(sub.args[0], K) if sub.args else None
        lits = [argv] if isinstance(argv, str) else (argv or [])
        encl = [f.name for f in fns if f.lineno <= sub.lineno <= (f.end_lineno or f.lineno)]
        resolved = [C.rel(C.resolve(os.path.dirname(path), a)) for a in lits
                    if isinstance(a, str) and C.resolve(os.path.dirname(path), a)]
        rows.append({"line": sub.lineno, "fn": encl[-1] if encl else "<module>",
                     "argv": " ".join(a for a in lits if isinstance(a, str))[:110],
                     "resolved": [r for r in resolved if r]})
    return rows


def stamp():
    """WHO measured this and WHEN. The tree is a MOVING TARGET: HEAD read `e92adbb5cc10` at the
    start of this unit's run and `cea5fc2ac5d3` twenty minutes later, with no edit by this unit.
    A count without a timestamp and a HEAD is a rumour about a tree that no longer exists."""
    import subprocess, datetime
    g = lambda *a: subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True,
                                  env={k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}).stdout.strip()
    return f"HEAD {g('rev-parse', '--short=12', 'HEAD')} @ {datetime.datetime.now(datetime.timezone.utc):%Y-%m-%dT%H:%M:%SZ}"


def main():
    entries = dict(differ.substrate_entries())
    cli, dyn = C.closure(["checks/differ.py"])
    rp_edges = run_path(os.path.join(ROOT, "checks/differ.py"))
    rp_files = sorted({e[3] for e in rp_edges if e[2] in ("SUBPROCESS", "ARGFILE", "IMPORTLIB")} | {"checks/differ.py"})

    # WHICH graphcmp.py SUBCOMMANDS does `cmd_run` issue? `run(out, "emit", ...)` / `run(out,
    # "dbg", ...)` hand the subcommand as an ARGUMENT to a wrapper that forwards `*args`, so the
    # file-level walk stops at `graphcmp.py` and cannot say WHICH of its functions run. This
    # reads the token out of the `run(...)` call inside `cmd_run`, so the mapping from subcommand
    # to bend fixture is READ, not assumed.
    src = open(os.path.join(ROOT, "checks/differ.py"), encoding="utf-8", errors="replace").read()
    tr = ast.parse(src)
    K = C.consts(tr)
    fs = funcs_of(os.path.join(ROOT, "checks/differ.py"))
    subs = set()
    for sub in ast.walk(fs["cmd_run"]):
        if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name) and sub.func.id == "run":
            toks = [C.strlit(a, K) for a in sub.args[1:]]
            for t in toks:
                if isinstance(t, str) and not t.startswith("-"):
                    subs.add(t)
                    break

    # every `.py` under .agents/slop/ that the run path reaches, per the two closures
    res = {
        "digest_total": len(entries),
        "cli_closure": cli,
        "run_path_files": rp_files,
        "run_path_edges": [e for e in rp_edges if e[2] != "CALL"],
        "run_path_call_edges": len([e for e in rp_edges if e[2] == "CALL"]),
        "dynamic_sites": dyn,
        "graphcmp_subproc": subproc_inventory(".agents/slop/graphcmp.py"),
        "graphcmp_subcommands_from_cmd_run": sorted(subs),
        "in_digest": {f: (f in entries) for f in sorted(set(cli) | set(rp_files))},
    }
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()