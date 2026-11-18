#!/usr/bin/env python3
"""execgate-gate.py -- THE GATE OVER THE PORT's OWN RENDERED KERNEL, EXECUTED.

    .venv/bin/python .agents/slop/execgap/execgate-gate.py            # the measurement
    .venv/bin/python .agents/slop/execgap/execgate-gate.py --plants   # and the three plants

WHAT IT MEASURES, AND WHY IT IS NOT A LABEL. `execgate.bend` renders the port's kernel, writes
the `.c`, runs `cc`, runs the binary and prints the binary's own stdout. THIS FILE DECIDES: it
compares those rows against `expected.rows`, which are line-by-line pins derived by hand. It
never computes the expected value, so no CPython in this tree can make the answer agree with
itself.

THE FIVE VERDICTS, as exits, the same five `gates/gatekit.py` spells:

    0 PASS      every row ran and agreed
    1 FAIL      a row ran and disagreed
    3 REFUSED   the lane could not run (no compiler, no rows, a bound fired)
    4 SKIP      there was nothing to measure
    5 DEAD      rows came back but the comparison compared NOTHING

`DEAD` IS THE ONE THAT MATTERS HERE. A lane that prints no `out=` row -- because the compile
failed, or because the program printed nothing -- would otherwise read as "no disagreements",
which is the failure this tree has measured four times. So the row COUNT is asserted first, and
a short row set is `DEAD`, never `PASS`.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LANE = os.path.join(".agents", "slop", "execgap", "execgate.bend")
PINS = os.path.join(HERE, "expected.rows")

PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5

# The rows the lane must produce before the comparison is a comparison at all.
REQUIRED = ("mode", "sig", "c_len", "in12", "in15", "cc_status", "run_status", "changed", "out")


def pins():
    """The pins, read from the `.rows` file beside this one. No defaults: a missing pin is
    a REFUSAL, because a gate with a fallback expectation measures its own fallback."""
    out = {}
    with open(PINS) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k] = v
    return out


def rows_of(text):
    """`name=value` rows, in order, from the lane's stdout. A value may contain `=`, so the
    split is on the FIRST one. Anything before the first `name=` line is ignored by name, not
    by position."""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^([a-z0-9_]+)=(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def run_lane(plant=None):
    """The lane, under `checks/bounded.py`, because 2.4 GB of peak RSS is a bound worth reading
    a token for. The TOKEN is the verdict on the run; the exit status is not (three different
    things exit 1 here).

    THE OUTPUT DIRECTORY IS CREATED HERE AND NOT BY THE LANE, and that is a measured requirement:
    `Base`'s `File.open` does NOT create parent directories, so on a fresh clone -- where
    `out/` is not committed, because its contents are build artefacts -- the lane died with
    `No such file or directory` and the gate correctly said DEAD. The harness owns its own
    directory; the lane writes only the two files inside it."""
    os.makedirs(os.path.join(ROOT, ".agents", "slop", "execgap", "out"), exist_ok=True)
    argv = [sys.executable, "checks/bounded.py", "--seconds", "900", "--mb", "4000", "--",
            "./bin/bend", LANE]
    if plant:
        argv.append(plant)
    p = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True)
    token = "no-token"
    for line in p.stderr.splitlines():
        if line.startswith("[bounded]"):
            token = line.split()[1]
    return rows_of(p.stdout), token, p


def norm(s):
    """Whitespace-insensitive, so `1, 2` and `1,2` are the same list of numbers -- but NOT
    order-insensitive and NOT value-insensitive: the comparison is over the whole row."""
    return " ".join(s.replace(",", " ").split())


def cmp_row(name, got, want, verdicts):
    ok = norm(got) == norm(want)
    verdicts.append((name, "AGREE" if ok else "DISAGREE", got, want))
    return ok


def main():
    argv = sys.argv[1:]
    p = pins()
    rows, token, proc = run_lane()
    verdicts = []

    print("execgate-gate: THE PORT's OWN RENDERED KERNEL, EXECUTED")
    print("  lane      %s" % LANE)
    print("  bounded   %s" % token)

    if token != "WITHIN-LIMITS":
        print("REFUSED -- the lane did not come back within its bounds (%s)" % token)
        return REFUSED

    missing = [r for r in REQUIRED if r not in rows]
    if missing:
        print("DEAD -- the lane produced %d row(s) and none of: %s" % (len(rows), ", ".join(missing)))
        print("  the lane's stdout was:\n%s" % (proc.stdout or "<empty>"))
        print("  the lane's stderr was:\n%s" % (proc.stderr or "<empty>"))
        return DEAD

    if rows["cc_status"] != "0" or rows["run_status"] != "0":
        print("REFUSED -- the compile or the run did not succeed")
        print("  cc_status=%s run_status=%s" % (rows["cc_status"], rows["run_status"]))
        print("  cc_err=%s" % rows.get("cc_err", ""))
        print("  run_err=%s" % rows.get("run_err", ""))
        return REFUSED

    ok = True
    ok &= cmp_row("mode", rows["mode"], "real", verdicts)
    ok &= cmp_row("sig", rows["sig"], p["expect_sig"], verdicts)
    ok &= cmp_row("in12", rows["in12"], p["expect_in12"], verdicts)
    ok &= cmp_row("in15", rows["in15"], p["expect_in15"], verdicts)
    ok &= cmp_row("changed", rows["changed"], p["expect_changed"], verdicts)
    ok &= cmp_row("out", rows["out"], p["expect_out"], verdicts)

    # THE CONTROL INSIDE THE ROW. `changed` counts cells that left the sentinel, so "20 of 20"
    # means THE KERNEL WROTE EVERY CELL. Without it, a buffer that was already correct would
    # satisfy `out` while the kernel did nothing.
    wrote = rows["changed"] == p["expect_changed"]
    verdicts.append(("wrote-every-cell", "AGREE" if wrote else "DISAGREE",
                     rows["changed"], p["expect_changed"]))
    ok &= wrote

    if "--plants" in argv:
        ok &= run_plants(p, verdicts)

    width = max(len(v[0]) for v in verdicts)
    for name, verdict, got, want in verdicts:
        line = "  %-*s %-9s" % (width, name, verdict)
        if verdict not in ("AGREE", "RED"):
            line += " got=%r want=%r" % (got, want)
        print(line)
    # NOT A ROW: the rendered text's LENGTH is information, not a claim. The kernel is allowed to
    # change; what must not change is what it COMPUTES, and that is the `out` row above.
    print("  %-*s %s (the port's rendered text, for the record)" % (width, "c_len", rows["c_len"]))

    if not ok:
        print("FAIL -- a row ran and disagreed (%d rows compared)" % len(verdicts))
        return FAIL
    print("PASS -- %d row(s) agreed, and the kernel the port rendered computed the matmul"
          % len(verdicts))
    return PASS


def run_plants(p, verdicts):
    """The three planted lanes. A plant that stays GREEN is a FAILURE OF THE GATE, not a pass:
    it would mean the comparison cannot see a wrong number."""
    print("\n  THE PLANTS -- each must move the answer, and a green plant fails this gate")
    ok = True
    for plant, expect in (("plant=data", "diff"), ("plant=swap", "diff"), ("plant=nocall", "none")):
        rows, token, proc = run_lane(plant)
        got = rows.get("out", "<no out row>")
        changed = rows.get("changed", "<no changed row>")
        if token != "WITHIN-LIMITS" or "out" not in rows:
            verdicts.append((plant, "REFUSED", token, "WITHIN-LIMITS"))
            print("  %-12s REFUSED (%s)" % (plant, token))
            ok = False
            continue
        if expect == "diff":
            moved = norm(got) != norm(p["expect_out"])
            verdicts.append((plant, "RED" if moved else "STILL-GREEN", got, p["expect_out"]))
            print("  %-12s %-12s changed=%-3s out=%s" % (plant, "RED" if moved else "STILL-GREEN",
                                                        changed, got[:44]))
        else:
            # THE NO-OP PLANT'S ROW IS `changed`, NOT `out`: an unwritten buffer is -99 in every
            # cell, so the OUT row is a second witness of the same fact and the `changed` count
            # is the control that says the kernel wrote nothing at all.
            moved = changed == p["expect_plant_nocall_changed"]
            verdicts.append((plant, "RED" if moved else "STILL-GREEN", changed,
                             p["expect_plant_nocall_changed"]))
            print("  %-12s %-12s changed=%s (the kernel did not run, so the buffer is the "
                  "sentinel)" % (plant, "RED" if moved else "STILL-GREEN", changed))
        ok &= moved
        sys.stdout.flush()
        del proc
    return ok


if __name__ == "__main__":
    sys.exit(main())
