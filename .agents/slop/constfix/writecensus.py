#!/usr/bin/env python3
"""The write-site CENSUS, and the before/after comparison. **THE RESOLVER IS NOT HERE.**

    usage: .venv/bin/python .agents/slop/constfix/writecensus.py [--diff|--sites|--collide]

**EVERY LINE OF RESOLUTION LOGIC LIVES IN `checks/sweep.py`, AND THIS FILE CONSUMES IT BY
PATH.** MEASURED 2026-10-14: this file began with its own copy of `const()`, and the copy and
the original disagreed -- the copy found `.agents/slop/clangshim`, the original did not, and
the copy was wrong for two reasons that took a negative control to find. **A SECOND COPY OF A
RESOLVER IS A CONTRACT WITH NO GENERATOR**, and it is the same defect as `LIVE_UNITS`, the
173 `.txt` names and `ORACLE_WORD`: two answers to one question, and no way to tell which one
the tree is using. So `sweep.py` owns the resolver and this file asks it.

WHAT IS LEFT HERE, AND WHY IT IS NOT IN `sweep.py`: the per-SITE rows (which file, which line,
which callee), the diff against `sweep.py`'s previous resolver re-implemented verbatim for
comparison, and the read side used to report collisions. None of it is a verdict; all of it is
evidence about a verdict. **THE EVIDENCE BELONGS OUTSIDE THE GATE AND THE VERDICT BELONGS
INSIDE IT.**

VERDICTS. `PASS 0` the census and the gate agree. `FAIL 1` they differ. `REFUSED 3` the gate's
resolver could not be loaded, which is NOT the same as finding nothing.
"""
from __future__ import annotations

import argparse
import ast
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SLOP_PREFIX = ".agents/slop"


def gate():
    """`checks/sweep.py`, LOADED BY PATH. The one implementation of the resolver."""
    spec = importlib.util.spec_from_file_location("sweep_gate", os.path.join(REPO, "checks/sweep.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def instruments(root: str) -> list[str]:
    """`sweep.py`'s own instrument walk. Asked, not repeated."""
    return gate()._instrument_files(root)


def census(root: str) -> list[dict]:
    """One row per call site that names a `.agents/slop` directory, for the WRITE side."""
    g = gate()
    rows: list[dict] = []
    for path in g._instrument_files(root):
        rel = os.path.relpath(path, root)
        try:
            tree = ast.parse(open(path, errors="replace").read())
        except (OSError, SyntaxError):
            continue
        for body, env in g._scopes(tree):
            for node in ast.walk(ast.Module(body=list(body), type_ignores=[])):
                if not isinstance(node, ast.Call):
                    continue
                callee = node.func.id if isinstance(node.func, ast.Name) else getattr(node.func, "attr", "")
                slots = g._path_slots(node, env, read=False)
                for slot in slots or []:
                    v = g._resolve(slot, env)
                    d = g.slop_dir(v)
                    if d:
                        rows.append({"dir": d, "file": rel, "line": node.lineno, "fn": callee,
                                     "path": v.replace(g.UNKNOWN_MARK, "?")})
                    elif SLOP_PREFIX in v or any(
                            isinstance(c, ast.Constant) and isinstance(c.value, str)
                            and SLOP_PREFIX in c.value for c in ast.walk(slot)):
                        rows.append({"dir": None, "file": rel, "line": node.lineno, "fn": callee,
                                     "path": v.replace(g.UNKNOWN_MARK, "?")[:100]})
    return rows


def reads(root: str) -> list[dict]:
    """One row per call site that READS a `.agents/slop` directory."""
    g = gate()
    rows: list[dict] = []
    for path in g._instrument_files(root):
        rel = os.path.relpath(path, root)
        try:
            tree = ast.parse(open(path, errors="replace").read())
        except (OSError, SyntaxError):
            continue
        for body, env in g._scopes(tree):
            for node in ast.walk(ast.Module(body=list(body), type_ignores=[])):
                if not isinstance(node, ast.Call):
                    continue
                for slot in g._path_slots(node, env, read=True) or []:
                    d = g.slop_dir(g._resolve(slot, env))
                    if d:
                        rows.append({"dir": d, "file": rel, "line": node.lineno})
    return rows


def previous_resolver_dirs(root: str) -> tuple[str, ...]:
    """The directories `sweep.py`'s PREVIOUS resolver named -- the BEFORE column, as a set."""
    return tuple(sorted({r["dir"] for r in previous_resolver(root)}))


def previous_resolver(root: str) -> list[dict]:
    """`checks/sweep.py`'s PREVIOUS `const()`, re-implemented VERBATIM from `:180-193`.

    **RE-IMPLEMENTED AND NOT CALLED, DELIBERATELY.** The function it replaces is gone from the
    file, so comparing against it needs a copy; but a copy that were *used* would be the
    defect. It is read ONCE here, to produce the `BEFORE` column, and nothing downstream calls
    it. **A BASELINE IS A THING YOU MEASURE AGAINST, NOT A THING YOU MEASURE WITH.**
    """
    import glob

    def const(node, env):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name):
            return env.get(node.id)
        if isinstance(node, ast.Call):
            fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            if fn == "join":
                lits = [v for v in (const(a, env) for a in node.args) if isinstance(v, str)]
                return "".join(lits) if lits else None
        return None

    rows = []
    for path in sorted(glob.glob(os.path.join(root, "checks", "*.py"))
                       + glob.glob(os.path.join(root, "gates", "*.py"))):
        try:
            tree = ast.parse(open(path, errors="replace").read())
        except (OSError, SyntaxError):
            continue
        env = {}
        for st in tree.body:
            if isinstance(st, ast.Assign) and len(st.targets) == 1 and isinstance(st.targets[0], ast.Name):
                if (v := const(st.value, {})) is not None:
                    env[st.targets[0].id] = v
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            if fn not in ("makedirs", "mkdir", "write_text", "open"):
                continue
            if fn == "open":
                mode = "r"
                if len(node.args) > 1 and isinstance(node.args[1], ast.Constant):
                    mode = node.args[1].value
                if not any(ch in str(mode) for ch in "wax+"):
                    continue
            for arg in list(node.args) + [k.value for k in node.keywords]:
                v = const(arg, env)
                if v and SLOP_PREFIX + "/" in v:
                    head = v.split(SLOP_PREFIX + "/", 1)[1].strip("/").split("/")[0]
                    if head and "." not in head:
                        rows.append({"dir": SLOP_PREFIX + "/" + head,
                                     "file": os.path.relpath(path, root), "line": node.lineno})
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tree", default=REPO)
    ap.add_argument("--diff", action="store_true", help="compare with the previous resolver")
    ap.add_argument("--sites", action="store_true",
                    help="print the sites that name the prefix and no directory")
    ap.add_argument("--collide", action="store_true",
                    help="report directories that are BOTH written and read")
    args = ap.parse_args()
    try:
        g = gate()
    except Exception as exc:
        print(f"REFUSED 3: checks/sweep.py did not load ({exc}). "
              "NOT the same as finding nothing.")
        return 3

    new, old = census(args.tree), previous_resolver(args.tree)
    hits = [r for r in new if r["dir"]]
    unseen = [r for r in new if not r["dir"]]
    nd = {r["dir"] for r in hits}
    od = {r["dir"] for r in old}
    print(f"INSTRUMENTS (os.walk over checks/ + gates/, .py): {len(g._instrument_files(args.tree))}")
    print(f"write sites naming a {SLOP_PREFIX}/<dir>   previous resolver: "
          f"{len(od)} dirs from {len(old)} sites")
    print(f"                                  current resolver : {len(nd)} dirs from {len(hits)} sites")
    print(f"write sites that MENTION {SLOP_PREFIX} but yield no directory (the invisible set): "
          f"{len(unseen)}")
    for d in sorted(nd):
        who = sorted({(r['file'], r['line']) for r in hits if r['dir'] == d})
        mark = "  " if d in od else "+ "
        print(f" {mark}{d:38s} {len(who):3d} sites  " +
              ", ".join(f"{f}:{l}" for f, l in who[:4]) + (" ..." if len(who) > 4 else ""))
    print(f"  refused (written AND read, so not excludable): "
          f"{', '.join(g.self_output_conflicts(args.tree)) or 'NONE'}")
    print(f"  EXCLUDED BY sweep.py: {', '.join(g.self_output_dirs(args.tree)) or 'NONE FOUND'}")

    if args.sites:
        print("\nINVISIBLE: names the prefix, names no directory")
        for r in sorted(unseen, key=lambda r: (r["file"], r["line"])):
            print(f"  {r['file']}:{r['line']} [{r['fn']}]  {r['path']}")
    if args.collide:
        rd = reads(args.tree)
        rdirs = {r["dir"] for r in rd}
        print("\nREAD SIDE -- directories a live instrument READS BY PATH "
              f"({len(rd)} sites, {len(rdirs)} dirs):")
        for d in sorted(rdirs):
            who = sorted({(r['file'], r['line']) for r in rd if r['dir'] == d})
            print(f"   {d:38s} {len(who):3d} sites  " + ", ".join(f"{f}:{l}" for f, l in who[:3]))
        print("\nBOTH WRITTEN AND READ -- NOT EXCLUDABLE BY THE WRITE RULE ALONE:")
        for d in sorted(nd & rdirs) or ["   (none)"]:
            print(f"   {d}")
    if args.diff:
        print("\nNEWLY RESOLVED (current resolver, previous resolver had none):")
        for d in sorted(nd - od) or ["  (none)"]:
            print("  " + d)
        print("LOST (previous resolver named it, current does not):")
        for d in sorted(od - nd) or ["  (none)"]:
            print("  " + d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
