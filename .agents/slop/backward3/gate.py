"""THE GATE -- the port's rows against the expectations, with FOUR verdicts.

  PASS         the port's value EQUALS the expectation.
  MISMATCH     the port's value DIFFERS -- THE WRONGNESS CLASS.
  UNCHECKABLE  the expectation carries NO VALUE -- THE VACUITY CLASS.
  MISSING      the port does not print the row at all.

**TWO CLASSES, NOT ONE.**  An expectation whose value is EMPTY is not a wrong
expectation, it is a MISSING expectation: there is nothing to compare, so the gate
measured nothing and saying "PASS" would be a lie (the tree's doctrine 2 -- `SKIP` is
not `PASS`, and `DEAD` is not a zero).  So the two are reported separately and BOTH
are a RED verdict.

THE EXIT STATUS: 0 iff every expected row is `PASS`.  A `MISMATCH`, an `UNCHECKABLE`
and a `MISSING` all make it 1.

usage: gate.py <port.rows> <expect.rows> [<expect.rows> ...]
"""
import sys

PASS = "PASS"
MISMATCH = "MISMATCH"
UNCHECKABLE = "UNCHECKABLE"
MISSING = "MISSING"


def read_rows(path: str) -> dict:
    rows = {}
    for line in open(path):
        line = line.rstrip("\n")
        if "=" not in line:
            continue
        name, _, value = line.partition("=")
        rows[name] = value
    return rows


def compare(port: dict, expect: dict) -> dict:
    """The verdict for every expected row."""
    verdicts = {}
    for name, want in expect.items():
        if name not in port:
            verdicts[name] = (MISSING, None, want)
        elif want == "":
            verdicts[name] = (UNCHECKABLE, port[name], want)
        elif port[name] != want:
            verdicts[name] = (MISMATCH, port[name], want)
        else:
            verdicts[name] = (PASS, port[name], want)
    return verdicts


def main() -> int:
    port = read_rows(sys.argv[1])
    expect = {}
    for path in sys.argv[2:]:
        for name, value in read_rows(path).items():
            if name in expect:
                raise SystemExit("two expectation files both carry the row %s" % name)
            expect[name] = value
    verdicts = compare(port, expect)
    counts = {PASS: 0, MISMATCH: 0, UNCHECKABLE: 0, MISSING: 0}
    for name in sorted(verdicts):
        verdict, got, want = verdicts[name]
        counts[verdict] += 1
        if verdict != PASS:
            print("    %-12s %s" % (verdict, name))
            print("      want: %r" % want)
            print("      got : %r" % got)
    print("    rows expected: %d   PASS: %d   MISMATCH: %d   UNCHECKABLE: %d   MISSING: %d"
          % (len(expect), counts[PASS], counts[MISMATCH], counts[UNCHECKABLE], counts[MISSING]))
    ok = counts[MISMATCH] == 0 and counts[UNCHECKABLE] == 0 and counts[MISSING] == 0
    print("    VERDICT: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
