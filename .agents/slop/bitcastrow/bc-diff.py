#!/usr/bin/env python3
"""COMPARE WHOLE `name=value` LINES, and name every row that moved.

The house rule this exists for: a name-comparing harness reported 0 for all 30 mutations
in one unit and 0 for all 68 in another, because it compared row NAMES and the
mutation did not change any. Here the compared object is the WHOLE LINE, so a value that
moves is a moved line even when its name is untouched.

    .venv/bin/python .agents/slop/bitcastrow/bc-diff.py LABEL NEW BASE [--require N] [--rows N]

Prints, per differing row: name, the baseline line, the new line. Exits 0 when nothing
moved AND the compared set is NON-EMPTY -- the emptiness guard is the point, because a
harness that diffed two empty files would report UNCHANGED, which is exactly the
`${=SUB}` failure gates/README.md records.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def rows(path):
    """WHOLE `name=value` LINES, as a MULTISET keyed on `name`.

    A multiset and not a dict, because `fold.bend` emits `lf_sub_int32_-3_4` TWICE (two
    fixtures, the same name, both measured correct) and a dict silently collapsed them:
    the lane then counted 333 while the file held 334, and `--rows 334` failed for a
    reason that had nothing to do with the change under test. A duplicate NAME is real
    data here, so it is counted rather than resolved.
    """
    out = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith(("bend ", "[bounded]")):
            continue
        name = line.split("=", 1)[0] if "=" in line else "<no-eq>"
        out.setdefault(name, []).append(line)
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    label, new_p, base_p = argv[0], argv[1], argv[2]
    flags = argv[3:]
    need = int(flags[flags.index("--require") + 1]) if "--require" in flags else None
    want = int(flags[flags.index("--rows") + 1]) if "--rows" in flags else None

    base, new = rows(base_p), rows(new_p)
    # NON-EMPTINESS ASSERTED BEFORE ANY COMPARISON. Two empty lanes compare equal and
    # "UNCHANGED" would be a vacuous pass -- the `""` vs `""` failure gates/README.md
    # records for the retired shell form.
    for tag, d, f in (("baseline", base, base_p), ("new", new, new_p)):
        if not d:
            print(f"{label}: the {tag} lane {f} has NO ROWS -- the comparison below would "
                  f"report UNCHANGED vacuously", file=sys.stderr)
            return 1
    nb, nn = sum(len(v) for v in base.values()), sum(len(v) for v in new.values())
    if want is not None and nb != want:
        print(f"{label}: the baseline has {nb} rows, expected {want}", file=sys.stderr)
        return 1
    if set(base) != set(new):
        print(f"{label}: ROW NAMES DIFFER: only-baseline={sorted(set(base)-set(new))} "
              f"only-new={sorted(set(new)-set(base))}", file=sys.stderr)
        return 1

    moved = [(n, b, x) for n in sorted(base)
             for b, x in zip(base[n], new[n]) if b != x]
    print(f"{label}: {nb} rows compared, {len(moved)} MOVED")
    for n, b, x in moved:
        print(f"  {n}: {b}  ->  {x}")
    if need is not None and len(moved) < need:
        print(f"{label}: expected at least {need} rows to move and {len(moved)} did",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))