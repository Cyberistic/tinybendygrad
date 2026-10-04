// nan_census.mjs -- how many f32 NaN PATTERNS survive the JS lane, and what the
// EXHAUSTIVE denominator is. Nothing here is sampled: the population is every
// pattern with exponent 0xFF and a nonzero mantissa, both signs.
//
//   kept  =  f32_bits(f32_from_bits(p)) === p
//
// which is `comp.ts:539 f32_from_bits` and `comp.ts:541 f32_bits` -- the two
// runtime helpers `base.bend:54 F32.from_bits` and `F32.bits` compile to on the
// JS backend, and the same expression `runtime/dtype.js:51/55` uses for
// `of32`/`bits32`. C carries an F32 as the raw `u64` of its pattern
// (`comp.ts:391 f32_unbox`, a union), so its `f32_bits` is the identity.
//
// USAGE: node nan_census.mjs <workdir>

import {mkdirSync, writeFileSync} from "node:fs";
import {argv} from "node:process";

// Verbatim from the JS runtime, `references/bend/bend2/comp.ts:539-546`. They
// are RUNTIME-SIDE helpers in bend's own runtime prelude, not globals, so the
// census defines them rather than assuming them -- and defining them from the
// source means the number below is about bend's expression and not about mine.
const f32_from_bits = (u) => new Float32Array(new Uint32Array([u]).buffer)[0];
const f32_bits = (x) => new Uint32Array(new Float32Array([x]).buffer)[0];
// A REAL question about two JS numbers, which `Object.is(a, b)` cannot answer:
// `Object.is(NaN, NaN)` is true for every pair of NaNs, so an `Object.is` test
// here is tautological. This reads the two doubles' own 64-bit patterns.
const f64_bits = (x) => {
  const d = new Float64Array([x]);
  return new BigUint64Array(d.buffer)[0];
};
const NAN32 = (sign, m) => ((sign | 0x7F800000 | m) >>> 0);
const QUIET = (sign, m) => NAN32(sign, m | 0x400000);   // the top mantissa bit set

const work = argv[2];
mkdirSync(work, {recursive: true});
const perSign = 0x7FFFFF;
let quietKept = 0, signallingKept = 0;
for (let m = 1; m <= perSign; m += 1) {
  for (const sign of [0, 0x80000000]) {
    const p = NAN32(sign, m);
    if (f32_bits(f32_from_bits(p)) !== p) continue;
    if (m & 0x400000) quietKept += 1;
    else signallingKept += 1;
  }
}
const kept = quietKept + signallingKept, total = 2 * perSign;
// The four patterns `fp8_decode` can answer that are not finite, and whether a
// SEAM could have carried them. This is what decides whether reaching
// `fp8_decode`'s return value directly was NECESSARY or merely convenient.
const decodeAnswers = {
  "0x7fc00000": f32_bits(f32_from_bits(0x7fc00000)) === 0x7fc00000,
  "0xffc00000": f32_bits(f32_from_bits(0xffc00000)) === 0xffc00000,
  "0x7f800000": f32_bits(f32_from_bits(0x7f800000)) === 0x7f800000,
  "0xff800000": f32_bits(f32_from_bits(0xff800000)) === 0xff800000,
  "0xffc00000_as_f64_sign_kept": (f64_bits(f32_from_bits(0xffc00000)) >> 63n) === 1n,
  "two_nans_one_JS_value":
    f64_bits(f32_from_bits(0x7fc00001)) === f64_bits(f32_from_bits(0x7fc00000)),
};
writeFileSync(`${work}/nan.json`, JSON.stringify({
  kept, total, quietKept, signallingKept,
  quietDenominator: 2 * (perSign - (0x400000 - 1)), decodeAnswers}, null, 1));
process.stdout.write(`NAN kept ${kept} / ${total}   quiet ${quietKept}`
  + `   signalling ${signallingKept}\n${JSON.stringify(decodeAnswers, null, 1)}\n`);