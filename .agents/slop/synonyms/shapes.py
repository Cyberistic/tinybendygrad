#!/usr/bin/env python3
"""THE TWELFTH, AND EVERY VOCABULARY *SHAPE*. AST over the tree.

    .venv/bin/python .agents/slop/synonyms/shapes.py

`census.py` reads a `(gate, code)` pair only when the gate ships `VERDICTS`. It reads **11 over
8 gates**; the brief says 12. **A DENOMINATOR THAT DISAGREES WITH THE BRIEF IS A FINDING**, so
this looks for the twelfth by asking the question the census's SHAPE cannot: a runner's
vocabulary need not be a `VERDICTS` dict at all.

`hooks/run.py:56` spells it as a DICT (`NAME = {PASS: "GREEN", ...}`), not as a name<-code
unpack, and `hooks/run.py:32` says `0 GREEN` in prose. `twelfth.py` -- which reads ONLY
module-level `A, B, ... = <tuple>` -- cannot see that, and neither can `gate-surface.declaration()`,
whose marker is the literal name `VERDICTS`. **So there are at least TWO vocabulary shapes in
this tree and both instruments that claim to own the census are blind to one of them.**

The three shapes read here:
    UNPACK   `A, B = (0, 1)`            -- `gatekit`'s, the one `vocabulary()` knows
    VERDICTS `VERDICTS = {0: "OK"}`     -- a GATE declaring its own surface
    NAME     `NAME = {0: "GREEN"}`      -- a RUNNER's private copy of the vocabulary

Shape is AST-derived (`ast.Assign` whose value is a dict with all-int keys and all-str values),
never a regex, for `prune4`'s reason.
"""
import ast
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SURFACE = ROOT / "gates" / "gate-surface.py"
PRUNE = {".git", ".venv", "__pycache__", "node_modules", "references"}


def loaded(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def dicts_of(src, lineno_of):
    """Every module-level `X = {int: str, ...}` -- a vocabulary in DICT shape, by AST."""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    out = []
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        try:
            v = ast.literal_eval(node.value)
        except (ValueError, SyntaxError, TypeError):
            continue
        if (isinstance(v, dict) and v
                and all(type(k) is int for k in v)          # `type is`, not isinstance: bool IS int
                and all(isinstance(x, str) for x in v.values())):
            for t in node.targets:
                if isinstance(t, ast.Name):
                    out.append((t.id, node.lineno, v))
    return out


def main():
    sf = loaded(SURFACE, "gate_surface_under_shapes")
    vocab = sf.vocabulary()
    print(f"OWNER gates/gatekit.py: {', '.join(f'{c}={n}' for c, n in sorted(vocab.items()))}")
    print("  (`bool` is a subclass of `int`, so every key test here is `type(k) is int` -- the\n"
          "   first run of a dict-shape scan reported `{PASS: 'GREEN'}` under the UNPACK shape)\n")

    named, total = [], 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in PRUNE]
        for fn in sorted(filenames):
            if not fn.endswith(".py"):
                continue
            p = Path(dirpath) / fn
            try:
                src = p.read_text(errors="replace")
            except OSError:
                continue
            for name, lineno, v in dicts_of(src, None):
                bad = {int(k): (x, vocab[int(k)]) for k, x in sorted(v.items())
                       if int(k) in vocab and str(x).upper() != vocab[int(k)].upper()}
                if not bad:
                    continue
                total += len(bad)
                named.append((str(p.relative_to(ROOT)), lineno, name, bad, v))

    print(f"DICT-SHAPED VOCABULARIES THAT DISAGREE WITH THE OWNER: {total} entry/entries "
          f"over {len(named)} site(s)\n")
    for rel, lineno, name, bad, v in named:
        print(f"  {rel}:{lineno}  `{name}`  all={dict(sorted(v.items()))}")
        for c, (a, b) in sorted(bad.items()):
            print(f"      RENAMED: exit {c}: '{a}' where the owner says '{b}'")
        print()

    print("THE THREE SHAPES, AND WHO READS EACH:\n")
    print("  UNPACK   gates/gatekit.py:60        read by gates/gate-surface.py:vocabulary()  "
          "-- the OWNER")
    print("  VERDICTS checks/*, gates/*         read by gates/gate-surface.py:declaration() "
          "-- a GATE about itself")
    print("  NAME     .agents/slop/hooks/run.py:56   read by NOTHING -- a private copy in a "
          "RUNNER")
    print("\n  THE THIRD IS OUTSIDE `HOMES=('checks','gates')`, so `gates-pop.discover()` cannot")
    print("  see it, and `declares_surface()` (hooks/run.py:69) filters ON `VERDICTS`, so the")
    print("  runner that HOLDS the copy is also the runner that cannot see it.")
    return 0


if __name__ == "__main__":
    with __import__("contextlib").suppress(KeyboardInterrupt):
        sys.exit(main())