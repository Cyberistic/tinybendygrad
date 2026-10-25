#!/usr/bin/env python3
"""PRINT THE HARVESTED PACKET FOR A FIXTURE, NEXT TO THE FIXTURE'S OWN.

    .venv/bin/python .agents/slop/execfix/diffpacket.py <fixture-name>

IT IS THE `oracle.py` HARVEST WITHOUT THE EQUALITY CHECK, SO THE DIFFERENCE IS
VISIBLE INSTEAD OF REFUSED.
"""
import pathlib, sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import oracle as O  # noqa: E402


def main():
    want = sys.argv[1]
    recs = {n: (a, "\n".join(p) + "\n") for n, a, p in O.records()}
    argv, packet = recs[want]
    dt, maker = O.SEEDS[want]
    renders, calls = O.harvest(lambda: maker(dt))
    mine = O.encode(renders[0]).splitlines()
    theirs = packet.splitlines()
    import difflib
    for line in difflib.unified_diff(theirs, mine, "fixture", "harvest", lineterm="", n=1):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
