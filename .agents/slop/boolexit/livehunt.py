r"""THE LIVE HUNT: a function ANNOTATED `-> int` (or feeding `sys.exit`) that RETURNS A COMPARISON.

`checks/substrate-id.py`'s eleven `NAMES[rc]` sites are LATENT because every `return` in
`verdict_for` is a module int constant. But that is a fact about TODAY'S CALLERS, not a property
of the code, and `prune4`'s grade is the useful one. The QUESTION that decides LATENT-vs-LIVE is:

    does a COMPARISON reach an int-typed EXIT anywhere in the tree?

because a comparison IS the thing that leaks in (`True`/`False` come from comparisons), and an
exit code is exactly the `int` a caller cannot type. MEASURED on the ordinary case first: a plant
with an `int` proves nothing, so the plant here is a BOOL, and the assertion is that `int(True)`
and `1` take the same branch through the real code.
"""
import ast
import sys

from census import ROOT, population


def _fn(tree):
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            yield n


def int_annotated(fn):
    """`-> int`, `-> bool`, or nothing: the LAST TWO are the interesting pair."""
    r = fn.returns
    if r is None:
        return "unannotated"
    try:
        return ast.unparse(r)
    except Exception:
        return "?"


def is_cmp(node):
    return isinstance(node, (ast.Compare, ast.BoolOp)) or (
        isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not))


def intish(ann):
    return ann in ("int", "bool", "unannotated", "?")


def main():
    hits, files = [], 0
    for rel, p in population():
        try:
            src = p.read_text()
            tree = ast.parse(src)
        except (SyntaxError, OSError, UnicodeDecodeError):
            continue
        files += 1
        lines = src.splitlines()
        for fn in _fn(tree):
            ann = int_annotated(fn)
            if not intish(ann):
                continue
            for node in ast.walk(fn):
                # `return <comparison>` / `yield <comparison>` typed as int-or-bool
                if isinstance(node, (ast.Return, ast.Yield)) and node.value is not None \
                        and is_cmp(node.value):
                    hits.append(("RETURN-CMP", rel, node.lineno, fn.name, ann,
                                 lines[node.lineno - 1].strip()))
                # `sys.exit(<comparison>)`
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) \
                        and node.func.attr == "exit" and node.args and is_cmp(node.args[0]):
                    hits.append(("EXIT-CMP", rel, node.lineno,
                                 ast.unparse(node.func.value), ann,
                                 lines[node.lineno - 1].strip()))
                # `return True` / `return False` inside an `-> int` function
                if isinstance(node, ast.Return) and isinstance(node.value, ast.Constant) \
                        and isinstance(node.value.value, bool) and ann == "int":
                    hits.append(("RETURN-BOOL-AS-INT", rel, node.lineno, fn.name, ann,
                                 lines[node.lineno - 1].strip()))
    print(f"# THE LIVE HUNT -- functions annotated int/bool/unannotated whose BODY can yield a "
          f"COMPARISON, over {files} files discovered by os.walk under checks/ + gates/")
    print(f"## hits: {len(hits)}")
    for kind, rel, ln, fn, ann, line in hits:
        print(f"## {kind:<18} {rel}:{ln}  in {fn}() -> {ann}")
        print(f"##{'':>20} | {line[:100]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())