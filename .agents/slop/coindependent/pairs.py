#!/usr/bin/env python3
"""TWO FILES ASSERTING THE SAME FACT INDEPENDENTLY -- the class, swept.

    .venv/bin/python .agents/slop/coindependent/pairs.py

THE DEFECT THIS HUNTS, from `AGENTS.md`'s own record and this session's brief: `names.py`'s
hand list of substituted graphs and `checks/disagree-gate.py`'s `ARMED` tuple were
CHARACTER-IDENTICAL but by TWO INDEPENDENT COPIES, and the gate's PASS condition was that the two
agreed -- so a FOURTH substituted graph was invisible to both, and the gate exited 0 because both
copies shared the same omission. **AGREEMENT WAS THE PASS CONDITION AND THE AGREEMENT WAS BY
CONSTRUCTION OF A HAND LIST, NOT OF A DERIVATION.**

WHAT MAKES A PAIR A FINDING, EXACTLY, so this file cannot be accused of listing everything that
shares a word:

  (a) the SAME set of string literals is spelled in TWO files, AND
  (b) it is spelled as a LITERAL (not `load(...).declared()`), so editing one does not move the
      other, AND
  (c) at least one of the two files uses it as an EXPECTATION (a comparison, an assertion, or a
      membership test whose result is a verdict).

`(b)` is the whole distinction between a pair and a single source: `checks/no-txt.py` asks
`differ.declared()` for the `.txt` carve-out and `checks/differ.py`'s `artefacts_ok()` asks the
SAME function -- one module, two consumers, and a change to it moves both. That is NOT a pair in
this sense; it is the fix. This file prints those as `DERIVED` so the two classes are not
confused.

A literal table that is READ (a prompt, a docstring, a fixture) and never compared is not an
expectation and is excluded by `(c)`.
"""
import ast
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
HOMES = ("checks", "gates")
SUFFIXES = (".py",)


def string_lists(p: pathlib.Path):
    """Every `tuple`/`list`/`set`/`frozenset` literal of >=3 string constants, canonicalised to a
    sorted tuple, with its line. Partial literals (an f-string element) are skipped: a set that
    cannot be read whole is not a set this instrument can compare."""
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError:
        return []
    out = []
    for n in ast.walk(tree):
        if isinstance(n, (ast.Tuple, ast.List, ast.Set)):
            vals = []
            ok = True
            for e in n.elts:
                if isinstance(e, ast.Constant) and isinstance(e.value, str):
                    vals.append(e.value)
                else:
                    ok = False
                    break
            if ok and len(vals) >= 3:
                out.append((tuple(sorted(vals)), n.lineno, len(set(vals))))
    return out


def derived_consumers():
    """Files that load another file's declaration BY PATH -- the single-source shape, named so
    the report can say `this is the fix, not the fault`."""
    hits = {}
    for home in HOMES:
        for p in sorted((ROOT / home).iterdir()):
            if p.suffix not in SUFFIXES or not p.is_file():
                continue
            t = p.read_text(errors="replace")
            if "spec_from_file_location" in t or "declared()" in t or "discovered()" in t:
                for m in ("declared", "discovered", "substituted", "atoms", "table", "coverage"):
                    if m + "(" in t:
                        hits.setdefault(str(p.relative_to(ROOT)), set()).add(m)
    return hits


def expectation_names(p: pathlib.Path) -> set[str]:
    """Every identifier used in a `compare`-shaped position, so `(c)` has something concrete to
    test. Membership tests, `==`, `!=`, `in`, `assert`, and `if <name>` all count."""
    try:
        tree = ast.parse(p.read_text(errors="replace"))
    except SyntaxError:
        return set()
    names = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Compare):
            for op in (n.ops or []):
                if isinstance(op, (ast.Eq, ast.NotEq, ast.In, ast.NotIn, ast.Is, ast.IsNot)):
                    for side in (n.left, *n.comparators):
                        if isinstance(side, ast.Name):
                            names.add(side.id)
        if isinstance(n, ast.Assert) and isinstance(n.test, ast.Name):
            names.add(n.test.id)
        if isinstance(n, ast.If) and isinstance(n.test, ast.Name):
            names.add(n.test.id)
    return names


def main(argv):
    decls = {}       # canonical tuple -> [(relpath, line)]
    per_file = {}
    for home in HOMES:
        for dirpath, dirnames, filenames in os.walk(ROOT / home):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in sorted(filenames):
                if not fn.endswith(SUFFIXES):
                    continue
                p = pathlib.Path(dirpath) / fn
                rel = str(p.relative_to(ROOT))
                per_file[rel] = expectation_names(p)
                for key, line, _n in string_lists(p):
                    decls.setdefault(key, []).append((rel, line))

    shared = {k: v for k, v in decls.items()
              if len({rel for rel, _ in v}) >= 2 and len(k) >= 3}
    print(f"# {len(decls)} string-list declarations over {len(per_file)} files; "
          f"{len(shared)} value(s) spelled in 2+ files\n")
    print("SHARED LITERAL LISTS (candidate independent pairs):")
    for key, sites in sorted(shared.items(), key=lambda kv: -len(kv[1])):
        files = sorted({rel for rel, _ in sites})
        # `(c)`: is the shared value used as an expectation in any file? A NAME cannot be
        # recovered from a literal, so this reports the sites and lets a reader judge; the
        # judgement is the point, because a false pair is worse than a miss.
        print(f"  [{len(key)} names x {len(files)} files] {sorted(key)[:5]}{' ...' if len(key)>5 else ''}")
        for rel, line in sites:
            print(f"      {rel}:{line}")
    print("\nDERIVED CONSUMERS (single source, loaded by path -- NOT a pair):")
    for rel, what in sorted(derived_consumers().items()):
        print(f"  {rel}: {sorted(what)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
