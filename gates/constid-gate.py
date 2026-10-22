#!/usr/bin/env python3
"""constid-gate.py -- THE CONST-IDENTITY GATE: the merge, the split, and the wall.

    .venv/bin/python gates/constid-gate.py

TEN ROWS, THREE LANES -- CPython, bend interpreted (JS), bend compiled (C) -- over the two
places where a float CONST's IDENTITY can differ from upstream's.  A CONST's identity is a
HASH, so every count here is a COUNT OF KEYS IN ONE HASH TABLE, and never two equal values
in one row: upstream's table is `UOpMetaClass.ucache` and the port's is the ARENA.

THE FOUR COMPARED ROWS are the ones CPython can be asked the SAME question about, and they
AGREE:

    merge_f32_bits         the f32 of 0.1 is 0x3DCCCCCD on both sides, so the port's 32 bits
                           ARE the f32 of upstream's value.
    merge_keys_control     two constants upstream keeps apart are two keys on both sides, so
                           a count that reads 1 for every pair is a count that measured
                           nothing.
    split_keys_same        the same nan payload twice is ONE key on both sides -- and the
                           reason is `__hash__` (`hash(self.bits)`), not `__eq__`.
    split_keys_reachable   the REACHABLE nan is one key on both sides: upstream's
                           `DType.const` canonicalises a nan to `math.nan` (`dtype.py:81-82`),
                           so upstream has exactly one reachable const nan payload too.

THE THREE DECLARED DIVERGENCES are the MERGE, and they are PINNED on both sides so they
cannot change silently:

    merge_keys        upstream 2 keys, the port 1.  `0.1` and `0.10000000149011612` are two
                      doubles upstream -- two `ConstFloat.bits`, two hashes -- and ONE f32
                      here.
    merge_keys_int    upstream 2 keys, the port 1.  The same for 16777217.0 and
                      16777216.0, which is the pair whose VALUE the port's own formatter
                      can see: 2**24+1 is the smallest integer an f32 cannot hold.
    merge_value_text  upstream holds 16777217.0, the port holds 16777216.0.  The constant
                      HOLDS A DIFFERENT NUMBER.

THE THREE PORT-ONLY ROWS are the LANE SPLIT, and they are the half of the split that is
about STORAGE rather than about the comparator:

    split_keys_distinct  two nan payloads: the C lane keeps the payload and answers 2 keys,
                         the JS lane hands the float to JavaScript, whose `NaN` is a single
                         value, and answers 1.
    split_eq_distinct    the port's key comparator on the two payloads: 0 in the C lane
                         (the bits differ) and 1 in the JS lane (the bits are ALREADY the
                         same, because the payload is gone).
    split_bits_p2        the bits of the second payload after the round trip: 0x7FC00001 in
                         the C lane and 0x7FC00000 in the JS lane.

THE LANE SPLIT IS NOT A ROW A DIFF CAN SEE, so the gate carries its own check for it: the
two port lanes are read and the SPLIT is asserted, so a JS lane that learns to keep a nan
payload makes this gate go RED and say so.  A split that could not move would be a label.

WHAT THIS GATE DOES NOT CLAIM.  It does not claim the port's `eq_const.CFloat` is wrong:
it is the bitwise comparator, and upstream's own hash table is bitwise too, so it is RIGHT.
`gates/constid-plant.py` measures the two alternatives and finds that NEITHER is a fix --
IEEE SPLITS a constant upstream interns as one, and upstream's own `__eq__` MERGES two
different nan payloads upstream's hash table keeps apart.  What diverges is the WIDTH
(`CFloat` above), not the comparison.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

# TEN ROWS: four COMPARED, three DIVERGES (excluded from the diff and pinned on both
# sides), three PORT-ONLY (the lane split).  The count is DERIVED from the two lists, so
# the two numbers cannot disagree.
COMPARED = ("merge_f32_bits", "merge_keys_control", "split_keys_same",
            "split_keys_reachable")
DIVERGES = {
    "merge_keys": ("merge_keys=2", "merge_keys=1"),
    "merge_keys_int": ("merge_keys_int=2", "merge_keys_int=1"),
    "merge_value_text": ("merge_value_text=16777217.000000", "merge_value_text=16777216.000000"),
}
PORT_ONLY = ("split_keys_distinct", "split_eq_distinct", "split_bits_p2")
ROWS = len(COMPARED) + len(DIVERGES) + len(PORT_ONLY)

# THE LANE SPLIT, pinned on BOTH port lanes: (the JS lane's line, the C lane's line).  The
# JS lane is the one `bin/bend <file>` runs -- `main.ts`'s `book_run` -> `Comp.io_run`
# compiles the book to JS and runs it in bun -- and the C lane is the one `bin/bend <file>
# -o <bin>` builds.
LANE_SPLIT = {
    "split_keys_distinct": ("split_keys_distinct=1", "split_keys_distinct=2"),
    "split_eq_distinct": ("split_eq_distinct=1", "split_eq_distinct=0"),
    "split_bits_p2": ("split_bits_p2=2143289344", "split_bits_p2=2143289345"),
}

GATE = Gate(
    "constid-gate",
    bend="constid.bend",
    oracle="constid-oracle.py",
    rows=ROWS,
    compared=len(COMPARED),
    diverges=DIVERGES,
    port_only=list(PORT_ONLY),
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in COMPARED],
)
assert GATE.compared == len(COMPARED)


def _rows(path: Path) -> dict:
    if not path.exists():
        return {}
    return dict(l.split("=", 1) for l in path.read_text().splitlines() if "=" in l)


def lane_split_holds() -> bool:
    """THE LANE SPLIT, asserted on the two port lanes' OWN artifacts.

    A diff compares a row with its counterpart, and the two port lanes' nan rows are
    DIFFERENT BY DESIGN, so the diff cannot see this.  It is therefore pinned here, and a
    lane that learns to keep a nan payload makes this check FAIL rather than pass quietly.
    """
    bd, bn = _rows(GATE.dir / "bd.out"), _rows(GATE.dir / "bn.out")
    bad = {}
    for row, (want_js, want_c) in LANE_SPLIT.items():
        if bd.get(row) != want_js.split("=", 1)[1]:
            bad.setdefault(row, {})["bd"] = bd.get(row)
        if bn.get(row) != want_c.split("=", 1)[1]:
            bad.setdefault(row, {})["bn"] = bn.get(row)
    if bad:
        print(f"constid-gate: the lane split moved: {bad}", file=sys.stderr)
    return not bad


if __name__ == "__main__":
    sys.exit(gate(GATE, f"constid-gate: {ROWS} rows, 3 lanes -- {len(COMPARED)} COMPARED and "
                       f"AGREEING, {len(DIVERGES)} DECLARED divergences (the MERGE: upstream "
                       f"keeps two doubles apart and the port holds one f32, so the constant "
                       f"HOLDS A DIFFERENT NUMBER), and {len(PORT_ONLY)} port-only rows "
                       f"pinning the LANE SPLIT on the nan payload -- the C lane keeps it and "
                       f"the JS lane cannot, and upstream's own hash table is bitwise, so the "
                       f"port's bitwise `eq_const.CFloat` is RIGHT: the plant finds that IEEE "
                       f"SPLITS a constant upstream interns as one, and upstream's own `__eq__` "
                       f"MERGES two nan payloads upstream's hash table keeps apart -- so "
                       f"NEITHER is a fix, and what diverges is the WIDTH",
                  checks=lane_split_holds))
