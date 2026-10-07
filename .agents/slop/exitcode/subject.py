"""THE SUBJECT INVENTORY, AND THE TOKEN/NUMBER COLLISION -- both measured, neither inherited.

  1. CAN A GATE'S SUBJECT BE ABSENT? `SKIP` means "I could not run, so I measured nothing". That
     is a claim about a SUBJECT being empty, not about a token being unused. So the population is
     every gate that declares `VERDICTS` (read by `ast.literal_eval` off the module body, exactly
     as `gates/gate-surface.py` does it -- never by import, because importing a gate RUNS it), and
     the question is whether any of them can reach an early return whose enclosing `if` names an
     ABSENCE. Both names (`SKIP`) and numbers (`4`) count as a verdict; getting that wrong
     reported 0 of 15 over a file with three `return SKIP` in it.

  2. THE COLLISION. A gate that PRINTS one verdict word and RETURNS the number of a DIFFERENT one
     tells its reader two incompatible things. Scoped to ONE branch -- a `print` and the `return`
     inside the same `If` body, in source order -- because a file that merely mentions `DEAD` in
     prose says nothing, and a whole-file scan reported 49 false candidates for exactly that
     reason.

Usage: .venv/bin/python .agents/slop/exitcode/subject.py
"""
import ast
import importlib.util
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PRUNE = {".git", ".venv", "references", "__pycache__", "node_modules"}

spec = importlib.util.spec_from_file_location("gk", ROOT / "gates" / "gatekit.py")
gk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gk)
BY_WORD = {w: c for c, w in gk.VERDICT.items()}   # loaded from the OWNER, never re-spelled

ABSENT = re.compile(r"\bnot\b|\bno\b|is\s+None|empty|missing|absent|nothing|\bNone\b", re.I)


def files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in PRUNE]
        if Path(dirpath).name not in ("gates", "checks"):
            continue
        for n in filenames:
            if n.endswith(".py") and n != "gatekit.py":
                yield Path(dirpath) / n


def declares_verdicts(path):
    try:
        tree = ast.parse(path.read_text(errors="replace"))
    except SyntaxError:
        return None
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", None) == "VERDICTS"
                                                for t in node.targets):
            try:
                return ast.literal_eval(node.value)
            except (ValueError, SyntaxError, TypeError):
                return None
    return None


def printed_words(call):
    """Every verdict word in ONE `print` argument, whether the argument is a plain string or an
    F-STRING. MEASURED LESSON: a scanner that reads only `ast.Constant` sees `print("...REFUSED")`
    and is blind to `print(f"...REFUSED...")`, and `checks/wallcheck.py:396` is the f-string --
    the very line the collision claim is about. `JoinedStr.values` holds the literal chunks, so
    the words in `{...}` holes are correctly NOT read; only the prose is."""
    words = []
    for a in call.args:
        chunks = []
        if isinstance(a, ast.Constant) and isinstance(a.value, str):
            chunks.append(a.value)
        elif isinstance(a, ast.JoinedStr):
            chunks += [v.value for v in a.values
                       if isinstance(v, ast.Constant) and isinstance(v.value, str)]
        for c in chunks:
            for w in BY_WORD:
                if re.search(rf"\b{w}\b", c):
                    words.append((w, c))
    return words


def verdict_of(node):
    """The verdict a `return` names, as a NUMBER, whether spelled as a name or as an int."""
    if not isinstance(node, ast.Constant) and not isinstance(node, ast.Name):
        return None
    if isinstance(node, ast.Name):
        return BY_WORD.get(node.id)
    v = node.value
    if isinstance(v, int) and not isinstance(v, bool) and v in gk.VERDICT:
        return v
    return None


def absent_branches(tree):
    hits = []
    for node in ast.walk(tree):
        if isinstance(node, ast.If) and ABSENT.search(ast.dump(node.test)):
            for sub in ast.walk(node):
                if isinstance(sub, ast.Return):
                    hits.append((sub.lineno, verdict_of(sub.value)))
    return [h for h in hits if h[1] is not None]


def collisions(tree):
    """A `print` and a `return` in ONE `If` body that name DIFFERENT verdicts."""
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.If):
            continue
        printed, returned = [], []
        for sub in node.body:                      # SAME branch only, in source order
            if isinstance(sub, ast.Expr) and isinstance(sub.value, ast.Call) \
                    and getattr(sub.value.func, "id", None) == "print":
                printed += [(sub.lineno, w) for w, _ in printed_words(sub.value)]
            elif isinstance(sub, ast.Return):
                # `verdict_of` ALREADY yields the NUMBER. Wrapping it in `gk.VERDICT[...]` here
                # turned it into a WORD, so `BY_WORD[w] != code` compared a number to a string
                # and every print/return pair reported as a collision. MEASURED: 3 of 3
                # "collisions" were this bug and 0 were real.
                code = verdict_of(sub.value)
                if code is not None:
                    returned.append((sub.lineno, code))
        for pl, w in printed:
            for rl, code in returned:
                if BY_WORD[w] != code:
                    out.append((pl, rl, w, code))
    return out


def label(code):
    """`gk.VERDICT[code]` raises on a code the owner's table does not contain -- and THAT is
    itself the finding, so the label falls back to naming it UNASSIGNED rather than crashing.
    MEASURED: the first collision found here returns 2, which is not one of the five."""
    return gk.VERDICT.get(code, "UNASSIGNED (not one of the five)")


def main():
    parsed = {}
    for p in sorted(files()):
        try:
            parsed[p] = ast.parse(p.read_text(errors="replace"))
        except SyntaxError:
            continue

    declared = [p for p in sorted(files()) if declares_verdicts(p) is not None]
    print(f"GATES DISCOVERED BY DECLARATION = {len(declared)}")
    print(f"OWNER TABLE, loaded from gates/gatekit.py: {gk.VERDICT}\n")

    print("=== 1. SUBJECT INVENTORY: an early return under an ABSENCE-shaped test ===")
    shaped = 0
    for p in sorted(files()):
        hits = absent_branches(parsed.get(p)) if p in parsed else []
        if hits:
            shaped += 1
            print(f"  {p.relative_to(ROOT)}  "
                  + ", ".join(f":{l} ->{gk.VERDICT[c]}" for l, c in hits))
    print(f"  ==> {shaped} file(s) can leave early with nothing to examine.\n")

    print("=== 2. TOKEN/NUMBER COLLISION inside ONE branch: prints a word, returns another ===")
    n = 0
    for p in sorted(files()):
        if p not in parsed:
            continue
        for pl, rl, w, code in collisions(parsed[p]):
            n += 1
            print(f"  {p.relative_to(ROOT)}:{pl} prints {w!r} but :{rl} returns {code} "
                  f"({label(code)})")
    print(f"  ==> {n} collision(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())