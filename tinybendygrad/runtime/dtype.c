// dtype.c -- the numeric conversions tinygrad/dtype.py does with struct and
// ctypes, as Bend effects.
//
// WHY AN EFFECT AT ALL. Bend's only float is F32, and it can read an F32's bits
// (F32.bits) but cannot build an F32 from a bit pattern. Every conversion here
// is bit twiddling in both directions, so without this seam none of them is
// expressible: float_to_bf16 rounds bits, float_to_fp16/fp8 build a value from
// bits, fp8_to_float builds a value from bits, and the 64-bit div/mod need a
// 64-bit quotient. That is the whole list; the rest of dtype.bend is pure.
//
// The f32 restatement of float_to_fp8 is not a simplification. dtype.py does the
// arithmetic on f64 (`struct.pack('d', x)`), and this file does it on the f32
// pattern handed in. The two agree bit for bit on every f32 input, because the
// tie bit dtype.py compares against is at f64 bit (52 - sig_bits) and an f32 has
// no bits below pattern bit 23: see .agents/slop/notes/fp8_oracle.py, which
// checks all four formats over a million random patterns, every boundary
// exponent, and all 256 codes in both directions.
//
// ONE FILE, BOTH LANES. The .js file beside this one is the same arithmetic on
// the same tables, for the interpreted lane; keeping them adjacent is what makes
// the agreement checkable by eye.

// (bias, sig_bits, mant_mask, min_denorm_half, ovf_threshold, max_norm, min_norm)
// dtype.py's _fp8_cfg with the three f64 magnitude patterns rewritten as the f32
// patterns of the same values. Two of dtype.py's constants are an f64 ULP below
// 61440, which rounds to the same f32 pattern as 61440 itself.
#define FP8_E4M3      0
#define FP8_E5M2      1
#define FP8_E4M3FNUZ  2
#define FP8_E5M2FNUZ  3

// bend2's generated C declares u64/u32/u8 but no signed 64-bit type; the
// div/mod half of this file needs one and the casts are the whole of the cost.
typedef int64_t s64;

static const u32 fp8_bias[4]      = {  7, 15,  8, 16 };
static const u32 fp8_sig[4]       = {  4,  3,  4,  3 };
static const u32 fp8_mant[4]      = { 0x7, 0x3, 0x7, 0x3 };
static const u32 fp8_denorm[4]    = { 0x3A800000, 0x37000000, 0x3A000000, 0x36800000 };
static const u32 fp8_ovf[4]       = { 0x43E80000,  0x47700000, 0x43780000,  0x47700000 };
static const u32 fp8_max_norm[4]  = { 0x7E,       0x7B,       0x7F,        0x7F };
static const u32 fp8_min_norm[4]  = { 0x3C800000, 0x38800000, 0x3C000000,  0x38000000 };

static inline int fp8_is_fnuz(u32 kind) { return kind >= FP8_E4M3FNUZ; }

// dtype.py float_to_fp8, on the f32 bit pattern. `kind` is one of the FP8_* ids.
static u32 fp8_encode(u32 xb, u32 kind) {
  u32 exp_field = (xb >> 23) & 0xFFu;
  u32 sgn       = ((xb >> 31) & 1u) << 7;
  u32 bias      = fp8_bias[kind];
  u32 sig       = fp8_sig[kind];
  u32 hu        = 1u << (23 - sig);           // the tie bit, see fp8_oracle.py
  u32 absx      = xb & 0x7FFFFFFFu;
  u32 exp, mant, res;

  if (exp_field == 0xFFu) {
    // dtype.py's three non-finite cases, in its order. The fnuz formats have no
    // inf or nan at all and answer 0x80; e4m3 has no inf and answers jax's
    // 0x7f/0xff; e5m2 has a full nan and inf.
    if (fp8_is_fnuz(kind)) return 0x80u;
    if (kind == FP8_E4M3) return sgn != 0 ? 0xFFu : 0x7Fu;
    u32 mant_all = (xb & 0x7FFFFFu) == 0;
    return (mant_all ? 0x7Cu : 0x7Fu) | sgn;
  }

  exp  = exp_field - 127u + bias;
  mant = (xb >> (24 - sig)) & fp8_mant[kind];
  if (absx <= fp8_denorm[kind]) {
    res = 0;
  } else if (absx > fp8_ovf[kind]) {
    res = fp8_max_norm[kind];
  } else if (absx >= fp8_min_norm[kind]) {
    res = (exp << (sig - 1)) | mant;
    u32 rb = xb & ((hu << 1) - 1);
    if (rb > hu || (rb == hu && (mant & 1))) res += 1;
  } else {
    u32 sh = 1 - exp;
    u32 half;
    mant |= 1u << (sig - 1);
    res  = mant >> sh;
    half = hu << sh;
    u32 rb = (xb | (1u << 23)) & ((half << 1) - 1);
    if (rb > half || (rb == half && (res & 1))) res += 1;
  }
  // fnuz has no negative zero, so a zero result carries no sign
  return (fp8_is_fnuz(kind) && res == 0) ? 0u : (res | sgn);
}

// dtype.py fp8_to_float, answering the f32 bit pattern of the value.
static u32 fp8_decode(u32 x, u32 kind) {
  u32 sig = fp8_sig[kind], bias = fp8_bias[kind];
  if (fp8_is_fnuz(kind) && x == 0x80u) return 0x7FC00000u;   // nan
  if ((x & 0x7Fu) == 0) return (x & 0x80u) ? 0x80000000u : 0u;
  u32 mant_bits = sig - 1, exp_bits = 8 - sig;
  u32 exp_max = (1u << exp_bits) - 1, mant_max = (1u << mant_bits) - 1;
  u32 sgn = (x >> 7) & 1, exp = (x >> mant_bits) & exp_max, mant = x & mant_max;
  f32 v;
  if (!fp8_is_fnuz(kind) && exp == exp_max) {
    if (kind == FP8_E5M2) {
      // dtype.py: copysign(nan if mantissa else inf, -1 if sign else 1)
      return mant ? (sgn ? 0xFFC00000u : 0x7FC00000u)
                  : (sgn ? 0xFF800000u : 0x7F800000u);
    }
    if (mant == mant_max) return sgn ? 0xFFC00000u : 0x7FC00000u;
  }
  // the value is exact in f32 -- an fp8 has at most four significant bits
  v = (f32)(exp == 0 ? (mant / (f32)(mant_max + 1)) * (1.0f / (1u << bias))
                     : (1.0f + mant / (f32)(mant_max + 1)) *
                       ldexpf(1.0f, (int)exp - (int)bias));
  return f32_rewrap(sgn ? -v : v);
}

// float_to_fp16, as an f32 whose pattern is the half zero-extended. dtype.py is
// `struct.pack('e', x)` and catches OverflowError to return copysign(inf, x),
// which is exactly "saturate to a signed infinity". IEEE binary16 from an
// f32 pattern, round-half-to-even.
static u32 fp16_encode(u32 x) {
  u32 s = (x >> 16) & 0x8000u;          // sign, already in half position
  u32 e = (x >> 23) & 0xffu;
  u32 m = x & 0x7fffffu;
  if (e == 0xff) return s | 0x7c00u | (m ? 0x200u : 0u);   // inf / nan
  if (e == 0 && m == 0) return s;                          // signed zero
  int exp = (int)e - 127 + 15;
  if (exp >= 0x1f) return s | 0x7c00u;                     // overflow -> inf
  if (exp <= 0) {                                           // subnormal / zero
    if (exp < -10) return s;
    m |= 0x800000u;
    u32 shift = (u32)(14 - exp);
    u32 half = m >> shift;
    u32 rem = m & ((1u << shift) - 1u);
    u32 halfway = 1u << (shift - 1);
    if (rem > halfway || (rem == halfway && (half & 1u))) half++;
    return s | half;
  }
  u32 half = ((u32)exp << 10) | (m >> 13);
  u32 rem = m & 0x1fffu;
  if (rem > 0x1000u || (rem == 0x1000u && (half & 1u))) half++;   // may carry
  return s | half;
}

// The f32 pattern of a half value. NOT a zero extension: the two formats have
// different exponent widths and biases (f32 8/127, half 5/15), so the exponent
// is rebased and the fraction is shifted. A half subnormal is m * 2^-24, which
// is always an f32 normal, so it needs no denormal path on this side.
static u32 fp16_f32(u32 h) {
  u32 s = (h >> 15) & 1u, e = (h >> 10) & 0x1Fu, m = h & 0x3FFu;
  if (e == 0x1Fu) return (s << 31) | 0x7F800000u | (m ? 0x400000u : 0u);
  if (e == 0) {
    if (m == 0) return s << 31;
    u32 k = 31u - (u32)__builtin_clz(m);
    return (s << 31) | ((k + 103u) << 23) | ((m << (23 - k)) & 0x7FFFFFu);
  }
  return (s << 31) | ((e + 112u) << 23) | (m << 13);
}

static Term fp16_run(Env e, Term* f, IoWork* w) {
  return (Term)(intptr_t)fp16_f32(fp16_encode((u32)f[0]));
}

static Term fp8_to_run(Env e, Term* f, IoWork* w) {
  return (Term)(intptr_t)fp8_decode((u32)f[0] & 0xFFu, (u32)f[1] & 0xFFu);
}

static Term fp8_from_run(Env e, Term* f, IoWork* w) {
  return (Term)(intptr_t)fp8_encode((u32)f[0], (u32)f[1] & 0xFFu);
}

static Term bf16_run(Env e, Term* f, IoWork* w) {
  // dtype.py: round the f32 bits to bf16 with round-half-to-even, and answer
  // the value. bf16 IS the top half of an f32 pattern, so the rounded pattern
  // is the answer with no rebias -- which is exactly why this one differs from
  // the half above. NOTE the explicit u32: f32_rewrap takes an f32, so handing
  // it a u32 would reinterpret the bits as a float and back.
  u32 x = (u32)f[0];
  return (Term)(intptr_t)((x + 0x7FFFu + ((x >> 16) & 1u)) & 0xFFFF0000u);
}

// ===========================================================================
// The 64-bit helpers. Python's // and % are floor division; its cdiv/cmod
// truncate toward zero. A signed 64-bit quotient has no U32 encoding, which is
// the whole reason these are an effect and not a def.
//
// Every one takes an I64 as (hi, lo) and answers one the same way. INT64_MIN
// has no positive counterpart, so nothing here negates its divisor: cdiv uses
// |a|//|b| and the ceiling is computed directly, which is what Python's
// -(a // -b) means without the negation.
typedef struct { s64 q, r; } DivMod;

static DivMod floor_div_mod(s64 a, s64 b) {
  DivMod d;
  if (b == 0) { d.q = 0; d.r = a; return d; }   // tinygrad's zero-divisor branch
  d.q = a / b;
  d.r = a % b;
  if (d.r != 0 && ((d.r < 0) != (b < 0))) { d.q -= 1; d.r += b; }
  return d;
}

// cdiv truncates toward zero; its sign comes from the operands, not from a*b,
// because the product would overflow.
static s64 cdiv_of(s64 a, s64 b) {
  s64 q = (a < 0 ? -a : a) / (b < 0 ? -b : b);
  return (a < 0) != (b < 0) ? -q : q;
}

static s64 i64_of(Env e, Term t) {
  Term o[2];
  ctr_take(e, t, 2, o);
  return (s64)((((u64)(u32)o[0]) << 32) | (u32)o[1]);
}

static Term pack64(Env e, s64 v) {
  return io_tup(e, (Term)(intptr_t)(u32)((u64)v >> 32), (Term)(intptr_t)(u32)(u64)v);
}

static Term i64_run(Env e, Term* f, IoWork* w) {
  return pack64(e, i64_of(e, f[0]));
}

static Term div64_floor_run(Env e, Term* f, IoWork* w) {
  return pack64(e, floor_div_mod(i64_of(e, f[0]), i64_of(e, f[1])).q);
}

static Term div64_mod_run(Env e, Term* f, IoWork* w) {
  return pack64(e, floor_div_mod(i64_of(e, f[0]), i64_of(e, f[1])).r);
}

static Term div64_cdiv_run(Env e, Term* f, IoWork* w) {
  s64 a = i64_of(e, f[0]), b = i64_of(e, f[1]);
  return pack64(e, b == 0 ? 0 : cdiv_of(a, b));
}

static Term div64_cmod_run(Env e, Term* f, IoWork* w) {
  s64 a = i64_of(e, f[0]), b = i64_of(e, f[1]);
  return pack64(e, b == 0 ? a : a - cdiv_of(a, b) * b);
}

static Term div64_ceildiv_run(Env e, Term* f, IoWork* w) {
  s64 a = i64_of(e, f[0]), b = i64_of(e, f[1]);
  if (b == 0) return pack64(e, 0);
  s64 c = a / b;
  if (a % b != 0 && (a < 0) == (b < 0)) c += 1;
  return pack64(e, c);
}

// One guard per registration, the way base.bend's file_read.c does it: CID is
// only defined for an effect the calling program actually uses, so a program
// that never calls fp8_from must not name it.
#ifdef CID(Dt.bf16)
static void __attribute__((constructor)) dtype_bf16_use(void) {
  io_eff(CID(Dt.bf16), bf16_run, 0);
}
#endif
#ifdef CID(Dt.fp16)
static void __attribute__((constructor)) dtype_fp16_use(void) {
  io_eff(CID(Dt.fp16), fp16_run, 0);
}
#endif
#ifdef CID(Dt.fp8_from)
static void __attribute__((constructor)) dtype_fp8_from_use(void) {
  io_eff(CID(Dt.fp8_from), fp8_from_run, 0);
}
#endif
#ifdef CID(Dt.fp8_to)
static void __attribute__((constructor)) dtype_fp8_to_use(void) {
  io_eff(CID(Dt.fp8_to), fp8_to_run, 0);
}
#endif
#ifdef CID(Dt.i64_trunc)
static void __attribute__((constructor)) dtype_i64_trunc_use(void) {
  io_eff(CID(Dt.i64_trunc), i64_run, 0);
}
#endif
#ifdef CID(Dt.i64_floor_div)
static void __attribute__((constructor)) dtype_i64_floor_div_use(void) {
  io_eff(CID(Dt.i64_floor_div), div64_floor_run, 0);
}
#endif
#ifdef CID(Dt.i64_floor_mod)
static void __attribute__((constructor)) dtype_i64_floor_mod_use(void) {
  io_eff(CID(Dt.i64_floor_mod), div64_mod_run, 0);
}
#endif
#ifdef CID(Dt.i64_cdiv)
static void __attribute__((constructor)) dtype_i64_cdiv_use(void) {
  io_eff(CID(Dt.i64_cdiv), div64_cdiv_run, 0);
}
#endif
#ifdef CID(Dt.i64_cmod)
static void __attribute__((constructor)) dtype_i64_cmod_use(void) {
  io_eff(CID(Dt.i64_cmod), div64_cmod_run, 0);
}
#endif
#ifdef CID(Dt.i64_ceildiv)
static void __attribute__((constructor)) dtype_i64_ceildiv_use(void) {
  io_eff(CID(Dt.i64_ceildiv), div64_ceildiv_run, 0);
}
#endif
