#!/usr/bin/env python3
"""gen_wire.py -- the gate for T1-WIRE: which way does an `H.I64` ARGUMENT
arrive across a Bend foreign effect?

Reproduce (from the repo root):
    python3 .agents/slop/w64mile/gen_wire.py

WHAT IS ASSERTED, and why it needs no oracle.  `Dt.i64_trunc` is the identity on
a pair, so the seam's OWN contract says the answer equals the input.  That
statement is definitional, so it is a discriminator and not a transcribed
expectation: nothing here asserts what a wrong answer looks like.  Two readers
are applied to the SAME received bytes (`t1_wire.c`) and the rows are grouped by
WHICH reader is the identity.  Exactly one can be, so the grouping is a
measurement.

ROWS-PRESENT vs ROWS-EXPECTED, and the expectation is COUNTED, not typed: the
fixture table below is the list, the `.bend` has to print a row for every entry,
and a missing row fails the gate instead of shrinking it.

THE PLANT must move exactly the rows whose two halves DIFFER.  Half the fixtures
are equal-halves on purpose: an ordering bug is invisible on those, so without
them a "moved something" plant proves nothing about ordering.
THE DISARM is a different EXPRESSION for the same function (`U32.or(x, 0)` is x),
so the only correct moved-set is the empty one.  A disarm that moved a row would
mean the lane is not the one under test.
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
BEND = REPO / "bin" / "bend"

# (hi, lo). The first four have hi != lo, the last four have hi == lo.
FIXTURES = [
    (1, 2),
    (123456, 654321),
    (0, 7),
    (4000000000, 4000000001),
    (0, 0),
    (7, 7),
    (4294967295, 4294967295),
    (2147483648, 2147483648),
]
ASYMMETRIC = FIXTURES[:4]
SYMMETRIC = FIXTURES[4:]
READERS = ["flat", "boxed", "swap", "same"]


def build() -> dict[str, str]:
    """Compile + run t1_wire.bend once, and index the rows by (reader, fixture).

    A diff WHOLE `name=value` line, not a row name: a name-comparing harness
    reported 0 for every mutation in two earlier units.
    """
    out = HERE / "t1_wire.gen.c"
    exe = HERE / "t1_wire.gen"
    r = subprocess.run([str(BEND), str(HERE / "t1_wire.bend"), "-o", str(out)],
                       capture_output=True, text=True)
    if r.returncode != 0 or not out.exists():
        sys.exit(f"bend failed: {r.stdout}{r.stderr}")
    c = subprocess.run(["cc", "-O1", "-w", "-o", str(exe), str(out)],
                       capture_output=True, text=True)
    if c.returncode != 0:
        sys.exit(f"cc failed: {c.stderr}")
    p = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    rows: dict[str, str] = {}
    for line in p.stdout.splitlines():
        m = re.match(r"^WIRE (\w+)\|(\d+)\|(\d+) = (\d+:\d+)$", line)
        if not m:
            continue
        rows[f"{m[1]}|{m[2]}|{m[3]}"] = m[4]
    return rows


def main() -> None:
    base = build()
    expected = [f"{r}|{a}|{b}" for r in READERS for (a, b) in FIXTURES]
    present = [k for k in expected if k in base]
    print(f"rows present {len(present)} / rows expected {len(expected)}")
    if len(present) != len(expected):
        missing = [k for k in expected if k not in base]
        print(f"FAIL  MISSING ROWS {missing}")
    else:
        print("PASS  every expected row is present, none extra is tolerated")

    # ---- the discriminator. Identity is the contract, so this is derived.
    def is_identity(reader: str) -> bool:
        return all(base[f"{reader}|{a}|{b}"] == f"{a}:{b}" for (a, b) in FIXTURES)

    ident = [r for r in READERS if is_identity(r)]
    print(f"\nidentity readers: {ident}")
    # `same` is the STATED equivalence of `boxed` (U32.or(x,0) is x), so it is
    # REQUIRED to agree; a disagreement there is a defect in the harness, not a
    # second wire. The identity set must therefore be exactly {boxed, same}, and
    # `flat` -- the reader dtype.c:206 uses -- must be absent from it.
    ok_ident = ident == ["boxed", "same"]
    print("PASS  the identity set is exactly {boxed, same}, and `flat` is not "
          "among them" if ok_ident
          else "FAIL  the identity set is not {boxed, same}")

    # ---- port beside the CONTRACT, side by side.
    print("\n| fixture hi:lo | flat (dtype.c:206) | boxed (ctr_take) | swap | same |")
    print("|---|---|---|---|---|")
    for (a, b) in FIXTURES:
        print(f"| `{a}:{b}` | `{base[f'flat|{a}|{b}']}` | `{base[f'boxed|{a}|{b}']}` "
              f"| `{base[f'swap|{a}|{b}']}` | `{base[f'same|{a}|{b}']}` |")

    # ---- PLANT: `swap` against `boxed`. Derived moved-set = rows with hi != lo.
    plant_moved = sorted(f"swap|{a}|{b}" for (a, b) in FIXTURES
                         if base[f"swap|{a}|{b}"] != base[f"boxed|{a}|{b}"])
    want_moved = sorted(f"swap|{a}|{b}" for (a, b) in ASYMMETRIC)
    equal_moved = [k for k in plant_moved
                   if k in [f"swap|{a}|{b}" for (a, b) in SYMMETRIC]]
    print(f"\nPLANT (halves transposed) rows moved {len(plant_moved)}")
    print(f"  derived from the mutation's algebra, rows with hi != lo: {want_moved}")
    print(f"  equal-halves rows that moved (must be none): {equal_moved}")
    print("PLANT: PASS" if plant_moved == want_moved else "PLANT: FAIL")

    # ---- DISARM: a different expression for the same function.
    disarm_moved = sorted(f"same|{a}|{b}" for (a, b) in FIXTURES
                          if base[f"same|{a}|{b}"] != base[f"boxed|{a}|{b}"])
    print(f"DISARM (U32.or(x,0), same function) rows moved {len(disarm_moved)}")
    print("DISARM: PASS  0 is the only correct count" if not disarm_moved
          else f"DISARM: FAIL  moved {disarm_moved}")

    # ---- the consequence, stated against the live tree.
    live = "flat"
    ok = (ok_ident and len(present) == len(expected)
          and plant_moved == want_moved and not disarm_moved)
    print("\n===== VERDICT =====")
    print(f"{'PASS' if ok else 'FAIL'}  an H.I64 argument arrives BOXED "
          f"(one Term, a 2-field record); `{live}` -- "
          f"`runtime/dtype.c:205-206` -- does not read it.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()