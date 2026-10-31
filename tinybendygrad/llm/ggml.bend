import Base
import ./../base.bend as F
import ./../dtype.bend as DT
import ./../helpers.bend as H
import ./gguf.bend as G

# ===========================================================================
# llm/ggml.bend -- `ggml_data_to_tensor`'s DECODE (gguf.py:29-185), as VALUES.
#
# WHY THIS IS A SECOND FILE AND NOT MORE OF `gguf.bend`. It is the same upstream file,
# but `gguf.bend` is 24,915 bytes and the interpreter's per-file byte cliff is 28,987
# (bend2-constraints), so the quant decode cannot live there.
#
# WHY IT IS NOT A `Tensor`. MEASURED, and it is the whole finding: `ggml_data_to_tensor`
# touches `Tensor` in exactly ONE way -- it builds one. Every ladder in :42-184 is
# `bitcast` (a byte reinterpretation), `-`, `*`, `>>`, `&`, `where`, `reshape`/`transpose`
# and a GRID INDEX. So the decode is arithmetic over bytes and the Tensor is only the
# container it is written into. This file answers `List<&2, F32>` -- the decoded VALUES,
# which is what `Tensor.tolist()` hands back -- and constructs nothing.
#
# THEREFORE THE GRIDS ARE ARGUMENTS. `_ggml_iq_grid` (:11-14) and `_ggml_iq_signs`
# (:16-17) are the only two things that came from `tinygrad.runtime.autogen.ggml_common`,
# and NEITHER IS A TABLE HERE: `iq.grid` takes the grid's words as a parameter and
# `iq.signs` COMPUTES its 128 bytes, exactly as :17 does. So a caller that one day has
# the grids can pass them, and this file never needed the 413K-line module.
#
# PORTED, ONE ARM PER `ggml_type`, and the gate compares all of them against CPython's
# `Tensor.tolist()` on the same bytes: 0 float32, 1 float16, 2 Q4_0, 8 Q8_0, 12 Q4_K,
# 20 IQ4_NL, 30 bfloat16. NOT PORTED, and each is the same `iq.grid`+`iq.signs`+index
# arithmetic rather than a wall: 3 Q4_1, 6 Q5_0, 7 Q5_1, 10 Q2_K, 11 Q3_K, 13 Q5_K,
# 14 Q6_K, 16 IQ2_XXS, 17 IQ2_XS, 18 IQ3_XXS, 19 IQ1_S, 21 IQ3_S, 22 IQ2_S, 23 IQ4_XS,
# 29 IQ1_M, 39 MXFP4, 41 Q1_0. They answer `None` here and the gate has a row for that.
#
# AND THE BRIEF'S OWN FACT IS WRONG, MEASURED: `Q4_K` (:79-87) and `Q6_K` (:88-92) are NOT
# grid quants. Neither body mentions `_ggml_iq_grid`; they are arithmetic over 6-bit
# sub-block scales. The GRID family is the `IQ*` ones (:93-170), and `IQ4_NL` (:131-133)
# is the cheapest member: its whole grid is the sixteen-entry `kvalues_iq4nl`, which is
# why it is the one ported here.
# ===========================================================================

# one `ggml_type`'s element rule, as a tag. `ggml_data_to_tensor` dispatches on the int;
# a `Data` tag keeps the dispatch out of a `U32` arm ladder inside the loop body.
type Typ is Data:
  TF32{}
  TF16{}
  TBF16{}
  TQ4_0{}
  TQ8_0{}
  TQ4K{}
  TIQ4NL{}
  TQ4XS{}
  TQ1S{}
  TQ2X{}
  TQ3X{}
  TQ2XS{}
  TQ4_1{}
  TQ5_0{}
  TQ5_1{}
  TQ2K{}
  TQ3K{}
  TQ5K{}
  TQ6K{}
  TMXFP4{}
  TQ1_0{}
  TQ3S{}
  TQ2S{}
  TQ1M{}

# THE GRID FAMILY'S DATA, AS ARGUMENTS. `tinybendygrad/runtime/autogen/ggml_common.bend`
# is where a caller gets them -- generated from `tinygrad.runtime.autogen.ggml_common` by
# `ggml_common-gen.py` -- and nothing here imports it, so this file still ships no data.
# `sgn` is `iq.signs()`, computed rather than tabulated, so it costs the caller one call.
type Gs is Data:
  Gs{lut: List<&2, U32>, iq1s: List<&2, U32>, iq2xxs: List<&2, U32>, iq2xs: List<&2, U32>,
     iq3xxs: List<&2, U32>, iq3s: List<&2, U32>, iq2s: List<&2, U32>, sgn: List<&2, U32>}

def Gs.lut(x: Gs) -> List<&2, U32>:
  match x:
    case Gs{lut, _, _, _, _, _, _, _}: lut

def Gs.iq1s(x: Gs) -> List<&2, U32>:
  match x:
    case Gs{_, iq1s, _, _, _, _, _, _}: iq1s

def Gs.iq2xxs(x: Gs) -> List<&2, U32>:
  match x:
    case Gs{_, _, iq2xxs, _, _, _, _, _}: iq2xxs

def Gs.iq3xxs(x: Gs) -> List<&2, U32>:
  match x:
    case Gs{_, _, _, _, iq3xxs, _, _, _}: iq3xxs

def Gs.iq2xs(x: Gs) -> List<&2, U32>:
  match x:
    case Gs{_, _, _, iq2xs, _, _, _, _}: iq2xs

def Gs.iq3s(x: Gs) -> List<&2, U32>:
  match x:
    case Gs{_, _, _, _, _, iq3s, _, _}: iq3s

def Gs.iq2s(x: Gs) -> List<&2, U32>:
  match x:
    case Gs{_, _, _, _, _, _, iq2s, _}: iq2s

def Gs.sgn(x: Gs) -> List<&2, U32>:
  match x:
    case Gs{_, _, _, _, _, _, _, sgn}: sgn

def byte(+xs: List<&2, U32>, +i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(i)), 0)

def le2(+bs: List<&2, U32>, +i: U32) -> U32:
  U32.or(byte(bs, i), U32.shln(byte(bs, U32.add(i, 1)), 8n))

def le4.at(+bs: List<&2, U32>, +i: U32) -> U32:
  G.le4(byte(bs, i), byte(bs, U32.add(i, 1)), byte(bs, U32.add(i, 2)),
    byte(bs, U32.add(i, 3)))

# `blocks[:,i:i+2].bitcast(float16).cast(float32)` -- the f16 pair, widened by the
# port's own `DT.fp16_f32` (a dtype.bend primitive, not a second decoder).
def f16at(+bs: List<&2, U32>, i: U32) -> F32:
  F.F32.from_bits(DT.fp16_f32(le2(bs, i)))

# bfloat16 is the TOP HALF of an f32, so its widening is a shift and nothing else.
def bf16at(+bs: List<&2, U32>, i: U32) -> F32:
  F.F32.from_bits(U32.shln(le2(bs, i), 16n))

# an int8/int16 field widened to f32. `U32.to_f32` is NUMERIC and would answer 250 for
# a -6 stored as 0xFA, so the sign decides.
def i32f(+v: U32) -> F32:
  Bool.pick(F32, H.i32_is_neg(v), F32.neg(U32.to_f32(U32.sub(0, v))), U32.to_f32(v))

# `q_to_uint8(blocks[:,base:], 4)` -- :45-48. The 16 bytes become 32 values with the LOW
# nibbles first and the HIGH nibbles after, because that is what `.transpose(-1,-2)`
# produces on a `(1, 16, 2)` view. MEASURED against CPython: `e0,e1,e16,e17` of a
# `0x10, 0x20` block are `-8, -8, -7, -6`.
def nib(+bs: List<&2, U32>, base: U32, +j: U32) -> U32:
  U32.and(U32.shrn(byte(bs, U32.add(base, U32.mod(j, 16))),
    Nat.mul(U32.to_nat(U32.div(j, 16)), 4n)), 15)

# `s[:,0:4] & 63` and `(s[:,8:12] & 0xF) | ((s[:,0:4] >> 6) << 4)` -- :82.
def sc.at(+bs: List<&2, U32>, +sub: U32) -> U32:
  Bool.pick(U32, U32.is_lt(sub, 4),
    U32.and(byte(bs, U32.add(4, sub)), 63),
    U32.or(U32.and(byte(bs, U32.add(12, U32.sub(sub, 4))), 15),
      U32.shln(U32.shrn(byte(bs, U32.add(4, U32.sub(sub, 4))), 6n), 4n)))

# `s[:,4:8] & 63` and `(s[:,8:12] >> 4) | ((s[:,4:8] >> 6) << 4)` -- :83.
def mn.at(+bs: List<&2, U32>, +sub: U32) -> U32:
  Bool.pick(U32, U32.is_lt(sub, 4),
    U32.and(byte(bs, U32.add(8, sub)), 63),
    U32.or(U32.shrn(byte(bs, U32.add(12, U32.sub(sub, 4))), 4n),
      U32.shln(U32.shrn(byte(bs, U32.add(8, U32.sub(sub, 4))), 6n), 4n)))

# `_ggml_iq_grid` (:11-14) WITHOUT the device -- the grid's `rows` entries arrive as two
# 32-bit WORDS each (that is why :13 splits on 32, and why a `U32` cannot hold one entry),
# and byte `c` of an entry is `w0` when `c < 4` and `w1` otherwise.
def iq.gbyte(+w0: U32, +w1: U32, +c: U32) -> U32:
  Bool.pick(U32, U32.is_lt(c, 4),
    U32.and(U32.shrn(w0, Nat.mul(U32.to_nat(c), 8n)), 255),
    U32.and(U32.shrn(w1, Nat.mul(U32.to_nat(U32.sub(c, 4)), 8n)), 255))

# `wpe` is words per entry: `gguf.py:13`'s split gives TWO for an eight-byte grid and ONE
# for a four-byte one, because `range(0, 8*grid_shape[1], 32)` runs once when the width is
# four. The SECOND word's index is `b + (wpe - 1)`, which is `b` when there is one word and
# is never read then: byte `c` past 3 only exists when `wpe` is 2.
def gw(+e: U32, +wpe: U32, +g: List<&2, U32>, +c: U32) -> U32:
  +b = U32.mul(e, wpe)
  iq.gbyte(byte(g, b), byte(g, U32.add(b, U32.sub(wpe, 1))), c)

# ---------------------------------------------------------------------------
# the remaining families' shared reads
#
# `bit.at` is `q_to_uint8(x, 1)`: `transpose(-1,-2)` makes the output order
# BYTE-MAJOR THEN BIT, so element `e` is bit `e % 8` of byte `base + e // 8`. That is the
# order Q5_0/Q5_1, Q3_K, Q1_0 and every sign bitmap use, and it is why none of them needs
# the reshape the Python writes.
# ---------------------------------------------------------------------------
def bit.at(+bs: List<&2, U32>, +base: U32, +e: U32) -> U32:
  U32.and(U32.shrn(byte(bs, U32.add(base, U32.div(e, 8))), U32.to_nat(U32.mod(e, 8))), 1)

# `[(v >> (2*pair)) & 3]` -- the two-bit read Q2_K and Q3_K index their 64 payload bytes with
def pair.at(+bs: List<&2, U32>, +base: U32, +byte_i: U32, +pair: U32) -> U32:
  U32.and(U32.shrn(byte(bs, U32.add(base, byte_i)), Nat.mul(U32.to_nat(pair), 2n)), 3)

# Q2_K and Q3_K share their payload geometry: `reshape((-1,2,32))`, four two-bit pairs per
# byte, so element `e` sits in sub-block `e/16` at column `e%16`, and the byte it reads is
# `(i/8)*32 + (i%2)*16 + j` -- MEASURED by agreement, twice, on two different bases.
def pk2.byte(+i: U32, +j: U32) -> U32:
  U32.add(U32.add(U32.mul(U32.div(i, 8), 32), U32.mul(U32.mod(i, 2), 16)), j)

def pk2.pair(+i: U32) -> U32:
  U32.div(U32.mod(i, 8), 2)

# `stack([sl & 0xF, sl >> 4], dim=2)` over `sl = blocks[:,4:8]` -- the SAME interleave
# `q4xs.sc` learned the hard way: sub `i` reads byte `4 + i/2`, low half when `i` is even.
def sc2.at(+bs: List<&2, U32>, +base: U32, +sub: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.mod(sub, 2), 0),
    U32.and(byte(bs, U32.add(base, U32.div(sub, 2))), 15),
    U32.shrn(byte(bs, U32.add(base, U32.div(sub, 2))), 4n))

# Q3_K's twelve bytes of 6-bit scales: `lo` from the LOW nibbles of bytes 96..103 and `hi`
# from the two-bit pairs of bytes 104..107, and the pair for entry `n` is `n/4`.
def q3k.sc(+bs: List<&2, U32>, +n: U32) -> U32:
  +lo = nib(bs, 96, U32.add(U32.mul(U32.div(n, 8), 16), U32.mod(n, 8)))
  +hi = pair.at(bs, 104, U32.mod(n, 4), U32.div(n, 4))
  U32.sub(G.sc.sx8(U32.or(lo, U32.shln(hi, 4n))), 32)

# MXFP4's 16-entry code table (:176-178), as the MAGNITUDES; the sign is `code >= 8` and
# `F32.neg(0.0)` is -0.0, which is exactly the entry at index 8.
def mx.lut(+c: U32) -> F32:
  match c:
    case 7: 12.0
    case 6: 8.0
    case 5: 6.0
    case 4: 4.0
    case 3: 3.0
    case 2: 2.0
    case 1: 1.0
    case _: 0.0

# MXFP4's shared exponent (:171-174): byte 0 IS the f32 exponent, 0 and 1 are the two
# subnormals, and every other value is `(e - 1) << 23` with `U32` wrap.
def mx.d(+bs: List<&2, U32>) -> F32:
  +e = byte(bs, 0)
  F.F32.from_bits(Bool.pick(U32, U32.is_lt(e, 2),
    Bool.pick(U32, U32.is_eq(e, 0), 2097152, 4194304),
    U32.mul(U32.sub(e, 1), 8388608)))

# Q5_K's fifth bit: `q_to_uint8(blocks[:,16:48], 1).reshape((-1,8,32))` puts the BIT in the
# sub-block slot and the BYTE in the `k` slot, so element `e` reads bit `e/32` of byte
# `16 + e%32`.
def q5k.qh(+bs: List<&2, U32>, +e: U32) -> U32:
  U32.and(U32.shrn(byte(bs, U32.add(16, U32.mod(e, 32))), U32.to_nat(U32.div(e, 32))), 1)

# Q6_K's low nibble: 128 bytes, TWO nibbles each, and the halves are `(e%128)/64` -- the
# low halves of all 64 bytes of a group, then the high ones.
def q6k.xl(+bs: List<&2, U32>, +e: U32) -> U32:
  +b = U32.add(U32.mul(U32.div(e, 128), 64), U32.mod(e, 64))
  Bool.pick(U32, U32.is_eq(U32.div(U32.mod(e, 128), 64), 0),
    U32.and(byte(bs, b), 15), U32.shrn(byte(bs, b), 4n))

# Q6_K's high TWO bits: 64 bytes, four pairs each, and `reshape((-1,8,32))` keeps the pair
# in the sub-block slot, so `e` reads pair `(e%128)/32` of byte `128 + (e/128)*32 + e%32`.
def q6k.xh(+bs: List<&2, U32>, +e: U32) -> U32:
  pair.at(bs, 128, U32.add(U32.mul(U32.div(e, 128), 32), U32.mod(e, 32)),
    U32.div(U32.mod(e, 128), 32))

# IQ1_M's sixteen 3-bit scales: `(sc16[j] >> 3*m) & 7` with `j = (2*s + a) / 4`,
# `m = (2*s + a) % 4`, which is what `reshape((-1,8,2,1,1))` does to the (4,4) broadcast.
def q1m.sc(+bs: List<&2, U32>, +s: U32, +a: U32) -> U32:
  +fl = U32.add(U32.mul(s, 2), a)
  U32.and(U32.shrn(le2(bs, U32.add(48, U32.mul(U32.div(fl, 4), 2))),
    Nat.mul(U32.to_nat(U32.mod(fl, 4)), 3n)), 7)

# IQ1_M's f16 scale, reassembled from the four top nibbles of the four uint16s (:159-162)
def q1m.d(+bs: List<&2, U32>) -> F32:
  F.F32.from_bits(DT.fp16_f32(
    U32.or(U32.or(U32.shrn(U32.and(le2(bs, 48), 61440), 12n),
                  U32.shrn(U32.and(le2(bs, 50), 61440), 8n)),
           U32.or(U32.shrn(U32.and(le2(bs, 52), 61440), 4n),
                  U32.and(le2(bs, 54), 61440)))))

# IQ1_M's `qh_n[t]`: `stack([low nibbles, high nibbles], dim=-1)` per byte, so `t` is
# byte `t/2` and the low half when `t` is even.
def q1m.qh(+bs: List<&2, U32>, +t: U32) -> U32:
  +b = byte(bs, U32.add(32, U32.div(t, 2)))
  Bool.pick(U32, U32.is_eq(U32.mod(t, 2), 0), U32.and(b, 15), U32.shrn(b, 4n))

# IQ1_M's grid row: the payload byte plus the THREE low bits of `qh_n`, and `iq1s_grid` has
# 2048 rows, so the index is bounded by 255 + 7*256 = 2047 = the last row. MEASURED, not
# inferred: `q < 2048` for every payload byte and every `qh_n`.
def q1m.qi(+bs: List<&2, U32>, +t: U32) -> U32:
  U32.add(byte(bs, t), U32.shln(U32.and(q1m.qh(bs, t), 7), 8n))

def q3k.hm(+bs: List<&2, U32>, +e: U32) -> U32:
  U32.and(U32.shrn(byte(bs, U32.mod(e, 32)), U32.to_nat(U32.div(e, 32))), 1)

# the `(grid > 127).where(grid - 256, grid)` reinterpretation, shared by IQ1_S and IQ1_M
def sx.grid(+v: U32) -> U32:
  Bool.pick(U32, U32.is_ge(v, 128), U32.sub(v, 256), v)

# ---------------------------------------------------------------------------
# IQ4_XS (:148-156), 256 elements per 136-byte block. Its LUT is `kvalues_iq4nl`, so it is
# the grid-family member with no grid.
# ---------------------------------------------------------------------------
# `(scales_l | (scales_h << 4)).bitcast(int8) - 32`: the byte is REINTERPRETED as int8
# before the 32 is subtracted, so 0x80 is -160 and not 96.
# `stack([sl & 0xF, sl >> 4], dim=2)` over `sl = blocks[:,4:8]`: the LOW nibbles and the
# HIGH ones INTERLEAVE per byte -- (s0&F), (s0>>4), (s1&F), (s1>>4), ... -- so sub `i`
# reads byte `4 + i/2` and takes the low half when `i` is even. MEASURED: the oracle
# caught the low-half-for-0..3 reading on its first run, 192 of 256 values wrong.
def q4xs.sc(+bs: List<&2, U32>, +sub: U32) -> U32:
  +lo = Bool.pick(U32, U32.is_eq(U32.mod(sub, 2), 0),
    U32.and(byte(bs, U32.add(4, U32.div(sub, 2))), 15),
    U32.shrn(byte(bs, U32.add(4, U32.div(sub, 2))), 4n))
  +hi = U32.and(U32.shrn(le2(bs, 2), Nat.mul(U32.to_nat(sub), 2n)), 3)
  U32.sub(G.sc.sx8(U32.or(lo, U32.shln(hi, 4n))), 32)

# `stack([qs & 0xF, qs >> 4], dim=2)` over eight 16-byte sub-blocks: LOW nibbles first.
def q4xs.q(+bs: List<&2, U32>, +i: U32) -> U32:
  +k = U32.mod(i, 32)
  +b = U32.add(8, U32.add(U32.mul(U32.div(i, 32), 16), U32.mod(k, 16)))
  Bool.pick(U32, U32.is_lt(k, 16), U32.and(byte(bs, b), 15), U32.shrn(byte(bs, b), 4n))

# ---------------------------------------------------------------------------
# IQ1_S (:121-130), 256 elements per 50-byte block. One grid, no signs; the grid bytes are
# INT8 and `(grid > 127).where(grid - 256, grid)` is the reinterpretation.
# ---------------------------------------------------------------------------
def q1s.qh(+bs: List<&2, U32>, +s: U32) -> U32:
  le2(bs, U32.add(34, U32.mul(s, 2)))

# `d * ((qh >> 12 & 7) * 2 + 1)`, and the +1 is f32 addition in CPython, not an int one
def q1s.dl(+bs: List<&2, U32>, +s: U32) -> F32:
  F32.mul(f16at(bs, 0),
    F32.add(F32.mul(i32f(U32.and(U32.shrn(q1s.qh(bs, s), 12n), 7)), 2.0), 1.0))

# `(qh & 0x8000) == 0` chooses the sign of the 0.125 delta
def q1s.delta(+bs: List<&2, U32>, +s: U32) -> F32:
  Bool.pick(F32, U32.is_eq(U32.and(q1s.qh(bs, s), 32768), 0), 0.125, F32.neg(0.125))

# `q[i]` = the payload byte plus three bits of `qh`, which is what makes it a 0..2047 row
def q1s.qi(+bs: List<&2, U32>, +i: U32) -> U32:
  +s = U32.div(i, 4)
  +j = U32.mul(U32.mod(i, 4), 3)
  U32.add(byte(bs, U32.add(2, i)),
    U32.shln(U32.and(U32.shrn(q1s.qh(bs, s), U32.to_nat(j)), 7), 8n))

def q1s.gv(+bs: List<&2, U32>, +g: List<&2, U32>, +i: U32) -> U32:
  +sub = U32.div(i, 32)
  +c = U32.div(U32.mod(i, 32), 8)
  +b = gw(q1s.qi(bs, U32.add(U32.mul(sub, 4), c)), 2, g, U32.mod(i, 8))
  Bool.pick(U32, U32.is_ge(b, 128), U32.sub(b, 256), b)

# ---------------------------------------------------------------------------
# IQ2_XXS (:101-110), 256 elements per 66-byte block: eight groups of 32, and each group
# is FOUR grid rows (one byte each) times EIGHT sign bits.
# ---------------------------------------------------------------------------
def q2x.w(+bs: List<&2, U32>, +sub: U32) -> U32:
  le4.at(bs, U32.add(6, U32.mul(sub, 8)))

# `d * ((q >> 28) + 0.5) * 0.25`, left to right
def q2x.db(+bs: List<&2, U32>, +sub: U32) -> F32:
  F32.mul(F32.mul(f16at(bs, 0),
    F32.add(i32f(U32.shrn(q2x.w(bs, sub), 28n)), 0.5)), 0.25)

# one sign, from bit `k` of `_ggml_iq_signs[(q >> 7*j) & 0x7F]`: a ZERO bit is +1
def sign.bit(+sgn: List<&2, U32>, +sb: U32, +k: U32) -> F32:
  Bool.pick(F32, U32.is_eq(U32.and(U32.shrn(byte(sgn, sb), U32.to_nat(k)), 1), 0), 1.0,
    F32.neg(1.0))

def q2x.sg(+gs: Gs, +bs: List<&2, U32>, +i: U32) -> F32:
  +sub = U32.div(i, 32)
  +c = U32.div(U32.mod(i, 32), 8)
  sign.bit(Gs.sgn(gs), U32.and(U32.shrn(q2x.w(bs, sub), U32.to_nat(U32.mul(c, 7))), 127),
    U32.mod(i, 8))

# the grid row is the payload BYTE at (group, c), five of the eight being skipped
def q2x.row(+bs: List<&2, U32>, +i: U32) -> U32:
  byte(bs, U32.add(2, U32.add(U32.mul(U32.div(i, 32), 8), U32.div(U32.mod(i, 32), 8))))

# ---------------------------------------------------------------------------
# IQ3_XXS (:93-100), 256 elements per 98-byte block: 64 payload bytes are 64 grid rows of
# FOUR, so the grid index is `e // 4` and the byte within a row is `e % 4`.
# ---------------------------------------------------------------------------
def q3x.w(+bs: List<&2, U32>, +sub: U32) -> U32:
  le4.at(bs, U32.add(66, U32.mul(sub, 4)))

def q3x.db(+bs: List<&2, U32>, +sub: U32) -> F32:
  F32.mul(F32.mul(f16at(bs, 0),
    F32.add(i32f(U32.shrn(q3x.w(bs, sub), 28n)), 0.5)), 0.5)

def q3x.sg(+gs: Gs, +bs: List<&2, U32>, +i: U32) -> F32:
  +sub = U32.div(i, 32)
  +j = U32.mod(U32.div(i, 8), 4)
  sign.bit(Gs.sgn(gs), U32.and(U32.shrn(q3x.w(bs, sub), U32.to_nat(U32.mul(j, 7))), 127),
    U32.mod(i, 8))

# ---------------------------------------------------------------------------
# IQ2_XS (:111-119), 256 elements per 74-byte block: 32 uint16s, and each uint16 is BOTH
# a grid index (its low NINE bits into 512 rows) and a sign-byte selector (its top seven).
# ---------------------------------------------------------------------------
def q2xs.q(+bs: List<&2, U32>, +gi: U32) -> U32:
  le2(bs, U32.add(2, U32.mul(gi, 2)))

# `q_to_uint8(blocks[:,66:74].reshape((-1,8,1)), 4)`: eight scale bytes, LOW nibble first
def q2xs.sc(+bs: List<&2, U32>, +s: U32) -> U32:
  +b = byte(bs, U32.add(66, U32.div(s, 2)))
  Bool.pick(U32, U32.is_eq(U32.mod(s, 2), 0), U32.and(b, 15), U32.shrn(b, 4n))

def q2xs.db(+bs: List<&2, U32>, +s: U32) -> F32:
  F32.mul(F32.mul(f16at(bs, 0), F32.add(i32f(q2xs.sc(bs, s)), 0.5)), 0.25)

# one element. The association of each product is CPython's, left to right, because f32
# multiplication is not associative and the gate compares BITS.
def dec.el(+t: Typ, +bs: List<&2, U32>, +gs: Gs, +i: U32) -> F32:
  match t:
    case TF32{}:
      F.F32.from_bits(G.le4(byte(bs, U32.mul(i, 4)), byte(bs, U32.add(U32.mul(i, 4), 1)),
        byte(bs, U32.add(U32.mul(i, 4), 2)), byte(bs, U32.add(U32.mul(i, 4), 3))))
    case TF16{}: f16at(bs, U32.mul(i, 2))
    case TBF16{}: bf16at(bs, U32.mul(i, 2))
    case TQ4_0{}: F32.mul(i32f(U32.sub(nib(bs, 2, i), 8)), f16at(bs, 0))
    case TQ8_0{}: F32.mul(f16at(bs, 0), i32f(G.sc.sx8(byte(bs, U32.add(2, i)))))
    case TIQ4NL{}:
      F32.mul(f16at(bs, 0),
        i32f(Maybe.default(&2, U32, List.get(&2, U32, Gs.lut(gs), U32.to_nat(nib(bs, 2, i))), 0)))
    case TQ4K{}:
      +sub = U32.div(i, 32)
      +d = f16at(bs, 0)
      F32.sub(F32.mul(F32.mul(d, i32f(sc.at(bs, sub))),
                 i32f(U32.and(U32.shrn(
                   byte(bs, U32.add(16, U32.add(U32.mul(U32.div(sub, 2), 32), U32.mod(i, 32)))),
                   Nat.mul(U32.to_nat(U32.mod(sub, 2)), 4n)), 15))),
        F32.mul(f16at(bs, 2), i32f(mn.at(bs, sub))))
    case TQ4XS{}:
      F32.mul(F32.mul(f16at(bs, 0), i32f(q4xs.sc(bs, U32.div(i, 32)))),
        i32f(Maybe.default(&2, U32,
          List.get(&2, U32, Gs.lut(gs), U32.to_nat(q4xs.q(bs, i))), 0)))
    case TQ1S{}:
      F32.mul(q1s.dl(bs, U32.div(i, 32)),
        F32.add(i32f(q1s.gv(bs, Gs.iq1s(gs), i)), q1s.delta(bs, U32.div(i, 32))))
    case TQ2X{}:
      F32.mul(F32.mul(q2x.db(bs, U32.div(i, 32)),
        i32f(gw(q2x.row(bs, i), 2, Gs.iq2xxs(gs), U32.mod(i, 8)))),
        q2x.sg(gs, bs, i))
    case TQ2XS{}:
      # `db` is reshaped to `(-1, 16, 1, 1)` and the answer to `(-1, 16, 2, 8)`, so the
      # SCALE is per SIXTEEN elements -- not per thirty-two, which is what IQ2_XXS is.
      +s = U32.div(i, 16)
      +gi = U32.div(i, 8)
      F32.mul(F32.mul(q2xs.db(bs, s),
        i32f(gw(U32.and(q2xs.q(bs, gi), 511), 2, Gs.iq2xs(gs), U32.mod(i, 8)))),
        sign.bit(Gs.sgn(gs), U32.shrn(q2xs.q(bs, gi), 9n), U32.mod(i, 8)))
    case TQ3X{}:
      F32.mul(F32.mul(q3x.db(bs, U32.div(i, 32)),
        i32f(gw(byte(bs, U32.add(2, U32.div(i, 4))), 1, Gs.iq3xxs(gs), U32.mod(i, 4)))),
        q3x.sg(gs, bs, i))
    case TQ4_1{}:
      F32.add(F32.mul(i32f(nib(bs, 4, i)), f16at(bs, 0)), f16at(bs, 2))
    case TQ4XS{}:
      F32.mul(F32.mul(f16at(bs, 0), i32f(q4xs.sc(bs, U32.div(i, 32)))),
        i32f(Maybe.default(&2, U32,
          List.get(&2, U32, Gs.lut(gs), U32.to_nat(q4xs.q(bs, i))), 0)))
    case TQ5_0{}:
      +q5 = U32.add(nib(bs, 6, i), U32.shln(bit.at(bs, 2, i), 4n))
      F32.add(F32.mul(i32f(q5), f16at(bs, 0)), F32.mul(F32.neg(16.0), f16at(bs, 0)))
    case TQ5_1{}:
      +q6 = U32.add(nib(bs, 8, i), U32.shln(bit.at(bs, 4, i), 4n))
      F32.add(F32.mul(i32f(q6), f16at(bs, 0)), f16at(bs, 2))
    case TQ2K{}:
      +ii = U32.div(i, 16)
      +qc = pair.at(bs, 16, pk2.byte(ii, U32.mod(i, 16)), pk2.pair(ii))
      F32.sub(F32.mul(F32.mul(f16at(bs, 80), i32f(U32.and(byte(bs, ii), 15))), i32f(qc)),
        F32.mul(f16at(bs, 82), i32f(U32.shrn(byte(bs, ii), 4n))))
    case TQ3K{}:
      +ii = U32.div(i, 16)
      +qc = pair.at(bs, 32, pk2.byte(ii, U32.mod(i, 16)), pk2.pair(ii))
      F32.mul(F32.mul(f16at(bs, 108), i32f(q3k.sc(bs, ii))),
        i32f(U32.sub(U32.add(qc, U32.shln(q3k.hm(bs, i), 2n)), 4)))
    case TQ5K{}:
      +sub = U32.div(i, 32)
      +qc = U32.add(
        U32.and(U32.shrn(byte(bs, U32.add(48, U32.add(U32.mul(U32.div(sub, 2), 32), U32.mod(i, 32)))),
          Nat.mul(U32.to_nat(U32.mod(sub, 2)), 4n)), 15),
        U32.shln(q5k.qh(bs, i), 4n))
      F32.sub(F32.mul(F32.mul(f16at(bs, 0), i32f(sc.at(bs, sub))), i32f(qc)),
        F32.mul(f16at(bs, 2), i32f(mn.at(bs, sub))))
    case TQ6K{}:
      F32.mul(F32.mul(f16at(bs, 208),
          i32f(U32.sub(G.sc.sx8(U32.or(q6k.xl(bs, i), U32.shln(q6k.xh(bs, i), 4n))), 32))),
        i32f(G.sc.sx8(byte(bs, U32.add(192, U32.div(i, 16))))))
    case TMXFP4{}:
      +code = nib(bs, 1, i)
      +mag = Bool.pick(F32, U32.is_lt(code, 8), mx.lut(U32.mod(code, 8)),
        F32.neg(mx.lut(U32.mod(code, 8))))
      F32.mul(mag, mx.d(bs))
    case TQ1_0{}:
      F32.mul(f16at(bs, 0),
        Bool.pick(F32, U32.is_eq(bit.at(bs, 2, i), 1), 1.0, F32.neg(1.0)))
    case TQ3S{}:
      +s = U32.div(i, 32)
      +qi = U32.div(i, 4)
      +row = U32.add(byte(bs, U32.add(2, qi)),
        U32.shln(bit.at(bs, 66, U32.add(U32.mul(U32.div(qi, 8), 8), U32.mod(qi, 8))), 8n))
      F32.mul(F32.mul(F32.mul(f16at(bs, 0),
          F32.add(F32.mul(i32f(sc2.at(bs, 106, s)), 2.0), 1.0)),
          i32f(gw(row, 1, Gs.iq3s(gs), U32.mod(i, 4)))),
        Bool.pick(F32, U32.is_eq(bit.at(bs, 74, i), 0), 1.0, F32.neg(1.0)))
    case TQ2S{}:
      +s = U32.div(i, 16)
      +qi = U32.div(i, 8)
      +row = U32.add(byte(bs, U32.add(2, qi)),
        U32.shln(pair.at(bs, 66, U32.div(qi, 4), U32.mod(qi, 4)), 8n))
      +db = F32.mul(F32.mul(f16at(bs, 0),
        F32.add(i32f(nib(bs, 74, U32.add(U32.mul(U32.mod(s, 2), 16), U32.div(s, 2)))), 0.5)), 0.25)
      +sg = Bool.pick(F32, U32.is_eq(bit.at(bs, 34, i), 0), 1.0, F32.neg(1.0))
      F32.mul(F32.mul(db, i32f(gw(row, 2, Gs.iq2s(gs), U32.mod(i, 8)))), sg)
    case TQ1M{}:
      +t = U32.div(i, 8)
      +dl = F32.mul(q1m.d(bs),
        F32.add(F32.mul(i32f(q1m.sc(bs, U32.div(i, 32), U32.div(U32.mod(i, 32), 16))), 2.0), 1.0))
      F32.mul(dl, F32.add(i32f(sx.grid(gw(q1m.qi(bs, t), 2, Gs.iq1s(gs), U32.mod(i, 8)))),
        Bool.pick(F32, U32.is_eq(U32.and(q1m.qh(bs, t), 8), 0), 0.125, F32.neg(0.125))))

def dec.go(k: Nat, +i: U32, +t: Typ, +bs: List<&2, U32>, +gs: Gs,
           acc: List<&2, F32>) -> List<&2, F32>:
  match k:
    case 0n: List.reverse(&2, F32, acc)
    case 1n+p: dec.go(p, U32.add(i, 1), t, bs, gs, dec.el(t, bs, gs, i) <> acc)

def dec.run(t: Typ, +bs: List<&2, U32>, +gs: Gs, n: U32) -> List<&2, F32>:
  dec.go(U32.to_nat(n), 0, t, bs, gs, Nil{})

# the ELEVEN `ggml_type`s this file decodes. Descending, because a `U32` literal arm is a
# prefix match over the successor relation (bend2-constraints' `mixin/rand` rule 2), and
# the gate reads every code 0..45 so a mis-ordered arm answers a neighbour and goes red.
def typ.of(typ: U32) -> Maybe<&1, Typ>:
  match typ:
    case 41: Some{TQ1_0{}}
    case 39: Some{TMXFP4{}}
    case 30: Some{TBF16{}}
    case 29: Some{TQ1M{}}
    case 23: Some{TQ4XS{}}
    case 22: Some{TQ2S{}}
    case 21: Some{TQ3S{}}
    case 20: Some{TIQ4NL{}}
    case 19: Some{TQ1S{}}
    case 18: Some{TQ3X{}}
    case 17: Some{TQ2XS{}}
    case 16: Some{TQ2X{}}
    case 14: Some{TQ6K{}}
    case 13: Some{TQ5K{}}
    case 12: Some{TQ4K{}}
    case 11: Some{TQ3K{}}
    case 10: Some{TQ2K{}}
    case 8: Some{TQ8_0{}}
    case 7: Some{TQ5_1{}}
    case 6: Some{TQ5_0{}}
    case 3: Some{TQ4_1{}}
    case 2: Some{TQ4_0{}}
    case 1: Some{TF16{}}
    case 0: Some{TF32{}}
    case _: None{}

def ggml.vgo(m: Maybe<&1, Typ>, n: U32, +bs: List<&2, U32>,
             +gs: Gs) -> Maybe<&1, List<&2, F32>>:
  match m:
    case None{}: None{}
    case Some{+t}: Some{dec.run(t, bs, gs, n)}

# `ggml_data_to_tensor(t, n, ggml_type)`'s VALUES, or `None` where CPython raises.
# `bs` is ONE block's bytes -- the caller slices them, which is the `Tensor` view this
# file deliberately does not do -- and `gs` is the grid family's data.
def ggml.dec(typ: U32, n: U32, +bs: List<&2, U32>,
             +gs: Gs) -> Maybe<&1, List<&2, F32>>:
  ggml.vgo(typ.of(typ), n, bs, gs)

# ---------------------------------------------------------------------------
# `_ggml_iq_signs` (:16-17): 128 bytes, and byte `i` has its top bit set when `i` has an
# ODD number of set bits. This is a COMPUTATION in CPython and it is one here.
# ---------------------------------------------------------------------------
def pc.go(k: Nat, +v: U32, acc: U32) -> U32:
  match k:
    case 0n: acc
    case 1n+p: pc.go(p, U32.shrn(v, 1n), U32.add(acc, U32.and(v, 1)))

def pc(v: U32) -> U32: pc.go(8n, v, 0)

def pc.odd(+v: U32) -> Bool: U32.is_eq(U32.mod(pc(v), 2), 1)

def iq.signs.go(k: Nat, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+p:
      iq.signs.go(p, U32.add(i, 1), Bool.pick(U32, pc.odd(i), U32.or(i, 128), i) <> acc)

def iq.signs() -> List<&2, U32>: iq.signs.go(128n, 0, Nil{})

# the byte TABLE `_ggml_iq_grid` answers: `rows * wpe * 4` bytes, entry-major
def iq.grid.go(k: Nat, +i: U32, +wpe: U32, +g: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+p:
      +per = U32.mul(wpe, 4)
      iq.grid.go(p, U32.add(i, 1), wpe, g,
        gw(U32.div(i, per), wpe, g, U32.mod(i, per)) <> acc)

def iq.grid(rows: U32, +wpe: U32, +g: List<&2, U32>) -> List<&2, U32>:
  iq.grid.go(U32.to_nat(U32.mul(U32.mul(rows, wpe), 4)), 0, wpe, g, Nil{})
