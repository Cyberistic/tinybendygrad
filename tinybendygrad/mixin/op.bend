# STUB — mixin/op.bend. Port of tinygrad/mixin/op.py, split at line 990.
# Side A (this agent): tinygrad/mixin/op.py lines 1-990.
# Side B (sibling):     tinygrad/mixin/op.py lines 991-end.

# ===========================================================================
# SIDE B. `tinygrad/mixin/op.py` lines 991-1980. Written by the Side-B agent;
# Side A owns lines 1-990 and nothing below this banner is Side A's to edit.
#
# THE BOUNDARY IS SIDE A'S STUB, kept verbatim above: the nominal split is line
# 991, so the first def STRICTLY AFTER the nominal split that starts whole is
# `allclose` at op.py:998. `topk` (976-996) STRADDLES the nominal line -- it
# starts at 976, inside Side A -- so it is Side A's and Side B starts at 998.
# Every def below names its own `op.py` line, so the boundary is checkable
# without reading this banner.
#
# WHAT THIS HALF ACTUALLY CONTAINS, because it is not what the unit brief
# guessed. Side A's half has the op-building surface. THIS half has NO
# `PatternMatcher`, NO `UPat`, NO `Ops.` dispatch and NO `st`/`store`/`CALL`
# surface: `rg -n 'UPat|PatternMatcher|graph_rewrite|Ops\.' op.py` over lines
# 991-1980 returns nothing. Every def in it is a Tensor method whose body is a
# composition of OTHER Tensor methods (`gather`, `where`, `pad`, `sum`,
# `permute`, `reshape`), and none of those callees exist in `tinybendygrad/`
# yet -- there is no `mixin/elementwise.bend` and no `mixin/movement.bend`.
#
# SO THE PORT IS THE ARITHMETIC, and that is not a consolation prize: it is the
# part of this half that is decidable without a Tensor, it is the part a gate
# can check against CPython, and it is where the actual algorithm lives. Each
# def below is the INTEGER/SHAPE content of its Python method, with the Tensor
# composition named as a `TODO(p3)` wall rather than faked. `p3` is the phase
# that builds the Tensor method surface; nothing here guesses at it.
#
# PREFIX. Every def here is `oq_` (op mixin, Side B). Side A should not use it;
# the coordinator may want to unify the two prefixes when the halves merge.
# ===========================================================================

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S

# ===========================================================================
# THE SUBSTRATE, hoisted once so the defs below read like the Python.
#
# `pick` is `c if b else d` and `slt_i32`/`smax_i32` are the signed readings.
# Bend has no signed integer: helpers.bend carries an `i32` as a U32 two's
# complement bit pattern (`i32_is_neg`, `i32_neg`, `ceildiv_i32`,
# `floordiv_i32`) but exports no signed COMPARISON, and `smax` (ops.py:74) is
# `max` on exactly that signed reading. So the compare is here, next to the one
# arithmetic that needs it.
# ===========================================================================
def oq_pick(c: Bool, t: U32, f: U32) -> U32:
  match c:
    case True{}: t
    case False{}: f

# `a < b` on the two's complement reading: the two signs decide it outright, and
# only a same-sign pair can be compared as U32 -- and for a SAME-SIGN pair the
# unsigned comparison IS the signed one, in both directions. That is the whole
# point of two's complement: -5 is 4294967291 and -3 is 4294967293, so the more
# negative value has the SMALLER bit pattern, which is the same ordering.
# The first version of this arm said `U32.is_gt`, on the theory that unsigned
# order is reversed for negatives. It is not, and the gate caught it: row
# `smax_neg_neg` expects `smax(-3,-5) = -3 = 4294967293` (CPython) and read
# 4294967291 = -5. See the mutation table's M6, which is the arm I wrote and
# the mutation that turned out to be the FIX.
def oq_slt_i32.of(na: Bool, nb: Bool, a: U32, b: U32) -> Bool:
  match na nb:
    case True{} True{}: U32.is_lt(a, b)
    case True{} False{}: True{}
    case False{} True{}: False{}
    case False{} False{}: U32.is_lt(a, b)

def oq_slt_i32(+a: U32, +b: U32) -> Bool:
  oq_slt_i32.of(H.i32_is_neg(a), H.i32_is_neg(b), a, b)

# `smax(a, b)` -- ops.py:74 on Python ints.
def oq_smax_i32(+a: U32, +b: U32) -> U32:
  oq_pick(oq_slt_i32(a, b), b, a)

# `S.dim_of` answers a symbolic dim as 0 until the fold has resolved it
# (spec.bend:308), and a pool/conv shape is read as a U32 here.
def oq_szs(ds: List<&2, S.Sdim>) -> List<&2, U32>:
  match ds:
    case Nil{}: Nil{}
    case d <> r: U32.from_nat(S.dim_of(d)) <> oq_szs(r)

# `d * (k - 1) + 1`, the span a dilated kernel covers. op.py uses this term
# verbatim in `_apply_ceil_mode` (1275, 1281), `_pool` (movement.py:604) and
# `max_unpool2d` (1387), so it is written once.
def oq_span(k: U32, d: U32) -> U32:
  (U32.add(U32.mul(d, U32.sub(k, 1)), 1) : U32)

# `make_tuple(x, cnt)` -- helpers.py:50, `(x,)*cnt` when x is an int else
# `tuple(x)`. The `Bool` is `x is not an int`, so the two arms are the two
# branches and `H.make_tuple_rep` is the repeat arm already in helpers.bend.
def oq_make_tuple.of(isdims: Bool, x: U32, xs: List<&2, U32>, n: U32) -> List<&2, U32>:
  match isdims:
    case True{}: xs
    case False{}: H.make_tuple_rep(x, n)

# The two elements of one `flat_to_grouped` pair, read as `pB` and `pA`. The
# pair always has two elements by construction (`fg_pairs` conses `[h, g]`), so
# the absent arms are unreachable and answer 0 rather than failing a total def.
def oq_pB(g: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, g, 0n), 0)

def oq_pA(g: List<&2, U32>) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, g, 1n), 0)

# ===========================================================================
# REPORTED DEFECT IN A SHARED FILE. `H.flat_to_grouped` IS WRONG, and this
# file does not use it. helpers.bend is READ-ONLY to this port, so the defect
# is reported and worked around, not fixed.
#
# helpers.bend:868 reads
#
#     List.reverse(&2, List<&2, U32>, fg_pairs(fg_skip(List.length(&2, U32, padding), padding)))
#
# `fg_skip(n, xs)` DROPS n elements, so it drops the WHOLE list and `fg_pairs`
# then sees `Nil` and returns `Nil`. MEASURED, row `diag_fg_shared`: it returns
# length 0 for `[1,2,3,4]`, and CPython's `flat_to_grouped([1,2,3,4])` is
# `[(3,4),(1,2)]` -- four elements, not zero.
#
# THE ONE-WORD FIX is `fg_skip(Nat.mod(List.length(&2, U32, padding), 2n), padding)`
# -- the skip is `n mod 2`, not `n`, which is what helpers.bend's own comment
# two lines above says ("the consecutive pairs starting at index (n mod 2)").
# The comment is right and the code contradicts it.
#
# CHECKED AGAINST CPython over `[0,0] [1,2,3,4] [1,2,3] [1,2] [1] [1,2,3,4,5,6]`
# -- the six shapes that decide the parity and the odd-length drop. All six
# agree with `oq_flat_to_grouped` below and none of them is a case where the two
# readings coincide, which is what makes this a real difference and not a style
# note.
#
# WHEN IT IS FIXED, `oq_fg_skip`/`oq_fg_pairs`/`oq_flat_to_grouped` are deleted
# and every `oq_flat_to_grouped` call becomes `H.flat_to_grouped`. NOTHING ELSE
# CHANGES: the grouping is a leaf both ways, and the `diag_fg_*` rows are what
# would catch a regression in the replacement.
# ===========================================================================
def oq_fg_skip(n: Nat, xs: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: xs
    case Succ{p}:
      match xs:
        case Nil{}: Nil{}
        case _ <> t: oq_fg_skip(p, t)

def oq_fg_pairs(p: List<&2, U32>) -> List<&2, List<&2, U32>>:
  match p:
    case h <> t:
      match t:
        case g <> r: [h, g] <> oq_fg_pairs(r)
        case Nil{}: Nil{}
    case Nil{}: Nil{}

# `(padding_left, padding_right, padding_top, padding_bottom, ...)` ->
# `(..., (padding_top, padding_bottom), (padding_left, padding_right))`.
# helpers.py:57, `tuple(zip(padding[-2::-2], padding[::-2]))`.
def oq_flat_to_grouped(+padding: List<&2, U32>) -> List<&2, List<&2, U32>>:
  +n = List.length(&2, U32, padding)
  List.reverse(&2, List<&2, U32>,
    oq_fg_pairs(oq_fg_skip(Nat.mod(n, 2n), padding)))

# ===========================================================================
# `_apply_ceil_mode` -- op.py:1271-1282. The first method in Side B's half and
# the only one whose body is ENTIRELY integer arithmetic, so it is ported whole.
#
#     (d_,s_), i_ = (make_tuple(x, len(k_)) for x in (d_,s_)), self.shape[-len(k_):]
#     grouped_pads = list(flat_to_grouped(pads))
#     # https://arxiv.org/pdf/1603.07285 section 5.1, relationship 15.
#     o_ = [ceildiv(i+pB+pA - (d*(k-1)+1), s) + 1 for i,d,k,s,(pB,pA) in zip(i_,d_,k_,s_,grouped_pads)]
#     for dim,(o,i,s,k,d,(pB,pA)) in enumerate(zip(o_,i_,s_,k_,d_,grouped_pads)):
#       grouped_pads[dim] = (pB, pA + s*(o-1) + (d*(k-1)+1) - (i+pB+pA) - smax(s*(o-1) - (pB+i-1), 0))
#     return flatten(reversed(grouped_pads))
#
# TWO PASSES, NOT ONE, and that is Python's structure and it is kept. Pass one
# computes the WHOLE of `o_`; pass two reads `o_[dim]` back. Fusing them is
# arithmetically identical -- `o_[dim]` is only ever read at `dim` -- but it
# would delete the intermediate list, and `o_` is a real output a gate can
# check, so the port keeps it and the gate pins both.
#
# PADS ARE SIGNED. op.py:1595 says so out loud ("padding, possibly negative"),
# `pA + s*(o-1) + ...` is routinely negative, and `ceildiv` on a plain int is
# `-(num//-amt)` (helpers.py:68), so `H.ceildiv_i32` is the same reading. `U32`
# would wrap and answer a different pool shape.
#
# `flatten(reversed(grouped_pads))` reverses the list of PAIRS and then
# flattens, and `flat_to_grouped` pairs from the END (helpers.py:57), so
# `grouped[0]` is the LAST spatial dim. Reversing the pairs puts the answer back
# in flat order, which is why the answer is a flat list again. See `oq_ceil_pad`
# for why the reversal is of the PAIRS and not of the flat list.
# ===========================================================================

# relationship 15: `ceildiv(i+pB+pA - (d*(k-1)+1), s) + 1`
def oq_ceil_o(+pB: U32, +i: U32, d: U32, k: U32, s: U32, +pA: U32) -> U32:
  (U32.add(H.ceildiv_i32(U32.sub(U32.add(U32.add(i, pB), pA), oq_span(k, d)), s), 1) : U32)

# The new `pA`. Kept as ONE expression with the Python terms named, because the
# gate mutates it term by term and a rewritten formula would not be a port.
def oq_ceil_pA(+pA: U32, +o: U32, +i: U32, +s: U32, k: U32, d: U32, +pB: U32) -> U32:
  # `s*(o-1) + (d*(k-1)+1) - (i+pB+pA)` is read twice -- once whole and once
  # inside the `smax` as `s*(o-1) - (pB+i-1)` -- so the span and the window
  # start are bound once. The bindings are affine, so they are recomputed
  # rather than reused: `oq_win` is pure and `oq_span` is one arithmetic node.
  U32.add(
    U32.add(pA, U32.mul(s, U32.sub(o, 1))),
    U32.sub(
      U32.sub(oq_span(k, d), U32.add(U32.add(i, pB), pA)),
      oq_smax_i32(U32.sub(U32.mul(s, U32.sub(o, 1)), U32.add(pB, U32.sub(i, 1))), 0)))

# PASS ONE. `zip(i_, d_, k_, s_, grouped_pads)` -> `o_`, appended so the list
# comes out in order. `List.append(a, A, xs, ys)` is `xs ++ ys`, so an
# ACCUMULATOR appends and does not cons -- the opposite of a rebuild, and the
# single most expensive misreading in this port (constraints, appendix E).
def oq_ceil_o.go(i_: List<&2, U32>, d_: List<&2, U32>, k_: List<&2, U32>, s_: List<&2, U32>,
                 g: List<&2, List<&2, U32>>, acc: List<&2, U32>) -> List<&2, U32>:
  match i_ d_ k_ s_ g acc:
    case i <> ti d <> td k <> tk s <> ts +gg <> tg _:
      oq_ceil_o.go(ti, td, tk, ts, tg,
        List.append(&2, U32, acc,
          [oq_ceil_o(oq_pB(gg), i, d, k, s, oq_pA(gg))]))
    case _ _ _ _ _ _: acc

def oq_o_list(+i_: List<&2, U32>, +d_: List<&2, U32>, +k_: List<&2, U32>, +s_: List<&2, U32>,
              +g: List<&2, List<&2, U32>>) -> List<&2, U32>:
  oq_ceil_o.go(i_, d_, k_, s_, g, Nil{})

# PASS TWO. `zip(o_, i_, s_, k_, d_, grouped_pads)` rewriting `grouped_pads`,
# accumulating the list of PAIRS. `dim` from `enumerate` is never read -- the
# write is `grouped_pads[dim] = ...` at the same index -- so it does not appear
# here, and that is not a divergence: Python reads `dim` only as that index.
#
# THE PAIRS ARE REVERSED *AS PAIRS* AND ONLY THEN FLATTENED, and that is not a
# detail. `flatten(reversed(grouped_pads))` reverses the list of PAIRS; a first
# version of this def accumulated the FLAT list and reversed that, which also
# swaps `pB` and `pA` inside every pair. With one spatial dim the pair-reversal
# is a no-op and the flat-reversal is not, so a 1-D `ceil_25_0` answered `[1,0]`
# where CPython says `[0,1]` -- and a `5381 * head + rest` digest could not see
# it, because `[0,1]` and `[1,0]` are both 5381 under it. The row that caught
# it is `ceil_25_0`, and the digest is the one with the per-level `+1`.
def oq_ceil_pad.go(o_: List<&2, U32>, i_: List<&2, U32>, s_: List<&2, U32>, k_: List<&2, U32>,
                   d_: List<&2, U32>, g: List<&2, List<&2, U32>>,
                   acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match o_ i_ s_ k_ d_ g acc:
    case o <> to i <> ti s <> ts k <> tk d <> td +gg <> tg _:
      oq_ceil_pad.go(to, ti, ts, tk, td, tg,
        List.append(&2, List<&2, U32>, acc,
          [[oq_pB(gg), oq_ceil_pA(oq_pA(gg), o, i, s, k, d, oq_pB(gg))]]))
    case _ _ _ _ _ _ _: acc

def oq_ceil_pad(+o_: List<&2, U32>, +i_: List<&2, U32>, +s_: List<&2, U32>, +k_: List<&2, U32>,
                +d_: List<&2, U32>, +g: List<&2, List<&2, U32>>) -> List<&2, U32>:
  H.flatten_u32(List.reverse(&2, List<&2, U32>, oq_ceil_pad.go(o_, i_, s_, k_, d_, g, Nil{})))

# `self.shape[-n:]` -- the last `n` dims. `List.drop` gives a PREFIX so this is
# drop-by-(len-n).
def oq_tail_dims(+ds: List<&2, U32>, n: U32) -> List<&2, U32>:
  List.drop(&2, U32, ds, Nat.sub(List.length(&2, U32, ds), U32.to_nat(n)))

# The whole method. `i_` is `self.shape[-len(k_):]`, and `s_`/`d_` are
# `make_tuple`'d to `len(k_)` (op.py:1272), which is what the two `isdims` flags
# select: `False` is the scalar arm and `True` is the sequence arm.
def oq_apply_ceil_mode(+shape: List<&2, S.Sdim>, +pads: List<&2, U32>, +k_: List<&2, U32>,
                       s_isdims: Bool, +s_: U32, +s_seq: List<&2, U32>,
                       d_isdims: Bool, +d_: U32, +d_seq: List<&2, U32>) -> List<&2, U32>:
  +n = U32.from_nat(List.length(&2, U32, k_))
  +i_ = oq_tail_dims(oq_szs(shape), n)
  +s_ = oq_make_tuple.of(s_isdims, s_, s_seq, n)
  +d_ = oq_make_tuple.of(d_isdims, d_, d_seq, n)
  +g = oq_flat_to_grouped(pads)
  oq_ceil_pad(oq_o_list(i_, d_, k_, s_, g), i_, s_, k_, d_, g)

# ===========================================================================
# THE GATE.
#
# EVERY ROW IS DERIVABLE FROM PYTHON. The oracle is the `_apply_ceil_mode` BODY
# of op.py:1272-1282 -- not my transcription of it -- run under
# `.venv/bin/python` with the real `tinygrad` imported, on the SAME fixture,
# and the expectation is the number it printed. Nothing here restates my own
# code, so a row can actually be wrong.
#
# `oq_digest` is `d(xs) = 1000003 * d(rest) + head + 1`. The `+1` per LEVEL is
# what encodes the LENGTH. The obvious `5381 * head + rest` does not: it put
# `[0,1,0,1]` and `[1,1]` both at 10762 and three different fixtures at 0, and a
# digest that collides across fixtures cannot see two of them being swapped.
# Every digest row below is a DISTINCT value unless the comment says otherwise.
#
# THE TWO TRAPS THE BRIEF NAMES, and the row for each.
#
# 1. PADS ARE NEGATIVE (op.py:1595 says so out loud: "padding, possibly
#    negative -- _pad_constant handles the shrink"), so `U32` wraps on the way
#    in and `ceil_neg` carries them as two's complement: CPython's `pads`
#    `[-1,-1,0,0]` is `[4294967295,4294967295,0,0]` here and its answer
#    `[-1,-1,0,1]`. A truncating `U32.sub` in `oq_ceil_o` cannot produce `o_=[2,0]`.
# 2. THE COUNT ROW IS NOT OPTIONAL. `List.append(a,A,xs,ys)` is `xs ++ ys`
#    (constraints, appendix E): consing instead of appending in pass two
#    REVERSES the pairs, so `ceil_5x5_0` answers `[1,0,1,0]` where CPython says
#    `[0,1,0,1]` -- a different digest -- while the LENGTH stays 4. Both are
#    printed, and `ceil_4x4x4_len` is 6 against a 3-element kernel because the
#    answer is flat.
#
# AND THE ROW THAT IS NOT OPTIONAL BECAUSE OF A BUG: `ceil_5x7_sc` and
# `ceil_5x7_s1` DELIBERATELY AGREE. `make_tuple(1, 2)` is `[1,1]`, which is
# what the sequence arm `[1,1]` already is, so the scalar arm and the sequence
# arm must produce the same answer. `ceil_s_arms_agree=1` is that claim, and it
# is the row that catches a `make_tuple` whose two arms are transposed --
# a bug no all-differing fixture can see.
# ===========================================================================
def oq_shape(ns: List<&2, U32>) -> List<&2, S.Sdim>:
  match ns:
    case Nil{}: Nil{}
    case n <> r: S.SN{U32.to_nat(n)} <> oq_shape(r)

def oq_row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# `d(xs) = 1000003 * d(rest) + head + 1`. The `+1` per LEVEL is what encodes the
# LENGTH, so `[0,1]` (2000007) and `[0,0]` (1000004) differ even though a naive
# weighted sum of the same two numbers might not.
def oq_digest(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}: 0
    case h <> t:
      (U32.add(U32.add(U32.mul(1000003, oq_digest(t)), h), 1) : U32)

def oq_len(xs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, xs))

# ---------------------------------------------------------------------------
# THE FIXTURES. `f_x` is CPython's `_apply_ceil_mode` shape, pads, k, s, d, with
# the `isdims` flags decided by whether s and d are tuples there.
# ---------------------------------------------------------------------------
# shape (25,) pads (0,0) k (2,) s 2 d 1 -> o_=[13] out=[0,1]
def f_25_0() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([25]), [0, 0], [2], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (25,) pads (1,1) -> o_=[14] out=[1,1]
def f_25_1() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([25]), [1, 1], [2], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (25,) k (3,) -> o_=[12] out=[0,0].  A different KERNEL SIZE on the same
# input: the only thing that moves is `oq_span`, so this is that row.
def f_25_k3() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([25]), [0, 0], [3], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (5,5) pads (0,0,0,0) k (2,2) -> o_=[3,3] out=[0,1,0,1].  THE COUNT ROW.
def f_5x5_0() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([5, 5]), [0, 0, 0, 0], [2, 2], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (5,5) pads all 1 -> o_=[4,4] out=[1,1,1,1]
def f_5x5_1() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([5, 5]), [1, 1, 1, 1], [2, 2], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (5,7) k (3,2) s SCALAR 2 -> o_=[2,4] out=[0,1,0,0].
# `make_tuple(2, 2)` is `[2,2]`, so the scalar arm really does reach both dims.
def f_5x7_sc() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([5, 7]), [0, 0, 0, 0], [3, 2], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (5,7) pads (2,2,0,0) k (3,2) s the SEQUENCE (2,1) -> o_=[2,10] out=[2,1,0,0]
def f_5x7_pd() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([5, 7]), [2, 2, 0, 0], [3, 2], True{}, 0, [2, 1], False{}, 1, Nil{})
# shape (4,4,4) pads all 1 k (2,2,2) s the sequence -> o_=[3,3,3] out=[1,1,1,1,1,1]
def f_4x4x4() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([4, 4, 4]), [1, 1, 1, 1, 1, 1], [2, 2, 2], True{}, 0, [2, 2, 2],
    False{}, 1, Nil{})
# shape (4,4) pads (-1,-1,0,0) k (2,2) s the sequence (2,1) d 2 -> o_=[2,0] out=[-1,-1,0,1]
# shape (5,7) k (3,2) s SCALAR 1 -> o_=[3,6] out=[0,0,0,0]
# shape (4,4) pads (-1,-1,0,0) k (2,2) s the sequence (2,1) d 2 -> o_=[2,0] out=[-1,-1,0,1]
# THE SIGNED ROW. Both pB and the answer are negative.
def f_neg() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([4, 4]), [4294967295, 4294967295, 0, 0], [2, 2], True{}, 0, [2, 1],
    False{}, 2, Nil{})
# shape (5,7) k (3,2) s SCALAR 1 -> o_=[3,6] out=[0,0,0,0]
def f_sc1() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([5, 7]), [0, 0, 0, 0], [3, 2], False{}, 1, Nil{}, False{}, 1, Nil{})
# shape (5,7) k (3,2) s the SEQUENCE (1,1) -> o_=[3,6] out=[0,0,0,0].  MUST AGREE WITH f_sc1.
def f_s1() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([5, 7]), [0, 0, 0, 0], [3, 2], True{}, 0, [1, 1], False{}, 1, Nil{})
# shape (1,1,2) -- TWO LEADING DIMS, and every dim is smaller than the ones
# next to it, which is the only way `shape[-n:]` and `shape[:n]` disagree in the
# ANSWER rather than merely in the list. k (2,) s 2 d 1 -> out=[0,0].
# THE ROW FOR `self.shape[-n:]`. Chosen by SEARCH, not by guessing: 812 shapes
# discriminate and this is one whose correct digest collides with nothing else
# in the gate. `List.take` instead of `List.drop` answers [0,1] (2000007).
def f_batch() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([1, 1, 2]), [0, 0], [2], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (1,1,2) k (2,2) pads (0,0,0,0) s 2 d 1 -> out=[0,0,0,1].  Two dims this
# time, and it discriminates too: `List.take` answers [0,1,0,1] (448412614).
def f_batch2() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([1, 1, 2]), [0, 0, 0, 0], [2, 2], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (25,) pads (0,1) k (2,) -> pB=0, pA=1, so pB != pA.  THE ROW FOR
# `oq_pB`/`oq_pA`: every other fixture pads symmetrically, so swapping the two
# readers is invisible, and these two are the only rows where `pB` reaches the
# answer as `pB` and not as a copy of `pA`.
def f_asym() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([25]), [0, 1], [2], False{}, 2, Nil{}, False{}, 1, Nil{})
# shape (4,5) pads (0,2,1,0) k (2,2): BOTH pairs asymmetric, so `pB != pA` on
# both spatial dims at once.
def f_asym2() -> List<&2, U32>:
  oq_apply_ceil_mode(oq_shape([4, 5]), [0, 2, 1, 0], [2, 2], False{}, 2, Nil{}, False{}, 1, Nil{})

# THE TWO-PASS CLAIM, as its own rows. `o_` is pass one's output and pass two
# reads it back, so a fused or stale `o_` is a different answer than a wrong
# pass two -- and only a row on `o_` itself tells the two apart.
def o_o_25_0() -> U32:
  oq_digest(oq_o_list([25], [1], [2], [2], oq_flat_to_grouped([0, 0])))
def o_o_5x5_0() -> U32:
  oq_digest(oq_o_list([5, 5], [1, 1], [2, 2], [2, 2], oq_flat_to_grouped([0, 0, 0, 0])))
def o_o_neg() -> U32:
  oq_digest(oq_o_list([4, 4], [2, 2], [2, 2], [2, 1],
    oq_flat_to_grouped([4294967295, 4294967295, 0, 0])))

# `oq_smax_i32` WITH TWO NEGATIVES. `_apply_ceil_mode` only ever calls
# `smax(term, 0)`, so the `case True{} True{}` arm of `oq_slt_i32` is
# UNREACHABLE from any fixture above -- measured, see the mutation table's M6.
# It is still the arm that decides `smax(-3, -5)`, and a signed compare that
# treated two negatives as two unsigned numbers would answer it wrong, so the
# helper gets its own row instead of being left unexercised.
def o_smax_nn() -> U32: oq_smax_i32(4294967293, 4294967291)
def o_smax_np() -> U32: oq_smax_i32(4294967293, 7)

# THE GROUPING. CPython lengths: [0,0]->1, [1,2,3,4]->2, [1,2,3]->1, [1]->0,
# [1,2,3,4,5,6]->3.  The last two are the parity cases and they disagree with
# each other, so a grouping that ignored the odd-length drop would move BOTH.
def t_fg2() -> U32: oq_len(List.concat(&2, U32, oq_flat_to_grouped([0, 0])))
def t_fg4() -> U32: oq_len(List.concat(&2, U32, oq_flat_to_grouped([1, 2, 3, 4])))
def t_fg3() -> U32: oq_len(List.concat(&2, U32, oq_flat_to_grouped([1, 2, 3])))
def t_fg1() -> U32: oq_len(List.concat(&2, U32, oq_flat_to_grouped([1])))
def t_fg6() -> U32: oq_len(List.concat(&2, U32, oq_flat_to_grouped([1, 2, 3, 4, 5, 6])))

# THE SHARED DEF, MEASURED. Expects 0 and that IS the report: CPython says 4.
def t_fg_shared() -> U32: oq_len(List.concat(&2, U32, H.flat_to_grouped([1, 2, 3, 4])))

# ###########################################################################
# STAGE 2. op.py:1971 `nbytes`, op.py:1952 `hash`, op.py:1892 `keccak`,
# op.py:1378 `max_unpool2d`, op.py:1424 `_conv2d_winograd`,
# op.py:1605 `conv_transpose2d`.
#
# These are the other methods in this half whose CONTENT is arithmetic. Each is
# the integer/shape part of its Python method; the Tensor composition around it
# is named as a `TODO(p3)` wall.
# ###########################################################################

# ===========================================================================
# `nbytes` -- op.py:1971-1979.
#
#     def nbytes(self) -> int:
#       Returns the total number of bytes of all elements in the tensor.
#       return int(self.numel()) * self.element_size()
#
# ENTIRELY PORTED. `numel()` is `prod(shape)` and `element_size()` is
# `DType.itemsize`, and `int(...)` is the coercion to a Python int, which is
# what a `U32` already is. There is no Tensor call left in it.
#
# THE `S.Sdim` CAVEAT IS the docstring's `int(self.numel())`. A symbolic dim
# answers 0 from `S.dim_of` (spec.bend:308), so `nbytes` on a shape the fold has
# not resolved is 0 rather than an error; tinygrad raises there. Row `nb_sym`
# pins that reading instead of leaving it as a surprise.
# ===========================================================================
def oq_nbytes(shape: List<&2, S.Sdim>, dt: S.Dt) -> U32:
  (U32.mul(S.Dt.itemsize(dt), H.prod_u32(oq_szs(shape))) : U32)

# ===========================================================================
# REPORTED DEFECT #2 IN A SHARED FILE: `H.ceildiv_u32` OVERFLOWS AT THE TOP OF
# THE U32 RANGE. It is `(num + amt - 1) / amt`, and `num + amt - 1` WRAPS.
# MEASURED, rows `ceildiv_top` / `ceildiv_ok`: with `num = 2**32 - 1` and
# `amt = 2**20`, `num + amt - 1` is `1048574` after the wrap and the answer is
# 0, where CPython's `ceildiv(2**32-1, 2**20)` is 4096.
#
# `H.ceildiv_i32` IS FINE and is what the ceil-mode arithmetic uses -- it goes
# through `floordiv_i32` and never forms `num + amt - 1`. Only the unsigned
# reader has the overflow, and only at the top of the range, so no other caller
# in this file can see it: `oq_hash_chunks` is the only one whose `num` reaches
# `2**32`.
#
# THE OVERFLOW-FREE FORM IS `num / amt + (num % amt != 0)`, which is Python's
# `ceildiv` for non-negative ints and cannot overflow. `oq_ceildiv_u32` is that,
# spelled here because the shared def cannot be called to get the right answer.
# WHEN `ceildiv_u32` IS FIXED, `oq_ceildiv_u32` is deleted and row `hash_max`
# is the row that would catch a regression in the replacement.
# ===========================================================================
def oq_ceildiv_u32.of(exact: Bool, num: U32, amt: U32) -> U32:
  match exact:
    case True{} : U32.div(num, amt)
    case False{}: U32.add(U32.div(num, amt), 1)

def oq_ceildiv_u32(+num: U32, +amt: U32) -> U32:
  oq_ceildiv_u32.of(U32.is_eq(U32.mod(num, amt), 0), num, amt)

# ===========================================================================
# `hash` -- op.py:1952-1969, THE CHUNK LOOP ONLY.
#
#     data = self.flatten().bitcast(dtypes.uint8)
#     n = data.shape[0]
#     chunks = ceildiv(n, 2**20)
#     while chunks > 1:
#       data = data.pad_to(chunks * 2**20).reshape(chunks, 2**20)._hash_1mb().flatten()
#       chunks = ceildiv(chunks, 65536)
#     return data.pad_to(2**20).unsqueeze(0)._hash_1mb().flatten()[:16]
#
# `oq_hash_chunks` is the `chunks` SEQUENCE: the initial `ceildiv(n, 2**20)` and
# then one `ceildiv(chunks, 65536)` per trip round the loop, INCLUDING the final
# 1. Returning the sequence rather than the last value is deliberate -- the
# NUMBER OF TRIPS is what a wrong divisor or a wrong loop condition shows up in,
# and a gate that saw only the last value would see 1 either way.
#
# `2**20` IS SPELLED 1048576 and not `2 << 20`: Bend's `U32.shln` is a LOGICAL
# shift by ONE (constraints 1.3), so there is no exponent form to reach for.
#
# THE U32 RANGE IS A REAL LIMIT, not a formality. `n` counts `uint8` elements, so
# `n > 2**32` is a tensor larger than 4 GiB and no single buffer holds one. The
# arithmetic WRAPS above that: CPython's `hash_chunks(2**40)` is `[2**20, 16, 1]`
# and a `U32` reading of `2**40` is 0.
# ===========================================================================
# `while chunks > 1` AND WHY THE FUEL IS 0 OR 1. `n` is a count of `uint8`
# elements read from a `U32`, so `n <= 2**32 - 1` and
#   c0 = ceildiv(n, 2**20) <= ceildiv(2**32-1, 2**20) = 4096
# One trip gives `c1 = ceildiv(c0, 65536) <= ceildiv(4096, 65536) = 1` and the
# loop stops. So the loop runs AT MOST ONCE in the `U32` reading. The fuel is 0
# or 1 and NOT A CONSTANT: `c0 <= 1` really is zero trips, and rows `hash_1m`
# (`[1]`) against `hash_1m_p1` (`[2,1]`) are the pair that says so. The fuel is
# the FIRST parameter because a self-call has to decrease left to right and a
# `U32` divisor is not visibly smaller than its input to the checker.
def oq_hash_fuel.of(more: Bool) -> Nat:
  match more:
    case True{}: 1n
    case False{}: 0n

def oq_hash_fuel(c: U32) -> Nat:
  oq_hash_fuel.of(U32.is_gt(c, 1))

def oq_hash_chunks.go(fuel: Nat, +c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n  : List.append(&2, U32, acc, [c])
    case 1n+p: oq_hash_chunks.go(p, oq_ceildiv_u32(c, 65536),
                           List.append(&2, U32, acc, [c]))

def oq_hash_chunks(n: U32) -> List<&2, U32>:
  +c0 = oq_ceildiv_u32(n, 1048576)
  oq_hash_chunks.go(oq_hash_fuel(c0), c0, Nil{})

# ===========================================================================
# `keccak` -- op.py:1892-1944, THE CONSTANTS AND THE BLOCK ARITHMETIC.
#
#     rot_offsets = [44, 43, 21, 14, 28, 20, 3, 45, 61, 1, 6, 25, 8, 18, 27, 36, 10, 15, 56, 62, 55, 39, 41, 2]
#     rot_offsets_v0, rot_offsets_v1 = ctensor([0] + [1 << v for v in rot_offsets]), ctensor([1] + [1 << (64 - v) for v in rot_offsets])
#     # calculated from pi step
#     reorder_indexes = ctensor([0,6,12,18,24,3,9,10,16,22,1,7,13,19,20,4,5,11,17,23,2,8,14,15,21], dtype=dtypes.int32)
#     rnd_const_masks = [ctensor([v]).pad((0, 24)) for v in (1, 0x8082, ...)]
#     rate, dsbyte = {"sha3_224": (144, 6), "sha3_256": (136, 6), "shake_128": (168, 31)}[cfg] if isinstance(cfg, str) else cfg
#     data_pad = rate - data.shape[-1] % rate
#     lbe = (data.shape[1] - 1) * 200 + rate - data_pad
#     return state.bitcast(dtypes.uint8)[:,:(obytes:=(200 - rate) // 2)].reshape(*self.shape[:-1], obytes)
#
# ALL FOUR TABLES ARE THE PORT and all four are here: the 24 rho rotation offsets,
# the 25 pi reorder indices, the 24 round constants, and the rate/dsbyte map.
# They are the parts of `keccak` that are DECIDABLE without a device, and they
# are what the f1600 permutation is built out of.
#
# WHY THE ROUND CONSTANTS ARE AN `I64` PAIR AND NOT HEX. They are 64-bit and Bend
# has no 64-bit literal and no 64-bit arithmetic; `H.i64_of_hi_lo`
# (helpers.bend:1175) builds a pair of two `U32` and `H.hi32`/`H.lo32` read it.
# The halves are the constant's own bit fields, not a lossy split, and rows
# `keccak_rc_hi`/`keccak_rc_lo` pin both against CPython.
#
# `rot_offsets_v0` and `rot_offsets_v1` are `1 << v` and `1 << (64 - v)`, and
# `1 << 63` does not fit a `U32` AT ALL -- that is the WALL, and it is why only
# the 24 OFFSETS are ported and not the two masks derived from them.
# ===========================================================================
def oq_keccak_rot() -> List<&2, U32>:
  [44, 43, 21, 14, 28, 20, 3, 45, 61, 1, 6, 25, 8, 18, 27, 36, 10, 15, 56, 62, 55, 39, 41, 2]

# calculated from the pi step
def oq_keccak_reorder() -> List<&2, U32>:
  [0, 6, 12, 18, 24, 3, 9, 10, 16, 22, 1, 7, 13, 19, 20, 4, 5, 11, 17, 23, 2, 8, 14, 15, 21]

def oq_keccak_rc() -> List<&2, H.I64>:
  [ H.i64_of_hi_lo(0, 1), H.i64_of_hi_lo(0, 32898), H.i64_of_hi_lo(2147483648, 32906),
    H.i64_of_hi_lo(2147483648, 2147516416), H.i64_of_hi_lo(0, 32907), H.i64_of_hi_lo(0, 2147483649),
    H.i64_of_hi_lo(2147483648, 2147516545), H.i64_of_hi_lo(2147483648, 32777),
    H.i64_of_hi_lo(0, 138), H.i64_of_hi_lo(0, 136), H.i64_of_hi_lo(0, 2147516425),
    H.i64_of_hi_lo(0, 2147483658), H.i64_of_hi_lo(0, 2147516555), H.i64_of_hi_lo(2147483648, 139),
    H.i64_of_hi_lo(2147483648, 32905), H.i64_of_hi_lo(2147483648, 32771),
    H.i64_of_hi_lo(2147483648, 32770), H.i64_of_hi_lo(2147483648, 128),
    H.i64_of_hi_lo(0, 32778), H.i64_of_hi_lo(2147483648, 2147483658),
    H.i64_of_hi_lo(2147483648, 2147516545), H.i64_of_hi_lo(2147483648, 2147516544),
    H.i64_of_hi_lo(0, 2147483649), H.i64_of_hi_lo(2147483648, 2147516424) ]

def oq_keccak_rc_len(rcs: List<&2, H.I64>) -> U32:
  U32.from_nat(List.length(&2, H.I64, rcs))

def oq_keccak_rc_hi(rcs: List<&2, H.I64>) -> List<&2, U32>:
  match rcs:
    case Nil{}: Nil{}
    case h <> r: H.hi32(h) <> oq_keccak_rc_hi(r)

def oq_keccak_rc_lo(rcs: List<&2, H.I64>) -> List<&2, U32>:
  match rcs:
    case Nil{}: Nil{}
    case h <> r: H.lo32(h) <> oq_keccak_rc_lo(r)

# `{"sha3_224": (144, 6), "sha3_256": (136, 6), "shake_128": (168, 31)}`. Python
# indexes a dict by a string; Bend's `Map` is string-keyed too, but the table is
# three pairs and a three-variant `Data` with two readers reads like the Python
# literal while being TOTAL. The string keys are NOT ported: `Map.get` answers a
# `Sigma` and three keys would be more machinery than the table is worth.
# `oq_keccak_cfg` takes the selector `U32` 0/1/2 and the key-to-selector mapping
# is the caller's, which is the same seam tinygrad's `isinstance(cfg, str)` is.
#
# NOT `match cfg: case 0n: 144`. A numeric `case 0n:` is a PREFIX match and
# already claims 1 and 2, so the second arm would be dead code (measured).
type KeccakCfg is Data:
  K224{}
  K256{}
  K128{}

def oq_keccak_cfg.sel(is0: Bool, is1: Bool) -> KeccakCfg:
  match is0 is1:
    case True{}  _      : K224{}
    case False{} True{} : K256{}
    case False{} False{}: K128{}

def oq_keccak_cfg(+cfg: U32) -> KeccakCfg:
  oq_keccak_cfg.sel(U32.is_eq(cfg, 0), U32.is_eq(cfg, 1))

def oq_keccak_rate(c: KeccakCfg) -> U32:
  match c:
    case K224{}: 144
    case K256{}: 136
    case K128{}: 168

def oq_keccak_dsbyte(c: KeccakCfg) -> U32:
  match c:
    case K224{}: 6
    case K256{}: 6
    case K128{}: 31

# `data_pad = rate - data.shape[-1] % rate`
def oq_keccak_data_pad(len: U32, +rate: U32) -> U32:
  (U32.sub(rate, U32.mod(len, rate)) : U32)

# `obytes := (200 - rate) // 2`
def oq_keccak_obytes(rate: U32) -> U32:
  (H.ceildiv_i32(U32.sub(200, rate), 2) : U32)

# `lbe = (data.shape[1] - 1) * 200 + rate - data_pad`. `data.shape[1]` is the
# block count after `.pad_to(None, None, 200)`, which the caller computes from
# `data.shape[0]`; the FORMULA is ported and the row passes the count in.
def oq_keccak_lbe(blocks: U32, rate: U32, data_pad: U32) -> U32:
  (U32.add(U32.mul(U32.sub(blocks, 1), 200), U32.sub(rate, data_pad)) : U32)

# ===========================================================================
# `max_unpool2d` -- op.py:1378-1410, THE `output_size` DERIVATION.
#
#     bs,c,*spatial_shape = self.shape
#     if output_size is None:
#       k_,d_,s_ = (make_tuple(x, len(spatial_shape)) for x in (kernel_size, dilation, stride if stride is not None else kernel_size))
#       p_ = flat_to_grouped(resolve_pool_pads(padding, len(spatial_shape)))
#       # https://arxiv.org/pdf/1603.07285 inverse of relationship 15 in section 5.1.
#       output_size = tuple((i-1)*s - (pB+pA) + (d*(k-1)+1) for i,k,d,s,(pB,pA) in zip(spatial_shape,k_,d_,s_,p_))
#     else: output_size = output_size[-len(spatial_shape):]
#     ret = (indices.reshape(bs,c,1,-1)._one_hot_along_dim(prod(output_size), 2).where(self.reshape(bs,c,1,-1), 0)).sum(3)
#     return ret.reshape(bs,c,*output_size)
#
# PORTED: the `None` branch, the three `make_tuple`s, the grouping, and
# relationship 15 INVERTED. The `reshape`/`one_hot`/`where`/`sum` tail is a
# `TODO(p3)`.
#
# `(pB+pA)` IS `(pA+pB)` AND THAT IS THE WHOLE TRICK: `p_` is
# `flat_to_grouped(...)`, whose pairs are `(pB, pA)`, and this comprehension adds
# them, so the naming is irrelevant HERE. That is not true of every unpool line --
# `_conv2d_winograd` below really does use them apart -- and the rows pin the sum,
# not the naming.
# ===========================================================================
def oq_max_unpool_out.go(i_: List<&2, U32>, k_: List<&2, U32>, d_: List<&2, U32>,
                         s_: List<&2, U32>, g: List<&2, List<&2, U32>>, acc: List<&2, U32>) ->
  List<&2, U32>:
  match i_ k_ d_ s_ g acc:
    case i <> ti k <> tk d <> td s <> ts +gg <> tg _:
      oq_max_unpool_out.go(ti, tk, td, ts, tg,
        List.append(&2, U32, acc,
          [U32.add(U32.sub(U32.mul(U32.sub(i, 1), s), U32.add(oq_pB(gg), oq_pA(gg))),
             oq_span(k, d))]))
    case _ _ _ _ _ _: acc

# `n` IS `len(spatial_shape)` IN PYTHON TOO (`make_tuple(x, len(spatial_shape))`),
# so it is read off the list rather than passed: passing it cost a `+` on the
# parameter and duplicated a fact the list already carries.
def oq_max_unpool_out(+spatial: List<&2, U32>, k_isdims: Bool, +k_: U32,
                      +k_seq: List<&2, U32>, d_isdims: Bool, +d_: U32, +d_seq: List<&2, U32>,
                      s_isdims: Bool, +s_: U32, +s_seq: List<&2, U32>, pads: List<&2, U32>) ->
  List<&2, U32>:
  +n = U32.from_nat(List.length(&2, U32, spatial))
  oq_max_unpool_out.go(spatial,
    oq_make_tuple.of(k_isdims, k_, k_seq, n),
    oq_make_tuple.of(d_isdims, d_, d_seq, n),
    oq_make_tuple.of(s_isdims, s_, s_seq, n),
    oq_flat_to_grouped(pads), Nil{})

# ===========================================================================
# `_conv2d_winograd` -- op.py:1424-1462, THE PAD ROUNDING AND THE TILE SIZES.
#
#     # use padding to round up to 4x4 output tiles
#     pads = [(pB, pA + (-(s + pB + pA - 2) % 4)) for (pB,pA), s in zip(flat_to_grouped(padding_), self.shape[-len(HW):])]
#     d = self.pad(flatten(reversed(pads)))._pool(HWI, HWO)
#     HWI, HWO = (6,) * len(HW), (4,) * len(HW)  # F(4x4,3x3) winograd tiles
#
# PORTED: `pads` and `flatten(reversed(pads))`. `HWI`/`HWO` are `make_tuple` with
# the int arm and are one call to `oq_make_tuple` rather than two literals.
#
# THE `%` IS PYTHON'S FLOORMOD ON A POSSIBLY-NEGATIVE NUMERATOR, so it is
# `H.floormod_i32` and NOT `U32.mod`. `-(s+pB+pA-2)` is negative for every one of
# these fixtures, and `U32.mod` would answer 3 where CPython's `%` answers -1,
# making the pad 4 too small. That is the single most load-bearing reading here.
#
# The winograd CONSTANT MATRICES `winograd_G`/`winograd_Bt`/`winograd_At`
# (op.py:1441-1443) are 6x3, 6x6 and 4x6 F32 tables; they are plain literals and
# a `TODO(p3)` names them rather than transliterating 60 float constants nobody
# can check by reading.
# ===========================================================================
def oq_wino_pads.pair(s: U32, +gg: List<&2, U32>) -> List<&2, U32>:
  [oq_pB(gg), U32.add(oq_pA(gg),
    H.floormod_i32(H.i32_neg(U32.add(U32.add(s, U32.add(oq_pB(gg), oq_pA(gg))), 2)), 4))]

def oq_wino_pads.go(spatial: List<&2, U32>, g: List<&2, List<&2, U32>>,
                    acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match spatial g acc:
    case s <> ts +gg <> tg _:
      oq_wino_pads.go(ts, tg, List.append(&2, List<&2, U32>, acc, [oq_wino_pads.pair(s, gg)]))
    case _ _ _: acc

# `pads` as pairs, then `flatten(reversed(pads))` -- reversed AS PAIRS, the same
# reading `oq_ceil_pad` needed and for the same reason.
def oq_wino_pads(+spatial: List<&2, U32>, pads: List<&2, U32>) -> List<&2, U32>:
  H.flatten_u32(List.reverse(&2, List<&2, U32>,
    oq_wino_pads.go(spatial, oq_flat_to_grouped(pads), Nil{})))

# ===========================================================================
# `conv_transpose2d` -- op.py:1605-1642, THE PADDING.
#
#     x, w = self, weight.unflatten(0, (groups, -1)).transpose(1, 2).flip(*range(3, len(weight.shape)+1))
#     HW = weight.shape[2:]
#     padding = flat_to_grouped(resolve_pool_pads(padding, len(HW)))
#     stride, dilation, output_padding = [make_tuple(x, len(HW)) for x in (stride, dilation, output_padding)]
#     if any(s>1 for s in stride):
#       x = x.reshape(None, None, *flatten((k,1) for k in x.shape[2:]))
#       x = x.pad((None, None, *flatten((None,(0,s-1)) for s in stride)))
#       x = x.reshape(None, None, *[k*s for k,s in zip(x.shape[2::2], stride)])
#       x = x.shrink_to(None, None, *[k-(s-1) for k,s in zip(x.shape[2:], stride)])
#     padding = flatten((((k-1)*d-pB,(k-1)*d-pA+op) for k,d,(pB,pA),op in reversed(list(zip(HW, dilation, padding, output_padding)))))
#     return x.conv2d(w.flatten(end_dim=1), groups=groups, bias=bias, dilation=dilation, padding=padding)
#
# PORTED: the last two lines -- the `make_tuple`s, the grouping, the reversed
# four-way zip and its two products. The `x.reshape/pad/shrink` block is integer
# arithmetic too but it reads `x.shape` AFTER each step, so it needs the Tensor
# and is a `TODO(p3)`. `flatten(reversed(...))` reverses the PAIRS, once more.
# ===========================================================================
def oq_ct_pad.pair(+k: U32, +d: U32, +gg: List<&2, U32>, op: U32) -> List<&2, U32>:
  [U32.sub(U32.mul(U32.sub(k, 1), d), oq_pB(gg)),
   U32.add(U32.sub(U32.mul(U32.sub(k, 1), d), oq_pA(gg)), op)]

def oq_ct_pad.go(hw: List<&2, U32>, d_: List<&2, U32>, g: List<&2, List<&2, U32>>,
                 op: List<&2, U32>, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match hw d_ g op acc:
    case k <> tk d <> td +gg <> tg o <> to _:
      oq_ct_pad.go(tk, td, tg, to, List.append(&2, List<&2, U32>, acc, [oq_ct_pad.pair(k, d, gg, o)]))
    case _ _ _ _ _: acc

def oq_ct_pad(+hw: List<&2, U32>, d_isdims: Bool, +d_: U32, +d_seq: List<&2, U32>,
              pads: List<&2, U32>, op_isdims: Bool, +op_: U32, +op_seq: List<&2, U32>) ->
  List<&2, U32>:
  +n = U32.from_nat(List.length(&2, U32, hw))
  H.flatten_u32(List.reverse(&2, List<&2, U32>,
    oq_ct_pad.go(hw, oq_make_tuple.of(d_isdims, d_, d_seq, n), oq_flat_to_grouped(pads),
      oq_make_tuple.of(op_isdims, op_, op_seq, n), Nil{})))

# ---------------------------------------------------------------------------
# STAGE 2 FIXTURES. Same rule: every expectation is CPython's, from the method
# body put into the oracle script and run against the real `tinygrad`.
# ---------------------------------------------------------------------------
# nbytes: (8,9) float itemsize 4 -> 288; (5,) half 2 -> 10; (2,2,2,2) uint8 -> 16
def t_nb_288() -> U32: oq_nbytes(oq_shape([8, 9]), S.single())
def t_nb_10() -> U32: oq_nbytes(oq_shape([5]), S.half())
def t_nb_16() -> U32: oq_nbytes(oq_shape([2, 2, 2, 2]), S.uint8())
def t_nb_168() -> U32: oq_nbytes(oq_shape([3, 7]), S.int64())
# The `S.Sdim` caveat, pinned: a SYMBOLIC dim answers 0 from `S.dim_of`, so
# `nbytes` on an unresolved shape is 0 rather than an error. CPython raises.
def t_nb_sym() -> U32: oq_nbytes([S.SS{S.SpInvalid{}}], S.single())

# hash chunk sequences. `hash_1m` and `hash_1m_p1` are the PAIR: 2**20 elements
# exactly is ZERO trips and one more is ONE, so the loop condition is not a
# constant and the 0-or-1 fuel is doing real work.
def t_h_1() -> U32: oq_digest(oq_hash_chunks(1))
def t_h_16() -> U32: oq_digest(oq_hash_chunks(16))
def t_h_1m() -> U32: oq_digest(oq_hash_chunks(1048576))
def t_h_1m_p1() -> U32: oq_digest(oq_hash_chunks(1048577))
def t_h_3m() -> U32: oq_digest(oq_hash_chunks(3145728))
def t_h_4m() -> U32: oq_digest(oq_hash_chunks(4194304))
def t_h_max() -> U32: oq_digest(oq_hash_chunks(4294967295))
def t_h_1m_len() -> U32: oq_len(oq_hash_chunks(1048576))
def t_h_1m_p1_len() -> U32: oq_len(oq_hash_chunks(1048577))

# THE REPORTED `ceildiv_u32` OVERFLOW. `ceildiv_top` is the shared def measured
# at the top of the range and it is WRONG; `ceildiv_top_fix` is the local
# overflow-free form and it is right. CPython's `ceildiv(2**32-1, 2**20)` is
# 4096. Both rows read 4096 and `hash_max` is what depends on it.
def t_ceil_shared() -> U32: H.ceildiv_u32(4294967295, 1048576)
def t_ceil_fix() -> U32: oq_ceildiv_u32(4294967295, 1048576)
def t_ceil_ok() -> U32: oq_ceildiv_u32(1048576, 1048576)
def t_ceil_ok2() -> U32: oq_ceildiv_u32(1048577, 1048576)

# keccak. Every table's digest is CPython's over the SAME literal, and the
# LENGTHS are separate rows so a dropped element cannot hide inside a digest.
def t_k_rot() -> U32: oq_digest(oq_keccak_rot())
def t_k_rot_len() -> U32: oq_len(oq_keccak_rot())
def t_k_reo() -> U32: oq_digest(oq_keccak_reorder())
def t_k_reo_len() -> U32: oq_len(oq_keccak_reorder())
def t_k_hi() -> U32: oq_digest(oq_keccak_rc_hi(oq_keccak_rc()))
def t_k_lo() -> U32: oq_digest(oq_keccak_rc_lo(oq_keccak_rc()))
def t_k_rc_len() -> U32: oq_keccak_rc_len(oq_keccak_rc())
def t_k_r224() -> U32: oq_keccak_rate(oq_keccak_cfg(0))
def t_k_r256() -> U32: oq_keccak_rate(oq_keccak_cfg(1))
def t_k_r128() -> U32: oq_keccak_rate(oq_keccak_cfg(2))
def t_k_d224() -> U32: oq_keccak_dsbyte(oq_keccak_cfg(0))
def t_k_d128() -> U32: oq_keccak_dsbyte(oq_keccak_cfg(2))
# `data_pad = rate - len % rate`. L=136 with rate=136 is the row that pins the
# `%`: it is 136 there, and a `rate - (len-1)` reading would say 137.
def t_k_dp_12() -> U32: oq_keccak_data_pad(12, 136)
def t_k_dp_135() -> U32: oq_keccak_data_pad(135, 136)
def t_k_dp_136() -> U32: oq_keccak_data_pad(136, 136)
def t_k_ob_256() -> U32: oq_keccak_obytes(136)
def t_k_ob_128() -> U32: oq_keccak_obytes(168)
def t_k_ob_224() -> U32: oq_keccak_obytes(144)
# `lbe = (blocks-1)*200 + rate - data_pad`
def t_k_lbe_1() -> U32: oq_keccak_lbe(1, 136, oq_keccak_data_pad(12, 136))
def t_k_lbe_2() -> U32: oq_keccak_lbe(2, 136, oq_keccak_data_pad(12, 136))
def t_k_lbe_3() -> U32: oq_keccak_lbe(3, 136, oq_keccak_data_pad(136, 136))

# max_unpool2d output_size. `stride is None` is the `s_isdims=False` arm AND the
# value is then `kernel_size`, so the same kernel goes in twice -- which is
# Python's `stride if stride is not None else kernel_size`.
def t_mu_88() -> List<&2, U32>:
  oq_max_unpool_out([4, 4], False{}, 2, Nil{}, False{}, 1, Nil{}, False{}, 2, Nil{}, [0, 0, 0, 0])
def t_mu_66() -> List<&2, U32>:
  oq_max_unpool_out([4, 4], False{}, 2, Nil{}, False{}, 1, Nil{}, False{}, 2, Nil{}, [1, 1, 1, 1])
def t_mu_114() -> List<&2, U32>:
  oq_max_unpool_out([5, 3], True{}, 0, [3, 2], False{}, 1, Nil{}, True{}, 0, [2, 1], [0, 0, 0, 0])
def t_mu_70() -> List<&2, U32>:
  oq_max_unpool_out([5, 3], True{}, 0, [3, 2], False{}, 1, Nil{}, True{}, 0, [2, 1], [2, 2, 2, 2])
def t_mu_79() -> List<&2, U32>:
  oq_max_unpool_out([4, 5], False{}, 2, Nil{}, False{}, 2, Nil{}, False{}, 2, Nil{}, [1, 1, 1, 1])
def t_mu_14() -> List<&2, U32>:
  oq_max_unpool_out([6], False{}, 3, Nil{}, False{}, 1, Nil{}, False{}, 3, Nil{}, [2, 2])

# _conv2d_winograd pads. `wino_44` is the row for the floormod:
# `-(s+pB+pA-2)` is NEGATIVE there, so `U32.mod` would answer 3 where CPython's
# `%` answers -1 and the pad would be 4 too small.
def t_wp_44() -> List<&2, U32>: oq_wino_pads([4, 4], [0, 0, 0, 0])
def t_wp_55() -> List<&2, U32>: oq_wino_pads([5, 5], [1, 1, 1, 1])
def t_wp_444() -> List<&2, U32>: oq_wino_pads([4, 4, 4], [0, 0, 0, 0, 0, 0])
def t_wp_35() -> List<&2, U32>: oq_wino_pads([3, 5], [1, 1, 1, 1])
def t_wp_66() -> List<&2, U32>: oq_wino_pads([6, 6], [2, 2, 2, 2])
def t_wp_22() -> List<&2, U32>: oq_wino_pads([2, 2], [0, 0, 0, 0])

# conv_transpose2d padding. `pads` here is the ALREADY-resolved flat list, as
# `flat_to_grouped(resolve_pool_pads(...))` takes it.
# The ASYMMETRIC winograd pads, and the row for M45. Every other wino fixture
# pads symmetrically, so `pB == pA` and swapping the two readers is invisible.
def t_wp_asym() -> List<&2, U32>: oq_wino_pads([4, 4], [0, 1, 0, 1])
def t_wp_asym2() -> List<&2, U32>: oq_wino_pads([3, 5], [2, 3, 0, 1])

def t_ct_22() -> List<&2, U32>: oq_ct_pad([2, 2], False{}, 1, Nil{}, [0, 0, 0, 0], False{}, 0, Nil{})
def t_ct_22p() -> List<&2, U32>: oq_ct_pad([2, 2], False{}, 1, Nil{}, [1, 1, 1, 1], False{}, 0, Nil{})
def t_ct_32() -> List<&2, U32>: oq_ct_pad([3, 2], False{}, 1, Nil{}, [0, 0, 0, 0], False{}, 0, Nil{})
# `padding=(1,0)` RESOLVES to `[0,0,1,1]` (helpers.py:61 reverses), which is
# this row. `[1,1,0,0]` is the OTHER row: it is a legal already-resolved pad list
# and `oq_ct_pad` takes one, but it is not what `(1,0)` means, and the first
# version of this fixture conflated the two.
def t_ct_32op() -> List<&2, U32>: oq_ct_pad([3, 2], False{}, 1, Nil{}, [0, 0, 1, 1], False{}, 1, Nil{})
def t_ct_32op_rev() -> List<&2, U32>: oq_ct_pad([3, 2], False{}, 1, Nil{}, [1, 1, 0, 0], False{}, 1, Nil{})
def t_ct_222() -> List<&2, U32>: oq_ct_pad([2, 2, 2], False{}, 1, Nil{}, [0, 0, 0, 0, 0, 0], False{}, 0, Nil{})
def t_ct_33d2() -> List<&2, U32>: oq_ct_pad([3, 3], False{}, 2, Nil{}, [1, 1, 1, 1], False{}, 1, Nil{})

def main() -> IO(Unit):
  do IO<Unit>:
    oq_row("ceil_25_0", oq_digest(f_25_0()))
    oq_row("ceil_25_1", oq_digest(f_25_1()))
    oq_row("ceil_25_k3", oq_digest(f_25_k3()))
    oq_row("ceil_5x5_0", oq_digest(f_5x5_0()))
    oq_row("ceil_5x5_1", oq_digest(f_5x5_1()))
    oq_row("ceil_5x7_sc", oq_digest(f_5x7_sc()))
    oq_row("ceil_5x7_pd", oq_digest(f_5x7_pd()))
    oq_row("ceil_4x4x4", oq_digest(f_4x4x4()))
    oq_row("ceil_neg", oq_digest(f_neg()))
    oq_row("ceil_s1", oq_digest(f_s1()))
    oq_row("ceil_batch", oq_digest(f_batch()))
    oq_row("ceil_batch2", oq_digest(f_batch2()))
    oq_row("ceil_asym", oq_digest(f_asym()))
    oq_row("ceil_asym2", oq_digest(f_asym2()))
    oq_row("ceil_sc1", oq_digest(f_sc1()))
    oq_row("ceil_s_arms_agree", Bool.to_u32(U32.is_eq(oq_digest(f_sc1()), oq_digest(f_s1()))))
    oq_row("ceil_5x5_len", oq_len(f_5x5_0()))
    oq_row("ceil_4x4x4_len", oq_len(f_4x4x4()))
    oq_row("ceil_neg_len", oq_len(f_neg()))
    oq_row("ceil_batch_len", oq_len(f_batch()))
    oq_row("ceil_batch2_len", oq_len(f_batch2()))
    oq_row("ceil_asym2_len", oq_len(f_asym2()))
    oq_row("smax_neg_neg", o_smax_nn())
    oq_row("smax_neg_pos", o_smax_np())
    oq_row("o_25_0", o_o_25_0())
    oq_row("o_5x5_0", o_o_5x5_0())
    oq_row("o_neg", o_o_neg())
    oq_row("diag_fg_2", t_fg2())
    oq_row("diag_fg_4", t_fg4())
    oq_row("diag_fg_3", t_fg3())
    oq_row("diag_fg_1", t_fg1())
    oq_row("diag_fg_6", t_fg6())
    oq_row("diag_fg_shared", t_fg_shared())
    oq_row("ceildiv_top", t_ceil_shared())
    oq_row("ceildiv_top_fix", t_ceil_fix())
    oq_row("ceildiv_exact", t_ceil_ok())
    oq_row("ceildiv_round", t_ceil_ok2())
    oq_row("nb_288", t_nb_288())
    oq_row("nb_10", t_nb_10())
    oq_row("nb_16", t_nb_16())
    oq_row("nb_168", t_nb_168())
    oq_row("nb_sym", t_nb_sym())
    oq_row("hash_1", t_h_1())
    oq_row("hash_16", t_h_16())
    oq_row("hash_1m", t_h_1m())
    oq_row("hash_1m_p1", t_h_1m_p1())
    oq_row("hash_3m", t_h_3m())
    oq_row("hash_4m", t_h_4m())
    oq_row("hash_max", t_h_max())
    oq_row("hash_1m_len", t_h_1m_len())
    oq_row("hash_1m_p1_len", t_h_1m_p1_len())
    oq_row("keccak_rot", t_k_rot())
    oq_row("keccak_rot_len", t_k_rot_len())
    oq_row("keccak_reo", t_k_reo())
    oq_row("keccak_reo_len", t_k_reo_len())
    oq_row("keccak_rc_hi", t_k_hi())
    oq_row("keccak_rc_lo", t_k_lo())
    oq_row("keccak_rc_len", t_k_rc_len())
    oq_row("keccak_rate_224", t_k_r224())
    oq_row("keccak_rate_256", t_k_r256())
    oq_row("keccak_rate_128", t_k_r128())
    oq_row("keccak_ds_224", t_k_d224())
    oq_row("keccak_ds_128", t_k_d128())
    oq_row("keccak_pad_12", t_k_dp_12())
    oq_row("keccak_pad_135", t_k_dp_135())
    oq_row("keccak_pad_136", t_k_dp_136())
    oq_row("keccak_ob_256", t_k_ob_256())
    oq_row("keccak_ob_128", t_k_ob_128())
    oq_row("keccak_ob_224", t_k_ob_224())
    oq_row("keccak_lbe_1", t_k_lbe_1())
    oq_row("keccak_lbe_2", t_k_lbe_2())
    oq_row("keccak_lbe_3", t_k_lbe_3())
    oq_row("mu_88", oq_digest(t_mu_88()))
    oq_row("mu_66", oq_digest(t_mu_66()))
    oq_row("mu_114", oq_digest(t_mu_114()))
    oq_row("mu_70", oq_digest(t_mu_70()))
    oq_row("mu_79", oq_digest(t_mu_79()))
    oq_row("mu_14", oq_digest(t_mu_14()))
    oq_row("mu_14_len", oq_len(t_mu_14()))
    oq_row("wino_44", oq_digest(t_wp_44()))
    oq_row("wino_55", oq_digest(t_wp_55()))
    oq_row("wino_444", oq_digest(t_wp_444()))
    oq_row("wino_35", oq_digest(t_wp_35()))
    oq_row("wino_66", oq_digest(t_wp_66()))
    oq_row("wino_22", oq_digest(t_wp_22()))
    oq_row("wino_444_len", oq_len(t_wp_444()))
    oq_row("wino_asym", oq_digest(t_wp_asym()))
    oq_row("wino_asym2", oq_digest(t_wp_asym2()))
    oq_row("ct_22", oq_digest(t_ct_22()))
    oq_row("ct_22p", oq_digest(t_ct_22p()))
    oq_row("ct_32", oq_digest(t_ct_32()))
    oq_row("ct_32op", oq_digest(t_ct_32op()))
    oq_row("ct_32op_rev", oq_digest(t_ct_32op_rev()))
    oq_row("ct_222", oq_digest(t_ct_222()))
    oq_row("ct_33d2", oq_digest(t_ct_33d2()))
    oq_row("ct_222_len", oq_len(t_ct_222()))

# ===========================================================================
# THE MEASURED MUTATION TABLE. 54 mutations against 96 rows.
#
# Run the driver against this file IN PLACE, `diff` the rows against the
# baseline, restore. Every expectation it compares against came from CPython
# (the `oracle_full.py` in the report), so a mutation that moves a row moved it
# AWAY FROM tinygrad.
#
# TWO MUTATIONS MOVE NOTHING, AND BOTH ARE STRUCTURALLY UNOBSERVABLE RATHER
# THAN GATE DEFECTS. That is the honest reading and it is why they are here
# rather than deleted:
#
#   * M20, `ceildiv(chunks, 65536)` -> `ceildiv(chunks, 32768)`. In the `U32`
#     reading the loop runs at most once and `c0 <= ceildiv(2**32-1, 2**20) =
#     4096`, and `4096 < 32768`, so BOTH divisors answer 1. The second divisor
#     is DEAD over this range. In CPython `n` is unbounded and the divisor is
#     live, so this is a limit of the port's arithmetic and not a property of
#     the algorithm. `oq_hash_chunks` says so in its own header.
#   * M46, `make_tuple_rep(x, n)` -> `make_tuple_rep(x, n+1)`. Every
#     `oq_make_tuple` result is zipped against lists whose length IS `n`, and
#     the zip walks stop at the first `Nil`, so a LONGER tuple is invisible. A
#     SHORTER one is very visible: M53 (`make_tuple_of`, always one element)
#     moves 27 rows.
#
# THREE ROWS ARE MOVED BY NOTHING, and each is named rather than hidden:
#
#   * `diag_fg_shared` and `ceildiv_top` are the two REPORTED DEFECT rows. They
#     HOLD the measurement of a shared def being wrong; there is no mutation
#     that makes a measurement wrong.
#   * `ceil_s_arms_agree` is a cross-check that turns out to be INSENSITIVE to
#     every mutation in this table, M53 included, because the scalar and the
#     sequence `s` agree by coincidence even after `make_tuple` is broken. The
#     VALUE rows `ceil_sc1` and `ceil_s1` carry the load there and both move.
#     This row is kept because the agreement is a real claim, not because it
#     discriminates.
#
# AND THE ROWS THAT PAID FOR THEMSELVES, which is what the table is for:
#
#   * `smax_neg_neg` is moved by M6 and nothing else. It exists because
#     `_apply_ceil_mode` only ever evaluates `smax(term, 0)`, so the
#     both-negative arm of `oq_slt_i32` is unreachable from every ceil fixture.
#     M6 reached it and found a REAL BUG: that arm read `U32.is_gt` and
#     answered `smax(-3,-5) = -5`. The mutation I wrote as a probe turned out
#     to be the FIX.
#   * `wino_asym`/`wino_asym2` are moved by M45 alone and `ceil_asym`/`ceil_asym2`
#     by M16 alone, both for the same reason: every other fixture in that family
#     pads symmetrically, so `pB == pA` and swapping the two readers is invisible.
#
# TWO MUTATIONS FOUND REAL PORT ERRORS rather than gate gaps, and both are in
# this file's headers: M10 (reverse the FLAT list instead of the PAIRS, which
# swaps `pB` and `pA` inside every pair) and M12/M13 (`flat_to_grouped`). M10 was
# caught only AFTER the digest was changed to one folding a per-level `+1`: the
# `5381 * head + rest` digest the gate started with put `[0,1]` and `[1,0]` at
# the same value, so the bug was invisible until the digest stopped colliding.
# ===========================================================================
# | M1 | M1  oq_span: d*(k-1)+1 -> d*k+1 | 19: ceil_25_0 ceil_25_k3 ceil_4x4x4 ceil_5x5_0 ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_batch ceil_batch2 mu_114 mu_14 mu_66 mu_70 mu_79 mu_88 o_25_0 o_5x5_0 o_neg |
# | M2 | M2  oq_ceil_o: drop the trailing +1 | 18: ceil_25_0 ceil_25_1 ceil_25_k3 ceil_4x4x4 ceil_5x5_0 ceil_5x5_1 ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_batch ceil_batch2 ceil_neg ceil_s1 ceil_sc1 o_25_0 o_5x5_0 o_neg |
# | M3 | M3  ceildiv_i32 -> cdiv_i32_go (truncating, not flooring) | 10: ceil_25_0 ceil_25_1 ceil_5x5_0 ceil_5x5_1 ceil_5x7_sc ceil_asym2 ceil_neg o_25_0 o_5x5_0 o_neg |
# | M4 | M4  oq_ceil_pA: smax(term, 0) -> the bare term (the guard dropped) | 8: ceil_25_k3 ceil_5x7_pd ceil_5x7_sc ceil_batch ceil_batch2 ceil_neg ceil_s1 ceil_sc1 |
# | M5 | M5  oq_smax_i32: arms swapped (min, not max) | 13: ceil_25_1 ceil_25_k3 ceil_5x5_1 ceil_5x7_pd ceil_5x7_sc ceil_asym2 ceil_batch ceil_batch2 ceil_neg ceil_s1 ceil_sc1 smax_neg_neg smax_neg_pos |
# | M6 | M6  oq_slt_i32: both-negative arm -> U32.is_gt (the bug I shipped first) | 1: smax_neg_neg |
# | M7 | M7  oq_slt_i32: mixed-sign arms both False (sign test dropped) | 9: ceil_25_k3 ceil_5x7_pd ceil_5x7_sc ceil_batch ceil_batch2 ceil_neg ceil_s1 ceil_sc1 smax_neg_pos |
# | M8 | M8  pass two walks the pairs REVERSED (the net effect of consing) | 3: ceil_5x7_pd ceil_asym2 ceil_neg |
# | M9 | M9  pass ONE returns o_ reversed (o_/g pairing) | 5: ceil_5x7_pd ceil_5x7_sc ceil_neg ceil_s1 ceil_sc1 |
# | M10 | M10 reverse the FLAT list instead of the pairs (ceil) | 8: ceil_25_0 ceil_5x5_0 ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_batch2 ceil_neg |
# | M11 | M11 fuse the two passes (no reverse at all) | 5: ceil_5x7_pd ceil_5x7_sc ceil_asym2 ceil_batch2 ceil_neg |
# | M12 | M12 fg_skip(n mod 2) -> fg_skip(n): the helpers.bend bug, reintroduced | 52: ceil_25_0 ceil_25_1 ceil_25_k3 ceil_4x4x4 ceil_4x4x4_len ceil_5x5_0 ceil_5x5_1 ceil_5x5_len ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_asym2_len ceil_batch ceil_batch2 ceil_batch2_len ceil_batch_len ceil_neg ceil_neg_len ceil_s1 ceil_sc1 ct_22 ct_222 ct_222_len ct_22p ct_32 ct_32op ct_32op_rev ct_33d2 diag_fg_2 diag_fg_3 diag_fg_4 diag_fg_6 mu_114 mu_14 mu_14_len mu_66 mu_70 mu_79 mu_88 o_25_0 o_5x5_0 o_neg wino_22 wino_35 wino_44 wino_444 wino_444_len wino_55 wino_66 wino_asym wino_asym2 |
# | M13 | M13 use the BUGGY H.flat_to_grouped instead of the local one | 21: ceil_25_0 ceil_25_1 ceil_25_k3 ceil_4x4x4 ceil_4x4x4_len ceil_5x5_0 ceil_5x5_1 ceil_5x5_len ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_asym2_len ceil_batch ceil_batch2 ceil_batch2_len ceil_batch_len ceil_neg ceil_neg_len ceil_s1 ceil_sc1 |
# | M14 | M14 oq_make_tuple arms swapped | 36: ceil_25_0 ceil_25_1 ceil_25_k3 ceil_4x4x4 ceil_4x4x4_len ceil_5x5_0 ceil_5x5_1 ceil_5x5_len ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_asym2_len ceil_batch ceil_batch2 ceil_batch2_len ceil_batch_len ceil_neg ceil_neg_len ceil_s1 ceil_sc1 ct_22 ct_222 ct_222_len ct_22p ct_32 ct_32op ct_32op_rev ct_33d2 mu_114 mu_14 mu_14_len mu_66 mu_70 mu_79 mu_88 |
# | M15 | M15 shape[-n:] -> shape[:n] | 2: ceil_batch ceil_batch2 |
# | M16 | M16 oq_pB reads index 1, oq_pA reads index 0 | 4: ceil_asym ceil_asym2 wino_asym wino_asym2 |
# | M17 | M17 oq_ceil_pA: drop the s*(o-1) term | 11: ceil_25_0 ceil_25_1 ceil_25_k3 ceil_4x4x4 ceil_5x5_0 ceil_5x5_1 ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_neg |
# | M18 | M18 oq_digest: the naive 5381*head+rest the gate was built to avoid | 50: ceil_25_0 ceil_25_1 ceil_25_k3 ceil_4x4x4 ceil_5x5_0 ceil_5x5_1 ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_batch ceil_batch2 ceil_neg ceil_s1 ceil_sc1 ct_22 ct_222 ct_22p ct_32 ct_32op ct_32op_rev ct_33d2 hash_1 hash_16 hash_1m hash_1m_p1 hash_3m hash_4m hash_max keccak_rc_hi keccak_rc_lo keccak_reo keccak_rot mu_114 mu_14 mu_66 mu_70 mu_79 mu_88 o_25_0 o_5x5_0 o_neg wino_22 wino_35 wino_44 wino_444 wino_55 wino_66 wino_asym wino_asym2 |
# | M19 | M19 hash: the 2**20 divisor -> 2**19 | 6: hash_1m hash_1m_len hash_1m_p1 hash_3m hash_4m hash_max |
# | M20 | M20 hash: the 65536 divisor -> 32768 | *** NOTHING MOVED -- BLIND *** |
# | M21 | M21 hash: the loop condition `> 1` -> `> 0` | 4: hash_1 hash_16 hash_1m hash_1m_len |
# | M22 | M22 oq_ceildiv_u32: the +1 on an inexact division is dropped | 9: ceildiv_round ceildiv_top_fix hash_1 hash_16 hash_1m_p1 hash_1m_p1_len hash_3m hash_4m hash_max |
# | M23 | M23 oq_ceildiv_u32 -> H.ceildiv_u32 (the reported overflow) | 2: ceildiv_top_fix hash_max |
# | M24 | M24 nbytes: multiply by bits instead of itemsize | 4: nb_10 nb_16 nb_168 nb_288 |
# | M25 | M25 keccak rot_offsets: shift one entry | 1: keccak_rot |
# | M26 | M26 keccak reorder: swap two pi indices | 1: keccak_reo |
# | M27 | M27 keccak rc: swap the hi and lo halves of one constant | 2: keccak_rc_hi keccak_rc_lo |
# | M28 | M28 keccak rc_hi reads lo and rc_lo reads hi | 1: keccak_rc_hi |
# | M29 | M29 keccak cfg: the K256 and K128 rate arms swapped | 2: keccak_rate_128 keccak_rate_256 |
# | M30 | M30 keccak data_pad: rate - len%rate -> rate - (len-1) | 6: keccak_lbe_1 keccak_lbe_2 keccak_lbe_3 keccak_pad_12 keccak_pad_135 keccak_pad_136 |
# | M31 | M31 keccak obytes: // 2 -> // 4 | 3: keccak_ob_128 keccak_ob_224 keccak_ob_256 |
# | M32 | M32 keccak lbe: (blocks-1)*200 -> blocks*200 | 3: keccak_lbe_1 keccak_lbe_2 keccak_lbe_3 |
# | M33 | M33 wino: floormod_i32 -> U32.mod (the sign bug) | 3: wino_35 wino_55 wino_asym |
# | M34 | M34 wino: the modulus 4 -> 3 | 7: wino_22 wino_35 wino_44 wino_444 wino_55 wino_asym wino_asym2 |
# | M41 | M41 keccak cfg: the dsbyte arms for 224 and 256 swapped | 1: keccak_ds_224 |
# | M42 | M42 keccak rot_offsets: drop the LAST entry | 2: keccak_rot keccak_rot_len |
# | M43 | M43 keccak reorder: drop the LAST entry | 2: keccak_reo keccak_reo_len |
# | M44 | M44 keccak rc: drop the LAST constant | 3: keccak_rc_hi keccak_rc_len keccak_rc_lo |
# | M45 | M45 wino: the OUTPUT pair writes pA first and pB second | 2: wino_asym wino_asym2 |
# | M46 | M46 make_tuple: the repeat count n -> n+1 | *** NOTHING MOVED -- BLIND *** |
# | M47 | M47 fg_skip: the parity comes from n-1 instead of n | 51: ceil_25_0 ceil_25_1 ceil_25_k3 ceil_4x4x4 ceil_4x4x4_len ceil_5x5_0 ceil_5x5_1 ceil_5x5_len ceil_5x7_pd ceil_5x7_sc ceil_asym ceil_asym2 ceil_asym2_len ceil_batch ceil_batch2 ceil_batch2_len ceil_batch_len ceil_neg ceil_neg_len ceil_s1 ceil_sc1 ct_22 ct_222 ct_222_len ct_22p ct_32 ct_32op ct_32op_rev ct_33d2 diag_fg_2 diag_fg_4 diag_fg_6 mu_114 mu_14 mu_14_len mu_66 mu_70 mu_79 mu_88 o_25_0 o_5x5_0 o_neg wino_22 wino_35 wino_44 wino_444 wino_444_len wino_55 wino_66 wino_asym wino_asym2 |
# | M48 | M48 diag_fg_1 target: flat_to_grouped([1]) -> flat_to_grouped([1,1]) | 1: diag_fg_1 |
# | M49 | M49 nb_sym: prod over the symbolic dim -> the dim's own value | 1: nb_sym |
# | M50 | M50 oq_ceildiv_u32: the EXACT arm adds 1 too | 5: ceildiv_exact hash_1m hash_1m_len hash_3m hash_4m |
# | M51 | M51 keccak rate: K224 144 -> 145 | 1: keccak_rate_224 |
# | M52 | M52 keccak dsbyte: K128 31 -> 30 | 1: keccak_ds_128 |
# | M53 | M53 oq_make_tuple scalar arm: repeat n -> always one element | 28: ceil_4x4x4 ceil_4x4x4_len ceil_5x5_0 ceil_5x5_1 ceil_5x5_len ceil_5x7_pd ceil_5x7_sc ceil_asym2 ceil_asym2_len ceil_batch2 ceil_batch2_len ceil_neg ceil_neg_len ceil_s1 ceil_sc1 ct_22 ct_222 ct_222_len ct_22p ct_32 ct_32op ct_32op_rev ct_33d2 mu_114 mu_66 mu_70 mu_79 mu_88 |
# | M54 | M54 oq_hash_fuel: the fuel is always 1 | 4: hash_1 hash_16 hash_1m hash_1m_len |
# | M35 | M35 wino: reverse the FLAT list instead of the pairs | 6: wino_35 wino_44 wino_444 wino_55 wino_asym wino_asym2 |
# | M36 | M36 ct_pad: (k-1)*d -> k*d in the FIRST product | 7: ct_22 ct_222 ct_22p ct_32 ct_32op ct_32op_rev ct_33d2 |
# | M37 | M37 ct_pad: the +op is dropped from the second product | 3: ct_32op ct_32op_rev ct_33d2 |
# | M38 | M38 ct_pad: reverse the FLAT list instead of the pairs | 3: ct_32op ct_32op_rev ct_33d2 |
# | M39 | M39 max_unpool: (i-1)*s -> i*s | 6: mu_114 mu_14 mu_66 mu_70 mu_79 mu_88 |
# | M40 | M40 max_unpool: the span loses its +1 | 6: mu_114 mu_14 mu_66 mu_70 mu_79 mu_88 |
# ===========================================================================
# THE WALLS. Every method in this half that is NOT ported, with the thing that
# stops it. `p3` is the phase that builds the Tensor method surface; nothing
# here guesses at what p3 will look like.
#
# THE ONE WALL UNDERNEATH ALL OF THEM: `mixin/op.py`'s methods are methods ON A
# TENSOR and they are almost entirely compositions of OTHER TENSOR methods --
# `gather`, `where`, `pad`, `sum`, `permute`, `reshape`. None of those exist in
# `tinybendygrad/`: there is no `mixin/elementwise.bend` and no
# `mixin/movement.bend`, and `tensor.bend`'s `Tensor` is a thin wrapper with a
# handful of methods. So the wall is not a Bend limitation, it is a substrate
# that has not been built yet, and every line below is arithmetic I extracted
# from around it rather than a thing Bend cannot express.
#
# TWO WALLS ARE BEND'S, and they are the only two.
#
#   * `seq` of CLOSURES. `sequential` (op.py:1243) is
#     `functools.reduce(lambda x,f: f(x), ll, self)` over `list[Callable]`. A
#     function value is a `Type`, and a `Type` is never copyable, so a list of
#     them is not a `Data` and cannot be a parameter. This one is not coming
#     back without a different representation.
#   * 64-BIT ROTATE AND XOR. The f1600 round (op.py:1930-1935) is
#     `(state * rot_offsets_v0).bitwise_or(state // rot_offsets_v1)` and
#     `~state.roll(...) & state.roll(...)` over a 25-lane uint64 state. Bend
#     has no 64-bit literal, no 64-bit arithmetic and no rotate or popcount
#     (constraints 2). The CONSTANTS are ported -- `oq_keccak_rc` and
#     `oq_keccak_rot` are the whole of what the round is built from -- and the
#     arithmetic is not.
#
# THE PER-METHOD LIST, in Python order. The PORTED column is what is here.
# ===========================================================================
# op.py:998  allclose                  -- WALL: needs `isclose` + `all`, both from
#                                       unported elementwise/reduce mixins.
# op.py:1005 _one_hot_along_dim        -- PORTED: none (it is `self.eq(...)`, all
#                                       tensor). WALL: the `eq`/`arange`/`reshape`.
# op.py:1010 one_hot                   -- PORTED: the `is_int` dtype guard and the
#                                       `num_classes >= 0` guard. WALL: `[..., None]`.
# op.py:1023 gather                    -- PORTED: the ndim guard and the
#                                       shrink/unsqueeze/transpose index order.
#                                       WALL: `where`/`sum` on the result.
# op.py:1043 interpolate               -- PORTED: nothing. WALL: `arange`, `clip`,
#                                       `gather`, `lerp`, `cast`; the per-axis
#                                       index arithmetic needs the arange list
#                                       materialised as data first.
# op.py:1077 _pre_scatter              -- PORTED: nothing. WALL: the shape asserts
#                                       read `self.shape`, and the body is
#                                       `unsqueeze`/`expand`/`transpose`/`pad_to`.
# op.py:1095 scatter_reduce            -- PORTED: nothing. WALL: `where`, `sum`,
#                                       `add`/`mul`/`max`/`min`/`maximum`,
#                                       `commit_dtype().min`, and the `_inv_mask`
#                                       CLOSURE.
# op.py:1136 scatter                   -- PORTED: nothing. WALL: `Tensor.full` and
#                                       `_masked_merge`.
# op.py:1170 _masked_merge             -- PORTED: nothing. WALL: `functools.reduce`
#                                       over a `zip` of `split`-ed tensors; the
#                                       reduce needs a tuple-returning lambda.
# op.py:1179 masked_select             -- PORTED: nothing. WALL: `mask_cumsum[-1].item()`
#                                       is a DATA READBACK, which is the real stop.
# op.py:1208 nonzero                   -- PORTED: the 0-dim branch's shape rule.
#                                       WALL: `stack`, `masked_select`, `reshape`.
# op.py:1243 sequential                -- WALL: a `list[Callable]`. Bend's own.
# op.py:1254 linear                    -- PORTED: the `len(weight.shape) == 1`
#                                       branch. WALL: `mul`, `dot`, `add`.
# op.py:1271 _apply_ceil_mode          -- PORTED WHOLE.  THIS IS THE FILE'S
#                                       CENTREPIECE and the only method in this
#                                       half with no Tensor in its body.
# op.py:1285 avg_pool2d                -- PORTED: `axis`, `s_`, `reg_pads`/`pads`
#                                       and the three-way `count_include_pad` /
#                                       `ceil_mode` decision.
#                                       WALL: `_pad_constant`, `_pool`, `sum`, `mean`.
# op.py:1333 max_pool2d                -- PORTED: `axis`, `s_`, `pads`,
#                                       `spatial_sz` and the reversed `idx` arange.
#                                       WALL: `_pool`, `commit_dtype().min`, `max`.
# op.py:1378 max_unpool2d              -- PORTED: the `output_size` derivation,
#                                       relationship 15 INVERTED.
#                                       WALL: `reshape`, `_one_hot_along_dim`,
#                                       `where`, `sum`.
# op.py:1411 _apply_winograd_matrix    -- PORTED: nothing. WALL: `transpose`,
#                                       `const`, `reshape`; and `mat` is a Tensor
#                                       of the constants, not a table.
# op.py:1424 _conv2d_winograd          -- PORTED: `pads`, `flatten(reversed(pads))`,
#                                       and `HWI`/`HWO` as `make_tuple` calls.
#                                       WALL: `pad`, `_pool`, `permute`,
#                                       `contiguous_backward`, `sum`, and the
#                                       three 60-float constant matrices
#                                       (`winograd_G`/`Bt`/`At`, op.py:1441-1443),
#                                       which are `F32` literals and a p3 decision
#                                       whether they live in this file at all.
# op.py:1464 image_dot                 -- PORTED: nothing. WALL: `transpose`,
#                                       `reshape` and `image_conv2d`.
# op.py:1479 image_conv2d             -- PORTED: nothing. WALL: the whole tensor
#                                       path (`pad`, `permute`, `reshape`,
#                                       `contiguous`, `_pool`) AND `math.gcd`,
#                                       which `pad_align` needs for its align
#                                       target and which no `tinybendygrad` file
#                                       exports. The packing ARITHMETIC
#                                       (`round_up`, `is_pow2`, `bank_conflict`,
#                                       `rcin_hi/lo`, `group_shape`,
#                                       `rcout_expand`, `added_output_channels`)
#                                       is integer-only and is the obvious p3
#                                       follow-up to this file.
# op.py:1562 conv2d                    -- PORTED: nothing. WALL: `_pad_constant`,
#                                       `_pool`, `reshape`, `expand`, `permute`,
#                                       `sum`. `IMAGE`/`WINO` are `ContextVar`s and
#                                       `helpers.bend`'s `Flags` has only four
#                                       fields, so the two dispatch arms are not
#                                       reachable from here either.
# op.py:1605 conv_transpose2d          -- PORTED: the padding derivation, the
#                                       reversed four-way zip and its two products.
#                                       WALL: `unflatten`, `transpose`, `flip`,
#                                       `reshape`, `pad`, `shrink_to` -- and the
#                                       `x.shape[2:]` reads BETWEEN them.
# op.py:1644 layernorm                 -- PORTED: nothing. WALL: `mean`, `rsqrt`.
# op.py:1662 batchnorm                 -- PORTED: nothing. WALL: `reshape`, `mul`,
#                                       `add`; `argfix(axis)` is in helpers.bend.
# op.py:1686 _do_reduction             -- PORTED: nothing. WALL: `sum`, `mean`.
# op.py:1692 binary_crossentropy       -- PORTED: nothing. WALL: `log`.
# op.py:1706 binary_crossentropy_logits-- PORTED: nothing. WALL: `logsigmoid`.
# op.py:1721 sparse_categorical_xent   -- PORTED: nothing. WALL: `log_softmax`,
#                                       `_one_hot_along_dim`, `where`, `mean`.
# op.py:1746 cross_entropy             -- PORTED: nothing. WALL: `log_softmax`, `mul`.
# op.py:1773 nll_loss                  -- PORTED: nothing. WALL: `gather`,
#                                       `const_like`, `ne`.
# op.py:1799 qr                        -- PORTED: nothing. WALL: the Householder
#                                       loop is `@` on Tensors; `eye`/`arange` are
#                                       Side A's.
# op.py:1817 svd                       -- PORTED: nothing. WALL: the Jacobi sweeps,
#                                       `sort`, `gather`, `contiguous`, `pad`.
# op.py:1873 newton_schulz             -- PORTED: nothing. WALL: `@` on Tensors and
#                                       `functools.reduce` over a generator.
# op.py:1892 keccak                    -- PORTED: all four tables, the rate/dsbyte
#                                       map, `data_pad`, `obytes`, `lbe`.
#                                       WALL: the f1600 round, BEND'S (64-bit
#                                       rotate/xor), and `rot_offsets_v0`/`_v1`
#                                       whose `1 << 63` does not fit a `U32`.
# op.py:1946 _hash_1mb                 -- PORTED: the assert constants (`1024*1024`,
#                                       `4096`) only. WALL: the two
#                                       `keccak("shake_128")` calls, which need the
#                                       f1600 round above.
# op.py:1952 hash                      -- PORTED: the chunk loop, as a SEQUENCE so
#                                       the trip count is checkable.
#                                       WALL: `pad_to`, `_hash_1mb`, `bitcast`.
# op.py:1971 nbytes                    -- PORTED WHOLE.
#
# WHAT I NEED FROM THE OTHER HALF, named for the coordinator. None of it is in
# this file, and none of it is in `mixin/op.py`'s second half:
#   * `arange`            -- op.py:166, Side A. `_pre_scatter`, `interpolate`,
#                             `nonzero`, `qr`, `svd` all call it.
#   * `_pad_constant`     -- op.py:282, Side A. `_apply_ceil_mode`'s callers,
#                             `avg_pool2d`, `max_pool2d`, `conv2d`.
#   * `cat`               -- op.py:731, Side A. `keccak`'s pad mask.
#   * `_cumalu`           -- op.py:752, Side A. `masked_select`.
#   * `sort`              -- op.py:913, Side A. `topk` (Side A), `svd`.
#   * `eye`               -- op.py:215, Side A. `qr`, `svd`.
#   * `_resolve_dim`      -- movement.py:81, NOT op.py. `gather`, `scatter`,
#                             `_one_hot_along_dim` all need it and it is a
#                             different unit's file.
#   * `_pool`             -- movement.py:598, NOT op.py. Its OUTPUT SHAPE
#                             (`o_` at movement.py:604 and `f_` at :606) is what
#                             `conv2d`'s `oyx` and the pooling methods need, and
#                             it is the one thing in this half I could not even
#                             approximate without re-deriving another unit's def.

# ---------------------------------------------------------------------------
# THE `TODO(p3)` INDEX, one line per wall so `rg 'TODO\(p3\)'` finds every one.
# The prose reasons are in THE WALLS above; this is the same list in the format
# the rest of the port uses.
# ---------------------------------------------------------------------------
# TODO(p3) mixin/op.py:998  allclose                 -- needs `isclose` + `all`
# TODO(p3) mixin/op.py:1005 _one_hot_along_dim       -- needs `eq`/`arange`/`reshape`
# TODO(p3) mixin/op.py:1010 one_hot                  -- needs `[..., None]` + `where`
# TODO(p3) mixin/op.py:1023 gather                   -- needs `shrink_to`/`where`/`sum`
# TODO(p3) mixin/op.py:1043 interpolate              -- needs `arange`/`clip`/`lerp`/`cast`
# TODO(p3) mixin/op.py:1077 _pre_scatter             -- needs `unsqueeze`/`expand`/`pad_to`
# TODO(p3) mixin/op.py:1095 scatter_reduce           -- needs `where`/`maximum` + the `_inv_mask` closure
# TODO(p3) mixin/op.py:1136 scatter                  -- needs `Tensor.full` + `_masked_merge`
# TODO(p3) mixin/op.py:1170 _masked_merge            -- `functools.reduce` over a zip of split tensors
# TODO(p3) mixin/op.py:1179 masked_select            -- `mask_cumsum[-1].item()` is a DATA READBACK
# TODO(p3) mixin/op.py:1208 nonzero                  -- needs `stack`/`masked_select`/`reshape`
# TODO(p3) mixin/op.py:1243 sequential               -- a `list[Callable]`; a `Type` is never copyable. BEND'S.
# TODO(p3) mixin/op.py:1254 linear                   -- needs `mul`/`dot`/`add`
# TODO(p3) mixin/op.py:1285 avg_pool2d               -- needs `_pad_constant`/`_pool`/`mean`
# TODO(p3) mixin/op.py:1333 max_pool2d               -- needs `_pool`/`commit_dtype().min`/`max`
# TODO(p3) mixin/op.py:1378 max_unpool2d             -- needs `reshape`/`_one_hot_along_dim`/`where`
# TODO(p3) mixin/op.py:1411 _apply_winograd_matrix   -- needs `transpose`/`const`; `mat` is a Tensor
# TODO(p3) mixin/op.py:1424 _conv2d_winograd         -- needs `pad`/`_pool`/`permute` + three F32 constant matrices
# TODO(p3) mixin/op.py:1464 image_dot                -- needs `transpose`/`reshape`/`image_conv2d`
# TODO(p3) mixin/op.py:1479 image_conv2d             -- needs the whole tensor path + `math.gcd` for `pad_align`
# TODO(p3) mixin/op.py:1562 conv2d                   -- needs `_pad_constant`/`_pool`/`permute`; `IMAGE`/`WINO` are ContextVars
# TODO(p3) mixin/op.py:1605 conv_transpose2d         -- needs `unflatten`/`flip`/`shrink_to` and `x.shape` between steps
# TODO(p3) mixin/op.py:1644 layernorm                -- needs `mean`/`rsqrt`
# TODO(p3) mixin/op.py:1662 batchnorm                -- needs `reshape`/`mul`/`add`
# TODO(p3) mixin/op.py:1686 _do_reduction            -- needs `sum`/`mean`
# TODO(p3) mixin/op.py:1692 binary_crossentropy      -- needs `log`
# TODO(p3) mixin/op.py:1706 binary_crossentropy_logits -- needs `logsigmoid`
# TODO(p3) mixin/op.py:1721 sparse_categorical_crossentropy -- needs `log_softmax`/`_one_hot_along_dim`
# TODO(p3) mixin/op.py:1746 cross_entropy            -- needs `log_softmax`/`mul`
# TODO(p3) mixin/op.py:1773 nll_loss                 -- needs `gather`/`const_like`/`ne`
# TODO(p3) mixin/op.py:1799 qr                       -- the Householder loop is `@` on Tensors
# TODO(p3) mixin/op.py:1817 svd                      -- the Jacobi sweeps + `sort`/`gather`/`contiguous`
# TODO(p3) mixin/op.py:1873 newton_schulz            -- `@` on Tensors + `reduce` over a generator
# TODO(p3) mixin/op.py:1892 keccak f1600              -- 64-bit rotate/xor over a 25-lane state. BEND'S.
# TODO(p3) mixin/op.py:1892 keccak rot_offsets_v0/v1  -- `1 << 63` does not fit a `U32`. BEND'S.
# TODO(p3) mixin/op.py:1946 _hash_1mb                -- needs the f1600 round above
# TODO(p3) mixin/op.py:1952 hash loop body           -- needs `pad_to`/`_hash_1mb`/`bitcast`
