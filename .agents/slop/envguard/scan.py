#!/usr/bin/env python3
"""Which gates READ a path under `runs/` or `gates/artifacts/` with no preceding existence
check -- the defect class `runsgate` found one instance of in `checks/env-precond.py`.

POPULATION BY DISCOVERY (AGENTS.md doctrine 1): `os.walk` is not needed; the population is
exactly the top-level `checks/*.py` and `gates/*.py`, enumerated by glob, never by a hand list.

A READ SITE is a `read_text()`/`read_bytes()`/`open()` call. Its path is RESOLVED by folding
module-level `NAME = <str>` and `NAME = <expr> / "lit"` assignments, so `RUN / "x"` and
`ROOT / "runs/..."` both resolve. Anything unresolvable becomes `{NAME}`, which is HONEST: the
scanner says it could not follow the expression rather than pretending the path is not under
`runs/`. Counts are therefore a LOWER BOUND on reads under `runs/`/`artifacts/`.

GUARDED means one of, in the SAME function and BEFORE the read line:
  * `X.exists()` / `X.is_file()` whose resolved basename is the read's basename;
  * the read is inside a `try:` block;
  * a `require(...)` call -- the refusal idiom this session added, which asserts existence
    without spelling `.exists()` at the call site.
This is a heuristic, and its MISSES are named in the report; it is a population instrument,
not a gate.
"""
from __future__ import annotations

import ast
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
# `.dir` because `gatekit` publishes `Gate.dir = gates/artifacts/<name>` and every gate reads
# its lanes through it; a Name-fold cannot see `GATE.dir` (an instance attribute), so the
# TOKEN set names the shape instead of the value.
TOKEN = ("runs", "artifacts", ".dir")


def render(n: ast.AST, consts: dict[str, str]) -> str:
    if isinstance(n, ast.Constant) and isinstance(n.value, str):
        return n.value
    if isinstance(n, ast.Name):
        return consts.get(n.id, "{" + n.id + "}")
    if isinstance(n, ast.Attribute):
        return render(n.value, consts) + "." + n.attr
    if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Div):
        return render(n.left, consts) + "/" + render(n.right, consts)
    if isinstance(n, ast.JoinedStr):
        parts = []
        for v in n.values:
            parts.append(render(v.value, consts) if isinstance(v, ast.FormattedValue)
                         else (v.value if isinstance(v, ast.Constant) else "{}"))
        return "".join(parts)
    if isinstance(n, ast.Call):
        if isinstance(n.func, ast.Name) and n.func.id == "Path" and n.args:
            return render(n.args[0], consts)
        if isinstance(n.func, ast.Attribute):
            return render(n.func.value, consts)
    return "{?}"


def consts_of(tree: ast.Module) -> dict[str, str]:
    c: dict[str, str] = {}
    c["__file__"] = "{__file__}"
    for _ in range(3):                      # settle transitive NAME = NAME / "x"
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                    and isinstance(node.targets[0], ast.Name):
                c.setdefault(node.targets[0].id, render(node.value, c))
    # a second pass so a Name whose RHS used an earlier Name resolves
    c2 = {k: render(v, c) if False else v for k, v in c.items()}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                and isinstance(node.targets[0], ast.Name):
            c[node.targets[0].id] = render(node.value, c)
    return c


class Reads(ast.NodeVisitor):
    def __init__(self, consts: dict[str, str]) -> None:
        self.c = consts
        self.stack: list[ast.AST] = []
        self.sites: list[tuple[int, str, str, bool, str]] = []   # line, func, path, guarded, why

    def _func(self) -> str:
        for n in reversed(self.stack):
            if isinstance(n, ast.FunctionDef):
                return n.name
        return "<module>"

    def _guards(self, fn: ast.AST, line: int) -> list[str]:
        out = []
        for n in ast.walk(fn):
            if isinstance(n, ast.Call) and getattr(n, "lineno", 0) <= line:
                f = n.func
                if isinstance(f, ast.Attribute) and f.attr in ("exists", "is_file"):
                    out.append(render(f.value, self.c))
                elif isinstance(f, ast.Name) and f.id == "require":
                    out.extend(render(a, self.c) for a in n.args)
        return out

    def _written(self, fn: ast.AST, line: int) -> list[str]:
        """Paths this function WROTE before `line` -- a write-then-read is guarded by
        construction, and only a write-then-read is: `open(..., 'w'/'wb'/'a')` and
        `write_text()`. A read of bytes just produced cannot be a missing-input defect."""
        out = []
        for n in ast.walk(fn):
            if not isinstance(n, ast.Call) or getattr(n, "lineno", 0) > line:
                continue
            f = n.func
            if isinstance(f, ast.Attribute) and f.attr == "write_text" and n.args:
                out.append(render(f.value, self.c))
            elif isinstance(f, ast.Attribute) and f.attr == "open" and len(n.args) >= 1:
                mode = n.args[0]
                if isinstance(mode, ast.Constant) and any(c in str(mode.value) for c in "wa+"):
                    out.append(render(f.value, self.c))
            elif isinstance(f, ast.Name) and f.id == "open" and len(n.args) >= 2:
                mode = n.args[1]
                if isinstance(mode, ast.Constant) and any(c in str(mode.value) for c in "wa+"):
                    out.append(render(n.args[0], self.c))
        return out

    def _in_try(self, fn: ast.AST, line: int) -> bool:
        for n in ast.walk(fn):
            if isinstance(n, ast.Try) and n.lineno <= line <= (n.end_lineno or line):
                body_lines = {getattr(s, "lineno", 0) for b in n.body for s in ast.walk(b)}
                if line in body_lines:
                    return True
        return False

    def visit_FunctionDef(self, node):          # noqa: N802
        self.stack.append(node)
        self.generic_visit(node)
        self.stack.pop()

    def visit_Call(self, node):                 # noqa: N802
        f = node.func
        target = None
        if isinstance(f, ast.Attribute) and f.attr in ("read_text", "read_bytes"):
            target = f.value
        elif isinstance(f, ast.Name) and f.id == "open" and node.args:
            target = node.args[0]
        if target is not None:
            path = render(target, self.c)
            if any(t in path for t in TOKEN):
                fn = next((n for n in reversed(self.stack) if isinstance(n, ast.FunctionDef)),
                          None) or node
                guards = self._guards(fn, node.lineno)
                writes = self._written(fn, node.lineno)
                base = path.split("/")[-1]
                hit = [g for g in guards if g.split("/")[-1] == base]
                wrote = [w for w in writes if w.split("/")[-1] == base]
                if hit:
                    why, g = "exists:" + base, True
                elif wrote:
                    why, g = "written-before-read:" + base, True
                elif self._in_try(fn, node.lineno):
                    why, g = "in-try", True
                else:
                    why, g = "-", False
                self.sites.append((node.lineno, self._func(), path, g, why))
        self.generic_visit(node)


def main() -> int:
    files = sorted(p for pat in ("checks/*.py", "gates/*.py")
                   for p in ROOT.glob(pat) if p.is_file())
    total_reads = guarded = 0
    lines: list[str] = []
    for p in files:
        tree = ast.parse(p.read_text())
        r = Reads(consts_of(tree))
        r.visit(tree)
        for line, fn, path, g, why in r.sites:
            total_reads += 1
            guarded += 1 if g else 0
            tag = "ok  " if g else "MISS"
            lines.append(f"  {tag} {str(p.relative_to(ROOT))}:{line}  {fn}()  {path}  [{why}]")
    print(f"FILES {len(files)}  READS {total_reads}  GUARDED {guarded}  "
          f"UNGUARDED {total_reads - guarded}")
    print("(paths under runs/ or gates/artifacts/; `MISS` = no exists/is_file, no write-before-"
          "read in the same function, not in a try)\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
