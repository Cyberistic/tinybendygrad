#!/usr/bin/env python3
"""multi-collision.py -- for each of the 26 names both sides spell alike, WHAT is each side
measuring, and is the port's answer consistent with CPython's value.

The question this answers is not "do the strings match". It is: the port prints `eq(a, b)`
-- a BOOLEAN about a PROJECTION of a quantity -- while the oracle prints the QUANTITY. So a
name both sides spell alike is not evidence of a correspondence and a name they spell
differently is not evidence against one. For each collision this reads the port's own row
body out of multi.bend, names the predicate it asserts, evaluates that predicate against the
value CPython returned, and reports CONSISTENT / INCONSISTENT / UNCLEAR.

A CONSISTENT verdict means the port's 1 is TRUE on CPython's own answer: the row is not
wrong, it is encoded differently. An INCONSISTENT verdict is a PORT DEFECT -- the port
asserts something CPython's value contradicts.

    .venv/bin/python .agents/slop/multi-collision.py
"""
import pathlib
import re
import sys

SLOP = pathlib.Path(__file__).resolve().parent
PORT = SLOP.parents[1] / "tinybendygrad" / "schedule" / "multi.bend"

# `def t_NAME() -> U32: BODY`, one line each in this file. Read once so no body is
# transcribed: a hand-copied body is the exact class of error this file exists to catch.
BODIES = {}
for line in PORT.read_text().splitlines():
  m = re.match(r"def t_(\w+)\(\) -> U32: (.*)$", line)
  if m:
    BODIES[m.group(1)] = m.group(2)

# (name, what the PORT asserts, evaluated against CPython's value from multi-raw-oracle.py)
# The middle column is the port's OWN expression with `eq`/`yes` named out.
CLAIMS = {
    # broadcast_axes: `bx_n` is the LENGTH and `bx_a0` is the FIRST element (multi.bend:2551).
    "bx_none":   ("len(broadcast_axes((2,3),(2,3))) == 0",        "bx_n", (), 0),
    "bx_pad":    ("broadcast_axes((3,),(2,3))[0] == 0",          "bx_a0", (0,), 0),
    "bx_exp":    ("broadcast_axes((1,3),(2,3))[0] == 0",         "bx_a0", (0,), 0),
    "bx_both":   ("len(broadcast_axes((1,),(2,3))) == 2",         "bx_n", (0, 1), 2),
    "bx_noop":   ("len(broadcast_axes((2,),(2,3))) == 1",         "bx_n", (0,), 1),
    "bx_scalar": ("len(broadcast_axes((),(2,3))) == 2",           "bx_n", (0, 1), 2),
    "bx_1out":   ("len(broadcast_axes((2,),(1,2))) == 1",         "bx_n", (0,), 1),
    "bx_11":     ("len(broadcast_axes((1,),(1,))) == 0",          "bx_n", (), 0),
    "bx_1_2":    ("broadcast_axes((1,),(2,))[0] == 0",            "bx_a0", (0,), 0),
    "bx_rank1":  ("len(broadcast_axes((3,),(3,))) == 0",          "bx_n", (), 0),
    # permute_multi: `pm_index` is `tuple.index` on BOTH sides (multi.bend:1424).
    "pm_id":     ("(0,1).index(0) == 0",                         "pm_index", 0, 0),
    "pm_sw1":    ("(1,0).index(1) == 0",                         "pm_index", 0, 0),
    "pm_cyc":    ("(2,0,1).index(1) == 2",                       "pm_index", 2, 2),
    "pm_rev":    ("(2,1,0).index(2) == 0",                       "pm_index", 0, 0),
    # the 5 that AGREE -- included, because an agreement on the literal `1` is the one a
    # normalisation would report as corroboration and it is the least informative row here.
    "pm_id1":    ("(0,1).index(1) == 1",                         "pm_index", 1, 1),
    "pm_sw":     ("(1,0).index(0) == 1",                         "pm_index", 1, 1),
    "pm_cyc0":   ("(2,0,1).index(0) == 1",                       "pm_index", 1, 1),
    "pm_mid":    ("(0,2,1).index(2) == 1",                       "pm_index", 1, 1),
    "fl_mid_n":  ("len(flip axes of (0,1,0)) == 1",               "fl_n", 1, 1),
    # reduce_multi: `mu_len` is the LENGTH of the red/rem list (multi.bend:2666-2671).
    "rd_all_red":  ("len(reduced axes of [(0,4),(1,4)], na=1) == 1", "mu_len", (0,), 1),
    "rd_all_rem":  ("len(remaining axes of [(0,4),(1,4)], na=1) == 1", "mu_len", (1,), 1),
    "rd_some_red": ("len(reduced axes of [(1,4),(2,4)], na=1) == 0", "mu_len", (), 0),
    "rd_some_rem": ("len(remaining axes of [(1,4),(2,4)], na=1) == 2", "mu_len", (1, 2), 2),
    "rd_none_red": ("len(reduced axes of [(2,4),(3,4)], na=1) == 0", "mu_len", (), 0),
    "rd_two_red":  ("len(reduced axes of [(0,4),(1,4)], na=2) == 2", "mu_len", (0, 1), 2),
    # reshape_multi: `rs_mid` cannot raise, so the row is the REFUSAL (multi.bend:2746).
    "rs_mid_ok": ("(2,12) does not contain 4 as a partial product, so not ok",
                  "yes(Rs.ok(...))", 0, 0),
}


def main():
  print(f"port row bodies read from {PORT.name}: {len(BODIES)}")
  missing = [k for k in CLAIMS if k not in BODIES]
  if missing:
    sys.exit(f"REFUSING: these claimed rows are not in the port: {missing}")

  inc = []
  for nm in sorted(CLAIMS):
    claim, reader, value, want = CLAIMS[nm]
    if isinstance(value, tuple):
      got = len(value) if reader in ("bx_n", "mu_len") else (value[0] if reader == "bx_a0" else value)
    else:
      got = value
    ok = got == want
    (inc.append(nm) if not ok else None)
    print(f"{nm:<12} {reader:<11} port says {want!r:<5} cpython {got!r:<8} "
          f"{'CONSISTENT' if ok else 'INCONSISTENT'}   {claim}")
    print(f"{'':<12} body: {BODIES[nm]}")
  print(f"\n{len(CLAIMS)-len(inc)} CONSISTENT of {len(CLAIMS)} collisions; "
        f"{len(inc)} INCONSISTENT {inc}")


if __name__ == "__main__":
  main()
