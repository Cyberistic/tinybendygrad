/**
 * bend_sdk.ts -- BendLibrarySDK.
 *
 * One typed surface over the four lanes under langs/.  init() picks a backend
 * the way the contract says: detect WebAssembly, try wasm, catch, fall back to
 * the JavaScript one.  executeTask() is the only call a consumer makes, and it
 * dispatches on the backend chosen at init.
 *
 * The answer is always the same eight f32, in the same order, as raw bits:
 *
 *     [loss, ce, h0, h1, h2, z0, z1, z2]
 *
 * The loss is the mean cross-entropy over the batch; ce, h and z are the last
 * sample's own cross-entropy, hidden layer and logits.  The bits are the
 * contract, not a convenience: they are what every lane must agree on, down
 * to the last ulp.
 *
 * The payload is the flat 42-number field list every lane speaks: eight image
 * bit patterns, two class indices, thirty-two weight bit patterns.  Bits, not
 * decimals, because a decimal would let two lanes agree by rounding it
 * differently -- see langs/README.md.
 *
 * This module takes no Node import and makes no filesystem call: it is the
 * surface a consumer imports, and reading a vector file is the harness's job
 * (bench.ts), not the library's.
 */
import * as js from "../js/bend_core.js";
import * as wasm from "./bend_wasm.ts";

/** Which backend is live. */
export type Backend = "wasm" | "js";

/** IMAGES = BATCH*IN = 8, LABELS = BATCH = 2, WEIGHTS = 32 with 27 used. */
export const IMAGES = 8;
export const LABELS = 2;
export const WEIGHTS = 32;

/** The payload length: images, then labels, then weights. */
export const PAYLOAD = IMAGES + LABELS + WEIGHTS;

/** How many f32 the answer holds. */
export const ANSWER = 8;

/** What init() takes. */
export interface InitOptions {
  /**
   * Skip the wasm attempt and take the JavaScript backend.  This is the one
   * switch the contract asks for; it exists so a host with no WebAssembly
   * still has a working SDK, and so the wasm lane can be compared against the
   * JS lane on purpose rather than by accident.
   */
  forceJS?: boolean;
}

/** The eight answers, in order, each an f32 as raw bits. */
export type Answer = readonly [
  number, // loss
  number, // ce, the last sample's cross-entropy
  number, // h0
  number, // h1
  number, // h2
  number, // z0
  number, // z1
  number, // z2
];

/** What a backend has to provide. */
export interface BendBackend {
  readonly name: Backend;
  /** False when this backend cannot run here, which is the wasm lane's wall. */
  readonly available: boolean;
  /** Why it is unavailable, when it is.  One line, for the caller to log. */
  readonly unavailableReason?: string;
  execute(data: readonly number[]): readonly number[];
  bits(f32: number): number;
}

/** The f32 a bit pattern denotes, and the bits an f32 has. */
export const f32OfBits = (b: number): number =>
  new Float32Array(new Uint32Array([b >>> 0]).buffer)[0];

export const bitsOf = (f: number): number =>
  new Uint32Array(new Float32Array([f]).buffer)[0];

/** The JavaScript backend, wrapped so it answers the same shape as wasm. */
const jsBackend: BendBackend = {
  name: "js",
  available: true,
  execute: (data) => js.execute(data),
  bits: bitsOf,
};

/**
 * BendLibrarySDK -- the one surface a consumer imports.
 *
 * The exported surface of the core underneath it is, in Bend,
 *
 *     core_step(images: Array<F32>, labels: Array<U32>, weights: Array<F32>)
 *                -> F32
 *
 * which crosses into TypeScript as
 *
 *     core_step(images: number[], labels: number[], weights: number[]): number
 *
 * on the JavaScript lane.  That is the def the mnist example imports;
 * everything else here is the dispatch around it.
 */
export class BendLibrarySDK {
  /** The backend init() settled on. */
  readonly backend: BendBackend;
  /** True when the wasm attempt was made and did not pan out. */
  readonly fellBack: boolean;
  /** Why wasm was not used, when it was not.  Absent when it was. */
  readonly wasmReason: string | undefined;

  // Written out rather than declared as constructor parameter properties, so
  // this module runs under Node's strip-only TypeScript, which does not erase
  // those, and so the three fields read the same way in every tool.
  private constructor(backend: BendBackend, fellBack: boolean, wasmReason: string | undefined) {
    this.backend = backend;
    this.fellBack = fellBack;
    this.wasmReason = wasmReason;
  }

  /**
   * Detect WebAssembly, try wasm, catch, fall back to JavaScript.
   *
   * forceJS skips the wasm attempt outright.  Without it, a runtime with no
   * WebAssembly, and a wasm module that will not instantiate or whose lane
   * this host cannot host at all, both land in the same place: the JS
   * backend, with the reason kept for the caller to log.  Nothing here throws
   * for a missing wasm -- falling back is the whole point, so the try/catch
   * is the contract's dance rather than a shortcut around an error channel.
   */
  static async init(options: InitOptions = {}): Promise<BendLibrarySDK> {
    if (options.forceJS === true) {
      return new BendLibrarySDK(jsBackend, false, "forceJS asked for the JS backend");
    }
    if (typeof WebAssembly === "undefined") {
      return new BendLibrarySDK(jsBackend, true, "this runtime has no WebAssembly");
    }
    try {
      const backend = await wasm.tryLoad();
      if (backend.available) return new BendLibrarySDK(backend, false, undefined);
      return new BendLibrarySDK(jsBackend, true, backend.unavailableReason);
    } catch (cause) {
      const why = cause instanceof Error ? cause.message : String(cause);
      return new BendLibrarySDK(jsBackend, true, `wasm did not load: ${why}`);
    }
  }

  /** Which backend init() settled on. */
  get backendName(): Backend {
    return this.backend.name;
  }

  /**
   * Run one step over the flat payload and answer the eight f32 as raw bits.
   *
   * Dispatch is a property lookup on the backend, not a branch the caller
   * makes, and a wrong-length payload is refused before any lane sees it.
   */
  executeTask(data: readonly number[]): Answer {
    if (data.length !== PAYLOAD) {
      throw new RangeError(`executeTask wants ${PAYLOAD} numbers, got ${data.length}`);
    }
    const out = this.backend.execute(data);
    if (out.length !== ANSWER) {
      throw new RangeError(`${this.backend.name} answered ${out.length} f32, wanted ${ANSWER}`);
    }
    return [
      this.backend.bits(out[0]),
      this.backend.bits(out[1]),
      this.backend.bits(out[2]),
      this.backend.bits(out[3]),
      this.backend.bits(out[4]),
      this.backend.bits(out[5]),
      this.backend.bits(out[6]),
      this.backend.bits(out[7]),
    ];
  }

  /** The same eight bits as one string, which is what verify.sh diffs. */
  format(answer: Answer): string {
    return answer.join(",");
  }

  /** The loss alone, as f32.  For callers that only want the number. */
  loss(answer: Answer): number {
    return f32OfBits(answer[0]);
  }
}

export default BendLibrarySDK;
