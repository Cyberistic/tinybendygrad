#!/usr/bin/env python3
"""PARSES `checks/citation-gate.py`'s OWN OUTPUT into a TSV. It does NOT re-census: a second
census is a second opinion about which text a comment claims, and that is the whole problem.

    .venv/bin/python checks/citation-gate.py > census.out      # CITEGATE_ROWS=100000
    .venv/bin/python .agents/slop/stale269/rows.py census.out rows.tsv

Columns: `class port_file port_line name cited_line nearest dist occ quote`. `nearest`/`dist`/`occ`
are the gate's own numbers, copied verbatim -- including the fact that it picked NEAREST, which
the gate itself documents as wrong for `Allocator` inside `BumpAllocator`.
"""
import re
import sys

ROW = re.compile(
    r"^(?P<port>[\w./-]+\.bend):(?P<pl>\d+)\s+"
    r"(?P<name>[\w./-]+\.py):(?P<cl>\d+)"
    r"(?:(?:,\s*nearest occurrence is (?P<near>\d+) \((?P<dist>\d+) off, (?P<occ>\d+) in the file\))"
    r"|(?: of (?P<eof>\d+))"
    r"|(?P<other>\s+text is in (?P<opath>[\w./-]+))?)"
    r"\s+`(?P<quote>[^`]*)`"
)
CLS = re.compile(r"^\s+(\d+) ([A-Z-]+)\s")


def main(argv: list[str]) -> int:
    cls = ""
    out = []
    for ln in open(argv[1], encoding="utf-8"):
        m = CLS.match(ln)
        if m:
            cls = m.group(2)
            continue
        if not ln.startswith("        "):
            continue
        m = ROW.match(ln.strip())
        if not m:
            if not ln.strip().startswith("..."):
                print(f"UNPARSED: {ln.strip()}", file=sys.stderr)
            continue
        d = m.groupdict()
        out.append((cls, d["port"], d["pl"], d["name"], d["cl"], d["near"] or d["eof"] or "",
                    d["dist"] or "", d["occ"] or "", d["opath"] or "", d["quote"]))
    with open(argv[2], "w", encoding="utf-8") as fh:
        fh.write("class\tport\tpl\tname\tcl\tnearest\tdist\tocc\tother\tquote\n")
        for r in out:
            fh.write("\t".join(r) + "\n")
    print(f"  {len(out)} rows -> {argv[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))