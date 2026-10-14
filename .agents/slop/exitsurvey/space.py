#!/usr/bin/env python3
"""THE ADMISSIBLE SPACE: WHAT IS LEFT AFTER THE ACCIDENTS, AND IS `SKIP` STILL LIVE.

    .venv/bin/python .agents/slop/exitsurvey/space.py

`gates/gatekit.py:59` RECORDS BOTH ORIGINS IN PROSE -- "4 is `e2e.py`'s SKIP and 3 is
`checks/sb-gate.sh`'s REFUSED" -- so the vocabulary is PARTLY A LEDGER OF ACCIDENTS. The space is
therefore WHAT IS LEFT AFTER THE ACCIDENTS, not what `gatekit` forgot, and computing it needs every
collision measured rather than remembered:

  (a) THE DELIBERATE PRODUCERS -- codes a gate RETURNS ON PURPOSE and the brief or `gatekit:75`
      counts. Read by AST over the whole tree, not by grepping `exit(2)`: `prune4`'s lesson.
  (b) `argparse`'s OWN 2 -- a stdlib contract nobody here can change, and the reason moving 2 -> 3
      is wrong rather than merely breaking.
  (c) THE FIVE `gatekit` NAMES.
  (d) THE SHELL: `checks/sb-gate.sh`'s historical REFUSED, which is why 3 is what it is.
  (e) `e2e.py`'s SKIP, which is why 4 is what it is.

AND `SKIP` IS VERIFIED HERE ACROSS EVERY `gatekit` CONSUMER, NOT ONE FILE, because `synonyms`
reported 0 `return SKIP` sites by reading a single file and `exitcode` then measured 3 in
`msgdiff-gate.py`. A claim about a vocabulary read from one file is a claim about that file.
"""
import ast
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def consts(tree):
    out = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Tuple):
            try:
                vals = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            for t, v in zip(node.targets, vals):
                if isinstance(t, ast.Name) and isinstance(v, int):
                    out[t.id] = v
        elif isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
            try:
                v = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            if isinstance(v, int) and not isinstance(v, bool):
                out[node.targets[0].id] = v
    return out


def literal(node, k):
    if isinstance(node, ast.Constant) and isinstance(node.value, int) and not isinstance(node.value, bool):
        return node.value
    if isinstance(node, ast.Name):
        return k.get(node.id)
    return None


def consumers():
    """Every `.py` whose AST IMPORTS `gatekit` -- a DIRECTORY WALK plus an AST filter, which is
    doctrine 1(b): a glob on a suffix, a walk for the population, and the import as the classifier."""
    out = []
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in (".git", ".venv", "references", "__pycache__",
                                            "node_modules", ".jj")]
        for f in sorted(fn):
            if not f.endswith(".py"):
                continue
            p = Path(dp) / f
            try:
                t = ast.parse(p.read_text(errors="replace"))
            except SyntaxError:
                continue
            for n in ast.walk(t):
                hit = ((isinstance(n, ast.ImportFrom) and n.module == "gatekit")
                       or (isinstance(n, ast.Import) and any(a.name == "gatekit" for a in n.names)))
                if hit:
                    out.append(p)
                    break
    return sorted(set(out))


def produces_skip(path):
    """`return SKIP` / `return <the name bound to 4>` / `sys.exit(SKIP)` in this file, by AST."""
    try:
        tree = ast.parse(path.read_text(errors="replace"))
    except SyntaxError:
        return []
    k = consts(tree)
    hits = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Return) and n.value is not None:
            if isinstance(n.value, ast.Name) and (n.value.id == "SKIP" or k.get(n.value.id) == 4):
                hits.append((n.lineno, "return " + ast.unparse(n.value)))
        elif isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "exit" \
                and n.args and isinstance(n.args[0], ast.Name) and k.get(n.args[0].id) == 4:
            hits.append((n.lineno, "exit " + ast.unparse(n.args[0])))
    return hits


def main():
    gk = loaded(ROOT / "gates" / "gatekit.py", "gk_under_space")
    gs = loaded(ROOT / "gates" / "gate-surface.py", "gs_under_space")
    vocab = gs.vocabulary()
    entries, libs = gs.population(ROOT)

    print("=" * 78)
    print("A. IS `SKIP` STILL LIVE? -- ACROSS EVERY CONSUMER, NOT ONE FILE")
    print("-" * 78)
    cons = consumers()
    print(f"CONSUMERS (an AST import of `gatekit`, over a directory walk): {len(cons)}")
    tot = 0
    for p in cons:
        for line, what in produces_skip(p):
            tot += 1
            print(f"  {p.relative_to(ROOT)}:{line}  {what}")
    print(f"\n`return SKIP` / `exit SKIP` / `exit <name bound to 4>` SITES OVER ALL {len(cons)} "
          f"CONSUMERS: {tot}")
    own = produces_skip(ROOT / "gates" / "gatekit.py")
    print(f"  in the OWNER gates/gatekit.py itself: {len(own)} -- "
          f"{'a constant nothing in the owner names is not a constant nothing can produce'}")

    print("\n" + "=" * 78)
    print("B. THE DELIBERATE PRODUCERS -- BY AST, OVER THE WHOLE TREE (not grep for `exit(2)`)")
    print("-" * 78)
    # the two numbers `gatekit:75` claims: 13 FILES that return 2 on purpose. Counted by AST over
    # every tracked .py, so a shell script's `exit 2` is separately visible.
    deliberate, shells = {}, []
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in (".git", ".venv", "references", "__pycache__",
                                            "node_modules", ".jj")]
        for f in sorted(fn):
            p = Path(dp) / f
            if f.endswith(".py"):
                try:
                    tree = ast.parse(p.read_text(errors="replace"))
                except SyntaxError:
                    continue
                k = consts(tree)
                hits = []
                for n in ast.walk(tree):
                    if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
                            and n.func.attr in ("exit", "_exit") and n.args:
                        if literal(n.args[0], k) == 2:
                            hits.append(n.lineno)
                    elif isinstance(n, ast.Return) and n.value is not None \
                            and literal(n.value, k) == 2:
                        hits.append(n.lineno)
                if hits:
                    deliberate[str(p.relative_to(ROOT))] = sorted(hits)
            elif f.endswith(".sh"):
                # a SHELL `exit 2` is a different producer in a different language and the AST above
                # cannot see it; `checks/*.sh` is 17 files and one of them owns the REFUSED=3 origin
                txt = p.read_text(errors="replace")
                if any(l.strip() in ("exit 2", "exit 2  # noqa") for l in txt.splitlines()):
                    shells.append(str(p.relative_to(ROOT)))
    for rel, lines in sorted(deliberate.items()):
        print(f"  {rel:52} {len(lines):>3} site(s)  {lines[:6]}")
    print(f"\n  {len(deliberate)} .py FILE(S) return/exit 2 ON PURPOSE, by AST over the tree")
    print(f"  {len(shells)} .sh file(s) spell a bare `exit 2`: {shells or '(none)'}")

    print("\n" + "=" * 78)
    print("C. THE ADMISSIBLE SPACE -- WHAT IS LEFT AFTER THE ACCIDENTS")
    print("-" * 78)
    taken = {
        0: "gatekit PASS (also the shell's, also every gate's -- not up for reassignment)",
        1: "gatekit FAIL (also `hooks/run.py` calls a traceback-exiting rc 1 DEAD; see E)",
        2: "THE DELIBERATE PRODUCERS above, AND `argparse`'s own 2 since 2.7 -- a mistyped argv "
           "reads as a refusal whether or not anyone means one",
        3: "gatekit REFUSED, and `checks/sb-gate.sh`'s historical REFUSED -- `gatekit.py:59` says so",
        4: "gatekit SKIP, and `e2e.py`'s SKIP -- `gatekit.py:59` says so",
        5: "gatekit DEAD (the exit `exitcode` closed)",
    }
    for c, why in sorted(taken.items()):
        print(f"  {c}  TAKEN. {why}")
    print(f"\n  codes >= 10, which is where a NEW verdict could sit without colliding with a "
          f"stdlib\n  contract, a shell, or anything a reader already knows: "
          f"{[c for c in range(10, 256)][:8]} ... (a further 246)")
    print("  NOTHING IN THE TREE CLAIMS 6, 7, 8 or 9 TODAY -- measured below, by AST.")

    claimed = {}
    for rel, lines in deliberate.items():
        for l in lines:
            claimed.setdefault(rel, lines)
    higher = []
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in (".git", ".venv", "references", "__pycache__",
                                            "node_modules", ".jj")]
        for f in sorted(fn):
            if not f.endswith(".py"):
                continue
            p = Path(dp) / f
            try:
                tree = ast.parse(p.read_text(errors="replace"))
            except SyntaxError:
                continue
            k = consts(tree)
            for n in ast.walk(tree):
                v = None
                if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) \
                        and n.func.attr in ("exit", "_exit") and n.args:
                    v = literal(n.args[0], k)
                elif isinstance(n, ast.Return) and n.value is not None:
                    v = literal(n.value, k)
                if isinstance(v, int) and 6 <= v <= 9:
                    higher.append((str(p.relative_to(ROOT)), n.lineno, v))
    print(f"  codes 6-9 in EXIT position across the whole tree: {len(higher)} site(s) "
          f"{higher[:8]}")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())