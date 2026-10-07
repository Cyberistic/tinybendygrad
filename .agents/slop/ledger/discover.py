#!/usr/bin/env python3
"""DISCOVER THE DIARY CLASS. Population by WRITE SITE, not by filename shape.

Doctrine 1 says a basename regex is not a population. A filename shape
(`*.ledger.tsv`, `*baseline.rows`) is exactly such a shape: it cannot see a
ledger named `census.rows` or `oracles/pins.tsv`, and it cannot see a file
named `ledger.tsv` that is HAND-WRITTEN and read by nobody.

So the population here is: **every path some code in this tree WRITES**. The
write sites are the declaration (`gates/gates-pop.py:104` is
`LEDGER = HERE / "gates-pop.ledger.tsv"`; `checks/citation-gate.py:47` is
`HIST = ... "citation-gate.ledger.tsv"`; `gates/indexread-gate.py:55` is
`BASELINE = ... "indexread-baseline.rows"`). For each such path we then ask
WHO ELSE mentions it, and whether any one of those mentions is a read on a run
that also writes it.

A path whose ONLY write site is `--print-baseline`-adjacent is a pin. A path
whose read site and write site are in the SAME run is a diary. We do not judge
content. We only ask: same process, same run?

    .venv/bin/python .agents/slop/ledger/discover.py [--json]
"""
import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
CODE_EXT = (".py", ".sh", ".mjs", ".js", ".bend")

# Write verbs. Each is a SYNTAX shape in a source file, not a filename shape:
# it is the tree declaring "this path is produced here".
WRITE_SHAPES = (
    re.compile(r"""open\(\s*([A-Za-z_][\w.]*)\s*,\s*["'][wax]"""),          # open(x, "w"/"a"/"x")
    re.compile(r"""\.open\(\s*["'][wax]"""),                                # x.open("w")
    re.compile(r"""write_text\("""),                                       # Path.write_text
    re.compile(r""">\s*[A-Za-z_][\w.\[\]]*\s*$"""),                        # f > var
    re.compile(r"""tee\s+"""),
    re.compile(r"""\bcp\s+"""),
    re.compile(r""">>>?"""),                                                # shell redirect
)

# Reads. Deliberately includes the WRITE shapes' sibling ops so a file that is
# only ever read still registers a read site.
READ_SHAPES = (
    re.compile(r"""\.read_text\("""),
    re.compile(r"""readlines\("""),
    re.compile(r"""\bread\(\)"""),
    re.compile(r"""open\(\s*([A-Za-z_][\w.]*)\s*\)"""),
    re.compile(r"""\bcat\s+"""),
    re.compile(r"""open\(\s*["']r"""),
    re.compile(r"""<[A-Za-z_][\w.\[\]]*\s*$"""),
    re.compile(r"""\bwc\s+-l\s+"""),
)

# A quoted literal that LOOKS like a data file this project makes. Not the
# population -- only a way to turn a write site into a PATH.
PATHY = re.compile(r"""["']([\w./-]+\.(?:tsv|rows|json|md|out|bin|jsonl))["']""")


def tracked(root):
    """`git ls-tree`, NEVER `git ls-files`: the index has reset 6+ times and
    reading it answers a question about a staging area nobody pinned."""
    out = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"],
                         cwd=root, capture_output=True, text=True, check=True)
    return [p for p in out.stdout.splitlines() if p]


def code_files(paths):
    return [p for p in paths if p.endswith(CODE_EXT)
            and not p.endswith(".bend") or p.endswith(".bend")]


def scan(root, paths):
    """One pass per code file: constant-ish assignments that name a data path,
    and every line whose shape reads or writes a variable."""
    per_file = {}
    assigns = {}
    for rel in paths:
        if not rel.endswith(CODE_EXT):
            continue
        full = os.path.join(root, rel)
        try:
            src = open(full, encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            continue
        lines = []
        for i, ln in enumerate(src, 1):
            w = any(s.search(ln) for s in WRITE_SHAPES)
            r = any(s.search(ln) for s in READ_SHAPES)
            if not (w or r):
                continue
            lines.append((i, "write" if w else "", "read" if r else "", ln.strip()))
        if lines:
            per_file[rel] = lines
        # name -> the data path it is assigned
        for i, ln in enumerate(src, 1):
            m = re.match(r"""^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.+)$""", ln)
            if not m:
                continue
            for p in PATHY.findall(m.group(2)):
                assigns.setdefault(m.group(1), []).append((rel, i, p))
    return per_file, assigns


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv[1:])

    paths = tracked(ROOT)
    per_file, assigns = scan(ROOT, paths)
    by_path = {}
    for sym, sites in assigns.items():
        for rel, i, p in sites:
            by_path.setdefault(p, {"sym": sym, "decl": []})["decl"].append((rel, i))

    # Every write site found, keyed by the symbol it writes, if we can tell.
    writers = {}
    for rel, lines in per_file.items():
        for i, w, r, ln in lines:
            if not w:
                continue
            for sym, sites in assigns.items():
                if re.search(rf"\b{sym}\b", ln):
                    for _, _, p in sites:
                        writers.setdefault(p, set()).add(f"{rel}:{i}")

    # Readers: a line that mentions the bare basename or a symbol bound to it.
    readers = {}
    basenames = {os.path.basename(p): p for p in writers}
    syms = {}
    for p, info in by_path.items():
        syms[os.path.basename(p)] = info["sym"]
    for rel, lines in per_file.items():
        for i, w, r, ln in lines:
            if not r:
                continue
            for base, p in basenames.items():
                if base in ln or (syms.get(base) and re.search(rf"\b{syms[base]}\b", ln)):
                    readers.setdefault(p, set()).add(f"{rel}:{i}")

    rows = []
    for p in sorted(writers):
        w = sorted(writers[p])
        r = sorted(readers.get(p, ()))
        wfiles = {x.split(":")[0] for x in w}
        rfiles = {x.split(":")[0] for x in r}
        overlap = sorted(wfiles & rfiles)
        rows.append({
            "path": p, "tracked": p in set(paths),
            "writers": w, "readers": r,
            "files_both": overlap,
            "co_located": bool(overlap),
        })
    if a.json:
        print(json.dumps(rows, indent=1))
        return 0
    print(f"{len(rows)} data path(s) are WRITTEN by tracked code in this tree "
          f"(population: `git ls-tree -r HEAD`, {len(paths)} paths, "
          f"code extensions {CODE_EXT})\n")
    for row in rows:
        tag = "SAME-FILE WRITE+READ" if row["co_located"] else "write-only or read-only"
        print(f"{row['path']}   [{tag}]   tracked={row['tracked']}")
        for x in row["writers"]:
            print(f"    WRITES  {x}")
        for x in row["readers"]:
            print(f"    READS   {x}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))