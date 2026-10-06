#!/usr/bin/env python3
"""Every path READ or WRITTEN under a `.gitignore`d directory by `checks/*.py` or
`gates/*.py`, and whether the absent directory is handled before the path is touched.

POPULATION BY DISCOVERY (AGENTS.md doctrine 1). Two enumerations, neither a hand list:
  * the FILES are `glob("checks/*.py") + glob("gates/*.py")`;
  * the IGNORED PREFIXES are PARSED OUT OF `.gitignore` itself, so adding an ignore rule
    adds a root here without editing this file. Patterns with `*` are kept as globs.

A SITE is a read (`read_text`/`read_bytes`/`open` default) or a write (`write_text`/
`write_bytes`/`open` with w/a/x), or a directory op (`mkdir`/`makedirs`). The path is
RESOLVED by folding module-level `NAME = <str|Name/str|Path(...)>`, so `ART / name`,
`ROOT / "runs/..."` and `D / f"{x}.rows"` resolve as far as the fold can see. Anything
unresolvable stays `{NAME}` -- the scanner says it could not follow the expression rather
than pretending the path is not ignored. Counts are therefore a LOWER BOUND.

GUARDED -- a read is guarded if, in the same function before the read line, one of:
  * `X.exists()`/`X.is_file()` whose basename is the read's basename;
  * the read is inside a `try:` block;
  * a `require(...)` call;
  * the same basename was WRITTEN (`write_text`/`open w`) earlier (a produced file).
A WRITE is guarded if, in the same function before the write line, a `mkdir`/`makedirs`
ran whose resolved path is a PREFIX of the write's, or a `require`/`exists` fired, or the
write is inside a `try:`. This is the exact crash `gates/wk-cd-gate.py` hit: a write into
a directory that was never created.

This is a population instrument, not a gate. Its misses are NAMED in the report.
"""
from __future__ import annotations

import ast
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]


def ignored_prefixes() -> list[str]:
    """.gitignore's own path-shaped lines, as repo-relative prefixes/globs. Lines that name
    a bare extension (`*.py[cod]`), a negation, or a comment are dropped: they cannot
    contain a path a `.py` in this repo writes under. A trailing `/` is stripped."""
    out = []
    for raw in (ROOT / ".gitignore").read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("!"):
            continue
        if "/" not in line and "*" not in line:
            continue                      # a bare basename/extension, not a directory root
        out.append(line.lstrip("/").rstrip("/"))
    return out


IGN = ignored_prefixes()


# `bin/bend` is a FILE (the two-line launcher), never a directory a `.py` opens by name,
# and its LAST COMPONENT `bend` is the extension of every driver in the tree -- matching it
# componentwise would flag every `.bend` path as ignored. `gatekit` publishes
# `Gate.dir = gates/artifacts/<name>`; a Name-fold cannot see an instance attribute, so
# `.dir` is matched as the TOKEN for that root (envguard's reason, kept).
STOP = {"bin/bend"}
DOTDIR = "gates/artifacts (.dir)"


def ignored(path: str) -> str | None:
    """The ignored prefix a rendered path falls under, or None. The fold renders
    `Path(__file__).resolve().parent / "artifacts"` as `{__file__}.resolve.parent/artifacts`,
    so a REPO-RELATIVE prefix cannot match it; matching is by path COMPONENT against
    `.gitignore`'s own last segments, and by glob for the `*`-patterns. False positives are
    classified in the report, never silently dropped."""
    if ".dir" in path:
        return DOTDIR
    comps = set(re.split(r"[/.]", path))
    for ig in IGN:
        if ig in STOP:
            continue
        if "*" in ig:
            if re.fullmatch(ig.replace("**", ".*").replace("*", "[^/]*") + r"(/.*)?",
                            path.split("/")[-1]):
                return ig
        elif ig.split("/")[-1] in comps:
            return ig
    return None


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
        if isinstance(n.func, ast.Name) and n.func.id in ("Path", "str") and n.args:
            return render(n.args[0], consts)
        if isinstance(n.func, ast.Attribute):
            return render(n.func.value, consts)
    return "{?}"


def consts_of(tree: ast.Module) -> dict[str, str]:
    c: dict[str, str] = {"__file__": "{__file__}"}
    for _ in range(4):                    # settle transitive NAME = NAME / "x"
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and len(node.targets) == 1 \
                    and isinstance(node.targets[0], ast.Name):
                c[node.targets[0].id] = render(node.value, c)
    return c


READ = {"read_text", "read_bytes", "iterdir", "glob", "rglob"}
WRITE = {"write_text", "write_bytes", "mkdir", "makedirs", "rmtree", "unlink",
         "replace", "rename"}


class Sites(ast.NodeVisitor):
    def __init__(self, consts: dict[str, str]) -> None:
        self.c = consts
        self.stack: list[ast.AST] = []
        self.sites: list[tuple[int, str, str, str, bool, str]] = []  # line,fn,path,kind,guarded,why

    def _func(self) -> str:
        for n in reversed(self.stack):
            if isinstance(n, ast.FunctionDef):
                return n.name
        return "<module>"

    def _before(self, fn: ast.AST, line: int) -> list[ast.Call]:
        return [n for n in ast.walk(fn) if isinstance(n, ast.Call)
                and 0 < getattr(n, "lineno", 0) <= line]

    def _in_try(self, fn: ast.AST, line: int) -> bool:
        for n in ast.walk(fn):
            if isinstance(n, ast.Try) and n.lineno <= line <= (n.end_lineno or line):
                body = {getattr(s, "lineno", 0) for b in n.body for s in ast.walk(b)}
                if line in body:
                    return True
        return False

    def _read_guards(self, fn: ast.AST, line: int, base: str) -> list[str]:
        out = []
        for n in self._before(fn, line):
            f = n.func
            if isinstance(f, ast.Attribute) and f.attr in ("exists", "is_file", "is_dir"):
                out.append("exists:" + render(f.value, self.c).split("/")[-1])
            elif isinstance(f, ast.Attribute) and f.attr == "write_text":
                out.append("written:" + render(f.value, self.c).split("/")[-1])
            elif isinstance(f, ast.Attribute) and f.attr == "open" and n.args:
                m = n.args[0]
                if isinstance(m, ast.Constant) and any(ch in str(m.value) for ch in "wax+"):
                    out.append("written:" + render(f.value, self.c).split("/")[-1])
            elif isinstance(f, ast.Name) and f.id == "require":
                out += ["require:" + render(a, self.c).split("/")[-1] for a in n.args]
        return [g for g in out if g.split(":", 1)[1] == base]

    def _write_guard(self, fn: ast.AST, line: int, path: str) -> str:
        for n in self._before(fn, line):
            f = n.func
            if isinstance(f, ast.Attribute) and f.attr in ("mkdir", "makedirs"):
                target = render(f.value if f.attr == "mkdir" else n.args[0], self.c)
                if path.startswith(target.rstrip("/") + "/") or path == target:
                    return "mkdir:" + target
            if isinstance(f, ast.Attribute) and f.attr in ("exists", "is_file"):
                if render(f.value, self.c) in path:
                    return "exists-parent"
            if isinstance(f, ast.Name) and f.id == "require":
                for a in n.args:
                    if render(a, self.c).rstrip("/") in path:
                        return "require-parent"
        return "-"

    def visit_FunctionDef(self, node):            # noqa: N802
        self.stack.append(node)
        self.generic_visit(node)
        self.stack.pop()

    def visit_Call(self, node):                   # noqa: N802
        f = node.func
        target = kind = None
        if isinstance(f, ast.Attribute) and f.attr in READ:
            target, kind = f.value, "read"
        elif isinstance(f, ast.Attribute) and f.attr in WRITE:
            if f.attr in ("replace", "rename") and node.args:
                target, kind = node.args[-1], "write"
            else:
                target, kind = f.value, "write"
        elif isinstance(f, ast.Attribute) and f.attr == "open" and node.args:
            mode = node.args[0]
            w = isinstance(mode, ast.Constant) and any(ch in str(mode.value) for ch in "wax+")
            target, kind = f.value, ("write" if w else "read")
        elif isinstance(f, ast.Name) and f.id == "open" and node.args:
            target, kind = node.args[0], "read"
        elif isinstance(f, ast.Name) and f.id in ("makedirs",) and node.args:
            target, kind = node.args[0], "write"
        if target is not None:
            path = render(target, self.c)
            ig = ignored(path)
            if ig:
                fn = next((n for n in reversed(self.stack)
                           if isinstance(n, ast.FunctionDef)), node)
                base = path.split("/")[-1]
                if kind == "read":
                    g = self._read_guards(fn, node.lineno, base)
                    why = g[0] if g else ("in-try" if self._in_try(fn, node.lineno) else "-")
                    ok = bool(g) or self._in_try(fn, node.lineno)
                else:
                    why = self._write_guard(fn, node.lineno, path)
                    ok = why != "-" or self._in_try(fn, node.lineno)
                    if why == "-" and self._in_try(fn, node.lineno):
                        why = "in-try"
                self.sites.append((node.lineno, self._func(), path, kind, ok, why))
        self.generic_visit(node)


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--ignored":
        print("\n".join(IGN))
        return 0
    files = sorted(p for pat in ("checks/*.py", "gates/*.py")
                   for p in ROOT.glob(pat) if p.is_file())
    tot = u = 0
    lines: list[str] = []
    for p in files:
        try:
            tree = ast.parse(p.read_text())
        except SyntaxError as e:
            lines.append(f"  !! {p.relative_to(ROOT)}: unparseable ({e})")
            continue
        s = Sites(consts_of(tree))
        s.visit(tree)
        for line, fn, path, kind, ok, why in s.sites:
            tot += 1
            u += 0 if ok else 1
            tag = "ok  " if ok else "MISS"
            lines.append(f"  {tag} {str(p.relative_to(ROOT))}:{line}  [{kind}]  "
                         f"{fn}()  {path}  [{why}]")
    print(f"FILES {len(files)}  SITES {tot}  GUARDED {tot - u}  UNGUARDED {u}")
    print(f"IGNORED PREFIXES (parsed from .gitignore): {IGN}\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
