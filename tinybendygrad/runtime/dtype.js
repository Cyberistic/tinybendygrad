// dtype.js -- the interpreted-lane half of the runtime/dtype.c seam.
//
// Same tables, same arithmetic as dtype.c, but the SEAM is not the same shape in
// the two lanes, and reading dtype.c is how this file came to disagree with it.
// The conventions are declared once, in .agents/slop/abi/abi.json, and named
// ABI-1..ABI-7 here so a wrong read has a name:
//
//   ABI-1  a seam receives its arguments POSITIONALLY, one slot per parameter of
//          its CID. An H.I64 is ONE slot carrying a record, not two words.
//   ABI-2  a record crosses into JS BY ITS BEND FIELD NAMES, {hi, lo}, and
//          crosses back the same way. In C it is a constructor node opened
//          POSITIONALLY by ctr_take, so a.fst/a.snd is wrong in both
//          directions and under one name.
//   ABI-3  the two words are ordered HIGH FIRST: hi is bits 63..32, lo is 31..0.
//   ABI-5  the words are carried as JS numbers into BigInt arithmetic, never
//          combined in Number arithmetic, which has 53 mantissa bits.
//
// JS gives exact integer and double arithmetic, and every value here is either a
// bit pattern or a float with at most four significant bits, so nothing rounds
// differently than in C.

const FP8_E4M3 = 0;
const FP8_E5M2 = 1;
const FP8_E4M3FNUZ = 2;
const FP8_E5M2FNUZ = 3;

// (bias, sig_bits, mant_mask, min_denorm_half, ovf_threshold, max_norm, min_norm)
// dtype.py's _fp8_cfg with the f64 magnitude patterns as f32 patterns.
const FP8_CFG = [
  [7, 4, 0x7, 0x3a800000, 0x43e80000, 0x7e, 0x3c800000],
  [15, 3, 0x3, 0x37000000, 0x47700000, 0x7b, 0x38800000],
  [8, 4, 0x7, 0x3a000000, 0x43780000, 0x7f, 0x3c000000],
  [16, 3, 0x3, 0x36800000, 0x47700000, 0x7f, 0x38000000],
];

function of32(u) {
  return new Float32Array(new Uint32Array([u >>> 0]).buffer)[0];
}

function bits32(x) {
  return new Uint32Array(new Float32Array([x]).buffer)[0];
}

function fp8_encode(xb, kind) {
  const [bias, sig, mant, denorm, ovf, maxNorm] = FP8_CFG[kind];
  const fnuz = kind >= FP8_E4M3FNUZ;
  const expField = (xb >>> 23) & 0xff;
  const sgn = ((xb >>> 31) & 1) << 7;
  const hu = 1 << (23 - sig);
  const absx = xb & 0x7fffffff;
  if (expField === 0xff) {
    if (fnuz) return 0x80;
    if (kind === FP8_E4M3) return sgn !== 0 ? 0xff : 0x7f;
    return (((xb & 0x7fffff) === 0 ? 0x7c : 0x7f) | sgn);
  }
  const exp = expField - 127 + bias;
  let m = (xb >>> (24 - sig)) & mant;
  let res;
  const minNorm = FP8_CFG[kind][6];
  if (absx <= denorm) {
    res = 0;
  } else if (absx > ovf) {
    res = maxNorm;
  } else if (absx >= minNorm) {
    res = (exp << (sig - 1)) | m;
    const rb = xb & ((hu << 1) - 1);
    if (rb > hu || (rb === hu && (m & 1))) res += 1;
  } else {
    const sh = 1 - exp;
    m |= 1 << (sig - 1);
    res = m >>> sh;
    const half = hu << sh;
    const rb = (xb | (1 << 23)) & ((half << 1) - 1);
    if (rb > half || (rb === half && (res & 1))) res += 1;
  }
  return (fnuz && res === 0) ? 0 : (res | sgn);
}

function fp8_decode(x, kind) {
  const sig = FP8_CFG[kind][1];
  if (kind >= FP8_E4M3FNUZ && x === 0x80) return 0x7fc00000;
  if ((x & 0x7f) === 0) return (x & 0x80) ? 0x80000000 : 0;
  const mantBits = sig - 1, expBits = 8 - sig;
  const expMax = (1 << expBits) - 1, mantMax = (1 << mantBits) - 1;
  const sgn = (x >> 7) & 1, exp = (x >> mantBits) & expMax, mant = x & mantMax;
  if (kind < FP8_E4M3FNUZ && exp === expMax) {
    if (kind === FP8_E5M2) {
      return mant ? (sgn ? 0xffc00000 : 0x7fc00000)
                  : (sgn ? 0xff800000 : 0x7f800000);
    }
    if (mant === mantMax) return sgn ? 0xffc00000 : 0x7fc00000;
  }
  const bias = FP8_CFG[kind][0];
  const v = of32(exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias));
  return bits32(sgn ? -v : v);
}

function f16_bits(x) {
  // IEEE binary16 from an f32 pattern, round-half-to-even, saturating to inf.
  const xb = bits32(x);
  const s = (xb >>> 16) & 0x8000;
  const e = (xb >>> 23) & 0xff;
  const m = xb & 0x7fffff;
  if (e === 0xff) return s | 0x7c00 | (m ? 0x200 : 0);
  const ue = e - 127 + 15;
  if (ue >= 0x1f) return s | 0x7c00;
  if (ue <= 0) {
    if (ue < -10) return s;
    return s | ((m | 0x800000) >>> (27 - ue));
  }
  const keep = m >>> 13, rest = m & 0x1fff;
  let hm = keep;
  if (rest > 0x1000 || (rest === 0x1000 && (keep & 1))) hm += 1;
  return s | (hm === 0x400 ? ((ue + 1) << 10) : ((ue << 10) | hm));
}

function half_to_f32(h) {
  // NOT a zero extension: the two formats have different exponent widths and
  // biases (f32 8/127, half 5/15), so the exponent is rebased by 112 and the
  // fraction gains 13 leading bits. A half subnormal is m * 2^-24, which is
  // inside the f32 normal range, so the low exponents all share one encoding.
  const s = (h & 0x8000) << 16;
  const e = (h >>> 10) & 0x1f;
  const m = h & 0x3ff;
  if (e === 0) return m === 0 ? (s >>> 0) : ((s | (103 << 23) | (m << 14)) >>> 0);
  if (e === 0x1f) return ((s | 0x7f800000 | (m << 13)) >>> 0);
  return ((s | ((e + 112) << 23) | (m << 13)) >>> 0);
}

function dtype_bf16(u) {
  return of32(((u + 0x7fff + ((u >>> 16) & 1)) & 0xffff0000) >>> 0);
}

function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(of32(x))));
}

function dtype_fp8_from(xb, kind) {
  return fp8_encode(xb >>> 0, kind & 0xff);
}

function dtype_fp8_to(x, kind) {
  return fp8_decode(x >>> 0, kind & 0xff);
}

// ABI-1/ABI-2: an I64 crosses by its BEND FIELD NAMES (helpers.bend's
// `I64{hi: U32, lo: U32}`), both in and out. `p.fst`/`p.snd` are not that
// record, and `undefined >>> 0 === 0` makes such a read total rather than loud.
// ABI-3: hi is the high word. ABI-5: the words become BigInt before they are
// combined, because `hi * 2**32` in Number arithmetic is inexact for most hi.
function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.hi >>> 0) << 32n) | BigInt(p.lo >>> 0));
}

// ABI-2 the way out: the answer is an H.I64 again, so it is built with hi/lo.
// `io_tup` builds a Tuple{fst,snd}, which is the C lane's positional shape and
// is not what generated code reads.
function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return {$: "tinybendygrad/helpers.I64", hi: Number((u >> 32n) & 0xffffffffn),
          lo: Number(u & 0xffffffffn)};
}

// Python's // and %: floor division, and the remainder that goes with it.
function floor_pair(a, b) {
  if (b === 0n) return [0n, a];              // tinygrad's zero-divisor branch
  let q = a / b, r = a % b;
  if (r !== 0n && ((r < 0n) !== (b < 0n))) { q -= 1n; r += b; }
  return [q, r];
}

// cdiv truncates toward zero. Its sign comes from the operands, not from a*b:
// the product would overflow.
function cdiv_of(a, b) {
  const q = (a < 0n ? -a : a) / (b < 0n ? -b : b);
  return (a < 0n) !== (b < 0n) ? -q : q;
}

io_eff(CID(Dt.bf16), dtype_bf16);
io_eff(CID(Dt.fp16), dtype_fp16);
io_eff(CID(Dt.fp8_from), dtype_fp8_from);
io_eff(CID(Dt.fp8_to), dtype_fp8_to);
io_eff(CID(Dt.i64_trunc), (a) => pack64(i64_of(a)));
io_eff(CID(Dt.i64_floor_div), (a, b) => pack64(floor_pair(i64_of(a), i64_of(b))[0]));
io_eff(CID(Dt.i64_floor_mod), (a, b) => pack64(floor_pair(i64_of(a), i64_of(b))[1]));
io_eff(CID(Dt.i64_cdiv), (a, b) => pack64(
  i64_of(b) === 0n ? 0n : cdiv_of(i64_of(a), i64_of(b))));
io_eff(CID(Dt.i64_cmod), (a, b) => pack64(
  i64_of(b) === 0n ? i64_of(a) : i64_of(a) - cdiv_of(i64_of(a), i64_of(b)) * i64_of(b)));
io_eff(CID(Dt.i64_ceildiv), (a, b) => pack64(   // dtype.py ceildiv is -(a // -b)
  i64_of(b) === 0n ? 0n : -floor_pair(i64_of(a), -i64_of(b))[0]));
