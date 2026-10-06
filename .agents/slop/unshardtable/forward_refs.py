#!/usr/bin/env python
"""Doctrine 1: discover the file's own forward references, do not list them.

A forward reference is a CALL to a def `N` that appears at a line ABOVE the
`def N(` line. Scans fold.bend, keys defs by their full dotted name (`Kahn.ans`,
`mm.lift`), and for each def name finds the first call line and the def line.
Reports every pair where call_line < def_line.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[3]
FOLD = ROOT / "tinybendygrad/uop/fold.bend"

DEF_RE = re.compile(r"^def ([A-Za-z0-9_.]+)\(")


def main():
    lines = FOLD.read_text().splitlines()
    defs = {}
    for ln, line in enumerate(lines, 1):
        m = DEF_RE.match(line)
        if m:
            defs.setdefault(m.group(1), ln)

    rows = []
    for name, dline in defs.items():
        # a call: the name followed by `(`, not preceded by `def `
        call_re = re.compile(r"(?<![\w.])" + re.escape(name) + r"\s*\(")
        first = None
        for ln, line in enumerate(lines, 1):
            if line.startswith("def " + name + "("):
                continue
            code = line.split("#", 1)[0]  # strip comments: a name in prose is not a call
            if call_re.search(code):
                first = ln
                break
        if first is not None and first < dline:
            rows.append((first, dline, name))

    rows.sort()
    print(f"# forward references: {len(rows)}")
    for call_ln, def_ln, name in rows:
        print(f"{name}\tcall@{call_ln}\tdef@{def_ln}")


if __name__ == "__main__":
    main()
