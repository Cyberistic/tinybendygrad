"""WHICH `.bend` DRIVERS REACH AN ARGV. An AST instrument, not a grep.

The gap this unit was handed was found by a grep that MISSED `.agents/slop/graphcmp-dbg.bend`,
because that name is assembled at runtime (`SLOP / "graphcmp-dbg.bend"`, graphcmp.py:274).
A grep is therefore the wrong instrument twice over: it misses assembled names, and it fires on
prose. This one resolves constants and then asks a question a grep cannot ask --
"does this path reach a call whose body I have READ and found to invoke `subprocess.run`?"

  ast.parse drops comments entirely (they are not nodes) and marks docstrings as `Expr(Constant)`.
  So the two prose shapes the task names -- a comment, a docstring -- are structurally
  unreachable by the walk, and the only string constants it can see are ones the program
  actually evaluates into a call. That is the control, and `--control` prints the table.

Usage:  .venv/bin/python .agents/slop/driverfix/argv.py [--control]
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# A callee counted as EXECUTING a subprocess: either `subprocess.<fn>` outright, or a wrapper
# whose body has been READ and found to contain a `subprocess.run`. Every wrapper is cited so a
# reader can check the claim rather than trust it.
#   gc        -> differ.py:400   subprocess.run([PY, GCMP, *args], ...)
#   run       -> differ.py:445   `gc(*args, stdout=f, stderr=err)`  -- the step that writes an artifact
#   emit_bend -> graphcmp.py:2187 subprocess.run([BEND, str(probe or BEND_PROBE), graph], ...)
#   debug_run -> graphcmp.py:3064 subprocess.run([BEND, BEND_DBG], ...)
# `write` (differ.py:468) is DELIBERATELY ABSENT: it writes text and runs nothing. differ.py:901
# passes a driver path to `write`, and if `write` were a wrapper the control could not tell an
# invocation from a refusal message naming the very file whose absence it reports.
WRAPPERS = {
    "checks/differ.py": {"gc", "run"},
    ".agents/slop/graphcmp.py": {"emit_bend", "debug_run"},
}
SUBPROCESS_FNS = {"run", "Popen", "call", "check_output", "check_call"}

FILES = list(WRAPPERS)


# `REPO = pathlib.Path(__file__).resolve().parents[2]` is not a constant, but it is the SAME
# anchor for every path in a file, so what the population question needs -- WHICH FILE -- is in
# the tail. Resolving the anchor to a sentinel keeps the tail and loses only the prefix. Returning
# None here instead (the first revision of this instrument did) silently unbound `SLOP`, `BEND`,
# `BEND_PROBE` and `BEND_DBG` together, and the control caught it: it reported ZERO drivers in
# graphcmp.py while the file plainly holds two subprocess argv literals. A resolver that cannot
# see the filesystem must degrade to a marker, not to a hole.
ROOTLESS = "<root>"


def const(node: ast.AST, env: dict[str, str]) -> str | None:
    """Resolve a node to a path string, or None. Handles `A / "b" / "c"` over module constants."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return env.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        head, tail = const(node.left, env), const(node.right, env)
        if head is None or tail is None:
            return None
        return f"{head}/{tail}" if head else tail
    if isinstance(node, ast.Subscript):
        # `X.parents[N]` / `X.parent` -- the `resolve().parents[N]` that anchors every path in
        # graphcmp.py. Not a Call at all, which is why the first two revisions of this function
        # returned None here and unbound the whole file.
        if isinstance(node.value, ast.Attribute) and node.value.attr in {"parent", "parents"}:
            return ROOTLESS
        return None
    if isinstance(node, ast.Attribute) and node.attr in {"resolve", "parent", "parents"}:
        return ROOTLESS
    if isinstance(node, ast.Call):
        # `pathlib.Path(x)` -- an Attribute callee, not a bare Name, which is how graphcmp.py
        # spells it and why the bare-`Path` arm alone matched nothing there.
        if isinstance(node.func, ast.Attribute) and node.func.attr == "Path" and node.args:
            return const(node.args[0], env)
        if isinstance(node.func, ast.Name) and node.func.id == "Path" and node.args:
            return const(node.args[0], env)
    return None


def env_of(tree: ast.Module) -> dict[str, str]:
    """Resolvable `NAME = <const>` bindings: module-level AND function-local, in source order.

    Function-local matters for exactly one case: `probe = Path(".agents/slop/graphcmp-empty.bend")`
    at differ.py:897 is how the zero-row guard names its fixture, and `run(..., str(probe))` at
    :904 is the only place the name reaches a subprocess. A module-only env leaves the local
    unbound and the chain breaks at the hop that actually matters."""
    env: dict[str, str] = {}

    def bind(node: ast.stmt) -> None:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            v = const(node.value, env)
            if v is not None:
                env[node.targets[0].id] = v

    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign,)):
            bind(node)
    return env


def callee(node: ast.Call) -> str | None:
    f = node.func
    if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id == "subprocess":
        return f"subprocess.{f.attr}" if f.attr in SUBPROCESS_FNS else None
    return f.id if isinstance(f, ast.Name) else None


def invoked(src: str) -> list[tuple[str, str, int]]:
    """(driver_path, call_site, line) for every `.bend` path that reaches an executing call."""
    rel = src
    tree = ast.parse(Path(ROOT / rel).read_text(), filename=rel)
    env = env_of(tree)
    wrappers = WRAPPERS[rel]
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        c = callee(node)
        if isinstance(node.func, ast.Name):
            c = node.func.id
        # ACCEPT ONLY AN EXECUTING CALLEE. The first revision tested `if c is None and ...`, so a
        # bare `Path(".agents/slop/graphcmp-empty.bend")` -- an ASSIGNMENT at differ.py:897, not an
        # invocation -- scored as a hit and the control's "HIT" column became meaningless.
        if not (c and c.startswith("subprocess.")) and c not in wrappers:
            continue
        # argv-bearing positions: subprocess.run's LIST literal, or any positional arg of a wrapper
        args = []
        if c and c.startswith("subprocess.") and node.args and isinstance(node.args[0], ast.List):
            args = node.args[0].elts
        else:
            args = list(node.args)
        for a in args:
            for piece in (a.elts if isinstance(a, ast.List) else [a]):
                if isinstance(piece, ast.Call) and isinstance(piece.func, ast.Name) and piece.func.id == "str":
                    piece = piece.args[0] if piece.args else piece
                if isinstance(piece, ast.BinOp) and isinstance(piece.op, ast.BitOr):  # `probe or BEND_PROBE`
                    piece = piece.right
                v = const(piece, env)
                if v and v.endswith(".bend"):
                    out.append((v, f"{c or '?'}", node.lineno))
    return sorted(set(out))


def main() -> int:
    control = "--control" in sys.argv
    hits: dict[str, set[str]] = {}
    for rel in FILES:
        print(f"\n== {rel}")
        for path, site, line in invoked(rel):
            hits.setdefault(path.split("/")[-1], set()).add(site)
            print(f"   {path}   <- {site}() at line {line}")

    print("\n== DRIVERS REACHING AN EXECUTING CALL")
    for k in sorted(hits):
        print(f"   HIT   {k:24s} {sorted(hits[k])}")

    # ---- THE CONTROL. A grep census of the same two names, so the difference is visible. ----
    print("\n== CONTROL: every textual mention of the two drivers, classified")
    names = ("graphcmp-dbg.bend", "graphcmp-empty.bend")
    reached = {p.split("/")[-1]: (f"{rel}:{ln}") for p, rel, ln in
               [(a, b, c) for b in FILES for a, _, c in invoked(b)]}
    for rel in FILES:
        for i, line in enumerate(Path(ROOT / rel).read_text().splitlines(), 1):
            for n in names:
                if n in line:
                    kind = "HIT   " if reached.get(n) == f"{rel}:{i}" else "prose "
                    print(f"   {kind}{rel}:{i}  {line.strip()[:78]}")

    want = {"graphcmp-dbg.bend", "graphcmp-empty.bend"}
    got = set(hits)
    ok = got >= want
    print(f"\nCONTROL {'PASS' if ok else 'FAIL'}: found {sorted(got)}; required both of {sorted(want)}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())