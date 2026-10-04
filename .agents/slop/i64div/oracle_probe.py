#!/usr/bin/env python3
"""I64DIV oracle probe. Calls tinygrad/helpers.py. NOTHING IS TYPED BY HAND."""
import sys
REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, REPO)
from tinygrad.helpers import cdiv, cmod, floordiv, floormod, ceildiv  # noqa: E402

S = 1 << 63
def w(v):
    v &= (1 << 64) - 1
    return f"{v >> 32}:{v & 0xFFFFFFFF}"
def sg(v):
    v &= (1 << 64) - 1
    return v - (1 << 64) if v >= S else v

CASES = [
    ("p_1_over_min",     1, -S),
    ("p_min_over_min",  -S, -S),
    ("p_min_over_3",    -S, 3),
    ("p_1_over_2p62",    1, 1 << 62),
    ("p_max_over_min",  S - 1, -S),
    ("p_minp1_over_min", -S + 1, -S),
    ("p_min_over_neg1", -S, -1),
    ("p_2p62x2_over_min", 1 << 62, -S),
    ("p_2p63m1_over_2p62", S - 1, 1 << 62),
    ("p_neg1_over_min", -1, -S),
    ("p_max_over_3",    S - 1, 3),
    ("p_min_over_7",    -S, 7),
    ("p_min_over_neg7", -S, -7),
    ("p_max_over_min_p1", S - 1, -S + 1),
]
print(f"{'row':22} {'floordiv':>22} {'floormod':>22} {'cdiv':>22} {'cmod':>22}")
for nm, a, b in CASES:
    print(f"{nm:22} {w(floordiv(a,b)):>22} {w(floormod(a,b)):>22} {w(cdiv(a,b)):>22} {w(cmod(a,b)):>22}")

print()
print("--- signed values (what the pair means) ---")
for nm, a, b in CASES:
    print(f"{nm:22} a={sg(a):>21} b={sg(b):>21}  floordiv={sg(floordiv(a,b)):>21}")

print()
print("--- the three zero-divisor rows, MEASURED not assumed ---")
for f in (floordiv, cdiv, cmod, floormod):
    try:
        print(f"  {f.__name__:9}(7, 0) = {f(7, 0)}")
    except Exception as e:
        print(f"  {f.__name__:9}(7, 0) raised {type(e).__name__}")
try:
    print("  ceildiv  (7, 0) =", ceildiv(7, 0))
except Exception as e:
    print("  ceildiv  (7, 0) raised", type(e).__name__)
print("  floordiv(0, 0) =", floordiv(0, 0), " floormod(0,0) =", floormod(0, 0),
      " cdiv(0,0) =", cdiv(0, 0), " cmod(0,0) =", cmod(0, 0))
