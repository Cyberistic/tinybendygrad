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

def byte(+xs: List<&2, U32>, +i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, U32.to_nat(i)), 0)

def le2(+bs: List<&2, U32>, +i: U32) -> U32:
  U32.or(byte(bs, i), U32.shln(byte(bs, U32.add(i, 1)), 8n))

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

# one element. The association of each product is CPython's, left to right, because f32
# multiplication is not associative and the gate compares BITS.
def dec.el(+t: Typ, +bs: List<&2, U32>, lut: List<&2, U32>, +i: U32) -> F32:
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
        i32f(Maybe.default(&2, U32, List.get(&2, U32, lut, U32.to_nat(nib(bs, 2, i))), 0)))
    case TQ4K{}:
      +sub = U32.div(i, 32)
      +d = f16at(bs, 0)
      F32.sub(F32.mul(F32.mul(d, i32f(sc.at(bs, sub))),
                 i32f(U32.and(U32.shrn(
                   byte(bs, U32.add(16, U32.add(U32.mul(U32.div(sub, 2), 32), U32.mod(i, 32)))),
                   Nat.mul(U32.to_nat(U32.mod(sub, 2)), 4n)), 15))),
        F32.mul(f16at(bs, 2), i32f(mn.at(bs, sub))))

def dec.go(k: Nat, +i: U32, +t: Typ, +bs: List<&2, U32>, +lut: List<&2, U32>,
           acc: List<&2, F32>) -> List<&2, F32>:
  match k:
    case 0n: List.reverse(&2, F32, acc)
    case 1n+p: dec.go(p, U32.add(i, 1), t, bs, lut, dec.el(t, bs, lut, i) <> acc)

def dec.run(t: Typ, +bs: List<&2, U32>, +lut: List<&2, U32>, n: U32) -> List<&2, F32>:
  dec.go(U32.to_nat(n), 0, t, bs, lut, Nil{})

# the SEVEN `ggml_type`s this file decodes. Descending, because a `U32` literal arm is a
# prefix match over the successor relation (bend2-constraints' `mixin/rand` rule 2), and
# the gate reads every code 0..45 so a mis-ordered arm answers a neighbour and goes red.
def typ.of(typ: U32) -> Maybe<&1, Typ>:
  match typ:
    case 30: Some{TBF16{}}
    case 20: Some{TIQ4NL{}}
    case 12: Some{TQ4K{}}
    case 8: Some{TQ8_0{}}
    case 2: Some{TQ4_0{}}
    case 1: Some{TF16{}}
    case 0: Some{TF32{}}
    case _: None{}

def ggml.vgo(m: Maybe<&1, Typ>, n: U32, +bs: List<&2, U32>,
             lut: List<&2, U32>) -> Maybe<&1, List<&2, F32>>:
  match m:
    case None{}: None{}
    case Some{+t}: Some{dec.run(t, bs, lut, n)}

# `ggml_data_to_tensor(t, n, ggml_type)`'s VALUES, or `None` where CPython raises.
# `bs` is ONE block's bytes -- the caller slices them, which is the `Tensor` view this
# file deliberately does not do.
def ggml.dec(typ: U32, n: U32, +bs: List<&2, U32>,
             lut: List<&2, U32>) -> Maybe<&1, List<&2, F32>>:
  ggml.vgo(typ.of(typ), n, bs, lut)

# ---------------------------------------------------------------------------
# the two pieces of the GRID family that are pure, and the only two that ever needed
# `tinygrad.runtime.autogen.ggml_common`. Neither takes a constant from it.
# ---------------------------------------------------------------------------
def pc.go(k: Nat, +v: U32, acc: U32) -> U32:
  match k:
    case 0n: acc
    case 1n+p: pc.go(p, U32.shrn(v, 1n), U32.add(acc, U32.and(v, 1)))

def pc(v: U32) -> U32: pc.go(8n, v, 0)

def pc.odd(+v: U32) -> Bool: U32.is_eq(U32.mod(pc(v), 2), 1)

# `_ggml_iq_signs` (:16-17): 128 bytes, and byte `i` has its top bit set when `i` has an
# ODD number of set bits. This is a COMPUTATION in CPython and it is one here.
def iq.signs.go(k: Nat, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+p:
      iq.signs.go(p, U32.add(i, 1), Bool.pick(U32, pc.odd(i), U32.or(i, 128), i) <> acc)

def iq.signs() -> List<&2, U32>: iq.signs.go(128n, 0, Nil{})

# `_ggml_iq_grid` (:11-14) WITHOUT the device: the grid's `rows` entries arrive as two
# 32-bit WORDS each (that is why :13 splits on 32, and why a `U32` cannot hold one entry),
# and the answer is the `rows * 8` byte table that `.bitcast(uint8).float()` produces.
def iq.gbyte(+w0: U32, +w1: U32, +c: U32) -> U32:
  Bool.pick(U32, U32.is_lt(c, 4),
    U32.and(U32.shrn(w0, Nat.mul(U32.to_nat(c), 8n)), 255),
    U32.and(U32.shrn(w1, Nat.mul(U32.to_nat(U32.sub(c, 4)), 8n)), 255))

def iq.grid.go(k: Nat, +i: U32, +g: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+p:
      +r = U32.mul(U32.div(i, 8), 2)
      iq.grid.go(p, U32.add(i, 1), g,
        iq.gbyte(byte(g, r), byte(g, U32.add(r, 1)), U32.mod(i, 8)) <> acc)

def iq.grid(rows: U32, +g: List<&2, U32>) -> List<&2, U32>:
  iq.grid.go(U32.to_nat(U32.mul(rows, 8)), 0, g, Nil{})
