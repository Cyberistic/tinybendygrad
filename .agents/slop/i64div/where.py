#!/usr/bin/env python3
"""I64DIV: WHICH DEF IS WRONG -- `i64_div` or `cdiv_i64`?

MEASURED, and the comparator is normalised: every port answer is read SIGNED
before it is compared, because the port's I64 pair and CPython's int are the same
64 bits read two ways. An earlier version of this script compared a raw residue
against a signed int and reported 160 phantom disagreements.
"""
import sys
REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, REPO)
from tinygrad.helpers import cdiv, cmod, floordiv, floormod  # noqa: E402

W = 1 << 64
S = 1 << 63
def u(v): return v & (W - 1)
def sg(v):
    v = u(v)
    return v - W if v >= S else v
def w(v):
    v = u(v)
    return f"{v >> 32}:{v & 0xFFFFFFFF}"

# ---- the port's algorithm, re-implemented EXACTLY as helpers.bend spells it ----
def port_is_neg(x):  return (u(x) >> 63) & 1 == 1
def port_neg(neg, x): return u(~x + 1) if neg else u(x)
def port_abs(x):      return port_neg(port_is_neg(x), x)

def port_divmod(a, b):
    if u(b) == 0:
        return (0, u(a))
    q, r = u(port_abs(a)) // u(port_abs(b)), u(port_abs(a)) % u(port_abs(b))
    flip = port_is_neg(a) ^ port_is_neg(b)
    q = port_neg(flip, q + (1 if (flip and r != 0) else 0))
    r = port_neg(port_is_neg(b), (u(port_abs(b)) - r) if (flip and r != 0) else r)
    return (q, r)

def port_div(a, b):  return sg(port_divmod(a, b)[0])
def port_mod(a, b):  return sg(port_divmod(a, b)[1])
def port_cdiv(x, y):
    if u(y) == 0: return 0
    return sg(port_neg(port_is_neg(x) ^ port_is_neg(y), port_div(u(port_abs(x)), u(port_abs(y)))))
def port_cmod(x, y): return sg(u(x - port_cdiv(x, y) * u(y)))

EXTREMES = [-S, -S + 1, -(1 << 62), -(1 << 31), -7, -3, -2, -1, 0, 1, 2, 3, 7,
            1 << 31, 1 << 32, (1 << 32) - 1, 1 << 62, S - 2, S - 1]
GRID = [(a, b) for a in EXTREMES for b in EXTREMES]

def sweep(name, mine, theirs, pairs=GRID):
    bad = []
    for a, b in pairs:
        if sg(mine(a, b)) != sg(theirs(a, b)):
            bad.append((a, b))
    wmin = [p for p in bad if u(p[0]) == u(-S) or u(p[1]) == u(-S)]
    wo   = [p for p in bad if u(p[0]) != u(-S) and u(p[1]) != u(-S)]
    print(f"{name:12} pairs={len(pairs):5}  disagree={len(bad):5}  "
          f"with_int64.min={len(wmin):5}  without={len(wo):5}")
    for a, b in bad[:8]:
        print(f"      ({sg(a)}, {sg(b)})  port={sg(mine(a,b))}  upstream={sg(theirs(a,b))}")
    return bad

print("=== SWEEP 1: `i64_div` / `i64_mod` -- THE DEFS THE BRIEF NAMES ===")
bd = sweep("i64_div", port_div, floordiv)
bm = sweep("i64_mod", port_mod, floormod)
print()
print("=== SWEEP 2: `cdiv_i64` / `cmod_i64` -- THE DEFS THE 54 ROWS ARE ON ===")
bc = sweep("cdiv_i64", port_cdiv, cdiv)
bk = sweep("cmod_i64", port_cmod, cmod)

print()
print("=== HYPOTHESIS: cdiv_i64 must take the UNSIGNED quotient, not a floordiv ===")
def fixed_cdiv(x, y):
    if u(y) == 0: return 0
    return sg(port_neg(port_is_neg(x) ^ port_is_neg(y), u(port_abs(x)) // u(port_abs(y))))
def fixed_cmod(x, y): return sg(u(x - fixed_cdiv(x, y) * u(y)))
bcf = sweep("cdiv FIXED", fixed_cdiv, cdiv)
bkf = sweep("cmod FIXED", fixed_cmod, cmod)

print()
print("=== AND THE REMAINDER: `i64_mod` OF A MAGNITUDE PAIR (gcd's use) ===")
print("gcd.go runs i64_mod on i64_abs values, so the magnitude pair's OWN sign bit")
print("is read as a sign. Measured: unsigned magnitude mod, versus what gcd needs.")
def gcd_port(a, b):
    a, b = port_abs(a), port_abs(b)
    for _ in range(128):
        if u(b) == 0: return sg(a)
        a, b = b, u(a) % u(b)
    return sg(a)
import math
bad = [(a, b) for a in EXTREMES for b in EXTREMES
       if gcd_port(a, b) != math.gcd(a, b)]
print(f"  gcd (port sim)  pairs=361  disagree={len(bad)}")
for a, b in bad[:8]:
    print(f"      ({sg(a)}, {sg(b)})  port={gcd_port(a,b)}  upstream={math.gcd(a,b)}")
