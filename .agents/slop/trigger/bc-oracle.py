#!/usr/bin/env python3
"""Oracle for `uop/fold.bend`'s `bitcast_dims` U32-vs-I64 DECISION (the `fold.bend:509-514` comment).

Every `cpython=` expectation below is CALLED, never typed. The CPython side is the real
`tinygrad` BITCAST arm at `tinygrad/uop/ops.py:390-396` -- reached through
`Tensor.bitcast`, and `"unsupported size in bitcast"` is the proof it is THAT arm and not
some other bitcast path. The PORT side is the arithmetic `bitcast_dims.scale` /
`bitcast_dims.put.of` actually performs:

    i   = H.lo32(sint)          # LOW 32 BITS of the last dim      <- truncation 1
    n   = U32.mul(i, inp)       # (i*inp) mod 2**32                 <- truncation 2
    ok  = U32.is_zero(U32.mod(n, out))   # None, i.e. raise, when not zero
    res = sint_of(U32.div(n, out))        # n // out, both operands UNSIGNED

So the port model is `& 0xFFFFFFFF` in exactly two places and CPython's own operators
elsewhere. `//` and `%` are the floor pair, which is what upstream's `//` and `%` are.

Run:  .venv/bin/python .agents/slop/trigger/bc-oracle.py
"""

import sys

sys.path.insert(0, ".")

from tinygrad import Tensor  # noqa: E402

M32 = 0xFFFFFFFF
PAIRS = [(i, o) for i in (1, 2, 4, 8) for o in (1, 2, 4, 8) if i != o]  # ops.py:393 needs out != inp


def cpython(dim, inp, out):
    """(raises: Bool, value) from the real BITCAST arm, or ('unbuildable', err)."""
    try:
        s = Tensor.empty(1, dim, dtype=f"int{inp * 8}").bitcast(dtype=f"int{out * 8}").shape
    except RuntimeError as e:
        return (True, str(e))
    except Exception as e:  # noqa: BLE001 - a refusal to build IS a measurement
        return ("unbuildable", f"{type(e).__name__}: {e}")
    return (False, s[1])


def port(dim, inp, out):
    i = dim & M32
    n = (i * inp) & M32
    return (n % out != 0, n // out)


def show(dim, inp, out):
    craw, cval = cpython(dim, inp, out)
    praw, pval = port(dim, inp, out)
    if craw == "unbuildable":
        print(f"skip  dim={dim} inp={inp} out={out} :: cpython will not build it: {cval}")
        return "skip"
    # Upstream RAISES on `(ps[-1]*inp) % output_sz` being nonzero. The port answers None,
    # which every caller turns into the same refusal, so `raise` and `None` are one answer.
    # BOTH HALVES ARE COMPARED. Comparing only the raise flag reports `cpython=4294967296
    # port=0` as agreement, which is the name-comparing harness this repo has been bitten by.
    same = craw == praw and (bool(craw) or cval == pval)
    print(f"{'ok  ' if same else 'DIFF'} dim={dim} inp={inp} out={out} "
          f"cpython={'raise' if craw else cval} port={'raise' if praw else pval}")
    return same


def band(title, dims):
    print(f"--- {title} ---")
    ok = bad = skip = 0
    for dim in dims:
        for inp, out in PAIRS:
            r = show(dim, inp, out)
            ok += r is True
            bad += r is False
            skip += r == "skip"
    print(f"    -> agree={ok} DIFFER={bad} unbuildable={skip}\n")
    return ok, bad, skip


print(f"itemsize pairs probed: {PAIRS}\n")
a1 = band("non-negative dims, dim*inp < 2**32  (what the comment claims)", [0, 1, 2, 3, 5, 8, 16, 1024, 65535, 1 << 20])
a2 = band("the last in-window dim per inp: 2**32//inp - 1",
          [4294967295, 2147483647, 1073741823, 536870911])
a3 = band("the FIRST out-of-window dim per inp: 2**32//inp",
          [536870912, 1073741824, 2147483648, 4294967296])
a4 = band("far past the window", [1 << 33, 1 << 34, (1 << 40)])
a5 = band("negative dims -- upstream `isinstance(ps[-1], int)` is TRUE for these", [-1, -2, -3, -4, -8, -16])

# The decisive band: for EACH inp, the last dim the comment is right about and the first
# one it is wrong about, so the threshold is pinned by rows rather than inferred from a
# summary. Expected: 0 DIFFER at 2**32//inp - 1 and 3 DIFFER at 2**32//inp (three outs, out != inp).
print("--- THE THRESHOLD ITSELF, one dim either side, per inp ---")
ok6 = bad6 = 0
for inp in (1, 2, 4, 8):
    for dim in (2**32 // inp - 1, 2**32 // inp):
        for out in (1, 2, 4, 8):
            if out == inp:
                continue
            r = show(dim, inp, out)
            ok6 += r is True
            bad6 += r is False
print(f"    -> agree={ok6} DIFFER={bad6}  EXPECTED agree=12 DIFFER=12\n")

T = (a1, a2, a3, a4, a5)
rows = sum(sum(x) for x in T)
ok = sum(x[0] for x in T)
bad = sum(x[1] for x in T)
skip = sum(x[2] for x in T)
print(f"TOTAL rows={rows} agree={ok} DIFFER={bad} unbuildable={skip}")
print(f"THRESHOLD BAND rows={ok6 + bad6} agree={ok6} DIFFER={bad6} (EXPECTED 12 / 12)")
print("\nTHE THRESHOLD, computed rather than typed. `U32.mul` overflows when")
print("`dim*inp >= 2**32`, so the largest exact dim is 2**32//inp - 1:")
for inp in (1, 2, 4, 8):
    print(f"  inp={inp}: exact while dim <= {2**32 // inp - 1}, first divergence at dim = {2**32 // inp}")