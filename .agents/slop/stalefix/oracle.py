#!/usr/bin/env python
"""The GREEN half of `stale-repro.py`: 3 rows, byte-identical to `green.bend`'s stdout.

A synthetic oracle, so the repro costs one bend compile and no tinygrad import. The rows are
`name=value`, which is the shape every real gate oracle emits, and `green.bend` prints exactly
these three lines.
"""
for name, value in (("r0", "0"), ("r1", "1"), ("r2", "2")):
    print(f"{name}={value}")
