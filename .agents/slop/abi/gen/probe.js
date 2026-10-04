function word_to_u32(w) {
  let x = 0;
  for (let i = 0; w.$ === "WCon"; i++) {
    x |= Number(w.head) << i;
    w = w.tail;
  }
  return x >>> 0;
}

function u32_to_word(x) {
  let w = {$: "WNil"};
  for (let i = 31; i >= 0; i--) {
    w = {$: "WCon", head: ((x >>> i) & 1) === 1, tail: w};
  }
  return w;
}

function cmp_new(a, b) {
  return {$: a < b ? "LT"
    : a === b ? "EQ" : "GT"};
}

function nat_divmod(a, b) {
  return b === 0 ? {$: "Tuple", fst: 0, snd: a}
    : {$: "Tuple", fst: Math.trunc(a / b), snd: a % b};
}

function nat_chk(n) {
  if (n > 281474976710655) {
    throw "bend: a Nat past the largest immediate 2^48-1";
  }
  return n;
}

function nat_host(n) {
  const int = typeof n === "bigint" || Number.isInteger(n);
  if (int && n >= 0 && n <= 2 ** 53) {
    return Number(n);
  }
  return { [Symbol.toPrimitive]() { throw "bend: a Nat past the largest immediate 2^48-1"; } };
}

function f32_show(x) {
  if (x !== x) {
    return "nan";
  }
  if (!Number.isFinite(x) || Object.is(x, -0)) {
    return x < 0 ? "-inf"
      : x === 0 ? "-0" : "inf";
  }
  let s = "x";
  for (let p = 1; p <= 9 && f32_round(s) !== x; p += 1) {
    s = String(Number(x.toExponential(p - 1)));
  }
  return s;
}

function f32_bits(x) {
  return new Uint32Array(new Float32Array([x]).buffer)[0];
}

function f32_from_bits(u) {
  return new Float32Array(new Uint32Array([u]).buffer)[0];
}

function f32_read(s) {
  const re = /^\s*[+-]?((\d+\.?\d*|\.\d+)(e[+-]?\d+)?|inf(inity)?|nan)$/i;
  const v = f32_round(s.replace(/inf\w*/i, "Infinity"));
  return re.test(s) ? {$: "Some", value: v} : {$: "None"};
}

const f32_round = function f32_round(s) {
  const d = Number(s), a = Math.abs(d), f = Math.fround(a), g = 2 * a - Math.min(f, 340282366920938500000000000000000000000);
  if (g === f || Math.fround(g) !== g || g === 1 / 0)
    return Math.sign(d) * f;
  let k = 0;
  while (a * 2 ** k % 1 !== 0)
    k += 1;
  const [, i, r, e] = /(\d*)\.?(\d*)(?:e([+-]?\d+))?$/i.exec(s), n = Number(e ?? 0) - r.length, x = BigInt(i + r) * 2n ** BigInt(k) * 10n ** BigInt(Math.max(n, 0)), y = BigInt(a * 2 ** k) * 10n ** BigInt(Math.max(-n, 0));
  return Math.sign(d) * (x === y || x > y !== g > f ? f : g);
};

function char_new(code) {
  if (code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
    throw "bend: " + code + " is not a Unicode scalar value";
  }
  return String.fromCodePoint(code);
}

// Array
// =====

function array_new(d, v) {
  if (d > 31) {
    throw "bend: an array past the deepest block class 31";
  }
  return Array(2 ** d).fill(v);
}

function array_node(a, b) {
  if (a.length !== b.length) {
    throw "bend: runtime fail-stop";
  }
  return a.concat(b);
}

function array_rmw(a, i, f) {
  const at = i % a.length;
  const old = a[at];
  a[at] = f(old);
  return {$: "Tuple", fst: a, snd: old};
}

// Run
// ===

function run_tail(f, x) {
  return {$: "$JMP", f: f.j?.f === f ? f.j : f, x: [x]};
}

function run_clo(j) {
  const f = (x) => run_loop(j(x));
  f.j = j;
  j.f = f;
  return f;
}

function run_loop(r) {
  while (r !== null && typeof r === "object" && r.$ === "$JMP") {
    r = r.f(...r.x);
  }
  return r;
}

function run_lib(f, n) {
  return (...a) => a.length < n ? run_lib((...b) => f(...a, ...b), n - a.length)
    : f(...a);
}

// Effect
// ======

const $0eff = Object.create(null);

function io_eff(k, run, need) {
  if (k in $0eff) {
    throw new Error("bend: two effects register " + k);
  }
  $0eff[k] = { run, need };
}
(() => {
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
//   ABI-4  a scalar crosses as BITS in C and as a VALUE in node, so `of32`
//          (pattern->value) belongs on an ANSWER and `bits32` (value->pattern)
//          on an ARGUMENT: once each, at the seam, and never in the other place.
//   ABI-5  the words are carried as JS numbers into BigInt arithmetic, never
//          combined in Number arithmetic, which has 53 mantissa bits.
//
// Which of the two a given helper answers is `dtype.bend`'s declaration, not a
// choice: `Dt.bf16(bits: U32) -> IO(F32)` and `Dt.fp8_to(..) -> IO(F32)` owe a
// value out, `Dt.fp8_from(..) -> IO(U32)` owes a pattern. JS doubles are exact
// for every bit pattern here, so nothing rounds differently than in C -- but a
// value read as a pattern is not a rounding difference, it is a different
// number, and it is silent.

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
  const v = exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias);
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
  return of32(half_to_f32(f16_bits(x)));
}

function dtype_fp8_from(xb, kind) {
  return fp8_encode(xb >>> 0, kind & 0xff);
}

function dtype_fp8_to(x, kind) {
  return of32(fp8_decode(x >>> 0, kind & 0xff));
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

io_eff("tinybendygrad/dtype.Dt.bf16", dtype_bf16);
io_eff("tinybendygrad/dtype.Dt.fp16", dtype_fp16);
io_eff("tinybendygrad/dtype.Dt.fp8_from", dtype_fp8_from);
io_eff("tinybendygrad/dtype.Dt.fp8_to", dtype_fp8_to);
io_eff("tinybendygrad/dtype.Dt.i64_trunc", (a) => pack64(i64_of(a)));
io_eff("tinybendygrad/dtype.Dt.i64_floor_div", (a, b) => pack64(floor_pair(i64_of(a), i64_of(b))[0]));
io_eff("tinybendygrad/dtype.Dt.i64_floor_mod", (a, b) => pack64(floor_pair(i64_of(a), i64_of(b))[1]));
io_eff("tinybendygrad/dtype.Dt.i64_cdiv", (a, b) => pack64(
  i64_of(b) === 0n ? 0n : cdiv_of(i64_of(a), i64_of(b))));
io_eff("tinybendygrad/dtype.Dt.i64_cmod", (a, b) => pack64(
  i64_of(b) === 0n ? i64_of(a) : i64_of(a) - cdiv_of(i64_of(a), i64_of(b)) * i64_of(b)));
io_eff("tinybendygrad/dtype.Dt.i64_ceildiv", (a, b) => pack64(   // dtype.py ceildiv is -(a // -b)
  i64_of(b) === 0n ? 0n : -floor_pair(i64_of(a), -i64_of(b))[0]));

})();

(() => {
// IO
// ==

function io_print(text) {
  io_out(1, io_bytes(text + "\n"));
  return { $: "Unit" };
}

io_eff("IO.print", io_print);

})();

for (const k of ["tinybendygrad/dtype.Dt.i64_trunc","IO.print","tinybendygrad/dtype.Dt.i64_floor_div","tinybendygrad/dtype.Dt.fp8_from","tinybendygrad/dtype.Dt.bf16","tinybendygrad/dtype.Dt.fp16","tinybendygrad/dtype.Dt.fp8_to"]) {
  if (!(k in $0eff)) {
    throw new Error("bend: no effect registers " + k);
  }
}

// Program
// =======

function $main$() {
  return run_clo((_x_0) => {
  return $IO$bind$((_x_1) => $tinybendygrad$047dtype$Dt$i64_trunc$(($tinybendygrad$047helpers$i64_of_hi_lo$(15, 240)), _x_1), run_clo((_x_2) => {
  return run_clo((_x_3) => {
  const _x_4 = ($tinybendygrad$047helpers$i64_text$(_x_2));
  return $IO$bind$((_x_5) => $IO$print$(("abi123 trunc_A = " + _x_4), _x_5), run_clo((_x_6) => {
  return run_clo((_x_7) => {
  return $IO$bind$((_x_8) => $tinybendygrad$047dtype$Dt$i64_trunc$(($tinybendygrad$047helpers$i64_of_hi_lo$(3735928559, 305419896)), _x_8), run_clo((_x_9) => {
  return run_clo((_x_10) => {
  const _x_11 = ($tinybendygrad$047helpers$i64_text$(_x_9));
  return $IO$bind$((_x_12) => $IO$print$(("abi123 trunc_B = " + _x_11), _x_12), run_clo((_x_13) => {
  return run_clo((_x_14) => {
  return $IO$bind$((_x_15) => $tinybendygrad$047dtype$Dt$i64_floor_div$(($tinybendygrad$047helpers$i64_of_hi_lo$(7, 0)), ($tinybendygrad$047helpers$i64_of_hi_lo$(3, 0)), _x_15), run_clo((_x_16) => {
  return run_clo((_x_17) => {
  const _x_18 = ($tinybendygrad$047helpers$i64_text$(_x_16));
  return $IO$bind$((_x_19) => $IO$print$(("abi123 fdiv_b3 = " + _x_18), _x_19), run_clo((_x_20) => {
  return run_clo((_x_21) => {
  return $IO$bind$((_x_22) => $tinybendygrad$047dtype$Dt$i64_floor_div$(($tinybendygrad$047helpers$i64_of_hi_lo$(7, 0)), ($tinybendygrad$047helpers$i64_of_hi_lo$(5, 0)), _x_22), run_clo((_x_23) => {
  return run_clo((_x_24) => {
  const _x_25 = ($tinybendygrad$047helpers$i64_text$(_x_23));
  return $IO$bind$((_x_26) => $IO$print$(("abi123 fdiv_b5 = " + _x_25), _x_26), run_clo((_x_27) => {
  return run_clo((_x_28) => {
  return $IO$bind$((_x_29) => $tinybendygrad$047dtype$Dt$i64_floor_div$(($tinybendygrad$047helpers$i64_of_hi_lo$(7, 0)), ($tinybendygrad$047helpers$i64_of_hi_lo$(1, 0)), _x_29), run_clo((_x_30) => {
  return run_clo((_x_31) => {
  const _x_32 = ($tinybendygrad$047helpers$i64_text$(_x_30));
  return $IO$bind$((_x_33) => $IO$print$(("abi123 fdiv_b1 = " + _x_32), _x_33), run_clo((_x_34) => {
  return run_clo((_x_35) => {
  return $IO$bind$((_x_36) => $tinybendygrad$047dtype$Dt$fp8_from$(f32_bits(1.5), 0, _x_36), run_clo((_x_37) => {
  return run_clo((_x_38) => {
  const _x_39 = ($U32$show$(_x_37));
  return $IO$bind$((_x_40) => $IO$print$(("abi1 fp8from_e4m3 = " + _x_39), _x_40), run_clo((_x_41) => {
  return run_clo((_x_42) => {
  return $IO$bind$((_x_43) => $tinybendygrad$047dtype$Dt$fp8_from$(f32_bits(1.5), 2, _x_43), run_clo((_x_44) => {
  return run_clo((_x_45) => {
  const _x_46 = ($U32$show$(_x_44));
  return $IO$bind$((_x_47) => $IO$print$(("abi1 fp8from_fnuz = " + _x_46), _x_47), run_clo((_x_48) => {
  return run_clo((_x_49) => {
  return $IO$bind$((_x_50) => $tinybendygrad$047dtype$Dt$bf16$(f32_bits(1.5), _x_50), run_clo((_x_51) => {
  return run_clo((_x_52) => {
  const _x_53 = f32_show(_x_51);
  return $IO$bind$((_x_54) => $IO$print$(("abi1 bf16_1p5 = " + _x_53), _x_54), run_clo((_x_55) => {
  return run_clo((_x_56) => {
  return $IO$bind$((_x_57) => $tinybendygrad$047dtype$Dt$fp16$(1.5, _x_57), run_clo((_x_58) => {
  return run_clo((_x_59) => {
  const _x_60 = f32_show(_x_58);
  return $IO$bind$((_x_61) => $IO$print$(("abi4 fp16_1p5 = " + _x_60), _x_61), run_clo((_x_62) => {
  return run_clo((_x_63) => {
  return $IO$bind$((_x_64) => $tinybendygrad$047dtype$Dt$fp16$(1.100000023841858, _x_64), run_clo((_x_65) => {
  return run_clo((_x_66) => {
  const _x_67 = f32_show(_x_65);
  return $IO$bind$((_x_68) => $IO$print$(("abi4 fp16_1p1 = " + _x_67), _x_68), run_clo((_x_69) => {
  return run_clo((_x_70) => {
  return $IO$bind$((_x_71) => $tinybendygrad$047dtype$Dt$fp16$((-2.25), _x_71), run_clo((_x_72) => {
  return run_clo((_x_73) => {
  const _x_74 = f32_show(_x_72);
  return $IO$bind$((_x_75) => $IO$print$(("abi4 fp16_m2p25 = " + _x_74), _x_75), run_clo((_x_76) => {
  return run_clo((_x_77) => {
  return $IO$bind$((_x_78) => $tinybendygrad$047dtype$Dt$fp8_to$(60, 0, _x_78), run_clo((_x_79) => {
  const _x_80 = f32_show(_x_79);
  return (_x_81) => $IO$print$(("abi4 fp8to_0x3C = " + _x_80), _x_81);
}), _x_77);
});
}), _x_73);
});
}), _x_70);
});
}), _x_66);
});
}), _x_63);
});
}), _x_59);
});
}), _x_56);
});
}), _x_52);
});
}), _x_49);
});
}), _x_45);
});
}), _x_42);
});
}), _x_38);
});
}), _x_35);
});
}), _x_31);
});
}), _x_28);
});
}), _x_24);
});
}), _x_21);
});
}), _x_17);
});
}), _x_14);
});
}), _x_10);
});
}), _x_7);
});
}), _x_3);
});
}), _x_0);
});
}

function $IO$bind$(_m_0, _f_0, _k_0) {
  return run_tail(_m_0, run_clo((_x_0) => {
  return run_tail(_f_0(_x_0), _k_0);
}));
}

function $tinybendygrad$047dtype$Dt$i64_trunc$(_x_0, _k_0) {
  return { $: "$FFI", run: $0eff["tinybendygrad/dtype.Dt.i64_trunc"].run, need: $0eff["tinybendygrad/dtype.Dt.i64_trunc"].need, args: [(_x_0)], kont: (_k_0) };
}
function $tinybendygrad$047helpers$i64_of_hi_lo$(_hi_0, _lo_0) {
  return {$: "tinybendygrad/helpers.I64", "hi": _hi_0, "lo": _lo_0};
}

function $IO$print$(_text_0, _k_0) {
  return { $: "$FFI", run: $0eff["IO.print"].run, need: $0eff["IO.print"].need, args: [(_text_0)], kont: (_k_0) };
}
function $tinybendygrad$047helpers$i64_text$(_x_0) {
  return $tinybendygrad$047helpers$i64_show$(($tinybendygrad$047helpers$hi32$(_x_0)), ($tinybendygrad$047helpers$lo32$(_x_0)));
}

function $tinybendygrad$047dtype$Dt$i64_floor_div$(_a_0, _b_0, _k_0) {
  return { $: "$FFI", run: $0eff["tinybendygrad/dtype.Dt.i64_floor_div"].run, need: $0eff["tinybendygrad/dtype.Dt.i64_floor_div"].need, args: [(_a_0), (_b_0)], kont: (_k_0) };
}
function $tinybendygrad$047dtype$Dt$fp8_from$(_bits_0, _kind_0, _k_0) {
  return { $: "$FFI", run: $0eff["tinybendygrad/dtype.Dt.fp8_from"].run, need: $0eff["tinybendygrad/dtype.Dt.fp8_from"].need, args: [(_bits_0), (_kind_0)], kont: (_k_0) };
}
function $U32$show$(_a_0) {
  const _b_0 = _a_0;
  return $U32$show$if$(_b_0, (_b_0 === 0));
}

function $tinybendygrad$047dtype$Dt$bf16$(_bits_0, _k_0) {
  return { $: "$FFI", run: $0eff["tinybendygrad/dtype.Dt.bf16"].run, need: $0eff["tinybendygrad/dtype.Dt.bf16"].need, args: [(_bits_0)], kont: (_k_0) };
}
function $tinybendygrad$047dtype$Dt$fp16$(_x_0, _k_0) {
  return { $: "$FFI", run: $0eff["tinybendygrad/dtype.Dt.fp16"].run, need: $0eff["tinybendygrad/dtype.Dt.fp16"].need, args: [(_x_0)], kont: (_k_0) };
}
function $tinybendygrad$047dtype$Dt$fp8_to$(_bits_0, _kind_0, _k_0) {
  return { $: "$FFI", run: $0eff["tinybendygrad/dtype.Dt.fp8_to"].run, need: $0eff["tinybendygrad/dtype.Dt.fp8_to"].need, args: [(_bits_0), (_kind_0)], kont: (_k_0) };
}
function $tinybendygrad$047helpers$i64_show$(_hi_0, _lo_0) {
  return $String$concat$({$: "Con", "head": ($U32$show$(_hi_0)), "tail": {$: "Con", "head": ":", "tail": {$: "Con", "head": ($U32$show$(_lo_0)), "tail": {$: "Nil"}}}});
}

function $tinybendygrad$047helpers$hi32$(_x_0) {
  const _hi_0 = _x_0["hi"];
  return _hi_0;
}

function $tinybendygrad$047helpers$lo32$(_x_0) {
  const _lo_0 = _x_0["lo"];
  return _lo_0;
}

function $U32$show$if$(_a_0, _z_0) {
  if (_z_0) {
    return "0";
  } else {
    return $U32$show$go$(10, _a_0, "");
  }
}

function $String$concat$(_xs_0) {
  if (_xs_0.$ === "Nil") {
    return "";
  } else {
    const _h_0 = _xs_0["head"];
    const _t_0 = _xs_0["tail"];
    const _x_0 = ($String$concat$(_t_0));
    return (_h_0 + _x_0);
  }
}

function $U32$show$go$($0, $1, $2, $3) {
  let $pc = 0;
  for (;;) switch ($pc) {
    case 0: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = _n_0;
        $3 = (_n_0 === 0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _n_0 = $2;
      const _z_0 = $3;
      if (_z_0) {
        return _acc_0;
      } else {
        const _x_0 = (10 === 0 ? _n_0 : _n_0 % 10);
        $0 = _g_0;
        $1 = (10 === 0 ? 0 : (_n_0 / 10) >>> 0);
        $2 = (char_new(((48 + _x_0) >>> 0)) + _acc_0);
        $pc = 0; continue;
      }
    }
  }
}

function $U32$show$fin$($0, $1, $2, $3) {
  let $pc = 1;
  for (;;) switch ($pc) {
    case 0: {
      const _f_0 = $0;
      const _n_0 = $1;
      const _acc_0 = $2;
      if (_f_0 === 0) {
        return _acc_0;
      } else {
        const _g_0 = (_f_0 - 1);
        $0 = _g_0;
        $1 = _acc_0;
        $2 = _n_0;
        $3 = (_n_0 === 0);
        $pc = 1; continue;
      }
    }
    case 1: {
      const _g_0 = $0;
      const _acc_0 = $1;
      const _n_0 = $2;
      const _z_0 = $3;
      if (_z_0) {
        return _acc_0;
      } else {
        const _x_0 = (10 === 0 ? _n_0 : _n_0 % 10);
        $0 = _g_0;
        $1 = (10 === 0 ? 0 : (_n_0 / 10) >>> 0);
        $2 = (char_new(((48 + _x_0) >>> 0)) + _acc_0);
        $pc = 0; continue;
      }
    }
  }
}

// Cli
// ===

let cli_args = [];

function cli(argv) {
  cli_args.push(argv[0]);
  for (let i = 1; i < argv.length; i += 1) {
    if (argv[i] === "--") {
      cli_args.push(...argv.slice(i + 1));
      break;
    } else if (argv[i] === "--bend-help") {
      io_out(1, io_bytes("usage: " + argv[0] + "\n"));
      process.exit(0);
    } else if (argv[i] === "--threads" || argv[i] === "--gpu") {
      i += 1;
    } else {
      cli_args.push(argv[i]);
    }
  }
}

// Show
// ====

// show_val prints a pure main's value as term_show does (see show_main);
// chain is the bracket it continues, or 0. show_chr escapes as char_show.

function show_chr(c, q) {
  const k = { 10: "n", 9: "t", 13: "r", 0: "0", 92: "\\" }[c]
    ?? (c === q.codePointAt(0) ? q : null);
  return k !== null ? "\\" + k : c < 32 || c === 127
    || (c >= 0xD800 && c <= 0xDFFF) || c > 0x10FFFF
    ? "\\u{" + c.toString(16) + "}" : String.fromCodePoint(c);
}

function show_val(D, N, d, v, chain) {
  if (D[d] === 7) {
    const fs = Object.values(typeof v === "boolean"
      ? { $: v ? "True" : "False" } : v);
    let a = d + 3;
    for (; N[D[a]] !== fs[0]; a += 4 + 2 * D[a + 2]) {}
    const o = "{[("[D[a + 3]];
    let s = o === "{" ? fs[0] + "{" : chain === o ? "" : o;
    for (const [j, f] of fs.slice(1).entries()) {
      if (o === "[" ? j === 0 && chain === o : j > 0) {
        s += ", ";
      }
      s += show_val(D, N, D[a + 5 + 2 * j], f, j === 1 && o !== "{" ? o : 0);
    }
    return o === "{" || chain !== o ? s + "}])"[D[a + 3]] : s;
  }
  return D[d] === 0 ? String(v)
    : D[d] === 1 ? f32_show(v).replace(/^-?\d+(?=e|$)/, "$&.0")
    : D[d] === 2 ? v + "n"
    : D[d] === 3 ? "'" + show_chr(v.codePointAt(0), "'") + "'"
    : D[d] === 4 ? "\"" + [...v].map((c) =>
      show_chr(c.codePointAt(0), "\"")).join("") + "\""
    : D[d] === 5 ? "{==}"
    : "[" + v.map((x) => show_val(D, N, D[d + 1], x, 0)).join(", ") + "]";
}

// Io
// ==

// Apple arm64 passes variadic fcntl flags on the stack, so io_sys
// binds fcntl there with the flags as the ninth fixed argument. A
// parked effect waits for fd (a write when out) or until at
// (performance.now()), either one undefined when unused; io_wake
// resumes k with the value of more, and undefined parks it again. The
// waits stay in deadline order, as io_park does in C.

function io_exit(main, show) {
  try {
    if (show !== null) {
      io_out(1, io_bytes(show_val(...show, 0, run_loop(main()), 0) + "\n"));
      process.exit(0);
    }
    process.exit(io_run(main));
  } catch (e) {
    io_errs(String(e));
    process.exit(1);
  }
}

function io_out(fd, data) {
  const fs = require("fs");
  let at = 0;
  while (at < data.length) {
    try {
      at += fs.writeSync(fd, data, at, data.length - at);
    } catch (e) {
      if (e.code === "EAGAIN" || e.code === "EINTR") {
        continue;
      }
      try {
        fs.writeSync(2, "bend: a short write on a standard stream\n");
      } catch (o) {
      }
      process.exit(1);
    }
  }
}

function io_errs(message) {
  io_out(2, io_bytes(message + "\n"));
}

function io_sys() {
  if (globalThis.BEND_SYS === undefined) {
    const ffi = require("bun:ffi");
    const mac = process.platform === "darwin";
    const err = mac ? "__error" : "__errno_location";
    const sel = mac ? "select$DARWIN_EXTSN" : "select";
    const T = { i: "i32", u: "u32", U: "u64", I: "i64", p: "ptr",
      c: "cstring" };
    const vari = mac && process.arch === "arm64";
    const lib = ffi.dlopen(mac ? "libSystem.dylib" : "libc.so.6",
      Object.fromEntries(("socket:iii>i bind:ipu>i listen:ii>i connect:ipu>i"
        + " accept:ipp>i send:ipUi>I recv:ipUi>I read:ipU>I pread:ipUI>I"
        + " sendto:ipUipu>I recvfrom:ipUipp>I close:i>i setsockopt:iiipu>i"
        + " " + sel + ":ipppp>i"
        + (vari ? " fcntl:iiiiiiiii>i" : " fcntl:iii>i") + " getsockopt:iiipp>i"
        + " strerror:i>c " + err + ":>p").split(" ").map((s) => {
        const [name, args, ret] = s.split(/[:>]/);
        return [name, { args: [...args].map((a) => T[a]), returns: T[ret] }];
      }))).symbols;
    const fcntl = (fd, cmd, arg) => vari
      ? lib.fcntl(fd, cmd, 0, 0, 0, 0, 0, 0, arg)
      : lib.fcntl(fd, cmd, arg);
    globalThis.BEND_SYS = { ...lib, fcntl, select: lib[sel],
      ptr: ffi.ptr, mac,
      errno: () => ffi.read.i32(lib[err](), 0) };
  }
  return globalThis.BEND_SYS;
}

function io_fail(code) {
  return { $: "Fail",
    error: io_tup(code >>> 0, String(io_sys().strerror(code))) };
}

function io_done(value) {
  return { $: "Done", value };
}

function io_tup(...xs) {
  return xs.reduceRight((snd, fst) => ({ $: "Tuple", fst, snd }));
}

function io_bytes(text) {
  return new TextEncoder().encode(text);
}

function io_text(b, n) {
  return new TextDecoder("utf-8", { ignoreBOM: true }).decode(b.subarray(0, n));
}

// Bytes cross as they are (0..255), one List cell each, with no UTF-8 in
// either direction; io_unlist answers null if a value is past 255.
function io_list(b, n) {
  let xs = { $: "Nil" };
  while (n > 0) {
    xs = { $: "Con", head: b[--n], tail: xs };
  }
  return xs;
}

function io_unlist(xs) {
  const b = [];
  for (; xs.$ === "Con"; xs = xs.tail) {
    b.push(xs.head);
  }
  return b.some((x) => x > 255) ? null : Uint8Array.from(b);
}

function io_addr(host, port) {
  const part = host.split(".");
  const deci = (p) => /^(0|[1-9]\d{0,2})$/.test(p) && Number(p) < 256;
  if (port > 65535 || part.length !== 4 || !part.every(deci)) {
    return null;
  }
  const b = new Uint8Array(16);
  const head = io_sys().mac ? [16, 2] : [2, 0];
  b.set([...head, port >> 8, port & 255, ...part.map(Number)]);
  return b;
}

function io_push(fun, arg, fresh) {
  const io = globalThis.BEND_IO;
  io.runs.push({ fun, arg });
  io.live += fresh ? 1 : 0;
}

function io_wait(io) {
  const soon = io.waits[0]?.at ?? Infinity;
  const ms = soon === Infinity ? -1
    : Math.max(0, Math.ceil(soon - performance.now()));
  const fds = io.waits.filter((w) => w.fd !== undefined);
  const top = fds.reduce((m, w) => Math.max(m, w.fd), 0);
  const len = (top >> 6 << 3) + 8;
  const set = new Uint8Array(2 * len);
  const at = (w) => (w.out ? len : 0) + (w.fd >> 3);
  for (const w of fds) {
    set[at(w)] |= 1 << (w.fd & 7);
  }
  const tv = new BigInt64Array([BigInt(ms / 1000 | 0),
    BigInt(ms % 1000 * 1000)]);
  const sys = io_sys();
  if (sys.select(top + 1, sys.ptr(set), sys.ptr(set, len), null,
    ms < 0 ? null : sys.ptr(tv)) < 0) {
    if (sys.errno() !== 4) {
      throw "bend: the poller failed";
    }
    set.fill(0);
  }
  const now = performance.now();
  io.waits = io.waits.filter((w) => {
    const ready = w.at <= now || w.fd !== undefined
      && set[at(w)] & 1 << (w.fd & 7);
    if (ready) {
      io_push(io_wake, w, false);
    }
    return !ready;
  });
}

function io_wake(w) {
  const x = w.more();
  return x === undefined ? undefined : w.k(x);
}

function io_park_on(fd, out, k, more, at) {
  const ws = globalThis.BEND_IO.waits;
  const i = ws.findLastIndex((w) => (w.at ?? Infinity) <= (at ?? Infinity));
  ws.splice(i + 1, 0, { fd, out, k, more, at });
}

function io_run(m) {
  const io = { runs: [], live: 0, waits: [] };
  globalThis.BEND_IO = io;
  try {
    io_push(run_loop(m()), (x) => ({ $: "Emit", value: x }), true);
    for (;;) {
      if (io.runs.length === 0) {
        if (io.live === 0) {
          return 0;
        }
        if (io.waits.length === 0) {
          io_errs("bend: deadlock: every computation waits on a channel");
          return 1;
        }
        io_wait(io);
        continue;
      }
      const s = io.runs.shift();
      let op = s.fun(s.arg);
      while (op !== undefined) {
        if (op.$ === "Emit") {
          io.live -= 1;
          break;
        }
        if (op.$ === "Halt") {
          io_errs(op.message);
          return op.code;
        }
        const need = op.need?.() ?? {};
        if (need.time || need.read) {
          const more = () => op.run(...op.args, op.kont);
          io_park_on(need.read ? op.args[0] : undefined, false, op.kont, more,
            need.read ? undefined : performance.now() + Number(op.args[0]));
          break;
        }
        const x = op.run(...op.args, op.kont);
        if (x === undefined) {
          break;
        }
        op = op.kont(x);
      }
    }
  } catch (req) {
    if (req instanceof RangeError) {
      throw "bend: memory fault (machine stack overflow?)";
    }
    if (req?.$ !== "$FFI") {
      throw req;
    }
    io_errs("bend: runtime fail-stop");
    return 1;
  }
}

cli(process.argv.slice(1));
io_exit($main$, null);