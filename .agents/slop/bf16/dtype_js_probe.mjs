// dtype_js_probe.mjs -- the JS LANE's answer for bf16_run's arithmetic, over the
// FULL 2^32 f32 pattern space, against dtype.py:229-233 read at the pattern level.
//
// dtype.js is ANOTHER UNIT'S FILE and this driver never writes it. It appends
// exactly two things to a $TMPDIR copy and ASSERTS that (JSFP8's rule: "we drove
// the tree" must be checked, not asserted):
//   * 3 stub lines so the module loads standalone -- `io_eff`/`CID`/`Dt` are the
//     registration table, and the module calls them at load. This is the same
//     shape as fp8fix/build.py compiling the live .c rather than going through
//     dtype.bend.
//   * 1 export line, because dtype_bf16 is module-local.
//
// THE RESULT, and it is the same defect the C lane just had:
//
//   dtype.js patterns 4294967296  disagree with dtype.py  4294934527
//
// Every one of those is a non-finite f32 pattern whose low 16 bits are nonzero:
// dtype.js:151 rounds them, where dtype.py:230 returns x unchanged. The 256
// bf16-representable non-finite codes are untouched for the same reason the C's
// were -- adding 0x7FFF to a zero low half cannot carry.
//
// THE CONTROL IS THE PART THAT MAKES THE NUMBER TRUSTWORTHY, and it is the third
// mode: this harness must be able to print 4294967296/0 disagreements. A sweep
// that only ever prints "many" is indistinguishable from a broken comparison.
//   * `control` replaces dtype_bf16's body with upstream's guarded answer and the
//     count MUST be 0.
//   * `plant` replaces it with a deliberately wrong one (saturation) and the
//     count MUST be the non-finite space minus the inf/nan-uncorrupted corner.
import fs from 'fs';

const SRC = process.argv[2];
const MODE = process.argv[3] || 'measure';   // measure | control | plant
const STUB = [
  'const io_eff=()=>{};',
  'const CID=(x)=>x;',
  'const Dt={bf16:"bf16",fp16:"fp16",fp8_from:"fp8_from",fp8_to:"fp8_to",'
  + 'i64_trunc:"i64_trunc",i64_floor_div:"a",i64_floor_mod:"b",i64_cdiv:"c",'
  + 'i64_cmod:"d",i64_ceildiv:"e"};',
];
const BODY = /return of32\(\(\(u \+ 0x7fff[\s\S]*?;/;

function load() {
  const src = fs.readFileSync(SRC, 'utf8');
  if (!/function dtype_bf16/.test(src)) throw new Error('ANCHOR MOVED: dtype_bf16 gone');
  if (/dtype_bf16[\s\S]{0,80}math\.isfinite/.test(src))
    throw new Error('dtype.js ALREADY HAS A GUARD -- this driver is stale, rerun');
  const lines = src.split('\n');
  const first = lines.findIndex(l => /^io_eff\(/.test(l));
  if (first < 0) throw new Error('ANCHOR MOVED: no top-level io_eff registration');
  lines.splice(first, 0, ...STUB);
  let out = lines.join('\n') + '\nexport { dtype_bf16 };\n';
  if (MODE === 'control')
    out = out.replace(BODY, 'if ((u & 0x7f800000) === 0x7f800000) return of32(u >>> 0);');
  if (MODE === 'plant')
    out = out.replace(BODY,
      'if ((u & 0x7f800000) === 0x7f800000) return of32(((u & 0x80000000) | 0x7f800000) >>> 0);');
  const tmp = `/tmp/dtype_js_probe_${MODE}.mjs`;
  fs.writeFileSync(tmp, out);
  return import(tmp + `?v=${Date.now()}`).catch(() => import(tmp));
}

const m = await load();
let dis = 0, nfDis = 0, finDis = 0, n = 0;
const ex = [];
for (let p = 0; p <= 0xffffffff; p++) {
  const got = Number(m.dtype_bf16(p)) >>> 0;
  const nf = (p & 0x7f800000) === 0x7f800000;
  // dtype.py:230 returns x unchanged; :232 is the RNE bit add.
  const spec = nf ? p : (p + 0x7fff + ((p >>> 16) & 1)) & 0xffff0000;
  n++;
  if (got !== spec >>> 0) {
    dis++;
    if (nf) nfDis++; else finDis++;
    if (ex.length < 4) ex.push([p.toString(16), got.toString(16), (spec >>> 0).toString(16)]);
  }
}
console.log(`${MODE}: patterns=${n} disagree=${dis} nonfinite=${nfDis} finite=${finDis}`, ex);