// probe.mjs -- the JS lane's bf16, measured at the SEAM'S OWN RETURN TYPE, over
// the full 2^32 f32 pattern space.
//
// dtype.bend declares `Dt.bf16(bits: U32) -> IO(F32)`: the port owes a VALUE
// (ABI-4), not a pattern. So the disagreement oracle here is the returned
// double's BITS, read losslessly out of a Float64Array. That is the whole point
// of this driver, and it is the instrument the C lane's probe does not use:
// `.agents/slop/bf16/dtype_js_probe.mjs:66` reads `Number(fn(p)) >>> 0`, and
// `ToUint32(NaN)` is +0 by spec, so that readback cannot see a NaN at all.
// Every readback this driver offers is reported side by side, so the reader can
// see which one produced the C lane's number.
//
// dtype.js is ANOTHER unit's tree relative to the C lane and MINE here. This
// driver NEVER writes it: it appends 3 stub lines (so the module loads without
// the interpreter) plus one export, to a $TMPDIR copy, and ASSERTS both edits
// landed.
import fs from 'fs';
import os from 'os';
import path from 'path';

const SRC = process.argv[2] || 'tinybendygrad/runtime/dtype.js';
const MODE = process.argv[3] || 'measure';   // measure | control | plant

const STUB = [
  'const io_eff=()=>{};',
  'const CID=(x)=>x;',
  'const Dt={bf16:"bf16",fp16:"fp16",fp8_from:"fp8_from",fp8_to:"fp8_to",'
  + 'i64_trunc:"i64_trunc",i64_floor_div:"a",i64_floor_mod:"b",i64_cdiv:"c",'
  + 'i64_cmod:"d",i64_ceildiv:"e"};',
];
const BODY = /return of32\(\(\(u \+ 0x7fff[\s\S]*?;/;
const GUARDED = 'if ((u & 0x7f800000) === 0x7f800000) return of32(u >>> 0);';
const SATURATED = 'if ((u & 0x7f800000) === 0x7f800000) return of32(((u & 0x80000000) | 0x7f800000) >>> 0);';
const QUIETED = 'if ((u & 0x7f800000) === 0x7f800000) return of32(((u & 0x80000000) | 0x7fc00000) >>> 0);';

const tmp = path.join(os.tmpdir(), `jsbf16_${MODE}.mjs`);

function build() {
  const src = fs.readFileSync(SRC, 'utf8');
  if (!/function dtype_bf16/.test(src)) throw new Error('ANCHOR MOVED: dtype_bf16 gone');
  const lines = src.split('\n');
  const first = lines.findIndex(l => /^io_eff\(/.test(l));
  if (first < 0) throw new Error('ANCHOR MOVED: no top-level io_eff registration');
  lines.splice(first, 0, ...STUB);
  let out = lines.join('\n') + '\nexport { dtype_bf16 };\n';
  const body = { control: GUARDED, plant: SATURATED, quieten: QUIETED }[MODE];
  if (body) {
    if (!BODY.test(out)) throw new Error('ANCHOR MOVED: bf16 body shape changed');
    out = out.replace(BODY, body);
  }
  fs.writeFileSync(tmp, out);
  return out;
}

build();
const m = await import(tmp + `?v=${Date.now()}`).catch(() => import(tmp));

// --- lossless readback: the returned double's own 64 bits -----------------
const F64 = new Float64Array(1), U64 = new BigUint64Array(F64.buffer);
const d64 = (x) => { F64[0] = x; return U64[0]; };
// the ORACLE: dtype.py:229-233 read on patterns. :230 passes non-finite through,
// :232 is the RNE bit add, whose carry behaviour is upstream's own (BF16-2).
const specPat = (p) => (p & 0x7f800000) === 0x7f800000 ? p
  : (p + 0x7fff + ((p >>> 16) & 1)) & 0xffff0000;

// class of an f32 pattern
const cls = (p) => {
  if ((p & 0x7f800000) !== 0x7f800000) return 'finite';
  if ((p & 0x7fffff) === 0) return 'inf';
  return (p & 0x400000) ? 'qNaN' : 'sNaN';
};
const CLASSES = ['finite', 'inf', 'qNaN', 'sNaN'];
// per class per sign
const key = (p) => (p >>> 31 ? '-' : '+') + cls(p);

const n = { readbackA: 0, readbackB: 0 };   // A: >>>0 (the C lane's), B: f64 bits
const byClass = Object.create(null);        // readbackB disagreements
const byClassA = Object.create(null);
for (const k of CLASSES) { byClass[k] = 0; byClassA[k] = 0; }
let firstDisagree = null;

for (let p = 0; p <= 0xffffffff; p++) {
  const got = m.dtype_bf16(p);
  const sp = specPat(p) >>> 0;
  const g64 = d64(got);
  const e64 = d64(new Float32Array(new Uint32Array([sp]).buffer)[0]);
  const k = key(p);
  // readback A -- what .agents/slop/bf16/dtype_js_probe.mjs:66 does
  if ((Number(got) >>> 0) !== sp) {
    n.readbackA++;
    const c = cls(p);
    if (byClassA[c] !== undefined) byClassA[c]++;
  }
  // readback B -- the seam's declared return type, read losslessly
  if (g64 !== e64) {
    n.readbackB++;
    byClass[cls(p)]++;
    if (firstDisagree === null)
      firstDisagree = { p: p.toString(16), got: g64.toString(16), want: e64.toString(16) };
  } else if (g64 === e64) { /* agreed */ }
}

console.log(`mode=${MODE} patterns=4294967296`);
console.log(`  readbackA >>>0   disagree=${n.readbackA}  byClass=${JSON.stringify(byClassA)}`);
console.log(`  readbackB f64bits disagree=${n.readbackB}  byClass=${JSON.stringify(byClass)}`);
console.log(`  firstDisagreeB=${JSON.stringify(firstDisagree)}`);

// --- WHICH LINE loses it: three stages, separated -------------------------
// stage 1: the arithmetic on an integer pattern (dtype.js:151), in isolation
// stage 2: of32 (dtype.js:51-53), pattern -> double
// stage 3: the probe's own readback
const of32 = (u) => new Float32Array(new Uint32Array([u >>> 0]).buffer)[0];
let arithBad = 0, of32Bad = 0, both = 0;
for (let p = 0; p <= 0xffffffff; p++) {
  const want = specPat(p) >>> 0;
  // stage 1: the integer expression, before of32
  const arith = (p & 0x7f800000) === 0x7f800000 ? p : (p + 0x7fff + ((p >>> 16) & 1)) & 0xffff0000;
  if ((arith >>> 0) !== want) { arithBad++; both++; }
  // stage 2: of32 must turn the CORRECT pattern into the correct double
  if (d64(of32(want)) !== d64(new Float32Array(new Uint32Array([want]).buffer)[0])) of32Bad++;
  if (arithBad > 1000) break;
}
console.log(`  stage1_arith_bad=${arithBad} (integer-only, i.e. dtype.js:151's expression)`);
// stage 2 above compares of32 to itself -- measure it against the IDEAL: does
// of32(want) read back, as f64 bits, to what a float32 load of `want` is?
const of32payloadBad = (() => {
  let bad = 0;
  for (let p = 0x7f800000; p <= 0x7fffffff; p++) {
    const x = of32(p);
    if (Number.isNaN(x)) {
      // what f64 did the f32 load actually produce?
      // ideal: f32->f64 widening of the bits, payload shifted 29, sNaN quieted
      const quiet = (p & 0x400000) ? p : (p | 0x400000);
      const want64 = (BigInt(p >>> 0) & 0x80000000n ? 0xfff0000000000000n : 0x7ff0000000000000n)
        | (BigInt(quiet & 0x7fffff) << 29n);
      if (d64(x) !== want64) bad++;
    }
  }
  return bad;
})();
console.log(`  stage2_of32_qnan_f64bits_wrong=${of32payloadBad} of 4194303 sNaN + 4194303 qNaN`);

// stage 3: what `>>> 0` does to a NaN, spelled out, so no reader has to guess
const nanPat = 0x7fc00001;
const nanVal = of32(nanPat);
console.log(`  stage3 >>>0 on the NaN of 0x${nanPat.toString(16)} = ${nanVal >>> 0}`
  + `  (spec ${nanPat})   NaN?=${Number.isNaN(nanVal)}  f64bits=0x${d64(nanVal).toString(16)}`);
console.log(`  stage3 readbackA therefore CANNOT distinguish any NaN pattern: 1 distinct answer`
  + ` for all 16777214 of them.`);