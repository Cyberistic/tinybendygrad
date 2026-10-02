# ===========================================================================
# `_min_max` -- ops.py:1104-1163, the INTEGER INTERVAL OF A UOp.
#
# WHAT THIS IS. `self._min_max` is `(vmin, vmax)`: the smallest and largest value a
# node can take, used by `resolve` (ops.py:64) to decide a symbolic bool, by
# `shard_shape` (ops.py:461) to size a shard, and by `variable` (ops.py:1013) to
# decide whether a PARAM has bounds. It is a Kahn fold over the same arena as the
# other six properties, and it is answered HERE, on its own walk, for the reason the
# header gives: `_min_max` needs no shape, no device and no addrspace, and a node
# whose `_shape` this file defers (every RESHAPE, and UNSHARD) still HAS an interval.
# Folding it into `Derived` would have made every deferred shape defer its interval
# too, and `gap_ok` is the row that would have noticed.
#
# ===========================================================================
# THE WIDTH, AND IT IS NOT A CHOICE -- IT IS MEASURED.
#
# Python's ints are arbitrary precision, and `_min_max`'s bounds LEAVE int64 on real
# graphs. Measured by `.agents/slop/oracles/mm-range.py` over 21 tinygrad graphs:
#
#   graph      nodes   widest bound (bit length)   nodes with a bound past i64
#   --------   -----   ------------------------   ---------------------------
#   matmul       232            96                        21
#   conv         328            96                        24
#   sum          198            96                        13
#   arange        31            32                         0
#
# and the values past i64 are `dtypes.uint64.max` = 2**64-1 and `uint64.max << 10`.
# So the honest width is NOT 64 bits. Two facts decide what this port can do:
#
#   1. `U32.shrn`/`shln` and `Nat` are the runtime's only numbers, and `Nat` REFUSES
#      past 2**48-1 (`.agents/slop/notes/bend2-constraints.md`; `Nat.pow(2n,70n)`
#      prints "a Nat past the largest immediate 2^48-1"). A 65-bit value is not a
#      runtime number in Bend 2.0.34 at all.
#   2. `H.I64` is a HAND-ROLLED PAIR, so a magnitude wider than 2**64-1 is
#      expressible in principle and absent in practice.
#
# The port is therefore a SIGN BIT PLUS AN UNSIGNED 64-BIT MAGNITUDE, which covers
# [-2**63, 2**64-1] -- every dtype limit tinygrad has, INCLUDING `uint64.max`, which
# a signed I64 cannot hold. When an INTERMEDIATE leaves that window the answer is
# `PInf`/`NInf`, and that is not a fudge: a value at or beyond 2**64 is at or beyond
# every dtype limit, so widening to infinity is a sound OVER-APPROXIMATION and every
# consumer of `_min_max` asks a question an over-approximation still answers
# (`resolve` asks whether vmin is zero; `shard_shape` asks for a count).
#
# THE THREE BUGS THAT MATURED IN THE ARITHMETIC, all measured against CPython and
# all of them silent, since each produced a plausible number:
#   * `Bool.or(is_zero(lo), is_zero(hi))` reads as "the pair is zero" and is not --
#     it reads as "SOME word is zero", so 2**32 came out as a product of zero.
#   * the underflow test for an unsigned subtract is `a < b`, and NOT `result < a`;
#     the second is what an ADD overflows on and it is the wrong predicate here.
#   * in a 64x64 product `s` IS limb 1 and `u` IS limb 2, so the overflow test is
#     `u != 0 or t3.hi != 0`, and NOT `t3.hi + (u >> 32) != 0` (that sum wraps).
# ===========================================================================

type Bound is Data:
  NInf{}                       # below every representable value
  PInf{}                       # above every representable value
  Int{neg: Bool, mag: H.I64}   # exact integer: 0 <= mag <= 2**64-1
  Flt{bits: U32}               # an exact f32 image, as its IEEE bits

type MinMax is Data:
  MinMax{lo: Bound, hi: Bound}

def Bound.int(neg: Bool, mag: H.I64) -> Bound:
  Int{neg, mag}

def Bound.zero() -> Bound: Int{False{}, H.i64_of_hi_lo(0, 0)}

# ===========================================================================
# THE UNSIGNED 64-BIT CORE, on the `hi`/`lo` pair, overflow-ANSWERING. `None` is the
# overflow and every caller turns it into `PInf`/`NInf`, which is the ONE place this
# port knowingly differs from CPython and the difference is an over-approximation.
# ===========================================================================

def u64.of(ok: Bool, +hi: U32, +lo: U32) -> Maybe<&2, H.I64>:
  match ok:
    case True{}: Some{H.i64_of_hi_lo(hi, lo)}
    case False{}: None{}

def u64.lt(+eh: U32, el: U32, +fh: U32, fl: U32) -> Bool:
  Bool.or(U32.is_lt(eh, fh), Bool.and(U32.is_eq(eh, fh), U32.is_lt(el, fl)))

def u64.le(+eh: U32, el: U32, +fh: U32, fl: U32) -> Bool:
  Bool.or(U32.is_lt(eh, fh), Bool.and(U32.is_eq(eh, fh), U32.is_le(el, fl)))

def u64.eq(+eh: U32, el: U32, fh: U32, fl: U32) -> Bool:
  Bool.and(U32.is_eq(eh, fh), U32.is_eq(el, fl))

# "this pair is zero", which is what every overflow test asks. IT IS `and`: `or`
# answers true for (0, 5) as well as for (0, 0), and that is how 2**32 came out as a
# product of zero.
def u64.is_zero(+hi: U32, lo: U32) -> Bool:
  Bool.and(U32.is_zero(lo), U32.is_zero(hi))

def u64.is_one(+hi: U32, lo: U32) -> Bool:
  Bool.and(U32.is_zero(hi), U32.is_eq(lo, 1))

# the carry out of `U32.add`, which is its own overflow test
def u32c(+a: U32, b: U32) -> U32:
  Bool.pick(U32, U32.is_lt(U32.add(a, b), a), 1, 0)

def u64.add(+ah: U32, +al: U32, bh: U32, +bl: U32) -> Maybe<&2, H.I64>:
  +lo = U32.add(al, bl)
  +hi = U32.add(U32.add(ah, bh), u32c(al, bl))
  u64.of(Bool.not(u64.lt(hi, lo, ah, al)), hi, lo)

# WRAPPING, because restoring division needs `r - d` mod 2**64 and the borrow there
# is answered by the shift's own carried bit rather than by the subtraction.
def u64w.sub(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.sub(ah, U32.add(bh, u32c(bl, U32.sub(al, bl)))), U32.sub(al, bl))

# The underflow test is `a < b`, NOT `result < a`. The second is what an ADD
# overflows on and it is silently the wrong predicate for a subtraction: `0 - 2**32`
# wraps to a value GREATER than `a` and so reads as no underflow at all.
def u64.sub(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<&2, H.I64>:
  +lo = U32.sub(al, bl)
  +hi = U32.sub(ah, U32.add(bh, u32c(bl, U32.sub(al, bl))))
  u64.of(Bool.not(u64.lt(ah, al, bh, bl)), hi, lo)

# ---- MUL ---------------------------------------------------------------------
#
# A 64x64 product is 128 bits, so the answer is the HIGH word and every bit from
# 2**64 up is the overflow.
#
# THE LIMBS ARE 16 WIDE, and that is the whole trick. `U32.mul` wraps, so a 32x32
# product cannot be overflow-tested at all -- `U32.mul(a,b)/a == b` holds for a
# wrapped product of a particular size as readily as for an exact one. A 16x16
# product is BELOW 2**32, so `U32.mul` is exact on it, and the four partials
# accumulate with every column sum under 2**20 -- no wrap test anywhere in this
# section.
def u32x16(+x: U32) -> U32: U32.shrn(x, 16n)

def u32lo16(+x: U32) -> U32: U32.and(x, 65535)

# a*b = p0 + (p1+p2)*2**16 + p3*2**32 over 16-bit halves, which is the statement
# `u32m.wide`'s three `n` lines are.
def u32m.wide(+p0: U32, +p1: U32, +p2: U32, +p3: U32) -> H.I64:
  +n1 = U32.add(U32.add(u32lo16(p1), u32lo16(p2)), u32x16(p0))
  +n2 = U32.add(U32.add(U32.add(u32x16(p1), u32x16(p2)), u32lo16(p3)), u32x16(n1))
  +n3 = U32.add(u32x16(p3), u32x16(n2))
  H.i64_of_hi_lo(U32.or(u32lo16(n2), U32.shln(u32lo16(n3), 16n)),
    U32.or(u32lo16(p0), U32.shln(u32lo16(n1), 16n)))

def u32m(+a: U32, +b: U32) -> H.I64:
  u32m.wide(U32.mul(u32lo16(a), u32lo16(b)), U32.mul(u32lo16(a), u32x16(b)),
    U32.mul(u32x16(a), u32lo16(b)), U32.mul(u32x16(a), u32x16(b)))

# The 64x64 combination is THREE columns wide, so each is under 2**34 and cannot
# wrap either.
def u64.join(+t0: H.I64, +t1: H.I64, +t2: H.I64, +t3: H.I64) -> Maybe<&2, H.I64>:
  +s = U32.add(U32.add(H.hi32(t0), H.lo32(t1)), H.lo32(t2))
  +u = U32.add(U32.add(U32.add(H.hi32(t1), H.hi32(t2)), H.lo32(t3)), U32.shrn(s, 32n))
  # `s` IS LIMB 1 and `u` IS LIMB 2 -- the WORDS, not partial words -- so every bit
  # of `u` is already above 2**64 and the overflow test is `u != 0 or t3.hi != 0`.
  # It is NOT `t3.hi + (u >> 32) != 0`, which wraps a U32 and reads as zero for a
  # product that overflowed. Nor can `u << 32` build the high word: a U32 shift by
  # 32 SATURATES TO 0 (bend2-constraints, the `1 << 34` trap).
  u64.of(Bool.and(u64.is_zero(H.hi32(t3), 0), u64.is_zero(u, 0)),
    U32.or(U32.and(s, 4294967295), U32.shln(U32.and(u, 4294967295), 32n)),
    H.lo32(t0))

def u64.mul(+ah: U32, +al: U32, +bh: U32, +bl: U32) -> Maybe<&2, H.I64>:
  u64.join(u32m(al, bl), u32m(al, bh), u32m(ah, bl), u32m(ah, bh))

# ---- THE SHIFTS --------------------------------------------------------------
#
# `U32.shl` is a ONE-BIT shift and `U32.shln(x, n)` is the n-bit one, so every
# shift AMOUNT here is a `Nat` literal or a `Nat` difference. That is the whole of
# the rule bend2-constraints records: a bit-packer whose field positions are runtime
# values is UNWRITABLE. So the shift amounts below are `Nat`s derived from a
# countdown, and no amount is ever a `U32`.

def u64.shl(ah: U32, al: U32, k: Nat) -> Maybe<&2, H.I64>:
  u64.shl.go(k, ah, al, 0, 0)

def u64.shl.go(k: Nat, ah: U32, al: U32, th: U32, tl: U32) -> Maybe<&2, H.I64>:
  match k:
    case 0n: u64.of(Bool.not(u64.lt(th, tl, 0, 0)), th, tl)
    case 1n+p: u64.shl.ov(p, u64.shl.go(p, 0, U32.shrn(al, 31n),
      U32.shln(al, 1n), U32.or(U32.shln(th, 1n), U32.shrn(tl, 31n)), U32.shln(tl, 1n)))

def u64.shl.ov(k: Nat, m: Maybe<&2, H.I64>) -> Maybe<&2, H.I64>:
  match m:
    case None{}: None{}
    case Some{x}: x

def u64.shr(ah: U32, al: U32, k: Nat) -> H.I64:
  u64.shr.go(k, ah, al)

def u64.shr.go(k: Nat, ah: U32, al: U32) -> H.I64:
  match k:
    case 0n: H.i64_of_hi_lo(ah, al)
    case 1n+p: u64.shr.go(p, U32.shrn(ah, 1n), U32.or(U32.shrn(al, 1n), U32.shln(U32.and(ah, 1), 31n)))

# ---- THE BIT COUNT -----------------------------------------------------------
#
# `int(x).bit_length()` is the AND arm's mask width (ops.py:1110), and it is a COUNT
# not a value, so it is a `Nat` and the doubling below is the only way to get one.
def u64.blen(ah: U32, al: U32) -> Nat:
  u64.blen.go(ah, al, 0n, 0)

def u64.blen.go(ah: U32, al: U32, n: Nat, bits: Nat) -> Nat:
  match Bool.or(U32.is_zero(ah), U32.is_zero(al)):
    case True{}: n
    case False{}: u64.blen.go(U32.shrn(ah, 1n), U32.or(U32.shrn(al, 1n), U32.shln(U32.and(ah, 1), 31n)), Nat.add(n, 1n), bits)

# ---- BITWISE, on the two halves ------------------------------------------------

def u64.and(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.and(ah, bh), U32.and(al, bl))

def u64.or(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.or(ah, bh), U32.or(al, bl))

def u64.xor(ah: U32, al: U32, bh: U32, bl: U32) -> H.I64:
  H.i64_of_hi_lo(U32.xor(ah, bh), U32.xor(al, bl))

def u64.not(ah: U32, al: U32) -> H.I64:
  H.i64_of_hi_lo(U32.not(ah), U32.not(al))