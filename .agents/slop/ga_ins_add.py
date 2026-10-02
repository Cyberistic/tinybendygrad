#!/usr/bin/env python3
"""Insert the `write_ins` port (three files) into generate.bend, above the gate.

Run:  python3 .agents/slop/ga_ins_add.py <file.bend>
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
PARTS = ("ga_ins_head.bend", "ga_ins_body.bend", "ga_ins_tail.bend")


def main(path):
    p = pathlib.Path(path)
    s = p.read_text()
    for part in PARTS:
        block = (HERE / part).read_text().rstrip("\n")
        tag = block.split("\n")[1]
        if tag in s:
            continue
        at = s.index("# THE GATE.")
        at = s.rindex("# =====", 0, at)
        s = s[:at] + block + "\n\n" + s[at:]
    p.write_text(s)
    print("inserted %s: %d lines" % (", ".join(PARTS), len(s.split("\n"))))


if __name__ == "__main__":
    main(sys.argv[1])
