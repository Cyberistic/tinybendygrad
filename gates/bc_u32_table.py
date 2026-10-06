#!/usr/bin/env python3
"""THE FIXTURE TABLE, ONCE. Every `.bend` row line and every CPython expectation is
GENERATED from `ROWS` here, so a fixture cannot be right on one lane and wrong on the other.

WHY THE UNIVERSE IS NOT "THE THRESHOLD THAT FAILED". `bitcast_dims` truncates to U32
THREE times, not once, and the three have DIFFERENT boundaries:

  L1  `H.lo32(i)`      the last dim  -> bites at `dim >= 2**32`
  L2  `U32.mul(i,inp)` the product   -> bites at `(dim mod 2**32)*inp >= 2**32`
  L3  `sint_of(q)`     `i64_of_i32`'s sign extension of the QUOTIENT -> bites at
      `(dim*inp)//out >= 2**31`, which for `out == 1` is `dim*inp >= 2**31` -- i.e.
      INSIDE the window `fold.bend` claims is exact.

L3 is why a single row at the documented threshold tests one of three defects, and why
the documented threshold `2**32//inp - 1` is not the true one: for `out == 1` the
binding constraint is `2**31//inp - 1`, and band a2 of `.agents/slop/trigger/
bc-oracle.py` ("0 DIFFER at 2**32//inp - 1") is FALSE for its `inp=2, out=1` row.

Each row below is tagged with the mode it isolates. `ps` is the 2-axis shape `[1, dim]`,
so a row shows BOTH that `ps[:-1]` survives and what the scaled last dim is.
"""

M32 = 0xFFFFFFFF
P31 = 0x80000000
P63 = 0x8000000000000000
P64 = 0x10000000000000000

# band -> rows.  A row is (name, dim, inp, out).  The shape handed to `bitcast_dims`
# is `[1, dim]`, so `inp` and `out` are ITEMSIZES and `dim` is the dim being scaled.
BANDS = {
    # ---- A: THE INTERIOR. all three constraints slack. every one of these AGREES,
    # and two of them are REFUSALS, so the `some_if` arm is pinned too.
    "A": [
        ("a_one", 1, 2, 1),
        ("a_b4", 4, 1, 4),
        ("a_halve", 8, 1, 2),
        ("a_up", 6, 4, 2),
        ("a_down", 6, 2, 4),
        ("a_300", 300, 8, 2),
        ("a_65k", 65534, 4, 8),
        ("a_reject4", 3, 1, 4),
        ("a_reject8", 5, 1, 8),
    ],
    # ---- B: THE `U32.mul` BOUNDARY, one step either side, per inp, with out = 8 so
    # L3 is slack. `dim*inp == 2**32 - inp` is the last exact product; `== 2**32` is
    # the first wrap, and it wraps to 0 -- a `raise` in the port where CPython has a
    # shape, so this band moves from a number to a refusal.
    "B": [
        ("b_i1_lo", (1 << 32) - 1, 1, 8),
        ("b_i1_at", 1 << 32, 1, 8),
        ("b_i2_lo", (1 << 31) - 1, 2, 8),
        ("b_i2_at", 1 << 31, 2, 8),
        ("b_i4_lo", (1 << 30) - 1, 4, 8),
        ("b_i4_at", 1 << 30, 4, 8),
        ("b_i8_lo", (1 << 29) - 1, 8, 4),
        ("b_i8_at", 1 << 29, 8, 4),
    ],
    # ---- C: THE `sint_of` BOUNDARY. `out == 1`, `dim*inp == 2**31`: the product is
    # EXACT (`2**31 < 2**32`) and the port is still WRONG, because the quotient's bit
    # 31 becomes a sign. These rows are wrong INSIDE the documented window.
    "C": [
        ("c_i2_lo", (1 << 30) - 1, 2, 1),
        ("c_i2_at", 1 << 30, 2, 1),
        ("c_i4_lo", (1 << 29) - 1, 4, 1),
        ("c_i4_at", 1 << 29, 4, 1),
        ("c_i8_lo", (1 << 28) - 1, 8, 1),
        ("c_i8_at", 1 << 28, 8, 1),
    ],
    # ---- D: THE `H.lo32` BOUNDARY. `dim >= 2**32`, so the dim itself is truncated and
    # the product stays in window. `out = 8` keeps `q < 2**31` so L3 is slack, which
    # leaves the lo32 drop as the ONLY thing wrong. The `+8`/`+64` rows answer a SMALL
    # POSITIVE number where CPython has the full dim -- the failure does not look like
    # a zero, so a "is the answer 0" check would miss every one of them.
    "D": [
        ("d_p32_at", 1 << 32, 1, 8),
        ("d_p32_p8", (1 << 32) + 8, 1, 8),
        ("d_p32_p64", (1 << 32) + 64, 1, 8),
        ("d_p32_i2", 1 << 32, 2, 8),
        ("d_p32_i4", 1 << 32, 4, 8),
        ("d_p33_i1", 1 << 33, 1, 8),
        ("d_p34_i2", 1 << 34, 2, 8),
        ("d_p40_i4", 1 << 40, 4, 8),
    ],
    # ---- E: L1 AND L3 TOGETHER, so the two truncations can be seen composing.
    "E": [
        ("e_p32_i1_o2", (1 << 32) + 2, 1, 2),
        ("e_p32_i2_o1", (1 << 32) + 1, 2, 1),
    ],
    # ---- F: `out == inp`, the `same` arm, which never reaches the arithmetic at all.
    "F": [
        ("f_same_i1", (1 << 33) + 4, 1, 1),
        ("f_same_i8", 1 << 40, 8, 8),
    ],
    # ---- G: THE FIX'S OWN WINDOW EDGE. `i64_mul` wraps mod 2**64 and `i64_divmod`
    # reads bit 63 of the dividend as a sign, so the fixed port is exact while
    # `dim*inp < 2**63` and NOT ONE BIT FURTHER. These rows are the post-fix residual
    # and they are pinned on BOTH sides rather than excluded.
    "G": [
        ("g_i8_lo", (1 << 60) - 1, 8, 4),
        ("g_i8_at", 1 << 60, 8, 4),
        ("g_i4_lo", (1 << 61) - 1, 4, 8),
        ("g_i4_at", 1 << 61, 4, 8),
    ],
}

ROWS = [(f"{b}_{n}", d, i, o) for b, rs in BANDS.items() for n, d, i, o in rs]
# the shape handed to `bitcast_dims`, and the one `Tensor.empty` builds. TWO AXES on
# purpose: `drop_last` keeps the `1`, so a row carries the preserved prefix AND the
# scaled last dim, and a drop that dropped the wrong axis would move every row.
def ps_of(dim):
    return (1, dim)


# ---------------------------------------------------------------- CPython
def cpython(dim, inp, out):
    """The real `tinygrad` BITCAST arm (ops.py:390-396), through `Tensor.bitcast`.

    A `RuntimeError` is the arm's OWN refusal -- `raise RuntimeError("unsupported size
    in bitcast")`, which every caller turns into the port's `None`, so `raise` and
    `None` are ONE answer -- and anything else is a tensor CPython would not build at
    all, which is a DIFFERENT thing and is reported as `unbuildable`.
    """
    import sys
    if "tinygrad" not in sys.modules:
        sys.path.insert(0, ".")
        from tinygrad import Tensor  # noqa: F401
    from tinygrad import Tensor
    try:
        sh = Tensor.empty(1, dim, dtype=f"int{inp * 8}").bitcast(dtype=f"int{out * 8}").shape
    except RuntimeError as e:
        assert "unsupported size in bitcast" in str(e), e
        return (True, str(e))
    except Exception as e:  # noqa: BLE001 - a refusal to build IS a measurement
        return ("unbuildable", f"{type(e).__name__}: {e}")
    assert len(sh) == 2, sh
    return (False, list(sh))


# ---------------------------------------------------------------- the PORT
def port_unfixed(dim, inp, out, ps=None):
    """`bitcast_dims.scale` / `.put` / `.put.of` EXACTLY, BEFORE the fix.

    `same` short-circuits; `lo32` is truncation 1; `U32.mul` is 2; and `sint_of` is
    `i64_of_i32`, whose `match_hi` turns bit 31 into a SIGN -- truncation 3, which the
    prior unit's model did not have because it used Python ints for the answer.
    """
    ps = ps if ps is not None else ps_of(dim)
    if out == inp:
        return (False, list(ps))                       # bitcast_dims.res, True arm
    lo = dim & M32                                     # H.lo32
    n = (lo * inp) & M32                               # U32.mul
    if n % out != 0:
        return (True, None)                            # some_if(..., False) -> None
    q = n // out
    q -= P32 if q >= P31 else 0                        # sint_of -> i64_of_i32
    return (False, list(ps[:-1]) + [q])


P32 = 1 << 32


def port_fixed(dim, inp, out, ps=None):
    """AFTER the fix: `i64_mul` / `i64_div` / `i64_mod`, and the quotient is `SI{q}`
    rather than `sint_of(q)`, so neither bit 63 nor bit 31 can turn into a sign.

    `i64_mul` WRAPS MOD 2**64 and `i64_divmod` READS BIT 63 AS A SIGN (helpers.bend's
    own "THE DIVIDER IS NOT WRONG" note), so the fixed window is `dim*inp < 2**63` --
    one bit SHORTER than the product's range, which is why band G exists. A model that
    used unsigned semantics here would report the last two rows of the census agreeing,
    and that is a mistake copied rather than a result.
    """
    ps = ps if ps is not None else ps_of(dim)
    if out == inp:
        return (False, list(ps))
    n = (dim * inp) % P64                              # i64_mul
    if n >= P63:
        n -= P64                                      # ... read as a SIGN
    if n % out != 0:                                   # i64_mod FLOORS
        return (True, None)
    q = n // out                                      # i64_div floors
    q -= P64 if q >= P63 else 0
    return (False, list(ps[:-1]) + [q])


# ---------------------------------------------------------------- rendering
def render(ans):
    """ONE string, and it is NEVER empty: `raise`, or the whole dim list."""
    if ans[0] == "unbuildable":
        return f"unbuildable:{ans[1]}"
    if ans[0]:
        return "raise"
    return "[" + ",".join(str(v) for v in ans[1]) + "]"


def same(a, b):
    return render(a) == render(b)


# ---------------------------------------------------------------- mode tag
def modes(dim, inp, out):
    lo = dim & M32
    n = (lo * inp) & M32
    m = []
    if lo != dim:
        m.append("L1")
    if lo * inp >= (1 << 32):
        m.append("L2")
    if n % out == 0 and (n // out) >= P31:
        m.append("L3")
    return "+".join(m) if m else "agree"


def census():
    out = []
    for name, dim, inp, out_ in ROWS:
        c, u, f = cpython(dim, inp, out_), port_unfixed(dim, inp, out_), port_fixed(dim, inp, out_)
        out.append((name, dim, inp, out_, modes(dim, inp, out_),
                    render(c), render(u), render(f),
                    "agree" if same(c, u) else "DIFFER", "agree" if same(c, f) else "DIFFER"))
    return out


if __name__ == "__main__":
    hdr = f"{'row':<14} {'dim':>21} {'in':>2} {'out':>3}  {'mode':<8} {'cpython':<24} " \
          f"{'unfixed':<24} {'fixed':<24} pre   post"
    print(hdr)
    pre_ok = pre_bad = post_bad = 0
    for r in census():
        name, dim, inp, out_, m, rc, ru, rf, pre, post = r
        pre_ok += pre == "agree"
        pre_bad += pre == "DIFFER"
        post_bad += post == "DIFFER"
        print(f"{name:<14} {dim:>21} {inp:>2} {out_:>3}  {m:<8} {rc:<24} {ru:<24} {rf:<24} "
              f"{pre:<6} {post}")
    print(f"\nrows={len(ROWS)}  PRE-fix agree={pre_ok} DIFFER={pre_bad}   "
          f"POST-fix DIFFER={post_bad}")
    print("\nPER BAND -- the bands are not all the same KIND:")
    for band in BANDS:
        rs = [r for r in census() if r[0].startswith(band + "_")]
        ag = sum(1 for r in rs if r[8] == "agree")
        mo = sorted({r[4] for r in rs})
        print(f"  {band}: pre-fix {ag} agree / {len(rs) - ag} DIFFER   modes={mo}")