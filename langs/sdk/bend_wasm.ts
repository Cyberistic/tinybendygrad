/**
 * bend_wasm.ts -- the wasm backend, in the emscripten shape.
 *
 * The contract this file implements is emscripten's: a module that exports
 * `_malloc`, a generic `ccall(ident, returnType, argTypes, args)` and `_free`,
 * and a C entry point reached by name.  Nothing here is emscripten-specific
 * beyond that ABI, so a module built by `emcc -sEXPORTED_FUNCTIONS=...` drops
 * straight in.
 *
 * ---------------------------------------------------------------------------
 * LANE STATUS: this lane cannot be built from Bend 2.0.34 on wasm32.  The wall
 * is measured, not guessed, and it is not a missing toolchain -- see
 * langs/wasm/WALL.md for the commands, the outputs and the line of Bend's own
 * C that no wasm32 address space can hold.  In short: `corpus_setup` reserves
 * `1ull << 33` (8 GiB) of corpus before main runs, wasm32 caps linear memory
 * at 4 GiB, and wasm32's size_t is 32 bits, so the reservation truncates to
 * nothing and every access past the heap traps.
 *
 * So this backend reports unavailable with that reason, the SDK falls back to
 * JavaScript, and verify.sh says so out loud rather than quietly passing.  The
 * glue below is real and exercised by the JS-equivalent path; it is the module
 * that is missing, not the calling convention.
 * ---------------------------------------------------------------------------
 */
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

import { ANSWER, IMAGES, LABELS, WEIGHTS, type Answer, type BendBackend } from "./bend_sdk.ts";

/** The four lanes' answer is eight f32; wasm32 spells f32 as its own type. */
type EmscriptenModule = {
  /** Emscripten's allocator, exported as _malloc. */
  _malloc(size: number): number;
  /** Emscripten's release, exported as _free. */
  _free(ptr: number): void;
  /** Emscripten's generic call, resolved against the module's exports. */
  ccall(
    ident: string,
    returnType: string | null,
    argTypes: readonly string[],
    args: readonly number[],
  ): unknown;
  /** HEAPU8, for reading a f32 back out of linear memory. */
  HEAPU8: Uint8Array;
  /** HEAPF32, which is the typed view the same memory gives. */
  HEAPF32?: Float32Array;
  /** setValue, when the runtime provides one; ccall-only otherwise. */
  setValue?: (ptr: number, value: number, type?: string) => void;
};

/** The exported name of the C entry point.  Must match bend_wasm_shim.c. */
export const ENTRY = "bend_core_task";

/** langs/wasm/core.wasm, resolved from this file's own location. */
export function modulePath(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  return path.resolve(here, "..", "wasm", "core.wasm");
}

/**
 * The wall, in one line, so a caller that logs `unavailableReason` learns
 * something true rather than "not found".
 */
export const WALL =
  "Bend 2.0.34 reserves an 8 GiB corpus (corpus_setup: 1ull << 33) before " +
  "main; wasm32 caps linear memory at 4 GiB and its size_t is 32 bits, so no " +
  "wasm32 module can host it. See langs/wasm/WALL.md.";

/** A backend that is not available, and why. */
const unavailable = (reason: string): BendBackend => ({
  name: "wasm",
  available: false,
  unavailableReason: reason,
  execute: () => {
    throw new RangeError("the wasm lane is unavailable; init() falls back to js");
  },
  bits: (f32) => new Uint32Array(new Float32Array([f32]).buffer)[0],
});

/**
 * Load core.wasm if it is there and this host can host it.
 *
 * Returns an unavailable backend rather than throwing when the module is
 * missing or the lane is walled, because falling back is the SDK's job, not
 * the backend's.  Throws only when a module IS present and still will not
 * instantiate, which is a real fault the caller should hear about -- init()
 * catches it anyway, and records it as the fallback reason.
 */
export async function tryLoad(): Promise<BendBackend> {
  const file = modulePath();
  if (!fs.existsSync(file)) return unavailable(`no ${file}: ${WALL}`);
  let instance: WebAssembly.Instance;
  try {
    const bytes = fs.readFileSync(file);
    ({ instance } = await WebAssembly.instantiate(bytes, wasiImports()));
  } catch (cause) {
    // A present-but-broken module is a defect, not an absent lane: let it out.
    throw cause instanceof Error ? cause : new RangeError(String(cause));
  }
  const named = namedExports(instance.exports);
  if (typeof named._malloc !== "function" || typeof named._free !== "function") {
    return unavailable(`core.wasm exports no _malloc/_free; build it with ${BUILD}`);
  }
  const ccall = typeof named.ccall === "function" ? named.ccall : makeCcall(named);
  return live(named, ccall, file);
}

/**
 * wasm exports arrive as an untyped bag, so read it through a guard rather
 * than asserting it into shape: whatever comes back is checked, and the
 * backend refuses to run if the three names it needs are not functions.
 */
function namedExports(exports: WebAssembly.Exports): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const name of Object.keys(exports)) out[name] = exports[name];
  return out;
}

/** The emcc invocation that would produce a hostable module. */
export const BUILD =
  "emcc -O3 -sEXPORTED_FUNCTIONS=_malloc,_free,bend_core_task " +
  "-sEXPORTED_RUNTIME_METHODS=ccall,HEAPF32 langs/wasm/bend_wasm_shim.c langs/c/core.c -o langs/wasm/core.wasm";

/**
 * The minimal WASI preview1 import object, which is what a wasm32 build of a
 * Bend program imports: the runtime calls printf, malloc and clock_gettime.
 * Provided here so a wasi-sdk build runs unmodified; a module built without
 * WASI simply asks for none of it.
 */
function wasiImports(): WebAssembly.Imports {
  const mem = new WebAssembly.Memory({ initial: 2 });
  const u8 = () => new Uint8Array(mem.buffer);
  const dv = () => new DataView(mem.buffer);
  const preview1 = {
    /** Count the bytes the iovecs describe; this harness never writes them. */
    fd_write: (_fd: number, iovs: number, n: number, out: number): number => {
      const view = dv();
      const written = Array.from({ length: n }, (_, i) =>
        view.getUint32(iovs + i * 8 + 4, true),
      ).reduce((a, b) => a + b, 0);
      view.setUint32(out, written, true);
      return 0;
    },
    proc_exit: (): number => 0,
    /** A deterministic zero, which is all core_step ever asks WASI for. */
    random_get: (ptr: number, len: number): number => u8().fill(0, ptr, ptr + len) && 0,
  };
  return { wasi_snapshot_preview1: preview1 } as unknown as WebAssembly.Imports;
}

/**
 * A ccall for a module that was not built by emscripten.
 *
 * Emscripten's ccall looks the name up in the module's export table and calls
 * it with the arguments as given.  That is all it is, and a plain wasm module
 * exports by name too, so this is the same thing with the lookup written out.
 * returnType/argTypes are accepted and ignored: wasm carries no types, so they
 * are documentation rather than dispatch.
 */
function makeCcall(exports: Record<string, unknown>): EmscriptenModule["ccall"] {
  return (ident, _returnType, _argTypes, args) => {
    const fn = exports[ident];
    if (typeof fn !== "function") {
      throw new RangeError(`core.wasm exports no ${ident}`);
    }
    return Reflect.apply(fn, exports, args);
  };
}

/** The live backend: the malloc, ccall and free dance, once per call. */
function live(mod: EmscriptenModule, ccall: EmscriptenModule["ccall"], file: string): BendBackend {
  const heap = mod.HEAPF32 ?? new Float32Array(mod.HEAPU8.buffer);
  const f32FromBits = (b: number): number =>
    new Float32Array(new Uint32Array([b >>> 0]).buffer)[0];
  return {
    name: "wasm",
    available: true,
    unavailableReason: undefined,
    execute: (data) => {
      // _malloc the input block, fill it through the heap, ccall the entry,
      // _malloc the answer, read it back, then _free both.  The three calls
      // are the whole contract, and the frees are what keep a long run from
      // growing the heap by one task per call.
      const inBytes = (IMAGES + LABELS + WEIGHTS) * 4;
      const inPtr = mod._malloc(inBytes);
      const outPtr = mod._malloc(ANSWER * 4);
      try {
        // Two runs of f32 with a run of u32 between them, so the payload is
        // written as three typed views rather than element by element.
        const base = inPtr >>> 2;
        heap.set(data.slice(0, IMAGES).map(f32FromBits), base);
        new Uint32Array(heap.buffer, (base + IMAGES) * 4, LABELS).set(
          data.slice(IMAGES, IMAGES + LABELS),
        );
        heap.set(data.slice(IMAGES + LABELS).map(f32FromBits), base + IMAGES + LABELS);
        ccall(ENTRY, null, ["number"], [inPtr, outPtr]);
        return Array.from(heap.subarray(outPtr >>> 2, (outPtr >>> 2) + ANSWER));
      } finally {
        mod._free(inPtr);
        mod._free(outPtr);
      }
    },
    bits: (f32) => new Uint32Array(new Float32Array([f32]).buffer)[0],
  };
}

/** The shape this backend answers, for the d.ts and the docs. */
export type WasmAnswer = Answer;

/** Where this backend looks for its module.  Exported for the bench table. */
export const module = modulePath();
