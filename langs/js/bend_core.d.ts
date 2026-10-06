/**
 * bend_core.d.ts -- the typed surface of the JavaScript lane.
 *
 * `bend core.bend -o core.mjs` exports every non-IO def of the program as a
 * plain ES module default object.  That object is untyped JS, so this file is
 * the typed hand-shaken wrapper: it declares exactly the one def the SDK and
 * the mnist example call, in the terms the contract uses.
 *
 * Conventions forced by the Bend side, not chosen here:
 *
 * - `Nat` crosses as `bigint`.  Bend's Nat is unary and its own literals are
 *   `bigint` in JS, so a Nat parameter is a `bigint`.
 * - `F32` crosses as `number`, always the f32-rounded value.  Bend's JS lane
 *   wraps every f32 operation in Math.fround, so a `number` here is an f32
 *   widened to f64 -- exact, never rounded.
 * - `U32` crosses as `number`, always an integer in [0, 2^32).
 * - `Array<T>` crosses as the caller's own array, and the program may write
 *   into it.  The SDK always passes a fresh copy for that reason.
 */

/** One f32 widened to an f64.  Exact: no f32 value is lost. */
export type F32 = number;

/** A Bend `Nat`, which is unary and unbounded on the JS side. */
export type Nat = bigint;

/**
 * The typed surface `core.mjs` exports.  Only the defs the matrix's callers
 * use are declared; the module carries every non-IO def, and the rest are
 * reachable through an index signature so nothing is claimed to be absent
 * that is in fact there.
 */
export interface BendCore {
  /**
   * One forward step: mean cross-entropy over the batch.
   *
   * images is 8 f32 (two samples of four features), labels is 2 u32 (one
   * class index each, 0..2), and weights is 32 f32 -- 27 used, five padding:
   * W1 in three rows of five at [0..14] and W2 in three rows of four at
   * [15..26], each row's last column being that row's bias.
   *
   * The three arrays may be written to in place, so pass copies you own.
   */
  readonly core_step: (
    images: readonly F32[],
    labels: readonly number[],
    weights: readonly F32[],
  ) => F32;

  /**
   * The same step, answering [loss, ce, h0, h1, h2, z0, z1, z2]: the mean
   * cross-entropy, then the last sample's own cross-entropy, hidden layer and
   * logits.  Diagnostics only -- the numbers are the same f32 the step used.
   */
  readonly core_trace: (
    images: readonly F32[],
    labels: readonly number[],
    weights: readonly F32[],
  ) => readonly F32[];

  /** The payload string `main` reads from argv[1], rendered back into text. */
  readonly run: (payload: readonly string[]) => string;

  readonly [def: string]: unknown;
}

/** The module default export, as emitted by `-o core.mjs`. */
declare const core: BendCore;

export default core;
