// bend_core.js -- the JavaScript backend of the SDK.
//
// One thin wrapper over the ES module Bend emits from core.bend.  It owns the
// two conversions the JS lane forces on a caller and nothing else:
//
//   - an Array crosses into the JS lane as the caller's own array and the
//     callee writes into it, so an array is good for exactly one call;
//   - a Bend List is {$: "Nil"} / {$: "Con", head, tail}, not a JS array.
//
// The payload arrives as u32 BIT PATTERNS, which is the one encoding every
// lane speaks: the Bend, C and native harnesses read the same decimal field
// list from argv and reinterpret those bits, so no lane can agree with
// another by rounding a decimal differently.  The conversion to f32 happens
// here, once, and is exact -- a reinterpretation, not an arithmetic step.
//
// There is no arithmetic and no formatting here beyond f32 bits, so nothing
// in this file can move a result.
import core from "./core.mjs";

/** IMAGES = BATCH*IN = 8, LABELS = BATCH = 2, WEIGHTS = 32 with 27 used. */
export const IMAGES = 8;
export const LABELS = 2;
export const WEIGHTS = 32;

/** The f32 a bit pattern denotes, and the bits an f32 has. */
export function f32OfBits(bits) {
  return new Float32Array(new Uint32Array([bits >>> 0]).buffer)[0];
}

export function bits(f32) {
  return new Uint32Array(new Float32Array([f32]).buffer)[0];
}

/**
 * The three inputs core_step takes, as fresh arrays: images and weights with
 * their bit patterns reinterpreted, labels left as the class indices they are.
 */
function inputs(data) {
  const f32s = (from, n) => {
    const out = new Array(n).fill(0);
    for (let i = 0; i < n && from + i < data.length; i += 1) {
      out[i] = f32OfBits(data[from + i]);
    }
    return out;
  };
  const u32s = (from, n) => {
    const out = new Array(n).fill(0);
    for (let i = 0; i < n && from + i < data.length; i += 1) out[i] = data[from + i];
    return out;
  };
  return [f32s(0, IMAGES), u32s(IMAGES, LABELS), f32s(IMAGES + LABELS, WEIGHTS)];
}

/**
 * A Bend List<F32> as a JS array of numbers.  The emitted module builds lists
 * as tagged objects, which is the documented shape -- constructors cross as
 * {$: "Name", field: value} -- so this walks the spine.
 */
function list(xs) {
  const out = [];
  for (let t = xs; t !== undefined && t.$ !== "Nil"; t = t.tail) out.push(Number(t.head));
  return out;
}

/**
 * The eight f32 core_trace answers -- [loss, ce, h0, h1, h2, z0, z1, z2] --
 * with the loss taken from core_step instead, so this backend exercises the
 * same def the mnist example imports and verify.sh can hold the two against
 * each other.  They are the same value: core_step is core_trace read at 0.
 */
export function execute(data) {
  const loss = core.core_step(...inputs(data));
  const trace = list(core.core_trace(...inputs(data)));
  return [loss, ...trace.slice(1)];
}

/** The loss alone: core_step over the payload, copied first. */
export function coreStep(data) {
  return core.core_step(...inputs(data));
}

/** The backend name the SDK dispatches on. */
export const name = "js";

/** Ready: this backend is the compiler's own output, so there is nothing to load. */
export const available = true;

export default { name, available, execute, coreStep, bits, f32OfBits };
