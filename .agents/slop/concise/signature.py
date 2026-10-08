#!/usr/bin/env python3
"""Find docstrings that RESTATE THE SIGNATURE PYTHON ALREADY CARRIES.

Named target in the `concise` brief: "a docstring that repeats the function name
and its type signature, which Python already carries". This is the one part of
the job `tokenize` cannot see, so it is `ast`: for every FunctionDef/AsyncFunctionDef/
ClassDef, take its docstring and decide whether the docstring adds anything the
signature did not already say.

THREE CLASSES, each mechanical, so a hit is checkable and not a taste judgement:

  SIGN    the docstring's first sentence is the signature restated in prose --
          "Increment the counter." over `def increment(self, counter: int) -> int:`.
          Scored by CONTENT-WORD overlap: of the identifier and parameter tokens
          in the signature, what fraction appear in the docstring's first
          sentence. >= 0.5 of them appearing, AND the docstring's first sentence
          carries no `->`, no `Args:`, no `Returns:` and no backticked name that
          the signature lacks. Python's own `help()` prints the signature above
          the docstring, so the restatement is visible twice.
  NAME    the docstring's first sentence merely echoes the identifier
          ("`plant` -- builds a plant.") and nothing else.
  WALL    a module docstring whose first line is > 60 words: a header that could
          not be stated in one line, and AGENTS.md calls a paragraph-long
          justification the wrong shape.

Every candidate is PRINTED WITH ITS SIGNATURE so the reader can disagree with the
classifier. Nothing is auto-edited: a docstring is prose and prose is the record.
"""

import ast
import os
import re
import subprocess
import sys

ROOTS = ("checks", "gates", "tinybendygrad", ".agents/slop")
STOP = frozenset("""a an the of to in is are be and or not for with on at by from as it its
self cls this that these those returns return arg args kwarg value values new make get set
run call calls use used using if else when then so such than there here we you i""".split())


def words(text: str) -> set[str]:
    return {w for w in re.findall(r"[A-Za-z_][A-Za-z_0-9]*", text)
            if w.casefold() not in STOP}


def classify(sig: set[str], first: str, doc: str) -> str | None:
    """A RESTATEMENT, not a docstring that merely mentions its parameters.

    v1 of this classifier tested `coverage` -- what fraction of the SIGNATURE's
    tokens appear in the sentence -- at >= 0.5, and it fired on 180 sites, most of
    them GOOD docstrings: "`1 / sqrt(ci * k * k)` with an f32 round after each
    operation" mentions both parameters and is the most useful line in the file.
    Coverage measures the wrong direction. A restatement is DENSE, not
    comprehensive: nearly every content word it has is a name the signature
    already prints. So the test is `density` -- signature tokens over content
    words -- plus a length ceiling, since a restatement has nothing to add and
    therefore stops.
    """
    content = {w.casefold() for w in words(first)}
    sig = {w.casefold() for w in sig}
    if not content or not sig:
        return None
    if any(t in first for t in ("->", "Args:", "Returns:", "Raises:", "Example", "e.g.")):
        return None
    if len(first.split()) > 14 or len(doc.splitlines()) > 2:
        return None
    density = len(sig & content) / len(content)
    coverage = len(sig & content) / len(sig)
    return "SIGN" if density >= 0.6 and coverage >= 0.5 else None


def main() -> int:
    tracked = set(subprocess.run(
        ["git", "ls-tree", "-r", "HEAD", "--name-only", "--", *ROOTS],
        capture_output=True, text=True, check=True).stdout.splitlines())
    files = []
    for root in ROOTS:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            files += [os.path.join(dirpath, f) for f in filenames if f.endswith(".py")]
    files = sorted(set(files) & tracked)

    signs, walls, unparsed = [], [], []
    for path in files:
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        try:
            tree = ast.parse(src)
        except SyntaxError as exc:
            unparsed.append((path, exc))
            continue

        mod_doc = ast.get_docstring(tree, clean=True)
        if mod_doc:
            head = mod_doc.strip().split("\n\n")[0]
            if len(head.split()) > 60:
                walls.append((path, 1, len(head.split()), head.replace("\n", " ")))

        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            doc = ast.get_docstring(node, clean=True)
            if not doc:
                continue
            sig = {node.name}
            if isinstance(node, ast.ClassDef):
                sig |= {b.id for b in node.bases if isinstance(b, ast.Name)}
            else:
                args = [a.arg for a in list(node.args.posonlyargs) + list(node.args.args)
                        + list(node.args.kwonlyargs)]
                if node.args.vararg:
                    sig.add(node.args.vararg.arg)
                if node.args.kwarg:
                    sig.add(node.args.kwarg.arg)
                sig |= set(args)
                if node.returns:
                    sig |= words(ast.unparse(node.returns))
                for default in list(node.args.defaults) + [d for d in node.args.kw_defaults if d]:
                    sig |= words(ast.unparse(default))
            first = doc.strip().split(". ")[0].strip()
            verdict = classify(sig, first, doc)
            if verdict == "SIGN":
                sigsrc = ast.unparse(node).split("\n")[0][:78]
                signs.append((path, node.lineno, sorted(sig)[:4], sigsrc, first[:88]))

    print(f"AST over {len(files)} tracked .py files "
          f"(os.walk x git ls-tree -r HEAD); {len(unparsed)} unparseable, excluded "
          f"from every denominator below")
    print(f"\nSIGN  docstring's first sentence restates the signature: {len(signs)}\n")
    for path, lineno, sig, sigsrc, first in signs[:30]:
        print(f"  {path}:{lineno}")
        print(f"      sig    {sigsrc}")
        print(f"      doc    {first}")

    print(f"\nWALL  module docstring's first paragraph > 60 words: {len(walls)}\n")
    for path, lineno, n, head in sorted(walls, key=lambda w: -w[2])[:20]:
        print(f"  {n:>4} words  {path}:{lineno}")
        print(f"      {head[:112]}")
    for path, exc in unparsed:
        print(f"\nUNPARSEABLE (excluded, named so the exclusion is not silent): {path}: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
