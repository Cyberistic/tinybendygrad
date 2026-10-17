#!/usr/bin/env python3
r"""THE FOUR HARNESS CLASSES.  ONE question per site: CAN THE PROCESS'S EXIT CODE CHANGE WHEN
THE CHILD LANE ANSWERS REFUSED / DEAD / NOTHING?

The census at `gates/exitcode-census-gate.py` grades the SHAPE OF WHAT THE AUTHOR HANDED
`sys.exit`.  It has no shape for the next question up, which is the one a `-mutate.py` asks:
the author CHOSE `0`, and the choice is constant, and the harness only PRINTS the refusal.  A
reader of `$?` alone gets PASS.  That is the MAYBE-NONE MEANING one process out.

MEASURED LEXICALLY, AND SAID SO.  `rc_reaches` is a FIXPOINT over the entry function's own local
assignments (no depth limit, no guess): from the returned expression, follow names bound by
`Assign`/`AugAssign`/`AnnAssign`/`NamedExpr` inside the entry, transitively.  It does not follow
calls, so a verdict laundered through `report(x)` is reported as NOT REACHING, which is the safe
direction for a question whose bad answer is "the harness can see it".

VOCABULARY, NOT A LIST OF FILES.  Populations are discovered: `*-mutate.py` / `*-gen.py` by a
directory walk over the repo's own top-level owners, plant harnesses by `def plant(` / `--plant`,
shell harnesses by `checks/*.sh`.
"""
import ast, fnmatch, os, re, subprocess, sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
# names the TREE uses for a child verdict.  Read from gates/gatekit.py's own five, not invented.
GATEKIT = ROOT / "gates" / "gatekit.py"
FIVE = ("PASS", "FAIL", "REFUSED", "SKIP", "DEAD")
VERDICT_SUBSTR = ("refus", "dead", "skip", "unmoved", "moved_any", "not_moved", "gap",
                  "missing", "bad", "fail", "expect", "zero", "silent", "stale", "empty",
                  "unreachable", "diverg")


def exit_sites(tree):
    """Every exit site's value expression, `extract()`-style.  Module-level, because
    `sys.exit(main())` lives at module scope -- walking a FunctionDef cannot see it."""
    out = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Call):
            f = n.func
            if ((isinstance(f, ast.Attribute) and f.attr == "exit"
                 and isinstance(f.value, ast.Name) and f.value.id == "sys")
                    or (isinstance(f, ast.Name) and f.id in ("exit", "quit"))):
                out.append(n.args[0] if n.args else None)
    return out


def entry_of(tree):
    """The same-module function whose return value reaches `sys.exit(...)`, else None."""
    funcs = {f.name: f for f in ast.walk(tree)
             if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))}
    best = None
    for a in exit_sites(tree):
        nm = None
        if isinstance(a, ast.Call) and isinstance(a.func, ast.Name): nm = a.func.id
        elif isinstance(a, ast.Name): nm = a.id
        if nm is None or nm not in funcs: continue
        if best is None or funcs[nm].lineno < best.lineno: best = funcs[nm]
    return best


def returns_in_source_order(fn):
    stack, out, seen = list(fn.body), [], set()
    while stack:
        n = stack.pop()
        if id(n) in seen: continue
        seen.add(id(n))
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)): continue
        if isinstance(n, ast.Return): out.append(n)
        stack.extend(ast.iter_child_nodes(n))
    return sorted(out, key=lambda n: n.lineno)


def binds(fn):
    """{name: ast node} for every binding inside fn, LAST wins (source order)."""
    out = {}
    for n in ast.walk(fn):
        if isinstance(n, ast.Assign):
            for t in n.targets:
                for nm in ast.walk(t):
                    if isinstance(nm, ast.Name): out[nm.id] = n.value
        elif isinstance(n, ast.AugAssign) and isinstance(n.target, ast.Name):
            out.setdefault(n.target.id, n)
        elif isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name) and n.value is not None:
            out[n.target.id] = n.value
        elif isinstance(n, (ast.NamedExpr,)) and isinstance(n.target, ast.Name):
            out[n.target.id] = n.value
    return out


def closure_names(expr, env):
    """Fixpoint: every name `expr` can be influenced by, through fn-local bindings."""
    seen, frontier, out = set(), [expr], set()
    while frontier:
        e = frontier.pop()
        for n in ast.walk(e):
            if isinstance(n, ast.Name):
                if n.id in seen: continue
                seen.add(n.id)
                if n.id in env and isinstance(env[n.id], ast.AST):
                    frontier.append(env[n.id])
                elif n.id not in dir(__builtins__):
                    out.add(n.id)
    return out


# `gatekit` is the tree's OWN declaration of the five (`gates/gatekit.py:60`
# `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`), so a name bound to `gatekit.X` IS a
# verdict reference -- without this the instrument could not follow `return code` past
# `if code == gatekit.PASS: code = gatekit.REFUSED` and would call a wired exit UNWIRED.
def is_verdict_name(nm, extra):
    if nm == "gatekit" or nm in extra:
        return True
    low = nm.lower()
    return any(w in low for w in VERDICT_SUBSTR)


def grade(path, cls):
    try: tree = ast.parse(path.read_text(errors="replace"))
    except Exception as exc: return [dict(cls=cls, file=rel(path), fn="-", verdict="UNPARSEABLE", note=str(exc)[:40])]
    fn = entry_of(tree)
    if fn is None:
        return [dict(cls=cls, file=rel(path), fn="-", verdict="NO-EXIT-SITE", note="nothing reaches sys.exit")]
    env = binds(fn)
    rets = returns_in_source_order(fn)
    last = rets[-1] if rets else None
    touched = closure_names(last.value, env) if (last and last.value is not None) else set()
    vnames = sorted(nm for nm in env if is_verdict_name(nm, FIVE))
    # LIVE = incremented (AugAssign) or assigned a verdict-looking literal, inside the entry
    live = set()
    for n in ast.walk(fn):
        if isinstance(n, ast.AugAssign) and isinstance(n.target, ast.Name) and is_verdict_name(n.target.id, FIVE):
            live.add(n.target.id)
    printed = set()
    for n in ast.walk(fn):
        if isinstance(n, ast.JoinedStr) or (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                                           and n.func.attr in ("write", "print", "append")):
            printed |= {x.id for x in ast.walk(n) if isinstance(x, ast.Name)}
    live_printed = sorted(live & printed)
    # `gatekit` itself counts as REACHED: the exit names a constant the tree DECLARED, so the
    # rc is one of the five by construction and not a value this harness computed and discarded.
    reaches = sorted({nm for nm in vnames if nm in touched} | ({"gatekit"} if "gatekit" in touched else set()))
    const = isinstance(last.value, ast.Constant) if (last and last.value is not None) else (last is None)
    constv = last.value.value if (last and isinstance(last.value, ast.Constant)) else None
    if last is None or last.value is None:
        v = "MAYBE-NONE"          # a bare `return` -> sys.exit(None) -> 0 == PASS
    elif reaches:
        v = "SEES-CHILD"          # the rc MOVES with the child's verdict
    elif live_printed and const:
        v = "GREEN-ON-REFUSAL"    # constant rc, refusal only printed
    elif live_printed:
        v = "PRINTS-REFUSAL-UNWIRED"
    elif const:
        v = "CONST-PASS"          # constant rc, nothing to see
    else:
        v = "COMPUTED-UNTRACED"
    return [dict(cls=cls, file=rel(path), fn=f"{fn.name}@{fn.lineno}", verdict=v,
                 last=f"return {constv if const else ast.unparse(last.value)[:22]}" if last else "-",
                 live_printed=",".join(live_printed) or "-", reaches=",".join(reaches) or "-")]


def rel(p):
    try: return str(p.relative_to(ROOT))
    except ValueError: return str(p)


def tracked():
    return {p for p in subprocess.run(["git", "ls-files", "-z"], capture_output=True,
                                      text=True, cwd=ROOT).stdout.split("\0") if p.endswith(".py")}


TR = tracked()
CLASSES = {"mutate": "*-mutate.py", "gen": "*-gen.py", "oracle": "*-oracle.py"}
rows = []
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [d for d in dn if d not in (".git", "__pycache__", "node_modules", "references", "runs", ".venv")]
    for n in fn:
        for cls, pat in CLASSES.items():
            if fnmatch.fnmatch(n, pat) and rel(Path(dp) / n) in TR:
                rows += grade(Path(dp) / n, cls)
# the plant class: any tracked .py that defines a plant entry point
for p in sorted(TR):
    if "-gen" in p or "-mutate" in p or "-oracle" in p: continue
    fp = ROOT / p
    if not fp.is_file(): continue
    try: t = ast.parse(fp.read_text(errors="replace"))
    except Exception: continue
    names = {f.name for f in ast.walk(t) if isinstance(f, ast.FunctionDef)}
    if "plant" in names:                      # a PLANT is a def, not the word in prose
        rows += grade(fp, "plant")
rows.sort(key=lambda r: (r["cls"], r["file"]))
w = max(len(r["file"]) for r in rows)
print(f"{'class':<7} {'file':<{w}} {'entry':<16} {'VERDICT':<24} {'last return':<26} printed-only")
for r in rows:
    print(f"{r['cls']:<7} {r['file']:<{w}} {r.get('fn','-'):<16} {r['verdict']:<24} "
          f"{r.get('last','-'):<26} {r.get('live_printed','-')}")
print("\nBY CLASS / VERDICT")
for cls in sorted({r["cls"] for r in rows}):
    c = Counter(r["verdict"] for r in rows if r["cls"] == cls)
    print(f"  {cls:<7} n={sum(c.values()):<4} {dict(c)}")
print(f"\n  TOTAL {len(rows)} sites; GREEN-ON-REFUSAL = "
      f"{sum(1 for r in rows if r['verdict'] == 'GREEN-ON-REFUSAL')}, "
      f"MAYBE-NONE = {sum(1 for r in rows if r['verdict'] == 'MAYBE-NONE')}")
