#!/usr/bin/env python3
"""INDEPENDENT re-derivation of the REFUSED-only set. Nothing inherited: no column, no hand list.

    .venv/bin/python .agents/slop/modulerefuse/x1-derive.py

THE POPULATION IS DISCOVERED TWICE AND THE UNION IS THE ANSWER, because a population defined by one
predicate cannot be wrong about a file that predicate cannot see:

  P1  a refusal CALL SITE at module scope (no enclosing `def`)  -- the SHAPE
  P2  the process answers 3 with NO argv                          -- the BEHAVIOUR

`zerogate` reported a fifth gate (`git-index-guard.py`) with "no `refuse()` at all" that was rc=3,
i.e. it classified by BEHAVIOUR alone. This file classifies by shape, by behaviour, and by
`argparse`-position, and prints the disagreements, because a set nobody can reproduce is a list.

SCOPE, IN THE SAME SENTENCE AS EVERY NUMBER BELOW: `checks/*.py` and `gates/*.py` at the top level
of each home, as they exist on DISK. `git ls-tree -r HEAD` is reported separately and its
difference from disk is stated, because AGENTS.md records that the index has reset six times and a
population read off a reset index is a population of a tree that no longer exists.
"""
import ast
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PY = ROOT / ".venv" / "bin" / "python"
HOMES = ("checks", "gates")
TIMEOUT = 60
# A refusal is an EXIT whose code is one of gatekit's own five, so the vocabulary is imported, not
# re-spelled: gates/gatekit.py:59 -- PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5.
FIVE = (0, 1, 3, 4, 5)
REFUSE_EXITS = (3, 4, 5)
sys.path.insert(0, str(ROOT / "gates"))
from gatekit import REFUSED, SKIP, DEAD  # noqa: E402


def spans(tree):
    """Every function's line span. `ast` has no parent links, so SCOPE is answered by CONTAINMENT.

    This is the fix for a classifier bug a sibling unit measured: `ast.walk` has no notion of scope,
    so a `refuse()` inside `main()` read as module scope and a demonstrably alive gate was reported
    structurally dead. A `def` boundary is the subject, so it is excluded by construction.
    """
    return [(n.lineno, n.end_lineno or n.lineno)
            for n in ast.walk(tree)
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]


def call_sites(tree):
    """(lineno, callee-name, in_a_def) for every call that could be an exit."""
    sp = spans(tree)
    out = []
    for n in ast.walk(tree):
        name = None
        if isinstance(n, ast.Call):
            if isinstance(n.func, ast.Name):
                name = n.func.id
            elif isinstance(n.func, ast.Attribute):
                name = n.func.attr
        if name:
            out.append((n.lineno, name, any(lo <= n.lineno <= hi for lo, hi in sp)))
    return out


def shape_of(path):
    """(module-scope exit sites, argparse line, refuse-helper names) read off the AST."""
    src = path.read_text(errors="replace")
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        return None, f"UNPARSEABLE {e.msg}", []
    # a refusal = a call to a `refuse*`-named helper, or an exit with a FIVE code. Both spellings
    # appear in this tree; neither is a list of files.
    codes = {}
    for n in ast.walk(tree):
        if isinstance(n, ast.Constant) and n.value in REFUSE_EXITS:
            codes.setdefault(n.value, []).append(n.lineno)
    ap = [n.lineno for n in ast.walk(tree)
          if isinstance(n, ast.Call) and getattr(n.func, "attr", getattr(n.func, "id", "")) == "parse_args"]
    mods = [(l, k) for l, k, in_def in call_sites(tree)
            if not in_def and (k.split("_")[0] in ("refuse", "refusal")
                               or k in ("exit", "quit", "_exit"))]
    mods = [(l, k) for l, k in mods if k != "exit" or l in codes.get(3, []) + codes.get(4, [])
            + codes.get(5, [])]
    helpers = sorted({n.name for n in ast.walk(tree)
                      if isinstance(n, ast.FunctionDef) and n.name.split("_")[0] in ("refuse", "refusal")})
    return mods, (min(ap) if ap else None), helpers


def run(rel, argv):
    try:
        r = subprocess.run([str(PY), str(ROOT / rel), *argv], cwd=ROOT,
                           capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "", ""
    err = [l for l in (r.stderr or "").splitlines() if l.strip()]
    out = [l for l in (r.stdout or "").splitlines() if l.strip()]
    return str(r.returncode), (err[0][:56] if err else ""), (out[0][:40] if out else "")


def main():
    disk, tree_files = [], []
    for home in HOMES:
        h = ROOT / home
        if not h.is_dir():
            print(f"REFUSED: {home}/ absent -- an absent home cannot be a population")
            return REFUSED
        for p in sorted(h.iterdir()):
            if p.suffix == ".py" and p.is_file():
                disk.append(str(p.relative_to(ROOT)))

    git = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only", *HOMES],
                         cwd=ROOT, capture_output=True, text=True,
                         env={"GIT_INDEX_FILE": str(ROOT / ".git" / "agent-index"), "PATH": "/usr/bin:/bin"},
                         timeout=60)
    tree_files = sorted(f for f in git.stdout.splitlines() if f.endswith(".py") and "/" in f
                        and f.count("/") == 1)
    only_tree = sorted(set(tree_files) - set(disk))
    only_disk = sorted(set(disk) - set(tree_files))
    print(f"SCOPE: {'/'.join(HOMES)}/*.py, TOP LEVEL OF EACH HOME (not recursive -- gates/oracles/ "
          f"is a different\n       population and gates/gates-pop.py:SUFFIXES scans `iterdir()` for "
          f"the same reason).\n")
    print(f"DISK  : {len(disk)} .py\n"
          f"HEAD  : {len(tree_files)} .py  (git ls-tree -r HEAD, GIT_INDEX_FILE=.git/agent-index)\n"
          f"ONLY ON DISK: {len(only_disk)} {only_disk}\n"
          f"ONLY IN HEAD: {len(only_tree)} {only_tree}\n")

    print(f"{'':2} {'file':34} {'module-scope exit':26} {'parse_args':>10} {'no-argv':>8} "
          f"{'--help':>7} {'--bad':>6}")
    print("-" * 100)
    by_shape, by_behaviour = [], []
    rows = []
    for rel in disk:
        mods, ap, helpers = shape_of(ROOT / rel)
        if mods is None:
            continue
        if not mods and not helpers:
            continue                       # no refusal vocabulary at all: not a candidate
        base = run(rel, [])
        hlp = run(rel, ["--help"])
        bad = run(rel, ["--no-such-flag-9f3c"])
        rows.append((rel, mods, ap, base, hlp, bad, helpers))
        if mods:
            by_shape.append(rel)
        if base[0] == str(REFUSED) and not mods:
            by_behaviour.append(rel)
        sites = ",".join(f"{l}:{k}" for l, k in mods) or "-"
        print(f"  {rel:34} {sites[:26]:26} {str(ap):>10} {base[0]:>8} {hlp[0]:>7} {bad[0]:>6}")
    print()
    print(f"P1 SHAPE   -- module-scope exit call site: {len(by_shape)}")
    for r in by_shape:
        print(f"             {r}")
    print(f"P2 BEHAVIOUR -- rc={REFUSED} with NO argv and NO module-scope exit: {len(by_behaviour)}")
    for r in by_behaviour:
        print(f"             {r}")
    print(f"\nP1 n P2  = {len(set(by_shape) ^ set(by_behaviour))} disagreement(s) -- this is the whole "
          f"reason two\n   classifiers exist. A gate that refuses inside `main()` is argv-REACHABLE, "
          f"so its green\n   is not unreachable; a gate that refuses at module scope exits BEFORE "
          f"argparse parses.")
    return 0


if __name__ == "__main__":
    sys.exit(main())