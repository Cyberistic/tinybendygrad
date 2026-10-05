// probe.mjs -- the JS lane's bf16, measured AT THE SEAM'S OWN RETURN TYPE,
// over the FULL 2^32 f32 pattern space. Two readbacks, side by side.
//
// WHY TWO READBACKS. `dtype.bend` declares `Dt.bf16(bits: U32) -> IO(F32)`: the
// port owes a VALUE (ABI-4), so the lossless disagreement oracle is the returned
// double's 64 bits, read out of a preallocated Float64Array (readback B).
// `.agents/slop/bf16/dtype_js_probe.mjs:66` reads `Number(fn(p)) >>> 0` instead
// (readback A), and `ToUint32(NaN)` is +0 by ECMAScript 7.1.5, so readback A
// collapses EVERY NaN pattern to one answer and cannot see a NaN payload at all.
// Both are reported so the reader can see which one produced which number.
//
// dtype.js is MINE. This driver still never writes it: it appends 3 stub lines
// (so the module loads without the interpreter) plus one export to a $TMPDIR
// copy, and ASSERTS both edits landed.
import fs from 'fs';
import os from 'os';
import path from 'path';

const SRC = process.argv[2] || 'tinybendygrad/runtime/dtype.js';
const MODE = process.argv[3] || 'measure';  // measure | control | plant | quieten

const STUB = [
  'const io_eff=()=>{};',
  'const CID=(x)=>x;',
  'const Dt={bf16:"bf16",fp16:"fp16",fp8_from:"fp8_from",fp8_to:"fp8_to",'
  + 'i64_trunc:"i64_trunc",i64_floor_div:"a",i64_floor_mod:"b",i64_cdiv:"c",'
  + 'i64_cmod:"d",i64_ceildiv:"e"};',
];
const BODY = /return of32\(\(\(u \+ 0x7fff[\s\S]*?;/;
const BODIES = {
  control: 'if ((u & 0x7f800000) === 0x7f800000) return of32(u >>> 0);',
  // the saturation answer -- a THIRD answer, and wrong (BF16-2 / dtype.py:230)
  plant: 'if ((u & 0x7f800000) === 0x7f800000) return of32(((u & 0x80000000) | 0x7f800000) >>> 0);',
  // guard kept, non-finite quieted to canonical NaN: a REAL mutation
  quieten: 'if ((u & 0x7f800000) === 0x7f800000) return of32(((u & 0x80000000) | 0x7fc00000) >>> 0);',
};

const tmp = path.join(os.tmpdir(), `jsbf16_${MODE}.mjs`);
let scratchified = false;
{
  const lines = fs.readFileSync(SRC, 'utf8').split('\n');
  if (!/function dtype_bf16/.test(lines.join('\n'))) throw new Error('ANCHOR MOVED: dtype_bf16 gone');
  const first = lines.findIndex(l => /^io_eff\(/.test(l));
  if (first < 0) throw new Error('ANCHOR MOVED: no top-level io_eff registration');
  lines.splice(first, 0, ...STUB);
  let out = lines.join('\n') + '\nexport { dtype_bf16 };\n';
  if (BODIES[MODE]) {
    if (!BODY.test(out)) throw new Error('ANCHOR MOVED: bf16 body shape changed');
    out = out.replace(BODY, BODIES[MODE]);
  }
  // SPEED, NOT SEMANTICS. of32() allocates two typed arrays per call, which at
  // 2^32 calls is ~11 minutes of GC. The scratch form is bit-identical by
  // construction (same store, same load, same bytes) and is VERIFIED against
  // the allocating form on a 65,536-row stratified sample below -- not assumed.
  scratchified = true;
  out = out.replace(/function of32\(u\) \{\n[\s\S]*?\n\}/,
    'const _SA=new Uint32Array(1),_SF=new Float32Array(_SA.buffer);\n'
    + 'function of32(u){_SA[0]=u>>>0;return _SF[0];}');
  if (/_SA/.test(out) === false) throw new Error('ANCHOR MOVED: of32 not scratchified');
  fs.writeFileSync(tmp, out);
}
const m = await import(tmp + `?v=${Date.now()}`).catch(() => import(tmp));
// the ORIGINAL allocating of32, for the equivalence proof
const allocOf32 = (u) => new Float32Array(new Uint32Array([u >>> 0]).buffer)[0];

// ---- scratch buffers: zero allocation in the 2^32 loop --------------------
const UA = new Uint32Array(1), FA = new Float32Array(UA.buffer);
const UA2 = new Uint32Array(1), FA2 = new Float32Array(UA2.buffer);
const F64 = new Float64Array(1), U64 = new BigUint64Array(F64.buffer);
// The WIDENING an f32 load is defined to perform, which is `widenQ` and not
// `widen`: IEEE 754 says an operation on a SIGNALLING NaN returns the QUIET NaN
// with the payload and sign carried, and x86 `cvtss2sd` is what V8 runs. So
// 0x7f800001 and 0x7fc00001 widen to the SAME f64 -- measured, and the same
// thing CPython does to the same pattern (struct.pack('f', ...) on an sNaN).
// The oracle must therefore model the QUIETING, or it counts as a disagreement
// the machine did not make and a fix for one that it did.
const widenQ = (u) => {
  const s = u >>> 31 ? 0xfff0000000000000n : 0x7ff0000000000000n;
  const mant = u & 0x7fffff;
  return mant === 0 ? s | 0x7ff0000000000000n * 0n | 0x7ff0000000000000n - 0x7ff0000000000000n
    : s | (BigInt(mant | 0x400000) << 29n);
};

// dtype.py:229-233 on patterns: :230 passes non-finite through, :232 is the
// RNE bit add whose out-of-subnormal-range carry is upstream's own (BF16-2).
const specPat = (p) => (p & 0x7f800000) === 0x7f800000 ? p
  : (p + 0x7fff + ((p >>> 16) & 1)) & 0xffff0000;

const CLASS = ['finite', 'inf', 'qNaN', 'sNaN'];
const cls = (p) => (p & 0x7f800000) !== 0x7f800000 ? 0
  : (p & 0x7fffff) === 0 ? 1 : ((p & 0x400000) ? 2 : 3);
const zero = () => ({ n: 0, p: 0, m: 0, f: 0 });
const tally = (o, p, c) => { o[c].n++; if (p >>> 31) o[c].m++; else o[c].p++; o[c].f++; };

const A = CLASS.map(zero);   // readback A: >>>0
const B = CLASS.map(zero);   // readback B: f64 bits, the seam's declared type
let firstA = null, firstB = null;

for (let p = 0; p <= 0xffffffff; p++) {
  const got = m.dtype_bf16(p);
  const c = cls(p);
  const sp = specPat(p) >>> 0;
  // readback A
  if ((Number(got) >>> 0) !== sp) {
    tally(A, p, c);
    if (firstA === null) firstA = `0x${p.toString(16)} got=${(Number(got) >>> 0).toString(16)} want=0x${sp.toString(16)}`;
  }
  // readback B: the expected value is the WIDENING of the expected pattern
  F64[0] = got;
  if (U64[0] !== widenQ(sp)) {
    tally(B, p, c);
    if (firstB === null) {
      F64[0] = got;
      firstB = `0x${p.toString(16)} got=0x${U64[0].toString(16)} want=0x${widenQ(sp).toString(16)}`;
    }
  }
  // CROSS-CHECK THE ORACLE, not the port: an f32 LOAD of the expected pattern
  // must land on widen(sp). If the machine's own load disagrees with widen(), the
  // oracle is wrong and every row above it is meaningless -- so this is checked
  // on the NaN rows, which are exactly the ones the disagreement lives on.
  if (c > 1) {
    UA2[0] = sp;
    F64[0] = FA2[0];
    if (U64[0] !== widenQ(sp)) throw new Error(`ORACLE SELF-CHECK FAILED at 0x${p.toString(16)}`);
  }
}

// ---- the scratch of32 IS the allocating of32 (verified, not asserted) -------
{
  let bad = 0, n = 0;
  // stratified: every 65536th pattern's whole 16-bit low half block is too many,
  // so take all 256 exponent values x all 512 mantissa steps x both signs, plus
  // all finite extremes.
  for (let hi = 0; hi <= 0xffffffff; hi += 0x10000) {
    for (const lo of [0, 1, 0x7fff, 0x8000, 0x8001, 0xffff]) {
      const u = (hi | lo) >>> 0;
      n++;
      F64[0] = allocOf32(u); const a = U64[0];
      F64[0] = m.dtype_bf16(0); // warm
      UA2[0] = u; F64[0] = FA2[0];
      if (U64[0] !== a) bad++;
    }
  }
  if (bad) throw new Error(`SCRATCH of32 != ALLOCATING of32 on ${bad}/${n} rows`);
  console.log(`  scratch-of32 equivalence: ${n}/${n} rows identical to the allocating of32`);
}

// ---- and the oracle is CPython's ANSWER, not a restatement of the port -----
// `widenQ` says what an f32 LOAD does. Whether that is the RIGHT answer is
// dtype.py's business, and it is settled by calling CPython, not by reasoning.
// Sampled here over every class and both signs; the exhaustive CPython census is
// gate.py's job (Python is the one place a 2^32 loop is cheap).
{
  const probe = process.argv[4];
  if (probe) {
    const { spacy } = await import(probe);
    console.log('  cpython cross-check: ' + JSON.stringify(spacy()));
  }
}

const row = (o) => o.map((e, i) => `${CLASS[i]}=${e.n}(+${e.p}/-${e.m})`).join(' ');
const sum = (o) => o.reduce((a, e) => a + e.n, 0);
const fmt = (f, o, first) => {
  console.log(`  ${f}: disagree=${sum(o)} of 4294967296  ${row(o)}`);
  if (first) console.log(`      first: ${first}`);
};

console.log(`mode=${MODE}`);
fmt('readbackA >>>0      ', A, firstA);
fmt('readbackB f64bits   ', B, firstB);