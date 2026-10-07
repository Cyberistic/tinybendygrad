#!/usr/bin/env python3
"""WHERE IS THE TWELFTH? Every module-level name<-code unpack in the tree, AST.

    .venv/bin/python .agents/slop/synonyms/twelfth.py

`census.py` counts a RENAMED CODE as (gate, code) pairs whose token differs from the owner's.
It reads 11 over 8 gates. The brief says 12. **A DENOMINATOR THAT DISAGREES WITH THE BRIEF IS
A FINDING, NOT A ROUNDING ERROR**, so this asks the narrowest possible question -- which
modules in the tree spell a verdict code as a name<-code tuple at all -- and prints every one
with the tokens, so the twelfth is either HERE by name or ABSENT, and both are answers.

It also reports, per unpack, whether the module IMPORTS the codes from `gates/gatekit.py` or
RE-SPELLS them. That is the whole question of the relationship: a gate that imports cannot
disagree with the owner, and a gate that re-spells can, and only the second is a synonym.
"""
import ast
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"
PRUNE = (".git", ".venv", "__pycache__", "node_modules", "references")


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def walk(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in PRUNE]
        for fn in sorted(filenames):
            if fn.endswith(".py"):
                yield Path(dirpath) / fn


def unpacks(src):
    """Every module-level `A, B, ... = <literal>`, by AST. Returns `[(lineno, {code: NAME})]`."""
    out = []
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return out
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for tgt in node.targets:
            if not (isinstance(tgt, ast.Tuple) and len(tgt.elts) > 1
                    and all(isinstance(e, ast.Name) for e in tgt.elts)):
                continue
            try:
                codes = ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                continue
            # `all(isinstance(c, int) ...)` is not decoration: a tuple of LISTS is a tuple, and
            # `dict(zip(...))` raises `TypeError: unhashable type: 'list'` on one. MEASURED here
            # on the first run -- `gates/gate-surface.py`'s own `vocabulary()` has the same
            # latent hole and would raise rather than `refuse`, which is the wrong failure for
            # an instrument whose entire job is to name an ambiguous owner.
            if (isinstance(codes, tuple) and len(codes) == len(tgt.elts)
                    and all(isinstance(c, int) for c in codes)):
                out.append((node.lineno, dict(zip(codes, (e.id for e in tgt.elts)))))
    return out


def main():
    sf = loaded(SURFACE, "gate_surface_under_twelfth")
    vocab = sf.vocabulary()
    print(f"OWNER gates/gatekit.py: {', '.join(f'{c}={n}' for c, n in sorted(vocab.items()))}\n")

    hits = []
    for p in sorted(walk(ROOT)):
        rel = str(p.relative_to(ROOT))
        src = p.read_text(errors="replace")
        for lineno, m in unpacks(src):
            imports = ("gatekit" in src) and not rel.endswith("gatekit.py")
            hits.append((rel, lineno, m, imports))

    print(f"MODULE-LEVEL name<-code UNPACKS over the whole tree minus {list(PRUNE)}: {len(hits)}\n")
    renamed_total = 0
    for rel, lineno, m, imports in hits:
        bad = {c: n for c, n in sorted(m.items())
               if int(c) in vocab and str(n).upper() != vocab[int(c)].upper()}
        unm = [c for c in sorted(m) if int(c) not in vocab]
        if not (bad or unm):
            continue
        renamed_total += len(bad)
        print(f"  {rel}:{lineno}"
              + ("  [IMPORTS gatekit]" if imports else "  [RE-SPELLS]")
              + f"  codes={dict(sorted(m.items()))}")
        if bad:
            print(f"      RENAMED: " + ", ".join(
                f"{c}:{n}->{vocab[int(c)]}" for c, n in sorted(bad.items())))
        if unm:
            print(f"      UNMAPPED: " + ", ".join(
                f"{c}:{m[c]}" for c in unm))
        print()
    print(f"TOTAL RENAMED name<-code ENTRIES over the WHOLE tree: {renamed_total}")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())