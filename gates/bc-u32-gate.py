#!/usr/bin/env python3
"""bc-u32-gate.py -- the CPython gate for `bitcast_dims`' RANGE, and the half that was
missing before the fix could be applied.

    .venv/bin/python gates/bc-u32-gate.py

39 rows, THREE LANES, against the real tinygrad BITCAST arm (ops.py:390-396) reached
through `Tensor.bitcast`.

WHAT THIS GATE IS FOR. `fold.bend`'s `bitcast_dims` truncated to U32 THREE times --
`H.lo32` on the dim, `U32.mul` on the product, and `sint_of`'s sign extension on the
quotient -- and NOTHING IN `fold.bend`'s OWN 334 ROWS NAMED `bitcast`. That is the whole
reason the defect survived: a change no row can see is a change nobody can check. This
gate is the rows that see it, and it was built BEFORE the fix and MEASURED against the
unfixed tree, because a row written after the code it approves cannot tell a fix from a
description of the bug.

WHY THIS UNIVERSE AND NOT THE THRESHOLD THAT FAILED. The three truncations have
DIFFERENT boundaries, so one row at `2**32//inp` tests one of three defects:

  band A  the interior -- every row AGREES, two of them are REFUSALS, so the `some_if`
          arm is pinned too. Without this band a universe of only failures cannot tell a
          correct fix from one that refuses everything.
  band B  the `U32.mul` boundary, one step either side, per `inp`, `out = 8` so the
          third truncation is slack. `dim*inp == 2**32` wraps to 0 -- a REFUSAL in the
          port where CPython has a shape -- so this band moves from a number to a
          refusal, and a value-only comparison would miss the flag half.
  band C  the `sint_of` boundary: `out == 1`, `dim*inp == 2**31`. The product is EXACT
          and the port is still wrong, because the quotient's bit 31 became a sign. This
          is the band the previous census could not see.
  band D  the `H.lo32` boundary: `dim >= 2**32`. The `+8`/`+64` rows answer a SMALL
          POSITIVE number where CPython has the full dim, so the failure does NOT look
          like a zero and an "is the answer 0" check misses every one of them.
  band E  L1 and L3 together, so the two truncations can be seen composing.
  band F  `out == inp`, the `same` arm, which never reaches the arithmetic.
  band G  the FIX'S OWN window edge, at `dim*inp == 2**63`.

THE TWO SURVIVING DIVERGENCES ARE PINNED, NOT EXCLUDED. `G_g_i8_at` and `G_g_i4_at` sit
one bit past `dim*inp < 2**63`, because `i64_mul` wraps mod 2**64 and `i64_divmod`
reads bit 63 of the dividend as a sign. The fix MOVED THE WINDOW; it did not abolish
one. A divergence nobody checks is a tolerance, so both sides are asserted below and a
future change that moves them is a gate failure rather than a silently absorbed diff.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate

ROWS = 39
# The two rows at `dim*inp == 2**63`: the fix's own edge. Pin BOTH sides.
DIVERGES = {
    "G_g_i8_at": ("G_g_i8_at=[1,2305843009213693952]", "G_g_i8_at=[1,-2305843009213693952]"),
    "G_g_i4_at": ("G_g_i4_at=[1,1152921504606846976]", "G_g_i4_at=[1,-1152921504606846976]"),
}

GATE = Gate(
    "bc-u32-gate",
    bend=".agents/slop/bitcastrow/bc-rows.bend",
    oracle=".agents/slop/bitcastrow/bc-oracle.py",
    rows=ROWS,
    compared=ROWS - len(DIVERGES),
    diverges=DIVERGES,
    # The band-A refusal rows and the band-F `same` rows: present on every lane, and the
    # claim that they are PRESENT is the point -- a fix that refused everything would
    # lose them rather than pass.
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in
          ("A_a_reject4", "A_a_reject8", "F_f_same_i1", "F_f_same_i8")],
)

if __name__ == "__main__":
    ok = GATE.run() == 0
    if ok:
        # THE DISCRIMINATION ASSERTION, and it is the one line no amount of value
        # checking replaces: the gate's rows must SPAN both answers, and the interior
        # must not have been sacrificed to make that true. A universe of 39 failures
        # would pass a `0 DIFFER` check just as happily as 39 successes.
        lane = {k: dict(l.split("=", 1) for l in (GATE.dir / f"{k}.{'rows' if k == 'py' else 'out'}").read_text().splitlines()
                        if "=" in l) for k in ("py", "bd", "bn")}
        refuses = sum(1 for n, v in lane["bd"].items() if v == "raise")
        shapes = sum(1 for n, v in lane["bd"].items() if v != "raise")
        if not refuses or not shapes:
            print(f"bc-u32-gate: the port lane is all-refusals ({refuses}) or all-shapes "
                  f"({shapes}); a row set that cannot do both cannot refute a fix that "
                  f"does only one", file=sys.stderr)
            ok = False
        # The band-C rows are the ones the previous census could not see, so their
        # presence is asserted by NAME rather than by count.
        for r in ("C_c_i2_at", "C_c_i4_at", "C_c_i8_at"):
            if lane["bd"].get(r) != "[1,2147483648]":
                print(f"bc-u32-gate: {r} is {lane['bd'].get(r)!r}, not [1,2147483648] -- "
                      f"the sign-extension defect is back or the row moved", file=sys.stderr)
                ok = False
    print(f"bc-u32-gate: {ROWS} rows, 3 lanes, {len(DIVERGES)} pinned divergences "
          f"at the 2**63 window edge" if ok else "bc-u32-gate: FAILED")
    sys.exit(0 if ok else 1)