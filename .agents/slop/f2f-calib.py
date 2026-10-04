#!/usr/bin/env python3
"""f2f-calib.py -- WHAT THE PAD SWEEP CAN AND CANNOT SEE, measured.

The sweep prepends `pad` PARAMs and asks whether the answer's mask CONST moves with `pad`.
That is a question about POSITION, so it discriminates exactly one kind of defect: a wrong
value that is a function of the fixture's slot number rather than of its value. Everything
else is position-INDEPENDENT and the sweep says nothing about it, however clean it looks.

So for each injected class this prints, per pad, the mask CONST the port interned, and
whether that value TRACKS `pad`. The verdict column is the claim the sweep licenses.

  tracks pad   = the wrong value is a function of arena position -> the sweep sees it
  fixed        = the wrong value is a constant                  -> the sweep is blind
  the sweep's whole value is the `tracks pad` row. A `fixed` row is caught by ONE fixture
  compared to CPython, and no number of arena sizes adds anything.
"""
import re
import sys


def rows(path):
    """Keys are `<fx>.<pad><rowname>`, so `n1.p0k` is fixture n1, pad 0, row `k`.

    The pad is the digits between the `p` and the trailing row letter, which is why the
    row name is stripped off the RIGHT: `p17k` must not parse as pad `17`, row `` and
    pad `1`, row `7k`.
    """
    out = {}
    for line in open(path):
        m = re.match(r'^(\w+)\.p(\d+)([a-z])=(.*)$', line.strip())
        if m:
            out[f"{m.group(1)}.p{m.group(2)}{m.group(3)}"] = m.group(4)
    return out


def main():
    fixed = rows(sys.argv[1])
    oracle = rows(sys.argv[2])
    # The mask CPython interns in `n1` -- `1 << (fe-1)`'s partner, `2**fe - 1` with
    # fe = 8 for a float32 source, so 255. Read from the ORACLE, not typed.
    want = [v for k, v in oracle.items() if k.startswith("n1.p0k")][0].split(",")
    print(f"CPython's n1 mask CONST list: {want}")
    print(f"{'class':8} {'pad':>4}  {'mask CONSTs beyond the fixed lane':44} verdict")
    for cls in sys.argv[3:]:
        got = rows(f"{cls}.txt")
        base = set(fixed[f"n1.p0k"].split(","))
        tracks = set()
        for pad in (0, 1, 2, 5, 17, 64):
            extra = [c for c in got[f"n1.p{pad}k"].split(",") if c not in base]
            tracks.add(tuple(extra))
            print(f"{cls:8} {pad:>4}  {','.join(extra) or '-':44}")
        verdict = "TRACKS pad -- the sweep sees it" if len(tracks) > 1 else \
                  "FIXED -- invisible to the sweep"
        print(f"{cls:8} {'':4}  {'':44} {verdict}\n")


if __name__ == "__main__":
    main()