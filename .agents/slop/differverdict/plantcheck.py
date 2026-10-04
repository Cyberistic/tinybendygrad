#!/usr/bin/env python3
"""Did the comparison REJECT the plant? Read the planted summary against the oracle's.

A comparison that has never rejected anything is not a comparison. The planted change moved
`PINS['not-comparable']` from "0" to "16", which the brief names as the forbidden move ("a
pin moved to match the code is a gate deleted"). `PINS` feeds `unhealthy()`, which `run` does
NOT call -- so the honest question is whether it moved any ARTIFACT at all, and if not, what
that says about the code under the plant.
"""
import hashlib
import sys
from pathlib import Path

SLOP = Path(__file__).resolve().parent
ORACLE = SLOP / "oracle-D"
PLANTED = SLOP / "python-planted"
PYTHON = SLOP / "python-D"


def nonblank(p: Path) -> bytes:
    return b"".join(ln + b"\n" for ln in p.read_bytes().split(b"\n")[:-1] if ln.strip())


def main():
    if not PLANTED.is_dir() or not any(PLANTED.iterdir()):
        print(f"PLANT RUN PRODUCED NOTHING in {PLANTED} -- the instrument failed, "
              f"not the plant. This proves nothing.")
        return 2
    on = {p.name for p in ORACLE.iterdir() if p.is_file()}
    pn = {p.name for p in PLANTED.iterdir() if p.is_file()}
    base = {p.name for p in PYTHON.iterdir() if p.is_file()}
    print(f"oracle {len(on)} files, unplanted-python {len(base)}, PLANTED-python {len(pn)}")
    diff_vs_oracle = [n for n in sorted(on & pn) if nonblank(ORACLE / n) != nonblank(PLANTED / n)]
    diff_vs_base = [n for n in sorted(base & pn) if nonblank(PYTHON / n) != nonblank(PLANTED / n)]
    print(f"\nPLANTED vs ORACLE: {len(diff_vs_oracle)} differing files")
    for n in diff_vs_oracle:
        print(f"  {n}")
    print(f"\nPLANTED vs UNPLANTED-PYTHON (what the pin edit actually moved): "
          f"{len(diff_vs_base)} differing files")
    for n in diff_vs_base:
        print(f"  {n}")
    print(f"\nfile SET changed by the plant: only-oracle={sorted(on - pn)} "
          f"only-planted={sorted(pn - on)}")
    print(f"file SET changed vs unplanted: only-base={sorted(base - pn)} "
          f"only-planted={sorted(pn - base)}")
    # AND THE PIN'S OWN REACH: does PINS appear in any artifact at all?
    hit = [n for n in sorted(pn) if b"not-comparable" in nonblank(PLANTED / n)]
    print(f"\nfiles whose CONTENT mentions 'not-comparable': {hit}")
    if not diff_vs_base:
        print("\nVERDICT: THE PLANT MOVED NOTHING. `PINS` is read only by `unhealthy()`, which "
              "`run` never calls -- so `run`'s artifacts are blind to a pin edit by "
              "construction. That is a STATEMENT ABOUT THE PLANT, not a pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())