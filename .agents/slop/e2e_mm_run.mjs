// .agents/slop/e2e_mm_run.mjs -- THE GPU LANE. Drives the compiled Bend program
// on a real WebGPU adapter and writes the raw result next to the CPython oracle.
//
// WHAT ACTUALLY EXECUTES. `e2e_mm.mjs` is `bend`'s output for
// .agents/slop/e2e_mm.bend, and `webgpu_call.js` is a byte copy of
// tinybendygrad/runtime/webgpu_call.js -- the PORT'S OWN driver, unmodified. The
// page imports both and calls `walk(mm_run())`. So the step order, the buffer
// creations, the writes, the shader modules, the bind group layouts, the bind
// groups, the pipelines, the dispatches, the submits, the staging copy and the
// map are all decided by `webgpu_call.bend`'s pure defs. This file contributes a
// static server, a Chrome, and a place to print.
//
// THE ADAPTER IS PROBED, NOT ASSUMED. `e2e_gpu_probe.mjs` is the standalone
// proof that this machine has a device that computes (it dispatches a kernel and
// reads the answer back); this file re-asks `navigator.gpu` for the adapter's
// vendor and architecture and puts them in the artifact, so the committed output
// names the hardware the numbers came from. `gpu_present=false` with an `error`
// is a legitimate outcome and the gate reads it as one.
//
// RUN:  node .agents/slop/e2e_mm_run.mjs
// OUT:  runs/e2e/e2e-mm-gpu.json   (and stdout)
// EXIT: 0 if the walk completed and produced a readback, 1 otherwise.

import { readFile, writeFile, mkdir, copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { launch, shutdown, Session, CHROME_BINARIES } from "./xd2/cdp.mjs";
import { serve } from "./xd2/serve.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "../..");
const BUNDLE = join(HERE, "e2e");
const OUT = join(ROOT, "runs/e2e");

// CHROME-STABLE, `--headless=new`, and nothing else. MEASURED, twice, by
// e2e_gpu_probe.mjs across three (binary, flag) cases: chrome-stable headless
// gives `vendor=apple architecture=metal-3` and a verified readback, headed gives
// the same, and chrome-for-testing gives `"gpu": false` for every flag set tried
// (including `--enable-unsafe-webgpu` and `--use-angle=metal`). The adapter also
// needs a SECURE CONTEXT, which is why this serves the page over http://127.0.0.1
// instead of opening a file:// URL -- `navigator.gpu` is undefined on about:blank.
const FLAGS = ["--headless=new"];

async function build() {
  // (1) the port's driver, byte for byte, so `./webgpu_call.mjs` resolves beside it
  await copyFile(join(ROOT, "tinybendygrad/runtime/webgpu_call.js"), join(BUNDLE, "webgpu_call.js"));
  // (2) the port's PURE half, freshly emitted. The committed
  // tinybendygrad/runtime/webgpu_call.mjs is STALE -- measured: 610 exports where a
  // fresh emit has 664, the difference being `../helpers.gi_*` defs added since,
  // and every shared export byte-identical -- so it is emitted here rather than
  // copied, and the live tree is not touched.
  const fresh = join(HERE, "webgpu_call.fresh.mjs");
  await emit(join(ROOT, "tinybendygrad/runtime/webgpu_call.bend"), fresh);
  await copyFile(fresh, join(BUNDLE, "webgpu_call.mjs"));
  // (3) the program under test
  await emit(join(HERE, "e2e_mm.bend"), join(BUNDLE, "e2e_mm.mjs"));
}

async function emit(src, dst) {
  const { sh } = await import("./xd2/sh.mjs");
  await sh(join(ROOT, "bin/bend"), src, "-o", dst);
}

const srv = await serve(BUNDLE);
let h, payload = null, fatal = null;
try {
  await build();
  h = await launch(CHROME_BINARIES["chrome-stable"], FLAGS, srv.url + "/index.html");
  const s = await Session.openPage(h.port, { url: srv.url + "/index.html" });
  // `readyState === "complete"` is NOT the module script finishing: a `type=module`
  // script is DEFERRED, so the document completes first and the walk is still
  // running. The page sets `document.title = "done"` as its last statement and
  // that is the signal, so poll for it. Reading `#o` on arrival is what made the
  // first run report `WALK FAILED` with an `undefined` error -- the element still
  // said `running`, which JSON-parsed into an object with no `ok`.
  const deadline = Date.now() + 240000;
  let ready = false;
  for (;;) {
    const r = await s.eval(`return document.title === "done";`, { timeoutMs: 20000 }).catch(() => false);
    if (r === true) { ready = true; break; }
    if (Date.now() > deadline) break;
    await new Promise((r2) => setTimeout(r2, 250));
  }
  // READ `#o` ONLY AFTER THE TITLE, and report the console when it never arrives.
  // A `type=module` script that fails to LOAD (a bad import path) never runs a
  // statement, so `#o` keeps its initial text and the title never changes -- and
  // an unconditional read reports that as `{"ok": false}` with no `error`, which
  // is what the first two runs did.
  payload = ready
    ? await s.eval(`return document.getElementById("o").textContent;`, { timeoutMs: 60000 })
    : JSON.stringify({ ok: false, error: "page never reached document.title=done",
                       console: s.log.slice(0, 40), title: (await s.eval("return document.title;", { timeoutMs: 5000 }).catch(() => "?")) });
  s.close();
} catch (e) {
  fatal = String(e && e.stack ? e.stack : e).slice(0, 2000);
} finally {
  if (h) await shutdown(h);
  await srv.close();
}

let parsed = null;
if (payload) { try { parsed = JSON.parse(payload); } catch { parsed = { __unparsed: String(payload).slice(0, 400) }; } }
const rec = {
  note: "produced by .agents/slop/e2e_mm_run.mjs: bend -o on .agents/slop/e2e_mm.bend, "
      + "then tinybendygrad/runtime/webgpu_call.js's walk() on the five Cs it returns, "
      + "in headless Chrome. out_u32 are the GPU's words, little-endian.",
  chrome: CHROME_BINARIES["chrome-stable"], flags: FLAGS,
  driver: "tinybendygrad/runtime/webgpu_call.js (byte copy)",
  fatal, result: parsed,
};
await mkdir(OUT, { recursive: true });
await writeFile(join(OUT, "e2e-mm-gpu.json"), JSON.stringify(rec, null, 1) + "\n");

if (fatal) { console.log("FATAL\n" + fatal); process.exit(1); }
if (!parsed) { console.log("NO PAYLOAD"); process.exit(1); }
if (!parsed.ok) { console.log("WALK FAILED\n" + parsed.error); process.exit(1); }
console.log(`adapter  ${parsed.gpu_vendor}/${parsed.gpu_architecture}`);
console.log(`cs       ${parsed.cs_count} [${parsed.cs_lens}]`);
console.log(`steps    ${parsed.steps} performed, WriteBuffer x${parsed.writes}, `
          + `Dispatch x${parsed.dispatches}, MappedRange x${parsed.mapped}`);
console.log(`out_u32  ${JSON.stringify(parsed.out_u32)}`);
process.exit(0);
