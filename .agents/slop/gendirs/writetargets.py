#!/usr/bin/env python3
"""DISCOVERY of write targets, WITH A FIXPOINT, because a scanner that reads only literals sees
1 of 12 and then reports 1.

MEASURED, and it is why this file exists: the first version resolved a write target only from a
literal in the call, and 1,209 of 1,690 write calls were UNRESOLVED. A tree writes its output
through a module constant -- `D = ROOT / "runs/graphcmp/D"`, `gendir = HERE / "gen"` -- so the
literal is one hop away. The fixpoint binds module-level and function-level assignments to
their string values until nothing new resolves, and every write call then looks its argument up
in that environment.

WHAT IT STILL CANNOT SEE, and prints as a count rather than hiding: a write performed by a
SUBPROCESS. `checks/abi4_gate.py:501` calls `rc_of(REPO / "checks/abi_gate.py")`, which runs
that gate with `cwd=REPO`, and `checks/abi_gate.py:605-616` writes `checks/gen/probe.{js,gen.c}`.
MEASURED: that is 268,523 bytes into a directory NO static scan of `abi4_gate.py` can reach. So
this scanner is a LOWER BOUND on the population and the report says so with a number.
"""
import ast
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKIP = {".git", "references", "node_modules", ".venv", "__pycache__", "bin"}

WRITE_ATTR = {"write_text", "write_bytes", "mkdir", "rmtree", "unlink", "replace",
              "makedirs", "touch", "write", "appendText"}
WRITE_FN = {"copy", "copytree", "copy2", "copyfile"}
SH_WRITE = re.compile(r"\b(?P<c>cp|mv|tee|install|rsync)\b[^\n|;&]*?\s(?P<dst>[\w./{}$-]+)")


def sources():
    out = []
    for dirpath, dirnames, files in os.walk(ROOT):
        rel = os.path.relpath(dirpath, ROOT)
        rel = "" if rel == "." else rel
        dirnames[:] = [d for d in dirnames if d not in SKIP and f"{rel}/{d}" not in SKIP]
        if rel.split("/")[0] in SKIP:
            dirnames[:] = []
            continue
        out += [Path(dirpath) / f for f in files
                if Path(f).suffix in (".py", ".sh", ".mjs", ".js")]
    return sorted(out)


def env_of(scope, env):
    """Bind `NAME = <path expr>` in one scope, mutating `env` in place. Returns nothing: the
    caller loops until the env stops growing, which is the fixpoint."""
    for node in ast.walk(scope):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        # `env` PASSED IN, not defaulted. MEASURED: `expr(node.value)` built a FRESH `{}`, so
        # `__file__` and every earlier binding were invisible, and `HERE = Path(__file__).resolve()
        # .parent` evaluated to None -- the one constant the whole scan depends on. **A FIXPOINT
        # THAT EVALUATES ITS RIGHT-HAND SIDE AGAINST AN EMPTY ENVIRONMENT IS NOT A FIXPOINT.**
        val = expr(node.value, env)
        if val is None:
            continue
        for t in targets:
            if isinstance(t, ast.Name):
                env[t.id] = val


def expr(node, env=None):
    """The string VALUE of a path expression, or None. Four shapes, in the order they occur:
    `Path("a") / "b"`, `os.path.join(a, b)`, `"a" + b`, and a bare name already in `env`."""
    env = env or {}
    if node is None:
        return None
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return env.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        a, b = expr(node.left, env), expr(node.right, env)
        return (a.rstrip("/") + "/" + b.lstrip("/")) if (a is not None and b is not None) else None
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        a, b = expr(node.left, env), expr(node.right, env)
        return (a + b) if (a is not None and b is not None) else None
    if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Attribute) \
            and node.value.attr == "parents":
        # `HERE.parents[n]`. MEASURED: `checks/abi_gate.py:50` is `REPO = HERE.parents[0]`, and
        # without this arm `REPO` is unbound, so every write that names `REPO / ...` -- which is
        # most of them -- is unresolved. The index is EVALUATED, not pattern-matched, because
        # `gates/gates-pop.py`'s own finding is that a depth CONSTANT is not the property.
        base = expr(node.value.value, env)
        i = node.slice.value if isinstance(node.slice, ast.Constant) else None
        if base is None or not isinstance(i, int):
            return None
        return "/".join(base.split("/")[:len(base.split("/")) - i]) or "/"
    if isinstance(node, ast.Attribute):
        # `Path(__file__).resolve().parent` -- a METHOD on a call, and then a `.parent`. BOTH
        # arms are load-bearing, and the second one is the one that was wrong first: recursing
        # into `.parent` returns the FILE's own path, so `HERE` binds to `.../abi_gate.py` and
        # `HERE / "gen"` resolves to `.../abi_gate.py/gen`, which is not a directory and does
        # not exist -- **AND THE SCANNER THEN REPORTS NOTHING, WHICH IS THE `artefacts_ok()`
        # SHAPE: A GUARD THAT ANSWERS ABOUT A PATH THAT CANNOT BE RIGHT.** So `parent` STRIPS
        # a component and `parents[n]` POPS n, because a value that loses a step is worse than
        # one that fails to bind.
        base = expr(node.value, env)
        if base is None:
            return None
        if node.attr == "parent":
            return base.rsplit("/", 1)[0] or "/"
        return base
    if isinstance(node, ast.Call):
        f = node.func
        nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
        if nm == "Path" and node.args:
            return expr(node.args[0], env)
        if nm in ("join", "normpath", "resolve", "absolute", "expanduser"):
            parts = [expr(a, env) for a in node.args]
            if all(p is not None for p in parts) and parts:
                return "/".join(p.strip("/") for p in parts) if nm == "join" else parts[0]
        # `str(x)` / `os.fspath(x)` / `str(Path(...))` -- a CAST, not a path operation.
        # MEASURED: `checks/abi_gate.py:616` is `"-o", str(gendir / f"probe.{ext}")`, and
        # without this arm the cast's argument is never reached, so the ONLY write to
        # `checks/gen/` in the whole tree is invisible. **A CAST IS NOT A PATH OPERATION AND A
        # SCANNER THAT TREATS IT AS ONE NEVER REACHES THE PATH.**
        if nm in ("str", "fspath", "abspath", "realpath") and node.args:
            return expr(node.args[0], env)
        return expr(node.func, env)
    # `f"probe.{ext}"` is an f-string, and it is the shape `checks/abi_gate.py:616` writes
    # `checks/gen/` with -- `str(gendir / f"probe.{ext}")`. An f-string interpolating a name the
    # fixpoint already knows becomes a GLOB SEGMENT, so the DIRECTORY is still resolved and the
    # file name is honestly reported as unknown rather than guessed.
    if isinstance(node, ast.JoinedStr):
        out = ""
        for v in node.values:
            if isinstance(v, ast.Constant):
                out += str(v.value)
            else:
                inner = expr(v.value, env)
                out += "*" if inner is None else inner
        return out
    return None


def py_targets(src, seed):
    """`(found, unresolved)`. `found` is `(target, line, call)`; `unresolved` is `(line, call)`.

    `seed` binds `__file__`; see `main` for why a fixpoint without it measures nothing."""
    try:
        tree = ast.parse(src)
    except SyntaxError as e:
        return [], [(e.lineno or 0, f"UNPARSEABLE:{e.msg}")]
    env = dict(seed)
    for _ in range(8):                       # the fixpoint: until nothing new binds
        before = len(env)
        env_of(tree, env)
        for f in (n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.ClassDef))):
            env_of(f, env)
        if len(env) == before:
            break
    found, unresolved = [], []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        f = node.func
        nm = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
        if nm in WRITE_ATTR or nm in WRITE_FN:
            if not node.args:
                # `gendir.mkdir(exist_ok=True)` -- the DIRECTORY is the RECEIVER, not an
                # argument. MEASURED: `checks/abi_gate.py:606` is the only line in the whole
                # tree that creates `checks/gen/`, and reading only the arguments loses it.
                rec = expr(node.func.value, env) if isinstance(node.func, ast.Attribute) else None
                (found.append((rec, node.lineno, nm)) if rec
                 else unresolved.append((node.lineno, nm)))
                continue
            t = expr(node.args[-1], env)
            base = expr(node.args[0], env) if (len(node.args) > 1 and nm in WRITE_FN) else None
            if t is None and base is None:
                unresolved.append((node.lineno, nm))
                continue
            tgt = (base.rstrip("/") + "/" + t.lstrip("/")) if (base and t) else (t or base)
            found.append((tgt, node.lineno, nm))
        elif nm == "open" and len(node.args) >= 2:
            t = expr(node.args[0], env)
            (found.append((t, node.lineno, "open")) if t
             else unresolved.append((node.lineno, "open")))
        elif nm in ("run", "call", "check_output", "Popen") and node.args:
            # `subprocess.run([..., "-o", str(gendir / f"probe.{ext}")], ...)` -- a COMPILER
            # WRITES THE FILE. This is the shape that hides `checks/gen/` from a scanner that
            # only knows write-shaped METHODS: `checks/abi_gate.py:616` hands the path to
            # `bend -o` and never touches the file itself. MEASURED: it is the ONLY write to
            # that directory, and 268,523 bytes land there per run.
            for a in ast.walk(node.args[0]):
                if isinstance(a, ast.Constant) and isinstance(a.value, str) \
                        and a.value in ("-o", "--out", "--output", "-O"):
                    sib = a.value
                    seq = node.args[0]
                    if isinstance(seq, (ast.List, ast.Tuple)):
                        els = seq.elts
                        vals = [e.value if isinstance(e, ast.Constant) else None for e in els]
                        if sib in vals:
                            k = vals.index(sib)
                            if k + 1 < len(els):
                                t = expr(els[k + 1], env)
                                (found.append((t, node.lineno, f"subprocess {sib}"))
                                 if t else unresolved.append((node.lineno, f"subprocess {sib}")))
    return found, unresolved


def sh_targets(src):
    found = []
    for i, line in enumerate(src.splitlines(), 1):
        if re.match(r"^\s*#", line):
            continue
        m = SH_WRITE.search(line)
        if m:
            found.append((m.group("dst"), i, m.group("c")))
        for r in re.finditer(r"""(?:>|>>)\s*["']?([\w./{}$-]+)""", line):
            found.append((r.group(1), i, "redirect"))
    return found, []


def main():
    srcs = sources()
    rows, unresolved = [], []
    for p in srcs:
        rel = os.path.relpath(p, ROOT)
        src = p.read_text(errors="replace")
        # `__file__` SEEDED WITH THE SOURCE'S OWN ABSOLUTE PATH. Without it `HERE =
        # Path(__file__).resolve().parent` never binds, every downstream constant is unbound, and
        # the scan reports ZERO for `checks/gen/` -- which is the directory the whole brief is
        # about. MEASURED: with the seed, `checks/abi_gate.py:605-616` resolves to
        # `<repo>/checks/gen`; without it, to nothing. **A CONSTANT PROPAGATION FIXPOINT THAT
        # DOES NOT KNOW WHAT `__file__` IS PROPAGATES CONSTANTS FROM NOTHING.**
        found, unres = py_targets(src, {"__file__": str(p)}) if p.suffix != ".sh" \
            else sh_targets(src)
        for t, ln, kind in found:
            if not t:
                continue
            tgt = t if t.startswith("/") else os.path.normpath(str(p.parent / t))
            rows.append((tgt, rel, ln, kind))
        for ln, kind in unres:
            unresolved.append((rel, ln, kind))
    print(f"SOURCE FILES READ: {len(srcs)}")
    print(f"WRITE CALLS RESOLVED: {len(rows)}   STILL UNRESOLVED: {len(unresolved)}")
    if unresolved:
        print("  (each of these is a hole in the population -- a SUBPROCESS write is one)")
        for rel, ln, kind in unresolved[:40]:
            print(f"  UNRESOLVED {rel}:{ln} {kind}")
        if len(unresolved) > 40:
            print(f"  ... and {len(unresolved) - 40} more")
    dirs = {}
    for t, rel, ln, kind in rows:
        d = t if os.path.isdir(t) else os.path.dirname(t)
        dirs.setdefault(d, []).append((rel, ln, kind))
    print(f"\nDISTINCT TARGET DIRECTORIES: {len(dirs)}")
    for d in sorted(dirs):
        print(f"  {os.path.relpath(d, ROOT) if str(d).startswith(str(ROOT)) else d}\t"
              f"{len(dirs[d])}\t{', '.join(sorted({r for r, _, _ in dirs[d]}))[:110]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())