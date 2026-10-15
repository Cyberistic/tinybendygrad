#!/usr/bin/env python3
"""Which `.agents/slop/<dir>` do this tree's instruments WRITE and READ?

ONE RESOLVER, LOADED BY PATH from `checks/sweep.py`; the only thing that varies is the
POPULATION -- which files count as an instrument.  A second copy of the resolver would be a
second vocabulary with no generator, which is the defect this whole tree keeps paying for.

    .venv/bin/python .agents/slop/sweepdirs/census.py
"""
from __future__ import annotations

import ast
import importlib.util
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))


def load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, rel))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


SW = load("sweep", "checks/sweep.py")
CODE_EXT = (".py", ".sh", ".mjs", ".js", ".bend")


def tracked(*pathspecs: str) -> list[str]:
    r = subprocess.run(["git", "ls-files", "-z", "--", *pathspecs], cwd=ROOT,
                       capture_output=True, text=True)
    return sorted(p for p in r.stdout.split("\0") if p and os.path.lexists(os.path.join(ROOT, p)))


def census(files: list[str], namer=SW.slop_dir) -> tuple[set[str], set[str]]:
    """`(written, read)` `.agents/slop/...` over this file list, by AST, with sweep's resolver."""
    writes: set[str] = set()
    reads: set[str] = set()
    for rel in files:
        try:
            tree = ast.parse(open(os.path.join(ROOT, rel), errors="replace").read())
        except (OSError, SyntaxError):
            continue
        for body, env in SW._scopes(tree):
            for node in ast.walk(ast.Module(body=list(body), type_ignores=[])):
                if not isinstance(node, ast.Call):
                    continue
                for read, out in ((False, writes), (True, reads)):
                    for slot in SW._path_slots(node, env, read) or []:
                        d = namer(SW._resolve(slot, env))
                        if d:
                            out.add(d)
    return writes, reads


def slop_file(value: str) -> str | None:
    """`slop_dir`'s finer sibling: the FILE a write names, or `None`.

    `slop_dir` keeps ONE component; the evidence names a FILE, so the truncation is where an
    ownership claim about `residue/000-the-residue.md` becomes a claim about all of `residue/`.
    Every component must be nameable -- one opaque component makes the whole path opaque.
    """
    if SW.SLOP_PREFIX + "/" not in value:
        return None
    tail = value.split(SW.SLOP_PREFIX + "/", 1)[1].strip("/")
    if not tail or SW.UNKNOWN_MARK in tail or "." not in tail.rsplit("/", 1)[-1]:
        return None
    return SW.SLOP_PREFIX + "/" + tail


REDIRECT = re.compile(r">>?\s*['\"]?|(?:\btee\b|\bcp\b|\bmv\b|\bcat\b)\s+.*?['\"]?(?=[^\s'\"]*\.agents/slop/)")
SLOPT = re.compile(r"\.agents/slop/([A-Za-z0-9_-]+)")


def shell_belt(files: list[str]) -> set[str]:
    """A REGEX over the tree's own write sites for the half an AST walk over `.py` cannot see:
    a shell redirect (`>`, `>>`, `tee`, `cp`, `mv`) whose operand names `.agents/slop/<dir>`."""
    out: set[str] = set()
    for rel in files:
        try:
            text = open(os.path.join(ROOT, rel), errors="replace").read()
        except OSError:
            continue
        for line in text.splitlines():
            if line.lstrip().startswith("#"):
                continue
            if REDIRECT.search(line) and ".agents/slop/" in line:
                out |= {".agents/slop/" + m for m in SLOPT.findall(line)}
    return out


def scope(name: str) -> list[str]:
    if name == "code":            # sweep._instrument_files' own population: disk, checks/ + gates/
        return [os.path.relpath(os.path.join(dp, f), ROOT)
                for base in ("checks", "gates")
                for dp, _d, fs in os.walk(os.path.join(ROOT, base))
                for f in sorted(fs) if f.endswith(".py")]
    if name == "tree":
        return tracked("*.py")
    if name == "agents":
        return tracked(":(glob).agents/slop/**/*.py") + tracked(".agents/slop/*.py")
    if name == "nonpy":           # the regex belt's population: every OTHER code file
        return tracked(*(f"*{e}" for e in CODE_EXT if e != ".py"))
    raise SystemExit(f"unknown scope {name}")


def main() -> int:
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    print(f"# census {stamp}  HEAD {head}")
    for name in ("code", "tree", "agents"):
        files = scope(name)
        w, r = census(files)
        print(f"# {name:8s} {len(files):5d} .py -> writes {len(w):3d} {sorted(w)}")
        print(f"# {'':8s} {'':5s}      reads  {len(r):3d} {sorted(r)}")
        print(f"# {'':8s} {'':5s}      writes-reads {len(w - r):3d} {sorted(w - r)}")
    files = scope("nonpy")
    belt = shell_belt(files)
    pybelt = shell_belt(scope("tree"))
    print(f"# nonpy    {len(files):5d} code files -> shell-belt {len(belt):3d} {sorted(belt)}")
    print(f"# py-belt  {len(scope('tree')):5d} .py files -> shell-belt {len(pybelt):3d} {sorted(pybelt)}")
    wf, _rf = census(scope("tree"), namer=slop_file)
    print(f"# files    {len(scope('tree')):5d} .py -> files written {len(wf):3d}: "
          + "  ".join(sorted(wf)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
