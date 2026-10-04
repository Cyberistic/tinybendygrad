// Operands arrive as 64-bit LSB-first bit lists; the double lives only inside.
export function f4add(a, b) {
  const x = bitsToF64(a);
  const y = bitsToF64(b);
  return f64ToBits(x + y);
}

function bitsToF64(bits) {
  // bits is an array of Bool in LSB-first order.
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
  for (let i = 0; i < 64; i++) { out[i] = (v & 1n) === 1n; v >>= 1n; }
  return out;
}
