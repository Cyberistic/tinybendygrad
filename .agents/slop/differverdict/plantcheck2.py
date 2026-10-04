#!/usr/bin/env python3
"""Did the comparison REJECT the sort plant? The planted run is compared to BOTH the
oracle's artifacts and the UNPLANTED Python's, so "the comparison is broken" is
distinguishable from "the plant moved nothing".
"""
import sys
from pathlib import Path

SLOP = Path(__file__).resolve().parent
ORACLE = SLOP / "warm-oracle"
PLANTED = SLOP / "warm-planted"
CLEAN = SLOP / "warm-python"


def nb(p: Path) -> bytes:
    return b"".join(ln + b"\n" for ln in p.read_bytes().split(b"\n")[:-1] if ln.strip())


def diffset(x: Path, y: Path) -> tuple[list[str], list[str], list[str]]:
    xn = {p.name for p in x.iterdir() if p.is_file()}
    yn = {p.name for p in y.iterdir() if p.is_file()}
    d = sorted(n for n in xn & yn if nb(x / n) != nb(y / n))
    return d, sorted(xn - yn), sorted(yn - xn)


def main():
    if not PLANTED.is_dir() or not any(PLANTED.iterdir()):
        print("PLANT RUN PRODUCED NOTHING -- instrument failure, proves nothing")
        return 2
    for label, other in (("ORACLE", ORACLE), ("UNPLANTED-PYTHON", CLEAN)):
        d, onlya, onlyb = diffset(other, PLANTED)
        print(f"PLANTED vs {label}: {len(d)} differing files")
        for n in d:
            print(f"    {n}")
        if onlya:
            print(f"    only in {label}: {onlya}")
        if onlyb:
            print(f"    only in PLANTED: {onlyb}")
        print()
    d, _, _ = diffset(ORACLE, PLANTED)
    if d:
        print(f"VERDICT: THE COMPARISON REJECTED THE PLANT -- {len(d)} file(s) differ that "
              f"did not differ before the plant.")
    else:
        print("VERDICT: THE PLANT MOVED NOTHING THE COMPARISON COULD SEE.")
    return 0


if __name__ == "__main__":
    sys.exit(main())