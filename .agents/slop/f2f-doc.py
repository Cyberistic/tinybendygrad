#!/usr/bin/env python3
"""f2f-doc.py -- the `q*` naming and the `n=`-is-a-window note, applied to dtype.bend.

Kept as a file rather than a heredoc so the exact strings are reviewable, and because
`python3 - <<'PY'` inside a shell one-liner loses `\u26a0` to the shell's own escaping.
"""
import sys

OLD = """# SEVEN FIXTURES, and each one is the ONLY way into a def:
#
#   w1  fp8e4m3 -> float32      widening, dtype.py:104. `f2f.up` + `f2f.sign` +
#                              `f2f.nosign` + `f2f.norm` + `f2f.qnan` + `f2f.isnan`
#                              + `f2f.up.tail` + `f2f.ocp`.
#   n1  float32 -> fp8e4m3      narrowing to an e4m3 target, dtype.py:115. `f2f_clamp`
#                              + `rne` + `f2f.down.*` + `f2f.down.m1`.
#   n2  float32 -> fp8e5m2      narrowing to a NON-e4m3 target, and the ONLY way into
#                              `f2f.down.m2` (dtype.py:120's `else` arm).
#   f1  fp8e4m3fnuz -> float32  `fr in dtypes.fp8_fnuz`, dtype.py:108 -- the ONLY fixture
#                              that reaches `f2f.fnuz`, one of the three defs whose `U32`
#                              return was the forward reference.
#   f2  float32 -> fp8e5m2fnuz  `to in dtypes.fp8_fnuz`, dtype.py:123 -- the ONLY fixture
#                              that reaches `f2f.down.fnuz`.
#   x1  float16 -> bfloat16     dtype.py:125 `else: raise NotImplementedError`. THE
#                              NEGATIVE ROW: a fixture that must FAIL. `f2f.sel2`
#                              answers 2 and `f2f.sel`'s `_` arm maps it to `None`, so the
#                              port DECLINES where CPython RAISES. Printing `unported` is
#                              the honest string: it says the port does not build the arm,
#                              and it is NOT dtype.py's exception name.
#   x2  float32 -> float64      a widening whose `mx` is an `f64` CONST -- the second arm
#                              of `f2f_clamp_max`, the subject `c7` names.
#
# CPython, `.agents/slop/f2f-fixtures.py`, run twice with the same result. NOT
# transcribed: that file calls `DD.f2f` on a live `tinygrad`."""

NEW = """# SEVEN FIXTURES, and each one is the ONLY way into a def:
#
#   q1  fp8e4m3 -> float32      widening, dtype.py:104. `f2f.up` + `f2f.sign` +
#                              `f2f.nosign` + `f2f.norm` + `f2f.qnan` + `f2f.isnan`
#                              + `f2f.up.tail` + `f2f.ocp`.
#   q2  float32 -> fp8e4m3      narrowing to an e4m3 target, dtype.py:115. `f2f_clamp`
#                              + `rne` + `f2f.down.*` + `f2f.down.m1`.
#   q3  float32 -> fp8e5m2      narrowing to a NON-e4m3 target, and the ONLY way into
#                              `f2f.down.m2` (dtype.py:120's `else` arm).
#   q4  fp8e4m3fnuz -> float32  `fr in dtypes.fp8_fnuz`, dtype.py:108 -- the ONLY fixture
#                              that reaches `f2f.fnuz`, one of the three defs whose `U32`
#                              return was the forward reference.
#   q5  float32 -> fp8e5m2fnuz  `to in dtypes.fp8_fnuz`, dtype.py:123 -- the ONLY fixture
#                              that reaches `f2f.down.fnuz`.
#   q6  float16 -> bfloat16     dtype.py:125 `else: raise NotImplementedError`. THE
#                              NEGATIVE ROW: a fixture that must FAIL. `f2f.sel2`
#                              answers 2 and `f2f.sel`'s `_` arm maps it to `None`, so the
#                              port DECLINES where CPython RAISES. Printing `unported` is
#                              the honest string: it says the port does not build the arm,
#                              and it is NOT dtype.py's exception name.
#   q7  float32 -> float64      a widening whose `mx` is an `f64` CONST -- the second arm
#                              of `f2f_clamp_max`, the subject `c7` names.
#
# CPython, `.agents/slop/f2f-fixtures.py`, run twice with the same result. NOT
# transcribed: that file calls `DD.f2f` on a live `tinygrad`.
#
# !! THE NAMES ARE `q*` AND NOT `f*`/`g*`/`h*`/`k*`, because `.agents/slop/dd-oracle.py`
# ALREADY OWNS THOSE for the SAME DEFS with DIFFERENT fixtures: its `f1` is
# `fp8e4m3 -> f32` where `q1` is, its `f2` is `fp8e4m3fnuz -> f32` where `q4` is, and
# its `g3`/`g4`/`g6`/`g7` are `q2`/`q3`/`q5`/`q7`. Two DIFFERENT fixtures sharing one
# `name=` key is a disagreement MANUFACTURED BY THE NAMING, and `dd-band-diff.py` cannot
# see it -- it compares whole `name=value` lines, so a collision reads exactly like a real
# bug. MEASURED: with `f1`/`f2` reused, the differ reported 8 disagreements of which 4
# were this collision and 0 were real. `grep -c '^q' dd-oracle.txt` is 0.
#
# !! `n=` IS THE INTERNING WINDOW (`rows.put`'s `to - from`), and CPython's is the same
# quantity -- `dd-oracle.py`'s `ORDER` hook, reinstalled in `f2f-fixtures.py`. It is NOT
# the cone size, which deduplicates shared subtrees and the window does not: `q1n` is 26
# and `q1c` is 27, and the two are separate rows for that reason."""


def main():
    p = sys.argv[1]
    s = open(p).read()
    if s.count(OLD) != 1:
        raise SystemExit(f"ANCHOR {s.count(OLD)}-BAD")
    open(p, "w").write(s.replace(OLD, NEW, 1))
    print("documentation updated")


if __name__ == "__main__":
    main()