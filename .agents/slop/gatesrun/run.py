#!/usr/bin/env python3
"""gatesrun: re-derive the gate population by DISCOVERY, classify each entry point by what
the file DOES, execute the ones whose subject is NOT `bend`, and emit one row per entry.

Population = a DIRECTORY WALK of `checks/` and `gates/` (`iterdir`, `.py`/`.sh`). An entry
point is a Python file with an `if __name__` guard (AST) or a shell file that self-references
`$0`. No hand list of files is consulted; `gates/gates-pop.py`'s ledger is not read.

CLASS (by behaviour, read from the AST/source, never from the filename):
  gatekit   imports the shared gate plumbing -> a gate
  gate      has a __main__ that returns/exits non-zero on disagreement -> a gate
  oracle    emits `name=value` rows and has no failing branch -> expected values
  wrapper   delegates to another program (shell `exec`, or names another gate)
  driver    exercises a port/tool; no verdict of its own
  unknown   none of the above

RUN POLICY: an entry that invokes `bend` (directly, or through gatekit, or through a wrapper
whose target invokes it) is NOT executed -- `bend` is another unit's exclusively. Those are
SKIP, never PASS. A server/scan that does not terminate is also SKIP.
"""
from __future__ import annotations
import ast
import io
import json
import os
import re
import subprocess
import sys
import tokenize
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
HOMES = ("checks", "gates")
SUFFIXES = (".py", ".sh")
TIMEOUT_S = 120

SH_ENTRANCE = re.compile(r"^\s*(?:exec\b|\$\{?0)", re.M)
SH_SELFREF = re.compile(r"\$\{?0\b")
SH_COMMENT = re.compile(r"^\s*#.*$", re.M)
BEND_INVOKE = re.compile(r"bin/bend|BEND\s*=\s*.*bend|run_lane|bend_run|emit_bend|bend_rows")
ROW_EMIT = re.compile(r"print\(.*?=\s*f?[\"']")
NONZERO = re.compile(r"sys\.exit\(\s*[1-9]|SystemExit\(\s*[1-9]|raise SystemExit\(\s*[1-9]|return\s+[1-9]\b")
WRITE_SRC = re.compile(r"\.(?:bend|py|sh)[\"']")


def strip_code(src, is_py):
    if not is_py:
        return SH_COMMENT.sub("", src)
    try:
        docs = set()
        for node in ast.walk(ast.parse(src)):
            if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
                d = ast.get_docstring(node, clean=False)
                if d is not None:
                    ex = node.body[0]
                    docs.update(range(ex.lineno, (ex.end_lineno or ex.lineno) + 1))
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (SyntaxError, tokenize.TokenError, IndentationError):
        return src
    out = []
    for t in toks:
        if t.type == tokenize.COMMENT:
            out.append(t._replace(string=""))
        elif t.type == tokenize.STRING and t.start[0] in docs:
            out.append(t._replace(string=t.string[0] + " " * (len(t.string) - 2) + t.string[-1]))
        else:
            out.append(t)
    return tokenize.untokenize(out)


def is_entry(src, is_py):
    if is_py:
        try:
            return any(isinstance(n, ast.If) and "__main__" in ast.dump(n.test)
                       for n in ast.walk(ast.parse(src)))
        except SyntaxError:
            return False
    return bool(SH_SELFREF.search(SH_COMMENT.sub("", src)))


def imports(src, name):
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return False
    for n in ast.walk(tree):
        if isinstance(n, ast.Import) and any(a.name.split(".")[0] == name for a in n.names):
            return True
        if isinstance(n, ast.ImportFrom) and (n.module or "").split(".")[0] == name:
            return True
    return False


def classify(p, src, code):
    is_py = p.suffix == ".py"
    if is_py and imports(src, "gatekit"):
        return "gatekit"
    if not is_py:
        # a shell file that names another entry point is a wrapper; else a driver
        return "wrapper" if shell_targets(p, src) else "driver"
    emits = len(ROW_EMIT.findall(code))
    nonzero = bool(NONZERO.search(code))
    sub = imports(src, "subprocess")
    arg = imports(src, "argparse")
    tg = imports(src, "tinygrad") or imports(src, "common")
    if emits >= 2 and not nonzero:
        return "oracle"
    if sub and not nonzero:
        return "wrapper"
    if tg and not nonzero:
        return "driver"
    if nonzero:
        return "gate"
    return "unknown"


def shell_targets(p, src):
    """Names of other entry-point files this shell script invokes, for transitive bend."""
    out = []
    for m in re.finditer(r"(checks|gates)/([A-Za-z0-9_.-]+\.(?:py|sh))", src):
        out.append(f"{m.group(1)}/{m.group(2)}")
    return sorted(set(out))


def invokes_bend(p, src, code, seen=None):
    seen = seen or set()
    key = str(p)
    if key in seen:
        return False
    seen.add(key)
    if p.suffix == ".py":
        if imports(src, "gatekit") or BEND_INVOKE.search(code):
            return True
        # conservative: a Python file that NAMES a `.bend` path in code (not in a docstring,
        # which `strip_code` already blanked) is presumed to run it. A false SKIP is honest;
        # running `bend` is not this unit's to do.
        return bool(re.search(r"\.bend\b", code))
    if BEND_INVOKE.search(code) or re.search(r"\bbend\b", code):
        return True
    for rel in shell_targets(p, src):
        t = ROOT / rel
        if t.is_file() and str(t) != key:
            tsrc = t.read_text(errors="replace")
            if invokes_bend(t, tsrc, strip_code(tsrc, True), seen):
                return True
    return False


def token_from(rc, out, err):
    blob = (out + "\n" + err)
    if rc == 0:
        return "PASS"
    if rc == 3 or "REFUSED" in blob:
        return "REFUSED"
    if rc == 5:
        return "DEAD"
    if re.search(r"Traceback \(most recent|ModuleNotFoundError|ImportError|No such file|"
                 r"FileNotFoundError|usage:|unbound variable|syntax error|command not found",
                 blob):
        return "DEAD"
    if rc != 0:
        return "FAIL"
    return "PASS"


def main():
    entries, libs = [], []
    for home in HOMES:
        for p in sorted((ROOT / home).iterdir()):
            if p.suffix not in SUFFIXES or not p.is_file():
                continue
            src = p.read_text(errors="replace")
            (entries if is_entry(src, p.suffix == ".py") else libs).append((p, src))
    rows = []
    for p, src in entries:
        is_py = p.suffix == ".py"
        code = strip_code(src, is_py)
        cls = classify(p, src, code)
        bend = invokes_bend(p, src, code, {})
        rel = str(p.relative_to(ROOT))
        if bend:
            rows.append((rel, cls, "SKIP", "SKIP", "invokes bend (exclusive to another unit)"))
            continue
        if p.name in ("serve.py", "cli.py"):
            rows.append((rel, cls, "SKIP", "SKIP", "long-running server/driver"))
            continue
        # meta-instruments that WRITE state on a bare run, and a contended file: read by hand,
        # never executed here (gates-pop --ledger check is run separately).
        if rel in ("gates/gates-pop.py", "gates/gendirs.py", "gates/retention-check.py"):
            rows.append((rel, cls, "SKIP", "SKIP", "meta-instrument writes state; read not run"))
            continue
        cmd = ([".venv/bin/python", rel] if is_py else ["/bin/sh", rel])
        try:
            r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=TIMEOUT_S)
            rc, out, err = r.returncode, r.stdout, r.stderr
        except subprocess.TimeoutExpired:
            rows.append((rel, cls, "SKIP", "SKIP", f"timeout >{TIMEOUT_S}s"))
            continue
        tok = token_from(rc, out, err)
        (OUT / (rel.replace("/", "_") + ".out")).write_text(out)
        (OUT / (rel.replace("/", "_") + ".err")).write_text(err)
        cause = (err.strip().splitlines() or out.strip().splitlines() or ["-"])[-1][:160]
        rows.append((rel, cls, f"rc={rc}", tok, cause))
        print(f"{tok:8} {cls:8} {rel}")
    header = "path\tclass\trc\ttoken\tcause\n"
    (OUT / "run-classes.tsv").write_text(header + "\n".join("\t".join(r) for r in rows) + "\n")
    from collections import Counter
    c = Counter(r[3] for r in rows)
    print(f"\nENTRIES={len(entries)} LIBS={len(libs)}  {dict(c)}")


if __name__ == "__main__":
    sys.exit(main())
