#!/usr/bin/env python
"""Doctrine 1: is the forward-reference wall real?

Scan every .bend file in the port. For each `def name(`, find the first CALL
site (comment text stripped). A call above the def is a forward reference. If
ZERO exist anywhere, the wall is real (Bend orders defs); if some file has one,
it is stylistic.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3] / "tinybendygrad"
DEF_RE = re.compile(r"^\s*def ([A-Za-z0-9_.]+)\(")


def scan(path):
    lines = path.read_text().splitlines()
    defs = {}
    for ln, line in enumerate(lines, 1):
        m = DEF_RE.match(line)
        if m:
            defs.setdefault(m.group(1), ln)
    hits = []
    for name, dline in defs.items():
        call_re = re.compile(r"(?<![\w.])" + re.escape(name) + r"\s*\(")
        for ln, line in enumerate(lines, 1):
            if ln >= dline:
                break
            code = line.split("#", 1)[0]
            if re.match(r"^\s*def " + re.escape(name) + r"\(", line):
                continue
            if call_re.search(code):
                hits.append((ln, dline, name))
                break
    return hits


def main():
    total, files = 0, 0
    for path in sorted(ROOT.rglob("*.bend")):
        hits = scan(path)
        if hits:
            files += 1
            for ln, dline, name in hits:
                print(f"{path.relative_to(ROOT)}\t{name}\tcall@{ln}\tdef@{dline}")
            total += len(hits)
    print(f"# forward references across the tree: {total} in {files} files")


if __name__ == "__main__":
    main()
