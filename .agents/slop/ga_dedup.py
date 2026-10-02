#!/usr/bin/env python3
"""Drop comment blocks that `ga_topo.py` duplicated, until the file is stable.

`ga_topo.py` claims each comment run once (it stops the walk-back at the previous
block), but an earlier version did not, so the file on disk when this unit took
over carried several hundred duplicated comment lines.  Comments do not affect
compilation; LOC does, and a 2,600-line file with 700 lines of repeated prose is
worse than a 1,900-line one.

Run:  python3 .agents/slop/ga_dedup.py <file.bend>       # once
"""
import pathlib
import sys


def sweep(lines):
    out, i, n, killed = [], 0, len(lines), 0
    while i < n:
        if not lines[i].startswith("#"):
            out.append(lines[i])
            i += 1
            continue
        blocks, cur, j = [], [], i
        while j < n and (lines[j].startswith("#")
                         or (lines[j].strip() == "" and j + 1 < n and lines[j + 1].startswith("#"))):
            if lines[j].strip() == "":
                blocks.append(cur)
                cur = []
                j += 1
                continue
            cur.append(lines[j])
            j += 1
        blocks.append(cur)
        blocks = [b for b in blocks if b]
        uniq = []
        for b in blocks:
            if uniq and uniq[-1] == b:
                killed += 1
                continue
            uniq.append(b)
        for k, b in enumerate(uniq):
            if k:
                out.append("")
            out.extend(b)
        i = j
    return out, killed


def main(path):
    p = pathlib.Path(path)
    total = 0
    while True:
        lines, killed = sweep(p.read_text().split("\n"))
        if not killed:
            break
        total += killed
        p.write_text("\n".join(lines))
    print("dropped %d duplicated comment blocks; %d lines now"
          % (total, len(p.read_text().split("\n"))))


if __name__ == "__main__":
    main(sys.argv[1])