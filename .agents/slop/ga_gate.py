#!/usr/bin/env python3
"""Diff a `bend generate.bend` gate run against `.agents/slop/ga-oracle.txt`.

THE HARNESS DIFFS WHOLE `name=value` LINES, NOT ROW NAMES.  A name-comparing
harness reported 0 moved rows for all 30 mutations in one unit of this project
and for all 68 in another: when a mutation changed a VALUE, both sides carried
the same NAME and the comparison said nothing happened.

Every `py=` in the gate came from the oracle, so the oracle's own rows are the
expectation and this needs no second source of truth.

⚠ THE PARSER IS ONE LINE, NOT DOTALL, AND THAT IS A DELIBERATE REGRESSION GUARD.
It used to be `re.DOTALL` because `gl` printed a WHOLE GENERATED FILE per row and a
line-oriented regex found nothing.  That shape is GONE -- `gl` now prints one row
per emitted line -- and the reason it had to go is in generate.bend's `gl.go`:
a whole-file row value is 16,815 characters and a `String` is an `SCon` spine with
no tail call, so the row was 16,815 nested frames and the interpreter overflowed on
5 runs in 12.  A DOTALL parser would still parse that output happily, so leaving it
on would have let the overflow come back silently.  `.agents/slop/ga_rows.py`
MEASURES that every port row is one line, and `rebase-gate-selftest.py` drives it.

Run:  python3 .agents/slop/ga_gate.py <run.txt>
"""
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent

# `NAME = [PORT]   py=[PYTHON]`, one line, and the closing bracket is the END of the
# line.  No DOTALL, no lazy matching across lines -- see the module docstring.
ROW = re.compile(r"^(.*?) = \[(.*)\]   py=\[(.*)\]$")


def parse(path):
    """{name: (port, py)} from lane output, and the names of any line that LOOKS like
    a row but does not parse -- which is the shape a re-introduced multi-line value
    takes, and it must be named rather than dropped."""
    text = pathlib.Path(path).read_text()
    rows, broken = {}, []
    for line in text.split("\n"):
        if " = [" not in line:
            continue
        m = ROW.match(line)
        if m is None:
            broken.append(line[:70])
            continue
        rows[m.group(1).strip()] = (m.group(2), m.group(3))
    return rows, broken


def main(path):
    got, broken = parse(path)
    want, _ = parse(HERE / "ga-oracle.txt")

    if broken:
        print(f"MULTI-LINE ROWS: {len(broken)} line(s) look like a row and do not parse "
              "as one.  A row value must be ONE line or the differ cannot see it:")
        for b in broken[:6]:
            print("   " + b)
        return 1

    ok = bad = 0
    for nm, (g, w) in sorted(got.items()):
        if nm not in want:
            print("ROW NOT IN ORACLE: %s -- refusing to score it" % nm)
            bad += 1
            continue
        _, wy = want[nm]
        if g == w == wy:
            ok += 1
        else:
            bad += 1
            if bad <= 12:
                print("MISMATCH %s" % nm)
                print("   port[%s]" % g[:160])
                print("   py  [%s]" % wy[:160])
    ungated = sorted(set(want) - set(got))
    print("GATE: %d rows, %d agree, %d differ" % (len(got), ok, bad))
    print("ORACLE: %d rows, %d gated, %d ungated" % (len(want), len(got), len(ungated)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))