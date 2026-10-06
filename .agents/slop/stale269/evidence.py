#!/usr/bin/env python3
"""EVIDENCE FOR ONE ROW: what the comment claims, what is on the line it names now, and what is
on EVERY line the quoted text occurs on -- with the PREFIX test, which is the class that made a
prior instrument report `Allocator` inside `BumpAllocator`.

    .venv/bin/python .agents/slop/stale269/evidence.py rows.tsv CLASS [PORT_FILE_SUBSTR]

Prints, per row:
  CLAIM     the port's citation line, comment text only, with the number it names
  AT-NAMED  the cited file's line `cl` today -- so "the number moved" is a COMPARISON, not a claim
  ANCHORS   EVERY line the quote occurs on, each with the boundary verdict and the whole line
BOUNDARY is the brief's `S.Dt` vs `S.DtX` trap: a match whose NEXT char is a word char is a
PREFIX of a longer token and the naive pin accepted it.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
# The gate's own resolver, imported -- NOT reimplemented. A second resolver is a second opinion.
import importlib.util  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "citation_gate", os.path.join(ROOT, "checks/citation-gate.py"))
G = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(G)


def occ_lines(body: str, quote: str) -> list[tuple[int, int, str]]:
    """(line_no, start_offset, is_clean) for every occurrence. `is_clean` is the boundary test."""
    out = []
    for m in re.finditer(re.escape(quote), body):
        line = body[: m.start()].count("\n") + 1
        end = m.end()
        before = body[m.start() - 1] if m.start() else ""
        after = body[end] if end < len(body) else ""
        clean = not (after and re.match(r"\w", after))
        out.append((line, m.start(), clean, before, after))
    return out


def main(argv: list[str]) -> int:
    rows = open(argv[1], encoding="utf-8").read().splitlines()[1:]
    want, filt = argv[2], (argv[3] if len(argv) > 3 else "")
    idx = G.python_files()
    for rb in rows:
        f = rb.split("\t")
        if f[0] != want or filt not in f[1]:
            continue
        _, port, pl, name, cl, near, dist, occ, other, quote = f
        rel = os.path.relpath(os.path.join(ROOT, port), ROOT)
        tgt = G.resolve(name, rel, idx)
        print(f"\n===== {rel}:{pl}  cites {name}:{cl} -> nearest {near} ({dist} off, {occ} in file)")
        src = open(os.path.join(ROOT, port), encoding="utf-8").read().splitlines()
        for i in range(max(0, int(pl) - 1), min(len(src), int(pl) + 2)):
            print(f"  CLAIM  {rel}:{i+1}  {src[i].strip()}")
        if tgt is None:
            print(f"  AT-NAMED  <unresolved: {name}>")
            continue
        body = open(tgt, encoding="utf-8", errors="replace").read()
        bl = body.splitlines()
        print(f"  AT-NAMED  {os.path.relpath(tgt, ROOT)}:{cl}  "
              f"{(bl[int(cl) - 1].strip() if 0 < int(cl) <= len(bl) else '<PAST EOF, %d lines>' % len(bl))}")
        for line, off, clean, before, after in occ_lines(body, quote):
            tag = "ok " if clean else "PREFIX" if after and re.match(r"\w", after) else "SUFFIX"
            print(f"  ANCHOR {tag} {os.path.relpath(tgt, ROOT)}:{line}  ...{bl[line-1].strip()[:150]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))