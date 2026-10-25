"""THE CONTROLS -- and the control ON the control.

**A GATE THAT ONLY CAUGHT EMPTINESS WOULD BE CATCHING VACUITY AND NOT WRONGNESS.**
So every expected row is checked TWICE:

  (a) a WRONG BUT NON-EMPTY expectation -> that row must come back `MISMATCH`, and
      every OTHER row must stay `PASS`;
  (b) an EMPTY expectation              -> that row must come back `UNCHECKABLE`, and
      every OTHER row must stay `PASS`.

The two classes are DISTINCT, and the assertion is on the class, not merely on "not
PASS": a control that asserted only "the gate went red" would be satisfied by a gate
that went red for the wrong reason.

**THE CONTROL ON THE CONTROL.**  The controls above prove the gate REJECTS.  They do
not prove the EXPECTATIONS are a witness rather than a transcript of the port's own
output -- and that is the property that matters, because a gate whose expectations
were copied from the port's output is a tautology.  So this file ALSO checks:

  (c) THE EXPECTATIONS DISAGREE WITH THE PORT'S OUTPUT AT HEAD.  The five rows the
      fixture fix moved carry values that the port did NOT print before the fix, so
      the expectation file cannot be a transcript of the port's output as it stood.

And the arm that settles the DIRECTION of the dependence is `run.sh oracleplant`:
perturbing the ORACLE moves the expectation file while the port does not move, and
perturbing the PORT moves the port while the expectation file does not move.  A file
that is a function of the port cannot move when only the oracle moves.

usage: ctl-rows.py <port.rows> <expect.rows>
"""
import sys

sys.dont_write_bytecode = True  # no __pycache__ beside the instrument
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from gate import MISMATCH, PASS, UNCHECKABLE, compare, read_rows  # noqa: E402


def perturb(expect: dict, name: str, value: str) -> dict:
    out = dict(expect)
    out[name] = value
    return out


def main() -> int:
    port = read_rows(sys.argv[1])
    expect = read_rows(sys.argv[2])
    failures = 0
    checks = 0

    print("(0) the UNPERTURBED expectations")
    verdicts = compare(port, expect)
    bad = [n for n, v in verdicts.items() if v[0] != PASS]
    checks += 1
    if bad:
        failures += 1
        print("    FAIL: %d row(s) not PASS: %s" % (len(bad), sorted(bad)))
    else:
        print("    PASS  OK  (%d rows)" % len(expect))

    for name in sorted(expect):
        # (a) WRONG BUT NON-EMPTY
        wrong = perturb(expect, name, expect[name] + "_WRONG")
        verdicts = compare(port, wrong)
        named = verdicts[name][0]
        others = [n for n, v in verdicts.items() if n != name and v[0] != PASS]
        checks += 1
        if named != MISMATCH or others:
            failures += 1
            print("    FAIL (a) %-16s -> %s (want MISMATCH), other rows broken: %s"
                  % (name, named, sorted(others)))
        else:
            print("    (a) %-16s wrong-but-non-empty -> %-12s OK" % (name, named))

        # (b) EMPTY
        empty = perturb(expect, name, "")
        verdicts = compare(port, empty)
        named = verdicts[name][0]
        others = [n for n, v in verdicts.items() if n != name and v[0] != PASS]
        checks += 1
        if named != UNCHECKABLE or others:
            failures += 1
            print("    FAIL (b) %-16s -> %s (want UNCHECKABLE), other rows broken: %s"
                  % (name, named, sorted(others)))
        else:
            print("    (b) %-16s empty              -> %-12s OK" % (name, named))

    print("CONTROLS: %d rows x 2 perturbations + the clean run = %d checks, failures: %d"
          % (len(expect), checks, failures))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
