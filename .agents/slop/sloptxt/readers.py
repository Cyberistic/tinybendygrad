#!/usr/bin/env python3
"""Reader census for the owned `.agents/slop/**/*.txt` population.

POPULATION BY DISCOVERY: an os.walk of the repo (same ownership rule as no-txt.py), not git.
A READER is a GIT-TRACKED **CODE** FILE (see CODE_EXT) whose bytes name the target's
basename or repo-relative path -- that is a file that can OPEN it. Mentions in `.md`, `.json`
citation databases and TODO prose are NOT readers and are reported separately as CITES, because
`.agents/slop/_cite/cites.json` cites almost every path in the tree and would otherwise veto every rename.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SKIP = {".git", "references", "node_modules", "__pycache__"}
SKIP_PREFIX = ("tinygrad", ".venv", "node_modules")
CODE_EXT = (".py", ".sh", ".bash", ".mjs", ".js", ".cjs", ".ts", ".bend")
NAME_RE = re.compile(rb"[\w./\-]+\.txt")


def owned(rel):
    parts = rel.split(os.sep)
    return not (set(parts) & SKIP or any(p.startswith(SKIP_PREFIX) for p in parts))


def targets():
    out = []
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in SKIP]
        for f in fn:
            if f.endswith(".txt"):
                rel = os.path.relpath(os.path.join(dp, f), ROOT)
                if owned(rel):
                    out.append(rel)
    return sorted(out)


def tracked():
    o = subprocess.run(["git", "-C", ROOT, "ls-files"], capture_output=True, text=True).stdout
    return [l for l in o.splitlines() if l]


def main():
    tg = targets()
    by_base = {}
    for t in tg:
        by_base.setdefault(os.path.basename(t), []).append(t)
    readers = {t: [] for t in tg}
    cites = {t: [] for t in tg}
    globs = []
    for f in tracked():
        if f.endswith(".txt"):
            continue
        p = os.path.join(ROOT, f)
        try:
            if os.path.getsize(p) > 2_000_000:
                continue
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\x00" in data:
            continue
        is_code = f.endswith(CODE_EXT)
        for m in NAME_RE.finditer(data):
            base = os.path.basename(m.group(0).decode("utf-8", "replace"))
            if base in by_base:
                ln = data[: m.start()].count(b"\n") + 1
                for t in by_base[base]:
                    (readers if is_code else cites)[t].append(f"{f}:{ln}")
        if is_code and b"*.txt" in data:
            globs.append(f"{f}:{data[: data.index(b'*.txt')].count(b'\n') + 1}")
    json.dump(
        {
            "targets": tg,
            "readers": {k: sorted(set(v)) for k, v in readers.items() if v},
            "cites": {k: sorted(set(v)) for k, v in cites.items() if v},
            "globs": sorted(set(globs)),
        },
        open(".agents/slop/sloptxt/readers.json", "w"),
        indent=1,
    )
    print(f"targets={len(tg)}  code-reader-named={sum(1 for v in readers.values() if v)}", file=sys.stderr)
    print(f"*.txt globs in tracked code: {sorted(set(globs))}", file=sys.stderr)
    for t in sorted(readers):
        if readers[t]:
            print(f"  {t}\n      <- {sorted(set(readers[t]))[:5]}", file=sys.stderr)


main()
