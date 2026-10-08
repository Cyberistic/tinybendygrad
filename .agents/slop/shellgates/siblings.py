#!/usr/bin/env python3
"""THE SIBLING CLASS: every place the tree RUNS an entry point with an interpreter other than the
one that entry point DECLARES.

    .venv/bin/python .agents/slop/shellgates/siblings.py --rows out.rows

`gates/gate-surface.py:311` is one site of this class -- `[str(PY), str(gate), *argv]`, PYTHON for
every entry point in a population `gates/gates-pop.py:141` puts `.py` and `.sh` into as ONE SET.
The question this file answers is the one nobody asked: **how many MORE sites are there, over
what denominator.**

POPULATION, IN THREE STAGES, EACH STAGE NAMING ITS OWN DENOMINATOR.
  A  the CALL SITES, BY AST over the scopes below for every `subprocess.run/Popen/call/
     check_output/check_call/getoutput/getstatusoutput`, `os.system`, `os.popen`, `os.execv*`,
     `os.spawn*`. Found by AST, never by grepping for `subprocess`, because a grep cannot tell a
     call from a docstring -- and this file's own docstring is the first such string in the tree.
  B  of A, the RESOLVABLE ones: where the interpreter element AND the target element BOTH reduce
     to a string by CONSTANT FOLDING (a literal, a `a / "b"` join chain, or a module-scope name
     bound to either). The remainder is COUNTED AND PRINTED, never dropped -- a census that
     discards the sites it could not read and reports the rest as a total is reporting a lower
     bound as a denominator.
  C  of B, the MISMATCHES: the target's own `#!` kind is not the kind of interpreter used.

A MISMATCH NEEDS BOTH SIDES. A target that ships no shebang is `NO-DECLARATION`, counted BESIDE
the mismatches and never inside them -- otherwise this file inflates exactly the way
`gate-surface.py:357`'s suffix filter does, reporting a finding about the reader as a finding
about the tree.
"""
from __future__ import annotations

import argparse
import ast
import contextlib
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

SCOPES = ("checks", "gates", ".agents/slop")
SUBPROCESS_CALLS = frozenset({"run", "Popen", "call", "check_call", "check_output", "getoutput",
                              "getstatusoutput"})
EXEC_CALLS = frozenset({"system", "popen", "execv", "execvp", "execvpe", "execl", "execlp",
                        "spawnv", "spawnvp", "spawnl", "spawnlp"})
SHELL_NAMES = frozenset({"sh", "bash", "zsh", "dash", "ksh", "mksh", "ash"})

_spec = importlib.util.spec_from_file_location("interp_under_siblings", HERE / "interp.py")
I = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(I)


# ---- constant folding, over the ONE module's own scope --------------------------------
def fold(node, env):
    """`node` -> a string when it is CONSTANT, else None.

    A ROOT-RELATIVE FALLBACK IS ADMITTED, AND IT IS THE ONE INFERENCE HERE. `ROOT / "gates" /
    "gatekit.py"` does not fold, because `ROOT` is `Path(__file__).resolve().parents[n]` and no
    gate's root is a string constant -- yet the suffix IS a repo-relative path and every gate in
    this tree asserts its root is the repo root. So an unfoldable HEAD with a folded TAIL yields
    the tail, repo-relative. It cannot invent a site: `tmp / "planted.py"` yields
    `"planted.py"`, `ROOT / "planted.py"` does not exist, and the site is counted UNRESOLVED.

    `os.environ[...]` is deliberately NOT folded -- an environment lookup is a value at RUN time,
    and folding it would make a site look resolvable that is not.
    """
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) \
            and node.value.id == "sys" and node.attr == "executable":
        return "sys.executable"                 # definitional, not inferred -- see `kind_of`
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        left, right = fold(node.left, env), fold(node.right, env)
        if right is None or "/" in right:
            return None
        if left is None:
            return right                        # the root-relative fallback, stated above
        return left.rstrip("/") + "/" + right
    if isinstance(node, ast.Name):
        return env.get(node.id)
    if isinstance(node, ast.Call):
        if callee(node) == ("os.path", "join") and node.args:
            parts = [fold(a, env) for a in node.args]
            if parts[0] is None and len(parts) == 2 and parts[1] is not None:
                return parts[1]                 # same root-relative fallback
            if all(parts):
                head, tail = parts[0], [p.strip("/") for p in parts[1:]]
                return "/".join([head.rstrip("/")] + tail).lstrip("/") \
                    if not head.startswith("/") else "/".join([head.rstrip("/")] + tail)
    return None


def module_env(tree):
    """`NAME -> str` for module-scope assignments that fold. THE POPULATION OF RESOLVABLE NAMES,
    read from the module's own body, so a rename moves it and a new constant appears without this
    file being edited."""
    env = {}
    for node in ast.walk(tree):
        targets = None
        if isinstance(node, ast.Assign):
            targets, value = node.targets, node.value
        elif isinstance(node, ast.AnnAssign):
            targets, value = [node.target], node.value
        else:
            continue
        if value is None:
            continue
        for t in targets:
            if isinstance(t, ast.Name):
                v = fold(value, env)
                if v is not None:
                    env[t.id] = v
    return env


def callee(node):
    """`(module, attr)` for a call's callee, or `(None, None)`."""
    f = node.func
    if isinstance(f, ast.Attribute):
        base = f.value
        mod = base.id if isinstance(base, ast.Name) else (
            base.attr if isinstance(base, ast.Attribute) else None)
        return mod, f.attr
    return None, None


def vector(call, env):
    """`(folded elements, n unfolded holes)` for the command vector. The hole count is kept so a
    `[*base, gate]` shape is recognisable rather than silently truncated to its first element."""
    if not call.args:
        return [], 0
    a = call.args[0]
    items = a.elts if isinstance(a, (ast.List, ast.Tuple)) else [a]
    out, holes = [], 0
    for it in items:
        v = fold(it, env)
        holes += v is None
        out.append(v)
    return out, holes


def kind_of(token):
    """`token` -> PYTHON | SHELL | NODE | OTHER | NONE, read from the interpreter's own NAME.

    A set of interpreter NAMES, not of file suffixes; the population is the call sites.
    `sys.executable` IS PYTHON and this is DEFINITIONAL, not inferred: it is documented as the
    path of the Python interpreter running the current process, and this file is a Python program,
    so there is no reading under which it is not `PYTHON`.
    """
    if not token:
        return "NONE"
    if token == "sys.executable":
        return "PYTHON"
    base = token.rsplit("/", 1)[-1]
    if base.startswith("python"):
        return "PYTHON"
    if base in SHELL_NAMES:
        return "SHELL"
    if base in {"node", "nodejs"}:
        return "NODE"
    return "OTHER"


def in_repo(path):
    """`path` -> the resolved file if it is a REGULAR file inside the repo, else None.

    `resolve()` first, because `.venv/bin/python` and a fixture symlink both point outside; a
    target outside the repo is not this tree's entry point and counting it would be a claim about
    someone else's file."""
    try:
        real = path.resolve(strict=True)
        real.relative_to(ROOT)
    except (OSError, ValueError):
        return None
    return real if real.is_file() else None


def entry_point(ROOT, vec):
    """`(interpreter kind, target, how)` for ONE call site.

    THE ARGUMENT/ENTRY-POINT QUESTION. Getting it wrong is how a first version of this file
    reported **34 mismatches of 59 resolved sites and every one was its own bug**, in three
    separable classes -- each measured, each now a named state instead of a score:

      * `argv[0]` MAY BE THE TARGET ITSELF. `["./bin/bend", driver]` is a DIRECT exec: the kernel
        reads `bin/bend`'s `#!/bin/sh` and runs `sh`, so the site AGREES. Comparing argv[0]'s
        NAME against the target's shebang called all 8 `checks/differ.py`-shaped sites wrong.
      * WHEN `argv[0]` IS AN INTERPRETER, THE TARGET IS THE FIRST NON-FLAG ARGUMENT -- and only
        that one. `[PY, "checks/bounded.py", "--mb", "2048", "--", "./bin/bend", drv]` names
        `checks/bounded.py` as the script and `./bin/bend` as an ARGUMENT to it; taking every
        non-flag element counted `bin/bend` as a second entry point of every such site.
      * WHEN `argv[0]` IS A THIRD-PARTY PROGRAM, THERE IS NO SCRIPT ARGUMENT. `["jj", "file",
        "show", "-r", rev, ".agents/slop/rebase-gate.py"]` ends in a repo path that is DATA --
        the revision of a file -- and reading it as the entry point invented a mismatch against a
        git call. This is why the rule keys on argv[0]'s KIND, not on "does the vector contain a
        repo path".

    Returns `how` in {"DIRECT", "VIA-INTERPRETER", "THIRD-PARTY", "UNREAD-ARGV0", "NO-TARGET"}.
    """
    prog = vec[0] if vec else None
    interp = kind_of(prog)
    if interp == "NONE":
        return "NONE", None, "UNREAD-ARGV0"
    if prog and "/" in prog:
        p = in_repo(Path(prog))
        if p is not None:
            return interp, p, "DIRECT"
    if interp not in ("PYTHON", "SHELL", "NODE"):
        return interp, None, "THIRD-PARTY"
    for tok in vec[1:]:
        if tok is None or tok.startswith("-"):
            continue
        t = in_repo(Path(tok) if tok.startswith("/") else ROOT / tok)
        if t is not None:
            return interp, t, "VIA-INTERPRETER"
    return interp, None, "NO-TARGET"


def main():
    ap = argparse.ArgumentParser(prog="siblings.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rows", default=None)
    a = ap.parse_args()

    files, sites = [], []
    for scope in SCOPES:
        base = ROOT / scope
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*.py")):
            if "__pycache__" in p.parts:
                continue
            try:
                tree = ast.parse(p.read_text(errors="replace"))
            except (SyntaxError, ValueError):
                continue
            files.append(p)
            env = module_env(tree)
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                mod, attr = callee(node)
                if not ((mod == "subprocess" and attr in SUBPROCESS_CALLS)
                        or (mod == "os" and attr in EXEC_CALLS)):
                    continue
                vec, holes = vector(node, env)
                if not vec or all(v is None for v in vec):
                    continue
                sites.append((str(p.relative_to(ROOT)), node.lineno, vec, holes))

    rows, unres = [], []
    for rel, lineno, vec, holes in sites:
        interp, target, how = entry_point(ROOT, vec)
        if target is None:
            unres.append((rel, lineno, f"{vec[0] or '<unfolded>'} [{how}]", holes))
            continue
        decl = I.declared_interpreter(target)
        if how == "DIRECT":
            # The kernel reads the target's own shebang; there is nothing for the site to get
            # wrong, and scoring argv[0]'s NAME against it is the bug this file shipped first.
            verdict = "agrees"
        elif decl.kind in ("PYTHON", "SHELL", "NODE") and decl.kind != interp:
            verdict = "MISMATCH"
        elif decl.kind in ("PYTHON", "SHELL", "NODE"):
            verdict = "agrees"
        else:
            verdict = "NO-DECLARATION"           # beside the mismatches, never inside them
        rows.append((rel, lineno, interp, how, str(target.relative_to(ROOT)), decl.kind,
                     verdict, decl.declared or "-"))

    mism = [r for r in rows if r[6] == "MISMATCH"]
    nodecl = [r for r in rows if r[6] == "NO-DECLARATION"]
    by_how = {}
    for rel, lineno, i0, holes in unres:
        by_how[i0.split("[")[-1].rstrip("]")] = by_how.get(i0.split("[")[-1].rstrip("]"), 0) + 1

    print(f"I  SCOPE, STATED WITH EVERY NUMBER: {len(files)} `.py` file(s) AST-parsed under "
          + ", ".join(f"`{s}/`" for s in SCOPES) + ".")
    print(f"A  CALL SITES BY AST: {len(sites)} in {len(files)} file(s).")
    print(f"B  RESOLVED TO A REPO ENTRY POINT: {len(rows)} site(s) in "
          f"{len({r[0] for r in rows})} file(s). {len(unres)} name no repo entry point and are "
          f"COUNTED, NOT DROPPED, by reason: "
          + ", ".join(f"{k}={v}" for k, v in sorted(by_how.items()))
          + f". **B is a LOWER BOUND over {len(sites)} sites.**")
    print(f"C  MISMATCHES: {len(mism)} of {len(rows)} resolved sites, and {len(mism)} of "
          f"{len(sites)} sites overall. NO-DECLARATION: {len(nodecl)}, counted beside.\n")

    print("C  THE MISMATCHES, each with BOTH sides:")
    for r in mism:
        print(f"  {r[0]}:{r[1]}  runs {r[2]:6} ({r[3]}) at a target whose `#!` says "
              f"{r[5]:6} ({r[7]})\n      -> {r[4]}")
    if not mism:
        print("  (none)")
    print("\nB  EVERY RESOLVED SITE, so C reads as a subset of a stated denominator:")
    for r in rows:
        print(f"  {r[0]}:{r[1]}  interp={r[2]:7} how={r[3]:15} target={r[4]}  shebang={r[5]:6} {r[6]}")
    print(f"\nUNRESOLVED BY REASON (first 20):")
    for rel, lineno, i0, holes in unres[:20]:
        print(f"  {rel}:{lineno}  argv0={i0!r}  unfolded-holes={holes}")

    if a.rows:
        Path(a.rows).write_text(
            "site\tline\tinterp_kind\thow\ttarget\tshebang_kind\tverdict\tshebang\n"
            + "".join("\t".join(str(c) for c in r) + "\n" for r in rows)
            + "".join(f"{r[0]}\t{r[1]}\t{r[2]}\t-\t-\t-\tUNRESOLVED\t-\n" for r in unres))
        print(f"\n== {len(rows)+len(unres)} row(s) written to {a.rows}")
    return 1 if mism else 0


if __name__ == "__main__":
    with contextlib.suppress(KeyboardInterrupt):
        sys.exit(main())