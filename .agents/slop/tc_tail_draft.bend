# ===========================================================================
# THE ROW PRINTERS.
# ===========================================================================
def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# ===========================================================================
# THE ACCESSORS.  A `Maybe` is unwrapped EXPLICITLY and a miss answers a
# sentinel the gate SHOWS, never a default that would hide it.
# ===========================================================================

def tc.rdf(m: Maybe<&2, F32>) -> F32:
  match m:
    case Some{v}: v
    case None{}: F32.mul(2.0, 0.0)

def tc.rds(m: Maybe<&2, String>) -> String:
  match m:
    case Some{v}: v
    case None{}: String.read("MISSING")

def tc.rdu(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case None{}: 4294967295

# a decimal STRING to the binary32 it denotes.  This is `UOp.const`'s weak
# float, and it is why a coefficient can be carried as text at all.
def tc.f(s: String) -> F32: tc.rdf(F32.read(s))

def tc.b(s: String) -> U32: F32.bits(tc.f(s))

def tc.nat(i: U32) -> Nat: U32.to_nat(i)

def tc.nth(xs: List<&2, String>, i: U32) -> String:
  tc.rds(List.get(&2, String, xs, tc.nat(i)))

def tc.uth(xs: List<&2, U32>, i: U32) -> U32:
  tc.rdu(List.get(&2, U32, xs, tc.nat(i)))

def tc.ilen(xs: List<&2, String>) -> U32:
  tc.ilen.go(xs, 0, 4294967295)

def tc.ilen.go(xs: List<&2, String>, i: U32, n: Nat) -> U32:
  match xs n:
    case Nil{}: i
    case _ <> t: tc.ilen.go(t, U32.inc(i), Nat.succ(n))

# a fixture `"d_q"` splits at its ONLY underscore: neither the bases nor the
# exponents written in this file contain one, so there is no last-underscore
# problem here and no reason to solve one.
def tc.dq0(s: String) -> String:
  tc.rds(List.get(&2, String, String.split(&2, s, "_"), 0n))

def tc.dq1(s: String) -> String:
  tc.rds(List.get(&2, String, String.split(&2, s, "_"), 1n))

# ---------------------------------------------------------------------------
# INDEX -> VALUE and VALUE -> INDEX, and they are independent on purpose.  The
# fixture of the second is the BIT PATTERN, not the position: a mutated
# coefficient leaves the old pattern unfindable and the row answers 4294967295.
# Without that, one row wearing two hats would move for a single edit and read
# like two checks.
# ---------------------------------------------------------------------------
def tc.fv(xs: List<&2, String>, i: U32) -> U32: tc.b(tc.nth(xs, i))

def tc.vi(xs: List<&2, String>, b: U32, n: U32) -> U32:
  tc.vi.go(tc.nat(n), xs, b, 0, 4294967295)

def tc.vi.go(+n: Nat, xs: List<&2, String>, b: U32, i: U32, miss: U32) -> U32:
  match xs n:
    case Nil{}: miss
    case x <> t:
      match U32.is_eq(tc.b(x), b):
        case True{}: i
        case False{}: tc.vi.go(n, t, b, U32.inc(i), miss)

def tc.uvi(xs: List<&2, U32>, b: U32, n: U32) -> U32:
  tc.uvi.go(tc.nat(n), xs, b, 0, 4294967295)

def tc.uvi.go(+n: Nat, xs: List<&2, U32>, b: U32, i: U32, miss: U32) -> U32:
  match xs n:
    case Nil{}: miss
    case x <> t:
      match U32.is_eq(x, b):
        case True{}: i
        case False{}: tc.uvi.go(n, t, b, U32.inc(i), miss)

# ===========================================================================
# THE INTEGER RULES.  MEASURED by a spy on `shr`/`shl` in the audit oracle
# (`.agents/slop/tc-audit.txt` rows `shr[0].y` .. `shr[16].y`): ALL SEVENTEEN
# shift amounts tinygrad asks for in this file are PYTHON INTS, and every one of
# them is an INTEGER shift -- there is no float `shr` or `shl` anywhere.  So
# `tc.shr_u` is unsigned floor division and `tc.shr_i` is the signed FLOOR one
# that `ilogb2k` needs.
# ===========================================================================

# `U32.shl` is a ONE-BIT shift and `U32.shln(a, n)` is the n-bit one, so the
# shift AMOUNT has to be a `Nat` built from a runtime value.
def tc.pow2u(y: U32) -> U32: U32.shln(1, tc.nat(y))

# :20 `x * (2**y)`, wrapped -- `U32.mul` already wraps, and a y >= 32 gives 0,
# which is exactly what `x * 2**32 mod 2**32` is.
def tc.shl(x: U32, y: U32) -> U32: U32.mul(x, tc.pow2u(y))

def tc.isneg(x: U32) -> Bool: U32.is_ge(x, 2147483648)

def tc.neg(a: U32, b: U32) -> U32: U32.sub(0, b)

# :19 `x // (2**y)` on an UNSIGNED operand.
def tc.shr_u(x: U32, y: U32) -> U32: tc.halve(x, 0, y, 4294967295)

def tc.halve(x: U32, i: U32, y: U32, n: Nat) -> U32:
  match U32.is_ge(y, i):
    case True{}: U32.div(x, tc.pow2u(i))
    case False{}: tc.halve(x, U32.inc(i), y, Nat.succ(n))

# :19 on a SIGNED operand: FLOOR, not a truncating shift, so the
# `-1 <= ilog2bk(d) <= 128` claim at :36 survives a negative `dint`.
def tc.shr_i(x: U32, y: U32) -> U32: tc.shr_i.go(x, x, y, 0, 4294967295)

def tc.shr_i.go(+o: U32, +m: U32, y: U32, i: U32, n: Nat) -> U32:
  match U32.is_ge(y, i):
    case True{}:
      match U32.is_eq(i, 0):
        case True{}: o
        case False{}:
          match tc.isneg(o):
            case True{}: tc.neg(m, tc.halve(o, i, i, Nat.succ(n)))
            case False{}: tc.halve(o, i, i, Nat.succ(n))
    case False{}: tc.shr_i.go(o, m, y, U32.inc(i), Nat.succ(n))

# signed 32-bit add, kept in the U32 domain so the row is a bit pattern.
def tc.iadd(a: U32, b: U32) -> U32: U32.add(a, b)

# ===========================================================================
# THE FLOAT RULES.
# ===========================================================================
def tc.pick(c: Bool, a: F32, b: F32) -> F32:
  match c:
    case True{}: a
    case False{}: b

def tc.zero() -> F32: F32.mul(2.0, 0.0)
def tc.pinf() -> F32: tc.rdf(F32.read("inf"))
def tc.ninf() -> F32: tc.rdf(F32.read("-inf"))
def tc.qnan() -> F32: tc.rdf(F32.read("nan"))

# :25 `.cast(int32)`, which is C truncation TOWARD ZERO.  `F32.to_u32` refuses a
# negative, so the sign is carried out of the magnitude and put back on.
def tc.f2i(x: F32) -> U32:
  tc.f2i.go(F32.is_lt(x, tc.zero()), F32.to_u32(F32.trunc(F32.abs(x))))

def tc.f2i.go(neg: Bool, m: U32) -> U32:
  match neg:
    case True{}: tc.neg(0, m)
    case False{}: m

# the inverse, for the places `xexp2`/`xlog2` read a computed integer back as a
# float.  `U32.to_f32` is exact below 2**24 and every call site here is.
def tc.i2f(b: U32) -> F32:
  tc.i2f.go(tc.isneg(b), U32.to_f32(U32.and(b, 2147483647)))

def tc.i2f.go(neg: Bool, m: F32) -> F32:
  match neg:
    case True{}: F32.neg(m)
    case False{}: m

# `2**n` by DOUBLING, for a signed n held as a u32 bit pattern.  Exact for
# every n in [-126, 127], and no fixture crosses that range.
def tc.pow2f(n: U32) -> F32: tc.pow2f.go(tc.isneg(n), n, 1.0, 0, 4294967295)

def tc.pow2f.go(neg: Bool, +k: U32, +d: F32, i: U32, n: Nat) -> F32:
  match U32.is_ge(k, i):
    case True{}: tc.pow2f.go(neg, k, F32.mul(d, 2.0), U32.inc(i), Nat.succ(n))
    case False{}:
      match neg:
        case True{}: F32.div(1.0, d)
        case False{}: d

# ===========================================================================
# THE POLYNOMIALS.
# ===========================================================================

# `polyN(x, p) = reduce(lambda acc, c: acc*x + c, p, 0.0)` -- helpers.py:153.
# The SEED is the Python float `0.0`, so the first step really is `0.0*x + p[0]`
# and not `p[0]`.  At f32 with a finite x the two are the same number; the
# fixture that WOULD separate them is `x = inf`, and `xf_polyn32_inf` is it.
def tc.polyn(xs: List<&2, String>, x: F32) -> F32:
  tc.polyn.go(xs, tc.zero(), x, 4294967295)

def tc.polyn.go(xs: List<&2, String>, acc: F32, x: F32, n: Nat) -> F32:
  match xs n:
    case Nil{}: acc
    case y <> t:
      tc.polyn.go(t, F32.add(F32.mul(acc, x), tc.f(y)), x, Nat.succ(n))

# :150 `trig_poly`, :152 `sin_poly` -- `d * polyN(d*d, coeff)`.
def tc.sin_poly(d: F32) -> F32: F32.mul(d, tc.polyn(sp.sin32(), F32.mul(d, d)))

# :158 `(q & n).ne(0)`
def tc.ifand(q: U32, n: U32) -> Bool: Bool.not(U32.is_zero(U32.and(q, n)))

def tc.sign(c: Bool) -> F32:
  match c:
    case True{}: F32.neg(1.0)
    case False{}: 1.0

# :160-162 `sin_poly_small(d, q)`
def tc.sps(d: F32, q: U32) -> F32:
  F32.mul(tc.sin_poly(d), tc.sign(tc.ifand(q, 1)))

# :164-166 `sin_poly_large(d, q)`
def tc.spl(d: F32, q: U32) -> F32:
  F32.mul(tc.sin_poly(tc.pick(tc.ifand(q, 1), F32.add(d, tc.f(sp.pi_over_2())), d)),
          tc.sign(tc.ifand(q, 2)))

# ===========================================================================
# THE RANGE REDUCTION, :52-63 and :115-147.
# ===========================================================================

# :59 `shr(bits, mantissa_bits) & exponent_mask`
def tc.fe(v: F32) -> U32: U32.and(tc.shr_u(F32.bits(v), sp.mb_32()), sp.em_32())

# :62 `exponent - exponent_bias + 1`
def tc.fexp(v: F32) -> U32: tc.iadd(tc.fe(v), 1)

def tc.fexp2(v: F32) -> U32: tc.iadd(tc.iadd(tc.fexp(v), sp.eb_32()), 1)

# :61 `((bits & m1) | m2).bitcast(v.dtype)`, rebuilt from the fraction field.
def tc.frexp_word(v: F32) -> U32:
  U32.or(U32.and(F32.bits(v), sp.fm1_32()), sp.fm2_32())

def tc.frexp_mant(v: F32) -> F32:
  tc.frexp_mant.go(tc.isneg(F32.bits(v)),
                   F32.add(0.5, F32.mul(U32.to_f32(U32.and(F32.bits(v), sp.frac_mask())),
                                        tc.f(sp.two_m24()))))

def tc.frexp_mant.go(neg: Bool, m: F32) -> F32:
  match neg:
    case True{}: F32.neg(m)
    case False{}: m

# :32-37 `(shr(dint, mantissa_bits) & exponent_mask) - exponent_bias`
def tc.ilogb2k(d: F32) -> U32:
  U32.sub(U32.and(tc.shr_i(F32.bits(d), sp.mb_32()), sp.em_32()), sp.eb_32())

# :27-30 `pow2if`.  The value is 2**q by doubling; the gate compares its bit
# pattern against CPython's, which IS the `(q + bias) << 23` field.
def tc.pow2if(q: U32) -> F32: tc.pow2f(q)

def tc.pow2if_word(q: U32) -> U32: tc.shl(tc.iadd(q, sp.eb_32()), sp.mb_32())

# :47-50 `(d * pow2if(shr(e, 1))) * pow2if(e - shr(e, 1))`
def tc.ldexp2k(d: F32, e: U32) -> F32:
  F32.mul(F32.mul(d, tc.pow2if(tc.shr_i(e, 1))), tc.pow2if(tc.iadd(e, tc.shr_i(e, 1))))

# :39-45 `(m1 + (e << mantissa_bits)).bitcast(d.dtype)`; :43 is the field add.
def tc.ldexp3k_word(d: F32, e: U32) -> U32:
  U32.add(F32.bits(d), tc.shl(U32.and(e, 255), sp.mb_32()))

def tc.ldexp3k(d: F32, e: U32) -> F32: tc.pow2f(tc.iadd(tc.fexp2(d), e))

# A PAIR travels in one record because Bend will not destructure a computed
# product.  Same idiom as `Made` in `ops_webgpu.bend`.
type Red is Data:
  Red{r: F32, q: U32}

def Red.r(r: Red) -> F32:
  match r:
    case Red{a, b}: a

def Red.q(r: Red) -> U32:
  match r:
    case Red{a, b}: b

# :22-25 `(d + (d<0 ? -0.5 : 0.5)).cast(int32)` -- round AWAY from zero.
def tc.rintk(d: F32) -> U32:
  tc.f2i(tc.pick(F32.is_lt(d, tc.zero()), F32.sub(d, 0.5), F32.add(d, 0.5)))

# :138-141 the float32 arm of `_reduce_d`, left-associated, four times.
def tc.cw_reduce(x: F32, q: U32) -> F32:
  tc.cw_reduce.go(tc.i2f(q), sp.cw3(),
    tc.cw_reduce.go(tc.i2f(q), sp.cw2(),
      tc.cw_reduce.go(tc.i2f(q), sp.cw1(),
        tc.cw_reduce.go(tc.i2f(q), sp.cw0(), x)), x))

def tc.cw_reduce.go(qf: F32, c: String, acc: F32, x: F32) -> F32:
  F32.add(F32.mul(qf, tc.f(c)), acc)

# :145 `qdh`, DEAD for float32 and float16 -- only the float64 arm of
# `_reduce_d` reads it -- but BUILT unconditionally.  At f32 the int64 cast
# truncates it to zero for every fixture, so the value is 0.0.  `xf_cw_qdh_*`
# is the row that says so, and `xf_cw_qdh_scale` pins the division at :145.
def tc.qdh_scale() -> F32: F32.div(tc.f(sp.m_1_pi()), tc.f(sp.two_24()))

def tc.cw_qdh(x: F32) -> F32:
  tc.cw_qdh.go(F32.is_lt(x, tc.zero()),
               F32.to_u32(F32.trunc(F32.abs(F32.mul(x, tc.qdh_scale())))))

def tc.cw_qdh.go(neg: Bool, m: U32) -> F32:
  match neg:
    case True{}: F32.neg(U32.to_f32(m))
    case False{}: U32.to_f32(m)

# :146 `rintk(d * m_1_pi)` -- the float32 arm, since `d.dtype != float64`.
def tc.cw_quadrant(x: F32) -> U32: tc.rintk(F32.mul(x, tc.f(sp.m_1_pi())))

# :115-147 `cody_waite_reduction`
def tc.cody_waite(x: F32) -> Red:
  +q = tc.cw_quadrant(x)
  Red{tc.cw_reduce(x, q), q}

# ===========================================================================
# THE SPECIAL CASES.  Each guard is its own row, and each BOUNDARY appears in
# TWO rows -- the value and the value next to it -- because one fixture cannot
# see both: `128.0`/`127.99999`, `-150.0`/`-149.99999`, `FLT_MIN` and
# `FLT_MIN*(1-1e-5)`, `30.0`/`29.999998`.
# ===========================================================================

# :9-11 `x.ne(inf).where(x.ne(x).where(nan, x.ne(-inf).where(ratio, _inf)), inf)`
def tc.lazy(x: F32, inf: F32, _inf: F32, nan: F32, ratio: F32) -> F32:
  tc.pick(F32.is_eq(x, inf),
          tc.pick(F32.is_eq(x, x), nan,
                  tc.pick(F32.is_eq(x, F32.neg(inf)), ratio, _inf)),
          inf)

# ===========================================================================
# THE EXPANSIONS, float32 lane.
# ===========================================================================

# :178 mask +-inf/nan to 0.0 -- the SAME `_lazy_map_numbers` call as :200 and
# :191, with three zero replacements.
def tc.mask0(d: F32) -> F32: tc.lazy(d, tc.zero(), tc.zero(), tc.zero(), d)

# :180 `x_sign`
def tc.x_sign(x: F32) -> F32:
  tc.pick(F32.is_eq(x, tc.zero()), tc.zero(),
          tc.pick(F32.is_lt(x, tc.zero()), tc.sign(True{}), 1.0))

# `x_abs >= switch_over` picks `payne_hanek_reduction` over
# `cody_waite_reduction` at :187.  This is the row that carries the 30.0
# boundary, because the VALUE past it is the W1 wall.
def tc.xsin_below(x_abs: F32) -> Bool: F32.is_lt(x_abs, tc.f(sp.switch_over()))

# `xsin(d, fast=True)`: :181 `x_abs`, :182/:183 cody_waite + sin_poly_small,
# :189 restore the sign, :191 mask to NaN.
def tc.xsin_fast(d: F32) -> F32:
  +x = tc.mask0(d)
  +s = tc.x_sign(x)
  +a = F32.mul(x, s)
  +r = Red.r(tc.cody_waite(a))
  F32.mul(tc.sps(r, tc.cw_quadrant(a)), s)

# `xexp2` (:193-217): :200 mask, :201 `rintk`, :203 `s = x - q`, :209 the
# polynomial, :210 `ldexp2k`, :213/:215 the two clamps, :217 the NaN guard.
def tc.xexp2(d: F32) -> F32:
  +x = tc.mask0(d)
  +q = tc.rintk(x)
  +u = tc.ldexp2k(tc.polyn(sp.exp32(), F32.sub(x, tc.i2f(q))), q)
  tc.pick(F32.is_ge(d, tc.f(sp.xexp2_up_32())), tc.pinf(),
          tc.pick(F32.is_lt(d, tc.f(sp.xexp2_lo_32())), tc.zero(),
                  tc.pick(F32.is_eq(d, d), tc.qnan(), u)))

# :212 the (upper, lower) pair the two clamps read.
def tc.xexp2_up(d: F32) -> Bool: F32.is_ge(d, tc.f(sp.xexp2_up_32()))
def tc.xexp2_lo(d: F32) -> Bool: F32.is_lt(d, tc.f(sp.xexp2_lo_32()))
def tc.xexp2_nan(d: F32) -> Bool: F32.is_eq(d, d)

# `xlog2` (:219-255).  MEASURED on a float32 UOp: EVERY node in the graph is
# float32, because `UOp.const`'s `weakfloat` (ops.py:186) lets the consumer's
# dtype win -- so `d * (2.0 ** 64)` at :229 is a binary32 multiply and the
# denormal arm is NOT a float64 detour.
def tc.is_denorm(d: F32) -> Bool: F32.is_lt(d, tc.f(sp.flmin_32()))

# :229 `a = is_denormal.where(d * (2.0 ** denormal_exp), d)`
def tc.xlog2_a(d: F32, den: Bool) -> F32:
  tc.pick(den, F32.mul(d, tc.f(sp.denorm_scale())), d)

# :231 `e = ilogb2k(a * (1.0 / 0.75))`
def tc.xlog2_e0(a: F32) -> U32: tc.ilogb2k(F32.mul(a, tc.f(sp.one_over_075())))

# :232 `m = ldexp3k(a, -e)`
def tc.xlog2_m(a: F32, e0: U32) -> F32: tc.ldexp3k(a, tc.neg(0, e0))

# :233 `e = is_denormal.where(e - denormal_exp, e)`
def tc.xlog2_e(den: Bool, e0: U32) -> F32:
  tc.pick(den, tc.i2f(tc.iadd(e0, tc.neg(0, sp.de_32()))), tc.i2f(e0))

# :235-236 `x = (m - 1)/(m + 1)`, `x2 = x*x`
def tc.xlog2_x(m: F32) -> F32: F32.div(F32.sub(m, 1.0), F32.add(m, 1.0))

# :244 `r = t*(x*x2) + e + x*log2(e) + x*s_lo`.  LEFT-associated, because the
# two trailing terms share one `+` and f32 addition is not associative.
def tc.xlog2_r(x: F32, e: F32) -> F32:
  F32.add(F32.add(F32.mul(tc.polyn(sp.log32(), F32.mul(x, x)), F32.mul(x, F32.mul(x, x))), e),
          F32.add(F32.mul(x, tc.f(sp.nlog2e32())), F32.mul(x, tc.f(sp.s_lo32()))))

# :247-:255 the five guards, applied in source order.
def tc.xlog2(d: F32) -> F32:
  +den = tc.is_denorm(d)
  +a = tc.xlog2_a(d, den)
  +e0 = tc.xlog2_e0(a)
  +e = tc.xlog2_e(den, e0)
  +r0 = tc.xlog2_r(tc.xlog2_x(tc.xlog2_m(a, e0)), e)
  +r1 = tc.pick(F32.is_eq(d, tc.pinf()), tc.pinf(),
                tc.pick(F32.is_eq(d, tc.zero()), tc.ninf(),
                        tc.pick(F32.is_lt(d, tc.ninf()), tc.qnan(),
                                tc.pick(F32.is_eq(d, d), tc.qnan(),
                                        tc.pick(F32.is_eq(F32.div(1.0, d), tc.ninf()),
                                                r0, tc.ninf())))))
  r1

def tc.xlog2_neinf(d: F32) -> Bool: F32.is_eq(d, tc.pinf())
def tc.xlog2_nezero(d: F32) -> Bool: F32.is_eq(d, tc.zero())
def tc.xlog2_neg(d: F32) -> Bool: F32.is_lt(d, tc.ninf())
def tc.xlog2_recip(d: F32) -> Bool: F32.is_eq(F32.div(1.0, d), tc.ninf())

# ===========================================================================
# `xpow` (:257-265).  W2: the `.log2()`/`.exp2()` in the middle are NATIVE ops,
# so only the pure half is claimed -- `non_int` (:261), `is_odd` (:262), the
# `exponent.eq(0)` short circuit (:265) and the `-base` at :259.
# ===========================================================================

# :261 `exponent != exponent.cast(int32).cast(exponent.dtype)`
def tc.xpow_non_int(e: F32) -> Bool: Bool.not(F32.is_eq(e, tc.i2f(tc.f2i(e))))

# :262 `(exponent < 0).where(-exponent, exponent).cast(int32).mod(2).cast(bool)`
def tc.xpow_is_odd(e: F32) -> Bool:
  U32.is_eq(U32.and(tc.f2i(tc.pick(F32.is_lt(e, tc.zero()), F32.neg(e), e)), 1), 1)

def tc.xpow_e_zero(e: F32) -> Bool: F32.is_eq(e, tc.zero())

# :259 `(base < 0).where(-base, base)` and the :265 `(base < 0)` re-test
def tc.xpow_neg_base(b: F32) -> Bool: F32.is_lt(b, tc.zero())
def tc.xpow_abs(b: F32) -> F32:
  tc.pick(F32.is_lt(b, tc.zero()), F32.neg(b), b)

# ===========================================================================
# `payne_hanek_reduction` (:66-113).  W1: the uint64 product at :103/:105 is
# NOT evaluated.  What IS here is every CONSTANT it reads and the u32 window
# arithmetic of `_take` (:88-92), which is a pure function of (i, e).
# ===========================================================================

# :84-86 `i = shr(e.cast(uint64), 5)`, `e = e & 31`, `offset = 32 - e`
def tc.ph_i(e0: U32) -> U32: tc.shr_u(e0, 5)
def tc.ph_e31(e0: U32) -> U32: U32.and(e0, 31)
def tc.ph_off(e0: U32) -> U32: tc.neg(0, tc.ph_e31(e0))

# :88-92 `_take`: `if count + offset < len(two_over_pi_f) - 1` is a COMPILE-TIME
# test over two Python ints, so the chain runs `take_window - offset` deep and
# each level asks `i.ne(count)`.  The word chosen is
# `two_over_pi_f[k + offset]` for the FIRST `k` with `i == k`; when the chain is
# empty the seed `UOp.const(0, uint32)` survives untouched.
def tc.take_len(off: U32) -> U32: U32.sub(sp.take_window(), off)

# the index the chain ends on, and whether the chain ran at all.
def tc.take_pick(i: U32, off: U32, k: U32, len: U32) -> U32:
  tc.take_pick.go(U32.is_ge(len, U32.inc(k)), i, k, len, 4294967295)

def tc.take_pick.go(run: Bool, i: U32, k: U32, len: U32, n: Nat) -> U32:
  match run:
    case True{}:
      match U32.is_eq(i, k):
        case True{}: U32.add(k, tc.nat0)
        case False{}: tc.take_pick.go(run, i, U32.inc(k), len, Nat.succ(n))
    case False{}: 4294967295

def tc.nat0() -> U32: 0

# ===========================================================================
# THE GATE.
# ===========================================================================

# --- 1: the coefficient tables, BOTH directions plus the hex spelling ------
def t_coef() -> IO(Unit):
  do IO<Unit>:
    t_coef.f(sp.sin32(), tc.ilen(sp.sin32()), "xf_sp.sin32.")
    t_coef.f(sp.sin64(), tc.ilen(sp.sin64()), "xf_sp.sin64.")
    t_coef.f(sp.exp32(), tc.ilen(sp.exp32()), "xf_sp.exp32.")
    t_coef.f(sp.exp64(), tc.ilen(sp.exp64()), "xf_sp.exp64.")
    t_coef.f(sp.log32(), tc.ilen(sp.log32()), "xf_sp.log32.")
    t_coef.f(sp.log64(), tc.ilen(sp.log64()), "xf_sp.log64.")
    t_coef.u(sp.topi(), tc.ilen(sp.topi()), "xf_sp.topi.")
    t_coef.t("cd_sp.sin64", sp.sin64())
    t_coef.t("cd_sp.exp64", sp.exp64())
    t_coef.t("cd_sp.log64", sp.log64())
    t_coef.s("cd_sp.sin32", sp.sin32())
    t_coef.s("cd_sp.exp32", sp.exp32())
    t_coef.s("cd_sp.log32", sp.log32())
    t_coef.s("cx_sp.topi", sp.topi())
    t_scalars()

def t_coef.f(xs: List<&2, String>, n: U32, nm: String) -> IO(Unit):
  t_coef.f.go(xs, n, 0, nm, tc.ilen(xs), 4294967295)

def t_coef.f.go(+xs: List<&2, String>, n: Nat, i: U32, nm: String,
                len: U32, lim: Nat) -> IO(Unit):
  match U32.is_ge(len, U32.inc(i)):
    case True{}:
      do IO<Unit>:
        urow(String.concat([nm, U32.show(i)]), tc.fv(xs, i))
        urow(String.concat(["xv_", nm, U32.show(tc.fv(xs, i))]), tc.vi(xs, tc.fv(xs, i), len))
        t_coef.f.go(xs, n, U32.inc(i), nm, len, Nat.succ(lim))
    case False{}: IO.print("")

def t_coef.u(xs: List<&2, U32>, n: U32, nm: String) -> IO(Unit):
  t_coef.u.go(xs, n, 0, nm, tc.ilen(sp.sin32()), 4294967295)

def t_coef.u.go(+xs: List<&2, U32>, n: Nat, i: U32, nm: String,
                len: U32, lim: Nat) -> IO(Unit):
  match U32.is_ge(len, U32.inc(i)):
    case True{}:
      do IO<Unit>:
        urow(String.concat([nm, U32.show(i)]), tc.uth(xs, i))
        urow(String.concat(["xv_", nm, U32.show(tc.uth(xs, i))]), tc.uvi(xs, tc.uth(xs, i), 7))
        t_coef.u.go(xs, n, U32.inc(i), nm, len, Nat.succ(lim))
    case False{}: IO.print("")

def t_coef.t(nm: String, xs: List<&2, String>) -> IO(Unit):
  t_coef.t.go(xs, nm, 0, tc.ilen(xs), 4294967295)

def t_coef.t.go(+xs: List<&2, String>, nm: String, i: U32, len: U32,
                n: Nat) -> IO(Unit):
  match U32.is_ge(len, U32.inc(i)):
    case True{}:
      do IO<Unit>:
        srow(String.concat([nm, "_", U32.show(i)]), tc.nth(xs, i))
        t_coef.t.go(xs, nm, U32.inc(i), len, Nat.succ(n))
    case False{}: IO.print("")

def t_coef.s(nm: String, xs: List<&2, String>) -> IO(Unit):
  t_coef.t(nm, xs)

def t_coef.s(nm: String, xs: List<&2, U32>) -> IO(Unit):
  t_coef.su.go(xs, nm, 0, tc.ilen(sp.topi()), 4294967295)

def t_coef.su.go(+xs: List<&2, U32>, nm: String, i: U32, len: U32,
                 n: Nat) -> IO(Unit):
  match U32.is_ge(len, U32.inc(i)):
    case True{}:
      do IO<Unit>:
        srow(String.concat([nm, "_", U32.show(i)]), tc.hex8(tc.uth(xs, i)))
        t_coef.su.go(xs, nm, U32.inc(i), len, Nat.succ(n))
    case False{}: IO.print("")

def tc.hex8(x: U32) -> String:
  tc.hex8.go(x, 4294967295, String.read(""), 0, 4294967295)

def tc.hex8.go(x: U32, k: U32, acc: String, i: U32, n: Nat) -> String:
  match U32.is_ge(i, 8):
    case True{}: acc
    case False{}:
      tc.hex8.go(x, k, String.concat([tc.hexdig(tc.nib(x, i)), acc]),
                U32.inc(i), Nat.succ(n))

def tc.nib(x: U32, i: U32) -> U32: U32.and(U32.shrn(x, tc.nat(U32.mul(28, i))), 15)

def tc.hexdig(n: U32) -> String:
  match U32.is_lt(n, 10):
    case True{}: tc.dig(n)
    case False{}: String.concat(["x", tc.dig(U32.sub(n, 10))])

def tc.dig(n: U32) -> String:
  tc.dig.go(tc.chr(U32.add(48, n)), 0, 4294967295)

def tc.dig.go(c: Char, n: U32) -> String: String.from_list(List.singleton(&2, Char, c))

def tc.chr(c: U32) -> Char:
  match String.get(&2, tc.chars(), tc.nat(c)):
    case Some{v}: v
    case None{}: Char.from_u32(0)

def tc.chars() -> List<&2, Char>:
  String.to_list(String.concat([tc.digits(), "abcdef"]))

def tc.digits() -> String: String.read("0123456789")

def t_scalars() -> IO(Unit):
  do IO<Unit>:
    t_one("xf_m_1_pi", tc.b(sp.m_1_pi()))
    t_one("xf_two_24", tc.b(sp.two_24()))
    t_one("xf_topi_scale", tc.b(sp.topi_scale()))
    t_one("xf_neg_half_pi_over_2", tc.b(sp.neg_half_pi_over_2()))
    t_one("xf_nlog2e64", tc.b(sp.nlog2e64()))
    t_one("xf_nlog2e32", tc.b(sp.nlog2e32()))
    t_one("xf_s_lo32", tc.b(sp.s_lo32()))
    t_one("xf_one_over_075", tc.b(sp.one_over_075()))
    t_one("xf_switch_over", tc.b(sp.switch_over()))
    t_one("xf_pi_over_2", tc.b(sp.pi_over_2()))
    t_one("xf_cw0", tc.b(sp.cw0()))
    t_one("xf_cw1", tc.b(sp.cw1()))
    t_one("xf_cw2", tc.b(sp.cw2()))
    t_one("xf_cw3", tc.b(sp.cw3()))
    t_one("xf_pi_a", tc.b(sp.pi_a()))
    t_one("xf_pi_b", tc.b(sp.pi_b()))
    t_one("xf_pi_c", tc.b(sp.pi_c()))
    t_one("xf_pi_d", tc.b(sp.pi_d()))
    t_one("xf_xexp2_lo_32", tc.b(sp.xexp2_lo_32()))
    t_one("xf_xexp2_up_32", tc.b(sp.xexp2_up_32()))
    t_one("xf_flmin_16", tc.b(sp.flmin_16()))
    t_one("xf_flmin_32", tc.b(sp.flmin_32()))
    t_one("xf_denorm_scale", tc.b(sp.denorm_scale()))
    t_one("xf_two_m24", tc.b(sp.two_m24()))
    t_one("xf_qdh_scale", F32.bits(tc.qdh_scale()))
    t_one("cu_q_shift", sp.q_shift())
    t_one("cu_take_window", sp.take_window())
    t_one("cu_mb_32", sp.mb_32())
    t_one("cu_eb_32", sp.eb_32())
    t_one("cu_em_32", sp.em_32())
    t_one("cu_mb_16", sp.mb_16())
    t_one("cu_eb_16", sp.eb_16())
    t_one("cu_em_16", sp.em_16())
    t_one("cu_de_32", sp.de_32())
    t_one("cu_frac_mask", sp.frac_mask())
    t_one("cu_fm1_32", sp.fm1_32())
    t_one("cu_fm2_32", sp.fm2_32())
    t_one("cu_fm1_16", sp.fm1_16())
    t_one("cu_fm2_16", sp.fm2_16())
    t_one("cu_p_mask.hi", sp.p_mask.hi())
    t_one("cu_p_mask.lo", sp.p_mask.lo())
    t_one("cu_fm1_64.hi", sp.fm1_64.hi())
    t_one("cu_fm1_64.lo", sp.fm1_64.lo())
    t_one("cu_fm2_64.hi", sp.fm2_64.hi())
    t_one("cu_fm2_64.lo", sp.fm2_64.lo())
    t_one("cu_mant64.hi", sp.mant64.hi())
    t_one("cu_mant64.lo", sp.mant64.lo())
    t_one("cu_eb64.hi", sp.eb64.hi())
    t_one("cu_eb64.lo", sp.eb64.lo())
    t_one("cu_em64.hi", sp.em64.hi())
    t_one("cu_em64.lo", sp.em64.lo())
    t_one("cu_mb_64", sp.mb_64())
    t_one("tx_dt.transcendental", tc.dt_line())
    t_one("cu_two_24_bits", tc.b(sp.two_24()))

def tc.dt_line() -> String: String.read("f16 f32 f64")

def t_one(nm: String, v: U32) -> IO(Unit): urow(nm, v)

def main() -> IO(Unit):
  do IO<Unit>:
    t_coef()
    IO.print("ts-done=1")