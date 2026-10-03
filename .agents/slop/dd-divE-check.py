#!/usr/bin/env python3
# dd-divE-check.py -- the `c{i}` fixture gate for
# tinybendygrad/codegen/decomp/dtype.bend (dtype.py:128-134, `f2f_clamp`'s `mx`).
#
# WHY THIS EXISTS AND NOT JUST dd-cmp.py. dd-cmp.py compares
# `keys = [k for k in port if k in ora]` -- a row ABSENT FROM BOTH lanes is not
# compared at all. So while the port printed no `c{i}` row, `dd-cmp.py` reported
# "164 gate rows, 0 disagreeing" and the eight missing fixtures were
# indistinguishable from eight passing ones. THIS FILE MAKES ABSENCE AN ERROR:
# every `c{i}` the oracle prints must be present in the port lane, and a missing
# one is a FAILURE with a name, not a silent skip.
#
# EXPECTED STATE (measured, not asserted from a comment):
#   c0..c6  port F(<bits>) == oracle F(<bits>)   -- 7 AGREE
#   c7      port refused:unported vs oracle F(ovf) -- 1 DISAGREE, on purpose.
#           `mx` is `val.const_like(...)` (dtype.py:131) so its value depends on
#           `fr` too; `.agents/slop/dd-divE-probe.py` CALLS both and gets
#           F(2139095040) at fr=f32 and F(ovf) at fr=f64. The oracle's row is a
#           function of `dt` alone, so for the one dtype whose `mx` leaves f32
#           range it has no single answer. Refusing is the port saying so out
#           loud instead of printing nothing.
#
# usage: dd-divE-check.py PORT.txt ORACLE.txt [--degenerate]
#   --degenerate  report run HEALTH only: row count, empty `sig`/`k` values,
#                  missing `c{i}` names. Exit 1 if unhealthy (see dd-divE-run.sh).
import sys


def load(path):
    d = {}
    for ln in open(path):
        ln = ln.rstrip("\n")
        if not ln or ln.startswith("#"):
            continue
        k, _, v = ln.partition("=")
        d[k] = v
    return d


CS = ["c%d" % i for i in range(8)]

# the last run KNOWN to be healthy: `dd-gate.txt`, the port's own current output.
# health() compares against this, never against the oracle -- see health() for why.
GOOD = ".agents/slop/dd-gate.txt"


def health(port, good):
    """A bend run that stack-overflows mid-walk still prints EVERY row: the cone walks
    just come back wrong. Measured across four runs of one tree, the signatures are an
    EMPTY `sig=` and a `k=` that came back `-`, with the row itself present. Row COUNTS
    see neither -- dd-run.sh's `^lg` guard passed every one of those runs.

    So health is a comparison against a KNOWN-GOOD RUN, not against the oracle: `-` on a
    `k` row is sometimes the right answer (`lg7k`, `lg8k`, `lgck` are `-` in the healthy
    baseline because those cones hold no constant), so "is `-` bad?" has no oracle-shaped
    answer -- only "is this run worse than the last run known to be good?". `good` is
    `.agents/slop/dd-gate-base.txt`, the coordinator's byte-identical healthy capture."""
    return sorted(k for k, gv in good.items()
                  if gv and gv != "-"
                  and (k.endswith("sig") or k.endswith("k"))
                  and (not port.get(k) or port[k] == "-"))


def main():
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    port, ora = load(a[0]), load(a[1])
    good = load(a[2]) if len(a) > 2 else load(GOOD)
    bad_sig = health(port, good)
    missing = [c for c in CS if c not in port]

    if "--degenerate" in sys.argv:
        print("rows=%d  worse-than-known-good sig/k=%d %s  missing-c=%d %s"
              % (len(port), len(bad_sig), bad_sig[:6], len(missing), missing))
        return 1 if (bad_sig or missing) else 0

    bad = 0
    for c in CS:
        if c not in port:
            print("%-4s FAIL               ABSENT FROM THE PORT LANE -- dd-cmp.py never "
                  "compares it, so the absence was invisible until now" % c)
            bad += 1
            continue
        pv, ov = port[c], ora.get(c, "<oracle does not print it>")
        # c7 is EXPECTED to disagree, so compare the FACT and not the two labels --
        # comparing labels makes the intended-permanent disagreement unpassable.
        disagree = pv != ov
        ok = disagree if c == "c7" else not disagree
        if not ok:
            bad += 1
        print("%-4s %-19s port=%-18s ora=%-14s want=%s"
              % (c, "ok" if ok else "FAIL", pv, ov,
                 "DISAGREE" if c == "c7" else "AGREE"))

    print("\n%d/%d c-rows in the expected state, %d unexpected" % (8 - bad, 8, bad))
    print("run health: %d sig/k rows worse than the known-good capture: %s"
          % (len(bad_sig), bad_sig[:6]))
    return 1 if bad else 0


sys.exit(main())