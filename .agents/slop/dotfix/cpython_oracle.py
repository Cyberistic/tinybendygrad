# CPython's ANSWER, READ OFF THE VENDORED `tinygrad` IN THIS REPO.
#
# NOT A PORT FILE. THE ORACLE. IT PRINTS, FOR EACH CASE:
#   * `x.shape[0:-1]`, `w.shape[0:-2]`, `w.shape[axis_w:]`, `k` -- THE FOUR
#     TERMS OF op.py:390-391, AS PYTHON EVALUATES THEM;
#   * THE RESHAPE TARGETS `x'` AND `w'`;
#   * THE RESULT SHAPE OF `x.dot(w)`.
#
# THE `axis_w` SUBTLETY, WHICH IS THE POINT OF LINE 389. THE SOURCE IS
#
#     if x.shape[-1] != w.shape[axis_w:=-min(w.ndim,2)]: raise RuntimeError
#
# PYTHON'S SLICE GRAMMAR MAKES `axis_w:=-min(w.ndim,2)` A NAMED EXPRESSION
# (`axis_w := -min(w.ndim,2)`) AND THE SLICE'S LOWER BOUND, WITH NO UPPER
# BOUND -- SO THE GUARD READS `w.shape[axis_w]`, A SINGLE DIM, NOT
# `w.shape[axis_w:]`. LINE 391 IS A DIFFERENT EXPRESSION: `axis_w` IS A PLAIN
# NAME THERE, SO `w.shape[axis_w:]` IS A SLICE AND ANSWERS THE LAST
# `min(w.ndim,2)` DIMS. THE TWO ARE NOT THE SAME SHAPE, AND THE PORT MUST
# SPELL BOTH.
#
# RUN: .venv/bin/python .agents/slop/dotfix/cpython_oracle.py

from tinygrad import Tensor

CASES = [
    # (name, x.shape, w.shape)
    ("A", (2, 3), (3, 4)),
    ("B", (2, 4, 3), (3, 4)),
    ("C", (8, 64, 7, 7), (7, 16)),
    ("D", (2, 3), (3,)),
    ("E", (2, 3, 4), (3, 4, 5)),
    ("F", (2, 3, 4), (3, 4, 1)),
    # THE ONE dw==3 CASE CPYTHON DOES NOT REFUSE: x(3,3,4) . w(3,4,1) BROADCASTS
    # (x'=(3,3,1,4), w'=(3,1,4,1) -> (3,1,1,4)) AND ANSWERS (3,3,1). IT IS HERE
    # SO THE PORT'S dw>=3 DIVERGENCE HAS A WELL-FORMED CPYTHON ANSWER TO BE
    # COMPARED AGAIN, NOT ONLY AN IndexError.
    ("G", (3, 3, 4), (3, 4, 1)),
]


def reshape_targets(xs, ws):
    dx, dw = len(xs), len(ws)
    axis_w = -min(dw, 2)
    k = min(dx - 1, dw - 1, 1)
    xp = (*xs[0:-1], *([1] * k), xs[-1])
    wp = (*ws[0:-2], *([1] * k), *ws[axis_w:])
    return axis_w, k, xp, wp


def main():
    for name, xs, ws in CASES:
        x = Tensor.empty(*xs)
        w = Tensor.empty(*ws)
        axis_w, k, xp, wp = reshape_targets(xs, ws)
        dx, dw = len(xs), len(ws)
        guard_dim = ws[axis_w]  # THE GUARD IS `w.shape[axis_w]`, A SINGLE DIM
        print(f"{name}")
        print(f"  x.shape          = {xs}")
        print(f"  w.shape          = {ws}")
        print(f"  dx,dw            = {dx},{dw}")
        print(f"  k=min(dx-1,dw-1,1) = {k}")
        print(f"  axis_w=-min(dw,2) = {axis_w}")
        print(f"  guard w.shape[axis_w] = {guard_dim}  (x.shape[-1] = {xs[-1]})")
        print(f"  x.shape[0:-1]    = {xs[0:-1]}")
        print(f"  w.shape[0:-2]    = {ws[0:-2]}")
        print(f"  w.shape[axis_w:] = {ws[axis_w:]}")
        print(f"  x' target        = {xp}")
        print(f"  w' target        = {wp}  (before transpose)")
        try:
            print(f"  x.dot(w).shape   = {x.dot(w).shape}")
        except Exception as e:  # noqa: BLE001
            print(f"  x.dot(w) RAISED  = {type(e).__name__}: {e}")
        print()


if __name__ == "__main__":
    main()
