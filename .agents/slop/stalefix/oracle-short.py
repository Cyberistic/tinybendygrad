#!/usr/bin/env python
"""The SHORT half: 2 of the green oracle's 3 rows.

This is the only defect scenario 2 needs. The driver typechecks, the warm check passes, the
oracle lane runs, both port lanes run, the native compile runs, and THEN `run()` returns 1 on
the row count -- which is the shape that leaves the three `.sub` files holding the PREVIOUS
run's bytes while `py.txt` holds this run's. A single short row puts the failure after every
lane has written, which is the whole point of having a second scenario at all.
"""
for name, value in (("r0", "0"), ("r1", "1")):
    print(f"{name}={value}")
