// S-jslane -- what shape does `H.I64` actually cross the JS boundary as?
//
// NOT a fix for `runtime/dtype.js` -- another unit owns that ABI and
// `.agents/slop/JS-LANE-GATE.md` already gated it.  This file answers ONE
// question, by execution rather than by reading a call site:
//
//     `Dt.i64_trunc` is the IDENTITY.  So the reading that is the identity is
//     the correct one, and the discriminator needs no oracle at all.
//
// Written in the SAME dialect `runtime/dtype.js` is: the emitted JS is one CJS
// scope, so an ESM `import`/`export` in here is a SyntaxError and the probe
// never runs.  (It did, the first time.  A probe that cannot run cannot lie.)

// `io_tup` is what `runtime/dtype.js:141` builds.  Reproduced here so the shape
// it produces is in this file rather than quoted.
function io_tup(fst, snd) {
  return { $: "Tuple", fst: fst, snd: snd };
}

// dtype.js:136-138 verbatim
function shipped_i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.fst >>> 0) << 32n) | BigInt(p.snd >>> 0));
}
function shipped_pack64(v) {
  const u = BigInt.asUintN(64, v);
  return io_tup(Number((u >> 32n) & 0xffffffffn), Number(u & 0xffffffffn));
}

// the reading the record's OWN fields ask for: H.I64 is I64{hi, lo}
function named_i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.hi >>> 0) << 32n) | BigInt(p.lo >>> 0));
}
function named_pack64(v) {
  const u = BigInt.asUintN(64, v);
  return { $: "I64", hi: Number((u >> 32n) & 0xffffffffn), lo: Number(u & 0xffffffffn) };
}

// PROBE returns the high word of what the SHIPPED reader made of its argument,
// so the `.bend` side prints a Nat and the answer is visible in the row.
function PROBE(a) {
  const k = Object.keys(a);
  console.error("JS  argument keys = " + JSON.stringify(k));
  console.error("JS  argument      = " + JSON.stringify(a));
  console.error("JS  shipped i64_of(a)      = " + shipped_i64_of(a));
  console.error("JS  shipped pack64(above)  = " + JSON.stringify(shipped_pack64(shipped_i64_of(a))));
  console.error("JS  named   i64_of(a)      = " + named_i64_of(a));
  console.error("JS  named   pack64(above)  = " + JSON.stringify(named_pack64(named_i64_of(a))));
  console.error("JS  is shipped the identity? " +
    (shipped_pack64(shipped_i64_of(a)).fst === a.hi &&
     shipped_pack64(shipped_i64_of(a)).snd === a.lo));
  console.error("JS  is named   the identity? " +
    (named_pack64(named_i64_of(a)).hi === a.hi &&
     named_pack64(named_i64_of(a)).lo === a.lo));
  // ship the SHIPPED answer's high word, so the row is the shipped lane's row
  return shipped_pack64(shipped_i64_of(a)).fst;
}

io_eff(CID(Probe), PROBE);