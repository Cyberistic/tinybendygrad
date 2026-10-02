#!/usr/bin/env python3
"""Diff a `bend generate.bend` gate run against `.agents/slop/ga-oracle.txt`.

THE HARNESS DIFFS WHOLE `name=value` LINES, NOT ROW NAMES.  A name-comparing
harness reported 0 moved rows for all 30 mutations in one unit of this project
and for all 68 in another: when a mutation changed a VALUE, both sides carried
the same NAME and the comparison said nothing happened.

Every `py=` in the gate came from the oracle, so the oracle's own rows are the
expectation and this needs no second source of truth.

Run:  python3 .agents/slop/ga_gate.py <run.txt>
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent


def parse(path):
    """`NAME = [PORT]   py=[PYTHON]`, where BOTH sides may span lines.

    The emitter rows carry a whole generated file, so a line-oriented regex
    finds nothing: it has to be DOTALL and lazy, so a `]   py=[` that appears
    INSIDE a value cannot end the match early.
    """
    text = pathlib.Path(path).read_text()
    rows = {}
    for m in re.finditer(r"^(.*?) = \[(.*?)\]   py=\[(.*?)\]$", text, re.M | re.S):
        rows[m.group(1).strip()] = (m.group(2), m.group(3))
    return rows


def main(path):
    got = parse(path)
    # the oracle's per-LINE rows joined into the whole emitted file, which is
    # the unit `ga_fix.py` splices into the gate
    seen = []
    for ln in (HERE / "ga-oracle.txt").read_text().split("\n"):
        if " = [" in ln and ln.endswith("]"):
            seen.append((ln.split(" = [", 1)[0], ln.split(" = [", 1)[1][:-1]))
    want = [(k, v) for k, v in seen if " |" not in k]
    want += [(tag, "\n".join(v for k, v in seen if k.startswith(tag + " |")))
             for tag in ("enum rdna3", "operands rdna3", "common", "ins rdna3", "ins cdna",
                         "pcode rdna3", "pcode cdna")]
    # a gate row is `py=`-complete: the port's name must be an oracle row name
    ok = bad = 0
    for nm, (g, w) in sorted(got.items()):
        if nm not in dict(want):
            print("ROW NOT IN ORACLE: %s -- refusing to score it" % nm)
            bad += 1
            continue
        if g == w:
            ok += 1
        else:
            bad += 1
            if bad <= 12:
                print("MISMATCH %s" % nm)
                gl, wl = g.split("\n"), w.split("\n")
                if len(gl) != len(wl):
                    print("   line count: port=%d py=%d" % (len(gl), len(wl)))
                shown = 0
                for i in range(max(len(gl), len(wl))):
                    a = gl[i] if i < len(gl) else "<none>"
                    b = wl[i] if i < len(wl) else "<none>"
                    if a != b:
                        print("   %4d port[%s]" % (i, a[:150]))
                        print("        py  [%s]" % b[:150])
                        shown += 1
                        if shown >= 6:
                            break
    print("GATE: %d rows, %d agree, %d differ" % (len(got), ok, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))