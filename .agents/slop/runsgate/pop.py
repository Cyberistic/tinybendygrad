#!/usr/bin/env python3
"""The population of gate INPUTS that live under a `.gitignore` rule.

DOCTRINE 1: the population is DISCOVERED, not listed. This walks the three
file sets the task names (`checks/*.sh`, `checks/*.py`, `gates/*.py`) and pulls
every STRING LITERAL (.py, via AST) and every WORD TOKEN (.sh, via regex) that
resolves to a path inside the repo and names a `runs/` or `gates/artifacts/`
component. Then, for each DISTINCT resolved path, it asks three questions:

  named    is it named by some file's source?              (the read/write site)
  present  is it on disk right now?                        (os.path)
  ignored  does `git check-ignore` say a rule names it?    (git)
  tracked  does `git ls-files` say the index holds it?     (git)

A file that is `present and ignored and not tracked` is the defect: a gate can
read it here and cannot see it in a clone.

READ vs WRITE is NOT decided here. It cannot be decided by a string literal's
shape, and gendirs.py already owns write-site discovery. This instrument's job
is the DENOMINATOR the two prior units never took.
"""
import ast
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def git(*args):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


# A READ names a file the code CONSUMES; a WRITE names one it PRODUCES. The classifier
# is a TOKEN, not a call-graph -- it is honest about being a lower bound, and it is why
# every row below is also printed with the site so a human can overrule it.
READ_TOKENS = ("read_text", "read_bytes", "read()", "open(", "json.load", "loads(",
               ".exists", "is_file", "is_dir", "iterdir", "rglob", "glob(",
               "ls-files", "check-ignore", "cat ", "cp ", "[ -f", "[ -e",
               "grep ", "diff ", "pathlib.Path(", "Path(")
WRITE_TOKENS = ("write_text", "write_bytes", "mkdir", "write(", "rm ", "unlink",
                "rmtree", "replace(", "copyfile", "copytree", "> ", "dump(")


def classify(line):
    has_r = any(t in line for t in READ_TOKENS)
    has_w = any(t in line for t in WRITE_TOKENS)
    if has_r and not has_w:
        return "READ"
    if has_w and not has_r:
        return "WRITE"
    if has_r and has_w:
        return "BOTH"
    # A path BOUND to a NAME is a citation of an input (`ORACLE=...`, `D=...`): the
    # name is what the read sites use. A bare comment mention stays CITE.
    if re.match(r"\s*[A-Za-z_][A-Za-z0-9_]*\s*[:=]", line):
        return "READ"
    return "CITE"


def py_literals(path):
    """(str, lineno, line_text) for every string literal in a .py file. AST, so a string
    in a comment or a docstring is INCLUDED (a docstring naming a path is a citation)."""
    src = path.read_text()
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return
    lines = src.splitlines()
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            txt = lines[node.lineno - 1] if 0 < node.lineno <= len(lines) else ""
            yield node.value, node.lineno, txt


SH_WORD = re.compile(r"[A-Za-z0-9_./~$-]*/[A-Za-z0-9_./{}$-]*")


def sh_literals(path):
    """Every shell word token containing a `/`. Crude on purpose: a shell token is
    not parseable without the shell, and a MISSED token is a population that shrank."""
    for i, line in enumerate(path.read_text().splitlines(), 1):
        for m in SH_WORD.finditer(line):
            yield m.group(0), i, line


def candidates(text):
    """Yield plausible repo-relative path prefixes found in a string. We do NOT try to
    reconstruct `$ROOT/...`; we look for the substring that starts at `runs/` or
    `gates/artifacts/`, which is the part `.gitignore` cares about."""
    out = []
    for marker in ("runs/", "gates/artifacts/", "checks/gen/", "checks/rows-",
                   "checks/check.out"):
        idx = 0
        while (i := text.find(marker, idx)) != -1:
            tail = text[i:]
            # trim at a quote, space, `>`, `)`, `"`, `'`, or backtick
            tail = re.split(r"[\s\"'`)>|;:]", tail, 1)[0]
            # trim a trailing shell/comma artifact
            tail = tail.rstrip(".,")
            if tail:
                out.append(tail)
            idx = i + len(marker)
    return out


def main():
    files = (sorted((ROOT / "checks").glob("*.sh"))
             + sorted((ROOT / "checks").glob("*.py"))
             + sorted((ROOT / "gates").glob("*.py")))
    paths = {}   # resolved rel path -> list of (file:line, class)
    for f in files:
        lits = py_literals(f) if f.suffix == ".py" else sh_literals(f)
        for text, ln, line in lits:
            for cand in candidates(text):
                rel = str(Path(cand))
                if rel.startswith("./"):
                    rel = rel[2:]
                paths.setdefault(rel, []).append((f"{f.name}:{ln}", classify(line)))

    rows = []
    for rel in sorted(paths):
        p = ROOT / rel
        present = p.exists()
        ignored = bool(git("check-ignore", "--", rel).strip())
        tracked = bool(git("ls-files", "--", rel).strip())
        sites = sorted(set(paths[rel]))
        reads = sorted(ln for ln, c in sites if c == "READ")
        rows.append((rel, present, ignored, tracked, reads, sites))

    n_named = len(rows)
    n_read = sum(1 for r in rows if r[4])
    n_ignored = sum(1 for r in rows if r[2])
    n_tracked = sum(1 for r in rows if r[3])
    defect = [r for r in rows if r[4] and r[1] and r[2] and not r[3]]
    print(f"POPULATION  {n_named} distinct paths named across {len(files)} files "
          f"({sum(1 for f in files if f.suffix == '.sh')} sh + "
          f"{sum(1 for f in files if f.suffix == '.py')} py)")
    print(f"  paths with a READ site        : {n_read}/{n_named}")
    print(f"  ignored by a rule             : {n_ignored}/{n_named}")
    print(f"  tracked in the index          : {n_tracked}/{n_named}")
    print(f"  READ + PRESENT + IGNORED + UNTRACKED (the defect): {len(defect)}")
    print()
    for rel, present, ignored, tracked, reads, sites in rows:
        kind = "READ" if reads else "    "
        flag = "DEFECT" if (reads and present and ignored and not tracked) else ""
        where = ", ".join(reads[:3]) or ", ".join(ln for ln, _ in sites[:2])
        print(f"  {'T' if tracked else '-'}{'I' if ignored else '-'}"
              f"{'P' if present else '-'} {kind:4} {rel:42} {flag:6} {where}")
    print()
    print("KEYS: T=tracked I=ignored P=present-on-disk; READ = a line that CONSUMES it")


if __name__ == "__main__":
    main()
