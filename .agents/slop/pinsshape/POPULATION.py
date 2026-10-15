#!/usr/bin/env python3
"""POPULATION.py -- MEASUREMENT, NOT A GATE. No verdict, no exit code that means anything.

Enumerates every `gates/*.rows` and, for each: the owner (who NAMES it), the declared writer
(from its own header), the column shape, and the row count. It exists to answer ONE question the
tree has never answered in one place: what shapes do pins tables have, and who says they have them.

THE OWNER LOOKUP IS A LITERAL SCAN OVER THE WHOLE `gates/` DIRECTORY, NOT `ast.parse`, because
MEASURED: `ast` cannot read a `.bend` driver and `gates/symcases.rows` is named by one
(`gates/sym_graph_census.bend:130`, `def CASES() -> String: "gates/symcases.rows"`), so an
AST-only owner lookup charges a table for being unreadable when it is read perfectly well.

Writes `.rows` because the tree has no `.txt`.
"""

import os
import re
import stat
import sys
import warnings
from pathlib import Path

import importlib.util

ROOT = Path(__file__).resolve().parents[3]
GATES = ROOT / "gates"

# The instrument's own WRITER regex, imported so this measurement and the gate agree on what a
# declared writer IS. Copied by reference, not re-spelled.
sys.path.insert(0, str(GATES))
with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    _spec = importlib.util.spec_from_file_location("ps", GATES / "pins-shape-gate.py")
    ps = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(ps)


SKIP_DIRS = {".git", "__pycache__", "references", "node_modules", ".venv", "tinygrad",
             "runs", ".agents"}


def owner_pool():
    """Every regular file in the REPO that could be a gate or a driver -- TREE-WIDE, because
    `gates/cstyle-live.rows` is named by `checks/repair-dupes.py:48` and `checks/dup-gate.py:372`,
    not by anything in `gates/`. MEASURED `discover()` returns ZERO `.bend` files (169 .py +
    17 .sh + 1 extless + 1 .mjs of 188 entries) so the shared population cannot see the 58
    drivers; this pool is the DIRECTORY, which is the only shape that has no suffix set in it."""
    out = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            p = Path(dirpath) / name
            try:
                if stat.S_ISREG(os.lstat(p).st_mode):
                    out.append(p)
            except OSError:
                continue
    return sorted(out)


def owners_by_literal(pool, targets):
    """`{basename: {file names naming it}}` by a LITERAL over each source's text. A `.py` file's
    string literals that end in `.rows` are found by `ast`; every OTHER language falls back to a
    regex over the raw text, because the whole point is that `.bend` names its tables too."""
    import ast

    out = {t: set() for t in targets}
    lit = re.compile(r'"([\w./-]+\.rows)"|\'([\w./-]+\.rows)\'')
    for f in pool:
        try:
            src = f.read_text(errors="replace")
        except OSError:
            continue
        found = set()
        if f.suffix == ".py":
            try:
                tree = ast.parse(src)
                found = {n.value.rsplit("/", 1)[-1] for n in ast.walk(tree)
                         if isinstance(n, ast.Constant) and isinstance(n.value, str)
                         and n.value.endswith(".rows")}
            except SyntaxError:
                found = set()
        if not found:                       # every non-python language, and unreadable python
            for a, b in lit.findall(src):
                found.add((a or b).rsplit("/", 1)[-1])
        for n in found & set(targets):
            out[n].add(f.name)
    return out


def main():
    tables = [p for p in sorted(GATES.iterdir())
              if p.suffix == ".rows" and not p.name.startswith(".")
              and stat.S_ISREG(os.lstat(p).st_mode)]
    pool = owner_pool()
    named = owners_by_literal(pool, [p.name for p in tables])

    print(f"# gates/*.rows POPULATION -- measured {sys.argv[1] if len(sys.argv) > 1 else ''}")
    print(f"# pool = every regular file under gates/ ({len(pool)}), suffix-free; "
          f"of those, {sum(1 for p in pool if p.suffix == '.bend')} are .bend drivers that "
          f"gates-pop.discover() returns 0 of\n")
    print(f"{'file':34s} {'rows':>5s} {'cols':>4s} {'delim':8s} {'writer':34s} owners")
    print("-" * 150)
    shapes = {}
    for p in tables:
        rows, head = ps.data_rows(p), ps.header(p)
        widths, tabbed = ps.arity(rows)
        ncol = sorted(set(widths))[0] if len(set(widths)) == 1 else None
        w = ps.WRITER.search(head)
        writer = w.group(1) if w else "--NONE--"
        # is the declared writer actually in the tree?
        if w and w.group(1).endswith(".py") and not ps._resolve(w.group(1), p.parent):
            writer += " (MISSING!)"
        # does the file declare an arity word?
        aw = ps.ARITY_WORD.findall(head)
        decl = ",".join(sorted({x.upper() for x in aw})) or "--none--"
        shapes.setdefault(ncol, []).append(p.name)
        print(f"{p.name:34s} {len(rows):5d} {ncol if ncol is not None else -1:4d} "
              f"{'TAB' if tabbed else 'ws':8s} {writer:34s} {decl:8s} "
              f"{','.join(sorted(named[p.name])) or 'NONE'}")
    print()
    print("# column-count buckets:")
    for k in sorted(shapes, key=lambda x: (x is None, x)):
        print(f"#   {str(k):5s} ({len(shapes[k])}): {', '.join(shapes[k])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())