#!/usr/bin/env python3
"""THE DECLARED VERDICT VOCABULARY of every executable under `checks/` and `gates/`.

    .venv/bin/python .agents/slop/coindependent/vocab.py            # the table, to stdout
    .venv/bin/python .agents/slop/coindependent/vocab.py --rows     # same, as TSV

DOCTRINE 1, APPLIED TO THE GATES THEMSELVES. The population is DISCOVERED by `os.walk`, never a
hand list, because this instrument's one job is to make a number that nobody has written down:
**a gate with N declared verdicts of which M are reachable has an M/N real surface.**

WHAT IT READS, AND WHAT IT CANNOT. It reads each file's text. It does NOT run anything -- running
is `probe.py`'s job, and a verdict this file reports as DECLARED is not claimed reachable here.
The two columns meet in `REPORT.md`.

THE EXIT VOCABULARY is syntactic: integer literals passed to `sys.exit(...)`, `raise
SystemExit(...)`, and `return <int>` inside an `__main__`-reachable function. `gatekit`'s five
shared exits (`PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`) are attached to every file that
imports `gatekit` or the bare word `VERDICT`, because reading them off the shared module is the
one legitimate derivation available without execution.

THE TOKEN VOCABULARY is the uppercase verdict words this tree uses, found in `print`/`echo`
context. Tokens and exits are NOT the same vocabulary and the report keeps them apart -- `OK` and
`RED` are tokens with no exit, `REFUSED` is both, and a caller reading only `$?` sees only the
exits.

THIS FILE KNOWS ITS OWN BLIND SPOT AND NAMES IT: a verdict reached through `sys.exit(main())`
where `main` returns a computed value is counted as the function's `return` literals UNION the
`exit` literals of every function, so a file may be credited with an exit it cannot actually
reach. That over-count is exactly why the REACHABLE column cannot be read off this file.
"""
import ast
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
HOMES = ("checks", "gates")
SUFFIXES = (".py", ".sh")

# The verdict words this tree actually spells, and the class each belongs to. Discovery of the
# WORDS is by this set, not by any file's declaration -- the same shape as `gates/gates-pop.py`'s
# token classes, and it is a list the same way, admitted here rather than hidden.
TOKENS = ("PASS", "FAIL", "REFUSED", "SKIP", "DEAD", "OK", "RED", "GREEN", "CLEAN",
          "BROKEN", "INCOMPLETE", "UNMEASURABLE", "MISSING")
EXITWORDS = {"PASS": 0, "FAIL": 1, "REFUSED": 3, "SKIP": 4, "DEAD": 5}


def entry_reason(p: pathlib.Path) -> str:
    """`py-main` if the file has an `if __name__ == '__main__'` guard, else `lib`; for shell,
    `sh` if it self-dispatches on `$0` or `exec`s, else `lib`. AST for Python, never a regex on
    `__main__` (a regex counts prose); a self-reference for shell, because a line-anchored token
    missed 15 of 17 shell gates in `gates-pop`'s own history."""
    src = p.read_text(errors="replace")
    if p.suffix == ".py":
        try:
            tree = ast.parse(src)
        except SyntaxError:
            return "UNPARSEABLE"
        for n in ast.walk(tree):
            if isinstance(n, ast.If) and "__main__" in ast.dump(n.test):
                return "py-main"
        return "lib"
    code = re.sub(r"^\s*#.*$", "", src, flags=re.M)
    return "sh" if (re.search(r"^\s*(?:exec\b|\$\{?0)", code, re.M)
                    or re.search(r"\$\{?0\b", code)) else "lib"


def _int(node):
    # `bool` is a subclass of `int` in Python, so `sys.exit(True)` would be read as exit 1 and
    # `sys.exit(False)` as exit 0. Neither is an integer the author wrote as a verdict. Excluded.
    if isinstance(node, ast.Constant) and isinstance(node.value, int) \
            and not isinstance(node.value, bool):
        return node.value
    return None


def exits_from_python(src: str) -> set[int]:
    """Every integer an `exit`/`SystemExit`/`return` can carry, UNIONED across the file.

    Unioned rather than traced, deliberately: tracing needs a call graph and this instrument's
    honest claim is "these integers are spelled", not "this file can reach them". `probe.py`
    supplies reachability. `return <int>` is included because the tree's idiom is
    `sys.exit(main())` where `main` returns the verdict -- see `gatekit.py:main`.
    """
    out = set()
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return out
    for n in ast.walk(tree):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "exit":
            for a in n.args:
                if (v := _int(a)) is not None:
                    out.add(v)
        elif isinstance(n, ast.Raise) and n.exc is not None:
            e = n.exc
            if isinstance(e, ast.Call) and getattr(e.func, "id", None) == "SystemExit":
                for a in e.args:
                    if (v := _int(a)) is not None:
                        out.add(v)
        elif isinstance(n, ast.Return) and n.value is not None:
            if (v := _int(n.value)) is not None:
                out.add(v)
    return out


def exits_from_shell(src: str) -> set[int]:
    out = set()
    for m in re.finditer(r"\bexit\s+(\d+)", src):
        out.add(int(m.group(1)))
    for m in re.finditer(r"\breturn\s+(\d+)", src):
        out.add(int(m.group(1)))
    return out


def tokens_from(src: str) -> set[str]:
    return {w for w in TOKENS if re.search(r"\b" + w + r"\b", src)}


def uses_gatekit(src: str) -> bool:
    return bool(re.search(r"from\s+gatekit\s+import|import\s+gatekit", src)) or "VERDICT[code]" in src


def scan(root=ROOT, homes=HOMES):
    rows = []
    for home in homes:
        h = root / home
        for dirpath, dirnames, filenames in os.walk(h):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in sorted(filenames):
                if not fn.endswith(SUFFIXES):
                    continue
                p = pathlib.Path(dirpath) / fn
                src = p.read_text(errors="replace")
                reason = entry_reason(p)
                if p.suffix == ".py":
                    codes = exits_from_python(src)
                else:
                    codes = exits_from_shell(src)
                if uses_gatekit(src):
                    codes |= set(EXITWORDS.values())
                # `oracle_drift` is the tree's one additional exit a gatekit gate can carry:
                # a drifted frozen oracle is `sys.exit(2)`, and ONLY the gates that call it can
                # reach 2. Credited by the call, not by importing gatekit.
                if "oracle_drift" in src:
                    codes.add(2)
                rows.append({
                    "path": str(p.relative_to(root)),
                    "reason": reason,
                    "exits": sorted(codes),
                    "tokens": sorted(tokens_from(src)),
                    "gatekit": uses_gatekit(src),
                })
    return rows


def main(argv):
    rows = scan()
    entries = [r for r in rows if r["reason"] in ("py-main", "sh")]
    if not entries:
        print("REFUSED: empty population -- a table over 0 gates cannot be wrong", file=sys.stderr)
        return 2
    if "--rows" in argv:
        print("path\treason\tdeclared_exits\ttokens\tgatekit")
        for r in rows:
            print(f"{r['path']}\t{r['reason']}\t"
                  f"{','.join(map(str, r['exits'])) or '-'}\t"
                  f"{','.join(r['tokens']) or '-'}\t{int(r['gatekit'])}")
        return 0
    print(f"# DISCOVERED {len(rows)} file(s) under {'/'.join(HOMES)}/ "
          f"({len(entries)} entry point(s), {len(rows)-len(entries)} lib(s))\n")
    print(f"{'path':44} {'kind':8} {'exits':12} {'tokens'}")
    for r in rows:
        print(f"{r['path']:44} {r['reason']:8} "
              f"{','.join(map(str, r['exits'])) or '-':12} {','.join(r['tokens']) or '-'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
