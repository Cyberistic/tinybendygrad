// SHAPE C: the f64 add with NO float type named anywhere on the boundary.
// Operands and result are 64-bit LSB-first Bool lists. A double is
// reconstructed only inside this function, from the bits, and the bits are the
// only thing that crosses. This is the row that decides the wall: if it runs,
// then 64-bit transport is fine and the ONLY missing thing in Bend is IEEE-754
// SEMANTICS, which is a very different problem from "Bend has no 64 bits".
function f4add(a, b) {
  const x = bitsToF64(a);
  const y = bitsToF64(b);
  return f64ToBits(x + y);
}

function bitsToF64(bits) {
  let v = 0n;
  for (let i = bits.length - 1; i >= 0; i--) {
    v = (v << 1n) | (bits[i] ? 1n : 0n);
  }
  const buf = new ArrayBuffer(8);
  new DataView(buf).setBigUint64(0, v, true);
  return new DataView(buf).getFloat64(0, true);
}

function f64ToBits(x) {
  const buf = new ArrayBuffer(8);
  new DataView(buf).setFloat64(0, x, true);
  let v = new DataView(buf).getBigUint64(0, true);
  const out = new Array(64);
  for (let i = 0; i < 64; i++) {
    out[i] = (v & 1n) === 1n;
    v >>= 1n;
  }
  return out;
}