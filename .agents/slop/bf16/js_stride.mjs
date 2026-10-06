// The SAME exhaustive sweep, but with a stride, so the control runs in seconds.
// The stride skips patterns; every skipped one is counted and PRINTED, because a
// stride that silently reduces n is how a "full sweep" becomes a sample.
// dtype_bf16 returns of32(u) -- an F32 VALUE, not a pattern (dtype.js:51-53
// `of32` goes through a Float32Array). So the comparison must read the value's
// bits back out. MEASURED, not guessed: the first cut compared the returned
// NUMBER against the expected PATTERN and reported 2130673664 finite
// disagreements -- including 0x3F800000 (1.0f) "answering 0" -- on a tree whose
// arithmetic was correct. A probe that cannot tell a correct file from a wrong
// one is the JSFP8 instrument problem again, one level up.
//
// The control below is what settles it: `measure` must disagree, `control` (the
// guarded body) must report 0.
const m = await import(process.argv[2]);
const stride = Number(process.argv[3] || 1);
const buf = new Float32Array(1);
const i32 = new Int32Array(buf.buffer);
const bits = v => { buf[0] = v; return i32[0] >>> 0; };

let dis = 0, n = 0, nfDis = 0;
const ex = [];
for (let p = 0; p <= 0xffffffff; p += stride) {
  const got = bits(m.dtype_bf16(p));
  const nf = (p & 0x7f800000) === 0x7f800000;
  const spec = (nf ? p : (p + 0x7fff + ((p >>> 16) & 1)) & 0xffff0000) >>> 0;
  n++;
  if (got !== spec) {
    dis++;
    if (nf) nfDis++;
    if (ex.length < 4) ex.push([p.toString(16), got.toString(16), spec.toString(16)]);
  }
}
console.log(`stride=${stride} checked=${n} of 4294967296 disagree=${dis} `
  + `nonfinite=${nfDis}`, ex);