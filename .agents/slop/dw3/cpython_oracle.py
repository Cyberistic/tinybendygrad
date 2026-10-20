# CPython's ANSWER, READ OFF THE VENDORED `tinygrad` IN THIS REPO.
#
# NOT A PORT FILE. THE ORACLE. TWO JOBS:
#
#   1. MEASURE THE GUARD EXPRESSION `w.shape[axis_w:=-min(w.ndim,2)]` -- IS IT A
#      SINGLE DIM OR A SLICE? THE ANSWER DECIDES WHAT THE PORT MUST SPELL.
#   2. ENUMERATE dw>=3 SHAPES AND SAY, FOR EACH, WHETHER CPYTHON ACCEPTS OR
#      REFUSES, AND BY WHICH OF ITS TWO REFUSALS.
#
# RUN: .venv/bin/python .agents/slop/dw3/cpython_oracle.py

import itertools

from tinygrad import Tensor


def guard_dim(ws):
    """CPython's guard expression, COPIED VERBATIM FROM tinygrad/mixin/op.py:389.

    `axis_w:=-min(len(ws),2)` IS TEXTUALLY IDENTICAL TO CPython's
    `axis_w:=-min(w.ndim,2)`; `len(ws)` IS `w.ndim` FOR A TUPLE.
    """
    return ws[axis_w:=-min(len(ws), 2)]


def broadcast_ok(a, b):
    """CPython's `_broadcast_shape` RULE, ALIGNED RIGHT, ONE OF THE PAIR IS 1."""
    n = max(len(a), len(b))
    pa = (1,) * (n - len(a)) + tuple(a)
    pb = (1,) * (n - len(b)) + tuple(b)
    return all(x == y or x == 1 or y == 1 for x, y in zip(pa, pb))


def reshape_targets(xs, ws):
    """CPython op.py:390-391, EVALUATED."""
    dx, dw = len(xs), len(ws)
    axis_w = -min(dw, 2)
    k = min(dx - 1, dw - 1, 1)
    xp = (*xs[0:-1], *([1] * k), xs[-1])
    wp = (*ws[0:-2], *([1] * k), *ws[axis_w:])
    return axis_w, k, xp, wp


def transposed(wp, axis_w):
    """`.transpose(-1, axis_w)` ON A SHAPE: SWAP THE LAST AXIS WITH `len+axis_w`."""
    out = list(wp)
    out[-1], out[len(wp) + axis_w] = out[len(wp) + axis_w], out[-1]
    return tuple(out)


def cpython(xs, ws):
    """WHAT CPYTHON DOES. RETURNS (verdict, detail)."""
    x, w = Tensor.empty(*xs), Tensor.empty(*ws)
    try:
        shape = x.dot(w).shape
        return "ACCEPT", shape
    except Exception as e:  # noqa: BLE001
        return "REFUSE", f"{type(e).__name__}: {e}"


def predicted(xs, ws):
    """THE RULE, PREDICTED FROM THE SOURCE TEXT ALONE (NO TENSOR)."""
    dx, dw = len(xs), len(ws)
    axis_w = -min(dw, 2)
    if xs[-1] != ws[axis_w]:
        return "REFUSE", "GUARD"
    _, _, xp, wp = reshape_targets(xs, ws)
    if not broadcast_ok(xp, transposed(wp, axis_w)):
        return "REFUSE", "BROADCAST"
    return "ACCEPT", ""


def main():
    print("=== 1. THE GUARD EXPRESSION: SINGLE DIM OR SLICE? ===")
    for ws in [(3,), (3, 4), (3, 4, 1), (3, 4, 5, 6)]:
        v = guard_dim(ws)
        print(f"  w.shape={ws}  w.shape[axis_w:=-min(dw,2)] = {v!r}  type={type(v).__name__}")
    print()

    print("=== 2. ENUMERATION: CPYTHON'S VERDICT vs THE RULE PREDICTED FROM SOURCE ===")
    print("  case  x.shape           w.shape        cpython                 predicted")
    bad = 0
    total = 0
    mech = {}
    for dw in (2, 3, 4):
        for dx in (1, 2, 3, 4):
            for xs in itertools.product((1, 2, 3), repeat=dx):
                for ws in itertools.product((1, 2, 3), repeat=dw):
                    total += 1
                    v, d = cpython(xs, ws)
                    pv, pd = predicted(xs, ws)
                    mech.setdefault((dw, v, pd), 0)
                    mech[(dw, v, pd)] += 1
                    if v != pv:
                        bad += 1
                        if bad <= 12:
                            print(f"  MISMATCH x={xs} w={ws} cpython={v}/{d} predicted={pv}/{pd}")
                    if dw == 3 and v == "ACCEPT":
                        print(f"  ACCEPTED x={xs} w={ws} -> {d}")
    print(f"  enumerated={total} rule-mismatches={bad}")
    for key in sorted(mech):
        print(f"  dw={key[0]} cpython={key[1]} predicted-mechanism={key[2]}: {mech[key]} cases")
    print()

    print("=== 3. THE NAMED CASES ===")
    for name, xs, ws in [
        # dw <= 2 -- THE REGRESSION SET. A/B/C ARE dw=2, D IS dw=1.
        ("A", (2, 3), (3, 4)),
        ("B", (2, 4, 3), (3, 4)),
        ("C", (8, 64, 7, 7), (7, 16)),
        ("D", (2, 3), (3,)),
        # dw == 2 AND CPYTHON REFUSES -- THE GUARD FIRES (3 != 4).
        ("P", (2, 3), (4, 5)),
        # dw == 3
        ("E", (2, 3, 4), (3, 4, 5)),   # REFUSE: BROADCAST
        ("F", (2, 3, 4), (3, 4, 1)),   # REFUSE: BROADCAST
        ("G", (3, 3, 4), (3, 4, 1)),   # ACCEPT
        ("H", (3, 3, 4), (3, 5, 1)),   # REFUSE: GUARD
        ("I", (3, 3, 4), (3, 4, 2)),   # ACCEPT
        # dw == 4
        ("M", (2, 2, 4), (3, 3, 4, 5)),  # REFUSE: BROADCAST
        ("N", (2, 4), (3, 3, 4, 5)),     # ACCEPT
        ("O", (2, 4), (3, 3, 5, 5)),     # REFUSE: GUARD
    ]:
        v, d = cpython(xs, ws)
        pv, pd = predicted(xs, ws)
        axis_w, k, xp, wp = reshape_targets(xs, ws)
        print(f"  {name}: x={xs} w={ws}")
        print(f"     axis_w={axis_w} k={k} guard w.shape[axis_w]={ws[axis_w]} x.shape[-1]={xs[-1]}")
        print(f"     x'={xp}  w'={wp} -> transposed {transposed(wp, axis_w)}")
        print(f"     CPYTHON: {v} {d}    PREDICTED: {pv} {pd}")


if __name__ == "__main__":
    main()
