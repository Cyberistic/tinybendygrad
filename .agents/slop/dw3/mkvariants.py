#!/usr/bin/env python3
"""BUILD THE FOUR ABLATION VARIANTS OF THE PORT FROM THE TREE'S OWN FILE.

THE PATCH IS NOT HAND-TYPED HERE AND NEITHER IS A VARIANT: EVERY VARIANT IS
THE TREE'S `tinybendygrad/nn/layers.bend` WITH A NAMED SUBSET OF THE FIXES
APPLIED, IN A NAMED ORDER. FOUR VARIANTS, AND EACH ONE IS ONE STEP FURTHER:

    scratchg    S1 = GUARD ONLY            (the :389 refusal, ported)
    scratchgw   S2 = S1 + WSHAPE           (the `ws[axis_w:]` term + the tail drop)
    scratchgwo  S3 = S2 + ORDER            (the transpose axis)
    scratchfix  S4 = S3 + BROADCAST + HEADER   (the whole patch)

SO EACH FIX IS PROVED SEPARATELY: S1 IS THE PATCH WITHOUT THE OTHER TWO, AND
THE PORT'S ANSWER FOR EVERY CASE IS READ OFF EVERY VARIANT.

THE SCRIPT ASSERTS THAT S4 IS BYTE-IDENTICAL TO THE HAND-EDITED
`scratchfix/nn/layers.bend`, SO THE DIFF I DELIVER AND THE VARIANTS I MEASURE
CANNOT DRIFT APART.

RUN: .venv/bin/python .agents/slop/dw3/mkvariants.py
"""

import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SRC = os.path.join(ROOT, "tinybendygrad")
REL = "nn/layers.bend"

HEADER_OLD = """# ===========================================================================
# `dot` -- mixin/op.py:367-392, THE BODY LINE BY LINE.
#
#   x, dx, dw = self, self.ndim, w.ndim                                        # :384
#   if not (dx > 0 and dw > 0): raise RuntimeError(...)                       # :385
#   if x.shape[-1] != w.shape[axis_w:...]: raise RuntimeError(...)             # :386
#   x = x.reshape(*x.shape[0:-1], *[1]*min(dx-1, dw-1, 1), x.shape[-1])        # :387
#   w = w.reshape(*w.shape[0:-2], *[1]*min(dx-1, dw-1, 1), *w.shape[axis_w:]).transpose(-1, axis_w)  # :388
#   return (x*w).sum(-1, dtype=dtype).cast(least_upper_dtype(x.dtype, w.dtype))  # :390
#
# AND THE TWO RAISES AT :385-386 ARE PORTED AS A `Maybe`, not skipped: a def
# whose answer for a 0-D operand is a well-formed graph is a def that builds the
# wrong graph silently, which is the failure mode this file is written against.
#
# `axis_w = -w.ndim if w.ndim > 1 else 0` (:383), so on the RESHAPED `w` of
# length `len` the axis `axis_w` IS `len - dw`, and `-1` IS `len - 1`. That is
# the pair `nn_dot.order` exchanges, and it is why :388 needs no negative index
# anywhere.
# ==========================================================================="""

HEADER_NEW = """# ===========================================================================
# `dot` -- mixin/op.py:367-392 (THE VENDORED `002630241`), THE BODY LINE BY LINE.
#
#   x, dx, dw = self, self.ndim, w.ndim                                         # :387
#   if not (dx > 0 and dw > 0): raise RuntimeError(...)                        # :388
#   if x.shape[-1] != w.shape[axis_w:=-min(w.ndim,2)]: raise RuntimeError(...)   # :389
#   x = x.reshape(*x.shape[0:-1], *[1]*min(dx-1, dw-1, 1), x.shape[-1])         # :390
#   w = w.reshape(*w.shape[0:-2], *[1]*min(dx-1, dw-1, 1), *w.shape[axis_w:]).transpose(-1, axis_w)  # :391
#   return (x*w).sum(-1, dtype=dtype).cast(least_upper_dtype(x.dtype, w.dtype))  # :392
#
# AND THE TWO RAISES AT :388-389 ARE PORTED AS A `Maybe`, not skipped: a def
# whose answer for a 0-D operand is a well-formed graph is a def that builds the
# wrong graph silently, which is the failure mode this file is written against.
#
# `axis_w = -min(w.ndim, 2)` (:389) -- NOT THE `-w.ndim` AN EARLIER REVISION OF
# THIS BLOCK CLAIMED. THE TWO SPELLINGS ARE NOT THE SAME EXPRESSION:
#
#   * :389 IS `w.shape[axis_w:=-min(w.ndim,2)]`, AND PYTHON'S GRAMMAR MAKES THE
#     WALRUS THE SUBSCRIPT'S ONLY INDEX -- THERE IS NO SECOND `:` -- SO THE
#     GUARD READS `w.shape[axis_w]`, A SINGLE DIM. MEASURED, `.venv/bin/python`:
#     IT ANSWERS `3` FOR `w.shape=(3,4)`, NOT `(3,4)`.
#   * :391 IS `w.shape[axis_w:]` WITH `axis_w` A PLAIN NAME, SO IT IS A SLICE
#     AND ANSWERS THE LAST `min(dw,2)` DIMS.
#
# SO ON THE RESHAPED `w` OF LENGTH `len` THE AXIS `axis_w` IS `len - min(dw,2)`
# AND `-1` IS `len - 1`. THAT IS THE PAIR `nn_dot.order` EXCHANGES, AND IT IS
# WHY :391 NEEDS NO NEGATIVE INDEX ANYWHERE.
# ==========================================================================="""

WSHAPE_OLD = """# `w.shape[0:-2]` ++ `[1]*k` ++ `w.shape[axis_w:]` -- :388. The last term IS
# `w.shape` on BOTH arms of :383 (`-w.ndim` on a `w.ndim`-length list is index
# 0, and the `else 0` arm is index 0 too), so this is `drop 2` ++ `ones k` ++
# the whole list, and `List.drop` answers `Nil{}` when `dw < 2` -- which is what
# makes the `dw == 1` arm correct without a `Bool`. The duplication of the
# batch dims for `dw >= 3` is CPython's, not a typo here: `w.shape[0:-2]` and
# `w.shape[axis_w:]` really are two different slices of the same list.
def nn_dot.wshape(+ws: List<&2, U32>, k: U32) -> List<&2, U32>:
  List.concat(&2, U32, [List.drop(&2, U32, ws, 2n), H.make_tuple_rep(1, k), ws])"""

WSHAPE_NEW = """# `axis_w = -min(dw,2)` (header), SO `w.shape[axis_w:]` IS THE LAST
# `min(dw,2)` DIMS -- `(w0,)` FOR dw==1, `(w0,w1)` FOR dw==2, `(w1,w2)` FOR
# dw==3 -- AND `w.shape[0:-2]` IS EVERY DIM BUT THE LAST TWO -- `()` FOR
# dw<=2 AND `(w0,)` FOR dw==3.
#
# SO THE TARGET IS `DROP_LAST 2` ++ `ONES k` ++ `DROP_FIRST (dw-min(dw,2))`, AND
# `Nat.sub` SATURATES AT 0 (base.bend:657) SO `dw-min(dw,2)` IS 0 FOR dw==1
# AND dw==2 -- WHICH IS EXACTLY CPython's `w.shape[axis_w:]` THERE. THE HEAD
# DROP `List.drop(ws, 2n)` THIS USED TO SPELL ANSWERED `ws[2:]`, WHICH IS
# `(w2,)` FOR dw==3 WHERE CPython'S FIRST SLICE ANSWERS `(w0,)`.
def nn_dot.wshape(+ws: List<&2, U32>, k: U32) -> List<&2, U32>:
  +dw = List.length(&2, U32, ws)
  List.concat(&2, U32, [nn_tail_drop(ws, 2n), H.make_tuple_rep(1, k),
    List.drop(&2, U32, ws, Nat.sub(dw, Nat.min(dw, 2n)))])"""

ORDER_OLD = """# `.transpose(-1, axis_w)` -- :388, as the IDENTITY ORDER with positions `a` and
# `b` exchanged (header). `dw == 1` makes `a == b == 0`, so the order IS the
# identity and `M.mo_permute`'s own identity test hands `w` back unchanged --
# which is exactly what CPython's `transpose(-1, 0)` on a 1-D tensor does.
# `dw == 1` makes `a == b == 0`, so the order IS the identity and
# `M.mo_permute`'s own identity test hands `w` back unchanged -- which is exactly
# what CPython's `transpose(-1, 0)` on a 1-D tensor does.
def nn_dot.order(+len: U32, +dw: U32) -> List<&2, U32>:
  +ids = nn_range(len)
  List.set(&2, U32, List.set(&2, U32, ids, U32.to_nat(U32.sub(len, dw)), U32.sub(len, 1)),
    U32.to_nat(U32.sub(len, 1)), U32.sub(len, dw))"""

ORDER_NEW = """def nn_umin(a: U32, b: U32) -> U32: U32.min(a, b)

# `.transpose(-1, axis_w)` -- :391, AS THE IDENTITY ORDER WITH TWO POSITIONS
# EXCHANGED. `axis_w = -min(dw,2)` (header), SO ON THE RESHAPED `w` OF LENGTH
# `len` THE AXIS IS `len - min(dw,2)` AND `-1` IS `len - 1`: THOSE ARE THE TWO
# POSITIONS EXCHANGED. FOR dw==1 THEY COINCIDE (BOTH 0), SO THE ORDER IS THE
# IDENTITY AND `M.mo_permute`'s OWN IDENTITY TEST HANDS `w` BACK UNCHANGED --
# WHICH IS EXACTLY WHAT CPython'S `transpose(-1, -1)` ON A 1-D TENSOR DOES.
def nn_dot.order(+len: U32, +dw: U32) -> List<&2, U32>:
  +ids = nn_range(len)
  +b = U32.sub(len, nn_umin(dw, 2))
  List.set(&2, U32, List.set(&2, U32, ids, U32.to_nat(b), U32.sub(len, 1)),
    U32.to_nat(U32.sub(len, 1)), b)"""

GUARD_OLD = """# `dx > 0 and dw > 0` (:385). A `Bool` and not a `Maybe`, because it selects
# between two answers that both exist.
def nn_dot.rd(+ax: List<&2, U32>, +bw: List<&2, U32>) -> Bool:
  Bool.and(U32.is_gt(nn_len32(ax), 0), U32.is_gt(nn_len32(bw), 0))"""

GUARD_NEW = """# A MISSING DIM IS A REFUSAL, NOT A DEFAULT VALUE: THE WHOLE GUARD IS `False`.
def nn_dot.guard.ans(m: Maybe<&2, Bool>) -> Bool:
  match m:
    case Some{b}: b
    case None{}: False{}

# `x.shape[-1] != w.shape[axis_w]` (:389) -- THE SECOND REFUSAL, AND THE ONE
# THAT WAS NEVER PORTED. `axis_w = -min(dw,2)` (header), SO `w.shape[axis_w]`
# IS `w.shape[-1]` FOR dw==1 AND `w.shape[-2]` FOR dw>=2: THE INDEX IS
# `dw - min(dw,2)` INTO `w.shape`. A MISSING DIM IS A REFUSAL, NOT A DEFAULT
# VALUE: THE WHOLE GUARD IS `False`.
def nn_dot.guard(+ax: List<&2, U32>, +bw: List<&2, U32>) -> Bool:
  +dw = List.length(&2, U32, bw)
  nn_dot.guard.ans(
    Maybe.bind(&2, U32, Bool, List.last(&2, U32, ax),
      xl => Maybe.map(&2, U32, Bool, wl => U32.is_eq(xl, wl),
        List.get(&2, U32, bw, Nat.sub(dw, Nat.min(dw, 2n))))))

# `dx > 0 and dw > 0` (:388) AND `x.shape[-1] != w.shape[axis_w]` (:389) --
# BOTH REFUSALS, AND A `Bool` AND NOT A `Maybe`, BECAUSE IT SELECTS BETWEEN
# TWO ANSWERS THAT BOTH EXIST. CPython RAISES ON THE FIRST, SO THE ORDER IS
# CPython's: THE RANK GUARD FIRST.
def nn_dot.rd(+ax: List<&2, U32>, +bw: List<&2, U32>) -> Bool:
  Bool.and(U32.is_gt(nn_len32(ax), 0), Bool.and(U32.is_gt(nn_len32(bw), 0), nn_dot.guard(ax, bw)))"""

BROADCAST_OLD = """# `(x*w).sum(-1).cast(dt)` -- :390, the whole tail as one def because it is one
# expression. `M.mo_sum(False{}, ...)` IS `mixin/reduce.py:20` hoisted
# (mixin/op.bend:811), downcast-and-cast-back included.
def nn_dot.tail(+xr: T.Tensor, +wr: T.Tensor, ax: U32, dt: S.Dt) -> T.Tensor:
  M.mo_cast_t(nn_sum(False{}, T.tn_mul(xr, wr), [ax]), dt)"""

BROADCAST_NEW = """# `(x*w).sum(-1).cast(dt)` -- :392. `M.mo_sum(False{}, ...)` IS
# `mixin/reduce.py:20` hoisted (mixin/op.bend:811), downcast-and-cast-back
# included. IT TAKES THE PRODUCT, NOT THE TWO OPERANDS, BECAUSE THE PRODUCT
# IS WHERE THE SECOND REFUSAL LIVES.
def nn_dot.tail(+xw: T.Tensor, ax: U32, dt: S.Dt) -> T.Tensor:
  M.mo_cast_t(nn_sum(False{}, xw, [ax]), dt)

# CPython's SECOND REFUSAL IS AT `(x*w)`: `_broadcast_shape` (ops.py:80) RAISES
# `IndexError` WHEN THE TWO RESHAPED SHAPES DO NOT BROADCAST. THE PORT'S FOLD
# REFUSES THE SAME WAY -- `F.bcast_shape` (fold.bend:672) ANSWERS `None` -- AND
# THE PRODUCT IS WHERE THAT REFUSAL SHOWS. THE PRODUCT IS NEVER 0-D (BOTH
# OPERANDS HAVE AT LEAST ONE DIM), SO AN EMPTY SHAPE IS THE REFUSAL AND NOT A
# ZERO-RANK TENSOR: THE RESULT OF A 1-D `dot` A 1-D IS 0-D, AND THE PRODUCT IS
# NOT.
def nn_dot.mul(+xr: T.Tensor, +wr: T.Tensor, ax: U32, dt: S.Dt) -> Maybe<&2, T.Tensor>:
  +xw = T.tn_mul(xr, wr)
  Maybe.bind(&2, List<&2, U32>, T.Tensor, nn_shape(xw),
    s => Bool.pick(Maybe<&2, T.Tensor>, List.is_empty(&2, U32, s), None{}, Some{nn_dot.tail(xw, ax, dt)}))"""

PAIR_OLD = """def nn_dot.pair(+x: T.Tensor, +w: T.Tensor, +ax: List<&2, U32>, +bw: List<&2, U32>, dt: S.Dt) -> T.Tensor:
  +k = nn_dotk(nn_len32(ax), nn_len32(bw))
  +xs = nn_dot.xshape(ax, k)
  +ws = nn_dot.wshape(bw, k)
  +wr0 = M.mo_reshape(w, nn_ks(ws))
  nn_dot.tail(M.mo_reshape(x, nn_ks(xs)),
    M.mo_permute(wr0, nn_dot.order(nn_len32(ws), nn_len32(bw))), nn_last_ax(nn_umax(nn_len32(xs), nn_len32(ws))), dt)"""

PAIR_NEW = """def nn_dot.pair(+x: T.Tensor, +w: T.Tensor, +ax: List<&2, U32>, +bw: List<&2, U32>, dt: S.Dt) -> Maybe<&2, T.Tensor>:
  +k = nn_dotk(nn_len32(ax), nn_len32(bw))
  +xs = nn_dot.xshape(ax, k)
  +ws = nn_dot.wshape(bw, k)
  +wr0 = M.mo_reshape(w, nn_ks(ws))
  nn_dot.mul(M.mo_reshape(x, nn_ks(xs)),
    M.mo_permute(wr0, nn_dot.order(nn_len32(ws), nn_len32(bw))), nn_last_ax(nn_umax(nn_len32(xs), nn_len32(ws))), dt)"""

BODY_OLD = """def nn_dot.body(dt: Maybe<&2, S.Dt>, +x: T.Tensor, +w: T.Tensor, ax: List<&2, U32>, bw: List<&2, U32>) -> Maybe<&2, T.Tensor>:
  match dt:
    case Some{d}: Some{nn_dot.pair(x, w, ax, bw, d)}
    case None{}: None{}"""

BODY_NEW = """def nn_dot.body(dt: Maybe<&2, S.Dt>, +x: T.Tensor, +w: T.Tensor, ax: List<&2, U32>, bw: List<&2, U32>) -> Maybe<&2, T.Tensor>:
  match dt:
    case Some{d}: nn_dot.pair(x, w, ax, bw, d)
    case None{}: None{}"""

ENTRY_OLD = """# `nn_dot` -- the `dot` ENTRY, refusals first. `Maybe` is the port's spelling
# of `raise RuntimeError` for the two guards at :385-386 and for the `SU` shape
# arm, and all three are the SAME `None`: CPython raises for two of them and the
# fold refuses the third."""

ENTRY_NEW = """# `nn_dot` -- the `dot` ENTRY, refusals first. `Maybe` is the port's spelling
# of `raise RuntimeError` for the two guards at :388-389 and for the `SU` shape
# arm, and all three are the SAME `None`: CPython raises for two of them and the
# fold refuses the third."""

SUM_OLD = """# `sum(-1)` -- :390. PYTHON'S `-1` HAS NO `U32` IMAGE, and the port's own"""

SUM_NEW = """# `sum(-1)` -- :392. PYTHON'S `-1` HAS NO `U32` IMAGE, and the port's own"""

PAIRDOC_OLD = """# `x.reshape(...)` and `w.reshape(...).transpose(-1, axis_w)` -- :387-388. The"""

PAIRDOC_NEW = """# `x.reshape(...)` and `w.reshape(...).transpose(-1, axis_w)` -- :390-391. The"""

FIXES = {
    "GUARD": [(GUARD_OLD, GUARD_NEW)],
    "WSHAPE": [(WSHAPE_OLD, WSHAPE_NEW)],
    "ORDER": [(ORDER_OLD, ORDER_NEW)],
    "BROADCAST": [(BROADCAST_OLD, BROADCAST_NEW), (PAIR_OLD, PAIR_NEW), (BODY_OLD, BODY_NEW)],
    "HEADER": [(HEADER_OLD, HEADER_NEW), (ENTRY_OLD, ENTRY_NEW), (SUM_OLD, SUM_NEW), (PAIRDOC_OLD, PAIRDOC_NEW)],
}

VARIANTS = [
    ("scratchg", ["GUARD"]),
    ("scratchgw", ["GUARD", "WSHAPE"]),
    ("scratchgwo", ["GUARD", "WSHAPE", "ORDER"]),
    ("scratchfix", ["GUARD", "WSHAPE", "ORDER", "BROADCAST", "HEADER"]),
]


def apply(text, fixes):
    for name in fixes:
        for old, new in FIXES[name]:
            n = text.count(old)
            if n != 1:
                raise SystemExit(f"THE {name} REPLACEMENT MATCHED {n} TIMES, NOT 1:\n{old[:120]}")
            text = text.replace(old, new)
    return text


def main():
    with open(os.path.join(SRC, REL), encoding="utf-8") as fh:
        orig = fh.read()
    for name, fixes in VARIANTS:
        out = os.path.join(HERE, name)
        if os.path.isdir(out):
            shutil.rmtree(out)
        shutil.copytree(SRC, out)
        with open(os.path.join(out, REL), "w", encoding="utf-8") as fh:
            fh.write(apply(orig, fixes))
        print(f"{name}: {len(fixes)} fix(es) -> {', '.join(fixes)}")
    hand = os.path.join(HERE, "scratchfix.hand.bend")
    with open(hand, encoding="utf-8") as fh:
        hand_text = fh.read()
    made = apply(orig, ["GUARD", "WSHAPE", "ORDER", "BROADCAST", "HEADER"])
    if hand_text != made:
        raise SystemExit("THE HAND-EDITED scratchfix.hand.bend IS NOT THE SCRIPT'S S4")
    print("scratchfix MATCHES THE SCRIPT'S S4, BYTE FOR BYTE")


if __name__ == "__main__":
    main()
